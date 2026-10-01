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
local ForkliftLoadedOnTrailer = false
local ForkliftSecured = false
local ForkliftRiskLevel = 0

-- =======================================================================
-- CÁLCULO DINÂMICO DE BOUNDING BOX (Z-AXIS CLAMP) PARA CARRETAS E FORKLIFT
-- Utiliza GetModelDimensions para obter o limite Z superior real da geometria
-- da prancha, eliminando paletes flutuando no ar ou afundando no metal.
-- =======================================================================
local function GetTrailerDeckZ(trailer)
    if not trailer or not DoesEntityExist(trailer) then return 0.95 end
    local model = GetEntityModel(trailer)
    local tMin, tMax = GetModelDimensions(model)

    -- Para carretas prancha / flatbed (trflat, freighttrailer, armytrailer, docktrailer):
    -- O tMax.z determina a superfície superior do chassi. Subtraímos uma margem milimétrica
    -- apenas caso haja grade dianteira/pescoço saliente (gooseneck).
    local deckZ = tMax.z
    if model == joaat('trflat') then
        deckZ = tMax.z - 0.14 -- Alinha a madeira do palete perfeitamente ao deck de ferro
    elseif model == joaat('freighttrailer') then
        deckZ = tMax.z - 0.10
    elseif model == joaat('armytrailer') then
        deckZ = tMax.z - 0.12
    elseif model == joaat('docktrailer') then
        deckZ = tMax.z - 0.14
    else
        -- Fallback universal para carretas fechadas ou customizadas
        if (tMax.z - tMin.z) > 2.5 then
            deckZ = tMin.z + 0.95
        else
            deckZ = tMax.z - 0.10
        end
    end
    return deckZ
end
_G.GetTrailerDeckZ = GetTrailerDeckZ

local function GetForkliftDeckZ(trailer, forkEntity)
    local deckZ = GetTrailerDeckZ(trailer)
    local forkModel = (forkEntity and DoesEntityExist(forkEntity) and GetEntityModel(forkEntity)) or joaat('forklift')
    local fMin, fMax = GetModelDimensions(forkModel)
    local forkliftHalfHeight = (fMax.z - fMin.z) / 2.0
    -- Gap de 1cm (0.01 unidades) para evitar clipping e capotamento por Havok
    local safeForkZ = deckZ + forkliftHalfHeight + 0.01
    return safeForkZ
end
_G.GetForkliftDeckZ = GetForkliftDeckZ

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
    local point = lib.points.new({
        coords = targetCoords,
        distance = 150.0,
        nearby = function(self)
            local pos = self.coords
            if isEntity and targetEntity and DoesEntityExist(targetEntity) then
                pos = GetEntityCoords(targetEntity)
                self.coords = pos
            end

            DrawMarker(
                20,
                pos.x, pos.y, pos.z + offsetZ,
                0.0, 0.0, 0.0,
                180.0, 0.0, 0.0,
                0.6, 0.6, 0.6,
                0, 255, 0, 180,
                true,  -- bobs
                false, -- faceCamera
                2,
                true,  -- rotate
                nil, nil, false
            )
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

                    local dockCoords = Config.LoadingBayCoords or (Config.Polarix and Config.Polarix.Warehouse and Config.Polarix.Warehouse.LoadingBayCoords) or vector3(1244.53, -3135.57, 4.53)

                    -- Atualiza objetivo e rota GPS para a baía demarcada
                    UpdateMissionObjective('dock', dockCoords, 'Baía de Carregamento')

                    SendMissionNotify('Central Logística', 'Carreta engatada! Leve o conjunto até a baía demarcada.', 'info')

                    -- Monitoramento de estacionamento na baía
                    if DockWatcherPoint then pcall(function() DockWatcherPoint:remove() end) end
                    DockWatcherPoint = lib.points.new({
                        coords = dockCoords,
                        distance = 18.0,
                        nearby = function(self)
                            if CurrentStage ~= 'STEP_4_PARK_DOCK' then return end
                            local pedVeh = GetVehiclePedIsIn(cache.ped, false)
                            if pedVeh ~= 0 and pedVeh == JobEntities.truck then
                                local dist = #(GetEntityCoords(pedVeh) - dockCoords)
                                local speed = GetEntitySpeed(pedVeh)
                                if dist < 9.0 and speed < 1.2 then
                                    self:remove()
                                    DockWatcherPoint = nil

                                    -- ETAPA 4 CONCLUÍDA -> TRANSIÇÃO DIRETA COM BASE NO TIPO DE CARGA
                                    ClearObjectiveMarkers(false)

                                    if ActiveJob and ActiveJob.cargoType == 'heavy' then
                                        CurrentStage = 'STEP_5_ENTER_HANDLER'
                                        if JobEntities.handler and DoesEntityExist(JobEntities.handler) then
                                            UpdateMissionObjective('forklift', JobEntities.handler, 'Reach Stacker (Handler)')
                                        end
                                        SendMissionNotify('Central Logística', 'Caminhão posicionado! Assuma o Reach Stacker para içar o contêiner.', 'info')
                                    elseif ActiveJob and (ActiveJob.cargoType == 'liquid' or ActiveJob.cargoType == 'adr') then
                                        CurrentStage = 'STEP_5_FUEL_LOADING'
                                        SendMissionNotify('Central Logística', 'Caminhão posicionado na baía! Conecte a mangueira para o carregamento.', 'info')
                                    else
                                        CurrentStage = 'STEP_5_ENTER_FORKLIFT'
                                        if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
                                            UpdateMissionObjective('forklift', JobEntities.forklift, 'Empilhadeira de Carregamento')
                                        end
                                        SendMissionNotify('Central Logística', 'Caminhão posicionado na baía! Assuma a empilhadeira para iniciar o carregamento.', 'info')
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

    -- CORREÇÃO 1: TRAVA DO EIXO Z (Z-AXIS CLAMP) PARA PALETES
    -- O cálculo de GetOffsetFromEntityGivenWorldCoords captura imperfeições de colisão,
    -- resultando num eixo Z muito alto (palete flutuando no ar).
    -- Mantemos as coordenadas X e Y originais definidas pelo jogador e cravamos o Z na prancha.
    if palletEnt and DoesEntityExist(palletEnt) and trailer and DoesEntityExist(trailer) then
        local pCoords = GetEntityCoords(palletEnt)
        local rawOffset = GetOffsetFromEntityGivenWorldCoords(trailer, pCoords.x, pCoords.y, pCoords.z)
        local deckZ = GetTrailerDeckZ(trailer)
        local safeZ = deckZ + 0.01 -- Gap de 1cm para evitar clipping e capotamento por Havok
        local finalOffset = vector3(rawOffset.x, rawOffset.y, safeZ)

        local tRot = GetEntityRotation(trailer, 2)
        local pRot = GetEntityRotation(palletEnt, 2)
        local relHeading = pRot.z - tRot.z

        NetworkRequestControlOfEntity(palletEnt)
        DetachEntity(palletEnt, true, true)

        -- 1. PREPARAÇÃO DA ENTIDADE (ANTES DO ATTACH)
        -- Desliga reação física (gravidade/massa), tornando-a estática para a engine Havok
        SetEntityDynamic(palletEnt, false)
        -- Garante que a colisão global do objeto continua ativa (para que os jogadores esbarrem nele)
        SetEntityCollision(palletEnt, true, true)
        -- Força o motor a ignorar a colisão estritamente entre a carga e o reboque (em ambas as direções)
        SetEntityNoCollisionEntity(palletEnt, trailer, false)
        SetEntityNoCollisionEntity(trailer, palletEnt, false)

        -- 2. ANEXAÇÃO SEGURA (ATTACH) COM COLISÃO INTERNA FALSE
        AttachEntityToEntity(
            palletEnt, trailer, 0,
            finalOffset.x, finalOffset.y, finalOffset.z,
            0.0, 0.0, relHeading,
            false, false, false, false, 2, true
        )
        -- Reforça a blindagem de colisão mútua Pallet x Trailer sem afetar o Player
        SetEntityNoCollisionEntity(palletEnt, trailer, false)
        SetEntityNoCollisionEntity(trailer, palletEnt, false)
        FreezeEntityPosition(palletEnt, false)
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
        palletData.riskLevel = 'high'
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
        SendMissionNotify('Atenção', 'A corda ficou frouxa! Cuidado nas curvas.', 'error')
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

    -- 3. Aplique o AttachEntityToEntity na extremidade traseira com gap de segurança de 1cm
    NetworkRequestControlOfEntity(fork)
    local deckZ = GetTrailerDeckZ(trailer)
    local forkModel = (fork and DoesEntityExist(fork) and GetEntityModel(fork)) or joaat('forklift')
    local fMin, fMax = GetModelDimensions(forkModel)
    local forkliftHalfHeight = (fMax.z - fMin.z) / 2.0
    local safeForkZ = deckZ + forkliftHalfHeight + 0.01 -- Gap de 1cm para evitar clipping e capotamento por Havok

    DetachEntity(fork, true, true)

    -- 1. PREPARAÇÃO DA ENTIDADE (ANTES DO ATTACH)
    SetEntityDynamic(fork, false)
    SetEntityCollision(fork, true, true)
    SetEntityNoCollisionEntity(fork, trailer, false)
    SetEntityNoCollisionEntity(trailer, fork, false)

    -- 2. ANEXAÇÃO SEGURA (ATTACH) COM COLISÃO INTERNA FALSE
    AttachEntityToEntity(
        fork, trailer, 0,
        0.0, -5.5, safeForkZ,
        0.0, 0.0, 0.0,
        false, false, false, false, 2, true
    )
    SetEntityNoCollisionEntity(fork, trailer, false)
    SetEntityNoCollisionEntity(trailer, fork, false)
    FreezeEntityPosition(fork, false)

    ForkliftLoadedOnTrailer = true

    if success then
        ForkliftSecured = true
        ForkliftRiskLevel = 0
        PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
        SendMissionNotify('Central Logística', 'Empilhadeira travada com correntes de alta resistência.', 'success')
    else
        ForkliftSecured = true
        ForkliftRiskLevel = 'high'
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
        SendMissionNotify('Atenção', 'A amarração da empilhadeira ficou frouxa! Cuidado redobrado nas curvas.', 'error')
    end

    hasRopes = false
    HasRopes = false
    ClearObjectiveMarkers(false)
    if not CheckAllTiedAndStartRoute() then
        SetupNextPalletTarget()
    end
end

local function SetupForkliftTieTarget()
    if ActiveStrappingZoneId then
        pcall(function() exports.ox_target:removeZone(ActiveStrappingZoneId) end)
        ActiveStrappingZoneId = nil
    end

    local fork = JobEntities.forklift
    if not fork or not DoesEntityExist(fork) then
        hasRopes = false
        HasRopes = false
        ClearObjectiveMarkers(false)
        TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob.jobId)
        return
    end

    local fCoords = GetEntityCoords(fork)
    UpdateMissionObjective('forklift', fCoords, 'Travar Empilhadeira na Carreta')
    SendMissionNotify('Central Logística', 'Agora amarre a empilhadeira na traseira da carreta.', 'info')
end

-- ox_target diretamente configurado para o modelo da empilhadeira
exports.ox_target:addModel('forklift', {
    {
        name = 'aust_tie_forklift_model',
        icon = 'fas fa-link',
        label = 'Travar Empilhadeira com Correntes',
        distance = 3.5,
        canInteract = function(entity)
            if not ActiveJob or not ActiveJob.withForklift or ForkliftSecured then return false end
            if not (hasRopes or HasRopes) then return false end
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
    }
})

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
    CurrentStage = 'STEP_6_EMBARK_FORKLIFT'
    ClearObjectiveMarkers(false)

    local fork = JobEntities.forklift
    local trailer = JobEntities.trailer

    if not fork or not DoesEntityExist(fork) or not trailer or not DoesEntityExist(trailer) then
        SetupRopesStage()
        return
    end

    local trailerRear = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -6.0, 0.5)
    UpdateMissionObjective('trailer_rear', trailerRear, 'Embarcar Empilhadeira na Carreta')
    SendMissionNotify('Central Logística', 'Paletes estivados! Agora posicione a empilhadeira na traseira da carreta para embarque.', 'info')

    CreateThread(function()
        while CurrentStage == 'STEP_6_EMBARK_FORKLIFT' do
            local sleep = 250
            local ped = cache.ped or PlayerPedId()
            local veh = cache.vehicle or GetVehiclePedIsIn(ped, false)

            if veh == fork then
                local tCoords = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -5.5, 0.0)
                local dist = #(GetEntityCoords(fork) - tCoords)

                if dist < 6.0 then
                    sleep = 0
                    lib.showTextUI('[E] Embarcar Empilhadeira na Carreta', { position = 'left-center', icon = 'truck-ramp-box' })

                    if IsControlJustPressed(0, 38) then -- Tecla E
                        lib.hideTextUI()
                        TaskLeaveVehicle(ped, fork, 0)
                        Wait(1200)

                        -- Garante controle de rede
                        NetworkRequestControlOfEntity(fork)
                        local timeout = 1000
                        while not NetworkHasControlOfEntity(fork) and timeout > 0 do
                            Wait(50)
                            timeout = timeout - 50
                        end

                        -- Anexa a empilhadeira com segurança na traseira da carreta
                        local tRot = GetEntityRotation(trailer, 2)
                        AttachEntityToEntity(
                            fork, trailer, 0,
                            0.0, -5.2, 0.35,
                            0.0, 0.0, 0.0,
                            false, false, true, false, 2, true
                        )
                        SetEntityCollision(fork, true, true)
                        SetEntityNoCollisionEntity(fork, trailer, true)
                        SetEntityNoCollisionEntity(trailer, fork, true)
                        FreezeEntityPosition(fork, true)

                        ForkliftLoadedOnTrailer = true
                        PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)
                        SendMissionNotify('Central Logística', 'Empilhadeira embarcada na carreta! Agora pegue as cintas para travar.', 'success')

                        SetupRopesStage()
                        break
                    end
                else
                    lib.hideTextUI()
                end
            else
                lib.hideTextUI()
            end

            Wait(sleep)
        end
    end)
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
    -- Seta verde flutuante e rota GPS para o destino final (cor 5 amarela/laranja oficial GTA V)
    UpdateMissionObjective('delivery', dest, 'Destino da Entrega')

    SendMissionNotify('Central Logística', 'Toda a carga está segura! Siga a rota no seu GPS para o destino.', 'success')
    PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)

    -- Ativa monitoramento de risco químico para cargas perigosas ADR
    if ActiveJob and ActiveJob.cargoType == 'adr' then
        AdrHazardModule.StartMonitoring(jobId, JobEntities.truck, JobEntities.trailer, function(currentIntegrity)
            SendMissionNotify('Status de Carga ADR', ('Integridade química: %d%%. Contenha o vazamento na válvula!'):format(currentIntegrity), 'warning')
        end)
    end

    -- Monitoramento otimizado de Força G lateral, física híbrida e queda dinâmica de paletes frouxos
    CreateThread(function()
        local lastDropTime = 0

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

            -- Otimização Resmon: Dorme e esconde HUD caso o motorista esteja fora do caminhão da missão
            local currentVeh = cache.vehicle or GetVehiclePedIsIn(ped, false)
            if currentVeh ~= truck or GetPedInVehicleSeat(truck, -1) ~= ped then
                SendNUIMessage({ action = 'gmeter_hide' })
                Wait(800)
            else
                Wait(75)

                local targetList = LoadedPallets or LoadedPalletData or {}
                local hasHighRisk = false
                local anyRemaining = false

                local trailer = JobEntities.trailer
                for _, pData in ipairs(targetList) do
                    if pData.isSecured and not pData.lost and not pData.isFallen then
                        anyRemaining = true
                        if pData.riskLevel == 'high' or pData.riskLevel == 'medium' then
                            hasHighRisk = true
                        end
                        -- Blindagem contínua: anula colisão Pallet x Trailer mantendo o Player sólido
                        if trailer and DoesEntityExist(trailer) and pData.entity and DoesEntityExist(pData.entity) then
                            SetEntityNoCollisionEntity(pData.entity, trailer, true)
                            SetEntityNoCollisionEntity(trailer, pData.entity, true)
                        end
                    end
                end

                -- Se não há mais carga presa ou se a viagem acabou, oculta o medidor
                if not anyRemaining and (not ActiveJob or not ActiveJob.withForklift or not ForkliftLoadedOnTrailer or not ForkliftSecured) then
                    SendNUIMessage({ action = 'gmeter_hide' })
                else
                    local speed = GetEntitySpeed(truck) -- m/s
                    local speedKmh = speed * 3.6
                    local steering = GetVehicleSteeringAngle(truck) -- [-40, 40]
                    local now = GetGameTimer()

                    -- Sensibilidade punitiva hardcore: frouxa (2.65x) vs perfeita (0.85x)
                    local sensitivity = hasHighRisk and 2.65 or 0.85
                    local rawForce = (steering / 20.0) * (speedKmh / 42.0) * sensitivity
                    if rawForce > 1.0 then rawForce = 1.0 elseif rawForce < -1.0 then rawForce = -1.0 end

                    -- Converte força lateral em porcentagem (0 a 100, 50 = centro)
                    local percent = math.floor(50.0 + (rawForce * 50.0))
                    if percent < 2 then percent = 2 elseif percent > 98 then percent = 98 end

                    local isCritical = (percent <= 15 or percent >= 85)

                    -- Atualiza HUD de estabilidade em tempo real
                    SendNUIMessage({
                        action = 'gmeter_update',
                        percent = percent,
                        isCritical = isCritical,
                        speed = speedKmh
                    })

                    -- Gatilho de Física Hardcore: rompimento ao cruzar faixa vermelha (>24 km/h) com debounce de 4s
                    if isCritical and speedKmh > 24.0 and (now - lastDropTime >= 4000) then
                        local candidatePallet = nil

                        -- 1. Prioridade para paletes com amarração frouxa
                        for _, pData in ipairs(targetList) do
                            if pData.isSecured and (pData.riskLevel == 'high' or pData.riskLevel == 'medium') and not pData.lost and not pData.isFallen then
                                candidatePallet = pData
                                break
                            end
                        end

                        -- 2. Se amarração for perfeita, rompe apenas em curvas extremas (> 80 km/h)
                        if not candidatePallet and speedKmh > 80.0 then
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
                                if NetworkGetEntityIsNetworked(palletEnt) then
                                    NetworkRequestControlOfEntity(palletEnt)
                                end

                                -- 3. RESTAURAÇÃO NA QUEDA (IMEDIATAMENTE ANTES DO DETACH)
                                SetEntityDynamic(palletEnt, true)
                                DetachEntity(palletEnt, true, true)
                                SetEntityCollision(palletEnt, true, true)
                                FreezeEntityPosition(palletEnt, false)
                                ActivatePhysics(palletEnt)
                                SetEntityMass(palletEnt, 250.0)

                                -- Aplica impulso centrífugo realista para lançar o palete fora da caçamba
                                local rightVector = GetEntityRightVector(truck)
                                local sign = (steering > 0) and 1.0 or -1.0
                                local palletImpulse = rightVector * (sign * 6.5) + vector3(0.0, 0.0, 1.2)
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

                                local netId = NetworkGetNetworkIdFromEntity(palletEnt)
                                TriggerServerEvent('aurp_trucker:server:palletLost', ActiveJob.jobId, netId)

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

                                if NetworkGetEntityIsNetworked(fork) then
                                    NetworkRequestControlOfEntity(fork)
                                end

                                DetachEntity(fork, true, true)
                                SetEntityCollision(fork, true, true)
                                FreezeEntityPosition(fork, false)
                                SetVehicleEngineHealth(fork, 350.0) -- Dano severo no motor
                                SetVehicleBodyHealth(fork, 400.0)

                                local rightVector = GetEntityRightVector(truck)
                                local sign = (steering > 0) and -1.0 or 1.0
                                local forkImpulse = rightVector * (sign * 8.0) + vector3(0.0, 0.0, 1.8)
                                ApplyForceToEntityCenterOfMass(fork, 1, forkImpulse.x, forkImpulse.y, forkImpulse.z, false, false, true, false)

                                PlaySoundFrontend(-1, "WRECKED", "CAR_STEAL_2_SOUNDSET", true)
                                SendMissionNotify('ALERTA MÁXIMO!', 'A corrente cedeu e a empilhadeira capotou na rodovia!', 'error')

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

    ActiveDeliveryPoint = lib.points.new({
        coords = deliveryCoords,
        distance = 25.0,
        onEnter = function()
            lib.showTextUI('[E] Descarregar Mercadoria e Concluir Frete', { position = 'top-center' })
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        nearby = function(self)
            -- Restauração rigorosa dos parâmetros visuais do commit 8f218cf:
            -- Cilindro tipo 1, diâmetro 4.0m, altura 1.5m, azul ciano translúcido (0, 150, 255, 140)
            DrawMarker(
                1,
                self.coords.x, self.coords.y, self.coords.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                4.0, 4.0, 1.5,
                0, 150, 255, 140,
                false, true, 2, false, nil, nil, false
            )

            if IsControlJustPressed(0, 38) then -- Tecla E
                local ped = cache.ped or PlayerPedId()
                if GetVehiclePedIsIn(ped, false) ~= 0 then
                    SendMissionNotify('Central Logística', 'Estacione o caminhão e desembarque para descarregar!', 'error')
                    return
                end

                lib.hideTextUI()
                CurrentStage = 'STEP_9_DELIVERY'
                SendNUIMessage({ action = 'gmeter_hide' })

                local ok = lib.progressCircle({
                    duration = 6000,
                    position = 'bottom',
                    label = 'Descarregando mercadoria e finalizando serviço...',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
                })

                if ok then
                    ClearObjectiveMarkers(false)
                    TriggerServerEvent('aurp_trucker:server:completePolarixDelivery', jobId)
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
            ForkliftModule.StartOperation(ActiveJob.jobId, JobEntities.trailer, ActiveJob.requiredCount or 4, function(action, palletEnt, loaded, total)
                if action == 'picked' then
                    -- Com o pallet carregado, a seta aponta para o interior/traseira da carreta
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        local rearCoords = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)
                        UpdateMissionObjective('trailer_rear', rearCoords, 'Aperte [G] na caçamba para posicionar o pallet')
                    end
                elseif action == 'dropped' then
                    -- Registra o palete carregado para a futura amarração individual
                    table.insert(LoadedPallets, {
                        entity = palletEnt,
                        isSecured = false,
                        riskLevel = 0,
                        lost = false
                    })

                    -- Pallet acomodado: seta volta a apontar para o próximo pallet
                    local nextP = GetNextAvailablePallet()
                    if nextP then
                        UpdateMissionObjective('pallet', nextP, 'Próximo Pallet de Carga')
                    end
                end
            end, function()
                -- Todos os pallets carregados! Se configurado com empilhadeira embarcada, embarca primeiro
                if ActiveJob and ActiveJob.withForklift and JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
                    SetupEmbarkForkliftStage()
                else
                    SetupRopesStage()
                end
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

