-- aurp_trucker — server/services/truck_simulation_service.lua
-- Gerencia sincronização de combustível, fadiga e upgrades de frota

TruckSimulationService = {}

-- Estado em memória por jogador: { lastFuel, lastFatigue, lastSyncTime, vehicleWasMoving, currentPlate }
local SimState = {}

-- ============================================================
-- INICIALIZAÇÃO DO JOGADOR
-- ============================================================

-- Chamado quando jogador conecta (via evento QBCore:Server:OnPlayerLoaded)
function TruckSimulationService.OnPlayerLoaded(src)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local fatigue = DB_GetFatigue(citizenId)
    SimState[src] = {
        lastFuel         = 100.0,
        lastFatigue      = fatigue,
        lastSyncTime     = GetGameTimer(),
        vehicleWasMoving = false,
        currentPlate     = nil,
        coords           = vector3(0, 0, 0),
    }

    TriggerClientEvent('aurp_trucker:client:setFatigue', src, { fatigue = fatigue })
end

-- ============================================================
-- SPAWN DE VEÍCULO
-- ============================================================

-- Chamado quando jogador pega veículo da empresa
function TruckSimulationService.OnVehicleSpawn(src, plate)
    local Player = Framework.GetPlayer(src)
    if not Player then return end

    local fuel = DB_GetVehicleFuel(plate)
    if SimState[src] then
        SimState[src].lastFuel     = fuel
        SimState[src].currentPlate = plate
    end

    -- Enviar config de upgrades junto com o fuel
    local company   = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    local upgrades  = company and DB_GetFleetUpgrades(company.id) or {}
    local hasAntiSleep = upgrades.anti_sleep == true

    TriggerClientEvent('aurp_trucker:client:setVehicleFuel', src, { plate = plate, fuel = fuel })
    TriggerClientEvent('aurp_trucker:client:setSimConfig',   src, { hasAntiSleep = hasAntiSleep })
end

-- ============================================================
-- SYNC PERIÓDICO
-- ============================================================

-- payload = { fuel, fatigue, vehicleWasMoving, plate }
function TruckSimulationService.OnSync(src, payload)
    local state = SimState[src]
    if not state then return end

    local now      = GetGameTimer()
    local elapsed  = (now - state.lastSyncTime) / 1000.0  -- segundos
    state.lastSyncTime = now

    -- Validar combustível: teto e piso
    local reportedFuel = tonumber(payload.fuel) or state.lastFuel
    local cfg          = Config.TruckSimulation.Fuel
    local maxDrop      = cfg.ConsumptionRate * cfg.LoadedMultiplier * elapsed * 1.2
    local minDrop      = cfg.ConsumptionRate * elapsed * 0.5
    local actualDrop   = state.lastFuel - reportedFuel

    local savedFuel
    if actualDrop > maxDrop then
        savedFuel = state.lastFuel - maxDrop
    elseif actualDrop < minDrop and payload.vehicleWasMoving then
        savedFuel = state.lastFuel - (cfg.ConsumptionRate * elapsed)
    else
        savedFuel = reportedFuel
    end
    savedFuel = math.max(0.0, math.min(100.0, savedFuel))

    -- Validar fadiga: aceita qualquer valor entre 0-100 (acúmulo client-side é confiável)
    local savedFatigue = math.max(0.0, math.min(100.0, tonumber(payload.fatigue) or state.lastFatigue))

    -- Persistir
    local plate = payload.plate or state.currentPlate
    if plate then DB_SetVehicleFuel(plate, savedFuel) end

    local Player = Framework.GetPlayer(src)
    if Player then DB_SetFatigue(Framework.GetCitizenId(Player), savedFatigue) end

    state.lastFuel         = savedFuel
    state.lastFatigue      = savedFatigue
    state.vehicleWasMoving = payload.vehicleWasMoving or false
    -- audit C-01: rastrear integridade server-side (clamp 0-100; nil = sem job ativo)
    if payload.integrity ~= nil then
        local reportedIntegrity = tonumber(payload.integrity) or 100
        -- Integridade só pode diminuir (nunca aumenta durante viagem)
        local current = state.lastIntegrity or 100
        state.lastIntegrity = math.max(0, math.min(current, reportedIntegrity))
    end
    if payload.coords then
        local c = payload.coords
        state.coords = vector3(
            tonumber(c.x) or 0,
            tonumber(c.y) or 0,
            tonumber(c.z) or 0
        )
    end
end

-- ============================================================
-- CHECKPOINTS OBRIGATÓRIOS
-- ============================================================

function TruckSimulationService.OnVehicleDestroyed(src, payload)
    -- Força sync do estado atual; job será marcado como failed pelo JobService
    TruckSimulationService.OnSync(src, payload)
end

function TruckSimulationService.OnPlayerDropped(src)
    local state   = SimState[src]
    if not state then return end
    local Player  = Framework.GetPlayer(src)
    -- Persistir último estado conhecido
    if Player then DB_SetFatigue(Framework.GetCitizenId(Player), state.lastFatigue) end
    if state.currentPlate then DB_SetVehicleFuel(state.currentPlate, state.lastFuel) end
    SimState[src] = nil
end

-- ============================================================
-- FLEET UPGRADES
-- ============================================================

-- Retorna true se empresa tem o upgrade
function TruckSimulationService.HasUpgrade(companyId, upgradeKey)
    local upgrades = DB_GetFleetUpgrades(companyId)
    return upgrades[upgradeKey] == true
end

-- Retorna última posição conhecida do jogador (vector3) ou nil se não houver SimState
function TruckSimulationService.GetCoords(src)
    local state = SimState[src]
    if not state then return nil end
    return state.coords
end

-- Retorna true se jogador está atualmente em um caminhão (tem plate no SimState)
function TruckSimulationService.IsInTruck(src)
    local state = SimState[src]
    return state ~= nil and state.currentPlate ~= nil
end

-- H1: Retorna nível de combustível rastreado server-side (0–100)
-- Usado por payForFuel para calcular preço sem confiar no cliente
function TruckSimulationService.GetLastFuel(src)
    local state = SimState[src]
    return state and state.lastFuel or 100.0
end

-- H1: Atualiza combustível server-side após reabastecimento
function TruckSimulationService.SetLastFuel(src, fuelLevel)
    local state = SimState[src]
    if state then
        state.lastFuel = math.max(0.0, math.min(100.0, fuelLevel))
        if state.currentPlate then
            DB_SetVehicleFuel(state.currentPlate, state.lastFuel)
        end
    end
end

-- Compra upgrade — retorna { success, reason }
function TruckSimulationService.PurchaseUpgrade(src, upgradeKey)
    local Player = Framework.GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end

    local upgrade = Config.FleetUpgrades[upgradeKey]
    if not upgrade then return { success = false, reason = 'Upgrade inválido' } end

    local company = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    if not company then return { success = false, reason = 'Sem empresa' } end

    local member = DB_GetMember(Framework.GetCitizenId(Player))
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Sem permissão' }
    end

    local upgrades = DB_GetFleetUpgrades(company.id)
    if upgrades[upgradeKey] then
        return { success = false, reason = 'Upgrade já adquirido' }
    end

    local companyData = CompanyService.Get(company.id)
    if not companyData or companyData.balance < upgrade.price then
        return { success = false, reason = 'Saldo insuficiente' }
    end

    -- Deduzir do saldo da empresa
    local newBalance = DB_UpdateCompanyBalance(company.id, -upgrade.price)
    if not newBalance then
        return { success = false, reason = 'Saldo insuficiente' }
    end
    if VP_Trucker.Companies[company.id] then
        VP_Trucker.Companies[company.id].balance = newBalance
    end

    -- Salvar upgrade
    upgrades[upgradeKey] = true
    DB_SetFleetUpgrades(company.id, upgrades)

    -- Notificar membros online que estão nesta empresa
    if upgradeKey == 'anti_sleep' then
        for _, playerSrc in ipairs(GetPlayers()) do
            local src2 = tonumber(playerSrc)
            local p = Framework.GetPlayer(src2)
            if p then
                local memberCompany = CompanyService.GetByMember(Framework.GetCitizenId(p))
                if memberCompany and memberCompany.id == company.id then
                    TriggerClientEvent('aurp_trucker:client:setSimConfig', src2, { hasAntiSleep = true })
                end
            end
        end
    end

    return { success = true }
end

-- Retorna estado de sim de um jogador (para exports)
function TruckSimulationService.GetState(src)
    return SimState[src]
end

-- audit C-01: retorna integridade rastreada server-side (0-100).
-- Fallback 100 se sem dado de sync ainda (ex: entrega muito rápida antes do 1o sync).
function TruckSimulationService.GetLastIntegrity(src)
    local state = SimState[src]
    if not state then return 100 end
    -- Resetar após leitura para evitar reutilização em jobs subsequentes
    local val = state.lastIntegrity or 100
    state.lastIntegrity = nil
    return val
end

-- PERF: Cleanup periódico de entradas órfãs — fallback caso playerDropped event
-- falhe ou o recurso reinicie sem disparar o evento
Citizen.CreateThread(function()
    while true do
        Wait(600000)  -- a cada 10 minutos
        local connected = {}
        for _, src in ipairs(GetPlayers()) do
            connected[tonumber(src)] = true
        end
        local pruned = 0
        for src in pairs(SimState) do
            if not connected[src] then
                SimState[src] = nil
                pruned = pruned + 1
            end
        end
        if pruned > 0 and Config.Debug then
            print(('[aurp_trucker] SimState pruning: %d entradas órfãs removidas'):format(pruned))
        end
    end
end)
