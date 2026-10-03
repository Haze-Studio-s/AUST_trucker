-- server/services/cargo_tracking_service.lua
-- CargoTrackingService: gerencia cargo vinculado a veículos e mecânicas de roubo (v14.0.0)

CargoTrackingService = {}

-- Timers pendentes de vulnerabilidade: plate → true (ativo) / false (cancelado)
local PendingVulnerability = {}

-- -------------------------------------------------------
-- Helpers internos
-- -------------------------------------------------------

-- Retorna o source FiveM de um citizenId (ou nil se offline)
local function GetSrcByCitizenId(citizenId)
    local players = Framework.GetAllPlayers()
    for src, Player in pairs(players) do
        if Framework.GetCitizenId(Player) == citizenId then
            return src
        end
    end
    return nil
end

-- Retorna o nome da zona mais próxima das coordenadas dadas
function CargoTrackingService.GetNearestZoneName(coords)
    local nearest, dist = 'local desconhecido', math.huge
    for _, zone in ipairs(Config.CargoTheft.PoliceZones) do
        local d = #(coords - zone.coords)
        if d < dist then
            nearest = zone.name
            dist    = d
        end
    end
    return nearest
end

-- Notifica todos os policiais online com alerta vago de roubo
local function NotifyPolice(zoneName)
    local players = Framework.GetAllPlayers()
    for src, Player in pairs(players) do
        if Framework.GetJob(Player).name == Config.CargoTheft.PoliceJob then
            TriggerClientEvent('aurp_trucker:client:policeCargoAlert', src, zoneName)
        end
    end
end

-- -------------------------------------------------------
-- API pública
-- -------------------------------------------------------

-- Registra cargo quando o jogador entra no caminhão com job ativo
-- Chamado de: events.lua (registerTruckPlate)
function CargoTrackingService.RegisterCargo(plate, jobId, citizenId, basePayment, gpsEnabled)
    VP_Trucker.CargoByPlate[plate] = {
        jobId           = jobId,
        citizenId       = citizenId,
        gpsEnabled      = gpsEnabled,
        isStolen        = false,
        basePayment     = basePayment,
        vulnerableSince = nil,
        theftBy         = nil,
        theftStartedAt  = nil,
    }
    DB_SetTruckPlate(jobId, plate)
end

-- Inicia o timer de vulnerabilidade quando jogador sai do caminhão
-- Chamado de: events.lua (cargoPlayerLeft)
function CargoTrackingService.OnPlayerLeft(plate, ownerSrc)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo or cargo.isStolen then return end

    PendingVulnerability[plate] = true

    SetTimeout(Config.CargoTheft.VulnerableDelay * 1000, function()
        if not PendingVulnerability[plate] then return end  -- foi cancelado
        PendingVulnerability[plate] = nil

        local c = VP_Trucker.CargoByPlate[plate]
        if not c then return end

        c.vulnerableSince = os.time()

        -- Re-resolve owner source (may have changed if player reconnected in 30s window)
        local resolvedOwnerSrc = GetSrcByCitizenId(c.citizenId)
        if resolvedOwnerSrc then
            TriggerClientEvent('aurp_trucker:client:cargoVulnerable', resolvedOwnerSrc, plate)
        end

        -- Broadcast blip para todos (se configurado)
        if Config.CargoTheft.VulnerableBlip then
            local players = Framework.GetAllPlayers()
            for src, _ in pairs(players) do
                if src ~= resolvedOwnerSrc then
                    TriggerClientEvent('aurp_trucker:client:cargoVulnerableOther', src, plate)
                end
            end
        end
    end)
end

-- Cancela timer/roubo quando jogador volta ao caminhão
-- Chamado de: events.lua (cargoPlayerReturned)
function CargoTrackingService.OnPlayerReturned(plate)
    PendingVulnerability[plate] = false  -- cancela timer pendente

    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return end

    -- Cancela roubo em andamento
    if cargo.theftBy then
        local thiefSrc = GetSrcByCitizenId(cargo.theftBy)
        if thiefSrc then
            TriggerClientEvent('aurp_trucker:client:theftCancelled', thiefSrc)
        end
    end

    cargo.vulnerableSince = nil
    cargo.theftBy         = nil
    cargo.theftStartedAt  = nil
end

-- Inicia um roubo de carga
-- Retorna true on success, false + msg on failure
-- Chamado de: events.lua (startCargoTheft)
function CargoTrackingService.StartTheft(plate, thiefCitizenId, thiefSrc, truckCoords)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return false, 'Carga não encontrada.' end
    if not cargo.vulnerableSince then return false, 'Carga não está vulnerável.' end
    if cargo.theftBy then return false, 'Roubo já em andamento.' end
    if cargo.citizenId == thiefCitizenId then return false, 'Não pode roubar sua própria carga.' end

    cargo.theftBy        = thiefCitizenId
    cargo.theftStartedAt  = os.time()
    cargo.startCoords     = truckCoords

    -- Notificação GPS
    if cargo.gpsEnabled then
        local ownerSrc = GetSrcByCitizenId(cargo.citizenId)
        if ownerSrc then
            TriggerClientEvent('aurp_trucker:client:cargoTheftAlert', ownerSrc, plate)
        end
        local zoneName = CargoTrackingService.GetNearestZoneName(truckCoords)
        NotifyPolice(zoneName)
    end

    return true
end

-- Completa o roubo — transfere cargo para o ladrão
-- Retorna { destId, basePayment } on success, nil on failure
-- Chamado de: events.lua (completeCargoTheft)
function CargoTrackingService.CompleteTheft(plate, thiefPlate, thiefCitizenId, thiefCoords)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return nil end
    if cargo.theftBy ~= thiefCitizenId then return nil end

    -- Validação de proximidade no momento da conclusão (fail-closed)
    if cargo.startCoords and thiefCoords then
        local maxRange = (Config.CargoTheft and Config.CargoTheft.TheftRange and Config.CargoTheft.TheftRange + 10.0) or 25.0
        if #(thiefCoords - cargo.startCoords) > maxRange then
            return nil
        end
    end

    -- Validação de timing server-side (evita exploit de conclusão prematura)
    if not cargo.theftStartedAt then return nil end  -- roubo não foi iniciado via StartTheft
    local elapsed = os.time() - cargo.theftStartedAt
    if elapsed < (Config.CargoTheft.TheftDuration - 2) then
        return nil  -- muito rápido: cheat
    end

    -- Falha o job original
    -- pcall: falha no DB (ex.: ENUM sem 'failed') não pode abortar a transferência de posse
    local okF, errF = pcall(DB_SetCargoFailed, cargo.jobId)
    if not okF then
        print(('[aurp_trucker] CompleteTheft: DB_SetCargoFailed falhou (job %s): %s'):format(tostring(cargo.jobId), tostring(errF)))
    end

    -- Notifica o dono
    local ownerSrc = GetSrcByCitizenId(cargo.citizenId)
    if ownerSrc then
        TriggerClientEvent('aurp_trucker:client:cargoStolen', ownerSrc)
    end

    -- Busca dados do job para montar entrada do ladrão
    local okJ, job = pcall(DB_GetJobById, cargo.jobId)
    if not okJ then job = nil end
    local result = {
        jobId       = cargo.jobId,
        destId      = job and job.dest_id or nil,
        basePayment = cargo.basePayment,
    }

    -- Remove entrada do dono
    VP_Trucker.CargoByPlate[plate] = nil
    PendingVulnerability[plate]    = nil

    -- Registra cargo sob a plate do ladrão
    VP_Trucker.CargoByPlate[thiefPlate] = {
        jobId           = cargo.jobId,
        citizenId       = thiefCitizenId,
        gpsEnabled      = false,
        isStolen        = true,
        basePayment     = cargo.basePayment,
        vulnerableSince = nil,
        theftBy         = nil,
        theftStartedAt  = nil,
        stolenAt        = os.time(),  -- referência de tempo server-side para JobService.CompleteTheft
        destId          = result.destId,
    }

    return result
end

-- Cancela roubo (chamado quando ladrão desiste ou dono voltou)
function CargoTrackingService.CancelTheft(plate, thiefCitizenId)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return end
    if cargo.theftBy ~= thiefCitizenId then return end
    cargo.theftBy        = nil
    cargo.theftStartedAt  = nil
end

-- Reivindica entrega — valida que o plate e citizenId batem
-- Retorna cargo entry (e remove do mapa) on success, nil on failure
-- Chamado de: events.lua (completeJob)
function CargoTrackingService.ClaimDelivery(plate, citizenId)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return nil end
    if cargo.citizenId ~= citizenId then return nil end
    VP_Trucker.CargoByPlate[plate] = nil
    PendingVulnerability[plate]    = nil
    return cargo
end

-- Remove entrada (job abandonado ou falhou por outro motivo)
function CargoTrackingService.RemoveCargo(plate)
    VP_Trucker.CargoByPlate[plate] = nil
    PendingVulnerability[plate]    = nil
end

-- Recupera cargo ativo do DB no startup (jobs que estavam ativos quando o server caiu)
function CargoTrackingService.LoadFromDB()
    local rows = DB_GetActiveCargoJobs() or {}
    for _, row in ipairs(rows) do
        VP_Trucker.CargoByPlate[row.truck_plate] = {
            jobId           = row.id,
            citizenId       = row.assigned_citizenid,
            gpsEnabled      = false,  -- GPS state não é persistido; conservador: sem notificação pós-restart
            isStolen        = false,
            basePayment     = row.base_payment,
            vulnerableSince = nil,
            theftBy         = nil,
            theftStartedAt  = nil,
        }
    end
    if Config.Debug then
        print(('[aurp_trucker] CargoTracking: recovered %d active cargo entries'):format(#rows))
    end
end
