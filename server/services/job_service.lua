-- aurp_trucker — server/services/job_service.lua
-- Geração, aceitação, conclusão e abandono de jobs

JobService = {}

local MAX_JOBS = Config.JobGeneration.maxActiveJobs or 8

-- Retorna tabela { [destId] = pendingCount } para todos os destinos com jobs ativos/disponíveis
local function GetDestPendingCounts()
    local rows = MySQL.query.await(
        "SELECT dest_id, COUNT(*) as cnt FROM trucker_jobs WHERE status IN ('available','active') GROUP BY dest_id"
    ) or {}
    local counts = {}
    for _, row in ipairs(rows) do
        counts[row.dest_id] = row.cnt
    end
    return counts
end

-- Seleção ponderada: elementos com menos ocorrências têm maior peso.
-- Retorna nil se items estiver vazio.
local function WeightedRandom(items, weightFn)
    if #items == 0 then return nil end
    local totalWeight = 0
    local weights = {}
    for i, item in ipairs(items) do
        local w = weightFn(item)
        weights[i] = w
        totalWeight = totalWeight + w
    end
    if totalWeight <= 0 then return items[math.random(#items)] end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for i, item in ipairs(items) do
        cumulative = cumulative + weights[i]
        if roll <= cumulative then return item end
    end
    return items[#items]
end

-- Gera um ID único para job
local function GenerateJobId()
    return ('job_%d_%d'):format(os.time(), math.random(10000, 99999))
end

-- Calcula distância 2D entre dois vector3
local function CalcDistance(c1, c2)
    local dx = c1.x - c2.x
    local dy = c1.y - c2.y
    return math.sqrt(dx*dx + dy*dy) / 1000.0  -- km
end

-- Calcula tempo de expiração: jobs mais lucrativos expiram mais rápido
local function CalcExpiresAt(payment)
    local cfg = Config.JobGeneration.jobExpiration
    local ratio = math.min(1.0, payment / cfg.basePayment)
    local duration = cfg.maxTime - (cfg.maxTime - cfg.minTime) * ratio
    return os.time() + duration
end

-- Seleciona produto aleatório de uma indústria primária
local function PickProduct(primaryIndustry)
    local products = primaryIndustry.products
    if not products or #products == 0 then return nil end
    return products[math.random(#products)]
end

-- Verifica se destino aceita o produto
local function DestAccepts(dest, productName)
    if not dest.acceptedProducts then return false end
    for _, accepted in ipairs(dest.acceptedProducts) do
        if accepted == productName then return true end
    end
    return false
end

-- Gera um job entre origin e dest compatíveis (ponderado por demanda quando ativado)
local function GenerateOne()
    -- Peso para sortear cargo_qty (1–6 pacotes)
    local QTY_WEIGHTS = {
        { qty = 1, w = 30 },
        { qty = 2, w = 25 },
        { qty = 3, w = 20 },
        { qty = 4, w = 12 },
        { qty = 5, w =  8 },
        { qty = 6, w =  5 },
    }
    local function PickCargoQty()
        local total = 0
        for _, entry in ipairs(QTY_WEIGHTS) do total = total + entry.w end
        local roll = math.random() * total
        local cum  = 0
        for _, entry in ipairs(QTY_WEIGHTS) do
            cum = cum + entry.w
            if roll <= cum then return entry.qty end
        end
        return 1
    end

    local cargoQty = PickCargoQty()

    local origins = Config.PrimaryIndustries
    local dests   = Config.SecondaryIndustries

    -- Mapa de produtos aceitos por destino (para filtragem rápida)
    local destByProduct = {}
    for _, dest in ipairs(dests) do
        for _, product in ipairs(dest.acceptedProducts or {}) do
            if not destByProduct[product] then destByProduct[product] = {} end
            table.insert(destByProduct[product], dest)
        end
    end

    -- Contagem de jobs pendentes por destino (para ponderação)
    local pendingByDest = {}
    if Config.JobGeneration.DemandWeighting then
        pendingByDest = GetDestPendingCounts()
    end

    -- Tentar até 20 combinações
    for _ = 1, 20 do
        local origin  = origins[math.random(#origins)]
        local product = PickProduct(origin)
        if product then
            local validDests = destByProduct[product.name]
            if validDests and #validDests > 0 then
                local dest
                if Config.JobGeneration.DemandWeighting then
                    -- Peso inverso: destinos com menos jobs pendentes têm mais chance
                    dest = WeightedRandom(validDests, function(d)
                        local pending = pendingByDest[d.id] or 0
                        return 1.0 / (1.0 + pending)  -- nunca zero
                    end)
                else
                    dest = validDests[math.random(#validDests)]
                end
                if dest then
                    local dist    = CalcDistance(origin.coords, dest.coords)
                    local payment = math.floor((product.basePrice * cargoQty) + dist * Config.JobGeneration.distanceMultiplier * dest.multiplier)
                    payment = math.min(payment, Config.General.payment.maxPayment)
                    return {
                        id            = GenerateJobId(),
                        origin_id     = origin.id,
                        dest_id       = dest.id,
                        cargo_item    = product.name,
                        trailer_model = product.trailer,
                        base_payment  = payment,
                        distance      = dist,
                        expires_at    = CalcExpiresAt(payment),
                        cargo_qty     = cargoQty,
                        weight        = product.weight or 80,
                    }
                end
            end
        end
    end
    return nil
end

-- Retorna tipo ADR do produto (cargo_item = product.name), ou nil se não exige ADR
local function GetProductAdr(productName)
    for _, industry in ipairs(Config.PrimaryIndustries) do
        for _, product in ipairs(industry.products or {}) do
            if product.name == productName and product.adr then
                return product.adr
            end
        end
    end
    return nil
end

-- Gera lote de jobs até MAX_JOBS ativos
function JobService.GenerateBatch()
    local current = DB_CountActiveJobs()
    local toGenerate = MAX_JOBS - current

    for i = 1, toGenerate do
        local job = GenerateOne()
        if job then
            DB_InsertJob(job)
            if Config.Debug then
                print(('[aurp_trucker] Job gerado: %s → %s (%s) $%d'):format(
                    job.origin_id, job.dest_id, job.cargo_item, job.base_payment))
            end
        end
    end
end

-- Retorna jobs disponíveis do DB (enriquecidos com nome de indústria)
function JobService.GetAvailable(citizenId)
    local rows = DB_GetAvailableJobs()
    local result = {}

    -- Indexar indústrias por id para lookup rápido
    local originIndex = {}
    for _, o in ipairs(Config.PrimaryIndustries) do
        originIndex[o.id] = o
    end
    local destIndex = {}
    for _, d in ipairs(Config.SecondaryIndustries) do
        destIndex[d.id] = d
    end

    -- ADR: certs válidas do jogador (mapa { [adr_type] = expires_at })
    local validCerts = citizenId and AdrService.GetValid(citizenId) or {}

    for _, row in ipairs(rows) do
        local origin = originIndex[row.origin_id]
        local dest   = destIndex[row.dest_id]
        if origin and dest then
            local adrRequired = GetProductAdr(row.cargo_item)
            table.insert(result, {
                id           = row.id,
                originName   = origin.name,
                destName     = dest.name,
                cargoItem    = row.cargo_item,
                trailerModel = row.trailer_model,
                basePayment  = row.base_payment,
                distance     = tonumber(row.distance) or 0,
                expiresAt    = row.expires_at_unix,
                adrRequired  = adrRequired,
                adrLocked    = adrRequired ~= nil and not validCerts[adrRequired],
                cargoQty     = row.cargo_qty or 1,
                weight       = row.weight or 80,
            })
        end
    end
    return result
end

-- Aceita job para um jogador
function JobService.Accept(jobId, citizenId, companyId)
    -- Gate ADR: verifica se o job exige certificação
    local jobRow = DB_GetJobWithConvoy(jobId)
    if jobRow and jobRow.cargo_item then
        local adrRequired = GetProductAdr(jobRow.cargo_item)
        if adrRequired and not AdrService.HasCert(citizenId, adrRequired) then
            return false
        end
    end
    DB_AcceptJob(jobId, citizenId, companyId)
    return true
end

-- Retorna job ativo do jogador
function JobService.GetActiveByPlayer(citizenId)
    local row = DB_GetActiveJobByPlayer(citizenId)
    if not row then return nil end

    -- Enriquecer com nomes
    local originIndex = {}
    for _, o in ipairs(Config.PrimaryIndustries) do originIndex[o.id] = o end
    local destIndex = {}
    for _, d in ipairs(Config.SecondaryIndustries) do destIndex[d.id] = d end

    local origin = originIndex[row.origin_id]
    local dest   = destIndex[row.dest_id]

    -- Buscar loadTime do produto na indústria de origem
    local loadTime = 6000
    if origin then
        for _, product in ipairs(origin.products or {}) do
            if product.name == row.cargo_item then
                loadTime = product.loadTime or loadTime
                break
            end
        end
    end

    return {
        jobId        = row.id,
        originName   = origin and origin.name or row.origin_id,
        originCoords = origin and origin.coords or nil,
        destName     = dest and dest.name or row.dest_id,
        destCoords   = dest and dest.coords or nil,
        unloadTime   = dest and dest.unloadTime or 6000,
        cargoItem    = row.cargo_item,
        trailerModel = row.trailer_model,
        payment      = row.base_payment,
        acceptedAt   = row.accepted_at_unix,
        cargoQty     = row.cargo_qty or 1,
        weight       = row.weight or 80,
        originId     = row.origin_id,
        loadTime     = loadTime,
    }
end

-- Retorna manifesto de transporte para o jogador
function JobService.GetManifest(citizenId)
    local job = JobService.GetActiveByPlayer(citizenId)
    if not job then return nil end

    local company = CompanyService.GetByMember(citizenId)

    return {
        cargo        = job.cargoItem,
        trailerModel = job.trailerModel,
        origin       = job.originName,
        destination  = job.destName,
        companyName  = company and company.name or 'Autônomo',
        issuedAt     = job.acceptedAt,
    }
end

-- Completa job, aplica bônus de skill e concede XP
-- payload = { deliveryTime, plate, cargoIntegrity }
-- cargoIntegrity: 0–100 (reportado pelo client; clamped server-side)
function JobService.Complete(src, payload)
    local Player = Framework.GetPlayer(src)
    if not Player then return false end

    local citizenId = Framework.GetCitizenId(Player)
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return false end

    -- Validação estrita de tempo server-side: nunca confiar no client
    if not activeJob.accepted_at_unix or activeJob.accepted_at_unix <= 0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Erro de integridade da missão (dados corrompidos ou inexistentes).', 'error')
        return false
    end
    local elapsed = math.max(0, os.time() - activeJob.accepted_at_unix)

    -- Validação anti-cheat (velocidade mínima, proximidade geográfica e routing bucket)
    local acOk, acReason = AntiCheatService.ValidateDelivery(src, citizenId, activeJob, elapsed)
    if not acOk then
        TriggerClientEvent('aurp_trucker:notify', src, acReason or 'Entrega inválida.', 'error')
        return false
    end

    -- Detectar se é job de convoy — delegar pagamento ao ConvoyService
    if activeJob.convoy_id and ConvoyService then
        DB_CompleteJob(activeJob.id)
        DB_AddPlayerStats(citizenId, 0, activeJob.distance)
        ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, 1.0)
        ConvoyService.MemberComplete(src, activeJob.convoy_id, citizenId, activeJob)
        return true, 0
    end

    -- Calcular multiplicador de tempo (usa elapsed server-side já computado acima)
    local bonus    = Config.JobGeneration.timeBonus
    local timeMult = bonus.slow.multiplier
    if elapsed <= bonus.fast.time then
        timeMult = bonus.fast.multiplier
    elseif elapsed <= bonus.normal.time then
        timeMult = bonus.normal.multiplier
    end

    -- Fase 3B: Delegar para IllegalService se job ilegal
    if activeJob.illegal_type and IllegalService then
        return IllegalService.OnComplete(src, activeJob, payload, timeMult)
    end

    -- audit C-01: integridade rastreada server-side via syncSimulation (não confia no client)
    -- Fallback 100 se player entregou antes do primeiro sync (raro, mas possível em jobs curtos)
    local serverIntegrity = TruckSimulationService.GetLastIntegrity(src)

    -- Aplicar bônus de skills contextual (v13)
    local skillBonus = ProgressionService.CalcBonus(citizenId, {
        distance       = activeJob.distance,
        basePayment    = activeJob.base_payment,
        cargoIntegrity = serverIntegrity,
    })
    timeMult = timeMult + skillBonus.speedBonus

    -- Aplicar bônus de empresa (nivel da empresa aumenta o multiplicador)
    local company     = CompanyService.GetByMember(citizenId)
    local companyMult = 1.0
    if company then
        companyMult = CompanyService.GetPerks(company.id).bonus
    end
    local rawIntegrity  = serverIntegrity
    local integrityMult = math.max(
        Config.TruckSimulation.Cargo.MinPaymentRate,
        rawIntegrity / 100
    )
    local payment = math.floor(activeJob.base_payment * skillBonus.paymentMult * timeMult * companyMult * integrityMult)

    -- Bônus de estacionamento manual do caminhoneiro (+45 XP, +5% pagamento)
    if payload and payload.parkedManually then
        payment = math.floor(payment * 1.05)
        ProgressionService.GrantXP(src, citizenId, 450, 1.0, 0)
        TriggerClientEvent('aurp_trucker:notify', src, 'Bônus de manobra: Estacionamento perfeito manual (+5% $ e +45 XP)!', 'success')
    end

    -- Pagar jogador
    Framework.AddMoney(Player, Config.General.payment.currency, payment, 'aurp-trucker-job')

    -- Desgaste de frota própria (se aplicável)
    if TruckFleetService and payload and payload.truckId then
        TruckFleetService.ApplyTripWear(citizenId, payload.truckId, activeJob.distance)
    end

    -- Atualizar DB de stats e conceder XP
    DB_CompleteJob(activeJob.id)
    if rawIntegrity < 30 then
        DB_RecordInfraction(citizenId, activeJob.id, 'cargo_damage',
            ('Carga entregue com %d%% de integridade'):format(rawIntegrity),
            'aurp_trucker:auto')
    end
    DB_AddPlayerStats(citizenId, payment, activeJob.distance)
    ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, timeMult, activeJob.distance)

    -- Evento externo (vp-sala e outros recursos)
    TriggerEvent('aurp_trucker:jobCompleted', citizenId,
        company and company.id or nil,
        { jobId = activeJob.id, cargo = activeJob.cargo_item },
        payment)

    -- XP de empresa
    if company then
        CompanyService.AddXP(company.id, Config.CompanyXpPerDelivery)
    end

    -- Integração Logística com vp_gasstations (Abastecimento físico de combustível nos postos)
    if GetResourceState('vp_gasstations') == 'started' then
        local isFuelCargo = (activeJob.trailer_model == 'tanker')
            or (activeJob.cargo_item and (
                activeJob.cargo_item:find('Combustível')
                or activeJob.cargo_item:find('Gasolina')
                or activeJob.cargo_item:find('Diesel')
                or activeJob.cargo_item:find('Petróleo')
            ))

        if isFuelCargo then
            local destCoords = nil
            for _, d in ipairs(Config.SecondaryIndustries or {}) do
                if d.id == activeJob.dest_id then
                    destCoords = d.coords
                    break
                end
            end

            if destCoords then
                local liters = (tonumber(activeJob.cargo_qty) and (activeJob.cargo_qty * 1000)) or 2500
                pcall(function()
                    exports['vp_gasstations']:AddFuelStock(destCoords, liters, ('Caminhoneiro (%s)'):format(citizenId))
                end)
            end
        end
    end

    -- GP-H05: repor slot imediatamente após conclusão para evitar lista vazia
    -- (cron de 30min não é suficiente em servidores com vários jogadores simultâneos)
    CreateThread(function()
        Wait(500)
        JobService.GenerateBatch()
    end)

    return true, payment
end

-- Abandona job ativo do jogador
function JobService.Abandon(citizenId)
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return end
    DB_AbandonJob(activeJob.id, citizenId)
    -- Fase 3B: limpar target de apreensão se job ilegal
    if activeJob.illegal_type and IllegalService then
        for plate, target in pairs(VP_Trucker.IllegalTargets) do
            if target.jobId == activeJob.id then
                IllegalService.ClearSeizureTarget(plate)
                break
            end
        end
    end
    -- GP-H05: repor slot abandonado imediatamente
    CreateThread(function()
        Wait(500)
        JobService.GenerateBatch()
    end)
end

-- Registra infração (chamado pelo vp-sala via export)
function JobService.RecordInfraction(citizenId, infractionType, reason, issuedBy)
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    local jobId = activeJob and activeJob.id or nil
    DB_RecordInfraction(citizenId, jobId, infractionType, reason, issuedBy)
    TriggerEvent('aurp_trucker:infractionRecorded', citizenId,
        { type = infractionType, reason = reason, issuedBy = issuedBy })
    return true
end

-- Expira jobs vencidos (cron)
function JobService.ExpireStale()
    DB_ExpireStaleJobs()
end

-- Gera um lote de jobs para um convoy (um job por membro, mesmo origin/dest, trailers distintos)
-- convoyId já foi inserido em trucker_convoy_jobs por ConvoyService.Start (FK obrigatória)
-- Retorna { [citizenid] = jobId } para ConvoyService popular o cache, ou nil se falhar
function JobService.GenerateConvoyBatch(convoyId, partyId, memberCids)
    local origins = Config.PrimaryIndustries
    local dests   = Config.SecondaryIndustries

    -- Mapa de produtos aceitos por destino
    local destByProduct = {}
    for _, dest in ipairs(dests) do
        for _, product in ipairs(dest.acceptedProducts or {}) do
            if not destByProduct[product] then destByProduct[product] = {} end
            table.insert(destByProduct[product], dest)
        end
    end

    local pendingByDest = {}
    if Config.JobGeneration.DemandWeighting then
        pendingByDest = GetDestPendingCounts()
    end

    -- Selecionar origin/dest compartilhado
    local sharedOrigin, sharedDest
    for _ = 1, 20 do
        local origin  = origins[math.random(#origins)]
        local product = PickProduct(origin)
        if not product then goto nextAttempt end

        local validDests = destByProduct[product.name]
        if not validDests or #validDests == 0 then goto nextAttempt end

        local dest
        if Config.JobGeneration.DemandWeighting then
            dest = WeightedRandom(validDests, function(d)
                local pending = pendingByDest[d.id] or 0
                return 1.0 / (1.0 + pending)
            end)
        else
            dest = validDests[math.random(#validDests)]
        end
        if not dest then goto nextAttempt end

        sharedOrigin = origin
        sharedDest   = dest
        break

        ::nextAttempt::
    end

    if not sharedOrigin or not sharedDest then
        if Config.Debug then print('[aurp_trucker] GenerateConvoyBatch: falha ao selecionar origin/dest') end
        return nil
    end

    local dist = CalcDistance(sharedOrigin.coords, sharedDest.coords)
    local memberJobs = {}

    for _, cid in ipairs(memberCids) do
        local product = PickProduct(sharedOrigin)
        if not product then
            if Config.Debug then print(('[aurp_trucker] GenerateConvoyBatch: sem produto para %s'):format(cid)) end
            goto nextMember
        end

        local payment = math.floor(product.basePrice + dist * Config.JobGeneration.distanceMultiplier * sharedDest.multiplier)
        payment = math.min(payment, Config.General.payment.maxPayment)

        local job = {
            id            = GenerateJobId(),
            origin_id     = sharedOrigin.id,
            dest_id       = sharedDest.id,
            cargo_item    = product.name,
            trailer_model = product.trailer,
            base_payment  = payment,
            distance      = dist,
            expires_at    = CalcExpiresAt(payment),
        }

        -- INSERT sequencial: trucker_jobs primeiro, depois trucker_convoy_members
        DB_InsertJob(job, convoyId)
        DB_CreateConvoyMember(convoyId, cid, job.id)

        memberJobs[cid] = job.id

        ::nextMember::
    end

    return memberJobs
end

-- Carrega jobs ativos do DB no restart (chamado por main.lua)
function JobService.LoadFromDB()
    -- Jobs 'active' orphaned após restart: liberar de volta para 'available'
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'available', assigned_citizenid = NULL, company_id = NULL, accepted_at = NULL WHERE status = 'active' AND expires_at > NOW()"
    )
    -- Jobs ativos com expires_at passado → expirar
    JobService.ExpireStale()
    if Config.Debug then
        print('[aurp_trucker] Jobs loaded from DB')
    end
end

-- Conclui entrega de carga roubada — usado quando isStolen = true
-- cargoEntry = { jobId, basePayment, ... }  (da CargoTrackingService.ClaimDelivery)
-- payload    = { deliveryTime, plate }
-- Retorna payment (number) on success, nil on failure
function JobService.CompleteTheft(src, cargoEntry, payload)
    local Player = Framework.GetPlayer(src)
    if not Player then return nil end

    local citizenId = Framework.GetCitizenId(Player)

    -- Calcular multiplicador de tempo (mesmo critério de JobService.Complete)
    -- v15: elapsed server-side (padrão #8) — usa theftStartedAt como referência de início
    local elapsed = (cargoEntry.theftStartedAt and cargoEntry.theftStartedAt > 0)
                    and math.max(0, os.time() - cargoEntry.theftStartedAt)
                    or  (tonumber(payload.deliveryTime) or 9999)
    local bonus    = Config.JobGeneration.timeBonus
    local timeMult = bonus.slow.multiplier
    if elapsed <= bonus.fast.time then
        timeMult = bonus.fast.multiplier
    elseif elapsed <= bonus.normal.time then
        timeMult = bonus.normal.multiplier
    end

    -- Aplicar bônus de roubo sobre o pagamento base
    local payment = math.floor(cargoEntry.basePayment * timeMult * (1.0 + Config.CargoTheft.TheftBonus))

    Framework.AddMoney(Player, 'bank', payment, 'cargo_theft_delivery')
    DB_AddPlayerStats(citizenId, payment, 0)  -- 0 distance (roubo não rastreia distância)

    -- XP pelo job roubado (menor que entrega normal — sem multiplicadores extras)
    ProgressionService.GrantXP(src, citizenId, 1, 0)  -- 1 job concluído, 0 distance (roubado)

    if Config.Debug then
        print(('[cargo-theft] Ladrão %s entregou carga roubada — $%d'):format(citizenId, payment))
    end

    return payment
end
