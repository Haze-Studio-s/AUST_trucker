-- aurp_trucker — server/exports_shop.lua
-- Exports para integração externa com o sistema de estoque de lojas (v16.0.0)
-- Uso: exports.AUST_trucker:ConsumeShopStock('General_1', 'burger', 1)

-- Quantidade válida: número finito, inteiro positivo e dentro de um teto sensato
local function validQty(qty)
    if type(qty) ~= 'number' or qty ~= qty or qty == math.huge or qty == -math.huge then return nil end
    if qty <= 0 or qty % 1 ~= 0 or qty > 100000 then return nil end
    return qty
end

local function validKey(v)
    return type(v) == 'string' and v ~= '' and #v <= 64
end

exports('ConsumeShopStock', function(shopId, itemName, qty)
    if not ShopStockService then return true end -- sem serviço = infinito
    if not validKey(shopId) or not validKey(itemName) then return false end
    if qty == nil then qty = 1 end
    qty = validQty(qty)
    if not qty then return false end
    return ShopStockService.ConsumeStock(shopId, itemName, qty)
end)

exports('RestockShop', function(shopId, itemName, qty)
    if not ShopStockService then return end
    if not validKey(shopId) or not validKey(itemName) then return end
    qty = validQty(qty)
    if not qty then return end
    return ShopStockService.OnDelivery(shopId, itemName, qty)
end)

exports('GetShopStock', function(shopId, itemName)
    if not ShopStockService then return -1 end
    if not validKey(shopId) or not validKey(itemName) then return -1 end
    return ShopStockService.GetStock(shopId, itemName)
end)

exports('GetAllShopStocks', function()
    if not ShopStockService then return {} end
    return ShopStockService.GetAllShopStocks()
end)
