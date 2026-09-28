-- aurp_trucker — server/services/illegal_service.lua
-- Fase 3B: Geração, alerta, registro e apreensão de jobs ilegais

IllegalService = {}

-- Lookup pré-computado: _compatibleByType[illegalType] = lista de destinos compatíveis
-- Evita O(n×m) loop em Generate (chamado a cada acceptIllegalJob)
local _compatibleByType = {}
for _, d in ipairs((Config.IllegalJobs and Config.IllegalJobs.deliveries) or {}) do
    for _, a in ipairs(d.accepts or {}) do
        _compatibleByType[a] = _compatibleByType[a] or {}
        table.insert(_compatibleByType[a], d)
    end
end

-- ============================================================
-- GERAR JOB ILEGAL
-- ============================================================

-- Gera e insere um job ilegal para um jogador.
-- Retorna { jobId, destArea, payment } ou nil se falhar.
function IllegalService.Generate(contactId, illegalType, src)
    if not Config.IllegalJobs then return nil end

    -- Validar tipo de cargo
    local mult = Config.IllegalJobs.paymentMultipliers[illegalType]
    if not mult then return nil end

    -- Selecionar destino compatível aleatório (lookup O(1) via tabela pré-computada)
    local compatible = _compatibleByType[illegalType] or {}
    if #compatible == 0 then return nil end
    local dest = compatible[math.random(#compatible)]

    -- Selecionar origem de Config.PrimaryIndustries (primeiro disponível para referência de distância)
    local origin = Config.PrimaryIndustries[math.random(#Config.PrimaryIndustries)]

    -- Calcular distância e pagamento
    local dx   = origin.coords.x - dest.coords.x
    local dy   = origin.coords.y - dest.coords.y
    local dist = math.sqrt(dx*dx + dy*dy) / 1000.0
    local payment = math.floor(dist * Config.JobGeneration.distanceMultiplier * mult)
    payment = math.min(payment, Config.General.payment.maxPayment)

    -- Montar job e inserir no DB diretamente como 'active' (evita janela de corrida)
    local Player = Framework.GetPlayer(src)
    if not Player then return nil end
    local cid = Framework.GetCitizenId(Player)

    local jobId = ('ilg_%d_%d'):format(os.time(), math.random(10000, 99999))
    local expiresAt = os.time() + 3600  -- 1 hora

    DB_InsertIllegalJob({
        id            = jobId,
        origin_id     = origin.id,
        dest_id       = dest.id,
        cargo_item    = illegalType,
        trailer_model = 'docktrailer',
        base_payment  = payment,
        distance      = dist,
        expires_at    = expiresAt,
        illegal_type  = illegalType,
        citizenid     = cid,
    })

    return {
        jobId    = jobId,
        destArea = dest.area,
        payment  = payment,
    }
end

-- ============================================================
-- BROADCAST DE ALERTA PARA COPS / SALA
-- ============================================================

-- Emite alerta de rádio para LSPD (e opcionalmente SALA) quando job ilegal é aceito.
function IllegalService.BroadcastAlert(src, illegalType, originArea)
    local label = (Config.IllegalJobs.alertLabels and Config.IllegalJobs.alertLabels[illegalType])
               or illegalType

    -- Determinar prefixo e canais
    local isHighPriority = false
    for _, t in ipairs(Config.IllegalJobs.highPriorityTypes or {}) do
        if t == illegalType then isHighPriority = true; break end
    end

    local prefix = isHighPriority and '[LSPD ⚠]' or '[LSPD]'
    local msg    = ('%s Movimentação suspeita de %s detectada na região de %s.'):format(prefix, label, originArea)

    -- Broadcast para LSPD (job = 'police')
    local players = Framework.GetAllPlayers()
    for _, player in pairs(players) do
        if Framework.GetJob(player).name == 'police' then
            TriggerClientEvent('aurp_trucker:client:policeAlert', Framework.GetSource(player), { message = msg })
        end
    end

    -- Alerta adicional para SALA se aplicável
    local isSalaAlert = false
    for _, t in ipairs(Config.IllegalJobs.salaAlertTypes or {}) do
        if t == illegalType then isSalaAlert = true; break end
    end
    if isSalaAlert then
        local salaMsg = ('[SALA] Alerta de %s na região de %s.'):format(label, originArea)
        for _, player in pairs(players) do
            if Framework.GetJob(player).name == 'sasp' then
                TriggerClientEvent('aurp_trucker:client:policeAlert', Framework.GetSource(player), { message = salaMsg })
            end
        end
    end
end

-- ============================================================
-- REGISTRAR PLACA PARA APREENSÃO
-- ============================================================

-- Chamado quando o motorista entra no caminhão com job ilegal ativo.
-- Armazena a placa em VP_Trucker.IllegalTargets e faz broadcast para todos os clients
-- registrarem o ox_target no caminhão (include cops fora de range que já estavam no servidor).
function IllegalService.RegisterSeizureTarget(src, jobId, plate, illegalType)
    if VP_Trucker.IllegalTargets[plate] then return end  -- já registrado

    local Player = Framework.GetPlayer(src)
    if not Player then return end

    VP_Trucker.IllegalTargets[plate] = {
        src         = src,
        jobId       = jobId,
        citizenid   = Framework.GetCitizenId(Player),
        illegalType = illegalType,
    }

    -- Broadcast para TODOS os clients (source = -1) para registrar ox_target
    TriggerClientEvent('aurp_trucker:client:illegalJobStarted', -1, {
        plate     = plate,
        driverSrc = src,
        illegalType = illegalType,
    })

    if Config.Debug then
        print(('[aurp_trucker] IllegalService: placa registrada para apreensão: %s (%s)'):format(plate, illegalType))
    end
end

-- ============================================================
-- REMOVER REGISTRO DE APREENSÃO
-- ============================================================

-- Limpa o registro de apreensão e notifica todos os clients para removerem o ox_target.
-- IMPORTANTE: lê `target` ANTES de nil-ar VP_Trucker.IllegalTargets[plate]
function IllegalService.ClearSeizureTarget(plate)
    local target = VP_Trucker.IllegalTargets[plate]  -- lê ANTES do nil
    VP_Trucker.IllegalTargets[plate] = nil

    -- Broadcast para todos os clients removerem o ox_target
    TriggerClientEvent('aurp_trucker:client:illegalJobEnded', -1, {
        plate     = plate,
        driverSrc = target and target.src or nil,
    })
end

-- ============================================================
-- APREENSÃO DE CARGA (ação do policial)
-- ============================================================

-- Cop aciona "Lacrar Carga" via ox_target.
-- Cancela o job, multa o motorista, registra infração.
function IllegalService.Seize(copSrc, plate)
    local target = VP_Trucker.IllegalTargets[plate]
    if not target then
        TriggerClientEvent('ox_lib:notify', copSrc, {
            title = 'Apreensão', description = 'Carga não encontrada.', type = 'error'
        })
        return
    end

    local driverSrc    = target.src
    local jobId        = target.jobId
    local citizenid    = target.citizenid
    local illegalType  = target.illegalType

    -- Cancelar job: expirar (não retornar para 'available')
    DB_ExpireJob(jobId)

    -- Multar motorista
    local fine = Config.IllegalJobs.seizureFines[illegalType] or 5000
    local DriverPlayer = Framework.GetPlayer(driverSrc)
    if DriverPlayer then
        -- Tenta remover cash, depois bank; se insuficiente, multa parcial do disponível
        local cashBalance = Framework.GetMoney(DriverPlayer, 'cash')
        local bankBalance = Framework.GetMoney(DriverPlayer, 'bank')
        local totalAvail  = cashBalance + bankBalance
        local actualFine  = math.min(fine, totalAvail)

        if actualFine > 0 then
            local fromCash = math.min(cashBalance, actualFine)
            if fromCash > 0 then
                Framework.RemoveMoney(DriverPlayer, 'cash', fromCash, 'aurp-trucker-seizure')
            end
            local fromBank = actualFine - fromCash
            if fromBank > 0 then
                Framework.RemoveMoney(DriverPlayer, 'bank', fromBank, 'aurp-trucker-seizure')
            end
        end

        -- Atualizar valor real da multa para notificação
        fine = actualFine

        -- Notificar motorista
        TriggerClientEvent('aurp_trucker:client:cargoSeized', driverSrc, {
            fine        = fine,
            illegalType = illegalType,
        })
    end

    -- Registrar infração
    DB_RecordInfraction(citizenid, jobId, 'illegal_seizure',
        ('Carga de %s apreendida pela polícia'):format(illegalType),
        'aurp_trucker:cop')

    -- Limpar target (broadcast illegalJobEnded para todos)
    IllegalService.ClearSeizureTarget(plate)

    -- Notificar cop
    TriggerClientEvent('aurp_trucker:client:seizureSuccess', copSrc, {
        plate       = plate,
        illegalType = illegalType,
        fine        = fine,
    })

    if Config.Debug then
        print(('[aurp_trucker] IllegalService.Seize: %s apreendido por cop %d, multa $%d'):format(plate, copSrc, fine))
    end
end

-- ============================================================
-- HOOK: CONCLUSÃO DE JOB ILEGAL
-- ============================================================

-- Chamado por JobService.Complete quando activeJob.illegal_type ~= nil.
-- Paga em cash, concede XP pessoal (sem XP de empresa).
-- payload.plate pode ser nil se o jogador completou a pé (nil-guard obrigatório).
function IllegalService.OnComplete(src, activeJob, payload, timeMult)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 0 end

    local citizenid = Framework.GetCitizenId(Player)
    local mult       = Config.IllegalJobs.paymentMultipliers[activeJob.illegal_type] or 1.0
    local skillBonus = ProgressionService.CalcBonus(citizenid, {
        distance       = activeJob.distance,
        basePayment    = activeJob.base_payment,
        cargoIntegrity = 0,
    })
    timeMult = timeMult + skillBonus.speedBonus
    local payment = math.floor(activeJob.base_payment * mult * timeMult * skillBonus.paymentMult)

    -- Decreto governamental: modificador de pagamento de frete
    local freightMod = 1.0
    pcall(function() freightMod = exports['AUST_governo']:GetDecreeModifier('freight_pay') end)
    if freightMod ~= 1.0 then payment = math.floor(payment * freightMod) end

    -- Pagar em cash (jobs ilegais não usam bank nem moeda de empresa)
    Framework.AddMoney(Player, 'cash', payment, 'aurp-trucker-illegal')

    -- Limpar target de apreensão (se placa conhecida)
    if payload.plate then
        IllegalService.ClearSeizureTarget(payload.plate)
    end

    -- XP pessoal (sem bônus de empresa, sem XP de empresa)
    ProgressionService.GrantXP(src, citizenid, activeJob.base_payment, timeMult)

    DB_CompleteJob(activeJob.id)
    DB_AddPlayerStats(citizenid, payment, activeJob.distance)

    return true, payment
end
