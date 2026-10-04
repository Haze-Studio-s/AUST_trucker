-- Regras puras (sem natives) do levantamento cinemático de pallet pelos garfos.
-- O pallet fica frozen no chão; a "primeira elevação" é lida no OSSO dos garfos, no referencial
-- do forklift (imune a rampa/inclinação e sem depender de física no pallet).
-- Usado por client/modules/forklift.lua. Todos os limiares vêm de Config.Polarix.KinematicLift.
ForkLift = {}

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

-- Diferença angular modular em [0, 180] (corrige a checagem frouxa do ESX: |a-b| < 1 or |a-b|-180 < 1).
function ForkLift.AngleDiff(a, b)
    if not finite(a) or not finite(b) then return 180.0 end
    local d = math.abs((a - b) % 360.0)
    if d > 180.0 then d = 360.0 - d end
    return d
end

-- Pallet e garfo são simétricos em 180°: devolve a diferença módulo 180 em [0, 90].
function ForkLift.AxisDiff(a, b)
    if not finite(a) or not finite(b) then return 90.0 end -- entrada inválida nunca "alinha"
    local d = ForkLift.AngleDiff(a, b)
    if d > 90.0 then d = 180.0 - d end
    return d
end

-- Alinhamento geométrico: palletLocal = posição do pallet no referencial do forklift.
function ForkLift.IsAligned(palletLocal, headingDiff, speed, cfg)
    local a = cfg.Align
    if not palletLocal or not finite(palletLocal.x) or not finite(palletLocal.y) or not finite(palletLocal.z) then
        return false
    end
    if math.abs(palletLocal.x) > a.xMax then return false end
    if palletLocal.y < a.yMin or palletLocal.y > a.yMax then return false end
    if math.abs(palletLocal.z) > a.zMax then return false end
    if not finite(headingDiff) or headingDiff > cfg.HeadingTolerance then return false end
    if not finite(speed) or speed > cfg.MaxForkliftSpeed then return false end
    return true
end

-- Detector por pallet. Fases: idle -> engaged -> (evento 'intent').
function ForkLift.NewDetector()
    return { phase = 'idle', minZ = nil, riseSince = nil, delta = 0.0 }
end

-- Devolve evento ('none' | 'engage' | 'intent' | 'disengage'), delta de elevação.
-- boneZ = Z do osso dos garfos no referencial do forklift; now em ms.
function ForkLift.Step(st, now, aligned, boneZ, cfg)
    if not finite(boneZ) then return 'none', st.delta end

    if not aligned then
        local was = st.phase == 'engaged'
        st.phase, st.minZ, st.riseSince, st.delta = 'idle', nil, nil, 0.0
        return was and 'disengage' or 'none', 0.0
    end

    if st.phase == 'idle' then
        st.phase, st.minZ, st.riseSince, st.delta = 'engaged', boneZ, nil, 0.0
        return 'engage', 0.0
    end

    -- engaged: o repouso acompanha o ponto mais baixo (mastro descendo não gera falso intent)
    if boneZ < st.minZ then st.minZ = boneZ end
    st.delta = boneZ - st.minZ

    if st.delta >= cfg.LiftThreshold then
        st.riseSince = st.riseSince or now
        if (now - st.riseSince) >= cfg.LiftDwellMs then
            return 'intent', st.delta
        end
    elseif st.delta < (cfg.LiftThreshold - cfg.LiftHysteresis) then
        st.riseSince = nil
    end
    return 'none', st.delta
end

-- Offset do pallet relativo ao osso, preservando a pose do mundo (snap visual zero).
-- palletLocal/boneLocal = posições no referencial do forklift. Premissa: osso com a mesma orientação
-- da raiz do veículo (garfos só sobem e descem); o chamador valida o erro depois do attach.
function ForkLift.RelativeAttach(palletLocal, boneLocal, palletRot, vehicleRot)
    local function norm(a)
        a = (a + 180.0) % 360.0 - 180.0
        return a
    end
    return {
        x = palletLocal.x - boneLocal.x,
        y = palletLocal.y - boneLocal.y,
        z = palletLocal.z - boneLocal.z,
        pitch = norm((palletRot.x or 0.0) - (vehicleRot.x or 0.0)),
        roll  = norm((palletRot.y or 0.0) - (vehicleRot.y or 0.0)),
        yaw   = norm((palletRot.z or 0.0) - (vehicleRot.z or 0.0)),
    }
end

-- Interpolação linear (0..1) de duas poses de attach, usada para assentar no perfil calibrado.
function ForkLift.Blend(from, to, t)
    if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
    local function l(a, b) return a + (b - a) * t end
    local function la(a, b)
        local d = ((b - a + 180.0) % 360.0) - 180.0
        return a + d * t
    end
    return {
        x = l(from.x, to.x), y = l(from.y, to.y), z = l(from.z, to.z),
        pitch = la(from.pitch, to.pitch), roll = la(from.roll, to.roll), yaw = la(from.yaw, to.yaw),
    }
end

-- Perfil de attach por combinação forkliftModel x palletModel (chaves: nome ou hash).
-- Nunca mistura com os offsets de trailer: o perfil de garfo é uma tabela própria.
function ForkLift.ResolveProfile(profiles, forkliftKeys, palletKeys)
    if type(profiles) ~= 'table' then return nil end
    for _, fk in ipairs(forkliftKeys) do
        local group = profiles[fk]
        if type(group) == 'table' then
            for _, pk in ipairs(palletKeys) do
                local p = group[pk]
                if type(p) == 'table' then
                    return {
                        bone = p.bone,
                        x = p.x or 0.0, y = p.y or 0.0, z = p.z or 0.0,
                        pitch = p.pitch or 0.0, roll = p.roll or 0.0, yaw = p.yaw or 0.0,
                    }
                end
            end
        end
    end
    return nil
end

-- Erro (m) entre a posição do pallet antes e depois do attach.
function ForkLift.AttachError(before, after)
    local dx, dy, dz = before.x - after.x, before.y - after.y, before.z - after.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
