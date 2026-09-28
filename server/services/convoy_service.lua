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
    local completedFraction = completedCount / convoy.totalCount
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
            -- Idempotência: verificar se este membro já recebeu o pagamento deste convoy
            local alreadyPaid = MySQL.scalar.await(
                "SELECT COUNT(*) FROM trucker_convoy_payments WHERE convoy_id = ? AND citizenid = ?",
                { convoyId, row.citizenid }
            )
            if (alreadyPaid or 0) > 0 then
                if Config.Debug then
                    print(('[aurp_trucker] Convoy %s: %s já foi pago, ignorando duplicidade'):format(convoyId, row.citizenid))
                end
            else
                local jobRow = DB_GetJobWithConvoy(row.job_id)
                if jobRow then
                    local payment = math.floor((jobRow.base_payment or 0) * bonusMult)
                    local memberSrc = Framework.FindPlayerByCitizenId(row.citizenid)
                    if memberSrc then
                        local p = Framework.GetPlayer(memberSrc)
                        if p then
                            Framework.AddMoney(p, Config.General.payment.currency, payment, 'aurp-trucker-convoy')
                            DB_AddPlayerStats(row.citizenid, payment, 0)
                            DB_RecordConvoyPayment(convoyId, row.citizenid, payment, bonusMult, completedCount, convoy.totalCount)
                            TriggerClientEvent('aurp_trucker:client:jobCompleted', memberSrc, payment)
                            TriggerClientEvent('aurp_trucker:notify', memberSrc,
                                ('Convoy concluído! Bônus ×%.1f — $%d recebidos'):format(bonusMult, payment), 'success')
                        end
                    else
                        -- Offline fallback idempotente: jogador completou mas desconectou antes do último membro finalizar
                        DB_AddPlayerStats(row.citizenid, payment, 0)
                        DB_RecordConvoyPayment(convoyId, row.citizenid, payment, bonusMult, completedCount, convoy.totalCount)
                        if Config.Framework == 'qbx' or Config.Framework == 'qbcore' then
                            pcall(function()
                                MySQL.update.await(
                                    'UPDATE players SET money = JSON_SET(money, "$.bank", JSON_EXTRACT(money, "$.bank") + ?) WHERE citizenid = ?',
                                    { payment, row.citizenid }
                                )
                            end)
                        elseif Config.Framework == 'esx' then
                            pcall(function()
                                MySQL.update.await(
                                    'UPDATE users SET bank = bank + ? WHERE identifier = ?',
                                    { payment, row.citizenid }
                                )
                            end)
                        end
                        if Config.Debug then
                            print(('[aurp_trucker] Convoy %s: Pagamento offline $%d creditado para %s'):format(
                                convoyId, payment, row.citizenid))
                        end
                    end
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
