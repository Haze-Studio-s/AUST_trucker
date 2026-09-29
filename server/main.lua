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
-- LOGÍSTICA 2.0: GERENCIAMENTO DE ENTIDADES NO SERVIDOR (OneSync & Buckets)
-- Fusão Cirúrgica: oConteneur + oForklift + Contratos & Lobbies
-- =======================================================================
LogisticsServer = {}

function LogisticsServer.SpawnJobEntities(src, citizenId, jobId, payload)
    local pPed = GetPlayerPed(src)
    if not pPed or pPed == 0 then return end

    local bucket = GetEntityRoutingBucket(pPed) or 0
    local pCfg = Config.PhysicalLoading or {}

    -- Inicializa container de entidades do jogador
    VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}
    local jobEnts = VP_Trucker.PlayerJobEntities[citizenId]

    -- Limpa quaisquer entidades órfãs anteriores do mesmo cidadão
    LogisticsServer.CleanupJobEntities(citizenId)

    local truckNetId = nil
    local trailerNetId = nil
    local machineNetId = nil
    local containerNetId = nil
    local palletNetIds = {}

    -- 1. Spawn do Caminhão (Servidor) — Z = 6.50 para prevenção de queda no limbo
    if payload.isQuickJob and payload.truckModel then
        local tHash = joaat(payload.truckModel)
        local tSpawn = payload.truckSpawn or vector4(1250.55, -3162.40, 5.88, 270.00)
        local truck = CreateVehicle(tHash, tSpawn.x, tSpawn.y, 6.50, tSpawn.w, true, true)
        while not DoesEntityExist(truck) do Wait(10) end
        SetEntityRoutingBucket(truck, bucket)
        SetVehicleDoorsLocked(truck, 2) -- Trancado para inspeção obrigatória (Estado 2)
        local plate = 'LC' .. math.random(1000, 9999)
        SetVehicleNumberPlateText(truck, plate)
        jobEnts.truck = truck
        jobEnts.plate = plate
        truckNetId = NetworkGetNetworkIdFromEntity(truck)
    end

    -- 2. Spawn do Reboque (Servidor)
    if payload.trailerModel then
        local trHash = joaat(payload.trailerModel)
        local trSpawn = payload.trailerSpawn or vector4(1274.21, -3186.43, 5.91, 90.00)
        local trailer = CreateVehicle(trHash, trSpawn.x, trSpawn.y, 6.50, trSpawn.w, true, true)
        while not DoesEntityExist(trailer) do Wait(10) end
        SetEntityRoutingBucket(trailer, bucket)
        jobEnts.trailer = trailer
        trailerNetId = NetworkGetNetworkIdFromEntity(trailer)
    end

    -- 3. Detecção de Modo de Carregamento Físico
    local cargoStr = tostring(payload.cargoName or ''):lower()
    local trModelStr = tostring(payload.trailerModel or ''):lower()
    local isContainer = (trModelStr == 'trflat' or trModelStr == 'trailers' or cargoStr:find('cont') ~= nil)
    local isForklift = (trModelStr == 'mule' or trModelStr == 'mule2' or cargoStr:find('palet') ~= nil or cargoStr:find('forklift') ~= nil)

    -- 4. Spawn do Maquinário e Cargas Cirúrgicas no Servidor
    if isContainer and pCfg.Handler then
        local hCfg = pCfg.Handler
        -- Spawn da Grua Handler
        local hHash = joaat(hCfg.VehicleModel or 'handler')
        local hSpawn = hCfg.SpawnCoords or vector4(1240.23, -3105.80, 5.80, 270.00)
        local handlerVeh = CreateVehicle(hHash, hSpawn.x, hSpawn.y, 6.50, hSpawn.w, true, true)
        while not DoesEntityExist(handlerVeh) do Wait(10) end
        SetEntityRoutingBucket(handlerVeh, bucket)
        jobEnts.machine = handlerVeh
        machineNetId = NetworkGetNetworkIdFromEntity(handlerVeh)

        -- Spawn do Contêiner
        local cHash = joaat(hCfg.ContainerProp or 'prop_contr_03b_ld')
        local cSpawn = hCfg.ContainerStagingCoords or vector4(1258.50, -3120.00, 5.80, 180.00)
        local containerProp = CreateObjectNoOffset(cHash, cSpawn.x, cSpawn.y, 6.50, true, true, false)
        while not DoesEntityExist(containerProp) do Wait(10) end
        SetEntityHeading(containerProp, cSpawn.w or 180.0)
        SetEntityRoutingBucket(containerProp, bucket)
        jobEnts.container = containerProp
        containerNetId = NetworkGetNetworkIdFromEntity(containerProp)

    elseif isForklift and pCfg.Forklift then
        local fCfg = pCfg.Forklift
        -- Spawn da Empilhadeira Forklift
        local fHash = joaat(fCfg.VehicleModel or 'forklift')
        local fSpawn = fCfg.SpawnCoords or vector4(1243.50, -3112.20, 5.80, 270.00)
        local forkliftVeh = CreateVehicle(fHash, fSpawn.x, fSpawn.y, 6.50, fSpawn.w, true, true)
        while not DoesEntityExist(forkliftVeh) do Wait(10) end
        SetEntityRoutingBucket(forkliftVeh, bucket)
        jobEnts.machine = forkliftVeh
        machineNetId = NetworkGetNetworkIdFromEntity(forkliftVeh)

        -- Spawn dos Paletes Industriais
        local palletPool = fCfg.PalletModels or { 'prop_boxpile_06a' }
        local pSpawns = fCfg.PalletStagingCoords or {
            vector4(1260.00, -3125.00, 5.80, 0.0),
            vector4(1262.50, -3125.00, 5.80, 0.0),
            vector4(1265.00, -3125.00, 5.80, 0.0),
        }
        jobEnts.pallets = {}
        for i = 1, math.min(#pSpawns, payload.requiredCount or 3) do
            local pModel = palletPool[math.random(#palletPool)]
            local pHash = joaat(pModel)
            local sp = pSpawns[i]
            local palletProp = CreateObjectNoOffset(pHash, sp.x, sp.y, 6.50, true, true, false)
            while not DoesEntityExist(palletProp) do Wait(10) end
            SetEntityHeading(palletProp, sp.w or 0.0)
            SetEntityRoutingBucket(palletProp, bucket)
            table.insert(jobEnts.pallets, palletProp)
            table.insert(palletNetIds, NetworkGetNetworkIdFromEntity(palletProp))
        end
    end

    -- Registra dados no ActiveLCContractData
    if ActiveLCContractData and ActiveLCContractData[jobId] then
        local cd = ActiveLCContractData[jobId]
        cd.truckNetId = truckNetId
        cd.trailerNetId = trailerNetId
        cd.machineNetId = machineNetId
        cd.containerNetId = containerNetId
        cd.palletNetIds = palletNetIds
        cd.isContainer = isContainer
        cd.isForklift = isForklift
        cd.stage = 'STATUS_SPAWNED'
    end

    -- Envia NetIDs ao cliente com payload de inicialização
    local entityPayload = {
        jobId = jobId,
        truckNetId = truckNetId,
        trailerNetId = trailerNetId,
        machineNetId = machineNetId,
        containerNetId = containerNetId,
        palletNetIds = palletNetIds,
        isContainer = isContainer,
        isForklift = isForklift,
        requiredCount = payload.requiredCount or 3,
        plate = jobEnts.plate,
        deliveryCoords = payload.deliveryCoords,
    }

    TriggerClientEvent('aurp_trucker:client:receiveJobEntities', src, entityPayload)
end

function LogisticsServer.CleanupJobEntities(citizenId)
    if not citizenId then return end
    local jobEnts = VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId]
    if not jobEnts then return end

    if jobEnts.truck and DoesEntityExist(jobEnts.truck) then
        DeleteEntity(jobEnts.truck)
    end
    if jobEnts.trailer and DoesEntityExist(jobEnts.trailer) then
        DeleteEntity(jobEnts.trailer)
    end
    if jobEnts.machine and DoesEntityExist(jobEnts.machine) then
        DeleteEntity(jobEnts.machine)
    end
    if jobEnts.container and DoesEntityExist(jobEnts.container) then
        DeleteEntity(jobEnts.container)
    end
    if jobEnts.pallets then
        for _, p in ipairs(jobEnts.pallets) do
            if DoesEntityExist(p) then DeleteEntity(p) end
        end
    end

    VP_Trucker.PlayerJobEntities[citizenId] = nil
end

-- Eventos de Ciclo de Vida dos 5 Estados
RegisterNetEvent('aurp_trucker:server:vehicleInspected', function(jobId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local data = ActiveLCContractData and ActiveLCContractData[jobId]
    if not data or data.citizenId ~= citizenId then return end

    local jobEnts = VP_Trucker.PlayerJobEntities[citizenId]
    if jobEnts and jobEnts.truck and DoesEntityExist(jobEnts.truck) then
        SetVehicleDoorsLocked(jobEnts.truck, 1) -- Destranca o veículo após vistoria
        if exports.qbx_vehiclekeys then
            pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, jobEnts.truck) end)
        end
    end

    data.stage = 'STATUS_INSPECTED'
    TriggerClientEvent('aurp_trucker:client:inspectionApproved', src, jobId)
    TriggerClientEvent('aurp_trucker:notify', src, 'Vistoria Aprovada', 'Veículo inspecionado e destrancado com sucesso! Chaves entregues. Prossiga ao pátio para carregamento.', 'success')
end)

RegisterNetEvent('aurp_trucker:server:cargoItemAttached', function(jobId, loaded, total)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local data = ActiveLCContractData and ActiveLCContractData[jobId]
    if not data or data.citizenId ~= citizenId then return end

    data.loadedCount = loaded
    data.requiredCount = total

    if loaded >= total then
        data.stage = 'STATUS_LOADED'
        TriggerClientEvent('aurp_trucker:client:cargoLoadingCompleted', src, jobId)
        TriggerClientEvent('aurp_trucker:notify', src, 'Carga Acomodada', 'Todas as mercadorias foram acondicionadas! Vá até a traseira do reboque para fixar as cintas e retirar o romaneio.', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, 'Progresso de Carga', ('Volume %d/%d acomodado com segurança no compartimento.'):format(loaded, total), 'inform')
    end
end)

RegisterNetEvent('aurp_trucker:server:strapAndManifest', function(jobId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local data = ActiveLCContractData and ActiveLCContractData[jobId]
    if not data or data.citizenId ~= citizenId then return end

    data.stage = 'STATUS_IN_TRANSIT'
    TriggerClientEvent('aurp_trucker:client:setJobState', src, jobId, 'STATUS_IN_TRANSIT')
    TriggerClientEvent('aurp_trucker:notify', src, 'Romaneio Liberado', 'Cintas travadas e manifesto carimbado pela administração! Siga a rota indicada no GPS até o destino.', 'success')
end)
