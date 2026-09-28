-- aurp_trucker — server/services/industry_service.lua
-- Interações de trading: BuyFrom / SellTo / Produção

IndustryService = {}

-- Retorna estado atual de todas as indústrias de trading para a NUI
function IndustryService.GetAll()
    local rows = DB_GetAllIndustryState() or {}

    -- Indexar por industryId+item+type
    local stateIndex = {}
    for _, row in ipairs(rows) do
        local k = row.industry_id .. ':' .. row.item .. ':' .. row.entry_type
        stateIndex[k] = row
    end

    local result = {}
    for industryId, industry in pairs(Config.Industries) do
        local entry = {
            id           = industryId,
            name         = industry.name,
            industryType = industry.type,
            coords       = industry.coords,
            production   = nil,
            consumption  = {},
        }

        if industry.production and industry.production.item then
            local key = industryId .. ':' .. industry.production.item .. ':production'
            local state = stateIndex[key]
            entry.production = {
                product          = industry.production.label,
                item             = industry.production.item,
                price            = state and state.current_price or industry.production.basePrice,
                currentStock     = state and state.current_stock or 0,
                maxStock         = industry.production.maxStock,
                unit             = industry.production.unit,
                productionPerHour = industry.production.productionPerHour,
            }
        end

        if industry.consumption then
            for _, c in ipairs(industry.consumption) do
                local key = industryId .. ':' .. c.item .. ':consumption'
                local state = stateIndex[key]
                table.insert(entry.consumption, {
                    product          = c.label,
                    item             = c.item,
                    price            = state and state.current_price or c.basePrice,
                    currentStock     = state and state.current_stock or 0,
                    maxStock         = c.maxStock,
                    unit             = c.unit,
                    consumptionPerHour = c.consumptionPerHour,
                })
            end
        end

        result[industryId] = entry
    end
    return result
end

function IndustryService.Get(industryId)
    local all = IndustryService.GetAll()
    return all[industryId]
end

-- Jogador compra item de produção da indústria
function IndustryService.BuyFrom(src, industryId, item, qty)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    local industryConfig = Config.Industries[industryId]
    if not industryConfig then return false, 'Indústria não encontrada' end

    -- Validar distância física do jogador até a indústria (fail-closed)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 'Jogador inválido'
    end
    local playerCoords = GetEntityCoords(ped)
    local indCoords = vec3(industryConfig.coords.x, industryConfig.coords.y, industryConfig.coords.z)
    local maxDist = industryConfig.radius or 15.0
    if #(playerCoords - indCoords) > maxDist then
        return false, 'Muito longe da indústria'
    end

    local citizenId = Framework.GetCitizenId(Player)
    local state = MySQL.single.await(
        "SELECT * FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'production' LIMIT 1",
        { industryId, item }
    )

    if not state then return false, 'Produto não encontrado' end
    if state.current_stock < qty then return false, 'Stock insuficiente' end

    local totalPrice = state.current_price * qty
    if Framework.GetMoney(Player, 'cash') < totalPrice then
        return false, ('Você precisa de $%d'):format(totalPrice)
    end

    -- [H1-FIX] Cobrar ANTES de entregar item — evita exploit de item gratuito se RemoveMoney falhar
    local removed = Framework.RemoveMoney(Player, 'cash', totalPrice, 'industry-purchase')
    if not removed then return false, 'Falha ao processar pagamento' end

    -- Adicionar item; em falha, estornar o pagamento
    local ok = exports.ox_inventory:AddItem(src, item, qty)
    if not ok then
        Framework.AddMoney(Player, 'cash', totalPrice, 'industry-purchase-refund')
        return false, 'Inventário cheio'
    end

    EconomyService.RecordPurchase(industryId, item, qty)
    -- Lucro da venda vai para a empresa dona (se houver)
    IndustryOwnershipService.OnSale(industryId, totalPrice)
    return true, nil
end

-- Jogador vende item de consumo para a indústria
function IndustryService.SellTo(src, industryId, item, qty)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    local industryConfig = Config.Industries[industryId]
    if not industryConfig then return false, 'Indústria não encontrada' end

    -- Validar distância física do jogador até a indústria (fail-closed)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 'Jogador inválido'
    end
    local playerCoords = GetEntityCoords(ped)
    local indCoords = vec3(industryConfig.coords.x, industryConfig.coords.y, industryConfig.coords.z)
    local maxDist = industryConfig.radius or 15.0
    if #(playerCoords - indCoords) > maxDist then
        return false, 'Muito longe da indústria'
    end

    local state = MySQL.single.await(
        "SELECT * FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'consumption' LIMIT 1",
        { industryId, item }
    )

    if not state then return false, 'Produto não aceito aqui' end

    -- Verificar limite de stock
    local maxStock
    for _, c in ipairs(industryConfig.consumption or {}) do
        if c.item == item then maxStock = c.maxStock; break end
    end
    if maxStock and state.current_stock + qty > maxStock then
        return false, 'Indústria não consegue receber mais desse produto'
    end

    -- Remover item do inventário
    local ok = exports.ox_inventory:RemoveItem(src, item, qty)
    if not ok then return false, 'Você não tem esse item' end

    local totalPrice = state.current_price * qty
    Framework.AddMoney(Player, 'cash', totalPrice, 'industry-sale')
    EconomyService.RecordSale(industryId, item, qty)
    return true, nil
end

-- ============================================================
-- NPC FAIL-SAFE: abastece indústrias de consumo sem insumos
-- ============================================================

function IndustryService.RunNpcFailsafe()
    local cfg    = Config.Economy
    local delay  = cfg.npcFailsafeDelay  or 1800
    local amount = cfg.npcFailsafeAmount or 10

    local starved = DB_GetStarvedConsumptionItems(delay) or {}
    for _, row in ipairs(starved) do
        if Config.Industries[row.industry_id] then
            DB_UpdateIndustryStock(row.industry_id, row.item, 'consumption', amount)
            DB_SetNpcFillTime(row.industry_id, row.item)
            if Config.Debug then
                print(('[aurp_trucker] NPC fail-safe: +%d %s → %s'):format(
                    amount, row.item, row.industry_id))
            end
        end
    end
end

-- Ciclo de produção das indústrias (cron)
-- ATENÇÃO: indústrias terciárias têm production = nil — pular produção
-- [M4-FIX] Um SELECT único por ciclo substitui N queries individuais por indústria
function IndustryService.RunProductionCycle(isPrimary)
    local targetType = isPrimary and 'primary' or 'secondary'

    local rows = MySQL.query.await(
        "SELECT industry_id, item, current_stock FROM trucker_industry_state WHERE entry_type = 'production'"
    ) or {}
    local stockMap = {}
    for _, row in ipairs(rows) do
        stockMap[row.industry_id .. ':' .. row.item] = row.current_stock
    end

    for industryId, industry in pairs(Config.Industries) do
        if industry.production ~= nil and industry.type == targetType then
            local key = industryId .. ':' .. industry.production.item
            local currentStock = stockMap[key]
            if currentStock ~= nil and currentStock < industry.production.maxStock then
                DB_UpdateIndustryStock(industryId, industry.production.item, 'production', 1)
            end
        end
    end

    -- Custo operacional deduzido uma vez por ciclo primário
    if isPrimary then
        IndustryOwnershipService.RunOperationalCosts()
    end
end

-- Threads de produção
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(Config.Economy.primaryProductionInterval)
        IndustryService.RunProductionCycle(true)  -- primárias
    end
end)

CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(Config.Economy.secondaryProductionInterval)
        IndustryService.RunProductionCycle(false)  -- secundárias
    end
end)

-- Thread NPC fail-safe (a cada 5 minutos)
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(300000)  -- 5 minutos
        IndustryService.RunNpcFailsafe()
    end
end)
