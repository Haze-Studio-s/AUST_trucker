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
--          STEP_4_PARK_DOCK, STEP_4_OPEN_DOORS, STEP_5_ENTER_FORKLIFT, 
--          STEP_6_LOAD_PALLETS, STEP_7_CLOSE_AND_STRAP, STEP_8_IN_TRANSIT, STEP_9_DELIVERY

local JobEntities = {
    truck = nil,
    trailer = nil,
    forklift = nil,
    pallets = {}
}

local ActiveDeliveryPoint = nil
local DockWatcherPoint = nil
local TrailerDoorsOpen = false

-- =======================================================================
-- 5. SISTEMA DE NOTIFICAÇÃO ESTILO LATION COM EFEITO SONORO
-- =======================================================================

function SendMissionNotify(title, message, notifyType)
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)
    if exports['lation_ui'] then
        exports['lation_ui']:Notify({
            title = title,
            message = message,
            type = notifyType or 'info',
            duration = 10000
        })
    else
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

    ActiveJob = nil
    CurrentStage = 'IDLE'
    TrailerDoorsOpen = false
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

                                    -- ETAPA 4: ABERTURA DAS PORTAS TRASEIRAS DO TRAILER (VIA OX_TARGET)
                                    CurrentStage = 'STEP_4_OPEN_DOORS'
                                    ClearObjectiveMarkers(false)

                                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                                        local rearCoords = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)
                                        UpdateMissionObjective('trailer_doors', rearCoords, 'Portas Traseiras do Reboque')

                                        SendMissionNotify('Central Logística', 'Caminhão posicionado na baía! Desça do veículo e abra as portas traseiras da carreta.', 'info')

                                        -- Configuração de ox_target nas portas traseiras (bones e traseira)
                                        exports.ox_target:addLocalEntity(JobEntities.trailer, {
                                            {
                                                name = 'aust_open_rear_doors',
                                                icon = 'fa-solid fa-door-open',
                                                label = 'Abrir Portas Traseiras',
                                                distance = 4.0,
                                                bones = { 'boot', 'door_dside_r', 'door_pside_r' },
                                                canInteract = function(entity)
                                                    if CurrentStage ~= 'STEP_4_OPEN_DOORS' or IsPedInAnyVehicle(cache.ped, false) then return false end
                                                    local rearPos = GetOffsetFromEntityInWorldCoords(entity, 0.0, -5.0, 0.0)
                                                    return #(GetEntityCoords(cache.ped) - rearPos) < 4.0
                                                end,
                                                onSelect = function()
                                                    -- Abertura real e física das portas traseiras
                                                    SetVehicleDoorOpen(JobEntities.trailer, 4, false, false)
                                                    SetVehicleDoorOpen(JobEntities.trailer, 5, false, false)
                                                    SetVehicleDoorAngleRatio(JobEntities.trailer, 4, 1.0)
                                                    SetVehicleDoorAngleRatio(JobEntities.trailer, 5, 1.0)
                                                    TrailerDoorsOpen = true

                                                    SendMissionNotify('Central Logística', 'Portas abertas. Assuma a empilhadeira para iniciar o carregamento.', 'info')

                                                    -- ETAPA 5: Seta passa para a Empilhadeira (Forklift)
                                                    CurrentStage = 'STEP_5_ENTER_FORKLIFT'
                                                    UpdateMissionObjective('forklift', JobEntities.forklift, 'Empilhadeira de Carregamento')
                                                end
                                            }
                                        })
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
-- ETAPA 7: FECHAR PORTAS E AMARRAR A CARGA
-- =======================================================================

local function SetupStrappingStage()
    CurrentStage = 'STEP_7_CLOSE_AND_STRAP'
    ClearObjectiveMarkers(false)

    SendMissionNotify('Central Logística', 'Carregamento finalizado! Feche as portas e amarre a carga na traseira.', 'success')

    if not JobEntities.trailer or not DoesEntityExist(JobEntities.trailer) then return end
    local rearPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)

    -- Seta verde exclusiva na traseira da carreta
    UpdateMissionObjective('trailer_strap', rearPos, 'Fechar Portas e Amarrar Carga')

    local function PerformCloseAndStrap()
        -- Fechamento físico das portas
        SetVehicleDoorShut(JobEntities.trailer, 4, false)
        SetVehicleDoorShut(JobEntities.trailer, 5, false)
        TrailerDoorsOpen = false

        -- Barra de progresso de amarração (5 segundos)
        local success = lib.progressBar({
            duration = 5000,
            label = 'Fechando portas e amarrando carga com cintas...',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
                clip = 'machinic_loop_meano',
                flag = 49
            }
        })

        if success then
            ClearObjectiveMarkers(false)
            if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                pcall(function() exports.ox_target:removeLocalEntity(JobEntities.trailer) end)
            end
            TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob.jobId)
        end
    end

    exports.ox_target:addLocalEntity(JobEntities.trailer, {
        {
            name = 'aust_strap_cargo',
            icon = 'fa-solid fa-boxes-packing',
            label = 'Fechar Portas e Amarrar Carga',
            distance = 4.0,
            bones = { 'boot', 'door_dside_r', 'door_pside_r' },
            canInteract = function(entity)
                if CurrentStage ~= 'STEP_7_CLOSE_AND_STRAP' or IsPedInAnyVehicle(cache.ped, false) then return false end
                local rearPos = GetOffsetFromEntityInWorldCoords(entity, 0.0, -5.0, 0.0)
                return #(GetEntityCoords(cache.ped) - rearPos) < 4.0
            end,
            onSelect = function()
                PerformCloseAndStrap()
            end
        }
    })
end

-- =======================================================================
-- ETAPA 8 & 9: ROTA FINAL, ENTREGA E RECOMPENSA
-- =======================================================================

local function SetupDeliveryDestination(deliveryCoords, jobId)
    CurrentStage = 'STEP_8_IN_TRANSIT'
    ClearObjectiveMarkers(false)

    -- Seta verde flutuante e rota GPS para o destino final
    UpdateMissionObjective('delivery', deliveryCoords, 'Destino da Entrega')

    SendMissionNotify('Central Logística', 'Carga amarrada e pronta! Siga a rota indicada até o destino final.', 'success')

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
            if not TrailerDoorsOpen then
                SendMissionNotify('Central Logística', 'As portas traseiras da carreta precisam ser abertas antes de operar a empilhadeira!', 'error')
                return
            end

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
                        UpdateMissionObjective('trailer_rear', rearCoords, 'Aperte [G] na traseira para posicionar o pallet')
                    end
                elseif action == 'dropped' then
                    -- Pallet acomodado: seta volta a apontar para o próximo pallet
                    local nextP = GetNextAvailablePallet()
                    if nextP then
                        UpdateMissionObjective('pallet', nextP, 'Próximo Pallet de Carga')
                    end
                end
            end, function()
                -- Todos os pallets carregados! Avança para Etapa 7
                SetupStrappingStage()
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
    local pallets = {}
    for _, netId in ipairs(palletNetIds) do
        if netId ~= 0 and NetworkDoesNetworkIdExist(netId) then
            local ent = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(ent) then
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

RegisterNetEvent('aurp_trucker:client:polarixReadyForTransit', function(deliveryCoords)
    if not ActiveJob then return end
    SetupDeliveryDestination(deliveryCoords, ActiveJob.jobId)
end)

RegisterNetEvent('aurp_trucker:client:polarixJobFinished', function(summary)
    CleanupCurrentJob()
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    SendMissionNotify('Central Logística', ('Entrega concluída com sucesso!\nPagamento: $%d creditado no banco\nXP Ganho: +%d'):format(
        summary.payment or 0,
        summary.xp or 0
    ), 'success')
end)
