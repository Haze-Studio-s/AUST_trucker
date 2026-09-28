-- aurp_trucker — server/services/adr_service.lua
-- Gerencia certificações ADR (hazmat) dos jogadores
-- Global: AdrService (acessível por callbacks.lua e job_service.lua)

AdrService = {}

-- Retorna true se o citizenId possui certificação adrType válida (não expirada)
function AdrService.HasCert(citizenId, adrType)
    local row = DB_GetAdrCert(citizenId, adrType)
    if not row then return false end
    return row.expires_at > os.time()
end

-- Concede certificação por Config.Adr.ValiditySeconds segundos
-- Retorna: expiresAt (number)
function AdrService.GrantCert(citizenId, adrType)
    local expiresAt = os.time() + Config.Adr.ValiditySeconds
    DB_UpsertAdrCert(citizenId, adrType, expiresAt)
    return expiresAt
end

-- Renova certificação (atalho para GrantCert)
-- Retorna: expiresAt (number)
function AdrService.Renew(citizenId, adrType)
    return AdrService.GrantCert(citizenId, adrType)
end

-- Retorna mapa { [adr_type] = expires_at } apenas com certs válidas (não expiradas)
function AdrService.GetValid(citizenId)
    local rows = DB_GetAdrCerts(citizenId) or {}
    local now  = os.time()
    local valid = {}
    for _, row in ipairs(rows) do
        if row.expires_at > now then
            valid[row.adr_type] = row.expires_at
        end
    end
    return valid
end

-- Retorna lista enriquecida de TODAS as certs (válidas e expiradas) para a UI
-- Cada objeto: { adr_type, expires_at, label }
-- Tipos sem linha no DB não aparecem aqui (NUI complementa com os 6 tipos)
function AdrService.GetAll(citizenId)
    local rows  = DB_GetAdrCerts(citizenId) or {}
    local result = {}
    for _, row in ipairs(rows) do
        result[#result + 1] = {
            adr_type   = row.adr_type,
            expires_at = row.expires_at,
            label      = Config.Adr.TypeLabels[row.adr_type],
        }
    end
    return result
end
