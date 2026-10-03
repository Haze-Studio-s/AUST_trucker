-- aurp_trucker — server/services/admin_service.lua
-- Serviço Administrativo em Tempo Real: Rotas, Spawns, Offsets 3D, Economia e NPCs

AdminService = {}

AdminService.CustomRoutes = {}
AdminService.Spawns = {}
AdminService.TrailerOffsets = {}
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

function AdminService.ReloadHomologatedProps()
    local props = MySQL.query.await('SELECT * FROM aust_trucker_homologated_props') or {}
    local propMap = {}
    for _, p in ipairs(props) do
        propMap[p.model_hash] = {
            id = p.id,
            model_hash = p.model_hash,
            name = p.name,
            cargo_category = p.cargo_category,
            offset = { x = tonumber(p.offset_x) or 0.0, y = tonumber(p.offset_y) or 0.0, z = tonumber(p.offset_z) or 0.0, heading = tonumber(p.heading) or 0.0 }
        }
    end
    AdminService.HomologatedProps = propMap
    return propMap
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

        -- 4. Carrega Props Homologados
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
            AdminService.Economy[e.key_name] = tonumber(e.numeric_value)
        end

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
    for _, o in ipairs(offsets) do
        local model = o.trailer_model:lower()
        if not offsetMap[model] then
            offsetMap[model] = { pallets = {}, forklift = nil }
        end
        local vecData = {
            id = o.id,
            label = o.label or nil,
            x = tonumber(o.offset_x) or 0.0,
            y = tonumber(o.offset_y) or 0.0,
            z = tonumber(o.offset_z) or 0.0,
            heading = tonumber(o.heading) or 0.0
        }
        local isFork = (o.is_forklift == 1 or o.is_forklift == true or tonumber(o.is_forklift) == 1 or tostring(o.is_forklift) == '1')
        if isFork then
            offsetMap[model].forklift = vecData
        else
            offsetMap[model].pallets[tostring(o.slot_index)] = vecData
            offsetMap[model].pallets[tonumber(o.slot_index)] = vecData
        end
    end

    -- Dual-indexação com normalização estrita de hash 32-bit (Signed e Unsigned)
    local dualMap = {}
    for model, data in pairs(offsetMap) do
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
    end
    AdminService.TrailerOffsets = dualMap

    -- Aplica os offsets dinâmicos sobre a tabela global Config.TrailerSlots com prioridade absoluta
    if Config and Config.TrailerSlots then
        for model, data in pairs(offsetMap) do
            local h = joaat(model)
            local u = h & 0xFFFFFFFF
            local s = (u >= 0x80000000) and (u - 0x100000000) or u

            local keys = { model, h, u, s, tostring(h), tostring(u), tostring(s) }
            for _, k in ipairs(keys) do
                if not Config.TrailerSlots[k] then
                    Config.TrailerSlots[k] = { pallets = {}, forklift = nil }
                end
                for idx, vec in pairs(data.pallets or {}) do
                    local slotEntry = { x = tonumber(vec.x) or 0.0, y = tonumber(vec.y) or 0.0, z = tonumber(vec.z) or 0.0, heading = tonumber(vec.heading) or 0.0 }
                    Config.TrailerSlots[k].pallets[tonumber(idx)] = slotEntry
                end
                if data.forklift then
                    local slotEntry = { x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                    Config.TrailerSlots[k].forklift = slotEntry
                end
            end
        end
    end

    return dualMap
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
    local currentOffsets = AdminService.ReloadTrailerOffsets()
    local currentProps = AdminService.ReloadHomologatedProps()

    local payload = {
        customRoutes = AdminService.CustomRoutes,
        routes = AdminService.CustomRoutes,
        spawns = AdminService.Spawns,
        trailerOffsets = currentOffsets,
        offsets = currentOffsets,
        homologatedProps = currentProps,
        props = currentProps,
        npcs = AdminService.NPCs,
        economy = AdminService.Economy,
        defaultProps = Config.PalletProps or { 'hei_prop_carrier_cargo_04b' },
    }

    TriggerClientEvent('aurp_trucker:client:openAdminPanel', src, payload)
end, false)

lib.callback.register('aurp_trucker:server:getAdminData', function(source)
    if not AdminService.IsPlayerAdmin(source) then return nil end
    local currentOffsets = AdminService.ReloadTrailerOffsets()
    local currentProps = AdminService.ReloadHomologatedProps()
    return {
        customRoutes = AdminService.CustomRoutes,
        routes = AdminService.CustomRoutes,
        spawns = AdminService.Spawns,
        trailerOffsets = currentOffsets,
        offsets = currentOffsets,
        homologatedProps = currentProps,
        props = currentProps,
        npcs = AdminService.NPCs,
        economy = AdminService.Economy,
        defaultProps = Config.PalletProps or { 'hei_prop_carrier_cargo_04b' },
    }
end)

-- Callback em tempo de execução para sincronização de offsets de reboque (100% da RAM, zero SQL overhead)
lib.callback.register('aurp_trucker:server:getTrailerOffsetsForModel', function(source, trailerModel)
    local offsets = AdminService.TrailerOffsets
    if not offsets or next(offsets) == nil then
        offsets = AdminService.ReloadTrailerOffsets()
    end

    local modelKey = tostring(trailerModel or ''):lower()
    local hash = tonumber(trailerModel) or joaat(modelKey)
    local u = hash & 0xFFFFFFFF
    local s = (u >= 0x80000000) and (u - 0x100000000) or u

    local targetData = offsets[modelKey] or offsets[hash] or offsets[u] or offsets[s] or offsets[tostring(hash)] or offsets[tostring(u)] or offsets[tostring(s)]
    if not targetData and Config.TrailerSlots then
        targetData = Config.TrailerSlots[hash] or Config.TrailerSlots[u] or Config.TrailerSlots[s] or Config.TrailerSlots[modelKey]
    end

    return {
        specific = targetData,
        all = offsets
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
    local label = data.label and tostring(data.label) or nil
    local ox, oy, oz = tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0
    local heading = tonumber(data.heading) or 0.0

    MySQL.query.await([[
        INSERT INTO aust_trucker_trailer_offsets
        (trailer_model, label, slot_index, offset_x, offset_y, offset_z, heading, is_forklift)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        label = VALUES(label), offset_x = VALUES(offset_x), offset_y = VALUES(offset_y), offset_z = VALUES(offset_z),
        heading = VALUES(heading)
    ]], {
        trailerModel, label, slotIndex, ox, oy, oz, heading, isForklift
    })

    -- Recarrega e normaliza dados frescos do banco
    local updatedOffsets = AdminService.ReloadTrailerOffsets()

    -- Notifica todos os clientes para sincronizar os novos offsets e atualizar a interface NUI
    TriggerClientEvent('aurp_trucker:client:adminSyncOffsets', -1, trailerModel, slotIndex, isForklift == 1, vector3(ox, oy, oz), heading, updatedOffsets)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Offset Calibrado',
        description = ('Offset do %s (%s) gravado no banco e ativo em tempo real!'):format(trailerModel, isForklift == 1 and 'Empilhadeira' or ('Slot ' .. tostring(slotIndex))),
        type = 'success'
    })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteTrailerOffset', function(trailerModel, slotIndex, isForklift)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not trailerModel then return end

    trailerModel = tostring(trailerModel):lower()
    slotIndex = tonumber(slotIndex) or 1
    local isFork = (isForklift == true or isForklift == 1 or isForklift == '1') and 1 or 0

    MySQL.query.await([[
        DELETE FROM aust_trucker_trailer_offsets 
        WHERE LOWER(trailer_model) = ? AND slot_index = ? AND is_forklift = ?
    ]], { trailerModel, slotIndex, isFork })

    local updated = AdminService.ReloadTrailerOffsets()
    TriggerClientEvent('aurp_trucker:client:adminSyncOffsets', -1, trailerModel, slotIndex, isFork == 1, vector3(0, 0, 0), 0.0, updated)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = ('Offset do slot %s (%s) excluído com sucesso.'):format(tostring(slotIndex), trailerModel), type = 'info' })
end)

-- 4. HOMOLOGAÇÃO DE CARGAS & PROPS
RegisterNetEvent('aurp_trucker:server:adminSaveHomologatedProp', function(propData)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not propData or not propData.modelHash then return end

    local modelHash = tostring(propData.modelHash):lower()
    local name = tostring(propData.name or modelHash)
    local category = tostring(propData.category or 'dry')
    local ox = tonumber(propData.x) or 0.0
    local oy = tonumber(propData.y) or 0.0
    local oz = tonumber(propData.z) or 0.0
    local heading = tonumber(propData.heading) or 0.0

    MySQL.query.await([[
        INSERT INTO aust_trucker_homologated_props
        (model_hash, name, cargo_category, offset_x, offset_y, offset_z, heading)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        name = VALUES(name), cargo_category = VALUES(cargo_category),
        offset_x = VALUES(offset_x), offset_y = VALUES(offset_y), offset_z = VALUES(offset_z), heading = VALUES(heading)
    ]], { modelHash, name, category, ox, oy, oz, heading })

    local props = AdminService.ReloadHomologatedProps()
    TriggerClientEvent('aurp_trucker:client:adminSyncProps', -1, props)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Prop Homologado', description = ('Carga "%s" (%s) homologada e liberada para rotas!'):format(name, modelHash), type = 'success' })
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteHomologatedProp', function(modelHash)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not modelHash then return end

    MySQL.query.await('DELETE FROM aust_trucker_homologated_props WHERE model_hash = ?', { tostring(modelHash):lower() })
    local props = AdminService.ReloadHomologatedProps()
    TriggerClientEvent('aurp_trucker:client:adminSyncProps', -1, props)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Admin Trucker', description = 'Prop desomologado e removido do catálogo.', type = 'info' })
end)

-- 5. PASTAS E DRAG-AND-DROP DE SPAWNS
RegisterNetEvent('aurp_trucker:server:adminMoveSpawnFolder', function(spawnId, folderName)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not spawnId then return end

    folderName = tostring(folderName or 'Geral'):gsub('^%s*(.-)%s*$', '%1')
    if folderName == '' then folderName = 'Geral' end

    MySQL.query.await('UPDATE aust_trucker_spawns SET folder_name = ? WHERE id = ?', { folderName, spawnId })
    if AdminService.Spawns[spawnId] then
        AdminService.Spawns[spawnId].folder_name = folderName
    end
    TriggerClientEvent('aurp_trucker:client:adminSyncSpawns', -1, AdminService.Spawns)
end)

RegisterNetEvent('aurp_trucker:server:adminDeleteSpawnFolder', function(folderName)
    local src = source
    if not AdminService.IsPlayerAdmin(src) or not folderName then return end

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

-- 7. ECONOMIA E XP (SINCRONIZAÇÃO GLOBAL)
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

            local adrLocked = false
            if isAdr and not validCerts['class_1'] and not validCerts['class_2'] and not validCerts['class_3'] then
                adrLocked = true
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

    -- Se por qualquer motivo não houver rotas dinâmicas, fallback para seed
    if #contracts == 0 then
        AdminService.SeedDefaultRoutes()
    end

    return contracts
end

function AdminService.GetSpawnsByType(spawnType)
    local results = {}
    if not AdminService.Spawns then return results end
    local targetType = tostring(spawnType or ''):lower()
    for _, s in ipairs(AdminService.Spawns) do
        if tostring(s.spawn_type):lower() == targetType and s.coords then
            table.insert(results, s.coords)
        end
    end
    return results
end
