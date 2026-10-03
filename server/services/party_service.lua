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
            citizenid           = cid,
            user_id             = cid,
            name                = info.src and GetCharName(info.src) or cid,
            isLeader            = (cid == party.leader),
            owner               = (cid == party.leader and 1 or 0),
            online              = info.src ~= nil,
            joined_at           = info.joined_at or os.time(),
            finished_deliveries = info.finished_deliveries or 0,
        })
    end

    local partyPayload = {
        id            = partyId,
        partyId       = partyId,
        code          = party.code or string.upper(string.sub(partyId, 1, 6)),
        name          = party.name or ('Grupo #' .. string.upper(string.sub(partyId, 1, 6))),
        description   = party.description or 'Grupo de transporte cooperativo',
        owner         = 0,
        user_id       = party.leader,
        members       = party.maxSize or 4,
        members_count = #membersPayload,
        members_list  = membersPayload,
        convoyActive  = party.convoyActive or false,
        maxSize       = party.maxSize or 4,
    }

    for cid, info in pairs(party.members) do
        if info.src then
            local pCopy = table.clone and table.clone(partyPayload) or partyPayload
            pCopy.isLeader = (cid == party.leader)
            pCopy.owner    = (cid == party.leader and 1 or 0)
            TriggerClientEvent('aurp_trucker:client:partyUpdate', info.src, {
                party = pCopy
            })
        end
    end
end

-- Cria uma nova party para o jogador
function PartyService.Create(src, data)
    local Player = Framework.GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    if VP_Trucker.PlayerParties[cid] then
        return nil, 'Você já está em um grupo ativo.'
    end

    local maxSize = (data and tonumber(data.members)) or Config.Party.maxSize or 4
    if maxSize > 8 then maxSize = 8 end
    if maxSize < 2 then maxSize = 2 end

    local partyId = NewUUID()
    local partyCode = string.upper(string.sub(partyId, 1, 6))

    local partyName = (data and data.name and tostring(data.name):gsub("^%s*(.-)%s*$", "%1") ~= "") and tostring(data.name):gsub("^%s*(.-)%s*$", "%1") or ('Frota #' .. partyCode)
    local partyDesc = (data and data.desc and tostring(data.desc):gsub("^%s*(.-)%s*$", "%1") ~= "") and tostring(data.desc):gsub("^%s*(.-)%s*$", "%1") or 'Transporte e Logística em Comboio'
    local partyPass = (data and data.pass and tostring(data.pass):gsub("^%s*(.-)%s*$", "%1") ~= "") and tostring(data.pass):gsub("^%s*(.-)%s*$", "%1") or nil

    pcall(DB_CreateParty, partyId, cid, maxSize)

    VP_Trucker.Parties[partyId] = {
        id          = partyId,
        code        = partyCode,
        name        = partyName,
        description = partyDesc,
        pass        = partyPass,
        leader      = cid,
        members     = { [cid] = { src = src, joined_at = os.time(), finished_deliveries = 0 } },
        graceTimers = {},
        maxSize     = maxSize,
        status      = 'forming',
    }
    VP_Trucker.PlayerParties[cid] = partyId

    BroadcastPartyUpdate(partyId)
    return partyId
end

-- Ingressa em um grupo existente por Nome ou Código
function PartyService.Join(src, nameOrCode, pass)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    if VP_Trucker.PlayerParties[cid] then
        return false, 'Você já participa de um grupo. Saia do grupo atual antes de entrar em outro.'
    end

    if not nameOrCode or tostring(nameOrCode):gsub("^%s*(.-)%s*$", "%1") == "" then
        return false, 'Informe o nome ou código do grupo.'
    end

    local cleanSearch = tostring(nameOrCode):gsub("^%s*(.-)%s*$", "%1"):upper()

    local foundPartyId, foundParty = nil, nil
    for pid, p in pairs(VP_Trucker.Parties) do
        if p.status ~= 'disbanded' then
            local pCode = (p.code or string.upper(string.sub(pid, 1, 6))):upper()
            local pName = (p.name or ""):upper()
            if pCode == cleanSearch or pName == cleanSearch or pid == nameOrCode then
                foundPartyId = pid
                foundParty = p
                break
            end
        end
    end

    if not foundParty or not foundPartyId then
        return false, 'Nenhum grupo encontrado com o nome ou código informado.'
    end

    -- Validar capacidade
    local memberCount = 0
    for _ in pairs(foundParty.members) do memberCount = memberCount + 1 end
    if memberCount >= (foundParty.maxSize or 4) then
        return false, 'Este grupo atingiu a capacidade máxima de membros.'
    end

    -- Validar senha se houver
    if foundParty.pass and foundParty.pass ~= "" then
        local inputPass = pass and tostring(pass):gsub("^%s*(.-)%s*$", "%1") or ""
        if inputPass ~= tostring(foundParty.pass) then
            return false, 'Senha incorreta para entrar neste grupo.'
        end
    end

    foundParty.members[cid] = { src = src, joined_at = os.time(), finished_deliveries = 0 }
    VP_Trucker.PlayerParties[cid] = foundPartyId

    BroadcastPartyUpdate(foundPartyId)
    return true, foundPartyId
end

-- Convida jogador pelo server id
function PartyService.Invite(src, targetSrc)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return false, 'Você não está em um grupo ativo.' end

    local party = VP_Trucker.Parties[partyId]
    if not party then return false, 'Grupo não encontrado.' end
    if party.leader ~= cid then return false, 'Apenas o líder da frota pode enviar convites.' end

    local memberCount = 0
    for _ in pairs(party.members) do memberCount = memberCount + 1 end
    if memberCount >= (party.maxSize or 4) then return false, 'O grupo já atingiu o limite de membros.' end

    local targetPlayer = Framework.GetPlayer(targetSrc)
    if not targetPlayer then return false, 'Jogador não encontrado ou offline.' end
    local targetCid = Framework.GetCitizenId(targetPlayer)

    if targetCid == cid or tonumber(targetSrc) == tonumber(src) then
        return false, 'Você não pode convidar a si mesmo.'
    end

    if VP_Trucker.PlayerParties[targetCid] then
        return false, 'O jogador convidado já está em um grupo.'
    end

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
        partyName  = party.name or 'Frota de Logística',
        leaderName = GetCharName(src),
    })
    return true
end

-- Expulsa membro do grupo (apenas líder)
function PartyService.Kick(src, targetCid)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return false, 'Você não está em um grupo.' end

    local party = VP_Trucker.Parties[partyId]
    if not party then return false, 'Grupo não encontrado.' end
    if party.leader ~= cid then return false, 'Apenas o líder pode expulsar membros.' end

    if targetCid == cid then return false, 'Você não pode expulsar a si mesmo.' end

    local memberInfo = party.members[targetCid]
    if not memberInfo then return false, 'Membro não encontrado no grupo.' end

    -- Se online, notificar e desvincular client
    if memberInfo.src then
        TriggerClientEvent('aurp_trucker:notify', memberInfo.src, 'Você foi removido do grupo pelo líder.', 'error')
        TriggerClientEvent('aurp_trucker:client:partyDisbanded', memberInfo.src)
    end

    party.members[targetCid] = nil
    VP_Trucker.PlayerParties[targetCid] = nil

    BroadcastPartyUpdate(partyId)
    return true
end

-- Aceita convite — adiciona membro ao party
function PartyService.Accept(src, partyId)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Framework.GetCitizenId(Player)

    if VP_Trucker.PlayerParties[cid] then return false, 'Você já está em um grupo ativo.' end

    local invite = VP_Trucker.PartyInvites and VP_Trucker.PartyInvites[cid]
    if not invite or invite.partyId ~= partyId or os.time() > (invite.expiresAt or 0) then
        return false, 'Você não possui convite válido ou ele expirou.'
    end
    VP_Trucker.PartyInvites[cid] = nil

    local party = VP_Trucker.Parties[partyId]
    if not party then return false, 'Grupo não encontrado.' end
    if party.status == 'disbanded' then return false, 'O grupo foi encerrado.' end

    local memberCount = 0
    for _ in pairs(party.members) do memberCount = memberCount + 1 end
    if memberCount >= (party.maxSize or 4) then return false, 'O grupo já atingiu o limite de vagas.' end

    party.members[cid] = { src = src, joined_at = os.time(), finished_deliveries = 0 }
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
