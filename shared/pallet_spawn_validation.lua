-- Validação pura (sem natives) dos spawns de pallet vindos do config ou do banco.
-- Não altera nem apaga dado de origem: devolve a lista aceita e a lista rejeitada com o motivo.
PalletSpawnValidation = {}

local DEFAULT_RULES = {
    maxCount      = 16,    -- máximo de spawns aceitos
    exactDup      = 0.01,  -- distância 3D abaixo da qual é duplicata exata
    nearDup       = 0.5,   -- distância 2D abaixo da qual é duplicata aproximada
    minSpacing    = 1.5,   -- distância 2D mínima entre dois pallets
    maxAbsXY      = 8000.0,
    minZ          = -200.0,
    maxZ          = 2000.0,
}

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function rule(rules, key)
    local v = rules and rules[key]
    if finite(v) then return v end
    return DEFAULT_RULES[key]
end

function PalletSpawnValidation.Validate(raw, rules)
    local accepted, rejected = {}, {}
    if type(raw) ~= 'table' then return accepted, rejected end

    local maxCount = rule(rules, 'maxCount')
    local exactDup = rule(rules, 'exactDup')
    local nearDup = rule(rules, 'nearDup')
    local minSpacing = rule(rules, 'minSpacing')
    local maxAbsXY = rule(rules, 'maxAbsXY')
    local minZ = rule(rules, 'minZ')
    local maxZ = rule(rules, 'maxZ')

    for index, c in ipairs(raw) do
        local x, y, z
        if type(c) == 'table' or type(c) == 'vector3' or type(c) == 'vector4' then
            x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
        end
        local reason
        if not x then
            reason = 'coordenada malformada'
        elseif not (finite(x) and finite(y) and finite(z)) then
            reason = 'coordenada não finita'
        elseif math.abs(x) > maxAbsXY or math.abs(y) > maxAbsXY or z < minZ or z > maxZ then
            reason = 'coordenada fora do mundo'
        elseif #accepted >= maxCount then
            reason = 'excede o máximo de spawns'
        else
            for _, a in ipairs(accepted) do
                local d2 = math.sqrt((a.x - x) ^ 2 + (a.y - y) ^ 2)
                local d3 = math.sqrt(d2 ^ 2 + (a.z - z) ^ 2)
                if d3 < exactDup then
                    reason = 'duplicata exata'
                elseif d2 < nearDup then
                    reason = 'duplicata aproximada'
                elseif d2 < minSpacing then
                    reason = 'muito próximo de outro spawn'
                end
                if reason then break end
            end
        end
        if reason then
            rejected[#rejected + 1] = { index = index, reason = reason, x = x, y = y, z = z }
        else
            accepted[#accepted + 1] = { x = x, y = y, z = z }
        end
    end
    return accepted, rejected
end
