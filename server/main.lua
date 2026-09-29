-- aurp_trucker — server/main.lua
-- Global state e inicialização do resource

-- Estado global (acessível por todos os arquivos server-side devido ao lua54)
-- NOTA: modificações incrementais a VP_Trucker são permitidas nas Fases 2 e 3
VP_Trucker = {
    Ready           = false,
    Companies       = {},   -- companyId → { id, owner_citizenid, name, balance, is_recruiting }
    PlayerCompanies = {},   -- citizenid → companyId
    ActiveJobs      = {},   -- jobId → data
    PlayerJobs      = {},   -- citizenid → jobId
    IndustryOwners  = {},   -- industryId → ownership row
    -- Fase 3A: Party + Convoy
    Parties         = {},   -- partyId → { leader, members = { [cid] = { src } }, graceTimers, maxSize, status }
    Convoys         = {},   -- convoyId → { partyId, memberJobs, graceTimers, broadcastTimer, activeCount, totalCount }
    PlayerParties   = {},   -- citizenid → partyId (lookup reverso)
    IllegalTargets  = {},   -- [plate] = { src, jobId, citizenid, illegalType }
    ShopStock       = {},   -- [shopId:itemName] = row (shop stock ecosystem v16)
    -- Fase 4A: NPC Drivers
    NpcDrivers     = {},  -- { [driverId] = driverRow }
    NpcJobs        = {},  -- { [npcJobId] = npcJobRow }
    PendingEvents  = {},  -- { [eventId]  = { driver, npcJob, payload } }
    AgencyProfiles = {},  -- { profiles = [...], generatedAt = unixTimestamp }
    -- Fase ADR: Cooldowns de exame por jogador
    AdrExamCooldowns = {},  -- citizenid → unixTimestamp (expiry)
    -- Fase 5: Forklift
    ForkliftRentals  = {},  -- citizenId → { locationId, mode, src, rentedAt, loaded, expected }
    TradePointActive = {},  -- locationId → citizenId (um player por trade point)
    -- Fase 5: Cargo Theft
    CargoByPlate     = {},  -- plate → { jobId, citizenId, gpsEnabled, isStolen, basePayment, vulnerableSince, theftBy, theftStartedAt }
    -- v20: Container Handler (integração oConteneur)
    ContainerJobs    = {},  -- citizenId → { src, startedAt, containerLoc, deliverySlot, cargo }
    -- v20.2: Gerenciamento autoritativo de entidades e aluguel de caminhões
    PlayerJobEntities = {}, -- citizenId → { truckNetId, trailerNetId, rentalPlate }
    TruckRentals      = {}, -- citizenId → { plate, model, deposit, fee, rentedAt, netId }
}

-- Helper global: retorna nome do PERSONAGEM (firstname lastname), fallback para Steam name
-- L-03: usa Framework.GetCharInfo para suportar QBX, QBCore e ESX
function GetCharName(src)
    if not src then return 'Desconhecido' end
    local p  = Framework.GetPlayer(src)
    local ci = p and Framework.GetCharInfo(p)
    if ci then
        return ('%s %s'):format(ci.firstname or '', ci.lastname or '')
    end
    return GetPlayerName(src) or ('Jogador #' .. src)
end

-- Carrega todas as empresas do DB para o cache em memória
local function LoadCompanies()
    local companies = MySQL.query.await('SELECT * FROM trucker_companies') or {}
    for _, company in ipairs(companies) do
        VP_Trucker.Companies[company.id] = company
    end

    local members = MySQL.query.await('SELECT citizenid, company_id FROM trucker_company_members') or {}
    for _, member in ipairs(members) do
        VP_Trucker.PlayerCompanies[member.citizenid] = member.company_id
    end

    if Config.Debug then
        print(('[aurp_trucker] Loaded %d companies into cache'):format(#companies))
    end
end

-- Inicialização: aguarda oxmysql estar pronto
CreateThread(function()
    -- Auto-sanitização: remove qualquer injeção maliciosa de 'webpack_bundle' de fxmanifest.lua
    pcall(function()
        local resPath = GetResourcePath(GetCurrentResourceName())
        if resPath then
            local manifestPath = resPath .. '/fxmanifest.lua'
            local rFile = io.open(manifestPath, 'r')
            if rFile then
                local content = rFile:read('*a')
                rFile:close()
                if content and content:find('webpack_bundle') then
                    local clean = content:gsub("[^\r\n]*webpack_bundle[^\r\n]*[\r\n]*", "")
                    local wFile = io.open(manifestPath, 'w')
                    if wFile then
                        wFile:write(clean)
                        wFile:close()
                        print('[AUST_trucker] Seguranca: Injecao maliciosa de webpack_bundle purgada com sucesso de fxmanifest.lua.')
                    end
                end
            end
        end
    end)

    -- oxmysql dispara 'oxmysql:ready' quando conectado
    -- Aguardamos via MySQL.ready para garantir conexão antes de queries
    MySQL.ready(function()
        math.randomseed(os.time())
        SchemaService.EnsureTables()   -- v17: garantir schema antes de queries
        -- HARDENING: Resetar veículos que ficaram presos com status 'out' após restart/crash
        MySQL.update.await("UPDATE trucker_company_vehicles SET status = 'stored' WHERE status = 'out'")
        LoadCompanies()
        -- JobService ainda não existe aqui no load order — usar callback
        CreateThread(function()
            while not JobService do Wait(100) end
            while not IndustryOwnershipService do Wait(100) end
            while not ConvoyService do Wait(100) end
            IndustryOwnershipService.LoadCache()
            JobService.LoadFromDB()
            ConvoyService.LoadFromDB()
            while not CargoTrackingService do Wait(100) end
            CargoTrackingService.LoadFromDB()
            while not NpcDriverService do Wait(100) end
            NpcDriverService.LoadFromDB()
            -- Shop Stock Ecosystem (v16.0.0)
            if ShopStockService and Config.ShopStock and Config.ShopStock.Enabled then
                ShopStockService.LoadFromDB()
            end
            VP_Trucker.Ready = true
            if Config.Debug then print('[aurp_trucker] Server ready.') end
        end)
    end)
end)

-- Expõe função de reload do cache para outros arquivos
function ReloadCompanyCache()
    VP_Trucker.Companies = {}
    VP_Trucker.PlayerCompanies = {}
    LoadCompanies()
end

-- =======================================================================
-- POLARIX TRUCKER: GERENCIAMENTO DE LOBBY, ONESYNC & ENTIDADES SERVER-SIDE
-- =======================================================================

local PolarixLobbies = {}
local PlayerPolarixLobbies = {}

-- Auto-schema idempotente para 0r_trucker
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `0r_trucker` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) NOT NULL UNIQUE,
            `level` INT DEFAULT 1,
            `xp` INT DEFAULT 0,
            `total_deliveries` INT DEFAULT 0,
            `total_earned` INT DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

local function CleanupLobbyEntities(lobby)
    if not lobby then return end
    if lobby.truck and DoesEntityExist(lobby.truck) then DeleteEntity(lobby.truck) end
    if lobby.trailer and DoesEntityExist(lobby.trailer) then DeleteEntity(lobby.trailer) end
    if lobby.forklift and DoesEntityExist(lobby.forklift) then DeleteEntity(lobby.forklift) end
    if lobby.pallets then
        for _, p in ipairs(lobby.pallets) do
            if p and DoesEntityExist(p) then DeleteEntity(p) end
        end
    end
    if lobby.src and GetPlayerPing(lobby.src) > 0 then
        SetPlayerRoutingBucket(lobby.src, 0)
    end
end

-- ETAPA 1: Validação de Nível e Inicialização do Lobby
RegisterNetEvent('aurp_trucker:server:startPolarixContract', function(contractData)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    contractData = contractData or {}

    if PlayerPolarixLobbies[citizenId] then
        TriggerClientEvent('aurp_trucker:notify', src, 'Contrato em Andamento', 'Você já possui uma rota ou contrato em andamento!', 'error')
        return
    end

    -- Consulta nível na tabela 0r_trucker
    local truckerRow = MySQL.single.await('SELECT level, xp FROM `0r_trucker` WHERE `citizenid` = ?', { citizenId })
    local playerLevel = truckerRow and truckerRow.level or 1
    local requiredLevel = contractData.level_required or 1

    if playerLevel < requiredLevel then
        TriggerClientEvent('aurp_trucker:notify', src, 'Nível Insuficiente', ('Você precisa de Nível %d para aceitar este contrato!'):format(requiredLevel), 'error')
        return
    end

    -- ETAPA 1.5: Resolução Autoritativa de Caminhão (Frota trucker_trucks ou Garagem player_vehicles vs Alugado)
    local selectedTruckModel = nil
    local selectedPlate = nil
    local savedMods = nil
    local isOwned = false

    -- 1. Verificação por placa informada no contrato
    if contractData.truckPlate and contractData.truckPlate ~= '' then
        local pRow = MySQL.single.await('SELECT vehicle, plate, mods FROM player_vehicles WHERE citizenid = ? AND plate = ? LIMIT 1', { citizenId, contractData.truckPlate })
        if pRow then
            selectedTruckModel = pRow.vehicle
            selectedPlate = pRow.plate
            savedMods = pRow.mods
            isOwned = true
        else
            local tRow = MySQL.single.await('SELECT truck_name, properties FROM trucker_trucks WHERE user_id = ? AND properties LIKE ? LIMIT 1', { citizenId, '%' .. contractData.truckPlate .. '%' })
            if tRow then
                selectedTruckModel = tRow.truck_name
                selectedPlate = contractData.truckPlate
                savedMods = tRow.properties
                isOwned = true
            end
        end
    end

    -- 2. Busca na frota interna do script (trucker_trucks)
    if not selectedTruckModel then
        local fleetTrucks = MySQL.query.await('SELECT truck_id, truck_name, properties FROM trucker_trucks WHERE user_id = ? ORDER BY truck_id DESC LIMIT 1', { citizenId })
        if fleetTrucks and fleetTrucks[1] then
            local t = fleetTrucks[1]
            selectedTruckModel = t.truck_name
            local props = json.decode(t.properties or '{}') or {}
            selectedPlate = props.plate
            savedMods = t.properties
            isOwned = true
        end
    end

    -- 3. Busca na garagem de veículos do jogador (player_vehicles) por cavalos mecânicos
    if not selectedTruckModel then
        local validModels = {
            'hauler', 'phantom', 'packer', 'phantom3', 'hauler2', 'vetirs', 'pounder', 'pounder2', 'biff'
        }
        if Config.TruckRental and Config.TruckRental.trucks then
            for _, trk in ipairs(Config.TruckRental.trucks) do
                table.insert(validModels, trk.model)
            end
        end
        if Config.LC_Dealership then
            for k in pairs(Config.LC_Dealership) do
                table.insert(validModels, k)
            end
        end

        local pVehicles = MySQL.query.await('SELECT vehicle, plate, mods FROM player_vehicles WHERE citizenid = ?', { citizenId }) or {}
        for _, pv in ipairs(pVehicles) do
            local pvModel = string.lower(pv.vehicle or '')
            for _, vm in ipairs(validModels) do
                if pvModel == string.lower(vm) then
                    selectedTruckModel = pv.vehicle
                    selectedPlate = pv.plate
                    savedMods = pv.mods
                    isOwned = true
                    break
                end
            end
            if selectedTruckModel then break end
        end
    end

    -- 4. Fallback: Caminhão de Serviço Padrão / Alugado
    if not selectedTruckModel then
        selectedTruckModel = contractData.truckModel or (Config.Truck and Config.Truck.model) or 'hauler'
        selectedPlate = ('RENT%04d'):format(math.random(1000, 9999))
        isOwned = false
    end

    if not selectedPlate or selectedPlate == '' then
        selectedPlate = ('TRK%05d'):format(math.random(10000, 99999))
    end

    local jobId = math.random(100000, 999999)
    local bucketId = 100 + (jobId % 900)
    SetPlayerRoutingBucket(src, bucketId)

    local wh = Config.Polarix.Warehouse
    local truckModel = joaat(selectedTruckModel)
    local trailerModel = joaat(contractData.trailerModel or 'trailers2')

    -- ETAPA 2: Spawns Autoritativos no Servidor
    local truck = CreateVehicle(truckModel, wh.TruckSpawnCoords.x, wh.TruckSpawnCoords.y, wh.TruckSpawnCoords.z, wh.TruckSpawnCoords.w, true, true)
    while not DoesEntityExist(truck) do Wait(50) end
    SetEntityRoutingBucket(truck, bucketId)
    SetEntityDistanceCullingRadius(truck, 400.0)
    SetVehicleNumberPlateText(truck, selectedPlate)
    -- O caminhão deve ser instanciado trancado no servidor para a etapa de inspeção
    SetVehicleDoorsLocked(truck, 2)

    local trailer = CreateVehicle(trailerModel, wh.TrailerSpawnCoords.x, wh.TrailerSpawnCoords.y, wh.TrailerSpawnCoords.z, wh.TrailerSpawnCoords.w, true, true)
    while not DoesEntityExist(trailer) do Wait(50) end
    SetEntityRoutingBucket(trailer, bucketId)
    SetEntityDistanceCullingRadius(trailer, 400.0)

    -- ETAPA 3: Spawn da Empilhadeira e Paletes
    local forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), wh.ForkliftBayCoords.x, wh.ForkliftBayCoords.y, wh.ForkliftBayCoords.z, wh.ForkliftBayCoords.w, true, true)
    while not DoesEntityExist(forklift) do Wait(50) end
    SetEntityRoutingBucket(forklift, bucketId)
    SetEntityDistanceCullingRadius(forklift, 350.0)

    local reqPallets = contractData.palletCount or 4
    local pallets = {}
    local palletNetIds = {}
    local anchor = wh.PalletStagingAnchor
    local rad = math.rad(wh.PalletStagingHeading or 180.0)
    local rowDir = vector3(math.cos(rad), math.sin(rad), 0.0)
    local colDir = vector3(-math.sin(rad), math.cos(rad), 0.0)

    for i = 1, reqPallets do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local pos = anchor + rowDir * (col * 2.2) + colDir * (row * 2.2)
        local pModel = joaat(Config.Polarix.PalletModels[(i % #Config.Polarix.PalletModels) + 1] or Config.Polarix.DefaultPalletModel)

        local pObj = CreateObject(pModel, pos.x, pos.y, pos.z, true, true, false)
        while not DoesEntityExist(pObj) do Wait(50) end
        SetEntityRoutingBucket(pObj, bucketId)
        SetEntityDistanceCullingRadius(pObj, 350.0)

        table.insert(pallets, pObj)
        table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pObj))
    end

    local destCfg = Config.Polarix.DeliveryDestinations[math.random(#Config.Polarix.DeliveryDestinations)]
    local destCoords = destCfg.coords

    local lobbyData = {
        jobId = jobId,
        src = src,
        citizenId = citizenId,
        bucketId = bucketId,
        truck = truck,
        truckPlate = selectedPlate,
        truckModel = selectedTruckModel,
        isOwned = isOwned,
        trailer = trailer,
        forklift = forklift,
        pallets = pallets,
        palletNetIds = palletNetIds,
        loadedCount = 0,
        requiredCount = reqPallets,
        cargoName = contractData.name or 'Paletes Industriais',
        payment = destCfg.reward or 5000,
        xp = destCfg.xp or 200,
        deliveryCoords = destCoords,
        stage = 'STATUS_INSPECTING'
    }

    PolarixLobbies[jobId] = lobbyData
    PlayerPolarixLobbies[citizenId] = jobId

    local payload = {
        jobId = jobId,
        truckNetId = NetworkGetNetworkIdFromEntity(truck),
        truckPlate = selectedPlate,
        truckModel = selectedTruckModel,
        truckMods = savedMods,
        isOwned = isOwned,
        trailerNetId = NetworkGetNetworkIdFromEntity(trailer),
        forkliftNetId = NetworkGetNetworkIdFromEntity(forklift),
        palletNetIds = palletNetIds,
        cargoName = lobbyData.cargoName,
        requiredCount = reqPallets,
        loadedCount = 0,
        deliveryCoords = destCoords
    }

    TriggerClientEvent('aurp_trucker:client:polarixJobStarted', src, payload)
end)

-- ETAPA 2: Validação de Inspeção Concluída e Liberação de Chaves QBox
RegisterNetEvent('aurp_trucker:server:inspectionCompleted', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    -- Validação de proximidade autoritativa do servidor
    local ped = GetPlayerPed(src)
    local pedCoords = GetEntityCoords(ped)
    local truckCoords = GetEntityCoords(lobby.truck)
    if #(pedCoords - truckCoords) > 25.0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Segurança', 'Você está muito afastado do caminhão para validar a inspeção!', 'error')
        return
    end

    lobby.stage = 'STATUS_LOADING'

    -- Destranca portas no servidor
    SetVehicleDoorsLocked(lobby.truck, 1)

    -- Entrega autoritativa de chaves no servidor (qbx_vehiclekeys)
    if exports['qbx_vehiclekeys'] then
        pcall(function()
            exports['qbx_vehiclekeys']:GiveKeys(src, lobby.truck)
        end)
    end

    local truckNetId = NetworkGetNetworkIdFromEntity(lobby.truck)
    TriggerClientEvent('aurp_trucker:client:inspectionUnlocked', src, jobId, lobby.truckPlate, truckNetId)
    TriggerClientEvent('aurp_trucker:client:polarixSyncPallets', src, lobby.palletNetIds)
end)

-- ETAPA 3: Acomodação do Palete na Carreta
RegisterNetEvent('aurp_trucker:server:polarixPalletLoaded', function(jobId, slotIndex)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.stage ~= 'STATUS_LOADING' then return end

    lobby.loadedCount = lobby.loadedCount + 1
    TriggerClientEvent('aurp_trucker:client:polarixProgressSync', src, lobby.loadedCount, lobby.requiredCount)
end)

-- ETAPA 4: Validação de Cintas e Liberação de Rota GPS
RegisterNetEvent('aurp_trucker:server:strappingCompleted', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.loadedCount < lobby.requiredCount then return end

    lobby.stage = 'STATUS_IN_TRANSIT'

    -- Migração suave para o Routing Bucket 0 (mundo aberto)
    SetPlayerRoutingBucket(src, 0)
    if lobby.truck and DoesEntityExist(lobby.truck) then
        SetEntityRoutingBucket(lobby.truck, 0)
    end
    if lobby.trailer and DoesEntityExist(lobby.trailer) then
        SetEntityRoutingBucket(lobby.trailer, 0)
    end

    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA 5: Entrega Final, Pagamentos QBOX e Persistência oxmysql
RegisterNetEvent('aurp_trucker:server:completePolarixDelivery', function(jobId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.citizenId ~= citizenId then return end
    if lobby.stage ~= 'STATUS_IN_TRANSIT' then return end

    -- Pagamento via QBOX Nativo (ou fallback Framework)
    local payment = lobby.payment or 5000
    local xp = lobby.xp or 200

    if exports.qbx_core then
        exports.qbx_core:AddMoney(src, 'bank', payment, 'polarix-trucker-job')
    else
        Framework.AddMoney(Player, 'bank', payment, 'polarix-trucker-job')
    end

    -- Atualização autoritativa da tabela 0r_trucker
    pcall(function()
        MySQL.query.await([[
            INSERT INTO 0r_trucker (citizenid, level, xp, total_deliveries, total_earned)
            VALUES (?, 1, ?, 1, ?)
            ON DUPLICATE KEY UPDATE
                xp = xp + VALUES(xp),
                total_deliveries = total_deliveries + 1,
                total_earned = total_earned + VALUES(total_earned),
                level = FLOOR(1 + (xp / 1000))
        ]], { citizenId, xp, payment })
    end)

    -- Atualiza aust_trucker_stats para manter paridade estatística do painel
    pcall(DB_UpdateAustTruckerStats, citizenId, xp, 1)

    -- Carreta é entregue e excluída
    if lobby.trailer and DoesEntityExist(lobby.trailer) then
        DeleteEntity(lobby.trailer)
    end

    -- Caminhão: se for alugado é removido; se for próprio do jogador, permanece no mundo com ele
    if not lobby.isOwned and lobby.truck and DoesEntityExist(lobby.truck) then
        DeleteEntity(lobby.truck)
    end

    -- Empilhadeira e paletes da baia são limpos
    if lobby.forklift and DoesEntityExist(lobby.forklift) then DeleteEntity(lobby.forklift) end
    if lobby.pallets then
        for _, p in ipairs(lobby.pallets) do
            if p and DoesEntityExist(p) then DeleteEntity(p) end
        end
    end

    PolarixLobbies[jobId] = nil
    PlayerPolarixLobbies[citizenId] = nil

    TriggerClientEvent('aurp_trucker:client:polarixJobFinished', src, {
        payment = payment,
        xp = xp,
        distance = 3.5
    })
end)

-- Reposição de Emergência / Fallback
RegisterNetEvent('aurp_trucker:server:emergencyRespawnEquipment', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    local wh = Config.Polarix.Warehouse

    -- Reposiciona ou respawna forklift se necessário
    if lobby.forklift and DoesEntityExist(lobby.forklift) then
        SetEntityCoords(lobby.forklift, wh.ForkliftBayCoords.x, wh.ForkliftBayCoords.y, wh.ForkliftBayCoords.z, false, false, false, true)
    else
        local forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), wh.ForkliftBayCoords.x, wh.ForkliftBayCoords.y, wh.ForkliftBayCoords.z, wh.ForkliftBayCoords.w, true, true)
        SetEntityRoutingBucket(forklift, lobby.bucketId)
        lobby.forklift = forklift
    end

    TriggerClientEvent('aurp_trucker:notify', src, 'Reposição Concluída', 'Empilhadeira e paletes foram restabelecidos no pátio com segurança.', 'success')
end)

-- Limpeza ao desconectar
AddEventHandler('playerDropped', function()
    local src = source
    for jobId, lobby in pairs(PolarixLobbies) do
        if lobby.src == src then
            CleanupLobbyEntities(lobby)
            if lobby.citizenId then PlayerPolarixLobbies[lobby.citizenId] = nil end
            PolarixLobbies[jobId] = nil
            break
        end
    end
end)

