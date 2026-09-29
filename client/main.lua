-- =======================================================================
-- AUST_trucker — client/main.lua
-- Integração Polarix TruckerJob: Máquina de Estados do Serviço (5 Etapas)
-- Stack QBOX / OX: ox_lib, ox_target, OneSync Server-Side Truth
-- =======================================================================

local ForkliftModule = require('client.modules.forklift')
local Zones = nil
local ok, mod = pcall(require, 'client.zones')
if ok and mod then
    Zones = mod
else
    Zones = rawget(_G, 'Zones') or _G.Zones
end

local ActiveJob = nil
local CurrentStage = 'IDLE' -- IDLE, STATUS_INSPECTING, STATUS_LOADING, STATUS_STRAPPING, STATUS_IN_TRANSIT, STATUS_UNLOADING
local InspectedParts = {}
local JobEntities = {
    truck = nil,
    trailer = nil,
    forklift = nil,
    pallets = {}
}
local ActiveDeliveryPoint = nil
local ActiveBlips = {
    depot = nil,
    delivery = nil,
    dock = nil
}

-- =======================================================================
-- HELPERS DE LIMPEZA E BLIPS
-- =======================================================================

local function ClearBlips()
    for k, blip in pairs(ActiveBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
        ActiveBlips[k] = nil
    end
end

local function CleanupCurrentJob()
    ClearBlips()
    if Zones and Zones.Cleanup then Zones.Cleanup() end
    if CargoDry and CargoDry.Cleanup then CargoDry.Cleanup() end
    if CargoLiquid and CargoLiquid.Cleanup then CargoLiquid.Cleanup() end
    if ActiveDeliveryPoint then
        pcall(function() ActiveDeliveryPoint:remove() end)
        ActiveDeliveryPoint = nil
    end
    if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
        pcall(function() exports.ox_target:removeLocalEntity(JobEntities.truck) end)
    end
    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
        pcall(function() exports.ox_target:removeLocalEntity(JobEntities.trailer) end)
    end
    ActiveJob = nil
    CurrentStage = 'IDLE'
    InspectedParts = {}
    JobEntities = { truck = nil, trailer = nil, forklift = nil, pallets = {} }
    SetWaypointOff()
end

-- =======================================================================
-- ETAPA 1: INÍCIO DE TURNO E CONTRATO (NPC DESPACHANTE OX_TARGET)
-- =======================================================================

local function OpenPolarixContractMenu()
    if ActiveJob then
        lib.notify({ title = 'Logística', description = 'Você já possui um frete ativo em andamento!', type = 'error' })
        return
    end

    local options = {
        {
            title = 'Carga Seca: Componentes Eletrônicos',
            description = 'Destino: Sandy Shores | Recompensa: $6.500 | 4 Paletes (Empilhadeira)',
            icon = 'boxes-stacked',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Componentes Eletrônicos',
                    cargoType = 'dry',
                    palletCount = 4,
                    level_required = 1,
                    trailerModel = 'trailers2'
                })
            end
        },
        {
            title = 'Carga Seca: Maquinário & Ferramentas',
            description = 'Destino: Paleto Bay | Recompensa: $8.500 | 6 Paletes (Empilhadeira)',
            icon = 'pallet',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Maquinário & Ferramentas',
                    cargoType = 'dry',
                    palletCount = 6,
                    level_required = 1,
                    trailerModel = 'trailers2'
                })
            end
        },
        {
            title = 'Carga Líquida: Combustível Automotivo',
            description = 'Destino: LSIA Freight Yard | Recompensa: $7.200 | Tanque (Mangueira)',
            icon = 'gas-pump',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Combustível Automotivo',
                    cargoType = 'liquid',
                    palletCount = 100,
                    level_required = 1,
                    trailerModel = 'tanker'
                })
            end
        },
        {
            title = 'Carga Líquida: Querosene de Aviação',
            description = 'Destino: Sandy Shores | Recompensa: $8.900 | Tanque (Mangueira)',
            icon = 'oil-can',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Querosene de Aviação',
                    cargoType = 'liquid',
                    palletCount = 100,
                    level_required = 1,
                    trailerModel = 'tanker2'
                })
            end
        }
    }

    lib.registerContext({
        id = 'aust_polarix_contract_menu',
        title = 'Central de Cargas & Logística (Seca e Líquida)',
        options = options
    })
    lib.showContext('aust_polarix_contract_menu')
end

RegisterCommand('polarixcontract', function()
    OpenPolarixContractMenu()
end, false)

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
            name = 'aust_open_polarix_contracts',
            icon = 'fa-solid fa-clipboard-list',
            label = 'Contratos de Paletes & Carregamento',
            distance = 2.5,
            onSelect = function()
                OpenPolarixContractMenu()
            end
        },
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
            label = 'Repor Carga / Equipamento Perdido',
            distance = 2.5,
            canInteract = function()
                return ActiveJob ~= nil and (CurrentStage == 'STATUS_LOADING' or CurrentStage == 'STATUS_INSPECTING')
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
-- ETAPA 2: RETIRADA E INSPEÇÃO OBRIGATÓRIA DE SEGURANÇA
-- =======================================================================

local function SetupVehicleInspection(truck, trailer, jobId)
    CurrentStage = 'STATUS_INSPECTING'

    -- Garante que o caminhão inicia trancado
    SetVehicleDoorsLocked(truck, 2)

    local setupFn = (Zones and Zones.SetupInspection) or (_G.Zones and _G.Zones.SetupInspection)
    if setupFn then
        setupFn(truck, jobId, function()
            TriggerServerEvent('aurp_trucker:server:inspectionCompleted', jobId)
        end)
    else
        -- Fallback de emergência (ox_target direto) se módulo zones falhar
        exports.ox_target:addLocalEntity(truck, {
            {
                name = 'inspect_truck_safety',
                icon = 'fa-solid fa-magnifying-glass',
                label = 'Inspecionar Caminhão e Liberar Chaves',
                distance = 2.5,
                onSelect = function()
                    local ok = lib.progressBar({
                        duration = 3000,
                        label = 'Inspecionando veículo...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' }
                    })
                    if ok then
                        TriggerServerEvent('aurp_trucker:server:inspectionCompleted', jobId)
                    end
                end
            }
        })
        lib.notify({
            title = 'Inspeção de Segurança',
            description = 'Aproxime-se do caminhão para realizar a inspeção e receber as chaves!',
            type = 'inform'
        })
    end
end

-- =======================================================================
-- ETAPA 4: FIXAÇÃO DE CINTAS E ASSINATURA DE ROMANEIO
-- =======================================================================

local function SetupStrappingAndManifest(trailer, jobId)
    CurrentStage = 'STATUS_STRAPPING'

    local setupFn = (Zones and Zones.SetupStrappingAndManifest) or (_G.Zones and _G.Zones.SetupStrappingAndManifest)
    if setupFn then
        setupFn(trailer, jobId, function()
            TriggerServerEvent('aurp_trucker:server:strappingCompleted', jobId)
        end)
    else
        if trailer and DoesEntityExist(trailer) then
            exports.ox_target:addLocalEntity(trailer, {
                {
                    name = 'strap_cargo_manifest',
                    icon = 'fa-solid fa-clipboard-check',
                    label = 'Fixar Cintas e Assinar Romaneio',
                    distance = 3.5,
                    onSelect = function()
                        local ok = lib.progressBar({
                            duration = 3500,
                            label = 'Fixando cintas de carga...',
                            useWhileDead = false,
                            canCancel = true,
                            disable = { move = true, car = true, combat = true }
                        })
                        if ok then
                            TriggerServerEvent('aurp_trucker:server:strappingCompleted', jobId)
                        end
                    end
                }
            })
        else
            TriggerServerEvent('aurp_trucker:server:strappingCompleted', jobId)
        end
    end
end

-- =======================================================================
-- ETAPA 5: ROTA FINAL, ENTREGA E DESCARREGAMENTO
-- =======================================================================

local function SetupDeliveryDestination(deliveryCoords, jobId, trailer)
    CurrentStage = 'STATUS_IN_TRANSIT'

    ClearBlips()
    ActiveBlips.delivery = AddBlipForCoord(deliveryCoords.x, deliveryCoords.y, deliveryCoords.z)
    SetBlipSprite(ActiveBlips.delivery, 477)
    SetBlipColour(ActiveBlips.delivery, 5)
    SetBlipScale(ActiveBlips.delivery, 0.95)
    SetBlipRoute(ActiveBlips.delivery, true)
    SetBlipRouteColour(ActiveBlips.delivery, 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Entrega: " .. (ActiveJob and ActiveJob.cargoName or "Carga Geral"))
    EndTextCommandSetBlipName(ActiveBlips.delivery)
    SetNewWaypoint(deliveryCoords.x, deliveryCoords.y)

    local setupFn = (Zones and Zones.SetupDeliveryPoint) or (_G.Zones and _G.Zones.SetupDeliveryPoint)
    if setupFn then
        setupFn(deliveryCoords, jobId, function()
            TriggerServerEvent('aurp_trucker:server:completePolarixDelivery', jobId)
        end)
    else
        if ActiveDeliveryPoint then
            pcall(function() ActiveDeliveryPoint:remove() end)
        end
        ActiveDeliveryPoint = lib.points.new({
            coords = deliveryCoords,
            distance = 25.0,
            onEnter = function()
                lib.showTextUI('[E] Descarregar Mercadoria', { position = 'top-center' })
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            nearby = function()
                if IsControlJustPressed(0, 38) then
                    local ped = cache.ped or PlayerPedId()
                    if GetVehiclePedIsIn(ped, false) ~= 0 then
                        lib.notify({ title = 'Entrega', description = 'Estacione o caminhão e desembarque para descarregar!', type = 'error' })
                        return
                    end
                    lib.hideTextUI()
                    local ok = lib.progressCircle({
                        duration = 6000,
                        position = 'bottom',
                        label = 'Descarregando mercadoria...',
                        canCancel = true,
                        disable = { move = true, car = true, combat = true }
                    })
                    if ok then
                        TriggerServerEvent('aurp_trucker:server:completePolarixDelivery', jobId)
                    end
                end
            end
        })
    end

    lib.notify({
        title = 'Manifesto Emitido (Estado 4)',
        description = 'Carga assegurada e rota traçada no GPS! Dirija até o destino com segurança.',
        type = 'success',
        duration = 9000
    })
end

-- =======================================================================
-- CALLBACKS NUI: INICIAR ENTREGA (START DELIVERY)
-- =======================================================================

local function HandleStartDeliveryNUI(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeUI' })
    SendNUIMessage({ action = 'hide' })

    if ActiveJob then
        lib.notify({ title = 'Logística', description = 'Você já possui uma rota ou entrega em andamento!', type = 'error' })
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
-- EVENTOS DE REDE (RECEBIMENTO E MUDANÇA DE ESTADO)
-- =======================================================================

RegisterNetEvent('aurp_trucker:client:polarixJobStarted', function(payload)
    CleanupCurrentJob()
    ActiveJob = payload
    CurrentStage = 'STATUS_INSPECTING'

    CreateThread(function()
        -- Aguarda sincronização OneSync das entidades criadas pelo servidor
        local truck = nil
        local trailer = nil

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

        local forklift = nil
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

            -- Sincroniza placa e tuning/mods salvos do caminhão próprio
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

            -- ESTADO 2: Caminhão inicia trancado aguardando inspeção obrigatória
            SetVehicleDoorsLocked(truck, 2)
            SetVehicleNeedsToBeHotwired(truck, false)
            SetVehicleHasBeenOwnedByPlayer(truck, true)

            SetupVehicleInspection(truck, trailer, payload.jobId)
        end
    end)
end)

RegisterNetEvent('aurp_trucker:client:inspectionUnlocked', function(jobId, truckPlate, truckNetId, forkliftPlate)
    if not ActiveJob or ActiveJob.jobId ~= jobId then return end
    CurrentStage = 'STATUS_LOADING'

    if JobEntities.truck and DoesEntityExist(JobEntities.truck) then
        SetVehicleDoorsLocked(JobEntities.truck, 1)
        SetVehicleNeedsToBeHotwired(JobEntities.truck, false)

        -- Feedback sonoro e visual de destrancar
        PlaySoundFrontend(-1, "REMOTE_PLYR_DOOR_UNLOCK", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", 1)

        if exports.qbx_vehiclekeys then
            pcall(function() exports.qbx_vehiclekeys:GiveKeys(JobEntities.truck) end)
        end
        if exports.ox_fuel then
            pcall(function() exports.ox_fuel:SetFuel(JobEntities.truck, 100.0) end)
        end
    end

    -- BUG 3 RESOLUTION: Destrancar e sincronizar chaves da empilhadeira no cliente
    if JobEntities.forklift and DoesEntityExist(JobEntities.forklift) then
        SetVehicleDoorsLocked(JobEntities.forklift, 1)
        SetVehicleNeedsToBeHotwired(JobEntities.forklift, false)
        if exports.qbx_vehiclekeys then
            pcall(function() exports.qbx_vehiclekeys:GiveKeys(JobEntities.forklift) end)
        end
    end

    -- Bifurcação Multi-Cargas (Seca vs Líquida)
    if ActiveJob.cargoType == 'liquid' then
        if CargoLiquid and CargoLiquid.Setup then
            CargoLiquid.Setup(ActiveJob, JobEntities.trailer, JobEntities.truck)
        end
        lib.notify({
            title = 'Inspeção Aprovada!',
            description = 'Caminhão-tanque liberado e chaves recebidas! Vá até a bomba de combustível para retirar a mangueira.',
            type = 'success',
            duration = 8000
        })
    else
        if CargoDry and CargoDry.Setup then
            CargoDry.Setup(ActiveJob, JobEntities.trailer, JobEntities.truck)
        else
            if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
                ForkliftModule.SetupTrailerTarget(JobEntities.trailer, jobId, function()
                    return CurrentStage, ActiveJob.loadedCount or 0, ActiveJob.requiredCount or 4
                end)
            end
        end
        lib.notify({
            title = 'Inspeção Aprovada!',
            description = 'Caminhão liberado e chaves recebidas! Vá até a empilhadeira para iniciar o carregamento.',
            type = 'success',
            duration = 8000
        })
    end
end)

RegisterNetEvent('aurp_trucker:client:startStrappingStage', function(jobId)
    if not ActiveJob or ActiveJob.jobId ~= jobId then return end
    SetupStrappingAndManifest(JobEntities.trailer, jobId)
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

RegisterNetEvent('aurp_trucker:client:polarixProgressSync', function(loaded, required)
    if not ActiveJob then return end
    ActiveJob.loadedCount = loaded
    ActiveJob.requiredCount = required

    lib.notify({
        title = 'Palete Carregado',
        description = ('Carga acomodada com sucesso! (%d/%d)'):format(loaded, required),
        type = 'inform'
    })

    if loaded >= required then
        SetupStrappingAndManifest(JobEntities.trailer, ActiveJob.jobId)
    end
end)

RegisterNetEvent('aurp_trucker:client:polarixReadyForTransit', function(deliveryCoords)
    if not ActiveJob then return end
    SetupDeliveryDestination(deliveryCoords, ActiveJob.jobId, JobEntities.trailer)
end)

RegisterNetEvent('aurp_trucker:client:polarixJobFinished', function(summary)
    CleanupCurrentJob()
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    lib.notify({
        title = 'Frete Entregue!',
        description = ('Pagamento de $%d creditado no banco!\nXP Ganho: +%d | Rota: %.2f km'):format(
            summary.payment or 0,
            summary.xp or 0,
            summary.distance or 0.0
        ),
        type = 'success',
        duration = 10000
    })
end)
