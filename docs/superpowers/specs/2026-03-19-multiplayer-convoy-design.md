# Multiplayer Convoy (Fase 3A) — Design Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implementar o sistema de party + convoy cooperativo do AUST_trucker — múltiplos motoristas, GPS cego para drivers, CB radio com range, e bônus grupal de pagamento.

**Architecture:** Dois serviços separados (`PartyService` para membership persistente, `ConvoyService` para execução do job) com ciclos de vida distintos. Party persiste entre jobs; convoy nasce e morre com o job. Cliente dedicado `convoy.client.lua` sem modificar o fluxo existente de jobs além do mínimo necessário.

**Tech Stack:** QBX (qbx_core) + ox_lib + oxmysql. NUI: React 18 + TypeScript + Zustand + Tailwind CSS. lua54 = yes. Versão alvo: 9.0.0.

---

## Decisões de Design

| Questão | Decisão |
|---|---|
| Tipo de convoy job | Híbrido — N trailers, N cargoes, 1 destino. Cada membro tem job individual com `convoy_id` |
| Blind driver | Sempre em convoy — driver não vê GPS/blip de entrega; escorts veem normalmente |
| CB radio | Texto com range de 500m — mensagens somem após 8s; fora do range = sem mensagem |
| Party formation | UI (nova aba no PDA), busca por nome de jogador online |
| Tamanho máximo | Configurável — `Config.Party.maxSize`, default 6 |
| Pagamento | Multiplicador fixo × 1.5 por membro; reduzido proporcionalmente por abandonos |
| Disconnect | Job individual cancela; grace period 3 min para reconectar; se não volta, slot `abandoned` e bônus reduzido |

---

## Camada de Dados

### Novas tabelas SQL

```sql
CREATE TABLE IF NOT EXISTS trucker_parties (
    id          VARCHAR(36)  PRIMARY KEY,
    leader_cid  VARCHAR(50)  NOT NULL,
    members     JSON         NOT NULL DEFAULT '[]',
    max_size    INT          NOT NULL DEFAULT 6,
    status      ENUM('forming','active','disbanded') NOT NULL DEFAULT 'forming',
    created_at  DATETIME     NOT NULL DEFAULT NOW()
);

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

-- Tabela de slots por membro — durável; sobrevive a restart do servidor
CREATE TABLE IF NOT EXISTS trucker_convoy_members (
    convoy_id   VARCHAR(36)  NOT NULL,
    citizenid   VARCHAR(50)  NOT NULL,
    job_id      INT          NOT NULL,
    status      ENUM('pending','active','completed','abandoned') NOT NULL DEFAULT 'pending',
    PRIMARY KEY (convoy_id, citizenid),
    FOREIGN KEY (convoy_id) REFERENCES trucker_convoy_jobs(id)
);
```

**Por que `trucker_convoy_members`:** o estado por slot (pending/completed/abandoned) é necessário para calcular bônus e para recovery após restart. Sem essa tabela, um restart durante convoy ativo deixaria `trucker_convoy_jobs.status = 'active'` indefinidamente sem caminho de cleanup.

### Campo adicionado em `trucker_jobs`

```sql
ALTER TABLE trucker_jobs
    ADD COLUMN IF NOT EXISTS convoy_id VARCHAR(36) NULL DEFAULT NULL;
```

### Campo adicionado em `TruckSimulationService` (SimState)

```lua
-- server/services/truck_simulation_service.lua — SimState por player
SimState[src] = {
    -- campos existentes:
    fuel, fatigue, vehicleWasMoving, currentPlate, lastSyncTime,
    -- NOVO (v9):
    coords = vector3(0, 0, 0),   -- última posição conhecida (sync a cada syncInterval)
}

-- syncSimulation payload do cliente passa a incluir coords:
-- { fuel, fatigue, vehicleWasMoving, plate, coords = { x, y, z } }
-- Getter público:
TruckSimulationService.GetCoords(src)  -- retorna vector3 ou nil
```

**Alteração em `client/hud.client.lua`:** `SyncToServer()` adiciona `coords = GetEntityCoords(SimState.currentVehicle)` ao payload quando `isTruck = true`.

### Cache em memória (VP_Trucker)

```lua
VP_Trucker.Parties = {}
-- [partyId] = {
--     leader       = citizenid,
--     members      = { [citizenid] = { src = src } },  -- src = nil se desconectado (entrada permanece para grace period)
--     graceTimers  = { [citizenid] = timerHandle },    -- ClearTimeout ao reconectar
--     maxSize      = number,
--     status       = 'forming' | 'active',
-- }

VP_Trucker.Convoys = {}
-- [convoyId] = {
--     partyId        = string,
--     memberJobs     = { [citizenid] = jobId },   -- em memória para acesso rápido
--     graceTimers    = { [citizenid] = threadHandle },
--     broadcastTimer = intervalHandle,             -- SetInterval para positionBroadcast
--     activeCount    = number,
--     totalCount     = number,
-- }
-- Nota: estado canônico por slot está em trucker_convoy_members (DB).
-- Em caso de restart, LoadFromDB() em ConvoyService reconstrói convoy ativos.

VP_Trucker.PlayerParties = {}
-- [citizenid] = partyId  (lookup reverso)
```

---

## Serviços de Servidor

### `server/services/party_service.lua`

Global: `PartyService`

| Método | Comportamento |
|---|---|
| `Create(src)` | Gera UUID, cria registro em DB, popula cache, retorna partyId |
| `Invite(src, targetSrc)` | Valida: src está em party e é líder; target não está em party; party não está cheia. Dispara `AUST_trucker:client:partyInvite` no target |
| `Accept(src, partyId)` | Adiciona membro ao cache e DB; broadcast `partyUpdate` para todos os membros |
| `Leave(src)` | Remove membro; se líder, transfere para o próximo membro online; se party vazia, dissolve; se convoy ativo, chama `ConvoyService.MemberAbandon` |
| `Disband(src)` | Só líder; marca todos os membros como sem party; cancela convoy ativo se houver; `status = 'disbanded'` no DB |
| `GetPartyBySrc(src)` | Lookup via `VP_Trucker.PlayerParties[citizenid]` |
| `OnPlayerDisconnect(src, citizenid)` | `citizenid` capturado no momento do disconnect (não no timer). Marca `members[cid].src = nil`; inicia grace timer 3 min (180s) que fecha sobre `citizenid`; se expirar, chama `Leave` passando `citizenid` diretamente — NÃO usa `src` stale |
| `OnPlayerReconnect(src, citizenid)` | Restaura `members[citizenid].src = src`; `ClearTimeout(party.graceTimers[citizenid])`; `party.graceTimers[citizenid] = nil`; notifica party |

**Implementação do grace timer:**
```lua
-- OnPlayerDisconnect recebe citizenid capturado ANTES de src ficar stale
function PartyService.OnPlayerDisconnect(src, citizenid)
    local partyId = VP_Trucker.PlayerParties[citizenid]
    if not partyId then return end
    local party = VP_Trucker.Parties[partyId]
    if not party then return end
    -- Marca src como nil MAS mantém a entrada (sub-table) para o grace period
    -- NUNCA usar party.members[citizenid] = nil aqui — isso apagaria o membro
    -- e OnPlayerReconnect não conseguiria restaurar sem crash
    if party.members[citizenid] then
        party.members[citizenid].src = nil
    end

    -- Timer fecha sobre citizenid (string), não sobre src (inválido após drop)
    local timer = SetTimeout(Config.Party.gracePeriod * 1000, function()
        PartyService.LeaveByIdentifier(partyId, citizenid)
    end)
    -- SEMPRE armazena em party.graceTimers — funciona para party em 'forming' E em convoy ativo
    party.graceTimers[citizenid] = timer
end
```

### `server/services/convoy_service.lua`

Global: `ConvoyService`

`convoy_service.lua` carrega APÓS `job_service.lua` no fxmanifest (depende de `JobService.GenerateConvoyBatch`).

| Método | Comportamento |
|---|---|
| `Start(partyId)` | Valida ≥2 membros ativos; cria registro em `trucker_convoy_jobs` primeiro (FK obrigatória antes dos membros); chama `JobService.GenerateConvoyBatch(partyId, memberCids)` que insere os jobs e rows de `trucker_convoy_members`; popula cache; chama `StartPositionBroadcast(convoyId)`; manda `convoyStarted` para todos |
| `StartPositionBroadcast(convoyId)` | `SetInterval(Config.Party.positionBroadcastInterval, fn)` — coleta `TruckSimulationService.GetCoords(src)` para cada membro ativo, envia `TriggerClientEvent('AUST_trucker:client:convoyPositions', memberSrc, positions)` para cada membro. Handle armazenado em `VP_Trucker.Convoys[convoyId].broadcastTimer` |
| `StopPositionBroadcast(convoyId)` | `ClearInterval(broadcastTimer)` — chamado quando `activeCount == 0` (convoy concluído/cancelado) |
| `MemberComplete(src, jobId, payload)` | Atualiza `trucker_convoy_members.status = 'completed'` no DB; decrementa `activeCount`; se `activeCount == 0` → calcula bônus final e paga todos; caso contrário aguarda |
| `MemberAbandon(partyId, citizenid)` | Atualiza `trucker_convoy_members.status = 'abandoned'` no DB; decrementa `activeCount`; recalcula `bonus_mult` proporcional |
| `Broadcast(src, message)` | Recebe mensagem; obtém coords do sender via `TruckSimulationService.GetCoords(src)`; itera membros do party; envia `AUST_trucker:client:cbMessage` apenas para membros com coords dentro de 500m |
| `GetConvoyByParty(partyId)` | Lookup em cache |
| `LoadFromDB()` | Chamado no startup: busca convoys `status='active'` no DB, reconstrói cache, marca slots orphaned (sem job ativo) como `abandoned` |

**Cálculo de bônus proporcional:**
```lua
local completedFraction = completedCount / totalCount
local finalMult = 1.0 + (0.5 * completedFraction)  -- 1.0 a 1.5
```

### `server/services/job_service.lua` — alteração

`GenerateConvoyBatch` pertence a `JobService` (é geração de job). Chamado por `ConvoyService.Start`.

```lua
-- Assinatura canônica:
-- JobService.GenerateConvoyBatch(convoyId, partyId, memberCids) → { [citizenid] = jobId }
-- convoyId já criado por ConvoyService.Start (FK obrigatória em trucker_convoy_members)
-- Reutiliza lógica demand-weighted de GenerateOne, fixando mesmo origin_id/dest_id.
-- Trailers: cada membro recebe trailer aleatório compatível com origin.
-- Para cada membro (sequencialmente, NÃO em batch):
--   1. INSERT INTO trucker_jobs → captura jobId retornado (auto-increment)
--   2. INSERT INTO trucker_convoy_members (convoy_id, citizenid, job_id, status='pending')
-- Retorna { [citizenid] = jobId } para ConvoyService popular o cache.
```

### Alterações em `server/events.lua`

**`playerDropped`** — adicionar ao handler existente (NÃO criar novo handler):
```lua
-- Captura citizenid ANTES de src ficar stale
AddEventHandler('playerDropped', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    local citizenid = Player and Player.PlayerData.citizenid
    TruckSimulationService.OnPlayerDropped(src)  -- já existe
    if citizenid then
        PartyService.OnPlayerDisconnect(src, citizenid)
    end
end)
```

**`QBCore:Server:OnPlayerLoaded`** — adicionar ao handler existente:
```lua
AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    DB_UpsertPlayerStats(citizenid)             -- já existe
    TruckSimulationService.OnPlayerLoaded(src)  -- já existe
    PartyService.OnPlayerReconnect(src, citizenid)  -- NOVO
end)
```

### `server/callbacks.lua` — novos callbacks

- `partyCreate` — cria party para o jogador (valida que não está em outro party)
- `partyInvite` — convida jogador pelo nome (busca em `GetPlayers()`, match por `GetPlayerName`)
- `partyAccept` — aceita convite (valida partyId ainda válido)
- `partyLeave` — sai do party
- `partyDisband` — dissolve party (valida que é líder)
- `convoyStart` — inicia convoy (valida líder + ≥2 membros)
- `cbRadioSend` — relay de mensagem CB radio via `ConvoyService.Broadcast`

---

## Cliente

### `client/convoy.client.lua` (novo arquivo)

**Estado local:**
```lua
local localCitizenId = nil  -- populado no OnPlayerLoaded

local ConvoyState = {
    partyId      = nil,
    isLeader     = false,
    members      = {},     -- { citizenid, name, status }
    convoyActive = false,
    isInTruck    = false,  -- atualizado via truckStateChanged de hud.client.lua
    gpsBlocked   = false,
    memberBlips  = {},     -- { [citizenid] = blipHandle }
    cbLog        = {},     -- últimas 5 mensagens { sender, text, timestamp }
}
```

**Captura do citizenid local:**
```lua
-- QBX popula PlayerData no evento abaixo
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    localCitizenId = QBX.PlayerData.citizenid
end)
```

**Rastreamento de isTruck via named event de `hud.client.lua`:**
```lua
-- hud.client.lua dispara este evento ao detectar mudança de isTruck no detection thread
AddEventHandler('AUST_trucker:client:truckStateChanged', function(isTruck)
    ConvoyState.isInTruck = isTruck
end)
```
**Alteração em `hud.client.lua`:** na thread de detecção de veículo (1s), ao mudar `SimState.isTruck`, disparar:
```lua
TriggerEvent('AUST_trucker:client:truckStateChanged', isTruck)
```
(apenas quando o valor mudar, não a cada tick)

**GPS Suppression (Blind Driver) — mecanismo único:**
```lua
-- client.lua dispara este evento após criar o blip de destino em StartJob()
AddEventHandler('AUST_trucker:client:jobStartedConvoy', function(blipHandle)
    if not ConvoyState.convoyActive then return end
    if not ConvoyState.isInTruck then return end  -- escorts mantêm GPS
    RemoveBlip(blipHandle)
    ConvoyState.gpsBlocked = true
    -- exibe aviso persistente no HUD via DrawText2d em thread separada
end)

RegisterNetEvent('AUST_trucker:client:jobCompleted', function()
    ConvoyState.gpsBlocked = false
end)
```

**Alteração em `client.lua`:** em `StartJob()`, após `AddBlipForCoord` do destino:
```lua
TriggerEvent('AUST_trucker:client:jobStartedConvoy', deliveryBlip)
```

**CB Radio HUD:**
- Thread a cada 500ms: se `#ConvoyState.cbLog > 0`, renderiza as últimas 5 mensagens via `DrawText2d` (canto inferior esquerdo, posição configurável)
- Mensagens expiram após `Config.Party.cbMessageDuration` segundos
- Tecla `Config.Party.cbRadioKey` (default `Z`) abre `lib.inputDialog`; ao confirmar, chama callback `cbRadioSend`

**Convoy Blips:**
```lua
RegisterNetEvent('AUST_trucker:client:convoyPositions', function(positions)
    -- positions = { [citizenid] = { x, y, z, name, isTruck } }
    for cid, pos in pairs(positions) do
        if cid ~= localCitizenId then  -- usa citizenid local capturado no OnPlayerLoaded
            local blip = ConvoyState.memberBlips[cid]
            if not blip then
                blip = AddBlipForCoord(pos.x, pos.y, pos.z)
                SetBlipSprite(blip, pos.isTruck and 477 or 1)
                SetBlipColour(blip, 5)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(pos.name)
                EndTextCommandSetBlipName(blip)
                ConvoyState.memberBlips[cid] = blip
            else
                SetBlipCoords(blip, pos.x, pos.y, pos.z)
            end
        end
    end
end)
```

**Party Invite:**
```lua
RegisterNetEvent('AUST_trucker:client:partyInvite', function(data)
    -- data = { partyId, leaderName }
    local confirm = lib.alertDialog({
        header   = 'Convite de Convoy',
        content  = data.leaderName .. ' convidou você para um convoy.',
        centered = true,
        cancel   = true,
    })
    if confirm == 'confirm' then
        lib.callback.await('AUST_trucker:partyAccept', false, data.partyId)
    end
end)
```

### fxmanifest — client_scripts

```
client/client.lua
client/hud.client.lua
client/convoy.client.lua    ← após hud.client (usa truckStateChanged de hud)
client/industries.client.lua
client/industries_npc.client.lua
```

### fxmanifest — server_scripts (ordem correta com novos serviços)

```
@oxmysql/lib/MySQL.lua
server/main.lua
server/database.lua
server/services/company_service.lua
server/services/party_service.lua           ← novo; sem dependências de outros services
server/services/loan_service.lua
server/services/repo_service.lua            ← após loan_service
server/services/economy_service.lua
server/services/industry_ownership_service.lua
server/services/industry_service.lua
server/services/progression_service.lua
server/services/job_service.lua             ← convoy_service depende deste
server/services/convoy_service.lua          ← APÓS job_service (usa JobService.GenerateConvoyBatch)
server/services/truck_simulation_service.lua
server/exports.lua
server/callbacks.lua
server/events.lua
```

---

## NUI (React + TypeScript)

### Novos arquivos

**`html/src/types/index.ts`** — adicionar:
```typescript
export interface PartyMember {
    citizenid: string
    name:      string
    status:    'active' | 'abandoned'
    isLeader:  boolean
}

export interface Party {
    partyId:      string
    isLeader:     boolean
    members:      PartyMember[]
    convoyActive: boolean
    maxSize:      number
}
```

**`html/src/stores/usePartyStore.ts`:**
```typescript
interface PartyStore {
    party:           Party | null
    setParty:        (party: Party | null) => void
    updateMembers:   (members: PartyMember[]) => void
    setConvoyActive: (active: boolean) => void
}
```

**`html/src/components/convoy/PartyPanel.tsx`:**
- Lista de membros com badge de status (verde ativo, cinza abandonado, coroa para líder)
- Input de busca de jogador + botão "Convidar"
- Botão "Iniciar Convoy" — habilitado apenas para líder com ≥2 membros ativos
- Botão "Sair" / "Dissolver" (líder)
- Indicador de convoy ativo com status de cada membro

### Alterações em arquivos existentes

**`html/src/hooks/useNUI.ts`:**
- Case `'partyUpdate'` → `setParty(event.data.party)`
- Case `'convoyStarted'` → `setConvoyActive(true)`
- Case `'convoyEnded'` → `setConvoyActive(false)`

**`html/src/App.tsx`:**
- Nova tab "Convoy" com ícone de rádio
- Renderiza `<PartyPanel />` quando ativa

---

## Config

```lua
Config.Party = {
    maxSize                  = 6,
    cbRadioKey               = 'Z',    -- tecla para abrir input do rádio
    cbRadioRange             = 500.0,  -- metros
    cbMessageDuration        = 8,      -- segundos antes de sumir do HUD
    gracePeriod              = 180,    -- segundos de grace ao desconectar
    bonusMultiplier          = 1.5,    -- multiplicador de pagamento em convoy
    positionBroadcastInterval = 3000,  -- ms entre updates de blip
}
```

---

## Fluxo Completo (Happy Path)

```
Jogador A cria party (UI) → PartyService.Create()
A convida B e C → partyInvite disparado nos clientes
B e C aceitam → partyUpdate broadcast para todos

A (líder) clica "Iniciar Convoy" → ConvoyService.Start()
  → JobService.GenerateConvoyBatch: origin Sandy Shores, dest La Mesa, 3 trailers diferentes
  → 3 jobs inseridos no DB com convoy_id
  → 3 rows em trucker_convoy_members (status='pending')
  → convoyStarted enviado para A, B, C

B e C pegam seus trailers, aceitam seus jobs (status → 'active')
  → jobStartedConvoy dispara em cada cliente
  → convoy.client.lua: quem está em truck → gpsBlocked = true, blip removido
  → Escorts (isInTruck = false) mantêm GPS

A (motorista): "Entrem na rodovia 1, depois direita"  [tecla Z]
  → cbRadioSend → ConvoyService.Broadcast
  → Coords de A via TruckSimulationService.GetCoords(src)
  → B e C recebem cbMessage se dentro de 500m

Todos chegam ao destino → MemberComplete() para cada um
  → trucker_convoy_members.status = 'completed'
  → activeCount chega a 0 → bonus_mult = 1.5 aplicado para todos
  → Cada um recebe base_payment × 1.5
  → convoyEnded broadcast → party continua ativa para novo convoy
```

---

## Arquivos Modificados / Criados

| Arquivo | Ação |
|---|---|
| `import.sql` | + `trucker_parties`, `trucker_convoy_jobs`, `trucker_convoy_members`, + campo `convoy_id` em `trucker_jobs` |
| `sql/update_convoy_v9.sql` | migração v8→v9 (ALTER TABLE + CREATE TABLE IF NOT EXISTS) |
| `config/config.lua` | + `Config.Party` block |
| `server/main.lua` | + `VP_Trucker.Parties`, `VP_Trucker.Convoys`, `VP_Trucker.PlayerParties` |
| `server/database.lua` | + `DB_Party*`, `DB_Convoy*`, `DB_ConvoyMember*` functions |
| `server/services/party_service.lua` | CRIAR — global `PartyService` |
| `server/services/convoy_service.lua` | CRIAR — global `ConvoyService`; carrega APÓS job_service |
| `server/services/job_service.lua` | + `JobService.GenerateConvoyBatch()` |
| `server/services/truck_simulation_service.lua` | + campo `coords` em SimState + `GetCoords(src)` |
| `server/events.lua` | + `PartyService.OnPlayerDisconnect` em playerDropped existente; + `PartyService.OnPlayerReconnect` em OnPlayerLoaded existente |
| `server/callbacks.lua` | + 7 callbacks party/convoy + `cbRadioSend` |
| `client/hud.client.lua` | + coords em `SyncToServer()`; + `TriggerEvent('truckStateChanged')` ao mudar isTruck |
| `client/convoy.client.lua` | CRIAR |
| `client/client.lua` | mínimo: `TriggerEvent('jobStartedConvoy', blipHandle)` em `StartJob()` |
| `html/src/types/index.ts` | + `Party`, `PartyMember` |
| `html/src/stores/usePartyStore.ts` | CRIAR |
| `html/src/components/convoy/PartyPanel.tsx` | CRIAR |
| `html/src/hooks/useNUI.ts` | + party/convoy cases |
| `html/src/App.tsx` | + aba Convoy |
| `fxmanifest.lua` | + novos arquivos na ordem correta, versão 9.0.0 |
| `CHANGELOG.md` | entrada v9.0.0 |
