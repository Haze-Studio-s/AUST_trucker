-- Regras puras (sem natives) de registro de pallet no trailer, usadas por HandlePalletLoaded.
-- Garante: netId bem formado e do lobby; um pallet = um slot; um slot = um pallet; retry idempotente.
PalletRegistry = {}

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

function PalletRegistry.ParseNetId(v)
    if type(v) ~= 'number' or not finite(v) or v % 1 ~= 0 or v <= 0 then return nil end
    return v
end

-- Devolve verdict ('ok' | 'retry' | 'reject'), reason, netId resolvido, slot parseado.
function PalletRegistry.Evaluate(lobby, slotIndex, palletNetId)
    local required = lobby.requiredCount or 0

    local slot = nil
    if slotIndex ~= nil then
        slot = tonumber(slotIndex)
        if not finite(slot) or slot < 1 or slot > required or slot % 1 ~= 0 then
            return 'reject', 'slot ' .. tostring(slotIndex) .. ' fora de 1..' .. tostring(required)
        end
    end

    local nid = nil
    if palletNetId ~= nil then
        nid = PalletRegistry.ParseNetId(palletNetId)
        if not nid then
            return 'reject', 'netId malformado: ' .. tostring(palletNetId)
        end
        local found = false
        for _, known in ipairs(lobby.palletNetIds or {}) do
            if known == nid then found = true break end
        end
        if not found then
            return 'reject', 'netId ' .. tostring(nid) .. ' não é palete deste lobby'
        end
    else
        nid = (lobby.palletNetIds or {})[slot or ((lobby.loadedCount or 0) + 1)]
    end

    local usedPallets = lobby.usedPallets or {}
    local slotPallets = lobby.slotPallets or {}
    local usedSlots = lobby.usedSlots or {}

    if nid and usedPallets[nid] ~= nil then
        local prev = usedPallets[nid]
        if slot == nil or slot == prev then
            return 'retry', nil, nid, prev
        end
        return 'reject', ('palete %s já registrado no slot %s (pedido: %s)'):format(tostring(nid), tostring(prev), tostring(slot))
    end

    if slot and (slotPallets[slot] ~= nil or usedSlots[slot]) then
        return 'reject', 'slot ' .. tostring(slot) .. ' já ocupado'
    end

    return 'ok', nil, nid, slot
end

function PalletRegistry.Commit(lobby, nid, slot, loadedCount)
    lobby.usedPallets = lobby.usedPallets or {}
    lobby.slotPallets = lobby.slotPallets or {}
    lobby.usedSlots = lobby.usedSlots or {}
    local key = slot or loadedCount
    if nid then lobby.usedPallets[nid] = key end
    lobby.slotPallets[key] = nid or true
    if slot then lobby.usedSlots[slot] = true end
end

-- Plausibilidade pallet↔trailer. dist nil = entidade inexistente no servidor.
function PalletRegistry.CheckPlacement(dist, maxDist)
    if dist == nil then return false, 'palete inexistente no servidor' end
    if not finite(dist) or dist > maxDist then
        return false, ('palete a %s m da carreta (máx %s)'):format(tostring(dist), tostring(maxDist))
    end
    return true
end

-- ============================================================================
-- Estado lógico do pallet (autoridade do servidor):
--   STAGED -> CLAIMED -> CARRIED -> STOWED -> DELIVERED, mais RECOVERY (voltando ao chão).
-- Cada registro: { state, carrier, slot, version, claimedAt, reqs = { [op] = reqId } }.
-- CAS: toda transição valida o estado de origem e o carregador; `version` sobe a cada mudança.
-- Idempotência: repetir a mesma operação com o mesmo reqId devolve o mesmo resultado sem mudar nada.
-- ============================================================================
PalletRegistry.State = {
    STAGED = 'STAGED', CLAIMED = 'CLAIMED', CARRIED = 'CARRIED',
    STOWED = 'STOWED', DELIVERED = 'DELIVERED', RECOVERY = 'RECOVERY',
}
local S = PalletRegistry.State

local function isLobbyPallet(lobby, nid)
    for i, known in ipairs(lobby.palletNetIds or {}) do
        if known == nid then return true, i end
    end
    return false
end

-- Cria sob demanda; só pallets do lobby têm registro.
function PalletRegistry.Get(lobby, nid)
    nid = PalletRegistry.ParseNetId(nid)
    if not nid then return nil, 'netId malformado' end
    local ok, idx = isLobbyPallet(lobby, nid)
    if not ok then return nil, 'netId ' .. tostring(nid) .. ' não é palete deste lobby' end
    lobby.palletStates = lobby.palletStates or {}
    local rec = lobby.palletStates[nid]
    if not rec then
        rec = { state = S.STAGED, carrier = nil, slot = idx, version = 0, reqs = {} }
        lobby.palletStates[nid] = rec
    end
    return rec, nil, nid
end

local function bump(rec, state, carrier)
    rec.state, rec.carrier = state, carrier
    rec.version = rec.version + 1
end

local function repeated(rec, op, reqId)
    return reqId ~= nil and rec.reqs[op] == reqId
end

-- Quantos pallets (CLAIMED/CARRIED) o jogador já segura. Um forklift carrega um por vez.
function PalletRegistry.CarriedBy(lobby, src)
    local n = 0
    for _, rec in pairs(lobby.palletStates or {}) do
        if rec.carrier == src and (rec.state == S.CLAIMED or rec.state == S.CARRIED) then n = n + 1 end
    end
    return n
end

-- Reivindicação lazy: um CLAIMED que não virou CARRIED dentro do lease volta a STAGED.
function PalletRegistry.ExpireClaims(lobby, nowMs, leaseMs)
    local freed = {}
    for nid, rec in pairs(lobby.palletStates or {}) do
        if rec.state == S.CLAIMED and rec.claimedAt and (nowMs - rec.claimedAt) >= leaseMs then
            bump(rec, S.STAGED, nil)
            rec.claimedAt = nil
            freed[#freed + 1] = nid
        end
    end
    return freed
end

-- opts = { maxCarried = 1 }. Devolve ok, reason, rec.
function PalletRegistry.Claim(lobby, nid, src, reqId, nowMs, opts)
    local rec, err, id = PalletRegistry.Get(lobby, nid)
    if not rec then return false, err end
    if repeated(rec, 'claim', reqId) and rec.carrier == src and (rec.state == S.CLAIMED or rec.state == S.CARRIED) then
        return true, nil, rec, true
    end
    if rec.state ~= S.STAGED then
        return false, ('palete %s em %s (esperado STAGED)'):format(tostring(id), rec.state)
    end
    local maxCarried = (opts and opts.maxCarried) or 1
    if PalletRegistry.CarriedBy(lobby, src) >= maxCarried then
        return false, 'jogador já segura ' .. tostring(maxCarried) .. ' palete(s)'
    end
    bump(rec, S.CLAIMED, src)
    rec.claimedAt = nowMs
    rec.reqs.claim = reqId
    return true, nil, rec, false
end

function PalletRegistry.ConfirmCarry(lobby, nid, src, reqId)
    local rec, err, id = PalletRegistry.Get(lobby, nid)
    if not rec then return false, err end
    if rec.state == S.CARRIED and rec.carrier == src then return true, nil, rec, true end
    if rec.state ~= S.CLAIMED or rec.carrier ~= src then
        return false, ('palete %s em %s com carregador %s (esperado CLAIMED de %s)'):format(
            tostring(id), rec.state, tostring(rec.carrier), tostring(src))
    end
    bump(rec, S.CARRIED, src)
    rec.claimedAt = nil
    rec.reqs.confirm = reqId
    return true, nil, rec, false
end

-- Liberação voluntária (jogador saiu do forklift / attach falhou): volta ao chão no slot de origem.
function PalletRegistry.Release(lobby, nid, src, reqId)
    local rec, err, id = PalletRegistry.Get(lobby, nid)
    if not rec then return false, err end
    if rec.state == S.STAGED then return true, nil, rec, true end
    if (rec.state ~= S.CLAIMED and rec.state ~= S.CARRIED) or rec.carrier ~= src then
        return false, ('palete %s em %s não liberável por %s'):format(tostring(id), rec.state, tostring(src))
    end
    bump(rec, S.STAGED, nil)
    rec.claimedAt = nil
    rec.reqs.release = reqId
    return true, nil, rec, false
end

-- Estiva confirmada pelo registro de slot (HandlePalletLoaded). Aceita só quem carregava.
-- strict = exige CARRIED (RequireClaim); sem strict, aceita STAGED (fluxo legado sem claim).
function PalletRegistry.CanStow(lobby, nid, src, strict)
    if nid == nil then return not strict, strict and 'palete sem netId' or nil end
    local rec, err = PalletRegistry.Get(lobby, nid)
    if not rec then return false, err end
    if rec.state == S.STOWED or rec.state == S.DELIVERED then return true, nil, rec end
    if rec.state == S.CARRIED and rec.carrier == src then return true, nil, rec end
    if not strict and rec.state == S.STAGED then return true, nil, rec end
    return false, ('palete %s em %s (carregador %s); estiva exige CARRIED por %s'):format(
        tostring(nid), rec.state, tostring(rec.carrier), tostring(src)), rec
end

function PalletRegistry.MarkStowed(lobby, nid, slot)
    local rec = PalletRegistry.Get(lobby, nid)
    if not rec then return false end
    if rec.state == S.STOWED or rec.state == S.DELIVERED then return true end
    bump(rec, S.STOWED, rec.carrier)
    if slot then rec.slot = slot end
    return true
end

function PalletRegistry.MarkDelivered(lobby)
    local n = 0
    for _, rec in pairs(lobby.palletStates or {}) do
        if rec.state == S.STOWED then bump(rec, S.DELIVERED, rec.carrier) n = n + 1 end
    end
    return n
end

-- Queda do carregador / forklift destruído: CLAIMED e CARRIED vão para RECOVERY.
-- O chamador devolve o pallet ao chão e então chama MarkRecovered.
function PalletRegistry.Recover(lobby, src)
    local list = {}
    for nid, rec in pairs(lobby.palletStates or {}) do
        if rec.carrier == src and (rec.state == S.CLAIMED or rec.state == S.CARRIED) then
            bump(rec, S.RECOVERY, nil)
            rec.claimedAt = nil
            list[#list + 1] = nid
        end
    end
    return list
end

function PalletRegistry.MarkRecovered(lobby, nid)
    local rec = PalletRegistry.Get(lobby, nid)
    if rec and rec.state == S.RECOVERY then bump(rec, S.STAGED, nil) return true end
    return false
end
