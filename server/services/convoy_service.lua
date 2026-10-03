-- aurp_trucker — server/services/convoy_service.lua
-- Gerencia execução do convoy (lifecycle do job)
-- Carrega APÓS job_service.lua no fxmanifest (usa JobService.GenerateConvoyBatch)

ConvoyService = {}

local function NewUUID()
    local t = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' }
    local s = ''
    for i = 1, 32 do
        s = s .. t[math.random(16)]
        if i == 8 or i == 12 or i == 16 or i == 20 then s = s .. '-' end
    end
    return s
end

-- Broadcast periódico de posições para blips dos membros
function ConvoyService.StartPositionBroadcast(convoyId)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    local handle = SetInterval(Config.Party.positionBroadcastInterval, function()
      local okTick, errTick = pcall(function()
        local cv = VP_Trucker.Convoys[convoyId]
        if not cv then return end

        local party = VP_Trucker.Parties[cv.partyId]
        if not party then return end

        local positions = {}
        for cid, info in pairs(party.members) do
            if info.src then
                local coords = TruckSimulationService.GetCoords(info.src)
                if coords then
                    positions[cid] = {
                        x       = coords.x,
                        y       = coords.y,
                        z       = coords.z,
                        name    = GetCharName(info.src),
                        isTruck = TruckSimulationService.IsInTruck(info.src),
                    }
                end
            end
        end

        for cid, info in pairs(party.members) do
            if info.src and TruckSimulationService.IsInTruck(info.src) then
                TriggerClientEvent('aurp_trucker:client:positionsUpdate', info.src, positions)
            end
        end
      end)
      if not okTick then print('[aurp_trucker] Convoy broadcast erro: ' .. tostring(errTick)) end
    end)

    VP_Trucker.Convoys[convoyId].broadcastTimer = handle
end

function ConvoyService.StopPositionBroadcast(convoyId)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy or not convoy.broadcastTimer then return end
    ClearInterval(convoy.broadcastTimer)
    convoy.broadcastTimer = nil
end

-- Inicia convoy para um party
function ConvoyService.Start(partyId)
    local party = VP_Trucker.Parties[partyId]
    if not party then return false, 'Party não encontrado' end

    local memberCids = {}
    for cid, info in pairs(party.members) do
        if info.src then table.insert(memberCids, cid) end
    end

    if #memberCids < 2 then
        return false, 'Convoy precisa de pelo menos 2 membros online'
    end

    local convoyId   = NewUUID()
    local totalCount = #memberCids

    -- 1. Inserir trucker_convoy_jobs PRIMEIRO (FK obrigatória para trucker_convoy_members)
    DB_CreateConvoy(convoyId, partyId, Config.Party.bonusMultiplier, totalCount)

    -- 2. Gerar jobs e inserir convoy_members
    local memberJobs = JobService.GenerateConvoyBatch(convoyId, partyId, memberCids)
    if not memberJobs then
        DB_SetConvoyStatus(convoyId, 'cancelled')
        return false, 'Falha ao gerar jobs para o convoy'
    end

    -- 3. Popular cache
    local members = {}
    for cid, info in pairs(party.members) do
        if memberJobs[cid] then
            members[cid] = { jobId = memberJobs[cid], src = info.src, status = 'active' }
        end
    end

    VP_Trucker.Convoys[convoyId] = {
        partyId        = partyId,
        memberJobs     = memberJobs,
        members        = members,
        graceTimers    = {},
        broadcastTimer = nil,
        activeCount    = totalCount,
        totalCount     = totalCount,
        status         = 'active',
        bonus_mult     = Config.Party.bonusMultiplier,
    }

    party.convoyActive = true

    -- 4. Iniciar broadcast de posições
    ConvoyService.StartPositionBroadcast(convoyId)

    -- 5. Notificar membros
    for _, cid in ipairs(memberCids) do
        local info = party.members[cid]
        if info and info.src then
            local jobData = JobService.GetActiveByPlayer(cid)
            TriggerClientEvent('aurp_trucker:client:convoyStarted', info.src, {
                convoyId = convoyId,
                jobId    = memberJobs[cid],
                jobData  = jobData,
                isLeader = (cid == party.leader),
            })
        end
    end

    if Config.Debug then
        print(('[aurp_trucker] Convoy %s iniciado: %d membros'):format(convoyId, totalCount))
    end

    return true, convoyId
end

-- Chamado por JobService.Complete quando convoy_id detectado
function ConvoyService.MemberComplete(src, convoyId, citizenid, activeJob)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    DB_SetConvoyMemberStatus(convoyId, citizenid, 'completed')
    -- C-01: após o await, re-verificar se o convoy ainda existe
    -- (_PayAll pode ter sido chamado por outro membro enquanto aguardávamos o DB)
    if not VP_Trucker.Convoys[convoyId] then return end
    if convoy.members and convoy.members[citizenid] then
        convoy.members[citizenid].status = 'completed'
    end
    convoy.activeCount = math.max(0, convoy.activeCount - 1)

    if Config.Debug then
        print(('[aurp_trucker] Convoy %s: %s completou. Restam: %d'):format(convoyId, citizenid, convoy.activeCount))
    end

    if convoy.activeCount == 0 then
        ConvoyService._PayAll(convoyId)
    end
end

-- Membro abandona o convoy
function ConvoyService.MemberAbandon(convoyId, citizenid)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    DB_SetConvoyMemberStatus(convoyId, citizenid, 'abandoned')
    -- C-01: após o await, re-verificar se o convoy ainda existe
    if not VP_Trucker.Convoys[convoyId] then return end
    if convoy.members and convoy.members[citizenid] then
        convoy.members[citizenid].status = 'abandoned'
    end
    convoy.activeCount = math.max(0, convoy.activeCount - 1)

    -- Recalcular bônus proporcional
    local rows = DB_GetConvoyMembers(convoyId) or {}
    local completedCount = 0
    for _, row in ipairs(rows) do
        if row.status == 'completed' then completedCount = completedCount + 1 end
    end
    local completedFraction = (convoy.totalCount and convoy.totalCount > 0) and (completedCount / convoy.totalCount) or 0
    local newMult = 1.0 + (0.5 * completedFraction)
    DB_SetConvoyBonusMult(convoyId, newMult)
    convoy.bonus_mult = newMult

    -- Notificar membros restantes sobre o abandono e o novo bônus
    local abandonSrc  = Framework.FindPlayerByCitizenId(citizenid)
    local abandonName = (abandonSrc and GetCharName(abandonSrc)) or 'Um membro'
    local party = VP_Trucker.Parties[convoy.partyId]
    if party then
        for cid, info in pairs(party.members) do
            if info.src and cid ~= citizenid then
                TriggerClientEvent('aurp_trucker:notify', info.src,
                    ('%s abandonou o convoy. Novo bônus: ×%.1f'):format(abandonName, newMult), 'warning')
            end
        end
    end

    if convoy.activeCount == 0 then
        ConvoyService._PayAll(convoyId)
    end
end

-- Relay de mensagem CB radio com range check
function ConvoyService.Broadcast(src, message)
    local partyId = PartyService.GetPartyBySrc(src)
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party then return end

    local senderCoords = TruckSimulationService.GetCoords(src)
    local senderName   = GetCharName(src)

    for cid, info in pairs(party.members) do
        if info.src then
            local inRange = true

            if senderCoords then
                local targetCoords = TruckSimulationService.GetCoords(info.src)
                if targetCoords then
                    local dx = senderCoords.x - targetCoords.x
                    local dy = senderCoords.y - targetCoords.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    inRange = dist <= Config.Party.cbRadioRange
                end
            end

            if inRange then
                TriggerClientEvent('aurp_trucker:client:cbMessage', info.src, {
                    sender    = senderName,
                    message   = message,
                    timestamp = os.time(),
                })
            end
        end
    end
end

-- Paga todos os membros quando convoy concluído
function ConvoyService._PayAll(convoyId)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end
    -- Nil cache immediately to prevent double-payout from concurrent completion/abandon
    VP_Trucker.Convoys[convoyId] = nil

    local rows = DB_GetConvoyMembers(convoyId) or {}
    local completedCount = 0
    for _, row in ipairs(rows) do
        if row.status == 'completed' then completedCount = completedCount + 1 end
    end

    local bonusMult = 1.0
    if convoy.totalCount > 0 then
        bonusMult = 1.0 + (0.5 * (completedCount / convoy.totalCount))
    end

    local party = VP_Trucker.Parties[convoy.partyId]

    for _, row in ipairs(rows) do
        if row.status == 'completed' then
            local jobRow = DB_GetJobWithConvoy(row.job_id)
            if jobRow then
                local payment = math.floor((jobRow.base_payment or 0) * bonusMult)
                -- Idempotência: reivindica o pagamento ANTES de pagar (INSERT IGNORE + UNIQUE convoy/membro).
                -- Só paga quem conseguiu inserir o registro.
                if DB_ClaimConvoyPayment(convoyId, row.citizenid, payment, bonusMult, completedCount, convoy.totalCount) then
                    local memberSrc = Framework.FindPlayerByCitizenId(row.citizenid)
                    local p = memberSrc and Framework.GetPlayer(memberSrc)
                    local paid = false
                    if p then
                        paid = Framework.AddMoney(p, Config.General.payment.currency, payment, 'aurp-trucker-convoy')
                    end
                    if paid then
                        DB_AddPlayerStats(row.citizenid, payment, 0)
                        TriggerClientEvent('aurp_trucker:client:jobCompleted', memberSrc, payment)
                        TriggerClientEvent('aurp_trucker:notify', memberSrc,
                            ('Convoy concluído! Bônus ×%.1f — $%d recebidos'):format(bonusMult, payment), 'success')
                        if ContractService and ContractService.PayPending then
                            pcall(ContractService.PayPending, memberSrc, row.citizenid)
                        end
                    else
                        -- Offline (ou crédito falhou): NÃO mexe direto nas tabelas do framework.
                        -- Registra pagamento pendente (trucker_pending_payouts) + log; pago no próximo login/ação.
                        DB_AddPlayerStats(row.citizenid, payment, 0)
                        print(('[aurp_trucker] Convoy %s: pagamento PENDENTE $%d para %s (offline/falha)'):format(
                            convoyId, payment, tostring(row.citizenid)))
                        local okQ, errQ = pcall(MySQL.insert.await,
                            'INSERT INTO trucker_pending_payouts (citizenid, amount, reason) VALUES (?, ?, ?)',
                            { row.citizenid, payment, 'convoy:' .. tostring(convoyId) })
                        if not okQ then
                            print(('[aurp_trucker] Convoy %s: ERRO ao registrar pendência: %s'):format(convoyId, tostring(errQ)))
                        end
                    end
                elseif Config.Debug then
                    print(('[aurp_trucker] Convoy %s: %s já foi pago, ignorando duplicidade'):format(convoyId, row.citizenid))
                end
            end
        end
    end

    DB_SetConvoyStatus(convoyId, 'completed')

    -- StopPositionBroadcast normally reads from VP_Trucker.Convoys, but we already nilled it;
    -- clear timer directly from the local reference
    if convoy.broadcastTimer then
        ClearInterval(convoy.broadcastTimer)
        convoy.broadcastTimer = nil
    end

    if party then
        for cid, info in pairs(party.members) do
            if info.src then
                TriggerClientEvent('aurp_trucker:client:convoyEnded', info.src)
            end
        end
    end
end

-- Cancela convoy
function ConvoyService.Cancel(convoyId)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    ConvoyService.StopPositionBroadcast(convoyId)
    DB_SetConvoyStatus(convoyId, 'cancelled')

    -- Libera os jobs ativos dos membros (e marca membros pendentes/ativos como abandonados)
    local okRel, errRel = pcall(function()
        local members = DB_GetConvoyMembers(convoyId) or {}
        for _, m in ipairs(members) do
            if m.status == 'pending' or m.status == 'active' then
                DB_SetConvoyMemberStatus(convoyId, m.citizenid, 'abandoned')
            end
        end
        DB_ReleaseConvoyJobs(convoyId)
    end)
    if not okRel then
        print(('[aurp_trucker] Convoy %s: erro ao liberar jobs no cancelamento: %s'):format(convoyId, tostring(errRel)))
    end

    local party = VP_Trucker.Parties[convoy.partyId]
    if party then
        for cid, info in pairs(party.members) do
            if info.src then
                TriggerClientEvent('aurp_trucker:client:convoyEnded', info.src)
            end
        end
    end

    VP_Trucker.Convoys[convoyId] = nil
end

-- Cancela convoys em andamento após restart do servidor.
-- Não é seguro retomar convoy após restart: membros perdem o job client-side.
-- Todos os membros 'pending'/'active' são abandonados; convoy é cancelado.
function ConvoyService.LoadFromDB()
    local active = DB_GetActiveConvoys() or {}
    for _, convoy in ipairs(active) do
        local members = DB_GetConvoyMembers(convoy.id) or {}
        for _, m in ipairs(members) do
            if m.status == 'pending' or m.status == 'active' then
                DB_SetConvoyMemberStatus(convoy.id, m.citizenid, 'abandoned')
            end
        end
        DB_SetConvoyStatus(convoy.id, 'cancelled')
    end

    if Config.Debug then
        print(('[aurp_trucker] ConvoyService.LoadFromDB: %d convoys cancelados após restart'):format(#active))
    end
end
