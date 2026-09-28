-- aurp_trucker — client/repo.client.lua
-- Fase 6: Gameplay client-side das missões Repo Man

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local ActiveRepoMission = nil
local repoAgentBlip     = nil   -- blip do agente visível apenas para o dono do veículo (6B)
local repoTargetBlip    = nil   -- blip da localização do veículo (zona de spawn) enviado em repoTargetNotify
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
  impoundBlipHandle = number|nil,
  ownerNotified     = boolean,
  pvpStartTime      = number|nil,
  ownerSrc          = number|nil,
  pvpOwnerBlip      = number|nil,
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
    m.impoundBlipHandle = impBlip

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

            -- Completar missão (guard against double-trigger on zone re-entry)
            if am.deliveryTriggered then return end
            am.deliveryTriggered = true
            TriggerServerEvent('aurp_trucker:completeRepoOrder', am.orderId)
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
                                TriggerServerEvent('aurp_trucker:repoNotifyOwner', m.orderId,
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
                    TriggerServerEvent('aurp_trucker:failRepoOrder', m.orderId, 'detected')
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
        TriggerServerEvent('aurp_trucker:failRepoOrder', m.orderId, 'flatbed_timeout')
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

    -- Thread de atualização de posição para o dono (janela pvpBlipDuration)
    CreateThread(function()
        while ActiveRepoMission do
            local elapsed = GetGameTimer() - (m.pvpStartTime or 0)
            if elapsed > Config.RepoMan.pvpBlipDuration * 1000 then return end
            local coords = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('aurp_trucker:repoAgentPositionUpdate',
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
    TriggerServerEvent('aurp_trucker:repoNotifyOwner', m.orderId,
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
        TriggerServerEvent('aurp_trucker:failRepoOrder', m.orderId, 'flatbed_timeout')
    end)
end

-- ============================================================
-- HANDLER: startRepoMission
-- ============================================================

RegisterNetEvent('aurp_trucker:client:startRepoMission')
AddEventHandler('aurp_trucker:client:startRepoMission', function(orderData)
    if ActiveRepoMission then
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
        impoundBlipHandle = nil,
        ownerNotified     = false,
        pvpStartTime      = nil,
        ownerSrc          = orderData.owner_src or nil,
        pvpOwnerBlip      = nil,
        deliveryTriggered = false,
    }

    SetGPS(spawnCoords, 1)
    lib.notify({ title = 'Repo Man', description = 'Missão iniciada — vá até o veículo alvo', type = 'inform', duration = 8000 })

    -- Dispatch por tipo
    local mType = orderData.mission_type
    if mType == 'simple' or mType == 'stealth' then
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
                TriggerServerEvent('aurp_trucker:failRepoOrder', ActiveRepoMission.orderId, 'agent_died')
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

RegisterNetEvent('aurp_trucker:client:repoMissionEnded')
AddEventHandler('aurp_trucker:client:repoMissionEnded', function(data)
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

RegisterNetEvent('aurp_trucker:client:repoTargetNotify')
AddEventHandler('aurp_trucker:client:repoTargetNotify', function(data)
    lib.notify({
        title       = 'Repossessão!',
        description = ('Agente %s está apreendendo seu veículo!'):format(data.agentName or 'Desconhecido'),
        type        = 'error',
        duration    = 10000,
    })
    -- Blip na zona do veículo — armazenar handle para cleanup posterior (fix #4)
    if repoTargetBlip and DoesBlipExist(repoTargetBlip) then
        RemoveBlip(repoTargetBlip)
    end
    repoTargetBlip = AddBlipForCoord(data.zone_coords.x, data.zone_coords.y, data.zone_coords.z)
    SetBlipSprite(repoTargetBlip, 225)
    SetBlipColour(repoTargetBlip, 1)
    SetBlipFlashes(repoTargetBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Seu Veículo')
    EndTextCommandSetBlipName(repoTargetBlip)
end)

RegisterNetEvent('aurp_trucker:client:repoAgentUpdate')
AddEventHandler('aurp_trucker:client:repoAgentUpdate', function(data)
    if not data or not data.coords then return end
    if not repoAgentBlip then
        repoAgentBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(repoAgentBlip, 1)
        SetBlipColour(repoAgentBlip, 1)   -- vermelho
        SetBlipFlashes(repoAgentBlip, true)
        SetBlipAsShortRange(repoAgentBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Agente Repo')
        EndTextCommandSetBlipName(repoAgentBlip)
    else
        SetBlipCoords(repoAgentBlip, data.coords.x, data.coords.y, data.coords.z)
    end
end)

RegisterNetEvent('aurp_trucker:client:repoOwnerMissionEnded')
AddEventHandler('aurp_trucker:client:repoOwnerMissionEnded', function(data)
    -- Limpar blips do agente e da zona do veículo (6B / fix #4)
    if repoAgentBlip and DoesBlipExist(repoAgentBlip) then
        RemoveBlip(repoAgentBlip)
        repoAgentBlip = nil
    end
    if repoTargetBlip and DoesBlipExist(repoTargetBlip) then
        RemoveBlip(repoTargetBlip)
        repoTargetBlip = nil
    end

    if data and data.recovered then
        lib.notify({ title = 'Veículo Repossessado',
            description = 'Seu veículo foi recolhido pelo agente', type = 'error' })
    else
        lib.notify({ title = 'Veículo Salvo',
            description = 'A tentativa de repossessão falhou', type = 'success' })
    end
end)

-- ============================================================
-- CLEANUP no stop do resource
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CleanupMission()
    if repoAgentBlip and DoesBlipExist(repoAgentBlip) then
        RemoveBlip(repoAgentBlip)
        repoAgentBlip = nil
    end
    if repoTargetBlip and DoesBlipExist(repoTargetBlip) then
        RemoveBlip(repoTargetBlip)
        repoTargetBlip = nil
    end
end)
