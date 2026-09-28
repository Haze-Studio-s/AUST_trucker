-- server/services/anti_cheat_service.lua
-- AntiCheatService — rate limiting por evento + validação de entrega
-- Sem dependências de outros services (carregado antes de job_service)

AntiCheatService = {}

-- _cooldowns[citizenId][action] = os.time() + cooldownSeconds
-- CleanupPlayer remove _cooldowns[citizenId] inteiramente para evitar tabela esparsa
local _cooldowns = {}

-- Lookup pré-computado: _secondaryById[id] = industry data
-- Evita O(n) loop em ValidateDelivery (chamado em cada entrega)
local _secondaryById = {}
for _, d in ipairs(Config.SecondaryIndustries or {}) do
    _secondaryById[d.id] = d
end

-- Verifica e aplica rate limit para uma ação.
-- Retorna true se permitido, false se bloqueado (cooldown ativo).
function AntiCheatService.RateLimit(citizenId, action)
    if not Config.AntiCheat.Enabled then return true end
    local cooldown = Config.AntiCheat.RateLimits[action]
    if not cooldown or cooldown <= 0 then return true end

    local now = os.time()
    _cooldowns[citizenId] = _cooldowns[citizenId] or {}
    local expiry = _cooldowns[citizenId][action]
    if expiry and now < expiry then
        if Config.Debug then
            print(('[AC] RateLimit bloqueou %s:%s (%.0fs restantes)'):format(
                citizenId, action, expiry - now))
        end
        return false
    end
    _cooldowns[citizenId][action] = now + cooldown
    return true
end

-- Valida se uma entrega é legítima.
-- activeJob: linha raw de DB_GetActiveJobByPlayer (campos: dest_id, distance, accepted_at_unix)
-- elapsedSeconds: os.time() - activeJob.accepted_at_unix (calculado pelo chamador)
-- src: player source (para GetPlayerPed + GetEntityCoords via OneSync)
-- Retorna: ok (bool), reason (string|nil)
function AntiCheatService.ValidateDelivery(src, citizenId, activeJob, elapsedSeconds)
    if not Config.AntiCheat.Enabled then return true, nil end

    if not activeJob or not activeJob.dest_id then
        return false, 'Nenhuma missão ativa encontrada para validação.'
    end

    -- 1. Velocidade máxima e tempo mínimo realista de viagem (anti-teleport)
    --    minSeconds = (distance_km / MaxSpeedKmh) * 3600
    local distKm = tonumber(activeJob.distance) or 0
    local maxSpeed = tonumber(Config.AntiCheat.MaxSpeedKmh) or 120.0
    local calculatedMin = (distKm / maxSpeed) * 3600
    local absoluteMin = tonumber(Config.AntiCheat.MinTravelTimeSeconds) or 25

    local minSeconds = math.max(absoluteMin, math.floor(calculatedMin))
    if elapsedSeconds < minSeconds then
        if Config.Debug then
            print(('[AC] ValidateDelivery FAIL velocidade: %s elapsed=%ds min=%ds dist=%.1fkm'):format(
                citizenId, elapsedSeconds, minSeconds, distKm))
        end
        return false, ('Tempo de viagem insuficiente (%ds decorridos, mínimo necessário: %ds).'):format(elapsedSeconds, minSeconds)
    end

    -- 2. Proximidade ao destino (OneSync — fail-closed)
    local destCoords = nil
    local _dest = _secondaryById[activeJob.dest_id]
    -- M-01: fallback lazy para industries adicionadas dinamicamente após boot
    if not _dest then
        for _, d in ipairs(Config.SecondaryIndustries or {}) do
            if d.id == activeJob.dest_id then
                _secondaryById[d.id] = d  -- cachear para próximas chamadas
                _dest = d
                break
            end
        end
    end
    if _dest then destCoords = _dest.coords end

    if not destCoords then
        if Config.Debug then print(('[AC] ValidateDelivery FAIL: destCoords não encontrado para %s'):format(tostring(activeJob.dest_id))) end
        return false, 'Destino de entrega inválido.'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        if Config.Debug then print(('[AC] ValidateDelivery FAIL: ped inválido para %s'):format(citizenId)) end
        return false, 'Estado do jogador inválido — tente novamente.'
    end

    -- HARDENING: Validar routing bucket (entregas apenas na dimensão principal)
    if GetPlayerRoutingBucket(src) ~= 0 then
        return false, 'Entrega não permitida em dimensão privada.'
    end

    local pos = GetEntityCoords(ped)
    -- #10: Fail-closed em (0,0,0)
    if pos.x == 0.0 and pos.y == 0.0 and pos.z == 0.0 then
        if Config.Debug then print(('[AC] ValidateDelivery BLOCKED: coords (0,0,0) para %s'):format(citizenId)) end
        return false, 'Posição inválida — tente novamente'
    end

    local destVec = vec3(destCoords.x, destCoords.y, destCoords.z)
    local dist = #(pos - destVec)
    if dist > Config.AntiCheat.DestinationRadius then
        if Config.Debug then
            print(('[AC] ValidateDelivery FAIL posição: %s dist_dest=%.1fm max=%.1fm'):format(
                citizenId, dist, Config.AntiCheat.DestinationRadius))
        end
        return false, 'Você não está no destino de entrega.'
    end

    return true, nil
end

-- Remove todos os cooldowns de um jogador ao desconectar.
-- IMPORTANTE: remove a key completa, não apenas as sub-keys, para evitar crescimento de tabela esparsa.
function AntiCheatService.CleanupPlayer(citizenId)
    _cooldowns[citizenId] = nil
end
