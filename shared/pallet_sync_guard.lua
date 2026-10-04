-- Guarda de idempotência do polarixSyncPallets (cliente). Sem natives.
-- O servidor envia a lista de paletes mais de uma vez por job; só o primeiro envio por netId
-- pode reposicionar/reativar a física. Os demais apenas reconhecem o estado já aplicado.
PalletSyncGuard = {}

function PalletSyncGuard.New()
    return { jobId = nil, claimed = {}, ents = {}, syncCount = 0 }
end

-- Registra um novo evento de sync. Um jobId diferente zera o estado. Devolve o nº do sync no job.
function PalletSyncGuard.Begin(state, jobId)
    jobId = jobId or 'nojob'
    if state.jobId ~= jobId then
        state.jobId = jobId
        state.claimed = {}
        state.ents = {}
        state.syncCount = 0
    end
    state.syncCount = state.syncCount + 1
    return state.syncCount
end

-- true apenas para quem pode aplicar snap/física neste netId.
function PalletSyncGuard.Claim(state, netId)
    if state.claimed[netId] then return false end
    state.claimed[netId] = true
    return true
end

-- Falha antes de aplicar (entidade não apareceu): permite nova tentativa num sync posterior.
function PalletSyncGuard.Release(state, netId)
    state.claimed[netId] = nil
end

function PalletSyncGuard.Reset(state)
    state.jobId = nil
    state.claimed = {}
    state.ents = {}
    state.syncCount = 0
end
