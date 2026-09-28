-- aurp_trucker — client/flatbed.client.lua
-- Sistema de flatbed integrado (adaptado de gs_flatbed cl_main.lua + cl_target.lua)
-- Expõe global Flatbed para uso por repo.client.lua

Flatbed = {}

local FLATBED_MODEL    = GetHashKey(Config.Flatbed.model)
local stateTimerConst  = {4.0, 2.0}
local soundId          = nil
local flatbedInAction  = false
local resourceStopping = false

-- ============================================================
-- HELPERS
-- ============================================================

local function lerp(start, finish, amount)
    return (1 - amount) * start + amount * finish
end

local function PlayBedSound(entity)
    if soundId then StopSound(soundId); ReleaseSoundId(soundId) end
    soundId = GetSoundId()
    PlaySoundFromEntity(soundId, 'OPENING', entity, 'DOOR_GARAGE', false, false)
end

local function ReleaseBedSound()
    if not soundId then return end
    StopSound(soundId)
    ReleaseSoundId(soundId)
    soundId = nil
end

local function GetStateCoords(entity)
    if not DoesEntityExist(entity) then return nil end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return nil end
    return Config.Flatbed.statePositions
end

local function DoesFlatbedHaveBedAndNotMoving(vehicle)
    return Entity(vehicle).state.bedProp ~= nil
       and not Entity(vehicle).state.bedMoving
end

-- ============================================================
-- LOW-LEVEL BED MOVEMENT (runs on entity owner client)
-- ============================================================

local function LowerFlatbedLocal(flatbedVehicle)
    if not DoesFlatbedHaveBedAndNotMoving(flatbedVehicle) then return end
    local stateCoords = GetStateCoords(flatbedVehicle)
    if not stateCoords then return end

    Entity(flatbedVehicle).state:set('bedMoving', true, true)
    local bedNet    = Entity(flatbedVehicle).state.bedProp
    local bedEntity = NetworkGetEntityFromNetworkId(bedNet)

    PlayBedSound(flatbedVehicle)
    local LERP_VALUE = 0.0
    local state = 0
    CreateThread(function()
        while true do
            if state == 2 then
                Entity(flatbedVehicle).state:set('bedLowered', true, true)
                Entity(flatbedVehicle).state:set('bedMoving', false, true)
                ReleaseBedSound()
                return
            end
            local offsetPos, offsetRot = {}, {}
            for i = 1, 3 do
                offsetPos[i] = lerp(stateCoords[state].pos[i], stateCoords[state + 1].pos[i], LERP_VALUE)
                offsetRot[i] = lerp(stateCoords[state].rot[i], stateCoords[state + 1].rot[i], LERP_VALUE)
            end
            AttachEntityToEntity(bedEntity, flatbedVehicle,
                GetEntityBoneIndexByName(flatbedVehicle, 'chassis'),
                offsetPos[1], offsetPos[2], offsetPos[3],
                offsetRot[1], offsetRot[2], offsetRot[3],
                false, false, false, false, 0, 2)
            LERP_VALUE = LERP_VALUE + (1.0 * GetFrameTime()) / stateTimerConst[state + 1]
            if LERP_VALUE >= 1.0 then LERP_VALUE = 0.0; state = state + 1 end
            Wait(0)
        end
    end)
end

local function RaiseFlatbedLocal(flatbedVehicle)
    if not DoesFlatbedHaveBedAndNotMoving(flatbedVehicle) then return end
    local stateCoords = GetStateCoords(flatbedVehicle)
    if not stateCoords then return end

    Entity(flatbedVehicle).state:set('bedMoving', true, true)
    local bedNet    = Entity(flatbedVehicle).state.bedProp
    local bedEntity = NetworkGetEntityFromNetworkId(bedNet)

    PlayBedSound(flatbedVehicle)
    local LERP_VALUE = 0.0
    local state = 2
    CreateThread(function()
        while true do
            if state == 0 then
                Entity(flatbedVehicle).state:set('bedLowered', false, true)
                Entity(flatbedVehicle).state:set('bedMoving', false, true)
                ReleaseBedSound()
                return
            end
            local offsetPos, offsetRot = {}, {}
            for i = 1, 3 do
                offsetPos[i] = lerp(stateCoords[state].pos[i], stateCoords[state - 1].pos[i], LERP_VALUE)
                offsetRot[i] = lerp(stateCoords[state].rot[i], stateCoords[state - 1].rot[i], LERP_VALUE)
            end
            AttachEntityToEntity(bedEntity, flatbedVehicle,
                GetEntityBoneIndexByName(flatbedVehicle, 'chassis'),
                offsetPos[1], offsetPos[2], offsetPos[3],
                offsetRot[1], offsetRot[2], offsetRot[3],
                false, false, false, false, 0, 2)
            LERP_VALUE = LERP_VALUE + (1.0 * GetFrameTime()) / stateTimerConst[state]
            if LERP_VALUE >= 1.0 then LERP_VALUE = 0.0; state = state - 1 end
            Wait(0)
        end
    end)
end

local function AttachVehicleLocal(flatbedVehicle, vehicleToAttach)
    if not DoesEntityExist(vehicleToAttach) then return end
    if not DoesFlatbedHaveBedAndNotMoving(flatbedVehicle) then return end

    local bedNet      = Entity(flatbedVehicle).state.bedProp
    local bedEntity   = NetworkGetEntityFromNetworkId(bedNet)
    local vehRot      = GetEntityRotation(vehicleToAttach, 2)
    local bedRot      = GetEntityRotation(bedEntity, 2)
    local rotOffsetZ  = vehRot.z - bedRot.z
    local vehCoords   = GetEntityCoords(vehicleToAttach)
    local bedOffset   = GetOffsetFromEntityGivenWorldCoords(bedEntity, vehCoords.x, vehCoords.y, vehCoords.z)

    AttachEntityToEntity(vehicleToAttach, bedEntity, 0,
        bedOffset.x, bedOffset.y, bedOffset.z + 0.025,
        0.0, 0.0, rotOffsetZ,
        0, 0, false, false, 2, true)
end

local function DetachVehicleLocal(vehicleToDetach)
    if not DoesEntityExist(vehicleToDetach) then return end
    DetachEntity(vehicleToDetach, false, true)
    SetVehicleOnGroundProperly(vehicleToDetach)
end

-- ============================================================
-- ORIGIN FUNCTIONS (decide entre local e relay via server)
-- ============================================================

local function OriginLower(flatbedVehicle)
    if NetworkGetEntityOwner(flatbedVehicle) == PlayerId() then
        LowerFlatbedLocal(flatbedVehicle)
    else
        TriggerServerEvent('aurp_trucker:flatbed:LowerFlatbed',
            NetworkGetNetworkIdFromEntity(flatbedVehicle))
    end
end

local function OriginRaise(flatbedVehicle)
    if NetworkGetEntityOwner(flatbedVehicle) == PlayerId() then
        RaiseFlatbedLocal(flatbedVehicle)
    else
        TriggerServerEvent('aurp_trucker:flatbed:RaiseFlatbed',
            NetworkGetNetworkIdFromEntity(flatbedVehicle))
    end
end

local function OriginAttach(flatbedVehicle, vehicleToAttach)
    if NetworkGetEntityOwner(vehicleToAttach) == PlayerId() then
        AttachVehicleLocal(flatbedVehicle, vehicleToAttach)
        Entity(flatbedVehicle).state:set('attachedVehicle', VehToNet(vehicleToAttach), true)
    else
        TriggerServerEvent('aurp_trucker:flatbed:AttachVehicle',
            NetworkGetNetworkIdFromEntity(flatbedVehicle),
            NetworkGetNetworkIdFromEntity(vehicleToAttach))
    end
end

local function OriginDetach(flatbedVehicle)
    local attachedNetId = Entity(flatbedVehicle).state.attachedVehicle
    if not attachedNetId or attachedNetId == -1 then return end
    local attachedVeh = NetToVeh(attachedNetId)
    if not DoesEntityExist(attachedVeh) then return end

    if NetworkGetEntityOwner(attachedVeh) == PlayerId() then
        DetachVehicleLocal(attachedVeh)
        Entity(flatbedVehicle).state:set('attachedVehicle', -1, true)
    else
        TriggerServerEvent('aurp_trucker:flatbed:DetachVehicle',
            NetworkGetNetworkIdFromEntity(flatbedVehicle),
            attachedNetId)
    end
end

-- ============================================================
-- ANIMAÇÃO DO OPERADOR
-- ============================================================

local currentAnimProp = nil

local function HandleAnimation()
    local ped  = PlayerPedId()
    local anim = Config.Flatbed.animation
    RequestAnimDict(anim.dict)
    while not HasAnimDictLoaded(anim.dict) do Wait(10) end
    RequestModel(anim.prop_model)
    while not HasModelLoaded(anim.prop_model) do Wait(10) end

    local prop = CreateObject(anim.prop_model, 0, 0, 0, true, true, true)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, anim.prop_bone),
        anim.prop_placement[1], anim.prop_placement[2], anim.prop_placement[3],
        anim.prop_placement[4], anim.prop_placement[5], anim.prop_placement[6],
        true, true, false, true, 1, true)
    TaskPlayAnim(ped, anim.dict, anim.anim, 8.0, -8.0, -1, 1, 0, false, false, false)
    currentAnimProp = prop
end

local function CancelAnimation()
    ClearPedTasks(PlayerPedId())
    if currentAnimProp and DoesEntityExist(currentAnimProp) then
        DeleteEntity(currentAnimProp)
        currentAnimProp = nil
    end
end

-- ============================================================
-- NETWORK EVENTS (recebidos de sv_main ou do próprio client)
-- ============================================================

RegisterNetEvent('aurp_trucker:flatbed:AttachBedToVehicle')
AddEventHandler('aurp_trucker:flatbed:AttachBedToVehicle', function(vehicleNetId, bedNetId)
    local startTime = GetGameTimer()
    while not NetworkDoesNetworkIdExist(bedNetId)
       and GetGameTimer() - startTime < 1000 do Wait(10) end

    if not NetworkDoesNetworkIdExist(bedNetId) then
        TriggerServerEvent('aurp_trucker:flatbed:DeleteBedEntity', vehicleNetId, bedNetId)
        return
    end

    local flatbedVehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    local bedEntity
    local bedWaitStart = GetGameTimer()
    while true do
        bedEntity = NetworkGetEntityFromNetworkId(bedNetId)
        if DoesEntityExist(bedEntity) then break end
        if GetGameTimer() - bedWaitStart > 3000 then
            TriggerServerEvent('aurp_trucker:flatbed:DeleteBedEntity', vehicleNetId, bedNetId)
            return
        end
        Wait(10)
    end

    local stateCoords = Config.Flatbed.statePositions
    AttachEntityToEntity(bedEntity, flatbedVehicle,
        GetEntityBoneIndexByName(flatbedVehicle, 'chassis'),
        stateCoords[0].pos[1], stateCoords[0].pos[2], stateCoords[0].pos[3],
        stateCoords[0].rot[1], stateCoords[0].rot[2], stateCoords[0].rot[3],
        false, false, false, false, 0, 2)

    if not IsEntityAttachedToEntity(bedEntity, flatbedVehicle) then
        TriggerServerEvent('aurp_trucker:flatbed:DeleteBedEntity', vehicleNetId, bedNetId)
    end
end)

RegisterNetEvent('aurp_trucker:flatbed:LowerFlatbedClient')
AddEventHandler('aurp_trucker:flatbed:LowerFlatbedClient', function(vehicleNetId)
    LowerFlatbedLocal(NetworkGetEntityFromNetworkId(vehicleNetId))
end)

RegisterNetEvent('aurp_trucker:flatbed:RaiseFlatbedClient')
AddEventHandler('aurp_trucker:flatbed:RaiseFlatbedClient', function(vehicleNetId)
    RaiseFlatbedLocal(NetworkGetEntityFromNetworkId(vehicleNetId))
end)

RegisterNetEvent('aurp_trucker:flatbed:AttachVehicleClient')
AddEventHandler('aurp_trucker:flatbed:AttachVehicleClient', function(flatbedNetId, vehicleToAttachNetId)
    AttachVehicleLocal(
        NetworkGetEntityFromNetworkId(flatbedNetId),
        NetworkGetEntityFromNetworkId(vehicleToAttachNetId))
end)

RegisterNetEvent('aurp_trucker:flatbed:DetachVehicleClient')
AddEventHandler('aurp_trucker:flatbed:DetachVehicleClient', function(vehicleToAttachNetId)
    DetachVehicleLocal(NetworkGetEntityFromNetworkId(vehicleToAttachNetId))
end)

-- ============================================================
-- GLOBAL Flatbed — API usada por repo.client.lua
-- ============================================================

---Spawna flatbed3 em coords/heading. Retorna netId.
function Flatbed.Spawn(coords, heading)
    local modelHash = FLATBED_MODEL
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    local veh = CreateVehicle(modelHash, coords.x, coords.y, coords.z, heading, true, false)
    local startTime = GetGameTimer()
    while not DoesEntityExist(veh) and GetGameTimer() - startTime < 5000 do Wait(10) end

    SetVehicleEngineOn(veh, false, true, false)
    SetVehicleDoorsLocked(veh, 4)
    SetEntityAsMissionEntity(veh, true, true)
    SetModelAsNoLongerNeeded(modelHash)
    return NetworkGetNetworkIdFromEntity(veh)
end

---Abaixa a cama do flatbed (com animação de operador).
function Flatbed.LowerBed(flatbedEntity)
    if flatbedInAction then return end
    flatbedInAction = true
    HandleAnimation()
    Wait(Config.Flatbed.animation.duration)
    CancelAnimation()
    OriginLower(flatbedEntity)
    flatbedInAction = false
end

---Registra ox_target "Carregar Veículo" no flatbed.
---onAttached() é chamado quando statebag attachedVehicle != -1.
function Flatbed.RegisterAttachTarget(flatbedEntity, targetEntity, onAttached)
    exports.ox_target:addLocalEntity(flatbedEntity, {
        {
            name     = 'repo_attach_vehicle',
            label    = 'Carregar Veículo',
            icon     = 'fas fa-truck-loading',
            distance = 4.0,
            onSelect = function()
                if flatbedInAction then return end
                flatbedInAction = true
                HandleAnimation()
                Wait(Config.Flatbed.animation.duration)
                CancelAnimation()
                OriginAttach(flatbedEntity, targetEntity)
                flatbedInAction = false

                -- Aguardar até 10s para statebag confirmar attach
                local waitStart = GetGameTimer()
                CreateThread(function()
                    while GetGameTimer() - waitStart < 10000 do
                        if Entity(flatbedEntity).state.attachedVehicle ~= -1 then
                            -- Levantar cama e aguardar animação terminar antes de chamar callback
                            Wait(500)
                            OriginRaise(flatbedEntity)
                            -- Aguardar bedMoving = false (animação de subir concluída)
                            local raiseStart = GetGameTimer()
                            while Entity(flatbedEntity).state.bedMoving
                               and GetGameTimer() - raiseStart < 8000 do
                                Wait(200)
                            end
                            if onAttached then onAttached() end
                            return
                        end
                        Wait(200)
                    end
                end)
            end,
        },
    })
end

---Remove ox_target e detach (cleanup parcial — não despawna).
function Flatbed.Detach(flatbedEntity)
    if DoesEntityExist(flatbedEntity) then
        exports.ox_target:removeLocalEntity(flatbedEntity, { 'repo_attach_vehicle' })
        OriginDetach(flatbedEntity)
    end
end

---Despawna flatbed e limpa statebags.
function Flatbed.Despawn(flatbedEntity)
    if not DoesEntityExist(flatbedEntity) then return end
    exports.ox_target:removeLocalEntity(flatbedEntity, { 'repo_attach_vehicle' })
    local bedNetId = Entity(flatbedEntity).state.bedProp
    if bedNetId then
        local bedEnt = NetworkGetEntityFromNetworkId(bedNetId)
        if DoesEntityExist(bedEnt) then DeleteEntity(bedEnt) end
    end
    DeleteVehicle(flatbedEntity)
end

-- ============================================================
-- SYNC: reagir a mudanças de attachedVehicle para todos os clientes (6C)
-- Propaga attach/detach do flatbed via OneSync StateBag sem tráfego adicional.
-- Guard: entity owner ignorado — já processou localmente via OriginAttach/OriginDetach.
-- ============================================================

AddStateBagChangeHandler('attachedVehicle', nil, function(bagName, _, value, _, _)
    if resourceStopping then return end
    -- Ignorar key deletions (resource restart / entity cleanup) — value nil não é gameplay (fix #6)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not entity or not DoesEntityExist(entity) then return end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return end

    -- Entity owner já fez o attach/detach localmente; não re-processar
    if NetworkGetEntityOwner(entity) == PlayerId() then return end

    if value ~= -1 then
        -- Outro cliente carregou um veículo: replicar attach localmente
        local targetVeh = NetToVeh(value)
        if DoesEntityExist(targetVeh) then
            AttachVehicleLocal(entity, targetVeh)
        end
    else
        -- Veículo descarregado: encontrar qual veículo está attachado ao bed e detachar
        local bedNetId = Entity(entity).state.bedProp
        if not bedNetId then return end
        local bedEnt = NetworkGetEntityFromNetworkId(bedNetId)
        if not DoesEntityExist(bedEnt) then return end

        local allVehs = GetGamePool('CVehicle')
        for _, veh in ipairs(allVehs) do
            if IsEntityAttachedToEntity(veh, bedEnt) then
                DetachVehicleLocal(veh)
                break
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    resourceStopping = true
    ReleaseBedSound()
end)
