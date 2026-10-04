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
