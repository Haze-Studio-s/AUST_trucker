-- aurp_trucker — server/services/admin_service.lua
-- Serviço Administrativo em Tempo Real: Rotas, Spawns, Offsets 3D, Economia e NPCs

AdminService = {}

AdminService.CustomRoutes = {}
AdminService.Spawns = {}
AdminService.TrailerOffsets = {}
AdminService.VehiclePropOffsets = {}
AdminService.HomologatedProps = {}
AdminService.NPCs = {}
AdminService.Economy = {
    km_multiplier = 3.5,
    xp_multiplier = 1.0,
    adr_bonus_pct = 35.0,
    fragile_bonus_pct = 20.0,
    valuable_bonus_pct = 25.0,
    base_payment_per_km = 18.5,
    base_xp_per_km = 5.0,
    adr_multiplier = 1.45,
    fragile_bonus = 1.25,
    valuable_bonus = 1.35,
    cargo_loss_penalty = 500
}

-- ============================================================
-- VALIDAÇÃO / SANITIZAÇÃO DE ENTRADAS ADMIN
-- ============================================================

local function IsFiniteNumber(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

-- Número finito dentro de [min,max]; fora do intervalo é limitado, inválido vira default
local function ClampNum(v, min, max, default)
    local n = tonumber(v)
    if not IsFiniteNumber(n) then return default end
    if n < min then return min end
    if n > max then return max end
    return n
end

-- String aparada e limitada ao tamanho da coluna; inválida vira default
local function CleanStr(v, maxLen, default)
    if type(v) ~= 'string' and type(v) ~= 'number' then return default end
    local str = tostring(v):gsub('^%s*(.-)%s*$', '%1')
    if str == '' then return default end
    if #str > maxLen then str = str:sub(1, maxLen) end
    return str
end

-- Identificador seguro (letras, números, _ e -)
local function CleanId(v, maxLen)
    local str = CleanStr(v, maxLen, nil)
    if not str or str:find('[^%w_%-]') then return nil end
    return str
end

local function CleanCoords(c)
    if type(c) ~= 'table' then return {} end
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not (IsFiniteNumber(x) and IsFiniteNumber(y) and IsFiniteNumber(z)) then return {} end
    if math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or z < -500.0 or z > 2500.0 then return {} end
    local out = { x = x, y = y, z = z }
    local w = tonumber(c.w or c.heading)
    if IsFiniteNumber(w) then out.w = w end
    return out
end

local ROUTE_TYPES  = { quick = true, freight = true, adr = true, heavy = true, carrier = true }
local SPAWN_TYPES  = { truck = true, trailer = true, forklift = true, pallet = true, handler = true, loading_bay = true, delivery = true, load_bay = true, delivery_bay = true }
local PROP_CATS    = { dry = true, fragile = true, valuable = true, adr = true, heavy = true }

-- Chaves de economia permitidas e seus intervalos [min, max]
local ECONOMY_LIMITS = {
    km_multiplier       = { 0.1, 10.0 },
    xp_multiplier       = { 0.1, 10.0 },
    adr_multiplier      = { 0.1, 10.0 },
    fragile_bonus       = { 0.1, 10.0 },
    valuable_bonus      = { 0.1, 10.0 },
    adr_bonus_pct       = { 0.0, 500.0 },
    fragile_bonus_pct   = { 0.0, 500.0 },
    valuable_bonus_pct  = { 0.0, 500.0 },
    base_payment_per_km = { 0.0, 1000.0 },
    base_xp_per_km      = { 0.0, 1000.0 },
    cargo_loss_penalty  = { 0.0, 100000.0 },
}

local MAX_BASE_PAYMENT = 500000
local MAX_BASE_XP      = 50000

local function AdminLog(src, action, detail)
    print(('[AUST_Trucker Admin] src=%s action=%s %s'):format(tostring(src), tostring(action), detail and tostring(detail) or ''))
end

-- ============================================================
-- VERIFICAÇÃO DE PERMISSÕES MULTI-FRAMEWORK
-- ============================================================

function AdminService.IsPlayerAdmin(src)
    -- Apenas o console do servidor (src == 0) é implicitamente admin; nil/inválido nunca
    if src == 0 then return true end
    if type(src) ~= 'number' then return false end

    -- 1. ACE Permissions (Nativa FiveM) — exige a ACE dedicada (ACEs genéricas 'command'/'admin' não bastam)
    if IsPlayerAceAllowed(src, 'command.truckeradmin') then
        return true
    end

    local fw = Config.Framework or 'qbx'

    -- 2. QBX Core
    if fw == 'qbx' and exports.qbx_core then
        local ok, hasPerm = pcall(function()
            return exports.qbx_core:HasPermission(src, 'admin') or exports.qbx_core:HasPermission(src, 'god')
        end)
        if ok and hasPerm then return true end
    end

    -- 3. QBCore
    if (fw == 'qbcore' or fw == 'qbx') and QBCore and QBCore.Functions then
        local ok, hasPerm = pcall(function()
            return QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god')
        end)
        if ok and hasPerm then return true end
    end

    -- 4. ESX Legacy
    if fw == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local group = xPlayer.getGroup()
            if group == 'admin' or group == 'superadmin' or group == 'owner' then
                return true
            end
        end
    end

    return false
end

-- ============================================================
-- CARREGAMENTO E SINCRONIZAÇÃO EM MEMÓRIA (BOOT & REFRESH)
-- ============================================================

function AdminService.SeedDefaultRoutes()
    local loads = (Config.LC_Jobs and Config.LC_Jobs.available_loads) or {}
    local deliveryLocs = Config.LC_DeliveryLocations or { vector4(1452.67, 6552.02, 14.89, 138.69) }
    local originCoords = Config.LC_Headquarters and Config.LC_Headquarters.coords or vector3(1208.83, -3115.0, 5.54)
    local rentalTrucks = { "hauler", "phantom", "packer", "hauler2", "brickades" }

    for i, load in ipairs(loads) do
        local routeId = 'route_' .. tostring(i)
        local def = load.def or {0, 0, 0, 0}
        local adr = (def[1] or 0) > 0
        local fragile = (def[2] or 0) > 0
        local valuable = (def[3] or 0) > 0
        local destIndex = ((i - 1) % #deliveryLocs) + 1
        local dest = deliveryLocs[destIndex] or deliveryLocs[1]
        local truckModel = rentalTrucks[((i - 1) % #rentalTrucks) + 1]
        local jobType = (i % 2 == 0) and 'freight' or 'quick'
        if adr then jobType = 'adr' end

        local rawDist = #(vector3(dest.x, dest.y, dest.z) - originCoords) / 1000.0
        local realDist = tonumber(string.format("%.2f", rawDist)) or 1.0
        if realDist <= 0 then realDist = 1.0 end

        local basePay = math.floor(realDist * (AdminService.Economy.base_payment_per_km or 18.5) * 100 + 1200)
        local baseXP = math.floor(realDist * (AdminService.Economy.base_xp_per_km or 5.0) * 15 + 150)

        MySQL.query.await([[
            INSERT IGNORE INTO aust_trucker_custom_routes
            (id, name, type, cargo_model, cargo_name, truck_model, trailer_model, base_payment, base_xp, req_skill, fragile, valuable, pickup_coords, delivery_coords, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        ]], {
            routeId,
            load.name or ('Contrato #' .. i),
            jobType,
            'hei_prop_carrier_cargo_04b',
            load.name or 'Paletes Industriais',
            truckModel,
            load.trailer or 'trailers2',
            basePay,
            baseXP,
            0,
            fragile and 1 or 0,
            valuable and 1 or 0,
            json.encode({ x = originCoords.x, y = originCoords.y, z = originCoords.z }),
            json.encode({ x = dest.x, y = dest.y, z = dest.z })
        })
    end
end

function AdminService.SeedDefaultProps()
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM aust_trucker_homologated_props') or 0
    if count > 0 then return end

    local defaultList = {
        { model_hash = 'hei_prop_carrier_cargo_04b', name = 'Contêiner Grande Seco', cargo_category = 'dry', offset_z = 0.0 },
        { model_hash = 'm24_1_prop_m24_1_carrier_cargo_04a', name = 'Carga Marítima M24', cargo_category = 'dry', offset_z = 0.0 },
        { model_hash = 'prop_boxpile_02b', name = 'Pilhas de Caixas Frágeis', cargo_category = 'fragile', offset_z = 0.0 },
        { model_hash = 'prop_boxpile_06a', name = 'Caixas de Alta Densidade', cargo_category = 'dry', offset_z = 0.0 },
        { model_hash = 'prop_barrel_exp_01a', name = 'Barris Explosivos ADR', cargo_category = 'adr', offset_z = 0.0 },
        { model_hash = 'prop_rub_crate_01', name = 'Carga de Valiosos Blindada', cargo_category = 'valuable', offset_z = 0.0 },
        { model_hash = 'prop_wood_pallet_01', name = 'Palete de Madeira Padrão', cargo_category = 'dry', offset_z = 0.0 }
    }

    for _, p in ipairs(defaultList) do
        MySQL.query.await([[
            INSERT IGNORE INTO aust_trucker_homologated_props
            (model_hash, name, cargo_category, offset_x, offset_y, offset_z, heading)
            VALUES (?, ?, ?, 0.0, 0.0, ?, 0.0)
        ]], { p.model_hash, p.name, p.cargo_category, p.offset_z })
    end
end

function AdminService.ReloadHomologatedProps()
    local props = MySQL.query.await('SELECT * FROM aust_trucker_homologated_props') or {}
    local propMap = {}
    local propList = {}
    for _, p in ipairs(props) do
        local m = tostring(p.model_hash):lower()
        local item = {
            id = p.id,
            model_hash = m,
            prop_model = m,
            name = p.name,
            label = p.name,
            cargo_category = p.cargo_category,
            category = p.cargo_category,
            offset_x = tonumber(p.offset_x) or 0.0,
            offset_y = tonumber(p.offset_y) or 0.0,
            offset_z = tonumber(p.offset_z) or 0.0,
            heading = tonumber(p.heading) or 0.0,
            offset = { x = tonumber(p.offset_x) or 0.0, y = tonumber(p.offset_y) or 0.0, z = tonumber(p.offset_z) or 0.0, heading = tonumber(p.heading) or 0.0 }
        }
        propMap[m] = item
        table.insert(propList, item)
    end
    AdminService.HomologatedProps = propMap
    return propList, propMap
end

function AdminService.LoadAll()
    CreateThread(function()
        -- 1. Carrega Rotas Personalizadas (com Seed Automático se tabela estiver vazia)
        local routes = MySQL.query.await('SELECT * FROM aust_trucker_custom_routes') or {}
        if #routes == 0 then
            AdminService.SeedDefaultRoutes()
            routes = MySQL.query.await('SELECT * FROM aust_trucker_custom_routes') or {}
        end

        local routeMap = {}
        for _, r in ipairs(routes) do
            if r.pickup_coords and type(r.pickup_coords) == 'string' then
                pcall(function() r.pickup_coords = json.decode(r.pickup_coords) end)
            end
            if r.delivery_coords and type(r.delivery_coords) == 'string' then
                pcall(function() r.delivery_coords = json.decode(r.delivery_coords) end)
            end
            routeMap[r.id] = r
        end
        AdminService.CustomRoutes = routeMap

        -- 2. Carrega Spawns
        local spawns = MySQL.query.await('SELECT * FROM aust_trucker_spawns') or {}
        local spawnMap = {}
        for _, s in ipairs(spawns) do
            if s.coords and type(s.coords) == 'string' then
                pcall(function() s.coords = json.decode(s.coords) end)
            end
            s.folder_name = s.folder_name or 'Geral'
            spawnMap[s.id] = s
        end
        AdminService.Spawns = spawnMap

        -- 3. Carrega Offsets de Reboques Mapeados Visualmente
        local offsetMap = AdminService.ReloadTrailerOffsets()

        -- 4. Carrega Props Homologados (com auto-seed inicial se vazio)
        AdminService.SeedDefaultProps()
        AdminService.ReloadHomologatedProps()

        -- 5. Carrega NPCs Despachantes
        local npcs = MySQL.query.await('SELECT * FROM aust_trucker_npcs') or {}
        local npcMap = {}
        for _, n in ipairs(npcs) do
            if n.coords and type(n.coords) == 'string' then
                pcall(function() n.coords = json.decode(n.coords) end)
            end
            npcMap[n.id] = n
        end
        AdminService.NPCs = npcMap

        -- 6. Carrega Economia
        local eco = MySQL.query.await('SELECT * FROM aust_trucker_economy_settings') or {}
        for _, e in ipairs(eco) do
            local lim = ECONOMY_LIMITS[e.key_name]
            if lim then
                AdminService.Economy[e.key_name] = ClampNum(e.numeric_value, lim[1], lim[2], AdminService.Economy[e.key_name])
            end
        end

        -- 7. Carrega Offsets de Veículos <-> Props (PropEditor)
        AdminService.ReloadVehiclePropOffsets()

        local totalTrailers = 0
        for _ in pairs(offsetMap) do totalTrailers = totalTrailers + 1 end

        print(("^2[AUST_Trucker Admin] Dados administrativos unificados carregados: %d Rotas, %d Spawns, %d Reboques, %d NPCs, %d Props Homologados.^7"):format(
            #routes, #spawns, totalTrailers, #npcs, next(AdminService.HomologatedProps) and #routes or 0
        ))
    end)
end

function AdminService.ReloadTrailerOffsets()
    local offsets = MySQL.query.await('SELECT * FROM aust_trucker_trailer_offsets') or {}
    local offsetMap = {}
    local rawModelMap = {}

    for _, o in ipairs(offsets) do
        local model = o.trailer_model:lower()
        local prop = (o.prop_model and o.prop_model ~= '' and o.prop_model:lower()) or 'hei_prop_carrier_cargo_04b'
        local compKey = model .. '::' .. prop

        if not offsetMap[compKey] then
            offsetMap[compKey] = {
                trailer_model = model,
                prop_model = prop,
                label = o.label or nil,
                pallets = {},
                forklift = nil
            }
        end
        if not rawModelMap[model] then
            rawModelMap[model] = {
                trailer_model = model,
                prop_model = prop,
                label = o.label or nil,
                pallets = {},
                forklift = nil
            }
        end

        local vecData = {
            id = o.id,
            label = o.label or nil,
            prop_model = prop,
            x = tonumber(o.offset_x) or 0.0,
            y = tonumber(o.offset_y) or 0.0,
            z = tonumber(o.offset_z) or 0.0,
            heading = tonumber(o.heading) or 0.0
        }
        local isFork = (o.is_forklift == 1 or o.is_forklift == true or tonumber(o.is_forklift) == 1 or tostring(o.is_forklift) == '1')
        if isFork then
            offsetMap[compKey].forklift = vecData
            rawModelMap[model].forklift = vecData
        else
            offsetMap[compKey].pallets[tostring(o.slot_index)] = vecData
            offsetMap[compKey].pallets[tonumber(o.slot_index)] = vecData
            rawModelMap[model].pallets[tostring(o.slot_index)] = vecData
            rawModelMap[model].pallets[tonumber(o.slot_index)] = vecData
        end
    end

    -- Dual-indexação com normalização estrita de hash 32-bit (Signed e Unsigned)
    local dualMap = {}
    for compKey, data in pairs(offsetMap) do
        dualMap[compKey] = data
        local model = data.trailer_model
        local prop = data.prop_model
        local h = joaat(model)
        local u = h & 0xFFFFFFFF
        local s = (u >= 0x80000000) and (u - 0x100000000) or u
        dualMap[h .. '::' .. prop] = data
        dualMap[u .. '::' .. prop] = data
        dualMap[s .. '::' .. prop] = data
        dualMap[tostring(h) .. '::' .. prop] = data
        dualMap[tostring(u) .. '::' .. prop] = data
        dualMap[tostring(s) .. '::' .. prop] = data
    end

    -- Fallbacks genéricos pelo modelo simples (compatibilidade reversa)
    for model, data in pairs(rawModelMap) do
        dualMap[model] = data
        local h = joaat(model)
        local u = h & 0xFFFFFFFF
        local s = (u >= 0x80000000) and (u - 0x100000000) or u
        dualMap[h] = data
        dualMap[u] = data
        dualMap[s] = data
        dualMap[tostring(h)] = data
        dualMap[tostring(u)] = data
        dualMap[tostring(s)] = data
        if not offsetMap[model] then
            offsetMap[model] = data
        end
    end

    AdminService.TrailerOffsets = dualMap
    AdminService.CleanTrailerOffsets = offsetMap

    -- Aplica os offsets dinâmicos sobre a tabela global Config.TrailerSlots com prioridade absoluta
    if Config and Config.TrailerSlots then
        -- Reconstrói: restaura o estado estático original das chaves já mescladas antes (remove offsets apagados)
        AdminService._slotBase = AdminService._slotBase or {}
        for k, base in pairs(AdminService._slotBase) do
            if base == false then
                Config.TrailerSlots[k] = nil
            else
                local restored = { pallets = {}, forklift = base.forklift }
                for idx, v in pairs(base.pallets or {}) do restored.pallets[idx] = v end
                Config.TrailerSlots[k] = restored
            end
        end

        for model, data in pairs(rawModelMap) do
            local h = joaat(model)
            local u = h & 0xFFFFFFFF
            local s = (u >= 0x80000000) and (u - 0x100000000) or u

            local keys = { model, h, u, s, tostring(h), tostring(u), tostring(s) }
            for _, k in ipairs(keys) do
                -- Guarda o estado estático original (uma única vez por chave) para permitir rebuild
                if AdminService._slotBase[k] == nil then
                    local orig = Config.TrailerSlots[k]
                    if orig then
                        local copy = { pallets = {}, forklift = orig.forklift }
                        for idx, v in pairs(orig.pallets or {}) do copy.pallets[idx] = v end
                        AdminService._slotBase[k] = copy
                    else
                        AdminService._slotBase[k] = false
                    end
                end
                if not Config.TrailerSlots[k] then
                    Config.TrailerSlots[k] = { pallets = {}, forklift = nil }
                end
                for idx, vec in pairs(data.pallets or {}) do
                    local slotEntry = { id = vec.id, label = vec.label, prop_model = vec.prop_model, x = tonumber(vec.x) or 0.0, y = tonumber(vec.y) or 0.0, z = tonumber(vec.z) or 0.0, heading = tonumber(vec.heading) or 0.0 }
                    Config.TrailerSlots[k].pallets[tonumber(idx)] = slotEntry
                end
                if data.forklift then
                    local slotEntry = { id = data.forklift.id, label = data.forklift.label, prop_model = data.forklift.prop_model or 'forklift', x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                    Config.TrailerSlots[k].forklift = slotEntry
                end
            end
        end
    end

    return dualMap, offsetMap
end

---Resolução de offsets de reboque em cascata (Par exato Trailer+Prop -> Modelo genérico -> Padrão Config)
function AdminService.GetOffsetsForTrailerAndCargo(trailerModel, cargoPropModel)
    if not trailerModel then return nil end
    local offsets = AdminService.TrailerOffsets
    if not offsets or next(offsets) == nil then
        offsets = AdminService.ReloadTrailerOffsets()
    end

    local modelKey = tostring(trailerModel):lower()
    local hash = tonumber(trailerModel) or joaat(modelKey)
    local u = tostring(hash & 0xFFFFFFFF)
    local s = tostring((hash & 0xFFFFFFFF >= 0x80000000) and (hash & 0xFFFFFFFF - 0x100000000) or (hash & 0xFFFFFFFF))
    local hStr = tostring(hash)

    local propKey = cargoPropModel and tostring(cargoPropModel):lower() or nil

    -- 1. Resolução prioritária pela combinação exata (Trailer + Prop)
    if propKey and propKey ~= '' then
        local candidates = {
            modelKey .. '::' .. propKey,
            hStr .. '::' .. propKey,
            u .. '::' .. propKey,
            s .. '::' .. propKey
        }
        for _, k in ipairs(candidates) do
            if offsets[k] and offsets[k].pallets and next(offsets[k].pallets) ~= nil then
                return offsets[k]
            end
        end
    end

    -- 2. Resolução em Cascata: Fallback para o modelo genérico do trailer
    local fallbackKeys = { modelKey, hStr, u, s, hash }
    for _, k in ipairs(fallbackKeys) do
        if offsets[k] and offsets[k].pallets and next(offsets[k].pallets) ~= nil then
            return offsets[k]
        end
    end

    -- 3. Resolução em Cascata: Fallback para Config.TrailerSlots estático
    for _, k in ipairs(fallbackKeys) do
        if Config.TrailerSlots and Config.TrailerSlots[k] and Config.TrailerSlots[k].pallets and next(Config.TrailerSlots[k].pallets) ~= nil then
            return Config.TrailerSlots[k]
        end
    end

    return nil
end

function AdminService.ReloadVehiclePropOffsets()
    local rows = MySQL.query.await('SELECT * FROM aust_trucker_vehicle_prop_offsets') or {}
    local rawMap = {}
    local dualMap = {}

    for _, row in ipairs(rows) do
        local vModel = tostring(row.vehicle_model):lower()
        local pModel = tostring(row.prop_model):lower()
        local entry = {
            id = row.id,
            vehicle_model = vModel,
            prop_model = pModel,
            offset_x = tonumber(row.offset_x) or 0.0,
            offset_y = tonumber(row.offset_y) or 0.0,
            offset_z = tonumber(row.offset_z) or 0.0,
            rot_pitch = tonumber(row.rot_pitch) or 0.0,
            rot_roll = tonumber(row.rot_roll) or 0.0,
            rot_yaw = tonumber(row.rot_yaw) or 0.0,
            offset = vector3(tonumber(row.offset_x) or 0.0, tonumber(row.offset_y) or 0.0, tonumber(row.offset_z) or 0.0),
            rotation = vector3(tonumber(row.rot_pitch) or 0.0, tonumber(row.rot_roll) or 0.0, tonumber(row.rot_yaw) or 0.0)
        }

        if not rawMap[vModel] then rawMap[vModel] = {} end
        rawMap[vModel][pModel] = entry

        -- Indexação dual no mapa de execução rápida (string, hash signed, unsigned)
        local vHash = joaat(vModel)
        local pHash = joaat(pModel)
        local vUnsigned = vHash & 0xFFFFFFFF
        local vSigned = (vUnsigned >= 0x80000000) and (vUnsigned - 0x100000000) or vUnsigned

        local vKeys = { vModel, vHash, vUnsigned, vSigned, tostring(vHash), tostring(vUnsigned), tostring(vSigned) }
        local pKeys = { pModel, pHash, pHash & 0xFFFFFFFF, tostring(pHash) }

        for _, vk in ipairs(vKeys) do
            if not dualMap[vk] then dualMap[vk] = {} end
            for _, pk in ipairs(pKeys) do
                dualMap[vk][pk] = entry
            end
        end
    end

    AdminService.VehiclePropOffsets = dualMap
    return dualMap, rawMap
end

MySQL.ready(function()
    AdminService.LoadAll()
end)

-- ============================================================
-- COMANDO E CALLBACK DE ABERTURA DO PAINEL
-- ============================================================

RegisterCommand('truckeradmin', function(source, args)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then
        if src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Acesso Negado',
                description = 'Você não possui permissão administrativa para acessar o painel de rotas.',
                type = 'error'
            })
        else
            print("[AUST_Trucker Admin] Comando disponível apenas in-game para administradores.")
        end
        return
    end

    -- Consulta viva do banco para garantir que o menu sempre abra com dados frescos
    local currentOffsets, cleanOffsets = AdminService.ReloadTrailerOffsets()
    local currentProps = AdminService.ReloadHomologatedProps()

    local payload = {
        customRoutes = AdminService.CustomRoutes,
        routes = AdminService.CustomRoutes,
        spawns = AdminService.Spawns,
        trailerOffsets = cleanOffsets or currentOffsets,
        offsets = cleanOffsets or currentOffsets,
        homologatedProps = currentProps,
        props = currentProps,
        npcs = AdminService.NPCs,
        economy = AdminService.Economy,
        defaultProps = Config.PalletProps or { 'hei_prop_carrier_cargo_04b' },
        vehiclePropOffsets = (select(2, AdminService.ReloadVehiclePropOffsets())),
    }

    TriggerClientEvent('aurp_trucker:client:openAdminPanel', src, payload)
end, false)

-- ============================================================
-- COMANDO ADMINISTRATIVO: /truckerxp [id] [quantidade]
-- Concede XP de caminhoneiro diretamente para testar o sistema
-- de progressão, level-ups e árvore de skills.
-- ============================================================

RegisterCommand('truckerxp', function(source, args)
    local src = source

    -- Validação de Permissão Administrativa (Console + Multi-Framework)
    if not AdminService.IsPlayerAdmin(src) then
        if src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Acesso Negado',
                description = 'Você não possui permissão administrativa para conceder XP.',
                type = 'error'
            })
        else
            print("[AUST_Trucker Admin] Permissão negada.")
        end
        return
    end

    local targetId = nil
    local amount = nil

    if #args >= 2 then
        targetId = tonumber(args[1])
        amount = tonumber(args[2])
    elseif #args == 1 and src ~= 0 then
        -- Se executado in-game com 1 argumento, auto-atribui ao admin
        targetId = src
        amount = tonumber(args[1])
    end

    local function NotifyCaller(title, desc, nType)
        if src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title = title,
                description = desc,
                type = nType or 'inform',
                duration = 7000
            })
        else
            print(('[AUST_Trucker Admin] %s: %s'):format(title, desc))
        end
    end

    if not targetId or not amount or amount <= 0 or amount ~= amount or amount == math.huge then
        NotifyCaller('Sintaxe Inválida', 'Uso: /truckerxp [id] [quantidade]\nExemplo: /truckerxp 1 5000', 'error')
        return
    end

    amount = math.floor(amount)
    if amount > 10000000 then
        NotifyCaller('Limite Excedido', 'A quantidade máxima de XP por comando é 10.000.000.', 'error')
        return
    end

    local targetPlayer = Framework.GetPlayer(targetId)
    if not targetPlayer then
        NotifyCaller('Jogador Não Encontrado', ('O jogador com ID %s não está online ou não foi encontrado.'):format(tostring(targetId)), 'error')
        return
    end

    local citizenId = Framework.GetCitizenId(targetPlayer)
    if not citizenId or citizenId == '' then
        NotifyCaller('Identificador Ausente', 'Não foi possível obter o CitizenID do jogador alvo.', 'error')
        return
    end

    local targetName = Framework.GetCharName(targetPlayer) or ('ID ' .. tostring(targetId))

    -- Concessão atômica via ProgressionService
    local res = ProgressionService.AddDirectXP(targetId, citizenId, amount)

    -- Feedback para o jogador alvo
    if res.levelsGained and res.levelsGained > 0 then
        if targetId ~= src then
            TriggerClientEvent('ox_lib:notify', targetId, {
                title = 'XP Administrativo Recebido',
                description = ('Um administrador concedeu +%d XP para você! Nível %d alcançado (+%d Skill Points).'):format(
                    amount, res.newLevel, res.levelsGained
                ),
                type = 'success',
                duration = 8000
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = 'XP de Caminhoneiro',
            description = ('Você recebeu +%d XP de um administrador! (XP Total: %d)'):format(
                amount, res.totalXP or 0
            ),
            type = 'inform',
            duration = 6000
        })
        TriggerClientEvent('aurp_trucker:client:refreshSkillsUI', targetId)
    end

    -- Feedback detalhado para o Administrador
    local adminFeedback = ('Concedido +%d XP para %s (ID: %d).\nNível: %d (+%d) | XP Total: %d | Skill Points: %d'):format(
        amount,
        targetName,
        targetId,
        res.newLevel or 1,
        res.levelsGained or 0,
        res.totalXP or 0,
        res.totalSkillPoints or 0
    )

    NotifyCaller('XP Concedido com Sucesso', adminFeedback, 'success')
    AdminLog(src, 'GRANT_XP', ('Target=%s (ID=%s) Amount=%d NewLevel=%s SkillPoints=%s'):format(
        tostring(citizenId), tostring(targetId), amount, tostring(res.newLevel), tostring(res.totalSkillPoints)
    ))
end, false)

-- ============================================================
-- COMANDO ADMINISTRATIVO: /truckerlicense [id] [heavy|adr] [1|0]
-- Gerencia certificações técnicas de motoristas diretamente.
-- ============================================================
RegisterCommand('truckerlicense', function(source, args)
    local src = source

    if not AdminService.IsPlayerAdmin(src) then
        if src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Acesso Negado',
                description = 'Você não possui permissão administrativa para alterar licenças.',
                type = 'error'
            })
        else
            print("[AUST_Trucker Admin] Permissão negada.")
        end
        return
    end

    local function NotifyCaller(title, desc, nType)
        if src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title = title,
                description = desc,
                type = nType or 'inform',
                duration = 7000
            })
        else
            print(('[AUST_Trucker Admin] %s: %s'):format(title, desc))
        end
    end

    local targetId = tonumber(args[1])
    local licType = args[2] and string.lower(args[2])
    local state = tonumber(args[3]) or 1

    if not targetId or not licType or (licType ~= 'heavy' and licType ~= 'adr') then
        NotifyCaller('Sintaxe Inválida', 'Uso: /truckerlicense [id] [heavy|adr] [1|0]\nExemplo: /truckerlicense 1 heavy 1', 'error')
        return
    end

    local targetPlayer = Framework.GetPlayer(targetId)
    if not targetPlayer then
        NotifyCaller('Jogador Não Encontrado', ('O jogador com ID %s não está online.'):format(tostring(targetId)), 'error')
        return
    end

    local citizenId = Framework.GetCitizenId(targetPlayer)
    if not citizenId or citizenId == '' then
        NotifyCaller('Identificador Ausente', 'Não foi possível obter o CitizenID do jogador alvo.', 'error')
        return
    end
    citizenId = tostring(citizenId):gsub('^%s*(.-)%s*$', '%1')

    local colName = (licType == 'heavy') and 'heavy_certified' or 'adr_certified'
    local val = (state == 1) and 1 or 0

    MySQL.query.await(([[
        INSERT INTO trucker_licenses (citizenid, %s)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE %s = ?
    ]]):format(colName, colName), { citizenId, val, val })

    local licName = (licType == 'heavy') and 'Certificação Heavy Lift Operator' or 'Certificação ADR Specialist'
    local actionText = (val == 1) and 'CONCEDIDA' or 'REVOGADA'

    if targetId ~= src then
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = 'Certificação Atualizada',
            description = ('Um administrador atualizou sua licença: %s (%s).'):format(licName, actionText),
            type = (val == 1) and 'success' or 'warning',
            duration = 7000
        })
    end

    NotifyCaller('Licença Atualizada', ('%s para CitizenID %s (ID: %d): %s'):format(actionText, citizenId, targetId, licName), 'success')
    AdminLog(src, 'SET_LICENSE', ('Target=%s (ID=%s) License=%s State=%d'):format(citizenId, tostring(targetId), licType, val))
end, false)

lib.callback.register('aurp_trucker:server:getAdminData', function(source)
    if not AdminService.IsPlayerAdmin(source) then return nil end
    local currentOffsets, cleanOffsets = AdminService.ReloadTrailerOffsets()
    local currentProps = AdminService.ReloadHomologatedProps()
    local _, cleanVehProps = AdminService.ReloadVehiclePropOffsets()
    return {
        customRoutes = AdminService.CustomRoutes,
        routes = AdminService.CustomRoutes,
        spawns = AdminService.Spawns,
        trailerOffsets = cleanOffsets or currentOffsets,
        offsets = cleanOffsets or currentOffsets,
        homologatedProps = currentProps,
        props = currentProps,
        npcs = AdminService.NPCs,
        economy = AdminService.Economy,
        defaultProps = Config.PalletProps or { 'hei_prop_carrier_cargo_04b' },
        vehiclePropOffsets = cleanVehProps,
    }
end)

-- Callback em tempo de execução para sincronização de offsets de reboque (100% da RAM, zero SQL overhead)
lib.callback.register('aurp_trucker:server:getTrailerOffsetsForModel', function(source, trailerModel, cargoPropModel)
    local specificData = AdminService.GetOffsetsForTrailerAndCargo(trailerModel, cargoPropModel)
    return {
        specific = specificData,
        all = AdminService.TrailerOffsets
    }
end)

-- ============================================================
-- EVENTOS DE SALVAMENTO & HOT-RELOAD EM TEMPO REAL
-- ============================================================

-- 0. TELEPORTE (autorizado e executado no servidor)
RegisterNetEvent('aurp_trucker:server:adminTeleport', function(coords)
    local src = source
    -- source de evento de rede é sempre > 0; recusa qualquer outra origem
    if type(src) ~= 'number' or src <= 0 then return end
    if not AdminService.IsPlayerAdmin(src) then
        print(('[AUST_Trucker] adminTeleport negado para src %s (sem permissão admin)'):format(tostring(src)))
        return
    end
    if type(coords) ~= 'table' then return end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    local heading = tonumber(coords.heading or coords.w)
    -- Coordenadas finitas e dentro dos limites do mapa do GTA V
    if not (IsFiniteNumber(x) and IsFiniteNumber(y) and IsFiniteNumber(z)) then return end
    if math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or z < -500.0 or z > 2500.0 then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)
    if IsFiniteNumber(heading) then SetEntityHeading(ped, heading + 0.0) end

    print(('[AUST_Trucker] Admin %s teleportou para %.1f, %.1f, %.1f'):format(tostring(src), x, y, z))
end)

-- 1. ROTAS E CONTRATOS
RegisterNetEvent('aurp_trucker:server:adminSaveRoute', function(routeData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(routeData) ~= 'table' then return end

    local routeId = CleanId(routeData.id, 50) or ('route_' .. tostring(os.time()) .. '_' .. math.random(100, 999))
    local rType = CleanStr(routeData.type, 20, 'quick')
    if not ROUTE_TYPES[rType] then rType = 'quick' end

    -- Somente campos sanitizados (nunca a tabela crua do cliente) vão para o banco e para a memória
    local clean = {
        id              = routeId,
        name            = CleanStr(routeData.name, 100, 'Nova Rota Customizada'),
        type            = rType,
        cargo_model     = CleanStr(routeData.cargo_model, 100, 'hei_prop_carrier_cargo_04b'),
        cargo_name      = CleanStr(routeData.cargo_name, 100, 'Paletes de Carga'),
        truck_model     = CleanStr(routeData.truck_model, 50, 'hauler'),
        trailer_model   = CleanStr(routeData.trailer_model, 50, 'trailers2'),
        base_payment    = math.floor(ClampNum(routeData.base_payment, 0, MAX_BASE_PAYMENT, 5000)),
        base_xp         = math.floor(ClampNum(routeData.base_xp, 0, MAX_BASE_XP, 200)),
        req_skill       = math.floor(ClampNum(routeData.req_skill, 0, 100, 0)),
        fragile         = routeData.fragile and 1 or 0,
        valuable        = routeData.valuable and 1 or 0,
        pickup_coords   = CleanCoords(routeData.pickup_coords),
        delivery_coords = CleanCoords(routeData.delivery_coords),
        is_active       = (routeData.is_active ~= false and routeData.is_active ~= 0) and 1 or 0,
    }

    MySQL.query.await([[
        INSERT INTO aust_trucker_custom_routes
        (id, name, type, cargo_model, cargo_name, truck_model, trailer_model, base_payment, base_xp, req_skill, fragile, valuable, pickup_coords, delivery_coords, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), type = VALUES(type), cargo_model = VALUES(cargo_model), cargo_name = VALUES(cargo_name),
        truck_model = VALUES(truck_model), trailer_model = VALUES(trailer_model), base_payment = VALUES(base_payment),
        base_xp = VALUES(base_xp), req_skill = VALUES(req_skill), fragile = VALUES(fragile), valuable = VALUES(valuable),
        pickup_coords = VALUES(pickup_coords), delivery_coords = VALUES(delivery_coords), is_active = VALUES(is_active)
    ]], {
        clean.id, clean.name, clean.type, clean.cargo_model, clean.cargo_name, clean.truck_model, clean.trailer_model,
        clean.base_payment, clean.base_xp, clean.req_skill, clean.fragile, clean.valuable,
        json.encode(clean.pickup_coords), json.encode(clean.delivery_coords), clean.is_active
    })

    AdminService.CustomRoutes[routeId] = clean
    AdminLog(src, 'adminSaveRoute', routeId)
    TriggerClientEvent('aurp_trucker:client:adminSyncRoutes', -1, AdminService.CustomRoutes)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Rota salva e sincronizada em tempo real!', type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteRoute', function(routeId)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then return end
    routeId = CleanId(routeId, 50)
    if not routeId then return end

    MySQL.query.await('DELETE FROM aust_trucker_custom_routes WHERE id = ?', { routeId })
    AdminService.CustomRoutes[routeId] = nil
    AdminLog(src, 'adminDeleteRoute', routeId)
    TriggerClientEvent('aurp_trucker:client:adminSyncRoutes', -1, AdminService.CustomRoutes)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Rota excluída do servidor.', type = 'info' })
end)

-- 2. SPAWNS E BAÍAS
RegisterNetEvent('aurp_trucker:server:adminSaveSpawn', function(spawnData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(spawnData) ~= 'table' then return end

    local spawnId = CleanId(spawnData.id, 50) or ('spawn_' .. tostring(os.time()) .. '_' .. math.random(100, 999))
    local spawnType = CleanStr(spawnData.spawn_type, 20, 'truck')
    if not SPAWN_TYPES[spawnType] then spawnType = 'truck' end

    local existing = AdminService.Spawns[spawnId]
    local clean = {
        id          = spawnId,
        name        = CleanStr(spawnData.name, 100, 'Ponto de Spawn'),
        spawn_type  = spawnType,
        coords      = CleanCoords(spawnData.coords),
        heading     = ClampNum(spawnData.heading, -360.0, 360.0, 0.0),
        folder_name = (existing and existing.folder_name) or 'Geral',
    }

    MySQL.query.await([[
        INSERT INTO aust_trucker_spawns (id, name, spawn_type, coords, heading)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), spawn_type = VALUES(spawn_type), coords = VALUES(coords), heading = VALUES(heading)
    ]], {
        clean.id, clean.name, clean.spawn_type, json.encode(clean.coords), clean.heading
    })

    AdminService.Spawns[spawnId] = clean
    AdminLog(src, 'adminSaveSpawn', spawnId)
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Ponto de spawn gravado com sucesso!', type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteSpawn', function(spawnId)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then return end
    spawnId = CleanId(spawnId, 50)
    if not spawnId then return end

    MySQL.query.await('DELETE FROM aust_trucker_spawns WHERE id = ?', { spawnId })
    AdminService.Spawns[spawnId] = nil
    AdminLog(src, 'adminDeleteSpawn', spawnId)
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Spawn excluído.', type = 'info' })
end)

-- 3. MAPEAMENTO DE OFFSETS DE TRAILER (GIZMO / NUDGE TOOL) COM CHAVE COMPOSTA (TRAILER + PROP)
RegisterNetEvent('aurp_trucker:server:adminSaveTrailerOffset', function(data)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(data) ~= 'table' then return end

    local trailerModel = CleanStr(data.trailerModel, 50, nil)
    if not trailerModel then return end
    trailerModel = trailerModel:lower()
    local slotIndex = math.floor(ClampNum(data.slotIndex, 1, 64, 1))
    local isForklift = data.isForklift and 1 or 0
    local label = CleanStr(data.label, 100, nil)
    local propModel = CleanStr(data.propModel, 100, nil)
    propModel = (propModel and propModel:lower()) or (isForklift == 1 and 'forklift' or 'hei_prop_carrier_cargo_04b')
    local ox, oy, oz = ClampNum(data.x, -50.0, 50.0, 0.0), ClampNum(data.y, -50.0, 50.0, 0.0), ClampNum(data.z, -50.0, 50.0, 0.0)
    local heading = ClampNum(data.heading, -360.0, 360.0, 0.0)

    MySQL.query.await([[
        INSERT INTO aust_trucker_trailer_offsets
        (trailer_model, label, prop_model, slot_index, offset_x, offset_y, offset_z, heading, is_forklift)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        label = VALUES(label), offset_x = VALUES(offset_x), offset_y = VALUES(offset_y), offset_z = VALUES(offset_z),
        heading = VALUES(heading)
    ]], {
        trailerModel, label, propModel, slotIndex, ox, oy, oz, heading, isForklift
    })

    AdminLog(src, 'adminSaveTrailerOffset', ('%s prop=%s slot=%d fork=%d'):format(trailerModel, propModel, slotIndex, isForklift))

    -- Recarrega e normaliza dados frescos do banco
    local updatedOffsets, cleanOffsets = AdminService.ReloadTrailerOffsets()

    -- Notifica todos os clientes para sincronizar os novos offsets e atualizar a interface NUI
    local offsetPayload = {
        label = label,
        prop_model = propModel,
        x = ox,
        y = oy,
        z = oz,
        heading = heading
    }
    TriggerClientEvent('aurp_trucker:client:adminSyncOffsets', -1, trailerModel, slotIndex, isForklift == 1, offsetPayload, heading, cleanOffsets or updatedOffsets)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Offset Calibrado',
        description = ('Offset do %s [%s] (%s) gravado no banco e ativo em tempo real!'):format(trailerModel, propModel, isForklift == 1 and 'Empilhadeira' or ('Slot ' .. tostring(slotIndex))),
        type = 'success'
    })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteTrailerOffset', function(dataOrModel, maybeSlot, maybeFork, maybeProp)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not dataOrModel then return end

    local id, trailerModel, slotIndex, isForklift, propModel
    if type(dataOrModel) == 'table' then
        id = tonumber(dataOrModel.id)
        trailerModel = CleanStr(dataOrModel.trailerModel or dataOrModel.trailer, 50, nil)
        slotIndex = tonumber(dataOrModel.slotIndex or dataOrModel.slot)
        isForklift = dataOrModel.isForklift or dataOrModel.is_forklift or dataOrModel.fork
        propModel = CleanStr(dataOrModel.propModel or dataOrModel.prop_model or dataOrModel.prop, 100, nil)
    else
        trailerModel = CleanStr(dataOrModel, 50, nil)
        slotIndex = tonumber(maybeSlot)
        isForklift = maybeFork
        propModel = CleanStr(maybeProp, 100, nil)
    end
    if propModel then propModel = propModel:lower() end
    if id and not IsFiniteNumber(id) then id = nil end
    if not id and not trailerModel then return end
    AdminLog(src, 'adminDeleteTrailerOffset', ('id=%s trailer=%s prop=%s slot=%s fork=%s'):format(tostring(id), tostring(trailerModel), tostring(propModel), tostring(slotIndex), tostring(isForklift)))

    local rowsAffected = 0
    if id and id > 0 then
        local res = MySQL.query.await('DELETE FROM aust_trucker_trailer_offsets WHERE id = ?', { id })
        rowsAffected = (res and res.affectedRows) or 1
    end

    if not rowsAffected or rowsAffected == 0 then
        if trailerModel then
            local modelStr = tostring(trailerModel):lower()
            local isFork = (isForklift == true or isForklift == 1 or isForklift == '1') and 1 or 0
            if slotIndex and propModel then
                MySQL.query.await([[
                    DELETE FROM aust_trucker_trailer_offsets 
                    WHERE LOWER(trailer_model) = ? AND LOWER(prop_model) = ? AND slot_index = ? AND is_forklift = ?
                ]], { modelStr, propModel, slotIndex, isFork })
            elseif slotIndex then
                MySQL.query.await([[
                    DELETE FROM aust_trucker_trailer_offsets 
                    WHERE LOWER(trailer_model) = ? AND slot_index = ? AND is_forklift = ?
                ]], { modelStr, slotIndex, isFork })
            elseif propModel then
                MySQL.query.await([[
                    DELETE FROM aust_trucker_trailer_offsets 
                    WHERE LOWER(trailer_model) = ? AND LOWER(prop_model) = ?
                ]], { modelStr, propModel })
            else
                MySQL.query.await([[
                    DELETE FROM aust_trucker_trailer_offsets 
                    WHERE LOWER(trailer_model) = ?
                ]], { modelStr })
            end
        end
    end

    local updatedOffsets, cleanOffsets = AdminService.ReloadTrailerOffsets()
    TriggerClientEvent('aurp_trucker:client:adminSyncOffsets', -1, trailerModel or '', slotIndex or 1, (isForklift == 1 or isForklift == true), vector3(0, 0, 0), 0.0, cleanOffsets or updatedOffsets)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = ('Offset do trailer %s excluído com sucesso.'):format(tostring(trailerModel or id or '')), type = 'info' })
end)

-- 3.1. PROPE DITOR 6DoF: OFFSETS LIVRES VEÍCULO <-> PROP
RegisterNetEvent('aurp_trucker:server:adminSaveVehiclePropOffset', function(data)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(data) ~= 'table' then return end

    local vehicleModel = CleanStr(data.vehicleModel, 50, nil)
    local propModel = CleanStr(data.propModel, 100, nil)
    if not vehicleModel or not propModel then return end

    vehicleModel = vehicleModel:lower()
    propModel = propModel:lower()

    local ox = ClampNum(data.x, -50.0, 50.0, 0.0)
    local oy = ClampNum(data.y, -50.0, 50.0, 0.0)
    local oz = ClampNum(data.z, -50.0, 50.0, 0.0)

    local rotPitch = ClampNum(data.pitch or data.rot_pitch or (data.rotation and data.rotation.x), -360.0, 360.0, 0.0)
    local rotRoll  = ClampNum(data.roll  or data.rot_roll  or (data.rotation and data.rotation.y), -360.0, 360.0, 0.0)
    local rotYaw   = ClampNum(data.yaw   or data.rot_yaw   or (data.rotation and data.rotation.z), -360.0, 360.0, 0.0)

    MySQL.query.await([[
        INSERT INTO aust_trucker_vehicle_prop_offsets
        (vehicle_model, prop_model, offset_x, offset_y, offset_z, rot_pitch, rot_roll, rot_yaw)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        offset_x = VALUES(offset_x), offset_y = VALUES(offset_y), offset_z = VALUES(offset_z),
        rot_pitch = VALUES(rot_pitch), rot_roll = VALUES(rot_roll), rot_yaw = VALUES(rot_yaw)
    ]], {
        vehicleModel, propModel, ox, oy, oz, rotPitch, rotRoll, rotYaw
    })

    AdminLog(src, 'adminSaveVehiclePropOffset', ('%s + %s: pos(%.2f, %.2f, %.2f) rot(%.1f, %.1f, %.1f)'):format(
        vehicleModel, propModel, ox, oy, oz, rotPitch, rotRoll, rotYaw
    ))

    -- Recarrega o cache em memória RAM e notifica todos os clientes em tempo real (zero restarts)
    local dualMap, rawMap = AdminService.ReloadVehiclePropOffsets()
    TriggerClientEvent('aurp_trucker:client:adminSyncVehiclePropOffsets', -1, rawMap, dualMap)

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'PropEditor Salvo',
        description = ('Offset de %s + %s atualizado e sincronizado no servidor sem restart!'):format(vehicleModel, propModel),
        type = 'success',
        duration = 4500
    })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteVehiclePropOffset', function(data)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not data then return end

    local id = type(data) == 'table' and tonumber(data.id) or tonumber(data)
    local vehicleModel = type(data) == 'table' and CleanStr(data.vehicleModel, 50, nil) or nil
    local propModel = type(data) == 'table' and CleanStr(data.propModel, 100, nil) or nil

    if id and id > 0 then
        MySQL.query.await('DELETE FROM aust_trucker_vehicle_prop_offsets WHERE id = ?', { id })
    elseif vehicleModel and propModel then
        MySQL.query.await([[
            DELETE FROM aust_trucker_vehicle_prop_offsets 
            WHERE LOWER(vehicle_model) = ? AND LOWER(prop_model) = ?
        ]], { vehicleModel:lower(), propModel:lower() })
    end

    local dualMap, rawMap = AdminService.ReloadVehiclePropOffsets()
    TriggerClientEvent('aurp_trucker:client:adminSyncVehiclePropOffsets', -1, rawMap, dualMap)

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'PropEditor',
        description = 'Offset veículo/prop excluído com sucesso.',
        type = 'info'
    })
end)

-- 4. HOMOLOGAÇÃO DE CARGAS & PROPS
RegisterNetEvent('aurp_trucker:server:adminSaveHomologatedProp', function(propData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(propData) ~= 'table' then return end

    local modelHash = CleanStr(propData.modelHash or propData.prop_model or propData.model, 100, nil)
    if not modelHash then return end
    modelHash = modelHash:lower()
    local name = CleanStr(propData.name or propData.label, 100, modelHash)
    local category = (CleanStr(propData.category or propData.cargo_category, 20, 'dry')):lower()
    if not PROP_CATS[category] then category = 'dry' end
    local ox = ClampNum(propData.x or propData.offset_x, -50.0, 50.0, 0.0)
    local oy = ClampNum(propData.y or propData.offset_y, -50.0, 50.0, 0.0)
    local oz = ClampNum(propData.z or propData.offset_z, -50.0, 50.0, 0.0)
    local heading = ClampNum(propData.heading, -360.0, 360.0, 0.0)

    MySQL.query.await([[
        INSERT INTO aust_trucker_homologated_props
        (model_hash, name, cargo_category, offset_x, offset_y, offset_z, heading)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), cargo_category = VALUES(cargo_category),
        offset_x = VALUES(offset_x), offset_y = VALUES(offset_y), offset_z = VALUES(offset_z), heading = VALUES(heading)
    ]], { modelHash, name, category, ox, oy, oz, heading })

    AdminLog(src, 'adminSaveHomologatedProp', modelHash)
    local propsList = AdminService.ReloadHomologatedProps()
    TriggerClientEvent('aurp_trucker:client:adminSyncProps', -1, propsList)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Prop Homologado', description = ('Carga "%s" (%s) homologada e salva no banco!'):format(name, modelHash), type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteHomologatedProp', function(modelHash)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then return end
    local m = CleanStr(modelHash, 100, nil)
    if not m then return end
    m = m:lower()
    AdminLog(src, 'adminDeleteHomologatedProp', m)
    MySQL.query.await('DELETE FROM aust_trucker_homologated_props WHERE LOWER(model_hash) = ?', { m })
    local propsList = AdminService.ReloadHomologatedProps()
    TriggerClientEvent('aurp_trucker:client:adminSyncProps', -1, propsList)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = ('Prop "%s" desomologado e removido do catálogo.'):format(m), type = 'info' })
end)

-- 5. PASTAS E DRAG-AND-DROP DE SPAWNS
RegisterNetEvent('aurp_trucker:server:adminMoveSpawnFolder', function(spawnId, folderName)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then return end
    spawnId = CleanId(spawnId, 50)
    if not spawnId then return end

    folderName = CleanStr(folderName, 100, 'Geral')
    AdminLog(src, 'adminMoveSpawnFolder', spawnId .. ' -> ' .. folderName)

    MySQL.query.await('UPDATE aust_trucker_spawns SET folder_name = ? WHERE id = ?', { folderName, spawnId })
    if AdminService.Spawns[spawnId] then
        AdminService.Spawns[spawnId].folder_name = folderName
    end
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteSpawnFolder', function(folderName)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then return end
    folderName = CleanStr(folderName, 100, nil)
    if not folderName then return end
    AdminLog(src, 'adminDeleteSpawnFolder', folderName)

    MySQL.query.await("UPDATE aust_trucker_spawns SET folder_name = 'Geral' WHERE folder_name = ?", { folderName })
    for _, s in pairs(AdminService.Spawns) do
        if s.folder_name == folderName then
            s.folder_name = 'Geral'
        end
    end
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = ('Pasta "%s" removida. Itens movidos para "Geral".'):format(folderName), type = 'info' })
end)

-- 6. NPCS E DESPACHANTES
RegisterNetEvent('aurp_trucker:server:adminSaveNPC', function(npcData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(npcData) ~= 'table' then return end

    local npcId = CleanId(npcData.id, 50) or ('npc_' .. tostring(os.time()) .. '_' .. math.random(100, 999))
    local clean = {
        id          = npcId,
        name        = CleanStr(npcData.name, 100, 'Despachante Logístico'),
        model       = CleanStr(npcData.model, 50, 's_m_m_dockwork_01'),
        coords      = CleanCoords(npcData.coords),
        heading     = ClampNum(npcData.heading, -360.0, 360.0, 0.0),
        blip_sprite = math.floor(ClampNum(npcData.blip_sprite, 0, 900, 477)),
        blip_color  = math.floor(ClampNum(npcData.blip_color, 0, 90, 2)),
        is_active   = (npcData.is_active ~= false and npcData.is_active ~= 0) and 1 or 0,
    }

    MySQL.query.await([[
        INSERT INTO aust_trucker_npcs (id, name, model, coords, heading, blip_sprite, blip_color, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), model = VALUES(model), coords = VALUES(coords), heading = VALUES(heading),
        blip_sprite = VALUES(blip_sprite), blip_color = VALUES(blip_color), is_active = VALUES(is_active)
    ]], {
        clean.id, clean.name, clean.model, json.encode(clean.coords), clean.heading,
        clean.blip_sprite, clean.blip_color, clean.is_active
    })

    AdminService.NPCs[npcId] = clean
    AdminLog(src, 'adminSaveNPC', npcId)
    TriggerClientEvent('aurp_trucker:client:adminSyncNPCs', -1, AdminService.NPCs)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'NPC despachante atualizado em tempo real!', type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteNPC', function(npcId)
    local src = source
    if not AdminService.IsPlayerAdmin(src) then return end
    npcId = CleanId(npcId, 50)
    if not npcId then return end

    MySQL.query.await('DELETE FROM aust_trucker_npcs WHERE id = ?', { npcId })
    AdminService.NPCs[npcId] = nil
    AdminLog(src, 'adminDeleteNPC', npcId)
    TriggerClientEvent('aurp_trucker:client:adminSyncNPCs', -1, AdminService.NPCs)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'NPC removido do mapa.', type = 'info' })
end)

-- 7. ECONOMIA E XP (SINCRONIZAÇÃO GLOBAL)
RegisterNetEvent('aurp_trucker:server:adminSaveEconomy', function(settings)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or type(settings) ~= 'table' then return end

    for key, val in pairs(settings) do
        -- Whitelist de chaves conhecidas + valores limitados ao intervalo permitido
        local lim = (type(key) == 'string' and #key <= 50) and ECONOMY_LIMITS[key] or nil
        local num = lim and ClampNum(val, lim[1], lim[2], nil) or nil
        if num then
            AdminService.Economy[key] = num
            AdminLog(src, 'adminSaveEconomy', ('%s=%s'):format(key, tostring(num)))
            MySQL.query.await([[
                INSERT INTO aust_trucker_economy_settings (key_name, numeric_value)
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE numeric_value = VALUES(numeric_value)
            ]], { key, num })
        end
    end

    TriggerClientEvent('aurp_trucker:client:adminSyncEconomy', -1, AdminService.Economy)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Economia e multiplicadores atualizados globalmente!', type = 'success' })
end)

-- ============================================================
-- CENTRALIZADOR DE CONTRATOS ATIVOS DO EMPREGO (SINCRONIZAÇÃO VIVA)
-- ============================================================

function AdminService.GetActiveContracts(citizenId)
    local contracts = {}
    local routes = AdminService.CustomRoutes or {}
    local eco = AdminService.Economy or {}
    local kmPay = eco.base_payment_per_km or eco.km_multiplier or 18.5
    local kmXP = eco.base_xp_per_km or eco.xp_multiplier or 5.0
    local adrMult = eco.adr_multiplier or (1 + ((eco.adr_bonus_pct or 35.0) / 100))
    local fragileMult = eco.fragile_bonus or (1 + ((eco.fragile_bonus_pct or 20.0) / 100))
    local valuableMult = eco.valuable_bonus or (1 + ((eco.valuable_bonus_pct or 25.0) / 100))

    local validCerts = (citizenId and AdrService and AdrService.GetValid and AdrService.GetValid(citizenId)) or {}

    local idx = 1
    for rId, r in pairs(routes) do
        if r.is_active ~= 0 and r.is_active ~= false then
            local dist = tonumber(r.distance) or tonumber(r.distance_km) or 5.0
            if dist <= 0 then dist = 3.5 end

            local isAdr = (r.type == 'adr' or r.requires_adr == 1 or r.requires_adr == true)
            local isFragile = (r.fragile == 1 or r.fragile == true)
            local isValuable = (r.valuable == 1 or r.valuable == true)

            local basePayment = tonumber(r.base_payment) or tonumber(r.payment) or math.floor(dist * kmPay * 100 + 1200)
            local baseXP = tonumber(r.base_xp) or tonumber(r.xp) or math.floor(dist * kmXP * 15 + 150)

            if isAdr then basePayment = math.floor(basePayment * adrMult) end
            if isFragile then basePayment = math.floor(basePayment * fragileMult) end
            if isValuable then basePayment = math.floor(basePayment * valuableMult) end

            -- Certificados no DB são tipos nomeados (flammable_liquid, toxic, ...). Rotas customizadas
            -- só carregam o flag 'adr'; se a rota informar um adr_type específico, exige esse; senão, qualquer cert válida.
            local adrLocked = false
            if isAdr then
                local needed = r.adr_type
                if type(needed) == 'string' and Config.Adr and Config.Adr.TypeLabels and Config.Adr.TypeLabels[needed] then
                    adrLocked = not validCerts[needed]
                else
                    adrLocked = next(validCerts) == nil
                end
            end

            local contractData = {
                id             = r.id or rId,
                contract_id    = r.id or rId,
                name           = r.name or r.title or 'Contrato de Transporte',
                contract_name  = r.name or r.title or 'Contrato de Transporte',
                type           = r.type or 'quick',
                contract_type  = (r.type == 'freight') and 1 or 0,
                cargo_model    = r.cargo_model or r.cargo_prop or 'hei_prop_carrier_cargo_04b',
                cargo_name     = r.cargo_name or r.title or 'Carga Padrão',
                truck          = r.truck_model or 'hauler',
                truckModel     = r.truck_model or 'hauler',
                trailer        = r.trailer_model or 'trailers2',
                trailerModel   = r.trailer_model or 'trailers2',
                reward         = basePayment,
                payment        = basePayment,
                base_payment   = basePayment,
                xp             = baseXP,
                base_xp        = baseXP,
                distance       = dist,
                distance_km    = dist,
                level_required = tonumber(r.req_skill) or tonumber(r.required_level) or 1,
                req_skill      = tonumber(r.req_skill) or tonumber(r.required_level) or 1,
                fragile        = isFragile and 1 or 0,
                valuable       = isValuable and 1 or 0,
                cargo_type     = isAdr and 1 or 0,
                requires_adr   = isAdr,
                adrRequired    = isAdr,
                adrLocked      = adrLocked,
                withForklift   = (r.has_forklift == 1 or r.has_forklift == true),
                pickup_coords  = r.pickup_coords,
                delivery_coords = r.delivery_coords,
                palletCount    = 4,
            }

            if ProgressionService and ProgressionService.CalculateContractBonuses and citizenId then
                local bonuses = ProgressionService.CalculateContractBonuses(citizenId, contractData)
                contractData.reward = math.floor(basePayment * bonuses.moneyMultiplier)
                contractData.bonus_money_pct = bonuses.moneyBonusPct
                contractData.bonus_exp_pct = bonuses.expBonusPct
            end

            table.insert(contracts, contractData)
            idx = idx + 1
        end
    end

    -- Caminho de leitura: nunca escreve no banco (seed só ocorre no boot/LoadAll quando a tabela está vazia)
    return contracts
end

function AdminService.GetSpawnsByType(spawnType)
    local results = {}
    if not AdminService.Spawns then return results end
    local targetType = tostring(spawnType or ''):lower()
    for _, s in pairs(AdminService.Spawns) do
        if tostring(s.spawn_type):lower() == targetType and s.coords then
            table.insert(results, s.coords)
        end
    end
    return results
end
