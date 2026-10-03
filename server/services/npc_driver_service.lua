-- aurp_trucker — server/services/npc_driver_service.lua
-- Gerencia motoristas NPC das empresas: lifecycle, jobs simulados, eventos, satisfação

NpcDriverService = {}

-- Helper: UUID v4 simples (mesmo padrão de party_service.lua)
local function NewUUID()
    local t = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' }
    local s = ''
    for i = 1, 32 do
        s = s .. t[math.random(16)]
        if i == 8 or i == 12 or i == 16 or i == 20 then s = s .. '-' end
    end
    return s
end

-- Helper: retorna src do owner de uma empresa (nil se offline)
local function GetOwnerSrc(companyId)
    local company = VP_Trucker.Companies[companyId]
    if not company then return nil end
    local ownerCid = company.owner_citizenid
    local players = Framework.GetAllPlayers() or {}
    for _, p in pairs(players) do
        if Framework.GetCitizenId(p) == ownerCid then
            return Framework.GetSource(p)
        end
    end
    return nil
end

-- Nomes de NPC gerados aleatoriamente
local NPC_NAMES = {
    'Carlos Souza', 'João Lima', 'Pedro Alves', 'Marcos Ferreira',
    'Rafael Costa', 'Bruno Oliveira', 'Diego Santos', 'Lucas Pereira',
    'André Rocha', 'Felipe Gomes', 'Thiago Martins', 'Rodrigo Nunes',
    'Eduardo Carvalho', 'Gabriel Silva', 'Mateus Ribeiro',
}

local function GenerateDriverProfile(index)
    local name = NPC_NAMES[math.random(#NPC_NAMES)]
    local roll = math.random(10)
    local skill = roll <= 6 and 'junior' or (roll <= 9 and 'pleno' or 'senior')
    local salaryBase = Config.NpcDrivers.hireCost[skill] or 2000
    local salary = math.floor(salaryBase * (0.10 + math.random() * 0.10))
    return {
        index      = index,
        name       = name,
        skillLevel = skill,
        salary     = salary,
        hireCost   = Config.NpcDrivers.hireCost[skill],
    }
end

-- ============================================================
-- LOAD FROM DB (chamado em main.lua após Ready)
-- ============================================================

function NpcDriverService.LoadFromDB()
    local drivers = DB_GetAllActiveNpcDrivers() or {}
    for _, d in ipairs(drivers) do
        VP_Trucker.NpcDrivers[d.id] = d
    end

    local now = os.time()

    -- Jobs em 'event' → auto-fail (evento perdido no restart)
    local eventJobs = DB_GetNpcJobsByStatus('event') or {}
    if #eventJobs > 0 then
        local jobIds         = {}
        local driverPrefixes = {}
        for _, j in ipairs(eventJobs) do
            table.insert(jobIds, j.id)
            table.insert(driverPrefixes, 'npc_' .. j.driver_id)
            local driver = VP_Trucker.NpcDrivers[j.driver_id]
            if driver then
                driver.status        = 'idle'
                driver.active_job_id = nil
                DB_UpdateNpcDriverStatus(j.driver_id, 'idle', nil)
            end
        end
        -- audit C-02: guard contra batch vazio — IN () é SQL inválido e crasharia o oxmysql
        if #jobIds > 0 then
            local ph1 = string.rep('?,', #jobIds):sub(1, -2)
            MySQL.update.await(
                'UPDATE trucker_npc_jobs SET status=\'failed\', earnings=0 WHERE id IN (' .. ph1 .. ')',
                jobIds
            )
        end
        if #driverPrefixes > 0 then
            local ph2 = string.rep('?,', #driverPrefixes):sub(1, -2)
            MySQL.update.await(
                "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid IN (" .. ph2 .. ')',
                driverPrefixes
            )
        end
    end

    -- Jobs em 'active' → restaurar cache; expirados → completar
    -- Aceitável pois limite é 5 drivers/empresa × N empresas
    local activeJobs = DB_GetNpcJobsByStatus('active') or {}
    for _, j in ipairs(activeJobs) do
        VP_Trucker.NpcJobs[j.id] = j
        if j.expected_end_at <= now then
            local driver = VP_Trucker.NpcDrivers[j.driver_id]
            if driver then
                NpcDriverService._CompleteJob(driver, j)
            end
        end
    end

    -- Drivers em 'resting' com resting_until passado → idle
    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.status == 'resting' and driver.resting_until and driver.resting_until <= now then
            driver.status        = 'idle'
            driver.active_job_id = nil
            DB_UpdateNpcDriverStatus(id, 'idle', nil)
        end
    end

    if Config.Debug then
        local count = 0
        for _ in pairs(VP_Trucker.NpcDrivers) do count = count + 1 end
        print(('[aurp_trucker] NpcDriverService.LoadFromDB: %d drivers carregados'):format(count))
    end
end

-- ============================================================
-- PROCESS TICK (SetInterval 5min)
-- ============================================================

function NpcDriverService.ProcessTick()
    local now = os.time()

    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        -- Resting: verificar se tempo acabou
        if driver.status == 'resting' and driver.resting_until and driver.resting_until <= now then
            driver.status        = 'idle'
            driver.active_job_id = nil
            DB_UpdateNpcDriverStatus(id, 'idle', nil)
        end

        -- Working: verificar se job concluiu (ignorar jobs pausados em 'event')
        if driver.status == 'working' and driver.active_job_id then
            local npcJob = VP_Trucker.NpcJobs[driver.active_job_id]
            if npcJob and npcJob.status ~= 'event' and now >= npcJob.expected_end_at then
                NpcDriverService._RollEvent(driver, npcJob)
            end
        end

        -- Idle: tentar atribuir job
        if driver.status == 'idle' then
            NpcDriverService._TryAssignJob(driver)
        end

        -- Rotina diária
        local today     = math.floor(now / 86400)
        local lastCheck = math.floor((driver.last_tenure_check or 0) / 86400)
        if today > lastCheck then
            NpcDriverService._CheckTenure(driver)
            NpcDriverService._ApplySatisfactionDecay(driver)
            NpcDriverService._CheckQuitRisk(driver)
            driver.last_tenure_check = now
            DB_UpdateNpcDriverTenure(id, driver.tenure_days, now)
        end
    end

    NpcDriverService._BroadcastPositions()
end

-- ============================================================
-- JOB ASSIGNMENT
-- ============================================================

function NpcDriverService._TryAssignJob(driver)
    local company = VP_Trucker.Companies[driver.company_id]
    if not company then return end

    local job = nil
    if company.allow_illegal_npc == 1 then
        local catchChance = Config.NpcDrivers.contraband.catchChance[driver.skill_level] or 0.15
        if math.random() > catchChance then
            job = DB_GetOneAvailableIllegalJobForNpc()
        end
    end

    if not job then
        job = DB_GetOneAvailableJobForNpc()
    end
    if not job then return end

    -- Reservar trucker_job
    MySQL.update.await(
        "UPDATE trucker_jobs SET status='active', assigned_citizenid=? WHERE id=? AND status='available'",
        { 'npc_' .. driver.id, job.id }
    )

    local baseDuration = math.max(60, (job.distance or 1) / 0.5)
    local duration = math.floor(baseDuration / (Config.NpcDrivers.skillSpeedFactor[driver.skill_level] or 1.0))

    local npcJobId = NewUUID()
    local now = os.time()
    local npcJob = {
        id              = npcJobId,
        driver_id       = driver.id,
        company_id      = driver.company_id,
        origin_id       = job.origin_id,
        dest_id         = job.dest_id,
        cargo_item      = job.cargo_item,
        base_payment    = job.base_payment,
        distance        = job.distance,
        illegal         = (job.illegal_type and 1) or 0,
        assigned_at     = now,
        expected_end_at = now + duration,
        status          = 'active',
        earnings        = 0,
    }

    DB_InsertNpcJob(npcJob)
    VP_Trucker.NpcJobs[npcJobId] = npcJob
    driver.status        = 'working'
    driver.active_job_id = npcJobId
    DB_UpdateNpcDriverStatus(driver.id, 'working', npcJobId)

    if Config.Debug then
        print(('[aurp_trucker] NPC %s → job %s (%s→%s, %ds)'):format(
            driver.name, npcJobId, job.origin_id, job.dest_id, duration))
    end
end

-- ============================================================
-- JOB COMPLETION
-- ============================================================

function NpcDriverService._CompleteJob(driver, npcJob)
    local earnings = math.floor((npcJob.base_payment or 0) * (Config.NpcDrivers.skillEfficiency[driver.skill_level] or 1.0))

    -- Creditar empresa (DB_UpdateCompanyBalance não atualiza cache — fazer manualmente)
    DB_UpdateCompanyBalance(npcJob.company_id, earnings)
    if VP_Trucker.Companies[npcJob.company_id] then
        VP_Trucker.Companies[npcJob.company_id].balance =
            (VP_Trucker.Companies[npcJob.company_id].balance or 0) + earnings
    end

    -- Reputação: apenas jobs legítimos
    if npcJob.illegal == 0 then
        local repGain = (npcJob.distance or 0) >= Config.NpcDrivers.reputation.longJobDistanceKm
            and Config.NpcDrivers.reputation.gainPerLongJob
            or  Config.NpcDrivers.reputation.gainPerNormalJob
        DB_UpdateCompanyReputation(npcJob.company_id, repGain)
    end

    local satGain = Config.NpcDrivers.satisfaction.gainPerJob
    driver.xp             = (driver.xp or 0) + 1
    driver.satisfaction   = math.min(100, (driver.satisfaction or 80) + satGain)
    driver.total_earnings = (driver.total_earnings or 0) + earnings
    driver.status         = 'idle'
    driver.active_job_id  = nil

    DB_UpdateNpcJobStatus(npcJob.id, 'completed', earnings)
    DB_UpdateNpcDriverStats(driver.id, 1, satGain, earnings)
    DB_UpdateNpcDriverStatus(driver.id, 'idle', nil)
    VP_Trucker.NpcJobs[npcJob.id] = nil

    MySQL.update.await(
        "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
        { 'npc_' .. driver.id }
    )

    local ownerSrc = GetOwnerSrc(npcJob.company_id)
    if ownerSrc then
        TriggerClientEvent('aurp_trucker:client:npcDriverJobCompleted', ownerSrc, {
            driverName = driver.name,
            earnings   = earnings,
            skillLevel = driver.skill_level,
        })
    end

    if Config.Debug then
        print(('[aurp_trucker] NPC %s completou job — $%d'):format(driver.name, earnings))
    end
end

-- ============================================================
-- EVENTS
-- ============================================================

function NpcDriverService._RollEvent(driver, npcJob)
    local chance = Config.NpcDrivers.eventChance[driver.skill_level] or 0.15
    if (driver.satisfaction or 80) < Config.NpcDrivers.satisfaction.lowThreshold then
        chance = chance * 2
    end

    if math.random() < chance then
        local eventType
        if npcJob.illegal == 1 then
            eventType = 'contraband_caught'
        else
            local graveTypes = { 'major_accident', 'cargo_stolen' }
            local minorTypes = { 'traffic_fine', 'minor_accident', 'fuel_over', 'delayed' }
            if math.random() < 0.5 then
                eventType = minorTypes[math.random(#minorTypes)]
            else
                eventType = graveTypes[math.random(#graveTypes)]
            end
        end

        local isGrave = eventType == 'major_accident'
                     or eventType == 'cargo_stolen'
                     or eventType == 'contraband_caught'

        if isGrave then
            NpcDriverService._HandleGraveEvent(driver, npcJob, eventType)
        else
            NpcDriverService._HandleMinorEvent(driver, npcJob, eventType)
        end
    else
        NpcDriverService._CompleteJob(driver, npcJob)
    end
end

function NpcDriverService._HandleMinorEvent(driver, npcJob, eventType)
    local cfg = Config.NpcDrivers.minorEvents[eventType]
    if not cfg then
        NpcDriverService._CompleteJob(driver, npcJob)
        return
    end

    if eventType == 'traffic_fine' or eventType == 'fuel_over' then
        local cost = math.random(cfg.costMin, cfg.costMax)
        npcJob.base_payment = math.max(0, (npcJob.base_payment or 0) - cost)
    elseif eventType == 'delayed' then
        npcJob.expected_end_at = (npcJob.expected_end_at or os.time()) + (cfg.extraMinutes * 60)
        DB_UpdateNpcJobStatus(npcJob.id, 'active', 0)
        return
    elseif eventType == 'minor_accident' then
        local lossFactor = 1.0 - ((cfg.integrityLoss or 0) / 100)
        npcJob.base_payment = math.floor((npcJob.base_payment or 0) * lossFactor)
    end

    NpcDriverService._CompleteJob(driver, npcJob)
end

function NpcDriverService._HandleGraveEvent(driver, npcJob, eventType)
    -- CRÍTICO: atualizar cache ANTES do DB para que ProcessTick não re-role no mesmo job
    npcJob.status = 'event'
    DB_UpdateNpcJobStatus(npcJob.id, 'event', 0)

    local eventId   = NewUUID()
    local expiresAt = os.time() + Config.NpcDrivers.graveEventTimerSeconds

    local payload = {
        eventId    = eventId,
        driverId   = driver.id,
        driverName = driver.name,
        type       = eventType,
        expiresAt  = expiresAt,
    }

    if eventType == 'major_accident' then
        local cfg = Config.NpcDrivers.graveEvents.major_accident
        payload.repairCost = math.random(cfg.repairMin, cfg.repairMax)

    elseif eventType == 'contraband_caught' then
        payload.bribeAmount = Config.NpcDrivers.graveEvents.contraband_caught.bribeAmount
        -- Efeitos imediatos
        DB_UpdateCompanyReputation(npcJob.company_id, -Config.NpcDrivers.contraband.reputationPenalty)
        DB_UpdateCompanyBalance(npcJob.company_id, -Config.NpcDrivers.contraband.fineAmount, true) -- multa: pode deixar saldo negativo
        if VP_Trucker.Companies[npcJob.company_id] then
            VP_Trucker.Companies[npcJob.company_id].balance =
                (VP_Trucker.Companies[npcJob.company_id].balance or 0) - Config.NpcDrivers.contraband.fineAmount
        end
        -- Alerta SALA
        local companyName = (VP_Trucker.Companies[npcJob.company_id] or {}).name or '?'
        local originName  = npcJob.origin_id
        for _, o in ipairs(Config.PrimaryIndustries or {}) do
            if o.id == npcJob.origin_id then originName = o.name; break end
        end
        TriggerEvent('aurp_trucker:npcContrabandAlert', {
            companyName = companyName,
            driverName  = driver.name,
            area        = originName,
            illegalType = npcJob.cargo_item,
        })
    end

    VP_Trucker.PendingEvents[eventId] = { driver = driver, npcJob = npcJob, payload = payload }

    local ownerSrc = GetOwnerSrc(npcJob.company_id)
    if ownerSrc then
        TriggerClientEvent('aurp_trucker:client:npcGraveEvent', ownerSrc, payload)
    end

    -- Auto-resolver como 'ignore' após timer
    SetTimeout(Config.NpcDrivers.graveEventTimerSeconds * 1000, function()
        if VP_Trucker.PendingEvents[eventId] then
            NpcDriverService.RespondToEvent(nil, eventId, 'ignore')
        end
    end)
end

function NpcDriverService.RespondToEvent(src, eventId, response)
    local pending = VP_Trucker.PendingEvents[eventId]
    if not pending then return { success = false, reason = 'Evento não encontrado' } end

    VP_Trucker.PendingEvents[eventId] = nil

    local driver  = pending.driver
    local npcJob  = pending.npcJob
    local payload = pending.payload

    if payload.type == 'major_accident' then
        if response == 'pay' and src then
            local Player = Framework.GetPlayer(src)
            if Player then
                local cost = payload.repairCost or 1000
                if Framework.RemoveMoney(Player, 'bank', cost, 'npc-repair') then
                    NpcDriverService._CompleteJob(driver, npcJob)
                else
                    response = 'ignore'
                end
            end
        end
        if response == 'ignore' then
            DB_UpdateNpcDriverSatisfaction(driver.id, -Config.NpcDrivers.satisfaction.penaltyEventIgnored)
            driver.satisfaction = math.max(0, (driver.satisfaction or 80) - Config.NpcDrivers.satisfaction.penaltyEventIgnored)
            npcJob.base_payment = 0
            NpcDriverService._CompleteJob(driver, npcJob)
        end

    elseif payload.type == 'cargo_stolen' then
        DB_UpdateNpcDriverSatisfaction(driver.id, -Config.NpcDrivers.satisfaction.penaltyEventIgnored)
        driver.satisfaction = math.max(0, (driver.satisfaction or 80) - Config.NpcDrivers.satisfaction.penaltyEventIgnored)
        npcJob.base_payment = 0
        NpcDriverService._CompleteJob(driver, npcJob)

    elseif payload.type == 'contraband_caught' then
        if response == 'pay' and src then
            local Player = Framework.GetPlayer(src)
            if Player then
                local bribe = payload.bribeAmount or 3000
                -- #12: Verificar se pagamento do suborno foi bem-sucedido
                local paid = Framework.RemoveMoney(Player, 'bank', bribe, 'npc-bribe')
                if not paid then
                    -- Sem dinheiro para suborno — tratar como 'ignore'
                    local restingUntil = os.time() + Config.NpcDrivers.contraband.driverRestSeconds
                    driver.status        = 'resting'
                    driver.active_job_id = nil
                    return
                end
            end
            NpcDriverService._CompleteJob(driver, npcJob)
        else
            -- Sem suborno: driver fica retido 24h
            local restingUntil = os.time() + Config.NpcDrivers.contraband.driverRestSeconds
            driver.status        = 'resting'
            driver.active_job_id = nil
            DB_SetNpcDriverResting(driver.id, restingUntil)
            DB_UpdateNpcJobStatus(npcJob.id, 'failed', 0)
            VP_Trucker.NpcJobs[npcJob.id] = nil
            MySQL.update.await(
                "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
                { 'npc_' .. driver.id }
            )
        end
    end

    local ownerSrc = GetOwnerSrc(npcJob.company_id)
    if ownerSrc then
        TriggerClientEvent('aurp_trucker:client:npcEventResolved', ownerSrc, {
            eventId    = eventId,
            resolution = response,
        })
    end

    return { success = true }
end

-- ============================================================
-- DAILY ROUTINES
-- ============================================================

function NpcDriverService._CheckTenure(driver)
    driver.tenure_days = (driver.tenure_days or 0) + 1

    local cfg  = Config.NpcDrivers.tenureDemands
    local now  = os.time()

    for _, demand in ipairs(cfg) do
        if driver.tenure_days == demand.days then
            driver.last_demand_at = now
            local ownerSrc = GetOwnerSrc(driver.company_id)
            if ownerSrc then
                TriggerClientEvent('aurp_trucker:client:npcDemandGenerated', ownerSrc, {
                    driverId   = driver.id,
                    driverName = driver.name,
                    demandType = demand.type,
                    value      = demand.value,
                    expiresAt  = now + (Config.NpcDrivers.demandExpiryDays * 86400),
                })
            end
        end
    end
end

function NpcDriverService._ApplySatisfactionDecay(driver)
    local company = VP_Trucker.Companies[driver.company_id]
    if not company then return end

    local expectedSalary = math.floor((Config.NpcDrivers.hireCost[driver.skill_level] or 2000) * 0.12)
    if (driver.salary or 0) < expectedSalary then
        local decay = Config.NpcDrivers.satisfaction.decayPerDayLowSalary
        driver.satisfaction = math.max(0, (driver.satisfaction or 80) - decay)
        DB_UpdateNpcDriverSatisfaction(driver.id, -decay)
    end
end

function NpcDriverService._CheckQuitRisk(driver)
    if (driver.satisfaction or 80) < Config.NpcDrivers.satisfaction.criticalThreshold then
        if math.random(100) <= 10 then
            local companyId = driver.company_id
            driver.status = 'quit'
            DB_SetNpcDriverQuit(driver.id)
            VP_Trucker.NpcDrivers[driver.id] = nil

            local ownerSrc = GetOwnerSrc(companyId)
            if ownerSrc then
                TriggerClientEvent('aurp_trucker:client:npcDriverQuit', ownerSrc, {
                    driverName = driver.name,
                })
            end
        end
    end
end

function NpcDriverService._BroadcastPositions()
    local byCompany = {}
    local now = os.time()

    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.status == 'working' and driver.active_job_id then
            local npcJob = VP_Trucker.NpcJobs[driver.active_job_id]
            if npcJob and npcJob.status == 'active' then
                local elapsed  = now - (npcJob.assigned_at or now)
                local total    = math.max(1, (npcJob.expected_end_at or now) - (npcJob.assigned_at or now))
                local progress = math.min(1.0, elapsed / total)

                local ox, oy, oz = 0, 0, 30
                local dx2, dy2, dz2 = 0, 0, 30
                for _, ind in ipairs(Config.PrimaryIndustries or {}) do
                    if ind.id == npcJob.origin_id then
                        ox = ind.coords.x; oy = ind.coords.y; oz = ind.coords.z
                    end
                end
                for _, ind in ipairs(Config.SecondaryIndustries or {}) do
                    if ind.id == npcJob.dest_id then
                        dx2 = ind.coords.x; dy2 = ind.coords.y; dz2 = ind.coords.z
                    end
                end

                local posX = ox + (dx2 - ox) * progress
                local posY = oy + (dy2 - oy) * progress
                local posZ = oz + (dz2 - oz) * progress

                local cid = driver.company_id
                if not byCompany[cid] then byCompany[cid] = {} end
                byCompany[cid][id] = {
                    x      = posX,
                    y      = posY,
                    z      = posZ,
                    name   = driver.name,
                    status = driver.status,
                }
            end
        end
    end

    for companyId, positions in pairs(byCompany) do
        local ownerSrc = GetOwnerSrc(companyId)
        if ownerSrc then
            TriggerClientEvent('aurp_trucker:client:npcPositionUpdate', ownerSrc, positions)
        end
    end
end

-- ============================================================
-- MANAGEMENT API
-- ============================================================

function NpcDriverService.GetAgencyProfiles()
    local ap  = VP_Trucker.AgencyProfiles
    local now = os.time()
    if ap.generatedAt and (now - ap.generatedAt) < Config.NpcDrivers.agencyRefreshSeconds
       and #(ap.profiles or {}) == 3 then
        return ap.profiles
    end
    local profiles = {}
    for i = 1, 3 do
        table.insert(profiles, GenerateDriverProfile(i))
    end
    VP_Trucker.AgencyProfiles = { profiles = profiles, generatedAt = now }
    return profiles
end

function NpcDriverService.Hire(src, companyId, profileIndex, playerCoords)
    -- S-04: Usar coords server-side em vez de confiar no client
    local ped = GetPlayerPed(src)
    local serverCoords = ped and ped ~= 0 and GetEntityCoords(ped) or playerCoords
    local agency = Config.NpcDrivers.agencyLocation
    local dx = (serverCoords.x or 0) - agency.x
    local dy = (serverCoords.y or 0) - agency.y
    if math.sqrt(dx*dx + dy*dy) > Config.NpcDrivers.agencyRadius then
        return false, 'Você precisa estar na agência de emprego'
    end

    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end

    local count = 0
    for _, d in pairs(VP_Trucker.NpcDrivers) do
        if d.company_id == companyId then count = count + 1 end
    end
    if count >= Config.NpcDrivers.maxDriversPerCompany then
        return false, ('Limite de %d motoristas atingido'):format(Config.NpcDrivers.maxDriversPerCompany)
    end

    local profiles = NpcDriverService.GetAgencyProfiles()
    local profile  = profiles[profileIndex]
    if not profile then return false, 'Perfil inválido' end

    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    if not Framework.RemoveMoney(Player, 'bank', profile.hireCost, 'npc-hire') then
        return false, 'Saldo bancário insuficiente'
    end

    local driverId = NewUUID()
    local driver = {
        id                = driverId,
        company_id        = companyId,
        name              = profile.name,
        skill_level       = profile.skillLevel,
        salary            = profile.salary,
        satisfaction      = Config.NpcDrivers.satisfaction.startValue,
        xp                = 0,
        tenure_days       = 0,
        total_earnings    = 0,
        status            = 'idle',
        active_job_id     = nil,
        last_tenure_check = os.time(),
        resting_until     = nil,
    }
    DB_InsertNpcDriver(driver)
    VP_Trucker.NpcDrivers[driverId] = driver

    -- Invalidar perfis da agência
    VP_Trucker.AgencyProfiles.generatedAt = 0

    if Config.Debug then
        print(('[aurp_trucker] Contratado: %s (%s) para empresa %s'):format(driver.name, driver.skill_level, companyId))
    end
    return true, driver
end

function NpcDriverService.Fire(src, companyId, driverId)
    local driver = VP_Trucker.NpcDrivers[driverId]
    if not driver or driver.company_id ~= companyId then
        return false, 'Motorista não encontrado'
    end

    if driver.active_job_id then
        local npcJob = VP_Trucker.NpcJobs[driver.active_job_id]
        if npcJob then
            DB_UpdateNpcJobStatus(npcJob.id, 'failed', 0)
            VP_Trucker.NpcJobs[npcJob.id] = nil
        end
        MySQL.update.await(
            "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
            { 'npc_' .. driverId }
        )
    end

    DB_SetNpcDriverQuit(driverId)
    VP_Trucker.NpcDrivers[driverId] = nil
    return true
end

function NpcDriverService.Train(src, companyId, driverId)
    local driver = VP_Trucker.NpcDrivers[driverId]
    if not driver or driver.company_id ~= companyId then
        return false, 'Motorista não encontrado'
    end

    local nextSkill, cost, jobsRequired
    if driver.skill_level == 'junior' then
        nextSkill    = 'pleno'
        cost         = Config.NpcDrivers.trainingCost.junior_to_pleno
        jobsRequired = Config.NpcDrivers.trainingJobsRequired.junior_to_pleno
    elseif driver.skill_level == 'pleno' then
        nextSkill    = 'senior'
        cost         = Config.NpcDrivers.trainingCost.pleno_to_senior
        jobsRequired = Config.NpcDrivers.trainingJobsRequired.pleno_to_senior
    else
        return false, 'Motorista já é Sênior'
    end

    if (driver.xp or 0) < jobsRequired then
        return false, ('Precisa de %d jobs completados (atual: %d)'):format(jobsRequired, driver.xp or 0)
    end

    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    if not Framework.RemoveMoney(Player, 'bank', cost, 'npc-training') then
        return false, 'Saldo bancário insuficiente'
    end

    driver.skill_level = nextSkill
    DB_UpdateNpcDriverSkill(driverId, nextSkill)
    return true, nextSkill
end

function NpcDriverService.SetAllowIllegal(src, companyId, allowed)
    local company = VP_Trucker.Companies[companyId]
    if not company then return false end
    company.allow_illegal_npc = allowed and 1 or 0
    DB_SetNpcAllowIllegal(companyId, allowed)
    return true
end

function NpcDriverService.GetByCompany(companyId)
    local result = {}
    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.company_id == companyId then
            local d = {}
            for k, v in pairs(driver) do d[k] = v end
            if driver.active_job_id then
                d.activeJob = VP_Trucker.NpcJobs[driver.active_job_id]
            end
            table.insert(result, d)
        end
    end
    return result
end

-- ============================================================
-- LC RECRUITMENT AGENCY & PERSONAL FLEET DRIVERS
-- ============================================================

local agencyCache = nil
local lastAgencyGen = 0

function NpcDriverService.GetAgencyCatalog()
    local now = os.time()
    if agencyCache and (now - lastAgencyGen < 1200) then
        return agencyCache
    end

    agencyCache = {}
    lastAgencyGen = now
    local avatars = {
        'avatar1.png', 'avatar2.png', 'avatar3.png', 'avatar4.png',
        'avatar5.png', 'avatar6.png', 'avatar7.png', 'avatar8.png'
    }
    local names = {
        'Lucas Silva', 'Mateus Santos', 'Julia Rocha', 'Gabriel Oliveira',
        'Fernanda Souza', 'Rodrigo Lima', 'Beatriz Costa', 'Diego Martins',
        'Thiago Ferreira', 'Camila Ribeiro', 'Eduardo Carvalho', 'Larissa Alves'
    }

    for i = 1, 8 do
        local distSkill = math.random(0, 3)
        local valSkill  = math.random(0, 3)
        local fragSkill = math.random(0, 3)
        local fastSkill = math.random(0, 3)
        local totalSkills = distSkill + valSkill + fragSkill + fastSkill
        local basePrice = math.random(500, 1000)
        local price = math.floor(basePrice * (1 + (totalSkills * 0.25)))

        table.insert(agencyCache, {
            id = i,
            name = names[math.random(#names)],
            img = 'img/avatar/' .. avatars[math.random(#avatars)],
            price = price,
            product_type = math.random(0, 2),
            distance_skill = distSkill,
            valuable_skill = valSkill,
            fragile_skill = fragSkill,
            fast_skill = fastSkill,
        })
    end

    return agencyCache
end

function NpcDriverService.GetHiredDrivers(citizenId)
    local drivers = MySQL.query.await(
        'SELECT * FROM trucker_drivers WHERE user_id = ? ORDER BY driver_id DESC',
        { citizenId }
    ) or {}
    return drivers
end

local HiringDriverLock = {}

function NpcDriverService.HireAgencyDriver(src, citizenId, driverIndex)
    if HiringDriverLock[citizenId] then
        return false, 'Processando contratação anterior...'
    end
    HiringDriverLock[citizenId] = true

    local catalog = NpcDriverService.GetAgencyCatalog()
    local driver = catalog[driverIndex]
    if not driver then
        HiringDriverLock[citizenId] = nil
        return false, 'Candidato não encontrado na agência'
    end

    local hired = NpcDriverService.GetHiredDrivers(citizenId)
    local playerStats = DB_GetPlayerStats(citizenId)
    local lvl = playerStats and playerStats.level or 1
    local maxDrivers = 1
    if lvl >= 30 then maxDrivers = 5
    elseif lvl >= 20 then maxDrivers = 3
    elseif lvl >= 10 then maxDrivers = 2 end

    if #hired >= maxDrivers then
        HiringDriverLock[citizenId] = nil
        return false, ('Limite de motoristas atingido para seu nível (%d max)'):format(maxDrivers)
    end

    local balance = Framework.GetPlayerMoney(src, 'bank')
    if balance < driver.price then
        HiringDriverLock[citizenId] = nil
        return false, 'Saldo bancário insuficiente para contratar'
    end

    if not Framework.RemovePlayerMoney(src, 'bank', driver.price, 'Contratação de Motorista: ' .. driver.name) then
        HiringDriverLock[citizenId] = nil
        return false, 'Falha ao processar pagamento'
    end

    local driverId = MySQL.insert.await(
        [[INSERT INTO trucker_drivers (user_id, name, product_type, distance_skill, valuable_skill, fragile_skill, fast_skill, price, img, truck_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)]],
        { citizenId, driver.name, driver.product_type, driver.distance_skill, driver.valuable_skill, driver.fragile_skill, driver.fast_skill, driver.price, driver.img }
    )

    HiringDriverLock[citizenId] = nil
    return true, { driverId = driverId, name = driver.name }
end

function NpcDriverService.AssignTruck(src, citizenId, driverId, truckId)
    local driver = MySQL.single.await('SELECT * FROM trucker_drivers WHERE driver_id = ? AND user_id = ?', { driverId, citizenId })
    if not driver then return false, 'Motorista não encontrado' end

    if truckId and truckId > 0 then
        local truck = MySQL.single.await('SELECT * FROM trucker_trucks WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })
        if not truck then return false, 'Caminhão não encontrado' end

        -- Desaloca outro motorista se já usava o caminhão
        MySQL.update.await('UPDATE trucker_drivers SET truck_id = NULL WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })
        MySQL.update.await('UPDATE trucker_trucks SET driver = NULL WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })

        -- Aloca
        MySQL.update.await('UPDATE trucker_drivers SET truck_id = ? WHERE driver_id = ? AND user_id = ?', { truckId, driverId, citizenId })
        MySQL.update.await('UPDATE trucker_trucks SET driver = ? WHERE truck_id = ? AND user_id = ?', { driverId, truckId, citizenId })
    else
        -- Desalocar
        if driver.truck_id then
            MySQL.update.await('UPDATE trucker_trucks SET driver = NULL WHERE truck_id = ? AND user_id = ?', { driver.truck_id, citizenId })
        end
        MySQL.update.await('UPDATE trucker_drivers SET truck_id = NULL WHERE driver_id = ? AND user_id = ?', { driverId, citizenId })
    end

    return true
end

function NpcDriverService.FireHiredDriver(src, citizenId, driverId)
    local driver = MySQL.single.await('SELECT * FROM trucker_drivers WHERE driver_id = ? AND user_id = ?', { driverId, citizenId })
    if not driver then return false, 'Motorista não encontrado' end

    if driver.truck_id then
        MySQL.update.await('UPDATE trucker_trucks SET driver = NULL WHERE truck_id = ? AND user_id = ?', { driver.truck_id, citizenId })
    end

    MySQL.query.await('DELETE FROM trucker_drivers WHERE driver_id = ? AND user_id = ?', { driverId, citizenId })
    return true
end

-- ============================================================
-- INTERVAL (registrado no final do arquivo — fora de funções)
-- ============================================================

SetInterval(function()
    NpcDriverService.ProcessTick()
end, Config.NpcDrivers.cronIntervalMinutes * 60 * 1000)
