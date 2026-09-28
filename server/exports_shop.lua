-- aurp_trucker — server/exports_shop.lua
-- Exports para integração externa com o sistema de estoque de lojas (v16.0.0)
-- Uso: exports.AUST_trucker:ConsumeShopStock('General_1', 'burger', 1)

exports('ConsumeShopStock', function(shopId, itemName, qty)
    if not ShopStockService then return true end -- sem serviço = infinito
    return ShopStockService.ConsumeStock(shopId, itemName, qty)
end)

exports('RestockShop', function(shopId, itemName, qty)
    if not ShopStockService then return end
    return ShopStockService.OnDelivery(shopId, itemName, qty)
end)

exports('GetShopStock', function(shopId, itemName)
    if not ShopStockService then return -1 end
    return ShopStockService.GetStock(shopId, itemName)
end)

exports('GetAllShopStocks', function()
    if not ShopStockService then return {} end
    return ShopStockService.GetAllShopStocks()
end)
