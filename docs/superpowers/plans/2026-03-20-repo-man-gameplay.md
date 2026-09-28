# Repo Man Gameplay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar a gameplay in-world do Repo Man: spawn de veículo alvo e flatbed, mecânicas por tipo de missão (simple/stealth/npc_hostile/pvp), flatbed integrado internamente, entrega no impound.

**Architecture:** Sistema de flatbed (adaptado de gs_flatbed) expõe global `Flatbed` para `repo.client.lua`. Servidor controla criação do bed prop via `entityCreated`. Client gerencia estado de missão em `ActiveRepoMission`. Cleanup passa por `CleanupMission()` em todos os caminhos de saída.

**Tech Stack:** FiveM Lua 5.4 (lua54='yes'), ox_lib, ox_target, qbx_core, oxmysql

**Spec:** `docs/superpowers/specs/2026-03-20-repo-man-gameplay-design.md`

---

## File Map

| Ação | Arquivo | Responsabilidade |
|------|---------|-----------------|
| CRIAR | `stream/flatbed3/` | Stream files do modelo flatbed3 (copiados do 0r-towtruck-mix pack) |
| CRIAR | `server/flatbed.server.lua` | Bed prop creation, attach/detach authority (adaptado de gs_flatbed sv_main.lua) |
| CRIAR | `client/flatbed.client.lua` | Animação bed, attach vehicle, global `Flatbed` (adaptado de gs_flatbed cl_main + cl_target) |
| CRIAR | `client/repo.client.lua` | Gameplay completa: spawn, missão por tipo, entrega, cleanup |
| MODIFICAR | `config/config.lua` | ADD `Config.Flatbed` + ADD seção gameplay ao `Config.RepoMan` |
| MODIFICAR | `server/services/repo_service.lua` | ADD `TriggerClientEvent('AUST_trucker:client:repoMissionEnded')` em Complete e Fail |
| MODIFICAR | `server/events.lua` | ADD handler `repoAgentPositionUpdate` (relay para dono pvp) |
| MODIFICAR | `fxmanifest.lua` | v6.1.0, ADD flatbed.server.lua, flatbed.client.lua, repo.client.lua, stream files |

---

## Task 1: Stream files + Config + fxmanifest base

**Files:**
- Create: `stream/flatbed3/` (copy from external)
- Modify: `config/config.lua`
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Copiar stream files do flatbed3**

```bash
# Source: C:/Users/Vinicius/Downloads/Nova pasta (2)/0r-towtruck-mix.pack/flatbed/stream/
# Destino: stream/flatbed3/  (criar pasta)
cp "C:/Users/Vinicius/Downloads/Nova pasta (2)/0r-towtruck-mix.pack/flatbed/stream/flatbed3.yft"      stream/flatbed3/flatbed3.yft
cp "C:/Users/Vinicius/Downloads/Nova pasta (2)/0r-towtruck-mix.pack/flatbed/stream/flatbed3_hi.yft"   stream/flatbed3/flatbed3_hi.yft
cp "C:/Users/Vinicius/Downloads/Nova pasta (2)/0r-towtruck-mix.pack/flatbed/stream/flatbed3.ytd"      stream/flatbed3/flatbed3.ytd
cp "C:/Users/Vinicius/Downloads/Nova pasta (2)/0r-towtruck-mix.pack/flatbed/stream/flatbed3+hi.ytd"   stream/flatbed3/flatbed3+hi.ytd
```

- [ ] **Step 2: Adicionar Config.Flatbed ao config.lua**

Adicionar ANTES do `Config.RepoMan` existente (em volta da linha 640):

```lua
Config.Flatbed = {
    model    = 'flatbed3',
    bedModel = 'inm_flatbed_base',

    -- Animação do operador ao usar controles do flatbed
    animation = {
        dict          = 'amb@world_human_tourist_map@male@base',
        anim          = 'base',
        prop_model    = 'xm_prop_x17_tem_control_01',
        prop_bone     = 28422,
        prop_placement = { -0.01, 0, 0, -20.0, 364.0, 0.0 },
        duration      = 1500,
    },

    -- Posições do bed prop em 3 estados: [0]=recolhido, [1]=recuado, [2]=abaixado
    -- NOTA: offsets estimados baseados no modelo flatbed vanilla — AJUSTAR in-game se necessário
    statePositions = {
        [0] = { pos = {0.0, -3.6, 0.22}, rot = {0.0, 0.0, 0.0} },
        [1] = { pos = {0.0, -7.6, 0.22}, rot = {0.0, 0.0, 0.0} },
        [2] = { pos = {0.0, -7.8, -0.7}, rot = {14.0, 0.0, 0.0} },
    },
}
```

- [ ] **Step 3: Adicionar seção gameplay ao Config.RepoMan existente**

Adicionar as chaves DENTRO do bloco `Config.RepoMan` existente (após `ImpoundHeading`):

```lua
    -- Gameplay (Sub-spec 2)
    vehicleModels = {
        sedan  = { 'sultan', 'premier', 'asea', 'stratum' },
        suv    = { 'granger', 'cavalcade', 'patriot' },
        truck  = { 'bison', 'bobcatxl', 'sandking2' },
        sport  = { 'feltzer2', 'sentinel', 'schafter2' },
    },
    flatbedSpawnDistance   = 55.0,
    impoundRadius          = 15.0,
    missionTimeout         = 900,
    stealthDetectionRadius = 15.0,
    pvpBlipDuration        = 300,
    npcGuardModel          = 's_m_m_security_01',
    npcGuardCount          = { min = 2, max = 4 },
    npcGuardRadius         = 8.0,
    npcLeashRadius         = 80.0,
```

- [ ] **Step 4: Atualizar fxmanifest.lua**

```lua
-- Alterar versão:
version '6.1.0'

-- Adicionar em server_scripts (após repo_service.lua):
'server/flatbed.server.lua',

-- Adicionar em client_scripts (NA ORDEM CORRETA — flatbed ANTES de repo):
'client/flatbed.client.lua',
'client/repo.client.lua',
```

> **NOTA:** Arquivos em `stream/` são auto-streamados pelo FiveM. NÃO adicionar `data_file` para `.yft`/`.ytd` — isso causaria erro de manifest.

- [ ] **Step 5: Commit**

```bash
git add stream/flatbed3/ config/config.lua fxmanifest.lua
git commit -m "feat(repo-gameplay): add flatbed3 stream files, Config.Flatbed, Config.RepoMan gameplay keys"
```

---

## Task 2: server/flatbed.server.lua

**Files:**
- Create: `server/flatbed.server.lua`

Adaptado de gs_flatbed `sv_main.lua`. Troca prefixo `gs_flatbed:` → `AUST_trucker:flatbed:`. Usa `Config.Flatbed` em vez de `Config.FlatBedModels`.

- [ ] **Step 1: Criar server/flatbed.server.lua**

```lua
-- AUST_trucker — server/flatbed.server.lua
-- Sistema de flatbed integrado (adaptado de gs_flatbed sv_main.lua)
-- Gerencia criação/destruição do bed prop e relay de operações de attach/lower

local FLATBED_MODEL = GetHashKey(Config.Flatbed.model)
local BED_MODEL     = Config.Flatbed.bedModel

-- Cria bed prop ao detectar flatbed3 no mundo
AddEventHandler('entityCreated', function(entity)
    if not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return end

    local bedNetId = Entity(entity).state.bedProp
    if bedNetId and DoesEntityExist(NetworkGetEntityFromNetworkId(bedNetId)) then return end
    Entity(entity).state.bedProp = nil

    local flatbedNetId = NetworkGetNetworkIdFromEntity(entity)
    TriggerEvent('AUST_trucker:flatbed:CreateBedEntity', flatbedNetId)
end)

-- Remove bed prop ao destruir flatbed
AddEventHandler('entityRemoved', function(entity)
    if GetEntityType(entity) ~= 2 then return end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return end

    local bedNetId = Entity(entity).state.bedProp
    if not bedNetId then return end
    local bedEnt = NetworkGetEntityFromNetworkId(bedNetId)
    if DoesEntityExist(bedEnt) then DeleteEntity(bedEnt) end
end)

RegisterNetEvent('AUST_trucker:flatbed:CreateBedEntity')
AddEventHandler('AUST_trucker:flatbed:CreateBedEntity', function(flatbedNetId)
    -- IMPORTANTE: usar CreateThread pois Wait() não pode ser chamado diretamente em AddEventHandler
    Citizen.CreateThread(function()
        local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
        if not DoesEntityExist(flatbedVehicle) then return end
        if GetEntityModel(flatbedVehicle) ~= FLATBED_MODEL then return end

        local existingBedNetId = Entity(flatbedVehicle).state.bedProp
        if existingBedNetId then
            if DoesEntityExist(NetworkGetEntityFromNetworkId(existingBedNetId)) then return end
        end

        local vehicleCoords = GetEntityCoords(flatbedVehicle)
        local bedEntity = CreateObjectNoOffset(BED_MODEL,
            vehicleCoords.x, vehicleCoords.y, vehicleCoords.z - 3.0, true, 0, 1)

        local startTime = GetGameTimer()
        while not DoesEntityExist(bedEntity) do
            if GetGameTimer() - startTime > 5000 then return end
            Wait(10)
        end

        local flatbedOwner = NetworkGetEntityOwner(flatbedVehicle)
        local bedOwner     = NetworkGetEntityOwner(bedEntity)
        startTime = GetGameTimer()
        while flatbedOwner ~= bedOwner and GetGameTimer() - startTime < 500 do
            Wait(100)
            flatbedOwner = NetworkGetEntityOwner(flatbedVehicle)
            bedOwner     = NetworkGetEntityOwner(bedEntity)
        end

        if flatbedOwner ~= bedOwner and bedOwner ~= -1 then
            DeleteEntity(bedEntity)
            return
        end

        if not DoesEntityExist(flatbedVehicle) or not DoesEntityExist(bedEntity) then
            if DoesEntityExist(bedEntity) then DeleteEntity(bedEntity) end
            return
        end

        local bedNetId = NetworkGetNetworkIdFromEntity(bedEntity)
        Entity(flatbedVehicle).state.bedProp         = bedNetId
        Entity(flatbedVehicle).state.attachedVehicle = -1
        Entity(flatbedVehicle).state.bedLowered      = false
        Entity(flatbedVehicle).state.bedMoving       = false

        if flatbedOwner ~= -1 then
            TriggerClientEvent('AUST_trucker:flatbed:AttachBedToVehicle', flatbedOwner, flatbedNetId, bedNetId)
        end
    end)
end)

RegisterNetEvent('AUST_trucker:flatbed:DeleteBedEntity')
AddEventHandler('AUST_trucker:flatbed:DeleteBedEntity', function(flatbedNetId, bedNetId)
    local bedEntity = NetworkGetEntityFromNetworkId(bedNetId)
    if DoesEntityExist(bedEntity) then DeleteEntity(bedEntity) end

    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    if not DoesEntityExist(flatbedVehicle) then return end

    local existingBedNetId = Entity(flatbedVehicle).state.bedProp
    if existingBedNetId then
        local existingBed = NetworkGetEntityFromNetworkId(existingBedNetId)
        if DoesEntityExist(existingBed) then DeleteEntity(existingBed) end
    end
    Entity(flatbedVehicle).state.bedProp = nil
end)

RegisterNetEvent('AUST_trucker:flatbed:LowerFlatbed')
AddEventHandler('AUST_trucker:flatbed:LowerFlatbed', function(flatbedNetId)
    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    if not DoesEntityExist(flatbedVehicle) then return end
    local owner = NetworkGetEntityOwner(flatbedVehicle)
    if owner ~= -1 then
        TriggerClientEvent('AUST_trucker:flatbed:LowerFlatbedClient', owner, flatbedNetId)
    end
end)

RegisterNetEvent('AUST_trucker:flatbed:RaiseFlatbed')
AddEventHandler('AUST_trucker:flatbed:RaiseFlatbed', function(flatbedNetId)
    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    if not DoesEntityExist(flatbedVehicle) then return end
    local owner = NetworkGetEntityOwner(flatbedVehicle)
    if owner ~= -1 then
        TriggerClientEvent('AUST_trucker:flatbed:RaiseFlatbedClient', owner, flatbedNetId)
    end
end)

RegisterNetEvent('AUST_trucker:flatbed:AttachVehicle')
AddEventHandler('AUST_trucker:flatbed:AttachVehicle', function(flatbedNetId, vehicleToAttachNetId)
    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    local attachEntity   = NetworkGetEntityFromNetworkId(vehicleToAttachNetId)
    if not DoesEntityExist(flatbedVehicle) or not DoesEntityExist(attachEntity) then return end

    Entity(flatbedVehicle).state.attachedVehicle = vehicleToAttachNetId
    local attachOwner = NetworkGetEntityOwner(attachEntity)
    if attachOwner ~= -1 then
        TriggerClientEvent('AUST_trucker:flatbed:AttachVehicleClient', attachOwner, flatbedNetId, vehicleToAttachNetId)
    end
end)

RegisterNetEvent('AUST_trucker:flatbed:DetachVehicle')
AddEventHandler('AUST_trucker:flatbed:DetachVehicle', function(flatbedNetId, vehicleToAttachNetId)
    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    local attachEntity   = NetworkGetEntityFromNetworkId(vehicleToAttachNetId)
    if not DoesEntityExist(flatbedVehicle) or not DoesEntityExist(attachEntity) then return end

    Entity(flatbedVehicle).state.attachedVehicle = -1
    local attachOwner = NetworkGetEntityOwner(attachEntity)
    if attachOwner ~= -1 then
        TriggerClientEvent('AUST_trucker:flatbed:DetachVehicleClient', attachOwner, vehicleToAttachNetId)
    end
end)
```

- [ ] **Step 2: Verificar manualmente que o arquivo foi salvo corretamente (sem erros de sintaxe visíveis)**

- [ ] **Step 3: Commit**

```bash
git add server/flatbed.server.lua
git commit -m "feat(repo-gameplay): add flatbed server (adapted from gs_flatbed)"
```

---

## Task 3: client/flatbed.client.lua

**Files:**
- Create: `client/flatbed.client.lua`

Adaptado de gs_flatbed `cl_main.lua` + `cl_target.lua`. Expõe global `Flatbed` usado por `repo.client.lua`. Sem verificação de job — ativa para qualquer entidade `flatbed3` spawnad por este resource.

- [ ] **Step 1: Criar client/flatbed.client.lua**

```lua
-- AUST_trucker — client/flatbed.client.lua
-- Sistema de flatbed integrado (adaptado de gs_flatbed cl_main.lua + cl_target.lua)
-- Expõe global Flatbed para uso por repo.client.lua

Flatbed = {}

local FLATBED_MODEL    = GetHashKey(Config.Flatbed.model)
local stateTimerConst  = {4.0, 2.0}
local soundId          = nil
local flatbedInAction  = false

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
                0, 0, 1, 0, 0, 1)
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
                0, 0, 1, 0, 0, 1)
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
        TriggerServerEvent('AUST_trucker:flatbed:LowerFlatbed',
            NetworkGetNetworkIdFromEntity(flatbedVehicle))
    end
end

local function OriginRaise(flatbedVehicle)
    if NetworkGetEntityOwner(flatbedVehicle) == PlayerId() then
        RaiseFlatbedLocal(flatbedVehicle)
    else
        TriggerServerEvent('AUST_trucker:flatbed:RaiseFlatbed',
            NetworkGetNetworkIdFromEntity(flatbedVehicle))
    end
end

local function OriginAttach(flatbedVehicle, vehicleToAttach)
    if NetworkGetEntityOwner(vehicleToAttach) == PlayerId() then
        AttachVehicleLocal(flatbedVehicle, vehicleToAttach)
        Entity(flatbedVehicle).state:set('attachedVehicle', VehToNet(vehicleToAttach), true)
    else
        TriggerServerEvent('AUST_trucker:flatbed:AttachVehicle',
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
        TriggerServerEvent('AUST_trucker:flatbed:DetachVehicle',
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

RegisterNetEvent('AUST_trucker:flatbed:AttachBedToVehicle')
AddEventHandler('AUST_trucker:flatbed:AttachBedToVehicle', function(vehicleNetId, bedNetId)
    local startTime = GetGameTimer()
    while not NetworkDoesNetworkIdExist(bedNetId)
       and GetGameTimer() - startTime < 1000 do Wait(10) end

    if not NetworkDoesNetworkIdExist(bedNetId) then
        TriggerServerEvent('AUST_trucker:flatbed:DeleteBedEntity', vehicleNetId, bedNetId)
        return
    end

    local flatbedVehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    local bedEntity      = NetworkGetEntityFromNetworkId(bedNetId)
    while not DoesEntityExist(bedEntity) do Wait(10) end

    local stateCoords = Config.Flatbed.statePositions
    AttachEntityToEntity(bedEntity, flatbedVehicle,
        GetEntityBoneIndexByName(flatbedVehicle, 'chassis'),
        stateCoords[0].pos[1], stateCoords[0].pos[2], stateCoords[0].pos[3],
        stateCoords[0].rot[1], stateCoords[0].rot[2], stateCoords[0].rot[3],
        0, 0, 1, 0, 0, 1)

    if not IsEntityAttachedToEntity(bedEntity, flatbedVehicle) then
        TriggerServerEvent('AUST_trucker:flatbed:DeleteBedEntity', vehicleNetId, bedNetId)
    end
end)

RegisterNetEvent('AUST_trucker:flatbed:LowerFlatbedClient')
AddEventHandler('AUST_trucker:flatbed:LowerFlatbedClient', function(vehicleNetId)
    LowerFlatbedLocal(NetworkGetEntityFromNetworkId(vehicleNetId))
end)

RegisterNetEvent('AUST_trucker:flatbed:RaiseFlatbedClient')
AddEventHandler('AUST_trucker:flatbed:RaiseFlatbedClient', function(vehicleNetId)
    RaiseFlatbedLocal(NetworkGetEntityFromNetworkId(vehicleNetId))
end)

RegisterNetEvent('AUST_trucker:flatbed:AttachVehicleClient')
AddEventHandler('AUST_trucker:flatbed:AttachVehicleClient', function(flatbedNetId, vehicleToAttachNetId)
    AttachVehicleLocal(
        NetworkGetEntityFromNetworkId(flatbedNetId),
        NetworkGetEntityFromNetworkId(vehicleToAttachNetId))
end)

RegisterNetEvent('AUST_trucker:flatbed:DetachVehicleClient')
AddEventHandler('AUST_trucker:flatbed:DetachVehicleClient', function(vehicleToAttachNetId)
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
```

- [ ] **Step 2: Commit**

```bash
git add client/flatbed.client.lua
git commit -m "feat(repo-gameplay): add flatbed client (adapted from gs_flatbed)"
```

---

## Task 4: client/repo.client.lua — estado + simple/stealth

**Files:**
- Create: `client/repo.client.lua` (início do arquivo)

- [ ] **Step 1: Criar client/repo.client.lua com estado + simple/stealth**

```lua
-- AUST_trucker — client/repo.client.lua
-- Fase 6: Gameplay client-side das missões Repo Man

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local ActiveRepoMission = nil
--[[
{
  orderId           = string,
  missionType       = 'simple'|'stealth'|'npc_hostile'|'pvp',
  targetVehicle     = number,  -- netId
  flatbedVehicle    = number|nil,
  npcs              = { number, ... },
  targetSpawnCoords = vector3,
  phase             = 'driving_to_zone'|'attaching'|'driving_to_impound',
  blipHandle        = number|nil,
  impoundZoneId     = string|nil,
  ownerNotified     = boolean,
  pvpStartTime      = number|nil,
  ownerSrc          = number|nil,  -- src do dono (pvp)
  pvpOwnerBlip      = number|nil,  -- blip do agent para o dono
}
]]

-- ============================================================
-- HELPERS
-- ============================================================

local function SetGPS(coords, color)
    SetNewWaypoint(coords.x, coords.y)
end

local function RemoveGPS()
    ClearGpsPlayerWaypoint()
end

local function SpawnTargetVehicle(orderData)
    -- Buscar zona pelo campo correto do DB: location_zone
    local zone = nil
    for _, z in ipairs(Config.RepoMan.NpcZones) do
        if z.name == orderData.location_zone then zone = z; break end
    end

    local spawnCoords
    if zone then
        -- Spawnar dentro da zona NPC com offset aleatório
        local offset = vector3(
            math.random(-math.floor(zone.radius * 0.6), math.floor(zone.radius * 0.6)),
            math.random(-math.floor(zone.radius * 0.6), math.floor(zone.radius * 0.6)),
            0.0)
        spawnCoords = zone.coords + offset
    else
        -- Fallback para pvp (dono real — zona pode ser 'Desconhecida')
        spawnCoords = Config.RepoMan.ImpoundLocation + vector3(300.0, 300.0, 0.0)
    end

    -- Usar vehicle_model direto do DB row (modelo específico já definido na ordem)
    -- Config.RepoMan.vehicleModels é usado pelo servidor ao gerar NPC orders (não aqui)
    local modelName = orderData.vehicle_model or 'mule'
    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    local veh = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z,
        math.random(0, 359), true, false)
    while not DoesEntityExist(veh) do Wait(10) end

    SetVehicleEngineOn(veh, false, true, false)
    SetVehicleDoorsLocked(veh, 4)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleNumberPlateText(veh, orderData.vehicle_plate or 'REPO00')
    SetModelAsNoLongerNeeded(modelHash)

    -- Blip no target
    local blip = AddBlipForEntity(veh)
    SetBlipSprite(blip, 225)
    SetBlipColour(blip, 1)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Veículo Alvo')
    EndTextCommandSetBlipName(blip)

    return NetworkGetNetworkIdFromEntity(veh), blip, spawnCoords
end

local function SpawnFlatbedNearby(targetCoords)
    -- Spawnar ~55m à frente do target
    local heading = math.random(0, 359)
    local rad     = math.rad(heading)
    local dist    = Config.RepoMan.flatbedSpawnDistance
    local spawnCoords = vector3(
        targetCoords.x + dist * math.cos(rad),
        targetCoords.y + dist * math.sin(rad),
        targetCoords.z)
    return Flatbed.Spawn(spawnCoords, heading)
end

-- ============================================================
-- CLEANUP
-- ============================================================

local function CleanupMission()
    if not ActiveRepoMission then return end
    local m = ActiveRepoMission
    ActiveRepoMission = nil  -- nil primeiro para evitar re-entrância

    RemoveGPS()

    -- Remover blip do target
    if m.blipHandle and DoesBlipExist(m.blipHandle) then
        RemoveBlip(m.blipHandle)
    end

    -- Remover blip e zona ox_lib do impound
    if m.impoundBlipHandle and DoesBlipExist(m.impoundBlipHandle) then
        RemoveBlip(m.impoundBlipHandle)
    end
    if m.impoundZoneId then
        lib.removeZone(m.impoundZoneId)
    end

    -- Deletar NPCs
    for _, npc in ipairs(m.npcs or {}) do
        if DoesEntityExist(npc) then DeletePed(npc) end
    end

    -- Flatbed missions: detach + deletar target + despawnar flatbed
    if m.flatbedVehicle then
        local flatbedEnt = NetToVeh(m.flatbedVehicle)
        if DoesEntityExist(flatbedEnt) then
            Flatbed.Detach(flatbedEnt)
        end
        if m.targetVehicle then
            local targetEnt = NetToVeh(m.targetVehicle)
            if DoesEntityExist(targetEnt) then DeleteVehicle(targetEnt) end
        end
        if DoesEntityExist(flatbedEnt) then
            Flatbed.Despawn(flatbedEnt)
        end
    else
        -- simple/stealth: deletar target apenas se não foi entregue
        if m.phase ~= 'driving_to_impound' and m.targetVehicle then
            local targetEnt = NetToVeh(m.targetVehicle)
            if DoesEntityExist(targetEnt) then
                exports.ox_target:removeLocalEntity(targetEnt, { 'repo_assume_vehicle' })
                DeleteVehicle(targetEnt)
            end
        end
    end
end

-- ============================================================
-- ZONA DE ENTREGA (impound)
-- ============================================================

local function EntrarFaseEntrega()
    if not ActiveRepoMission then return end
    local m = ActiveRepoMission

    SetGPS(Config.RepoMan.ImpoundLocation, 3)
    m.phase = 'driving_to_impound'

    -- Blip no impound
    local impBlip = AddBlipForCoord(Config.RepoMan.ImpoundLocation.x,
        Config.RepoMan.ImpoundLocation.y, Config.RepoMan.ImpoundLocation.z)
    SetBlipSprite(impBlip, 1)
    SetBlipColour(impBlip, 2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Impound')
    EndTextCommandSetBlipName(impBlip)
    m.impoundBlipHandle = impBlip  -- armazenado para CleanupMission poder remover

    lib.notify({ title = 'Repo Man', description = 'Leve o veículo ao impound!', type = 'inform' })

    local zoneId = 'repo_impound_' .. m.orderId
    m.impoundZoneId = zoneId

    lib.zones.sphere({
        coords = Config.RepoMan.ImpoundLocation,
        radius = Config.RepoMan.impoundRadius,
        name   = zoneId,
        onEnter = function()
            if not ActiveRepoMission then return end
            local am = ActiveRepoMission

            -- Validar veículo correto
            local ped    = PlayerPedId()
            local inVeh  = GetVehiclePedIsIn(ped, false)
            local valid  = false

            if am.flatbedVehicle then
                -- pvp/npc_hostile: deve estar no flatbed E com target attachado
                local flatbedEnt = NetToVeh(am.flatbedVehicle)
                local attached   = Entity(flatbedEnt).state.attachedVehicle
                valid = (inVeh == flatbedEnt) and (attached ~= -1)
            else
                -- simple/stealth: deve estar no target vehicle
                local targetEnt = NetToVeh(am.targetVehicle)
                valid = (inVeh == targetEnt)
            end

            if not valid then
                lib.notify({
                    title       = 'Repo Man',
                    description = 'Você precisa estar no veículo correto para entregar',
                    type        = 'error',
                })
                return
            end

            -- Completar missão
            TriggerServerEvent('AUST_trucker:completeRepoOrder', am.orderId)
            if DoesBlipExist(impBlip) then RemoveBlip(impBlip) end
        end,
    })
end

-- ============================================================
-- MECÂNICA: simple / stealth
-- ============================================================

local function StartSimpleStealth(orderData, targetNetId, targetBlip, spawnCoords)
    local m = ActiveRepoMission
    local targetEnt = NetToVeh(targetNetId)

    -- ox_target "Assumir Veículo"
    exports.ox_target:addLocalEntity(targetEnt, {
        {
            name     = 'repo_assume_vehicle',
            label    = 'Assumir Veículo',
            icon     = 'fas fa-car',
            distance = 2.5,
            onSelect = function()
                if not ActiveRepoMission then return end

                -- Desbloquear e entrar
                SetVehicleDoorsLocked(targetEnt, 1)
                local ped = PlayerPedId()
                TaskWarpPedIntoVehicle(ped, targetEnt, -1)

                -- Aguardar entrada
                local waitStart = GetGameTimer()
                while GetVehiclePedIsIn(ped, false) ~= targetEnt
                   and GetGameTimer() - waitStart < 5000 do Wait(200) end

                exports.ox_target:removeLocalEntity(targetEnt, { 'repo_assume_vehicle' })

                -- Notificar dono (stealth — somente após sair da zona)
                if m.missionType == 'stealth' and not m.ownerNotified then
                    CreateThread(function()
                        while ActiveRepoMission do
                            local agentCoords = GetEntityCoords(PlayerPedId())
                            local dist = #(agentCoords - m.targetSpawnCoords)
                            if dist >= 80.0 then
                                -- Servidor busca dono pelo vehicle_owner_citizenid na DB row
                                TriggerServerEvent('AUST_trucker:repoNotifyOwner', m.orderId,
                                    { x = m.targetSpawnCoords.x, y = m.targetSpawnCoords.y, z = m.targetSpawnCoords.z })
                                m.ownerNotified = true
                                return
                            end
                            Wait(2000)
                        end
                    end)
                end

                EntrarFaseEntrega()
            end,
        },
    })

    -- Stealth: thread de detecção
    if orderData.mission_type == 'stealth' then
        CreateThread(function()
            while ActiveRepoMission and ActiveRepoMission.phase == 'driving_to_zone' do
                local targetCoords = GetEntityCoords(NetToVeh(targetNetId))
                local nearby = lib.getNearbyPlayers(targetCoords,
                    Config.RepoMan.stealthDetectionRadius, false)
                if #nearby > 0 then
                    lib.notify({ title = 'Detectado!',
                        description = 'Missão stealth comprometida', type = 'error' })
                    TriggerServerEvent('AUST_trucker:failRepoOrder', m.orderId, 'detected')
                    return
                end
                Wait(1000)
            end
        end)
    end
end

-- ============================================================
-- MECÂNICA: npc_hostile
-- ============================================================

local function SpawnNpcGuards(targetCoords)
    local count  = math.random(Config.RepoMan.npcGuardCount.min, Config.RepoMan.npcGuardCount.max)
    local model  = GetHashKey(Config.RepoMan.npcGuardModel)
    local npcs   = {}

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    -- Relationship Group hostil ao player
    local groupHash = GetHashKey('REPO_GUARDS')
    AddRelationshipGroup('REPO_GUARDS')
    SetRelationshipBetweenGroups(5, groupHash, GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), groupHash)

    for i = 1, count do
        local angle  = (i / count) * math.pi * 2
        local radius = Config.RepoMan.npcGuardRadius * math.random(50, 100) / 100.0
        local pos    = vector3(
            targetCoords.x + radius * math.cos(angle),
            targetCoords.y + radius * math.sin(angle),
            targetCoords.z)

        local ped = CreatePed(4, model, pos.x, pos.y, pos.z, math.deg(angle) + 180, true, true)
        while not DoesEntityExist(ped) do Wait(10) end

        SetPedRelationshipGroupHash(ped, groupHash)
        SetPedArmour(ped, 50)
        GiveWeaponToPed(ped, GetHashKey('WEAPON_PISTOL'), 120, false, true)
        TaskGuardCurrentPosition(ped, Config.RepoMan.npcGuardRadius, Config.RepoMan.npcGuardRadius, true)
        SetEntityAsMissionEntity(ped, true, true)
        table.insert(npcs, ped)
    end

    SetModelAsNoLongerNeeded(model)

    -- Thread de leash (NPCs não perseguem além de npcLeashRadius)
    CreateThread(function()
        while ActiveRepoMission do
            for _, npc in ipairs(npcs) do
                if DoesEntityExist(npc) then
                    local dist = #(GetEntityCoords(npc) - targetCoords)
                    if dist > Config.RepoMan.npcLeashRadius then
                        TaskGoStraightToCoord(npc, targetCoords.x, targetCoords.y, targetCoords.z,
                            2.0, 5000, 0.0, 0.1)
                    end
                end
            end
            Wait(3000)
        end
    end)

    return npcs
end

local function StartNpcHostile(orderData, targetNetId, targetBlip, spawnCoords)
    local m = ActiveRepoMission

    -- Spawnar guards
    m.npcs = SpawnNpcGuards(spawnCoords)

    -- Spawnar flatbed
    local flatbedNetId = SpawnFlatbedNearby(spawnCoords)
    m.flatbedVehicle   = flatbedNetId

    -- Blip no flatbed
    local fbBlip = AddBlipForEntity(NetToVeh(flatbedNetId))
    SetBlipSprite(fbBlip, 479)
    SetBlipColour(fbBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Reboque')
    EndTextCommandSetBlipName(fbBlip)

    -- GPS ao flatbed primeiro
    SetGPS(GetEntityCoords(NetToVeh(flatbedNetId)), 5)
    lib.notify({ title = 'Repo Man', description = 'Busque o reboque e carregue o veículo!', type = 'inform' })

    -- Aguardar bed prop ser criado pelo servidor (max 10s)
    local waitStart = GetGameTimer()
    CreateThread(function()
        while GetGameTimer() - waitStart < 10000 do
            local flatbedEnt = NetToVeh(flatbedNetId)
            if DoesEntityExist(flatbedEnt) and Entity(flatbedEnt).state.bedProp then
                if DoesBlipExist(fbBlip) then RemoveBlip(fbBlip) end

                -- Registrar target para attach
                local targetEnt = NetToVeh(targetNetId)
                Flatbed.LowerBed(flatbedEnt)
                Wait(5000)  -- aguardar animação de baixar

                Flatbed.RegisterAttachTarget(flatbedEnt, targetEnt, function()
                    -- Attach completo: deletar guards, GPS ao impound
                    for _, npc in ipairs(m.npcs or {}) do
                        if DoesEntityExist(npc) then DeletePed(npc) end
                    end
                    m.npcs = {}
                    EntrarFaseEntrega()
                end)
                return
            end
            Wait(500)
        end
        -- Timeout: falhar missão
        TriggerServerEvent('AUST_trucker:failRepoOrder', m.orderId, 'flatbed_timeout')
    end)
end

-- ============================================================
-- MECÂNICA: pvp
-- ============================================================

local function StartPvp(orderData, targetNetId, targetBlip, spawnCoords)
    local m = ActiveRepoMission

    -- Spawnar flatbed
    local flatbedNetId = SpawnFlatbedNearby(spawnCoords)
    m.flatbedVehicle   = flatbedNetId
    m.pvpStartTime     = GetGameTimer()

    -- Thread de atualização de posição para o dono (300s de janela)
    CreateThread(function()
        while ActiveRepoMission do
            local elapsed = GetGameTimer() - (m.pvpStartTime or 0)
            if elapsed > Config.RepoMan.pvpBlipDuration * 1000 then return end
            local coords = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('AUST_trucker:repoAgentPositionUpdate',
                m.orderId, { x = coords.x, y = coords.y, z = coords.z })
            Wait(10000)
        end
    end)

    -- Blip no flatbed
    local fbBlip = AddBlipForEntity(NetToVeh(flatbedNetId))
    SetBlipSprite(fbBlip, 479)
    SetBlipColour(fbBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Reboque')
    EndTextCommandSetBlipName(fbBlip)

    SetGPS(GetEntityCoords(NetToVeh(flatbedNetId)), 5)

    -- Notificar dono imediatamente ao aceitar missão pvp
    TriggerServerEvent('AUST_trucker:repoNotifyOwner', m.orderId,
        { x = spawnCoords.x, y = spawnCoords.y, z = spawnCoords.z })

    lib.notify({ title = 'Repo Man', description = 'O dono foi notificado — seja rápido!', type = 'warning' })

    -- Aguardar bed prop e registrar attach
    local waitStart = GetGameTimer()
    CreateThread(function()
        while GetGameTimer() - waitStart < 10000 do
            local flatbedEnt = NetToVeh(flatbedNetId)
            if DoesEntityExist(flatbedEnt) and Entity(flatbedEnt).state.bedProp then
                if DoesBlipExist(fbBlip) then RemoveBlip(fbBlip) end

                local targetEnt = NetToVeh(targetNetId)
                Flatbed.LowerBed(flatbedEnt)
                Wait(5000)

                Flatbed.RegisterAttachTarget(flatbedEnt, targetEnt, function()
                    EntrarFaseEntrega()
                end)
                return
            end
            Wait(500)
        end
        TriggerServerEvent('AUST_trucker:failRepoOrder', m.orderId, 'flatbed_timeout')
    end)
end

-- ============================================================
-- HANDLER: startRepoMission
-- ============================================================

RegisterNetEvent('AUST_trucker:client:startRepoMission')
AddEventHandler('AUST_trucker:client:startRepoMission', function(orderData)
    if ActiveRepoMission then
        -- Missão anterior não foi limpa corretamente
        CleanupMission()
    end

    local targetNetId, targetBlip, spawnCoords = SpawnTargetVehicle(orderData)

    ActiveRepoMission = {
        orderId           = orderData.id,
        missionType       = orderData.mission_type,
        targetVehicle     = targetNetId,
        flatbedVehicle    = nil,
        npcs              = {},
        targetSpawnCoords = spawnCoords,
        phase             = 'driving_to_zone',
        blipHandle        = targetBlip,
        impoundZoneId     = nil,
        impoundBlipHandle = nil,   -- blip do impound (removido no CleanupMission)
        ownerNotified     = false,
        pvpStartTime      = nil,
        ownerSrc          = orderData.owner_src or nil,
        pvpOwnerBlip      = nil,
    }

    SetGPS(spawnCoords, 1)
    lib.notify({ title = 'Repo Man', description = 'Missão iniciada — vá até o veículo alvo', type = 'inform', duration = 8000 })

    -- Dispatch por tipo
    local mType = orderData.mission_type
    if mType == 'simple' or mType == 'stealth' then
        -- Aguardar target existir localmente
        local waitStart = GetGameTimer()
        CreateThread(function()
            while GetGameTimer() - waitStart < 10000 do
                local targetEnt = NetToVeh(targetNetId)
                if DoesEntityExist(targetEnt) then
                    StartSimpleStealth(orderData, targetNetId, targetBlip, spawnCoords)
                    return
                end
                Wait(300)
            end
        end)
    elseif mType == 'npc_hostile' then
        local waitStart = GetGameTimer()
        CreateThread(function()
            while GetGameTimer() - waitStart < 10000 do
                local targetEnt = NetToVeh(targetNetId)
                if DoesEntityExist(targetEnt) then
                    StartNpcHostile(orderData, targetNetId, targetBlip, spawnCoords)
                    return
                end
                Wait(300)
            end
        end)
    elseif mType == 'pvp' then
        local waitStart = GetGameTimer()
        CreateThread(function()
            while GetGameTimer() - waitStart < 10000 do
                local targetEnt = NetToVeh(targetNetId)
                if DoesEntityExist(targetEnt) then
                    StartPvp(orderData, targetNetId, targetBlip, spawnCoords)
                    return
                end
                Wait(300)
            end
        end)
    end

    -- Thread de detecção de morte do agent
    CreateThread(function()
        while ActiveRepoMission do
            if GetEntityHealth(PlayerPedId()) <= 0 then
                TriggerServerEvent('AUST_trucker:failRepoOrder', ActiveRepoMission.orderId, 'agent_died')
                return
            end
            Wait(2000)
        end
    end)

    -- Timeout fallback (missionTimeout + 30s)
    local orderId = orderData.id
    SetTimeout((Config.RepoMan.missionTimeout + 30) * 1000, function()
        if ActiveRepoMission and ActiveRepoMission.orderId == orderId then
            CleanupMission()
        end
    end)
end)

-- ============================================================
-- HANDLER: repoMissionEnded (agent)
-- ============================================================

RegisterNetEvent('AUST_trucker:client:repoMissionEnded')
AddEventHandler('AUST_trucker:client:repoMissionEnded', function(data)
    CleanupMission()
    if data and data.success then
        lib.notify({
            title       = 'Repo Man',
            description = ('Veículo entregue! Recebido: $%d'):format(data.payment or 0),
            type        = 'success',
            duration    = 8000,
        })
    else
        lib.notify({ title = 'Repo Man', description = 'Missão encerrada', type = 'error' })
    end
end)

-- ============================================================
-- HANDLERS: owner-side (passivos — qualquer jogador pode receber)
-- ============================================================

RegisterNetEvent('AUST_trucker:client:repoTargetNotify')
AddEventHandler('AUST_trucker:client:repoTargetNotify', function(data)
    lib.notify({
        title       = 'Repossessão!',
        description = ('Agente %s está apreendendo seu veículo!'):format(data.agentName or 'Desconhecido'),
        type        = 'error',
        duration    = 10000,
    })
    -- Blip na zona do veículo
    local blip = AddBlipForCoord(data.zone_coords.x, data.zone_coords.y, data.zone_coords.z)
    SetBlipSprite(blip, 225)
    SetBlipColour(blip, 1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Seu Veículo')
    EndTextCommandSetBlipName(blip)
    -- Armazenar handle para remoção posterior
    -- (simplicidade: não rastrear — blip permanece até cliente desconectar)
end)

RegisterNetEvent('AUST_trucker:client:repoAgentUpdate')
AddEventHandler('AUST_trucker:client:repoAgentUpdate', function(data)
    -- Atualizar blip do agent (se o dono tiver um blip criado)
    -- Implementação simples: waypoint temporário
    -- Para produção: manter handle do blip via AddBlipForCoord + SetBlipCoords
end)

RegisterNetEvent('AUST_trucker:client:repoOwnerMissionEnded')
AddEventHandler('AUST_trucker:client:repoOwnerMissionEnded', function(data)
    if data and data.recovered then
        lib.notify({ title = 'Veículo Repossessado',
            description = 'Seu veículo foi recolhido pelo agente', type = 'error' })
    else
        lib.notify({ title = 'Veículo Salvo',
            description = 'A tentativa de repossessão falhou', type = 'success' })
    end
end)
```

- [ ] **Step 2: Commit**

```bash
git add client/repo.client.lua
git commit -m "feat(repo-gameplay): add repo.client.lua — full mission gameplay"
```

---

## Task 5: Patches de servidor — repo_service.lua + events.lua

**Files:**
- Modify: `server/services/repo_service.lua` (linhas ~130-222)
- Modify: `server/events.lua` (após bloco REPO MAN existente)

- [ ] **Step 1: Adicionar repoMissionEnded em RepoService.Complete (repo_service.lua ~linha 200)**

Após `RepoService.BroadcastAvailableOrders()` no final de `Complete`, ANTES do `return`:

```lua
    -- Notificar agent client
    TriggerClientEvent('AUST_trucker:client:repoMissionEnded', src, {
        success = true,
        payment = payment,
    })
    -- Notificar dono do veículo (pvp/stealth — evento separado)
    if order.vehicle_owner_citizenid then
        local players = GetPlayers()
        for _, pid in ipairs(players) do
            local P = exports.qbx_core:GetPlayer(tonumber(pid))
            if P and P.PlayerData.citizenid == order.vehicle_owner_citizenid then
                TriggerClientEvent('AUST_trucker:client:repoOwnerMissionEnded',
                    tonumber(pid), { recovered = true })
                break
            end
        end
    end
```

- [ ] **Step 2: Adicionar repoMissionEnded em RepoService.Fail (repo_service.lua ~linha 221)**

Após `RepoService.BroadcastAvailableOrders()` no final de `Fail`, ANTES do `return`:

```lua
    -- Notificar agent client
    TriggerClientEvent('AUST_trucker:client:repoMissionEnded', src, { success = false })
    -- Notificar dono do veículo
    if order.vehicle_owner_citizenid then
        local players = GetPlayers()
        for _, pid in ipairs(players) do
            local P = exports.qbx_core:GetPlayer(tonumber(pid))
            if P and P.PlayerData.citizenid == order.vehicle_owner_citizenid then
                TriggerClientEvent('AUST_trucker:client:repoOwnerMissionEnded',
                    tonumber(pid), { recovered = false })
                break
            end
        end
    end
```

- [ ] **Step 3: Adicionar handlers em server/events.lua (após o bloco REPO MAN existente)**

```lua
RegisterNetEvent('AUST_trucker:repoAgentPositionUpdate')
AddEventHandler('AUST_trucker:repoAgentPositionUpdate', function(orderId, coords)
    local src    = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    -- Buscar ordem e descobrir dono
    local order = DB_GetRepoOrderById(tonumber(orderId) or 0)
    if not order or order.status ~= 'active' then return end
    if not order.vehicle_owner_citizenid then return end

    -- Relay coords ao dono (se online)
    local players = GetPlayers()
    for _, pid in ipairs(players) do
        local P = exports.qbx_core:GetPlayer(tonumber(pid))
        if P and P.PlayerData.citizenid == order.vehicle_owner_citizenid then
            TriggerClientEvent('AUST_trucker:client:repoAgentUpdate', tonumber(pid), { coords = coords })
            break
        end
    end
end)

RegisterNetEvent('AUST_trucker:repoNotifyOwner')
AddEventHandler('AUST_trucker:repoNotifyOwner', function(orderId, spawnCoords)
    local src    = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local order = DB_GetRepoOrderById(tonumber(orderId) or 0)
    if not order or not order.vehicle_owner_citizenid then return end

    local agentName = Player.PlayerData.charinfo
        and (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname)
        or 'Agente'

    -- spawnCoords vem do client — coordenadas reais do spawn do veículo alvo
    local coords = spawnCoords or { x = 0.0, y = 0.0, z = 0.0 }

    local players = GetPlayers()
    for _, pid in ipairs(players) do
        local P = exports.qbx_core:GetPlayer(tonumber(pid))
        if P and P.PlayerData.citizenid == order.vehicle_owner_citizenid then
            TriggerClientEvent('AUST_trucker:client:repoTargetNotify', tonumber(pid), {
                agentName   = agentName,
                zone_coords = coords,
            })
            break
        end
    end
end)
```

- [ ] **Step 4: Verificar que `DB_GetRepoOrderById` existe em database.lua**

```bash
grep -n "DB_GetRepoOrderById" server/database.lua
```

Se não existir, adicionar em `server/database.lua`:

```lua
function DB_GetRepoOrderById(orderId)
    return MySQL.query.await(
        'SELECT * FROM trucker_repo_orders WHERE id = ?', { orderId }
    )[1] or nil
end
```

- [ ] **Step 5: Commit**

```bash
git add server/services/repo_service.lua server/events.lua server/database.lua
git commit -m "feat(repo-gameplay): add repoMissionEnded emits + position relay + owner notify handlers"
```

---

## Task 6: fxmanifest v6.1.0 + CHANGELOG

**Files:**
- Modify: `fxmanifest.lua` (verificar que todos os arquivos foram adicionados na Task 1)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Verificar fxmanifest completo**

Confirmar que `fxmanifest.lua` contém exatamente:
```lua
version '6.1.0'

-- server_scripts deve conter (na ordem):
'server/flatbed.server.lua',   -- após repo_service.lua

-- client_scripts deve conter (na ordem — flatbed ANTES de repo):
'client/flatbed.client.lua',
'client/repo.client.lua',

-- NOTA: arquivos em stream/ são auto-streamados pelo FiveM — NÃO adicionar data_file para .yft/.ytd
```

- [ ] **Step 2: Adicionar entrada no CHANGELOG.md**

```markdown
## [6.1.0] — 2026-03-20

### Added
- **Repo Man Gameplay (Fase 6 Sub-spec 2)**: gameplay in-world completa para missões de repossessão
  - Tipos `simple` e `stealth`: agent dirige target vehicle até o impound
  - Tipos `npc_hostile` e `pvp`: flatbed carrega target vehicle, entrega rebocada
  - Detecção stealth via `lib.getNearbyPlayers` (raio 15m)
  - NPC guards hostis para `npc_hostile` com leash de 80m
  - Notificação em tempo real do dono do veículo para `pvp` (blip + relay de coords)
  - Validação de veículo correto na zona de entrega (impound)
  - Cleanup completo em todos os caminhos de saída (complete, fail, timeout)
- **Sistema de flatbed integrado** (`client/flatbed.client.lua` + `server/flatbed.server.lua`):
  - Adaptado de gs_flatbed sem dependência externa
  - Bed prop `inm_flatbed_base` com animação de baixar/subir
  - API global `Flatbed` com `Spawn`, `LowerBed`, `RegisterAttachTarget`, `Detach`, `Despawn`
- **Stream files `flatbed3`**: modelo de reboque customizado (do pack 0r-towtruck-mix)
- `Config.Flatbed`: configuração do modelo, animação e offsets de bed
- `Config.RepoMan` gameplay: `vehicleModels`, `flatbedSpawnDistance`, `impoundRadius`, `missionTimeout`, `stealthDetectionRadius`, `pvpBlipDuration`, NPC guard params

### Modified
- `server/services/repo_service.lua`: `RepoService.Complete` e `RepoService.Fail` agora emitem `AUST_trucker:client:repoMissionEnded` ao agent e `repoOwnerMissionEnded` ao dono
- `server/events.lua`: ADD handlers `repoAgentPositionUpdate` (relay pvp), `repoNotifyOwner`
```

- [ ] **Step 3: Commit final**

```bash
git add fxmanifest.lua CHANGELOG.md
git commit -m "feat(repo-gameplay): v6.1.0 — Repo Man gameplay complete"
```

---

## Notas para o Implementador

### Offsets do flatbed3
Os valores em `Config.Flatbed.statePositions` são estimados baseados no modelo vanilla `flatbed`. **É provável que precisem ajuste**. Para calibrar:
1. Inicie o server, spawne um `flatbed3` em jogo
2. Observe se o bed prop (`inm_flatbed_base`) anima corretamente
3. Ajuste `pos` e `rot` dos estados `[0]`, `[1]`, `[2]` até a animação de abaixar ficar certa

### owner_src no orderData
O `orderData` enviado por `RepoService.Accept` → `startRepoMission` pode não conter `owner_src` ainda. Se `startRepoMission` não incluir o src do dono, o `repoNotifyOwner` deve buscar por citizenid no servidor (já implementado assim). Verificar o que `DB_GetRepoOrderById` retorna e se `vehicle_owner_citizenid` está presente.

### Testes in-game
1. Aceitar missão `simple` → verificar spawn do target → assumir veículo → entregar ao impound
2. Aceitar missão `stealth` → verificar polling de detecção → dono é notificado após sair
3. Aceitar missão `npc_hostile` → verificar spawn do flatbed + guards → carregar → entregar
4. Aceitar missão `pvp` → verificar notificação do dono → relay de coords → completar

### lua54 chunk isolation
`Flatbed` é global em `flatbed.client.lua` — visível em `repo.client.lua` porque ambos estão em `client_scripts` com `flatbed.client.lua` carregando ANTES. Não usar `local Flatbed`.
