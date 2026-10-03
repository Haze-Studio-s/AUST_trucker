-- =======================================================================
-- AUST_trucker — client/cargo_liquid.lua
-- Sistema de Carga Líquida: Abastecimento de Tanque, Mangueira, PTFX e Zonas de Risco
-- Stack QBOX / OX: ox_lib, ox_target, OneSync Server-Side Truth
-- =======================================================================

CargoLiquid = {}

local CurrentJobData = nil
local TrailerEntity = nil
local TruckEntity = nil
local HoseProp = nil
local HoldingHose = false
local CurrentStage = 'IDLE' -- IDLE, WAITING_HOSE, HOLDING_HOSE, CONNECTED, FILLING, FILLED
local RiskZonePoint = nil
local TerminalTargetZones = {}
local FillingActive = false

-- =======================================================================
-- LIMPEZA DO MÓDULO DE CARGA LÍQUIDA
-- =======================================================================
function CargoLiquid.Cleanup()
    if RiskZonePoint then
        pcall(function() RiskZonePoint:remove() end)
        RiskZonePoint = nil
    end

    for _, zoneId in ipairs(TerminalTargetZones) do
        pcall(function() exports.ox_target:removeZone(zoneId) end)
    end
    TerminalTargetZones = {}

    if TrailerEntity and DoesEntityExist(TrailerEntity) then
        pcall(function() exports.ox_target:removeLocalEntity(TrailerEntity) end)
    end

    if HoseProp and DoesEntityExist(HoseProp) then
        DetachEntity(HoseProp, true, true)
        DeleteEntity(HoseProp)
        HoseProp = nil
    end

    HoldingHose = false
    FillingActive = false
    CurrentStage = 'IDLE'
    CurrentJobData = nil
    TrailerEntity = nil
    TruckEntity = nil
    lib.hideTextUI()
end

-- =======================================================================
-- HELPER: EFEITO VISUAL PTFX DE VAZAMENTO DE COMBUSTÍVEL
-- =======================================================================
local function PlayFuelLeakPtfx(coords)
    lib.requestNamedPtfxAsset('core')
    UseParticleFxAssetNextCall('core')
    local pfx = StartParticleFxLoopedAtCoord(
        'ent_sht_petrol',
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        1.6,
        false, false, false, false
    )

    PlaySoundFrontend(-1, "FLIGHT_SCHOOL_LESSON_FAILED", "HUD_AWARDS", 0)

    SetTimeout(6000, function()
        if pfx then
            StopParticleFxLooped(pfx, false)
        end
    end)
end

-- =======================================================================
-- MONITORAMENTO DE SEGURANÇA: ENTRADA EM VEÍCULO COM MANGUEIRA
-- =======================================================================
local function StartSafetyVehicleWatcher()
    CreateThread(function()
        while HoldingHose do
            Wait(250)
            local ped = cache.ped or PlayerPedId()
            if IsPedInAnyVehicle(ped, false) or IsPedGettingIntoAVehicle(ped) then
                if CurrentJobData then
                    TriggerServerEvent('aurp_trucker:server:cancelHose', CurrentJobData.jobId)
                end

                if HoseProp and DoesEntityExist(HoseProp) then
                    DetachEntity(HoseProp, true, true)
                    DeleteEntity(HoseProp)
                    HoseProp = nil
                end

                HoldingHose = false
                CurrentStage = 'WAITING_HOSE'

                lib.notify({
                    title = 'Violação de Segurança',
                    description = 'A mangueira foi recolhida automaticamente porque você entrou no veículo!',
                    type = 'error',
                    duration = 6000
                })
                break
            end
        end
    end)
end

-- =======================================================================
-- INICIALIZAÇÃO DA CARGA LÍQUIDA
-- =======================================================================
function CargoLiquid.Setup(jobData, trailer, truck)
    CargoLiquid.Cleanup()
    CurrentJobData = jobData
    TrailerEntity = trailer
    TruckEntity = truck
    CurrentStage = 'WAITING_HOSE'

    local liquidCfg = Config.CargoTypes and Config.CargoTypes.liquid
    if not liquidCfg then return end

    -- 1. Registro de ox_target nos terminais/bombas de combustível mapeados
    for _, term in ipairs(liquidCfg.fuelTerminals or {}) do
        local zoneId = exports.ox_target:addBoxZone({
            coords = term.coords,
            size = vec3(term.radius or 2.5, term.radius or 2.5, 3.0),
            rotation = (term.pumpCoords and term.pumpCoords.w) or 0.0,
            options = {
                {
                    name = 'aust_pickup_liquid_hose_' .. term.id,
                    icon = 'fa-solid fa-gas-pump',
                    label = 'Pegar Mangueira de Combustível',
                    distance = 2.8,
                    canInteract = function()
                        return CurrentStage == 'WAITING_HOSE' and not HoldingHose
                    end,
                    onSelect = function()
                        TriggerServerEvent('aurp_trucker:server:pickupHose', CurrentJobData.jobId, term.id)
                    end
                }
            }
        })
        table.insert(TerminalTargetZones, zoneId)
    end

    -- 2. Registro de ox_target no caminhão-tanque / carreta
    if trailer and DoesEntityExist(trailer) then
        exports.ox_target:addLocalEntity(trailer, {
            {
                name = 'aust_connect_liquid_hose',
                icon = 'fa-solid fa-link',
                label = 'Conectar Mangueira na Válvula',
                distance = 3.5,
                canInteract = function()
                    return HoldingHose and (CurrentStage == 'HOLDING_HOSE' or CurrentStage == 'WAITING_HOSE')
                end,
                onSelect = function()
                    local ok = lib.progressBar({
                        duration = 3200,
                        label = 'Conectando mangueira na válvula do tanque...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' }
                    })

                    if ok then
                        TriggerServerEvent('aurp_trucker:server:connectHose', CurrentJobData.jobId)
                    end
                end
            },
            {
                name = 'aust_disconnect_liquid_hose',
                icon = 'fa-solid fa-link-slash',
                label = 'Desconectar e Guardar Mangueira',
                distance = 3.5,
                canInteract = function()
                    return CurrentStage == 'FILLED'
                end,
                onSelect = function()
                    local ok = lib.progressBar({
                        duration = 3500,
                        label = 'Desconectando mangueira e selando válvulas...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' }
                    })

                    if ok then
                        TriggerServerEvent('aurp_trucker:server:disconnectHose', CurrentJobData.jobId)
                    end
                end
            }
        })
    end

    lib.notify({
        title = 'Carga Líquida Iniciada',
        description = 'Estacione próximo à bomba, pegue a mangueira e conecte-a na lateral da carreta-tanque.',
        type = 'inform',
        duration = 8000
    })
end

-- =======================================================================
-- EVENTOS DO SERVIDOR
-- =======================================================================

-- 1. Mangueira autorizada pelo servidor
RegisterNetEvent('aurp_trucker:client:hosePickedUp', function(jobId, hoseNetId)
    if not CurrentJobData or CurrentJobData.jobId ~= jobId then return end

    local start = GetGameTimer()
    while not NetworkDoesNetworkIdExist(hoseNetId) and GetGameTimer() - start < 4000 do
        Wait(100)
    end

    local prop = nil
    if NetworkDoesNetworkIdExist(hoseNetId) then
        prop = NetworkGetEntityFromNetworkId(hoseNetId)
    end

    -- Fallback de criação client-side caso OneSync demore na propagação do prop
    if not prop or not DoesEntityExist(prop) then
        local pHash = joaat('prop_cs_fuel_nozle')
        lib.requestModel(pHash)
        local ped = cache.ped or PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        prop = CreateObject(pHash, pCoords.x, pCoords.y, pCoords.z, true, true, false)
    end

    HoseProp = prop
    HoldingHose = true
    CurrentStage = 'HOLDING_HOSE'

    local ped = cache.ped or PlayerPedId()
    local handBone = GetPedBoneIndex(ped, 28422) -- Mão Direita (SKEL_R_Hand)

    AttachEntityToEntity(
        prop, ped, handBone,
        0.12, 0.05, 0.0,
        80.0, 0.0, 0.0,
        true, true, false, true, 1, true
    )

    StartSafetyVehicleWatcher()

    lib.notify({
        title = 'Mangueira em Mãos',
        description = 'Leve a mangueira até o bocal lateral do caminhão-tanque para conectar.',
        type = 'success',
        duration = 7000
    })
end)

-- 2. Mangueira conectada no bocal do tanque
RegisterNetEvent('aurp_trucker:client:hoseConnected', function(jobId)
    if not CurrentJobData or CurrentJobData.jobId ~= jobId then return end

    HoldingHose = false
    CurrentStage = 'FILLING'
    FillingActive = true

    local liquidCfg = Config.CargoTypes and Config.CargoTypes.liquid
    local attachOffset = (liquidCfg and liquidCfg.tankerAttachOffset) or vector3(-1.45, -2.5, 0.5)

    if HoseProp and DoesEntityExist(HoseProp) and TrailerEntity and DoesEntityExist(TrailerEntity) then
        DetachEntity(HoseProp, true, true)
        AttachEntityToEntity(
            HoseProp, TrailerEntity, 0,
            attachOffset.x, attachOffset.y, attachOffset.z,
            0.0, 90.0, 0.0,
            false, false, false, false, 2, true
        )
    end

    -- Criação da zona de risco (ox_lib.points) monitorando a distância máxima (9.0m)
    local trailerCoords = GetEntityCoords(TrailerEntity)
    local maxDist = (liquidCfg and liquidCfg.maxDistance) or 9.0

    if RiskZonePoint then pcall(function() RiskZonePoint:remove() end) end

    RiskZonePoint = lib.points.new({
        coords = trailerCoords,
        distance = maxDist,
        onExit = function()
            if CurrentStage == 'FILLING' and FillingActive then
                FillingActive = false
                TriggerServerEvent('aurp_trucker:server:hoseLeak', CurrentJobData.jobId)
            end
        end,
        nearby = function(self)
            if DoesEntityExist(TrailerEntity) then
                self.coords = GetEntityCoords(TrailerEntity)
            end
        end
    })

    -- Simulação de enchimento (0% a 100%)
    CreateThread(function()
        local duration = (liquidCfg and liquidCfg.fillDuration) or 12000
        local startTime = GetGameTimer()

        while FillingActive and CurrentStage == 'FILLING' do
            local elapsed = GetGameTimer() - startTime
            local pct = math.min(100, math.floor((elapsed / duration) * 100))

            lib.showTextUI(('Abastecendo Tanque: %d%%'):format(pct), {
                position = 'top-center',
                icon = 'gas-pump'
            })

            if pct >= 100 then
                lib.hideTextUI()
                CurrentStage = 'FILLED'
                FillingActive = false
                PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", 0)

                lib.notify({
                    title = 'Abastecimento Concluído',
                    description = 'Tanque 100% cheio! Desconecte a mangueira na lateral da carreta para liberar a rota.',
                    type = 'success',
                    duration = 9000
                })
                break
            end
            Wait(200)
        end
    end)
end)

-- 3. Vazamento de combustível por rompimento de mangueira
RegisterNetEvent('aurp_trucker:client:playLeakPtfx', function(jobId, penalty)
    if not CurrentJobData or CurrentJobData.jobId ~= jobId then return end

    FillingActive = false
    lib.hideTextUI()

    local coords = TrailerEntity and DoesEntityExist(TrailerEntity) and GetEntityCoords(TrailerEntity) or GetEntityCoords(PlayerPedId())
    PlayFuelLeakPtfx(coords)

    if HoseProp and DoesEntityExist(HoseProp) then
        DetachEntity(HoseProp, true, true)
        DeleteEntity(HoseProp)
        HoseProp = nil
    end

    CurrentStage = 'WAITING_HOSE'
    HoldingHose = false

    lib.notify({
        title = 'PERIGO: Vazamento de Combustível!',
        description = ('Você se afastou além da distância limite! Mangueira rompida e multa de $%d aplicada.'):format(penalty or 1500),
        type = 'error',
        duration = 10000
    })
end)

-- 4. Cancelamento de mangueira
RegisterNetEvent('aurp_trucker:client:hoseCancelled', function(jobId)
    if not CurrentJobData or CurrentJobData.jobId ~= jobId then return end
    HoldingHose = false
    CurrentStage = 'WAITING_HOSE'
    if HoseProp and DoesEntityExist(HoseProp) then
        DetachEntity(HoseProp, true, true)
        DeleteEntity(HoseProp)
        HoseProp = nil
    end
end)

-- 5. Conclusão do carregamento líquido (Desconexão bem sucedida)
RegisterNetEvent('aurp_trucker:client:liquidLoadingCompleted', function(jobId, deliveryCoords)
    CargoLiquid.Cleanup()
    lib.notify({
        title = 'Válvula Selada',
        description = 'Mangueira guardada e carga lacrada! Rota traçada no GPS.',
        type = 'success',
        duration = 8000
    })
end)

RegisterNetEvent('aurp_trucker:client:cleanupCargoLiquid', function()
    CargoLiquid.Cleanup()
end)

-- Limpeza ao parar o resource (zonas, mangueira, textUI)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    pcall(CargoLiquid.Cleanup)
end)

return CargoLiquid
