-- =======================================================================
-- AUST_trucker — client/modules/adr_hazard.lua
-- Módulo de Risco Físico e Contenção de Emergência para Cargas Perigosas (ADR)
-- Partículas de Vazamento, Minigame de Válvula e Integridade Dinâmica
-- =======================================================================

local AdrHazardModule = {}
local MonitoringActive = false
local IsLeaking = false
local LeakPtfx = nil
local CurrentIntegrity = 100
local ContainmentZoneId = nil
local LastHealthTruck = 1000.0
local LastHealthTrailer = 1000.0

local function RequestPtfxAsset(asset)
    RequestNamedPtfxAsset(asset)
    local t = 0
    while not HasNamedPtfxAssetLoaded(asset) and t < 3000 do
        Wait(50)
        t = t + 50
    end
end

local function StartLeakPtfx(entity)
    if IsLeaking then return end
    IsLeaking = true

    RequestPtfxAsset('core')
    UseParticleFxAssetNextCall('core')

    LeakPtfx = StartParticleFxLoopedOnEntity(
        'ent_amb_smoke_gas_pipes',
        entity,
        0.0, -3.8, 0.4,
        0.0, 0.0, 0.0,
        1.2,
        false, false, false
    )
end

local function StopLeakPtfx()
    if LeakPtfx and DoesParticleFxLoopedExist(LeakPtfx) then
        StopParticleFxLooped(LeakPtfx, false)
        LeakPtfx = nil
    end
    IsLeaking = false
end

local function SetupContainmentTarget(jobId, trailer, onRepairedCb)
    if ContainmentZoneId then
        pcall(function() exports.ox_target:removeZone(ContainmentZoneId) end)
        ContainmentZoneId = nil
    end

    local valveCoords = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -4.5, 0.5)

    ContainmentZoneId = exports.ox_target:addSphereZone({
        coords = valveCoords,
        radius = 2.0,
        debug = false,
        options = {
            {
                name = 'aust_adr_contain_leak',
                icon = 'fas fa-wrench',
                label = 'Conter Vazamento Químico (Estancar Válvula)',
                distance = 2.5,
                canInteract = function()
                    return IsLeaking and not IsPedInAnyVehicle(cache.ped, false)
                end,
                onSelect = function()
                    local success = lib.skillCheck({'medium', 'hard', 'medium'}, {'w', 'a', 's', 'd'})
                    if success then
                        local ok = lib.progressBar({
                            duration = 4500,
                            label = 'Apertando válvula de alívio e contendo vazamento...',
                            useWhileDead = false,
                            canCancel = true,
                            disable = { move = true, car = true, combat = true },
                            anim = {
                                dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
                                clip = 'machinic_loop_meano',
                                flag = 49
                            }
                        })

                        if ok then
                            StopLeakPtfx()
                            if ContainmentZoneId then
                                pcall(function() exports.ox_target:removeZone(ContainmentZoneId) end)
                                ContainmentZoneId = nil
                            end
                            PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
                            SendMissionNotify('Emergência ADR', 'Vazamento contido com sucesso! Siga a viagem com cautela dobrada.', 'success')

                            TriggerServerEvent('aurp_trucker:server:adrLeakContained', jobId, CurrentIntegrity)
                            if onRepairedCb then onRepairedCb(CurrentIntegrity) end
                        end
                    else
                        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
                        SendMissionNotify('Falha na Contenção', 'A válvula escapou da ferramenta! O vazamento continua!', 'error')
                    end
                end
            }
        }
    })
end

function AdrHazardModule.StartMonitoring(jobId, truck, trailer, onIntegrityChangeCb)
    MonitoringActive = true
    IsLeaking = false
    CurrentIntegrity = 100
    LastHealthTruck = DoesEntityExist(truck) and GetVehicleBodyHealth(truck) or 1000.0
    LastHealthTrailer = DoesEntityExist(trailer) and GetVehicleBodyHealth(trailer) or 1000.0

    CreateThread(function()
        while MonitoringActive do
            Wait(350)
            if not truck or not DoesEntityExist(truck) then break end

            local speedKmh = GetEntitySpeed(truck) * 3.6
            local steerAngle = GetVehicleSteeringAngle(truck)
            local currentTruckHealth = GetVehicleBodyHealth(truck)
            local currentTrailerHealth = trailer and DoesEntityExist(trailer) and GetVehicleBodyHealth(trailer) or 1000.0

            local impactDetected = (LastHealthTruck - currentTruckHealth > 40.0) or (LastHealthTrailer - currentTrailerHealth > 40.0)
            local harshTurnDetected = (speedKmh > 58.0 and math.abs(steerAngle) > 16.0)

            LastHealthTruck = currentTruckHealth
            LastHealthTrailer = currentTrailerHealth

            if (impactDetected or harshTurnDetected) and not IsLeaking then
                local leakTarget = (trailer and DoesEntityExist(trailer)) and trailer or truck
                StartLeakPtfx(leakTarget)
                PlaySoundFrontend(-1, "WRECKED", "CAR_STEAL_2_SOUNDSET", true)
                SendMissionNotify('PERIGO ADR!', 'Vazamento químico iniciado por impacto ou curva brusca! Estacione e estanque a válvula.', 'error')

                SetupContainmentTarget(jobId, leakTarget, function(repairedIntegrity)
                    CurrentIntegrity = repairedIntegrity
                end)
            end

            -- Enquanto houver vazamento ativo, deduz gradualmente a integridade da carga
            if IsLeaking then
                CurrentIntegrity = math.max(10, CurrentIntegrity - 2)
                if onIntegrityChangeCb then
                    onIntegrityChangeCb(CurrentIntegrity)
                end
                Wait(2500)
            end
        end
    end)
end

function AdrHazardModule.StopMonitoring()
    MonitoringActive = false
    StopLeakPtfx()
    if ContainmentZoneId then
        pcall(function() exports.ox_target:removeZone(ContainmentZoneId) end)
        ContainmentZoneId = nil
    end
end

function AdrHazardModule.GetIntegrity()
    return CurrentIntegrity
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        AdrHazardModule.StopMonitoring()
    end
end)

return AdrHazardModule
