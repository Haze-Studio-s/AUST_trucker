-- Telemetria de pallets: observa, nunca altera física. Só existe com Config.Debug = true.
-- Uso: /palletdebug [netId | stop | dump | auto | freeze | unfreeze]   (sem argumento = pallet mais próximo)
-- freeze/unfreeze só agem quando o operador digita (teste manual do pallet acompanhado); nada é automático.
-- Saída: linhas "[AUST PALLET DEBUG]" no console F8, no máximo 1 por segundo por pallet seguido.
if not (Config and Config.Debug) then return end

PalletDebug = {}

local TAG = '[AUST PALLET DEBUG]'
local INTERVAL_MS = 1000
local known = {}        -- [netId] = { ent, jobId, firstSeen, syncs, lastZ, firstDropAt, snap }
local order = {}
local tracked = nil     -- netId em acompanhamento
local autoTrack = true  -- segue o 1º pallet sincronizado a partir do momento do sync

local function now() return GetGameTimer() end

local function fmt(n, d)
    if n == nil then return 'n/a' end
    return (('%%.%df'):format(d or 3)):format(n)
end

local function entry(netId, ent)
    local e = known[netId]
    if not e then
        e = { netId = netId, syncs = 0, firstSeen = now() }
        known[netId] = e
        order[#order + 1] = netId
    end
    if ent and ent ~= 0 then e.ent = ent end
    return e
end

local function resolveEnt(e)
    if e.ent and DoesEntityExist(e.ent) then return e.ent end
    if NetworkDoesNetworkIdExist(e.netId) then
        local ent = NetworkGetEntityFromNetworkId(e.netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then e.ent = ent return ent end
    end
    return nil
end

-- Raio vertical só contra o mapa (flag 1), ignorando o próprio objeto.
local function mapRayZ(ent, x, y, z)
    local ray = StartShapeTestRay(x, y, z + 2.0, x, y, z - 10.0, 1, ent, 7)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    if hit == 1 then return hitCoords.z end
    return nil
end

local function sample(e)
    local ent = resolveEnt(e)
    if not ent then
        print(('%s netId=%s entidade inexistente no client'):format(TAG, tostring(e.netId)))
        return
    end
    local model = GetEntityModel(ent)
    local minD, maxD = GetModelDimensions(model)
    local c = GetEntityCoords(ent)
    local okG, groundZ = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    if not okG then groundZ = nil end
    local rayZ = mapRayZ(ent, c.x, c.y, c.z)
    local baseZ = c.z + minD.z                       -- base do modelo assumindo sem rotação
    local ref = groundZ or rayZ
    local height = ref and (baseZ - ref) or nil

    local t = (now() - e.firstSeen) / 1000.0
    local dz = e.lastZ and (c.z - e.lastZ) or 0.0
    e.lastZ = c.z
    local flag = ''
    if dz < -0.005 then
        flag = ' FALLING'
        if not e.firstDropAt then
            e.firstDropAt = t
            flag = flag .. (' FIRST_DROP_AT_t=%.1fs'):format(t)
        end
    end
    if height and height < -0.02 then flag = flag .. ' BASE_BELOW_GROUND' end

    local owner = NetworkGetEntityOwner(ent)
    local ownerSrv = owner and owner ~= -1 and GetPlayerServerId(owner) or 'n/a'
    local okC, collDisabled = pcall(GetEntityCollisonDisabled, ent)
    local attached = IsEntityAttached(ent)
    local attachedTo = attached and GetEntityAttachedTo(ent) or nil
    local attachedNet = (attachedTo and attachedTo ~= 0 and NetworkGetEntityIsNetworked(attachedTo)) and NetworkGetNetworkIdFromEntity(attachedTo) or nil

    local slot, slotData = 'n/a', nil
    if attachedTo and attachedTo ~= 0 then
        local st = Entity(attachedTo).state.loadedSlots
        if type(st) == 'table' then
            for k, v in pairs(st) do
                if type(v) == 'table' and v.palletNet == e.netId then slot, slotData = k, v end
            end
        end
    end

    print(('%s t=%.1fs netId=%s ent=%s model=%s owner(srv)=%s mine=%s | xyz=(%s, %s, %s) dZ=%s groundZ=%s rayZ=%s '
        .. 'minDim.z=%s maxDim.z=%s baseZ=%s heightAboveGround=%s | frozen=%s static=%s(dynamic=%s) gravity=n/a collision=%s '
        .. '| attached=%s to=%s slot=%s statebag=%s | job=%s syncs=%d%s'):format(
        TAG, t, tostring(e.netId), tostring(ent), tostring(model), tostring(ownerSrv), tostring(NetworkHasControlOfEntity(ent)),
        fmt(c.x, 2), fmt(c.y, 2), fmt(c.z, 3), fmt(dz, 3), fmt(groundZ), fmt(rayZ),
        fmt(minD.z), fmt(maxD.z), fmt(baseZ), fmt(height),
        tostring(IsEntityPositionFrozen(ent)), tostring(IsEntityStatic(ent)), tostring(not IsEntityStatic(ent)),
        okC and tostring(not collDisabled) or 'n/a',
        tostring(attached), tostring(attachedNet), tostring(slot), slotData and json.encode(slotData) or 'n/a',
        tostring(e.jobId), e.syncs, flag))
end

function PalletDebug.OnSync(netId, ent, jobId, syncN, action)
    local e = entry(netId, ent)
    e.jobId = jobId
    e.syncs = e.syncs + 1
    print(('%s sync#%s netId=%s job=%s action=%s t=%.1fs'):format(TAG, tostring(syncN), tostring(netId), tostring(jobId), action, (now() - e.firstSeen) / 1000.0))
    if autoTrack and not tracked and action == 'applied' then
        tracked = netId
        print(('%s auto-tracking netId=%s (use /palletdebug stop para parar)'):format(TAG, tostring(netId)))
    end
end

function PalletDebug.OnSnap(netId, ent, info)
    local e = entry(netId, ent)
    local c = GetEntityCoords(ent)
    e.snap = info
    print(('%s snap netId=%s preZ=%s groundFound=%s groundZ=%s postZ=%s (origem posta em groundZ+0.05; método=%s)'):format(
        TAG, tostring(netId), fmt(info.preZ), tostring(info.groundFound), fmt(info.groundZ), fmt(c.z),
        info.groundFound and 'SetEntityCoordsNoOffset' or 'PlaceObjectOnGroundProperly'))
end

-- Transição de estado do levantamento cinemático (frozen -> claiming -> attached_to_forks ...).
function PalletDebug.OnState(netId, from, to, info)
    entry(netId)
    print(('%s state netId=%s %s -> %s %s'):format(TAG, tostring(netId), tostring(from), tostring(to), info and ('(' .. tostring(info) .. ')') or ''))
end

-- Telemetria de elevação (no máximo 1 linha por 250 ms por pallet; sempre imprime engage/intent/disengage).
-- liftDelta = subida do osso dos garfos no referencial do forklift; é a medida que decide o attach.
local lastLift = {}
function PalletDebug.OnLift(netId, ev, delta, minZ, speed, aligned)
    local t = now()
    if ev == 'none' and (lastLift[netId] and (t - lastLift[netId]) < 250) then return end
    if ev == 'none' and not aligned then return end
    lastLift[netId] = t
    print(('%s lift netId=%s ev=%s liftDelta=%s boneMinZ=%s forkliftSpeed=%s aligned=%s'):format(
        TAG, tostring(netId), ev, fmt(delta), fmt(minZ), fmt(speed, 2), tostring(aligned)))
end

CreateThread(function()
    while true do
        if tracked and known[tracked] then
            sample(known[tracked])
            Wait(INTERVAL_MS)
        else
            Wait(1000)
        end
    end
end)

local function nearestPallet()
    local me = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, e in pairs(known) do
        local ent = resolveEnt(e)
        if ent then
            local d = #(GetEntityCoords(ent) - me)
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    return best
end

RegisterCommand('palletdebug', function(_, args)
    local a = args[1]
    if a == 'stop' then
        tracked, autoTrack = nil, false
        print(TAG .. ' parado (auto-tracking desligado; /palletdebug auto religa)')
    elseif a == 'auto' then
        autoTrack = true
        print(TAG .. ' auto-tracking ligado')
    elseif a == 'freeze' or a == 'unfreeze' then
        local e = tracked and known[tracked]
        local ent = e and resolveEnt(e)
        if ent then
            FreezeEntityPosition(ent, a == 'freeze')
            print(('%s TESTE MANUAL: %s netId=%s'):format(TAG, a, tostring(tracked)))
        else
            print(TAG .. ' sem pallet acompanhado; use /palletdebug primeiro')
        end
    elseif a == 'dump' then
        for _, netId in ipairs(order) do sample(known[netId]) end
    elseif a and tonumber(a) then
        local netId = tonumber(a)
        if NetworkDoesNetworkIdExist(netId) then
            entry(netId, NetworkGetEntityFromNetworkId(netId))
            tracked = netId
            print(('%s acompanhando netId=%s'):format(TAG, a))
        else
            print(('%s netId %s não existe neste client'):format(TAG, a))
        end
    else
        local e = nearestPallet()
        if e then
            e.firstSeen = now()
            e.firstDropAt, e.lastZ = nil, nil
            tracked = e.netId
            print(('%s acompanhando o pallet mais próximo netId=%s (t=0 agora)'):format(TAG, tostring(e.netId)))
        else
            print(TAG .. ' nenhum pallet de missão conhecido; inicie o job ou use /palletdebug <netId>')
        end
    end
end, false)
