# Multiplayer Convoy (Fase 3A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar party system + convoy cooperativo com GPS cego para drivers, CB radio com range de 500m, e bônus de pagamento em grupo para o AUST_trucker v9.0.0.

**Architecture:** Dois serviços server-side independentes — `PartyService` (lifecycle persistente, entre jobs) e `ConvoyService` (lifecycle do job). Cliente dedicado `convoy.client.lua`. Mínima invasão no fluxo de job existente: apenas hook em `JobService.Complete` e um `TriggerEvent` em `StartLoading()`.

**Tech Stack:** QBX (qbx_core) + ox_lib + oxmysql + React 18 + TypeScript + Zustand + Tailwind CSS. lua54 = yes. Versão alvo: 9.0.0.

---

## Arquivos Criados / Modificados

| Arquivo | Ação |
|---|---|
| `sql/update_convoy_v9.sql` | CRIAR — migração v8→v9 |
| `import.sql` | MODIFICAR — + 3 tabelas + convoy_id em trucker_jobs |
| `config/config.lua` | MODIFICAR — + Config.Party block |
| `server/main.lua` | MODIFICAR — + Parties/Convoys/PlayerParties no VP_Trucker; + wait ConvoyService |
| `server/database.lua` | MODIFICAR — + DB_Party*, DB_Convoy*, DB_ConvoyMember*, DB_GetJobWithConvoy |
| `server/services/party_service.lua` | CRIAR — global PartyService |
| `server/services/convoy_service.lua` | CRIAR — global ConvoyService |
| `server/services/job_service.lua` | MODIFICAR — + GenerateConvoyBatch; Complete detecta convoy_id |
| `server/services/truck_simulation_service.lua` | MODIFICAR — + coords em SimState + GetCoords() |
| `server/events.lua` | MODIFICAR — playerDropped + OnPlayerLoaded |
| `server/callbacks.lua` | MODIFICAR — + 7 callbacks party/convoy |
| `client/hud.client.lua` | MODIFICAR — coords em SyncToServer + truckStateChanged event |
| `client/client.lua` | MODIFICAR — jobStartedConvoy TriggerEvent em StartLoading() |
| `client/convoy.client.lua` | CRIAR — cliente convoy/party/CB radio |
| `fxmanifest.lua` | MODIFICAR — v9.0.0, novos arquivos na ordem correta |
| `CHANGELOG.md` | MODIFICAR — entrada v9.0.0 |
| `html/src/types/index.ts` | MODIFICAR — + PartyMember, Party, TabName 'convoy' |
| `html/src/stores/usePartyStore.ts` | CRIAR — Zustand store |
| `html/src/components/convoy/PartyPanel.tsx` | CRIAR — UI de party |
| `html/src/hooks/useNUI.ts` | MODIFICAR — + partyUpdate/convoyStarted/convoyEnded |
| `html/src/App.tsx` | MODIFICAR — + convoy tab |

---

## Task 1: Schema + Config

**Files:**
- Modify: `import.sql`
- Create: `sql/update_convoy_v9.sql`
- Modify: `config/config.lua`

- [ ] **Step 1: Criar arquivo de migração `sql/update_convoy_v9.sql`**

```sql
-- AUST_trucker — migração v8→v9 (Multiplayer Convoy / Fase 3A)
-- Executar em servidores existentes. fresh installs usam import.sql diretamente.

-- 1. Adicionar convoy_id em trucker_jobs
ALTER TABLE trucker_jobs
    ADD COLUMN IF NOT EXISTS convoy_id VARCHAR(36) NULL DEFAULT NULL;

-- 2. Tabela de parties (lifecycle persistente)
CREATE TABLE IF NOT EXISTS trucker_parties (
    id          VARCHAR(36)  PRIMARY KEY,
    leader_cid  VARCHAR(50)  NOT NULL,
    members     JSON         NOT NULL DEFAULT '[]',
    max_size    INT          NOT NULL DEFAULT 6,
    status      ENUM('forming','active','disbanded') NOT NULL DEFAULT 'forming',
    created_at  DATETIME     NOT NULL DEFAULT NOW()
);

-- 3. Tabela de convoy jobs (lifecycle do job)
CREATE TABLE IF NOT EXISTS trucker_convoy_jobs (
    id           VARCHAR(36)  PRIMARY KEY,
    party_id     VARCHAR(36)  NOT NULL,
    status       ENUM('forming','active','completed','cancelled') NOT NULL DEFAULT 'forming',
    bonus_mult   FLOAT        NOT NULL DEFAULT 1.5,
    active_count INT          NOT NULL DEFAULT 0,
    total_count  INT          NOT NULL DEFAULT 0,
    started_at   DATETIME     NULL,
    completed_at DATETIME     NULL,
    FOREIGN KEY (party_id) REFERENCES trucker_parties(id)
);

-- 4. Tabela de slots por membro (durável — sobrevive a restart)
-- NOTA: job_id é VARCHAR(50) pois trucker_jobs.id é VARCHAR(50) PRIMARY KEY (string gerada por GenerateJobId())
CREATE TABLE IF NOT EXISTS trucker_convoy_members (
    convoy_id   VARCHAR(36)  NOT NULL,
    citizenid   VARCHAR(50)  NOT NULL,
    job_id      VARCHAR(50)  NOT NULL,
    status      ENUM('pending','active','completed','abandoned') NOT NULL DEFAULT 'pending',
    PRIMARY KEY (convoy_id, citizenid),
    FOREIGN KEY (convoy_id)  REFERENCES trucker_convoy_jobs(id),
    FOREIGN KEY (job_id)     REFERENCES trucker_jobs(id)
);
```

- [ ] **Step 2: Atualizar `import.sql` — adicionar campo convoy_id em trucker_jobs**

No bloco `CREATE TABLE trucker_jobs`, adicionar após `company_id VARCHAR(50) NULL`:
```sql
    convoy_id           VARCHAR(36)     NULL DEFAULT NULL,
```

- [ ] **Step 3: Atualizar `import.sql` — adicionar as 3 novas tabelas ao final do arquivo**

```sql
-- =============================================
-- PARTIES (Fase 3A — Multiplayer Convoy)
-- =============================================

CREATE TABLE IF NOT EXISTS trucker_parties (
    id          VARCHAR(36)  PRIMARY KEY,
    leader_cid  VARCHAR(50)  NOT NULL,
    members     JSON         NOT NULL DEFAULT '[]',
    max_size    INT          NOT NULL DEFAULT 6,
    status      ENUM('forming','active','disbanded') NOT NULL DEFAULT 'forming',
    created_at  DATETIME     NOT NULL DEFAULT NOW()
);

-- =============================================
-- CONVOY JOBS (Fase 3A)
-- =============================================

CREATE TABLE IF NOT EXISTS trucker_convoy_jobs (
    id           VARCHAR(36)  PRIMARY KEY,
    party_id     VARCHAR(36)  NOT NULL,
    status       ENUM('forming','active','completed','cancelled') NOT NULL DEFAULT 'forming',
    bonus_mult   FLOAT        NOT NULL DEFAULT 1.5,
    active_count INT          NOT NULL DEFAULT 0,
    total_count  INT          NOT NULL DEFAULT 0,
    started_at   DATETIME     NULL,
    completed_at DATETIME     NULL,
    FOREIGN KEY (party_id) REFERENCES trucker_parties(id)
);

-- =============================================
-- CONVOY MEMBERS (Fase 3A)
-- =============================================

CREATE TABLE IF NOT EXISTS trucker_convoy_members (
    convoy_id   VARCHAR(36)  NOT NULL,
    citizenid   VARCHAR(50)  NOT NULL,
    job_id      VARCHAR(50)  NOT NULL,
    status      ENUM('pending','active','completed','abandoned') NOT NULL DEFAULT 'pending',
    PRIMARY KEY (convoy_id, citizenid),
    FOREIGN KEY (convoy_id)  REFERENCES trucker_convoy_jobs(id),
    FOREIGN KEY (job_id)     REFERENCES trucker_jobs(id)
);
```

- [ ] **Step 4: Adicionar `Config.Party` em `config/config.lua`**

Adicionar ao final do arquivo (antes do último `end` de Config, ou como bloco standalone):
```lua
Config.Party = {
    maxSize                  = 6,        -- máximo de membros por party
    cbRadioKey               = 'Z',      -- tecla para abrir input do rádio CB
    cbRadioRange             = 500.0,    -- metros — fora do range não recebe mensagem
    cbMessageDuration        = 8,        -- segundos antes de sumir do HUD
    gracePeriod              = 180,      -- segundos de grace period ao desconectar
    bonusMultiplier          = 1.5,      -- multiplicador de pagamento em convoy completo
    positionBroadcastInterval = 3000,   -- ms entre updates de blip de posição
}
```

- [ ] **Step 5: Commit**

```bash
git add sql/update_convoy_v9.sql import.sql config/config.lua
git commit -m "feat(convoy): schema v9 (trucker_parties, convoy_jobs, convoy_members) + Config.Party"
```

---

## Task 2: DB Functions

**Files:**
- Modify: `server/database.lua`

- [ ] **Step 1: Adicionar funções DB_Party* ao final de `server/database.lua`**

```lua
-- ============================================================
-- PARTIES (Fase 3A)
-- ============================================================

function DB_CreateParty(partyId, leaderCid, maxSize)
    MySQL.insert.await(
        'INSERT INTO trucker_parties (id, leader_cid, max_size) VALUES (?, ?, ?)',
        { partyId, leaderCid, maxSize }
    )
end

function DB_GetParty(partyId)
    return MySQL.single.await(
        'SELECT * FROM trucker_parties WHERE id = ? LIMIT 1',
        { partyId }
    )
end

function DB_SetPartyStatus(partyId, status)
    MySQL.update.await(
        'UPDATE trucker_parties SET status = ? WHERE id = ?',
        { status, partyId }
    )
end

-- ============================================================
-- CONVOY JOBS (Fase 3A)
-- ============================================================

function DB_CreateConvoy(convoyId, partyId, bonusMult, totalCount)
    MySQL.insert.await([[
        INSERT INTO trucker_convoy_jobs (id, party_id, bonus_mult, total_count, active_count, status, started_at)
        VALUES (?, ?, ?, ?, ?, 'active', NOW())
    ]], { convoyId, partyId, bonusMult, totalCount, totalCount })
end

function DB_GetActiveConvoys()
    return MySQL.query.await(
        "SELECT * FROM trucker_convoy_jobs WHERE status = 'active'"
    ) or {}
end

function DB_SetConvoyStatus(convoyId, status)
    local extra = (status == 'completed' or status == 'cancelled') and ', completed_at = NOW()' or ''
    MySQL.update.await(
        ('UPDATE trucker_convoy_jobs SET status = ? %s WHERE id = ?'):format(extra),
        { status, convoyId }
    )
end

function DB_SetConvoyBonusMult(convoyId, bonusMult)
    MySQL.update.await(
        'UPDATE trucker_convoy_jobs SET bonus_mult = ? WHERE id = ?',
        { bonusMult, convoyId }
    )
end

-- ============================================================
-- CONVOY MEMBERS (Fase 3A)
-- ============================================================

function DB_CreateConvoyMember(convoyId, citizenid, jobId)
    MySQL.insert.await([[
        INSERT INTO trucker_convoy_members (convoy_id, citizenid, job_id, status)
        VALUES (?, ?, ?, 'pending')
    ]], { convoyId, citizenid, jobId })
end

function DB_GetConvoyMember(convoyId, citizenid)
    return MySQL.single.await(
        'SELECT * FROM trucker_convoy_members WHERE convoy_id = ? AND citizenid = ? LIMIT 1',
        { convoyId, citizenid }
    )
end

function DB_SetConvoyMemberStatus(convoyId, citizenid, status)
    MySQL.update.await(
        'UPDATE trucker_convoy_members SET status = ? WHERE convoy_id = ? AND citizenid = ?',
        { status, convoyId, citizenid }
    )
end

function DB_GetConvoyMembers(convoyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_convoy_members WHERE convoy_id = ?',
        { convoyId }
    ) or {}
end
```

- [ ] **Step 2: Adicionar `DB_GetJobWithConvoy` e modificar `DB_InsertJob` em `server/database.lua`**

Adicionar função que retorna convoy_id junto ao job:
```lua
-- Retorna job completo incluindo convoy_id (usado por JobService.Complete para detectar convoy)
function DB_GetJobWithConvoy(jobId)
    return MySQL.single.await(
        'SELECT id, base_payment, distance, cargo_item, convoy_id FROM trucker_jobs WHERE id = ? LIMIT 1',
        { jobId }
    )
end
```

Modificar `DB_InsertJob` para aceitar convoy_id opcional (localizada na linha ~143 de database.lua):
```lua
function DB_InsertJob(job, convoyId)
    -- job = { id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at }
    -- convoyId: VARCHAR(36) opcional — nil para jobs individuais
    return MySQL.insert.await(
        [[INSERT INTO trucker_jobs
          (id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at, convoy_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)]],
        { job.id, job.origin_id, job.dest_id, job.cargo_item, job.trailer_model,
          job.base_payment, job.distance, job.expires_at, convoyId or nil }
    )
end
```

- [ ] **Step 3: Commit**

```bash
git add server/database.lua
git commit -m "feat(convoy): DB_Party*, DB_Convoy*, DB_ConvoyMember* + DB_InsertJob aceita convoyId"
```

---

## Task 3: TruckSimulationService — coords

**Files:**
- Modify: `server/services/truck_simulation_service.lua`
- Modify: `client/hud.client.lua`

- [ ] **Step 1: Adicionar coords ao SimState inicial em `truck_simulation_service.lua`**

Na função `TruckSimulationService.OnPlayerLoaded` (linha ~20), no bloco `SimState[src] = { ... }`, adicionar campo:
```lua
SimState[src] = {
    lastFuel         = 100.0,
    lastFatigue      = fatigue,
    lastSyncTime     = GetGameTimer(),
    vehicleWasMoving = false,
    currentPlate     = nil,
    coords           = vector3(0, 0, 0),   -- NOVO v9: última posição conhecida
}
```

- [ ] **Step 2: Adicionar leitura de coords no `OnSync` em `truck_simulation_service.lua`**

Na função `TruckSimulationService.OnSync`, após a linha `state.vehicleWasMoving = payload.vehicleWasMoving or false`, adicionar:
```lua
-- Atualizar coords (payload.coords = { x, y, z } enviado pelo cliente quando isTruck=true)
if payload.coords then
    local c = payload.coords
    state.coords = vector3(
        tonumber(c.x) or 0,
        tonumber(c.y) or 0,
        tonumber(c.z) or 0
    )
end
```

- [ ] **Step 3: Adicionar getters públicos em `truck_simulation_service.lua`**

Adicionar após `TruckSimulationService.HasUpgrade`:
```lua
-- Retorna última posição conhecida do jogador (vector3) ou nil se não houver SimState
function TruckSimulationService.GetCoords(src)
    local state = SimState[src]
    if not state then return nil end
    return state.coords
end

-- Retorna true se jogador está atualmente em um caminhão (tem plate no SimState)
-- Usado por ConvoyService para popular o campo isTruck nas posições de broadcast
function TruckSimulationService.IsInTruck(src)
    local state = SimState[src]
    return state ~= nil and state.currentPlate ~= nil
end
```

- [ ] **Step 4: Modificar `client/hud.client.lua` — adicionar coords a SyncToServer**

Localizar a função `SyncToServer()` (linha ~57) e adicionar `coords` ao payload:
```lua
local function SyncToServer()
    local coords = SimState.currentVehicle and GetEntityCoords(SimState.currentVehicle) or nil
    TriggerServerEvent('AUST_trucker:syncSimulation', {
        fuel             = SimState.fuel,
        fatigue          = SimState.fatigue,
        vehicleWasMoving = SimState.vehicleWasMoving,
        plate            = SimState.currentPlate,
        coords           = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })
    SimState.lastSyncTime = GetGameTimer()
end
```

- [ ] **Step 5: Modificar `client/hud.client.lua` — disparar evento truckStateChanged ao mudar isTruck**

Adicionar variável local antes do thread de detecção (linha ~132):
```lua
local prevIsTruck = false
```

Na thread de detecção de veículo (dentro do `CreateThread`), após cada bloco que modifica `SimState.isTruck`, adicionar o disparo do evento somente quando o valor mudar. O padrão é: depois de qualquer linha que seta `SimState.isTruck = true` ou `SimState.isTruck = false`, verificar se mudou e disparar.

Substituir o bloco do thread de detecção de veículo por:
```lua
local prevIsTruck = false

CreateThread(function()
    while true do
        Wait(1000)
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 then
            local model   = GetEntityModel(vehicle)
            local isTruck = IsTruckModel(model)

            if isTruck then
                if vehicle ~= SimState.currentVehicle then
                    if SimState.currentVehicle then SyncToServer() end

                    local plate = GetVehicleNumberPlateText(vehicle)
                    SimState.currentVehicle = vehicle
                    SimState.currentPlate   = plate
                    SimState.lastKnownPlate = plate
                    SimState.isTruck        = true
                    SimState.sleepTriggered = false

                    TriggerServerEvent('AUST_trucker:spawnVehicle', plate)
                end

                if IsVehicleDriveable(vehicle, false) == false or GetEntityHealth(vehicle) <= 0 then
                    OnVehicleDestroyed()
                end

                SimState.vehicleWasMoving = GetEntitySpeed(vehicle) > 2.0
            else
                if SimState.isTruck then SyncToServer() end
                SimState.currentVehicle   = nil
                SimState.currentPlate     = nil
                SimState.isTruck          = false
                SimState.vehicleWasMoving = false
            end
        else
            if SimState.isTruck then SyncToServer() end
            SimState.currentVehicle   = nil
            SimState.currentPlate     = nil
            SimState.isTruck          = false
            SimState.vehicleWasMoving = false
        end

        -- Notificar convoy.client.lua quando isTruck mudar
        if SimState.isTruck ~= prevIsTruck then
            prevIsTruck = SimState.isTruck
            TriggerEvent('AUST_trucker:client:truckStateChanged', SimState.isTruck)
        end
    end
end)
```

**Importante:** Remover o bloco `CreateThread` original e substituir pelo acima. Não duplicar o thread.

- [ ] **Step 6: Commit**

```bash
git add server/services/truck_simulation_service.lua client/hud.client.lua
git commit -m "feat(convoy): TruckSimulationService.GetCoords + SyncToServer envia coords + truckStateChanged event"
```

---

## Task 4: VP_Trucker + PartyService

**Files:**
- Modify: `server/main.lua`
- Create: `server/services/party_service.lua`

- [ ] **Step 1: Modificar `server/main.lua` — adicionar Parties/Convoys/PlayerParties ao VP_Trucker**

Substituir o bloco `VP_Trucker = { ... }` por:
```lua
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
}
```

- [ ] **Step 2: Modificar `server/main.lua` — aguardar ConvoyService no init**

No bloco `CreateThread` dentro de `MySQL.ready`, substituir:
```lua
CreateThread(function()
    while not JobService do Wait(100) end
    while not IndustryOwnershipService do Wait(100) end
    while not ConvoyService do Wait(100) end   -- NOVO v9
    IndustryOwnershipService.LoadCache()
    JobService.LoadFromDB()
    ConvoyService.LoadFromDB()                  -- NOVO v9
    VP_Trucker.Ready = true
    if Config.Debug then print('[AUST_trucker] Server ready.') end
end)
```

- [ ] **Step 3: Criar `server/services/party_service.lua`**

```lua
-- AUST_trucker — server/services/party_service.lua
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
            name      = (info.src and GetPlayerName(info.src)) or cid,
            isLeader  = (cid == party.leader),
            online    = info.src ~= nil,
        })
    end

    local payload = {
        partyId      = partyId,
        isLeader     = false,
        members      = membersPayload,
        convoyActive = VP_Trucker.Convoys ~= nil and VP_Trucker.Convoys[partyId] ~= nil,
        maxSize      = party.maxSize,
    }

    for cid, info in pairs(party.members) do
        if info.src then
            payload.isLeader = (cid == party.leader)
            SendNUIMessage = nil  -- não usar aqui
            TriggerClientEvent('AUST_trucker:client:partyUpdate', info.src,
                { party = { partyId = partyId, isLeader = (cid == party.leader),
                            members = membersPayload, convoyActive = payload.convoyActive,
                            maxSize = party.maxSize } })
        end
    end
end

-- Cria uma nova party para o jogador
function PartyService.Create(src)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end
    local cid = Player.PlayerData.citizenid

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

-- Convida jogador pelo server id (validado pelo callback)
function PartyService.Invite(src, targetSrc)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Player.PlayerData.citizenid

    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return false, 'Você não está em um party' end

    local party = VP_Trucker.Parties[partyId]
    if party.leader ~= cid then return false, 'Apenas o líder pode convidar' end

    local memberCount = 0
    for _ in pairs(party.members) do memberCount = memberCount + 1 end
    if memberCount >= party.maxSize then return false, 'Party cheio' end

    local targetPlayer = exports.qbx_core:GetPlayer(targetSrc)
    if not targetPlayer then return false, 'Jogador não encontrado' end
    local targetCid = targetPlayer.PlayerData.citizenid

    if VP_Trucker.PlayerParties[targetCid] then return false, 'Jogador já está em um party' end

    TriggerClientEvent('AUST_trucker:client:partyInvite', targetSrc, {
        partyId    = partyId,
        leaderName = GetPlayerName(src),
    })
    return true
end

-- Aceita convite — adiciona membro ao party
function PartyService.Accept(src, partyId)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Player.PlayerData.citizenid

    if VP_Trucker.PlayerParties[cid] then return false, 'Você já está em um party' end

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
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    PartyService.LeaveByIdentifier(VP_Trucker.PlayerParties[cid], cid)
end

-- Remove membro pelo citizenid (funciona mesmo com src stale)
function PartyService.LeaveByIdentifier(partyId, citizenid)
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party then return end

    -- Se convoy ativo, marcar como abandoned
    for convoyId, convoy in pairs(VP_Trucker.Convoys) do
        if convoy.partyId == partyId and convoy.memberJobs[citizenid] then
            ConvoyService.MemberAbandon(convoyId, citizenid)
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
        -- Party vazia: dissolver
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
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local cid = Player.PlayerData.citizenid

    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return false, 'Você não está em um party' end

    local party = VP_Trucker.Parties[partyId]
    if party.leader ~= cid then return false, 'Apenas o líder pode dissolver' end

    -- Cancelar convoy ativo se houver
    for convoyId, convoy in pairs(VP_Trucker.Convoys) do
        if convoy.partyId == partyId then
            ConvoyService.Cancel(convoyId)
        end
    end

    -- Notificar todos e limpar cache
    for memberCid, info in pairs(party.members) do
        if info.src then
            TriggerClientEvent('AUST_trucker:client:partyDisbanded', info.src)
        end
        -- Limpar grace timers
        if party.graceTimers[memberCid] then
            ClearTimeout(party.graceTimers[memberCid])
        end
        VP_Trucker.PlayerParties[memberCid] = nil
    end

    DB_SetPartyStatus(partyId, 'disbanded')
    VP_Trucker.Parties[partyId] = nil
end

-- Retorna partyId de um jogador pelo src
function PartyService.GetPartyBySrc(src)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil end
    return VP_Trucker.PlayerParties[Player.PlayerData.citizenid]
end

-- Chamado quando jogador desconecta (src e citizenid capturados ANTES de ficar stale)
function PartyService.OnPlayerDisconnect(src, citizenid)
    local partyId = VP_Trucker.PlayerParties[citizenid]
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party then return end

    -- Marca src como nil MAS mantém a sub-table (grace period)
    if party.members[citizenid] then
        party.members[citizenid].src = nil
    end

    -- Timer fecha sobre citizenid (string imutável) — NUNCA sobre src (stale)
    local timer = SetTimeout(Config.Party.gracePeriod * 1000, function()
        PartyService.LeaveByIdentifier(partyId, citizenid)
    end)
    -- SEMPRE armazena em party.graceTimers (mesmo se convoy ainda não iniciado)
    party.graceTimers[citizenid] = timer
end

-- Chamado quando jogador reconecta (via QBCore:Server:OnPlayerLoaded)
function PartyService.OnPlayerReconnect(src, citizenid)
    local partyId = VP_Trucker.PlayerParties[citizenid]
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party or not party.members[citizenid] then return end

    -- Cancelar grace timer
    if party.graceTimers[citizenid] then
        ClearTimeout(party.graceTimers[citizenid])
        party.graceTimers[citizenid] = nil
    end

    -- Restaurar src
    party.members[citizenid].src = src

    -- Enviar estado atual do party para o cliente reconectado
    BroadcastPartyUpdate(partyId)
end
```

- [ ] **Step 4: Commit**

```bash
git add server/main.lua server/services/party_service.lua
git commit -m "feat(convoy): VP_Trucker.Parties/Convoys/PlayerParties + PartyService completo"
```

---

## Task 5: JobService — GenerateConvoyBatch + Complete hook

**Files:**
- Modify: `server/services/job_service.lua`

- [ ] **Step 1: Adicionar `JobService.GenerateConvoyBatch` ao final de `job_service.lua`**

```lua
-- Gera um lote de jobs para um convoy (um job por membro, mesmo origin/dest, trailers distintos)
-- Retorna { [citizenid] = jobId } para ConvoyService popular o cache
-- NOTA: convoyId já foi inserido em trucker_convoy_jobs por ConvoyService.Start (FK obrigatória)
function JobService.GenerateConvoyBatch(convoyId, partyId, memberCids)
    -- 1. Selecionar origin/dest compartilhado usando lógica demand-weighted
    local origins = Config.PrimaryIndustries
    local dests   = Config.SecondaryIndustries

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

    -- Tentar até 20 combinações para encontrar origin/dest válidos
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
        if Config.Debug then print('[AUST_trucker] GenerateConvoyBatch: falha ao selecionar origin/dest') end
        return nil
    end

    local dist      = CalcDistance(sharedOrigin.coords, sharedDest.coords)
    local memberJobs = {}

    -- 2. Para cada membro: produto independente (trailer diferente), mesmo origin/dest
    for _, cid in ipairs(memberCids) do
        local product = PickProduct(sharedOrigin)
        if not product then
            if Config.Debug then print(('[AUST_trucker] GenerateConvoyBatch: sem produto para %s'):format(cid)) end
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

        -- 3. INSERT sequencial: trucker_jobs primeiro, depois trucker_convoy_members
        DB_InsertJob(job, convoyId)
        DB_CreateConvoyMember(convoyId, cid, job.id)

        memberJobs[cid] = job.id

        ::nextMember::
    end

    return memberJobs
end
```

- [ ] **Step 2: Modificar `JobService.Complete` para detectar convoy e delegar pagamento**

Localizar a função `JobService.Complete` (linha ~242). Após `local activeJob = DB_GetActiveJobByPlayer(citizenId)` e antes do cálculo de tempo, adicionar:

```lua
-- Detectar se é job de convoy — delegar pagamento ao ConvoyService
if activeJob.convoy_id and ConvoyService then
    -- Marcar job como concluído no DB mas NÃO pagar aqui
    DB_CompleteJob(activeJob.id)
    DB_AddPlayerStats(citizenId, 0, activeJob.distance)  -- registra distância, payment = 0 por ora
    ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, 1.0)

    -- Delegar pagamento ao ConvoyService (que paga todos quando activeCount chega a 0)
    ConvoyService.MemberComplete(src, activeJob.convoy_id, citizenId, activeJob)
    return true, 0  -- payment = 0 aqui; o real vem do ConvoyService._PayAll
end
```

**Importante:** Este bloco deve vir ANTES do cálculo de `timeMult`, `skillMult`, etc.

- [ ] **Step 3: Commit**

```bash
git add server/services/job_service.lua
git commit -m "feat(convoy): JobService.GenerateConvoyBatch + Complete delega para ConvoyService quando convoy_id"
```

---

## Task 6: ConvoyService

**Files:**
- Create: `server/services/convoy_service.lua`

- [ ] **Step 1: Criar `server/services/convoy_service.lua`**

```lua
-- AUST_trucker — server/services/convoy_service.lua
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

        -- Coletar posições de todos os membros ativos
        local positions = {}
        for cid, info in pairs(party.members) do
            if info.src then
                local coords = TruckSimulationService.GetCoords(info.src)
                if coords then
                    positions[cid] = {
                        x       = coords.x,
                        y       = coords.y,
                        z       = coords.z,
                        name    = GetPlayerName(info.src),
                        isTruck = TruckSimulationService.IsInTruck(info.src),
                    }
                end
            end
        end

        -- Enviar para cada membro
        for cid, info in pairs(party.members) do
            if info.src then
                TriggerClientEvent('AUST_trucker:client:convoyPositions', info.src, positions)
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

    -- Coletar membros ativos (src não-nil)
    local memberCids = {}
    for cid, info in pairs(party.members) do
        if info.src then table.insert(memberCids, cid) end
    end

    if #memberCids < 2 then
        return false, 'Convoy precisa de pelo menos 2 membros online'
    end

    local convoyId = NewUUID()
    local totalCount = #memberCids

    -- 1. Inserir trucker_convoy_jobs PRIMEIRO (FK obrigatória para trucker_convoy_members)
    DB_CreateConvoy(convoyId, partyId, Config.Party.bonusMultiplier, totalCount)

    -- 2. Gerar jobs e inserir convoy_members (sequencialmente, dentro de GenerateConvoyBatch)
    local memberJobs = JobService.GenerateConvoyBatch(convoyId, partyId, memberCids)
    if not memberJobs then
        -- Falha na geração: cancelar convoy recém-criado
        DB_SetConvoyStatus(convoyId, 'cancelled')
        return false, 'Falha ao gerar jobs para o convoy'
    end

    -- 3. Popular cache em memória
    VP_Trucker.Convoys[convoyId] = {
        partyId      = partyId,
        memberJobs   = memberJobs,
        graceTimers  = {},
        broadcastTimer = nil,
        activeCount  = totalCount,
        totalCount   = totalCount,
    }

    -- 4. Iniciar broadcast periódico de posições
    ConvoyService.StartPositionBroadcast(convoyId)

    -- 5. Notificar membros com seus jobs
    for _, cid in ipairs(memberCids) do
        local info = party.members[cid]
        if info and info.src then
            local jobId = memberJobs[cid]
            local jobData = JobService.GetActiveByPlayer(cid)
            -- Aceitar o job automaticamente (convoy_members status = 'pending' → 'active' quando aceitar job)
            TriggerClientEvent('AUST_trucker:client:convoyStarted', info.src, {
                convoyId = convoyId,
                jobId    = jobId,
                jobData  = jobData,
                isLeader = (cid == party.leader),
            })
        end
    end

    if Config.Debug then
        print(('[AUST_trucker] Convoy %s iniciado: %d membros, party %s'):format(convoyId, totalCount, partyId))
    end

    return true, convoyId
end

-- Chamado por JobService.Complete quando convoy_id detectado
function ConvoyService.MemberComplete(src, convoyId, citizenid, activeJob)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    DB_SetConvoyMemberStatus(convoyId, citizenid, 'completed')
    convoy.activeCount = math.max(0, convoy.activeCount - 1)

    if Config.Debug then
        print(('[AUST_trucker] Convoy %s: %s completou. Restam: %d'):format(convoyId, citizenid, convoy.activeCount))
    end

    if convoy.activeCount == 0 then
        ConvoyService._PayAll(convoyId)
    end
end

-- Membro abandona o convoy (desconexão ou leave explícito)
function ConvoyService.MemberAbandon(convoyId, citizenid)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    DB_SetConvoyMemberStatus(convoyId, citizenid, 'abandoned')
    convoy.activeCount = math.max(0, convoy.activeCount - 1)

    -- Recalcular bônus proporcional
    local rows = DB_GetConvoyMembers(convoyId)
    local completedCount = 0
    for _, row in ipairs(rows) do
        if row.status == 'completed' then completedCount = completedCount + 1 end
    end
    -- completedFraction = (concluídos até agora) / total
    -- bonus: 1.0 a 1.5 proporcional
    local completedFraction = completedCount / convoy.totalCount
    local newMult = 1.0 + (0.5 * completedFraction)
    DB_SetConvoyBonusMult(convoyId, newMult)

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
    local senderName   = GetPlayerName(src)

    for cid, info in pairs(party.members) do
        if info.src then
            local targetCoords = TruckSimulationService.GetCoords(info.src)
            local inRange = true

            if senderCoords and targetCoords then
                local dx = senderCoords.x - targetCoords.x
                local dy = senderCoords.y - targetCoords.y
                local dist = math.sqrt(dx*dx + dy*dy)
                inRange = dist <= Config.Party.cbRadioRange
            end

            if inRange then
                TriggerClientEvent('AUST_trucker:client:cbMessage', info.src, {
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

    -- Buscar bonus_mult final do DB (pode ter sido recalculado por abandons)
    local rows = DB_GetConvoyMembers(convoyId)
    local bonusMult = Config.Party.bonusMultiplier

    -- Recalcular com base nos status finais
    local completedCount = 0
    for _, row in ipairs(rows) do
        if row.status == 'completed' then completedCount = completedCount + 1 end
    end
    if convoy.totalCount > 0 then
        bonusMult = 1.0 + (0.5 * (completedCount / convoy.totalCount))
    end

    local party = VP_Trucker.Parties[convoy.partyId]

    for _, row in ipairs(rows) do
        if row.status == 'completed' then
            local jobRow = DB_GetJobWithConvoy(row.job_id)
            if jobRow then
                local payment = math.floor((jobRow.base_payment or 0) * bonusMult)
                -- Buscar player pelo cid
                for _, playerSrc in ipairs(GetPlayers()) do
                    local p = exports.qbx_core:GetPlayer(tonumber(playerSrc))
                    if p and p.PlayerData.citizenid == row.citizenid then
                        p.Functions.AddMoney(Config.General.payment.currency, payment, 'aurp-trucker-convoy')
                        DB_AddPlayerStats(row.citizenid, payment, 0)  -- distância já somada no Complete
                        TriggerClientEvent('AUST_trucker:client:jobCompleted', tonumber(playerSrc), payment)
                        TriggerClientEvent('AUST_trucker:notify', tonumber(playerSrc),
                            ('Convoy concluído! Bônus ×%.1f — $%d recebidos'):format(bonusMult, payment), 'success')
                        break
                    end
                end
            end
        end
    end

    -- Finalizar convoy
    DB_SetConvoyStatus(convoyId, 'completed')
    ConvoyService.StopPositionBroadcast(convoyId)

    -- Notificar party que convoy terminou
    if party then
        for cid, info in pairs(party.members) do
            if info.src then
                TriggerClientEvent('AUST_trucker:client:convoyEnded', info.src)
            end
        end
    end

    VP_Trucker.Convoys[convoyId] = nil
end

-- Cancela convoy (disband do party ou falha)
function ConvoyService.Cancel(convoyId)
    local convoy = VP_Trucker.Convoys[convoyId]
    if not convoy then return end

    ConvoyService.StopPositionBroadcast(convoyId)
    DB_SetConvoyStatus(convoyId, 'cancelled')

    local party = VP_Trucker.Parties[convoy.partyId]
    if party then
        for cid, info in pairs(party.members) do
            if info.src then
                TriggerClientEvent('AUST_trucker:client:convoyEnded', info.src)
            end
        end
    end

    VP_Trucker.Convoys[convoyId] = nil
end

-- Recupera convoys ativos após restart do servidor
function ConvoyService.LoadFromDB()
    local active = DB_GetActiveConvoys() or {}
    for _, convoy in ipairs(active) do
        local members = DB_GetConvoyMembers(convoy.id)
        local memberJobs = {}
        local activeCount = 0

        for _, m in ipairs(members) do
            memberJobs[m.citizenid] = m.job_id
            -- Slots pending/active sem jogador online → abandoned
            if m.status == 'pending' or m.status == 'active' then
                DB_SetConvoyMemberStatus(convoy.id, m.citizenid, 'abandoned')
            else
                activeCount = activeCount + 1
            end
        end

        -- Se nenhum ativo após limpeza: finalizar
        if activeCount == 0 then
            DB_SetConvoyStatus(convoy.id, 'cancelled')
        else
            VP_Trucker.Convoys[convoy.id] = {
                partyId      = convoy.party_id,
                memberJobs   = memberJobs,
                graceTimers  = {},
                broadcastTimer = nil,
                activeCount  = activeCount,
                totalCount   = convoy.total_count,
            }
        end
    end

    if Config.Debug then
        print(('[AUST_trucker] ConvoyService.LoadFromDB: %d convoys recuperados'):format(#active))
    end
end
```

- [ ] **Step 2: Commit**

```bash
git add server/services/convoy_service.lua
git commit -m "feat(convoy): ConvoyService completo (Start, MemberComplete, MemberAbandon, Broadcast, _PayAll, LoadFromDB)"
```

---

## Task 7: Server Events + Callbacks

**Files:**
- Modify: `server/events.lua`
- Modify: `server/callbacks.lua`

- [ ] **Step 1: Modificar `server/events.lua` — handler `playerDropped`**

Localizar (linha ~331):
```lua
AddEventHandler('playerDropped', function()
    TruckSimulationService.OnPlayerDropped(source)
end)
```

Substituir por:
```lua
AddEventHandler('playerDropped', function()
    local src = source
    -- Capturar citizenid ANTES de src ficar stale
    local Player = exports.qbx_core:GetPlayer(src)
    local citizenid = Player and Player.PlayerData.citizenid
    TruckSimulationService.OnPlayerDropped(src)
    if citizenid and PartyService then
        PartyService.OnPlayerDisconnect(src, citizenid)
    end
end)
```

- [ ] **Step 2: Modificar `server/events.lua` — handler `QBCore:Server:OnPlayerLoaded`**

Localizar o handler de `QBCore:Server:OnPlayerLoaded` em events.lua. Adicionar `PartyService.OnPlayerReconnect` ao final:

```lua
AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid
    DB_UpsertPlayerStats(citizenId)
    TruckSimulationService.OnPlayerLoaded(src)
    if PartyService then
        PartyService.OnPlayerReconnect(src, citizenId)
    end
end)
```

**Nota:** Verificar se o handler já existe em events.lua. Se sim, apenas adicionar a linha `PartyService.OnPlayerReconnect`. Se não existir (está em outro arquivo), criar aqui. Nunca duplicar handlers.

- [ ] **Step 3: Atualizar `getInitialData` em `server/callbacks.lua` para incluir party atual**

Localizar o return de `getInitialData` e adicionar `currentParty`:
```lua
    -- Helper: serializar party para NUI
    local partyPayload = nil
    local myPartyId = VP_Trucker.PlayerParties[citizenId]
    if myPartyId then
        local party = VP_Trucker.Parties[myPartyId]
        if party then
            local membersPayload = {}
            for cid, info in pairs(party.members) do
                table.insert(membersPayload, {
                    citizenid = cid,
                    name      = (info.src and GetPlayerName(info.src)) or cid,
                    isLeader  = (cid == party.leader),
                    online    = info.src ~= nil,
                })
            end
            -- Verificar se há convoy ativo para esta party
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

    return {
        -- ... campos existentes (jobs, company, activeJob, etc.) ...
        currentParty = partyPayload,   -- NOVO v9
    }
```

**Nota:** Adicionar `currentParty = partyPayload` ao return existente sem remover os outros campos. O return já existe e tem vários campos — inserir apenas a nova linha.

- [ ] **Step 4: Adicionar 7 callbacks em `server/callbacks.lua`**

Adicionar ao final do arquivo:

```lua
-- =============================================
-- PARTY / CONVOY CALLBACKS (Fase 3A)
-- =============================================

lib.callback.register('AUST_trucker:partyCreate', function(source)
    local partyId, err = PartyService.Create(source)
    return { success = partyId ~= nil, partyId = partyId, reason = err }
end)

lib.callback.register('AUST_trucker:partyInvite', function(source, targetName)
    -- Buscar targetSrc pelo nome
    local targetSrc = nil
    for _, playerSrc in ipairs(GetPlayers()) do
        local s = tonumber(playerSrc)
        if GetPlayerName(s) == targetName then targetSrc = s; break end
    end
    if not targetSrc then return { success = false, reason = 'Jogador não encontrado' } end

    local ok, err = PartyService.Invite(source, targetSrc)
    return { success = ok, reason = err }
end)

lib.callback.register('AUST_trucker:partyAccept', function(source, partyId)
    local ok, err = PartyService.Accept(source, partyId)
    return { success = ok, reason = err }
end)

lib.callback.register('AUST_trucker:partyLeave', function(source)
    PartyService.Leave(source)
    return { success = true }
end)

lib.callback.register('AUST_trucker:partyDisband', function(source)
    local ok, err = PartyService.Disband(source)
    return { success = ok ~= false, reason = err }
end)

lib.callback.register('AUST_trucker:convoyStart', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local cid     = Player.PlayerData.citizenid
    local partyId = VP_Trucker.PlayerParties[cid]
    if not partyId then return { success = false, reason = 'Você não está em um party' } end
    local party = VP_Trucker.Parties[partyId]
    if not party then return { success = false, reason = 'Party não encontrado' } end
    if party.leader ~= cid then return { success = false, reason = 'Apenas o líder pode iniciar o convoy' } end

    local ok, result = ConvoyService.Start(partyId)
    return { success = ok, reason = ok and nil or result }
end)

lib.callback.register('AUST_trucker:cbRadioSend', function(source, message)
    if not message or message == '' then return { success = false } end
    -- Limitar tamanho da mensagem
    message = tostring(message):sub(1, 100)
    ConvoyService.Broadcast(source, message)
    return { success = true }
end)
```

- [ ] **Step 4: Commit**

```bash
git add server/events.lua server/callbacks.lua
git commit -m "feat(convoy): events.lua (playerDropped + OnPlayerLoaded) + 7 callbacks party/convoy"
```

---

## Task 8: Client Files

**Files:**
- Modify: `client/hud.client.lua` (coords em SyncToServer + truckStateChanged — já feito na Task 3)
- Modify: `client/client.lua`
- Create: `client/convoy.client.lua`

> **Nota:** As modificações em `client/hud.client.lua` foram implementadas na Task 3. Esta task apenas verifica o client.lua e cria convoy.client.lua.

- [ ] **Step 1: Modificar `client/client.lua` — adicionar TriggerEvent após criar delivery blip em `StartLoading()`**

Localizar a seção em `StartLoading()` onde `jobProgress.deliveryBlip` é criado (~linha 706):
```lua
        -- Criar blip para delivery
        jobProgress.deliveryBlip = CreateBlip(
            currentJob.delivery.coords,
            473, -- warehouse icon
            3, -- blue
            "ENTREGAR: " .. currentJob.delivery.name,
            1.0,
            true -- route
        )
```

Adicionar logo após (após a linha `)`):
```lua
        -- Notificar convoy.client.lua (para GPS suppression em blind driver mode)
        TriggerEvent('AUST_trucker:client:jobStartedConvoy', jobProgress.deliveryBlip)
```

- [ ] **Step 2: Criar `client/convoy.client.lua`**

```lua
-- AUST_trucker — client/convoy.client.lua
-- Client-side: party UI, convoy blips, GPS suppression, CB radio HUD
-- Carrega APÓS hud.client.lua (usa evento AUST_trucker:client:truckStateChanged de lá)

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local localCitizenId = nil  -- populado no OnPlayerLoaded

local ConvoyState = {
    partyId      = nil,
    isLeader     = false,
    members      = {},     -- lista: { citizenid, name, isLeader, online }
    convoyActive = false,
    isInTruck    = false,  -- atualizado via truckStateChanged de hud.client.lua
    gpsBlocked   = false,
    memberBlips  = {},     -- { [citizenid] = blipHandle }
    cbLog        = {},     -- últimas 5 mensagens: { sender, text, timestamp }
    maxSize      = 6,
}

-- ============================================================
-- CAPTURA DO CITIZENID LOCAL
-- ============================================================

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    -- QBX popula PlayerData antes deste evento
    if QBX and QBX.PlayerData then
        localCitizenId = QBX.PlayerData.citizenid
    end
end)

-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

-- Atualização de estado do party (broadcast após qualquer mudança)
RegisterNetEvent('AUST_trucker:client:partyUpdate', function(data)
    if not data or not data.party then return end
    local party = data.party
    ConvoyState.partyId  = party.partyId
    ConvoyState.isLeader = party.isLeader
    ConvoyState.members  = party.members or {}
    ConvoyState.maxSize  = party.maxSize or 6

    -- Sincronizar convoyActive sem sobrescrever se já true (pode chegar antes do convoyStarted)
    if party.convoyActive ~= nil then
        ConvoyState.convoyActive = party.convoyActive
    end

    -- Notificar NUI
    SendNUIMessage({ action = 'partyUpdate', party = party })
end)

-- Party dissolvido pelo líder
RegisterNetEvent('AUST_trucker:client:partyDisbanded', function()
    ConvoyState.partyId      = nil
    ConvoyState.isLeader     = false
    ConvoyState.members      = {}
    ConvoyState.convoyActive = false
    ConvoyState.gpsBlocked   = false
    -- Limpar blips
    for cid, blip in pairs(ConvoyState.memberBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    ConvoyState.memberBlips = {}
    SendNUIMessage({ action = 'partyUpdate', party = nil })
end)

-- Convoy iniciado pelo líder
RegisterNetEvent('AUST_trucker:client:convoyStarted', function(data)
    ConvoyState.convoyActive = true
    SendNUIMessage({ action = 'convoyStarted' })
    lib.notify({ title = 'Convoy', description = 'Convoy iniciado! Siga as instruções pelo rádio CB.', type = 'info' })
end)

-- Convoy concluído ou cancelado
RegisterNetEvent('AUST_trucker:client:convoyEnded', function()
    ConvoyState.convoyActive = false
    ConvoyState.gpsBlocked   = false
    -- Limpar blips de membros
    for cid, blip in pairs(ConvoyState.memberBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    ConvoyState.memberBlips = {}
    SendNUIMessage({ action = 'convoyEnded' })
end)

-- Convite de party recebido
RegisterNetEvent('AUST_trucker:client:partyInvite', function(data)
    -- data = { partyId, leaderName }
    CreateThread(function()
        local confirm = lib.alertDialog({
            header   = 'Convite de Convoy',
            content  = (data.leaderName or 'Alguém') .. ' convidou você para um convoy.',
            centered = true,
            cancel   = true,
        })
        if confirm == 'confirm' then
            local result = lib.callback.await('AUST_trucker:partyAccept', false, data.partyId)
            if result and not result.success then
                lib.notify({ title = 'Party', description = result.reason or 'Erro ao entrar no party', type = 'error' })
            end
        end
    end)
end)

-- Posições dos membros para blips
RegisterNetEvent('AUST_trucker:client:convoyPositions', function(positions)
    -- positions = { [citizenid] = { x, y, z, name, isTruck } }
    for cid, pos in pairs(positions) do
        if cid ~= localCitizenId then
            local blip = ConvoyState.memberBlips[cid]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(pos.x, pos.y, pos.z)
                SetBlipSprite(blip, 477)   -- caminhão
                SetBlipColour(blip, 5)     -- amarelo
                SetBlipScale(blip, 0.8)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(pos.name or cid)
                EndTextCommandSetBlipName(blip)
                ConvoyState.memberBlips[cid] = blip
            else
                SetBlipCoords(blip, pos.x, pos.y, pos.z)
            end
        end
    end
end)

-- Mensagem CB radio recebida
RegisterNetEvent('AUST_trucker:client:cbMessage', function(data)
    -- data = { sender, message, timestamp }
    table.insert(ConvoyState.cbLog, {
        sender    = data.sender,
        text      = data.message,
        timestamp = GetGameTimer(),
    })
    -- Manter apenas as últimas 5
    while #ConvoyState.cbLog > 5 do
        table.remove(ConvoyState.cbLog, 1)
    end
end)

-- ============================================================
-- GPS SUPPRESSION (Blind Driver)
-- ============================================================

-- hud.client.lua dispara este evento quando isTruck muda
AddEventHandler('AUST_trucker:client:truckStateChanged', function(isTruck)
    ConvoyState.isInTruck = isTruck
end)

-- client.lua dispara este evento quando cria o blip de destino em StartLoading()
AddEventHandler('AUST_trucker:client:jobStartedConvoy', function(blipHandle)
    if not ConvoyState.convoyActive then return end
    -- Apenas drivers (isInTruck = true) ficam cegos; escorts mantêm GPS
    if not ConvoyState.isInTruck then return end

    if DoesBlipExist(blipHandle) then
        RemoveBlip(blipHandle)
    end
    ConvoyState.gpsBlocked = true
    lib.notify({ title = 'Convoy', description = 'GPS bloqueado — use o rádio CB para navegação!', type = 'warning', duration = 8000 })
end)

-- Limpar gpsBlocked quando job concluído
RegisterNetEvent('AUST_trucker:client:jobCompleted', function()
    ConvoyState.gpsBlocked = false
end)

-- ============================================================
-- THREAD: HUD CB RADIO (500ms)
-- ============================================================

CreateThread(function()
    while true do
        Wait(500)
        if #ConvoyState.cbLog == 0 then goto continue end

        local now = GetGameTimer()
        local duration = Config.Party.cbMessageDuration * 1000

        -- Remover mensagens expiradas
        local i = 1
        while i <= #ConvoyState.cbLog do
            if (now - ConvoyState.cbLog[i].timestamp) >= duration then
                table.remove(ConvoyState.cbLog, i)
            else
                i = i + 1
            end
        end

        -- Renderizar mensagens restantes
        local y = 0.88
        for _, msg in ipairs(ConvoyState.cbLog) do
            local text = ('[CB] %s: %s'):format(msg.sender, msg.text)
            SetTextFont(0)
            SetTextScale(0.35, 0.35)
            SetTextColour(255, 230, 100, 220)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(0.02, y)
            y = y - 0.025
        end

        ::continue::
    end
end)

-- ============================================================
-- TECLA CB RADIO
-- ============================================================

CreateThread(function()
    while true do
        Wait(0)
        -- Apenas quando em convoy ativo e em truck
        if not ConvoyState.convoyActive then Wait(500); goto continue end
        if not ConvoyState.isInTruck then Wait(500); goto continue end

        -- Tecla configurável em Config.Party.cbRadioKey (default 'Z')
        -- Mapeamento GTA: Z = control 20. Se cbRadioKey mudar, esta linha precisa ser atualizada.
        -- Para implementação futura: resolver string→control hash via RegisterKeyMapping
        if IsControlJustPressed(0, 20) then
            CreateThread(function()
                local input = lib.inputDialog('Rádio CB', {
                    { type = 'input', label = 'Mensagem', placeholder = 'Digite sua mensagem...', maxLength = 100 }
                })
                if input and input[1] and input[1] ~= '' then
                    lib.callback.await('AUST_trucker:cbRadioSend', false, input[1])
                end
            end)
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: INDICADOR GPS BLOQUEADO (Blind Driver)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        if not ConvoyState.gpsBlocked then goto continue end

        -- Aviso persistente no canto da tela
        SetTextFont(0)
        SetTextScale(0.4, 0.4)
        SetTextColour(255, 80, 80, 200)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName('GPS BLOQUEADO — Use o Rádio CB [Z]')
        EndTextCommandDisplayText(0.02, 0.93)

        ::continue::
    end
end)
```

- [ ] **Step 3: Commit**

```bash
git add client/client.lua client/convoy.client.lua
git commit -m "feat(convoy): client.lua jobStartedConvoy + convoy.client.lua (party UI, blips, GPS suppression, CB radio)"
```

---

## Task 9: fxmanifest + TypeScript + NUI

**Files:**
- Modify: `fxmanifest.lua`
- Modify: `html/src/types/index.ts`
- Create: `html/src/stores/usePartyStore.ts`
- Create: `html/src/components/convoy/PartyPanel.tsx`
- Modify: `html/src/hooks/useNUI.ts`
- Modify: `html/src/App.tsx`

- [ ] **Step 1: Modificar `fxmanifest.lua` — v9.0.0, novos arquivos na ordem correta**

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'AURP Development Team'
description 'Sistema de Caminhoneiros — Empresas, Jobs e Economia Dinâmica'
version '9.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'qbx_core',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/party_service.lua',           -- Fase 3A: sem dependências de outros services
    'server/services/loan_service.lua',
    'server/services/repo_service.lua',            -- após loan_service
    'server/services/economy_service.lua',
    'server/services/industry_ownership_service.lua',
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',
    'server/services/job_service.lua',             -- convoy_service depende deste
    'server/services/convoy_service.lua',          -- Fase 3A: APÓS job_service
    'server/services/truck_simulation_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}

client_scripts {
    'client/client.lua',
    'client/hud.client.lua',
    'client/convoy.client.lua',                    -- Fase 3A: após hud.client (usa truckStateChanged)
    'client/industries.client.lua',
    'client/industries_npc.client.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/*.js',
    'html/assets/*.css',
}
```

- [ ] **Step 2: Modificar `html/src/types/index.ts` — adicionar PartyMember, Party; atualizar TabName**

Adicionar ao final das interfaces existentes (antes de `export type TabName`):
```typescript
export interface PartyMember {
  citizenid: string
  name:      string
  isLeader:  boolean
  online:    boolean
}

export interface Party {
  partyId:      string
  isLeader:     boolean
  members:      PartyMember[]
  convoyActive: boolean
  maxSize:      number
}
```

Modificar `TabName` para incluir `'convoy'`:
```typescript
export type TabName = 'jobs' | 'missions' | 'active' | 'company' | 'garage' | 'industries' | 'stats' | 'convoy'
```

- [ ] **Step 3: Criar `html/src/stores/usePartyStore.ts`**

```typescript
import { create } from 'zustand'
import type { Party, PartyMember } from '../types'

interface PartyStore {
  party:           Party | null
  setParty:        (party: Party | null) => void
  updateMembers:   (members: PartyMember[]) => void
  setConvoyActive: (active: boolean) => void
}

export const usePartyStore = create<PartyStore>((set) => ({
  party: null,

  setParty: (party) => set({ party }),

  updateMembers: (members) => set((state) => ({
    party: state.party ? { ...state.party, members } : null,
  })),

  setConvoyActive: (convoyActive) => set((state) => ({
    party: state.party ? { ...state.party, convoyActive } : null,
  })),
}))
```

- [ ] **Step 4: Criar `html/src/components/convoy/PartyPanel.tsx`**

```tsx
import { useState } from 'react'
import { usePartyStore } from '../../stores/usePartyStore'
import { fetchNUI } from '../../hooks/useNUI'

export function PartyPanel() {
  const { party, setParty } = usePartyStore()
  const [searchName, setSearchName] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleCreate() {
    setLoading(true)
    const result = await fetchNUI<{ success: boolean; partyId?: string; reason?: string }>('partyCreate')
    if (!result.success) setError(result.reason ?? 'Erro ao criar party')
    setLoading(false)
  }

  async function handleInvite() {
    if (!searchName.trim()) return
    setLoading(true)
    const result = await fetchNUI<{ success: boolean; reason?: string }>('partyInvite', searchName.trim())
    if (!result.success) setError(result.reason ?? 'Erro ao convidar')
    else setSearchName('')
    setLoading(false)
  }

  async function handleLeave() {
    await fetchNUI('partyLeave')
    setParty(null)
  }

  async function handleDisband() {
    await fetchNUI('partyDisband')
    setParty(null)
  }

  async function handleStartConvoy() {
    setLoading(true)
    const result = await fetchNUI<{ success: boolean; reason?: string }>('convoyStart')
    if (!result.success) setError(result.reason ?? 'Erro ao iniciar convoy')
    setLoading(false)
  }

  const activeCount = party?.members.filter(m => m.online).length ?? 0

  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-lg font-semibold text-zinc-100">Convoy</h2>

      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-300 rounded px-3 py-2 text-sm">
          {error}
          <button className="ml-2 underline" onClick={() => setError(null)}>×</button>
        </div>
      )}

      {!party ? (
        <div className="flex flex-col gap-3">
          <p className="text-zinc-400 text-sm">Você não está em nenhum party.</p>
          <button
            className="bg-blue-700 hover:bg-blue-600 text-white rounded px-4 py-2 text-sm font-medium disabled:opacity-50"
            onClick={handleCreate}
            disabled={loading}
          >
            Criar Party
          </button>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {/* Convoy status */}
          {party.convoyActive && (
            <div className="bg-green-900/40 border border-green-700 text-green-300 rounded px-3 py-2 text-sm font-medium">
              Convoy ativo — use a tecla Z para o Rádio CB
            </div>
          )}

          {/* Lista de membros */}
          <div className="flex flex-col gap-1">
            {party.members.map(m => (
              <div
                key={m.citizenid}
                className="flex items-center gap-2 bg-zinc-800 rounded px-3 py-2"
              >
                <span className={`w-2 h-2 rounded-full ${m.online ? 'bg-green-500' : 'bg-zinc-500'}`} />
                <span className="text-zinc-100 text-sm flex-1">{m.name}</span>
                {m.isLeader && (
                  <span className="text-yellow-400 text-xs">👑 Líder</span>
                )}
                {!m.online && (
                  <span className="text-zinc-500 text-xs">offline (grace)</span>
                )}
              </div>
            ))}
          </div>

          {/* Convidar jogador — apenas líder */}
          {party.isLeader && !party.convoyActive && (
            <div className="flex gap-2">
              <input
                className="flex-1 bg-zinc-800 border border-zinc-600 text-zinc-100 rounded px-3 py-2 text-sm"
                placeholder="Nome do jogador..."
                value={searchName}
                onChange={e => setSearchName(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleInvite()}
              />
              <button
                className="bg-blue-700 hover:bg-blue-600 text-white rounded px-3 py-2 text-sm disabled:opacity-50"
                onClick={handleInvite}
                disabled={loading || !searchName.trim()}
              >
                Convidar
              </button>
            </div>
          )}

          {/* Ações */}
          <div className="flex gap-2">
            {party.isLeader && !party.convoyActive && (
              <button
                className="flex-1 bg-green-700 hover:bg-green-600 text-white rounded px-4 py-2 text-sm font-medium disabled:opacity-50"
                onClick={handleStartConvoy}
                disabled={loading || activeCount < 2}
                title={activeCount < 2 ? 'Precisa de pelo menos 2 membros online' : ''}
              >
                Iniciar Convoy ({activeCount}/{party.maxSize})
              </button>
            )}
            {party.isLeader ? (
              <button
                className="bg-red-900 hover:bg-red-800 text-red-200 rounded px-4 py-2 text-sm"
                onClick={handleDisband}
                disabled={loading}
              >
                Dissolver
              </button>
            ) : (
              <button
                className="flex-1 bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded px-4 py-2 text-sm"
                onClick={handleLeave}
                disabled={loading}
              >
                Sair do Party
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 5: Modificar `html/src/hooks/useNUI.ts` — adicionar Party ao NUIMessage e handlers**

Adicionar import no topo:
```typescript
import { usePartyStore } from '../stores/usePartyStore'
import type { Party } from '../types'
```

Adicionar `party?` e `currentParty?` ao NUIMessage interface:
```typescript
interface NUIMessage {
  // ... campos existentes ...
  party?:        Party | null
  currentParty?: Party | null
}
```

No `useEffect`, adicionar `setParty` na desestruturação:
```typescript
const { setParty, setConvoyActive } = usePartyStore()
```

No `case 'open'` existente, adicionar hidratação de party após os outros `set*` calls:
```typescript
case 'open': {
  // ... código existente ...
  setParty(event.data.currentParty ?? null)   // NOVO v9 — hidrata party ao abrir NUI
  // ... resto do case existente ...
}
```

Adicionar novos cases ao switch:
```typescript
case 'partyUpdate':
  setParty(event.data.party ?? null)
  break
case 'convoyStarted':
  setConvoyActive(true)
  break
case 'convoyEnded':
  setConvoyActive(false)
  break
```

- [ ] **Step 6: Modificar `html/src/App.tsx` — adicionar convoy tab**

Adicionar import:
```typescript
import { PartyPanel } from './components/convoy/PartyPanel'
```

Adicionar renderização dentro do `div` de conteúdo:
```tsx
{activeTab === 'convoy'     && <PartyPanel />}
```

**Nota sobre TabBar:** A aba "Convoy" precisa ser adicionada ao componente `TabBar.tsx` também. Localizar `html/src/components/layout/TabBar.tsx` e adicionar entrada para `'convoy'` com ícone de rádio (Radio) do lucide-react.

- [ ] **Step 7: Verificar `html/src/components/layout/TabBar.tsx` e adicionar tab Convoy**

Localizar o arquivo e adicionar `'convoy'` à lista de tabs. O padrão existente usa ícones do lucide-react. Adicionar:
```typescript
{ id: 'convoy', label: 'Convoy', icon: Radio }
```

Importar `Radio` de `'lucide-react'` no topo do arquivo.

- [ ] **Step 8: Commit**

```bash
git add fxmanifest.lua html/src/types/index.ts html/src/stores/usePartyStore.ts html/src/components/convoy/PartyPanel.tsx html/src/hooks/useNUI.ts html/src/App.tsx html/src/components/layout/TabBar.tsx
git commit -m "feat(convoy): fxmanifest v9.0.0 + NUI types + usePartyStore + PartyPanel + useNUI convoy cases"
```

---

## Task 10: Build + CHANGELOG

**Files:**
- Build: `html/` (npm run build)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Build NUI**

```bash
cd html
npm run build
cd ..
```

Verificar que `html/assets/` foi atualizado com os novos bundles.

- [ ] **Step 2: Commit final com build**

```bash
git add html/assets/
git commit -m "build: NUI v9.0.0"
```

- [ ] **Step 3: Adicionar entrada ao CHANGELOG.md**

```markdown
## [9.0.0] — 2026-03-19

### Added (Fase 3A — Multiplayer Convoy)
- **Party System:** criação, convite, aceitação, saída e dissolução de parties pelo PDA
- **Convoy:** N motoristas com trailers distintos, mesmo origin/dest (demand-weighted), pagamento com bônus ×1.5 proporcional
- **Blind Driver:** driver em convoy não vê GPS/blip de destino; escorts mantêm GPS normalmente
- **CB Radio:** texto com range de 500m (tecla Z); mensagens somem após 8s; fora do range = silêncio
- **Blips de posição:** broadcast a cada 3s de posição de todos os membros para blips no mapa
- **Grace period:** desconexão não cancela party/convoy imediatamente — 3min para reconectar
- **Bônus proporcional:** se membros abandonam, bonus_mult é reduzido proporcionalmente (1.0–1.5)
- Novas tabelas: `trucker_parties`, `trucker_convoy_jobs`, `trucker_convoy_members`
- Campo `convoy_id` em `trucker_jobs`
- `TruckSimulationService.GetCoords(src)` para range check do CB radio e broadcast de posições
- Migração `sql/update_convoy_v9.sql` para servidores existentes

### Technical
- Novos serviços: `PartyService`, `ConvoyService`
- `JobService.GenerateConvoyBatch` — geração em lote com mesmo origin/dest
- `convoy.client.lua` — cliente dedicado sem modificar fluxo de job existente
- `usePartyStore`, `PartyPanel` — nova aba "Convoy" no PDA
```

- [ ] **Step 4: Commit final**

```bash
git add CHANGELOG.md html/assets/
git commit -m "feat: AUST_trucker v9.0.0 — Fase 3A Multiplayer Convoy (party + convoy + CB radio + blind driver)"
```

---

## Notas de Implementação

### Ordem de verificação antes de começar

1. Confirmar que `trucker_jobs.id` é `VARCHAR(50)` no DB atual (string, não INT)
2. Confirmar que o handler `QBCore:Server:OnPlayerLoaded` existe em `server/events.lua` — se não, criar lá
3. Confirmar que `lib.notify` está sendo usado corretamente (QBX usa `lib.notify`, não `TriggerClientEvent('AUST_trucker:notify')`)
4. Confirmar que `StartLoading()` é a função de `client/client.lua` que cria o blip de delivery — a spec menciona `StartJob()` mas o código real usa `StartLoading()` para esta etapa (linha ~619). Ambas as funções existem; o blip de delivery fica em `StartLoading()` (~linha 706).

### Armadilhas conhecidas

- **`trucker_convoy_members.job_id` DEVE ser `VARCHAR(50)`** — a spec original disse `INT` mas `trucker_jobs.id` é string (`job_123_12345`)
- **Grace timer armazenado em `party.graceTimers[cid]` SEMPRE** — mesmo quando convoy ainda não foi iniciado; `ClearTimeout` no reconnect
- **`ConvoyService.Start` insere `trucker_convoy_jobs` ANTES de chamar `GenerateConvoyBatch`** — a FK `trucker_convoy_members.convoy_id → trucker_convoy_jobs.id` exige isso
- **`JobService.Complete` hook de convoy deve vir ANTES do cálculo de `timeMult`** — o `return true, 0` early-return precisa acontecer antes dos cálculos de multiplicador
- **`prevIsTruck` declarado FORA do `CreateThread` em `hud.client.lua`** — variável local no escopo do arquivo, não dentro do loop
- **`convoy.client.lua` após `hud.client.lua` no fxmanifest** — usa `AUST_trucker:client:truckStateChanged` disparado por hud
- **`party_service.lua` ANTES de `loan_service.lua` no fxmanifest** — sem dependências; convoy_service APÓS job_service
