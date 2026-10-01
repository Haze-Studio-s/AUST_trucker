-- aurp_trucker — server/services/admin_service.lua
-- Serviço Administrativo em Tempo Real: Rotas, Spawns, Offsets 3D, Economia e NPCs

AdminService = {}

AdminService.CustomRoutes = {}
AdminService.Spawns = {}
AdminService.TrailerOffsets = {}
AdminService.NPCs = {}
AdminService.Economy = {
    km_multiplier = 3.5,
    xp_multiplier = 1.0,
    adr_bonus_pct = 35.0,
    fragile_bonus_pct = 20.0,
    valuable_bonus_pct = 25.0,
}

-- ============================================================
-- VERIFICAÇÃO DE PERMISSÕES MULTI-FRAMEWORK
-- ============================================================

function AdminService.IsPlayerAdmin(src)
    if not src or src == 0 then return true end

    -- 1. ACE Permissions (Nativa FiveM)
    if IsPlayerAceAllowed(src, 'command.truckeradmin') or IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'admin') then
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

function AdminService.LoadAll()
    CreateThread(function()
        -- 1. Carrega Rotas Personalizadas
        local routes = MySQL.query.await('SELECT * FROM aust_trucker_custom_routes') or {}
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
            spawnMap[s.id] = s
        end
        AdminService.Spawns = spawnMap

        -- 3. Carrega Offsets de Reboques Mapeados Visualmente
        local offsets = MySQL.query.await('SELECT * FROM aust_trucker_trailer_offsets') or {}
        local offsetMap = {}
        for _, o in ipairs(offsets) do
            local model = o.trailer_model
            if not offsetMap[model] then
                offsetMap[model] = { pallets = {}, forklift = nil }
            end
            if o.is_forklift == 1 then
                offsetMap[model].forklift = vector3(o.offset_x, o.offset_y, o.offset_z)
            else
                offsetMap[model].pallets[o.slot_index] = vector3(o.offset_x, o.offset_y, o.offset_z)
            end
        end
        AdminService.TrailerOffsets = offsetMap

        -- Aplica os offsets dinâmicos sobre a tabela global Config.TrailerSlots
        if Config and Config.TrailerSlots then
            for model, data in pairs(offsetMap) do
                local hash = joaat(model)
                if not Config.TrailerSlots[hash] then
                    Config.TrailerSlots[hash] = { pallets = {}, forklift = nil }
                end
                for idx, vec in pairs(data.pallets) do
                    Config.TrailerSlots[hash].pallets[idx] = vec
                end
                if data.forklift then
                    Config.TrailerSlots[hash].forklift = data.forklift
                end
            end
        end

        -- 4. Carrega NPCs Despachantes
        local npcs = MySQL.query.await('SELECT * FROM aust_trucker_npcs') or {}
        local npcMap = {}
        for _, n in ipairs(npcs) do
            if n.coords and type(n.coords) == 'string' then
                pcall(function() n.coords = json.decode(n.coords) end)
            end
            npcMap[n.id] = n
        end
        AdminService.NPCs = npcMap

        -- 5. Carrega Economia
        local eco = MySQL.query.await('SELECT * FROM aust_trucker_economy_settings') or {}
        for _, e in ipairs(eco) do
            AdminService.Economy[e.key_name] = tonumber(e.numeric_value)
        end

        print(("^2[AUST_Trucker Admin] Dados administrativos carregados: %d Rotas, %d Spawns, %d Reboques Calibrados, %d NPCs.^7"):format(
            #routes, #spawns, #offsets, #npcs
        ))
    end)
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

    local payload = {
        routes = AdminService.CustomRoutes,
        spawns = AdminService.Spawns,
        offsets = AdminService.TrailerOffsets,
        npcs = AdminService.NPCs,
        economy = AdminService.Economy,
        defaultProps = Config.PalletProps or { 'hei_prop_carrier_cargo_04b' },
    }

    TriggerClientEvent('aurp_trucker:client:openAdminPanel', src, payload)
end, false)

lib.callback.register('aurp_trucker:server:getAdminData', function(source)
    if not AdminService.IsPlayerAdmin(source) then return nil end
    return {
        routes = AdminService.CustomRoutes,
        spawns = AdminService.Spawns,
        offsets = AdminService.TrailerOffsets,
        npcs = AdminService.NPCs,
        economy = AdminService.Economy,
        defaultProps = Config.PalletProps or { 'hei_prop_carrier_cargo_04b' },
    }
end)

-- ============================================================
-- EVENTOS DE SALVAMENTO & HOT-RELOAD EM TEMPO REAL
-- ============================================================

-- 1. ROTAS E CONTRATOS
RegisterNetEvent('aurp_trucker:server:adminSaveRoute', function(routeData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not routeData then return end

    local routeId = routeData.id or ('route_' .. tostring(os.time()) .. '_' .. math.random(100, 999))
    routeData.id = routeId

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
        routeId,
        routeData.name or 'Nova Rota Customizada',
        routeData.type or 'quick',
        routeData.cargo_model or 'hei_prop_carrier_cargo_04b',
        routeData.cargo_name or 'Paletes de Carga',
        routeData.truck_model or 'hauler',
        routeData.trailer_model or 'trailers2',
        tonumber(routeData.base_payment) or 5000,
        tonumber(routeData.base_xp) or 200,
        tonumber(routeData.req_skill) or 0,
        routeData.fragile and 1 or 0,
        routeData.valuable and 1 or 0,
        json.encode(routeData.pickup_coords or {}),
        json.encode(routeData.delivery_coords or {}),
        (routeData.is_active ~= false) and 1 or 0
    })

    AdminService.CustomRoutes[routeId] = routeData
    TriggerClientEvent('aurp_trucker:client:adminSyncRoutes', -1, AdminService.CustomRoutes)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Rota salva e sincronizada em tempo real!', type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteRoute', function(routeId)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not routeId then return end

    MySQL.query.await('DELETE FROM aust_trucker_custom_routes WHERE id = ?', { routeId })
    AdminService.CustomRoutes[routeId] = nil
    TriggerClientEvent('aurp_trucker:client:adminSyncRoutes', -1, AdminService.CustomRoutes)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Rota excluída do servidor.', type = 'info' })
end)

-- 2. SPAWNS E BAÍAS
RegisterNetEvent('aurp_trucker:server:adminSaveSpawn', function(spawnData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not spawnData then return end

    local spawnId = spawnData.id or ('spawn_' .. tostring(os.time()) .. '_' .. math.random(100, 999))
    spawnData.id = spawnId

    MySQL.query.await([[
        INSERT INTO aust_trucker_spawns (id, name, spawn_type, coords, heading)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), spawn_type = VALUES(spawn_type), coords = VALUES(coords), heading = VALUES(heading)
    ]], {
        spawnId,
        spawnData.name or 'Ponto de Spawn',
        spawnData.spawn_type or 'truck',
        json.encode(spawnData.coords or {}),
        tonumber(spawnData.heading) or 0.0
    })

    AdminService.Spawns[spawnId] = spawnData
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Ponto de spawn gravado com sucesso!', type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteSpawn', function(spawnId)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not spawnId then return end

    MySQL.query.await('DELETE FROM aust_trucker_spawns WHERE id = ?', { spawnId })
    AdminService.Spawns[spawnId] = nil
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Spawn excluído.', type = 'info' })
end)

-- 3. MAPEAMENTO DE OFFSETS DE TRAILER (GIZMO / NUDGE TOOL)
RegisterNetEvent('aurp_trucker:server:adminSaveTrailerOffset', function(data)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not data then return end

    local trailerModel = data.trailerModel:lower()
    local slotIndex = tonumber(data.slotIndex) or 1
    local isForklift = data.isForklift and 1 or 0
    local ox, oy, oz = tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0
    local heading = tonumber(data.heading) or 0.0

    MySQL.query.await([[
        INSERT INTO aust_trucker_trailer_offsets
        (trailer_model, slot_index, offset_x, offset_y, offset_z, heading, is_forklift)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        offset_x = VALUES(offset_x), offset_y = VALUES(offset_y), offset_z = VALUES(offset_z),
        heading = VALUES(heading)
    ]], {
        trailerModel, slotIndex, ox, oy, oz, heading, isForklift
    })

    -- Atualiza cache em memória
    if not AdminService.TrailerOffsets[trailerModel] then
        AdminService.TrailerOffsets[trailerModel] = { pallets = {}, forklift = nil }
    end
    if isForklift == 1 then
        AdminService.TrailerOffsets[trailerModel].forklift = vector3(ox, oy, oz)
    else
        AdminService.TrailerOffsets[trailerModel].pallets[slotIndex] = vector3(ox, oy, oz)
    end

    -- Atualiza Config.TrailerSlots do servidor
    local hash = joaat(trailerModel)
    if not Config.TrailerSlots[hash] then
        Config.TrailerSlots[hash] = { pallets = {}, forklift = nil }
    end
    if isForklift == 1 then
        Config.TrailerSlots[hash].forklift = vector3(ox, oy, oz)
    else
        Config.TrailerSlots[hash].pallets[slotIndex] = vector3(ox, oy, oz)
    end

    -- Notifica todos os clientes para sincronizar os novos offsets instantaneamente
    TriggerClientEvent('aurp_trucker:client:adminSyncOffsets', -1, trailerModel, slotIndex, isForklift == 1, vector3(ox, oy, oz), heading)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Offset Calibrado',
        description = ('Offset do %s (Slot %s) gravado no banco e ativo em tempo real!'):format(trailerModel, tostring(slotIndex)),
        type = 'success'
    })
end)

-- 4. NPCS E DESPACHANTES
RegisterNetEvent('aurp_trucker:server:adminSaveNPC', function(npcData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not npcData then return end

    local npcId = npcData.id or ('npc_' .. tostring(os.time()) .. '_' .. math.random(100, 999))
    npcData.id = npcId

    MySQL.query.await([[
        INSERT INTO aust_trucker_npcs (id, name, model, coords, heading, blip_sprite, blip_color, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), model = VALUES(model), coords = VALUES(coords), heading = VALUES(heading),
        blip_sprite = VALUES(blip_sprite), blip_color = VALUES(blip_color), is_active = VALUES(is_active)
    ]], {
        npcId,
        npcData.name or 'Despachante Logístico',
        npcData.model or 's_m_m_dockwork_01',
        json.encode(npcData.coords or {}),
        tonumber(npcData.heading) or 0.0,
        tonumber(npcData.blip_sprite) or 477,
        tonumber(npcData.blip_color) or 2,
        (npcData.is_active ~= false) and 1 or 0
    })

    AdminService.NPCs[npcId] = npcData
    TriggerClientEvent('aurp_trucker:client:adminSyncNPCs', -1, AdminService.NPCs)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'NPC despachante atualizado em tempo real!', type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteNPC', function(npcId)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not npcId then return end

    MySQL.query.await('DELETE FROM aust_trucker_npcs WHERE id = ?', { npcId })
    AdminService.NPCs[npcId] = nil
    TriggerClientEvent('aurp_trucker:client:adminSyncNPCs', -1, AdminService.NPCs)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'NPC removido do mapa.', type = 'info' })
end)

-- 5. ECONOMIA E XP
RegisterNetEvent('aurp_trucker:server:adminSaveEconomy', function(settings)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not settings then return end

    for key, val in pairs(settings) do
        local num = tonumber(val)
        if num then
            AdminService.Economy[key] = num
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
