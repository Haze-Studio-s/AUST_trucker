-- aurp_trucker — server/exports.lua
-- API pública para integração com vp-sala e outros domínios

-- ============================================================
-- PARCEL DELIVERY — Workers ativos
-- ============================================================

--- Lista todos os entregadores de encomendas ativos no momento.
--- Útil para vp-sala, painéis administrativos e dispatch.
--- @return table[] [{ citizenId, source, name, routeLabel, completedStops }]
exports('GetParcelWorkers', function()
    if not ParcelService then return {} end
    return ParcelService.GetActiveWorkers()
end)

--- Verifica se um jogador está realizando entrega de encomendas.
--- @param citizenId string
--- @return boolean
exports('IsDoingParcel', function(citizenId)
    if not ParcelService then return false end
    return ParcelService.IsWorking(citizenId)
end)

-- Job ativo de um jogador (para inspeção SALA em tempo real)
-- @param citizenId string
-- @return table|nil { jobId, originName, destName, cargoItem, trailerModel, payment, acceptedAt }
exports('GetPlayerActiveJob', function(citizenId)
    if not JobService or type(citizenId) ~= 'string' then return nil end
    return JobService.GetActiveByPlayer(citizenId)
end)

-- Manifesto de transporte (documento para fiscalização física)
-- @return table|nil { cargo, trailerModel, origin, destination, companyName, issuedAt }
exports('GetJobManifest', function(citizenId)
    if not JobService or type(citizenId) ~= 'string' then return nil end
    return JobService.GetManifest(citizenId)
end)

-- Dados da empresa para auditoria SALA
-- @return table|nil { id, name, ownerCitizenId, balance, is_recruiting }
exports('GetCompanyInfo', function(companyId)
    if not CompanyService then return nil end
    return CompanyService.Get(companyId)
end)

-- Empresa de um jogador
-- @return table|nil
exports('GetPlayerCompany', function(citizenId)
    if not CompanyService or type(citizenId) ~= 'string' then return nil end
    return CompanyService.GetByMember(citizenId)
end)

-- SALA registra infração
-- @param infractionType 'overload'|'no_manifest'|'expired_manifest'|'dangerous_cargo'
-- @param issuedBy citizenid do inspetor OU 'vp-sala:auto'
-- @return boolean
exports('RecordInfraction', function(citizenId, infractionType, reason, issuedBy)
    if not JobService or type(citizenId) ~= 'string' or type(infractionType) ~= 'string' then return false end
    return JobService.RecordInfraction(citizenId, infractionType, reason, issuedBy)
end)

-- Histórico de infrações para MDT SALA
-- @return table[]
exports('GetInfractions', function(citizenId)
    if type(citizenId) ~= 'string' or not DB_GetInfractions then return {} end
    return DB_GetInfractions(citizenId)
end)

-- ============================================================
-- TRUCK SIMULATION — para HUDs externas e integração
-- ============================================================

-- Último combustível sincronizado do jogador (0–100)
-- Use quando Config.TruckSimulation.HUD.Enabled = false e tiver HUD própria
exports('GetPlayerFuel', function(source)
    if not TruckSimulationService then return 100.0 end
    local state = TruckSimulationService.GetState(source)
    return state and state.lastFuel or 100.0
end)

-- Última fadiga sincronizada do jogador (0–100)
exports('GetPlayerFatigue', function(source)
    if not TruckSimulationService then return 0.0 end
    local state = TruckSimulationService.GetState(source)
    return state and state.lastFatigue or 0.0
end)

-- ============================================================
-- CRUDE OIL PIPELINE (Phase 1)
-- ============================================================

--- Returns active crude oil job for a given vehicle plate.
--- Used by vp-sala (via pcall) to verify manifest during transport checks.
exports('GetActiveJobByPlate', function(plate)
    if type(plate) ~= 'string' or not GetActiveCrudeJobByPlate then return nil end
    local job = GetActiveCrudeJobByPlate(plate)
    if not job then return nil end
    return {
        cargoType      = 'crude_oil',
        manifestId     = job.manifestId,
        wellId         = job.wellId,
        barrelCount    = job.qty,
        pricePerBarrel = job.pricePerBarrel,
    }
end)
