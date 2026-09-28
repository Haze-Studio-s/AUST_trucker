-- aurp_trucker — server/services/truck_rental_service.lua
-- Sistema autoritativo de Aluguel de Caminhões com retenção e estorno de caução por avaria

TruckRentalService = {}

local ActiveRentals = {} -- [citizenId] = { plate, model, deposit, fee, rentedAt, netId, vehicleEntity }

function TruckRentalService.GetRental(citizenId)
    return ActiveRentals[citizenId]
end

function TruckRentalService.RegisterNetId(citizenId, netId)
    local rental = ActiveRentals[citizenId]
    if rental then
        rental.netId = tonumber(netId)
        if VP_Trucker and VP_Trucker.PlayerJobEntities then
            VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}
            VP_Trucker.PlayerJobEntities[citizenId].truckNetId = tonumber(netId)
            VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = rental.plate
        end
    end
end

-- Alugar caminhão (cobrança de taxa + caução no servidor)
lib.callback.register('aurp_trucker:rental:rentTruck', function(source, model)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    if ActiveRentals[citizenId] then
        return { success = false, reason = 'Você já possui um caminhão alugado ativo.' }
    end

    local truckCfg = nil
    for _, t in ipairs(Config.TruckRental.trucks or {}) do
        if t.model == model then
            truckCfg = t
            break
        end
    end

    if not truckCfg then
        return { success = false, reason = 'Modelo de caminhão não disponível para aluguel.' }
    end

    local fee = truckCfg.fee or Config.TruckRental.rentalFee or 300
    local deposit = truckCfg.deposit or Config.TruckRental.depositAmount or 1500
    local totalCost = fee + deposit

    -- Fail-closed: tentar debitar do banco ou dinheiro
    local removed = Framework.RemoveMoney(Player, 'bank', totalCost, 'truck-rental-deposit')
    if not removed then
        removed = Framework.RemoveMoney(Player, 'cash', totalCost, 'truck-rental-deposit')
        if not removed then
            return { success = false, reason = ('Saldo insuficiente. Necessário: $%d (Taxa: $%d + Caução: $%d)'):format(totalCost, fee, deposit) }
        end
    end

    local plate = ('ALUG%04d'):format(math.random(1000, 9999))

    ActiveRentals[citizenId] = {
        plate    = plate,
        model    = model,
        deposit  = deposit,
        fee      = fee,
        rentedAt = os.time(),
        netId    = nil
    }

    if VP_Trucker and VP_Trucker.PlayerJobEntities then
        VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}
        VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = plate
    end

    -- Registrar no banco para persistência idempotente
    CreateThread(function()
        pcall(MySQL.insert.await,
            'INSERT INTO trucker_rentals (citizenid, plate, model, deposit, fee, rented_at) VALUES (?, ?, ?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE plate = VALUES(plate), model = VALUES(model), deposit = VALUES(deposit), fee = VALUES(fee), rented_at = NOW()',
            { citizenId, plate, model, deposit, fee }
        )
    end)

    return {
        success     = true,
        plate       = plate,
        model       = model,
        deposit     = deposit,
        fee         = fee,
        spawnCoords = Config.TruckRental.spawnCoords
    }
end)

-- Devolver caminhão alugado (cálculo de avarias e estorno da caução)
lib.callback.register('aurp_trucker:rental:returnTruck', function(source, payload)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    local rental = ActiveRentals[citizenId]
    if not rental then
        return { success = false, reason = 'Você não possui nenhum aluguel ativo registrado.' }
    end

    payload = payload or {}
    local netId = tonumber(payload.netId or rental.netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId)

    -- Validação de existência
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return { success = false, reason = 'Caminhão não encontrado no mundo.' }
    end

    -- Validação de proximidade à vaga de devolução (fail-closed OneSync)
    local vehCoords = GetEntityCoords(entity)
    local returnCoords = Config.TruckRental.returnCoords
    local dist = #(vehCoords - returnCoords)
    if dist > (Config.TruckRental.returnRadius or 20.0) then
        return { success = false, reason = 'Estacione o caminhão na vaga de devolução da empresa.' }
    end

    -- Avaliação de danos (GTA V base health: 1000.0)
    local bodyHealth = tonumber(payload.bodyHealth) or 1000.0
    local engineHealth = tonumber(payload.engineHealth) or 1000.0
    local worstHealth = math.max(0.0, math.min(1000.0, math.min(bodyHealth, engineHealth)))

    local deposit = rental.deposit
    local damagePenalty = 0

    -- Se a vida estiver abaixo de 950, deduz proporcionalmente da caução
    if worstHealth < 950.0 then
        local damageFactor = 1.0 - (worstHealth / 1000.0)
        damagePenalty = math.floor(deposit * damageFactor)
        damagePenalty = math.min(deposit, damagePenalty)
    end

    local refund = math.max(0, deposit - damagePenalty)

    -- Devolver estorno ao banco do jogador
    if refund > 0 then
        Framework.AddMoney(Player, 'bank', refund, 'truck-deposit-refund')
    end

    -- Excluir entidade com segurança server-side
    DeleteEntity(entity)

    -- Limpar registros
    ActiveRentals[citizenId] = nil
    if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
        VP_Trucker.PlayerJobEntities[citizenId].truckNetId = nil
        VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = nil
    end

    CreateThread(function()
        pcall(MySQL.query.await, 'DELETE FROM trucker_rentals WHERE citizenid = ?', { citizenId })
    end)

    return {
        success       = true,
        deposit       = deposit,
        damagePenalty = damagePenalty,
        refund        = refund
    }
end)

-- Limpeza ao desconectar jogador
function TruckRentalService.OnPlayerDropped(citizenId)
    local rental = ActiveRentals[citizenId]
    if rental then
        if rental.netId then
            local ent = NetworkGetEntityFromNetworkId(rental.netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                DeleteEntity(ent)
            end
        end
        ActiveRentals[citizenId] = nil
    end
end
