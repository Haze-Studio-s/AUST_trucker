-- aurp_trucker — client/forklift.client.lua
-- Modo 1: Trade Point Mini-Jobs + Modo 2: Industry Forklift Loading

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local activeTradePoint    = nil   -- config do trade point ativo (Modo 1)
local spawnedForklift     = nil   -- entity handle do forklift alugado
local spawnedPallets      = {}    -- lista de netIds pendentes
local missionTimer        = nil   -- GetGameTimer() ao iniciar missão (Modo 1)
local returnZone          = nil   -- lib.zones.sphere da zona de devolução
-- Modo 1: flag setada pelo RegisterNetEvent 'allPalletsLoaded' e polled pelo truck thread
-- Keyed por locationId para suportar eventual edge-case de missão reiniciada
local MissionCompleteFlag = {}    -- locationId → bool

-- ============================================================
-- HELPERS
-- ============================================================

local function SpawnVehicle(model, coords)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 5000 do Wait(100); t = t + 100 end
    if not HasModelLoaded(hash) then return nil end
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, true, false)
    SetModelAsNoLongerNeeded(hash)
    return (veh and veh ~= 0) and veh or nil
end

local function SpawnObject(model, coords)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 3000 do Wait(100); t = t + 100 end
    if not HasModelLoaded(hash) then return nil end
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, true, false, false)
    SetModelAsNoLongerNeeded(hash)
    return (obj and obj ~= 0) and obj or nil
end

local function FindNearbyTrailer(maxDist)
    maxDist = maxDist or 20.0
    local pos      = GetEntityCoords(PlayerPedId())
    local vehicles = GetGamePool('CVehicle')
    local closest, closestDist = nil, maxDist
    for _, v in ipairs(vehicles) do
        if IsThisModelATrailer(GetEntityModel(v)) then
            local d = #(GetEntityCoords(v) - pos)
            if d < closestDist then closestDist = d; closest = v end
        end
    end
    return closest
end

-- Source ID como string — usado no StateBag (server compara com tostring(src))
local function MySourceIdStr()
    return tostring(GetPlayerServerId(PlayerId()))
end

-- ============================================================
-- PALLET DETECTION THREAD
-- ============================================================

local function StartPalletDetectionThread(netIds, targetVehicle, locationId, bootLen)
    local pending = {}
    for _, netId in ipairs(netIds) do
        pending[netId] = true
    end

    CreateThread(function()
        while next(pending) do
            Wait(500)
            if not DoesEntityExist(targetVehicle) then break end

            local bootAngle  = GetVehicleDoorAngleRatio(targetVehicle, 5)
            local bootCoords = GetOffsetFromEntityInWorldCoords(targetVehicle, 0.0, -(bootLen or 4.0), 0.7)

            for netId in pairs(pending) do
                if not NetworkDoesEntityExistWithNetworkId(netId) then
                    -- Server deletou — carregamento confirmado
                    pending[netId] = nil
                else
                    local obj = NetToObj(netId)
                    if DoesEntityExist(obj) then
                        local d = #(GetEntityCoords(obj) - bootCoords)
                        if bootAngle >= Config.Forklift.BootDoorRatio and d <= Config.Forklift.LoadDetectRadius then
                            pending[netId] = nil
                            TriggerServerEvent('aurp_trucker:palletLoaded', netId, locationId)
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- MODO 1: TRADE POINT
-- ============================================================

local function CleanupTradePoint()
    if spawnedForklift and DoesEntityExist(spawnedForklift) then
        DeleteEntity(spawnedForklift)
    end
    spawnedForklift = nil
    spawnedPallets  = {}

    if activeTradePoint then
        MissionCompleteFlag[activeTradePoint.id] = nil  -- reset flag
    end
    activeTradePoint = nil
    missionTimer     = nil

    if returnZone then returnZone:remove(); returnZone = nil end

    VP_Trucker_ForkliftActive = nil
end

local function StartTradePointMission(tp)
    activeTradePoint = tp
    missionTimer     = GetGameTimer()

    -- Spawnar forklift
    spawnedForklift = SpawnVehicle(Config.Forklift.ForkliftModel, tp.forkliftSpawn)
    if not spawnedForklift then
        lib.notify({ title = 'Forklift', description = 'Erro ao spawnar empilhadeira', type = 'error' })
        -- Devolver via callback (sem refund: falha de spawn após rent)
        pcall(lib.callback.await, 'aurp_trucker:returnForklift', false)
        CleanupTradePoint()
        return
    end
    SetEntityAsMissionEntity(spawnedForklift, true, true)
    -- H-03: reportar netId ao server para limpeza de entidade em playerDropped
    TriggerServerEvent('aurp_trucker:forklift:setNetId', NetworkGetNetworkIdFromEntity(spawnedForklift))

    -- Spawnar pallets
    -- v20: suporte a palletPool — props visuais variados por TradePoint
    local function GetPalletModel()
        if tp.palletPool
            and Config.Forklift.PalletModels
            and Config.Forklift.PalletModels[tp.palletPool]
        then
            local pool = Config.Forklift.PalletModels[tp.palletPool]
            return pool[math.random(#pool)]
        end
        return Config.Forklift.PalletModel
    end

    local palletNetIds = {}
    for _, spawnCoords in ipairs(tp.palletSpawns) do
        local obj = SpawnObject(GetPalletModel(), spawnCoords)
        if obj then
            SetEntityAsMissionEntity(obj, true, true)
            SetEntityDynamic(obj, true)
            -- StateBag: source ID como string (server valida com tostring(src))
            Entity(obj).state:set('forklift_owner',    MySourceIdStr(), true)
            Entity(obj).state:set('forklift_location', tp.id, true)
            table.insert(palletNetIds, ObjToNet(obj))
        end
    end
    spawnedPallets = palletNetIds

    VP_Trucker_ForkliftActive = { locationId = tp.id, mode = 'tradepoint' }

    -- Inicializar flag de conclusão (será setada pelo RegisterNetEvent 'allPalletsLoaded')
    MissionCompleteFlag[tp.id] = false

    -- Zona de devolução
    returnZone = lib.zones.sphere({
        coords  = vector3(tp.forkliftSpawn.x, tp.forkliftSpawn.y, tp.forkliftSpawn.z),
        radius  = 15.0,
        onEnter = function()
            lib.showTextUI('[E] Devolver Forklift ($250)', { position = 'left-center', icon = 'truck' })
        end,
        onExit  = function()
            lib.hideTextUI()
        end,
        inside  = function()
            if IsControlJustReleased(0, 38) then  -- E
                lib.hideTextUI()
                local ok, result = pcall(lib.callback.await, 'aurp_trucker:returnForklift', false)
                if ok and result and result.success then
                    lib.notify({ title = 'Forklift', description = ('Devolvido! +$%d reembolsado'):format(result.refund), type = 'success' })
                    CleanupTradePoint()
                end
            end
        end,
    })

    lib.notify({ title = 'Forklift Alugado', description = ('%s — %d pallets para carregar!'):format(tp.name, tp.maxPallets), type = 'inform' })

    -- Thread do caminhão NPC
    CreateThread(function()
        local npcTruck = SpawnVehicle(tp.deliveryVehicle, tp.deliveryStart)
        if not npcTruck then
            lib.notify({ title = 'Forklift', description = 'Erro ao spawnar caminhão NPC', type = 'error' })
            CleanupTradePoint()
            return
        end
        SetEntityAsMissionEntity(npcTruck, true, true)

        -- Criar motorista IA
        local driverHash = GetHashKey('a_m_m_trucker_01')
        RequestModel(driverHash)
        local t = 0
        while not HasModelLoaded(driverHash) and t < 3000 do Wait(100); t = t + 100 end
        local driver = CreatePed(4, driverHash, tp.deliveryStart.x, tp.deliveryStart.y, tp.deliveryStart.z, tp.deliveryStart.w, true, false)
        SetPedIntoVehicle(driver, npcTruck, -1)
        SetModelAsNoLongerNeeded(driverHash)

        -- Dirigir até deliveryEnd
        TaskVehicleDriveToCoordLongrange(driver, npcTruck,
            tp.deliveryEnd.x, tp.deliveryEnd.y, tp.deliveryEnd.z,
            15.0, 786603, 5.0)

        -- Aguardar chegada (max 60s)
        local arrived  = false
        local deadline = GetGameTimer() + 60000
        while not arrived and GetGameTimer() < deadline do
            Wait(1000)
            if not DoesEntityExist(npcTruck) then break end
            local d = #(GetEntityCoords(npcTruck) - vector3(tp.deliveryEnd.x, tp.deliveryEnd.y, tp.deliveryEnd.z))
            if d < 8.0 then arrived = true end
        end

        local function cleanupNpc()
            Wait(5000)
            if DoesEntityExist(npcTruck) then DeleteEntity(npcTruck) end
            if DoesEntityExist(driver)   then DeleteEntity(driver)   end
        end

        if not arrived then
            lib.notify({ title = 'Forklift', description = 'Caminhão não chegou. Missão cancelada.', type = 'error' })
            CleanupTradePoint()
            CreateThread(cleanupNpc)
            return
        end

        -- Parar e abrir boot
        TaskVehicleStop(driver, npcTruck, 3.0, false)
        Wait(2000)
        SetVehicleDoorOpen(npcTruck, 5, false, false)

        -- Iniciar detecção de pallets
        StartPalletDetectionThread(palletNetIds, npcTruck, tp.id, 4.0)

        -- Aguardar sinal de conclusão via MissionCompleteFlag (setado pelo RegisterNetEvent)
        -- Ou timeout server-side dispara 'tradePointTimeout' que chama CleanupTradePoint()
        local done   = false
        local expire = GetGameTimer() + (tp.timeLimit + 10) * 1000  -- +10s buffer após server timeout

        while not done and GetGameTimer() < expire do
            Wait(500)
            done = MissionCompleteFlag[tp.id] == true
            -- Se activeTradePoint foi limpo (CleanupTradePoint chamado por timeout), sair
            if not activeTradePoint then break end
        end

        if MissionCompleteFlag[tp.id] then
            -- Todos os pallets carregados — processar pagamento
            local elapsed = math.floor((GetGameTimer() - missionTimer) / 1000)
            local ok, result = pcall(lib.callback.await, 'aurp_trucker:completeTradePoint', false,
                { locationId = tp.id, elapsedSeconds = elapsed })

            if ok and result and result.success then
                lib.notify({
                    title       = 'Trade Point Concluído!',
                    description = ('Pagamento: $%d'):format(result.payment),
                    type        = 'success',
                    duration    = 8000,
                })
            else
                lib.notify({ title = 'Forklift', description = 'Erro ao processar pagamento', type = 'error' })
            end
        end
        -- (se não done = timeout foi disparado pelo server via tradePointTimeout event)

        -- Caminhão parte
        TaskVehicleDriveToCoordLongrange(driver, npcTruck,
            tp.deliveryStart.x, tp.deliveryStart.y, tp.deliveryStart.z,
            20.0, 786603, 5.0)

        CleanupTradePoint()
        CreateThread(cleanupNpc)
    end)
end

-- Timeout server-side — cancelar missão client-side
RegisterNetEvent('aurp_trucker:client:tradePointTimeout', function(locationId)
    if not activeTradePoint or activeTradePoint.id ~= locationId then return end
    local tpName = activeTradePoint.name or locationId
    lib.notify({ title = 'Forklift', description = ('%s — Tempo esgotado! Missão cancelada sem reembolso.'):format(tpName), type = 'error' })
    CleanupTradePoint()
end)

-- Cleanup de entidades se resource restartar com missão ativa
AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    CleanupTradePoint()
end)

-- ============================================================
-- MODO 2: INDUSTRY LOAD
-- ============================================================

AddEventHandler('aurp_trucker:forklift:startIndustryLoad', function(qty, trailerHandle)
    local trailer = trailerHandle
    if not trailer or not DoesEntityExist(trailer) then
        trailer = FindNearbyTrailer()
    end
    if not trailer then
        lib.notify({ title = 'Forklift', description = 'Trailer não encontrado', type = 'error' })
        return
    end

    local locationId = VP_Trucker_ForkliftActive and VP_Trucker_ForkliftActive.locationId or 'industry'

    -- Spawnar pallets ao redor do trailer
    local trailerPos   = GetEntityCoords(trailer)
    local palletNetIds = {}
    for i = 1, qty do
        local offset   = vector3((i - 1) * 1.5 - (qty * 0.75), -8.0, 0.0)
        local worldPos = trailerPos + offset
        local obj = SpawnObject(Config.Forklift.PalletModel, worldPos)
        if obj then
            SetEntityAsMissionEntity(obj, true, true)
            SetEntityDynamic(obj, true)
            Entity(obj).state:set('forklift_owner',    MySourceIdStr(), true)
            Entity(obj).state:set('forklift_location', locationId, true)
            table.insert(palletNetIds, ObjToNet(obj))
        end
    end
    spawnedPallets = palletNetIds

    SetVehicleDoorOpen(trailer, 5, false, false)

    -- Atualizar rental.expected no server ANTES de iniciar a thread de detecção
    -- (evita race condition: expected = 1 no server quando pallet for detectado)
    TriggerServerEvent('aurp_trucker:updateForkliftExpected', qty)

    StartPalletDetectionThread(palletNetIds, trailer, locationId, 6.0)

    lib.notify({ title = 'Forklift', description = ('Carregue os %d pallets no trailer!'):format(qty), type = 'inform' })
end)

-- allPalletsLoaded: handler único para ambos os modos
-- NOTA: TriggerClientEvent do server dispara SOMENTE RegisterNetEvent (não AddEventHandler local)
RegisterNetEvent('aurp_trucker:client:allPalletsLoaded', function(locationId)
    local active = VP_Trucker_ForkliftActive
    if not active then return end

    if active.mode == 'industry' then
        -- Modo 2: sinalizar client.lua para continuar o fluxo normal de delivery
        if spawnedForklift and DoesEntityExist(spawnedForklift) then
            DeleteEntity(spawnedForklift)
        end
        spawnedForklift           = nil
        spawnedPallets            = {}
        VP_Trucker_ForkliftActive = nil
        TriggerEvent('aurp_trucker:forklift:industryLoadComplete')
    elseif active.mode == 'tradepoint' then
        -- Modo 1: setar flag que o NPC truck thread está polling
        MissionCompleteFlag[locationId] = true
    end
end)

-- ============================================================
-- OX_TARGET: NPCs de trade point (Proximity Streaming via lib.points)
-- ============================================================

CreateThread(function()
    Wait(2000)

    for _, tp in ipairs(Config.Forklift.TradePoints) do
        local point = lib.points.new({
            coords = tp.coords,
            distance = 60.0,
            npc = nil,
            onEnter = function(self)
                local npcHash = GetHashKey('a_m_m_trucker_01')
                RequestModel(npcHash)
                local t = 0
                while not HasModelLoaded(npcHash) and t < 3000 do Wait(100); t = t + 100 end

                self.npc = CreatePed(4, npcHash, tp.npcCoords.x, tp.npcCoords.y, tp.npcCoords.z, tp.npcCoords.w, false, false)
                SetModelAsNoLongerNeeded(npcHash)

                if self.npc and self.npc ~= 0 and DoesEntityExist(self.npc) then
                    SetEntityInvincible(self.npc, true)
                    SetBlockingOfNonTemporaryEvents(self.npc, true)
                    FreezeEntityPosition(self.npc, true)

                    local capturedTp = tp
                    exports.ox_target:addLocalEntity(self.npc, {
                        {
                            name     = 'aurp_trucker:forklift_' .. tp.id,
                            icon     = 'fas fa-truck-loading',
                            label    = ('Aceitar Ordem — %s'):format(tp.name),
                            distance = 3.0,
                            canInteract = function()
                                return VP_Trucker_ForkliftActive == nil
                            end,
                            onSelect = function()
                                if VP_Trucker_ForkliftActive then
                                    lib.notify({ title = 'Forklift', description = 'Você já tem um forklift ativo', type = 'error' })
                                    return
                                end

                                local ok, result = pcall(lib.callback.await, 'aurp_trucker:rentForklift', false, {
                                    locationId = capturedTp.id,
                                    mode       = 'tradepoint',
                                    expected   = capturedTp.maxPallets,
                                    deliveryVehicle = capturedTp.deliveryVehicle,
                                })

                                if not ok or not result then
                                    lib.notify({ title = 'Forklift', description = 'Erro ao alugar forklift', type = 'error' })
                                    return
                                end
                                if not result.success then
                                    lib.notify({ title = 'Forklift', description = result.reason or 'Erro desconhecido', type = 'error' })
                                    return
                                end

                                StartTradePointMission(capturedTp)
                            end,
                        }
                    })
                end
            end,
            onExit = function(self)
                if self.npc and self.npc ~= 0 and DoesEntityExist(self.npc) then
                    exports.ox_target:removeLocalEntity(self.npc)
                    DeleteEntity(self.npc)
                    self.npc = nil
                end
            end
        })

        AddEventHandler('onResourceStop', function(r)
            if r == GetCurrentResourceName() then
                if point.npc and point.npc ~= 0 and DoesEntityExist(point.npc) then
                    exports.ox_target:removeLocalEntity(point.npc)
                    DeleteEntity(point.npc)
                end
                pcall(function() point:remove() end)
            end
        end)
    end
end)

-- ============================================================
-- OX_TARGET: Props de industry spawn (Modo 2 - Proximity Streaming)
-- ============================================================

CreateThread(function()
    Wait(2000)

    for industryId, spawnCoords in pairs(Config.Forklift.IndustrySpawns) do
        local point = lib.points.new({
            coords = vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z),
            distance = 60.0,
            prop = nil,
            onEnter = function(self)
                local propHash = GetHashKey('prop_consite_bagb')
                RequestModel(propHash)
                local t = 0
                while not HasModelLoaded(propHash) and t < 3000 do Wait(100); t = t + 100 end

                self.prop = CreateObjectNoOffset(propHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
                SetModelAsNoLongerNeeded(propHash)

                if self.prop and self.prop ~= 0 and DoesEntityExist(self.prop) then
                    local capturedId     = industryId
                    local capturedCoords = spawnCoords

                    exports.ox_target:addLocalEntity(self.prop, {
                        {
                            name     = 'aurp_trucker:industry_forklift_' .. industryId,
                            icon     = 'fas fa-forklift',
                            label    = 'Alugar Forklift ($500)',
                            distance = 3.0,
                            canInteract = function()
                                return VP_Trucker_ForkliftActive == nil
                                    and VP_Trucker_CurrentJobOriginId == capturedId
                            end,
                            onSelect = function()
                                if VP_Trucker_ForkliftActive then
                                    lib.notify({ title = 'Forklift', description = 'Você já tem um forklift ativo', type = 'error' })
                                    return
                                end

                                local ok, result = pcall(lib.callback.await, 'aurp_trucker:rentForklift', false, {
                                    locationId = capturedId,
                                    mode       = 'industry',
                                    expected   = 1,
                                })

                                if not ok or not result or not result.success then
                                    lib.notify({ title = 'Forklift', description = (result and result.reason) or 'Erro ao alugar', type = 'error' })
                                    return
                                end

                                local forklift = SpawnVehicle(Config.Forklift.ForkliftModel, capturedCoords)
                                if forklift then
                                    SetEntityAsMissionEntity(forklift, true, true)
                                    spawnedForklift = forklift
                                end

                                VP_Trucker_ForkliftActive = { locationId = capturedId, mode = 'industry' }
                                lib.notify({ title = 'Forklift Alugado', description = 'Use a empilhadeira para carregar os pallets do trailer!', type = 'inform' })
                            end,
                        }
                    })
                end
            end,
            onExit = function(self)
                if self.prop and self.prop ~= 0 and DoesEntityExist(self.prop) then
                    exports.ox_target:removeLocalEntity(self.prop)
                    DeleteEntity(self.prop)
                    self.prop = nil
                end
            end
        })

        AddEventHandler('onResourceStop', function(r)
            if r == GetCurrentResourceName() then
                if point.prop and point.prop ~= 0 and DoesEntityExist(point.prop) then
                    exports.ox_target:removeLocalEntity(point.prop)
                    DeleteEntity(point.prop)
                end
                pcall(function() point:remove() end)
            end
        end)
    end
end)
