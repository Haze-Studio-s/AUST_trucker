-- Industries NPC Client
-- Handles NPC spawning and interactions for buying/selling

local spawnedNPCs = {}

-- Spawn NPC at industry location
local function SpawnIndustryNPC(industryId, industry)
    local coords = industry.coords

    -- Load model
    local model = joaat('s_m_m_trucker_01')
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end

    -- Create ped
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, 0.0, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    -- Store NPC reference
    spawnedNPCs[industryId] = ped

    -- Add ox_target interaction
    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'industry_' .. industryId,
            label = industry.name,
            icon = 'fas fa-industry',
            distance = 2.5,
            onSelect = function()
                OpenIndustryMenu(industryId, industry)
            end
        }
    })

    if Config.Debug then
        if Config.Debug then print('[AURP_TRUCKER] NPC spawned at:', industry.name) end
    end
end

-- Open industry menu
function OpenIndustryMenu(industryId, industry)
    local ok, industryData = pcall(lib.callback.await, 'aurp_trucker:getIndustryData', false, industryId)
    if not ok or not industryData then
        lib.notify({ title = 'AURP Trucker', description = 'Indústria não encontrada', type = 'error' })
        return
    end

    local menuOptions = {}

        -- Header option (read-only)
        table.insert(menuOptions, {
            title = industryData.name,
            description = 'Tipo: ' .. (industryData.industryType == 'primary' and 'Produtora' or industryData.industryType == 'secondary' and 'Processadora' or 'Distribuidora'),
            icon = 'fas fa-industry',
            iconColor = '#339af0',
            readOnly = true
        })

        -- Production status for secondary industries
        if industryData.industryType == 'secondary' and industryData.productionStatus then
            local statusColor = industryData.canProduce and '#2b8a3e' or '#ff6b6b'
            local statusIcon = industryData.canProduce and 'fas fa-circle-check' or 'fas fa-circle-xmark'

            table.insert(menuOptions, {
                title = '⚙️ Status de Produção',
                description = industryData.productionStatus,
                icon = statusIcon,
                iconColor = statusColor,
                readOnly = true,
                metadata = industryData.canProduce and {
                    { label = 'Receita', value = '2 itens de cada → 1 produto' }
                } or {
                    { label = 'Requisito', value = 'Mínimo 2 de cada material' }
                }
            })
        end

        -- Production items (sell to players)
        if industryData.production and industryData.production.product then
            local prod = industryData.production
            table.insert(menuOptions, {
                title = '🔹 Comprar ' .. prod.product,
                description = string.format('Preço: $%d | Stock: %d/%d %s', prod.price, prod.currentStock, prod.maxStock, prod.unit),
                icon = 'fas fa-shopping-cart',
                iconColor = '#2b8a3e',
                progress = (prod.currentStock / prod.maxStock) * 100,
                metadata = {
                    { label = 'Preço', value = '$' .. prod.price },
                    { label = 'Stock Disponível', value = prod.currentStock .. '/' .. prod.maxStock },
                    { label = 'Taxa de Produção', value = '+' .. prod.productionPerHour .. '/h' }
                },
                onSelect = function()
                    OpenBuyMenu(industryId, prod)
                end
            })
        end

        -- Consumption items (buy from players)
        if industryData.consumption and #industryData.consumption > 0 then
            for _, item in ipairs(industryData.consumption) do
                table.insert(menuOptions, {
                    title = '🔸 Vender ' .. item.product,
                    description = string.format('Preço: $%d | Stock: %d/%d %s', item.price, item.currentStock, item.maxStock, item.unit),
                    icon = 'fas fa-hand-holding-usd',
                    iconColor = '#408cff',
                    progress = (item.currentStock / item.maxStock) * 100,
                    metadata = {
                        { label = 'Preço de Compra', value = '$' .. item.price },
                        { label = 'Stock Atual', value = item.currentStock .. '/' .. item.maxStock },
                        { label = 'Taxa de Consumo', value = '-' .. item.consumptionPerHour .. '/h' }
                    },
                    onSelect = function()
                        OpenSellMenu(industryId, item)
                    end
                })
            end
        end

        -- Show menu
        lib.registerContext({
            id = 'trucker_industry_' .. industryId,
            title = industryData.name,
            options = menuOptions
        })

        lib.showContext('trucker_industry_' .. industryId)
end

-- Open buy menu (player buys from industry)
function OpenBuyMenu(industryId, product)
    local input = lib.inputDialog('Comprar ' .. product.product, {
        {
            type = 'number',
            label = 'Quantidade',
            description = 'Preço unitário: $' .. product.price,
            required = true,
            min = 1,
            max = product.currentStock
        }
    })

    if not input then return end

    local amount = tonumber(input[1])
    if not amount or amount <= 0 then
        lib.notify({ title = 'AURP Trucker', description = 'Quantidade inválida', type = 'error' })
        return
    end

    if amount > product.currentStock then
        lib.notify({ title = 'AURP Trucker', description = 'Stock insuficiente', type = 'error' })
        return
    end

    TriggerServerEvent('aurp_trucker:buyFromIndustry', industryId, product.item, amount)
end

-- Open sell menu (player sells to industry)
function OpenSellMenu(industryId, item)
    local input = lib.inputDialog('Vender ' .. item.product, {
        {
            type = 'number',
            label = 'Quantidade',
            description = 'Preço por unidade: $' .. item.price,
            required = true,
            min = 1,
            max = 999
        }
    })

    if not input then return end

    local amount = tonumber(input[1])
    if not amount or amount <= 0 then
        lib.notify({ title = 'AURP Trucker', description = 'Quantidade inválida', type = 'error' })
        return
    end

    TriggerServerEvent('aurp_trucker:sellToIndustry', industryId, item.item, amount)
end

-- Initialize NPCs on resource start
CreateThread(function()
    Wait(2000) -- Wait for config to load

    for industryId, industry in pairs(Config.Industries) do
        SpawnIndustryNPC(industryId, industry)
    end

    if Config.Debug then
        if Config.Debug then print('[AURP_TRUCKER] All industry NPCs spawned') end
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, ped in pairs(spawnedNPCs) do
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped)
            DeleteEntity(ped)
        end
    end
end)
