-- =======================================================================
-- AUST_trucker — client/main.lua
-- Máquina de Estados Autoritativa (8 Etapas Determinísticas)
-- Stack QBOX / OX: ox_lib, ox_target, ox_inventory, OneSync Server-Side Truth
-- =======================================================================

local ForkliftModule = require('client.modules.forklift')
local Zones = rawget(_G, 'Zones') or _G.Zones
if not Zones then
    local ok, mod = pcall(require, 'client.zones')
    if ok and mod then Zones = mod end
end

local ActiveJob = nil
local CurrentStage = 'IDLE' 
-- Estados: IDLE, STEP_1_START, STEP_2_ENTER_TRUCK, STEP_3_COUPLE_TRAILER, 
--          STEP_4_PARK_DOCK, STEP_5_ENTER_FORKLIFT, STEP_6_LOAD_PALLETS, 
--          STEP_7_SECURE_PALLETS, STEP_8_DELIVERY

local JobEntities = {
    truck = nil,
    trailer = nil,
    forklift = nil,
    pallets = {}
}

local ActiveDeliveryPoint = nil
local DockWatcherPoint = nil

-- =======================================================================
-- HELPERS DE LIMPEZA E ESTADO
-- =======================================================================

local function CleanupCurrentJob()
    if Zones and Zones.ClearAllObjectives then
        Zones.ClearAllObjectives()
    end
    if Zones and Zones.Cleanup then
        pcall(function() Zones.Cleanup() end)
    end
    if ForkliftModule and ForkliftModule.StopOperation then
        ForkliftModule.StopOperation()
    end
    if CargoDry and CargoDry.Cleanup then
        pcall(function() CargoDry.Cleanup() end)
    end
    if CargoLiquid and CargoLiquid.Cleanup then
        pcall(function() CargoLiquid.Cleanup() end)
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

    ActiveJob = nil
    CurrentStage = 'IDLE'
    JobEntities = { truck = nil, trailer = nil, forklift = nil, pallets = {} }
    SetWaypointOff()
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
                return ActiveJob ~= nil and (CurrentStage ~= 'IDLE' and CurrentStage ~= 'STEP_8_DELIVERY')
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
        lib.notify({ title = 'Central Logística', description = 'Você já possui uma rota ou entrega em andamento!', type = 'error' })
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
-- ETAPA 3 & 4: MONITORAMENTO DE ENGATE DA CARRETA E BAÍA DE CARGA
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
                    -- STEP 3 CONCLUÍDO -> TRANSIÇÃO PARA STEP 4
                    CurrentStage = 'STEP_4_PARK_DOCK'
                    Zones.ClearObjective('trailer')

                    local dockCoords = Config.LoadingBayCoords or (Config.Polarix and Config.Polarix.Warehouse and Config.Polarix.Warehouse.LoadingBayCoords) or vector3(1244.53, -3135.57, 4.53)

                    -- STEP 3 VISUALS: Rota GPS e Ponto da Baía de Carregamento
                    Zones.TrackObjective('dock', {
                        coords = dockCoords,
                        label = 'Baía de Carregamento',
                        sprite = 477,
                        color = 2,
                        route = true,
                        offsetZ = 2.0
                    })

                    lib.notify({
                        title = 'Central Logística',
                        description = 'Carreta engatada! Dirija até a baía de carregamento demarcada.',
                        type = 'info',
                        duration = 10000
                    })

                    -- Monitoramento de estacionamento na baía
                    if DockWatcherPoint then pcall(function() DockWatcherPoint:remove() end) end
                    DockWatcherPoint = lib.points.new({
                        coords = dockCoords,
                        distance = 15.0,
                        nearby = function(self)
                            if CurrentStage ~= 'STEP_4_PARK_DOCK' then return end
                            local pedVeh = GetVehiclePedIsIn(cache.ped, false)
                            if pedVeh ~= 0 and pedVeh == JobEntities.truck then
                                local dist = #(GetEntityCoords(pedVeh) - dockCoords)
                                local speed = GetEntitySpeed(pedVeh)
                                if dist < 9.0 and speed < 1.2 then
                                    -- STEP 4 CONCLUÍDO -> TRANSIÇÃO PARA STEP 5
                                    CurrentStage = 'STEP_5_ENTER_FORKLIFT'
                                    self:remove()
                                    DockWatcherPoint = nil
                                    Zones.ClearObjective('dock')

                                    -- STEP 4 VISUALS: Seta flutuante verde e blip sobre a empilhadeira (Z + 2.5)
                                    Zones.TrackObjective('forklift', {
                                        netId = ActiveJob.forkliftNetId,
                                        entity = JobEntities.forklift,
                                        label = 'Empilhadeira de Carregamento',
                                        sprite = 543,
                                        color = 2,
                                        offsetZ = 2.5
                                    })

                                    lib.notify({
                                        title = 'Central Logística',
                                        description = 'Estacione o caminhão e assuma a empilhadeira para carregar os pallets.',
                                        type = 'info',
                                        duration = 10000
                                    })
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
-- ETAPA 7: AMARRAÇÃO DE CARGA (AMARRAR PALLETS)
-- =======================================================================

local function SetupStrappingStage()
    CurrentStage = 'STEP_7_SECURE_PALLETS'
    Zones.ClearAllObjectives()

    lib.notify({
        title = 'Central Logística',
        description = 'Carregamento concluído! Saia da empilhadeira, vá à traseira do caminhão e amarre a carga.',
        type = 'success',
        duration = 10000
    })

    if not JobEntities.trailer or not DoesEntityExist(JobEntities.trailer) then return end
    local rearPos = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)

    -- Seta verde exclusiva na traseira da carreta
    Zones.TrackObjective('strap_zone', {
        coords = rearPos,
        label = 'Amarração de Carga',
        sprite = 479,
        color = 2,
        offsetZ = 1.2
    })

    local targetAdded = false
    local function PerformStrapping()
        local success = lib.progressBar({
            duration = 5000,
            label = 'Amarrando pallets e travando carga...',
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
            Zones.ClearObjective('strap_zone')
            if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                pcall(function() exports.ox_target:removeLocalEntity(JobEntities.trailer) end)
            end
            TriggerServerEvent('aurp_trucker:server:strappingCompleted', ActiveJob.jobId)
        end
    end

    exports.ox_target:addLocalEntity(JobEntities.trailer, {
        {
            name = 'aust_strap_cargo',
            icon = 'fa-solid fa-link',
            label = 'Amarrar Pallets',
            distance = 3.5,
            canInteract = function()
                local ped = cache.ped or PlayerPedId()
                return CurrentStage == 'STEP_7_SECURE_PALLETS' and not IsPedInAnyVehicle(ped, false)
            end,
            onSelect = function()
                PerformStrapping()
            end
        }
    })
end

-- =======================================================================
-- ETAPA 8: ROTA FINAL, ENTREGA E DESCARREGAMENTO
-- =======================================================================

local function SetupDeliveryDestination(deliveryCoords, jobId)
    CurrentStage = 'STEP_8_DELIVERY'
    Zones.ClearAllObjectives()

    -- STEP 8 VISUALS: Blip de entrega com GPS ativo e seta flutuante verde
    Zones.TrackObjective('delivery', {
        coords = deliveryCoords,
        label = 'Destino da Entrega',
        sprite = 477,
        color = 2,
        route = true,
        offsetZ = 2.5
    })

    lib.notify({
        title = 'Central Logística',
        description = 'Carga amarrada com sucesso! Siga a rota indicada até o destino final.',
        type = 'success',
        duration = 10000
    })

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
                    lib.notify({ title = 'Central Logística', description = 'Estacione o caminhão e desembarque para descarregar!', type = 'error' })
                    return
                end

                lib.hideTextUI()
                local ok = lib.progressCircle({
                    duration = 6000,
                    position = 'bottom',
                    label = 'Descarregando mercadoria e finalizando serviço...',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
                })

                if ok then
                    Zones.ClearAllObjectives()
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

    -- STEP 2: Entrar no Caminhão
    if CurrentStage == 'STEP_2_ENTER_TRUCK' then
        if JobEntities.truck and veh == JobEntities.truck then
            CurrentStage = 'STEP_3_COUPLE_TRAILER'

            -- Remove seta e blip do caminhão
            Zones.ClearObjective('truck')

            -- Seta e blip permanecem exclusivamente na Carreta/Carga
            Zones.TrackObjective('trailer', {
                netId = ActiveJob.trailerNetId,
                entity = JobEntities.trailer,
                label = 'Carreta / Carga',
                sprite = 479,
                color = 2,
                offsetZ = 2.8
            })

            lib.notify({
                title = 'Central Logística',
                description = 'Engate a carreta na traseira do caminhão.',
                type = 'info',
                duration = 10000
            })

            StartCouplingWatcher()
        end
    end

    -- STEP 5 -> 6: Entrar na Empilhadeira
    if CurrentStage == 'STEP_5_ENTER_FORKLIFT' then
        if JobEntities.forklift and veh == JobEntities.forklift then
            CurrentStage = 'STEP_6_LOAD_PALLETS'

            -- Remove seta da empilhadeira
            Zones.ClearObjective('forklift')

            -- Transfere seta flutuante verde e blips para os pallets do pátio
            for i, pallet in ipairs(JobEntities.pallets) do
                if pallet and DoesEntityExist(pallet) and not IsEntityAttached(pallet) then
                    Zones.TrackObjective('pallet_' .. i, {
                        entity = pallet,
                        label = 'Pallet de Carga',
                        sprite = 478,
                        color = 2,
                        offsetZ = 1.0
                    })
                end
            end

            lib.notify({
                title = 'Central Logística',
                description = 'Utilize a empilhadeira para pegar os pallets no pátio.',
                type = 'info',
                duration = 10000
            })

            -- Inicia ciclo de manuseio com a tecla [G]
            ForkliftModule.StartOperation(ActiveJob.jobId, JobEntities.trailer, ActiveJob.requiredCount or 4, function(action, palletEnt, loaded, total)
                if action == 'picked' then
                    -- Remove setas dos pallets e aponta para a traseira do reboque
                    Zones.ClearAllObjectives()
                    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                        local rearCoords = GetOffsetFromEntityInWorldCoords(JobEntities.trailer, 0.0, -5.5, 0.5)
                        Zones.TrackObjective('trailer_rear', {
                            coords = rearCoords,
                            label = 'Posicionar no Caminhão',
                            sprite = 479,
                            color = 2,
                            offsetZ = 1.5
                        })
                    end
                elseif action == 'dropped' then
                    -- Palete acomodado: remove seta da traseira e restaura nos paletes pendentes
                    Zones.ClearObjective('trailer_rear')
                    for idx, p in ipairs(JobEntities.pallets) do
                        if p and DoesEntityExist(p) and not IsEntityAttached(p) then
                            Zones.TrackObjective('pallet_' .. idx, {
                                entity = p,
                                label = 'Pallet de Carga',
                                sprite = 478,
                                color = 2,
                                offsetZ = 1.0
                            })
                        end
                    end
                end
            end, function()
                -- Todos os paletes carregados!
                SetupStrappingStage()
            end)
        end
    end
end)

-- =======================================================================
-- EVENTOS DE REDE: INICIALIZAÇÃO E TRANSIÇÕES AUTORITATIVAS
-- =======================================================================

RegisterNetEvent('aurp_trucker:client:polarixJobStarted', function(payload)
    CleanupCurrentJob()
    ActiveJob = payload
    CurrentStage = 'STEP_1_START'

    CreateThread(function()
        -- STEP 1: Sincronização OneSync das Entidades
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
        end

        if forklift and DoesEntityExist(forklift) then
            SetVehicleOnGroundProperly(forklift)
            SetEntityCollision(forklift, true, true)
            SetVehicleDoorsLocked(forklift, 1)
            SetVehicleNeedsToBeHotwired(forklift, false)
            if exports.qbx_vehiclekeys then
                pcall(function() exports.qbx_vehiclekeys:GiveKeys(forklift) end)
            end
        end

        -- STEP 1 VISUALS: Blips e Setas Verdes Flutuantes Simultâneas (Caminhão e Carga)
        Zones.TrackObjective('truck', {
            netId = payload.truckNetId,
            entity = truck,
            label = 'Seu Caminhão',
            sprite = 477,
            color = 2,
            route = true,
            offsetZ = 2.8
        })

        Zones.TrackObjective('trailer', {
            netId = payload.trailerNetId,
            entity = trailer,
            label = 'Carreta / Carga',
            sprite = 479,
            color = 2,
            route = false,
            offsetZ = 2.8
        })

        -- Notificação inicial de 10 segundos
        lib.notify({
            title = 'Central Logística',
            description = 'Caminhão e carga liberados no pátio. Entre no caminhão para iniciar.',
            type = 'info',
            duration = 10000
        })

        CurrentStage = 'STEP_2_ENTER_TRUCK'
    end)
end)

RegisterNetEvent('aurp_trucker:client:polarixSyncPallets', function(palletNetIds)
    local pallets = {}
    for _, netId in ipairs(palletNetIds) do
        if netId ~= 0 and NetworkDoesNetworkIdExist(netId) then
            local ent = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(ent) then
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

    lib.notify({
        title = 'Central Logística',
        description = ('Entrega concluída com sucesso!\nPagamento: $%d creditado no banco\nXP Ganho: +%d'):format(
            summary.payment or 0,
            summary.xp or 0
        ),
        type = 'success',
        duration = 10000
    })
end)
