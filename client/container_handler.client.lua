-- aurp_trucker — client/container_handler.client.lua
-- v20: Mecânica de Handler portuário com grua (bone frame_2)
-- Integrado com ProgressionService + CompanyService via lib.callback
-- Baseado em oConteneur — reescrito no padrão AUST_trucker

if not Config.ContainerHandler or not Config.ContainerHandler.Enabled then return end

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

-- 'idle' | 'pickup' | 'deliver' | 'done'
local CH_STATE    = 'idle'
local chHandler   = nil   -- entity: Handler vehicle
local chContainer = nil   -- entity: contêiner acoplado
local chJob       = nil   -- { containerLoc, deliverySlot, cargo }
local chBlip      = nil   -- blip temporário ativo
local chNpcTruck  = { cab = nil, trailer = nil, driver = nil }

-- ============================================================
-- HELPERS
-- ============================================================

local function ShowHint(msg, thisFrame)
    AddTextEntry('CH_HINT', msg)
    if thisFrame then
        DisplayHelpTextThisFrame('CH_HINT', false)
    else
        BeginTextCommandDisplayHelp('CH_HINT')
        EndTextCommandDisplayHelp(0, false, true, 4000)
    end
end

local function SetActiveBlip(x, y, z, blipCfg, route)
    if chBlip then RemoveBlip(chBlip) end
    chBlip = AddBlipForCoord(x, y, z)
    SetBlipSprite(chBlip, blipCfg.id)
    SetBlipColour(chBlip, blipCfg.color)
    SetBlipRoute(chBlip, route ~= false)
end

-- audit H-02: LoadModel carrega e aguarda o modelo, mas NÃO chama SetModelAsNoLongerNeeded.
-- O chamador (SpawnVeh/SpawnObj) é responsável por liberar após criar a entidade.
-- Chamar SetModelAsNoLongerNeeded antes do CreateVehicle pode fazer o GC desalocar o modelo.
local function LoadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 5000 do Wait(100); t = t + 100 end
    return HasModelLoaded(hash) and hash or nil
end

local function SpawnVeh(model, x, y, z, heading, isNetwork)
    local hash = LoadModel(model)
    if not hash then return nil end
    local veh = CreateVehicle(hash, x, y, z, heading, isNetwork ~= false, false)
    SetModelAsNoLongerNeeded(hash)  -- liberado APÓS criar entidade
    return (veh and veh ~= 0) and veh or nil
end

local function SpawnObj(model, x, y, z, heading)
    local hash = LoadModel(model)
    if not hash then return nil end
    local obj = CreateObjectNoOffset(hash, x, y, z, false, 0, false)
    SetModelAsNoLongerNeeded(hash)  -- liberado APÓS criar entidade
    if obj and obj ~= 0 and heading then
        SetEntityHeading(obj, heading)
    end
    return (obj and obj ~= 0) and obj or nil
end

-- ============================================================
-- SPAWN DO CAMINHÃO DE SAÍDA NO SLOT DE ENTREGA
-- Hauler + Flatbed congelados — partem após a entrega
-- ============================================================

local function SpawnExitTruck(slot)
    local cfg = Config.ContainerHandler.ExitTruck

    local trailerHash = LoadModel(cfg.trailer)
    local cabHash     = LoadModel(cfg.cab)
    local pedHash     = LoadModel(cfg.driver)
    if not trailerHash or not cabHash or not pedHash then return end

    local trailer = CreateVehicle(trailerHash, slot.x, slot.y, slot.z, slot.h, false, false)
    SetModelAsNoLongerNeeded(trailerHash)  -- audit H-02: liberar APÓS criar entidade
    if not trailer or trailer == 0 then return end

    -- Cab posicionado à frente do trailer
    local fwdX = GetEntityForwardX(trailer)
    local fwdY = GetEntityForwardY(trailer)
    local cab  = CreateVehicle(cabHash,
        slot.x + fwdX * 6.0,
        slot.y + fwdY * 6.0,
        slot.z, slot.h, false, false)
    SetModelAsNoLongerNeeded(cabHash)  -- audit H-02: liberar APÓS criar entidade
    if not cab or cab == 0 then
        SetEntityAsNoLongerNeeded(trailer)
        return
    end

    local driver = CreatePedInsideVehicle(cab, 26, pedHash, -1, false, false)
    SetModelAsNoLongerNeeded(pedHash)  -- audit H-02: liberar APÓS criar entidade

    FreezeEntityPosition(cab,     true)
    FreezeEntityPosition(trailer, true)

    chNpcTruck = { cab = cab, trailer = trailer, driver = driver }
end

-- ============================================================
-- CLEANUP GERAL
-- ============================================================

local function Cleanup()
    if CH_STATE == 'idle' then return end
    CH_STATE  = 'idle'
    chJob     = nil

    if chBlip then RemoveBlip(chBlip); chBlip = nil end

    if chContainer and DoesEntityExist(chContainer) then
        SetEntityAsNoLongerNeeded(chContainer)
    end
    chContainer = nil

    for _, v in pairs(chNpcTruck) do
        if v and DoesEntityExist(v) then SetEntityAsNoLongerNeeded(v) end
    end
    chNpcTruck = { cab = nil, trailer = nil, driver = nil }

    if chHandler and DoesEntityExist(chHandler) then
        SetEntityAsNoLongerNeeded(chHandler)
    end
    chHandler = nil

    TriggerServerEvent('aurp_trucker:containerHandler:cancel')
end

-- ============================================================
-- INICIAR MISSÃO
-- ============================================================

local function StartContainerMission()
    if CH_STATE ~= 'idle' then
        lib.notify({ title = 'Handler', description = 'Você já tem uma missão ativa', type = 'error' })
        return
    end

    -- Verificar se o spawn do Handler está livre
    local sp = Config.ContainerHandler.HandlerSpawn
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(v) - vector3(sp.x, sp.y, sp.z)) < 6.0 then
            lib.notify({ title = 'Handler', description = Config.ContainerHandler.BlockedSpawnMsg, type = 'error' })
            return
        end
    end

    -- Solicitar dados da missão ao servidor (location, slot, cargo)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:containerHandler:start', false)
    if not ok or not result or not result.success then
        lib.notify({
            title       = 'Handler',
            description = (result and result.reason) or 'Erro ao iniciar missão',
            type        = 'error',
        })
        return
    end

    chJob = result  -- { containerLoc, deliverySlot, cargo }

    -- Spawnar Handler e colocar jogador dentro
    local handler = SpawnVeh('handler', sp.x, sp.y, sp.z, sp.w, true)
    if not handler then
        lib.notify({ title = 'Handler', description = 'Erro ao spawnar Handler', type = 'error' })
        TriggerServerEvent('aurp_trucker:containerHandler:cancel')
        return
    end
    SetEntityAsMissionEntity(handler, true, true)
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(handler), true)
    SetPedIntoVehicle(PlayerPedId(), handler, -1)
    chHandler = handler

    -- Spawnar contêiner na localização de pickup
    local loc = chJob.containerLoc
    local container = SpawnObj(
        Config.ContainerHandler.ContainerModel,
        loc.x, loc.y, loc.z,
        loc.h + 90.0
    )
    if not container then
        lib.notify({ title = 'Handler', description = 'Erro ao spawnar contêiner', type = 'error' })
        Cleanup()
        return
    end
    SetEntityAsMissionEntity(container, true, true)
    chContainer = container

    -- Blip de pickup
    SetActiveBlip(loc.x, loc.y, loc.z, Config.ContainerHandler.BlipPickup, true)

    CH_STATE = 'pickup'

    lib.notify({
        title       = 'Handler Ativado!',
        description = ('Busque o contêiner com ~y~%s~s~ em ~y~%s'):format(
            chJob.cargo.name, loc.name
        ),
        type     = 'inform',
        duration = 8000,
    })
end

-- ============================================================
-- THREAD PRINCIPAL — mecânica do crane bone
-- Sleep dinâmico: 500ms idle, 0ms durante missão ativa
-- ============================================================

CreateThread(function()
    local HANDLER_HASH = Config.ContainerHandler.HandlerHash

    while true do
        local sleep = 500

        if CH_STATE ~= 'idle' and CH_STATE ~= 'done' then
            sleep = 0

            if DoesEntityExist(chContainer) then
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)

                -- Só processar se o jogador está no Handler correto
                if GetEntityModel(veh) == HANDLER_HASH then
                    local bone     = GetEntityBoneIndexByName(veh, Config.ContainerHandler.CraneBone)
                    local cranePos = GetWorldPositionOfEntityBone(veh, bone)

                    -- ── ESTADO: PICKUP ──────────────────────────────────
                    if CH_STATE == 'pickup' then
                        local loc  = chJob.containerLoc
                        local dist = #(vec3(cranePos.x, cranePos.y, cranePos.z)
                                     - vec3(loc.x, loc.y, loc.z))

                        if dist < 5.0 then
                            ShowHint(Config.ContainerHandler.PromptAttach, true)

                            if IsControlJustPressed(0, 47) then  -- G / INPUT_DETONATE
                                -- Acoplar contêiner na grua com suporte a 6DoF
                                local chOffX, chOffY, chOffZ = 0.0, 1.78, -2.5
                                local chPitch, chRoll, chYaw = 0.0, 0.0, 90.0
                                if GetVehiclePropOffset then
                                    local customOff, customRot = GetVehiclePropOffset(veh, GetEntityModel(chContainer))
                                    if customOff then
                                        chOffX, chOffY, chOffZ = customOff.x, customOff.y, customOff.z
                                        if customRot then
                                            chPitch, chRoll, chYaw = customRot.x, customRot.y, customRot.z
                                        end
                                    end
                                end

                                AttachEntityToEntity(
                                    chContainer, veh, bone,
                                    chOffX, chOffY, chOffZ,
                                    chPitch, chRoll, chYaw,
                                    false, false, true, false, 0, true
                                )

                                -- Trocar blip para entrega
                                local slot = chJob.deliverySlot
                                SetActiveBlip(slot.x, slot.y, slot.z, Config.ContainerHandler.BlipDelivery, true)

                                -- Spawnar caminhão de saída no slot (cinematic de entrega)
                                SpawnExitTruck(slot)

                                CH_STATE = 'deliver'

                                lib.notify({
                                    title       = 'Contêiner Acoplado!',
                                    description = ('Entregue em ~y~%s'):format(slot.name),
                                    type        = 'success',
                                })
                            end
                        end

                    -- ── ESTADO: DELIVER ─────────────────────────────────
                    elseif CH_STATE == 'deliver' then

                        -- Contêiner desacoplado sem confirmação = erro
                        if not IsEntityAttached(chContainer) then
                            lib.notify({ title = 'Handler', description = Config.ContainerHandler.DroppedMsg, type = 'error' })
                            Cleanup()
                        else
                            local slot = chJob.deliverySlot
                            local dist = #(vec3(cranePos.x, cranePos.y, cranePos.z)
                                         - vec3(slot.x, slot.y, slot.z))

                            if dist < 5.0 then
                                ShowHint(Config.ContainerHandler.PromptDetach, true)

                                if IsControlJustPressed(0, 47) then
                                    -- Desacoplar contêiner da grua
                                    DetachEntity(chContainer, false, true)

                                    CH_STATE = 'done'  -- evita o monitor de perda de contêiner

                                    -- Confirmar entrega no servidor e receber pagamento
                                    local ok2, result = pcall(lib.callback.await,
                                        'aurp_trucker:containerHandler:complete', false,
                                        { x = slot.x, y = slot.y, z = slot.z }
                                    )

                                    if ok2 and result and result.success then
                                        -- Ancorar contêiner no flatbed e liberar caminhão NPC
                                        if chNpcTruck.trailer and DoesEntityExist(chNpcTruck.trailer) then
                                            AttachEntityToEntity(
                                                chContainer, chNpcTruck.trailer, 0,
                                                0.0, 0.0, 0.35,
                                                0.0, 0.0, 0.0,
                                                false, false, false, false, 0, true
                                            )
                                        end
                                        if chNpcTruck.cab     and DoesEntityExist(chNpcTruck.cab)
                                        and chNpcTruck.driver and DoesEntityExist(chNpcTruck.driver)
                                        and chNpcTruck.trailer and DoesEntityExist(chNpcTruck.trailer)
                                        then
                                            FreezeEntityPosition(chNpcTruck.cab,     false)
                                            FreezeEntityPosition(chNpcTruck.trailer, false)
                                            AttachVehicleToTrailer(chNpcTruck.cab, chNpcTruck.trailer, 10.0)
                                            TaskVehicleDriveWander(chNpcTruck.driver, chNpcTruck.cab, 40.0, 786468)
                                        end

                                        lib.notify({
                                            title       = 'Entrega Concluída!',
                                            description = ('Recebeu ~g~$%d~s~ pela entrega do contêiner'):format(result.payment),
                                            type        = 'success',
                                            duration    = 8000,
                                        })
                                    else
                                        lib.notify({
                                            title       = 'Handler',
                                            description = (result and result.reason) or 'Erro ao registrar entrega',
                                            type        = 'error',
                                        })
                                    end

                                    -- Limpar referências locais (mantém NPC para animação de saída)
                                    if chBlip then RemoveBlip(chBlip); chBlip = nil end
                                    chJob       = nil
                                    chContainer = nil
                                    chNpcTruck  = { cab = nil, trailer = nil, driver = nil }

                                    -- Liberar Handler (jogador pode abandonar o veículo)
                                    if chHandler and DoesEntityExist(chHandler) then
                                        SetEntityAsNoLongerNeeded(chHandler)
                                        chHandler = nil
                                    end

                                    Wait(500)
                                    CH_STATE = 'idle'
                                end
                            end
                        end
                    end

                end  -- GetEntityModel check

            else
                -- Contêiner desapareceu sem confirmação de entrega
                if CH_STATE ~= 'done' then
                    lib.notify({ title = 'Handler', description = Config.ContainerHandler.LostMsg, type = 'error' })
                    Cleanup()
                end
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- NPC + BLIP PERMANENTE + OX_TARGET
-- ============================================================

CreateThread(function()
    Wait(2000)

    -- Blip permanente no mapa
    local permanentBlip = AddBlipForCoord(
        Config.ContainerHandler.NpcCoords.x,
        Config.ContainerHandler.NpcCoords.y,
        Config.ContainerHandler.NpcCoords.z
    )
    SetBlipSprite(permanentBlip,  Config.ContainerHandler.Blip.sprite)
    SetBlipDisplay(permanentBlip, 4)
    SetBlipScale(permanentBlip,   Config.ContainerHandler.Blip.scale)
    SetBlipColour(permanentBlip,  Config.ContainerHandler.Blip.color)
    SetBlipAsShortRange(permanentBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.ContainerHandler.Blip.label)
    EndTextCommandSetBlipName(permanentBlip)

    -- Spawnar NPC
    local npcHash = LoadModel(Config.ContainerHandler.NpcModel)
    if not npcHash then return end

    local c   = Config.ContainerHandler.NpcCoords
    local npc = CreatePed(4, npcHash, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(npc, true)
    FreezeEntityPosition(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    TaskStartScenarioInPlace(npc, 'WORLD_HUMAN_CLIPBOARD', 0, true)

    -- ox_target no NPC
    exports.ox_target:addLocalEntity(npc, {
        {
            name        = 'aurp_trucker:ch_start',
            icon        = 'fas fa-ship',
            label       = 'Iniciar Missão de Contêiner',
            distance    = 3.0,
            canInteract = function() return CH_STATE == 'idle' end,
            onSelect    = StartContainerMission,
        },
        {
            name        = 'aurp_trucker:ch_cancel',
            icon        = 'fas fa-times-circle',
            label       = 'Abandonar Missão',
            distance    = 3.0,
            canInteract = function() return CH_STATE ~= 'idle' end,
            onSelect    = function()
                lib.notify({ title = 'Handler', description = 'Missão abandonada', type = 'inform' })
                Cleanup()
            end,
        },
    })

    AddEventHandler('onResourceStop', function(r)
        if r ~= GetCurrentResourceName() then return end
        if DoesEntityExist(npc) then
            exports.ox_target:removeLocalEntity(npc)
            DeleteEntity(npc)
        end
        RemoveBlip(permanentBlip)
        Cleanup()
    end)
end)
