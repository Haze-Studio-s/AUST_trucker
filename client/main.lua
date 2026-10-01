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

local ActiveDeliveryPoint = nil
local DockWatcherPoint = nil
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

local function ClearObjectiveMarkers(keepSecondary)
    if CurrentObjectivePoint then
        pcall(function() CurrentObjectivePoint:remove() end)
        CurrentObjectivePoint = nil
    end
    if CurrentObjectiveBlip and DoesBlipExist(CurrentObjectiveBlip) then
        RemoveBlip(CurrentObjectiveBlip)
        CurrentObjectiveBlip = nil
    end
    if not keepSecondary then
        if SecondaryObjectivePoint then
            pcall(function() SecondaryObjectivePoint:remove() end)
            SecondaryObjectivePoint = nil
        end
        if SecondaryObjectiveBlip and DoesBlipExist(SecondaryObjectiveBlip) then
            RemoveBlip(SecondaryObjectiveBlip)
            SecondaryObjectiveBlip = nil
        end
    end
end

function UpdateMissionObjective(objType, target, text, isSecondary)
    if not target then
        ClearObjectiveMarkers(false)
        return
    end

    if not isSecondary then
        ClearObjectiveMarkers(false)
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

            if objType ~= 'dock' and objType ~= 'delivery' then
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
            if pData.entity and DoesEntityExist(pData.entity) then
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity, 'aust_tie_current_pallet') end)
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity, 'tie_pallet_' .. idx) end)
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity) end)
                SetEntityCollision(pData.entity, true, true)
            end
        end
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
    if not netId or netId == 0 then return nil end
    local timeout = GetGameTimer() + (maxTimeoutMs or 10000)
    local lastLog = GetGameTimer()

    print(("[AUST_Trucker DEBUG - ETAPA 5] Aguardando resolução de rede para NetID: %s..."):format(tostring(netId)))

    while GetGameTimer() < timeout do
        local ok, ent = pcall(NetworkGetEntityFromNetworkId, netId)
        if ok and ent and ent ~= 0 and DoesEntityExist(ent) then
            print(("[AUST_Trucker DEBUG - ETAPA 5] Entidade NetID %s sincronizada! Handle: %s"):format(tostring(netId), tostring(ent)))
            return ent
        end

        if NetworkDoesNetworkIdExist(netId) then
            local netEnt = NetworkGetEntityFromNetworkId(netId)
            if netEnt and netEnt ~= 0 and DoesEntityExist(netEnt) then
                print(("[AUST_Trucker DEBUG - ETAPA 5] Entidade NetID %s sincronizada via NetworkDoesNetworkIdExist! Handle: %s"):format(tostring(netId), tostring(netEnt)))
                return netEnt
            end
        end

        if GetGameTimer() - lastLog >= 2000 then
            print(("[AUST_Trucker DEBUG - ETAPA 5] Aguardando streaming do NetID: %s (Restante: %d ms)"):format(tostring(netId), timeout - GetGameTimer()))
            lastLog = GetGameTimer()
        end

        Wait(100)
    end

    print(("^1[AUST_Trucker DEBUG - ETAPA 5] ERRO CRÍTICO: Timeout (10s) aguardando entidade física para NetID %s!^7"):format(tostring(netId)))
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

local function HandleStartDeliveryNUI(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', hidemenu = true })
    SendNUIMessage({ action = 'closeUI' })
    SendNUIMessage({ action = 'hide' })

    local ped = cache.ped or PlayerPedId()
    SetEntityVisible(ped, true)
    ResetEntityAlpha(ped)

    local payload = data or {}
    local contractId = payload.id or payload.contract_id or payload.contractId or payload.jobId
    print(("^2[AUST_Trucker DEBUG - ETAPA 1] HandleStartDeliveryNUI disparado! ID=%s^7"):format(tostring(contractId)))

    if ActiveJob then
        SendMissionNotify('Central Logística', 'Você já possui uma rota ou entrega em andamento!', 'error')
        if cb then cb({ ok = false, message = 'Já em serviço' }) end
        return
    end

    -- Opcional: Modal de Stacking Manual de Paletes (plt_lumberjack)
    local isDry = (payload.cargoType == 'dry') or (not payload.cargoType and not payload.adrType and not payload.liquidType)
    if isDry and Config.Stacking and Config.Stacking.Enabled then
        local alert = lib.alertDialog({
            header = 'Preparação de Carga no Pátio',
            content = 'Deseja realizar a **Montagem Manual de Paletes (Stacking)** antes de carregar o trailer?\n\n- **Montar Manualmente:** Ganhe **+20% de Pagamento** e +150 XP de bônus!\n- **Pular Montagem:** Paletes gerados prontos no galpão.',
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Sim (+20% Bônus)',
                cancel = 'Pular (Paletes Prontos)'
            }
        })
        payload.manualStacking = (alert == 'confirm')
    end

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
            Wait(250)
            if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
                local hasTrailer, trailerEnt = GetVehicleTrailerVehicle(JobEntities.truck)
                if not hasTrailer or trailerEnt == 0 then
                    hasTrailer = IsVehicleAttachedToTrailer(JobEntities.truck)
                end

                if hasTrailer then
                    -- ETAPA 3 CONCLUÍDA -> ROTA PARA A BAÍA DE CARGA
                    CurrentStage = 'STEP_4_PARK_DOCK'
                    ClearObjectiveMarkers(false)

                    local dockCfg = Config.LoadingBayCoords or (Config.Polarix and Config.Polarix.Warehouse and Config.Polarix.Warehouse.LoadingBayCoords) or vector4(1244.53, -3135.57, 4.53, 90.0)
                    local dockCoords = vector3(dockCfg.x, dockCfg.y, dockCfg.z)
                    local dockHeading = (type(dockCfg) == 'vector4' and dockCfg.w) or 90.0

                    -- Atualiza objetivo e rota GPS para a baía demarcada
                    UpdateMissionObjective('dock', dockCoords, 'Baía de Carregamento')

                    SendMissionNotify('Central Logística', 'Carreta engatada! Leve o conjunto até a vaga demarcada na baía.', 'info')

                    -- Monitoramento de estacionamento na baía com DrawMarker 30 (Padrão LC Truck Logistics / Lixeiro Charmoso)
                    if DockWatcherPoint then pcall(function() DockWatcherPoint:remove() end) end
                    local currentDockTextUi = nil

                    DockWatcherPoint = lib.points.new({
                        coords = dockCoords,
                        distance = 60.0,
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

                            if veh ~= 0 and (veh == tk or (tk and DoesEntityExist(tk) and IsEntityAttachedToEntity(veh, tk))) then
                                local trOrVeh = (tr and DoesEntityExist(tr)) and tr or veh
                                local trCoords = GetEntityCoords(trOrVeh)
                                local dist = #(trCoords - dockCoords)

                                local vehH = GetEntityHeading(veh)
                                local trH = (tr and DoesEntityExist(tr)) and GetEntityHeading(tr) or vehH
                                local vehDiff = math.abs((vehH - dockHeading + 180) % 360 - 180)
                                local trDiff = math.abs((trH - dockHeading + 180) % 360 - 180)
                                local isAligned = (vehDiff <= 20.0 or math.abs(vehDiff - 180) <= 20.0) and (trDiff <= 20.0 or math.abs(trDiff - 180) <= 20.0)

                                if dist <= 4.5 and isAligned then
                                    -- Vaga Verde Alinhada (Padrão LC Truck Logistics)
                                    DrawMarker(30, dockCoords.x, dockCoords.y, dockCoords.z - 0.6, 0.0, 0.0, 0.0, 90.0, dockHeading, 0.0, 3.0, 1.0, 10.0, 0, 255, 0, 50, 0, 0, 0, 0)
                                    if currentDockTextUi ~= 'park' then
                                        lib.showTextUI('[E] Estacionar Carreta na Baía')
                                        currentDockTextUi = 'park'
                                    end

                                    local speed = GetEntitySpeed(veh)
                                    if IsControlJustPressed(0, 38) or (speed < 0.3 and dist <= 3.0) then
                                        if currentDockTextUi then
                                            lib.hideTextUI()
                                            currentDockTextUi = nil
                                        end
                                        self:remove()
                                        DockWatcherPoint = nil
                                        ClearObjectiveMarkers(false)

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
                                    -- Vaga Vermelha Não-Alinhada / Em Aproximação (Padrão LC Truck Logistics)
                                    DrawMarker(30, dockCoords.x, dockCoords.y, dockCoords.z - 0.6, 0.0, 0.0, 0.0, 90.0, dockHeading, 0.0, 3.0, 1.0, 10.0, 255, 0, 0, 50, 0, 0, 0, 0)
                                    if dist <= 22.0 then
                                        if currentDockTextUi ~= 'align' then
                                            lib.showTextUI('Alinhe o caminhão e o reboque na baía demarcada')
                                            currentDockTextUi = 'align'
                                        end
                                    else
                                        if currentDockTextUi then
                                            lib.hideTextUI()
                                            currentDockTextUi = nil
                                        end
                                    end
                                end
                            end
                        end
                    })
                    break
                end
            end
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
        print("[AUST_Trucker] ERRO: Tentativa de amarrar empilhadeira no fluxo de paletes!")
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

        -- Ancoragem padronizada na origem do trailer (bone 0) com trava rígida de rotação (fixedRot = true)
        FreezeEntityPosition(palletEnt, false)
        SetEntityDynamic(palletEnt, false)
        AttachEntityToEntity(
            palletEnt, trailer, 0,
            finalOffset.x, finalOffset.y, finalOffset.z,
            0.0, 0.0, finalHeading,
            false, false, false, false, 2, true
        )

        -- Colisão Sólida com Player/Mundo ativa durante o carregamento + Isolamento do chassi do reboque
        FreezeEntityPosition(palletEnt, false)
        SetEntityDynamic(palletEnt, false)
        SetEntityCollision(palletEnt, true, true)
        SetCanClimbOnEntity(palletEnt, true)
        SetEntityNoCollisionEntity(palletEnt, trailer, false)
        SetEntityNoCollisionEntity(trailer, palletEnt, false)

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
        PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
        SendMissionNotify('Central Logística', 'Palete amarrado com firmeza total.', 'success')
    else
        palletData.isSecured = true
        palletData.riskLevel = 'high'
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
        SendMissionNotify('Atenção', 'A corda ficou frouxa! Cuidado redobrado nas curvas.', 'error')
    end

    -- Avança para o próximo da lista e avalia condição de avanço sem deadlock
    currentTieIndex = currentTieIndex + 1
    if not CheckAllTiedAndStartRoute() then
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
    if not forkOffset then forkOffset = vector3(0.0, -5.2, 0.35) end
    forkHeading = forkHeading or (type(forkOffset) == 'table' and forkOffset.heading) or 0.0

    DetachEntity(fork, true, true)

    -- Ancoragem padronizada na origem do trailer (bone 0) com trava rígida de rotação (fixedRot = true)
    FreezeEntityPosition(fork, false)
    SetEntityDynamic(fork, false)
    AttachEntityToEntity(
        fork, trailer, 0,
        forkOffset.x, forkOffset.y, forkOffset.z,
        0.0, 0.0, forkHeading,
        false, false, false, false, 2, true
    )

    -- Colisão Sólida com Player/Mundo ativa durante o carregamento + Isolamento do chassi do reboque
    FreezeEntityPosition(fork, false)
    SetEntityDynamic(fork, false)
    SetEntityCollision(fork, true, true)
    SetCanClimbOnEntity(fork, true)
    SetEntityNoCollisionEntity(fork, trailer, false)
    SetEntityNoCollisionEntity(trailer, fork, false)

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
    else
        ForkliftSecured = true
        ForkliftRiskLevel = 'high'
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
        SendMissionNotify('Atenção', 'A amarração da empilhadeira ficou frouxa! Cuidado redobrado nas curvas.', 'error')
    end

    hasRopes = false
    HasRopes = false
    ClearObjectiveMarkers(false)

    -- Transição direta para a rota de entrega
    local dest = (ActiveJob and ActiveJob.deliveryCoords) or (Config.DeliveryCoords)
    TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob and ActiveJob.jobId)
    if StartDeliveryRoute then
        StartDeliveryRoute(dest, ActiveJob and ActiveJob.jobId)
    end
end

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

    -- 1. Spawna o holograma fantasma da empilhadeira na extremidade traseira da carreta
    if ForkliftModule.SpawnForkliftGhost then
        ForkliftModule.SpawnForkliftGhost(trailer)
    end

    -- 2. Atualiza a rota/objetivo visual para guiar o jogador até a empilhadeira
    local fCoords = GetEntityCoords(fork)
    UpdateMissionObjective('forklift', fCoords, 'Amarrar Empilhadeira na Carreta')
    SendMissionNotify('Central Logística', 'Paletes amarrados! Estacione a empilhadeira na traseira da carreta e use as cintas para amarrá-la a pé.', 'info')
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
            -- Deve ser liberado estritamente após todos os paletes estarem amarrados
            local totalLoaded = #LoadedPallets
            if totalLoaded > 0 and currentTieIndex <= totalLoaded then return false end
            local forkCoords = GetEntityCoords(entity)
            local trailerCoords = GetEntityCoords(trailer)
            return #(trailerCoords - forkCoords) < 12.0
        end,
        onSelect = function(data)
            ExecuteForkliftTie(data and data.entity)
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
        name = 'aust_snap_pallet_slot',
        icon = 'fas fa-truck-ramp-box',
        label = 'Fixar no Slot Ativo (Fantasma)',
        distance = 3.2,
        canInteract = function(entity)
            if CurrentStage ~= 'STEP_6_LOAD_PALLETS' then return false end
            if not ActiveJob or not JobEntities.trailer or not DoesEntityExist(JobEntities.trailer) then return false end
            if IsPedInAnyVehicle(cache.ped, false) then return false end
            if IsEntityAttached(entity) then return false end
            local tCoords = GetEntityCoords(JobEntities.trailer)
            local pCoords = GetEntityCoords(entity)
            return #(tCoords - pCoords) < 14.0
        end,
        onSelect = function(data)
            local palletEnt = data and data.entity
            if not palletEnt or not DoesEntityExist(palletEnt) then return end
            local trailer = JobEntities.trailer
            local currentSlot = ForkliftModule.GetCurrentSlotIndex and ForkliftModule.GetCurrentSlotIndex() or 1
            
            local ok = lib.progressBar({
                duration = 2000,
                label = ('Estivando palete no Slot %d...'):format(currentSlot),
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
            })
            if ok then
                local snapped, snappedOffset = ForkliftModule.SnapPalletToCurrentSlot(palletEnt, trailer, currentSlot)
                if snapped then
                    local sOffset = snappedOffset or (ForkliftModule.GetSlotOffset and ForkliftModule.GetSlotOffset(trailer, currentSlot)) or vector3(0.0, 0.0, 0.35)
                    table.insert(LoadedPallets, {
                        entity = palletEnt,
                        isSecured = false,
                        riskLevel = 0,
                        lost = false,
                        slotIndex = currentSlot,
                        relOffset = sOffset,
                        relHeading = 0.0
                    })
                    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                    local loadedCount = #LoadedPallets
                    local requiredCount = ActiveJob.requiredCount or 4
                    TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', ActiveJob.jobId, loadedCount)

                    if loadedCount < requiredCount then
                        local nextSlot = currentSlot + 1
                        local nextOffset = ForkliftModule.GetSlotOffset(trailer, nextSlot)
                        ForkliftModule.SpawnGhostProp(trailer, 'hei_prop_carrier_cargo_04b', nextOffset)
                    else
                        ForkliftModule.StopOperation()
                        SetupRopesStage()
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
        local hasCargo = false

        if trailer and DoesEntityExist(trailer) then
            local pList = LoadedPallets or LoadedPalletData or {}
            for _, pData in ipairs(pList) do
                local pEnt = pData.entity
                if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                    hasCargo = true
                    SetEntityNoCollisionEntity(pEnt, trailer, true)
                    SetEntityNoCollisionEntity(trailer, pEnt, true)
                end
            end

            local fork = JobEntities.forklift
            if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer then
                hasCargo = true
                SetEntityNoCollisionEntity(fork, trailer, true)
                SetEntityNoCollisionEntity(trailer, fork, true)
            end
        end

        Wait(hasCargo and 0 or 300)
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

    -- 2. Captura coordenadas mundiais tridimensionais em tempo real onde o palete está na caçamba
    local pCoords = GetEntityCoords(currentPallet.entity)
    if not pCoords or pCoords == vector3(0, 0, 0) then
        if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
            pCoords = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, 0.0, 0.5)
        end
    end

    -- 3. Move a seta verde flutuante diretamente para o topo deste palete
    UpdateMissionObjective('pallet', pCoords, ('Amarrar Palete (%d/%d)'):format(currentTieIndex, #LoadedPallets))

    -- 4. Cria a zona esférica de interação do ox_target EXCLUSIVAMENTE sobre a posição mundial do palete
    ActiveStrappingZoneId = exports.ox_target:addSphereZone({
        coords = pCoords,
        radius = 2.0,
        debug = false,
        options = {
            {
                name = 'aust_tie_current_pallet',
                icon = 'fas fa-tape',
                label = ('Amarrar Palete (%s/%s)'):format(currentTieIndex, #LoadedPallets),
                distance = 3.5,
                canInteract = function()
                    return (hasRopes or HasRopes) and not currentPallet.isSecured and not IsPedInAnyVehicle(cache.ped, false)
                end,
                onSelect = function()
                    ExecutePalletTie(currentTieIndex)
                end
            }
        }
    })

    SendMissionNotify('Central Logística', ('Amarre o palete %s de %s.'):format(currentTieIndex, #LoadedPallets), 'info')
end

local function StartStrappingPalletsStage()
    CurrentStage = 'STEP_7_STRAP_PALLETS'
    ClearObjectiveMarkers(false)
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
    ClearObjectiveMarkers(false)
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
    ClearObjectiveMarkers(false)

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
                SetEntityAsMissionEntity(pEnt, true, true)
                SetEntityLodDist(pEnt, 0xFFFF)
                FreezeEntityPosition(pEnt, false)
                SetEntityDynamic(pEnt, false)
                SetEntityCollision(pEnt, true, true)
                SetCanClimbOnEntity(pEnt, true)
                SetEntityNoCollisionEntity(pEnt, trailer, false)
                SetEntityNoCollisionEntity(trailer, pEnt, false)

                -- Reforço imediato de ancoragem na malha do trailer (origem bone 0)
                if pData.relOffset then
                    AttachEntityToEntity(
                        pEnt, trailer, 0,
                        pData.relOffset.x, pData.relOffset.y, pData.relOffset.z,
                        0.0, 0.0, pData.relHeading or 0.0,
                        false, false, false, false, 2, true
                    )
                end
            end
        end

        local fork = JobEntities.forklift
        if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer then
            SetEntityAsMissionEntity(fork, true, true)
            SetEntityLodDist(fork, 0xFFFF)
            FreezeEntityPosition(fork, false)
            SetEntityDynamic(fork, false)
            SetEntityCollision(fork, true, true)
            SetCanClimbOnEntity(fork, true)
            SetEntityNoCollisionEntity(fork, trailer, false)
            SetEntityNoCollisionEntity(trailer, fork, false)

            local forkOffset, forkHeading = (ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(trailer)) or vector3(0.0, -5.2, 0.35)
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

            -- PILAR 5: ESTABILIDADE FÍSICA HAVOK (PARKING FREEZE)
            if truckSpeed < 0.5 and not isDrivingTruck then
                if stoppedSince == 0 then stoppedSince = GetGameTimer() end
                if GetGameTimer() - stoppedSince >= 5000 and not isParkFrozen then
                    isParkFrozen = true
                    FreezeEntityPosition(truck, true)
                    if trailer and DoesEntityExist(trailer) then
                        FreezeEntityPosition(trailer, true)
                    end
                end
            else
                stoppedSince = 0
                if isParkFrozen then
                    isParkFrozen = false
                    FreezeEntityPosition(truck, false)
                    if trailer and DoesEntityExist(trailer) then
                        FreezeEntityPosition(trailer, false)
                    end
                end
            end

            if shouldBeInTransit then
                if not isCargoInTransitMode then
                    isCargoInTransitMode = true
                    -- MODO TRÂNSITO: Desativa colisão física para eliminar catapultas Havok e flickers de rede
                    local targetList = LoadedPallets or LoadedPalletData or {}
                    for _, pData in ipairs(targetList) do
                        local pEnt = pData.entity
                        if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                            SetEntityCollision(pEnt, false, false)
                            SetEntityDynamic(pEnt, false)
                            FreezeEntityPosition(pEnt, false)
                        end
                    end

                    local fork = JobEntities.forklift
                    if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer then
                        SetEntityCollision(fork, false, false)
                        SetEntityDynamic(fork, false)
                        FreezeEntityPosition(fork, false)
                    end
                end
            else
                if isCargoInTransitMode then
                    isCargoInTransitMode = false
                    -- MODO SÓLIDO: Caminhão parado (< 3 km/h) ou fora da cabine -> Colisão sólida a pé
                    local targetList = LoadedPallets or LoadedPalletData or {}
                    for _, pData in ipairs(targetList) do
                        local pEnt = pData.entity
                        if pEnt and DoesEntityExist(pEnt) and not pData.lost and not pData.isFallen then
                            SetEntityCollision(pEnt, true, true)
                            SetCanClimbOnEntity(pEnt, true)
                            SetEntityDynamic(pEnt, false)
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
                                if not IsEntityAttachedToEntity(pEnt, tr) then
                                    FreezeEntityPosition(pEnt, false)
                                    SetEntityDynamic(pEnt, false)
                                    if isCargoInTransitMode then
                                        SetEntityCollision(pEnt, false, false)
                                    else
                                        SetEntityCollision(pEnt, true, true)
                                        SetCanClimbOnEntity(pEnt, true)
                                        SetEntityNoCollisionEntity(pEnt, tr, false)
                                        SetEntityNoCollisionEntity(tr, pEnt, false)
                                    end
                                    local off = pData.relOffset or (ForkliftModule.GetSlotOffset and ForkliftModule.GetSlotOffset(tr, pData.slotIndex or _)) or vector3(0.0, 0.0, 0.35)
                                    local pHead = pData.relHeading or (type(off) == 'table' and off.heading) or 0.0
                                    AttachEntityToEntity(
                                        pEnt, tr, 0,
                                        off.x, off.y, off.z,
                                        0.0, 0.0, pHead,
                                        false, false, false, false, 2, true
                                    )
                                end
                            end
                        end

                        local fork = JobEntities.forklift
                        if fork and DoesEntityExist(fork) and ForkliftLoadedOnTrailer and ForkliftSecured then
                            if not IsEntityAttachedToEntity(fork, tr) then
                                FreezeEntityPosition(fork, false)
                                SetEntityDynamic(fork, false)
                                if isCargoInTransitMode then
                                    SetEntityCollision(fork, false, false)
                                else
                                    SetEntityCollision(fork, true, true)
                                    SetCanClimbOnEntity(fork, true)
                                    SetEntityNoCollisionEntity(fork, tr, false)
                                    SetEntityNoCollisionEntity(tr, fork, false)
                                end
                                local forkOffset, forkHeading = (ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(tr)) or vector3(0.0, -5.2, 0.35)
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

                    -- Componente de inclinação/tombamento (25° já indica risco severo)
                    local rollG = (activeRoll / 28.0)

                    -- Sensibilidade punitiva: se houver amarração frouxa, amplia a instabilidade
                    local riskMultiplier = hasHighRisk and 1.65 or 1.05
                    local rawForce = ((centripetalG * 1.4) + (rollG * 1.25)) * riskMultiplier
                    if rawForce > 1.0 then rawForce = 1.0 elseif rawForce < -1.0 then rawForce = -1.0 end

                    -- Converte força lateral em porcentagem (0 a 100, 50 = centro)
                    local targetPercent = math.floor(50.0 + (rawForce * 50.0))
                    if targetPercent < 2 then targetPercent = 2 elseif targetPercent > 98 then targetPercent = 98 end

                    -- Suavização exponencial para resposta fluida no HUD
                    currentSmoothPercent = currentSmoothPercent + (targetPercent - currentSmoothPercent) * 0.4
                    local percent = math.floor(currentSmoothPercent + 0.5)
                    local isCritical = (percent <= 15 or percent >= 85)

                    -- Atualiza HUD de estabilidade em tempo real
                    SendNUIMessage({
                        action = 'gmeter_update',
                        percent = percent,
                        isCritical = isCritical,
                        speed = speedKmh
                    })

                    -- GATILHO DINÂMICO E REALISTA DE QUEDA DE CARGA:
                    -- Ativado por inclinação crítica (|Roll| > 25° quase tombando) OU força sustentada na faixa vermelha (> 35 km/h)
                    local absRoll = math.abs(activeRoll)
                    local isSevereTilt = absRoll > 25.0
                    local isCentrifugalCritical = isCritical and speedKmh > 35.0

                    if (isSevereTilt or isCentrifugalCritical) and (now - lastDropTime >= 3500) then
                        local candidatePallet = nil

                        -- 1. Prioridade absoluta para paletes com amarração frouxa
                        for _, pData in ipairs(targetList) do
                            if pData.isSecured and (pData.riskLevel == 'high' or pData.riskLevel == 'medium') and not pData.lost and not pData.isFallen then
                                candidatePallet = pData
                                break
                            end
                        end

                        -- 2. Se amarração for perfeita, rompe se carreta quase capotar (|Roll| > 30°) OU curva extrema sustentada (> 65 km/h na faixa vermelha)
                        if not candidatePallet and (absRoll > 30.0 or (isCritical and speedKmh > 65.0)) then
                            for _, pData in ipairs(targetList) do
                                if pData.isSecured and not pData.lost and not pData.isFallen then
                                    candidatePallet = pData
                                    break
                                end
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

            if dist <= 4.5 and isAligned then
                -- Vaga Verde Alinhada (Padrão LC Truck Logistics / Lixeiro Charmoso)
                DrawMarker(30, destCoords.x, destCoords.y, destCoords.z - 0.6, 0.0, 0.0, 0.0, 90.0, destH, 0.0, 3.0, 1.0, 10.0, 0, 255, 0, 50, 0, 0, 0, 0)
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
                DrawMarker(30, destCoords.x, destCoords.y, destCoords.z - 0.6, 0.0, 0.0, 0.0, 90.0, destH, 0.0, 3.0, 1.0, 10.0, 255, 0, 0, 50, 0, 0, 0, 0)
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
    if CurrentStage ~= 'STEP_2_ENTER_TRUCK' then return end
    CurrentStage = 'STEP_3_COUPLE_TRAILER'

    JobEntities.truck = truck

    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)

    -- Remove a seta do caminhão; seta verde flutuante passa para a carreta
    local trailerTarget = (JobEntities.trailer and DoesEntityExist(JobEntities.trailer) and JobEntities.trailer)
        or (ActiveJob and ActiveJob.trailerCoords)

    UpdateMissionObjective('trailer', trailerTarget, 'Carreta / Carga')

    SendMissionNotify('Central Logística', 'Dê marcha-ré e engate a carreta no caminhão.', 'info')

    StartCouplingWatcher()
end

local function StartMissionStep1(truck, trailer, forklift)
    CurrentStage = 'STEP_2_ENTER_TRUCK'

    -- 1. Criação do blip e rota no GPS direcionando para o caminhão
    -- 2. Ativação da seta verde flutuante (marcador chevron tipo 20) sobre o teto do caminhão
    local truckTarget = (truck and DoesEntityExist(truck) and truck) or (ActiveJob and ActiveJob.truckCoords)
    UpdateMissionObjective('truck', truckTarget, 'Seu Caminhão')

    -- Blip secundário da carreta/carga
    local trailerTarget = (trailer and DoesEntityExist(trailer) and trailer) or (ActiveJob and ActiveJob.trailerCoords)
    if trailerTarget then
        UpdateMissionObjective('trailer', trailerTarget, 'Carreta / Carga', true)
    end

    -- 3. Disparo da notificação sonora de 10 segundos
    SendMissionNotify('Central Logística', 'Veículos liberados no pátio. Entre no caminhão para iniciar.', 'info')

    -- 4. Verificação imediata caso o jogador já esteja dentro do veículo
    local ped = cache.ped or PlayerPedId()
    local currentVeh = GetVehiclePedIsIn(ped, false)
    if currentVeh ~= 0 and truck and currentVeh == truck then
        if GetPedInVehicleSeat(currentVeh, -1) == ped then
            OnPlayerEnteredTruck(currentVeh)
        end
    end
end

-- =======================================================================
-- MONITORAMENTO REATIVO DE VEÍCULOS (OX_LIB CACHE)
-- =======================================================================

lib.onCache('vehicle', function(veh)
    if not ActiveJob or not veh then return end

    -- ETAPA 2: ENTRAR NO CAMINHÃO
    if CurrentStage == 'STEP_2_ENTER_TRUCK' then
        local isTargetTruck = false
        if JobEntities.truck and veh == JobEntities.truck then
            isTargetTruck = true
        elseif ActiveJob and ActiveJob.truckNetId and NetworkDoesNetworkIdExist(ActiveJob.truckNetId) then
            local netVeh = NetworkGetEntityFromNetworkId(ActiveJob.truckNetId)
            if netVeh ~= 0 and veh == netVeh then
                isTargetTruck = true
            end
        end

        if isTargetTruck then
            local pedSeat = GetPedInVehicleSeat(veh, -1)
            if pedSeat == cache.ped then
                OnPlayerEnteredTruck(veh)
            end
        end
    end

    -- ETAPA 5 & 6: OPERAÇÃO COM EMPILHADEIRA E TECLA 'G'
    if CurrentStage == 'STEP_5_ENTER_FORKLIFT' then
        if JobEntities.forklift and veh == JobEntities.forklift then
            CurrentStage = 'STEP_6_LOAD_PALLETS'

            -- Ao entrar na empilhadeira, a seta passa para os pallets no pátio
            local firstPallet = GetNextAvailablePallet()
            if firstPallet then
                UpdateMissionObjective('pallet', firstPallet, 'Pallet de Carga')
            end

            SendMissionNotify('Central Logística', 'Utilize a empilhadeira para carregar os pallets. Aproxime os garfos e aperte [G].', 'info')

            -- Inicia ciclo de manuseio com a tecla [G]
            ForkliftModule.StartOperation(ActiveJob.jobId, JobEntities.trailer, ActiveJob.requiredCount or 4, function(action, palletEnt, loaded, total, stowedSlot, slotOffset, slotHeading)
                if action == 'picked' then
                    -- Com o pallet carregado, a seta aponta para o interior/traseira da carreta
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        local rearCoords = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)
                        UpdateMissionObjective('trailer_rear', rearCoords, 'Aperte [G] na caçamba para posicionar o pallet')
                    end
                elseif action == 'dropped' then
                    -- Registra o palete carregado com os dados exatos do slot para a amarração individual
                    local sOffset, sHead = slotOffset, slotHeading
                    if not sOffset and ForkliftModule.GetSlotOffset then
                        sOffset, sHead = ForkliftModule.GetSlotOffset(JobEntities.trailer, stowedSlot or loaded)
                    end
                    if not sOffset then sOffset = vector3(0.0, 0.0, 0.35) end
                    local finalH = sHead or (type(sOffset) == 'table' and sOffset.heading) or 0.0

                    table.insert(LoadedPallets, {
                        entity = palletEnt,
                        isSecured = false,
                        riskLevel = 0,
                        lost = false,
                        slotIndex = stowedSlot or loaded,
                        relOffset = sOffset,
                        relHeading = finalH
                    })

                    -- Pallet acomodado: seta volta a apontar para o próximo pallet
                    local nextP = GetNextAvailablePallet()
                    if nextP then
                        UpdateMissionObjective('pallet', nextP, 'Próximo Pallet de Carga')
                    end
                end
            end, function()
                -- Todos os pallets carregados! Prossegue diretamente para a etapa de amarração com cintas
                ForkliftModule.StopOperation()
                SetupRopesStage()
            end)
        end
    end

    -- ETAPA 5 & 6: OPERAÇÃO COM REACH STACKER (CARGA PESADA / CONTÊINER)
    if CurrentStage == 'STEP_5_ENTER_HANDLER' then
        if JobEntities.handler and veh == JobEntities.handler then
            CurrentStage = 'STEP_6_LOAD_CONTAINER'

            if JobEntities.container and DoesEntityExist(JobEntities.container) then
                UpdateMissionObjective('pallet', JobEntities.container, 'Contêiner Marítimo')
            end

            SendMissionNotify('Central Logística', 'Opere o Reach Stacker! Aproxime o spreader do contêiner e aperte [G] para travar.', 'info')

            ReachStackerModule.SetMissionContainer(JobEntities.container)
            ReachStackerModule.StartOperation(ActiveJob.jobId, JobEntities.trailer, function(action, cEnt)
                if action == 'picked' then
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        local trailerPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, 0.0, 1.0)
                        UpdateMissionObjective('trailer_rear', trailerPos, 'Posicione sobre a prancha e aperte [G]')
                    end
                elseif action == 'dropped' then
                    SendMissionNotify('Central Logística', 'Contêiner fixado com sucesso na prancha! Entre no caminhão para iniciar a rota.', 'success')
                end
            end, function()
                ClearObjectiveMarkers(false)
                TriggerServerEvent('aurp_trucker:server:heavyContainerLoaded', ActiveJob.jobId)
            end)
        end
    end
end)

-- =======================================================================
-- EVENTOS DE REDE: INICIALIZAÇÃO E TRANSIÇÕES AUTORITATIVAS
-- =======================================================================

-- ETAPA 1: INÍCIO E SPAWN DINÂMICO
RegisterNetEvent('aurp_trucker:client:polarixJobStarted', function(payload)
    print(("^2[AUST_Trucker DEBUG - ETAPA 4] aurp_trucker:client:polarixJobStarted recebido com sucesso no Cliente! JobID: %s, TruckNetId: %s, TrailerNetId: %s, Cargo: %s^7"):format(
        tostring(payload and payload.jobId),
        tostring(payload and payload.truckNetId),
        tostring(payload and payload.trailerNetId),
        tostring(payload and payload.cargoType)
    ))

    CleanupCurrentJob()
    ActiveJob = payload
    CurrentStage = 'STEP_1_START'

    -- Prevenção de Deadlock: se não houver empilhadeira contratada, inicia como concluída
    local hasFork = payload and payload.withForklift and (payload.forkliftNetId and payload.forkliftNetId ~= 0)
    ForkliftSecured = not hasFork
    ForkliftLoadedOnTrailer = not hasFork
    ForkliftRiskLevel = 0

    -- Runtime Synchronization: Sobrescreve os offsets em memória com os dados mais recentes do banco
    if payload and payload.trailerOffsets then
        for mKey, data in pairs(payload.trailerOffsets) do
            local h = (type(mKey) == 'number') and mKey or joaat(tostring(mKey):lower())
            if not Config.TrailerSlots[h] then Config.TrailerSlots[h] = { pallets = {}, forklift = nil } end
            if not Config.TrailerSlots[mKey] then Config.TrailerSlots[mKey] = { pallets = {}, forklift = nil } end
            for idx, v in pairs(data.pallets or {}) do
                local slotEntry = { x = tonumber(v.x) or 0.0, y = tonumber(v.y) or 0.0, z = tonumber(v.z) or 0.0, heading = tonumber(v.heading) or 0.0 }
                Config.TrailerSlots[h].pallets[tonumber(idx)] = slotEntry
                Config.TrailerSlots[mKey].pallets[tonumber(idx)] = slotEntry
            end
            if data.forklift then
                local slotEntry = { x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                Config.TrailerSlots[h].forklift = slotEntry
                Config.TrailerSlots[mKey].forklift = slotEntry
            end
        end
    end

    CreateThread(function()
        -- Pré-carregamento assíncrono e protegido dos modelos de palete e contêiner
        CreateThread(function()
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

        -- 1. Espera ativa e segura pela existência física das entidades no cliente (Timeout 10s)
        local truck = WaitForNetworkEntity(payload.truckNetId, 10000)
        local trailer = WaitForNetworkEntity(payload.trailerNetId, 10000)
        local forklift = nil
        if payload.forkliftNetId and payload.forkliftNetId ~= 0 then
            forklift = WaitForNetworkEntity(payload.forkliftNetId, 10000)
        end
        local handler = nil
        if payload.handlerNetId and payload.handlerNetId ~= 0 then
            handler = WaitForNetworkEntity(payload.handlerNetId, 10000)
        end
        local container = nil
        if payload.containerNetId and payload.containerNetId ~= 0 then
            container = WaitForNetworkEntity(payload.containerNetId, 10000)
        end

        if not truck or not DoesEntityExist(truck) or not trailer or not DoesEntityExist(trailer) then
            print(("^1[AUST_Trucker DEBUG - ETAPA 5] ERRO: Truck (%s) ou Trailer (%s) não puderam ser sincronizados no cliente! Cancelando job...^7"):format(
                tostring(truck), tostring(trailer)
            ))
            SendMissionNotify('Falha de Streaming', 'Não foi possível sincronizar os veículos da missão no cliente.', 'error')
            TriggerServerEvent('aurp_trucker:server:cancelDelivery', payload.jobId, 'Falha de streaming de veículos no cliente')
            CleanupCurrentJob()
            return
        end

        print(("^2[AUST_Trucker DEBUG - ETAPA 5] Veículos sincronizados! Iniciando StartMissionStep1 para Job %s^7"):format(tostring(payload.jobId)))

        local playerPed = cache.ped or PlayerPedId()
        SetEntityVisible(playerPed, true)
        ResetEntityAlpha(playerPed)

        JobEntities.truck = truck
        JobEntities.trailer = trailer
        JobEntities.forklift = forklift
        JobEntities.handler = handler
        JobEntities.container = container

        if truck and DoesEntityExist(truck) then
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
        end

        if trailer and DoesEntityExist(trailer) then
            SetEntityVisible(trailer, true)
            ResetEntityAlpha(trailer)
            SetVehicleOnGroundProperly(trailer)
            SetEntityCollision(trailer, true, true)
            SetVehicleDoorsLocked(trailer, 1)
            SetVehicleDoorsLockedForAllPlayers(trailer, false)
            SetVehicleExplodesOnHighExplosionDamage(trailer, false)
            SetVehicleCanBeVisiblyDamaged(trailer, false)
            SetVehicleStrong(trailer, true)

            -- Lock 1: Identificação Sequencial e Requisição Bloqueante de Offsets do Reboque
            local tHash = GetEntityModel(trailer)
            local tModelName = payload.trailerModel or tostring(tHash)
            local ok, res = pcall(function()
                return lib.callback.await('aurp_trucker:server:getTrailerOffsetsForModel', false, tModelName)
            end)

            if ok and res and (res.specific or res.all) then
                local data = res.specific or (res.all and (res.all[tModelName:lower()] or res.all[tHash] or res.all[tostring(tHash)]))
                if data then
                    if not Config.TrailerSlots[tHash] then Config.TrailerSlots[tHash] = { pallets = {}, forklift = nil } end
                    if not Config.TrailerSlots[tModelName:lower()] then Config.TrailerSlots[tModelName:lower()] = { pallets = {}, forklift = nil } end
                    for idx, v in pairs(data.pallets or {}) do
                        local vec = vector3(v.x, v.y, v.z)
                        Config.TrailerSlots[tHash].pallets[tonumber(idx)] = vec
                        Config.TrailerSlots[tModelName:lower()].pallets[tonumber(idx)] = vec
                    end
                    if data.forklift then
                        local vec = vector3(data.forklift.x, data.forklift.y, data.forklift.z)
                        Config.TrailerSlots[tHash].forklift = vec
                        Config.TrailerSlots[tModelName:lower()].forklift = vec
                    end
                    print(("^2[AUST_Trucker Client] Lock 1 Sucesso: Offsets customizados injetados em memória para trailer %s (Hash %s)!^7"):format(
                        tModelName, tostring(tHash)
                    ))
                end
            end
        end

        if forklift and DoesEntityExist(forklift) then
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

        if handler and DoesEntityExist(handler) then
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

        if container and DoesEntityExist(container) then
            SetEntityVisible(container, true)
            ResetEntityAlpha(container)
            PlaceObjectOnGroundProperly(container)
            SetEntityCollision(container, true, true)
            FreezeEntityPosition(container, true)
        end

        -- 2. Inicialização sequencial e determinística da Etapa 1
        StartMissionStep1(truck, trailer, forklift)
    end)
end)

-- Sincronização dos Paletes e Garantia de Física Estática (Anti-Limbo)
RegisterNetEvent('aurp_trucker:client:polarixSyncPallets', function(palletNetIds)
    CreateThread(function()
        local pallets = {}
        for _, netId in ipairs(palletNetIds) do
            if netId and netId ~= 0 then
                local ent = WaitForNetworkEntity(netId, 8000)
                if ent and DoesEntityExist(ent) then
                    SetEntityAsMissionEntity(ent, true, true)
                    SetEntityLodDist(ent, 0xFFFF)
                    SetEntityVisible(ent, true)
                    ResetEntityAlpha(ent)
                    PlaceObjectOnGroundProperly(ent)
                    SetEntityCollision(ent, true, true)
                    FreezeEntityPosition(ent, true)
                    table.insert(pallets, ent)
                end
            end
        end
        JobEntities.pallets = pallets
        ForkliftModule.SetMissionPallets(pallets)
    end)
end)

RegisterNetEvent('aurp_trucker:client:polarixReadyForTransit', function(deliveryCoords)
    if not ActiveJob then return end
    StartDeliveryRoute(deliveryCoords, ActiveJob.jobId)
end)

RegisterNetEvent('aurp_trucker:client:polarixJobFinished', function(summary)
    CleanupCurrentJob()
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    if summary.lostPallets and summary.lostPallets > 0 then
        SendMissionNotify('Central Logística', ('Entrega concluída com penalidade por carga perdida (%d paletes perdidos).\nPagamento: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.lostPallets,
            summary.payment or 0,
            summary.xp or 0
        ), 'warning')
    else
        SendMissionNotify('Central Logística', ('Entrega concluída com sucesso!\nPagamento: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.payment or 0,
            summary.xp or 0
        ), 'success')
    end
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
        OffsetEditor.StartCalibration(data.trailerModel, data.slotIndex or 1, data.isForklift or false, data.propModel)
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

RegisterNUICallback('adminSaveSpawn', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveSpawn', data)
    if cb then cb('ok') end
end)

RegisterNUICallback('adminDeleteSpawn', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteSpawn', data and data.id)
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

RegisterNUICallback('adminTeleport', function(data, cb)
    if data and data.coords then
        local ped = cache.ped or PlayerPedId()
        SetEntityCoords(ped, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
        if data.coords.heading or data.coords.w then
            SetEntityHeading(ped, data.coords.heading or data.coords.w)
        end
    end
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
-- ONESYNC STATEBAGS: RECONEXÃO AUTOMÁTICA PÓS-CULLING (PILAR 1)
-- ============================================================
AddStateBagChangeHandler('loadedSlots', nil, function(bagName, key, value, _unused, replicated)
    if not value or type(value) ~= 'table' then return end
    local trailerEnt = GetEntityFromStateBagName(bagName)
    if not trailerEnt or trailerEnt == 0 or not DoesEntityExist(trailerEnt) then return end

    -- Se o reboque estiver no escopo do cliente, re-acopla paletes se descolados por culling
    for slotIndex, sData in pairs(value) do
        if sData and sData.palletNet then
            local pEnt = NetworkGetEntityFromNetworkId(sData.palletNet)
            if pEnt and pEnt ~= 0 and DoesEntityExist(pEnt) then
                if not IsEntityAttachedToEntity(pEnt, trailerEnt) then
                    local off = sData.offset or vector3(0.0, 0.0, 0.35)
                    local heading = sData.heading or 0.0
                    SetEntityCollision(pEnt, true, true)
                    SetCanClimbOnEntity(pEnt, true)
                    FreezeEntityPosition(pEnt, false)
                    SetEntityDynamic(pEnt, false)
                    SetEntityNoCollisionEntity(pEnt, trailerEnt, false)
                    SetEntityNoCollisionEntity(trailerEnt, pEnt, false)
                    AttachEntityToEntity(
                        pEnt, trailerEnt, 0,
                        off.x, off.y, off.z,
                        0.0, 0.0, heading,
                        false, false, false, false, 2, true
                    )
                end
            end
        end
    end
end)


