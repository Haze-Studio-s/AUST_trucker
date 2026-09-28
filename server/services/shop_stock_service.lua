-- aurp_trucker — server/services/shop_stock_service.lua
-- Ecossistema de estoque real: integra ox_inventory shops com logística de ressuprimento
-- Criado v16.0.0

ShopStockService = {}

-- ─── Cache: VP_Trucker.ShopStock[shopId:itemName] = row ──────────────────────

local function CacheKey(shopId, itemName)
    return shopId .. ':' .. itemName
end

-- ─── Inicialização ───────────────────────────────────────────────────────────

function ShopStockService.LoadFromDB()
    if not Config.ShopStock or not Config.ShopStock.Enabled then return end

    -- 1. Seed: garantir que todos os shops/items do Config existam no DB
    for shopType, shopCfg in pairs(Config.ShopStock.Shops) do
        local locations = shopCfg.locations or {}
        for locIdx, _ in ipairs(locations) do
            local shopId = shopType .. '_' .. locIdx
            for _, item in ipairs(shopCfg.items) do
                pcall(DB_UpsertShopStock, shopId, item.name, {
                    maxStock      = item.maxStock,
                    minThreshold  = item.minThreshold,
                    reorderQty    = item.reorderQty,
                    pricePerUnit  = item.pricePerUnit or Config.ShopStock.ContractPaymentPerUnit,
                    linkedType    = item.linkedType,
                    managementType = 'npc',
                })
            end
        end
    end

    -- 2. Carregar tudo do DB para cache
    local rows = DB_GetAllShopStock()
    VP_Trucker.ShopStock = {}
    for _, row in ipairs(rows) do
        VP_Trucker.ShopStock[CacheKey(row.shop_id, row.item_name)] = row
    end

    print(('[aurp_trucker] ShopStockService: %d registros de estoque carregados'):format(#rows))
end

-- ─── Consumo de estoque (chamado pelo hook ox_inventory buyItem) ─────────────

--- Consome qty unidades do estoque da loja.
--- @return boolean true se consumiu, false se esgotado ou item não rastreado
function ShopStockService.ConsumeStock(shopId, itemName, qty)
    qty = qty or 1
    local key = CacheKey(shopId, itemName)
    local cached = VP_Trucker.ShopStock[key]

    -- Item não rastreado → permitir compra (estoque infinito)
    if not cached then return true end

    -- Estoque insuficiente → bloquear compra
    if cached.current_stock < qty then return false end

    -- UPDATE atômico no DB
    local ok = DB_ConsumeShopStock(shopId, itemName, qty)
    if not ok then return false end

    -- Atualizar cache
    cached.current_stock = cached.current_stock - qty
    return true
end

-- ─── Entrega de ressuprimento (chamado quando contrato completa) ─────────────

function ShopStockService.OnDelivery(shopId, itemName, qty)
    if not shopId or not itemName or not qty or qty <= 0 then return end

    pcall(DB_RestockShop, shopId, itemName, qty)

    -- Atualizar cache
    local key = CacheKey(shopId, itemName)
    local cached = VP_Trucker.ShopStock[key]
    if cached then
        cached.current_stock = math.min(cached.max_stock, cached.current_stock + qty)
        cached.pending_contract_id = nil
    end

    if Config.Debug then
        print(('[aurp_trucker] ShopStock: entrega +%d %s para %s (novo stock: %d)'):format(
            qty, itemName, shopId, cached and cached.current_stock or -1
        ))
    end
end

-- ─── Consulta de estoque ─────────────────────────────────────────────────────

function ShopStockService.GetStock(shopId, itemName)
    local cached = VP_Trucker.ShopStock[CacheKey(shopId, itemName)]
    return cached and cached.current_stock or -1 -- -1 = não rastreado
end

function ShopStockService.GetAllShopStocks()
    return VP_Trucker.ShopStock or {}
end

-- ─── Geração automática de contratos de ressuprimento ────────────────────────

local function FindOriginIndustry(linkedType)
    -- Buscar PrimaryIndustry que tenha produto do tipo vinculado
    for _, industry in ipairs(Config.PrimaryIndustries) do
        if industry.type == linkedType then
            return industry
        end
    end
    -- Fallback: qualquer indústria tipo 'mixed'
    for _, industry in ipairs(Config.PrimaryIndustries) do
        if industry.type == 'mixed' then return industry end
    end
    return Config.PrimaryIndustries[1] -- último recurso
end

local function GetShopName(shopId)
    local shopType, locIdx = shopId:match('^(.+)_(%d+)$')
    if not shopType then return shopId end
    local cfg = Config.ShopStock.Shops[shopType]
    return cfg and (cfg.name .. ' #' .. locIdx) or shopId
end

local function GetShopCoords(shopId)
    local shopType, locIdx = shopId:match('^(.+)_(%d+)$')
    locIdx = tonumber(locIdx)
    if not shopType or not locIdx then return nil end
    local cfg = Config.ShopStock.Shops[shopType]
    if not cfg or not cfg.locations then return nil end
    return cfg.locations[locIdx]
end

function ShopStockService.CheckAndCreateContracts()
    if not ContractService or not ContractService.CreateResupplyContract then return end

    local lowStock = DB_GetLowStockShops()
    local created = 0

    for _, row in ipairs(lowStock) do
        local origin = FindOriginIndustry(row.linked_industry_type)
        if not origin then goto continue end

        local shopCoords = GetShopCoords(row.shop_id)
        if not shopCoords then goto continue end

        local shopName = GetShopName(row.shop_id)
        local qty = row.reorder_qty or 50
        local payPerUnit = row.price_per_unit or Config.ShopStock.ContractPaymentPerUnit

        local contractId = ContractService.CreateResupplyContract(
            row.shop_id, row.item_name, qty,
            shopName, shopCoords, origin, payPerUnit
        )

        if contractId then
            pcall(DB_SetShopPendingContract, row.shop_id, row.item_name, contractId)
            -- Atualizar cache
            local key = CacheKey(row.shop_id, row.item_name)
            if VP_Trucker.ShopStock[key] then
                VP_Trucker.ShopStock[key].pending_contract_id = contractId
            end
            created = created + 1
        end

        ::continue::
    end

    if created > 0 and Config.Debug then
        print(('[aurp_trucker] ShopStock: %d contratos de ressuprimento criados'):format(created))
    end
end

-- ─── NPC Failsafe: ressuprimento automático para lojas NPC zeradas ──────────

function ShopStockService.NpcAutoResupply()
    local amount = Config.ShopStock.NpcFailsafeAmount or 25
    local delay = Config.ShopStock.NpcFailsafeDelay or 1800

    local starved = MySQL.query.await([[
        SELECT shop_id, item_name, max_stock FROM trucker_shop_stock
        WHERE current_stock = 0 AND management_type = 'npc' AND pending_contract_id IS NULL
        AND (last_restock_at IS NULL OR last_restock_at < DATE_SUB(NOW(), INTERVAL ? SECOND))
    ]], { delay }) or {}

    for _, row in ipairs(starved) do
        local qty = math.min(amount, row.max_stock)
        pcall(DB_RestockShop, row.shop_id, row.item_name, qty)

        local key = CacheKey(row.shop_id, row.item_name)
        if VP_Trucker.ShopStock[key] then
            VP_Trucker.ShopStock[key].current_stock = math.min(row.max_stock, qty)
        end
    end

    if #starved > 0 and Config.Debug then
        print(('[aurp_trucker] ShopStock NPC failsafe: %d itens ressupridoss'):format(#starved))
    end
end

-- ─── Loops ───────────────────────────────────────────────────────────────────

CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    if not Config.ShopStock or not Config.ShopStock.Enabled then return end

    -- Registrar hook do ox_inventory APÓS resource estar pronto
    local hookOk = pcall(function()
        exports.ox_inventory:registerHook('buyItem', function(payload)
            local shopType = payload.shopType
            local shopId   = payload.shopId or 0
            local fullShopId = shopType .. '_' .. shopId
            local itemName = payload.itemName
            local count    = payload.count or 1

            local ok = ShopStockService.ConsumeStock(fullShopId, itemName, count)
            if not ok then
                -- Bloquear compra — fora de estoque
                return false
            end
            -- nil/true = permitir
        end)
    end)

    if hookOk then
        print('[aurp_trucker] ShopStockService: ox_inventory buyItem hook registrado')
    else
        print('[aurp_trucker] ShopStockService: WARN — ox_inventory hook falhou (ox_inventory não encontrado?)')
    end

    -- Loop de verificação de estoque baixo
    while true do
        Wait(Config.ShopStock.CheckInterval or 300000) -- 5 min
        pcall(ShopStockService.CheckAndCreateContracts)
    end
end)

-- Loop NPC failsafe separado
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    if not Config.ShopStock or not Config.ShopStock.Enabled then return end

    while true do
        Wait(900000) -- 15 min
        pcall(ShopStockService.NpcAutoResupply)
    end
end)
