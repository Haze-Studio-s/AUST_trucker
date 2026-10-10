-- =======================================================================
-- AUST_trucker — client/main.lua
-- Máquina de Estados Autoritativa (9 Etapas Determinísticas)
-- Notificações Lation com Áudio, Abertura Física Real de Portas,
-- Props Polarix Exclusivos, Física Anti-Limbo e Gestor de Objetivos
-- Stack QBOX / OX: ox_lib, ox_target, ox_inventory, OneSync Server-Side Truth
-- =======================================================================

local ForkliftModule = _G.ForkliftModule or require('client.modules.forklift')
local ReachStackerModule = _G.ReachStackerModule or require('client.modules.reach_stacker')
local AdrHazardModule = _G.AdrHazardModule or require('client.modules.adr_hazard')

local ActiveJob = nil
local CurrentStage = 'IDLE' 
-- Estados: IDLE, STEP_1_START, STEP_2_ENTER_TRUCK, STEP_3_COUPLE_TRAILER, 
--          STEP_4_PARK_DOCK, STEP_5_ENTER_FORKLIFT, STEP_5_ENTER_HANDLER,
--          STEP_6_LOAD_PALLETS, STEP_6_LOAD_CONTAINER, STEP_6_GET_ROPES,
--          STEP_7_STRAP_PALLETS, STEP_8_IN_TRANSIT, STEP_9_DELIVERY

local JobEntities = {
    truck = nil,
    trailer = nil,
    forklift = nil,
    handler = nil,
    container = nil,
    pallets = {}
}
_G.JobEntities = JobEntities
_G.ActiveJob = ActiveJob

local ActiveDeliveryPoint = nil
local DockWatcherPoint = nil
local TrailerBayWatcherPoint = nil
local hasRopes = false
local HasRopes = false
local currentTieIndex = 1
local currentStrappingIndex = 1
local ActiveStrappingZoneId = nil
local DispatcherPed = nil
local LoadedPallets = {}
local LoadedPalletData = LoadedPallets
Config.LoadedPallets = LoadedPallets
_G.LoadedPallets = LoadedPallets
local ForkliftLoadedOnTrailer = false
local ForkliftSecured = false
local ForkliftRiskLevel = 0

-- =======================================================================
-- CÁLCULO DINÂMICO DE BOUNDING BOX (Z-AXIS CLAMP) PARA CARRETAS E FORKLIFT
-- Utiliza GetModelDimensions para obter o limite Z superior real da geometria
-- da prancha, eliminando paletes flutuando no ar ou afundando no metal.
-- =======================================================================
local function GetTrailerDeckZ(trailer)
    if not trailer or not DoesEntityExist(trailer) then return 0.35 end
    local model = GetEntityModel(trailer)
    if model == joaat('trflat') or model == joaat('freighttrailer') or model == joaat('armytrailer') or model == joaat('docktrailer') then
        return 0.35
    end
    local tMin, tMax = GetModelDimensions(model)
    if (tMax.z - tMin.z) > 2.5 then
        return tMin.z + 0.95
    end
    return 0.35
end
_G.GetTrailerDeckZ = GetTrailerDeckZ

local function GetForkliftDeckZ(trailer, forkEntity)
    return 0.35
end
_G.GetForkliftDeckZ = GetForkliftDeckZ

local function GetEntityRightVector(entity)
    if not entity or not DoesEntityExist(entity) then return vector3(1.0, 0.0, 0.0) end
    local origin = GetEntityCoords(entity)
    local rightPoint = GetOffsetFromEntityInWorldCoords(entity, 1.0, 0.0, 0.0)
    return rightPoint - origin
end
_G.GetEntityRightVector = GetEntityRightVector

-- =======================================================================
-- 5. SISTEMA DE NOTIFICAÇÃO ESTILO LATION COM EFEITO SONORO
-- =======================================================================

function SendMissionNotify(title, message, notifyType)
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)

    local sent = false
    if GetResourceState('lation_ui') == 'started' then
        pcall(function()
            if exports['lation_ui'] and exports['lation_ui'].notify then
                exports['lation_ui']:notify({
                    title = title,
                    message = message,
                    type = notifyType or 'info',
                    duration = 10000
                })
                sent = true
            elseif exports['lation_ui'] and exports['lation_ui'].Notify then
                exports['lation_ui']:Notify({
                    title = title,
                    message = message,
                    type = notifyType or 'info',
                    duration = 10000
                })
                sent = true
            end
        end)
    end

    if not sent then
        lib.notify({
            title = title,
            description = message,
            type = notifyType or 'info',
            duration = 10000,
            position = 'top-right'
        })
    end
end
_G.SendMissionNotify = SendMissionNotify

-- =======================================================================
-- GESTOR CENTRALIZADO DE OBJETIVOS E MARCADOR VISUAL (SETA VERDE FLUTUANTE)
-- =======================================================================

local CurrentObjectivePoint = nil
local CurrentObjectiveBlip = nil
local SecondaryObjectivePoint = nil
local SecondaryObjectiveBlip = nil

local function PurgeObjectiveMarkers(keepSecondary)
    -- 1. Desliga rota e remove blip principal
    if CurrentObjectivePoint then
        pcall(function() CurrentObjectivePoint:remove() end)
        CurrentObjectivePoint = nil
    end
    if CurrentObjectiveBlip and DoesBlipExist(CurrentObjectiveBlip) then
        pcall(function() SetBlipRoute(CurrentObjectiveBlip, false) end)
        RemoveBlip(CurrentObjectiveBlip)
        CurrentObjectiveBlip = nil
    end

    -- 2. Se não mantiver secundário, varre secundário e todas as entidades da missão
    if not keepSecondary then
        if SecondaryObjectivePoint then
            pcall(function() SecondaryObjectivePoint:remove() end)
            SecondaryObjectivePoint = nil
        end
        if SecondaryObjectiveBlip and DoesBlipExist(SecondaryObjectiveBlip) then
            pcall(function() SetBlipRoute(SecondaryObjectiveBlip, false) end)
            RemoveBlip(SecondaryObjectiveBlip)
            SecondaryObjectiveBlip = nil
        end

        -- Varredura Dupla: Remove qualquer blip órfão agarrado a entidades da missão no GTA V
        local entitiesToPurge = {
            JobEntities and JobEntities.truck,
            JobEntities and JobEntities.trailer,
            JobEntities and JobEntities.forklift,
            JobEntities and JobEntities.handler,
            JobEntities and JobEntities.container
        }
        if LoadedPallets then
            for _, p in ipairs(LoadedPallets) do
                if p and p.entity then
                    entitiesToPurge[#entitiesToPurge + 1] = p.entity
                end
            end
        end

        for i = 1, #entitiesToPurge do
            local ent = entitiesToPurge[i]
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                local entBlip = GetBlipFromEntity(ent)
                if entBlip and entBlip ~= 0 and DoesBlipExist(entBlip) then
                    pcall(function() SetBlipRoute(entBlip, false) end)
                    RemoveBlip(entBlip)
                end
            end
        end

        if TrailerBayWatcherPoint then
            pcall(function() TrailerBayWatcherPoint:remove() end)
            TrailerBayWatcherPoint = nil
        end
        if DockWatcherPoint then
            pcall(function() DockWatcherPoint:remove() end)
            DockWatcherPoint = nil
        end
        if Zones and Zones.ClearObjective then
            pcall(Zones.ClearObjective)
        end
    end
end

-- Trava Síncrona: Garante que os marcadores foram destruídos antes de avançar para a próxima etapa
local function PurgeObjectiveMarkersAndWait(keepSecondary)
    PurgeObjectiveMarkers(keepSecondary)
    local maxWait = 50
    while maxWait > 0 do
        local remaining = false
        if CurrentObjectiveBlip and DoesBlipExist(CurrentObjectiveBlip) then
            remaining = true
        end
        if not keepSecondary and SecondaryObjectiveBlip and DoesBlipExist(SecondaryObjectiveBlip) then
            remaining = true
        end
        if not remaining then break end
        Wait(10)
        maxWait = maxWait - 10
    end
end

local ClearObjectiveMarkers = PurgeObjectiveMarkers
_G.PurgeObjectiveMarkers = PurgeObjectiveMarkers
_G.PurgeObjectiveMarkersAndWait = PurgeObjectiveMarkersAndWait

function UpdateMissionObjective(objType, target, text, isSecondary)
    if not target then
        PurgeObjectiveMarkersAndWait(false)
        return
    end

    if not isSecondary then
        PurgeObjectiveMarkersAndWait(true)
    else
        if SecondaryObjectivePoint then
            pcall(function() SecondaryObjectivePoint:remove() end)
            SecondaryObjectivePoint = nil
        end
        if SecondaryObjectiveBlip and DoesBlipExist(SecondaryObjectiveBlip) then
            pcall(function() SetBlipRoute(SecondaryObjectiveBlip, false) end)
            RemoveBlip(SecondaryObjectiveBlip)
            SecondaryObjectiveBlip = nil
        end
    end

    local isEntity = false
    local targetEntity = nil
    local targetCoords = nil

    if type(target) == 'number' and DoesEntityExist(target) then
        isEntity = true
        targetEntity = target
        targetCoords = GetEntityCoords(target)
    elseif type(target) == 'vector3' or type(target) == 'vector4' or (type(target) == 'table' and target.x) then
        targetCoords = vector3(target.x, target.y, target.z)
    end

    if not targetCoords then return end

    -- Blindagem contra duplicação de blips na mesma entidade
    if isEntity and targetEntity and DoesEntityExist(targetEntity) then
        local prevEntBlip = GetBlipFromEntity(targetEntity)
        if prevEntBlip and prevEntBlip ~= 0 and DoesBlipExist(prevEntBlip) then
            pcall(function() SetBlipRoute(prevEntBlip, false) end)
            RemoveBlip(prevEntBlip)
        end
    end

    -- Alturas (Z) e configurações de Blip
    local offsetZ = 2.0
    local sprite = 477
    local hasRoute = false

    if objType == 'truck' then
        offsetZ = 2.8
        sprite = 477
        hasRoute = true
    elseif objType == 'trailer' then
        offsetZ = 2.8
        sprite = 479
        hasRoute = false
    elseif objType == 'dock' then
        offsetZ = 2.0
        sprite = 477
        hasRoute = true
    elseif objType == 'trailer_doors' or objType == 'trailer_rear' or objType == 'trailer_strap' then
        offsetZ = 1.5
        sprite = 479
        hasRoute = false
    elseif objType == 'forklift' then
        offsetZ = 2.0
        sprite = 543
        hasRoute = false
    elseif objType == 'forklift_dock' then
        offsetZ = 1.6
        sprite = 543
        hasRoute = false
    elseif objType == 'pallet' then
        offsetZ = 1.2
        sprite = 478
        hasRoute = false
    elseif objType == 'delivery' then
        offsetZ = 2.5
        sprite = 477
        hasRoute = true
    end

    -- Criação do Blip
    local blip = nil
    if isEntity then
        blip = AddBlipForEntity(targetEntity)
    else
        blip = AddBlipForCoord(targetCoords.x, targetCoords.y, targetCoords.z)
    end

    if blip and DoesBlipExist(blip) then
        SetBlipSprite(blip, sprite)
        SetBlipColour(blip, (objType == 'delivery') and 5 or 2)
        SetBlipScale(blip, 0.85)
        if hasRoute then
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, (objType == 'delivery') and 5 or 2)
        end
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(text or "Objetivo de Carga")
        EndTextCommandSetBlipName(blip)
    end

    -- Marcador visual tipo 20 (Chevron / seta apontando para baixo) via ox_lib.points
    -- Escala e elevação Z dimensionadas dinamicamente com base no Bounding Box real do prop/entidade
    local markerScale = 0.6
    local dynamicOffsetZ = offsetZ

    if isEntity and targetEntity and DoesEntityExist(targetEntity) then
        local model = GetEntityModel(targetEntity)
        local minDim, maxDim = GetModelDimensions(model)
        local dimX = math.abs(maxDim.x - minDim.x)
        local dimY = math.abs(maxDim.y - minDim.y)
        local maxHoriz = math.max(dimX, dimY)

        -- Escala proporcional ao tamanho do prop: paletes ~0.55-0.65, empilhadeira ~1.0, contêiner/caminhão ~1.6-1.8
        markerScale = math.min(1.8, math.max(0.45, maxHoriz * 0.35))
        -- Posiciona a seta precisamente flutuando acima do topo do objeto
        dynamicOffsetZ = maxDim.z + (markerScale * 0.45) + 0.2
    end

    local point = lib.points.new({
        coords = targetCoords,
        distance = 150.0,
        nearby = function(self)
            local pos = self.coords
            if isEntity and targetEntity and DoesEntityExist(targetEntity) then
                pos = GetEntityCoords(targetEntity)
                self.coords = pos
            end

            local isVehicleObjective = (
                objType == 'truck'
                or objType == 'trailer'
                or objType == 'forklift'
                or objType == 'handler'
                or objType == 'trailer_rear'
                or objType == 'trailer_doors'
                or objType == 'trailer_strap'
                or objType == 'forklift_dock'
            )

            if objType ~= 'dock' and objType ~= 'delivery' and not isVehicleObjective then
                DrawMarker(
                    20,
                    pos.x, pos.y, pos.z + dynamicOffsetZ,
                    0.0, 0.0, 0.0,
                    180.0, 0.0, 0.0,
                    markerScale, markerScale, markerScale,
                    0, 255, 0, 180,
                    true,  -- bobs
                    false, -- faceCamera
                    2,
                    true,  -- rotate
                    nil, nil, false
                )
            end
        end
    })

    if isSecondary then
        SecondaryObjectivePoint = point
        SecondaryObjectiveBlip = blip
    else
        CurrentObjectivePoint = point
        CurrentObjectiveBlip = blip
    end
end
_G.UpdateMissionObjective = UpdateMissionObjective

-- =======================================================================
-- HELPERS DE LIMPEZA E ESTADO
-- =======================================================================

local function CleanupCurrentJob()
    ClearObjectiveMarkers(false)
    SendNUIMessage({ action = 'gmeter_hide' })
    pcall(lib.hideTextUI)

    if ForkliftModule and ForkliftModule.StopOperation then
        ForkliftModule.StopOperation()
    end
    if ReachStackerModule and ReachStackerModule.StopOperation then
        ReachStackerModule.StopOperation()
    end
    if AdrHazardModule and AdrHazardModule.StopMonitoring then
        AdrHazardModule.StopMonitoring()
    end
    if ActiveDeliveryPoint then
        pcall(function() ActiveDeliveryPoint:remove() end)
        ActiveDeliveryPoint = nil
    end
    if DockWatcherPoint then
        pcall(function() DockWatcherPoint:remove() end)
        DockWatcherPoint = nil
    end
    if TrailerBayWatcherPoint then
        pcall(function() TrailerBayWatcherPoint:remove() end)
        TrailerBayWatcherPoint = nil
    end
    if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
        pcall(function() exports.ox_target:removeLocalEntity(JobEntities.truck) end)
    end
    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
        pcall(function() exports.ox_target:removeLocalEntity(JobEntities.trailer) end)
    end
    if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
        pcall(function() exports.ox_target:removeLocalEntity(JobEntities.forklift) end)
    end
    if JobEntities.handler and DoesEntityExist(JobEntities.handler) then
        pcall(function() exports.ox_target:removeLocalEntity(JobEntities.handler) end)
    end

    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    if LoadedPallets then
        for idx, pData in ipairs(LoadedPallets) do
            if pData.strapEntities then
                for _, sEnt in ipairs(pData.strapEntities) do
                    if DoesEntityExist(sEnt) then
                        if IsEntityAttached(sEnt) then
                            DetachEntity(sEnt, false, false)
                        end
                        SetEntityAsMissionEntity(sEnt, true, true)
                        DeleteObject(sEnt)
                        DeleteEntity(sEnt)
                    end
                end
                pData.strapEntities = nil
            end
            if pData.strapEntity and DoesEntityExist(pData.strapEntity) then
                if IsEntityAttached(pData.strapEntity) then
                    DetachEntity(pData.strapEntity, false, false)
                end
                SetEntityAsMissionEntity(pData.strapEntity, true, true)
                DeleteObject(pData.strapEntity)
                DeleteEntity(pData.strapEntity)
                pData.strapEntity = nil
            end
            if pData.entity and DoesEntityExist(pData.entity) then
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity, 'aust_tie_current_pallet') end)
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity, 'tie_pallet_' .. idx) end)
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity) end)
                SetEntityCollision(pData.entity, true, true)
            end
        end
    end

    if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
        FreezeEntityPosition(JobEntities.truck, false)
        SetVehicleHandbrake(JobEntities.truck, false)
    end
    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
        FreezeEntityPosition(JobEntities.trailer, false)
        SetVehicleHandbrake(JobEntities.trailer, false)
    end

    ActiveJob = nil
    CurrentStage = 'IDLE'
    hasRopes = false
    HasRopes = false
    ForkliftLoadedOnTrailer = false
    ForkliftSecured = false
    ForkliftRiskLevel = 0
    currentTieIndex = 1
    currentStrappingIndex = 1
    LoadedPallets = {}
    LoadedPalletData = LoadedPallets
    Config.LoadedPallets = LoadedPallets
    JobEntities = { truck = nil, trailer = nil, forklift = nil, handler = nil, container = nil, pallets = {} }
    SetWaypointOff()
end

local function GetNextAvailablePallet()
    if not JobEntities.pallets then return nil end
    for _, p in ipairs(JobEntities.pallets) do
        if p and DoesEntityExist(p) and not IsEntityAttached(p) then
            return p
        end
    end
    return nil
end

local function WaitForNetworkEntity(netId, maxTimeoutMs)
    if not netId or netId == 0 or type(netId) ~= 'number' then return nil end
    local timeout = GetGameTimer() + (maxTimeoutMs or 6000)

    while GetGameTimer() < timeout do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                return ent
            end
        end
        Wait(50)
    end

    if NetworkDoesEntityExistWithNetworkId(netId) then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            return ent
        end
    end
    return nil
end


-- =======================================================================
-- DESPACHANTE NPC: ACESSO EXCLUSIVO VIA TABLET NUI (ZERO COMANDOS OBSOLETOS)
-- =======================================================================

CreateThread(function()
    while not Config or not Config.Polarix or not Config.Polarix.Warehouse do Wait(100) end
    local wh = Config.Polarix.Warehouse
    local pedHash = joaat(wh.YardManagerPed or 's_m_m_dockwork_01')
    lib.requestModel(pedHash)

    DispatcherPed = CreatePed(4, pedHash, wh.Dispatcher.x, wh.Dispatcher.y, wh.Dispatcher.z - 1.0, wh.Dispatcher.w, false, true)
    FreezeEntityPosition(DispatcherPed, true)
    SetEntityInvincible(DispatcherPed, true)
    SetBlockingOfNonTemporaryEvents(DispatcherPed, true)
    SetPedCanRagdoll(DispatcherPed, false)

    exports.ox_target:addLocalEntity(DispatcherPed, {
        {
            name = 'aust_open_trucker_tablet',
            icon = 'fa-solid fa-tablet-screen-button',
            label = 'Acessar Central de Cargas (Tablet)',
            distance = 2.5,
            onSelect = function()
                TriggerEvent('truck_logistics:openJobBoard')
            end
        },
        {
            name = 'aust_emergency_respawn_gear',
            icon = 'fa-solid fa-wrench',
            label = 'Repor Equipamento do Pátio',
            distance = 2.5,
            canInteract = function()
                return ActiveJob ~= nil and (CurrentStage ~= 'IDLE' and CurrentStage ~= 'STEP_8_IN_TRANSIT' and CurrentStage ~= 'STEP_9_DELIVERY')
            end,
            onSelect = function()
                if ActiveJob then
                    TriggerServerEvent('aurp_trucker:server:emergencyRespawnEquipment', ActiveJob.jobId)
                end
            end
        }
    })
end)

-- =======================================================================
-- CALLBACKS NUI: INICIAR ENTREGA (START DELIVERY)
-- =======================================================================

local isStartingDeliveryLock = false

local function HandleStartDeliveryNUI(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', hidemenu = true })
    SendNUIMessage({ action = 'closeUI' })
    SendNUIMessage({ action = 'hide' })

    local ped = cache.ped or PlayerPedId()
    SetEntityVisible(ped, true)
    ResetEntityAlpha(ped)

    if isStartingDeliveryLock then
        if cb then cb({ ok = false, message = 'Aguarde o processamento anterior...' }) end
        return
    end

    local raw = data or {}
    local payload = (raw.data and type(raw.data) == 'table') and raw.data or raw
    local contractId = payload.id or payload.contract_id or payload.contractId or payload.jobId
    if Config.Debug then print(("^2[AUST_Trucker DEBUG - ETAPA 1] HandleStartDeliveryNUI disparado! ID=%s^7"):format(tostring(contractId))) end

    if ActiveJob then
        SendMissionNotify('Central Logística', 'Você já possui uma rota ou entrega em andamento!', 'error')
        if cb then cb({ ok = false, message = 'Já em serviço' }) end
        return
    end

    isStartingDeliveryLock = true
    SetTimeout(4000, function() isStartingDeliveryLock = false end)

    TriggerServerEvent('aurp_trucker:server:startDelivery', payload)

    if cb then cb('ok') end
end

RegisterNUICallback('startDelivery', HandleStartDeliveryNUI)
RegisterNUICallback('acceptJob', HandleStartDeliveryNUI)
RegisterNUICallback('startJob', HandleStartDeliveryNUI)
RegisterNUICallback('startContract', HandleStartDeliveryNUI)
RegisterNUICallback('confirmJob', HandleStartDeliveryNUI)

local function HandleCloseMenuNUI(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', hidemenu = true })
    SendNUIMessage({ action = 'closeUI' })
    SendNUIMessage({ action = 'hide' })
    if cb then cb('ok') end
end

RegisterNUICallback('closeMenu', HandleCloseMenuNUI)
RegisterNUICallback('closeModal', HandleCloseMenuNUI)
RegisterNUICallback('cancelJob', HandleCloseMenuNUI)
RegisterNUICallback('focusMenu', function(data, cb)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    if cb then cb('ok') end
end)

-- =======================================================================
-- ETAPA 3 & 4: ACOPLAMENTO DA CARRETA E POSICIONAMENTO NA BAÍA
-- =======================================================================

local function StartCouplingWatcher()
    CreateThread(function()
        while CurrentStage == 'STEP_3_COUPLE_TRAILER' do
            local sleep = 250
            if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
                local hasTrailer, trailerEnt = GetVehicleTrailerVehicle(JobEntities.truck)
                if not hasTrailer or trailerEnt == 0 then
                    hasTrailer = IsVehicleAttachedToTrailer(JobEntities.truck)
                end

                -- Assistência Inteligente de Acoplamento da 5ª Roda (Smart Hitch Assist)
                -- Resolve a limitação de geometria física do GTA V para freighttrailer e outros reboques
                if not hasTrailer and JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                    local truckCoords = GetEntityCoords(JobEntities.truck)
                    local trailerCoords = GetEntityCoords(JobEntities.trailer)
                    local dist = #(truckCoords - trailerCoords)

                    if dist <= 15.0 then
                        sleep = 20 -- Frequência ágil em aproximação para evitar atraso de frame e puxões

                        -- Libera ativamente os freios do reboque na aproximação para permitir a articulação do acoplamento
                        SetVehicleHandbrake(JobEntities.trailer, false)
                        SetVehicleBrake(JobEntities.trailer, false)

                        -- Ponto da 5ª roda do caminhão (traseira)
                        local truckBone = GetEntityBoneIndexByName(JobEntities.truck, "attach_female")
                        local fifthWheelPos = (truckBone ~= -1) and GetWorldPositionOfEntityBone(JobEntities.truck, truckBone)
                        if not fifthWheelPos then
                            local tMin, _ = GetModelDimensions(GetEntityModel(JobEntities.truck))
                            local hitchY = (tMin.y < 0) and (tMin.y + 1.2) or -2.4
                            fifthWheelPos = GetOffsetFromEntityInWorldCoords(JobEntities.truck, 0.0, hitchY, 0.45)
                        end

                        -- Ponto do pino rei da carreta (dianteira precisa com tratamento dedicado para freighttrailer)
                        local trModel = GetEntityModel(JobEntities.trailer)
                        local isFreight = (trModel == joaat('freighttrailer'))
                        local trailerBone = GetEntityBoneIndexByName(JobEntities.trailer, "attach_male")
                        local kingpinPos = (trailerBone ~= -1) and GetWorldPositionOfEntityBone(JobEntities.trailer, trailerBone)
                        if not kingpinPos then
                            if isFreight then
                                kingpinPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, 5.2, 0.35)
                            else
                                local _, maxDim = GetModelDimensions(trModel)
                                local kingpinY = (maxDim.y > 0) and (maxDim.y - 1.2) or 3.5
                                kingpinPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, kingpinY, 0.2)
                            end
                        end

                        local hitchDist2D = #(vector2(fifthWheelPos.x, fifthWheelPos.y) - vector2(kingpinPos.x, kingpinPos.y))
                        local hitchDiffZ = math.abs(fifthWheelPos.z - kingpinPos.z)

                        -- Tolerâncias ampliadas: 2.0m XY e 1.0m Z para freighttrailer, com raio de busca nativo de 7.5m
                        local maxDistXY = isFreight and 2.0 or 1.5
                        local maxDeltaZ = isFreight and 1.0 or 0.8
                        local attachRadius = isFreight and 7.5 or 3.5

                        if hitchDist2D <= maxDistXY and hitchDiffZ <= maxDeltaZ then
                            -- Solicita controle autoritativo de rede local para evitar descompasso OneSync
                            if not NetworkHasControlOfEntity(JobEntities.trailer) then
                                NetworkRequestControlOfEntity(JobEntities.trailer)
                            end

                            -- Amortece velocidades relativas e libera freios da carreta
                            SetVehicleHandbrake(JobEntities.trailer, false)
                            SetVehicleBrake(JobEntities.trailer, false)
                            SetEntityVelocity(JobEntities.trailer, 0.0, 0.0, 0.0)

                            -- Engate suave com raio configurado eliminando snaps e garantindo acoplamento físico
                            AttachVehicleToTrailer(JobEntities.truck, JobEntities.trailer, attachRadius)
                            Wait(25)

                            hasTrailer, trailerEnt = GetVehicleTrailerVehicle(JobEntities.truck)
                            if not hasTrailer or trailerEnt == 0 then
                                hasTrailer = IsVehicleAttachedToTrailer(JobEntities.truck)
                            end

                            if hasTrailer then
                                PlaySoundFrontend(-1, "PIN_BUTTON", "ATM_SOUNDS", true)
                                SendMissionNotify('Central Logística', 'Carreta engatada na 5ª roda com sucesso!', 'success')
                            end
                        end
                    end
                end

                if hasTrailer then
                    -- Garante freios liberados para tráfego imediato
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        SetVehicleHandbrake(JobEntities.trailer, false)
                        SetVehicleBrake(JobEntities.trailer, false)
                    end

                    -- DESTRUIÇÃO INSTANTÂNEA SINCRONIZADA (Milissegundo Zero)
                    PurgeObjectiveMarkersAndWait(false)

                    local isContainerLoaded = false
                    if ActiveJob and ActiveJob.cargoType == 'heavy' then
                        if JobEntities.container and DoesEntityExist(JobEntities.container) and JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                            isContainerLoaded = IsEntityAttachedToEntity(JobEntities.container, JobEntities.trailer)
                        end
                    end

                    if isContainerLoaded then
                        CurrentStage = 'STEP_8_IN_TRANSIT'
                        SendMissionNotify('Central Logística', 'Carreta engatada com o contêiner carregado! Inicie o trajeto até o destino.', 'success')
                        if ActiveJob.deliveryCoords then
                            StartDeliveryRoute(ActiveJob.deliveryCoords, ActiveJob.jobId)
                        end
                        break
                    end

                    -- ETAPA 3 CONCLUÍDA -> TRANSIÇÃO AUTORITATIVA PARA A BAIA DE CARREGAMENTO DA PASTA
                    CurrentStage = 'STEP_4_PARK_DOCK'
                    local allocatedBay = nil
                    local reqJobId = ActiveJob and ActiveJob.jobId

                    -- Tenta obter baia livre da pasta selecionada (ou via servidor)
                    local function AcquireBayAndStartDock()
                        if ActiveJob and ActiveJob.loadBayCoords then
                            allocatedBay = ActiveJob.loadBayCoords
                        else
                            local res = lib.callback.await('aurp_trucker:server:requestLoadingBay', false, reqJobId)
                            if res and res.success and res.coords then
                                allocatedBay = res.coords
                            else
                                allocatedBay = (Config.LoadingBays and Config.LoadingBays[1]) or vector4(1244.02, -3135.68, 4.53, 90.0)
                            end
                        end

                        local dockCoords = vector3(allocatedBay.x, allocatedBay.y, allocatedBay.z)
                        local dockHeading = (type(allocatedBay) == 'vector4' and allocatedBay.w) or 90.0

                        -- Atualiza objetivo e rota GPS para a baía demarcada da pasta
                        UpdateMissionObjective('dock', dockCoords, 'Baía de Carregamento')
                        SendMissionNotify('Central Logística', 'Carreta engatada na 5ª roda! Leve o conjunto e estacione de ré na baía de carregamento indicada.', 'info')

                        if DockWatcherPoint then pcall(function() DockWatcherPoint:remove() end) end
                        local currentDockTextUi = nil

                        -- Parâmetros Equilibrados de Tolerância (Suave e Agradável)
                        local MAX_DOCK_DIST = (Config.Docking and Config.Docking.MaxDistance) or 2.2
                        local MAX_HEADING_ERR = (Config.Docking and Config.Docking.MaxHeadingError) or 14.0

                        DockWatcherPoint = lib.points.new({
                            coords = dockCoords,
                            distance = 250.0,
                            onExit = function()
                                if currentDockTextUi then
                                    lib.hideTextUI()
                                    currentDockTextUi = nil
                                end
                            end,
                            nearby = function(self)
                                if CurrentStage ~= 'STEP_4_PARK_DOCK' then return end
                                local ped = cache.ped or PlayerPedId()
                                local veh = cache.vehicle or GetVehiclePedIsIn(ped, false)
                                local tk = JobEntities.truck
                                local tr = JobEntities.trailer

                                local refEntity = (veh ~= 0) and veh or (tk and DoesEntityExist(tk) and tk) or ped
                                local trOrVeh = (tr and DoesEntityExist(tr)) and tr or refEntity

                                -- Validação Baseada na Carreta / Conjunto sobre a Vaga Demarcada
                                local trCoords = (tr and DoesEntityExist(tr)) and GetEntityCoords(tr) or GetEntityCoords(refEntity)
                                local distDock = #(vector3(trCoords.x, trCoords.y, trCoords.z) - dockCoords)

                                local markerZ = dockCoords.z - 0.45
                                local foundGround, groundZ = GetGroundZFor_3dCoord(dockCoords.x, dockCoords.y, dockCoords.z + 2.0, false)
                                if foundGround and groundZ > 0.0 then
                                    markerZ = groundZ + 0.05
                                end

                                -- Validação de Heading do Conjunto (Alinhamento com a baía)
                                local trH = (tr and DoesEntityExist(tr)) and GetEntityHeading(tr) or ((veh ~= 0) and GetEntityHeading(veh) or GetEntityHeading(ped))
                                local trDiff = math.abs((trH - dockHeading + 180) % 360 - 180)
                                local headingError = math.min(trDiff, math.abs(trDiff - 180.0))

                                local isAligned = (veh ~= 0) and (headingError <= 25.0)
                                local isDocked = (distDock <= 4.8) and isAligned

                                if isDocked then
                                    -- Vaga Verde Alinhada Rigorosa (Padrão LC Truck Logistics)
                                    DrawMarker(30, dockCoords.x, dockCoords.y, markerZ, 0.0, 0.0, 0.0, 90.0, dockHeading, 0.0, 3.0, 1.0, 10.0, 0, 255, 0, 50, 0, 0, 0, 0)
                                    if currentDockTextUi ~= 'park' then
                                        lib.showTextUI('[E] Estacionar Carreta na Baía')
                                        currentDockTextUi = 'park'
                                    end

                                    local speed = (veh ~= 0) and GetEntitySpeed(veh) or 0.0
                                    if IsControlJustPressed(0, 38) or (speed < 0.35 and distDock <= 3.2) then
                                        if currentDockTextUi then
                                            lib.hideTextUI()
                                            currentDockTextUi = nil
                                        end
                                        self:remove()
                                        DockWatcherPoint = nil
                                        PurgeObjectiveMarkersAndWait(false)

                                        -- Libera a baia ocupada no servidor
                                        if reqJobId then
                                            TriggerServerEvent('aurp_trucker:server:releaseLoadingBay', reqJobId)
                                        end
                                        -- Congela fisicamente o conjunto na baía para estabilidade do carregamento
                                        if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
                                            FreezeEntityPosition(JobEntities.truck, true)
                                        end
                                        if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                                            FreezeEntityPosition(JobEntities.trailer, true)
                                        end

                                        -- ETAPA 4 CONCLUÍDA -> TRANSIÇÃO DIRETA COM BASE NO TIPO DE CARGA
                                        if ActiveJob and ActiveJob.cargoType == 'heavy' then
                                            CurrentStage = 'STEP_5_ENTER_HANDLER'
                                            if JobEntities.handler and DoesEntityExist(JobEntities.handler) then
                                                UpdateMissionObjective('forklift', JobEntities.handler, 'Reach Stacker (Handler)')
                                            end
                                            SendMissionNotify('Central Logística', 'Caminhão posicionado! Assuma o Reach Stacker para içar o contêiner.', 'info')
                                        elseif ActiveJob and (ActiveJob.cargoType == 'liquid' or ActiveJob.cargoType == 'adr') then
                                            CurrentStage = 'STEP_5_FUEL_LOADING'
                                            SendMissionNotify('Central Logística', 'Caminhão posicionado na baía! Conecte a mangueira para o carregamento.', 'info')
                                        elseif ActiveJob and ActiveJob.cargoType == 'vehicle_carrier' then
                                            CurrentStage = 'STEP_5_LOAD_CARS'
                                            SendMissionNotify('Central Logística', 'Caminhão posicionado! Aproxime-se da cegonha com uma chave de boca para abrir a rampa e embarcar os carros.', 'info')
                                            if CarCarrierModule and CarCarrierModule.StartLoadingOperation then
                                                CarCarrierModule.StartLoadingOperation(ActiveJob.jobId, JobEntities.trailer, ActiveJob.vehicleNetIds or {}, function(action, loaded, total)
                                                    if action == 'completed' then
                                                        SendMissionNotify('Central Logística', 'Cegonha 100% carregada e travada! Entre no caminhão e inicie a rota rodoviária.', 'success')
                                                        UpdateMissionObjective('truck', JobEntities.truck, 'Seu Caminhão')
                                                        if ActiveJob.deliveryCoords then
                                                            StartDeliveryRoute(ActiveJob.deliveryCoords, ActiveJob.jobId)
                                                        end
                                                    end
                                                end)
                                            end
                                        else
                                            CurrentStage = 'STEP_5_ENTER_FORKLIFT'
                                            if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
                                                UpdateMissionObjective('forklift', JobEntities.forklift, 'Empilhadeira de Carregamento')
                                            end
                                            SendMissionNotify('Central Logística', 'Caminhão posicionado na baía! Assuma a empilhadeira para iniciar o carregamento.', 'info')
                                        end
                                    end
                                else
                                    -- Vaga Vermelha Não-Alinhada / Em Aproximação (Permanece Vermelho se torto ou afastado)
                                    DrawMarker(30, dockCoords.x, dockCoords.y, markerZ, 0.0, 0.0, 0.0, 90.0, dockHeading, 0.0, 3.0, 1.0, 10.0, 255, 0, 0, 50, 0, 0, 0, 0)
                                    if distDock <= 25.0 and veh ~= 0 then
                                        local hintText = isAligned and ('Aproxime a carreta da baía (%.1fm)'):format(distDock) or 'Alinhe a traseira do reboque perpendicular à porta'
                                        if currentDockTextUi ~= hintText then
                                            lib.showTextUI(hintText)
                                            currentDockTextUi = hintText
                                        end
                                    else
                                        if currentDockTextUi then
                                            lib.hideTextUI()
                                            currentDockTextUi = nil
                                        end
                                    end
                                end
                            end
                        })
                    end

                    AcquireBayAndStartDock()
                    break
                end
            end
            Wait(sleep)
        end
    end)
end

-- =======================================================================
-- ETAPA 6 & 7: SISTEMA DE CORDAS E AMARRAÇÃO INDIVIDUAL (PALETE A PALETE)
-- =======================================================================

local StartDeliveryRoute = nil

local function CheckAllTiedAndStartRoute()
    local palletList = LoadedPallets or LoadedPalletData or {}
    local totalRequired = #palletList
    local tiedCount = 0

    for _, pData in ipairs(palletList) do
        if pData.isSecured then
            tiedCount = tiedCount + 1
        end
    end

    local forkliftReady = true
    if ActiveJob and ActiveJob.withForklift then
        forkliftReady = ForkliftSecured
    end

    if (totalRequired == 0 or tiedCount >= totalRequired) and forkliftReady then
        hasRopes = false
        HasRopes = false
        ClearObjectiveMarkers(false)

        if ActiveStrappingZoneId then
            pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
            ActiveStrappingZoneId = nil
        end

        -- DESCONGELAMENTO FÍSICO DO CONJUNTO (CAMINHÃO E CARRETA) PARA A VIAGEM
        if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
            FreezeEntityPosition(JobEntities.truck, false)
            SetVehicleHandbrake(JobEntities.truck, false)
        end
        if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
            FreezeEntityPosition(JobEntities.trailer, false)
            SetVehicleHandbrake(JobEntities.trailer, false)
        end

        SendMissionNotify('Central Logística', 'Carga 100% amarrada e fixada! Entre no caminhão e inicie a rota rodoviária.', 'success')

        local dest = (ActiveJob and ActiveJob.deliveryCoords) or (Config.DeliveryCoords)
        if StartDeliveryRoute then
            StartDeliveryRoute(dest, ActiveJob and ActiveJob.jobId)
        end
        TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob and ActiveJob.jobId)
        return true
    end
    return false
end

local function ExecutePalletTie(index)
    local palletData = LoadedPallets[index]
    if not palletData then return end

    -- Destrói a zona ativa imediatamente para evitar múltiplos cliques ou disparos simultâneos
    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    local palletEnt = palletData.entity
    local trailer = JobEntities.trailer

    -- BLINDAGEM ESTRITA: Garantir que o trailer seja o reboque do contrato e não a empilhadeira
    if JobEntities.forklift and (palletEnt == JobEntities.forklift or trailer == JobEntities.forklift) then
        if Config.Debug then print("[AUST_Trucker] ERRO: Tentativa de amarrar empilhadeira no fluxo de paletes!") end
        return
    end

    -- SINCRONIZAÇÃO ABSOLUTA: Palete físico herda a coordenada exata do slot calibrado no banco/fantasma
    if palletEnt and DoesEntityExist(palletEnt) and trailer and DoesEntityExist(trailer) then
        local slotIdx = palletData.slotIndex or index
        local finalOffset = palletData.relOffset
        local finalHeading = palletData.relHeading or 0.0

        if not finalOffset then
            local off, h = ForkliftModule.GetSlotOffset and ForkliftModule.GetSlotOffset(trailer, slotIdx)
            if off then
                finalOffset = off
                finalHeading = h or (type(off) == 'table' and off.heading) or 0.0
            else
                local pCoords = GetEntityCoords(palletEnt)
                local rawOffset = GetOffsetFromEntityGivenWorldCoords(trailer, pCoords.x, pCoords.y, pCoords.z)
                local deckZ = GetTrailerDeckZ(trailer)
                finalOffset = vector3(rawOffset.x, rawOffset.y, deckZ + 0.01)
                finalHeading = 0.0
            end
        else
            if finalHeading == 0.0 and type(finalOffset) == 'table' and finalOffset.heading then
                finalHeading = finalOffset.heading
            end
        end

        palletData.relOffset = finalOffset
        palletData.relHeading = finalHeading

        -- Garante controle autoritativo de rede antes da amarração
        if NetworkGetEntityIsNetworked(palletEnt) and not NetworkHasControlOfEntity(palletEnt) then
            NetworkRequestControlOfEntity(palletEnt)
            local t = 300
            while not NetworkHasControlOfEntity(palletEnt) and t > 0 do
                Wait(30)
                t = t - 30
            end
        end

        local pNet = NetworkGetEntityIsNetworked(palletEnt) and NetworkGetNetworkIdFromEntity(palletEnt) or nil
        if pNet then
            SetNetworkIdCanMigrate(pNet, false)
        end

        -- BLINDAGEM RÍGIDA ONESYNC:
        -- Ancoragem padronizada no Bone 0 (Root) sem soft-pinning (elimina atraso elástico / rubberbanding)
        FreezeEntityPosition(palletEnt, false)
        SetEntityDynamic(palletEnt, false)
        SetEntityHasGravity(palletEnt, false)
        SetEntityVelocity(palletEnt, 0.0, 0.0, 0.0)
        AttachEntityToEntity(
            palletEnt, trailer, 0,
            finalOffset.x, finalOffset.y, finalOffset.z,
            0.0, 0.0, finalHeading,
            false, false, false, false, 2, true
        )

        -- 2. Isolamento rigoroso: Mantém colisão com o jogador ativa, anulando colisão contra trailer/truck
        SetEntityCollision(palletEnt, true, true)
        SetCanClimbOnEntity(palletEnt, true)
        SetEntityNoCollisionEntity(palletEnt, trailer, false)
        SetEntityNoCollisionEntity(trailer, palletEnt, false)
        local tk = JobEntities.truck
        if tk and DoesEntityExist(tk) then
            SetEntityNoCollisionEntity(palletEnt, tk, false)
            SetEntityNoCollisionEntity(tk, palletEnt, false)
        end
        -- Damping do Ped durante amarração para evitar loop de mola física (Trailer <-> Ped <-> Palete)
        local ped = cache.ped or PlayerPedId()
        SetEntityNoCollisionEntity(palletEnt, ped, true)

        -- Sincronização OneSync via Entity StateBags (Pilar 1)
        if trailer and DoesEntityExist(trailer) and NetworkGetEntityIsNetworked(trailer) and NetworkGetEntityIsNetworked(palletEnt) then
            local pNet = NetworkGetNetworkIdFromEntity(palletEnt)
            local curSlots = Entity(trailer).state.loadedSlots or {}
            local slotKey = tostring(palletData.slotIndex or 1)
            curSlots[slotKey] = {
                palletNet = pNet,
                offset = { x = finalOffset.x, y = finalOffset.y, z = finalOffset.z },
                heading = finalHeading
            }
            Entity(trailer).state:set('loadedSlots', curSlots, true)
        end
    end

    -- Minigame de perícia
    local success = lib.skillCheck({'easy', 'medium', 'medium'}, {'w', 'a', 's', 'd'})

    lib.progressBar({
        duration = 2500,
        label = 'Ajustando cinta de carga...',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            clip = 'machinic_loop_meano',
            flag = 49
        }
    })

    if success then
        palletData.isSecured = true
        palletData.riskLevel = 0

        -- SPAWN & ATTACH DA CINTA CATRACA CUSTOMIZADA (prop_ratchet_strap)
        if palletEnt and DoesEntityExist(palletEnt) then
            if palletData.strapEntities then
                for _, sEnt in ipairs(palletData.strapEntities) do
                    if DoesEntityExist(sEnt) then
                        if IsEntityAttached(sEnt) then DetachEntity(sEnt, false, false) end
                        DeleteEntity(sEnt)
                    end
                end
            end
            palletData.strapEntities = {}

            if palletData.strapEntity and DoesEntityExist(palletData.strapEntity) then
                if IsEntityAttached(palletData.strapEntity) then
                    DetachEntity(palletData.strapEntity, false, false)
                end
                DeleteEntity(palletData.strapEntity)
                palletData.strapEntity = nil
            end

            local strapModel = joaat('prop_ratchet_strap')
            RequestModel(strapModel)
            local timeout = 100
            while not HasModelLoaded(strapModel) and timeout > 0 do
                Wait(10)
                timeout = timeout - 1
            end

            if HasModelLoaded(strapModel) then
                -- Busca configurações de cinta calibradas no banco para este slot/trailer
                local slotIdx = palletData.slotIndex or index
                local offData, _ = ForkliftModule.GetSlotOffset and ForkliftModule.GetSlotOffset(trailer, slotIdx)
                local configuredStraps = (palletData.straps) or (offData and offData.straps)

                if configuredStraps and type(configuredStraps) == 'table' and #configuredStraps > 0 then
                    -- Aplica as cintas 6DoF exatas calibradas pelo admin vinculadas ao trailer
                    for _, sData in ipairs(configuredStraps) do
                        local sX = tonumber(sData.x) or 0.0
                        local sY = tonumber(sData.y) or 0.0
                        local sZ = tonumber(sData.z) or 0.0
                        local sRx = tonumber(sData.rx) or 0.0
                        local sRy = tonumber(sData.ry) or 0.0
                        local sRz = tonumber(sData.rz or sData.heading) or 0.0

                        local tCoords = GetEntityCoords(trailer)
                        local strapObj = CreateObject(strapModel, tCoords.x, tCoords.y, tCoords.z, true, true, false)
                        if DoesEntityExist(strapObj) then
                            SetEntityAsMissionEntity(strapObj, true, true)
                            SetEntityCollision(strapObj, false, false)
                            SetEntityInvincible(strapObj, true)
                            AttachEntityToEntity(
                                strapObj, trailer, 0,
                                sX, sY, sZ,
                                sRx, sRy, sRz,
                                false, false, false, false, 2, true
                            )
                            table.insert(palletData.strapEntities, strapObj)
                            table.insert(JobEntities.pallets, strapObj)
                            if not palletData.strapEntity then
                                palletData.strapEntity = strapObj
                            end
                        end
                    end
                else
                    -- Fallback padrão suave: cinta centralizada diretamente sobre o palete
                    local pCoords = GetEntityCoords(palletEnt)
                    local strapObj = CreateObject(strapModel, pCoords.x, pCoords.y, pCoords.z, true, true, false)
                    if DoesEntityExist(strapObj) then
                        SetEntityAsMissionEntity(strapObj, true, true)
                        SetEntityCollision(strapObj, false, false)
                        SetEntityInvincible(strapObj, true)
                        AttachEntityToEntity(
                            strapObj, palletEnt, 0,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            false, false, false, false, 2, true
                        )
                        palletData.strapEntity = strapObj
                        table.insert(palletData.strapEntities, strapObj)
                        table.insert(JobEntities.pallets, strapObj)
                    end
                end
                SetModelAsNoLongerNeeded(strapModel)
            end
        end

        PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
        SendMissionNotify('Central Logística', 'Palete amarrado com firmeza total.', 'success')

        -- Avança para o próximo da lista e avalia condição de avanço sem deadlock
        currentTieIndex = currentTieIndex + 1
        if not CheckAllTiedAndStartRoute() then
            SetupNextPalletTarget()
        end
    else
        palletData.isSecured = false
        palletData.riskLevel = 'high'
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
        SendMissionNotify('Atenção', 'A amarração falhou! Tente amarrar novamente.', 'error')
        SetupNextPalletTarget()
    end
end

-- CORREÇÃO 2: REVISÃO DO GATILHO DA EMPILHADEIRA (FORKLIFT TIE-DOWN)
-- Removemos verificações rígidas de toque físico (IsEntityTouchingEntity quebrada por suspensões).
-- Valida proximidade (< 15.0m) e aplica AttachEntityToEntity na extremidade traseira do trailer.
local function ExecuteForkliftTie(forkEntity)
    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    local fork = forkEntity or JobEntities.forklift
    local trailer = JobEntities.trailer

    if not fork or not DoesEntityExist(fork) or not trailer or not DoesEntityExist(trailer) then
        hasRopes = false
        HasRopes = false
        ClearObjectiveMarkers(false)
        TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob.jobId)
        return
    end

    -- 1. Obtenha as coordenadas do trailer e da empilhadeira
    local trailerCoords = GetEntityCoords(trailer)
    local forkCoords = GetEntityCoords(fork)

    -- 2. Verifique a distância (< 15.0 unidades)
    local dist = #(trailerCoords - forkCoords)
    if dist > 15.0 then
        SendMissionNotify('Atenção', 'A empilhadeira deve estar na traseira da carreta (até 15m) para travar.', 'error')
        return
    end

    local success = lib.skillCheck({'medium', 'hard'}, {'w', 'a', 's', 'd'})

    lib.progressBar({
        duration = 3500,
        label = 'Travando correntes de fixação da empilhadeira...',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            clip = 'machinic_loop_meano',
            flag = 49
        }
    })

    -- 3. Aplique o AttachEntityToEntity na extremidade traseira com a Matriz de Colisão Híbrida
    NetworkRequestControlOfEntity(fork)
    local timeout = 1000
    while not NetworkHasControlOfEntity(fork) and timeout > 0 do
        Wait(50)
        timeout = timeout - 50
    end

    local forkOffset, forkHeading = ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(trailer)
    if not forkOffset then forkOffset = vector3(0.0, -6.6, 0.35) end
    forkHeading = forkHeading or (type(forkOffset) == 'table' and forkOffset.heading) or 0.0

    DetachEntity(fork, true, true)

    local fNet = NetworkGetEntityIsNetworked(fork) and NetworkGetNetworkIdFromEntity(fork) or nil
    if fNet then
        SetNetworkIdCanMigrate(fNet, false)
    end

    -- Ancoragem padronizada rígida no Bone 0 (Root) do trailer sem soft-pinning
    FreezeEntityPosition(fork, false)
    SetEntityDynamic(fork, false)
    AttachEntityToEntity(
        fork, trailer, 0,
        forkOffset.x, forkOffset.y, forkOffset.z,
        0.0, 0.0, forkHeading,
        false, false, false, false, 2, true
    )

    -- Matriz Híbrida Havok (Padrão Paletes): Colisão com o jogador e mundo ATIVA
    SetEntityCollision(fork, true, true)
    SetCanClimbOnEntity(fork, true)

    -- Isolamento rigoroso: Nunca acordar física de colisão contra o trailer ou cavalo mecânico
    SetEntityNoCollisionEntity(fork, trailer, false)
    SetEntityNoCollisionEntity(trailer, fork, false)
    local tk = JobEntities.truck
    if tk and DoesEntityExist(tk) then
        SetEntityNoCollisionEntity(fork, tk, false)
        SetEntityNoCollisionEntity(tk, fork, false)
    end

    -- Sincronização OneSync via Entity StateBags (Pilar 1)
    if trailer and DoesEntityExist(trailer) and NetworkGetEntityIsNetworked(trailer) and NetworkGetEntityIsNetworked(fork) then
        local fNet = NetworkGetNetworkIdFromEntity(fork)
        Entity(trailer).state:set('loadedForklift', {
            forkNet = fNet,
            offset = { x = forkOffset.x, y = forkOffset.y, z = forkOffset.z },
            heading = forkHeading
        }, true)
    end

    -- Remove o holograma da empilhadeira
    if ForkliftModule.DeleteGhostProp then
        ForkliftModule.DeleteGhostProp()
    end

    ForkliftLoadedOnTrailer = true

    if success then
        ForkliftSecured = true
        ForkliftRiskLevel = 0
        PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
        SendMissionNotify('Central Logística', 'Empilhadeira travada com correntes de alta resistência!', 'success')

        hasRopes = false
        HasRopes = false
        ClearObjectiveMarkers(false)

        -- Transição direta para a rota de entrega
        local dest = (ActiveJob and ActiveJob.deliveryCoords) or (Config.DeliveryCoords)
        TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob and ActiveJob.jobId)
        if StartDeliveryRoute then
            StartDeliveryRoute(dest, ActiveJob and ActiveJob.jobId)
        end
    else
        ForkliftSecured = false
        ForkliftRiskLevel = 'high'
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
        SendMissionNotify('Atenção', 'A amarração da empilhadeira falhou! Ajuste e tente novamente.', 'error')
        if SetupForkliftTieTarget then
            SetupForkliftTieTarget()
        end
    end
end

-- =======================================================================
-- SISTEMA VISUAL DE AMARRAÇÃO DE CARGA: CINTAS VERMELHAS REALISTAS 3D (DRAWPOLY)
-- Renderização ativada EXCLUSIVAMENTE após vitória no minigame (isSecured == true)
-- Fitas vermelhas industriais com orientação planar correta, bordas de costura e relevo.
-- =======================================================================

local function DrawPolyQuad(v1, v2, v3, v4, r, g, b, a)
    -- Face 1 (Anti-horário)
    DrawPoly(v1.x, v1.y, v1.z, v2.x, v2.y, v2.z, v3.x, v3.y, v3.z, r, g, b, a)
    DrawPoly(v1.x, v1.y, v1.z, v3.x, v3.y, v3.z, v4.x, v4.y, v4.z, r, g, b, a)
    -- Face 2 (Horário - Bilateral para anular Backface Culling de qualquer ângulo)
    DrawPoly(v3.x, v3.y, v3.z, v2.x, v2.y, v2.z, v1.x, v1.y, v1.z, r, g, b, a)
    DrawPoly(v4.x, v4.y, v4.z, v3.x, v3.y, v3.z, v1.x, v1.y, v1.z, r, g, b, a)
end

-- Renderiza uma seção de fita gerando o plano de largura alinhado corretamente à superfície da carga
local function DrawStrapSectionWithSeam(pA, pB, widthVec, hw, edgeW, isTopFace)
    -- Vermelho Industrial Realista:
    -- Topo: Luz direta plena
    local cr, cg, cb = 225, 25, 25         -- Corpo central: Vermelho vivo
    local er, eg, eb = 135, 10, 10         -- Bordas/Costuras: Carmim / Vinho escuro (relevo)
    local hr, hg, hb = 250, 60, 60         -- Nervura central: Destaque de tensão tridimensional

    if not isTopFace then
        -- Laterais: Queda de luz suave nas descidas até a prancha
        cr, cg, cb = 180, 18, 18
        er, eg, eb = 100, 8, 8
        hr, hg, hb = 210, 45, 45
    end

    local innerW = hw - edgeW
    local midW = innerW * 0.40

    local a_leftEdge   = pA - widthVec * hw
    local a_leftInner  = pA - widthVec * innerW
    local a_midL       = pA - widthVec * midW
    local a_midR       = pA + widthVec * midW
    local a_rightInner = pA + widthVec * innerW
    local a_rightEdge  = pA + widthVec * hw

    local b_leftEdge   = pB - widthVec * hw
    local b_leftInner  = pB - widthVec * innerW
    local b_midL       = pB - widthVec * midW
    local b_midR       = pB + widthVec * midW
    local b_rightInner = pB + widthVec * innerW
    local b_rightEdge  = pB + widthVec * hw

    -- 1. Borda/Costura Esquerda (simula reforço e relevo)
    DrawPolyQuad(a_leftEdge, b_leftEdge, b_leftInner, a_leftInner, er, eg, eb, 255)

    -- 2. Corpo Central Vermelho
    DrawPolyQuad(a_leftInner, b_leftInner, b_rightInner, a_rightInner, cr, cg, cb, 255)

    -- 3. Borda/Costura Direita
    DrawPolyQuad(a_rightInner, b_rightInner, b_rightEdge, a_rightEdge, er, eg, eb, 255)

    -- 4. Nervura de Tensão Central (highlight sutil)
    DrawPolyQuad(a_midL, b_midL, b_midR, a_midR, hr, hg, hb, 255)
end

local function DrawRealisticSingleStrap(trailer, pEnt, relPos, yOffset, halfX, topZ, hw, edgeW)
    -- Vetor longitudinal da carreta (aponta para frente da carreta)
    -- Ao olhar de frente para o palete, a fita deve ter largura ao longo do eixo Y da carreta!
    local fwdVec = GetEntityForwardVector(trailer)

    -- 1. Ponto no trilho esquerdo da prancha
    local lRail = GetOffsetFromEntityInWorldCoords(trailer, -1.25, relPos.y + yOffset, relPos.z - 0.15)
    -- 2. Topo esquerdo do palete
    local topL  = GetOffsetFromEntityInWorldCoords(pEnt, -halfX, yOffset, topZ)
    -- 3. Topo direito do palete
    local topR  = GetOffsetFromEntityInWorldCoords(pEnt, halfX, yOffset, topZ)
    -- 4. Ponto no trilho direito da prancha
    local rRail = GetOffsetFromEntityInWorldCoords(trailer, 1.25, relPos.y + yOffset, relPos.z - 0.15)

    -- Seção 1 (Lateral Esquerda: lRail -> topL)
    -- A largura da fita deve se expandir para frente/trás (fwdVec) para ser vista de frente larga e rente à parede do palete
    DrawStrapSectionWithSeam(lRail, topL, fwdVec, hw, edgeW, false)

    -- Seção 2 (Topo da Carga: topL -> topR)
    -- No topo, a fita também se expande para frente/trás (fwdVec) deitada sobre a caixa
    DrawStrapSectionWithSeam(topL, topR, fwdVec, hw, edgeW, true)

    -- Seção 3 (Lateral Direita: topR -> rRail)
    -- Na lateral direita, desce até a prancha com largura ao longo de fwdVec
    DrawStrapSectionWithSeam(topR, rRail, fwdVec, hw, edgeW, false)
end

local function DrawPalletPolyStraps(trailer, pEnt)
    if not trailer or not DoesEntityExist(trailer) or not pEnt or not DoesEntityExist(pEnt) then return end
    local minDim, maxDim = GetModelDimensions(GetEntityModel(pEnt))
    local topZ = (maxDim and maxDim.z) or 1.1
    local halfX = math.max(0.42, (maxDim and maxDim.x and (maxDim.x * 0.95)) or 0.5)
    local pCoords = GetEntityCoords(pEnt)
    local relPos = GetOffsetFromEntityGivenWorldCoords(trailer, pCoords.x, pCoords.y, pCoords.z)

    -- Fita Industrial de 9cm de largura visível de frente (hw = 0.045m) com costura de 1cm (edgeW = 0.010m)
    local hw = 0.045
    local edgeW = 0.010

    -- Cinta 1: Paralela Frontal (+0.28m)
    DrawRealisticSingleStrap(trailer, pEnt, relPos, 0.28, halfX, topZ, hw, edgeW)

    -- Cinta 2: Paralela Traseira (-0.28m)
    DrawRealisticSingleStrap(trailer, pEnt, relPos, -0.28, halfX, topZ, hw, edgeW)
end

CreateThread(function()
    while true do
        local sleep = 500
        local trailer = JobEntities.trailer
        local pList = LoadedPallets or LoadedPalletData or {}

        if trailer and DoesEntityExist(trailer) and #pList > 0 then
            local ped = cache.ped or PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local trCoords = GetEntityCoords(trailer)
            local distTrailer = #(pCoords - trCoords)

            -- Renderização ativa realista: apenas visível a olho nu quando próximo (<= 20m)
            if distTrailer <= 20.0 then
                sleep = 0
                for _, pData in ipairs(pList) do
                    local pEnt = pData.entity
                    -- Condicionamento ESTRITO: Apenas paletes confirmados com sucesso no minigame (isSecured == true)
                    if pData.isSecured == true and pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                        DrawPalletPolyStraps(trailer, pEnt)
                    end
                end
            elseif distTrailer <= 50.0 then
                sleep = 250
            else
                sleep = 1000
            end
        end

        Wait(sleep)
    end
end)

local function SetupForkliftTieTarget()
    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    local fork = JobEntities.forklift
    local trailer = JobEntities.trailer
    if not fork or not DoesEntityExist(fork) or not trailer or not DoesEntityExist(trailer) then
        hasRopes = false
        HasRopes = false
        ClearObjectiveMarkers(false)
        TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob and ActiveJob.jobId)
        return
    end

    -- Garante colisão física ativa no modelo para o raycast do ox_target
    SetEntityCollision(fork, true, true)
    SetCanClimbOnEntity(fork, true)

    -- 1. Spawna o holograma fantasma da empilhadeira na extremidade traseira da carreta se ainda não estiver embarcada
    if ForkliftModule.SpawnForkliftGhost and not ForkliftModule.GetCurrentGhost() and not ForkliftLoadedOnTrailer then
        ForkliftModule.SpawnForkliftGhost(trailer)
    end

    -- 2. Atualiza a rota/objetivo visual para guiar o jogador até a empilhadeira
    local fCoords = GetEntityCoords(fork)
    UpdateMissionObjective('forklift', fCoords, 'Amarrar Empilhadeira na Carreta')

    -- 3. Cria SphereZone dedicada no ox_target na posição da empilhadeira (Padrão Paletes)
    ActiveStrappingZoneId = exports.ox_target:addSphereZone({
        coords = fCoords,
        radius = 3.0,
        debug = false,
        options = {
            {
                name = 'aust_tie_current_forklift_zone',
                icon = 'fas fa-link',
                label = 'Travar Catracas da Empilhadeira',
                distance = 4.0,
                canInteract = function()
                    return (hasRopes or HasRopes) and not ForkliftSecured and not IsPedInAnyVehicle(cache.ped, false)
                end,
                onSelect = function()
                    ExecuteForkliftTie(fork)
                end
            }
        }
    })

    if ForkliftLoadedOnTrailer then
        SendMissionNotify('Central Logística', 'Paletes amarrados! Trave as catracas da empilhadeira a pé para concluir a amarração.', 'info')
    else
        SendMissionNotify('Central Logística', 'Paletes amarrados! Estacione a empilhadeira no fantasma traseiro e use as cintas para amarrá-la.', 'info')
    end
end

-- ox_target diretamente configurado para o modelo da empilhadeira
exports.ox_target:addModel('forklift', {
    {
        name = 'aust_tie_forklift_model',
        icon = 'fas fa-link',
        label = 'Amarrar Empilhadeira na Carreta',
        distance = 4.0,
        canInteract = function(entity)
            if not ActiveJob or not ActiveJob.withForklift or ForkliftSecured then return false end
            if IsPedInAnyVehicle(cache.ped, false) then return false end
            local trailer = JobEntities.trailer
            if not trailer or not DoesEntityExist(trailer) then return false end
            local forkCoords = GetEntityCoords(entity)
            local trailerCoords = GetEntityCoords(trailer)
            return #(trailerCoords - forkCoords) < 15.0
        end,
        onSelect = function(data)
            ExecuteForkliftTie(data and data.entity)
        end
    },
    {
        name = 'aust_unload_forklift_model',
        icon = 'fas fa-arrow-down',
        label = 'Descer Empilhadeira da Carreta',
        distance = 4.0,
        canInteract = function(entity)
            if not ActiveJob or not ActiveJob.withForklift then return false end
            if not ForkliftLoadedOnTrailer then return false end
            if IsPedInAnyVehicle(cache.ped, false) then return false end
            local trailer = JobEntities.trailer
            if not trailer or not DoesEntityExist(trailer) then return false end
            return IsEntityAttachedToEntity(entity, trailer)
        end,
        onSelect = function(data)
            local fork = data and data.entity
            if not fork or not DoesEntityExist(fork) then return end
            local trailer = JobEntities.trailer

            local ok = lib.progressBar({
                duration = 3500,
                label = 'Soltando travas e descendo empilhadeira...',
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
                NetworkRequestControlOfEntity(fork)
                local timeout = 1000
                while not NetworkHasControlOfEntity(fork) and timeout > 0 do
                    Wait(50)
                    timeout = timeout - 50
                end

                DetachEntity(fork, true, true)
                SetEntityCollision(fork, true, true)
                FreezeEntityPosition(fork, false)
                SetEntityDynamic(fork, true)
                SetEntityHasGravity(fork, true)
                ActivatePhysics(fork)

                -- Posiciona a empilhadeira logo atrás do trailer com segurança no chão
                if trailer and DoesEntityExist(trailer) then
                    local groundPos = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -8.5, 0.0)
                    SetEntityCoords(fork, groundPos.x, groundPos.y, groundPos.z, false, false, false, true)
                    SetEntityHeading(fork, GetEntityHeading(trailer))
                    SetVehicleOnGroundProperly(fork)
                end

                ForkliftLoadedOnTrailer = false
                ForkliftSecured = false
                ForkliftRiskLevel = 0

                -- Atualiza StateBag
                if trailer and DoesEntityExist(trailer) and NetworkGetEntityIsNetworked(trailer) then
                    Entity(trailer).state:set('loadedForklift', nil, true)
                end

                PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
                SendMissionNotify('Empilhadeira', 'Empilhadeira descarregada no solo com sucesso! Pronta para operação.', 'success')
            end
        end
    }
})

-- ox_target para estiva manual a pé nos paletes no slot fantasma ativo
local PalletPropModels = {
    'hei_prop_carrier_cargo_04b',
    'm24_1_prop_m24_1_carrier_cargo_04a',
    'sm3d_prop_pallet_1',
    'sm3d_prop_pallet_2',
    'sm3d_prop_pallet_1_rep',
    'sm3d_prop_pallet_1_open',
}

exports.ox_target:addModel(PalletPropModels, {
    {
        name = 'aust_rescue_fallen_pallet',
        icon = 'fas fa-hand-holding-box',
        label = 'Recuperar Palete Caído',
        distance = 3.5,
        canInteract = function(entity)
            if CurrentStage ~= 'STEP_8_IN_TRANSIT' then return false end
            if not ActiveJob or not JobEntities.trailer or not DoesEntityExist(JobEntities.trailer) then return false end
            if IsPedInAnyVehicle(cache.ped, false) then return false end
            if IsEntityAttached(entity) then return false end

            local targetList = LoadedPallets or LoadedPalletData or {}
            for _, pData in ipairs(targetList) do
                if pData.entity == entity and pData.isFallen and not pData.isBroken then
                    return true
                end
            end
            return false
        end,
        onSelect = function(data)
            local palletEnt = data and data.entity
            if not palletEnt or not DoesEntityExist(palletEnt) then return end
            local trailer = JobEntities.trailer
            if not trailer or not DoesEntityExist(trailer) then return end

            local targetList = LoadedPallets or LoadedPalletData or {}
            local matchedPData = nil
            for _, pData in ipairs(targetList) do
                if pData.entity == palletEnt then
                    matchedPData = pData
                    break
                end
            end

            local ok = lib.progressBar({
                duration = 4000,
                label = 'Recolhendo e içando palete para a carreta...',
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
            })

            if ok then
                local slotIdx = (matchedPData and matchedPData.slotIndex) or 1
                local snapped, snappedOffset, snappedHeading = ForkliftModule.SnapPalletToCurrentSlot(palletEnt, trailer, slotIdx)
                if snapped then
                    if matchedPData then
                        matchedPData.lost = false
                        matchedPData.isFallen = false
                        matchedPData.isSecured = true
                        matchedPData.riskLevel = 0
                        matchedPData.relOffset = snappedOffset
                        local finalRot = type(snappedHeading) == 'vector3' and snappedHeading or vector3(0.0, 0.0, tonumber(snappedHeading) or 0.0)
                        matchedPData.relHeading = finalRot.z
                        matchedPData.relRot = finalRot
                    end

                    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                    SendMissionNotify('Carga Recuperada', 'Palete estivado e fixado novamente com sucesso!', 'success')

                    local netId = NetworkGetEntityIsNetworked(palletEnt) and NetworkGetNetworkIdFromEntity(palletEnt) or 0
                    if ActiveJob and ActiveJob.jobId then
                        TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', ActiveJob.jobId, #LoadedPallets)
                    end
                end
            end
        end
    }
})

-- =======================================================================
-- BLINDAGEM CONTÍNUA DE COLISÃO MÚTUA POR FRAME (ANTI-EXPLOSÃO / HAVOK SHIELD)
-- Executa SetEntityNoCollisionEntity a cada tick (Wait(0)) com thisFrameOnly = true
-- enquanto houver carga (paletes / empilhadeira) sobre a carreta.
-- Isso anula 100% o choque físico entre carga e carreta sem desativar a colisão
-- da carga com o Player (o jogador NÃO atravessa o palete).
-- =======================================================================
CreateThread(function()
    while true do
        local trailer = JobEntities.trailer
        local truck = JobEntities.truck
        local hasCargo = false

        -- 1. Condutor do Contrato Ativo (só enquanto o job existe; ao terminar, o loop volta ao modo 250ms)
        if ActiveJob and trailer and DoesEntityExist(trailer) then
            local pList = LoadedPallets or LoadedPalletData or {}
            for _, pData in ipairs(pList) do
                local pEnt = pData.entity
                if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                    hasCargo = true
                    SetEntityNoCollisionEntity(pEnt, trailer, true)
                    SetEntityNoCollisionEntity(trailer, pEnt, true)
                    if truck and DoesEntityExist(truck) then
                        SetEntityNoCollisionEntity(pEnt, truck, true)
                        SetEntityNoCollisionEntity(truck, pEnt, true)
                    end
                end
            end

            local fork = JobEntities.forklift
            if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer and IsEntityAttachedToEntity(fork, trailer) then
                hasCargo = true
                SetEntityNoCollisionEntity(fork, trailer, true)
                SetEntityNoCollisionEntity(trailer, fork, true)
                if truck and DoesEntityExist(truck) then
                    SetEntityNoCollisionEntity(fork, truck, true)
                    SetEntityNoCollisionEntity(truck, fork, true)
                end
            end
        end

        -- 2. Havok Shield para Clientes Espectadores (Observers próximos a reboques com carga ou empilhadeiras ativas)
        local ped = cache.ped or PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local nearbyVehicles = GetGamePool('CVehicle')
        local nearbyTrailers = {}

        for _, veh in ipairs(nearbyVehicles) do
            if DoesEntityExist(veh) and GetVehicleClass(veh) == 11 then
                if #(pCoords - GetEntityCoords(veh)) <= 40.0 then
                    nearbyTrailers[#nearbyTrailers + 1] = veh
                    if veh ~= trailer then
                        local sBag = Entity(veh).state
                        local lSlots = sBag and sBag.loadedSlots
                        if lSlots and type(lSlots) == 'table' then
                            for _, sData in pairs(lSlots) do
                                if sData.palletNet then
                                    local pEnt = NetworkGetEntityFromNetworkId(sData.palletNet)
                                    if pEnt and pEnt ~= 0 and DoesEntityExist(pEnt) then
                                        hasCargo = true
                                        SetEntityNoCollisionEntity(pEnt, veh, true)
                                        SetEntityNoCollisionEntity(veh, pEnt, true)
                                    end
                                end
                            end
                        end
                        local lFork = sBag and sBag.loadedForklift
                        if lFork and lFork.forkNet then
                            local fEnt = NetworkGetEntityFromNetworkId(lFork.forkNet)
                            if fEnt and fEnt ~= 0 and DoesEntityExist(fEnt) and IsEntityAttachedToEntity(fEnt, veh) then
                                hasCargo = true
                                SetEntityNoCollisionEntity(fEnt, veh, true)
                                SetEntityNoCollisionEntity(veh, fEnt, true)
                            end
                        end
                    end
                end
            end
        end

        -- 3. Blindagem de Empilhadeira Ativa de Terceiros e Paletes Carregados (Anti-Capotamento OneSync)
        for _, veh in ipairs(nearbyVehicles) do
            if DoesEntityExist(veh) and GetEntityModel(veh) == joaat('forklift') then
                if #(pCoords - GetEntityCoords(veh)) <= 40.0 then
                    local fBag = Entity(veh).state
                    local carriedNet = fBag and fBag.forkliftCarriedNet
                    local carriedEnt = carriedNet and NetworkGetEntityFromNetworkId(carriedNet)

                    if carriedEnt and carriedEnt ~= 0 and DoesEntityExist(carriedEnt) then
                        hasCargo = true
                        SetEntityNoCollisionEntity(carriedEnt, veh, true)
                        SetEntityNoCollisionEntity(veh, carriedEnt, true)

                        for _, trVeh in ipairs(nearbyTrailers) do
                            SetEntityNoCollisionEntity(carriedEnt, trVeh, true)
                            SetEntityNoCollisionEntity(trVeh, carriedEnt, true)
                        end
                    end

                    -- Blindagem Havok: Somente desativa colisão mútua entre empilhadeira e trailer SE ela estiver efetivamente embarcada/anexada
                    for _, trVeh in ipairs(nearbyTrailers) do
                        if IsEntityAttachedToEntity(veh, trVeh) then
                            hasCargo = true
                            SetEntityNoCollisionEntity(veh, trVeh, true)
                            SetEntityNoCollisionEntity(trVeh, veh, true)
                        end
                    end
                end
            end
        end

        -- Otimização Resmon: SetEntityNoCollisionEntity persiste no motor do GTA V
        -- Polling adaptativo a cada 500ms elimina 99% do consumo de CPU / GetGamePool
        Wait(hasCargo and 500 or 1500)
    end
end)

function SetupNextPalletTarget()
    -- Garante que qualquer zona ativa anterior seja destruída
    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    -- 1. Se completou todos os paletes
    if currentTieIndex > #LoadedPallets then
        if ActiveJob and ActiveJob.withForklift and not ForkliftSecured then
            SetupForkliftTieTarget()
            return
        end

        CheckAllTiedAndStartRoute()
        return
    end

    local currentPallet = LoadedPallets[currentTieIndex]
    if not currentPallet or not currentPallet.entity or not DoesEntityExist(currentPallet.entity) then
        currentTieIndex = currentTieIndex + 1
        SetupNextPalletTarget()
        return
    end

    -- 2. Captura coordenadas mundiais e relativas do palete em relação ao reboque
    local trailer = JobEntities.trailer
    local pCoords = GetEntityCoords(currentPallet.entity)
    local targetCoords = pCoords

    if trailer and DoesEntityExist(trailer) then
        local relPos = GetOffsetFromEntityGivenWorldCoords(trailer, pCoords.x, pCoords.y, pCoords.z)
        -- Lateral correspondente: se relPos.x >= 0, lateral direita (X ≈ +1.45m); caso contrário, lateral esquerda (X ≈ -1.45m)
        local sideX = (relPos.x >= 0.0) and 1.45 or -1.45
        targetCoords = GetOffsetFromEntityInWorldCoords(trailer, sideX, relPos.y, relPos.z)
    end

    -- 3. Move a seta verde flutuante diretamente para o topo deste palete
    UpdateMissionObjective('pallet', pCoords, ('Amarrar Palete (%d/%d)'):format(currentTieIndex, #LoadedPallets))

    -- 4. Cria a zona esférica de interação do ox_target EXCLUSIVAMENTE na lateral da carreta correspondente
    ActiveStrappingZoneId = exports.ox_target:addSphereZone({
        coords = targetCoords,
        radius = 1.6,
        debug = false,
        options = {
            {
                name = 'aust_tie_current_pallet',
                icon = 'fas fa-tape',
                label = ('Amarrar Palete (%s/%s)'):format(currentTieIndex, #LoadedPallets),
                distance = 2.5,
                canInteract = function()
                    return (hasRopes or HasRopes) and not currentPallet.isSecured and not IsPedInAnyVehicle(cache.ped, false)
                end,
                onSelect = function()
                    ExecutePalletTie(currentTieIndex)
                end
            }
        }
    })

    SendMissionNotify('Central Logística', ('Amarre o palete %s de %s na lateral da carreta.'):format(currentTieIndex, #LoadedPallets), 'info')
end

local function StartStrappingPalletsStage()
    CurrentStage = 'STEP_7_STRAP_PALLETS'
    PurgeObjectiveMarkersAndWait(false)
    currentTieIndex = 1

    if #LoadedPallets == 0 and (not ActiveJob or not ActiveJob.withForklift or not ForkliftLoadedOnTrailer or ForkliftSecured) then
        CheckAllTiedAndStartRoute()
        return
    end

    SetupNextPalletTarget()
end

local SetupRopesStage = nil
local SetupEmbarkForkliftStage = nil

SetupRopesStage = function()
    CurrentStage = 'STEP_6_GET_ROPES'
    PurgeObjectiveMarkersAndWait(false)
    hasRopes = false
    HasRopes = false
    currentTieIndex = 1

    SendMissionNotify('Central Logística', 'Carregamento finalizado! Vá até a lateral do caminhão e pegue as cintas de amarração.', 'info')

    if not JobEntities.truck or not DoesEntityExist(JobEntities.truck) then return end
    local boxCoords = GetOffsetFromEntityInWorldCoords(JobEntities.truck, -1.2, 0.5, 0.0)

    -- Seta verde exclusiva na caixa de ferramentas lateral do caminhão
    UpdateMissionObjective('dock', boxCoords, 'Caixa de Ferramentas (Pegar Cordas)')

    exports.ox_target:addLocalEntity(JobEntities.truck, {
        {
            name = 'aust_get_ropes',
            icon = 'fa-solid fa-toolbox',
            label = 'Pegar Cintas/Cordas de Amarração',
            distance = 2.8,
            canInteract = function()
                return CurrentStage == 'STEP_6_GET_ROPES' and not hasRopes and not HasRopes and not IsPedInAnyVehicle(cache.ped, false)
            end,
            onSelect = function()
                local ok = lib.progressBar({
                    duration = 2500,
                    label = 'Pegando cintas de amarração...',
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
                    hasRopes = true
                    HasRopes = true
                    PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
                    SendMissionNotify('Central Logística', 'Cintas recolhidas! Amarre cada palete individualmente no reboque.', 'info')
                    pcall(function() exports.ox_target:removeLocalEntity(JobEntities.truck, 'aust_get_ropes') end)
                    StartStrappingPalletsStage()
                end
            end
        }
    })
end

SetupEmbarkForkliftStage = function()
    SetupForkliftTieTarget()
end

-- =======================================================================
-- ETAPA 8 & 9: ROTA FINAL, ENTREGA E RECOMPENSA COM FÍSICA DE ROMPIMENTO
-- =======================================================================

function StartDeliveryRoute(deliveryCoords, jobId)
    if CurrentStage == 'STEP_8_IN_TRANSIT' then return end
    CurrentStage = 'STEP_8_IN_TRANSIT'
    PurgeObjectiveMarkersAndWait(false)

    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    -- Remove eventuais alvos remanescentes nos paletes
    for idx, pData in ipairs(LoadedPallets or {}) do
        if pData.entity and DoesEntityExist(pData.entity) then
            pcall(function() exports.ox_target:removeLocalEntity(pData.entity, 'aust_tie_current_pallet') end)
            pcall(function() exports.ox_target:removeLocalEntity(pData.entity, 'tie_pallet_' .. idx) end)
            pcall(function() exports.ox_target:removeLocalEntity(pData.entity) end)
        end
    end

    local fork = JobEntities.forklift
    if fork and DoesEntityExist(fork) then
        pcall(function() exports.ox_target:removeLocalEntity(fork, 'aust_tie_forklift_model') end)
    end

    local dest = deliveryCoords or (ActiveJob and ActiveJob.deliveryCoords) or (Config.DeliveryCoords)

    -- Traça rota e waypoint no GPS para o destino final
    if dest then
        SetNewWaypoint(dest.x, dest.y)
    end

    -- Orienta o jogador a entrar no caminhão com marcador e som
    if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
        UpdateMissionObjective('truck', JobEntities.truck, 'Entre no seu Caminhão')
    elseif dest then
        UpdateMissionObjective('delivery', dest, 'Destino da Entrega')
    end

    -- Ativa e exibe a interface NUI do G-Meter (Estabilidade da Carga)
    SendNUIMessage({ action = 'gmeter_show' })

    SendMissionNotify('Central Logística', 'Carga 100% amarrada e travada! Entre no caminhão e inicie a viagem.', 'success')
    PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)

    -- Ativa monitoramento de risco químico para cargas perigosas ADR
    if ActiveJob and ActiveJob.cargoType == 'adr' then
        AdrHazardModule.StartMonitoring(jobId, JobEntities.truck, JobEntities.trailer, function(currentIntegrity)
            SendMissionNotify('Status de Carga ADR', ('Integridade química: %d%%. Contenha o vazamento na válvula!'):format(currentIntegrity), 'warning')
        end)
    end

    -- BLINDAGEM DE ESTABILIDADE: PREPARAÇÃO DA CARGA PARA A VIAGEM
    local trailer = JobEntities.trailer
    if trailer and DoesEntityExist(trailer) then
        SetVehicleExplodesOnHighExplosionDamage(trailer, false)
        SetVehicleCanBeVisiblyDamaged(trailer, false)
        SetVehicleStrong(trailer, true)

        local trailerBone = GetEntityBoneIndexByName(trailer, "chassis")
        if trailerBone == -1 then trailerBone = GetEntityBoneIndexByName(trailer, "bodyshell") end
        if trailerBone == -1 then trailerBone = 0 end

        for _, pData in ipairs(LoadedPallets or {}) do
            local pEnt = pData.entity
            if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                if NetworkGetEntityIsNetworked(pEnt) and not NetworkHasControlOfEntity(pEnt) then
                    NetworkRequestControlOfEntity(pEnt)
                    local t = 200
                    while not NetworkHasControlOfEntity(pEnt) and t > 0 do
                        Wait(20)
                        t = t - 20
                    end
                end
                if NetworkGetEntityIsNetworked(pEnt) and NetworkHasControlOfEntity(pEnt) then
                    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(pEnt), false)
                end
                SetEntityAsMissionEntity(pEnt, true, true)
                SetEntityLodDist(pEnt, 0xFFFF)
                SetEntityVisible(pEnt, true)
                ResetEntityAlpha(pEnt)
                DisableCamCollisionForEntity(pEnt)
                FreezeEntityPosition(pEnt, false)
                SetEntityDynamic(pEnt, false)
                SetEntityHasGravity(pEnt, false)
                SetEntityVelocity(pEnt, 0.0, 0.0, 0.0)
                SetEntityCollision(pEnt, false, false)
                SetEntityNoCollisionEntity(pEnt, trailer, false)
                SetEntityNoCollisionEntity(trailer, pEnt, false)
                if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
                    SetEntityNoCollisionEntity(pEnt, JobEntities.truck, false)
                    SetEntityNoCollisionEntity(JobEntities.truck, pEnt, false)
                end

                -- Reforço imediato de ancoragem na malha do trailer (Bone 0) sem soft-pinning
                local off = pData.relOffset or vector3(0.0, 0.0, 0.35)
                local rot = pData.relRot or vector3(0.0, 0.0, pData.relHeading or 0.0)

                AttachEntityToEntity(
                    pEnt, trailer, 0,
                    off.x, off.y, off.z,
                    rot.x, rot.y, rot.z,
                    false, false, false, false, 2, true
                )
            end
        end

        local fork = JobEntities.forklift
        if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer then
            if NetworkGetEntityIsNetworked(fork) and not NetworkHasControlOfEntity(fork) then
                NetworkRequestControlOfEntity(fork)
                local t = 200
                while not NetworkHasControlOfEntity(fork) and t > 0 do
                    Wait(20)
                    t = t - 20
                end
            end
            if NetworkGetEntityIsNetworked(fork) and NetworkHasControlOfEntity(fork) then
                SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(fork), false)
            end
            SetEntityAsMissionEntity(fork, true, true)
            SetEntityLodDist(fork, 0xFFFF)
            FreezeEntityPosition(fork, false)
            SetEntityDynamic(fork, false)
            SetEntityHasGravity(fork, false)
            SetEntityVelocity(fork, 0.0, 0.0, 0.0)
            SetEntityCollision(fork, false, false)
            SetEntityNoCollisionEntity(fork, trailer, false)
            SetEntityNoCollisionEntity(trailer, fork, false)
            if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
                SetEntityNoCollisionEntity(fork, JobEntities.truck, false)
                SetEntityNoCollisionEntity(JobEntities.truck, fork, false)
            end

            local forkOffset, forkHeading = (ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(trailer)) or vector3(0.0, -6.6, 0.35)
            local fHead = forkHeading or (type(forkOffset) == 'table' and forkOffset.heading) or 0.0
            AttachEntityToEntity(
                fork, trailer, 0,
                forkOffset.x, forkOffset.y, forkOffset.z,
                0.0, 0.0, fHead,
                false, false, false, false, 2, true
            )
        end

        -- Registra todas as entidades da missão no servidor para Garbage Collection e Anti-Cheat (Pilares 2 e 3)
        local truckNet = (JobEntities.truck and DoesEntityExist(JobEntities.truck) and NetworkGetEntityIsNetworked(JobEntities.truck)) and NetworkGetNetworkIdFromEntity(JobEntities.truck) or nil
        local trailerNet = (JobEntities.trailer and DoesEntityExist(JobEntities.trailer) and NetworkGetEntityIsNetworked(JobEntities.trailer)) and NetworkGetNetworkIdFromEntity(JobEntities.trailer) or nil
        local forkNet = (JobEntities.forklift and DoesEntityExist(JobEntities.forklift) and NetworkGetEntityIsNetworked(JobEntities.forklift)) and NetworkGetNetworkIdFromEntity(JobEntities.forklift) or nil
        local palletNets = {}
        for _, pData in ipairs(LoadedPallets or {}) do
            if pData.entity and DoesEntityExist(pData.entity) and NetworkGetEntityIsNetworked(pData.entity) then
                table.insert(palletNets, NetworkGetNetworkIdFromEntity(pData.entity))
            end
        end
        TriggerServerEvent('aurp_trucker:server:registerJobEntities', truckNet, trailerNet, forkNet, palletNets)
    end

    -- Monitoramento otimizado de Força G lateral, física híbrida e queda dinâmica de paletes frouxos
    CreateThread(function()
        local lastDropTime = 0
        local lastSyncAnchorTime = 0
        local enteredTruck = false
        local isCargoInTransitMode = false
        local stoppedSince = 0
        local isParkFrozen = false
        local currentSmoothPercent = 50.0

        while CurrentStage == 'STEP_8_IN_TRANSIT' do
            local truck = JobEntities.truck
            local ped = cache.ped or PlayerPedId()

            if not truck or not DoesEntityExist(truck) or IsEntityDead(truck) or IsEntityInWater(truck) then
                SendMissionNotify('Missão Fracassada', 'O caminhão foi destruído ou submergiu! A entrega foi cancelada.', 'error')
                if ActiveJob and ActiveJob.jobId then
                    TriggerServerEvent('aurp_trucker:server:cancelDelivery', ActiveJob.jobId, 'Caminhão destruído ou afundado')
                end
                CleanupCurrentJob()
                break
            end

            -- Otimização Resmon & Controle Dinâmico Adaptativo de Colisão
            local currentVeh = cache.vehicle or GetVehiclePedIsIn(ped, false)
            local isDrivingTruck = (currentVeh == truck and GetPedInVehicleSeat(truck, -1) == ped)
            local truckSpeed = (truck and DoesEntityExist(truck)) and (GetEntitySpeed(truck) * 3.6) or 0.0
            local shouldBeInTransit = isDrivingTruck and (truckSpeed >= 3.0)

            -- PILAR 5: ESTABILIDADE FÍSICA HAVOK (PARKING FREEZE SEGURO)
            -- NUNCA congelar o reboque se houver entidades físicas atreladas (evita reação de parede infinita)
            if truckSpeed < 0.5 and not isDrivingTruck then
                if stoppedSince == 0 then stoppedSince = GetGameTimer() end
                if GetGameTimer() - stoppedSince >= 5000 and not isParkFrozen then
                    isParkFrozen = true
                    FreezeEntityPosition(truck, true)
                end
            else
                stoppedSince = 0
                if isParkFrozen then
                    isParkFrozen = false
                    FreezeEntityPosition(truck, false)
                end
            end

            -- CONTROLE FÍSICO CINEMÁTICO RÍGIDO (Elimina micro-desync e arrasto inercial)
            -- A carga permanece 100% cinemática (SetEntityDynamic = false, SetEntityHasGravity = false).
            -- O modo de trânsito é baseado na condução (isDrivingTruck), eliminando recálculos do Havok ao cruzar 3 km/h.
            if isDrivingTruck then
                if not isCargoInTransitMode then
                    isCargoInTransitMode = true
                    local targetList = LoadedPallets or LoadedPalletData or {}
                    for _, pData in ipairs(targetList) do
                        local pEnt = pData.entity
                        if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                            if NetworkGetEntityIsNetworked(pEnt) and not NetworkHasControlOfEntity(pEnt) then
                                NetworkRequestControlOfEntity(pEnt)
                            end
                            SetEntityCollision(pEnt, false, false)
                            SetEntityDynamic(pEnt, false)
                            SetEntityHasGravity(pEnt, false)
                            SetEntityVelocity(pEnt, 0.0, 0.0, 0.0)
                            FreezeEntityPosition(pEnt, false)
                        end
                    end

                    local fork = JobEntities.forklift
                    if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer then
                        if NetworkGetEntityIsNetworked(fork) and not NetworkHasControlOfEntity(fork) then
                            NetworkRequestControlOfEntity(fork)
                        end
                        SetEntityCollision(fork, false, false)
                        SetEntityDynamic(fork, false)
                        SetEntityHasGravity(fork, false)
                        SetEntityVelocity(fork, 0.0, 0.0, 0.0)
                        FreezeEntityPosition(fork, false)
                    end
                end
            else
                if isCargoInTransitMode then
                    isCargoInTransitMode = false
                    -- Fora da cabine: reativa colisão a pé, mantendo física cinemática estável
                    local targetList = LoadedPallets or LoadedPalletData or {}
                    for _, pData in ipairs(targetList) do
                        local pEnt = pData.entity
                        if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                            SetEntityCollision(pEnt, true, true)
                            SetCanClimbOnEntity(pEnt, true)
                            SetEntityDynamic(pEnt, false)
                            SetEntityHasGravity(pEnt, false)
                            SetEntityVelocity(pEnt, 0.0, 0.0, 0.0)
                            FreezeEntityPosition(pEnt, false)
                            if trailer and DoesEntityExist(trailer) then
                                SetEntityNoCollisionEntity(pEnt, trailer, false)
                                SetEntityNoCollisionEntity(trailer, pEnt, false)
                            end
                        end
                    end

                    local fork = JobEntities.forklift
                    if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer then
                        SetEntityCollision(fork, true, true)
                        SetCanClimbOnEntity(fork, true)
                        SetEntityDynamic(fork, false)
                        SetEntityHasGravity(fork, false)
                        SetEntityVelocity(fork, 0.0, 0.0, 0.0)
                        FreezeEntityPosition(fork, false)
                        if trailer and DoesEntityExist(trailer) then
                            SetEntityNoCollisionEntity(fork, trailer, false)
                            SetEntityNoCollisionEntity(trailer, fork, false)
                        end
                    end
                end
            end

            if not isDrivingTruck then
                SendNUIMessage({ action = 'gmeter_hide' })
                Wait(500)
            else
                -- SYNC ANCHOR PERIÓDICO (Garante sincronização total e previne descolamento em reboque)
                local curTime = GetGameTimer()
                if curTime - lastSyncAnchorTime >= 1500 then
                    lastSyncAnchorTime = curTime
                    local tr = JobEntities.trailer
                    if tr and DoesEntityExist(tr) then
                        local trBone = GetEntityBoneIndexByName(tr, "chassis")
                        if trBone == -1 then trBone = GetEntityBoneIndexByName(tr, "bodyshell") end
                        if trBone == -1 then trBone = 0 end

                        local targetList = LoadedPallets or LoadedPalletData or {}
                        for _, pData in ipairs(targetList) do
                            local pEnt = pData.entity
                            if pEnt and DoesEntityExist(pEnt) and pData.isSecured and not pData.lost and not pData.isFallen then
                                SetEntityDynamic(pEnt, false)
                                SetEntityHasGravity(pEnt, false)
                                if not IsEntityAttachedToEntity(pEnt, tr) then
                                    if NetworkGetEntityIsNetworked(pEnt) and not NetworkHasControlOfEntity(pEnt) then
                                        NetworkRequestControlOfEntity(pEnt)
                                    end
                                    if NetworkGetEntityIsNetworked(pEnt) and NetworkHasControlOfEntity(pEnt) then
                                        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(pEnt), false)
                                    end
                                    SetEntityLodDist(pEnt, 0xFFFF)
                                    SetEntityVisible(pEnt, true)
                                    ResetEntityAlpha(pEnt)
                                    DisableCamCollisionForEntity(pEnt)
                                    FreezeEntityPosition(pEnt, false)
                                    SetEntityDynamic(pEnt, false)
                                    SetEntityHasGravity(pEnt, false)
                                    SetEntityVelocity(pEnt, 0.0, 0.0, 0.0)
                                    if isCargoInTransitMode then
                                        SetEntityCollision(pEnt, false, false)
                                    else
                                        SetEntityCollision(pEnt, true, true)
                                        SetCanClimbOnEntity(pEnt, true)
                                        SetEntityNoCollisionEntity(pEnt, tr, false)
                                        SetEntityNoCollisionEntity(tr, pEnt, false)
                                    end
                                    local off = pData.relOffset or (ForkliftModule.GetSlotOffset and ForkliftModule.GetSlotOffset(tr, pData.slotIndex or _)) or vector3(0.0, 0.0, 0.35)
                                    local rot = pData.relRot or vector3(0.0, 0.0, pData.relHeading or (type(off) == 'table' and off.heading) or 0.0)

                                    AttachEntityToEntity(
                                        pEnt, tr, 0,
                                        off.x, off.y, off.z,
                                        rot.x, rot.y, rot.z,
                                        false, false, false, false, 2, true
                                    )
                                end
                            end
                        end

                        local fork = JobEntities.forklift
                        if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer and ForkliftSecured then
                            SetEntityDynamic(fork, false)
                            SetEntityHasGravity(fork, false)
                            if not IsEntityAttachedToEntity(fork, tr) then
                                if NetworkGetEntityIsNetworked(fork) and not NetworkHasControlOfEntity(fork) then
                                    NetworkRequestControlOfEntity(fork)
                                end
                                if NetworkGetEntityIsNetworked(fork) and NetworkHasControlOfEntity(fork) then
                                    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(fork), false)
                                end
                                FreezeEntityPosition(fork, false)
                                SetEntityDynamic(fork, false)
                                SetEntityHasGravity(fork, false)
                                SetEntityVelocity(fork, 0.0, 0.0, 0.0)
                                if isCargoInTransitMode then
                                    SetEntityCollision(fork, false, false)
                                else
                                    SetEntityCollision(fork, true, true)
                                    SetCanClimbOnEntity(fork, true)
                                    SetEntityNoCollisionEntity(fork, tr, false)
                                    SetEntityNoCollisionEntity(tr, fork, false)
                                end
                                local forkOffset, forkHeading = (ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(tr)) or vector3(0.0, -6.6, 0.35)
                                local fHead = forkHeading or (type(forkOffset) == 'table' and forkOffset.heading) or 0.0
                                AttachEntityToEntity(
                                    fork, tr, 0,
                                    forkOffset.x, forkOffset.y, forkOffset.z,
                                    0.0, 0.0, fHead,
                                    false, false, false, false, 2, true
                                )
                            end
                        end
                    end
                end

                if not enteredTruck then
                    enteredTruck = true
                    SendNUIMessage({ action = 'gmeter_show' })
                    if dest then
                        UpdateMissionObjective('delivery', dest, 'Destino da Entrega')
                    end
                end

                Wait(50)

                local targetList = LoadedPallets or LoadedPalletData or {}
                local hasHighRisk = false
                local anyRemaining = false

                for _, pData in ipairs(targetList) do
                    if pData.isSecured and not pData.lost and not pData.isFallen then
                        anyRemaining = true
                        if pData.riskLevel == 'high' or pData.riskLevel == 'medium' then
                            hasHighRisk = true
                        end
                    end
                end

                -- Se não há mais carga presa ou se a viagem acabou, oculta o medidor
                if not anyRemaining and (not ActiveJob or not ActiveJob.withForklift or not ForkliftLoadedOnTrailer or not ForkliftSecured) then
                    SendNUIMessage({ action = 'gmeter_hide' })
                else
                    -- CÁLCULO FÍSICO REAL DA ESTABILIDADE (G-METER VETORIAL)
                    local speed = GetEntitySpeed(truck) -- m/s
                    local speedKmh = speed * 3.6
                    local rotVel = GetEntityRotationVelocity(truck) -- rad/s
                    local yawRate = rotVel.z -- taxa angular de guinada em curva
                    local now = GetGameTimer()

                    -- Captura inclinação lateral (Roll) do caminhão e da carreta
                    local trailer = JobEntities.trailer
                    local trailerRoll = 0.0
                    if trailer and DoesEntityExist(trailer) then
                        trailerRoll = GetEntityRoll(trailer)
                    end
                    local truckRoll = GetEntityRoll(truck)

                    -- Determina a inclinação dominante em graus [-180, 180]
                    local activeRoll = (trailer and DoesEntityExist(trailer) and math.abs(trailerRoll) > math.abs(truckRoll)) and trailerRoll or truckRoll

                    -- Aceleração centrífuga lateral (a = v * omega_yaw / 9.81 em Gs)
                    local centripetalG = (speed * yawRate) / 9.81

                    -- Componente de inclinação/tombamento (calibrado para veículos pesados / suspensão rígida)
                    local rollG = (activeRoll / 38.0)

                    -- Sensibilidade equilibrada e realista: tolerância aumentada contra falsos positivos
                    local riskMultiplier = hasHighRisk and 1.35 or 0.85
                    local rawForce = ((centripetalG * 0.95) + (rollG * 0.85)) * riskMultiplier
                    if rawForce > 1.0 then rawForce = 1.0 elseif rawForce < -1.0 then rawForce = -1.0 end

                    -- Converte força lateral em porcentagem (0 a 100, 50 = centro)
                    local targetPercent = math.floor(50.0 + (rawForce * 50.0))
                    if targetPercent < 2 then targetPercent = 2 elseif targetPercent > 98 then targetPercent = 98 end

                    -- Suavização exponencial para resposta fluida no HUD
                    currentSmoothPercent = currentSmoothPercent + (targetPercent - currentSmoothPercent) * 0.35
                    local percent = math.floor(currentSmoothPercent + 0.5)
                    local isCritical = (percent <= 10 or percent >= 90)

                    -- Atualiza HUD de estabilidade com debounce inteligente de IPC
                    if not lastGmeterPercent or math.abs(percent - lastGmeterPercent) >= 1 or isCritical ~= lastGmeterCritical or (now - (lastGmeterSend or 0)) >= 200 then
                        lastGmeterPercent = percent
                        lastGmeterCritical = isCritical
                        lastGmeterSend = now
                        SendNUIMessage({
                            action = 'gmeter_update',
                            percent = percent,
                            isCritical = isCritical,
                            speed = speedKmh
                        })
                    end

                    -- GATILHO DINÂMICO E REALISTA DE QUEDA DE CARGA:
                    -- Tolerância aumentada: exige inclinação severa (> 32° real de roll) OU curva em alta velocidade (> 55 km/h na faixa crítica)
                    -- Blindagem Estrita: SÓ PODE DISPARAR DURANTE STEP_8_IN_TRANSIT (jamais no carregamento ou pátio)
                    local absRoll = math.abs(activeRoll)
                    local isSevereTilt = absRoll > 32.0
                    local isCentrifugalCritical = isCritical and speedKmh > 55.0

                    if CurrentStage == 'STEP_8_IN_TRANSIT' and (isSevereTilt or isCentrifugalCritical) and (now - lastDropTime >= 4500) then
                        local candidatePallet = nil

                        -- Somente paletes com amarração frouxa ou risco ativo podem ceder e cair
                        -- Cargas amarradas perfeitamente (riskLevel == 0) possuem retenção 100% inquebrável
                        for _, pData in ipairs(targetList) do
                            if pData.isSecured and (pData.riskLevel == 'high' or pData.riskLevel == 'medium') and not pData.lost and not pData.isFallen then
                                candidatePallet = pData
                                break
                            end
                        end

                        if candidatePallet then
                            lastDropTime = now
                            candidatePallet.lost = true
                            candidatePallet.isFallen = true

                            local palletEnt = candidatePallet.entity
                            if palletEnt and DoesEntityExist(palletEnt) then
                                pcall(function()
                                    if NetworkGetEntityIsNetworked(palletEnt) then
                                        NetworkRequestControlOfEntity(palletEnt)
                                        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(palletEnt), true)
                                    end

                                    -- RESTAURAÇÃO TOTAL NA QUEDA: REATIVA COLISÃO E FÍSICA DINÂMICA
                                    DetachEntity(palletEnt, true, true)
                                    SetEntityDynamic(palletEnt, true)
                                    SetEntityCollision(palletEnt, true, true)
                                    FreezeEntityPosition(palletEnt, false)
                                    SetEntityHasGravity(palletEnt, true)
                                    ActivatePhysics(palletEnt)

                                    -- Aplica impulso centrífugo realista para lançar o palete para fora da caçamba
                                    local refEntity = (trailer and DoesEntityExist(trailer)) and trailer or truck
                                    local rightVector = GetEntityRightVector(refEntity)
                                    local sign = (rawForce > 0) and 1.0 or -1.0
                                    if isSevereTilt and not isCentrifugalCritical then
                                        sign = (activeRoll > 0) and 1.0 or -1.0
                                    end
                                    local palletImpulse = rightVector * (sign * 7.5) + vector3(0.0, 0.0, 1.6)
                                    ApplyForceToEntityCenterOfMass(palletEnt, 1, palletImpulse.x, palletImpulse.y, palletImpulse.z, false, false, true, false)

                                    -- Efeito de impacto no HUD
                                    SendNUIMessage({ action = 'gmeter_drop' })

                                    -- Cálculo de Velocidade e Dano Estrutural no Impacto
                                    local isShattered = false
                                    if speed > 16.6 then -- > 60 km/h
                                        isShattered = true
                                        candidatePallet.isBroken = true
                                        PlaySoundFrontend(-1, "WRECKED", "CAR_STEAL_2_SOUNDSET", true)
                                        SendMissionNotify('CARGA DESTRUÍDA!', 'A amarração cedeu no limite da curva! O palete se despedaçou na pista.', 'error')
                                    else
                                        local roll = math.random(1, 100)
                                        if roll <= 60 then
                                            candidatePallet.isBroken = false
                                            candidatePallet.canRescue = true
                                            PlaySoundFrontend(-1, "COLLISION_DEFAULT", "CAR_STEAL_2_SOUNDSET", true)
                                            SendMissionNotify('PALETE CAÍDO!', 'Um palete caiu na pista, mas resistiu intacto! Pode ser resgatado com a empilhadeira.', 'warning')
                                        else
                                            isShattered = true
                                            candidatePallet.isBroken = true
                                            PlaySoundFrontend(-1, "WRECKED", "CAR_STEAL_2_SOUNDSET", true)
                                            SendMissionNotify('CARGA DESTRUÍDA!', 'O palete caiu da carreta e a mercadoria foi destruída no impacto.', 'error')
                                        end
                                    end

                                    if ActiveJob then
                                        ActiveJob.cargoHealth = math.max(0, (ActiveJob.cargoHealth or 100) - 20)
                                    end

                                    local netId = NetworkGetEntityIsNetworked(palletEnt) and NetworkGetNetworkIdFromEntity(palletEnt) or 0
                                    if ActiveJob and ActiveJob.jobId then
                                        TriggerServerEvent('aurp_trucker:server:palletLost', ActiveJob.jobId, netId)
                                    end

                                    CreateThread(function()
                                        local settleTimeout = GetGameTimer() + 8000
                                        while DoesEntityExist(palletEnt) and GetGameTimer() < settleTimeout do
                                            Wait(500)
                                            if GetEntitySpeed(palletEnt) < 0.2 then break end
                                        end
                                        if DoesEntityExist(palletEnt) then
                                            FreezeEntityPosition(palletEnt, true)
                                            if isShattered then
                                                SetEntityAsNoLongerNeeded(palletEnt)
                                            else
                                                if ActiveJob and ActiveJob.withForklift then
                                                    ForkliftModule.SetMissionPallets({ palletEnt })
                                                else
                                                    SetEntityAsNoLongerNeeded(palletEnt)
                                                end
                                            end
                                        end
                                    end)
                                end)
                            end
                        end
                    end

                    -- FÍSICA HÍBRIDA DA EMPILHADEIRA EMBARCADA: Queda em curvas severas se mal amarrada
                    if ActiveJob and ActiveJob.withForklift and ForkliftLoadedOnTrailer and ForkliftSecured and (ForkliftRiskLevel == 'high') then
                        local fork = JobEntities.forklift
                        if fork and DoesEntityExist(fork) and (now - lastDropTime >= 5000) then
                            if math.random(1, 100) <= 65 then -- 65% de chance de romper correntes frouxas
                                lastDropTime = now
                                ForkliftLoadedOnTrailer = false
                                ForkliftSecured = false

                                pcall(function()
                                    if NetworkGetEntityIsNetworked(fork) then
                                        NetworkRequestControlOfEntity(fork)
                                        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(fork), true)
                                    end

                                    DetachEntity(fork, true, true)
                                    SetEntityCollision(fork, true, true)
                                    FreezeEntityPosition(fork, false)
                                    SetVehicleEngineHealth(fork, 350.0) -- Dano severo no motor
                                    SetVehicleBodyHealth(fork, 400.0)

                                    local rightVector = GetEntityRightVector(truck)
                                    local sign = (rawForce > 0) and -1.0 or 1.0
                                    local forkImpulse = rightVector * (sign * 8.0) + vector3(0.0, 0.0, 1.8)
                                    ApplyForceToEntityCenterOfMass(fork, 1, forkImpulse.x, forkImpulse.y, forkImpulse.z, false, false, true, false)

                                    PlaySoundFrontend(-1, "WRECKED", "CAR_STEAL_2_SOUNDSET", true)
                                    SendMissionNotify('ALERTA MÁXIMO!', 'A corrente cedeu e a empilhadeira capotou na rodovia!', 'error')
                                end)

                                -- Adiciona interação ox_target para empurrar e desvirar a empilhadeira
                                exports.ox_target:addLocalEntity(fork, {
                                    {
                                        name = 'aust_push_forklift',
                                        icon = 'fas fa-arrows-rotate',
                                        label = 'Empurrar / Desvirar Empilhadeira',
                                        distance = 3.0,
                                        canInteract = function()
                                            return not IsPedInAnyVehicle(cache.ped, false) and (GetEntityRoll(fork) > 40.0 or GetEntityRoll(fork) < -40.0 or GetEntityPitch(fork) > 40.0 or GetEntityPitch(fork) < -40.0)
                                        end,
                                        onSelect = function()
                                            local ok = lib.progressBar({
                                                duration = 4500,
                                                label = 'Empurrando e alinhando a empilhadeira...',
                                                useWhileDead = false,
                                                canCancel = true,
                                                disable = { move = true, car = true, combat = true },
                                                anim = {
                                                    dict = 'misscarstealfinal',
                                                    clip = 'push_car_loop',
                                                    flag = 49
                                                }
                                            })

                                            if ok then
                                                local fCoords = GetEntityCoords(fork)
                                                SetEntityRotation(fork, 0.0, 0.0, GetEntityHeading(fork), 2, true)
                                                SetVehicleOnGroundProperly(fork)
                                                SetVehicleFixed(fork)
                                                SetVehicleEngineHealth(fork, 1000.0)
                                                PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
                                                SendMissionNotify('Manutenção', 'Empilhadeira desvirada com sucesso!', 'success')
                                                pcall(function() exports.ox_target:removeLocalEntity(fork, 'aust_push_forklift') end)
                                            end
                                        end
                                    }
                                })
                            end
                        end
                    end
                end
            end
        end
    end)

    if ActiveDeliveryPoint then
        pcall(function() ActiveDeliveryPoint:remove() end)
    end

    local destCoords = vector3(deliveryCoords.x, deliveryCoords.y, deliveryCoords.z)
    local destH = (type(deliveryCoords) == 'vector4' and deliveryCoords.w) or (ActiveJob and ActiveJob.deliveryCoords and type(ActiveJob.deliveryCoords) == 'vector4' and ActiveJob.deliveryCoords.w) or 0.0
    local currentDeliveryTextUi = nil
    local isUnloading = false

    ActiveDeliveryPoint = lib.points.new({
        coords = destCoords,
        distance = 60.0,
        onExit = function()
            if currentDeliveryTextUi then
                lib.hideTextUI()
                currentDeliveryTextUi = nil
            end
        end,
        nearby = function(self)
            if CurrentStage ~= 'STEP_8_IN_TRANSIT' or isUnloading then return end
            local ped = cache.ped or PlayerPedId()
            local veh = cache.vehicle or GetVehiclePedIsIn(ped, false)
            local tk = JobEntities.truck
            local tr = JobEntities.trailer

            local refEntity = (veh ~= 0) and veh or (tk and DoesEntityExist(tk) and tk) or ped
            local trOrVeh = (tr and DoesEntityExist(tr)) and tr or refEntity
            local trCoords = GetEntityCoords(trOrVeh)
            local dist = #(trCoords - destCoords)

            local vehH = (veh ~= 0) and GetEntityHeading(veh) or (tk and DoesEntityExist(tk) and GetEntityHeading(tk)) or GetEntityHeading(ped)
            local trH = (tr and DoesEntityExist(tr)) and GetEntityHeading(tr) or vehH
            local isAttached = (not tr or not DoesEntityExist(tr)) or (veh ~= 0 and (IsEntityAttachedToEntity(veh, tr) or IsVehicleAttachedToTrailer(veh)))

            local vehDiff = math.abs((vehH - destH + 180) % 360 - 180)
            local trDiff = math.abs((trH - destH + 180) % 360 - 180)
            local isAligned = (vehDiff <= 20.0 or math.abs(vehDiff - 180) <= 20.0) and (trDiff <= 20.0 or math.abs(trDiff - 180) <= 20.0) and isAttached

            local markerZ = destCoords.z - 0.45
            local foundGround, groundZ = GetGroundZFor_3dCoord(destCoords.x, destCoords.y, destCoords.z + 2.0, false)
            if foundGround and groundZ > 0.0 then
                markerZ = groundZ + 0.05
            end

            if dist <= 4.5 and isAligned then
                -- Vaga Verde Alinhada (Padrão LC Truck Logistics / Lixeiro Charmoso)
                DrawMarker(30, destCoords.x, destCoords.y, markerZ, 0.0, 0.0, 0.0, 90.0, destH, 0.0, 3.0, 1.0, 10.0, 0, 255, 0, 50, 0, 0, 0, 0)
                if currentDeliveryTextUi ~= 'park' then
                    lib.showTextUI('[E] Estacionar e Descarregar Carga')
                    currentDeliveryTextUi = 'park'
                end

                if IsControlJustPressed(0, 38) then -- Tecla E
                    isUnloading = true
                    if currentDeliveryTextUi then
                        lib.hideTextUI()
                        currentDeliveryTextUi = nil
                    end

                    CurrentStage = 'STEP_9_DELIVERY'
                    SendNUIMessage({ action = 'gmeter_hide' })

                    local ok = lib.progressCircle({
                        duration = 5000,
                        position = 'bottom',
                        label = 'Descarregando mercadoria e finalizando serviço...',
                        canCancel = false,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
                    })

                    if ok then
                        self:remove()
                        ActiveDeliveryPoint = nil
                        ClearObjectiveMarkers(false)
                        TriggerServerEvent('aurp_trucker:server:completePolarixDelivery', jobId)
                    else
                        isUnloading = false
                    end
                end
            else
                -- Vaga Vermelha Não-Alinhada / Em Aproximação (Padrão LC Truck Logistics / Lixeiro Charmoso)
                DrawMarker(30, destCoords.x, destCoords.y, markerZ, 0.0, 0.0, 0.0, 90.0, destH, 0.0, 3.0, 1.0, 10.0, 255, 0, 0, 50, 0, 0, 0, 0)
                if dist <= 22.0 then
                    if currentDeliveryTextUi ~= 'align' then
                        lib.showTextUI('Alinhe o caminhão e o reboque na vaga demarcada')
                        currentDeliveryTextUi = 'align'
                    end
                else
                    if currentDeliveryTextUi then
                        lib.hideTextUI()
                        currentDeliveryTextUi = nil
                    end
                end
            end
        end
    })
end

-- =======================================================================
-- TRANSIÇÕES DA MÁQUINA DE ESTADOS: ETAPAS DO CAMINHÃO
-- =======================================================================

local function OnPlayerEnteredTruck(truck)
    -- Descongelamento imediato do caminhão e liberação de freios sempre que o jogador assumir a cabine
    FreezeEntityPosition(truck, false)
    SetVehicleHandbrake(truck, false)
    SetVehicleBrake(truck, false)
    JobEntities.truck = truck
    if lcActiveJob then lcActiveJob.truck = truck end

    -- Verifica se a carreta já se encontra acoplada na 5ª roda
    local hasTrailer, trailerEnt = GetVehicleTrailerVehicle(truck)
    if not hasTrailer or trailerEnt == 0 then
        hasTrailer = IsVehicleAttachedToTrailer(truck)
    end

    if hasTrailer then
        -- Carreta já acoplada: purga imediatamente qualquer marcador de carreta e descongela
        PurgeObjectiveMarkersAndWait(false)
        if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
            FreezeEntityPosition(JobEntities.trailer, false)
            SetVehicleHandbrake(JobEntities.trailer, false)
            SetVehicleBrake(JobEntities.trailer, false)
            local trBlip = GetBlipFromEntity(JobEntities.trailer)
            if trBlip and DoesBlipExist(trBlip) then RemoveBlip(trBlip) end
        end

        -- Se for carga pesada (contêiner)
        if ActiveJob and ActiveJob.cargoType == 'heavy' then
            local isContainerLoaded = false
            if JobEntities.container and DoesEntityExist(JobEntities.container) and JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                isContainerLoaded = IsEntityAttachedToEntity(JobEntities.container, JobEntities.trailer)
            end

            if isContainerLoaded then
                CurrentStage = 'STEP_8_IN_TRANSIT'
                SendMissionNotify('Central Logística', 'Conjunto acoplado com contêiner carregado! Inicie o trajeto até o destino.', 'success')
                if ActiveJob.deliveryCoords then
                    StartDeliveryRoute(ActiveJob.deliveryCoords, ActiveJob.jobId)
                end
            else
                -- Contêiner no pátio: avança para a operação do Reach Stacker
                CurrentStage = 'STEP_6_LOAD_CONTAINER'
                local containerList = (JobEntities.containers and #JobEntities.containers > 0 and JobEntities.containers) or (JobEntities.container and { JobEntities.container }) or {}
                if containerList[1] and DoesEntityExist(containerList[1]) then
                    UpdateMissionObjective('pallet', containerList[1], 'Contêiner Marítimo')
                end
                SendMissionNotify('Central Logística', 'Carreta engatada! Assuma o Reach Stacker no pátio para carregar o contêiner.', 'info')
            end
            return
        end

        -- Se for outra carga (ex: paletes)
        CurrentStage = 'STEP_5_ENTER_FORKLIFT'
        SendMissionNotify('Central Logística', 'Carreta engatada na 5ª roda! Prossiga para o carregamento dos paletes.', 'success')
        return
    end

    if CurrentStage ~= 'STEP_2_ENTER_TRUCK' then return end

    -- Transição Estrita: Purga todos os marcadores anteriores com trava síncrona antes de avançar
    PurgeObjectiveMarkersAndWait(false)

    CurrentStage = 'STEP_3_COUPLE_TRAILER'

    -- Garante colisão ativa e física dinâmica para acoplamento da 5ª roda
    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
        FreezeEntityPosition(JobEntities.trailer, false)
        SetEntityCollision(JobEntities.trailer, true, true)
        SetEntityCollision(truck, true, true)
    end

    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)

    -- Remove a seta do caminhão; seta verde flutuante passa para a carreta
    local trailerTarget = (JobEntities.trailer and DoesEntityExist(JobEntities.trailer) and JobEntities.trailer)
        or (ActiveJob and ActiveJob.trailerCoords)

    UpdateMissionObjective('trailer', trailerTarget, 'Carreta / Carga')

    SendMissionNotify('Central Logística', 'Dê marcha-ré e engate a carreta no caminhão.', 'info')

    -- Renderização da vaga zebrada DrawMarker 30 no pátio inicial (idêntico ao final da entrega)
    if TrailerBayWatcherPoint then pcall(function() TrailerBayWatcherPoint:remove() end) end
    local trCoord = (JobEntities.trailer and DoesEntityExist(JobEntities.trailer) and GetEntityCoords(JobEntities.trailer))
        or (ActiveJob and ActiveJob.trailerCoords and vector3(ActiveJob.trailerCoords.x, ActiveJob.trailerCoords.y, ActiveJob.trailerCoords.z))
        or vector3(1272.21, -3159.80, 4.90)

    local trHeading = (JobEntities.trailer and DoesEntityExist(JobEntities.trailer) and GetEntityHeading(JobEntities.trailer))
        or (ActiveJob and ActiveJob.trailerCoords and type(ActiveJob.trailerCoords) == 'vector4' and ActiveJob.trailerCoords.w)
        or 90.0

    TrailerBayWatcherPoint = lib.points.new({
        coords = trCoord,
        distance = 60.0,
        nearby = function(self)
            if CurrentStage ~= 'STEP_3_COUPLE_TRAILER' then return end
            local ped = cache.ped or PlayerPedId()
            local veh = cache.vehicle or GetVehiclePedIsIn(ped, false)
            local targetPos = self.coords
            local targetH = trHeading

            local trEnt = JobEntities.trailer
            if trEnt and DoesEntityExist(trEnt) then
                targetPos = GetEntityCoords(trEnt)
                targetH = GetEntityHeading(trEnt)
                self.coords = targetPos
            end

            local isAligned = false
            if veh ~= 0 then
                local vehH = GetEntityHeading(veh)
                -- Alinhamento de ré: a frente do caminhão aponta na direção oposta ao trailer (~180°)
                local diff = math.abs((vehH - targetH + 180) % 360 - 180)
                local reverseDiff = math.abs(diff - 180.0)
                isAligned = (reverseDiff <= 25.0) or (diff <= 25.0)
            end

            local markerZ = targetPos.z - 0.45
            local foundGround, groundZ = GetGroundZFor_3dCoord(targetPos.x, targetPos.y, targetPos.z + 2.0, false)
            if foundGround and groundZ > 0.0 then
                markerZ = groundZ + 0.05
            end

            if isAligned then
                -- Vaga Verde Alinhada de Ré (Padrão LC Truck Logistics)
                DrawMarker(30, targetPos.x, targetPos.y, markerZ, 0.0, 0.0, 0.0, 90.0, targetH, 0.0, 3.0, 1.0, 10.0, 0, 255, 0, 50, 0, 0, 0, 0)
            else
                -- Vaga Vermelha Não-Alinhada / Em Aproximação (Padrão LC Truck Logistics)
                DrawMarker(30, targetPos.x, targetPos.y, markerZ, 0.0, 0.0, 0.0, 90.0, targetH, 0.0, 3.0, 1.0, 10.0, 255, 0, 0, 50, 0, 0, 0, 0)
            end
        end
    })

    StartCouplingWatcher()
end

local function IsMissionTruck(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) or not ActiveJob then return false end
    if JobEntities.truck and DoesEntityExist(JobEntities.truck) and veh == JobEntities.truck then
        return true
    end
    if ActiveJob.truckNetId and ActiveJob.truckNetId ~= 0 then
        if NetworkDoesNetworkIdExist(ActiveJob.truckNetId) then
            local netVeh = NetworkGetEntityFromNetworkId(ActiveJob.truckNetId)
            if netVeh ~= 0 and DoesEntityExist(netVeh) and veh == netVeh then
                return true
            end
        end
        if NetworkGetEntityIsNetworked(veh) then
            local myNet = VehToNet(veh)
            if myNet and myNet ~= 0 and myNet == ActiveJob.truckNetId then
                return true
            end
        end
    end
    if ActiveJob.truckPlate and ActiveJob.truckPlate ~= '' then
        local vehPlate = GetVehicleNumberPlateText(veh)
        if vehPlate then
            local cleanVeh = string.gsub(vehPlate, "%s+", ""):upper()
            local cleanTarget = string.gsub(ActiveJob.truckPlate, "%s+", ""):upper()
            if cleanVeh == cleanTarget then
                return true
            end
        end
    end
    return false
end

local function StartTruckEnterWatcher(truck)
    CreateThread(function()
        while CurrentStage == 'STEP_2_ENTER_TRUCK' and ActiveJob do
            Wait(250)
            local ped = cache.ped or PlayerPedId()
            local veh = cache.vehicle or GetVehiclePedIsIn(ped, false)

            if veh ~= 0 and DoesEntityExist(veh) and IsMissionTruck(veh) then
                local seat = GetPedInVehicleSeat(veh, -1)
                if seat == ped or seat == cache.ped or seat == 0 or GetVehiclePedIsIn(ped, false) == veh then
                    if seat ~= ped and seat ~= cache.ped and GetVehiclePedIsIn(ped, false) == veh then
                        SetPedIntoVehicle(ped, veh, -1)
                    end
                    JobEntities.truck = veh
                    if lcActiveJob then lcActiveJob.truck = veh end
                    OnPlayerEnteredTruck(veh)
                    break
                end
            end
        end
    end)
end

local function TriggerKeyfobChirp(veh)
    if not veh or not DoesEntityExist(veh) then return end
    CreateThread(function()
        for i = 1, 2 do
            pcall(function()
                SetVehicleIndicatorLights(veh, 0, true)
                SetVehicleIndicatorLights(veh, 1, true)
                SetVehicleLights(veh, 2)
                StartVehicleHorn(veh, 140, "HELDDOWN", false)
            end)
            Wait(140)
            pcall(function()
                SetVehicleIndicatorLights(veh, 0, false)
                SetVehicleIndicatorLights(veh, 1, false)
                SetVehicleLights(veh, 0)
            end)
            if i == 1 then
                Wait(140)
            end
        end
    end)
end
_G.TriggerKeyfobChirp = TriggerKeyfobChirp

local function StartMissionStep1(truck, trailer, forklift)
    CurrentStage = 'STEP_2_ENTER_TRUCK'

    -- Sincroniza ecossistema legado/NUI e HUD de telemetria
    if ActiveJob then
        lcActiveJob = {
            jobId = ActiveJob.jobId,
            truck = truck,
            trailer = trailer,
            cargoName = ActiveJob.cargoName,
            payment = ActiveJob.payment,
            stage = 'STEP_2_ENTER_TRUCK',
            deliveryCoords = ActiveJob.deliveryCoords
        }
        TriggerEvent('aurp_trucker:client:hudJobStarted')
        SendNUIMessage({ action = 'updateActiveJob', activeJob = lcActiveJob })
    end

    -- 1. Criação do blip e rota no GPS direcionando para o caminhão (Heavy RP: sem marcador 3D flutuante)
    local truckTarget = (truck and DoesEntityExist(truck) and truck) or (ActiveJob and ActiveJob.truckCoords)
    UpdateMissionObjective('truck', truckTarget, 'Seu Caminhão')

    -- Blip secundário da carreta/carga (apenas se a carreta NÃO estiver acoplada)
    local isAttached = false
    if truck and DoesEntityExist(truck) then
        local hasTr, trEnt = GetVehicleTrailerVehicle(truck)
        isAttached = (hasTr and trEnt ~= 0) or IsVehicleAttachedToTrailer(truck)
    end

    local trailerTarget = (trailer and DoesEntityExist(trailer) and trailer) or (ActiveJob and ActiveJob.trailerCoords)
    if trailerTarget and not isAttached then
        UpdateMissionObjective('trailer', trailerTarget, 'Carreta / Carga', true)
    end

    if ActiveJob and ActiveJob.cargoType == 'heavy' then
        local handlerTarget = (JobEntities.handler and DoesEntityExist(JobEntities.handler) and JobEntities.handler) or (ActiveJob.handlerCoords)
        if handlerTarget then
            UpdateMissionObjective('forklift', handlerTarget, 'Reach Stacker', true)
        end
        SendMissionNotify('Central Logística', 'Carga Pesada: Você pode carregar o contêiner com o Reach Stacker no pátio ou engatar a carreta primeiro.', 'info')
    end

    -- 3. Notificação diegética: se o caminhão já estiver materializado com placa, notifica a placa.
    -- Caso contrário, a notificação com a placa designada será disparada assim que a entidade for resolvida na rede.
    if truck and DoesEntityExist(truck) then
        local livePlate = GetVehicleNumberPlateText(truck)
        if (not livePlate or livePlate == '') and ActiveJob and ActiveJob.truckPlate then
            livePlate = ActiveJob.truckPlate
        end
        livePlate = string.gsub(livePlate or '', "^%s*(.-)%s*$", "%1")
        if livePlate ~= '' then
            SendMissionNotify('Central Logística', ('Veículo liberado no pátio. Placa designada: %s'):format(livePlate), 'info')
        end
    end

    -- 4. Inicia watcher contínuo à prova de falhas de assento
    StartTruckEnterWatcher(truck)

    -- 5. Verificação imediata caso o jogador já esteja dentro do veículo
    local ped = cache.ped or PlayerPedId()
    local currentVeh = GetVehiclePedIsIn(ped, false)
    if currentVeh ~= 0 and IsMissionTruck(currentVeh) then
        JobEntities.truck = currentVeh
        if lcActiveJob then lcActiveJob.truck = currentVeh end
        OnPlayerEnteredTruck(currentVeh)
    end
end

-- =======================================================================
-- MONITORAMENTO REATIVO DE VEÍCULOS (OX_LIB CACHE)
-- =======================================================================

lib.onCache('vehicle', function(veh)
    if not ActiveJob or not veh or veh == 0 then return end

    -- ETAPA 2: ENTRAR NO CAMINHÃO
    if CurrentStage == 'STEP_2_ENTER_TRUCK' then
        if IsMissionTruck(veh) then
            local ped = cache.ped or PlayerPedId()
            local pedSeat = GetPedInVehicleSeat(veh, -1)
            if pedSeat == ped or GetVehiclePedIsIn(ped, false) == veh then
                JobEntities.truck = veh
                if lcActiveJob then lcActiveJob.truck = veh end
                OnPlayerEnteredTruck(veh)
            end
        end
    end

    -- ETAPA 5 & 6: OPERAÇÃO COM EMPILHADEIRA E TECLA 'G'
    if CurrentStage == 'STEP_5_ENTER_FORKLIFT' then
        if JobEntities.forklift and veh == JobEntities.forklift then
            CurrentStage = 'STEP_6_LOAD_PALLETS'
            ForkliftLoadedOnTrailer = false

            -- Garante física e colisão ativa mútua e com o mundo na empilhadeira e no trailer
            if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                SetEntityCollision(JobEntities.trailer, true, true)
                SetCanClimbOnEntity(JobEntities.trailer, true)
            end
            if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
                SetEntityCollision(JobEntities.forklift, true, true)
                SetCanClimbOnEntity(JobEntities.forklift, true)
            end

            -- Ao entrar na empilhadeira, a seta passa para os pallets no pátio
            local firstPallet = GetNextAvailablePallet()
            if firstPallet then
                UpdateMissionObjective('pallet', firstPallet, 'Pallet de Carga')
            end

            SendMissionNotify('Central Logística', 'Encaixe os garfos sob o palete e erga a carga (Shift / NumPad 5) para travar.', 'info')

            -- Inicia ciclo de manuseio puramente baseado em física
            ForkliftModule.StartOperation(ActiveJob.jobId, JobEntities.trailer, ActiveJob.requiredCount or 4, function(action, palletEnt, loaded, total, stowedSlot, slotOffset, slotHeading)
                if action == 'picked' then
                    -- Com o pallet carregado, a seta aponta para o interior/traseira da carreta
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        local rearCoords = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)
                        UpdateMissionObjective('trailer_rear', rearCoords, 'Alinhe a carga sobre o holograma e baixe os garfos')
                    end
                elseif action == 'dropped' then
                    -- Registra o palete carregado com os dados exatos do slot para a amarração individual
                    local sOffset = slotOffset
                    local sRot = slotHeading
                    if not sOffset and ForkliftModule.GetSlotOffset then
                        local defOff, defHead = ForkliftModule.GetSlotOffset(JobEntities.trailer, stowedSlot or loaded)
                        sOffset = defOff
                        sRot = defHead
                    end
                    local finalPos = type(sOffset) == 'vector3' and sOffset or vector3(
                        (type(sOffset) == 'table' and sOffset.x) or 0.0,
                        (type(sOffset) == 'table' and sOffset.y) or 0.0,
                        (type(sOffset) == 'table' and sOffset.z) or 0.35
                    )

                    local pPitch = (type(sOffset) == 'table' and sOffset.rot_pitch) or 0.0
                    local pRoll = (type(sOffset) == 'table' and sOffset.rot_roll) or 0.0
                    local pYaw = (type(sOffset) == 'table' and (sOffset.rot_yaw or sOffset.heading)) or tonumber(sRot) or 0.0
                    local finalRot = (type(sRot) == 'vector3' and sRot) or vector3(pPitch, pRoll, pYaw)

                    table.insert(LoadedPallets, {
                        entity = palletEnt,
                        isSecured = false,
                        riskLevel = 0,
                        lost = false,
                        slotIndex = stowedSlot or loaded,
                        relOffset = finalPos,
                        relHeading = finalRot.z,
                        relRot = finalRot
                    })

                    if loaded < total then
                        -- Pallet acomodado: seta volta a apontar para o próximo pallet
                        local nextP = GetNextAvailablePallet()
                        if nextP then
                            UpdateMissionObjective('pallet', nextP, ('Próximo Pallet de Carga (%d/%d)'):format(loaded + 1, total))
                        end
                    else
                        -- ÚLTIMO PALETE ACOMODADO: O jogador deve IMEDIATAMENTE adicionar a forklift no trailer
                        local hasFork = (ActiveJob and ActiveJob.withForklift) or (JobEntities.forklift and DoesEntityExist(JobEntities.forklift))
                        if hasFork and JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                            local fOffset = ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(JobEntities.trailer) or { x = 0.0, y = -6.0, z = 0.35 }
                            local dockWorldPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, fOffset.x or 0.0, fOffset.y or -6.0, (fOffset.z or 0.35) + 0.6)
                            UpdateMissionObjective('forklift_dock', dockWorldPos, 'Embarcar Empilhadeira no Reboque [E]')
                            SendMissionNotify('Central Logística', 'Último palete estivado! Posicione a empilhadeira na traseira da carreta sobre o holograma e aperte [E] para embarcar.', 'info')
                        end
                    end
                end
            end, function()
                -- Empilhadeira embarcada (ou paletes finalizados sem empilhadeira): inicia a lógica das cordas
                ForkliftModule.StopOperation()
                SetupRopesStage()
            end, hasFork)
        end
    end

    -- ETAPA 5 & 6: OPERAÇÃO COM REACH STACKER (CARGA PESADA / CONTÊINER)
    local isHandlerModel = (GetEntityModel(veh) == joaat(Config.Polarix.Handler.VehicleModel or 'handler'))
    local isHandler = (JobEntities.handler and veh == JobEntities.handler) or isHandlerModel
    if ActiveJob and ActiveJob.cargoType == 'heavy' and isHandler and CurrentStage ~= 'STEP_8_IN_TRANSIT' and CurrentStage ~= 'STEP_9_DELIVERY' then
        if CurrentStage ~= 'STEP_6_LOAD_CONTAINER' then
            CurrentStage = 'STEP_6_LOAD_CONTAINER'

            local containerList = (JobEntities.containers and #JobEntities.containers > 0 and JobEntities.containers) or (JobEntities.container and { JobEntities.container }) or {}
            local reqCount = (ActiveJob and ActiveJob.requiredCount) or #containerList or 1

            if containerList[1] and DoesEntityExist(containerList[1]) then
                UpdateMissionObjective('pallet', containerList[1], 'Contêiner Marítimo')
            end

            SendMissionNotify('Central Logística', 'Opere o Reach Stacker! Aproxime o spreader do contêiner e aperte [G] para travar.', 'info')

            ReachStackerModule.StartOperation(ActiveJob.jobId, JobEntities.trailer, function(action, cEnt, curLoaded, totalExp)
                if action == 'picked' then
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        local trailerPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, 0.0, 1.0)
                        UpdateMissionObjective('trailer_rear', trailerPos, 'Posicione sobre a prancha e aperte [G]')
                    end
                elseif action == 'dropped_partial' then
                    SendMissionNotify('Central Logística', ('Contêiner %d/%d acoplado! Busque o próximo contêiner no pátio.'):format(curLoaded or 1, totalExp or 2), 'info')
                    local nextCont = ReachStackerModule.GetNearestGroundContainer(JobEntities.handler)
                    if nextCont and DoesEntityExist(nextCont) then
                        UpdateMissionObjective('pallet', nextCont, 'Próximo Contêiner')
                    end
                elseif action == 'dropped' then
                    PurgeObjectiveMarkersAndWait(false)
                    local isCoupled = false
                    if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
                        local hasTr, trEnt = GetVehicleTrailerVehicle(JobEntities.truck)
                        isCoupled = (hasTr and trEnt ~= 0) or IsVehicleAttachedToTrailer(JobEntities.truck)
                    end

                    if isCoupled then
                        CurrentStage = 'STEP_8_IN_TRANSIT'
                        UpdateMissionObjective('truck', JobEntities.truck, 'Seu Caminhão')
                        SendMissionNotify('Central Logística', 'Todos os contêineres fixados com sucesso! Entre no caminhão para iniciar a rota.', 'success')
                        if ActiveJob.deliveryCoords then
                            StartDeliveryRoute(ActiveJob.deliveryCoords, ActiveJob.jobId)
                        end
                    else
                        CurrentStage = 'STEP_2_ENTER_TRUCK'
                        UpdateMissionObjective('truck', JobEntities.truck, 'Seu Caminhão')
                        SendMissionNotify('Central Logística', 'Contêiner travado no chassis! Entre no caminhão e engate a carreta.', 'success')
                        StartTruckEnterWatcher(JobEntities.truck)
                    end
                end
            end, function()
                PurgeObjectiveMarkersAndWait(false)
            end, containerList, reqCount)
        end
    end

    if IsMissionTruck(veh) then
        local ped = cache.ped or PlayerPedId()
        if GetPedInVehicleSeat(veh, -1) == ped then
            FreezeEntityPosition(veh, false)
            SetVehicleHandbrake(veh, false)
            SetVehicleBrake(veh, false)
            JobEntities.truck = veh
            if lcActiveJob then lcActiveJob.truck = veh end
            local trEnt = JobEntities.trailer or GetVehicleTrailerVehicle(veh)
            if trEnt and trEnt ~= 0 and DoesEntityExist(trEnt) then
                FreezeEntityPosition(trEnt, false)
                SetVehicleHandbrake(trEnt, false)
                SetVehicleBrake(trEnt, false)
            end
        end
    end

    if CurrentStage == 'STEP_8_IN_TRANSIT' and IsMissionTruck(veh) then
        JobEntities.truck = veh
        if lcActiveJob then lcActiveJob.truck = veh end
        if ActiveJob and ActiveJob.deliveryCoords and not ActiveDeliveryPoint then
            StartDeliveryRoute(ActiveJob.deliveryCoords, ActiveJob.jobId)
        end
    end
end)

lib.onCache('seat', function(seat)
    if not ActiveJob or seat ~= -1 then return end
    local veh = cache.vehicle
    if veh and veh ~= 0 and IsMissionTruck(veh) then
        FreezeEntityPosition(veh, false)
        SetVehicleHandbrake(veh, false)
        SetVehicleBrake(veh, false)
        JobEntities.truck = veh
        if lcActiveJob then lcActiveJob.truck = veh end
        local trEnt = JobEntities.trailer or GetVehicleTrailerVehicle(veh)
        if trEnt and trEnt ~= 0 and DoesEntityExist(trEnt) then
            FreezeEntityPosition(trEnt, false)
            SetVehicleHandbrake(trEnt, false)
            SetVehicleBrake(trEnt, false)
        end
        if CurrentStage == 'STEP_2_ENTER_TRUCK' or CurrentStage == 'STEP_3_COUPLE_TRAILER' then
            OnPlayerEnteredTruck(veh)
        end
    end
end)

-- =======================================================================
-- EVENTOS DE REDE: INICIALIZAÇÃO E TRANSIÇÕES AUTORITATIVAS
-- =======================================================================

-- ETAPA 1: INÍCIO E SPAWN DINÂMICO
RegisterNetEvent('aurp_trucker:client:polarixJobStarted', function(payload)
    if Config.Debug then print(("^2[AUST_Trucker DEBUG - ETAPA 4] aurp_trucker:client:polarixJobStarted recebido com sucesso no Cliente! JobID: %s, TruckNetId: %s, TrailerNetId: %s, Cargo: %s^7"):format(
        tostring(payload and payload.jobId),
        tostring(payload and payload.truckNetId),
        tostring(payload and payload.trailerNetId),
        tostring(payload and payload.cargoType)
    )) end

    CleanupCurrentJob()
    ActiveJob = payload
    _G.ActiveJob = payload
    CurrentStage = 'STEP_1_START'

    -- Prevenção de Deadlock: se não houver empilhadeira contratada, inicia como concluída
    local hasFork = payload and payload.withForklift and (payload.forkliftNetId and payload.forkliftNetId ~= 0)
    ForkliftSecured = not hasFork
    ForkliftLoadedOnTrailer = false
    ForkliftRiskLevel = 0

    -- Runtime Synchronization: Sobrescreve os offsets em memória com os dados mais recentes do banco
    if payload and payload.trailerOffsets then
        pcall(function()
            for mKey, data in pairs(payload.trailerOffsets) do
                if mKey ~= '_specific' and type(data) == 'table' then
                    local numKey = tonumber(mKey)
                    local h = numKey or joaat(tostring(mKey):lower())
                    if not Config.TrailerSlots[h] then Config.TrailerSlots[h] = { pallets = {}, forklift = nil } end
                    if not Config.TrailerSlots[mKey] then Config.TrailerSlots[mKey] = { pallets = {}, forklift = nil } end
                    if numKey and not Config.TrailerSlots[numKey] then Config.TrailerSlots[numKey] = { pallets = {}, forklift = nil } end
                    for idx, v in pairs(data.pallets or {}) do
                        local sIdx = tonumber(idx)
                        if sIdx and v then
                            local slotEntry = {
                                id = v.id,
                                label = v.label,
                                prop_model = v.prop_model,
                                x = tonumber(v.x) or 0.0,
                                y = tonumber(v.y) or 0.0,
                                z = tonumber(v.z) or 0.0,
                                heading = tonumber(v.heading) or 0.0,
                                rot_pitch = tonumber(v.rot_pitch) or 0.0,
                                rot_roll = tonumber(v.rot_roll) or 0.0,
                                rot_yaw = tonumber(v.rot_yaw) or tonumber(v.heading) or 0.0,
                                straps = v.straps
                            }
                            Config.TrailerSlots[h].pallets[sIdx] = slotEntry
                            Config.TrailerSlots[mKey].pallets[sIdx] = slotEntry
                            if numKey then Config.TrailerSlots[numKey].pallets[sIdx] = slotEntry end
                        end
                    end
                    if data.forklift then
                        local slotEntry = {
                            id = data.forklift.id,
                            label = data.forklift.label,
                            prop_model = data.forklift.prop_model or 'forklift',
                            x = tonumber(data.forklift.x) or 0.0,
                            y = tonumber(data.forklift.y) or 0.0,
                            z = tonumber(data.forklift.z) or 0.0,
                            heading = tonumber(data.forklift.heading) or 0.0
                        }
                        Config.TrailerSlots[h].forklift = slotEntry
                        Config.TrailerSlots[mKey].forklift = slotEntry
                        if numKey then Config.TrailerSlots[numKey].forklift = slotEntry end
                    end
                end
            end
        end)
    end

    -- 1. Inicialização imediata e síncrona dos objetivos e GPS (Zero latência, sem bloqueios OneSync)
    StartMissionStep1(nil, nil, nil)

    CreateThread(function()
        -- Pré-carregamento assíncrono e protegido do modelo de prop herdado da pasta
        CreateThread(function()
            if payload and payload.cargoModel then
                pcall(function()
                    local cHash = type(payload.cargoModel) == 'number' and payload.cargoModel or joaat(payload.cargoModel)
                    if IsModelInCdimage(cHash) or IsModelValid(cHash) then RequestModel(cHash) end
                end)
            end
            local palletProps = Config.PalletProps or (Config.Polarix and Config.Polarix.PalletModels) or {}
            for _, modelName in ipairs(palletProps) do
                pcall(function()
                    local hash = joaat(modelName)
                    if IsModelInCdimage(hash) or IsModelValid(hash) then
                        RequestModel(hash)
                    end
                end)
            end
            pcall(function()
                local cHash = joaat(Config.Polarix.ContainerModel or 'prop_contr_03b_ld')
                if IsModelInCdimage(cHash) or IsModelValid(cHash) then RequestModel(cHash) end
            end)
        end)

        -- 2. Resolução progressiva e não-bloqueante dos veículos primários (Caminhão e Carreta)
        CreateThread(function()
            local truck = WaitForNetworkEntity(payload.truckNetId, 8000)
            local trailer = WaitForNetworkEntity(payload.trailerNetId, 8000)

            if not truck or not DoesEntityExist(truck) then
                if payload.truckNetId and NetworkDoesEntityExistWithNetworkId(payload.truckNetId) then
                    local ent = NetworkGetEntityFromNetworkId(payload.truckNetId)
                    if ent ~= 0 and DoesEntityExist(ent) then truck = ent end
                end
            end

            if not trailer or not DoesEntityExist(trailer) then
                if payload.trailerNetId and NetworkDoesEntityExistWithNetworkId(payload.trailerNetId) then
                    local ent = NetworkGetEntityFromNetworkId(payload.trailerNetId)
                    if ent ~= 0 and DoesEntityExist(ent) then trailer = ent end
                end
            end

            print(("^2[AUST_Trucker] Entidades sincronizadas! JobID: %s | Truck: %s (NetId: %s) | Trailer: %s (NetId: %s)^7"):format(
                tostring(payload.jobId), tostring(truck), tostring(payload.truckNetId), tostring(trailer), tostring(payload.trailerNetId)
            ))

            local playerPed = cache.ped or PlayerPedId()
            SetEntityVisible(playerPed, true)
            ResetEntityAlpha(playerPed)

            if truck and DoesEntityExist(truck) then
                JobEntities.truck = truck
                if lcActiveJob then lcActiveJob.truck = truck end

                SetEntityVisible(truck, true)
                ResetEntityAlpha(truck)
                SetVehicleOnGroundProperly(truck)
                SetEntityCollision(truck, true, true)
                SetVehicleDoorsLocked(truck, 1)
                SetVehicleNeedsToBeHotwired(truck, false)
                SetVehicleHasBeenOwnedByPlayer(truck, true)

                local truckPlate = payload.truckPlate or GetVehicleNumberPlateText(truck)
                if truckPlate and truckPlate ~= '' then
                    SetVehicleNumberPlateText(truck, truckPlate)
                end

                -- Leitura Dinâmica da Placa e Identificação Diegética (Heavy RP)
                local livePlate = GetVehicleNumberPlateText(truck)
                if (not livePlate or livePlate == '') and truckPlate then
                    livePlate = truckPlate
                end
                livePlate = string.gsub(livePlate or '', "^%s*(.-)%s*$", "%1")

                if ActiveJob then
                    ActiveJob.truckPlate = livePlate
                end
                if lcActiveJob then
                    lcActiveJob.truckPlate = livePlate
                end

                -- Disparo da notificação diegética na tela com a placa gerada/atribuída
                SendMissionNotify('Central Logística', ('Veículo liberado no pátio. Placa designada: %s'):format(livePlate), 'info')

                -- Sincronização diegética com a NUI da HUD
                SendNUIMessage({
                    action = 'updateActiveJob',
                    activeJob = {
                        plate = livePlate,
                        truckPlate = livePlate
                    }
                })

                -- Feedback Diegético de Alarme e Chaveiro (apenas para veículos alugados/frota)
                if not payload.isOwned then
                    TriggerKeyfobChirp(truck)
                end

                if payload.truckMods then
                    local modsData = type(payload.truckMods) == 'string' and json.decode(payload.truckMods) or payload.truckMods
                    if modsData and type(modsData) == 'table' then
                        lib.setVehicleProperties(truck, modsData)
                    end
                end

                if exports.qbx_vehiclekeys then
                    pcall(function() exports.qbx_vehiclekeys:GiveKeys(truck) end)
                end
                if exports.ox_fuel then
                    pcall(function() exports.ox_fuel:SetFuel(truck, 100.0) end)
                end

                -- Atualiza alvo dinâmico para a entidade física assim que materializada
                if CurrentStage == 'STEP_2_ENTER_TRUCK' then
                    UpdateMissionObjective('truck', truck, 'Seu Caminhão')
                end
            end

            if trailer and DoesEntityExist(trailer) then
                JobEntities.trailer = trailer
                if lcActiveJob then lcActiveJob.trailer = trailer end

                SetEntityVisible(trailer, true)
                ResetEntityAlpha(trailer)

                -- Assentamento de Solo Autoritativo com física nativa de suspensão e pernas de apoio
                FreezeEntityPosition(trailer, false)
                SetEntityCollision(trailer, true, true)
                SetVehicleOnGroundProperly(trailer)
                pcall(function() SetTrailerLegsRaised(trailer, false) end)

                SetVehicleDoorsLocked(trailer, 1)
                SetVehicleDoorsLockedForAllPlayers(trailer, false)
                SetVehicleExplodesOnHighExplosionDamage(trailer, false)
                SetVehicleCanBeVisiblyDamaged(trailer, false)
                SetVehicleStrong(trailer, true)

                if payload and payload.cargoType == 'heavy' then
                    for extraId = 1, 14 do
                        if DoesExtraExist(trailer, extraId) then
                            SetVehicleExtra(trailer, extraId, 1)
                        end
                    end
                end

                local trModel = GetEntityModel(trailer)
                if trModel == joaat('freighttrailer') or (payload and payload.cargoType == 'heavy') then
                    CreateThread(function()
                        Wait(150)
                        if DoesEntityExist(trailer) then
                            SetVehicleOnGroundProperly(trailer)
                            pcall(function() SetTrailerLegsRaised(trailer, false) end)
                            FreezeEntityPosition(trailer, false)
                            -- Libera ativamente freios para permitir engate físico livre
                            SetVehicleBrake(trailer, false)
                            SetVehicleHandbrake(trailer, false)
                        end
                    end)
                end

                if CurrentStage == 'STEP_2_ENTER_TRUCK' then
                    local isAlreadyAttached = false
                    if truck and DoesEntityExist(truck) then
                        local hasTr, trEnt = GetVehicleTrailerVehicle(truck)
                        isAlreadyAttached = (hasTr and trEnt ~= 0) or IsVehicleAttachedToTrailer(truck)
                    end
                    if not isAlreadyAttached then
                        UpdateMissionObjective('trailer', trailer, 'Carreta / Carga', true)
                    end
                end
            end

            -- ACOPLAMENTO AUTOMÁTICO EM TRABALHOS RÁPIDOS (Diretriz do Usuário: Resiliente com Trava Condicional)
            if truck and DoesEntityExist(truck) and trailer and DoesEntityExist(trailer) then
                local isQuickJobPallets = (payload and payload.cargoType == 'dry' and not payload.isOwned)
                local isQuickJobFreight = (payload and not payload.isOwned and (GetEntityModel(trailer) == joaat('freighttrailer') or payload.cargoType == 'heavy'))
                if isQuickJobPallets or isQuickJobFreight then
                    CreateThread(function()
                        Wait(350) -- Aguarda estabilização física do spawn OneSync
                        if not DoesEntityExist(truck) or not DoesEntityExist(trailer) then return end

                        SetVehicleHandbrake(trailer, false)
                        SetVehicleBrake(trailer, false)
                        SetVehicleHandbrake(truck, false)
                        SetVehicleBrake(truck, false)
                        FreezeEntityPosition(truck, false)
                        FreezeEntityPosition(trailer, false)

                        -- Laço de acoplamento de até 5 segundos (10 tentativas de 500ms) com raio estendido
                        local trkAttached = false
                        local attempts = 0
                        local attachRadius = (GetEntityModel(trailer) == joaat('freighttrailer')) and 7.5 or 6.5

                        while attempts < 10 and not trkAttached do
                            attempts = attempts + 1
                            AttachVehicleToTrailer(truck, trailer, attachRadius)
                            Wait(250)
                            local hasTrailer, trailerEnt = GetVehicleTrailerVehicle(truck)
                            if (hasTrailer and trailerEnt ~= 0) or IsVehicleAttachedToTrailer(truck) then
                                trkAttached = true
                                break
                            end
                            Wait(250)
                        end

                        if trkAttached then
                            ClearObjectiveMarkers(false)
                            local isHeavy = (payload and payload.cargoType == 'heavy')

                            if isHeavy then
                                -- Carga pesada (contêiner): caminhão livre para manobrar no pátio sem nenhum freeze
                                FreezeEntityPosition(truck, false)
                                FreezeEntityPosition(trailer, false)
                                SetVehicleHandbrake(truck, false)
                                SetVehicleHandbrake(trailer, false)
                                CurrentStage = 'STEP_6_LOAD_CONTAINER'

                                CreateThread(function()
                                    local wTimer = 0
                                    while (not JobEntities.handler or not DoesEntityExist(JobEntities.handler)) and wTimer < 4000 do
                                        Wait(100)
                                        wTimer = wTimer + 100
                                    end
                                    if JobEntities.handler and DoesEntityExist(JobEntities.handler) then
                                        UpdateMissionObjective('forklift', JobEntities.handler, 'Reach Stacker')
                                    end
                                end)

                                PlaySoundFrontend(-1, "PIN_BUTTON", "ATM_SOUNDS", true)
                                SendMissionNotify('Central Logística', 'Caminhão e carreta acoplados no pátio! Assuma o Reach Stacker para carregar o contêiner.', 'success')
                            else
                                -- Carga de paletes: congelamento preventivo na baia durante o carregamento com empilhadeira
                                FreezeEntityPosition(truck, true)
                                FreezeEntityPosition(trailer, true)
                                CurrentStage = 'STEP_5_ENTER_FORKLIFT'

                                CreateThread(function()
                                    local wTimer = 0
                                    while (not JobEntities.forklift or not DoesEntityExist(JobEntities.forklift)) and wTimer < 4000 do
                                        Wait(100)
                                        wTimer = wTimer + 100
                                    end
                                    if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
                                        UpdateMissionObjective('forklift', JobEntities.forklift, 'Empilhadeira de Carregamento')
                                    end
                                end)

                                PlaySoundFrontend(-1, "PIN_BUTTON", "ATM_SOUNDS", true)
                                SendMissionNotify('Central Logística', 'Caminhão e carreta acoplados no pátio! Assuma a empilhadeira para iniciar o carregamento dos paletes.', 'success')
                            end
                        else
                            -- Se o acoplamento automático não engatar em 5s, mantém descongelado para o jogador manobrar manualmente
                            FreezeEntityPosition(truck, false)
                            FreezeEntityPosition(trailer, false)
                            SetVehicleHandbrake(trailer, false)
                            SetVehicleBrake(trailer, false)
                            if Config.Debug then
                                print('^3[AUST_Trucker] Auto-couple atingiu timeout de 5s; veículos liberados para alinhamento manual.^7')
                            end
                        end
                    end)
                end
            end
        end)

        -- 3. Resolução assíncrona não-bloqueante de maquinário secundário (Empilhadeira, Handler, Contêiner)
        CreateThread(function()
            if payload.forkliftNetId and payload.forkliftNetId ~= 0 then
                local forklift = WaitForNetworkEntity(payload.forkliftNetId, 5000)
                if forklift and DoesEntityExist(forklift) then
                    JobEntities.forklift = forklift
                    SetEntityVisible(forklift, true)
                    ResetEntityAlpha(forklift)
                    SetVehicleOnGroundProperly(forklift)
                    SetEntityCollision(forklift, true, true)
                    SetVehicleDoorsLocked(forklift, 1)
                    SetVehicleDoorsLockedForAllPlayers(forklift, false)
                    SetVehicleNeedsToBeHotwired(forklift, false)
                    if exports.qbx_vehiclekeys then
                        pcall(function() exports.qbx_vehiclekeys:GiveKeys(forklift) end)
                    end
                end
            end

            if payload.handlerNetId and payload.handlerNetId ~= 0 then
                local handler = WaitForNetworkEntity(payload.handlerNetId, 5000)
                if handler and DoesEntityExist(handler) then
                    JobEntities.handler = handler
                    SetEntityVisible(handler, true)
                    ResetEntityAlpha(handler)
                    SetVehicleOnGroundProperly(handler)
                    SetEntityCollision(handler, true, true)
                    SetVehicleDoorsLocked(handler, 1)
                    SetVehicleDoorsLockedForAllPlayers(handler, false)
                    SetVehicleNeedsToBeHotwired(handler, false)
                    if exports.qbx_vehiclekeys then
                        pcall(function() exports.qbx_vehiclekeys:GiveKeys(handler) end)
                    end
                end
            end

            JobEntities.containers = {}
            if payload.containerNetIds and #payload.containerNetIds > 0 then
                for _, cNet in ipairs(payload.containerNetIds) do
                    local cEnt = WaitForNetworkEntity(cNet, 5000)
                    if cEnt and DoesEntityExist(cEnt) then
                        table.insert(JobEntities.containers, cEnt)
                        SetEntityVisible(cEnt, true)
                        ResetEntityAlpha(cEnt)
                        PlaceObjectOnGroundProperly(cEnt)
                        SetEntityCollision(cEnt, true, true)
                        FreezeEntityPosition(cEnt, true)
                    end
                end
                if #JobEntities.containers > 0 then
                    JobEntities.container = JobEntities.containers[1]
                end
            elseif payload.containerNetId and payload.containerNetId ~= 0 then
                local container = WaitForNetworkEntity(payload.containerNetId, 5000)
                if container and DoesEntityExist(container) then
                    JobEntities.container = container
                    JobEntities.containers = { container }
                    SetEntityVisible(container, true)
                    ResetEntityAlpha(container)
                    PlaceObjectOnGroundProperly(container)
                    SetEntityCollision(container, true, true)
                    FreezeEntityPosition(container, true)
                end
            end
        end)
    end)
end)

-- Guarda de idempotência de sincronização de paletes (Cliente)
local PalletSyncState = { jobId = nil, claimed = {}, ents = {} }
local PalletSyncGuard = {
    Begin = function(state, jId)
        if state.jobId ~= jId then
            state.jobId = jId
            state.claimed = {}
            state.ents = {}
        end
    end,
    Claim = function(state, netId)
        if state.claimed[netId] then return false end
        state.claimed[netId] = true
        return true
    end,
    Release = function(state, netId)
        state.claimed[netId] = nil
    end,
    Reset = function(state)
        state.jobId = nil
        state.claimed = {}
        state.ents = {}
    end
}

-- Sincronização dos Paletes e Garantia de Física Dinâmica Nativa (Sem Limbo / Ancoragem Segura de Solo)
RegisterNetEvent('aurp_trucker:client:polarixSyncPallets', function(palletNetIds, jobId)
    PalletSyncGuard.Begin(PalletSyncState, jobId)
    local safeNetIds = palletNetIds or {}
    CreateThread(function()
        local pallets = {}
        for _, netId in ipairs(safeNetIds) do
            if netId and netId ~= 0 then
                if not PalletSyncGuard.Claim(PalletSyncState, netId) then
                    local existingEnt = PalletSyncState.ents[netId]
                    if existingEnt and DoesEntityExist(existingEnt) then
                        table.insert(pallets, existingEnt)
                    end
                else
                    -- Processamento paralelo e atômico para cada palete (evita que o loop sequencial atrase os demais)
                    CreateThread(function()
                        local ent = WaitForNetworkEntity(netId, 8000)
                        if ent and DoesEntityExist(ent) then
                            SetEntityAsMissionEntity(ent, true, true)
                            SetEntityLodDist(ent, 0xFFFF)
                            SetEntityVisible(ent, true)
                            ResetEntityAlpha(ent)
                            DisableCamCollisionForEntity(ent)
                            SetEntityInvincible(ent, true)
                            SetEntityProofs(ent, true, true, true, true, true, true, true, true)
                            SetEntityCanBeDamaged(ent, false)

                            -- Garante controle autoritativo local no OneSync e permite migração para acoplamento
                            local ctrlTimeout = GetGameTimer() + 2000
                            while not NetworkHasControlOfEntity(ent) and GetGameTimer() < ctrlTimeout do
                                NetworkRequestControlOfEntity(ent)
                                Wait(50)
                            end
                            SetNetworkIdCanMigrate(netId, true)

                            -- 1. Ancoragem de segurança inicial
                            FreezeEntityPosition(ent, true)

                            local pCoords = GetEntityCoords(ent)
                            local baseSpawnZ = pCoords.z

                            -- 2. Pré-carrega colisão do terreno nas coordenadas do objeto
                            RequestCollisionAtCoord(pCoords.x, pCoords.y, pCoords.z)
                            local loadTimeout = GetGameTimer() + 3500
                            while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() < loadTimeout do
                                Wait(50)
                            end

                            -- Pausa para propagação de colisão do interior/MLO
                            Wait(200)

                            -- 3. ShapeTest / Raycast Vertical para baixo procurando piso sólido com tolerância
                            local groundZ = baseSpawnZ
                            local rayFound = false

                            local raycastStart = vector3(pCoords.x, pCoords.y, pCoords.z + 2.0)
                            local raycastEnd = vector3(pCoords.x, pCoords.y, pCoords.z - 5.0)
                            local rayHandle = StartShapeTestRay(raycastStart.x, raycastStart.y, raycastStart.z, raycastEnd.x, raycastEnd.y, raycastEnd.z, 1 | 16 | 32, ent, 7)
                            local _, hit, hitCoords = GetShapeTestResult(rayHandle)

                            if hit and hit ~= 0 and hitCoords.z > (baseSpawnZ - 4.0) then
                                groundZ = hitCoords.z
                                rayFound = true
                            else
                                local gFound, gz = GetGroundZFor_3dCoord(pCoords.x, pCoords.y, pCoords.z + 2.0, false)
                                if gFound and gz > (baseSpawnZ - 4.0) then
                                    groundZ = gz
                                    rayFound = true
                                end
                            end

                            -- Cálculo do offset vertical inferior da bounding box do modelo
                            local minDim, _ = GetModelDimensions(GetEntityModel(ent))
                            local bottomOffset = math.abs(minDim.z)
                            local finalRestZ = groundZ + bottomOffset + 0.03

                            if rayFound then
                                SetEntityCoordsNoOffset(ent, pCoords.x, pCoords.y, finalRestZ, false, false, false)
                            else
                                PlaceObjectOnGroundProperly(ent)
                                local curC = GetEntityCoords(ent)
                                finalRestZ = curC.z
                            end

                            -- 4. Estabilização e salvaguarda permanente em repouso:
                            -- O palete permanece com gravidade ativa e física sólida, segurado pelo Freeze no piso do MLO.
                            SetEntityCollision(ent, true, true)
                            SetCanClimbOnEntity(ent, true)
                            SetEntityHasGravity(ent, true)
                            FreezeEntityPosition(ent, true)
                            SetEntityVelocity(ent, 0.0, 0.0, 0.0)

                            PalletSyncState.ents[netId] = ent
                        else
                            PalletSyncGuard.Release(PalletSyncState, netId)
                        end
                    end)
                end
            end
        end

        -- Coleta entidades registradas com tolerância para abastecer o módulo da empilhadeira
        CreateThread(function()
            local waitTime = GetGameTimer() + 4000
            while GetGameTimer() < waitTime and #pallets < #safeNetIds do
                pallets = {}
                for _, netId in ipairs(safeNetIds) do
                    local ent = PalletSyncState.ents[netId]
                    if ent and DoesEntityExist(ent) then table.insert(pallets, ent) end
                end
                Wait(200)
            end
            JobEntities.pallets = pallets
            ForkliftModule.SetMissionPallets(pallets)
        end)
    end)
end)

RegisterNetEvent('aurp_trucker:client:polarixReadyForTransit', function(deliveryCoords)
    if not ActiveJob then return end
    StartDeliveryRoute(deliveryCoords, ActiveJob.jobId)
end)

RegisterNetEvent('aurp_trucker:client:heavyContainerNextRequired', function(currentLoaded, reqCount)
    if not ActiveJob then return end
    SendMissionNotify('Central Logística', ('Contêiner %d/%d carregado. Busque o próximo no pátio!'):format(currentLoaded, reqCount), 'info')
end)

RegisterNetEvent('aurp_trucker:client:polarixJobFinished', function(summary)
    CleanupCurrentJob()
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    local feeNotice = (summary.unloadingFee and summary.unloadingFee > 0)
        and ('\nTaxa Descarregamento Doca: -$%d (sem empilhadeira)'):format(summary.unloadingFee)
        or ''

    if summary.isQuickJob and summary.repairCost and summary.repairCost > 0 then
        SendMissionNotify('Central Logística', ('Caminhão devolvido com avarias!\nCusto de Reparo: -$%d%s\nPagamento Final: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.repairCost,
            feeNotice,
            summary.payment or 0,
            summary.xp or 0
        ), 'warning')
    elseif summary.lostPallets and summary.lostPallets > 0 then
        SendMissionNotify('Central Logística', ('Entrega concluída com penalidade por carga perdida (%d paletes perdidos).%s\nPagamento: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.lostPallets,
            feeNotice,
            summary.payment or 0,
            summary.xp or 0
        ), 'warning')
    elseif summary.unloadingFee and summary.unloadingFee > 0 then
        SendMissionNotify('Central Logística', ('Entrega concluída!\nServiço de descarregamento na doca: -$%d\nPagamento Líquido: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.unloadingFee,
            summary.payment or 0,
            summary.xp or 0
        ), 'inform')
    else
        SendMissionNotify('Central Logística', ('Entrega concluída com sucesso!\nPagamento: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.payment or 0,
            summary.xp or 0
        ), 'success')
    end

    TriggerEvent('aurp_trucker:client:refreshNUI')
end)

-- FLUXO TRABALHO RÁPIDO: Carga descarregada, pagamento retido, rota de retorno para devolução
RegisterNetEvent('aurp_trucker:client:polarixCargoDeliveredReturnRequired', function(data)
    ClearObjectiveMarkers(false)
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)

    SendMissionNotify('Carga Entregue!', ('A carga foi descarregada com sucesso! Seu pagamento de $%d está retido.\nRetorne à Central de Logística e devolva o caminhão da empresa para receber.'):format(
        data.retainedPayment or 0
    ), 'inform')

    local returnCoords = data.returnCoords or vector4(1245.79, -3155.76, 4.6, 90.0)
    SetNewWaypoint(returnCoords.x, returnCoords.y)

    local retBlip = AddBlipForCoord(returnCoords.x, returnCoords.y, returnCoords.z)
    SetBlipSprite(retBlip, 357)
    SetBlipColour(retBlip, 5)
    SetBlipScale(retBlip, 0.95)
    SetBlipRoute(retBlip, true)
    SetBlipRouteColour(retBlip, 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Devolução: Central Logística")
    EndTextCommandSetBlipName(retBlip)

    CurrentStage = 'STEP_RETURN_TRUCK'

    CreateThread(function()
        local retX, retY, retZ = returnCoords.x, returnCoords.y, returnCoords.z
        local retTextUi = nil
        local returning = false
        local targetJobId = data.jobId

        while ActiveJob and ActiveJob.jobId == targetJobId and not returning do
            local sleep = 1000
            local ped = cache.ped or PlayerPedId()
            local currentVeh = GetVehiclePedIsIn(ped, false)
            local pCoords = GetEntityCoords(ped)
            local dist = #(pCoords - vector3(retX, retY, retZ))

            if dist <= 60.0 then
                sleep = 2
                DrawMarker(1, retX, retY, retZ - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 5.0, 1.2, 255, 180, 0, 140, false, false, 2, false, nil, nil, false)

                if dist <= 5.0 then
                    local isCompanyTruck = (currentVeh ~= 0) and (JobEntities.truck and currentVeh == JobEntities.truck or DoesEntityExist(JobEntities.truck))
                    if isCompanyTruck and currentVeh ~= 0 then
                        if retTextUi ~= 'return' then
                            lib.showTextUI('[E] Devolver Caminhão da Empresa e Receber Pagamento')
                            retTextUi = 'return'
                        end

                        if IsControlJustPressed(0, 38) then
                            returning = true
                            if retTextUi then
                                lib.hideTextUI()
                                retTextUi = nil
                            end

                            BringVehicleToHalt(currentVeh, 2.5, 1, false)
                            Wait(100)
                            DoScreenFadeOut(500)
                            Wait(500)

                            local engH = GetVehicleEngineHealth(currentVeh)
                            local bdyH = GetVehicleBodyHealth(currentVeh)
                            local burst = 0
                            for tIdx = 0, 7 do
                                if IsVehicleTyreBurst(currentVeh, tIdx, false) then
                                    burst = burst + 1
                                end
                            end

                            TaskLeaveVehicle(ped, currentVeh, 0)
                            Wait(250)

                            if DoesBlipExist(retBlip) then
                                RemoveBlip(retBlip)
                            end

                            TriggerServerEvent('aurp_trucker:server:returnQuickJobTruck', targetJobId, {
                                engineHealth = engH,
                                bodyHealth = bdyH,
                                burstTires = burst
                            })

                            Wait(600)
                            DoScreenFadeIn(800)
                            break
                        end
                    else
                        if retTextUi ~= 'not_truck' then
                            lib.showTextUI('Você deve estar no caminhão da empresa para devolver!')
                            retTextUi = 'not_truck'
                        end
                    end
                else
                    if retTextUi then
                        lib.hideTextUI()
                        retTextUi = nil
                    end
                end
            else
                if retTextUi then
                    lib.hideTextUI()
                    retTextUi = nil
                end
            end
            Wait(sleep)
        end

        if retTextUi then lib.hideTextUI() end
        if DoesBlipExist(retBlip) then RemoveBlip(retBlip) end
    end)
end)

-- =======================================================================
-- LIMPEZA SEGURA NO CLIENTE AO REINICIAR/PARAR O RESOURCE
-- PREVENÇÃO CONTRA CRASH: pennsylvania-oxygen-yankee (DLC_ITYP_REQUEST)
-- =======================================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    -- 1. Esconde qualquer TextUI ativa
    pcall(function() lib.hideTextUI() end)

    -- 2. Interrompe operação da empilhadeira
    if ForkliftModule and ForkliftModule.StopOperation then
        ForkliftModule.StopOperation()
    end

    -- 3. Limpeza de rotas, blips, pontos e objetivos
    CleanupCurrentJob()

    -- 4. Deleta o ped despachante do pátio
    if DispatcherPed and DoesEntityExist(DispatcherPed) then
        pcall(function() exports.ox_target:removeLocalEntity(DispatcherPed) end)
        DeleteEntity(DispatcherPed)
        DispatcherPed = nil
    end

    -- 4.1 Remove opções registradas no ox_target
    pcall(function() exports.ox_target:removeModel('forklift', 'aust_tie_forklift_model') end)

    -- 5. CRÍTICO: Prevenção de corrupção de memória e crash fatal da engine
    -- Desvincula e deleta imediatamente qualquer objeto criado a partir dos arquétipos .ytyp
    local trackedModels = {
        [joaat('sm3d_prop_pallet_1')] = true,
        [joaat('sm3d_prop_pallet_2')] = true,
        [joaat('sm3d_prop_pallet_1_rep')] = true,
        [joaat('sm3d_prop_pallet_1_open')] = true,
        [joaat('sm3d_prop_pallet_1_broken')] = true,
        [joaat('sm3d_prop_pallet_empty')] = true,
        [joaat('sm3d_prop_logi_shelf_1')] = true,
        [joaat('sm3d_prop_logi_shelf_2')] = true,
        [joaat('sm3d_prop_logi_shelf_3')] = true,
        [joaat('prop_cs_fuel_nozle')] = true,
        [joaat('prop_ratchet_strap')] = true,
    }

    local objects = GetGamePool('CObject')
    for _, obj in ipairs(objects) do
        if DoesEntityExist(obj) then
            local model = GetEntityModel(obj)
            if trackedModels[model] then
                if IsEntityAttached(obj) then
                    DetachEntity(obj, false, false)
                end
                SetEntityAsMissionEntity(obj, true, true)
                DeleteObject(obj)
                DeleteEntity(obj)
            end
        end
    end

    -- 6. Libera referências de modelo
    for modelHash, _ in pairs(trackedModels) do
        SetModelAsNoLongerNeeded(modelHash)
    end
end)

-- =======================================================================
-- MÓDULO ADMINISTRATIVO (ADMIN MENU & ROTAS DINÂMICAS)
-- =======================================================================

RegisterNetEvent('aurp_trucker:client:openAdminPanel', function(payload)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'admin_open',
        data = payload
    })
end)

RegisterNUICallback('adminClose', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'admin_close' })
    if cb then cb('ok') end
end)

RegisterNUICallback('adminCaptureCoords', function(data, cb)
    local coords = OffsetEditor.CaptureCurrentCoords()
    if cb then cb({ ok = true, coords = coords }) end
end)

RegisterNUICallback('adminStartOffsetCalibration', function(data, cb)
    if data and data.trailerModel then
        OffsetEditor.StartCalibration(data.trailerModel, data.slotIndex or 1, data.isForklift or false, data.propModel, data.label, data.customName, data.propCount, data.folderName)
    end
    if cb then cb('ok') end
end)

RegisterNUICallback('adminSaveRoute', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveRoute', data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteRoute', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteRoute', data and data.id)
    if cb then cb('ok') end
end)

RegisterNetEvent('aurp_trucker:client:adminSyncRoutes', function(routes)
    SendNUIMessage({
        action = 'adminSyncRoutes',
        routes = routes
    })
end)

RegisterNetEvent('aurp_trucker:client:adminSyncSpawns', function(spawns)
    _G.ClientAdminSpawns = spawns
    if Config then Config.AdminSpawns = spawns end

    -- Sincronização em tempo real de baias de carregamento com missão ativa
    if ActiveJob and ActiveJob.spawnFolder and spawns then
        local targetF = tostring(ActiveJob.spawnFolder):lower()
        for _, sp in pairs(spawns) do
            if tostring(sp.folder_name or 'Geral'):lower() == targetF and tostring(sp.spawn_type):lower() == 'load_bay' then
                if sp.coords then
                    ActiveJob.loadBayCoords = sp.coords
                    if CurrentStage == 'STEP_4_PARK_DOCK' then
                        local dockCoords = vector3(sp.coords.x, sp.coords.y, sp.coords.z)
                        UpdateMissionObjective('dock', dockCoords, 'Baía de Carregamento')
                    end
                    break
                end
            end
        end
    end

    SendNUIMessage({
        action = 'adminSyncSpawns',
        spawns = spawns
    })
end)

RegisterNetEvent('aurp_trucker:client:adminSyncSpawnFolders', function(folders)
    SendNUIMessage({
        action = 'adminSyncSpawnFolders',
        folders = folders
    })
end)

RegisterNUICallback('adminSaveSpawn', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveSpawn', data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteSpawn', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteSpawn', data and data.id)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminCreateSpawnFolder', function(data, cb)
    if data and data.folder_name then
        TriggerServerEvent('aurp_trucker:server:adminCreateSpawnFolder', data.folder_name)
    end
    if cb then cb('ok') end
end)

RegisterNUICallback('adminSaveNPC', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveNPC', data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteNPC', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteNPC', data and data.id)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminSaveEconomy', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveEconomy', data)
    if cb then cb('ok') end
end)

-- Teleporte é autorizado e executado pelo servidor (checa admin + valida coords);
-- o client não move o ped por conta própria.
RegisterNUICallback('adminTeleport', function(data, cb)
    if data and type(data.coords) == 'table' then
        TriggerServerEvent('aurp_trucker:server:adminTeleport', data.coords)
    end
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteTrailerOffset', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteTrailerOffset', data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminSaveHomologatedProp', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveHomologatedProp', data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteHomologatedProp', function(data, cb)
    local model = (type(data) == 'table' and (data.prop_model or data.modelHash or data.model)) or data
    TriggerServerEvent('aurp_trucker:server:adminDeleteHomologatedProp', model)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminMoveSpawnFolder', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminMoveSpawnFolder', data and data.spawn_id, data and data.folder_name)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteSpawnFolder', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteSpawnFolder', data and data.folder_name)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminStartSpawnGizmo', function(data, cb)
    OffsetEditor.StartSpawnCalibration(data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminStartPreview', function(data, cb)
    OffsetEditor.StartPreview(data and data.spawns)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminStopPreview', function(_, cb)
    OffsetEditor.StopPreview()
    if cb then cb('ok') end
end)

-- ============================================================
-- NUI HARD ESCAPE & PREVENÇÃO DE DEADLOCK (PILAR 6)
-- ============================================================
RegisterNUICallback('escapeNui', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close_all' })
    if cb then cb('ok') end
end)

RegisterCommand('truckerfix', function()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close_all' })
    lib.notify({
        title = 'Trucker UI',
        description = 'Foco de interface liberado com sucesso!',
        type = 'info'
    })
end, false)

-- ============================================================
-- ONESYNC STATEBAGS: RECONEXÃO AUTOMÁTICA PÓS-CULLING (PILAR 1 & 2)
-- ============================================================
local function SyncTrailerPalletAttach(trailerEnt, slotIndex, sData)
    if not trailerEnt or not DoesEntityExist(trailerEnt) or not sData or not sData.palletNet then return end

    local isLocalDriver = (ActiveJob and ActiveJob.trailerNetId and trailerEnt and DoesEntityExist(trailerEnt) and NetworkGetEntityIsNetworked(trailerEnt) and ActiveJob.trailerNetId == NetworkGetNetworkIdFromEntity(trailerEnt))

    CreateThread(function()
        local timeout = 5000
        local deadline = GetGameTimer() + timeout
        local pEnt = 0

        -- Aguarda o prop ser streamado localmente (elimina prop fantasma de culling)
        while GetGameTimer() < deadline do
            if DoesEntityExist(trailerEnt) then
                pEnt = NetworkGetEntityFromNetworkId(sData.palletNet)
                if pEnt and pEnt ~= 0 and DoesEntityExist(pEnt) then
                    break
                end
            else
                return
            end
            Wait(100)
        end

        if not pEnt or pEnt == 0 or not DoesEntityExist(pEnt) then return end

        local off = sData.offset or vector3(0.0, 0.0, 0.35)
        local heading = sData.heading or 0.0

        -- Decisão A1 & A2: Observer Passivo Total
        -- O condutor local governa a autoridade; observers NUNCA requisitam controle de rede
        if isLocalDriver then
            if NetworkGetEntityIsNetworked(pEnt) and not NetworkHasControlOfEntity(pEnt) then
                NetworkRequestControlOfEntity(pEnt)
            end
            if NetworkGetEntityIsNetworked(pEnt) then
                SetNetworkIdCanMigrate(sData.palletNet, false)
            end
        end

        -- Blindagem Cinemática Anti-Inércia Havok
        FreezeEntityPosition(pEnt, false)
        SetEntityDynamic(pEnt, false)
        SetEntityHasGravity(pEnt, false)
        SetEntityVelocity(pEnt, 0.0, 0.0, 0.0)

        -- Matriz Havok Híbrida em Observers (Decisão A3):
        -- Mantém solidez física para pedestres e anula 100% o contato com o trailer
        SetEntityCollision(pEnt, true, true)
        SetCanClimbOnEntity(pEnt, true)
        SetEntityNoCollisionEntity(pEnt, trailerEnt, false)
        SetEntityNoCollisionEntity(trailerEnt, pEnt, false)

        -- Ancoragem padronizada no Bone 0 (Root da Entidade)
        if not IsEntityAttachedToEntity(pEnt, trailerEnt) then
            AttachEntityToEntity(
                pEnt, trailerEnt, 0,
                off.x, off.y, off.z,
                0.0, 0.0, heading,
                false, false, false, false, 2, true
            )
        end
    end)
end

AddStateBagChangeHandler('loadedSlots', nil, function(bagName, key, value, _unused, replicated)
    if not value or type(value) ~= 'table' then return end
    local trailerEnt = GetEntityFromStateBagName(bagName)
    if not trailerEnt or trailerEnt == 0 or not DoesEntityExist(trailerEnt) then return end

    for slotIndex, sData in pairs(value) do
        SyncTrailerPalletAttach(trailerEnt, slotIndex, sData)
    end
end)

AddStateBagChangeHandler('loadedForklift', nil, function(bagName, key, value, _unused, replicated)
    if not value or type(value) ~= 'table' then return end
    local trailerEnt = GetEntityFromStateBagName(bagName)
    if not trailerEnt or trailerEnt == 0 or not DoesEntityExist(trailerEnt) then return end

    if value.forkNet then
        local forkEnt = NetworkGetEntityFromNetworkId(value.forkNet)
        if forkEnt and forkEnt ~= 0 and DoesEntityExist(forkEnt) then
            local isLocalDriver = (ActiveJob and ActiveJob.trailerNetId and trailerEnt and DoesEntityExist(trailerEnt) and NetworkGetEntityIsNetworked(trailerEnt) and ActiveJob.trailerNetId == NetworkGetNetworkIdFromEntity(trailerEnt))

            if not IsEntityAttachedToEntity(forkEnt, trailerEnt) then
                local off = value.offset or vector3(0.0, -6.6, 0.35)
                local heading = value.heading or 0.0

                -- Decisão A1 & A2: Observer NUNCA solicita controle de rede da empilhadeira de outrem
                if isLocalDriver then
                    if NetworkGetEntityIsNetworked(forkEnt) and not NetworkHasControlOfEntity(forkEnt) then
                        NetworkRequestControlOfEntity(forkEnt)
                    end
                    if NetworkGetEntityIsNetworked(forkEnt) then
                        SetNetworkIdCanMigrate(value.forkNet, false)
                    end
                end

                -- Blindagem Cinemática Anti-Inércia
                FreezeEntityPosition(forkEnt, false)
                SetEntityDynamic(forkEnt, false)
                SetEntityHasGravity(forkEnt, false)
                SetEntityVelocity(forkEnt, 0.0, 0.0, 0.0)

                -- Matriz Havok Híbrida (Decisão A3):
                SetEntityCollision(forkEnt, true, true)
                SetCanClimbOnEntity(forkEnt, true)
                SetEntityNoCollisionEntity(forkEnt, trailerEnt, false)
                SetEntityNoCollisionEntity(trailerEnt, forkEnt, false)

                -- Ancoragem padronizada no Bone 0 (Root)
                AttachEntityToEntity(
                    forkEnt, trailerEnt, 0,
                    off.x, off.y, off.z,
                    0.0, 0.0, heading,
                    false, false, false, false, 2, true
                )
            end
        end
    end
end)

AddStateBagChangeHandler('isRigLoadingFrozen', nil, function(bagName, key, value, _unused, replicated)
    local trailerEnt = GetEntityFromStateBagName(bagName)
    if not trailerEnt or trailerEnt == 0 or not DoesEntityExist(trailerEnt) then return end

    local shouldFreeze = (value == true)
    SetEntityVelocity(trailerEnt, 0.0, 0.0, 0.0)
    SetVehicleBrake(trailerEnt, shouldFreeze)
    SetVehicleHandbrake(trailerEnt, shouldFreeze)
    FreezeEntityPosition(trailerEnt, shouldFreeze)
end)

-- Sincronização inicial de offsets de reboques do banco no carregamento do client
CreateThread(function()
    Wait(1500)
    pcall(function()
        local res = lib.callback.await('aurp_trucker:server:getTrailerOffsetsForModel', false, 'all')
        if res and res.all then
            for mKey, data in pairs(res.all) do
                local numKey = tonumber(mKey)
                local h = numKey or joaat(tostring(mKey):lower())
                local u = h & 0xFFFFFFFF
                local s = (u >= 0x80000000) and (u - 0x100000000) or u
                local storeKeys = { mKey, h, u, s, tostring(h), tostring(u), tostring(s) }
                for _, sk in ipairs(storeKeys) do
                    if not Config.TrailerSlots[sk] then Config.TrailerSlots[sk] = { pallets = {}, forklift = nil } end
                    for idx, v in pairs(data.pallets or {}) do
                        local slotEntry = { id = v.id, label = v.label, prop_model = v.prop_model, x = tonumber(v.x) or 0.0, y = tonumber(v.y) or 0.0, z = tonumber(v.z) or 0.0, heading = tonumber(v.heading) or 0.0, straps = v.straps }
                        Config.TrailerSlots[sk].pallets[tonumber(idx)] = slotEntry
                        Config.TrailerSlots[sk].pallets[tostring(idx)] = slotEntry
                    end
                    if data.forklift then
                        local slotEntry = { x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                        Config.TrailerSlots[sk].forklift = slotEntry
                    end
                end
            end
            if Config.Debug then print("^2[AUST_Trucker] Sincronização inicial de offsets de reboques concluída com sucesso!^7") end
        end

        -- Sincronização inicial dos offsets 6DoF do PropEditor (veículo <-> prop)
        local vpRes = lib.callback.await('aurp_trucker:server:getVehiclePropOffsets', false)
        if vpRes and vpRes.dualMap then
            Config.VehiclePropOffsets = vpRes.dualMap
            if vpRes.rawMap then
                SendNUIMessage({
                    action = 'admin_update_vehicle_prop_offsets',
                    offsets = vpRes.rawMap
                })
            end
            if Config.Debug then print("^2[AUST_Trucker] Sincronização inicial de VehiclePropOffsets (6DoF) concluída!^7") end
        end

        -- Sincronização inicial de spawns dinâmicos e baias
        local spRes = lib.callback.await('aurp_trucker:server:getAdminSpawns', false)
        if spRes and spRes.spawns then
            _G.ClientAdminSpawns = spRes.spawns
            if Config then Config.AdminSpawns = spRes.spawns end
            if Config.Debug then print("^2[AUST_Trucker] Sincronização inicial de Spawns Dinâmicos concluída!^7") end
        end
    end)
end)

-- ============================================================
-- ONESYNC OBSERVER: SINCRONIZAÇÃO PASSIVA DE PALETES DE MISSÃO
-- ============================================================
local ObserverProcessedPallets = {}

CreateThread(function()
    while true do
        local sleep = 2500
        local globalPallets = GlobalState.activeTruckerPallets
        if globalPallets and #globalPallets > 0 then
            local ped = cache.ped or PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            for _, netId in ipairs(globalPallets) do
                if netId and netId ~= 0 then
                    if NetworkDoesNetworkIdExist(netId) then
                        local ent = NetworkGetEntityFromNetworkId(netId)
                        if ent and ent ~= 0 and DoesEntityExist(ent) then
                            local entCoords = GetEntityCoords(ent)
                            local dist = #(pCoords - entCoords)
                            if dist < 120.0 then
                                sleep = 1000
                                if not ObserverProcessedPallets[netId] then
                                    ObserverProcessedPallets[netId] = true
                                    SetEntityAsMissionEntity(ent, true, true)
                                    SetEntityLodDist(ent, 0xFFFF)
                                    SetEntityVisible(ent, true)
                                    ResetEntityAlpha(ent)
                                    SetEntityInvincible(ent, true)
                                    SetEntityProofs(ent, true, true, true, true, true, true, true, true)
                                    SetEntityCollision(ent, true, true)
                                    SetCanClimbOnEntity(ent, true)
                                    SetEntityHasGravity(ent, true)
                                    -- Apenas observador passivo: mantém freeze se não estiver atrelado
                                    if not IsEntityAttached(ent) then
                                        FreezeEntityPosition(ent, true)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else
            ObserverProcessedPallets = {}
        end
        Wait(sleep)
    end
end)



