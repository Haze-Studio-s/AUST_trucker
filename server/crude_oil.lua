-- server/crude_oil.lua
-- Crude Oil Pipeline — aurp_trucker server side
-- Exports: StartCrudeJob (called by lsn-oilfield), CheckPlayerAdr (called by lsn-oilfield)
-- Events: aurp_trucker:server:completeCrudeDelivery (called by aurp_trucker client)

-- In-memory: plate → job data
-- Not persisted to trucker_jobs (separate flow from regular jobs)
local ActiveCrudeJobs = {}

----------------------------------------
-- EXPORTS (called by lsn-oilfield server via pcall)
----------------------------------------

--- Called by lsn-oilfield after barrels are loaded and manifest is created.
--- Registers the cargo and sends GPS to client.
exports('StartCrudeJob', function(src, plate, manifestId, wellId, qty, pricePerBarrel)
    if not src or not plate then return false end
    local plr = Framework.GetPlayer(src)
    if not plr then return false end

    plate = plate:gsub('%s+', ''):upper()
    local citizenId = Framework.GetCitizenId(plr)

    if ActiveCrudeJobs[plate] then
        if Config.Debug then
            print(('[crude_oil] WARNING: overwriting active job for plate %s (manifestId=%d)'):format(plate, ActiveCrudeJobs[plate].manifestId or -1))
        end
    end
    ActiveCrudeJobs[plate] = {
        src           = src,
        citizenId     = citizenId,
        manifestId    = manifestId,
        wellId        = wellId,
        qty           = qty,
        pricePerBarrel= pricePerBarrel,
        startedAt     = os.time(),
    }

    if Config.Debug then
        print(('[crude_oil] Job started: plate=%s manifestId=%d qty=%d'):format(plate, manifestId, qty))
    end

    -- Send refinery coords to client for GPS
    TriggerClientEvent('aurp_trucker:client:crudeJobStarted', src, Config.CrudeOil.Refineries)
    -- Send qty for progressBar duration on unload
    TriggerClientEvent('aurp_trucker:client:crudeJobData', src, { qty = qty, pricePerBarrel = pricePerBarrel })
    return true
end)

--- Checks if a player has a valid ADR cert of the given type.
--- Called by lsn-oilfield to verify before allowing pickup.
exports('CheckPlayerAdr', function(citizenId, adrType)
    return AdrService.HasCert(citizenId, adrType)
end)

----------------------------------------
-- NET EVENTS
----------------------------------------

--- Called by aurp_trucker client after progressBar at refinery completes.
RegisterNetEvent('aurp_trucker:server:completeCrudeDelivery', function(plate, refineryId)
    local src = source
    if not plate then return end
    plate = plate:gsub('%s+', ''):upper()

    local job = ActiveCrudeJobs[plate]
    if not job then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Nenhum job de crude ativo para este veículo' })
        return
    end

    -- Validate the request comes from the right player (via Framework bridge)
    local plr = Framework.GetPlayer(src)
    if not plr or Framework.GetCitizenId(plr) ~= job.citizenId then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Não autorizado' })
        return
    end

    -- Validar existência da refinaria
    local targetRefinery = nil
    for _, r in ipairs((Config.CrudeOil and Config.CrudeOil.Refineries) or {}) do
        if r.id == refineryId then
            targetRefinery = r
            break
        end
    end
    if not targetRefinery then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Refinaria inválida' })
        return
    end

    -- Validar distância física do jogador até a refinaria (fail-closed)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local playerCoords = GetEntityCoords(ped)
    local refCoords = vec3(targetRefinery.coords.x, targetRefinery.coords.y, targetRefinery.coords.z)
    local maxDist = (Config.CrudeOil and Config.CrudeOil.DeliveryRadius and Config.CrudeOil.DeliveryRadius * 3.5) or 25.0
    if #(playerCoords - refCoords) > maxDist then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Muito longe da refinaria' })
        return
    end

    -- Validar tempo mínimo decorrido (descarga + trajeto)
    local elapsed = os.time() - (job.startedAt or os.time())
    local minUnloadTime = math.floor(((job.qty or 1) * ((Config.CrudeOil and Config.CrudeOil.UnloadTimePerBarrel) or 2000)) / 1000)
    if elapsed < (minUnloadTime + 5) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Entrega muito rápida — rejeitada' })
        return
    end

    -- Clear job immediately to prevent double-delivery on rapid re-fire
    ActiveCrudeJobs[plate] = nil

    -- Mark manifest as delivered in lsn-oilfield
    local ok, delivered = pcall(function()
        return exports['AUST_oilfield']:CompleteTransportDelivery(job.manifestId)
    end)
    if not ok or not delivered then
        if Config.Debug then print('[crude_oil] CompleteTransportDelivery failed:', delivered) end
        -- Continue with payment even if manifest update failed (manifest may have expired)
    end

    -- Calculate payment
    local totalPayment = job.qty * job.pricePerBarrel

    -- Decreto governamental: modificador de pagamento de frete
    local freightMod = 1.0
    pcall(function() freightMod = exports['AUST_governo']:GetDecreeModifier('freight_pay') end)
    if freightMod ~= 1.0 then totalPayment = math.floor(totalPayment * freightMod) end

    -- #7: Usar Framework.AddMoney em vez de QBCore direto
    Framework.AddMoney(plr, 'cash', totalPayment, 'crude_oil_delivery')

    -- Imposto de transporte de crude: fire-and-forget (10% padrão em vp-governo)
    TriggerEvent('vp-governo:server:collectTax',
        'crude_transport', job.qty * job.pricePerBarrel,
        'Frete crude — Manifesto ' .. job.manifestId)

    if Config.Debug then
        print(('[crude_oil] Payment $%d to %s (manifest=%d)'):format(totalPayment, job.citizenId, job.manifestId))
    end

    -- Notify client to clear GPS and show summary
    TriggerClientEvent('aurp_trucker:client:crudeJobCompleted', src, {
        qty            = job.qty,
        pricePerBarrel = job.pricePerBarrel,
        totalPayment   = totalPayment,
    })

    -- Broadcast to lsn-oilfield clients to refresh well zones (barrels changed)
    TriggerClientEvent('lsn-oilfield:client:refreshCrudeZones', -1)

    lib.notify(src, {
        type        = 'success',
        title       = 'Entrega Concluída',
        description = ('$%d recebidos por %d barris de crude'):format(totalPayment, job.qty),
        duration    = 8000,
    })
end)

--- Called by client when job is abandoned (player exits vehicle or manually cancels).
RegisterNetEvent('aurp_trucker:server:abandonCrudeJob', function(plate)
    local src = source
    if not plate then return end
    plate = plate:gsub('%s+', ''):upper()

    local job = ActiveCrudeJobs[plate]
    if not job then return end

    local plr = Framework.GetPlayer(src)
    if not plr or Framework.GetCitizenId(plr) ~= job.citizenId then return end

    -- Return barrels to well
    local ok, err = pcall(function()
        exports['AUST_oilfield']:ReturnBarrels(job.wellId, job.qty)
    end)
    if not ok and Config.Debug then
        print('[crude_oil] ReturnBarrels error:', err)
    end

    -- Expire manifest immediately (don't wait for the 5-min thread)
    local ok2, err2 = pcall(function()
        exports['AUST_oilfield']:ExpireManifest(job.manifestId)
    end)
    if not ok2 and Config.Debug then print('[crude_oil] ExpireManifest error:', err2) end

    ActiveCrudeJobs[plate] = nil

    TriggerClientEvent('aurp_trucker:client:crudeJobAbandoned', src)
    TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'Job de crude oil cancelado — barris devolvidos ao poço' })
    if Config.Debug then
        print(('[crude_oil] Job abandoned: plate=%s, returned %d barrels to well %d'):format(plate, job.qty, job.wellId))
    end
end)

--- Expose for GetActiveJobByPlate export (defined in server/exports.lua)
--- Must be a global (no 'local') because server/exports.lua is a separate lua54 chunk.
function GetActiveCrudeJobByPlate(plate)
    if not plate then return nil end
    return ActiveCrudeJobs[plate:gsub('%s+', ''):upper()]
end

--- Retorna todos os jobs de crude ativos para o painel do governo.
exports('GetActiveCrudeJobsSummary', function()
    local result = {}
    for plate, job in pairs(ActiveCrudeJobs) do
        result[#result + 1] = {
            plate          = plate,
            wellId         = job.wellId,
            manifestId     = job.manifestId,
            qty            = job.qty,
            pricePerBarrel = job.pricePerBarrel,
            citizenId      = job.citizenId,
        }
    end
    return result
end)
