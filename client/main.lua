-- =======================================================================
-- AUST_trucker — client/main.lua
-- Máquina de Estados Autoritativa (9 Etapas Determinísticas)
-- Notificações Lation com Áudio, Abertura Física Real de Portas,
-- Props Polarix Exclusivos, Física Anti-Limbo e Gestor de Objetivos
-- Stack QBOX / OX: ox_lib, ox_target, ox_inventory, OneSync Server-Side Truth
-- =======================================================================

local ForkliftModule = require('client.modules.forklift')

local ActiveJob = nil
local CurrentStage = 'IDLE' 
-- Estados: IDLE, STEP_1_START, STEP_2_ENTER_TRUCK, STEP_3_COUPLE_TRAILER, 
--          STEP_4_PARK_DOCK, STEP_5_ENTER_FORKLIFT, STEP_6_LOAD_PALLETS, 
--          STEP_6_GET_ROPES, STEP_7_STRAP_PALLETS, STEP_8_IN_TRANSIT, STEP_9_DELIVERY

local JobEntities = {
    truck = nil,
    trailer = nil,
    forklift = nil,
    pallets = {}
}

local ActiveDeliveryPoint = nil
local DockWatcherPoint = nil
local HasRopes = false
local LoadedPalletData = {}

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
        hasRoute = false
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
        SetBlipColour(blip, 2) -- Verde oficial FiveM
        SetBlipScale(blip, 0.85)
        if hasRoute then
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, 2)
        end
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(text or "Objetivo de Carga")
        EndTextCommandSetBlipName(blip)
    end

    -- Marcador visual tipo 20 (Chevron / seta apontando para baixo) via ox_lib.points
    local point = lib.points.new({
        coords = targetCoords,
        distance = 80.0,
        nearby = function(self)
            local pos = self.coords
            if isEntity and DoesEntityExist(targetEntity) then
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

    if ForkliftModule and ForkliftModule.StopOperation then
        ForkliftModule.StopOperation()
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

    if LoadedPalletData then
        for _, pData in ipairs(LoadedPalletData) do
            if pData.entity and DoesEntityExist(pData.entity) then
                pcall(function() exports.ox_target:removeLocalEntity(pData.entity) end)
            end
        end
    end

    ActiveJob = nil
    CurrentStage = 'IDLE'
    HasRopes = false
    LoadedPalletData = {}
    JobEntities = { truck = nil, trailer = nil, forklift = nil, pallets = {} }
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

-- =======================================================================
-- DESPACHANTE NPC: ACESSO EXCLUSIVO VIA TABLET NUI (ZERO COMANDOS OBSOLETOS)
-- =======================================================================

CreateThread(function()
    while not Config or not Config.Polarix or not Config.Polarix.Warehouse do Wait(100) end
    local wh = Config.Polarix.Warehouse
    local pedHash = joaat(wh.YardManagerPed or 's_m_m_dockwork_01')
    lib.requestModel(pedHash)

    local dispatcherPed = CreatePed(4, pedHash, wh.Dispatcher.x, wh.Dispatcher.y, wh.Dispatcher.z - 1.0, wh.Dispatcher.w, false, true)
    FreezeEntityPosition(dispatcherPed, true)
    SetEntityInvincible(dispatcherPed, true)
    SetBlockingOfNonTemporaryEvents(dispatcherPed, true)
    SetPedCanRagdoll(dispatcherPed, false)

    exports.ox_target:addLocalEntity(dispatcherPed, {
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
    SendNUIMessage({ action = 'closeUI' })
    SendNUIMessage({ action = 'hide' })

    if ActiveJob then
        SendMissionNotify('Central Logística', 'Você já possui uma rota ou entrega em andamento!', 'error')
        if cb then cb({ ok = false, message = 'Já em serviço' }) end
        return
    end

    local payload = data or {}
    TriggerServerEvent('aurp_trucker:server:startDelivery', payload)

    if cb then cb('ok') end
end

RegisterNUICallback('startDelivery', HandleStartDeliveryNUI)
RegisterNUICallback('acceptJob', HandleStartDeliveryNUI)
RegisterNUICallback('startJob', HandleStartDeliveryNUI)

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

                                    -- ETAPA 4 CONCLUÍDA -> TRANSIÇÃO DIRETA PARA EMPILHADEIRA (SEM ABERTURA DE PORTAS)
                                    CurrentStage = 'STEP_5_ENTER_FORKLIFT'
                                    ClearObjectiveMarkers(false)

                                    if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
                                        UpdateMissionObjective('forklift', JobEntities.forklift, 'Empilhadeira de Carregamento')
                                    end

                                    SendMissionNotify('Central Logística', 'Caminhão posicionado na baía! Assuma a empilhadeira para iniciar o carregamento.', 'info')
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

local function StartStrappingPalletsStage()
    CurrentStage = 'STEP_7_STRAP_PALLETS'
    ClearObjectiveMarkers(false)

    local function UpdateNextPalletObjective()
        local targetPalletData = nil
        for _, pData in ipairs(LoadedPalletData) do
            if not pData.isSecured and not pData.lost and pData.entity and DoesEntityExist(pData.entity) then
                targetPalletData = pData
                break
            end
        end

        if targetPalletData then
            UpdateMissionObjective('pallet', targetPalletData.entity, 'Amarrar Palete')
        else
            -- Todos os paletes foram amarrados! Avança para o destino final
            ClearObjectiveMarkers(false)
            SendMissionNotify('Central Logística', 'Todos os paletes amarrados com sucesso! Carga pronta para transporte.', 'success')
            TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob.jobId)
        end
    end

    UpdateNextPalletObjective()

    for idx, pData in ipairs(LoadedPalletData) do
        local pEnt = pData.entity
        if pEnt and DoesEntityExist(pEnt) then
            exports.ox_target:addLocalEntity(pEnt, {
                {
                    name = 'aust_strap_pallet_' .. idx,
                    icon = 'fa-solid fa-boxes-packing',
                    label = 'Amarrar Palete',
                    distance = 2.8,
                    canInteract = function()
                        return CurrentStage == 'STEP_7_STRAP_PALLETS' and HasRopes and not pData.isSecured and not IsPedInAnyVehicle(cache.ped, false)
                    end,
                    onSelect = function()
                        -- Minigame de perícia lib.skillCheck
                        local passed = lib.skillCheck({'easy', 'medium', 'medium'}, {'w', 'a', 's', 'd'})

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

                        pData.isSecured = true
                        pcall(function() exports.ox_target:removeLocalEntity(pEnt, 'aust_strap_pallet_' .. idx) end)

                        if passed then
                            pData.riskLevel = 0
                            PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
                            SendMissionNotify('Central Logística', 'Palete amarrado com firmeza total.', 'success')
                        else
                            pData.riskLevel = 'high'
                            PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_ADD_SOUNDSET", true)
                            SendMissionNotify('Central Logística', 'A amarração ficou frouxa! Cuidado nas curvas para a corda não arrebentar.', 'warning')
                        end

                        UpdateNextPalletObjective()
                    end
                }
            })
        end
    end
end

local function SetupRopesStage()
    CurrentStage = 'STEP_6_GET_ROPES'
    ClearObjectiveMarkers(false)
    HasRopes = false

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
                return CurrentStage == 'STEP_6_GET_ROPES' and not HasRopes and not IsPedInAnyVehicle(cache.ped, false)
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

-- =======================================================================
-- ETAPA 8 & 9: ROTA FINAL, ENTREGA E RECOMPENSA COM FÍSICA DE ROMPIMENTO
-- =======================================================================

local function SetupDeliveryDestination(deliveryCoords, jobId)
    CurrentStage = 'STEP_8_IN_TRANSIT'
    ClearObjectiveMarkers(false)

    -- Remove eventuais alvos remanescentes nos paletes
    for _, pData in ipairs(LoadedPalletData) do
        if pData.entity and DoesEntityExist(pData.entity) then
            pcall(function() exports.ox_target:removeLocalEntity(pData.entity) end)
        end
    end

    -- Seta verde flutuante e rota GPS para o destino final
    UpdateMissionObjective('delivery', deliveryCoords, 'Destino da Entrega')

    SendMissionNotify('Central Logística', 'Carga amarrada e pronta! Siga a rota indicada até o destino final.', 'success')

    -- Thread leve de monitoramento de curvas bruscas e rompimento de cordas frouxas
    CreateThread(function()
        while CurrentStage == 'STEP_8_IN_TRANSIT' do
            Wait(250)
            local truck = JobEntities.truck
            if truck and DoesEntityExist(truck) then
                local speedKmh = GetEntitySpeed(truck) * 3.6
                local steerAngle = GetVehicleSteeringAngle(truck)

                if speedKmh > 50.0 and math.abs(steerAngle) > 12.0 then
                    for _, pData in ipairs(LoadedPalletData) do
                        if pData.isSecured and pData.riskLevel == 'high' and not pData.lost then
                            -- 25% de chance de rompimento
                            if math.random(1, 100) <= 25 then
                                pData.lost = true
                                local palletEnt = pData.entity
                                if palletEnt and DoesEntityExist(palletEnt) then
                                    DetachEntity(palletEnt, true, true)
                                    FreezeEntityPosition(palletEnt, false)
                                    SetEntityDynamic(palletEnt, true)
                                    SetEntityCollision(palletEnt, true, true)
                                    ActivatePhysics(palletEnt)

                                    local rightVector = GetEntityRightVector(truck)
                                    local sign = (steerAngle > 0) and -1.0 or 1.0
                                    local impulse = rightVector * (sign * 8.0)
                                    ApplyForceToEntityCenterOfMass(palletEnt, 1, impulse.x, impulse.y, 2.5, false, false, true, false)

                                    PlaySoundFrontend(-1, "WRECKED", "CAR_STEAL_2_SOUNDSET", true)
                                    SendMissionNotify('Alerta de Carga!', 'Uma cinta se rompeu e um palete caiu na pista!', 'error')

                                    local netId = NetworkGetNetworkIdFromEntity(palletEnt)
                                    TriggerServerEvent('aurp_trucker:server:palletLost', ActiveJob.jobId, netId)
                                end
                                Wait(3000) -- Cooldown para não ejetar múltiplos simultâneos
                                break
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
        nearby = function()
            if IsControlJustPressed(0, 38) then -- Tecla E
                local ped = cache.ped or PlayerPedId()
                if GetVehiclePedIsIn(ped, false) ~= 0 then
                    SendMissionNotify('Central Logística', 'Estacione o caminhão e desembarque para descarregar!', 'error')
                    return
                end

                lib.hideTextUI()
                CurrentStage = 'STEP_9_DELIVERY'

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
-- MONITORAMENTO REATIVO DE VEÍCULOS (OX_LIB CACHE)
-- =======================================================================

lib.onCache('vehicle', function(veh)
    if not ActiveJob or not veh then return end

    -- ETAPA 2: ENTRAR NO CAMINHÃO
    if CurrentStage == 'STEP_2_ENTER_TRUCK' then
        if JobEntities.truck and veh == JobEntities.truck then
            local pedSeat = GetPedInVehicleSeat(veh, -1)
            if pedSeat == cache.ped then
                CurrentStage = 'STEP_3_COUPLE_TRAILER'

                -- Remove a seta do caminhão; seta verde flutuante permanece exclusivamente sobre o trailer
                UpdateMissionObjective('trailer', JobEntities.trailer, 'Carreta / Carga')

                SendMissionNotify('Central Logística', 'Dê marcha-ré e engate a carreta no caminhão.', 'info')

                StartCouplingWatcher()
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
                    table.insert(LoadedPalletData, {
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
                -- Todos os pallets carregados! Avança para a Etapa das Cordas / Amarração
                SetupRopesStage()
            end)
        end
    end
end)

-- =======================================================================
-- EVENTOS DE REDE: INICIALIZAÇÃO E TRANSIÇÕES AUTORITATIVAS
-- =======================================================================

-- ETAPA 1: INÍCIO E SPAWN DINÂMICO
RegisterNetEvent('aurp_trucker:client:polarixJobStarted', function(payload)
    CleanupCurrentJob()
    ActiveJob = payload
    CurrentStage = 'STEP_1_START'

    CreateThread(function()
        -- Pré-carrega todos os modelos exclusivos de paletes Polarix
        local palletProps = Config.PalletProps or (Config.Polarix and Config.Polarix.PalletModels) or {}
        for _, modelName in ipairs(palletProps) do
            local hash = joaat(modelName)
            lib.requestModel(hash)
        end

        -- Sincronização OneSync das Entidades
        local truck = nil
        local trailer = nil
        local forklift = nil

        if payload.truckNetId and payload.truckNetId ~= 0 then
            local start = GetGameTimer()
            while not NetworkDoesNetworkIdExist(payload.truckNetId) and GetGameTimer() - start < 6000 do Wait(100) end
            if NetworkDoesNetworkIdExist(payload.truckNetId) then
                truck = NetToVeh(payload.truckNetId)
            end
        end

        if payload.trailerNetId and payload.trailerNetId ~= 0 then
            local start = GetGameTimer()
            while not NetworkDoesNetworkIdExist(payload.trailerNetId) and GetGameTimer() - start < 6000 do Wait(100) end
            if NetworkDoesNetworkIdExist(payload.trailerNetId) then
                trailer = NetToVeh(payload.trailerNetId)
            end
        end

        if payload.forkliftNetId and payload.forkliftNetId ~= 0 then
            local start = GetGameTimer()
            while not NetworkDoesNetworkIdExist(payload.forkliftNetId) and GetGameTimer() - start < 6000 do Wait(100) end
            if NetworkDoesNetworkIdExist(payload.forkliftNetId) then
                forklift = NetToVeh(payload.forkliftNetId)
            end
        end

        JobEntities.truck = truck
        JobEntities.trailer = trailer
        JobEntities.forklift = forklift

        if truck and DoesEntityExist(truck) then
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
            SetVehicleOnGroundProperly(trailer)
            SetEntityCollision(trailer, true, true)
            SetVehicleDoorsLocked(trailer, 1)
            SetVehicleDoorsLockedForAllPlayers(trailer, false)
        end

        if forklift and DoesEntityExist(forklift) then
            SetVehicleOnGroundProperly(forklift)
            SetEntityCollision(forklift, true, true)
            SetVehicleDoorsLocked(forklift, 1)
            SetVehicleDoorsLockedForAllPlayers(forklift, false)
            SetVehicleNeedsToBeHotwired(forklift, false)
            if exports.qbx_vehiclekeys then
                pcall(function() exports.qbx_vehiclekeys:GiveKeys(forklift) end)
            end
        end

        -- Marcadores visuais: Seta verde flutuante e blip apontando para o caminhão e para o trailer
        UpdateMissionObjective('truck', truck, 'Seu Caminhão')
        UpdateMissionObjective('trailer', trailer, 'Carreta / Carga', true)

        -- Notificação inicial estilo Lation de 10 segundos
        SendMissionNotify('Central Logística', 'Veículos liberados no pátio. Entre no caminhão para iniciar.', 'info')

        CurrentStage = 'STEP_2_ENTER_TRUCK'
    end)
end)

-- Sincronização dos Paletes e Garantia de Física Estática (Anti-Limbo)
RegisterNetEvent('aurp_trucker:client:polarixSyncPallets', function(palletNetIds)
    CreateThread(function()
        local pallets = {}
        for _, netId in ipairs(palletNetIds) do
            if netId and netId ~= 0 then
                local timeout = GetGameTimer() + 5000
                while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < timeout do
                    Wait(50)
                end
                if NetworkDoesNetworkIdExist(netId) then
                    local ent = NetworkGetEntityFromNetworkId(netId)
                    if DoesEntityExist(ent) then
                        PlaceObjectOnGroundProperly(ent)
                        SetEntityCollision(ent, true, true)
                        FreezeEntityPosition(ent, true)
                        table.insert(pallets, ent)
                    end
                end
            end
        end
        JobEntities.pallets = pallets
        ForkliftModule.SetMissionPallets(pallets)
    end)
end)

RegisterNetEvent('aurp_trucker:client:polarixReadyForTransit', function(deliveryCoords)
    if not ActiveJob then return end
    SetupDeliveryDestination(deliveryCoords, ActiveJob.jobId)
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
