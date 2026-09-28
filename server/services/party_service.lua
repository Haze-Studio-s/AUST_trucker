-- aurp_trucker — server/services/party_service.lua
-- Gerencia parties (persistentes entre jobs)

PartyService = {}

-- Helper: gera UUID v4 simples
local function NewUUID()
    local t = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' }
    local s = ''
    for i = 1, 32 do
        s = s .. t[math.random(16)]
        if i == 8 or i == 12 or i == 16 or i == 20 then s = s .. '-' end
    end
    return s
end

-- Helper: broadcast partyUpdate para todos os membros online
local function BroadcastPartyUpdate(partyId)
    local party = VP_Trucker.Parties[partyId]
    if not party then return end

    local membersPayload = {}
    for cid, info in pairs(party.members) do
        table.insert(membersPayload, {
            citizenid = cid,
            name      = info.src and GetCharName(info.src) or cid,
            isLeader  = (cid == party.leader),
            online    = info.src ~= nil,
        })
    end

    for cid, info in pairs(party.members) do
        if info.src then
            TriggerClientEvent('aurp_trucker:client:partyUpdate', info.src, {
                party = {
                    partyId      = partyId,
                    isLeader     = (cid == party.leader),
                    members      = membersPayload,
                    convoyActive = party.convoyActive or false,
                    maxSize      = party.maxSize,
                }
            })
        end
    end
end

-- Cria uma nova party para o jogador
function PartyService.Create(src)
    local Player = Framework.GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    if VP_Trucker.PlayerParties[cid] then
        return nil, 'Você já está em um party'
    end

    local partyId = NewUUID()
    DB_CreateParty(partyId, cid, Config.Party.maxSize)

    VP_Trucker.Parties[partyId] = {
        leader      = cid,
        members     = { [cid] = { src = src } },
        graceTimers = {},
        maxSize     = Config.Party.maxSize,
        status      = 'forming',
    }
    VP_Trucker.PlayerParties[cid] = partyId

    BroadcastPartyUpdate(partyId)
    return partyId
end

-- Convida jogador pelo server id
function PartyService.Invite(src, targetSrc)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return false, 'Você não está em um party' end

    local party = VP_Trucker.Parties[partyId]
    if party.leader ~= cid then return false, 'Apenas o líder pode convidar' end

    local memberCount = 0
    for _ in pairs(party.members) do memberCount = memberCount + 1 end
    if memberCount >= party.maxSize then return false, 'Party cheio' end

    local targetPlayer = Framework.GetPlayer(targetSrc)
    if not targetPlayer then return false, 'Jogador não encontrado' end
    local targetCid = Framework.GetCitizenId(targetPlayer)

    if VP_Trucker.PlayerParties[targetCid] then return false, 'Jogador já está em um party' end

    -- Limpeza de convites expirados (evita memory leak) e registro com TTL de 60s
    if not VP_Trucker.PartyInvites then VP_Trucker.PartyInvites = {} end
    local now = os.time()
    for cidKey, inv in pairs(VP_Trucker.PartyInvites) do
        if now > (inv.expiresAt or 0) then
            VP_Trucker.PartyInvites[cidKey] = nil
        end
    end

    VP_Trucker.PartyInvites[targetCid] = {
        partyId   = partyId,
        expiresAt = now + 60,
    }

    TriggerClientEvent('aurp_trucker:client:partyInvite', targetSrc, {
        partyId    = partyId,
        leaderName = GetCharName(src),
    })
    return true
end

-- Aceita convite — adiciona membro ao party
function PartyService.Accept(src, partyId)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    if VP_Trucker.PlayerParties[cid] then return false, 'Você já está em um party' end

    -- Validar convite pendente no servidor (fail-closed)
    local invite = VP_Trucker.PartyInvites and VP_Trucker.PartyInvites[cid]
    if not invite or invite.partyId ~= partyId or os.time() > invite.expiresAt then
        return false, 'Você não possui convite válido para este grupo'
    end
    -- Consumir convite imediatamente
    VP_Trucker.PartyInvites[cid] = nil

    local party = VP_Trucker.Parties[partyId]
    if not party then return false, 'Party não encontrado' end
    if party.status == 'disbanded' then return false, 'Party foi dissolvido' end

    local memberCount = 0
    for _ in pairs(party.members) do memberCount = memberCount + 1 end
    if memberCount >= party.maxSize then return false, 'Party cheio' end

    party.members[cid] = { src = src }
    VP_Trucker.PlayerParties[cid] = partyId

    BroadcastPartyUpdate(partyId)
    return true
end

-- Remove membro do party (pelo src ativo)
function PartyService.Leave(src)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local cid = Framework.GetCitizenId(Player)
    PartyService.LeaveByIdentifier(VP_Trucker.PlayerParties[cid], cid)
end

-- Remove membro pelo citizenid (funciona mesmo com src stale)
function PartyService.LeaveByIdentifier(partyId, citizenid)
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party then return end

    -- Se convoy ativo, marcar como abandoned
    if ConvoyService then
        for convoyId, convoy in pairs(VP_Trucker.Convoys) do
            if convoy.partyId == partyId and convoy.memberJobs[citizenid] then
                ConvoyService.MemberAbandon(convoyId, citizenid)
            end
        end
    end

    party.members[citizenid] = nil
    VP_Trucker.PlayerParties[citizenid] = nil

    -- Limpar grace timer se houver
    if party.graceTimers[citizenid] then
        ClearTimeout(party.graceTimers[citizenid])
        party.graceTimers[citizenid] = nil
    end

    -- Contar membros restantes
    local remaining = {}
    for cid, info in pairs(party.members) do
        table.insert(remaining, { cid = cid, info = info })
    end

    if #remaining == 0 then
        DB_SetPartyStatus(partyId, 'disbanded')
        VP_Trucker.Parties[partyId] = nil
        return
    end

    -- Se era o líder, transferir para próximo membro online
    if party.leader == citizenid then
        local newLeader = nil
        for _, m in ipairs(remaining) do
            if m.info.src then newLeader = m.cid; break end
        end
        party.leader = newLeader or remaining[1].cid
    end

    BroadcastPartyUpdate(partyId)
end

-- Dissolve o party (apenas líder)
function PartyService.Disband(src)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return false, 'Você não está em um party' end

    local party = VP_Trucker.Parties[partyId]
    if party.leader ~= cid then return false, 'Apenas o líder pode dissolver' end

    -- Cancelar convoy ativo se houver
    if ConvoyService then
        for convoyId, convoy in pairs(VP_Trucker.Convoys) do
            if convoy.partyId == partyId then
                ConvoyService.Cancel(convoyId)
            end
        end
    end

    -- Notificar todos e limpar cache
    for memberCid, info in pairs(party.members) do
        if info.src then
            TriggerClientEvent('aurp_trucker:client:partyDisbanded', info.src)
        end
        if party.graceTimers[memberCid] then
            ClearTimeout(party.graceTimers[memberCid])
        end
        VP_Trucker.PlayerParties[memberCid] = nil
    end

    DB_SetPartyStatus(partyId, 'disbanded')
    VP_Trucker.Parties[partyId] = nil
    return true
end

-- Retorna partyId de um jogador pelo src
function PartyService.GetPartyBySrc(src)
    local Player = Framework.GetPlayer(src)
    if not Player then return nil end
    return VP_Trucker.PlayerParties[Framework.GetCitizenId(Player)]
end

-- Chamado quando jogador desconecta (src e citizenid capturados ANTES de ficar stale)
function PartyService.OnPlayerDisconnect(src, citizenid)
    if VP_Trucker.PartyInvites then
        VP_Trucker.PartyInvites[citizenid] = nil
    end

    local partyId = VP_Trucker.PlayerParties[citizenid]
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party then return end

    if party.members[citizenid] then
        party.members[citizenid].src = nil
    end

    local timer = SetTimeout(Config.Party.gracePeriod * 1000, function()
        PartyService.LeaveByIdentifier(partyId, citizenid)
    end)
    party.graceTimers[citizenid] = timer
end

-- Chamado quando jogador reconecta
function PartyService.OnPlayerReconnect(src, citizenid)
    local partyId = VP_Trucker.PlayerParties[citizenid]
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party or not party.members[citizenid] then return end

    if party.graceTimers[citizenid] then
        ClearTimeout(party.graceTimers[citizenid])
        party.graceTimers[citizenid] = nil
    end

    party.members[citizenid].src = src

    BroadcastPartyUpdate(partyId)
end
