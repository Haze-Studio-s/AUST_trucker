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

    if lobby.handler and DoesEntityExist(lobby.handler) then
        DeleteEntity(lobby.handler)
    end

    if lobby.container and DoesEntityExist(lobby.container) then
        DeleteEntity(lobby.container)
    end

    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end

    if lobby.pallets then
        for _, p in ipairs(lobby.pallets) do
            if p and DoesEntityExist(p) then
                DeleteEntity(p)
            end
        end
    end

    if lobby.carrierCars then
        for _, c in ipairs(lobby.carrierCars) do
            if c and DoesEntityExist(c) then
                DeleteEntity(c)
            end
        end
    end
end

-- Helper de remoção de chaves autoritativas (Caminhão alugado, Empilhadeira, Reach Stacker e Carros da Cegonha)
local function RemoveJobKeys(src, lobby)
    if not src or not lobby then return end
    local platesToRemove = {}
    local truckPlate = lobby.truckPlate or (lobby.truck and DoesEntityExist(lobby.truck) and GetVehicleNumberPlateText(lobby.truck))
    if truckPlate and not lobby.isOwned then
        table.insert(platesToRemove, { plate = truckPlate, entity = lobby.truck })
    end
    if lobby.forkliftPlate then
        table.insert(platesToRemove, { plate = lobby.forkliftPlate, entity = lobby.forklift })
    end
    if lobby.handlerPlate then
        table.insert(platesToRemove, { plate = lobby.handlerPlate, entity = lobby.handler })
    end
    if lobby.carrierCars then
        for _, carEnt in ipairs(lobby.carrierCars) do
            if carEnt and DoesEntityExist(carEnt) then
                local cPlate = GetVehicleNumberPlateText(carEnt)
                table.insert(platesToRemove, { plate = cPlate, entity = carEnt })
            end
        end
    end

    for _, pData in ipairs(platesToRemove) do
        local targetPlate = pData.plate
        if exports.ox_inventory then
            pcall(function()
                exports.ox_inventory:RemoveItem(src, 'keys', 1, { plate = targetPlate })
                exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, { plate = targetPlate })
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
            end)
        end

        if exports['qbx_vehiclekeys'] and pData.entity and DoesEntityExist(pData.entity) then
            pcall(function() exports['qbx_vehiclekeys']:RemoveKeys(src, pData.entity) end)
        end
        if exports['qb-vehiclekeys'] then
            pcall(function() exports['qb-vehiclekeys']:RemoveKeys(src, targetPlate) end)
        end
    end
end

-- Mecânica Anti-Griefing: First Step Timer (6 minutos para desocupar o pátio)
local function StartFirstStepTimer(jobId, src, yardCoords)
    CreateThread(function()
        local startTime = os.time()
        local maxWaitSeconds = 360 -- 6 minutos de tolerância máxima no pátio
        yardCoords = yardCoords or vector3(1245.0, -3155.0, 4.5)

        while true do
            Wait(15000) -- Verificação periódica a cada 15 segundos
            local lobby = PolarixLobbies[jobId]
            if not lobby then break end

            if not GetPlayerPing(src) or GetPlayerPing(src) <= 0 then
                print(("[AUST_Trucker] Jogador desconectou durante etapa de pátio. Limpando Job %s"):format(tostring(jobId)))
                CleanupLobbyEntities(lobby)
                if lobby.citizenId then PlayerPolarixLobbies[lobby.citizenId] = nil end
                PolarixLobbies[jobId] = nil
                break
            end

            -- Verifica se o jogador já iniciou trânsito rodoviário ou saiu de perto do pátio
            local ped = GetPlayerPed(src)
            local pCoords = ped and DoesEntityExist(ped) and GetEntityCoords(ped)
            if lobby.stage == 'STATUS_IN_TRANSIT' or lobby.stage == 'STEP_8_IN_TRANSIT' or (pCoords and #(pCoords - yardCoords) > 120.0) then
                print(("[AUST_Trucker] First Step Timer concluído com sucesso para Job %s (Rota iniciada)."):format(tostring(jobId)))
                break
            end

            local elapsed = os.time() - startTime
            if elapsed >= maxWaitSeconds then
                print(("[AUST_Trucker] First Step Timer expirado para Job %s. Cancelando por inatividade de pátio."):format(tostring(jobId)))
                TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Liberado', 'Você excedeu o tempo limite de 6 minutos para sair do pátio. O contrato foi cancelado para desobstruir as vagas.', 'error')
                TriggerClientEvent('aust_trucker:client:ClearObjective', src)
                RemoveJobKeys(src, lobby)
                CleanupLobbyEntities(lobby)
                if lobby.citizenId then
                    PlayerPolarixLobbies[lobby.citizenId] = nil
                end
                PolarixLobbies[jobId] = nil
                break
            elseif elapsed >= 180 and elapsed < 195 then
                TriggerClientEvent('aurp_trucker:notify', src, 'Aviso de Pátio', 'Atenção: Você tem 3 minutos restantes para carregar e iniciar a viagem.', 'warning')
            elseif elapsed >= 300 and elapsed < 315 then
                TriggerClientEvent('aurp_trucker:notify', src, 'Aviso Urgente', 'Atenção: Apenas 1 minuto restante para desocupar as vagas do pátio logístico!', 'warning')
            end
        end
    end)
end

-- Auto-schema idempotente para 0r_trucker e trucker_licenses
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

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `trucker_licenses` (
            `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
            `adr_certified` TINYINT(1) DEFAULT 0,
            `heavy_certified` TINYINT(1) DEFAULT 0,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)


-- =======================================================================
-- ONESYNC SERVER-SIDE AREA CLEARANCE CHECK & FORCE EXPUNGE
-- =======================================================================
local function IsVehicleOccupiedByPlayer(veh)
    if not DoesEntityExist(veh) then return false end
    for seat = -1, 4 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped and ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped) then
            return true
        end
    end
    local players = GetPlayers()
    for _, pSrc in ipairs(players) do
        local pPed = GetPlayerPed(pSrc)
        if pPed and DoesEntityExist(pPed) then
            if GetVehiclePedIsIn(pPed, false) == veh then
                return true
            end
        end
    end
    return false
end

function IsSpawnPointClear(coords, radius, ignoreEntities)
    if not coords then return false end
    local targetCoords = vector3(coords.x, coords.y, coords.z)
    local checkRadius = radius or 4.5
    local ignore = ignoreEntities or {}

    if GetAllVehicles then
        local vehicles = GetAllVehicles()
        for _, veh in ipairs(vehicles) do
            if DoesEntityExist(veh) and not ignore[veh] then
                local entCoords = GetEntityCoords(veh)
                if #(targetCoords - entCoords) < checkRadius then
                    if IsVehicleOccupiedByPlayer(veh) then
                        print(("[AUST_Trucker DEBUG - ETAPA 3] Vaga em (%.1f, %.1f) ocupada por jogador no veículo %s."):format(targetCoords.x, targetCoords.y, tostring(veh)))
                        return false
                    else
                        print(("[AUST_Trucker DEBUG - ETAPA 3] Deletando veículo abandonado/vazio (ID: %s, Modelo: %s) para desobstruir vaga (%.1f, %.1f)."):format(
                            tostring(veh), tostring(GetEntityModel(veh)), targetCoords.x, targetCoords.y
                        ))
                        DeleteEntity(veh)
                    end
                end
            end
        end
    end

    return true
end

local ActiveSpawningPlayers = {}

-- ETAPA 1: Iniciar Entrega / Contrato Autoritativo (QBOX OneSync)
local function StartTruckDelivery(src, contractData)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    contractData = contractData or {}

    if ActiveSpawningPlayers[citizenId] then
        print(("[AUST_Trucker] Spawn concorrente bloqueado para CitizenId: %s (Lock ativo)"):format(tostring(citizenId)))
        return
    end
    ActiveSpawningPlayers[citizenId] = true

    SetTimeout(15000, function()
        if ActiveSpawningPlayers[citizenId] then
            ActiveSpawningPlayers[citizenId] = nil
        end
    end)

    print(("[AUST_Trucker DEBUG - ETAPA 2] Recebida solicitação de início no Servidor! Src: %s, CitizenId: %s, ContractData: %s"):format(
        tostring(src), tostring(citizenId), json.encode(contractData)
    ))

    -- Auto-limpeza de lobby fantasma prévio se as entidades não existirem mais
    if PlayerPolarixLobbies[citizenId] then
        local oldJobId = PlayerPolarixLobbies[citizenId]
        local oldLobby = PolarixLobbies[oldJobId]
        local isStillAlive = oldLobby and (
            (oldLobby.truck and DoesEntityExist(oldLobby.truck)) or
            (oldLobby.trailer and DoesEntityExist(oldLobby.trailer))
        )
        if not isStillAlive then
            print(("[AUST_Trucker DEBUG] Limpando lobby anterior fantasma/abandonado para CitizenId: %s"):format(tostring(citizenId)))
            CleanupLobbyEntities(oldJobId)
            PlayerPolarixLobbies[citizenId] = nil
        else
            ActiveSpawningPlayers[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Contrato em Andamento', 'Você já possui uma rota ou contrato em andamento!', 'error')
            return
        end
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
        ActiveSpawningPlayers[citizenId] = nil
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

    -- RESOLUÇÃO DO TIPO DE CARGA (Seca vs Líquida vs Pesada/Contêiner vs ADR vs Cegonha/Veículos)
    local cargoType = contractData.cargoType
    if not cargoType or (cargoType ~= 'dry' and cargoType ~= 'liquid' and cargoType ~= 'heavy' and cargoType ~= 'adr' and cargoType ~= 'vehicle_carrier') then
        local tModel = string.lower(contractData.trailerModel or '')
        local cName = string.lower(contractData.name or '')
        if tModel == 'tr2' or string.find(cName, 'cegonha') or string.find(cName, 'veiculo') or string.find(cName, 'veículo') or string.find(cName, 'carro') or string.find(cName, 'carrier') then
            cargoType = 'vehicle_carrier'
        elseif string.find(cName, 'adr') or string.find(cName, 'quimic') or string.find(cName, 'químic') or string.find(cName, 'explos') or string.find(cName, 'nuclear') or string.find(cName, 'corros') then
            cargoType = 'adr'
        elseif tModel == 'docktrailer' or string.find(tModel, 'contr') or string.find(cName, 'conteiner') or string.find(cName, 'contêiner') or string.find(cName, 'container') or string.find(cName, 'heavy') or string.find(cName, 'pesad') then
            cargoType = 'heavy'
        elseif tModel == 'tanker' or tModel == 'tanker2' or tModel == 'armytanker' or string.find(tModel, 'tanker') or string.find(cName, 'tanque') or string.find(cName, 'combust') or string.find(cName, 'oleo') or string.find(cName, 'óleo') or string.find(cName, 'querosene') or string.find(cName, 'solvente') then
            cargoType = 'liquid'
        else
            cargoType = 'dry'
        end
    end

    -- BLINDAGEM DE LICENÇAS TÉCNICAS (ADR & HEAVY LIFT)
    if cargoType == 'heavy' or cargoType == 'adr' then
        local licRow = MySQL.single.await('SELECT adr_certified, heavy_certified FROM trucker_licenses WHERE citizenid = ?', { citizenId })
        if cargoType == 'heavy' and (not licRow or licRow.heavy_certified ~= 1) then
            ActiveSpawningPlayers[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Licença Obrigatória', 'Você precisa da Certificação Heavy Lift Operator para aceitar fretes de contêiner!', 'error')
            return
        elseif cargoType == 'adr' and (not licRow or licRow.adr_certified ~= 1) then
            ActiveSpawningPlayers[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Licença Obrigatória', 'Você precisa da Certificação ADR Specialist para transportar materiais perigosos/químicos!', 'error')
            return
        end
    end

    local typeConfig = Config.CargoTypes and Config.CargoTypes[cargoType]
    if not typeConfig then typeConfig = Config.CargoTypes.dry end

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
        local fallbackModel = 'trflat'
        if cargoType == 'liquid' or cargoType == 'adr' then
            fallbackModel = 'tanker'
        elseif cargoType == 'heavy' then
            fallbackModel = 'docktrailer'
        end
        trailerModel = joaat(typeConfig.defaultTrailer or fallbackModel)
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

    print(("[AUST_Trucker DEBUG - ETAPA 3] Buscando vaga livre para caminhão (Modelo: %s, Placa: %s)..."):format(selectedTruckModel, plate))

    for idx, coord in ipairs(truckSpawns) do
        if IsSpawnPointClear(coord, 4.5) then
            truck = CreateVehicle(truckModel, coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(truck) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
            if DoesEntityExist(truck) then
                chosenTruckCoord = coord
                print(("[AUST_Trucker DEBUG - ETAPA 3] Caminhão criado com sucesso na vaga %d. NetID: %s"):format(
                    idx, tostring(NetworkGetNetworkIdFromEntity(truck))
                ))
                break
            end
        end
    end

    -- Fallback se todas as vagas estiverem com jogadores
    if not truck or not DoesEntityExist(truck) then
        local fallbackCoord = truckSpawns[1]
        print(("[AUST_Trucker DEBUG - ETAPA 3] Vagas ocupadas, aplicando fallback na vaga principal %s..."):format(tostring(fallbackCoord)))
        truck = CreateVehicle(truckModel, fallbackCoord.x, fallbackCoord.y, fallbackCoord.z + 0.5, fallbackCoord.w or 90.0, true, true)
        local waitTimer = GetGameTimer()
        while not DoesEntityExist(truck) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
        if DoesEntityExist(truck) then
            chosenTruckCoord = fallbackCoord
        end
    end

    if not truck or not DoesEntityExist(truck) then
        ActiveSpawningPlayers[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Falha ao instanciar caminhão no servidor.', 'error')
        return
    end

    SetVehicleNumberPlateText(truck, plate)
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

    print(("[AUST_Trucker DEBUG - ETAPA 3] Caminhão destrancado com chaves entregues. Placa: %s, Jogador: %s"):format(plate, tostring(src)))

    -- STEP B: TRAILER SPAWN
    local trailerSpawns = Config.TrailerSpawns or (wh and wh.TrailerSpawns) or { wh.TrailerSpawnCoords }
    local trailer = nil
    local chosenTrailerCoord = nil

    print(("[AUST_Trucker DEBUG - ETAPA 3] Buscando vaga livre para carreta (Modelo: %s)..."):format(requestedTrailer))

    for idx, coord in ipairs(trailerSpawns) do
        if IsSpawnPointClear(coord, 5.0, { [truck] = true }) then
            trailer = CreateVehicle(trailerModel, coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(trailer) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
            if DoesEntityExist(trailer) then
                chosenTrailerCoord = coord
                print(("[AUST_Trucker DEBUG - ETAPA 3] Carreta criada com sucesso na vaga %d. NetID: %s"):format(
                    idx, tostring(NetworkGetNetworkIdFromEntity(trailer))
                ))
                break
            end
        end
    end

    if not trailer or not DoesEntityExist(trailer) then
        local fallbackCoord = trailerSpawns[1]
        print(("[AUST_Trucker DEBUG - ETAPA 3] Vagas de carreta ocupadas, aplicando fallback na vaga principal %s..."):format(tostring(fallbackCoord)))
        trailer = CreateVehicle(trailerModel, fallbackCoord.x, fallbackCoord.y, fallbackCoord.z + 0.5, fallbackCoord.w or 90.0, true, true)
        local waitTimer = GetGameTimer()
        while not DoesEntityExist(trailer) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
        if DoesEntityExist(trailer) then
            chosenTrailerCoord = fallbackCoord
        end
    end

    if not trailer or not DoesEntityExist(trailer) then
        ActiveSpawningPlayers[citizenId] = nil
        if DoesEntityExist(truck) then DeleteEntity(truck) end
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Falha ao instanciar carreta/reboque no servidor.', 'error')
        return
    end

    SetVehicleDoorsLocked(trailer, 1)

    -- ETAPA 3: Spawn Condicional (Empilhadeira vs Reach Stacker)
    local forklift = nil
    local forkliftPlate = nil
    local chosenForkliftCoord = nil
    local handler = nil
    local handlerPlate = nil
    local chosenHandlerCoord = nil
    local containerObj = nil
    local containerNetId = nil
    local carrierCars = {}
    local carrierVehicleNetIds = {}
    local pallets = {}
    local palletNetIds = {}
    local reqPallets = math.min(12, math.max(4, tonumber(contractData.palletCount) or 4))
    local withForklift = (contractData.withForklift ~= false)

    if cargoType == 'dry' then
        if withForklift then
            local forkliftSpawns = wh.ForkliftSpawns or { wh.ForkliftBayCoords }

            for idx, coord in ipairs(forkliftSpawns) do
                if IsSpawnPointClear(coord, 3.5, { [truck] = true, [trailer] = true }) then
                    forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
                    local waitTimer = GetGameTimer()
                    while not DoesEntityExist(forklift) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
                    if DoesEntityExist(forklift) then
                        chosenForkliftCoord = coord
                        print(("[AUST_Trucker DEBUG - ETAPA 3] Empilhadeira criada na vaga %d. NetID: %s"):format(
                            idx, tostring(NetworkGetNetworkIdFromEntity(forklift))
                        ))
                        break
                    end
                end
            end

            if not forklift or not DoesEntityExist(forklift) then
                local fallbackCoord = forkliftSpawns[1]
                forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), fallbackCoord.x, fallbackCoord.y, fallbackCoord.z + 0.5, fallbackCoord.w or 90.0, true, true)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(forklift) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
                if DoesEntityExist(forklift) then chosenForkliftCoord = fallbackCoord end
            end
        else
            print(("[AUST_Trucker] Frete configurado sem empilhadeira embarcada por escolha do motorista."))
        end

        if forklift and DoesEntityExist(forklift) then
            forkliftPlate = ("FORK%04d"):format(math.random(1000, 9999))
            SetVehicleNumberPlateText(forklift, forkliftPlate)
            SetVehicleDoorsLocked(forklift, 1)

            if exports.ox_inventory then
                local forkKeyMeta = {
                    plate = forkliftPlate,
                    description = "Chave da Empilhadeira - " .. forkliftPlate
                }
                local added = exports.ox_inventory:AddItem(src, 'keys', 1, forkKeyMeta)
                if not added then exports.ox_inventory:AddItem(src, 'vehiclekey', 1, forkKeyMeta) end
            end
            if exports['qbx_vehiclekeys'] then pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, forklift) end) end
            if exports['qb-vehiclekeys'] then pcall(function() exports['qb-vehiclekeys']:GiveKeys(src, forkliftPlate) end) end
            TriggerClientEvent('vehiclekeys:client:SetOwner', src, forkliftPlate)
            TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, forkliftPlate)
        end

        -- Spawn Dinâmico e Iterativo de Paletes Polarix com Fixação Física (Zero Limbo)
        local palletSpawns = wh.PalletSpawns or {}
        local ignoreEntities = { [truck] = true, [trailer] = true, [forklift] = true }

        for _, coord in ipairs(palletSpawns) do
            if #pallets >= reqPallets then break end
            local pModel = joaat(Config.Polarix.PalletModels[(#pallets % #Config.Polarix.PalletModels) + 1] or Config.Polarix.DefaultPalletModel)
            local pObj = CreateObject(pModel, coord.x, coord.y, coord.z + 0.1, true, true, false)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
            if DoesEntityExist(pObj) then
                FreezeEntityPosition(pObj, true)
                ignoreEntities[pObj] = true
                table.insert(pallets, pObj)
                table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pObj))
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

                local pModel = joaat(Config.Polarix.PalletModels[(i % #Config.Polarix.PalletModels) + 1] or Config.Polarix.DefaultPalletModel)
                local pObj = CreateObject(pModel, pos.x, pos.y, pos.z + 0.1, true, true, false)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
                if DoesEntityExist(pObj) then
                    FreezeEntityPosition(pObj, true)
                    ignoreEntities[pObj] = true
                    table.insert(pallets, pObj)
                    table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(pObj))
                end
            end
        end

        print(("[AUST_Trucker DEBUG - ETAPA 3] %d Paletes gerados com sucesso para o frete."):format(#pallets))

    elseif cargoType == 'heavy' then
        reqPallets = 1
        local yardCfg = (Config.CargoTypes and Config.CargoTypes.heavy and Config.CargoTypes.heavy.yard) or {}
        local handlerSpawns = yardCfg.handlerSpawns or { wh.HandlerBayCoords or vector4(1130.11, -3083.45, 6.01, 269.29) }

        for idx, coord in ipairs(handlerSpawns) do
            if IsSpawnPointClear(coord, 5.0, { [truck] = true, [trailer] = true }) then
                handler = CreateVehicle(joaat(Config.Polarix.Handler.VehicleModel or 'handler'), coord.x, coord.y, coord.z + 0.5, coord.w or 270.0, true, true)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(handler) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
                if DoesEntityExist(handler) then
                    chosenHandlerCoord = coord
                    print(("[AUST_Trucker DEBUG - ETAPA 3] Reach Stacker criado na vaga %d. NetID: %s"):format(
                        idx, tostring(NetworkGetNetworkIdFromEntity(handler))
                    ))
                    break
                end
            end
        end

        if not handler or not DoesEntityExist(handler) then
            local fallbackCoord = handlerSpawns[1]
            handler = CreateVehicle(joaat(Config.Polarix.Handler.VehicleModel or 'handler'), fallbackCoord.x, fallbackCoord.y, fallbackCoord.z + 0.5, fallbackCoord.w or 270.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(handler) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
            if DoesEntityExist(handler) then chosenHandlerCoord = fallbackCoord end
        end

        if handler and DoesEntityExist(handler) then
            handlerPlate = ("DOCK%04d"):format(math.random(1000, 9999))
            SetVehicleNumberPlateText(handler, handlerPlate)
            SetVehicleDoorsLocked(handler, 1)

            if exports.ox_inventory then
                local hKeyMeta = { plate = handlerPlate, description = "Chave Reach Stacker - " .. handlerPlate }
                local added = exports.ox_inventory:AddItem(src, 'keys', 1, hKeyMeta)
                if not added then exports.ox_inventory:AddItem(src, 'vehiclekey', 1, hKeyMeta) end
            end
            if exports['qbx_vehiclekeys'] then pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, handler) end) end
            TriggerClientEvent('vehiclekeys:client:SetOwner', src, handlerPlate)
        end

        -- Spawn do Contêiner
        local cSpawns = yardCfg.containerSpawns or { vector4(1178.15, -3115.13, 5.02, 266.0) }
        local chosenCCoord = cSpawns[math.random(#cSpawns)]
        local cModel = joaat(Config.Polarix.ContainerModel or 'prop_contr_03b_ld')
        containerObj = CreateObject(cModel, chosenCCoord.x, chosenCCoord.y, chosenCCoord.z + 0.1, true, true, false)
        local waitTimer = GetGameTimer()
        while not DoesEntityExist(containerObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
        if DoesEntityExist(containerObj) then
            FreezeEntityPosition(containerObj, true)
            containerNetId = NetworkGetNetworkIdFromEntity(containerObj)
            print(("[AUST_Trucker DEBUG - ETAPA 3] Contêiner gerado com sucesso. NetID: %s"):format(tostring(containerNetId)))
        end
    elseif cargoType == 'vehicle_carrier' then
        reqPallets = 3
        local carrierCfg = (Config.CargoTypes and Config.CargoTypes.vehicle_carrier) or {}
        local carModels = carrierCfg.carModels or { 'elegy2', 'jester', 'comet2' }
        local stagingPoints = (carrierCfg.yard and carrierCfg.yard.stagingCoords) or {
            vector4(1235.0, -3150.0, 4.6, 90.0),
            vector4(1235.0, -3155.0, 4.6, 90.0),
            vector4(1235.0, -3160.0, 4.6, 90.0),
        }

        for i = 1, 3 do
            local cCoord = stagingPoints[i] or stagingPoints[1]
            local cModelName = carModels[i] or carModels[1]
            local cHash = joaat(cModelName)
            local cVeh = CreateVehicle(cHash, cCoord.x, cCoord.y, cCoord.z + 0.3, cCoord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(cVeh) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
            if DoesEntityExist(cVeh) then
                SetVehicleDoorsLocked(cVeh, 1)
                local cPlate = ("CAR%05d"):format(math.random(10000, 99999))
                SetVehicleNumberPlateText(cVeh, cPlate)
                if exports['qbx_vehiclekeys'] then pcall(function() exports['qbx_vehiclekeys']:GiveKeys(src, cVeh) end) end
                TriggerClientEvent('vehiclekeys:client:SetOwner', src, cPlate)
                table.insert(carrierCars, cVeh)
                table.insert(carrierVehicleNetIds, NetworkGetNetworkIdFromEntity(cVeh))
            end
        end
        print(("[AUST_Trucker DEBUG - ETAPA 3] %d Veículos instanciados no pátio para a Cegonha."):format(#carrierCars))
    else
        reqPallets = 100 -- Carga Líquida e ADR
    end

    local destCfg = Config.Polarix.DeliveryDestinations[math.random(#Config.Polarix.DeliveryDestinations)]
    local destCoords = destCfg.coords

    -- Bônus de remuneração e XP por paletes extras (> 4)
    local basePayment = destCfg.reward or 5000
    local baseXP = destCfg.xp or 200
    if cargoType == 'dry' and reqPallets > 4 then
        local extraPallets = reqPallets - 4
        basePayment = math.floor(basePayment * (1 + (extraPallets * 0.15)))
        baseXP = math.floor(baseXP * (1 + (extraPallets * 0.10)))
    elseif cargoType == 'vehicle_carrier' then
        basePayment = math.floor(basePayment * 1.45) -- 45% a mais de remuneração para transporte de luxo
        baseXP = math.floor(baseXP * 1.35)
    end

    local lobbyData = {
        jobId = jobId,
        src = src,
        citizenId = citizenId,
        bucketId = bucketId,
        cargoType = cargoType,
        truck = truck,
        truckPlate = plate,
        truckModel = selectedTruckModel,
        isOwned = isOwned,
        trailer = trailer,
        forklift = forklift,
        forkliftPlate = forkliftPlate,
        withForklift = withForklift,
        handler = handler,
        handlerPlate = handlerPlate,
        container = containerObj,
        containerNetId = containerNetId,
        carrierCars = carrierCars,
        vehicleNetIds = carrierVehicleNetIds,
        pallets = pallets,
        palletNetIds = palletNetIds,
        loadedCount = 0,
        requiredCount = reqPallets,
        cargoName = contractData.name or (cargoType == 'liquid' and 'Combustível Automotivo' or (cargoType == 'heavy' and 'Contêiner Marítimo' or (cargoType == 'adr' and 'Compostos Químicos ADR' or (cargoType == 'vehicle_carrier' and 'Cegonha de Veículos Esportivos' or 'Paletes Industriais')))),
        cargoIntegrity = 100,
        payment = basePayment,
        xp = baseXP,
        deliveryCoords = destCoords,
        stage = 'STEP_GET_TRUCK',
        current_object = nil,
        hoseProp = nil,
        hoseConnected = false
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
        handlerCoords = chosenHandlerCoord and vector3(chosenHandlerCoord.x, chosenHandlerCoord.y, chosenHandlerCoord.z),
        handlerPlate = handlerPlate,
        containerNetId = containerNetId,
        vehicleNetIds = carrierVehicleNetIds,
        palletNetIds = palletNetIds,
        withForklift = withForklift,
        cargoName = lobbyData.cargoName,
        requiredCount = reqPallets,
        loadedCount = 0,
        deliveryCoords = destCoords
    }

    print(("[AUST_Trucker DEBUG - ETAPA 4] Enviando aurp_trucker:client:polarixJobStarted para jogador %s (JobID: %s, TruckNetId: %s, TrailerNetId: %s, Cargo: %s)"):format(
        tostring(src), tostring(jobId), tostring(payload.truckNetId), tostring(payload.trailerNetId), tostring(cargoType)
    ))

    ActiveSpawningPlayers[citizenId] = nil

    TriggerClientEvent('aurp_trucker:client:polarixJobStarted', src, payload)
    TriggerClientEvent('aurp_trucker:client:polarixSyncPallets', src, palletNetIds)

    -- Inicia o First Step Timer anti-griefing de pátio (6 minutos)
    local yardLoc = chosenTruckCoord and vector3(chosenTruckCoord.x, chosenTruckCoord.y, chosenTruckCoord.z) or (wh and wh.TruckSpawnCoords and vector3(wh.TruckSpawnCoords.x, wh.TruckSpawnCoords.y, wh.TruckSpawnCoords.z))
    StartFirstStepTimer(jobId, src, yardLoc)
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

    -- Validação de proximidade autoritativa do servidor (6.0m máximo)
    local ped = GetPlayerPed(src)
    local pedCoords = GetEntityCoords(ped)
    local truckCoords = GetEntityCoords(lobby.truck)
    if #(pedCoords - truckCoords) > 6.0 then
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
    lobby.startedTransitAt = os.time()

    TriggerClientEvent('aurp_trucker:client:liquidLoadingCompleted', src, jobId, lobby.deliveryCoords)
    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA 4: Validação de Cintas e Liberação de Rota GPS (Carga Seca)
RegisterNetEvent('aurp_trucker:server:strappingCompleted', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end

    -- Prevenção de Deadlock: assegura contagem e transição de estado garantida
    lobby.loadedCount = math.max(lobby.loadedCount or 0, lobby.requiredCount or 1)
    lobby.stage = 'STATUS_IN_TRANSIT'
    lobby.startedTransitAt = os.time()

    print(("[AUST_Trucker] Frete %s pronto para trânsito (Player %s). Destino: %s"):format(
        tostring(jobId), tostring(src), tostring(lobby.deliveryCoords)
    ))

    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA: Notificação de Palete Perdido durante a Viagem (Corda Rompida)
RegisterNetEvent('aurp_trucker:server:palletLost', function(jobId, palletNetId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.stage ~= 'STATUS_IN_TRANSIT' then return end

    lobby.lostPallets = (lobby.lostPallets or 0) + 1
    print(("[AUST_Trucker] Palete perdido em rota para o frete %s (Player: %s)! Total de perdas: %d"):format(
        tostring(jobId), tostring(src), lobby.lostPallets
    ))
end)

-- ETAPA: Notificação de Contêiner Carregado via Reach Stacker (Carga Pesada)
RegisterNetEvent('aurp_trucker:server:heavyContainerLoaded', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.cargoType ~= 'heavy' then return end

    lobby.stage = 'STATUS_IN_TRANSIT'
    lobby.startedTransitAt = os.time()
    lobby.loadedCount = 1

    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA: Contenção de Emergência de Vazamento ADR
RegisterNetEvent('aurp_trucker:server:adrLeakContained', function(jobId, newIntegrity)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.cargoType ~= 'adr' then return end

    lobby.cargoIntegrity = newIntegrity or 100
    print(("[AUST_Trucker] Jogador %s conteve vazamento ADR. Integridade salva em %d%%"):format(tostring(src), lobby.cargoIntegrity))
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

    -- BLINDAGEM 1: Validação autoritativa de distância até o destino
    local ped = GetPlayerPed(src)
    local pedCoords = GetEntityCoords(ped)
    local dest = lobby.deliveryCoords
    if not dest then return end
    local destVec = vector3(dest.x, dest.y, dest.z)
    local dist = #(pedCoords - destVec)
    if dist > 35.0 then
        print(("[AUST_Trucker] ALERTA SEGURANÇA: Player %s tentou concluir entrega fora do raio (%.1fm de distância)!"):format(tostring(src), dist))
        TriggerClientEvent('aurp_trucker:notify', src, 'Segurança', 'Você está fora do ponto de entrega para concluir o serviço!', 'error')
        return
    end

    -- BLINDAGEM 2: Validação de integridade do caminhão
    if lobby.truck and DoesEntityExist(lobby.truck) then
        if GetEntityHealth(lobby.truck) <= 0 then
            TriggerClientEvent('aurp_trucker:notify', src, 'Carga Perdida', 'O caminhão foi destruído e a carga foi perdida!', 'error')
            return
        end
    end

    -- BLINDAGEM 3: Validação de tempo mínimo de viagem (anti-teleport)
    if lobby.startedTransitAt then
        local elapsed = os.time() - lobby.startedTransitAt
        if elapsed < 10 then
            print(("[AUST_Trucker] ALERTA SEGURANÇA: Player %s concluiu trajeto em tempo impossível (%ds)!"):format(tostring(src), elapsed))
            TriggerClientEvent('aurp_trucker:notify', src, 'Segurança', 'Tempo de rota inconsistente!', 'error')
            return
        end
    end

    -- Pagamento com cálculo de penalidade proporcional por paletes perdidos ou integridade ADR
    local basePayment = lobby.payment or 5000
    local baseXP = lobby.xp or 200
    local totalReq = lobby.requiredCount or 4
    local lostCount = lobby.lostPallets or 0
    local deliveredCount = math.max(0, totalReq - lostCount)
    local ratio = (lobby.cargoType == 'dry' and totalReq > 0) and math.max(0.2, deliveredCount / totalReq) or 1.0
    if lobby.cargoType == 'adr' then
        ratio = math.max(0.2, (lobby.cargoIntegrity or 100) / 100)
    end

    local payment = math.floor(basePayment * ratio)
    local xp = math.floor(baseXP * ratio)

    if exports.qbx_core then
        exports.qbx_core:AddMoney(src, 'bank', payment, 'polarix-trucker-job')
    else
        Framework.AddMoney(Player, 'bank', payment, 'polarix-trucker-job')
    end

    -- Remoção autoritativa de chaves
    RemoveJobKeys(src, lobby)

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

    -- Limpeza OneSync autoritativa de entidades geradas
    CleanupLobbyEntities(lobby)

    PolarixLobbies[jobId] = nil
    PlayerPolarixLobbies[citizenId] = nil

    TriggerClientEvent('aust_trucker:client:ClearObjective', src)
    TriggerClientEvent('aurp_trucker:client:polarixJobFinished', src, {
        payment = payment,
        xp = xp,
        lostPallets = lostCount,
        deliveredPallets = deliveredCount,
        distance = 3.5
    })
end)

-- Cancelamento / Aborto Autoritativo da Entrega
RegisterNetEvent('aurp_trucker:server:cancelDelivery', function(jobId, reason)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.citizenId ~= citizenId then return end

    RemoveJobKeys(src, lobby)
    CleanupLobbyEntities(lobby)

    PolarixLobbies[jobId] = nil
    PlayerPolarixLobbies[citizenId] = nil

    TriggerClientEvent('aust_trucker:client:ClearObjective', src)
    TriggerClientEvent('aurp_trucker:notify', src, 'Entrega Cancelada', reason or 'O contrato foi cancelado.', 'warning')
end)

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


