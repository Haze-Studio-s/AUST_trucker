-- aurp_trucker — client/hud.client.lua
-- Simulação de viagem: combustível, fadiga, integridade de carga, HUD

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local SimState = {
    -- Veículo
    currentVehicle   = nil,
    currentPlate     = nil,
    lastKnownPlate   = nil,   -- preservado até conclusão do job (C2 fix)
    isTruck          = false,

    -- Combustível
    fuel             = 100.0,
    lastSyncTime     = 0,

    -- Fadiga
    fatigue          = 0.0,
    hasAntiSleep     = false,
    sleepTriggered   = false,

    -- Integridade de carga
    integrity        = 100.0,
    hasActiveJob     = false,
    prevSpeed        = 0.0,
    lastImpactTime   = 0,
    prevBodyHealth   = 1000.0,

    -- Movimento (para anticheat piso)
    vehicleWasMoving = false,
}

-- ============================================================
-- HELPERS
-- ============================================================

local function IsTruckModel(model)
    for _, name in ipairs(Config.TruckSimulation.TruckModels) do
        if model == GetHashKey(name) then return true end
    end
    return false
end

local function SendHUDUpdate()
    if not Config.TruckSimulation.HUD.Enabled then return end
    SendNUIMessage({
        action    = 'updateHUD',
        visible   = SimState.isTruck,
        speed     = SimState.isTruck and math.floor(GetEntitySpeed(SimState.currentVehicle) * 3.6) or 0,
        fuel      = SimState.fuel,
        position  = Config.TruckSimulation.HUD.Position,
        fatigue   = SimState.fatigue,
        integrity = SimState.hasActiveJob and SimState.integrity or nil,
    })
end

local function SyncToServer()
    local coords = SimState.currentVehicle and GetEntityCoords(SimState.currentVehicle) or nil
    TriggerServerEvent('aurp_trucker:syncSimulation', {
        fuel             = SimState.fuel,
        fatigue          = SimState.fatigue,
        vehicleWasMoving = SimState.vehicleWasMoving,
        plate            = SimState.currentPlate,
        -- audit C-01: enviar integridade para rastreio server-side (não confiar no payload de completeJob)
        integrity        = SimState.hasActiveJob and math.floor(SimState.integrity) or nil,
        coords           = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })
    SimState.lastSyncTime = GetGameTimer()
end

-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

RegisterNetEvent('aurp_trucker:client:setVehicleFuel', function(data)
    if data.plate == SimState.currentPlate then
        SimState.fuel = data.fuel
        if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
            SetVehicleFuelLevel(SimState.currentVehicle, (SimState.fuel / 100.0) * Config.TruckSimulation.Fuel.TankCapacityGTA)
        end
    end
end)

RegisterNetEvent('aurp_trucker:client:setFatigue', function(data)
    SimState.fatigue = math.max(0.0, math.min(100.0, data.fatigue or 0.0))
end)

RegisterNetEvent('aurp_trucker:client:setSimConfig', function(data)
    if data.hasAntiSleep ~= nil then
        SimState.hasAntiSleep = data.hasAntiSleep
    end
end)

RegisterNetEvent('aurp_trucker:client:upgradeResult', function(result)
    if result.success then
        lib.notify({ title = 'Upgrade', description = 'Upgrade adquirido com sucesso!', type = 'success' })
    else
        lib.notify({ title = 'Erro', description = result.reason or 'Erro desconhecido', type = 'error' })
    end
end)

-- Job iniciado: reinicia integridade
local function OnJobStartedHUD()
    SimState.integrity      = 100.0
    SimState.hasActiveJob   = true
    SimState.prevSpeed      = 0.0
    SimState.lastImpactTime = 0
    if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
        SimState.prevBodyHealth = GetVehicleBodyHealth(SimState.currentVehicle)
    else
        SimState.prevBodyHealth = 1000.0
    end
end
RegisterNetEvent('aurp_trucker:client:jobStarted', OnJobStartedHUD)
RegisterNetEvent('aurp_trucker:client:hudJobStarted', OnJobStartedHUD)
RegisterNetEvent('aurp_trucker:client:polarixJobStarted', OnJobStartedHUD)

-- Job concluído (confirmação do servidor): reseta estado e limpa lastKnownPlate
RegisterNetEvent('aurp_trucker:client:jobCompleted', function()
    SimState.hasActiveJob   = false
    SimState.integrity      = 100.0
    SimState.lastKnownPlate = nil
end)

-- Veículo destruído: sync + notifica servidor
local function OnVehicleDestroyed()
    if not SimState.isTruck then return end
    TriggerServerEvent('aurp_trucker:vehicleDestroyed', {
        fuel             = SimState.fuel,
        fatigue          = SimState.fatigue,
        vehicleWasMoving = SimState.vehicleWasMoving,
        plate            = SimState.currentPlate,
    })
    SimState.currentVehicle = nil
    SimState.currentPlate   = nil
    SimState.isTruck        = false
    SimState.hasActiveJob   = false
    SimState.integrity      = 100.0
end

-- ============================================================
-- THREAD: DETECÇÃO DE VEÍCULO (1s)
-- ============================================================

local prevIsTruck = false
CreateThread(function()
    while true do
        Wait(1000)
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 then
            local model   = GetEntityModel(vehicle)
            local isTruck = IsTruckModel(model)

            if isTruck then
                if vehicle ~= SimState.currentVehicle then
                    if SimState.currentVehicle then SyncToServer() end

                    local plate = GetVehicleNumberPlateText(vehicle)
                    SimState.currentVehicle = vehicle
                    SimState.currentPlate   = plate
                    SimState.lastKnownPlate = plate   -- preservado até jobCompleted
                    SimState.isTruck        = true
                    SimState.sleepTriggered = false

                    TriggerServerEvent('aurp_trucker:spawnVehicle', plate)
                end

                if IsVehicleDriveable(vehicle, false) == false or GetEntityHealth(vehicle) <= 0 then
                    OnVehicleDestroyed()
                end

                SimState.vehicleWasMoving = GetEntitySpeed(vehicle) > 2.0
            else
                if SimState.isTruck then SyncToServer() end
                SimState.currentVehicle   = nil
                SimState.currentPlate     = nil
                SimState.isTruck          = false
                SimState.vehicleWasMoving = false
            end
        else
            if SimState.isTruck then SyncToServer() end
            SimState.currentVehicle   = nil
            SimState.currentPlate     = nil
            SimState.isTruck          = false
            SimState.vehicleWasMoving = false
        end

        -- Notificar convoy.client.lua quando isTruck mudar
        if SimState.isTruck ~= prevIsTruck then
            prevIsTruck = SimState.isTruck
            TriggerEvent('aurp_trucker:client:truckStateChanged', SimState.isTruck, SimState.currentPlate)
        end
    end
end)

-- ============================================================
-- THREAD: COMBUSTÍVEL (1s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        if not SimState.isTruck then goto continue end

        local cfg    = Config.TruckSimulation.Fuel
        local loaded = SimState.hasActiveJob and cfg.LoadedMultiplier or 1.0
        local consume = cfg.ConsumptionRate * loaded
        SimState.fuel = math.max(0.0, SimState.fuel - consume)

        if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
            SetVehicleFuelLevel(SimState.currentVehicle, (SimState.fuel / 100.0) * Config.TruckSimulation.Fuel.TankCapacityGTA)

            if SimState.fuel <= 0.0 then
                SetVehicleEnginePowerMultiplier(SimState.currentVehicle, 0.0)
            else
                SetVehicleEnginePowerMultiplier(SimState.currentVehicle, 1.0)
            end
        end

        if (GetGameTimer() - SimState.lastSyncTime) >= cfg.SyncInterval then
            SyncToServer()
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: FADIGA (1s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        if not SimState.isTruck then goto continue end
        if not SimState.currentVehicle then goto continue end

        local speed = GetEntitySpeed(SimState.currentVehicle)
        if speed < 2.0 then goto continue end

        local cfg = Config.TruckSimulation.Fatigue
        SimState.fatigue = math.min(100.0, SimState.fatigue + cfg.IncreaseRate)

        if SimState.fatigue >= cfg.HeavyThreshold then
            SetTimecycleModifier('HighContrast')
            SetTimecycleModifierStrength(cfg.TimecycleHeavyStrength)
        elseif SimState.fatigue >= cfg.WarnThreshold then
            SetTimecycleModifier('HighContrast')
            SetTimecycleModifierStrength(cfg.TimecycleWarnStrength)
        else
            ClearTimecycleModifier()
        end

        if SimState.fatigue >= cfg.CriticalThreshold then
            if (GetGameTimer() % 30000) < 1100 then
                lib.notify({ title = 'Fadiga Crítica!', description = 'Pare para descansar imediatamente!', type = 'error', duration = 5000 })
            end
        end

        if SimState.fatigue >= 100.0 and not SimState.sleepTriggered then
            if speed >= cfg.MinSpeedForSleep then
                SimState.sleepTriggered = true
                CreateThread(function()
                    DoScreenFadeOut(500)
                    Wait(500)

                    local vehicle = SimState.currentVehicle
                    if SimState.hasAntiSleep then
                        if vehicle and DoesEntityExist(vehicle) then
                            SetVehicleEnginePowerMultiplier(vehicle, 0.0)
                            local ped = PlayerPedId()
                            TaskVehicleTempAction(ped, vehicle, 1, 3000)
                        end
                        Wait(2000)
                        DoScreenFadeIn(500)
                        lib.notify({ title = 'Sistema Anti-Sono', description = 'Sistema ADAS ativado — veículo parado com segurança.', type = 'warning', duration = 5000 })
                    else
                        if vehicle and DoesEntityExist(vehicle) then
                            SetVehicleEnginePowerMultiplier(vehicle, 2.0)
                        end
                        Wait(3000)
                        if vehicle and DoesEntityExist(vehicle) then
                            SetVehicleEnginePowerMultiplier(vehicle, 1.0)
                        end
                        DoScreenFadeIn(500)
                        if SimState.hasActiveJob then
                            SimState.integrity = math.max(0.0, SimState.integrity - (Config.TruckSimulation.Cargo.ImpactDamage * 2))
                        end
                    end

                    SimState.sleepTriggered = false
                    ClearTimecycleModifier()
                end)
            end
        elseif SimState.fatigue < 100.0 then
            SimState.sleepTriggered = false
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: INTEGRIDADE DE CARGA (0.5s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(500)
        if not SimState.isTruck or not SimState.hasActiveJob then
            SimState.prevSpeed = 0.0
            goto continue
        end
        local veh = SimState.currentVehicle
        if not veh or not DoesEntityExist(veh) then goto continue end

        local cfg     = Config.TruckSimulation.Cargo
        local speed   = GetEntitySpeed(veh)
        local prevSpd = SimState.prevSpeed or 0.0
        SimState.prevSpeed = speed

        local decel = prevSpd - speed
        local now   = GetGameTimer()

        -- Checagem de impacto com tolerância calibrada e debounce
        if decel > (cfg.ImpactThreshold or 10.0) then
            local cooldown = cfg.ImpactCooldown or 2500
            if (now - (SimState.lastImpactTime or 0)) >= cooldown then
                -- 1. Detecção de frenagem intencional do jogador (S / Freio de Mão / Ré)
                local isBraking = IsControlPressed(0, 72) or IsControlPressed(0, 76) or IsDisabledControlPressed(0, 72) or IsDisabledControlPressed(0, 76)

                -- 2. Detecção física de colisão real no cavalo e na carreta
                local hasCollided = HasEntityCollidedWithAnything(veh)
                local hasTrailer, trailer = GetVehicleTrailerVehicle(veh)
                if hasTrailer and DoesEntityExist(trailer) and HasEntityCollidedWithAnything(trailer) then
                    hasCollided = true
                end

                -- 3. Detecção de deformação e dano na lataria
                local currentBodyHealth = GetVehicleBodyHealth(veh)
                local bodyDamage = (SimState.prevBodyHealth or 1000.0) - currentBodyHealth
                SimState.prevBodyHealth = currentBodyHealth

                local isCatastrophic = decel >= (cfg.CatastrophicThreshold or 18.0)
                local isTrueCollision = hasCollided or (bodyDamage > 3.0) or isCatastrophic

                -- Frenagem limpa sem bater em nada NUNCA causa dano
                if not isBraking or isTrueCollision then
                    if isTrueCollision then
                        local baseDmg = cfg.ImpactDamageBase or 4.0
                        local maxDmg = cfg.ImpactDamageMax or 15.0
                        local severityRatio = math.max(1.0, decel / (cfg.ImpactThreshold or 10.0))
                        local calculatedDamage = math.min(maxDmg, baseDmg * severityRatio)

                        SimState.integrity = math.max(0.0, SimState.integrity - calculatedDamage)
                        SimState.lastImpactTime = now

                        lib.notify({
                            title = 'Carga Danificada!',
                            description = ('Impacto detectado — Integridade: %d%%'):format(math.floor(SimState.integrity)),
                            type = 'error',
                            duration = 3500
                        })
                    end
                end
            end
        else
            if veh and DoesEntityExist(veh) then
                SimState.prevBodyHealth = GetVehicleBodyHealth(veh)
            end
        end

        -- Dano suave por velocidade excessiva acima do limite de segurança da rodovia
        if cfg.SpeedLimit and speed > cfg.SpeedLimit then
            local overRate = cfg.SpeedDamageRate or 0.002
            SimState.integrity = math.max(0.0, SimState.integrity - (overRate * 0.5))
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: HUD UPDATE (0.5s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(500)
        SendHUDUpdate()
    end
end)

-- ============================================================
-- BRIDGE: completeJob → servidor com cargoIntegrity injetado
-- ============================================================
-- client.lua dispara TriggerEvent('aurp_trucker:client:sendIntegrity', deliveryTime)
-- Este handler (em hud.client.lua, mesmo resource) pode acessar SimState diretamente.
-- NOTA lua54: named events cruzam chunks do mesmo resource (apenas `local` vars não cruzam).

AddEventHandler('aurp_trucker:client:sendIntegrity', function(deliveryTime)
    -- currentPlate pode ser nil se o jogador saiu do caminhão na zona de entrega
    -- (thread de detecção tem intervalo de 1s). lastKnownPlate é preservado até
    -- jobCompleted chegar do servidor, garantindo que DB_SetVehicleFuel seja chamado.
    local plate = SimState.currentPlate or SimState.lastKnownPlate
    TriggerServerEvent('aurp_trucker:completeJob', {
        deliveryTime   = deliveryTime,
        plate          = plate,
        cargoIntegrity = math.floor(SimState.integrity),
    })
end)

-- ============================================================
-- OX_TARGET: POSTOS DE COMBUSTÍVEL
-- ============================================================

CreateThread(function()
    while not exports['ox_target'] do Wait(100) end

    for _, station in ipairs(Config.TruckSimulation.Fuel.GasStations) do
        exports.ox_target:addSphereZone({
            name    = 'gas_station_' .. station.name,
            coords  = station.coords,
            radius  = station.radius or 5.0,
            options = {
                {
                    name        = 'refuel_truck',
                    label       = 'Abastecer Caminhão',
                    icon        = 'fas fa-gas-pump',
                    distance    = 3.0,
                    canInteract = function() return SimState.isTruck and SimState.fuel < 99.0 end,
                    onSelect    = function()
                        local needed = 100.0 - SimState.fuel
                        local price  = math.ceil(needed * Config.TruckSimulation.Fuel.FuelPricePerUnit)
                        local confirmed = lib.alertDialog({
                            header  = 'Abastecer',
                            content = ('Tanque: %.0f%% → 100%%\nCusto: $%d'):format(SimState.fuel, price),
                            centered = true,
                            cancel   = true,
                        })
                        if confirmed ~= 'confirm' then return end

                        -- H1: price não é mais enviado ao servidor (calculado server-side)
                        local ok, err = lib.callback.await('aurp_trucker:payForFuel', false)
                        if ok then
                            SimState.fuel = 100.0
                            if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
                                SetVehicleFuelLevel(SimState.currentVehicle, Config.TruckSimulation.Fuel.TankCapacityGTA)
                            end
                            SyncToServer()
                            lib.notify({ title = 'Abastecido', description = 'Tanque cheio!', type = 'success' })
                        else
                            lib.notify({ title = 'Erro', description = err or 'Saldo insuficiente', type = 'error' })
                        end
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- OX_TARGET: PARADAS DE DESCANSO
-- ============================================================

CreateThread(function()
    while not exports['ox_target'] do Wait(100) end

    for _, stop in ipairs(Config.TruckSimulation.Fatigue.RestStops) do
        exports.ox_target:addSphereZone({
            name    = 'rest_stop_' .. stop.name,
            coords  = stop.coords,
            radius  = stop.radius or 8.0,
            options = {
                {
                    name        = 'rest_driver',
                    label       = 'Descansar (' .. stop.name .. ')',
                    icon        = 'fas fa-bed',
                    distance    = 4.0,
                    canInteract = function() return SimState.fatigue > 5.0 end,
                    onSelect    = function()
                        local cfg       = Config.TruckSimulation.Fatigue
                        local duration  = math.ceil(SimState.fatigue * cfg.RestDuration)
                        local startedAt = GetGameTimer()

                        lib.progressBar({
                            duration  = duration * 1000,
                            label     = ('Descansando... (%.0f%% fadiga)'):format(SimState.fatigue),
                            canCancel = true,
                            disable   = { car = true, combat = true },
                            anim      = { dict = 'amb@world_human_seat_wall@male@base', clip = 'base' },
                        }, function(completed)
                            local elapsed    = (GetGameTimer() - startedAt) / 1000.0
                            local actualTime = completed and duration or elapsed
                            local reduction  = cfg.RestoreRate * actualTime
                            SimState.fatigue = math.max(0.0, SimState.fatigue - reduction)
                            ClearTimecycleModifier()
                            SyncToServer()

                            if completed then
                                lib.notify({ title = 'Descansado!', description = 'Fadiga zerada.', type = 'success' })
                            else
                                lib.notify({ title = 'Descanso interrompido', description = ('Fadiga: %.0f%%'):format(SimState.fatigue), type = 'warning' })
                            end
                        end)
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- CLEANUP — L-02: remover zones de ox_target no onResourceStop
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, station in ipairs((Config.TruckSimulation.Fuel.GasStations) or {}) do
        pcall(exports.ox_target.removeZone, exports.ox_target, 'gas_station_' .. station.name)
    end
    for _, stop in ipairs((Config.TruckSimulation.Fatigue.RestStops) or {}) do
        pcall(exports.ox_target.removeZone, exports.ox_target, 'rest_stop_' .. stop.name)
    end
end)

-- ============================================================
-- EXPORT CLIENT-SIDE
-- ============================================================

exports('GetCargoIntegrity', function()
    if not SimState.hasActiveJob then return nil end
    return math.floor(SimState.integrity)
end)
