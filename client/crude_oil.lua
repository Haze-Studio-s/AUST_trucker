-- client/crude_oil.lua
-- Crude Oil Pipeline — aurp_trucker client side
-- Handles refinery ox_target, unloading progressBar, and GPS events.

local ActiveZones    = {}    -- refinery ox_target zone names
local IsUnloading    = false
local CrudeJobActive = false
local CrudeJobData   = nil   -- { qty, pricePerBarrel } set by server on job start

----------------------------------------
-- Helpers
----------------------------------------

local function GetCurrentPlate()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if not veh or veh == 0 then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
end

----------------------------------------
-- Delivery flow
----------------------------------------

local function StartDelivery(refineryId)
    if IsUnloading then
        lib.notify({ type = 'error', description = 'Já está descarregando' })
        return
    end
    if not CrudeJobActive then
        lib.notify({ type = 'error', description = 'Nenhum cargo de crude oil ativo' })
        return
    end

    local plate = GetCurrentPlate()
    if not plate then
        lib.notify({ type = 'error', description = 'Nenhum veículo detectado' })
        return
    end

    if not CrudeJobData then
        lib.notify({ type = 'error', description = 'Dados do cargo ainda não disponíveis — tente novamente' })
        return
    end
    local qty = CrudeJobData.qty

    IsUnloading = true
    local totalMs = qty * Config.CrudeOil.UnloadTimePerBarrel
    local pbOk, success = pcall(lib.progressBar, {
        duration     = totalMs,
        label        = ('Descarregando %d barris...'):format(qty),
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = true, car = false, combat = true },
    })
    IsUnloading = false

    if not pbOk or not success then return end

    TriggerServerEvent('aurp_trucker:server:completeCrudeDelivery', plate, refineryId)
end

----------------------------------------
-- Refinery ox_target zones
----------------------------------------

local function RegisterRefineryZone(refinery)
    local c = refinery.coords
    if not c then return end

    local zoneName = 'crude_delivery_' .. refinery.id
    exports.ox_target:addSphereZone({
        name   = zoneName,
        coords = type(c) == 'vector4' and vec3(c.x, c.y, c.z) or vec3(c.x, c.y, c.z or 0),
        radius = Config.CrudeOil.DeliveryRadius,
        options = {
            {
                name     = 'crude_deliver_' .. refinery.id,
                icon     = 'fas fa-industry',
                label    = 'Entregar Crude Oil',
                onSelect = function()
                    StartDelivery(refinery.id)
                end,
                canInteract = function()
                    return CrudeJobActive and not IsUnloading
                end,
            },
        },
        debug = Config.Debug,
    })
    table.insert(ActiveZones, zoneName)
end

local function ClearZones()
    for _, z in ipairs(ActiveZones) do
        exports.ox_target:removeZone(z)
    end
    ActiveZones = {}
end

----------------------------------------
-- Server event handlers
----------------------------------------

--- Fired by server/crude_oil.lua:StartCrudeJob after cargo loaded.
RegisterNetEvent('aurp_trucker:client:crudeJobStarted', function(refineries)
    CrudeJobActive = true

    -- Rebuild refinery zones if not done yet (fallback for slow init)
    if #ActiveZones == 0 then
        for _, r in ipairs(refineries or Config.CrudeOil.Refineries or {}) do
            RegisterRefineryZone(r)
        end
    end

    -- Set GPS to first refinery
    if refineries and refineries[1] then
        local c = refineries[1].coords
        if c then
            SetNewWaypoint(c.x, c.y)
            lib.notify({ type = 'inform', description = 'Entregue o crude na refinaria — GPS definido', duration = 6000 })
        end
    end
end)

--- Store job data for qty reference during unload.
RegisterNetEvent('aurp_trucker:client:crudeJobData', function(data)
    CrudeJobData = data
end)

--- Fired by server after successful delivery.
RegisterNetEvent('aurp_trucker:client:crudeJobCompleted', function(summary)
    CrudeJobActive = false
    CrudeJobData   = nil
    RemoveWaypoint()
    lib.notify({
        type        = 'success',
        title       = 'Entrega de Crude Oil Concluída',
        description = ('$%d por %d barris'):format(summary.totalPayment, summary.qty),
        duration    = 10000,
    })
end)

--- Set GPS to well coords (from job board "accept" click for Mode B).
RegisterNetEvent('aurp_trucker:client:setCrudeGPS', function(coords)
    if coords and coords.x then
        SetNewWaypoint(coords.x, coords.y)
        lib.notify({ type = 'inform', description = 'GPS definido para o poço de crude oil', duration = 5000 })
    end
end)

----------------------------------------
-- Init: register refinery zones on login
----------------------------------------

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end
    Wait(2000)

    -- Fetch refinery list from lsn-oilfield (or fall back to config)
    local ok, refineries = pcall(function()
        return lib.callback.await('aurp_trucker:getRefineries', false)
    end)

    local refineryList = (ok and refineries) or (Config.CrudeOil and Config.CrudeOil.Refineries) or {}
    for _, r in ipairs(refineryList) do
        RegisterRefineryZone(r)
    end

    if Config.Debug then
        print(('[crude_oil client] %d refinery zones registered'):format(#ActiveZones))
    end
end)

--- Fired by server when player abandons the crude job.
RegisterNetEvent('aurp_trucker:client:crudeJobAbandoned', function()
    CrudeJobActive = false
    CrudeJobData   = nil
    RemoveWaypoint()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ClearZones()
end)
