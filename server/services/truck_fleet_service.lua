-- ============================================================
-- AUST_trucker — server/services/truck_fleet_service.lua
-- Gestão de Concessionária, Frota de Caminhões, Desgaste e Oficinas
-- ============================================================

TruckFleetService = {}

-- Retorna catálogo da concessionária
function TruckFleetService.GetCatalog()
    return Config.LC_Dealership or {}
end

-- Lista caminhões de um jogador
function TruckFleetService.GetPlayerTrucks(citizenId)
    local trucks = MySQL.query.await(
        'SELECT * FROM trucker_trucks WHERE user_id = ? ORDER BY truck_id DESC',
        { citizenId }
    ) or {}
    return trucks
end

-- Compra de caminhão na concessionária
function TruckFleetService.BuyTruck(src, citizenId, truckModel)
    local catalog = Config.LC_Dealership or {}
    local data = catalog[truckModel]
    if not data then
        return false, 'Modelo de caminhão indisponível no catálogo'
    end

    -- Checa nível do jogador
    local playerStats = DB_GetPlayerStats(citizenId)
    local currentLevel = playerStats and playerStats.level or 1
    if currentLevel < (data.required_level or 0) then
        return false, ('Nível insuficiente. Necessário nível %d'):format(data.required_level)
    end

    local price = data.price or 50000
    local balance = Framework.GetPlayerMoney(src, 'bank')
    if balance < price then
        return false, 'Saldo bancário insuficiente'
    end

    if not Framework.RemovePlayerMoney(src, 'bank', price, 'Compra de caminhão: ' .. data.name) then
        return false, 'Falha ao processar pagamento bancário'
    end

    local truckId = MySQL.insert.await(
        [[INSERT INTO trucker_trucks (user_id, truck_name, driver, body, engine, transmission, wheels, fuel, properties, garage_id)
          VALUES (?, ?, NULL, 1000, 1000, 1000, 1000, 100, '{}', 'trucker_1')]],
        { citizenId, truckModel }
    )

    return true, { truckId = truckId, model = truckModel, name = data.name }
end

-- Venda de caminhão próprio (70% do valor)
function TruckFleetService.SellTruck(src, citizenId, truckId)
    local truck = MySQL.single.await(
        'SELECT * FROM trucker_trucks WHERE truck_id = ? AND user_id = ? LIMIT 1',
        { truckId, citizenId }
    )
    if not truck then
        return false, 'Caminhão não encontrado na sua frota'
    end

    if truck.driver and truck.driver > 0 then
        return false, 'Desaloque o motorista antes de vender este caminhão'
    end

    local catalog = Config.LC_Dealership or {}
    local data = catalog[truck.truck_name]
    local basePrice = data and data.price or 30000
    local mult = Config.LC_SellMultiplier or 0.70
    local refund = math.floor(basePrice * mult)

    MySQL.query.await('DELETE FROM trucker_trucks WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })
    Framework.AddPlayerMoney(src, 'bank', refund, 'Venda de caminhão: ' .. truck.truck_name)

    return true, refund
end

-- Reparo mecânico (desgaste por componente)
function TruckFleetService.RepairTruck(src, citizenId, truckId, part)
    local truck = MySQL.single.await(
        'SELECT * FROM trucker_trucks WHERE truck_id = ? AND user_id = ? LIMIT 1',
        { truckId, citizenId }
    )
    if not truck then
        return false, 'Caminhão não encontrado'
    end

    local repairPrices = Config.LC_RepairPrice or {
        engine = 75,
        body = 40,
        transmission = 50,
        wheels = 25,
        fuel = 5
    }

    local totalCost = 0
    local updates = {}

    local function calcComponent(name, currentVal)
        local damagePercent = math.max(0, math.floor((1000 - currentVal) / 10))
        local cost = damagePercent * (repairPrices[name] or 30)
        return damagePercent, cost
    end

    if part == 'all' then
        for _, comp in ipairs({'engine', 'body', 'transmission', 'wheels'}) do
            local _, cost = calcComponent(comp, truck[comp] or 1000)
            totalCost = totalCost + cost
        end
        updates = { engine = 1000, body = 1000, transmission = 1000, wheels = 1000 }
    elseif repairPrices[part] then
        local _, cost = calcComponent(part, truck[part] or 1000)
        totalCost = cost
        updates[part] = 1000
    else
        return false, 'Componente mecânico inválido'
    end

    if totalCost <= 0 then
        return false, 'O veículo já está em perfeitas condições'
    end

    local balance = Framework.GetPlayerMoney(src, 'bank')
    if balance < totalCost then
        return false, ('Saldo bancário insuficiente. Custo: $%d'):format(totalCost)
    end

    if not Framework.RemovePlayerMoney(src, 'bank', totalCost, 'Reparo de frota') then
        return false, 'Falha ao processar pagamento de reparo'
    end

    local setClauses = {}
    local params = {}
    for k, v in pairs(updates) do
        table.insert(setClauses, string.format('%s = ?', k))
        table.insert(params, v)
    end
    table.insert(params, truckId)
    table.insert(params, citizenId)

    local query = string.format('UPDATE trucker_trucks SET %s WHERE truck_id = ? AND user_id = ?', table.concat(setClauses, ', '))
    MySQL.update.await(query, params)

    return true, { cost = totalCost, updates = updates }
end

-- Atualização de desgaste após viagem (server-authoritative)
function TruckFleetService.ApplyTripWear(citizenId, truckId, distanceKm)
    local wearFactor = math.max(1, math.floor(distanceKm * 2))
    MySQL.update.await(
        [[UPDATE trucker_trucks
          SET engine = GREATEST(100, engine - ?),
              body = GREATEST(100, body - ?),
              transmission = GREATEST(100, transmission - ?),
              wheels = GREATEST(100, wheels - ?),
              fuel = GREATEST(5, fuel - ?)
          WHERE truck_id = ? AND user_id = ?]],
        { wearFactor * 3, wearFactor * 2, wearFactor * 2, wearFactor * 4, math.floor(distanceKm * 1.5), truckId, citizenId }
    )
end
