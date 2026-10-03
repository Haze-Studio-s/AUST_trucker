-- aurp_trucker — server/services/economy_service.lua
-- Preços dinâmicos para Config.Industries (trading com ox_inventory)

EconomyService = {}

-- Cache de preços em memória: { [industryId] = { [item..entryType] = price } }
local priceCache = {}

local function cacheKey(industryId, item, entryType)
    return industryId .. ':' .. item .. ':' .. entryType
end

-- Inicializa cache a partir do DB
function EconomyService.Init()
    local rows = DB_GetAllIndustryState() or {}
    for _, row in ipairs(rows) do
        local key = cacheKey(row.industry_id, row.item, row.entry_type)
        priceCache[key] = row.current_price
    end
    if Config.Debug then
        print(('[aurp_trucker] EconomyService: %d price entries loaded'):format(#rows))
    end
end

function EconomyService.GetPrice(industryId, item, entryType)
    local key = cacheKey(industryId, item, entryType)
    return priceCache[key]
end

-- Atualiza preços com base em supply/demand
function EconomyService.UpdatePrices()
    local cfg = Config.Economy
    local rows = DB_GetAllIndustryState() or {}

    for _, row in ipairs(rows) do
        local industryConfig = Config.Industries[row.industry_id]
        if not industryConfig then goto continue end

        local maxStock, basePrice

        if row.entry_type == 'production' and industryConfig.production then
            maxStock  = industryConfig.production.maxStock
            basePrice = industryConfig.production.basePrice
        else
            -- encontrar item de consumo no config
            if industryConfig.consumption then
                for _, c in ipairs(industryConfig.consumption) do
                    if c.item == row.item then
                        maxStock  = c.maxStock
                        basePrice = c.basePrice
                        break
                    end
                end
            end
        end

        if not maxStock or maxStock == 0 or not basePrice then goto continue end

        local stockRatio = row.current_stock / maxStock  -- 0.0 a 1.0
        local targetMult

        if row.entry_type == 'production' then
            -- Mais stock → oferta alta → preço cai
            targetMult = cfg.priceCeiling - (cfg.priceCeiling - cfg.priceFloor) * stockRatio
        else
            -- Mais stock → demanda baixa → preço sobe (pagamos mais se temos pouco)
            targetMult = cfg.priceFloor + (cfg.priceCeiling - cfg.priceFloor) * (1 - stockRatio)
        end

        local currentMult = row.current_price / basePrice
        local newMult = currentMult + (targetMult - currentMult) * cfg.priceAdjustmentSpeed
        newMult = math.max(cfg.priceFloor, math.min(cfg.priceCeiling, newMult))

        local newPrice = math.floor(basePrice * newMult)
        DB_UpdateIndustryPrice(row.industry_id, row.item, row.entry_type, newPrice)

        local key = cacheKey(row.industry_id, row.item, row.entry_type)
        priceCache[key] = newPrice

        ::continue::
    end
end

-- Debounce: marca sujo e recalcula no máximo uma vez a cada poucos segundos
local pricesDirty, pricesTimerArmed = false, false
local PRICE_DEBOUNCE_MS = 5000

local function SchedulePriceUpdate()
    pricesDirty = true
    if pricesTimerArmed then return end
    pricesTimerArmed = true
    SetTimeout(PRICE_DEBOUNCE_MS, function()
        pricesTimerArmed = false
        if not pricesDirty then return end
        pricesDirty = false
        local ok, err = pcall(EconomyService.UpdatePrices)
        if not ok then print(('[aurp_trucker] Economy debounce erro: %s'):format(tostring(err))) end
    end)
end

function EconomyService.RecordSale(industryId, item, qty)
    -- Jogador vendeu item para indústria → stock de consumo aumenta
    DB_UpdateIndustryStock(industryId, item, 'consumption', qty)
    SchedulePriceUpdate()
end

function EconomyService.RecordPurchase(industryId, item, qty)
    -- Jogador comprou item da indústria → stock de produção diminui
    DB_UpdateIndustryStock(industryId, item, 'production', -qty)
    SchedulePriceUpdate()
end

-- Loop de atualização de preços
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    EconomyService.Init()

    while true do
        Wait(Config.Economy.priceUpdateInterval)
        pricesDirty = false
        local ok, err = pcall(EconomyService.UpdatePrices)
        if not ok then
            print(('[aurp_trucker] Economy UpdatePrices erro: %s'):format(tostring(err)))
        elseif Config.Debug then
            print('[aurp_trucker] Economy prices updated')
        end
    end
end)
