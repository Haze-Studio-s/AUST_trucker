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

-- Helper OneSync: Trava autoritativa de propriedade de rede no motorista (Anti-Desync de Proximidade / Observers)
function LockEntityNetworkOwner(entity, src)
    if not entity or not DoesEntityExist(entity) or not src then return end
    pcall(function()
        if NetworkSetEntityOwner then
            NetworkSetEntityOwner(entity, src)
        elseif rawget(_G, 'SetEntityOwner') then
            SetEntityOwner(entity, src)
        end
    end)
    pcall(function()
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if netId and netId ~= 0 then
            SetNetworkIdCanMigrate(netId, true)
        end
    end)
end
_G.LockEntityNetworkOwner = LockEntityNetworkOwner


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
                        if Config.Debug then print('[AUST_trucker] Seguranca: Injecao maliciosa de webpack_bundle purgada com sucesso de fxmanifest.lua.') end
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
        -- Aluguéis abertos antes do restart → caução integral como estorno pendente
        CreateThread(function()
            while not TruckRentalService do Wait(100) end
            TruckRentalService.Init()
        end)
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

-- Gera jobId único (evita colisão/sobrescrita de lobby ativo)
local function NewPolarixJobId()
    local id
    local tries = 0
    repeat
        id = math.random(100000, 999999)
        tries = tries + 1
    until not PolarixLobbies[id] or tries > 50
    if PolarixLobbies[id] then
        id = tonumber(('%d%d'):format(os.time() % 100000, math.random(10, 99))) or id
        while PolarixLobbies[id] do id = id + 1 end
    end
    return id
end

-- Aguarda entidade existir com timeout (padrão ~5s). Retorna true/false.
local function WaitEntityExists(ent, timeoutMs, step)
    local t0 = GetGameTimer()
    local limit = timeoutMs or 5000
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and (GetGameTimer() - t0 < limit) do
        Wait(step or 10)
    end
    return ent ~= nil and ent ~= 0 and DoesEntityExist(ent)
end

-- Valida número finito
local function IsFiniteNumber(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

-- Resolve o terminal de combustível pelo id (nil se inexistente)
local function FindFuelTerminal(terminalId)
    local cfg = Config.CargoTypes and Config.CargoTypes.liquid and Config.CargoTypes.liquid.fuelTerminals
    if not cfg or terminalId == nil then return nil end
    for _, term in ipairs(cfg) do
        if term.id == terminalId then return term end
    end
    return nil
end

-- Modelos de caminhão permitidos no aluguel/serviço (whitelist server-side)
local function GetAllowedTruckModels()
    local set = {}
    for _, m in ipairs({ 'hauler', 'phantom', 'packer', 'phantom3', 'hauler2', 'vetirs', 'pounder', 'pounder2', 'biff' }) do
        set[m] = true
    end
    if Config.Truck and type(Config.Truck.model) == 'string' then set[Config.Truck.model:lower()] = true end
    if Config.TruckRental and Config.TruckRental.trucks then
        for _, trk in ipairs(Config.TruckRental.trucks) do
            if type(trk.model) == 'string' then set[trk.model:lower()] = true end
        end
    end
    if Config.LC_Dealership then
        for k in pairs(Config.LC_Dealership) do
            if type(k) == 'string' then set[k:lower()] = true end
        end
    end
    return set
end

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

    if lobby.palletNetIds and #lobby.palletNetIds > 0 then
        local currentGlobal = GlobalState.activeTruckerPallets or {}
        local updatedGlobal = {}
        local removeLookup = {}
        for _, net in ipairs(lobby.palletNetIds) do removeLookup[net] = true end
        for _, net in ipairs(currentGlobal) do
            if not removeLookup[net] then table.insert(updatedGlobal, net) end
        end
        GlobalState.activeTruckerPallets = updatedGlobal
    end
end

-- Entrada na fase de carregamento. O client NUNCA envia `inspectionCompleted` (nenhum arquivo em client/
-- dispara esse evento), então o lobby fica em STEP_GET_TRUCK até o primeiro evento da fase de carga.
-- Em vez de exigir um evento que não chega, o primeiro evento válido de carregamento promove o estágio
-- (comportamento original do HandlePalletLoaded). Qualquer outro estágio continua recusado.
local function EnterLoadingStage(lobby)
    if lobby.stage == 'STATUS_LOADING' then return true end
    if lobby.stage == 'STEP_GET_TRUCK' then
        lobby.stage = 'STATUS_LOADING'
        return true
    end
    return false
end

-- Recusas de eventos do Polarix eram silenciosas (`return` sem log): quando uma validação recusava um evento
-- legítimo, o client seguia normalmente (o snap do palete é local) e o job travava sem nenhuma pista.
-- Agora cada recusa registra evento, job, estágio e motivo (no máx. 1 linha por chave a cada 5 s).
local _polarixRejectAt = {}
local function PolarixReject(event, jobId, lobby, reason)
    local key = ('%s:%s:%s'):format(event, tostring(jobId), reason)
    local now = GetGameTimer()
    if _polarixRejectAt[key] and (now - _polarixRejectAt[key]) < 5000 then return end
    _polarixRejectAt[key] = now
    print(('[AUST_Trucker Polarix] %s recusado (job %s, stage=%s, loaded=%s/%s): %s'):format(
        event, tostring(jobId), tostring(lobby and lobby.stage), tostring(lobby and lobby.loadedCount),
        tostring(lobby and lobby.requiredCount), reason))
end

-- Exposto a outros arquivos server-side (events.lua): a entidade pertence ao lobby ativo do jogador?
-- Retorna hasLobby (jogador tem lobby Polarix ativo), matches (entidade registrada pelo servidor no lobby)
function PolarixOwnsEntity(citizenId, ent)
    local jobId = citizenId and PlayerPolarixLobbies[citizenId]
    local lobby = jobId and PolarixLobbies[jobId]
    if not lobby then return false, false end
    if not ent or ent == 0 then return true, false end
    if ent == lobby.truck or ent == lobby.trailer or ent == lobby.forklift or ent == lobby.handler
        or ent == lobby.container or ent == lobby.hoseProp then
        return true, true
    end
    for _, p in ipairs(lobby.pallets or {}) do
        if p == ent then return true, true end
    end
    for _, c in ipairs(lobby.carrierCars or {}) do
        if c == ent then return true, true end
    end
    return true, false
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
                if Config.Debug then print(("[AUST_Trucker] Jogador desconectou durante etapa de pátio. Limpando Job %s"):format(tostring(jobId))) end
                CleanupLobbyEntities(lobby)
                if lobby.citizenId then PlayerPolarixLobbies[lobby.citizenId] = nil end
                PolarixLobbies[jobId] = nil
                break
            end

            -- Verifica se o jogador já iniciou trânsito rodoviário ou saiu de perto do pátio
            local ped = GetPlayerPed(src)
            local pCoords = ped and DoesEntityExist(ped) and GetEntityCoords(ped)
            if lobby.stage == 'STATUS_IN_TRANSIT' or lobby.stage == 'STEP_8_IN_TRANSIT' or (pCoords and #(pCoords - yardCoords) > 120.0) then
                if Config.Debug then print(("[AUST_Trucker] First Step Timer concluído com sucesso para Job %s (Rota iniciada)."):format(tostring(jobId))) end
                break
            end

            local elapsed = os.time() - startTime
            if elapsed >= maxWaitSeconds then
                if Config.Debug then print(("[AUST_Trucker] First Step Timer expirado para Job %s. Cancelando por inatividade de pátio."):format(tostring(jobId))) end
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

function IsEntityAssignedToAnyJob(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end

    -- 1. Verifica se pertence a algum lobby Polarix ativo no servidor
    if PolarixLobbies then
        for _, lobby in pairs(PolarixLobbies) do
            if lobby.truck == ent or lobby.trailer == ent or lobby.forklift == ent
                or lobby.handler == ent or lobby.container == ent or lobby.hoseProp == ent then
                return true
            end
            for _, p in ipairs(lobby.pallets or {}) do
                if p == ent then return true end
            end
            for _, c in ipairs(lobby.carrierCars or {}) do
                if c == ent then return true end
            end
        end
    end

    -- 2. Verifica se possui StateBag de frete ativo (OneSync Infinity)
    local sBag = Entity(ent).state
    if sBag and (sBag.activeJobData or sBag.loadedSlots or sBag.loadedForklift or sBag.isRigLoadingFrozen) then
        return true
    end

    -- 3. Verifica em VP_Trucker.PlayerJobEntities (server/events.lua)
    if VP_Trucker and VP_Trucker.PlayerJobEntities then
        local netId = nil
        pcall(function()
            netId = NetworkGetNetworkIdFromEntity(ent)
        end)
        if netId and netId ~= 0 then
            for _, data in pairs(VP_Trucker.PlayerJobEntities) do
                if data.truckNetId == netId or data.trailerNetId == netId or data.forkliftNetId == netId then
                    return true
                end
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
                    -- Se o veículo estiver ocupado por um jogador, a vaga está ocupada!
                    if IsVehicleOccupiedByPlayer(veh) then
                        if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Vaga em (%.1f, %.1f) ocupada por jogador no veículo %s."):format(targetCoords.x, targetCoords.y, tostring(veh))) end
                        return false
                    end

                    -- Se o veículo pertencer a qualquer trabalho ativo de outro jogador, NÃO DELETAR!
                    if IsEntityAssignedToAnyJob(veh) then
                        if Config.Debug then
                            print(("[AUST_Trucker DEBUG - ETAPA 3] Vaga em (%.1f, %.1f) ocupada por veículo de trabalho ativo (ID: %s, Modelo: %s). Preservando veículo!"):format(
                                targetCoords.x, targetCoords.y, tostring(veh), tostring(GetEntityModel(veh))
                            ))
                        end
                        return false
                    end

                    -- Se não pertence a ninguém e está vazio, pode ser limpo como veículo abandonado do mapa
                    if Config.Debug then
                        print(("[AUST_Trucker DEBUG - ETAPA 3] Deletando veículo abandonado/vazio (ID: %s, Modelo: %s) para desobstruir vaga (%.1f, %.1f)."):format(
                            tostring(veh), tostring(GetEntityModel(veh)), targetCoords.x, targetCoords.y
                        ))
                    end
                    DeleteEntity(veh)
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
    if not citizenId then return end
    citizenId = tostring(citizenId):gsub('^%s*(.-)%s*$', '%1')
    if type(contractData) ~= 'table' then contractData = {} end

    -- SEGURANÇA: o cliente só pode indicar QUAL contrato quer (id), a placa de um veículo próprio
    -- (validada por posse no DB) e preferências limitadas. Todo o resto vem do servidor/Config.
    local clientIn = contractData
    contractData = {
        jobId = clientIn.jobId, contractId = clientIn.contractId, id = clientIn.id,
        truckPlate = (type(clientIn.truckPlate) == 'string' and #clientIn.truckPlate <= 12) and clientIn.truckPlate or nil,
        palletCount = tonumber(clientIn.palletCount),
        clientNoForklift = (clientIn.withForklift == false),
    }

    if ActiveSpawningPlayers[citizenId] then
        if Config.Debug then print(("[AUST_Trucker] Spawn concorrente bloqueado para CitizenId: %s (Lock ativo)"):format(tostring(citizenId))) end
        return
    end
    ActiveSpawningPlayers[citizenId] = true

    SetTimeout(15000, function()
        if ActiveSpawningPlayers[citizenId] then
            ActiveSpawningPlayers[citizenId] = nil
        end
    end)

    if Config.Debug then
        print(("[AUST_Trucker DEBUG - ETAPA 2] Recebida solicitação de início no Servidor! Src: %s, CitizenId: %s, ContractData: %s"):format(
            tostring(src), tostring(citizenId), json.encode(contractData)
        ))
    end

    -- Auto-limpeza de lobby fantasma prévio se as entidades não existirem mais
    if PlayerPolarixLobbies[citizenId] then
        local oldJobId = PlayerPolarixLobbies[citizenId]
        local oldLobby = PolarixLobbies[oldJobId]
        local isStillAlive = oldLobby and (
            (oldLobby.truck and DoesEntityExist(oldLobby.truck)) or
            (oldLobby.trailer and DoesEntityExist(oldLobby.trailer))
        )
        if not isStillAlive then
            if Config.Debug then print(("[AUST_Trucker DEBUG] Limpando lobby anterior fantasma/abandonado para CitizenId: %s"):format(tostring(citizenId))) end
            CleanupLobbyEntities(oldLobby)
            PolarixLobbies[oldJobId] = nil
            PlayerPolarixLobbies[citizenId] = nil
        else
            ActiveSpawningPlayers[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Contrato em Andamento', 'Você já possui uma rota ou contrato em andamento!', 'error')
            return
        end
    end

    -- Dados do contrato derivados SOMENTE do servidor (rota customizada do admin ou Config.LC_Jobs)
    local srvForkliftFlag = nil
    if contractData.jobId or contractData.contractId or contractData.id then
        local rawId = contractData.jobId or contractData.contractId or contractData.id
        local numId = tonumber(rawId)

        local customRoute = AdminService and AdminService.CustomRoutes and (AdminService.CustomRoutes[rawId] or (numId and AdminService.CustomRoutes[numId]))
        if customRoute then
            contractData.name = customRoute.name or customRoute.title
            contractData.trailerModel = customRoute.trailer_model
            contractData.truckModel = customRoute.truck_model
            contractData.cargoType = customRoute.type
            contractData.cargoName = customRoute.cargo_name
            contractData.cargoModel = customRoute.cargo_model
            contractData.distance = customRoute.distance
            contractData.payment = customRoute.base_payment
            contractData.xp = customRoute.base_xp
            contractData.pickupCoords = customRoute.pickup_coords
            contractData.deliveryCoords = customRoute.delivery_coords
            contractData.level_required = customRoute.req_skill or customRoute.required_level
            if customRoute.has_forklift ~= nil then
                srvForkliftFlag = (customRoute.has_forklift == 1 or customRoute.has_forklift == true)
            end
        elseif numId and Config.LC_Jobs and Config.LC_Jobs.available_loads and Config.LC_Jobs.available_loads[numId] then
            local load = Config.LC_Jobs.available_loads[numId]
            contractData.name = load.name
            contractData.palletCount = contractData.palletCount or 4
            contractData.trailerModel = load.trailer
        end
    end
    -- withForklift: valor do servidor; o cliente só pode abrir mão da empilhadeira (sujeito à taxa de descarga)
    contractData.withForklift = (srvForkliftFlag ~= false) and not contractData.clientNoForklift
    if type(contractData.level_required) ~= 'number' then contractData.level_required = tonumber(contractData.level_required) end

    -- Consulta nível autoritativo unificado (trucker_player_progression + 0r_trucker)
    local pStats = nil
    if DB_GetPlayerStats then
        pcall(function() pStats = DB_GetPlayerStats(citizenId) end)
    end
    if not pStats then
        pStats = MySQL.single.await('SELECT level, xp FROM trucker_player_progression WHERE citizenid = ?', { citizenId })
    end
    local levelProg = pStats and tonumber(pStats.level) or 1
    local truckerRow = MySQL.single.await('SELECT level, xp FROM `0r_trucker` WHERE `citizenid` = ?', { citizenId })
    local level0r = truckerRow and tonumber(truckerRow.level) or 1
    local playerLevel = math.max(levelProg, level0r)
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
        -- SEGURANÇA: modelo só vem do servidor (rota admin) e precisa estar na whitelist de modelos permitidos
        local allowedTrucks = GetAllowedTruckModels()
        local wanted = contractData.truckModel
        if type(wanted) ~= 'string' or not allowedTrucks[wanted:lower()] then
            wanted = nil
        end
        selectedTruckModel = wanted or (Config.Truck and Config.Truck.model) or 'hauler'
        if type(selectedTruckModel) ~= 'string' or not allowedTrucks[selectedTruckModel:lower()] then
            selectedTruckModel = 'hauler'
        end
        selectedPlate = ('RENT%04d'):format(math.random(1000, 9999))
        isOwned = false
    end

    if not selectedPlate or selectedPlate == '' then
        selectedPlate = ('TRK%05d'):format(math.random(10000, 99999))
    end

    local jobId = NewPolarixJobId()
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
        elseif tModel == 'freighttrailer' or tModel == 'docktrailer' or string.find(tModel, 'contr') or string.find(cName, 'conteiner') or string.find(cName, 'contêiner') or string.find(cName, 'container') or string.find(cName, 'heavy') or string.find(cName, 'pesad') then
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
        local function isTruthy(val)
            return val == 1 or val == true or val == '1' or tostring(val) == '1' or tostring(val):lower() == 'true'
        end
        local hasHeavy = licRow and isTruthy(licRow.heavy_certified)
        local hasAdr   = licRow and isTruthy(licRow.adr_certified)

        if cargoType == 'heavy' and not hasHeavy then
            ActiveSpawningPlayers[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Licença Obrigatória', 'Você precisa da Certificação Heavy Lift Operator para aceitar fretes de contêiner!', 'error')
            return
        elseif cargoType == 'adr' and not hasAdr then
            ActiveSpawningPlayers[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Licença Obrigatória', 'Você precisa da Certificação ADR Specialist para transportar materiais perigosos/químicos!', 'error')
            return
        end
    end

    local typeConfig = Config.CargoTypes and Config.CargoTypes[cargoType]
    if not typeConfig then typeConfig = Config.CargoTypes.dry end

    local requestedTrailer = contractData.trailerModel or typeConfig.defaultTrailer
    -- OBRIGATORIEDADE ABSOLUTA: Todos os trabalhos voltados a contêiner / carga pesada devem spawnar com freighttrailer
    if cargoType == 'heavy' then
        requestedTrailer = 'freighttrailer'
    end
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
            fallbackModel = 'freighttrailer'
        end
        requestedTrailer = typeConfig.defaultTrailer or fallbackModel
        trailerModel = joaat(requestedTrailer)
    end

    -- STEP A: SPAWN AND PLATE ENFORCEMENT
    local plate = selectedPlate
    if not plate or plate == '' then
        plate = ("TRK%04d"):format(math.random(1000, 9999))
    end

    -- Iteração dinâmica com verificação de área livre no servidor (OneSync)
    local dynamicTruckSpawns = (AdminService and AdminService.GetSpawnsByType and AdminService.GetSpawnsByType('truck', contractData and contractData.spawn_folder)) or {}
    local truckSpawns = (#dynamicTruckSpawns > 0 and dynamicTruckSpawns) or wh.TruckSpawns or { wh.TruckSpawnCoords }
    local truck = nil
    local chosenTruckCoord = nil

    if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Buscando vaga livre para caminhão (Modelo: %s, Placa: %s)..."):format(selectedTruckModel, plate)) end

    for idx, coord in ipairs(truckSpawns) do
        if IsSpawnPointClear(coord, 4.5) then
            truck = CreateVehicle(truckModel, coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(truck) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
            if DoesEntityExist(truck) then
                chosenTruckCoord = coord
                if Config.Debug then
                    print(("[AUST_Trucker DEBUG - ETAPA 3] Caminhão criado com sucesso na vaga %d. NetID: %s"):format(
                        idx, tostring(NetworkGetNetworkIdFromEntity(truck))
                    ))
                end
                break
            end
        end
    end

    -- Fallback: Se nenhuma vaga esteve livre no loop inicial
    if not truck or not DoesEntityExist(truck) then
        if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Todas as vagas primárias ocupadas para caminhão!")):format() end
        ActiveSpawningPlayers[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Todas as vagas de caminhão estão ocupadas no momento. Aguarde a liberação do pátio.', 'error')
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

    if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Caminhão destrancado com chaves entregues. Placa: %s, Jogador: %s"):format(plate, tostring(src))) end

    -- STEP B: TRAILER SPAWN
    local dynamicTrailerSpawns = (AdminService and AdminService.GetSpawnsByType and AdminService.GetSpawnsByType('trailer', contractData and contractData.spawn_folder)) or {}
    local trailerSpawns = (#dynamicTrailerSpawns > 0 and dynamicTrailerSpawns) or Config.TrailerSpawns or (wh and wh.TrailerSpawns) or { wh.TrailerSpawnCoords }
    local trailer = nil
    local chosenTrailerCoord = nil

    if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Buscando vaga livre para carreta (Modelo: %s)..."):format(requestedTrailer)) end

    for idx, coord in ipairs(trailerSpawns) do
        local distToTruck = chosenTruckCoord and #(vector3(coord.x, coord.y, coord.z) - vector3(chosenTruckCoord.x, chosenTruckCoord.y, chosenTruckCoord.z)) or 999.0
        if distToTruck >= 14.0 and IsSpawnPointClear(coord, 5.0) then
            trailer = CreateVehicle(trailerModel, coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(trailer) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
            if DoesEntityExist(trailer) then
                chosenTrailerCoord = coord
                if Config.Debug then
                    print(("[AUST_Trucker DEBUG - ETAPA 3] Carreta criada com sucesso na vaga %d. NetID: %s (Distância do Cavalo: %.1fm)"):format(
                        idx, tostring(NetworkGetNetworkIdFromEntity(trailer)), distToTruck
                    ))
                end
                break
            end
        end
    end

    if not trailer or not DoesEntityExist(trailer) then
        if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Todas as vagas primárias de carreta ocupadas!")):format() end
        ActiveSpawningPlayers[citizenId] = nil
        if DoesEntityExist(truck) then DeleteEntity(truck) end
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Todas as vagas de carreta/reboque estão ocupadas no momento. Aguarde a liberação do pátio.', 'error')
        return
    end

    if not trailer or not DoesEntityExist(trailer) then
        ActiveSpawningPlayers[citizenId] = nil
        if DoesEntityExist(truck) then DeleteEntity(truck) end
        TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Falha ao instanciar carreta/reboque no servidor.', 'error')
        return
    end

    SetVehicleDoorsLocked(trailer, 1)

    -- Para cargas pesadas/contêiner: desativa extras para garantir chassi limpo sem contêiner pré-moldado
    if cargoType == 'heavy' then
        for extraId = 1, 14 do
            pcall(function() SetVehicleExtra(trailer, extraId, 1) end)
        end
    end


    -- ETAPA 3: Spawn Condicional (Empilhadeira vs Reach Stacker)
    local forklift = nil
    local forkliftPlate = nil
    local chosenForkliftCoord = nil
    local handler = nil
    local handlerPlate = nil
    local chosenHandlerCoord = nil
    local containerObj = nil
    local containerNetId = nil
    local containers = {}
    local containerNetIds = {}
    local carrierCars = {}
    local carrierVehicleNetIds = {}
    local pallets = {}
    local palletNetIds = {}
    local withForklift = (contractData.withForklift ~= false)
    local maxAllowedPallets = withForklift and 6 or 7

    -- Quantidade dinâmica de props definida no offset ou no contrato
    local dynamicPropCount = nil
    local cModel = contractData.cargoModel or contractData.cargo_model
    if AdminService and AdminService.GetOffsetsForTrailerAndCargo then
        local tOffsets = AdminService.GetOffsetsForTrailerAndCargo(tostring(requestedTrailer or trailerModel):lower(), cModel)
        if tOffsets and tOffsets.prop_count and tonumber(tOffsets.prop_count) and tonumber(tOffsets.prop_count) > 0 then
            dynamicPropCount = tonumber(tOffsets.prop_count)
        end
    end
    if not dynamicPropCount and AdminService and AdminService.TrailerOffsets then
        local tOffsets = AdminService.TrailerOffsets[tostring(requestedTrailer or trailerModel):lower()]
        if tOffsets and tOffsets.prop_count and tonumber(tOffsets.prop_count) and tonumber(tOffsets.prop_count) > 0 then
            dynamicPropCount = tonumber(tOffsets.prop_count)
        end
    end
    if not dynamicPropCount and contractData.prop_count and tonumber(contractData.prop_count) and tonumber(contractData.prop_count) > 0 then
        dynamicPropCount = tonumber(contractData.prop_count)
    end

    local reqPallets = dynamicPropCount and math.min(maxAllowedPallets, math.max(1, dynamicPropCount)) or math.min(maxAllowedPallets, math.max(1, tonumber(contractData.palletCount) or 4))

    if cargoType == 'dry' then
        local dynamicForkSpawns = (AdminService and AdminService.GetSpawnsByType and AdminService.GetSpawnsByType('forklift', contractData and contractData.spawn_folder)) or {}
        local forkliftSpawns = (#dynamicForkSpawns > 0 and dynamicForkSpawns) or wh.ForkliftSpawns or { wh.ForkliftBayCoords }

        for idx, coord in ipairs(forkliftSpawns) do
            if IsSpawnPointClear(coord, 3.5, { [truck] = true, [trailer] = true }) then
                forklift = CreateVehicle(joaat(Config.Polarix.Forklift.VehicleModel or 'forklift'), coord.x, coord.y, coord.z + 0.5, coord.w or 90.0, true, true)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(forklift) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
                if DoesEntityExist(forklift) then
                    chosenForkliftCoord = coord
                    if Config.Debug then
                        print(("[AUST_Trucker DEBUG - ETAPA 3] Empilhadeira criada na vaga %d. NetID: %s (Embarque rodoviário: %s)"):format(
                            idx, tostring(NetworkGetNetworkIdFromEntity(forklift)), tostring(withForklift)
                        ))
                    end
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

        -- Spawn de Paletes Pré-Gerados (Polarix com Suporte a Props Customizados do Admin)
        local dynamicPalletSpawns = (AdminService and AdminService.GetSpawnsByType and AdminService.GetSpawnsByType('pallet', contractData and contractData.spawn_folder)) or {}
        local rawPalletSpawns = (#dynamicPalletSpawns > 0 and dynamicPalletSpawns) or wh.PalletSpawns or {}
        local palletSpawns = {}
        for _, rawC in ipairs(rawPalletSpawns) do
            local px = tonumber(rawC.x)
            local py = tonumber(rawC.y)
            local pz = tonumber(rawC.z)
            if px and py and pz then
                table.insert(palletSpawns, vector3(px, py, pz))
            end
        end

        local ignoreEntities = { [truck] = true, [trailer] = true, [forklift] = true }

        local function ResolveCargoPropHash(slotIdx)
            local tOffsets = nil
            local reqKey = tostring(requestedTrailer or ''):lower()
            local cModel = contractData.cargoModel or contractData.cargo_model
            if AdminService and AdminService.GetOffsetsForTrailerAndCargo then
                tOffsets = AdminService.GetOffsetsForTrailerAndCargo(reqKey, cModel)
            elseif AdminService and AdminService.TrailerOffsets then
                tOffsets = AdminService.TrailerOffsets[reqKey]
                    or AdminService.TrailerOffsets[requestedTrailer]
                    or AdminService.TrailerOffsets[trailerModel]
            end
            local slotData = tOffsets and tOffsets.pallets and (tOffsets.pallets[slotIdx] or tOffsets.pallets[tostring(slotIdx)])
            local candidate = (slotData and slotData.prop_model and slotData.prop_model ~= '' and slotData.prop_model)
                or cModel
                or contractData.cargo_model
                or (Config.Polarix and Config.Polarix.PalletModels and Config.Polarix.PalletModels[((slotIdx - 1) % #Config.Polarix.PalletModels) + 1])
                or (Config.Polarix and Config.Polarix.DefaultPalletModel)
                or 'hei_prop_carrier_cargo_04b'

            local finalHash = nil
            if type(candidate) == 'number' then
                finalHash = candidate
            else
                local asNum = tonumber(candidate)
                if asNum then
                    finalHash = asNum
                else
                    finalHash = joaat(tostring(candidate))
                end
            end

            if not finalHash or finalHash == 0 then
                finalHash = joaat('hei_prop_carrier_cargo_04b')
            end
            return finalHash
        end

        for _, coord in ipairs(palletSpawns) do
            if #pallets >= reqPallets then break end
            local slotTargetIdx = #pallets + 1
            local pModel = ResolveCargoPropHash(slotTargetIdx)
            local pObj = CreateObject(pModel, coord.x, coord.y, coord.z + 0.15, true, true, false)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
            if DoesEntityExist(pObj) then
                FreezeEntityPosition(pObj, true)
                LockEntityNetworkOwner(pObj, src)
                SetEntityDistanceCullingRadius(pObj, 450.0)
                local pNet = NetworkGetNetworkIdFromEntity(pObj)
                if pNet and pNet ~= 0 then
                    table.insert(palletNetIds, pNet)
                end
                ignoreEntities[pObj] = true
                table.insert(pallets, pObj)
            else
                -- Fallback imediato com prop nativo padrão caso o prop customizado falhe no streaming do servidor
                local fallbackObj = CreateObject(joaat('hei_prop_carrier_cargo_04b'), coord.x, coord.y, coord.z + 0.15, true, true, false)
                local fbTimer = GetGameTimer()
                while not DoesEntityExist(fallbackObj) and (GetGameTimer() - fbTimer < 3000) do Wait(50) end
                if DoesEntityExist(fallbackObj) then
                    FreezeEntityPosition(fallbackObj, true)
                    LockEntityNetworkOwner(fallbackObj, src)
                    SetEntityDistanceCullingRadius(fallbackObj, 450.0)
                    local fbNet = NetworkGetNetworkIdFromEntity(fallbackObj)
                    if fbNet and fbNet ~= 0 then
                        table.insert(palletNetIds, fbNet)
                    end
                    ignoreEntities[fallbackObj] = true
                    table.insert(pallets, fallbackObj)
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

                local pModel = ResolveCargoPropHash(i)
                local pObj = CreateObject(pModel, pos.x, pos.y, pos.z + 0.15, true, true, false)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(pObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
                if DoesEntityExist(pObj) then
                    FreezeEntityPosition(pObj, true)
                    LockEntityNetworkOwner(pObj, src)
                    SetEntityDistanceCullingRadius(pObj, 450.0)
                    local pNet = NetworkGetNetworkIdFromEntity(pObj)
                    if pNet and pNet ~= 0 then
                        table.insert(palletNetIds, pNet)
                    end
                    ignoreEntities[pObj] = true
                    table.insert(pallets, pObj)
                else
                    local fallbackObj = CreateObject(joaat('hei_prop_carrier_cargo_04b'), pos.x, pos.y, pos.z + 0.15, true, true, false)
                    local fbTimer = GetGameTimer()
                    while not DoesEntityExist(fallbackObj) and (GetGameTimer() - fbTimer < 3000) do Wait(50) end
                    if DoesEntityExist(fallbackObj) then
                        FreezeEntityPosition(fallbackObj, true)
                        LockEntityNetworkOwner(fallbackObj, src)
                        SetEntityDistanceCullingRadius(fallbackObj, 450.0)
                        local fbNet = NetworkGetNetworkIdFromEntity(fallbackObj)
                        if fbNet and fbNet ~= 0 then
                            table.insert(palletNetIds, fbNet)
                        end
                        ignoreEntities[fallbackObj] = true
                        table.insert(pallets, fallbackObj)
                    end
                end
            end
        end

        if Config.Debug or #pallets < reqPallets then
            print(("[AUST_Trucker] %d/%d Paletes instanciados para o frete (NetIDs: %d)."):format(#pallets, reqPallets, #palletNetIds))
        end

    elseif cargoType == 'heavy' then
        reqPallets = 1
        local yardCfg = (Config.CargoTypes and Config.CargoTypes.heavy and Config.CargoTypes.heavy.yard) or {}
        local dynamicHandlerSpawns = (AdminService and AdminService.GetSpawnsByType and AdminService.GetSpawnsByType('handler', contractData and contractData.spawn_folder)) or {}
        local handlerSpawns = (#dynamicHandlerSpawns > 0 and dynamicHandlerSpawns) or yardCfg.handlerSpawns or { wh.HandlerBayCoords or vector4(1130.11, -3083.45, 6.01, 269.29) }

        for idx, coord in ipairs(handlerSpawns) do
            if IsSpawnPointClear(coord, 5.0, { [truck] = true, [trailer] = true }) then
                handler = CreateVehicle(joaat(Config.Polarix.Handler.VehicleModel or 'handler'), coord.x, coord.y, coord.z + 0.5, coord.w or 270.0, true, true)
                local waitTimer = GetGameTimer()
                while not DoesEntityExist(handler) and (GetGameTimer() - waitTimer < 5000) do Wait(10) end
                if DoesEntityExist(handler) then
                    chosenHandlerCoord = coord
                    if Config.Debug then
                        print(("[AUST_Trucker DEBUG - ETAPA 3] Reach Stacker criado na vaga %d. NetID: %s"):format(
                            idx, tostring(NetworkGetNetworkIdFromEntity(handler))
                        ))
                    end
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

        -- Spawn do Contêiner (Suporte a 40ft único ou 20ft duplo)
        local cSpawns = yardCfg.containerSpawns or {
            vector4(1178.15, -3115.13, 5.02, 266.0),
            vector4(1185.25, -3115.13, 5.02, 266.0)
        }
        local cModel = joaat(contractData.cargoModel or Config.Polarix.ContainerModel or 'prop_contr_03b_ld')
        local numContainers = tonumber(contractData.containerCount) or (contractData.name and contractData.name:lower():find('duplo') and 2) or 1
        reqPallets = numContainers
        containers = {}
        containerNetIds = {}

        for cIdx = 1, numContainers do
            local chosenCCoord = cSpawns[cIdx] or cSpawns[1]
            local cObj = CreateObject(cModel, chosenCCoord.x, chosenCCoord.y, chosenCCoord.z + 0.1, true, true, false)
            local waitTimer = GetGameTimer()
            while not DoesEntityExist(cObj) and (GetGameTimer() - waitTimer < 5000) do Wait(50) end
            if DoesEntityExist(cObj) then
                FreezeEntityPosition(cObj, true)
                local cNet = NetworkGetNetworkIdFromEntity(cObj)
                table.insert(containers, cObj)
                table.insert(containerNetIds, cNet)
                LockEntityNetworkOwner(cObj, src)
                if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] Contêiner %d gerado com sucesso. NetID: %s"):format(cIdx, tostring(cNet))) end
            end
        end
        containerObj = containers[1]
        containerNetId = containerNetIds[1]
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
        if Config.Debug then print(("[AUST_Trucker DEBUG - ETAPA 3] %d Veículos instanciados no pátio para a Cegonha."):format(#carrierCars)) end
    else
        reqPallets = 100 -- Carga Líquida e ADR
    end

    local destCfg = Config.Polarix.DeliveryDestinations[math.random(#Config.Polarix.DeliveryDestinations)]
    local destCoords = destCfg.coords

    -- Consulta autoritativa da tabela de Economia e Rotas do painel admin
    local eco = (AdminService and AdminService.Economy) or {}
    local kmPay = eco.base_payment_per_km or eco.km_multiplier or 18.5
    local kmXP = eco.base_xp_per_km or eco.xp_multiplier or 5.0
    local estDistance = (chosenTruckCoord and destCoords) and (math.max(1.0, math.floor(#(vector3(destCoords.x, destCoords.y, destCoords.z) - vector3(chosenTruckCoord.x, chosenTruckCoord.y, chosenTruckCoord.z)) / 100.0) / 10.0)) or 3.5

    local basePayment = tonumber(contractData.payment) or tonumber(contractData.base_payment)
    if not basePayment or basePayment <= 0 then
        basePayment = math.floor(estDistance * kmPay * 100 + (eco.base_salary or 1200))
    end
    if not basePayment or basePayment <= 0 then
        basePayment = destCfg.reward or 5000
    end

    local baseXP = tonumber(contractData.xp) or tonumber(contractData.base_xp)
    if not baseXP or baseXP <= 0 then
        baseXP = math.floor(estDistance * kmXP * 15 + 150)
    end
    if not baseXP or baseXP <= 0 then
        baseXP = destCfg.xp or 200
    end

    -- Bônus de remuneração e XP por paletes extras (> 4)
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
        routeId = contractData.id or contractData.route_id or nil,
        spawnFolder = contractData.spawn_folder or 'Geral',
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
        containers = containers,
        containerNetIds = containerNetIds,
        carrierCars = carrierCars,
        vehicleNetIds = carrierVehicleNetIds,
        pallets = pallets,
        palletNetIds = palletNetIds,
        loadedCount = 0,
        requiredCount = reqPallets,
        cargoName = contractData.name or (cargoType == 'liquid' and 'Combustível Automotivo' or (cargoType == 'heavy' and 'Contêiner Marítimo' or (cargoType == 'adr' and 'Compostos Químicos ADR' or (cargoType == 'vehicle_carrier' and 'Cegonha de Veículos Esportivos' or 'Paletes Industriais')))),
        cargoModel = (function()
            local cm = contractData.cargoModel or contractData.cargo_model
            if cm and cm ~= '' then return cm end
            local tOffsets = (AdminService and AdminService.GetOffsetsForTrailerAndCargo and AdminService.GetOffsetsForTrailerAndCargo(requestedTrailer or trailerModel, cm))
                or (AdminService and AdminService.TrailerOffsets and (AdminService.TrailerOffsets[requestedTrailer] or AdminService.TrailerOffsets[trailerModel]))
            local s1 = tOffsets and tOffsets.pallets and (tOffsets.pallets[1] or tOffsets.pallets['1'])
            if s1 and s1.prop_model and s1.prop_model ~= '' then return s1.prop_model end
            return 'hei_prop_carrier_cargo_04b'
        end)(),
        cargoIntegrity = 100,
        payment = basePayment,
        xp = baseXP,
        distance = (chosenTruckCoord and destCoords) and (math.max(1.0, math.floor(#(vector3(destCoords.x, destCoords.y, destCoords.z) - vector3(chosenTruckCoord.x, chosenTruckCoord.y, chosenTruckCoord.z)) / 100.0) / 10.0)) or 3.5,
        deliveryCoords = destCoords,
        stage = 'STEP_GET_TRUCK',
        current_object = nil,
        hoseProp = nil,
        hoseConnected = false
    }

    PolarixLobbies[jobId] = lobbyData
    PlayerPolarixLobbies[citizenId] = jobId

    -- BLINDAGEM ONESYNC: Trava de Autoridade Server-Side no Motorista (A1)
    -- Impede que observadores próximos roubem a propriedade de rede das entidades da carga
    LockEntityNetworkOwner(truck, src)
    LockEntityNetworkOwner(trailer, src)
    if forklift and DoesEntityExist(forklift) then
        LockEntityNetworkOwner(forklift, src)
    end
    if handler and DoesEntityExist(handler) then
        LockEntityNetworkOwner(handler, src)
    end
    if containerObj and DoesEntityExist(containerObj) then
        LockEntityNetworkOwner(containerObj, src)
    end
    if carrierCars and #carrierCars > 0 then
        for _, car in ipairs(carrierCars) do
            if DoesEntityExist(car) then LockEntityNetworkOwner(car, src) end
        end
    end
    if pallets and #pallets > 0 then
        for _, pObj in ipairs(pallets) do
            if DoesEntityExist(pObj) then LockEntityNetworkOwner(pObj, src) end
        end
    end

    -- StateBag Autoritativo Global de Frete (OneSync Infinity)
    if truck and DoesEntityExist(truck) then
        Entity(truck).state:set('activeJobData', {
            jobId = jobId,
            citizenId = citizenId,
            cargoType = cargoType,
            cargoName = lobbyData.cargoName,
            isOwned = isOwned,
            plate = plate,
            stage = 'STEP_GET_TRUCK',
            payment = basePayment,
            xp = baseXP
        }, true)
    end
    if _G.Player and _G.Player(src) then
        _G.Player(src).state:set('activeJobId', jobId, true)
    end

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
        containerNetIds = containerNetIds,
        vehicleNetIds = carrierVehicleNetIds,
        palletNetIds = palletNetIds,
        withForklift = withForklift,
        cargoName = lobbyData.cargoName,
        cargoModel = lobbyData.cargoModel,
        requiredCount = reqPallets,
        loadedCount = 0,
        deliveryCoords = destCoords,
        trailerModel = requestedTrailer or contractData.trailerModel,
        trailerOffsets = (AdminService and AdminService.GetOffsetsForTrailerAndCargo and AdminService.GetOffsetsForTrailerAndCargo(requestedTrailer or contractData.trailerModel, contractData.cargoModel or contractData.cargo_model))
            or (AdminService and AdminService.TrailerOffsets and (AdminService.TrailerOffsets[requestedTrailer or contractData.trailerModel]))
            or (Config.TrailerSlots and Config.TrailerSlots[requestedTrailer or contractData.trailerModel])
            or {}
    }

    if Config.Debug then
        print(("[AUST_Trucker DEBUG - ETAPA 4] Enviando aurp_trucker:client:polarixJobStarted para jogador %s (JobID: %s, TruckNetId: %s, TrailerNetId: %s, Cargo: %s)"):format(
            tostring(src), tostring(jobId), tostring(payload.truckNetId), tostring(payload.trailerNetId), tostring(cargoType)
        ))
    end

    ActiveSpawningPlayers[citizenId] = nil

    -- Replicar paletes ativos no StateBag da Carreta e no GlobalState (OneSync Infinity para Observadores)
    if palletNetIds and #palletNetIds > 0 then
        if trailer and DoesEntityExist(trailer) then
            Entity(trailer).state:set('missionPalletNetIds', palletNetIds, true)
        end
        local currentGlobal = GlobalState.activeTruckerPallets or {}
        local updatedGlobal = {}
        for _, n in ipairs(currentGlobal) do table.insert(updatedGlobal, n) end
        for _, n in ipairs(palletNetIds) do table.insert(updatedGlobal, n) end
        GlobalState.activeTruckerPallets = updatedGlobal
    end

    TriggerClientEvent('aurp_trucker:client:polarixJobStarted', src, payload)
    TriggerClientEvent('aurp_trucker:client:polarixSyncPallets', src, palletNetIds, jobId)

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
    -- Máquina de estados: inspeção só é válida antes do carregamento começar
    if lobby.stage ~= 'STEP_GET_TRUCK' and not (lobby.stage == 'STATUS_LOADING' and (lobby.loadedCount or 0) == 0) then return end
    if not lobby.truck or not DoesEntityExist(lobby.truck) then return end

    -- Validação de proximidade autoritativa do servidor (6.0m máximo)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
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
local function HandlePalletLoaded(src, jobId, slotIndex, palletNetId, slotOffset, slotHeading)
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then
        PolarixReject('palletLoaded', jobId, lobby, 'lobby inexistente ou de outro jogador')
        return
    end
    if lobby.cargoType ~= 'dry' then
        PolarixReject('palletLoaded', jobId, lobby, 'cargoType ' .. tostring(lobby.cargoType) .. ' não é dry')
        return
    end

    local required = lobby.requiredCount or 0

    -- Recuperação de palete perdido em trânsito: apenas devolve a perda (nunca soma além do total)
    if lobby.stage == 'STATUS_IN_TRANSIT' then
        if (lobby.lostPallets or 0) > 0 then
            lobby.lostPallets = lobby.lostPallets - 1
        end
        return
    end

    -- Máquina de estados: palete só é aceito durante o carregamento e até o total exigido
    if not EnterLoadingStage(lobby) then
        PolarixReject('palletLoaded', jobId, lobby, 'estágio não permite carregamento')
        return
    end
    if (lobby.loadedCount or 0) >= required then
        PolarixReject('palletLoaded', jobId, lobby, 'todos os paletes já foram contados')
        return
    end

    -- Valida distância do jogador até a carreta (anti-spam remoto)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not lobby.trailer or not DoesEntityExist(lobby.trailer) then
        PolarixReject('palletLoaded', jobId, lobby, 'ped ou carreta inexistente no servidor')
        return
    end
    local trailerDist = #(GetEntityCoords(ped) - GetEntityCoords(lobby.trailer))
    if trailerDist > 40.0 then
        PolarixReject('palletLoaded', jobId, lobby, ('jogador a %.1fm da carreta (máx 40)'):format(trailerDist))
        return
    end

    -- Rate limit leve por lobby (um palete a cada 1s no mínimo)
    local nowMs = GetGameTimer()
    if lobby.lastPalletAt and (nowMs - lobby.lastPalletAt) < 1000 then
        PolarixReject('palletLoaded', jobId, lobby, 'rate limit (1 palete/s)')
        return
    end

    -- Slot: inteiro dentro do total e ainda não utilizado
    slotIndex = tonumber(slotIndex)
    if slotIndex and (slotIndex ~= slotIndex or slotIndex < 1 or slotIndex > required or slotIndex % 1 ~= 0) then
        PolarixReject('palletLoaded', jobId, lobby, 'slot ' .. tostring(slotIndex) .. ' fora de 1..' .. tostring(required))
        return
    end
    lobby.usedSlots = lobby.usedSlots or {}
    if slotIndex and lobby.usedSlots[slotIndex] then
        PolarixReject('palletLoaded', jobId, lobby, 'slot ' .. tostring(slotIndex) .. ' já usado')
        return
    end

    -- netId do palete: precisa ser um dos paletes gerados pelo servidor para este lobby
    if palletNetId ~= nil then
        local found = false
        for _, nid in ipairs(lobby.palletNetIds or {}) do
            if nid == palletNetId then found = true break end
        end
        if not found then
            PolarixReject('palletLoaded', jobId, lobby, 'netId ' .. tostring(palletNetId) .. ' não é palete deste lobby')
            return
        end
    end

    -- Offset/heading vêm do cliente: saneia e limita
    local function clampN(v, lim, def)
        v = tonumber(v)
        if not IsFiniteNumber(v) then return def end
        return math.max(-lim, math.min(lim, v))
    end
    if type(slotOffset) ~= 'table' then slotOffset = nil end
    if slotOffset then
        slotOffset = { x = clampN(slotOffset.x, 6.0, 0.0), y = clampN(slotOffset.y, 12.0, 0.0), z = clampN(slotOffset.z, 6.0, 0.35) }
    end
    slotHeading = clampN(slotHeading, 360.0, 0.0)

    lobby.lastPalletAt = nowMs
    if slotIndex then lobby.usedSlots[slotIndex] = true end
    lobby.loadedCount = (lobby.loadedCount or 0) + 1
    lobby.current_object = slotIndex

    if lobby.pallets then
        for _, pObj in ipairs(lobby.pallets) do
            if DoesEntityExist(pObj) then
                FreezeEntityPosition(pObj, false)
            end
        end
    end

    -- Sincronização Autoritativa OneSync Infinity (Pilar 2: StateBags)
    if lobby.trailer and DoesEntityExist(lobby.trailer) then
        local trailerEnt = lobby.trailer
        local pNet = palletNetId
        if not pNet and lobby.palletNetIds and lobby.palletNetIds[slotIndex or lobby.loadedCount] then
            pNet = lobby.palletNetIds[slotIndex or lobby.loadedCount]
        end

        local curSlots = Entity(trailerEnt).state.loadedSlots or {}
        local sKey = tostring(slotIndex or lobby.loadedCount)
        local off = slotOffset or { x = 0.0, y = 0.0, z = 0.35 }
        local h = slotHeading or 0.0

        curSlots[sKey] = {
            palletNet = pNet,
            offset = { x = off.x, y = off.y, z = off.z },
            heading = h
        }
        Entity(trailerEnt).state:set('loadedSlots', curSlots, true)

        if pNet then
            local pEnt = NetworkGetEntityFromNetworkId(pNet)
            if pEnt and DoesEntityExist(pEnt) then
                LockEntityNetworkOwner(pEnt, src)
            end
        end
    end

    TriggerClientEvent('aurp_trucker:client:polarixProgressSync', src, lobby.loadedCount, lobby.requiredCount)
    TriggerClientEvent('aurp_trucker:client:dryProgressSync', src, lobby.loadedCount, lobby.requiredCount)

    if lobby.loadedCount < lobby.requiredCount then
        TriggerClientEvent('aurp_trucker:notify', src, 'Central Logística', ("Palete acomodado com sucesso! (%d/%d). Continue o carregamento."):format(lobby.loadedCount, lobby.requiredCount), 'info')
    else
        lobby.stage = 'STEP_STRAPPING'
        TriggerClientEvent('aurp_trucker:notify', src, 'Central Logística', 'Todos os paletes foram estivados com sucesso!', 'success')
    end
end

RegisterNetEvent('aurp_trucker:server:polarixPalletLoaded', function(jobId, slotIndex, palletNetId, slotOffset, slotHeading)
    HandlePalletLoaded(source, jobId, slotIndex, palletNetId, slotOffset, slotHeading)
end)

RegisterNetEvent('aurp_trucker:server:attachPalletToTrailer', function(jobId, slotIndex, palletNetId, slotOffset, slotHeading)
    HandlePalletLoaded(source, jobId, slotIndex, palletNetId, slotOffset, slotHeading)
end)

-- =======================================================================
-- SISTEMA DE CARGA LÍQUIDA: GERENCIAMENTO DE MANGUEIRA E ABASTECIMENTO
-- =======================================================================

-- 1. Pegar Mangueira na Bomba
RegisterNetEvent('aurp_trucker:server:pickupHose', function(jobId, terminalId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if not EnterLoadingStage(lobby) then return end

    if lobby.cargoType ~= 'liquid' then return end
    if lobby.hoseConnected then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    -- Validação de proximidade autoritativa do terminal (terminal inexistente = rejeita)
    local terminal = FindFuelTerminal(terminalId)
    if not terminal or not terminal.coords then
        TriggerClientEvent('aurp_trucker:notify', src, 'Terminal', 'Terminal de combustível inválido.', 'error')
        return
    end
    if #(pCoords - terminal.coords) > 15.0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Distância', 'Você está muito afastado da bomba para retirar a mangueira!', 'error')
        return
    end

    -- Reentrância: um prop de mangueira por lobby (evita criar um por chamada)
    if lobby.hoseCreating then return end
    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end
    lobby.hoseProp = nil
    lobby.hoseCreating = true

    -- Criação OneSync autoritativa do prop de mangueira no routing bucket do jogador
    local hoseModel = joaat('prop_cs_fuel_nozle')
    local hoseObj = CreateObject(hoseModel, pCoords.x, pCoords.y, pCoords.z, true, true, false)
    if not WaitEntityExists(hoseObj, 5000, 10) then
        lobby.hoseCreating = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Mangueira', 'Falha ao criar a mangueira. Tente novamente.', 'error')
        return
    end
    lobby.hoseCreating = nil

    -- O lobby pode ter sido encerrado durante a espera
    if PolarixLobbies[jobId] ~= lobby then
        DeleteEntity(hoseObj)
        return
    end

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
    if not EnterLoadingStage(lobby) then return end

    if lobby.cargoType ~= 'liquid' then return end
    if not lobby.hoseProp or not DoesEntityExist(lobby.hoseProp) then return end
    if not lobby.trailer or not DoesEntityExist(lobby.trailer) then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
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
    if lobby.cargoType ~= 'liquid' or lobby.stage ~= 'STATUS_LOADING' then return end
    -- Só existe vazamento se havia mangueira em uso (evita multa/spam sem mangueira)
    if not lobby.hoseProp then return end

    if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
        DeleteEntity(lobby.hoseProp)
    end
    lobby.hoseProp = nil
    lobby.hoseConnected = false

    local penalty = (Config.CargoTypes and Config.CargoTypes.liquid and Config.CargoTypes.liquid.leakPenalty) or 1500
    Framework.RemoveMoney(Player, 'bank', penalty, 'trucker-hose-leak')

    TriggerClientEvent('aurp_trucker:client:playLeakPtfx', src, jobId, penalty)
end)

-- 5. Desconectar Mangueira e Finalizar Carregamento Líquido
RegisterNetEvent('aurp_trucker:server:disconnectHose', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    -- Máquina de estados: só finaliza o carregamento líquido com mangueira conectada
    if lobby.cargoType ~= 'liquid' or lobby.stage ~= 'STATUS_LOADING' or not lobby.hoseConnected then return end
    if not lobby.trailer or not DoesEntityExist(lobby.trailer) then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
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
    if not lobby or lobby.src ~= src then
        PolarixReject('strappingCompleted', jobId, lobby, 'lobby inexistente ou de outro jogador')
        return
    end

    -- Máquina de estados: cintas só após todos os paletes (dry) ou, nos demais tipos de carga
    -- carregados sem paletes (ADR/cegonha), durante o carregamento
    if lobby.cargoType == 'dry' then
        if lobby.stage ~= 'STEP_STRAPPING' or (lobby.loadedCount or 0) < (lobby.requiredCount or 1) then
            PolarixReject('strappingCompleted', jobId, lobby, 'dry exige STEP_STRAPPING com todos os paletes contados pelo servidor')
            return
        end
    elseif lobby.cargoType == 'liquid' or lobby.cargoType == 'heavy' then
        PolarixReject('strappingCompleted', jobId, lobby, lobby.cargoType .. ' usa evento próprio')
        return -- têm eventos próprios (disconnectHose / heavyContainerLoaded)
    elseif not EnterLoadingStage(lobby) then
        PolarixReject('strappingCompleted', jobId, lobby, 'estágio não permite cintas')
        return
    end

    -- Proximidade da carreta
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not lobby.trailer or not DoesEntityExist(lobby.trailer) then
        PolarixReject('strappingCompleted', jobId, lobby, 'ped ou carreta inexistente no servidor')
        return
    end
    local strapDist = #(GetEntityCoords(ped) - GetEntityCoords(lobby.trailer))
    if strapDist > 60.0 then
        PolarixReject('strappingCompleted', jobId, lobby, ('jogador a %.1fm da carreta (máx 60)'):format(strapDist))
        return
    end

    -- Prevenção de Deadlock: assegura contagem e transição de estado garantida
    lobby.loadedCount = math.max(lobby.loadedCount or 0, lobby.requiredCount or 1)
    lobby.stage = 'STATUS_IN_TRANSIT'
    lobby.startedTransitAt = os.time()

    -- OneSync Anti-Rubberbanding: Descongela todas as entidades de carga no servidor para que o OneSync acompanhe o reboque
    if lobby.pallets then
        for _, pObj in ipairs(lobby.pallets) do
            if DoesEntityExist(pObj) then
                FreezeEntityPosition(pObj, false)
            end
        end
    end
    if lobby.forklift and DoesEntityExist(lobby.forklift) then
        if lobby.withForklift == false then
            DeleteEntity(lobby.forklift)
            lobby.forklift = nil
            if Config.Debug then print(("[AUST_Trucker] Empilhadeira de pátio removida para o frete sem embarque %s."):format(tostring(jobId))) end
        else
            FreezeEntityPosition(lobby.forklift, false)
        end
    end

    if Config.Debug then
        print(("[AUST_Trucker] Frete %s pronto para trânsito (Player %s). Destino: %s"):format(
            tostring(jobId), tostring(src), tostring(lobby.deliveryCoords)
        ))
    end

    TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
end)

-- ETAPA: Notificação de Palete Perdido durante a Viagem (Corda Rompida)
RegisterNetEvent('aurp_trucker:server:palletLost', function(jobId, palletNetId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.stage ~= 'STATUS_IN_TRANSIT' then return end

    if (lobby.lostPallets or 0) >= (lobby.requiredCount or 0) then return end
    lobby.lostPallets = (lobby.lostPallets or 0) + 1
    if Config.Debug then
        print(("[AUST_Trucker] Palete perdido em rota para o frete %s (Player: %s)! Total de perdas: %d"):format(
            tostring(jobId), tostring(src), lobby.lostPallets
        ))
    end
end)

-- ETAPA: Notificação de Contêiner Carregado via Reach Stacker (Carga Pesada)
RegisterNetEvent('aurp_trucker:server:heavyContainerLoaded', function(jobId, slotIdx, containerNetId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.cargoType ~= 'heavy' then return end
    if not EnterLoadingStage(lobby) then return end
    local hPed = GetPlayerPed(src)
    if not hPed or hPed == 0 or not lobby.trailer or not DoesEntityExist(lobby.trailer) then return end
    if #(GetEntityCoords(hPed) - GetEntityCoords(lobby.trailer)) > 60.0 then return end

    lobby.loadedCount = (lobby.loadedCount or 0) + 1
    local reqCount = lobby.requiredCount or 1

    if containerNetId and lobby.trailer and DoesEntityExist(lobby.trailer) then
        lobby.loadedContainerNetIds = lobby.loadedContainerNetIds or {}
        table.insert(lobby.loadedContainerNetIds, containerNetId)
        Entity(lobby.trailer).state:set('loadedContainers', lobby.loadedContainerNetIds, true)
    end

    if lobby.loadedCount >= reqCount then
        lobby.stage = 'STATUS_IN_TRANSIT'
        lobby.startedTransitAt = os.time()
        TriggerClientEvent('aurp_trucker:client:polarixReadyForTransit', src, lobby.deliveryCoords)
    else
        TriggerClientEvent('aurp_trucker:client:heavyContainerNextRequired', src, lobby.loadedCount, reqCount)
    end
end)

-- ETAPA: Contenção de Emergência de Vazamento ADR
RegisterNetEvent('aurp_trucker:server:adrLeakContained', function(jobId, newIntegrity)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    if lobby.cargoType ~= 'adr' then return end

    -- Valor vem do client: valida tipo/faixa e só permite diminuir a integridade
    local reported = tonumber(newIntegrity)
    if not reported or reported ~= reported or reported == math.huge or reported == -math.huge then return end
    reported = math.max(0, math.min(100, reported))
    lobby.cargoIntegrity = math.min(lobby.cargoIntegrity or 100, reported)
    if Config.Debug then
        print(("[AUST_Trucker] Jogador %s conteve vazamento ADR. Integridade salva em %d%%"):format(tostring(src), lobby.cargoIntegrity))
    end
end)


-- ETAPA 5: Entrega Final, Pagamentos QBOX e Persistência oxmysql
RegisterNetEvent('aurp_trucker:server:completePolarixDelivery', function(jobId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.citizenId ~= citizenId then
        PolarixReject('completePolarixDelivery', jobId, lobby, 'lobby inexistente ou de outro jogador')
        return
    end
    if lobby.stage ~= 'STATUS_IN_TRANSIT' then
        PolarixReject('completePolarixDelivery', jobId, lobby, 'só conclui em STATUS_IN_TRANSIT (cintas/carga não confirmadas pelo servidor?)')
        return
    end

    -- BLINDAGEM 1: Validação autoritativa de distância até o destino
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pedCoords = GetEntityCoords(ped)
    local dest = lobby.deliveryCoords
    if not dest then
        PolarixReject('completePolarixDelivery', jobId, lobby, 'lobby sem deliveryCoords')
        return
    end
    local destVec = vector3(dest.x, dest.y, dest.z)
    local dist = #(pedCoords - destVec)
    if dist > 35.0 then
        if Config.Debug then print(("[AUST_Trucker] ALERTA SEGURANÇA: Player %s tentou concluir entrega fora do raio (%.1fm de distância)!"):format(tostring(src), dist)) end
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
            if Config.Debug then print(("[AUST_Trucker] ALERTA SEGURANÇA: Player %s concluiu trajeto em tempo impossível (%ds)!"):format(tostring(src), elapsed)) end
            TriggerClientEvent('aurp_trucker:notify', src, 'Segurança', 'Tempo de rota inconsistente!', 'error')
            return
        end
    end

    -- CLAIM ATÔMICO: marca o lobby como "em conclusão" de forma síncrona, ANTES de qualquer await
    -- (RemoveJobKeys/MySQL cedem a thread). Chamadas concorrentes caem no check de stage acima.
    lobby.stage = 'STATUS_COMPLETING'

    -- Sincronia viva de Economia & XP com o painel administrativo antes de liquidar o pagamento
    local eco = (AdminService and AdminService.Economy) or {}
    local kmPay = eco.base_payment_per_km or eco.km_multiplier
    local kmXP = eco.base_xp_per_km or eco.xp_multiplier
    local dist = lobby.distance or 3.5

    local basePayment = lobby.payment or 5000
    local baseXP = lobby.xp or 200

    -- Se a rota tiver cadastro no painel admin, atualiza com os valores estritos salvos no painel
    if lobby.routeId and AdminService and AdminService.CustomRoutes and AdminService.CustomRoutes[lobby.routeId] then
        local rData = AdminService.CustomRoutes[lobby.routeId]
        if rData.base_payment and rData.base_payment > 0 then basePayment = rData.base_payment end
        if rData.base_xp and rData.base_xp > 0 then baseXP = rData.base_xp end
    elseif kmPay and kmPay > 0 then
        -- Se não tem rota fixa gravada, recalcula usando os multiplicadores vivos da aba Economia
        local calcPayment = math.floor(dist * kmPay * 100 + (eco.base_salary or 1200))
        if calcPayment > 0 then basePayment = calcPayment end
        if kmXP and kmXP > 0 then
            local calcXP = math.floor(dist * kmXP * 15 + 150)
            if calcXP > 0 then baseXP = calcXP end
        end
    end

    -- Bônus configurados na aba Economia (ADR, Carga Pesada, etc.)
    if lobby.cargoType == 'adr' and (eco.adr_bonus_pct or eco.adr_multiplier) then
        local adrMult = eco.adr_multiplier or (1 + ((eco.adr_bonus_pct or 35.0) / 100))
        basePayment = math.floor(basePayment * adrMult)
    end

    local totalReq = lobby.requiredCount or 4
    local lostCount = lobby.lostPallets or 0
    local deliveredCount = math.max(0, totalReq - lostCount)
    local ratio = (lobby.cargoType == 'dry' and totalReq > 0) and math.max(0.2, deliveredCount / totalReq) or 1.0
    if lobby.cargoType == 'adr' then
        ratio = math.max(0.2, (lobby.cargoIntegrity or 100) / 100)
    end

    local payment = math.floor(basePayment * ratio)
    local xp = math.floor(baseXP * ratio)

    -- Taxa de descarregamento na doca por ausência de empilhadeira própria
    local unloadingFee = 0
    if lobby.cargoType == 'dry' and lobby.withForklift == false then
        local feePercent = (Config.Polarix and Config.Polarix.CargoCapacity and Config.Polarix.CargoCapacity.UnloadingFeePercent) or 15
        unloadingFee = math.floor(payment * (feePercent / 100))
        payment = math.max(100, payment - unloadingFee)
        if Config.Debug then
            print(("[AUST_Trucker] Taxa de descarregamento de %d%% (-$%d) aplicada ao frete sem empilhadeira do jogador %s."):format(
                feePercent, unloadingFee, tostring(src)
            ))
        end
    end

    -- Remoção autoritativa de chaves secundárias (empilhadeira, reach stacker, carros cegonha)
    if lobby.forkliftPlate or lobby.handlerPlate or lobby.carrierCars then
        RemoveJobKeys(src, {
            forkliftPlate = lobby.forkliftPlate,
            forklift = lobby.forklift,
            handlerPlate = lobby.handlerPlate,
            handler = lobby.handler,
            carrierCars = lobby.carrierCars
        })
    end

    if lobby.isOwned then
        -- =======================================================================
        -- FLUXO 1: CAMINHÃO PRÓPRIO (OWNED TRUCK)
        -- Pagamento e XP imediatos. Jogador liberado do frete no ato da entrega.
        -- =======================================================================
        if not Framework.AddMoney(Player, 'bank', payment, 'polarix-trucker-job') then
            -- Pagamento falhou: devolve o lobby ao estado de trânsito para nova tentativa
            if PolarixLobbies[jobId] == lobby then lobby.stage = 'STATUS_IN_TRANSIT' end
            TriggerClientEvent('aurp_trucker:notify', src, 'Pagamento', 'Não foi possível creditar o pagamento. Tente novamente.', 'error')
            return
        end

        local dist = lobby.distance or 3.5

        -- Persistência oficial na tabela de progressão do sistema (trucker_player_progression)
        pcall(DB_AddPlayerStats, citizenId, payment, dist)
        if ProgressionService and ProgressionService.AddDirectXP then
            pcall(ProgressionService.AddDirectXP, src, citizenId, xp)
        else
            pcall(DB_AddXP, citizenId, xp)
        end

        -- Atualização autoritativa da tabela 0r_trucker e aust_trucker_stats para retrocompatibilidade
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

        pcall(DB_UpdateAustTruckerStats, citizenId, xp, 1)

        -- Deleta apenas a carreta da carga e adereços da entrega, preservando o caminhão do jogador
        if lobby.trailer and DoesEntityExist(lobby.trailer) then
            DeleteEntity(lobby.trailer)
        end
        if lobby.container and DoesEntityExist(lobby.container) then
            DeleteEntity(lobby.container)
        end
        if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
            DeleteEntity(lobby.hoseProp)
        end
        if lobby.pallets then
            for _, p in ipairs(lobby.pallets) do
                if p and DoesEntityExist(p) then DeleteEntity(p) end
            end
        end
        if lobby.carrierCars then
            for _, c in ipairs(lobby.carrierCars) do
                if c and DoesEntityExist(c) then DeleteEntity(c) end
            end
        end

        PolarixLobbies[jobId] = nil
        PlayerPolarixLobbies[citizenId] = nil

        if lobby.truck and DoesEntityExist(lobby.truck) then
            Entity(lobby.truck).state:set('activeJobData', nil, true)
        end
        if _G.Player and _G.Player(src) then
            _G.Player(src).state:set('activeJobId', nil, true)
        end

        TriggerClientEvent('aust_trucker:client:ClearObjective', src)
        TriggerClientEvent('aurp_trucker:client:polarixJobFinished', src, {
            isQuickJob = false,
            payment = payment,
            unloadingFee = unloadingFee,
            xp = xp,
            lostPallets = lostCount,
            deliveredPallets = deliveredCount,
            distance = dist
        })
    else
        -- =======================================================================
        -- FLUXO 2: TRABALHO RÁPIDO / VEÍCULO DA EMPRESA (QUICK JOB)
        -- Pagamento fica retido. Deleta carreta/carga e exige devolução à base de origem.
        -- =======================================================================
        lobby.stage = 'STATUS_RETURNING_TO_BASE'
        lobby.retainedPayment = payment
        lobby.retainedXP = xp
        lobby.unloadingFee = unloadingFee
        lobby.lostPallets = lostCount
        lobby.deliveredPallets = deliveredCount

        -- Deleta apenas a carreta e carga entregue no destino
        if lobby.trailer and DoesEntityExist(lobby.trailer) then
            DeleteEntity(lobby.trailer)
            lobby.trailer = nil
        end
        if lobby.container and DoesEntityExist(lobby.container) then
            DeleteEntity(lobby.container)
            lobby.container = nil
        end
        if lobby.hoseProp and DoesEntityExist(lobby.hoseProp) then
            DeleteEntity(lobby.hoseProp)
            lobby.hoseProp = nil
        end
        if lobby.pallets then
            for _, p in ipairs(lobby.pallets) do
                if p and DoesEntityExist(p) then DeleteEntity(p) end
            end
            lobby.pallets = {}
        end
        if lobby.carrierCars then
            for _, c in ipairs(lobby.carrierCars) do
                if c and DoesEntityExist(c) then DeleteEntity(c) end
            end
            lobby.carrierCars = {}
        end

        local returnCoords = (Config.Polarix and Config.Polarix.Warehouse and Config.Polarix.Warehouse.TruckSpawnCoords)
            or vector4(1245.79, -3155.76, 4.6, 90.0)

        TriggerClientEvent('aurp_trucker:client:polarixCargoDeliveredReturnRequired', src, {
            jobId = jobId,
            returnCoords = returnCoords,
            retainedPayment = payment,
            retainedXP = xp
        })
    end
end)

-- Devolução e Vistoria de Danos do Caminhão da Empresa (Trabalho Rápido)
RegisterNetEvent('aurp_trucker:server:returnQuickJobTruck', function(jobId, inspection)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.citizenId ~= citizenId then return end
    if lobby.stage ~= 'STATUS_RETURNING_TO_BASE' then return end

    -- Validação de proximidade da base de retorno
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local returnCoords = (Config.Polarix and Config.Polarix.Warehouse and Config.Polarix.Warehouse.TruckSpawnCoords)
        or vector4(1245.79, -3155.76, 4.6, 90.0)
    local distBase = #(pCoords - vector3(returnCoords.x, returnCoords.y, returnCoords.z))

    if distBase > 45.0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Distância', 'Você precisa estar no pátio da empresa para devolver o caminhão!', 'error')
        return
    end

    -- CLAIM ATÔMICO antes de qualquer await: impede pagamento duplicado por chamadas concorrentes
    lobby.stage = 'STATUS_RETURN_COMPLETING'

    local payment = lobby.retainedPayment or 0
    local xp = lobby.retainedXP or 0
    local repairCost = 0

    -- Vistoria Autoritativa de Avarias
    if inspection and type(inspection) == 'table' then
        local engineHealth = tonumber(inspection.engineHealth) or 1000.0
        local bodyHealth = tonumber(inspection.bodyHealth) or 1000.0
        local burstTires = tonumber(inspection.burstTires) or 0
        -- Valores vêm do client: rejeita NaN/inf e limita (burstTires negativo geraria dinheiro)
        if burstTires ~= burstTires or burstTires == math.huge or burstTires == -math.huge then burstTires = 0 end
        burstTires = math.floor(math.max(0, math.min(10, burstTires)))
        if engineHealth ~= engineHealth then engineHealth = 1000.0 end
        if bodyHealth ~= bodyHealth then bodyHealth = 1000.0 end

        -- Cálculo do custo de conserto baseado no desgaste real
        local engineDamage = math.max(0.0, 1000.0 - engineHealth)
        local bodyDamage = math.max(0.0, 1000.0 - bodyHealth)

        local engineCost = math.floor(engineDamage * 1.5)      -- até ~$1500 se motor destruído
        local bodyCost = math.floor(bodyDamage * 1.0)          -- até ~$1000 se lataria destruída
        local tireCost = burstTires * 150                      -- $150 por pneu estourado

        repairCost = math.max(0, engineCost + bodyCost + tireCost)
        -- Desconto limitado a no máximo 65% do pagamento retido para evitar saldo negativo
        repairCost = math.min(repairCost, math.floor(payment * 0.65))
    end

    local finalPayment = math.max(100, payment - repairCost)

    if not Framework.AddMoney(Player, 'bank', finalPayment, 'polarix-quickjob-returned') then
        if PolarixLobbies[jobId] == lobby then lobby.stage = 'STATUS_RETURNING_TO_BASE' end
        TriggerClientEvent('aurp_trucker:notify', src, 'Pagamento', 'Não foi possível creditar o pagamento. Tente novamente.', 'error')
        return
    end

    local dist = lobby.distance or 3.5

    -- Persistência oficial na tabela de progressão do sistema (trucker_player_progression)
    pcall(DB_AddPlayerStats, citizenId, finalPayment, dist)
    if ProgressionService and ProgressionService.AddDirectXP then
        pcall(ProgressionService.AddDirectXP, src, citizenId, xp)
    else
        pcall(DB_AddXP, citizenId, xp)
    end

    -- Remoção de chaves do caminhão da empresa
    RemoveJobKeys(src, lobby)

    -- Atualização de estatísticas 0r_trucker e aust_trucker_stats para retrocompatibilidade
    pcall(function()
        MySQL.query.await([[
            INSERT INTO 0r_trucker (citizenid, level, xp, total_deliveries, total_earned)
            VALUES (?, 1, ?, 1, ?)
            ON DUPLICATE KEY UPDATE
                xp = xp + VALUES(xp),
                total_deliveries = total_deliveries + 1,
                total_earned = total_earned + VALUES(total_earned),
                level = FLOOR(1 + (xp / 1000))
        ]], { citizenId, xp, finalPayment })
    end)

    pcall(DB_UpdateAustTruckerStats, citizenId, xp, 1)

    -- Limpeza definitiva das entidades restantes (caminhão da firma)
    CleanupLobbyEntities(lobby)

    if lobby.truck and DoesEntityExist(lobby.truck) then
        Entity(lobby.truck).state:set('activeJobData', nil, true)
    end
    if _G.Player and _G.Player(src) then
        _G.Player(src).state:set('activeJobId', nil, true)
    end

    PolarixLobbies[jobId] = nil
    PlayerPolarixLobbies[citizenId] = nil

    TriggerClientEvent('aust_trucker:client:ClearObjective', src)
    TriggerClientEvent('aurp_trucker:client:polarixJobFinished', src, {
        isQuickJob = true,
        payment = finalPayment,
        originalPayment = payment,
        repairCost = repairCost,
        unloadingFee = lobby.unloadingFee or 0,
        xp = xp,
        lostPallets = lobby.lostPallets or 0,
        deliveredPallets = lobby.deliveredPallets or 0,
        distance = dist
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
    if lobby.stage == 'STATUS_COMPLETING' or lobby.stage == 'STATUS_RETURN_COMPLETING' then return end
    lobby.stage = 'STATUS_CANCELLED'

    RemoveJobKeys(src, lobby)
    CleanupLobbyEntities(lobby)

    if lobby.truck and DoesEntityExist(lobby.truck) then
        Entity(lobby.truck).state:set('activeJobData', nil, true)
    end
    if _G.Player and _G.Player(src) then
        _G.Player(src).state:set('activeJobId', nil, true)
    end

    PolarixLobbies[jobId] = nil
    PlayerPolarixLobbies[citizenId] = nil

    TriggerClientEvent('aust_trucker:client:ClearObjective', src)
    TriggerClientEvent('aurp_trucker:notify', src, 'Entrega Cancelada', (type(reason) == 'string' and reason:sub(1, 120)) or 'O contrato foi cancelado.', 'warning')
end)

-- Reposição de Emergência / Fallback
RegisterNetEvent('aurp_trucker:server:emergencyRespawnEquipment', function(jobId)
    local src = source
    local lobby = PolarixLobbies[jobId]
    if not lobby or lobby.src ~= src then return end
    -- Só faz sentido em carga seca durante o pátio; rate limit de 10s por lobby
    if lobby.cargoType ~= 'dry' or (lobby.stage ~= 'STATUS_LOADING' and lobby.stage ~= 'STEP_GET_TRUCK' and lobby.stage ~= 'STEP_STRAPPING') then return end
    local nowMs = GetGameTimer()
    if lobby.lastRespawnAt and (nowMs - lobby.lastRespawnAt) < 10000 then return end
    lobby.lastRespawnAt = nowMs

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


