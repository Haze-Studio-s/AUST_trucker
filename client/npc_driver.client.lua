-- aurp_trucker — client/npc_driver.client.lua
-- Blips de rota, peds na base da agência, overlay de evento grave

local NpcDriverState = {
    activeDriverBlips = {},  -- { [driverId] = blipHandle }
    basePeds          = {},  -- { [driverId] = pedHandle }
    baseZone          = nil,
    inBaseZone        = false,
}

-- ============================================================
-- BLIPS DE ROTA
-- ============================================================

RegisterNetEvent('aurp_trucker:client:npcPositionUpdate', function(positions)
    -- positions = { [driverId] = { x, y, z, name, status } }
    for driverId, pos in pairs(positions) do
        if pos.status == 'working' then
            local blip = NpcDriverState.activeDriverBlips[driverId]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(pos.x, pos.y, pos.z)
                SetBlipSprite(blip, Config.NpcDrivers.blipSprite)
                SetBlipColour(blip, 46)  -- azul claro
                SetBlipScale(blip, Config.NpcDrivers.blipScale)
                SetBlipAsShortRange(blip, false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(('[NPC] %s'):format(pos.name or driverId))
                EndTextCommandSetBlipName(blip)
                NpcDriverState.activeDriverBlips[driverId] = blip
            else
                SetBlipCoords(blip, pos.x, pos.y, pos.z)
            end
        else
            local existing = NpcDriverState.activeDriverBlips[driverId]
            if existing and DoesBlipExist(existing) then RemoveBlip(existing) end
            NpcDriverState.activeDriverBlips[driverId] = nil
        end
    end
end)

-- ============================================================
-- PEDS NA AGÊNCIA
-- ============================================================

local function SpawnBasePeds(drivers)
    for id, ped in pairs(NpcDriverState.basePeds) do
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped)
            DeletePed(ped)
        end
    end
    NpcDriverState.basePeds = {}

    local baseCoord = Config.NpcDrivers.agencyLocation
    local spacing   = 1.5

    local idleDrivers = {}
    for _, d in ipairs(drivers or {}) do
        if d.status == 'idle' then table.insert(idleDrivers, d) end
    end

    for i, driver in ipairs(idleDrivers) do
        CreateThread(function()
            Wait((i - 1) * 100)  -- escalonar criação para evitar contenção de carregamento de modelos
            local model = GetHashKey(Config.NpcDrivers.basePedModel)
            RequestModel(model)
            while not HasModelLoaded(model) do Wait(50) end

            local offsetX = (i - 1) * spacing
            local ped = CreatePed(4, model, baseCoord.x + offsetX, baseCoord.y, baseCoord.z, 0.0, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            SetModelAsNoLongerNeeded(model)

            NpcDriverState.basePeds[driver.id] = ped

            exports.ox_target:addLocalEntity(ped, {
                {
                    name     = 'npc_driver_profile_' .. driver.id,
                    label    = ('[%s] %s — Ver Perfil'):format(driver.skill_level:upper(), driver.name),
                    icon     = 'fas fa-id-card',
                    distance = 3.0,
                    onSelect = function()
                        SendNUIMessage({ action = 'focusNpcDriver', driverId = driver.id })
                        SetNuiFocus(true, true)
                    end,
                },
            })
        end)
    end
end

local function DespawnBasePeds()
    for id, ped in pairs(NpcDriverState.basePeds) do
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped)
            DeletePed(ped)
        end
    end
    NpcDriverState.basePeds = {}
end

-- Zona na agência para spawnar peds dos drivers idle
CreateThread(function()
    Wait(3000)  -- aguardar resource carregar
    local zone = lib.zones.sphere({
        coords  = Config.NpcDrivers.agencyLocation,
        radius  = Config.NpcDrivers.agencyRadius,
        onEnter = function()
            NpcDriverState.inBaseZone = true
            local result = lib.callback.await('aurp_trucker:getNpcDriverData', false)
            if result and result.success then
                SpawnBasePeds(result.drivers)
            end
        end,
        onExit = function()
            NpcDriverState.inBaseZone = false
            DespawnBasePeds()
        end,
    })
    NpcDriverState.baseZone = zone
end)

-- ============================================================
-- EVENTOS GRAVES — OVERLAY NUI
-- ============================================================

RegisterNetEvent('aurp_trucker:client:npcGraveEvent', function(data)
    SendNUIMessage({ action = 'npcGraveEvent', event = data })
    SetNuiFocus(true, true)
end)

RegisterNetEvent('aurp_trucker:client:npcEventResolved', function(data)
    SendNUIMessage({ action = 'npcEventResolved', eventId = data.eventId })
end)

-- ============================================================
-- NOTIFICAÇÕES SIMPLES
-- ============================================================

RegisterNetEvent('aurp_trucker:client:npcDriverJobCompleted', function(data)
    lib.notify({
        title       = 'Motorista NPC',
        description = ('%s completou uma entrega — $%d'):format(data.driverName or '?', data.earnings or 0),
        type        = 'success',
        duration    = 5000,
    })
end)

RegisterNetEvent('aurp_trucker:client:npcDriverQuit', function(data)
    lib.notify({
        title       = 'Motorista Saiu',
        description = ('%s pediu demissão por baixa satisfação.'):format(data.driverName or '?'),
        type        = 'error',
        duration    = 8000,
    })
end)

RegisterNetEvent('aurp_trucker:client:npcDemandGenerated', function(data)
    lib.notify({
        title       = 'Demanda do Motorista',
        description = ('%s tem uma nova demanda: %s'):format(data.driverName or '?', data.demandType or '?'),
        type        = 'inform',
        duration    = 8000,
    })
end)

-- ============================================================
-- CLEANUP no stop do resource
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, blip in pairs(NpcDriverState.activeDriverBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    DespawnBasePeds()
    if NpcDriverState.baseZone then
        NpcDriverState.baseZone:remove()
        NpcDriverState.baseZone = nil
    end
end)
