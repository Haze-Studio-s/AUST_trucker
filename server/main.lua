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

-- FASE 2: MÓDULO 1 - CREW MULTIPLAYER (CO-OP LOGÍSTICO)
local TruckerCrews = {}        -- crewId -> { id, leader = citizenId, leaderSrc = src, members = { [citizenId] = { src = src, name = name } } }
local PlayerTruckerCrew = {}   -- citizenId -> crewId

local function CleanupLobbyEntities(lobby)
    if not lobby then return end

    if lobby.src and GetPlayerPing(lobby.src) > 0 then
        pcall(function() SetPlayerRoutingBucket(lobby.src, 0) end)
    end

    if lobby.trailer and DoesEntityExist(lobby.trailer) then
        DeleteEntity(lobby.trailer)
    end

    if not lobby.isOwned and lobby.truck and DoesEntityExist(lobby.truck) then
        DeleteEntity(lobby.truck)
    end

    if lobby.forklift and DoesEntityExist(lobby.forklift) then
        DeleteEntity(lobby.forklift)
    end

    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end

    if lobby.handler and DoesEntityExist(lobby.handler) then
        DeleteEntity(lobby.handler)
    end

    if lobby.container and DoesEntityExist(lobby.container) then
        DeleteEntity(lobby.container)
    end

    if lobby.policeVehicles then
        for _, v in ipairs(lobby.policeVehicles) do
            if DoesEntityExist(v) then DeleteEntity(v) end
        end
    end

    if lobby.policePeds then
        for _, p in ipairs(lobby.policePeds) do
            if DoesEntityExist(p) then DeleteEntity(p) end
        end
    end

    if lobby.pallets then
        for _, p in ipairs(lobby.pallets) do
            if p and DoesEntityExist(p) then
                DeleteEntity(p)
            end
        end
    end
end

-- =======================================================================
-- CARREGAMENTO DINÂMICO DE ROTAS (ROUTE CREATOR PERSISTIDO VIA JSON)
-- =======================================================================
local function LoadDynamicRoutes()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/routes.json')
    if raw and raw ~= '' then
        local success, routes = pcall(json.decode, raw)
        if success and type(routes) == 'table' then
            Config.Polarix = Config.Polarix or {}
            Config.Polarix.DeliveryDestinations = Config.Polarix.DeliveryDestinations or {}
            for _, r in ipairs(routes) do
                table.insert(Config.Polarix.DeliveryDestinations, {
                    id = r.id or ('custom_' .. math.random(1000, 9999)),
                    label = r.label or 'Destino Customizado',
                    cargoType = r.cargoType or 'dry',
                    coords = vector4(r.coords.x, r.coords.y, r.coords.z, r.coords.w or 0.0),
                    distance = r.distance or 5.0,
                    reward = r.reward or 6000,
                    xp = r.xp or 200
                })
            end
            print(("[AUST_Trucker] %d rotas customizadas carregadas dinamicamente de data/routes.json"):format(#routes))
        end
    end
end

-- Auto-schema idempotente para 0r_trucker e persistência de Heat
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `0r_trucker` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) NOT NULL UNIQUE,
            `level` INT DEFAULT 1,
            `xp` INT DEFAULT 0,
            `total_deliveries` INT DEFAULT 0,
            `total_earned` INT DEFAULT 0,
            `heat` INT DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    pcall(function()
        MySQL.query([[ALTER TABLE `0r_trucker` ADD COLUMN IF NOT EXISTS `heat` INT DEFAULT 0;]])
    end)
    pcall(function()
        MySQL.query([[ALTER TABLE `players` ADD COLUMN IF NOT EXISTS `trucker_heat` INT DEFAULT 0;]])
    end)

    -- Auto-schema idempotente para Bases/Garagens Tycoon (Fase 2)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `trucker_bases` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) NOT NULL,
            `base_id` VARCHAR(50) NOT NULL,
            `purchased_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY `unique_player_base` (`citizenid`, `base_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    LoadDynamicRoutes()
end)


-- =======================================================================
-- ONESYNC SERVER-SIDE AREA CLEARANCE CHECK
-- =======================================================================
function IsSpawnPointClear(coords, radius, ignoreEntities)
    if not coords then return false end
    local targetCoords = vector3(coords.x, coords.y, coords.z)
    local checkRadius = radius or 5.0
    local ignore = ignoreEntities or {}

    -- 1. Veículos no servidor
    if GetAllVehicles then
        local vehicles = GetAllVehicles()
        for _, veh in ipairs(vehicles) do
            if DoesEntityExist(veh) and not ignore[veh] then
                local entCoords = GetEntityCoords(veh)
                if #(targetCoords - entCoords) < checkRadius then
                    return false
                end
            end
        end
    end

    -- 2. Pedestres e jogadores no servidor
    if GetAllPeds then
        local peds = GetAllPeds()
        for _, ped in ipairs(peds) do
            if DoesEntityExist(ped) and not ignore[ped] then
                local entCoords = GetEntityCoords(ped)
                local pedRadius = (checkRadius > 3.0) and 3.0 or checkRadius
                if #(targetCoords - entCoords) < pedRadius then
                    return false
                end
            end
        end
    end

    -- 3. Objetos e props no servidor (paletes, caixas, obstáculos)
    if GetAllObjects then
        local objects = GetAllObjects()
        for _, obj in ipairs(objects) do
            if DoesEntityExist(obj) and not ignore[obj] then
                local entCoords = GetEntityCoords(obj)
                if #(targetCoords - entCoords) < checkRadius then
                    return false
                end
            end
        end
    end

    return true
end

-- ETAPA 1: Iniciar Entrega / Contrato Autoritativo (QBOX OneSync)
local function StartTruckDelivery(src, contractData)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    contractData = contractData or {}

    if PlayerPolarixLobbies[citizenId] then
        TriggerClientEvent('aurp_trucker:notify', src, 'Contrato em Andamento', 'Você já possui uma rota ou contrato em andamento!', 'error')
        return
    end

    -- Se recebeu apenas jobId ou contractId numérico do tablet NUI (JobList / acceptJob)
    if contractData.jobId or contractData.contractId or contractData.id then
        local rawId = contractData.jobId or contractData.contractId or contractData.id
        local numId = tonumber(rawId)
        if numId and Config.LC_Jobs and Config.LC_Jobs.available_loads and Config.LC_Jobs.available_loads[numId] then
            local load = Config.LC_Jobs.available_loads[numId]
            contractData.name = contractData.name or load.name
            contractData.palletCount = contractData.palletCount or 4
            contractData.trailerModel = contractData.trailerModel or load.trailer
        end
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
    local bucketId = 0 -- Mundo compartilhado padrão (Bucket 0)

    local wh = Config.Polarix.Warehouse
    local truckModel = joaat(selectedTruckModel)

    -- RESOLUÇÃO DO TIPO DE CARGA (Seca, Líquida, Contêiner, Ilegal, Caixas Manuais ou Paleteira)
    local cargoType = contractData.cargoType
    if not cargoType or (cargoType ~= 'dry' and cargoType ~= 'liquid' and cargoType ~= 'container' and cargoType ~= 'illegal' and cargoType ~= 'manual_boxes' and cargoType ~= 'pallet_jack') then
        local tModel = string.lower(contractData.trailerModel or '')
        local cName = string.lower(contractData.name or '')
        if string.find(cName, 'caixa') or string.find(cName, 'manual') or string.find(cName, 'fracionad') or string.find(cName, 'encomenda') then
            cargoType = 'manual_boxes'
        elseif string.find(cName, 'paleteira') or string.find(cName, 'jack') then
            cargoType = 'pallet_jack'
        elseif tModel == 'tanker' or tModel == 'tanker2' or tModel == 'armytanker' or string.find(tModel, 'tanker') or string.find(cName, 'tanque') or string.find(cName, 'combust') or string.find(cName, 'oleo') or string.find(cName, 'óleo') or string.find(cName, 'querosene') or string.find(cName, 'solvente') then
            cargoType = 'liquid'
        elseif string.find(tModel, 'contr') or string.find(cName, 'conteiner') or string.find(cName, 'contêiner') or string.find(cName, 'container') or string.find(cName, 'heavy') then
            cargoType = 'container'
        elseif string.find(cName, 'ilegal') or string.find(cName, 'clandestin') or string.find(cName, 'contrabando') then
            cargoType = 'illegal'
        else
            cargoType = 'dry'
        end
    end

    local typeConfig = Config.CargoTypes and Config.CargoTypes[cargoType]
    if not typeConfig then typeConfig = Config.CargoTypes.dry end

    -- Módulo 2: Trava/Desbloqueio por XP e Nível de Carreira (Tycoon Progression)
    local truckerRow = MySQL.single.await('SELECT level FROM `0r_trucker` WHERE `citizenid` = ?', { citizenId })
    local playerLevel = (truckerRow and truckerRow.level) or 1
    local minLevel = (typeConfig and typeConfig.minLevel) or 1
    if playerLevel < minLevel then
        TriggerClientEvent('aurp_trucker:notify', src, 'Nível Insuficiente', ('Você precisa de Nível %d de Caminhoneiro para aceitar este frete! (Seu nível atual: %d)'):format(minLevel, playerLevel), 'error')
        return
    end

    -- Módulo 3: Validação Noturna e Heat para Mercado Ilegal
    local playerHeat = 0
    if cargoType == 'illegal' then
        local hour = GetClockHours()
        local nightCfg = (Config.CargoTypes.illegal and Config.CargoTypes.illegal.nightHours) or { start = 22, finish = 4 }
        local isNight = (hour >= nightCfg.start or hour < nightCfg.finish)
        if not isNight then
            TriggerClientEvent('aurp_trucker:notify', src, 'Mercado Ilegal Fechado', ('Cargas clandestinas operam exclusivamente entre %02d:00 e %02d:00! Hora atual: %02d:00.'):format(nightCfg.start, nightCfg.finish, hour), 'error')
            return
        end

        local heatRow = MySQL.single.await('SELECT heat FROM `0r_trucker` WHERE `citizenid` = ?', { citizenId })
        playerHeat = (heatRow and heatRow.heat) or 0
    end

    local requestedTrailer = contractData.trailerModel or typeConfig.defaultTrailer
    local trailerModel = joaat(requestedTrailer)

    -- Validação autoritativa do modelo da carreta contra a lista permitida
    local isAllowedTrailer = false
    if typeConfig.allowedTrailers then
        for _, allowedHash in ipairs(typeConfig.allowedTrailers) do
            if trailerModel == allowedHash then
                isAllowedTrailer = true
                break
            end
        end
    end

    if not isAllowedTrailer then
        trailerModel = joaat(typeConfig.defaultTrailer or (cargoType == 'liquid' and 'tanker' or 'trflat'))
    end


    -- STEP A: SPAWN AND PLATE ENFORCEMENT
    local plate = selectedPlate
    if not plate or plate == '' then
        plate = ("TRK%04d"):format(math.random(1000, 9999))
    end

    -- Iteração dinâmica com verificação de área livre no servidor (OneSync)
    local truckSpawns = wh.TruckSpawns or { wh.TruckSpawnCoords }
    local truck = nil
    local chosenTruckCoord = nil

    for _, coord in ipairs(truckSpawns) do
        if IsSpawnPointClear(coord, 8.0) then
            truck = CreateVehicle(truckModel, coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(truck) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
            if DoesEntityExist(truck) then
                chosenTruckCoord = coord
                break
            end
        end
    end

    if not truck or not DoesEntityExist(truck) then
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Todas as vagas de caminhão estão ocupadas ou bloqueadas no momento! Desobstrua a área e tente novamente.', 'error')
        return
    end

    SetEntityDistanceCullingRadius(truck, 400.0)
    SetVehicleNumberPlateText(truck, plate)

    -- Caminhão spawna destrancado e pronto para condução (inspeção removida)
    SetVehicleDoorsLocked(truck, 1)

    -- ENTREGA IMEDIATA DE CHAVES DO CAMINHÃO (ox_inventory + qbx_vehiclekeys)
    if exports.ox_inventory then
        local keyMetadata = {
            plate = plate,
            description = "Chave do Veículo - " .. plate
        }
        local added = exports.ox_inventory:AddItem(src, 'keys', 1, keyMetadata)
        if not added then
            exports.ox_inventory:AddItem(src, 'vehiclekey', 1, keyMetadata)
        end
    end
    if exports['qbx_vehiclekeys'] then
        pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, truck) end)
    end
    if exports['qb-vehiclekeys'] then
        pcall(function() exports['qb-vehiclekeys']:GiveKeys(src, plate) end)
    end
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, plate)

    print(("[AUST_Trucker] Vehicle spawned unlocked with plate: %s for player %s (Cargo: %s)"):format(plate, tostring(src), cargoType))

    -- STEP B: TRAILER SPAWN
    local trailerSpawns = Config.TrailerSpawns or (wh and wh.TrailerSpawns) or { wh.TrailerSpawnCoords }
    local trailer = nil
    local chosenTrailerCoord = nil

    for _, coord in ipairs(trailerSpawns) do
        if IsSpawnPointClear(coord, 9.0, { [truck] = true }) then
            trailer = CreateVehicle(trailerModel, coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(trailer) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
            if DoesEntityExist(trailer) then
                chosenTrailerCoord = coord
                break
            end
        end
    end

    if not trailer or not DoesEntityExist(trailer) then
        if DoesEntityExist(truck) then DeleteEntity(truck) end
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Todas as vagas de carreta/reboque estão ocupadas no momento! Tente novamente em instantes.', 'error')
        return
    end

    SetEntityDistanceCullingRadius(trailer, 400.0)
    SetVehicleDoorsLocked(trailer, 1)

    -- ETAPA 3: Spawn Condicional (Empilhadeira/Paletes para Carga Seca/Ilegal, Handler/Container para Contêiner)
    local forklift = nil
    local forkliftPlate = nil
    local chosenForkliftCoord = nil
    local pallets = {}
    local palletNetIds = {}
    local reqPallets = contractData.palletCount or 4

    local handler = nil
    local handlerPlate = nil
    local containerObj = nil

    if cargoType == 'manual_boxes' then
        reqPallets = 6
        local staging = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.LoadingStaging) or vector3(1243.50, -3168.20, 5.50)
        local boxModel = joaat((Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.PropModel) or 'prop_cardbordbox_02a')
        for i = 1, reqPallets do
            local offsetX = ((i - 1) % 3) * 0.75
            local offsetY = math.floor((i - 1) / 3) * 0.75
            local bObj = CreateObject(boxModel, staging.x + offsetX, staging.y + offsetY, staging.z + 0.1, true, true, false)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(bObj) and (GetGameTimer() - waitTimer < 3000) do Wait(20) end
            if DoesEntityExist(bObj) then
                SetEntityDistanceCullingRadius(bObj, 350.0)
                FreezeEntityPosition(bObj, true)
                table.insert(pallets, bObj)
                table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(bObj))
            end
        end
    elseif cargoType == 'pallet_jack' then
        reqPallets = 4
        local staging = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.LoadingStaging) or vector3(1243.50, -3168.20, 5.50)
        local pjModel = joaat((Config.EarlyGame and Config.EarlyGame.PalletJack and Config.EarlyGame.PalletJack.PropModel) or 'prop_pallet_jack_01')
        local pjObj = CreateObject(pjModel, staging.x - 2.5, staging.y, staging.z + 0.1, true, true, false)
        local waitPJ = GetGameTimer()
        while not DoesEntityExist(pjObj) and (GetGameTimer() - waitPJ < 3000) do Wait(20) end
        if DoesEntityExist(pjObj) then
            SetEntityDistanceCullingRadius(pjObj, 350.0)
            FreezeEntityPosition(pjObj, true)
            table.insert(pallets, pjObj)
            table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pjObj))
        end
        for i = 1, reqPallets do
            local pModel = joaat(Config.Polarix.PalletModels[(i % #Config.Polarix.PalletModels) + 1] or Config.Polarix.DefaultPalletModel)
            local pObj = CreateObject(pModel, staging.x + (i * 1.5), staging.y + 2.5, staging.z + 0.1, true, true, false)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 3000) do Wait(20) end
            if DoesEntityExist(pObj) then
                SetEntityDistanceCullingRadius(pObj, 350.0)
                FreezeEntityPosition(pObj, true)
                table.insert(pallets, pObj)
                table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pObj))
            end
        end
    elseif cargoType == 'dry' or cargoType == 'illegal' then
        local forkliftSpawns = wh.ForkliftSpawns or { wh.ForkliftBayCoords }

        for _, coord in ipairs(forkliftSpawns) do
            if IsSpawnPointClear(coord, 4.0, { [truck] = true, [trailer] = true }) then
                forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(forklift) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
                if DoesEntityExist(forklift) then
                    chosenForkliftCoord = coord
                    break
                end
            end
        end

        if not forklift or not DoesEntityExist(forklift) then
            if DoesEntityExist(trailer) then DeleteEntity(trailer) end
            if DoesEntityExist(truck) then DeleteEntity(truck) end
            TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Todas as vagas de empilhadeira estão ocupadas no momento! Desobstrua a área e tente novamente.', 'error')
            return
        end

        SetEntityDistanceCullingRadius(forklift, 350.0)

        -- Placa, destrancamento e chaves imediatas da empilhadeira
        forkliftPlate = ("FORK%04d"):format(math.random(1000, 9999))
        SetVehicleNumberPlateText(forklift, forkliftPlate)
        SetVehicleDoorsLocked(forklift, 1)

        if exports.ox_inventory then
            local forkKeyMeta = {
                plate = forkliftPlate,
                description = "Chave da Empilhadeira - " .. forkliftPlate
            }
            local added = exports.ox_inventory:AddItem(src, 'keys', 1, forkKeyMeta)
            if not added then
                exports.ox_inventory:AddItem(src, 'vehiclekey', 1, forkKeyMeta)
            end
        end
        if exports['qbx_vehiclekeys'] then
            pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, forklift) end)
        end
        if exports['qb-vehiclekeys'] then
            pcall(function() exports['qb-vehiclekeys']:GiveKeys(src, forkliftPlate) end)
        end
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, forkliftPlate)
        TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, forkliftPlate)

        -- Spawn Dinâmico e Iterativo de Paletes Polarix com Fixação Física (Zero Limbo)
        local palletSpawns = wh.PalletSpawns or {}
        local ignoreEntities = { [truck] = true, [trailer] = true, [forklift] = true }

        for _, coord in ipairs(palletSpawns) do
            if #pallets >= reqPallets then break end
            if IsSpawnPointClear(coord, 2.5, ignoreEntities) then
                local pModel = joaat(Config.Polarix.PalletModels[(#pallets % #Config.Polarix.PalletModels) + 1] or Config.Polarix.DefaultPalletModel)
                local pObj = CreateObject(pModel, coord.x, coord.y, coord.z + 0.1, true, true, false)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
                if DoesEntityExist(pObj) then
                    SetEntityDistanceCullingRadius(pObj, 350.0)
                    FreezeEntityPosition(pObj, true)
                    ignoreEntities[pObj] = true
                    table.insert(pallets, pObj)
                    table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pObj))
                end
            end
        end

        -- Se a quantidade necessária de paletes for maior que os slots individuais livres, utiliza fallback seguro
        if #pallets < reqPallets and wh.PalletStagingAnchor then
            local anchor = wh.PalletStagingAnchor
            local rad = math.rad(wh.PalletStagingHeading or 180.0)
            local rowDir = vector3(math.cos(rad), math.sin(rad), 0.0)
            local colDir = vector3(-math.sin(rad), math.cos(rad), 0.0)

            for i = #pallets + 1, reqPallets do
                local col = (i - 1) % 3
                local row = math.floor((i - 1) / 3)
                local pos = anchor + rowDir * (col * 2.2) + colDir * (row * 2.2)

                if IsSpawnPointClear(pos, 2.0, ignoreEntities) then
                    local pModel = joaat(Config.Polarix.PalletModels[(i % #Config.Polarix.PalletModels) + 1] or Config.Polarix.DefaultPalletModel)
                    local pObj = CreateObject(pModel, pos.x, pos.y, pos.z + 0.1, true, true, false)
                    local waitTimer = GetGameTimer()
                    while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
                    if DoesEntityExist(pObj) then
                        SetEntityDistanceCullingRadius(pObj, 350.0)
                        FreezeEntityPosition(pObj, true)
                        ignoreEntities[pObj] = true
                        table.insert(pallets, pObj)
                        table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pObj))
                    end
                end
            end
        end

        if #pallets < reqPallets then
            for _, p in ipairs(pallets) do if DoesEntityExist(p) then DeleteEntity(p) end end
            if DoesEntityExist(forklift) then DeleteEntity(forklift) end
            if DoesEntityExist(trailer) then DeleteEntity(trailer) end
            if DoesEntityExist(truck) then DeleteEntity(truck) end
            TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'A área de paletes está obstruída no momento! Desobstrua a zona de carga e tente novamente.', 'error')
            return
        end
    elseif cargoType == 'container' then
        -- MÓDULO 2: Spawn de Handler Reach Stacker e Contêiner
        local handlerBay = wh.HandlerBayCoords or vector4(1240.20, -3195.10, 5.88, 270.00)
        local hModel = joaat(Config.CargoTypes.container.handlerModel or 'handler')
        handler = CreateVehicle(hModel, handlerBay.x, handlerBay.y, handlerBay.z + 0.5, handlerBay.w or 270.0, true, true)
        local waitH = GetGameTimer()
        while not DoesEntityExist(handler) and (GetGameTimer() - waitH < 5000) do Wait(10) end

        if not handler or not DoesEntityExist(handler) then
            if DoesEntityExist(trailer) then DeleteEntity(trailer) end
            if DoesEntityExist(truck) then DeleteEntity(truck) end
            TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'A vaga do Handler está ocupada! Desobstrua a área e tente novamente.', 'error')
            return
        end

        SetEntityDistanceCullingRadius(handler, 350.0)
        handlerPlate = ("HNDL%04d"):format(math.random(1000, 9999))
        SetVehicleNumberPlateText(handler, handlerPlate)
        SetVehicleDoorsLocked(handler, 1)

        if exports.ox_inventory then
            local hKeyMeta = { plate = handlerPlate, description = "Chave do Handler - " .. handlerPlate }
            local added = exports.ox_inventory:AddItem(src, 'keys', 1, hKeyMeta)
            if not added then exports.ox_inventory:AddItem(src, 'vehiclekey', 1, hKeyMeta) end
        end
        if exports['qbx_vehiclekeys'] then pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, handler) end) end
        if exports['qb-vehiclekeys'] then pcall(function() exports['qb-vehiclekeys']:GiveKeys(src, handlerPlate) end) end
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, handlerPlate)
        TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, handlerPlate)

        -- Spawn do prop de contêiner
        local contCoord = Config.ContainerSpawnCoord or vector4(1230.50, -3183.20, 5.00, 90.0)
        local cModel = joaat(Config.CargoTypes.container.containerModel or 'prop_contr_03b_ld')
        containerObj = CreateObject(cModel, contCoord.x, contCoord.y, contCoord.z + 0.1, true, true, false)
        local waitC = GetGameTimer()
        while not DoesEntityExist(containerObj) and (GetGameTimer() - waitC < 5000) do Wait(50) end

        if DoesEntityExist(containerObj) then
            SetEntityDistanceCullingRadius(containerObj, 350.0)
            FreezeEntityPosition(containerObj, true)
        end
    else
        reqPallets = 100 -- Carga Líquida: 100% de capacidade do tanque
    end

    -- Seleção inteligente de destino correspondente ao tipo de cargo
    local matchingDests = {}
    for _, d in ipairs(Config.Polarix.DeliveryDestinations) do
        if not d.cargoType or d.cargoType == cargoType then
            table.insert(matchingDests, d)
        end
    end
    local destCfg = (#matchingDests > 0) and matchingDests[math.random(#matchingDests)] or Config.Polarix.DeliveryDestinations[math.random(#Config.Polarix.DeliveryDestinations)]
    local destCoords = destCfg.coords

    local basePayment = destCfg.reward or 5000
    if cargoType == 'illegal' then
        local mult = (Config.CargoTypes.illegal and Config.CargoTypes.illegal.rewardMultiplier) or 2.5
        basePayment = math.floor(basePayment * mult)
    end

    -- Identificação de membros da Crew para Multiplayer Co-op (Fase 2)
    local crewId = PlayerTruckerCrew[citizenId]
    local crewMembers = {}
    if crewId and TruckerCrews[crewId] then
        local crew = TruckerCrews[crewId]
        for mCid, mData in pairs(crew.members) do
            if mData.src and GetPlayerPing(mData.src) > 0 then
                table.insert(crewMembers, { citizenId = mCid, src = mData.src, name = mData.name })
            end
        end
    end
    if #crewMembers == 0 then
        table.insert(crewMembers, { citizenId = citizenId, src = src, name = GetCharName(src) })
    end

    local cargoLabel = contractData.name or (
        cargoType == 'manual_boxes' and 'Carga Fracionada de Caixas' or (
        cargoType == 'pallet_jack' and 'Lotes de Paleteira Manual' or (
        cargoType == 'liquid' and 'Combustível Automotivo' or (
        cargoType == 'container' and 'Contêiner Industrial Heavy Lift' or (
        cargoType == 'illegal' and 'Carga Clandestina (Mercado Ilegal)' or 'Paletes Industriais')))))

    local lobbyData = {
        jobId = jobId,
        src = src,
        citizenId = citizenId,
        crewId = crewId,
        crewMembers = crewMembers,
        bucketId = bucketId,
        cargoType = cargoType,
        truck = truck,
        truckPlate = plate,
        truckModel = selectedTruckModel,
        isOwned = isOwned,
        trailer = trailer,
        forklift = forklift,
        forkliftPlate = forkliftPlate,
        handler = handler,
        handlerPlate = handlerPlate,
        container = containerObj,
        pallets = pallets,
        palletNetIds = palletNetIds,
        loadedCount = 0,
        requiredCount = reqPallets,
        cargoName = cargoLabel,
        payment = basePayment,
        xp = destCfg.xp or 200,
        deliveryCoords = destCoords,
        stage = 'STEP_GET_TRUCK',
        cargoHealth = 100,
        playerHeat = playerHeat,
        current_object = nil,
        hoseProp = nil,
        hoseConnected = false,
        twistlocksLocked = 0,
        policeVehicles = {},
        policePeds = {}
    }

    PolarixLobbies[jobId] = lobbyData
    PlayerPolarixLobbies[citizenId] = jobId

    local payload = {
        jobId = jobId,
        cargoType = cargoType,
        stage = 'STEP_GET_TRUCK',
        truckNetId = NetworkGetNetworkIdFromEntity(truck),
        truckCoords = chosenTruckCoord and vector3(chosenTruckCoord.x, chosenTruckCoord.y, chosenTruckCoord.z),
        truckPlate = plate,
        truckModel = selectedTruckModel,
        truckMods = savedMods,
        isOwned = isOwned,
        trailerNetId = NetworkGetNetworkIdFromEntity(trailer),
        trailerCoords = chosenTrailerCoord and vector3(chosenTrailerCoord.x, chosenTrailerCoord.y, chosenTrailerCoord.z),
        forkliftNetId = forklift and DoesEntityExist(forklift) and NetworkGetNetworkIdFromEntity(forklift) or 0,
        forkliftCoords = chosenForkliftCoord and vector3(chosenForkliftCoord.x, chosenForkliftCoord.y, chosenForkliftCoord.z),
        forkliftPlate = forkliftPlate,
        handlerNetId = handler and DoesEntityExist(handler) and NetworkGetNetworkIdFromEntity(handler) or 0,
        handlerPlate = handlerPlate,
        containerNetId = containerObj and DoesEntityExist(containerObj) and NetworkGetNetworkIdFromEntity(containerObj) or 0,
        palletNetIds = palletNetIds,
        cargoName = lobbyData.cargoName,
        requiredCount = reqPallets,
        loadedCount = 0,
        deliveryCoords = destCoords,
        playerHeat = playerHeat,
        isCrew = (#crewMembers > 1),
        crewCount = #crewMembers
    }

    print(("[AUST_Trucker] Dispatching polarixJobStarted to %d player(s) for job %s (Truck: %s, Cargo: %s)"):format(
        #crewMembers, tostring(jobId), tostring(payload.truckNetId), cargoType
    ))

    -- Sincronização Server-Authoritative para todos os membros da Crew
    for _, member in ipairs(crewMembers) do
        if member.src and GetPlayerPing(member.src) > 0 then
            PlayerPolarixLobbies[member.citizenId] = jobId
            TriggerClientEvent('aurp_trucker:client:polarixJobStarted', member.src, payload)
            TriggerClientEvent('aurp_trucker:client:polarixSyncPallets', member.src, palletNetIds)
            if member.src ~= src then
                TriggerClientEvent('aurp_trucker:notify', member.src, 'Equipe de Transporte', ('O líder %s iniciou o frete: %s! Dirija-se aos veículos.'):format(GetCharName(src), payload.cargoName), 'info')
            end
        end
    end
end

function GlobalStartTruckDelivery(src, contractData)
    StartTruckDelivery(src, contractData)
end

RegisterNetEvent('aurp_trucker:server:startDelivery', function(contractData)
    StartTruckDelivery(source, contractData)
end)

-- ETAPA 2: Validação de Inspeção Concluída e Liberação de Chaves QBox (Caminhão e Empilhadeira)
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

    -- Destranca portas do caminhão no servidor
    SetVehicleDoorsLocked(lobby.truck, 1)

    -- ENTREGA AUTORITATIVA DE CHAVES DO CAMINHÃO (ox_inventory + qbx_vehiclekeys)
    if exports.ox_inventory then
        local keyMetadata = {
            plate = lobby.truckPlate,
            description = "Truck Key - " .. lobby.truckPlate
        }
        local added = exports.ox_inventory:AddItem(src, 'keys', 1, keyMetadata)
        if not added then
            exports.ox_inventory:AddItem(src, 'vehiclekey', 1, keyMetadata)
        end
    end

    if exports['qbx_vehiclekeys'] then
        pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, lobby.truck) end)
    end
    if exports['qb-vehiclekeys'] then
        pcall(function() exports['qb-vehiclekeys']:GiveKeys(src, lobby.truckPlate) end)
    end
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, lobby.truckPlate)
    TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, lobby.truckPlate)

    -- BUG 3 RESOLUTION: ENTREGA AUTORITATIVA DE CHAVES DA EMPILHADEIRA (ox_inventory + qbx_vehiclekeys)
    if lobby.cargoType == 'dry' and lobby.forkliftPlate then
        if exports.ox_inventory then
            local forkKeyMeta = {
                plate = lobby.forkliftPlate,
                description = "Forklift Key - " .. lobby.forkliftPlate
            }
            local added = exports.ox_inventory:AddItem(src, 'keys', 1, forkKeyMeta)
            if not added then
                exports.ox_inventory:AddItem(src, 'vehiclekey', 1, forkKeyMeta)
            end
        end

        if exports['qbx_vehiclekeys'] and lobby.forklift and DoesEntityExist(lobby.forklift) then
            pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, lobby.forklift) end)
        end
        if exports['qb-vehiclekeys'] then
            pcall(function() exports['qb-vehiclekeys']:GiveKeys(src, lobby.forkliftPlate) end)
        end
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, lobby.forkliftPlate)
        TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, lobby.forkliftPlate)
    end

    local truckNetId = NetworkGetNetworkIdFromEntity(lobby.truck)
    TriggerClientEvent('aurp_trucker:client:inspectionUnlocked', src, jobId, lobby.truckPlate, truckNetId, lobby.forkliftPlate)
    TriggerClientEvent('aurp_trucker:client:polarixSyncPallets', src, lobby.palletNetIds)
end)

-- ETAPA 3: Acomodação do Palete na Carreta (Carga Seca)
local function HandlePalletLoaded(src, jobId, slotIndex)
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.stage ~= 'STEP_LOAD_CARGO' and lobby.stage ~= 'STATUS_LOADING' then return end

    lobby.loadedCount = lobby.loadedCount + 1
    lobby.current_object = slotIndex

    TriggerClientEvent('aurp_trucker:client:polarixProgressSync', src, lobby.loadedCount, lobby.requiredCount)
    TriggerClientEvent('aurp_trucker:client:dryProgressSync', src, lobby.loadedCount, lobby.requiredCount)

    if lobby.loadedCount < lobby.requiredCount then
        local forkNetId = (lobby.forklift and DoesEntityExist(lobby.forklift)) and NetworkGetNetworkIdFromEntity(lobby.forklift) or 0
        local forkCoords = (lobby.forklift and DoesEntityExist(lobby.forklift)) and GetEntityCoords(lobby.forklift) or nil
        TriggerClientEvent('aust_trucker:client:SetObjective', src, {
            netId = forkNetId,
            coords = forkCoords,
            label = "Empilhadeira de Carga",
            sprite = 543,
            color = 5,
            offsetZ = 2.5,
            notify = ("Palete acomodado com sucesso! (%d/%d). Continue o carregamento."):format(lobby.loadedCount, lobby.requiredCount)
        })
    else
        lobby.stage = 'STEP_STRAPPING'
        local trailerRearCoords = GetOffsetFromEntityInWorldCoords(lobby.trailer, 0.0, -5.5, 0.0)
        TriggerClientEvent('aust_trucker:client:SetObjective', src, {
            coords = trailerRearCoords,
            label = "Traseira da Carreta (Travar Cintas)",
            sprite = 478,
            color = 5,
            offsetZ = 1.5,
            notify = "Carregamento concluído! Trave as cintas e assine o romaneio na traseira da carreta."
        })
        TriggerClientEvent('aurp_trucker:client:startStrappingStage', src, jobId)
    end
end

RegisterNetEvent('aurp_trucker:server:polarixPalletLoaded', function(jobId, slotIndex)
    HandlePalletLoaded(source, jobId, slotIndex)
end)

RegisterNetEvent('aurp_trucker:server:attachPalletToTrailer', function(jobId, slotIndex)
    HandlePalletLoaded(source, jobId, slotIndex)
end)

-- =======================================================================
-- SISTEMA DE CARGA LÍQUIDA: GERENCIAMENTO DE MANGUEIRA E ABASTECIMENTO
-- =======================================================================

-- 1. Pegar Mangueira na Bomba
RegisterNetEvent('aurp_trucker:server:pickupHose', function(jobId, terminalId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.stage ~= 'STATUS_LOADING' then return end

    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)

    -- Validação de proximidade autoritativa do terminal
    local terminal = nil
    if Config.CargoTypes and Config.CargoTypes.liquid and Config.CargoTypes.liquid.fuelTerminals then
        for _, term in ipairs(Config.CargoTypes.liquid.fuelTerminals) do
            if term.id == terminalId then
                terminal = term
                break
            end
        end
    end

    if terminal and #(pCoords - terminal.coords) > 15.0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Distância', 'Você está muito afastado da bomba para retirar a mangueira!', 'error')
        return
    end

    -- Criação OneSync autoritativa do prop de mangueira no routing bucket do jogador
    local hoseModel = joaat('prop_cs_fuel_nozle')
    local hoseObj = CreateObject(hoseModel, pCoords.x, pCoords.y, pCoords.z, true, true, false)
    while not DoesEntityExist(hoseObj) do Wait(10) end
    SetEntityDistanceCullingRadius(hoseObj, 200.0)

    lobby.hoseProp = hoseObj
    lobby.hoseConnected = false

    local hoseNetId = NetworkGetNetworkIdFromEntity(hoseObj)
    TriggerClientEvent('aurp_trucker:client:hosePickedUp', src, jobId, hoseNetId)
end)

-- 2. Conectar Mangueira na Carreta-Tanque
RegisterNetEvent('aurp_trucker:server:connectHose', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.stage ~= 'STATUS_LOADING' then return end

    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)
    local trailerCoords = GetEntityCoords(lobby.trailer)

    if #(pCoords - trailerCoords) > 12.0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Distância', 'Você está muito distante da carreta para conectar a mangueira!', 'error')
        return
    end

    lobby.hoseConnected = true
    TriggerClientEvent('aurp_trucker:client:hoseConnected', src, jobId)
end)

-- 3. Cancelar Mangueira (ex: Entrada em Veículo)
RegisterNetEvent('aurp_trucker:server:cancelHose', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end
    lobby.hoseProp = nil
    lobby.hoseConnected = false

    TriggerClientEvent('aurp_trucker:client:hoseCancelled', src, jobId)
end)

-- 4. Rompimento de Mangueira e Vazamento (Distância > 9.0m)
RegisterNetEvent('aurp_trucker:server:hoseLeak', function(jobId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end

    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end
    lobby.hoseProp = nil
    lobby.hoseConnected = false

    local penalty = (Config.CargoTypes and Config.CargoTypes.liquid and Config.CargoTypes.liquid.leakPenalty) or 1500
    if exports.qbx_core then
        exports.qbx_core:RemoveMoney(src, 'bank', penalty, 'trucker-hose-leak')
    else
        Framework.RemoveMoney(Player, 'bank', penalty, 'trucker-hose-leak')
    end

    TriggerClientEvent('aurp_trucker:client:playLeakPtfx', src, jobId, penalty)
end)

-- 5. Desconectar Mangueira e Finalizar Carregamento Líquido
RegisterNetEvent('aurp_trucker:server:disconnectHose', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)
    local trailerCoords = GetEntityCoords(lobby.trailer)

    if #(pCoords - trailerCoords) > 10.0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Distância', 'Aproxime-se da carreta para desconectar a mangueira com segurança!', 'error')
        return
    end

    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end
    lobby.hoseProp = nil
    lobby.hoseConnected = false

    lobby.stage = 'STATUS_IN_TRANSIT'
    lobby.loadedCount = 100

    TriggerClientEvent('aurp_trucker:client:liquidLoadingCompleted', src, jobId, lobby.deliveryCoords)
    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA 4: Validação de Cintas e Liberação de Rota GPS (Carga Seca)
RegisterNetEvent('aurp_trucker:server:strappingCompleted', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.loadedCount < lobby.requiredCount then return end

    lobby.stage = 'STATUS_IN_TRANSIT'

    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA: Notificação de Palete Perdido durante a Viagem (Corda Rompida)
RegisterNetEvent('aurp_trucker:server:palletLost', function(jobId, palletNetId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    lobby.lostPallets = (lobby.lostPallets or 0) + 1
    print(("[AUST_Trucker] Palete perdido em rota para o frete %s (Player: %s)! Total de perdas: %d"):format(
        tostring(jobId), tostring(src), lobby.lostPallets
    ))
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

    -- Pagamento com cálculo de penalidade proporcional por paletes perdidos
    local basePayment = lobby.payment or 5000
    local baseXP = lobby.xp or 200
    local totalReq = lobby.requiredCount or 4
    local lostCount = lobby.lostPallets or 0
    local deliveredCount = math.max(0, totalReq - lostCount)
    local ratio = (lobby.cargoType == 'dry' and totalReq > 0) and math.max(0.2, deliveredCount / totalReq) or 1.0

    -- Módulo 1: Payout proporcional à integridade da carga (CargoHealth)
    local healthRatio = math.max(0.0, (lobby.cargoHealth or 100) / 100.0)
    local payment = math.floor(basePayment * ratio * healthRatio)
    local xp = math.floor(baseXP * ratio)

    local activeCrew = {}
    if lobby.crewMembers and #lobby.crewMembers > 1 then
        for _, m in ipairs(lobby.crewMembers) do
            if m.src and GetPlayerPing(m.src) > 0 then
                table.insert(activeCrew, m)
            end
        end
    end

    local isCrewDelivery = (#activeCrew > 1)
    local bonusPercent = (Config.Crew and Config.Crew.SharedPayoutBonusPercent) or 0.15
    local finalPayment = payment
    local finalXP = xp

    if isCrewDelivery then
        -- Bônus de 15% cooperativo total distribuído igualmente entre membros online
        local totalBonusPayment = math.floor(payment * (1.0 + bonusPercent))
        local totalBonusXP = math.floor(xp * (1.0 + bonusPercent))
        finalPayment = math.floor(totalBonusPayment / #activeCrew)
        finalXP = math.floor(totalBonusXP / #activeCrew)

        for _, m in ipairs(activeCrew) do
            local mPlayer = Framework.GetPlayer(m.src)
            if mPlayer then
                if exports.qbx_core then
                    exports.qbx_core:AddMoney(m.src, 'bank', finalPayment, 'trucker-crew-job')
                else
                    Framework.AddMoney(mPlayer, 'bank', finalPayment, 'trucker-crew-job')
                end

                pcall(function()
                    MySQL.query.await([[
                        INSERT INTO 0r_trucker (citizenid, level, xp, total_deliveries, total_earned)
                        VALUES (?, 1, ?, 1, ?)
                        ON DUPLICATE KEY UPDATE
                            xp = xp + VALUES(xp),
                            total_deliveries = total_deliveries + 1,
                            total_earned = total_earned + VALUES(total_earned),
                            level = FLOOR(1 + (xp / 1000))
                    ]], { m.citizenId, finalXP, finalPayment })
                end)

                pcall(DB_UpdateAustTruckerStats, m.citizenId, finalXP, 1)

                TriggerClientEvent('aust_trucker:client:ClearObjective', m.src)
                TriggerClientEvent('aurp_trucker:client:polarixJobFinished', m.src, {
                    payment = finalPayment,
                    xp = finalXP,
                    lostPallets = lostCount,
                    deliveredPallets = deliveredCount,
                    cargoHealth = lobby.cargoHealth or 100,
                    distance = 3.5,
                    isCrew = true,
                    crewCount = #activeCrew
                })
                PlayerPolarixLobbies[m.citizenId] = nil
            end
        end
    else
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

        TriggerClientEvent('aust_trucker:client:ClearObjective', src)
        TriggerClientEvent('aurp_trucker:client:polarixJobFinished', src, {
            payment = payment,
            xp = xp,
            lostPallets = lostCount,
            deliveredPallets = deliveredCount,
            cargoHealth = lobby.cargoHealth or 100,
            distance = 3.5
        })
        PlayerPolarixLobbies[citizenId] = nil
    end

    -- Módulo 3: Ganho de Heat (+15) para frete do Mercado Ilegal bem-sucedido
    if lobby.cargoType == 'illegal' then
        local heatReward = (Config.CargoTypes.illegal and Config.CargoTypes.illegal.heatReward) or 15
        pcall(function()
            MySQL.query.await('UPDATE `0r_trucker` SET `heat` = `heat` + ? WHERE `citizenid` = ?', { heatReward, citizenId })
            MySQL.query.await('UPDATE `players` SET `trucker_heat` = `trucker_heat` + ? WHERE `citizenid` = ?', { heatReward, citizenId })
        end)
    end

    -- STEP C: DUAL-LAYER KEY REMOVAL (TRUCK, FORKLIFT & HANDLER)
    local platesToRemove = {}
    local truckPlate = lobby.truckPlate or (lobby.truck and DoesEntityExist(lobby.truck) and GetVehicleNumberPlateText(lobby.truck))
    if truckPlate then table.insert(platesToRemove, { plate = truckPlate, entity = lobby.truck }) end
    if lobby.forkliftPlate then table.insert(platesToRemove, { plate = lobby.forkliftPlate, entity = lobby.forklift }) end
    if lobby.handlerPlate then table.insert(platesToRemove, { plate = lobby.handlerPlate, entity = lobby.handler }) end

    for _, pData in ipairs(platesToRemove) do
        local targetPlate = pData.plate
        print(("[AUST_Trucker] Removing key for plate: %s (Player: %s)"):format(targetPlate, tostring(src)))

        -- 1st Layer: Physical item removal via ox_inventory
        if exports.ox_inventory then
            local removed = exports.ox_inventory:RemoveItem(src, 'keys', 1, { plate = targetPlate })
            if not removed then
                exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, { plate = targetPlate })
            end

            -- Varredura por slots para assegurar limpeza completa de itens com a placa
            local slots = exports.ox_inventory:GetSlotsWithItem(src, 'keys') or {}
            for _, slotData in ipairs(slots) do
                if slotData.metadata and slotData.metadata.plate == targetPlate then
                    exports.ox_inventory:RemoveItem(src, 'keys', 1, nil, slotData.slot)
                end
            end
            local vehKeySlots = exports.ox_inventory:GetSlotsWithItem(src, 'vehiclekey') or {}
            for _, slotData in ipairs(vehKeySlots) do
                if slotData.metadata and slotData.metadata.plate == targetPlate then
                    exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, nil, slotData.slot)
                end
            end
        end

        -- 2nd Layer: Framework permission removal (qbx_vehiclekeys & qb-vehiclekeys)
        if exports['qbx_vehiclekeys'] and pData.entity and DoesEntityExist(pData.entity) then
            pcall(function() exports['qbx_vehiclekeys']:RemoveKeys(src, pData.entity) end)
        end
        if exports['qb-vehiclekeys'] then
            pcall(function() exports['qb-vehiclekeys']:RemoveKeys(src, targetPlate) end)
        end
    end

    -- Limpeza completa autoritativa de entidades do frete
    CleanupLobbyEntities(lobby)

    PolarixLobbies[jobId] = nil
end)

-- MÓDULO 1: Atualização e Sincronização de Dano da Carga (CargoHealth)
RegisterNetEvent('aurp_trucker:server:updateCargoHealth', function(jobId, health)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    lobby.cargoHealth = math.max(0, math.min(100, tonumber(health) or 100))
end)

-- MÓDULO 1: Carga 100% Destruída (Falha Crítica Fail-Closed)
RegisterNetEvent('aurp_trucker:server:cargoDestroyed', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    CleanupLobbyEntities(lobby)
    if lobby.citizenId then PlayerPolarixLobbies[lobby.citizenId] = nil end
    PolarixLobbies[jobId] = nil

    TriggerClientEvent('aust_trucker:client:ClearObjective', src)
    TriggerClientEvent('aurp_trucker:notify', src, 'Carga Destruída', 'A carga foi totalmente destruída pelos impactos! O frete foi cancelado sem pagamento.', 'error')
end)

-- MÓDULO 3: Mecânica "Lavar a Ficha" (Redução de Heat com Dinheiro Sujo)
RegisterNetEvent('aurp_trucker:server:washHeat', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local row = MySQL.single.await('SELECT heat FROM `0r_trucker` WHERE `citizenid` = ?', { citizenId })
    local heat = (row and row.heat) or 0

    if heat <= 0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Ficha Limpa', 'Você não possui Heat acumulado com as autoridades.', 'info')
        return
    end

    local costPerHeat = (Config.CargoTypes.illegal and Config.CargoTypes.illegal.washCleanCostPerHeat) or 250
    local totalCost = heat * costPerHeat

    local hasPaid = false
    if exports.ox_inventory then
        local count = exports.ox_inventory:GetItemCount(src, 'black_money') or 0
        if count >= totalCost then
            local removed = exports.ox_inventory:RemoveItem(src, 'black_money', totalCost)
            if removed then hasPaid = true end
        end
    end

    if not hasPaid then
        TriggerClientEvent('aurp_trucker:notify', src, 'Dinheiro Insuficiente', ('Você precisa de $%d em dinheiro sujo (black_money) para lavar sua ficha criminal!'):format(totalCost), 'error')
        return
    end

    MySQL.query.await('UPDATE `0r_trucker` SET `heat` = 0 WHERE `citizenid` = ?', { citizenId })
    MySQL.query.await('UPDATE `players` SET `trucker_heat` = 0 WHERE `citizenid` = ?', { citizenId })

    TriggerClientEvent('aurp_trucker:notify', src, 'Ficha Lavada', ('Ficha criminal limpa! Seu Heat policial foi zerado por $%d em dinheiro sujo.'):format(totalCost), 'success')
end)

-- MÓDULO 3: Disparo de Perseguição Policial NPC Ativa (Heat > 50)
RegisterNetEvent('aurp_trucker:server:triggerPolicePursuit', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.pursuitSpawned then return end
    lobby.pursuitSpawned = true

    local truckCoords = (lobby.truck and DoesEntityExist(lobby.truck)) and GetEntityCoords(lobby.truck) or nil
    if not truckCoords then return end

    local pModels = { 'police', 'police2', 'police3' }
    local copVehicles = {}
    local copPeds = {}
    local copNetIds = {}

    for i = 1, 2 do
        local offset = vector3(math.random(-25, 25), math.random(-45, -25), 0.0)
        local spawnPos = truckCoords + offset
        local vehHash = joaat(pModels[math.random(#pModels)])
        local pedHash = joaat('s_m_y_cop_01')

        local pVeh = CreateVehicle(vehHash, spawnPos.x, spawnPos.y, spawnPos.z + 1.0, 0.0, true, true)
        local timer = GetGameTimer()
        while not DoesEntityExist(pVeh) and (GetGameTimer() - timer < 3000) do Wait(10) end

        if DoesEntityExist(pVeh) then
            SetVehicleSiren(pVeh, true)
            local pPed = CreatePedInsideVehicle(pVeh, 6, pedHash, -1, true, true)
            local pTimer = GetGameTimer()
            while not DoesEntityExist(pPed) and (GetGameTimer() - pTimer < 3000) do Wait(10) end

            table.insert(copVehicles, pVeh)
            table.insert(copPeds, pPed)
            table.insert(copNetIds, {
                vehNetId = NetworkGetNetworkIdFromEntity(pVeh),
                pedNetId = NetworkGetNetworkIdFromEntity(pPed)
            })
        end
    end

    lobby.policeVehicles = copVehicles
    lobby.policePeds = copPeds

    TriggerClientEvent('aurp_trucker:client:startPolicePursuit', src, copNetIds)
end)

-- MÓDULO 4: Salvar Nova Rota Criada Dinamicamente em data/routes.json
RegisterNetEvent('aurp_trucker:server:saveNewRoute', function(routeData)
    local src = source
    if not routeData or not routeData.label or not routeData.coords then return end

    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/routes.json')
    local routes = {}
    if raw and raw ~= '' then
        local success, decoded = pcall(json.decode, raw)
        if success and type(decoded) == 'table' then
            routes = decoded
        end
    end

    local newEntry = {
        id = routeData.id or ('route_' .. math.random(1000, 9999)),
        label = routeData.label,
        cargoType = routeData.cargoType or 'dry',
        coords = {
            x = math.floor(routeData.coords.x * 100) / 100,
            y = math.floor(routeData.coords.y * 100) / 100,
            z = math.floor(routeData.coords.z * 100) / 100,
            w = math.floor((routeData.coords.w or 0.0) * 100) / 100
        },
        distance = routeData.distance or 8.0,
        reward = routeData.reward or 7000,
        xp = routeData.xp or 250
    }

    table.insert(routes, newEntry)
    SaveResourceFile(GetCurrentResourceName(), 'data/routes.json', json.encode(routes, { indent = true }), -1)

    -- Inclusão em tempo real na memória do servidor
    Config.Polarix = Config.Polarix or {}
    Config.Polarix.DeliveryDestinations = Config.Polarix.DeliveryDestinations or {}
    table.insert(Config.Polarix.DeliveryDestinations, {
        id = newEntry.id,
        label = newEntry.label,
        cargoType = newEntry.cargoType,
        coords = vector4(newEntry.coords.x, newEntry.coords.y, newEntry.coords.z, newEntry.coords.w or 0.0),
        distance = newEntry.distance,
        reward = newEntry.reward,
        xp = newEntry.xp
    })

    TriggerClientEvent('aurp_trucker:notify', src, 'Rota Salva', ('A rota "%s" foi persistida com sucesso em routes.json!'):format(newEntry.label), 'success')
end)

-- MÓDULO 4: Comando /truckerroute para Administradores
if lib and lib.addCommand then
    lib.addCommand('truckerroute', {
        help = 'Criador de Rotas Logísticas (Admin)',
        restricted = 'group.admin'
    }, function(source, args, raw)
        TriggerClientEvent('aurp_trucker:client:startRouteCreator', source)
    end)
else
    RegisterCommand('truckerroute', function(source, args, raw)
        if source == 0 then return end
        local isAllowed = false
        if exports.qbx_core and exports.qbx_core.HasPermission then
            isAllowed = exports.qbx_core:HasPermission(source, 'admin') or exports.qbx_core:HasPermission(source, 'god')
        elseif IsPlayerAceAllowed(source, 'command') then
            isAllowed = true
        end

        if isAllowed then
            TriggerClientEvent('aurp_trucker:client:startRouteCreator', source)
        else
            TriggerClientEvent('aurp_trucker:notify', source, 'Permissão Negada', 'Apenas administradores podem utilizar o Criador de Rotas.', 'error')
        end
    end, false)
end

-- Reposição de Emergência / Fallback
RegisterNetEvent('aurp_trucker:server:emergencyRespawnEquipment', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    local wh = Config.Polarix.Warehouse
    local forkliftSpawns = wh.ForkliftSpawns or { wh.ForkliftBayCoords }
    local chosenCoord = forkliftSpawns[1]

    for _, coord in ipairs(forkliftSpawns) do
        if IsSpawnPointClear(coord, 3.5, { [lobby.truck] = true, [lobby.trailer] = true }) then
            chosenCoord = coord
            break
        end
    end

    -- Reposiciona ou respawna forklift se necessário
    if lobby.forklift and DoesEntityExist(lobby.forklift) then
        SetEntityCoords(lobby.forklift, chosenCoord.x, chosenCoord.y, chosenCoord.z, false, false, false, true)
    else
        local forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), chosenCoord.x, chosenCoord.y, chosenCoord.z, chosenCoord.w or 90.0, true, true)
        lobby.forklift = forklift
    end

    TriggerClientEvent('aurp_trucker:notify', src, 'Reposição Concluída', 'Empilhadeira restabelecida no pátio com segurança.', 'success')
end)

-- MÓDULO 5: Anti-Combat Log no playerDropped (Multa $2000, +20 Heat e Deleção Segura)
AddEventHandler('playerDropped', function()
    local src = source
    for jobId, lobby in pairs(PolarixLobbies) do
        if lobby.src == src then
            local citizenId = lobby.citizenId

            -- Multa bancária por abandono de carga
            pcall(function()
                if exports.qbx_core then
                    exports.qbx_core:RemoveMoney(src, 'bank', 2000, 'trucker-abandon-penalty')
                end
            end)

            -- Penalidade de +20 Heat se o frete for do mercado ilegal
            if lobby.cargoType == 'illegal' and citizenId then
                pcall(function()
                    MySQL.query.await('UPDATE `0r_trucker` SET `heat` = `heat` + 20 WHERE `citizenid` = ?', { citizenId })
                    MySQL.query.await('UPDATE `players` SET `trucker_heat` = `trucker_heat` + 20 WHERE `citizenid` = ?', { citizenId })
                end)
            end

            CleanupLobbyEntities(lobby)
            if lobby.citizenId then PlayerPolarixLobbies[lobby.citizenId] = nil end
            PolarixLobbies[jobId] = nil
            break
        end
    end
end)

-- Limpeza ao reiniciar ou parar o resource (OneSync Safe Cleanup)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    if PolarixLobbies then
        for _, lobby in pairs(PolarixLobbies) do
            CleanupLobbyEntities(lobby)
        end
        PolarixLobbies = {}
        PlayerPolarixLobbies = {}
    end

    if VP_Trucker and VP_Trucker.PlayerJobEntities then
        for _, data in pairs(VP_Trucker.PlayerJobEntities) do
            if data.truckNetId then
                local ent = NetworkGetEntityFromNetworkId(data.truckNetId)
                if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
            end
            if data.trailerNetId then
                local ent = NetworkGetEntityFromNetworkId(data.trailerNetId)
                if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
            end
        end
        VP_Trucker.PlayerJobEntities = {}
    end
end)

-- =======================================================================
-- FASE 2: MÓDULO 3 - SINCRONIZAÇÃO DE CARREGAMENTO EARLY GAME
-- =======================================================================
RegisterNetEvent('aurp_trucker:server:boxLoaded', function(jobId, boxIndex)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby then return end

    lobby.loadedCount = math.min(lobby.requiredCount or 6, (lobby.loadedCount or 0) + 1)
    local members = lobby.crewMembers or { { src = lobby.src } }
    for _, m in ipairs(members) do
        if m.src and GetPlayerPing(m.src) > 0 then
            TriggerClientEvent('aurp_trucker:client:boxLoadedSync', m.src, lobby.loadedCount, lobby.requiredCount, boxIndex)
        end
    end

    if lobby.loadedCount >= (lobby.requiredCount or 6) then
        lobby.stage = 'STATUS_IN_TRANSIT'
        for _, m in ipairs(members) do
            if m.src and GetPlayerPing(m.src) > 0 then
                TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', m.src, lobby.deliveryCoords)
                TriggerClientEvent('aurp_trucker:notify', m.src, 'Carga Carregada', 'Todas as caixas foram embarcadas com sucesso! Entre no caminhão e siga a rota GPS.', 'success')
            end
        end
    end
end)

RegisterNetEvent('aurp_trucker:server:palletJackBatchLoaded', function(jobId, batchIndex)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby then return end

    lobby.loadedCount = math.min(lobby.requiredCount or 4, (lobby.loadedCount or 0) + 1)
    local members = lobby.crewMembers or { { src = lobby.src } }
    for _, m in ipairs(members) do
        if m.src and GetPlayerPing(m.src) > 0 then
            TriggerClientEvent('aurp_trucker:client:palletJackBatchSync', m.src, lobby.loadedCount, lobby.requiredCount, batchIndex)
        end
    end

    if lobby.loadedCount >= (lobby.requiredCount or 4) then
        lobby.stage = 'STATUS_IN_TRANSIT'
        for _, m in ipairs(members) do
            if m.src and GetPlayerPing(m.src) > 0 then
                TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', m.src, lobby.deliveryCoords)
                TriggerClientEvent('aurp_trucker:notify', m.src, 'Lotes Carregados', 'Todos os lotes da paleteira foram embarcados! Inicie o transporte até o destino.', 'success')
            end
        end
    end
end)

-- =======================================================================
-- FASE 2: MÓDULO 1 - CREW MULTIPLAYER (CO-OP LOGÍSTICO) CALLBACKS & EVENTOS
-- =======================================================================
lib.callback.register('aurp_trucker:server:getCrewData', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return { inCrew = false } end
    local citizenId = Framework.GetCitizenId(Player)

    local crewId = PlayerTruckerCrew[citizenId]
    if not crewId or not TruckerCrews[crewId] then
        return { inCrew = false }
    end

    local crew = TruckerCrews[crewId]
    local memberList = {}
    for cid, m in pairs(crew.members) do
        table.insert(memberList, { citizenId = cid, name = m.name, src = m.src, isLeader = (cid == crew.leader) })
    end

    return {
        inCrew = true,
        crewId = crewId,
        isLeader = (crew.leader == citizenId),
        leaderName = crew.members[crew.leader] and crew.members[crew.leader].name or 'Desconhecido',
        members = memberList,
        maxMembers = Config.Crew.MaxMembers or 4
    }
end)

RegisterNetEvent('aurp_trucker:server:createCrew', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    if PlayerTruckerCrew[citizenId] then
        TriggerClientEvent('aurp_trucker:notify', src, 'Equipe', 'Você já faz parte de uma equipe!', 'error')
        return
    end

    local crewId = ('crew_%d'):format(math.random(10000, 99999))
    local charName = GetCharName(src)

    TruckerCrews[crewId] = {
        id = crewId,
        leader = citizenId,
        leaderSrc = src,
        members = {
            [citizenId] = { src = src, name = charName }
        }
    }
    PlayerTruckerCrew[citizenId] = crewId

    TriggerClientEvent('aurp_trucker:notify', src, 'Equipe Criada', 'Você criou uma equipe de logística! Use o menu da equipe para convidar membros próximos.', 'success')
    TriggerClientEvent('aurp_trucker:client:crewUpdated', src, TruckerCrews[crewId])
end)

RegisterNetEvent('aurp_trucker:server:invitePlayer', function(targetSrc)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local crewId = PlayerTruckerCrew[citizenId]
    local crew = crewId and TruckerCrews[crewId]
    if not crew or crew.leader ~= citizenId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Equipe', 'Apenas o líder da equipe pode enviar convites!', 'error')
        return
    end

    local memberCount = 0
    for _ in pairs(crew.members) do memberCount = memberCount + 1 end
    local maxM = Config.Crew.MaxMembers or 4
    if memberCount >= maxM then
        TriggerClientEvent('aurp_trucker:notify', src, 'Equipe Lotada', ('Sua equipe já atingiu o limite máximo de %d membros!'):format(maxM), 'error')
        return
    end

    local targetPlayer = Framework.GetPlayer(targetSrc)
    if not targetPlayer then
        TriggerClientEvent('aurp_trucker:notify', src, 'Erro', 'Jogador não encontrado!', 'error')
        return
    end
    local targetCid = Framework.GetCitizenId(targetPlayer)

    if PlayerTruckerCrew[targetCid] then
        TriggerClientEvent('aurp_trucker:notify', src, 'Ocupado', 'Esse jogador já está em uma equipe!', 'error')
        return
    end

    -- Validação de proximidade server-side
    local pPed = GetPlayerPed(src)
    local tPed = GetPlayerPed(targetSrc)
    if #(GetEntityCoords(pPed) - GetEntityCoords(tPed)) > (Config.Crew.InviteDistance or 20.0) then
        TriggerClientEvent('aurp_trucker:notify', src, 'Distância', 'O jogador precisa estar próximo para receber o convite!', 'error')
        return
    end

    TriggerClientEvent('aurp_trucker:client:receiveCrewInvite', targetSrc, crewId, GetCharName(src))
    TriggerClientEvent('aurp_trucker:notify', src, 'Convite Enviado', ('Convite de equipe enviado para %s!'):format(GetCharName(targetSrc)), 'info')
end)

RegisterNetEvent('aurp_trucker:server:respondCrewInvite', function(crewId, accepted)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    if PlayerTruckerCrew[citizenId] then return end

    local crew = TruckerCrews[crewId]
    if not crew then
        TriggerClientEvent('aurp_trucker:notify', src, 'Equipe Expirada', 'Essa equipe não existe mais ou foi desfeita.', 'error')
        return
    end

    if not accepted then
        if crew.leaderSrc and GetPlayerPing(crew.leaderSrc) > 0 then
            TriggerClientEvent('aurp_trucker:notify', crew.leaderSrc, 'Convite Recusado', ('%s recusou o convite para a equipe.'):format(GetCharName(src)), 'warning')
        end
        return
    end

    local memberCount = 0
    for _ in pairs(crew.members) do memberCount = memberCount + 1 end
    if memberCount >= (Config.Crew.MaxMembers or 4) then
        TriggerClientEvent('aurp_trucker:notify', src, 'Equipe Lotada', 'A equipe já atingiu o limite de integrantes!', 'error')
        return
    end

    crew.members[citizenId] = { src = src, name = GetCharName(src) }
    PlayerTruckerCrew[citizenId] = crewId

    for _, m in pairs(crew.members) do
        TriggerClientEvent('aurp_trucker:notify', m.src, 'Novo Membro', ('%s ingressou na equipe de transporte!'):format(GetCharName(src)), 'success')
        TriggerClientEvent('aurp_trucker:client:crewUpdated', m.src, crew)
    end
end)

RegisterNetEvent('aurp_trucker:server:leaveCrew', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local crewId = PlayerTruckerCrew[citizenId]
    local crew = crewId and TruckerCrews[crewId]
    if not crew then return end

    crew.members[citizenId] = nil
    PlayerTruckerCrew[citizenId] = nil

    TriggerClientEvent('aurp_trucker:notify', src, 'Equipe', 'Você saiu da equipe.', 'info')
    TriggerClientEvent('aurp_trucker:client:crewUpdated', src, nil)

    if crew.leader == citizenId then
        local nextLeaderCid, nextLeaderData = next(crew.members)
        if nextLeaderCid then
            crew.leader = nextLeaderCid
            crew.leaderSrc = nextLeaderData.src
            for _, m in pairs(crew.members) do
                TriggerClientEvent('aurp_trucker:notify', m.src, 'Liderança', ('O líder anterior saiu. %s é o novo líder!'):format(nextLeaderData.name), 'info')
                TriggerClientEvent('aurp_trucker:client:crewUpdated', m.src, crew)
            end
        else
            TruckerCrews[crewId] = nil
        end
    else
        for _, m in pairs(crew.members) do
            TriggerClientEvent('aurp_trucker:notify', m.src, 'Membro Saiu', ('%s saiu da equipe.'):format(GetCharName(src)), 'info')
            TriggerClientEvent('aurp_trucker:client:crewUpdated', m.src, crew)
        end
    end
end)

RegisterNetEvent('aurp_trucker:server:disbandCrew', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local crewId = PlayerTruckerCrew[citizenId]
    local crew = crewId and TruckerCrews[crewId]
    if not crew or crew.leader ~= citizenId then return end

    for cid, m in pairs(crew.members) do
        PlayerTruckerCrew[cid] = nil
        TriggerClientEvent('aurp_trucker:notify', m.src, 'Equipe Desfeita', 'O líder encerrou a equipe de transporte.', 'warning')
        TriggerClientEvent('aurp_trucker:client:crewUpdated', m.src, nil)
    end
    TruckerCrews[crewId] = nil
end)

-- =======================================================================
-- FASE 2: MÓDULO 2 - SISTEMA TYCOON (BASES & OFICINA PRIVADA)
-- =======================================================================
lib.callback.register('aurp_trucker:server:getPlayerBases', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local citizenId = Framework.GetCitizenId(Player)

    local rows = MySQL.query.await('SELECT base_id FROM `trucker_bases` WHERE `citizenid` = ?', { citizenId }) or {}
    local owned = {}
    for _, r in ipairs(rows) do
        owned[r.base_id] = true
    end
    return owned
end)

lib.callback.register('aurp_trucker:server:buyBase', function(source, baseId)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, message = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    local baseCfg = Config.TycoonBases and Config.TycoonBases[baseId]
    if not baseCfg then
        return { success = false, message = 'Base inexistente no catálogo' }
    end

    local existing = MySQL.single.await('SELECT id FROM `trucker_bases` WHERE `citizenid` = ? AND `base_id` = ?', { citizenId, baseId })
    if existing then
        return { success = false, message = 'Você já é proprietário desta base logística!' }
    end

    local price = baseCfg.price or 150000
    local balance = 0

    if exports.qbx_core then
        balance = exports.qbx_core:GetMoney(source, 'bank')
    else
        balance = Framework.GetMoney(Player, 'bank')
    end

    if balance < price then
        return { success = false, message = ('Saldo bancário insuficiente! Preço da base: $%d.'):format(price) }
    end

    -- Transação Fail-Closed
    local removed = false
    if exports.qbx_core then
        removed = exports.qbx_core:RemoveMoney(source, 'bank', price, 'trucker-buy-base')
    else
        removed = Framework.RemoveMoney(Player, 'bank', price, 'trucker-buy-base')
    end

    if not removed then
        return { success = false, message = 'Falha ao processar pagamento bancário!' }
    end

    MySQL.query.await('INSERT INTO `trucker_bases` (`citizenid`, `base_id`) VALUES (?, ?)', { citizenId, baseId })
    return { success = true, baseId = baseId, label = baseCfg.label }
end)

lib.callback.register('aurp_trucker:server:repairVehicle', function(source, baseId)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, message = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    local baseCfg = Config.TycoonBases and Config.TycoonBases[baseId]
    if not baseCfg then return { success = false, message = 'Base inválida' } end

    local owns = MySQL.single.await('SELECT id FROM `trucker_bases` WHERE `citizenid` = ? AND `base_id` = ?', { citizenId, baseId })
    if not owns then
        return { success = false, message = 'Você não possui acesso a esta oficina privada!' }
    end

    local baseCost = (Config.WorkshopUpgrades and Config.WorkshopUpgrades.RepairBaseCost) or 1500
    local discount = baseCfg.repairDiscount or 0.40
    local finalCost = math.floor(baseCost * (1.0 - discount))

    local balance = 0
    if exports.qbx_core then
        balance = exports.qbx_core:GetMoney(source, 'bank')
    else
        balance = Framework.GetMoney(Player, 'bank')
    end

    if balance < finalCost then
        return { success = false, message = ('Saldo insuficiente para reparo ($%d)!'):format(finalCost) }
    end

    local paid = false
    if exports.qbx_core then
        paid = exports.qbx_core:RemoveMoney(source, 'bank', finalCost, 'trucker-workshop-repair')
    else
        paid = Framework.RemoveMoney(Player, 'bank', finalCost, 'trucker-workshop-repair')
    end

    if not paid then
        return { success = false, message = 'Falha na transação financeira' }
    end

    return { success = true, cost = finalCost, discount = math.floor(discount * 100) }
end)

lib.callback.register('aurp_trucker:server:applyUpgrade', function(source, baseId, category, level)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, message = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    local baseCfg = Config.TycoonBases and Config.TycoonBases[baseId]
    if not baseCfg then return { success = false, message = 'Base inválida' } end

    local owns = MySQL.single.await('SELECT id FROM `trucker_bases` WHERE `citizenid` = ? AND `base_id` = ?', { citizenId, baseId })
    if not owns then
        return { success = false, message = 'Você não possui acesso a esta oficina privada!' }
    end

    local upgCategory = Config.WorkshopUpgrades and Config.WorkshopUpgrades[category]
    local upgData = upgCategory and upgCategory[level]
    if not upgData then
        return { success = false, message = 'Upgrade não encontrado' }
    end

    local price = upgData.price or 10000
    local balance = 0
    if exports.qbx_core then
        balance = exports.qbx_core:GetMoney(source, 'bank')
    else
        balance = Framework.GetMoney(Player, 'bank')
    end

    if balance < price then
        return { success = false, message = ('Saldo insuficiente ($%d)!'):format(price) }
    end

    local paid = false
    if exports.qbx_core then
        paid = exports.qbx_core:RemoveMoney(source, 'bank', price, 'trucker-workshop-upgrade')
    else
        paid = Framework.RemoveMoney(Player, 'bank', price, 'trucker-workshop-upgrade')
    end

    if not paid then
        return { success = false, message = 'Falha ao processar pagamento do upgrade' }
    end

    return { success = true, mod = upgData.mod, level = upgData.level, label = upgData.label, price = price }
end)


