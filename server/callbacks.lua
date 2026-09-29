-- aurp_trucker — server/callbacks.lua
-- lib.callback.register (substitui QBCore.Functions.CreateCallback)

local function BuildDefaultContracts()
    local lc_contracts = {}
    local availableLoads = (Config.LC_Jobs and Config.LC_Jobs.available_loads) or {}
    local rentalTrucks = { "hauler", "phantom", "packer", "blacktop", "brickades" }
    for i, load in ipairs(availableLoads) do
        local truckModel = rentalTrucks[((i - 1) % #rentalTrucks) + 1]
        local def = load.def or {0,0,0,0}
        local baseDist = 0.8 + ((i * 1.37) % 9.2)
        local rewardRate = 1200 + ((def[3] or 0) * 450) + ((def[2] or 0) * 350) + ((def[1] or 0) > 0 and 600 or 0)
        local reward = math.floor(baseDist * rewardRate + 950)

        table.insert(lc_contracts, {
            contract_id   = i,
            contract_name = load.name,
            contract_type = (i % 2 == 0) and 1 or 0,
            distance      = tonumber(string.format("%.2f", baseDist)),
            reward        = reward,
            truck         = truckModel,
            trailer       = load.trailer,
            cargo_type    = def[1] or 0,
            fragile       = def[2] or 0,
            valuable      = def[3] or 0,
            fast          = (i % 3 == 0) and 1 or 0,
            illegal       = def[4] or 0,
            progress      = nil,
        })
    end
    return lc_contracts
end

local function BuildFallbackLcDados(citizenId, playerMoney)
    return {
        config = {
            locale = Config.locale or Config.lang or 'br',
            format = Config.format or { lang = 'br', currency = 'USD', location = 'pt-BR' },
            dealership = Config.LC_Dealership or {},
            repair_price = Config.LC_RepairPrice or { engine = 100, transmission = 100, wheels = 100, body = 100, fuel = 10 },
            required_xp_to_levelup = Config.LC_RequiredXP or { 100, 250, 450, 700, 1000, 1500, 2200, 3000, 4000, 5200 },
            max_loan_per_level = { 50000, 100000, 200000, 400000 },
            loans = Config.LC_Loans or { plans = {}, payment_interval_hours = 24 },
            cooldown = 2,
            party = { price_to_create = 500, max_members = 4, price_per_member = 100 },
            disable_loans = false,
            disable_drivers = false,
            max_emprestimo = 400000,
            player_level = 0,
        },
        trucker_available_contracts = BuildDefaultContracts(),
        trucker_users = {
            user_id = citizenId or 'default',
            money = playerMoney or 0,
            total_earned = 0,
            finished_deliveries = 0,
            exp = 0,
            traveled_distance = 0.0,
            skill_points = 0,
            product_type = 0,
            distance = 0,
            valuable = 0,
            fragile = 0,
            fast = 0,
            illegal = 0,
            dark_theme = 1,
        },
        trucker_trucks = {},
        trucker_drivers = {},
        trucker_loans = {},
        trucker_party_members = {},
        trucker_party = nil,
        top_truckers = {},
        available_money = playerMoney or 0,
    }
end

-- Dados iniciais para abrir a NUI
-- PERF: queries independentes lançadas em paralelo via Citizen.CreateThread (barrier pattern)
-- Reduz latência de abertura da NUI de ~15 queries sequenciais para 2 fases paralelas
function BuildInitialDataForPlayer(source, citizenId)
    local Player = source and Framework.GetPlayer(source)
    if not citizenId and Player then
        citizenId = Framework.GetCitizenId(Player)
    end
    if not citizenId then
        return {
            lc_dados = BuildFallbackLcDados(nil, 0),
            jobs = {},
            recruitingCompanies = {}
        }
    end

    local ok, result = pcall(function()
        local _r       = {}   -- resultados acumulados
        local _pending = 0    -- contador de threads ativas

        -- Helper: lança query numa thread separada, guarda resultado em _r[key]
        local function spawn(key, fn)
            _pending = _pending + 1
            Citizen.CreateThread(function()
                local s, v = pcall(fn)
                _r[key]  = s and v or nil
                _pending = _pending - 1
            end)
        end

        -- ── FASE 1: queries de jogador (sem dependência de empresa) ──────────��───
        spawn('stats', function()
            local s = DB_GetPlayerStats(citizenId)
            if not s then pcall(DB_UpsertPlayerStats, citizenId); s = DB_GetPlayerStats(citizenId) end
            if s then
                s.name = Framework.GetCharName(Player)
                s.money = Framework.GetMoney(Player, 'bank') or Framework.GetMoney(Player, 'cash') or 0
            end
            return s
        end)
        spawn('personalLoan',   function() return DB_GetActiveLoan(citizenId) end)
        spawn('skills',         function() return ProgressionService and ProgressionService.GetSkills(citizenId) or {} end)
        spawn('adrCerts',       function() return AdrService and AdrService.GetAll(citizenId) or {} end)
        spawn('recruiting',     function() return CompanyService.GetRecruiting() end)
        spawn('jobs',           function() return JobService and JobService.GetAvailable(citizenId) or {} end)
        spawn('activeJob',      function() return JobService and JobService.GetActiveByPlayer(citizenId) or nil end)
        spawn('activeContract', function() return ContractService and ContractService.GetActive(citizenId) or nil end)

        -- Empresa lookup (sequencial — company.id é pré-requisito das queries abaixo)
        local company = CompanyService.GetByMember(citizenId)

        -- ── FASE 2: queries dependentes da empresa ─��─────────────────────────────
        if company then
            spawn('member',      function() return DB_GetMember(citizenId) end)
            spawn('perks',       function() return CompanyService.GetPerks(company.id) end)
            spawn('companyLoan', function() return DB_GetActiveCompanyLoan(company.id) end)
            spawn('owned',       function()
                return IndustryOwnershipService and IndustryOwnershipService.GetCompanyOwned(company.id) or nil
            end)
            spawn('npcDrivers', function()
                if not NpcDriverService then return nil end
                return {
                    drivers      = NpcDriverService.GetByCompany(company.id),
                    profiles     = NpcDriverService.GetAgencyProfiles(),
                    reputation   = (VP_Trucker.Companies[company.id] or {}).reputation or 100,
                    allowIllegal = ((VP_Trucker.Companies[company.id] or {}).allow_illegal_npc or 0) == 1,
                }
            end)
            spawn('clients', function()
                if ContractService and ContractService.GetClients then
                    local cOk, cResult = pcall(ContractService.GetClients, company.id, company.company_level or 1)
                    return cOk and cResult or {}
                end
                local list = {}
                for _, c in ipairs(Config.SecondaryIndustries or {}) do
                    local sType = c.type or 'mixed'
                    local sCfg  = (Config.ClientSectors or {})[sType] or { label = sType }
                    list[#list+1] = {
                        id = c.id, name = c.name,
                        sector = sType, sectorLabel = sCfg.label or sType,
                        trustLevel = 0, trustXP = 0, trustLabel = 'Novo',
                        bonusPercent = 0, totalDeliveries = 0, totalRevenue = 0,
                        streak = 0, locked = false, sectorReputation = 0, maxOptions = 1,
                    }
                end
                return list
            end)
            if company.company_type == 'repo' then
                spawn('repoOrders',      function() return DB_GetAvailableRepoOrders() end)
                spawn('activeRepoOrder', function() return DB_GetActiveRepoOrder(citizenId) end)
            end
        end

        -- ── BARRIER: aguardar todas as threads completarem com timeout de segurança ───
        local waitLimit = 500
        while _pending > 0 and waitLimit > 0 do
            Wait(0)
            waitLimit = waitLimit - 1
        end
        if _pending > 0 and Config.Debug then
            print(('[aurp_trucker] getInitialData barrier timeout com %d queries pendentes'):format(_pending))
        end

        -- Merge crude oil (externo, sem DB próprio)
        local jobs = _r.jobs or {}
        local okCrude, crudeOrders = pcall(function() return exports['AUST_oilfield']:GetPostedOrders() end)
        if okCrude and crudeOrders then
            for _, order in ipairs(crudeOrders) do
                jobs[#jobs+1] = {
                    id             = 'crude_' .. order.wellId,
                    originName     = 'Poço de Petróleo #' .. order.wellId,
                    destName       = 'Refinaria Sandy Shores',
                    cargoItem      = 'crude_oil_barrel',
                    trailerModel   = 'tanker',
                    basePayment    = order.pricePerBarrel * order.barrels,
                    distance       = 0.0,
                    cargoQty       = order.barrels,
                    expiresAt      = nil,
                    adrRequired    = 'flammable_liquid',
                    adrLocked      = not AdrService.HasCert(citizenId, 'flammable_liquid'),
                    pricePerBarrel = order.pricePerBarrel,
                    wellCoords     = { x = order.coords.x, y = order.coords.y, z = order.coords.z },
                    isCrudeOrder   = true,
                }
            end
        end

        -- Montar companyPayload com dados já disponíveis em _r
        local companyPayload = nil
        if company then
            local levels = Config.CompanyLevels
            local lvl    = company.company_level or 1
            local perks  = _r.perks or {}
            companyPayload = {
                id              = company.id,
                owner_citizenid = company.owner_citizenid,
                name            = company.name,
                balance         = company.balance,
                is_recruiting   = company.is_recruiting,
                company_type    = company.company_type,
                company_level   = lvl,
                company_xp      = company.company_xp or 0,
                xp_next         = (lvl < #levels) and levels[lvl + 1].xpRequired or 0,
                xp_level_start  = levels[lvl].xpRequired,
                perks           = { vehicles = perks.vehicles, members = perks.members, bonus = perks.bonus },
                role            = _r.member and _r.member.role or 'driver',
            }
        end

        -- Party payload (usa memória, sem queries)
        local partyPayload = nil
        local myPartyId = VP_Trucker.PlayerParties[citizenId]
        if myPartyId then
            local party = VP_Trucker.Parties[myPartyId]
            if party then
                local membersPayload = {}
                for cid, info in pairs(party.members) do
                    table.insert(membersPayload, {
                        citizenid = cid,
                        name      = info.src and GetCharName(info.src) or cid,
                        isLeader  = (cid == party.leader),
                        online    = info.src ~= nil,
                    })
                end
                local convoyActive = false
                for _, convoy in pairs(VP_Trucker.Convoys) do
                    if convoy.partyId == myPartyId then convoyActive = true; break end
                end
                partyPayload = {
                    partyId      = myPartyId,
                    isLeader     = (party.leader == citizenId),
                    members      = membersPayload,
                    convoyActive = convoyActive,
                    maxSize      = party.maxSize,
                }
            end
        end

        -- Montar contratos LC idênticos à referência (Quick Jobs)
        local lc_contracts = {}
        local availableLoads = (Config.LC_Jobs and Config.LC_Jobs.available_loads) or {}
        local rentalTrucks = { "hauler", "phantom", "packer", "blacktop", "brickades" }
        local stats = _r.stats or {}
        local skills = _r.skills or {}
        local playerMoney = (Player and (Framework.GetMoney(Player, 'bank') or Framework.GetMoney(Player, 'cash'))) or 0
        local playerXP = tonumber(stats and stats.xp) or 0
        local calculatedLevel = (ProgressionService and ProgressionService.CalcLevel and ProgressionService.CalcLevel(playerXP)) or 0
        local storedLevel = tonumber(stats and stats.level) or 0

        -- Auto-heal / Sincronização retroativa de nível e skill points
        if calculatedLevel > storedLevel then
            local missingPoints = calculatedLevel - storedLevel
            local newRank = math.min(6, math.ceil(calculatedLevel / 5))
            DB_SetLevelData(citizenId, calculatedLevel, newRank, missingPoints)
            if stats then
                stats.level = calculatedLevel
                stats.rank = newRank
                stats.skill_points = (tonumber(stats.skill_points) or 0) + missingPoints
            end
        end

        local playerLevel = (stats and tonumber(stats.level)) or calculatedLevel
        local playerSkillPoints = (stats and tonumber(stats.skill_points)) or (ProgressionService and ProgressionService.GetSkillPoints and ProgressionService.GetSkillPoints(citizenId)) or 0

        for i, load in ipairs(availableLoads) do
            local truckModel = rentalTrucks[((i - 1) % #rentalTrucks) + 1]
            local def = load.def or {0,0,0,0}
            local adr = def[1] or 0
            local fragile = def[2] or 0
            local valuable = def[3] or 0
            local illegal = def[4] or 0
            local fast = (i % 3 == 0) and 1 or 0

            local baseDist = 0.8 + ((i * 1.37) % 9.2)
            local baseDistNum = tonumber(string.format("%.2f", baseDist))
            local rewardRate = 1200 + (valuable * 450) + (fragile * 350) + (adr > 0 and 600 or 0)
            local baseReward = math.floor(baseDist * rewardRate + 950)

            local contractData = {
                contract_id   = i,
                contract_name = load.name,
                contract_type = (i % 2 == 0) and 1 or 0, -- Alterna entre Quick Jobs (0) e Freight Jobs (1)
                distance      = baseDistNum,
                reward        = baseReward,
                truck         = truckModel,
                trailer       = load.trailer,
                cargo_type    = adr,
                fragile       = fragile,
                valuable      = valuable,
                fast          = fast,
                illegal       = illegal,
                progress      = nil,
            }

            -- Validação de Habilidades e Bloqueio de Contrato (Server-Side)
            local canAccept, lockType, lockReason = true, nil, nil
            if ProgressionService and ProgressionService.CanPlayerAcceptContract then
                canAccept, lockType, lockReason = ProgressionService.CanPlayerAcceptContract(citizenId, contractData)
            end
            contractData.locked = not canAccept
            contractData.lock_type = lockType
            contractData.lock_reason = lockReason

            -- Aplicação Dinâmica dos Bônus de Skills
            if ProgressionService and ProgressionService.CalculateContractBonuses then
                local bonuses = ProgressionService.CalculateContractBonuses(citizenId, contractData)
                contractData.reward = math.floor(baseReward * bonuses.moneyMultiplier)
                contractData.bonus_money_pct = bonuses.moneyBonusPct
                contractData.bonus_exp_pct = bonuses.expBonusPct
            end

            table.insert(lc_contracts, contractData)
        end

        local fleetTrucks = _r.fleetTrucks or (TruckFleetService and TruckFleetService.GetPlayerTrucks(citizenId)) or {}
        local hiredDrivers = _r.hiredDrivers or (NpcDriverService and NpcDriverService.GetHiredDrivers(citizenId)) or {}

        -- Motoristas da Agência de Recrutamento (user_id = nil para aparecer na aba Recruitment)
        local agencyCatalog = (NpcDriverService and NpcDriverService.GetAgencyCatalog()) or {}
        local combinedDrivers = {}
        for _, hd in ipairs(hiredDrivers) do
            table.insert(combinedDrivers, {
                driver_id    = hd.driver_id,
                user_id      = hd.user_id,
                name         = hd.name,
                img          = hd.img or 'img/avatar/avatar1.png',
                price        = hd.price or 1000,
                product_type = hd.product_type or 0,
                distance     = hd.distance or 0,
                valuable     = hd.valuable or 0,
                fragile      = hd.fragile or 0,
                fast         = hd.fast or 0,
            })
        end
        for i, cand in ipairs(agencyCatalog) do
            table.insert(combinedDrivers, {
                driver_id    = cand.driver_id or cand.id or i,
                user_id      = nil, -- user_id nil indica candidato disponível para contratação
                name         = cand.name,
                img          = cand.img or 'img/avatar/avatar1.png',
                price        = cand.price or 800,
                product_type = cand.product_type or 0,
                distance     = cand.distance or cand.distance_skill or 0,
                valuable     = cand.valuable or cand.valuable_skill or 0,
                fragile      = cand.fragile or cand.fragile_skill or 0,
                fast         = cand.fast or cand.fast_skill or 0,
            })
        end

        -- Empréstimos Ativos do Jogador
        local activeLoansList = {}
        if _r.personalLoan then
            table.insert(activeLoansList, {
                id               = _r.personalLoan.id,
                loan             = _r.personalLoan.amount,
                day_cost         = _r.personalLoan.monthly_payment,
                remaining_amount = _r.personalLoan.remaining_balance,
                timer            = _r.personalLoan.next_payment_at or os.time(),
            })
        end

        -- Ranking dos Top Caminhoneiros
        local topTruckersList = {}
        local topOk, topRows = pcall(function()
            return MySQL.query.await([[
                SELECT p.citizenid, p.total_distance as traveled_distance, p.xp as exp
                FROM trucker_player_progression p
                ORDER BY p.xp DESC
                LIMIT 10
            ]])
        end)
        if topOk and type(topRows) == 'table' then
            for _, row in ipairs(topRows) do
                table.insert(topTruckersList, {
                    name = 'Motorista #' .. string.sub(tostring(row.citizenid), 1, 5),
                    firstname = '',
                    traveled_distance = tonumber(row.traveled_distance) or 0,
                    exp = tonumber(row.exp) or 0
                })
            end
        end

        -- Sincronização de Party / Grupo
        local partyObj = nil
        local partyMembersList = {}
        if partyPayload then
            partyObj = {
                name          = partyPayload.name or ('Grupo #' .. partyPayload.partyId),
                description   = partyPayload.description or 'Grupo de transporte cooperativo',
                owner         = partyPayload.isLeader and 1 or 0,
                user_id       = partyPayload.isLeader and citizenId or '',
                members       = partyPayload.maxSize or 4,
                members_count = #partyPayload.members,
            }
            for _, m in ipairs(partyPayload.members) do
                table.insert(partyMembersList, {
                    user_id = m.citizenid,
                    name    = m.name,
                    owner   = m.isLeader,
                })
            end
        end

        local activeLocale = Config.locale or Config.lang or 'br'
        local activeFormat = Config.format or { lang = activeLocale, currency = 'USD', location = 'pt-BR' }

        local lc_dados = {
            config = {
                locale = activeLocale,
                format = activeFormat,
                dealership = Config.LC_Dealership or {},
                repair_price = Config.LC_RepairPrice or { engine = 100, transmission = 100, wheels = 100, body = 100, fuel = 10 },
                required_xp_to_levelup = Config.LC_RequiredXP or { 100, 250, 450, 700, 1000, 1500, 2200, 3000, 4000, 5200 },
                max_loan_per_level = { 50000, 100000, 200000, 400000 },
                loans = Config.LC_Loans or {},
                cooldown = 2,
                party = { price_to_create = 500, max_members = 4, price_per_member = 100 },
                disable_loans = false,
                disable_drivers = false,
                max_emprestimo = 400000,
                player_level = playerLevel,
            },
            trucker_available_contracts = lc_contracts,
            trucker_users = {
                user_id = citizenId,
                money = playerMoney,
                total_earned = tonumber(stats.total_earnings) or 0,
                finished_deliveries = tonumber(stats.total_deliveries) or 0,
                exp = playerXP,
                traveled_distance = tonumber(stats.total_distance) or 0.0,
                skill_points = playerSkillPoints,
                product_type = skills.product_type or 0,
                distance = skills.distance or 0,
                valuable = skills.valuable or 0,
                fragile = skills.fragile or 0,
                fast = skills.fast or 0,
                illegal = skills.illegal or 0,
                dark_theme = 1,
            },
            trucker_trucks = fleetTrucks,
            trucker_drivers = combinedDrivers,
            trucker_loans = activeLoansList,
            trucker_party_members = partyMembersList,
            trucker_party = partyObj,
            top_truckers = topTruckersList,
            available_money = playerMoney,
        }

        return {
            lc_dados            = lc_dados,
            jobs                = jobs,
            company             = companyPayload,
            activeJob           = _r.activeJob,
            stats               = _r.stats,
            recruitingCompanies = _r.recruiting,
            skills              = _r.skills,
            personalLoan        = _r.personalLoan,
            companyLoan         = _r.companyLoan,
            repoOrders          = _r.repoOrders,
            activeRepoOrder     = _r.activeRepoOrder,
            ownedIndustries     = _r.owned,
            currentParty        = partyPayload,
            npcDrivers          = _r.npcDrivers,
            adrCerts            = _r.adrCerts,
            activeContract      = _r.activeContract,
            clients             = _r.clients or {},
            rentalTrucks        = Config.TruckRental and Config.TruckRental.trucks or {},
            activeRental        = TruckRentalService and TruckRentalService.GetRental(citizenId) or nil,
            playerName          = (Player and Framework.GetCharName and Framework.GetCharName(Player)) or (GetCharName and GetCharName(source)) or 'Motorista',
            playerMoney         = (Player and (Framework.GetMoney(Player, 'bank') or Framework.GetMoney(Player, 'cash'))) or 0,
            fleetTrucks         = fleetTrucks,
            dealershipCatalog   = TruckFleetService and TruckFleetService.GetCatalog() or {},
            loanPlans           = loanPlans,
            agencyDrivers       = NpcDriverService and NpcDriverService.GetAgencyCatalog() or {},
            hiredDrivers        = hiredDrivers,
            repairPrices        = Config.LC_RepairPrice or {},
        }
    end)

    if not ok then
        print('^1[AUST_trucker] getInitialData ERROR: ' .. tostring(result) .. '^7')
        local pMoney = 0
        if Player then
            pMoney = Framework.GetMoney(Player, 'bank') or Framework.GetMoney(Player, 'cash') or 0
        end
        return {
            lc_dados = BuildFallbackLcDados(citizenId, pMoney),
            jobs = {},
            recruitingCompanies = {}
        }
    end

    return result
end

-- Callback principal para o frontend da NUI
lib.callback.register('aurp_trucker:getInitialData', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then
        return {
            lc_dados = BuildFallbackLcDados(nil, 0),
            jobs = {},
            recruitingCompanies = {}
        }
    end
    local citizenId = Framework.GetCitizenId(Player)
    return BuildInitialDataForPlayer(source, citizenId)
end)

-- Abertura direta padrão truck_logistics:getData / getDataFor(src)
function getDataFor(src)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local data = BuildInitialDataForPlayer(src, citizenId)
    local activeLocale = Config.locale or Config.lang or 'br'
    local activeFormat = Config.format or { lang = activeLocale, currency = 'USD', location = 'pt-BR' }
    TriggerClientEvent('truck_logistics:open', src, data.lc_dados, { config = { locale = activeLocale, format = activeFormat } })
end
exports('getDataFor', getDataFor)

RegisterNetEvent('truck_logistics:getData', function()
    local src = source
    getDataFor(src)
end)

-- Membros da empresa — derivação server-side (não confia no companyId do cliente)
lib.callback.register('aurp_trucker:getCompanyMembers', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    if not company then return {} end
    return DB_GetMembers(company.id) or {}
end)

-- Veículos da empresa
lib.callback.register('aurp_trucker:getCompanyVehicles', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    if not company then return {} end
    return DB_GetVehicles(company.id) or {}
end)

lib.callback.register('aurp_trucker:retrieveVehicle', function(source, plate)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, error = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, error = 'Sem empresa' } end

    -- Verificar se o veículo pertence à empresa
    local vehicles = DB_GetVehicles(company.id) or {}
    local vehicle = nil
    for _, v in ipairs(vehicles) do
        if v.plate == plate then vehicle = v break end
    end

    if not vehicle then return { success = false, error = 'Veículo não encontrado' } end

    -- C-08: Troca atômica de status — previne race condition TOCTOU
    -- O UPDATE falha silenciosamente se outro coroutine já alterou o status
    local affected = MySQL.update.await(
        "UPDATE trucker_company_vehicles SET status = 'out' WHERE plate = ? AND company_id = ? AND status = 'stored'",
        { plate, company.id }
    )
    if not affected or affected == 0 then
        return { success = false, error = 'Veículo já está em uso' }
    end
    return { success = true, model = vehicle.model, plate = vehicle.plate }
end)

lib.callback.register('aurp_trucker:storeVehicle', function(source, plate)
    -- L-03/L-12: Padronizado para { success, error } — consistente com demais callbacks
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, error = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, error = 'Sem empresa' } end

    local vehicles = DB_GetVehicles(company.id) or {}
    for _, v in ipairs(vehicles) do
        if v.plate == plate then
            DB_SetVehicleStatus(plate, 'stored')
            return { success = true }
        end
    end
    return { success = false, error = 'Veículo não pertence à empresa' }
end)

lib.callback.register('aurp_trucker:negotiateContract', function(source, clientId, terms)
    if not clientId or not terms then return { success = false, error = 'Dados inválidos' } end
    local ok, result = ContractService.Negotiate(source, clientId, terms)
    if not ok then
        return { success = false, error = result or 'Erro ao negociar' }
    end
    return { success = true, contract = result }
end)

lib.callback.register('aurp_trucker:getClients', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company then return {} end
    return ContractService.GetClients(company.id, (VP_Trucker.Companies[company.id] or {}).company_level or 1)
end)

lib.callback.register('aurp_trucker:getPlayerStats', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return nil end
    local citizenId = Framework.GetCitizenId(Player)
    local stats = DB_GetPlayerStats(citizenId)
    if not stats then
        -- Auto-create progression record if missing
        pcall(DB_UpsertPlayerStats, citizenId)
        stats = DB_GetPlayerStats(citizenId)
    end
    return stats
end)

lib.callback.register('aurp_trucker:getPlayerSkills', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    return ProgressionService.GetSkills(Framework.GetCitizenId(Player))
end)

-- PERF: Cache de histórico por empresa — TTL 60s (evita N queries a cada abertura do painel)
local _historyCache      = {}
local _HISTORY_CACHE_TTL = 60000  -- ms

lib.callback.register('aurp_trucker:getCompanyHistory', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return nil end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company then return nil end

    -- Servir do cache se ainda válido
    local cached = _historyCache[company.id]
    if cached and (GetGameTimer() - cached.ts) < _HISTORY_CACHE_TTL then
        return cached.data
    end

    local companyData = VP_Trucker.Companies[company.id] or {}

    -- M1: Parallel barrier — mesmo padrão de getInitialData
    -- 5 queries independentes lançadas em threads simultâneas; barrier aguarda todas
    local _r       = {}
    local _pending = 0

    local function spawn(key, fn)
        _pending = _pending + 1
        Citizen.CreateThread(function()
            local ok, val = pcall(fn)
            _r[key]  = ok and val or nil
            _pending = _pending - 1
        end)
    end

    spawn('recentJobs', function()
        return MySQL.query.await(
            "SELECT cargo_item, base_payment, distance, completed_at FROM trucker_jobs WHERE company_id = ? AND status = 'completed' ORDER BY completed_at DESC LIMIT 20",
            { company.id }
        ) or {}
    end)

    spawn('contracts', function()
        return MySQL.query.await(
            "SELECT id, contract_type, total_payment, client_id, bonus_percent, completed_at FROM trucker_contracts WHERE company_id = ? AND status = 'completed' ORDER BY completed_at DESC LIMIT 10",
            { company.id }
        ) or {}
    end)

    spawn('members', function()
        return DB_GetMembers(company.id) or {}
    end)

    spawn('totals', function()
        return MySQL.single.await(
            "SELECT COUNT(*) as total_jobs, COALESCE(SUM(base_payment), 0) as total_revenue, COALESCE(SUM(distance), 0) as total_distance FROM trucker_jobs WHERE company_id = ? AND status = 'completed'",
            { company.id }
        ) or { total_jobs = 0, total_revenue = 0, total_distance = 0 }
    end)

    spawn('contractTotals', function()
        return MySQL.single.await(
            "SELECT COUNT(*) as total_contracts, COALESCE(SUM(total_payment), 0) as contract_revenue FROM trucker_contracts WHERE company_id = ? AND status = 'completed'",
            { company.id }
        ) or { total_contracts = 0, contract_revenue = 0 }
    end)

    spawn('relationships', function()
        if ContractService and ContractService.GetClients then
            return ContractService.GetClients(company.id, companyData.company_level or 1)
        end
        return {}
    end)

    -- Barrier: aguardar todas as threads (máx. 500 ticks = ~5s de segurança)
    local _timeout = 0
    while _pending > 0 and _timeout < 500 do
        Wait(0)
        _timeout = _timeout + 1
    end

    -- Enriquecer contratos com nome do cliente (pós-barrier, in-memory)
    local completedContracts = _r.contracts or {}
    for _, c in ipairs(completedContracts) do
        for _, ind in ipairs(Config.SecondaryIndustries) do
            if ind.id == c.client_id then c.clientName = ind.name; break end
        end
    end

    local totals         = _r.totals         or { total_jobs = 0, total_revenue = 0, total_distance = 0 }
    local contractTotals = _r.contractTotals  or { total_contracts = 0, contract_revenue = 0 }

    local result = {
        companyName        = company.name,
        companyLevel       = companyData.company_level or 1,
        companyXP          = companyData.company_xp or 0,
        balance            = company.balance or 0,
        memberCount        = #(_r.members or {}),
        totalJobs          = totals.total_jobs or 0,
        totalRevenue       = (totals.total_revenue or 0) + (contractTotals.contract_revenue or 0),
        totalDistance      = totals.total_distance or 0,
        totalContracts     = contractTotals.total_contracts or 0,
        recentJobs         = _r.recentJobs or {},
        completedContracts = completedContracts,
        topClients         = _r.relationships or {},
    }

    _historyCache[company.id] = { data = result, ts = GetGameTimer() }
    return result
end)

-- Retorna os últimos convoys completados pelo jogador (histórico pessoal)
lib.callback.register('aurp_trucker:getConvoyHistory', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local citizenId = Framework.GetCitizenId(Player)
    return DB_GetConvoyHistory(citizenId, 20)
end)

lib.callback.register('aurp_trucker:getIndustries', function(source)
    local industries = IndustryService.GetAll()
    -- Enriquecer com info de ownership
    for industryId, data in pairs(industries) do
        local owner = IndustryOwnershipService.GetOwner(industryId)
        data.ownedByCompanyId   = owner and owner.company_id   or nil
        data.ownedByCompanyName = nil
        if owner and owner.company_id and VP_Trucker.Companies[owner.company_id] then
            data.ownedByCompanyName = VP_Trucker.Companies[owner.company_id].name
        end
    end
    return industries
end)

lib.callback.register('aurp_trucker:getIndustryData', function(source, industryId)
    return IndustryService.Get(industryId)
end)

-- ============================================================
-- INDUSTRY OWNERSHIP
-- ============================================================

-- Retorna indústrias possuídas pela empresa do jogador
lib.callback.register('aurp_trucker:getIndustryOwnership', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    if not company then return {} end
    return IndustryOwnershipService.GetCompanyOwned(company.id)
end)

-- Compra uma indústria para a empresa do jogador
lib.callback.register('aurp_trucker:buyIndustry', function(source, industryId)
    if type(industryId) ~= 'string' or industryId == '' then
        return { success = false, reason = 'ID de indústria inválido' }
    end
    if not Config.Industries[industryId] then
        return { success = false, reason = 'Indústria não existe' }
    end
    return IndustryOwnershipService.Buy(source, industryId)
end)

-- Skills do jogador
lib.callback.register('aurp_trucker:getSkills', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    return ProgressionService.GetSkills(Framework.GetCitizenId(Player))
end)

-- Comprar nível de skill
lib.callback.register('aurp_trucker:purchaseSkill', function(source, data)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, error = 'Jogador não encontrado' } end
    local ok, err = ProgressionService.PurchaseSkill(source, Framework.GetCitizenId(Player), data.skillType)
    if ok then
        return { success = true }
    else
        return { success = false, error = err }
    end
end)

-- ============================================================
-- LOANS
-- ============================================================

lib.callback.register('aurp_trucker:getLoanData', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return nil end
    local citizenId = Framework.GetCitizenId(Player)
    local company   = CompanyService.GetByMember(citizenId)
    return {
        personalLoan = DB_GetActiveLoan(citizenId),
        companyLoan  = company and DB_GetActiveCompanyLoan(company.id) or nil,
    }
end)

lib.callback.register('aurp_trucker:payLoan', function(source, loanId, amount, isCompanyLoan)
    amount = math.floor(tonumber(amount) or 0)
    loanId = tonumber(loanId) or 0
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)

    if AntiCheatService and not AntiCheatService.RateLimit(citizenId, 'payLoan') then
        return { success = false, reason = 'Aguarde antes de realizar outro pagamento' }
    end

    local companyId = nil
    if isCompanyLoan then
        local company = CompanyService.GetByMember(citizenId)
        if not company then
            return { success = false, reason = 'Empresa não encontrada' }
        end
        local member = DB_GetMember(citizenId)
        if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
            return { success = false, reason = 'Sem permissão para pagar empréstimo empresarial' }
        end
        companyId = company.id
    end

    return LoanService.Pay(source, citizenId, companyId, loanId, amount)
end)

-- ============================================================
-- REPO MAN
-- ============================================================

lib.callback.register('aurp_trucker:getRepoOrders', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    if not company or company.company_type ~= 'repo' then return {} end
    return DB_GetAvailableRepoOrders() or {}
end)

lib.callback.register('aurp_trucker:acceptRepoOrder', function(source, orderId)
    return RepoService.Accept(source, tonumber(orderId) or 0)
end)

-- H1: price NÃO é mais aceito do cliente — calculado server-side com SimState[src].lastFuel
-- Desta forma um cliente malicioso não pode enviar price=1 para abastecer gratuitamente
lib.callback.register('aurp_trucker:payForFuel', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end

    local serverFuel = TruckSimulationService.GetLastFuel(source)
    local needed     = 100.0 - serverFuel
    if needed < 0.1 then return false, 'Tanque já está cheio' end

    local price = math.ceil(needed * Config.TruckSimulation.Fuel.FuelPricePerUnit)
    if price <= 0 then return false, 'Preço inválido' end

    if not Framework.RemoveMoney(Player, 'cash', price, 'aurp-trucker-fuel') then
        return false, 'Saldo insuficiente'
    end

    -- Atualizar estado server-side imediatamente (antes do próximo sync)
    TruckSimulationService.SetLastFuel(source, 100.0)
    return true, price
end)

-- =============================================
-- PARTY / CONVOY CALLBACKS (Fase 3A)
-- =============================================

lib.callback.register('aurp_trucker:partyCreate', function(source)
    local partyId, err = PartyService.Create(source)
    return { success = partyId ~= nil, partyId = partyId, reason = err }
end)

lib.callback.register('aurp_trucker:partyInvite', function(source, targetName)
    -- H-05: Validar targetName antes de chamar :lower() — evita crash se nil/não-string
    if type(targetName) ~= 'string' or targetName == '' or #targetName > 64 then
        return { success = false, reason = 'Nome inválido' }
    end
    -- Buscar targetSrc pelo nome do personagem (ou Steam name como fallback)
    local targetSrc = nil
    local searchLower = targetName:lower()
    for _, playerSrc in ipairs(GetPlayers()) do
        local s = tonumber(playerSrc)
        local charName = GetCharName(s):lower()
        local steamName = (GetPlayerName(s) or ''):lower()
        if charName:find(searchLower, 1, true) or steamName:find(searchLower, 1, true) then
            targetSrc = s; break
        end
    end
    if not targetSrc then return { success = false, reason = 'Jogador não encontrado' } end

    local ok, err = PartyService.Invite(source, targetSrc)
    return { success = ok, reason = err }
end)

lib.callback.register('aurp_trucker:partyAccept', function(source, partyId)
    local ok, err = PartyService.Accept(source, partyId)
    return { success = ok, reason = err }
end)

lib.callback.register('aurp_trucker:partyLeave', function(source)
    PartyService.Leave(source)
    return { success = true }
end)

lib.callback.register('aurp_trucker:partyDisband', function(source)
    local ok, err = PartyService.Disband(source)
    return { success = ok ~= false, reason = err }
end)

lib.callback.register('aurp_trucker:convoyStart', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local cid     = Framework.GetCitizenId(Player)
    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return { success = false, reason = 'Você não está em um party' } end
    local party = VP_Trucker.Parties[partyId]
    if not party then return { success = false, reason = 'Party não encontrado' } end
    if party.leader ~= cid then return { success = false, reason = 'Apenas o líder pode iniciar o convoy' } end

    local ok, result = ConvoyService.Start(partyId)
    return { success = ok, reason = ok and nil or result }
end)

lib.callback.register('aurp_trucker:cbRadioSend', function(source, message)
    if not message or message == '' then return { success = false } end
    -- Limitar tamanho da mensagem
    message = tostring(message):sub(1, 100)
    ConvoyService.Broadcast(source, message)
    return { success = true }
end)

-- ============================================================
-- ILLEGAL DELIVERIES (Fase 3B)
-- ============================================================

-- Retorna opções de cargo disponíveis no contato para exibir no menu
lib.callback.register('aurp_trucker:getIllegalJobs', function(source, contactId)
    -- Validar contactId
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if not contact then return nil end  -- nil = client não exibe menu

    local options = {}
    for _, illegalType in ipairs(contact.cargo) do
        -- Selecionar área de destino aleatória compatível (não revela coords)
        local compatible = {}
        for _, d in ipairs(Config.IllegalJobs.deliveries) do
            for _, a in ipairs(d.accepts) do
                if a == illegalType then table.insert(compatible, d); break end
            end
        end
        local destArea = (#compatible > 0) and compatible[math.random(#compatible)].area or '???'

        -- Estimar faixa de pagamento (±20% em torno de estimativa com 30 km fictícios)
        local mult    = Config.IllegalJobs.paymentMultipliers[illegalType] or 1.0
        local estBase = math.floor(Config.JobGeneration.distanceMultiplier * 30 * mult)
        local low     = math.floor(estBase * 0.8)
        local high    = math.floor(estBase * 1.2)

        table.insert(options, {
            illegalType     = illegalType,
            cargoLabel      = Config.IllegalJobs.alertLabels[illegalType] or illegalType,
            paymentEstimate = ('$%d – $%d'):format(low, high),
            destArea        = destArea,
        })
    end
    return options
end)

-- Aceita um job ilegal específico do contato
lib.callback.register('aurp_trucker:acceptIllegalJob', function(source, contactId, illegalType)
    if not IllegalService then return { success = false, reason = 'Serviço indisponível' } end

    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local cid = Framework.GetCitizenId(Player)

    -- Validar: sem job ativo
    if DB_GetActiveJobByPlayer(cid) then
        return { success = false, reason = 'Você já tem um trabalho ativo' }
    end

    local result = IllegalService.Generate(contactId, illegalType, source)
    if not result then return { success = false, reason = 'Trabalho indisponível agora' } end

    -- Alerta para cops/SALA após aceite
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if contact then
        IllegalService.BroadcastAlert(source, illegalType, contact.area)
    end

    return { success = true, jobData = result }
end)

-- =====================================================
-- NPC DRIVERS (v10.0.0)
-- =====================================================

lib.callback.register('aurp_trucker:getNpcDriverData', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return nil end
    local citizenId = Framework.GetCitizenId(Player)
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local drivers  = NpcDriverService.GetByCompany(company.id)
    local profiles = NpcDriverService.GetAgencyProfiles()
    local rep      = (VP_Trucker.Companies[company.id] or {}).reputation or 100
    local illegal  = (VP_Trucker.Companies[company.id] or {}).allow_illegal_npc or 0

    return {
        success      = true,
        drivers      = drivers,
        profiles     = profiles,
        reputation   = rep,
        allowIllegal = illegal == 1,
    }
end)

lib.callback.register('aurp_trucker:hireNpcDriver', function(source, profileIndex, playerCoords)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Apenas owner/manager podem contratar' }
    end

    local ok, result = NpcDriverService.Hire(source, company.id, profileIndex, playerCoords or {})
    return { success = ok, reason = not ok and result or nil, driver = ok and result or nil }
end)

lib.callback.register('aurp_trucker:fireNpcDriver', function(source, driverId)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Framework.GetCitizenId(Player)
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Apenas owner/manager podem demitir' }
    end

    local ok, err = NpcDriverService.Fire(source, company.id, driverId)
    return { success = ok, reason = err }
end)

lib.callback.register('aurp_trucker:trainNpcDriver', function(source, driverId)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Framework.GetCitizenId(Player)
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local ok, result = NpcDriverService.Train(source, company.id, driverId)
    return { success = ok, reason = not ok and result or nil, newSkill = ok and result or nil }
end)

lib.callback.register('aurp_trucker:setNpcAllowIllegal', function(source, allowed)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Framework.GetCitizenId(Player)
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false } end

    local member = DB_GetMember(citizenId)
    if not member or member.role ~= 'owner' then
        return { success = false, reason = 'Apenas owner pode configurar jobs ilegais' }
    end

    NpcDriverService.SetAllowIllegal(source, company.id, allowed)
    return { success = true }
end)

lib.callback.register('aurp_trucker:npcRespondEvent', function(source, eventId, response)
    local result = NpcDriverService.RespondToEvent(source, eventId, response)
    return result
end)

-- ADR Certifications (v11.0.0)

lib.callback.register('aurp_trucker:submitAdrExam', function(source, data)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    local adrType   = data and data.adrType

    -- Validar tipo
    if not Config.Adr.ExamCost[adrType] then
        return { success = false, reason = 'Tipo ADR inválido' }
    end

    -- 1. Verificar cooldown
    local key     = citizenId .. '_' .. adrType
    local now     = os.time()
    local cooldown = VP_Trucker.AdrExamCooldowns[key]
    if cooldown and now < cooldown then
        return { success = false, reason = 'retry_cooldown', remainingSeconds = cooldown - now }
    end

    -- 2. Verificar se já possui cert válida
    if AdrService.HasCert(citizenId, adrType) then
        return { success = false, reason = 'Você já possui esta certificação' }
    end

    -- 3. Deduzir taxa do exame
    local cost    = Config.Adr.ExamCost[adrType]
    local removed = Framework.RemoveMoney(Player, 'bank', cost, 'adr-exam')
    if not removed then
        return { success = false, reason = 'Saldo bancário insuficiente' }
    end

    -- 4. Avaliar respostas (data.answers = { [questionIndex] = selectedOptionIndex })
    local questions = data.questions  -- { { qIdx, answer } } — índices das perguntas e respostas do player
    local bank      = Config.Adr.Questions[adrType]
    local correct   = 0
    if questions and bank then
        for _, qa in ipairs(questions) do
            local q = bank[qa.qIdx]
            if q and qa.answer == q.answer then
                correct = correct + 1
            end
        end
    end

    -- 5. Resultado
    if correct >= 2 then
        local expiresAt = AdrService.GrantCert(citizenId, adrType)
        return { success = true, passed = true, expiresAt = expiresAt }
    else
        -- 6. Reprovar: registrar cooldown (dinheiro NÃO devolvido)
        VP_Trucker.AdrExamCooldowns[key] = now + Config.Adr.RetryCooldownSeconds
        return { success = true, passed = false, correct = correct }
    end
end)

lib.callback.register('aurp_trucker:renewAdrCert', function(source, adrType)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)

    -- Validar tipo
    if not Config.Adr.RenewalCost[adrType] then
        return { success = false, reason = 'Tipo ADR inválido' }
    end

    -- Deve ter cert prévia (expirada ou válida) para renovar
    local existing = DB_GetAdrCert(citizenId, adrType)
    if not existing then
        return { success = false, reason = 'Sem certificação prévia — faça o exame primeiro' }
    end

    local cost    = Config.Adr.RenewalCost[adrType]
    local removed = Framework.RemoveMoney(Player, 'bank', cost, 'adr-renewal')
    if not removed then
        return { success = false, reason = 'Saldo bancário insuficiente' }
    end

    local expiresAt = AdrService.Renew(citizenId, adrType)
    return { success = true, expiresAt = expiresAt }
end)

-- ============================================================
-- FASE 5: FORKLIFT CALLBACKS
-- ============================================================

-- Aluguel de forklift
-- data = { locationId, mode, expected }
lib.callback.register('aurp_trucker:rentForklift', function(source, data)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Framework.GetCitizenId(Player)

    -- Validar e sanitizar inputs do client
    if type(data) ~= 'table' then return { success = false, reason = 'Dados inválidos' } end
    local locationId = tostring(data.locationId or '')
    local mode       = tostring(data.mode or '')
    if locationId == '' or (mode ~= 'tradepoint' and mode ~= 'industry') then
        return { success = false, reason = 'Dados inválidos' }
    end

    if ForkliftService.GetRental(citizenId) then
        return { success = false, reason = 'Você já tem um forklift alugado' }
    end

    if mode == 'tradepoint' and not ForkliftService.IsAvailable(locationId) then
        return { success = false, reason = 'Forklift em uso neste local' }
    end

    -- Para tradepoint: expected derivado do Config (não confia no client)
    -- Para industry:   expected inicial mínimo; updateForkliftExpected corrige depois
    local expected
    if mode == 'tradepoint' then
        for _, tp in ipairs(Config.Forklift.TradePoints) do
            if tp.id == locationId then expected = tp.maxPallets; break end
        end
        if not expected then return { success = false, reason = 'Local inválido' } end
    else
        expected = math.max(1, math.min(6, math.floor(tonumber(data.expected) or 1)))
    end

    local removed = Framework.RemoveMoney(Player, 'bank', Config.Forklift.RentalCost, 'forklift-rental')
    if not removed then
        return { success = false, reason = 'Saldo bancário insuficiente' }
    end

    -- src passado ao Rent para o timer server-side poder disparar evento de timeout
    ForkliftService.Rent(citizenId, source, locationId, mode, expected)
    return { success = true }
end)

-- Devolução voluntária (player retornou ao spawn — recebe $250)
lib.callback.register('aurp_trucker:returnForklift', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Framework.GetCitizenId(Player)

    local result = ForkliftService.Return(citizenId)
    if result.success and result.refund > 0 then
        Framework.AddMoney(Player, 'bank', result.refund, 'forklift-return')
    end
    return result
end)

-- Conclusão de trade point (todos os pallets carregados)
-- data = { locationId }  (elapsedSeconds é calculado server-side para evitar exploits)
lib.callback.register('aurp_trucker:completeTradePoint', function(source, data)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Framework.GetCitizenId(Player)

    local rental = ForkliftService.GetRental(citizenId)
    if not rental or rental.mode ~= 'tradepoint' or rental.locationId ~= tostring(data.locationId or '') then
        return { success = false, reason = 'Missão inválida' }
    end
    if rental.loaded < rental.expected then
        return { success = false, reason = 'Nem todos os pallets foram carregados' }
    end

    -- Tempo calculado server-side: rental.rentedAt gravado em ForkliftService.Rent()
    -- Usar os.time() aqui garante que o client não pode manipular o speedMult enviando elapsedSeconds = 0
    local elapsedSeconds = os.time() - (rental.rentedAt or os.time())
    local payment = ForkliftService.CompleteTradePoint(citizenId, rental.locationId, elapsedSeconds)
    Framework.AddMoney(Player, 'bank', payment, 'forklift-tradepoint')

    -- Cleanup SEM refund: missão concluída, forklift "devolvido" implicitamente
    ForkliftService.Cleanup(citizenId)

    return { success = true, payment = payment }
end)

-- =====================================================
-- GPS TRACKER (v14.0.0)
-- =====================================================

lib.callback.register('aurp_trucker:purchaseGpsTracker', function(src, plate)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador inválido.' end
    local citizenId = Framework.GetCitizenId(Player)

    -- Validar que o veículo pertence à empresa do jogador
    local company = CompanyService.GetByMember(citizenId)
    if not company then return false, 'Você não é membro de uma empresa.' end

    local vehicles = DB_GetVehicles(company.id) or {}
    local vehicle  = nil
    for _, v in ipairs(vehicles) do
        if v.plate == plate then vehicle = v; break end
    end
    if not vehicle then return false, 'Veículo não pertence à sua empresa.' end

    if vehicle.has_gps_tracker == 1 then
        return false, 'Este veículo já tem GPS tracker instalado.'
    end

    -- Cobrar da conta da empresa
    local price = Config.CargoTheft.GpsTrackerPrice
    if company.balance < price then
        return false, ('Saldo insuficiente. Necessário: $%d'):format(price)
    end

    CompanyService.UpdateBalance(company.id, -price)
    DB_SetGpsTracker(plate, true)

    return true, ('GPS Tracker instalado em %s — $%d debitados da empresa.'):format(plate, price)
end)

-- Crude Oil Pipeline — refinery list for client GPS
lib.callback.register('aurp_trucker:getRefineries', function(_src)
    local ok, result = pcall(function()
        return exports['AUST_oilfield']:GetRefineries()
    end)
    if ok and result then return result end
    return Config.CrudeOil and Config.CrudeOil.Refineries or {}  -- fallback to config
end)

-- ============================================================
-- CONTAINER HANDLER (v20)
-- ============================================================

-- Inicia missão: sorteia local + slot + cargo, registra job ativo
lib.callback.register('aurp_trucker:containerHandler:start', function(source)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    return ContainerHandlerService.Start(citizenId, source)
end)

-- Valida entrega server-side, paga e concede XP
lib.callback.register('aurp_trucker:containerHandler:complete', function(source, coords)
    if not coords then return { success = false, reason = 'Dados de entrega inválidos' } end
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    return ContainerHandlerService.Complete(citizenId, source, coords)
end)

-- ============================================================
-- LC LOGISTICS EXTENDED CALLBACKS
-- ============================================================

-- Compra na Concessionária
lib.callback.register('aurp_trucker:buyTruck', function(source, model)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return TruckFleetService.BuyTruck(source, citizenId, model)
end)

-- Venda de Caminhão Próprio
lib.callback.register('aurp_trucker:sellTruck', function(source, truckId)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return TruckFleetService.SellTruck(source, citizenId, truckId)
end)

-- Reparo Mecânico
lib.callback.register('aurp_trucker:repairTruck', function(source, truckId, part)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return TruckFleetService.RepairTruck(source, citizenId, truckId, part)
end)

-- Contratação de Empréstimo
lib.callback.register('aurp_trucker:takeLoanPlan', function(source, planIndex)
    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)
    return LoanService.TakePlan(source, citizenId, tonumber(planIndex) or 1)
end)

-- Contratação na Agência de Motoristas
lib.callback.register('aurp_trucker:hireAgencyDriver', function(source, driverIndex)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return NpcDriverService.HireAgencyDriver(source, citizenId, tonumber(driverIndex) or 1)
end)

-- Alocação de Caminhão para Motorista
lib.callback.register('aurp_trucker:assignDriverTruck', function(source, driverId, truckId)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return NpcDriverService.AssignTruck(source, citizenId, tonumber(driverId), tonumber(truckId))
end)

-- Demissão de Motorista da Frota
lib.callback.register('aurp_trucker:fireAgencyDriver', function(source, driverId)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return NpcDriverService.FireHiredDriver(source, citizenId, tonumber(driverId))
end)

-- Upgrade de Habilidade (Skill Tree)
lib.callback.register('aurp_trucker:upgradeSkill', function(source, skillType)
    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    return ProgressionService.PurchaseSkill(source, citizenId, tostring(skillType))
end)
