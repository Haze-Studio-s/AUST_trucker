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
