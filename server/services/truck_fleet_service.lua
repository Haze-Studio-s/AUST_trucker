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

local BuyingTruckLock = {}
local SellingTruckLock = {}

-- Executa fn sob lock por citizenId; SEMPRE libera o lock (pcall)
local function WithLock(lockTable, citizenId, fn, ...)
    if lockTable[citizenId] then
        return false, 'Transação em andamento, aguarde'
    end
    lockTable[citizenId] = true
    local ok, r1, r2 = pcall(fn, ...)
    lockTable[citizenId] = nil
    if not ok then
        print('[TruckFleetService] ERRO: ' .. tostring(r1))
        return false, 'Erro interno ao processar transação'
    end
    return r1, r2
end

local function _BuyTruck(src, citizenId, truckModel)
    local catalog = Config.LC_Dealership or {}
    local data = type(truckModel) == 'string' and catalog[truckModel] or nil
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
    if (tonumber(balance) or 0) < price then
        return false, 'Saldo bancário insuficiente'
    end

    if not Framework.RemovePlayerMoney(src, 'bank', price, 'Compra de caminhão: ' .. data.name) then
        return false, 'Falha ao processar pagamento bancário'
    end

    local okIns, truckId = pcall(MySQL.insert.await,
        [[INSERT INTO trucker_trucks (user_id, truck_name, driver, body, engine, transmission, wheels, fuel, properties, garage_id)
          VALUES (?, ?, NULL, 1000, 1000, 1000, 1000, 100, '{}', 'trucker_1')]],
        { citizenId, truckModel }
    )
    if not okIns or not truckId then
        print(('[TruckFleetService] ERRO insert BuyTruck (%s): %s - reembolsando'):format(tostring(citizenId), tostring(truckId)))
        Framework.AddPlayerMoney(src, 'bank', price, 'Reembolso: compra de caminhão falhou')
        return false, 'Falha ao registrar caminhão. Valor reembolsado.'
    end

    return true, { truckId = truckId, model = truckModel, name = data.name }
end

-- Compra de caminhão na concessionária
function TruckFleetService.BuyTruck(src, citizenId, truckModel)
    return WithLock(BuyingTruckLock, citizenId, _BuyTruck, src, citizenId, truckModel)
end

local function _SellTruck(src, citizenId, truckId)
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

    local affected = MySQL.update.await('DELETE FROM trucker_trucks WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })
    if not affected or affected == 0 then
        return false, 'Caminhão já vendido ou indisponível'
    end

    Framework.AddPlayerMoney(src, 'bank', refund, 'Venda de caminhão: ' .. truck.truck_name)

    return true, refund
end

-- Venda de caminhão próprio (70% do valor)
function TruckFleetService.SellTruck(src, citizenId, truckId)
    return WithLock(SellingTruckLock, citizenId, _SellTruck, src, citizenId, truckId)
end

-- Componentes permitidos (whitelist para nomes de coluna dinâmicos)
local REPAIR_COMPONENTS = { engine = true, body = true, transmission = true, wheels = true }
local RepairingTruckLock = {}

local function _RepairTruck(src, citizenId, truckId, part)
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

    -- Componentes mecânicos: escala 0-1000
    local function calcComponent(name, currentVal)
        local damagePercent = math.max(0, math.floor((1000 - (tonumber(currentVal) or 1000)) / 10))
        local cost = damagePercent * (repairPrices[name] or 30)
        return damagePercent, cost
    end

    if part == 'all' then
        for comp in pairs(REPAIR_COMPONENTS) do
            local _, cost = calcComponent(comp, truck[comp] or 1000)
            totalCost = totalCost + cost
            updates[comp] = 1000
        end
    elseif part == 'fuel' then
        -- Combustível: escala 0-100 (1 ponto = 1%)
        local missing = math.max(0, 100 - (tonumber(truck.fuel) or 100))
        totalCost = missing * (repairPrices.fuel or 5)
        updates.fuel = 100
    elseif type(part) == 'string' and REPAIR_COMPONENTS[part] then
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
    if (tonumber(balance) or 0) < totalCost then
        return false, ('Saldo bancário insuficiente. Custo: $%d'):format(totalCost)
    end

    if not Framework.RemovePlayerMoney(src, 'bank', totalCost, 'Reparo de frota') then
        return false, 'Falha ao processar pagamento de reparo'
    end

    -- Nomes de coluna vêm somente da whitelist acima
    local setClauses = {}
    local params = {}
    for k, v in pairs(updates) do
        if REPAIR_COMPONENTS[k] or k == 'fuel' then
            table.insert(setClauses, string.format('%s = ?', k))
            table.insert(params, v)
        end
    end
    table.insert(params, truckId)
    table.insert(params, citizenId)

    local query = string.format('UPDATE trucker_trucks SET %s WHERE truck_id = ? AND user_id = ?', table.concat(setClauses, ', '))
    local okUpd, affected = pcall(MySQL.update.await, query, params)
    if not okUpd or not affected or affected == 0 then
        print(('[TruckFleetService] ERRO update RepairTruck (%s): %s - reembolsando'):format(tostring(citizenId), tostring(affected)))
        Framework.AddPlayerMoney(src, 'bank', totalCost, 'Reembolso: reparo de frota falhou')
        return false, 'Falha ao aplicar reparo. Valor reembolsado.'
    end

    return true, { cost = totalCost, updates = updates }
end

-- Reparo mecânico (desgaste por componente)
function TruckFleetService.RepairTruck(src, citizenId, truckId, part)
    return WithLock(RepairingTruckLock, citizenId, _RepairTruck, src, citizenId, truckId, part)
end

-- Atualização de desgaste após viagem (server-authoritative)
-- Colunas são UNSIGNED: converte para SIGNED antes de subtrair (evita overflow/erro)
function TruckFleetService.ApplyTripWear(citizenId, truckId, distanceKm)
    distanceKm = tonumber(distanceKm) or 0
    local wearFactor = math.max(1, math.floor(distanceKm * 2))
    MySQL.update.await(
        [[UPDATE trucker_trucks
          SET engine = GREATEST(100, CAST(engine AS SIGNED) - ?),
              body = GREATEST(100, CAST(body AS SIGNED) - ?),
              transmission = GREATEST(100, CAST(transmission AS SIGNED) - ?),
              wheels = GREATEST(100, CAST(wheels AS SIGNED) - ?),
              fuel = GREATEST(5, CAST(fuel AS SIGNED) - ?)
          WHERE truck_id = ? AND user_id = ?]],
        { wearFactor * 3, wearFactor * 2, wearFactor * 2, wearFactor * 4, math.floor(distanceKm * 1.5), truckId, citizenId }
    )
end
