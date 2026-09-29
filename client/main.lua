-- =======================================================================
-- AUST_trucker — client/main.lua
-- Integração Polarix TruckerJob: Máquina de Estados do Serviço (5 Etapas)
-- Stack QBOX / OX: ox_lib, ox_target, OneSync Server-Side Truth
-- =======================================================================

local ForkliftModule = require('client.modules.forklift')

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
            title = 'Carga Industrial: Componentes Eletrônicos',
            description = 'Destino: Sandy Shores | Recompensa: $6.500 | 4 Paletes',
            icon = 'boxes-stacked',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Componentes Eletrônicos',
                    palletCount = 4,
                    level_required = 1,
                    trailerModel = 'trailers2'
                })
            end
        },
        {
            title = 'Carga Pesada: Maquinário & Ferramentas',
            description = 'Destino: Paleto Bay | Recompensa: $8.500 | 6 Paletes',
            icon = 'pallet',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Maquinário & Ferramentas',
                    palletCount = 6,
                    level_required = 1,
                    trailerModel = 'trailers2'
                })
            end
        },
        {
            title = 'Logística Express: Alimentos Refrigerados',
            description = 'Destino: Grapeseed | Recompensa: $5.200 | 4 Paletes',
            icon = 'snowflake',
            onSelect = function()
                TriggerServerEvent('aurp_trucker:server:startPolarixContract', {
                    name = 'Alimentos Refrigerados',
                    palletCount = 4,
                    level_required = 1,
                    trailerModel = 'trailers2'
                })
            end
        }
    }

    lib.registerContext({
        id = 'aust_polarix_contract_menu',
        title = 'Central de Cargas & Paletes',
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
    InspectedParts = {}
    CurrentStage = 'STATUS_INSPECTING'

    -- Garante que o caminhão inicia trancado
    SetVehicleDoorsLocked(truck, 2)

    local checkpoints = Config.Polarix.Inspection.Checkpoints
    local totalRequired = #checkpoints

    for _, cp in ipairs(checkpoints) do
        local cpOffset = cp.offset
        local cpPoint = lib.points.new({
            coords = GetOffsetFromEntityInWorldCoords(truck, cpOffset.x, cpOffset.y, cpOffset.z),
            distance = 1.8,
        })

        exports.ox_target:addLocalEntity(truck, {
            {
                name = 'inspect_' .. cp.id,
                icon = 'fa-solid fa-magnifying-glass',
                label = cp.label,
                distance = 2.2,
                canInteract = function()
                    return CurrentStage == 'STATUS_INSPECTING' and not InspectedParts[cp.id]
                end,
                onSelect = function()
                    local anim = Config.Polarix.Inspection.Animation
                    local success = lib.progressBar({
                        duration = Config.Polarix.Inspection.Duration or 3000,
                        label = cp.label .. '...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = anim.dict, clip = anim.clip }
                    })

                    if success then
                        InspectedParts[cp.id] = true
                        PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", 0)

                        local inspectedCount = 0
                        for _ in pairs(InspectedParts) do inspectedCount = inspectedCount + 1 end

                        lib.notify({
                            title = 'Inspeção de Segurança',
                            description = ('Item verificado (%d/%d)!'):format(inspectedCount, totalRequired),
                            type = 'inform'
                        })

                        if inspectedCount >= totalRequired then
                            -- Valida com o servidor e emite as chaves
                            TriggerServerEvent('aurp_trucker:server:inspectionCompleted', jobId)
                        end
                    end
                end
            }
        })
    end

    lib.notify({
        title = 'Inspeção Obrigatória',
        description = 'Realize a checagem nos pneus e motor do caminhão antes de ligar o veículo!',
        type = 'warning',
        duration = 8000
    })
end

-- =======================================================================
-- ETAPA 4: FIXAÇÃO DE CINTAS E ASSINATURA DE ROMANEIO
-- =======================================================================

local function SetupStrappingAndManifest(trailer, jobId)
    CurrentStage = 'STATUS_STRAPPING'

    exports.ox_target:addLocalEntity(trailer, {
        {
            name = 'strap_cargo_and_sign_manifest',
            icon = 'fa-solid fa-clipboard-check',
            label = Config.Polarix.Strapping.Label or 'Fixar Cintas de Carga e Assinar Romaneio',
            distance = 3.5,
            canInteract = function()
                return CurrentStage == 'STATUS_STRAPPING'
            end,
            onSelect = function()
                local anim = Config.Polarix.Strapping.Animation
                local success = lib.progressBar({
                    duration = Config.Polarix.Strapping.Duration or 4500,
                    label = 'Fixando cintas de catraca e validando romaneio...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = anim.dict, clip = anim.clip }
                })

                if success then
                    TriggerServerEvent('aurp_trucker:server:strappingCompleted', jobId)
                end
            end
        }
    })

    lib.notify({
        title = 'Carregamento Completo!',
        description = 'Vá até a traseira do reboque para travar as cintas e assinar o romaneio de carga.',
        type = 'success',
        duration = 9000
    })
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

    -- ox_lib point no destino para detectar aproximação sem Wait(0)
    ActiveDeliveryPoint = lib.points.new({
        coords = vector3(deliveryCoords.x, deliveryCoords.y, deliveryCoords.z),
        distance = 15.0,
        onEnter = function()
            lib.showTextUI('[E] Descarregar Mercadoria e Concluir Frete')
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        nearby = function()
            if IsControlJustPressed(0, 38) then -- Tecla E
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 then
                    lib.notify({ title = 'Entrega', description = 'Estacione o veículo e desembarque para descarregar!', type = 'error' })
                    return
                end

                lib.hideTextUI()
                local ok = lib.progressCircle({
                    duration = 6000,
                    position = 'bottom',
                    label = 'Descarregando paletes e registrando entrega...',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
                })

                if ok then
                    TriggerServerEvent('aurp_trucker:server:completePolarixDelivery', jobId)
                end
            end
        end
    })

    lib.notify({
        title = 'Manifesto Emitido',
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

        JobEntities.truck = truck
        JobEntities.trailer = trailer

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

            -- CLIENT-SIDE FALLBACK / SYNC (QBOX STANDARD):
            -- Explicitamente destranca as portas e garante chaves para o jogador
            SetVehicleDoorsLocked(truck, 1)
            SetVehicleNeedsToBeHotwired(truck, false)
            SetVehicleHasBeenOwnedByPlayer(truck, true)

            if exports.qbx_vehiclekeys then
                pcall(function() exports.qbx_vehiclekeys:GiveKeys(truck) end)
            end
            if exports.ox_fuel then
                pcall(function() exports.ox_fuel:SetFuel(truck, 100.0) end)
            end

            SetupVehicleInspection(truck, trailer, payload.jobId)
        end
    end)
end)

RegisterNetEvent('aurp_trucker:client:inspectionUnlocked', function(jobId, truckPlate, truckNetId)
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

    -- Configura o ox_target na carreta para receber os paletes
    if JobEntities.trailer and DoesEntityExist(JobEntities.trailer) then
        ForkliftModule.SetupTrailerTarget(JobEntities.trailer, jobId, function()
            return CurrentStage, ActiveJob.loadedCount or 0, ActiveJob.requiredCount or 4
        end)
    end

    lib.notify({
        title = 'Inspeção Aprovada!',
        description = 'Caminhão liberado e chaves recebidas! Vá até a empilhadeira para iniciar o carregamento.',
        type = 'success',
        duration = 8000
    })
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
