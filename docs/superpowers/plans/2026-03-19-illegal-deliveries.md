# Fase 3B — Illegal Deliveries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a parallel illegal cargo delivery system with police/SALA alerts and a seizure mechanic, built on top of the existing `trucker_jobs` table via a single `illegal_type` column.

**Architecture:** One new column (`illegal_type VARCHAR(20) NULL`) on `trucker_jobs` identifies illegal jobs (NULL = legal). A new `IllegalService` global handles generation, alerts, seizure and completion. `JobService.Complete` gets a two-line hook after the convoy hook. All alert broadcast and target registration use FiveM's `-1` broadcast target to ensure every client (including cops) participates.

**Tech Stack:** Lua 5.4 (lua54='yes'), QBX (qbx_core), ox_lib, ox_target, oxmysql, FiveM native APIs.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `sql/update_illegal_v9_1.sql` | CREATE | Migration: add `illegal_type` column + expand infraction ENUM |
| `import.sql` | MODIFY | Add `illegal_type` to CREATE TABLE + expand ENUM |
| `config/config.lua` | MODIFY | Add `Config.IllegalJobs` block |
| `server/database.lua` | MODIFY | Add `DB_InsertIllegalJob` + `DB_ExpireJob` |
| `server/main.lua` | MODIFY | Add `IllegalTargets = {}` to `VP_Trucker` + `math.randomseed` |
| `server/services/illegal_service.lua` | CREATE | `IllegalService` global — Generate, BroadcastAlert, RegisterSeizureTarget, ClearSeizureTarget, Seize, OnComplete |
| `server/services/job_service.lua` | MODIFY | Two-line illegal hook in `JobService.Complete` |
| `server/events.lua` | MODIFY | Add `seizeIllegalCargo` and `illegalRegisterPlate` handlers |
| `server/callbacks.lua` | MODIFY | Add `getIllegalJobs` and `acceptIllegalJob` callbacks |
| `client/hud.client.lua` | MODIFY | Pass plate in `truckStateChanged` event (line ~182) |
| `client/client.lua` | MODIFY | Add `AddEventHandler('AUST_trucker:client:triggerComplete', CompleteJob)` after `CompleteJob` declaration |
| `client/illegal.client.lua` | CREATE | Contact zones, delivery zones, state, events, polling thread |
| `fxmanifest.lua` | MODIFY | v9.1.0 + new files in correct load order |
| `CHANGELOG.md` | MODIFY | v9.1.0 entry |

---

## Task 1: Schema

**Files:**
- Create: `sql/update_illegal_v9_1.sql`
- Modify: `import.sql`

- [ ] **Step 1: Create migration file**

Create `sql/update_illegal_v9_1.sql`:
```sql
-- AUST_trucker — migração v9→v9.1 (Fase 3B — Illegal Deliveries)
ALTER TABLE trucker_jobs
    ADD COLUMN IF NOT EXISTS illegal_type VARCHAR(20) NULL DEFAULT NULL;

-- Adicionar 'illegal_seizure' ao ENUM de infraction_type
ALTER TABLE trucker_infractions
    MODIFY infraction_type ENUM('overload','no_manifest','expired_manifest','dangerous_cargo','illegal_seizure') NOT NULL;
```

- [ ] **Step 2: Update import.sql — add `illegal_type` to trucker_jobs CREATE TABLE**

In `import.sql`, find the `CREATE TABLE trucker_jobs` block. After the line `convoy_id VARCHAR(36) NULL DEFAULT NULL,`, add:
```sql
    illegal_type        VARCHAR(20)     NULL DEFAULT NULL,
```

- [ ] **Step 3: Update import.sql — expand infraction ENUM**

In `import.sql`, find `CREATE TABLE trucker_infractions`. Change:
```sql
    infraction_type ENUM('overload','no_manifest','expired_manifest','dangerous_cargo') NOT NULL,
```
to:
```sql
    infraction_type ENUM('overload','no_manifest','expired_manifest','dangerous_cargo','illegal_seizure') NOT NULL,
```

- [ ] **Step 4: Verify both files**

Check that:
- `sql/update_illegal_v9_1.sql` has two ALTER statements
- `import.sql` trucker_jobs has `illegal_type` after `convoy_id`
- `import.sql` trucker_infractions ENUM includes `'illegal_seizure'`

- [ ] **Step 5: Commit**
```bash
cd "E:/Users/Vinicius/Downloads/txData/Qbox_753251.base/resources/[standalone]/AUST_trucker"
git add sql/update_illegal_v9_1.sql import.sql
git commit -m "feat(3b): schema — illegal_type column + illegal_seizure infraction ENUM"
```

---

## Task 2: Config

**Files:**
- Modify: `config/config.lua`

- [ ] **Step 1: Read config/config.lua to find where to append**

Read `config/config.lua` to find the end of the file and verify `Config.JobGeneration.distanceMultiplier` exists (used in the payment formula).

- [ ] **Step 2: Append `Config.IllegalJobs` at end of config.lua**

Add at the end of `config/config.lua`:
```lua
-- =============================================
-- FASE 3B — ILLEGAL DELIVERIES
-- =============================================
Config.IllegalJobs = {
    -- Job names dos agentes que recebem alertas
    policeJob = 'police',
    salaJob   = 'sala',

    -- Multiplicadores de pagamento por tipo.
    -- Fórmula: base_payment = floor(dist_km × Config.JobGeneration.distanceMultiplier × paymentMultipliers[type])
    paymentMultipliers = {
        contraband = 2.0,
        animals    = 2.5,
        minerals   = 2.3,
        weapons    = 3.0,
        drugs      = 2.8,
    },

    -- Multas de apreensão por tipo (deduzidas do cash do motorista)
    seizureFines = {
        contraband = 5000,
        animals    = 12000,
        minerals   = 8000,
        weapons    = 20000,
        drugs      = 15000,
    },

    -- Textos de alerta por tipo
    alertLabels = {
        contraband = 'contrabando',
        animals    = 'tráfico de animais silvestres',
        minerals   = 'extração/desvio mineral ou petróleo',
        weapons    = 'armas e munições',
        drugs      = 'entorpecentes',
    },

    -- Tipos que acionam SALA além da LSPD
    salaTypes = { 'animals', 'minerals' },

    -- Tipos com alerta de alta prioridade para LSPD
    highPriorityTypes = { 'weapons', 'drugs' },

    -- Pontos de contato (onde o jogador vai pessoalmente para pegar missão)
    contacts = {
        {
            id     = 'porto_sul',
            label  = 'Contato do Porto',
            area   = 'Porto de LS',
            coords = vector3(1167.0, -3043.0, 5.9),
            radius = 3.0,
            cargo  = { 'contraband', 'minerals' },
        },
        {
            id     = 'paleto_floresta',
            label  = 'Contato Rural',
            area   = 'Zona Rural — Paleto',
            coords = vector3(-357.0, 6145.0, 31.5),
            radius = 3.0,
            cargo  = { 'animals', 'minerals' },
        },
        {
            id     = 'strawberry_galpao',
            label  = 'Contato do Galpão',
            area   = 'Strawberry — LS',
            coords = vector3(-1183.0, -1573.0, 4.0),
            radius = 3.0,
            cargo  = { 'drugs', 'weapons' },
        },
        {
            id     = 'sandy_deserto',
            label  = 'Contato do Deserto',
            area   = 'Sandy Shores',
            coords = vector3(1956.0, 3740.0, 32.6),
            radius = 3.0,
            cargo  = { 'drugs', 'animals', 'weapons' },
        },
        {
            id     = 'palomino_bay',
            label  = 'Contato da Baía',
            area   = 'Palomino Bay',
            coords = vector3(1389.0, -2067.0, 52.0),
            radius = 3.0,
            cargo  = { 'contraband', 'weapons' },
        },
    },

    -- Pontos de entrega clandestinos
    deliveries = {
        {
            id      = 'del_north_ls',
            area    = 'Norte de LS',
            coords  = vector3(138.0, -1744.0, 29.3),
            radius  = 8.0,
            accepts = { 'contraband', 'drugs', 'weapons' },
        },
        {
            id      = 'del_sandy_caves',
            area    = 'Cavernas — Sandy',
            coords  = vector3(2580.0, 3517.0, 53.7),
            radius  = 8.0,
            accepts = { 'animals', 'minerals' },
        },
        {
            id      = 'del_grapeseed',
            area    = 'Grapeseed',
            coords  = vector3(1710.0, 4922.0, 42.1),
            radius  = 8.0,
            accepts = { 'animals', 'minerals', 'contraband' },
        },
        {
            id      = 'del_vespucci',
            area    = 'Vespucci Canals',
            coords  = vector3(-789.0, -1607.0, 0.3),
            radius  = 8.0,
            accepts = { 'drugs', 'weapons', 'contraband' },
        },
    },
}
```

- [ ] **Step 3: Verify**

Read the bottom of `config/config.lua`. Confirm `Config.IllegalJobs` is present and all 5 contacts and 4 deliveries are there.

- [ ] **Step 4: Commit**
```bash
git add config/config.lua
git commit -m "feat(3b): config — Config.IllegalJobs with contacts, deliveries, multipliers"
```

---

## Task 3: DB Function + Cache

**Files:**
- Modify: `server/database.lua`
- Modify: `server/main.lua`

- [ ] **Step 1: Read server/database.lua to find where DB_InsertJob is defined**

Read `server/database.lua` and find `function DB_InsertJob`. Add `DB_InsertIllegalJob` directly after it.

- [ ] **Step 2: Add DB_InsertIllegalJob to database.lua**

After `DB_InsertJob`, add:
```lua
-- Insere job ilegal (com illegal_type preenchido, convoy_id sempre NULL)
function DB_InsertIllegalJob(job, illegalType)
    return MySQL.insert.await(
        [[INSERT INTO trucker_jobs
          (id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at, illegal_type)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)]],
        { job.id, job.origin_id, job.dest_id, job.cargo_item, job.trailer_model,
          job.base_payment, job.distance, job.expires_at, illegalType }
    )
end
```

Note: `convoy_id` is intentionally omitted — it defaults to NULL. `DB_GetActiveJobByPlayer` uses `SELECT *` so it will return `illegal_type` automatically once the migration runs — no change needed to that function.

- [ ] **Step 3: Add DB_ExpireJob to database.lua**

`DB_AbandonJob` resets a job to `'available'` (if not yet expired), which would push seized illegal jobs back into the job board. Illegal job seizures must set status to `'expired'` unconditionally. Add directly after `DB_InsertIllegalJob`:

```lua
-- Força expiração de um job específico (usado na apreensão de cargo ilegal)
-- Não usa DB_AbandonJob pois este retorna o job para 'available' se não vencido
function DB_ExpireJob(jobId)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'expired' WHERE id = ?",
        { jobId }
    )
end
```

- [ ] **Step 4: Add IllegalTargets to VP_Trucker in main.lua**

In `server/main.lua`, find:
```lua
    PlayerParties   = {},   -- citizenid → partyId (lookup reverso)
}
```
Replace with:
```lua
    PlayerParties   = {},   -- citizenid → partyId (lookup reverso)
    -- Fase 3B: Illegal Deliveries
    IllegalTargets  = {},   -- [plate] = { src, jobId, citizenid, illegalType }
}
```

- [ ] **Step 5: Add math.randomseed to main.lua**

In `server/main.lua`, find the `MySQL.ready(function()` block. At the very top of that callback (before `LoadCompanies()`), add:
```lua
        math.randomseed(os.time())
```
Without this, Lua 5.4 uses a fixed seed of 0 on every server restart, making `math.random` produce identical sequences (same delivery area for every player on every restart).

- [ ] **Step 6: Verify**

Read `server/database.lua` and confirm both `DB_InsertIllegalJob` and `DB_ExpireJob` are present.
Read `server/main.lua` and confirm `IllegalTargets = {}` is in `VP_Trucker` and `math.randomseed(os.time())` is inside `MySQL.ready`.

- [ ] **Step 7: Commit**
```bash
git add server/database.lua server/main.lua
git commit -m "feat(3b): DB_InsertIllegalJob + DB_ExpireJob + IllegalTargets cache + math.randomseed"
```

---

## Task 4: IllegalService

**Files:**
- Create: `server/services/illegal_service.lua`

This is the largest file. It has 6 methods. Write it in full — no stubs.

- [ ] **Step 1: Create server/services/illegal_service.lua**

```lua
-- AUST_trucker — server/services/illegal_service.lua
-- Fase 3B: lógica de jobs ilegais (global — lua54 sem local)

IllegalService = {}

-- Helper: calcula distância 2D entre dois vector3, retorna km (mesma lógica de job_service.lua)
local function CalcIllegalDist(c1, c2)
    local dx = c1.x - c2.x
    local dy = c1.y - c2.y
    return math.sqrt(dx*dx + dy*dy) / 1000.0
end

-- Helper: verifica se illegalType está em uma lista
local function InList(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Gera e aceita um job ilegal para o jogador.
-- Retorna { jobId, destCoords, destArea, cargoLabel, payment } ou nil se inválido.
function IllegalService.Generate(contactId, illegalType, requesterSrc)
    local Player = exports.qbx_core:GetPlayer(requesterSrc)
    if not Player then return nil end
    local cid = Player.PlayerData.citizenid

    -- Validar contactId
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if not contact then return nil end

    -- Validar illegalType para este contato
    if not InList(contact.cargo, illegalType) then return nil end

    -- Verificar se jogador já tem job ativo
    if DB_GetActiveJobByPlayer(cid) then return nil end

    -- Selecionar destino compatível aleatório
    local compatible = {}
    for _, d in ipairs(Config.IllegalJobs.deliveries) do
        if InList(d.accepts, illegalType) then
            table.insert(compatible, d)
        end
    end
    if #compatible == 0 then return nil end
    local delivery = compatible[math.random(#compatible)]

    -- Calcular pagamento: dist × distanceMultiplier × paymentMultiplier
    local dist     = CalcIllegalDist(contact.coords, delivery.coords)
    local mult     = Config.IllegalJobs.paymentMultipliers[illegalType] or 1.0
    local payment  = math.floor(dist * Config.JobGeneration.distanceMultiplier * mult)
    payment        = math.min(payment, Config.General.payment.maxPayment)

    -- Calcular expiração (reutiliza mesma lógica de CalcExpiresAt via os.time)
    local expiry = os.time() + 3600  -- 1 hora para jobs ilegais

    local job = {
        id            = ('ilg_%d_%d'):format(os.time(), math.random(10000, 99999)),
        origin_id     = contactId,
        dest_id       = delivery.id,
        cargo_item    = illegalType,
        trailer_model = 'tr2',  -- trailer genérico; jogador usa o que tiver
        base_payment  = payment,
        distance      = dist,
        expires_at    = expiry,
    }

    DB_InsertIllegalJob(job, illegalType)
    DB_AcceptJob(job.id, cid, nil)

    return {
        jobId      = job.id,
        destCoords = delivery.coords,
        destArea   = delivery.area,
        cargoLabel = Config.IllegalJobs.alertLabels[illegalType] or illegalType,
        payment    = payment,
    }
end

-- Envia alerta de texto para cops LSPD e, se aplicável, para agentes SALA.
function IllegalService.BroadcastAlert(src, illegalType, area)
    local cfg         = Config.IllegalJobs
    local isHighPrio  = InList(cfg.highPriorityTypes, illegalType)
    local isSalaType  = InList(cfg.salaTypes, illegalType)
    local label       = cfg.alertLabels[illegalType] or illegalType
    local prefix      = isHighPrio and '[LSPD ⚠] ' or '[LSPD] '
    local msg         = ('%sAlerta: suspeita de %s na área de %s'):format(prefix, label, area)

    for _, playerId in ipairs(GetPlayers()) do
        local pid    = tonumber(playerId)
        local P      = exports.qbx_core:GetPlayer(pid)
        if P then
            local jobName = P.PlayerData.job and P.PlayerData.job.name or ''
            if jobName == cfg.policeJob then
                lib.notify(pid, { title = 'Alerta Policial', description = msg,
                    type = isHighPrio and 'error' or 'warning', duration = 10000 })
            end
            if isSalaType and jobName == cfg.salaJob then
                lib.notify(pid, { title = 'Alerta SALA',
                    description = ('[SALA] Alerta ambiental: %s — área: %s'):format(label, area),
                    type = 'warning', duration = 10000 })
            end
        end
    end
end

-- Registra a placa do caminhão como alvo de apreensão e broadcast para todos os clients.
-- Chamado pelo handler de 'AUST_trucker:illegalRegisterPlate'.
function IllegalService.RegisterSeizureTarget(src, jobId, plate, illegalType)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    VP_Trucker.IllegalTargets[plate] = {
        src         = src,
        jobId       = jobId,
        citizenid   = cid,
        illegalType = illegalType,
    }

    -- Broadcast para TODOS os clients — cops e motorista registram o ox_target localmente
    TriggerClientEvent('AUST_trucker:client:illegalJobStarted', -1, {
        plate     = plate,
        driverSrc = src,
    })
end

-- Remove o alvo de apreensão e broadcast de limpeza para todos os clients.
function IllegalService.ClearSeizureTarget(plate)
    -- Ler ANTES de nil para capturar driverSrc
    local target = VP_Trucker.IllegalTargets[plate]
    VP_Trucker.IllegalTargets[plate] = nil

    TriggerClientEvent('AUST_trucker:client:illegalJobEnded', -1, {
        plate     = plate,
        driverSrc = target and target.src or nil,
    })
end

-- Processa a apreensão da carga por um cop.
-- Validação server-side é a única proteção — rejeita silenciosamente se inválido.
function IllegalService.Seize(copSrc, plate)
    local CopPlayer = exports.qbx_core:GetPlayer(copSrc)
    if not CopPlayer then return end

    -- Validar: cop tem job correto
    local copJob = CopPlayer.PlayerData.job and CopPlayer.PlayerData.job.name or ''
    local cfg    = Config.IllegalJobs
    if copJob ~= cfg.policeJob and copJob ~= cfg.salaJob then return end

    -- Validar: placa registrada como alvo
    local target = VP_Trucker.IllegalTargets[plate]
    if not target then return end

    -- Expirar job no DB — NÃO usar DB_AbandonJob (este retorna jobs ativos para 'available'
    -- se expires_at ainda for futuro, o que colocaria o job ilegal de volta no quadro de jobs)
    DB_ExpireJob(target.jobId)

    -- Deduzir multa do motorista em cash
    local fine        = cfg.seizureFines[target.illegalType] or 5000
    local TruckPlayer = exports.qbx_core:GetPlayer(target.src)
    if TruckPlayer then
        TruckPlayer.Functions.RemoveMoney('cash', fine, 'aurp-trucker-seizure')
    end

    -- Log de infração ('illegal_seizure' adicionado ao ENUM pela migração)
    local copId  = CopPlayer.PlayerData.citizenid
    local desc   = ('Carga apreendida por %s — tipo: %s'):format(copId, target.illegalType)
    DB_RecordInfraction(target.citizenid, target.jobId, 'illegal_seizure', desc, copId)

    -- Notificar motorista e cop
    TriggerClientEvent('AUST_trucker:client:cargoSeized', target.src, {
        fine        = fine,
        illegalType = target.illegalType,
    })
    TriggerClientEvent('AUST_trucker:client:seizureSuccess', copSrc, {
        illegalType = target.illegalType,
    })

    -- Limpar alvo (broadcast para remover ox_target em todos os clients)
    IllegalService.ClearSeizureTarget(plate)
end

-- Conclusão de um job ilegal — chamado por JobService.Complete quando illegal_type ~= nil.
-- Não aplica skillMult de empresa nem companyMult. Pagamento em cash.
function IllegalService.OnComplete(src, Player, citizenId, activeJob, payload)
    -- Calcular tempo
    local elapsed  = payload.deliveryTime or 9999
    local bonus    = Config.JobGeneration.timeBonus
    local timeMult = bonus.slow.multiplier
    if elapsed <= bonus.fast.time then
        timeMult = bonus.fast.multiplier
    elseif elapsed <= bonus.normal.time then
        timeMult = bonus.normal.multiplier
    end

    -- Integridade da carga
    local rawIntegrity  = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
    local integrityMult = math.max(Config.TruckSimulation.Cargo.MinPaymentRate, rawIntegrity / 100)

    -- Pagamento: sem skillMult, sem companyMult
    local payment = math.floor(activeJob.base_payment * timeMult * integrityMult)

    -- Pagar em cash (não banco)
    Player.Functions.AddMoney('cash', payment, 'aurp-trucker-illegal')

    -- Atualizar DB e stats
    DB_CompleteJob(activeJob.id)
    DB_AddPlayerStats(citizenId, payment, activeJob.distance)

    -- XP pessoal (sem XP de empresa)
    ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, 1.0)

    -- Limpar alvo de apreensão (nil-guard: plate pode ser nil se job concluído a pé)
    if payload.plate then
        IllegalService.ClearSeizureTarget(payload.plate)
    end

    return true, payment
end
```

- [ ] **Step 2: Verify the file**

Read `server/services/illegal_service.lua` and confirm:
- All 6 methods are present (`Generate`, `BroadcastAlert`, `RegisterSeizureTarget`, `ClearSeizureTarget`, `Seize`, `OnComplete`)
- `IllegalService = {}` is at top (global, no `local`)
- `DB_ExpireJob` is called with one arg: `(target.jobId)` — confirm `DB_AbandonJob` does NOT appear in `Seize`
- `ClearSeizureTarget` reads `target` BEFORE nilíng the table entry

- [ ] **Step 3: Commit**
```bash
git add server/services/illegal_service.lua
git commit -m "feat(3b): IllegalService — Generate, BroadcastAlert, Seize, OnComplete"
```

---

## Task 5: JobService Hook + Server Events

**Files:**
- Modify: `server/services/job_service.lua`
- Modify: `server/events.lua`

- [ ] **Step 1: Add illegal hook to JobService.Complete**

Read `server/services/job_service.lua` and find the line that checks convoy:
```lua
    -- Detectar se é job de convoy — delegar pagamento ao ConvoyService
    if activeJob.convoy_id and ConvoyService then
```
After the entire convoy `if` block (after `return true, 0`), add the illegal hook:
```lua
    -- Detectar job ilegal — delegar ao IllegalService
    if activeJob.illegal_type and IllegalService then
        return IllegalService.OnComplete(src, Player, citizenId, activeJob, payload)
    end
```
This block goes BEFORE the `-- Calcular multiplicador de tempo` line.

- [ ] **Step 2: Add two handlers to server/events.lua**

Read `server/events.lua` and find the end of the TRUCK SIMULATION section. Before the last closing of the file, add:

```lua
-- =====================================================
-- ILLEGAL DELIVERIES (Fase 3B)
-- =====================================================

-- Cop usa ox_target "Lacrar Carga" para lacrar carga ilegal
RegisterNetEvent('AUST_trucker:seizeIllegalCargo', function(plate)
    local src = source
    if not plate then return end
    if IllegalService then
        IllegalService.Seize(src, plate)
    end
end)

-- Motorista entra no caminhão com job ilegal ativo — registra placa para apreensão
RegisterNetEvent('AUST_trucker:illegalRegisterPlate', function(plate)
    local src = source
    if not plate then return end
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    local activeJob = DB_GetActiveJobByPlayer(cid)
    if not activeJob or not activeJob.illegal_type then return end
    if IllegalService then
        IllegalService.RegisterSeizureTarget(src, activeJob.id, plate, activeJob.illegal_type)
    end
end)
```

- [ ] **Step 3: Verify**

Read `server/services/job_service.lua` lines around the convoy hook and confirm the illegal hook is present immediately after the convoy block.
Read the end of `server/events.lua` and confirm both new handlers are there.

- [ ] **Step 4: Commit**
```bash
git add server/services/job_service.lua server/events.lua
git commit -m "feat(3b): JobService illegal hook + seizeIllegalCargo + illegalRegisterPlate events"
```

---

## Task 6: Server Callbacks

**Files:**
- Modify: `server/callbacks.lua`

- [ ] **Step 1: Read the end of server/callbacks.lua**

Read `server/callbacks.lua` to find the last registered callback so you know where to append.

- [ ] **Step 2: Add two callbacks at the end of callbacks.lua**

```lua
-- ============================================================
-- ILLEGAL DELIVERIES (Fase 3B)
-- ============================================================

-- Retorna opções de cargo disponíveis no contato para exibir no menu
lib.callback.register('AUST_trucker:getIllegalJobs', function(source, contactId)
    -- Validar contactId
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if not contact then return nil end  -- nil = client não exibe menu

    local options = {}
    for _, illegalType in ipairs(contact.cargo) do
        -- Selecionar área de destino aleatória compatível (não revela coords)
        local compatible = {}
        for _, d in ipairs(Config.IllegalJobs.deliveries) do
            for _, a in ipairs(d.accepts) do
                if a == illegalType then table.insert(compatible, d); break end
            end
        end
        local destArea = (#compatible > 0) and compatible[math.random(#compatible)].area or '???'

        -- Estimar faixa de pagamento (±20% em torno de estimativa com 30 km fictícios)
        local mult    = Config.IllegalJobs.paymentMultipliers[illegalType] or 1.0
        local estBase = math.floor(Config.JobGeneration.distanceMultiplier * 30 * mult)
        local low     = math.floor(estBase * 0.8 / 1000) * 1000
        local high    = math.floor(estBase * 1.2 / 1000) * 1000

        table.insert(options, {
            illegalType     = illegalType,
            cargoLabel      = Config.IllegalJobs.alertLabels[illegalType] or illegalType,
            paymentEstimate = ('$%d – $%d'):format(low, high),
            destArea        = destArea,
        })
    end
    return options
end)

-- Aceita um job ilegal específico do contato
lib.callback.register('AUST_trucker:acceptIllegalJob', function(source, contactId, illegalType)
    if not IllegalService then return { success = false, reason = 'Serviço indisponível' } end

    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local cid = Player.PlayerData.citizenid

    -- Validar: sem job ativo
    if DB_GetActiveJobByPlayer(cid) then
        return { success = false, reason = 'Você já tem um trabalho ativo' }
    end

    local result = IllegalService.Generate(contactId, illegalType, source)
    if not result then return { success = false, reason = 'Trabalho indisponível agora' } end

    -- Alerta para cops/SALA após aceite
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if contact then
        IllegalService.BroadcastAlert(source, illegalType, contact.area)
    end

    return { success = true, jobData = result }
end)
```

- [ ] **Step 3: Verify**

Read the end of `server/callbacks.lua` and confirm both callbacks are present with correct names (`AUST_trucker:getIllegalJobs`, `AUST_trucker:acceptIllegalJob`).

- [ ] **Step 4: Commit**
```bash
git add server/callbacks.lua
git commit -m "feat(3b): getIllegalJobs + acceptIllegalJob callbacks"
```

---

## Task 7: Client — hud.client.lua + client.lua patches

**Files:**
- Modify: `client/hud.client.lua`
- Modify: `client/client.lua`

These are small surgical modifications.

- [ ] **Step 1: Add plate argument to truckStateChanged in hud.client.lua**

Read `client/hud.client.lua` and find (around line 182):
```lua
            TriggerEvent('AUST_trucker:client:truckStateChanged', SimState.isTruck)
```
Replace with:
```lua
            TriggerEvent('AUST_trucker:client:truckStateChanged', SimState.isTruck, SimState.currentPlate)
```

This allows `illegal.client.lua` to receive the plate when the player enters a truck, since `SimState` is local to `hud.client.lua`'s chunk.

- [ ] **Step 2: Add triggerComplete bridge in client.lua**

Read `client/client.lua` and find the `CompleteJob` function declaration (around line 802):
```lua
function CompleteJob()
```
After the entire `CompleteJob` function body (find its closing `end`), add:
```lua
-- Bridge para illegal.client.lua cruzar o isolamento de chunk lua54
-- illegal.client.lua não pode chamar CompleteJob diretamente (local ao chunk)
AddEventHandler('AUST_trucker:client:triggerComplete', CompleteJob)
```

- [ ] **Step 3: Verify both changes**

Read `client/hud.client.lua` line ~182 and confirm `SimState.currentPlate` is the second arg.
Read `client/client.lua` after `CompleteJob` and confirm the `AddEventHandler` is present.

- [ ] **Step 4: Commit**
```bash
git add client/hud.client.lua client/client.lua
git commit -m "feat(3b): truckStateChanged passes plate + triggerComplete bridge for illegal client"
```

---

## Task 8: illegal.client.lua (new file)

**Files:**
- Create: `client/illegal.client.lua`

This is the largest client file. Write it in one shot.

- [ ] **Step 1: Create client/illegal.client.lua**

```lua
-- AUST_trucker — client/illegal.client.lua
-- Fase 3B: zonas de contato, menu de cargo ilegal, entrega, apreensão

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local illegalJobActive   = false
local illegalPlate       = nil

-- Placas com jobs ilegais ativos conhecidas por este client.
-- Populado por illegalJobStarted, removido por illegalJobEnded.
-- Usado pelo polling de re-registro para cops que chegam tarde.
local knownIllegalPlates = {}

-- ============================================================
-- ZONAS DE CONTATO
-- ============================================================

CreateThread(function()
    for _, contact in ipairs(Config.IllegalJobs.contacts) do
        local c = contact  -- captura local para closure

        exports.ox_target:addSphereZone({
            name    = 'illegal_contact_' .. c.id,
            coords  = c.coords,
            radius  = c.radius,
            options = {
                {
                    name    = 'illegal_talk_' .. c.id,
                    label   = 'Falar com Contato',
                    icon    = 'fas fa-handshake',
                    onSelect = function()
                        -- Buscar opções de cargo disponíveis neste contato
                        local options = lib.callback.await('AUST_trucker:getIllegalJobs', false, c.id)
                        if not options or #options == 0 then
                            lib.notify({ title = 'Contato', description = 'Nada disponível no momento.', type = 'inform' })
                            return
                        end

                        -- Construir menu ox_lib
                        local menuOptions = {}
                        for _, opt in ipairs(options) do
                            local o = opt  -- captura local
                            table.insert(menuOptions, {
                                title       = ('Carga: %s'):format(o.cargoLabel),
                                description = ('Pagamento estimado: %s | Destino: %s'):format(o.paymentEstimate, o.destArea),
                                onSelect    = function()
                                    local result = lib.callback.await('AUST_trucker:acceptIllegalJob', false, c.id, o.illegalType)
                                    if result and result.success then
                                        lib.notify({
                                            title       = 'Trabalho Aceito',
                                            description = ('Leve %s para %s. Pagamento: $%d.'):format(
                                                o.cargoLabel, result.jobData.destArea, result.jobData.payment),
                                            type        = 'success',
                                            duration    = 8000,
                                        })
                                        illegalJobActive = true
                                        -- Nota: plate só é registrado ao entrar no caminhão (truckStateChanged)
                                    else
                                        lib.notify({
                                            title       = 'Trabalho Indisponível',
                                            description = (result and result.reason) or 'Tente novamente.',
                                            type        = 'error',
                                        })
                                    end
                                end,
                            })
                        end

                        lib.registerContext({
                            id      = 'illegal_menu_' .. c.id,
                            title   = c.label,
                            options = menuOptions,
                        })
                        lib.showContext('illegal_menu_' .. c.id)
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- ZONAS DE ENTREGA
-- ============================================================

CreateThread(function()
    for _, delivery in ipairs(Config.IllegalJobs.deliveries) do
        local d = delivery  -- captura local

        exports.ox_target:addSphereZone({
            name    = 'illegal_delivery_' .. d.id,
            coords  = d.coords,
            radius  = d.radius,
            options = {
                {
                    name     = 'illegal_deliver_' .. d.id,
                    label    = 'Descarregar Carga Ilegal',
                    icon     = 'fas fa-boxes',
                    distance = 6.0,
                    -- Visível apenas quando job ilegal ativo (check local — não bypassable por design)
                    canInteract = function()
                        return illegalJobActive
                    end,
                    onSelect = function()
                        -- Aciona CompleteJob() em client.lua via bridge de evento (cruzamento de chunk)
                        TriggerEvent('AUST_trucker:client:triggerComplete')
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- REGISTRAR PLACA AO ENTRAR NO CAMINHÃO
-- ============================================================

-- truckStateChanged é emitido por hud.client.lua quando isTruck muda.
-- A partir da Fase 3B, o segundo argumento é a placa atual (SimState.currentPlate).
AddEventHandler('AUST_trucker:client:truckStateChanged', function(isInTruck, plate)
    if isInTruck and illegalJobActive and plate then
        TriggerServerEvent('AUST_trucker:illegalRegisterPlate', plate)
    end
end)

-- ============================================================
-- POLLING: RE-REGISTRO DE TARGET PARA COPS QUE CHEGAM TARDE
-- ============================================================

-- illegalJobStarted é broadcast único. Um cop fora de range não recebe o addLocalEntity.
-- Esta thread verifica a cada 5s se algum caminhão ilegal entrou em range de streaming.
CreateThread(function()
    while true do
        Wait(5000)
        for plate, _ in pairs(knownIllegalPlates) do
            local vehicle = GetVehicleWithNumberPlate(plate)
            if vehicle and vehicle ~= 0 then
                exports.ox_target:addLocalEntity(vehicle, {
                    {
                        name     = 'seize_illegal_cargo_' .. plate,
                        label    = 'Lacrar Carga',
                        icon     = 'fas fa-lock',
                        distance = 3.0,
                        onSelect = function()
                            TriggerServerEvent('AUST_trucker:seizeIllegalCargo', plate)
                        end,
                    }
                })
            end
        end
    end
end)

-- ============================================================
-- EVENTOS RECEBIDOS DO SERVIDOR
-- ============================================================

-- Broadcast: job ilegal iniciado — todos os clients registram ox_target no caminhão.
RegisterNetEvent('AUST_trucker:client:illegalJobStarted', function(data)
    if not data or not data.plate then return end

    -- Registrar placa no conjunto de placas conhecidas (para polling de cops tardios)
    knownIllegalPlates[data.plate] = true

    -- Atualizar estado do motorista
    local myServerId = GetPlayerServerId(PlayerId())
    if data.driverSrc == myServerId then
        illegalJobActive = true
        illegalPlate     = data.plate
    end

    -- Registrar ox_target no caminhão se já streamado
    -- Nota: GetVehicleWithNumberPlate (não GetVehicleWithPlate) é a função nativa correta
    local vehicle = GetVehicleWithNumberPlate(data.plate)
    if vehicle and vehicle ~= 0 then
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name     = 'seize_illegal_cargo_' .. data.plate,
                label    = 'Lacrar Carga',
                icon     = 'fas fa-lock',
                distance = 3.0,
                onSelect = function()
                    TriggerServerEvent('AUST_trucker:seizeIllegalCargo', data.plate)
                end,
            }
        })
    end
end)

-- Broadcast: job ilegal encerrado — todos os clients removem ox_target.
RegisterNetEvent('AUST_trucker:client:illegalJobEnded', function(data)
    if not data then return end

    -- Remover da lista de placas conhecidas
    if data.plate then
        knownIllegalPlates[data.plate] = nil

        -- Remover ox_target do caminhão (no-op se nunca foi registrado neste client)
        local vehicle = GetVehicleWithNumberPlate(data.plate)
        if vehicle and vehicle ~= 0 then
            exports.ox_target:removeLocalEntity(vehicle)
        end
    end

    -- Limpar estado local apenas no motorista
    local myServerId = GetPlayerServerId(PlayerId())
    if data.driverSrc == myServerId then
        illegalJobActive = false
        illegalPlate     = nil
    end
end)

-- Motorista: carga foi apreendida pelo cop
RegisterNetEvent('AUST_trucker:client:cargoSeized', function(data)
    illegalJobActive = false
    illegalPlate     = nil
    lib.notify({
        title       = 'Carga Apreendida',
        description = ('Sua carga foi lacrada e apreendida. Multa: $%d'):format(data.fine or 0),
        type        = 'error',
        duration    = 10000,
    })
end)

-- Cop: apreensão confirmada
RegisterNetEvent('AUST_trucker:client:seizureSuccess', function(data)
    local label = (Config.IllegalJobs.alertLabels and Config.IllegalJobs.alertLabels[data.illegalType])
               or data.illegalType or '?'
    lib.notify({
        title       = 'Apreensão Confirmada',
        description = ('Carga de %s lacrada com sucesso.'):format(label),
        type        = 'success',
        duration    = 6000,
    })
end)
```

- [ ] **Step 2: Verify the file**

Read `client/illegal.client.lua` and confirm:
- Both `CreateThread` blocks for contacts and deliveries are present
- `truckStateChanged` handler fires `illegalRegisterPlate` with plate
- Polling thread iterates `knownIllegalPlates`
- All 4 `RegisterNetEvent` handlers are present
- `knownIllegalPlates[data.plate] = true` in `illegalJobStarted`
- `knownIllegalPlates[data.plate] = nil` in `illegalJobEnded`

- [ ] **Step 3: Commit**
```bash
git add client/illegal.client.lua
git commit -m "feat(3b): illegal.client.lua — contacts, delivery zones, events, seizure polling"
```

---

## Task 9: fxmanifest + CHANGELOG + Push

**Files:**
- Modify: `fxmanifest.lua`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read fxmanifest.lua**

Read `fxmanifest.lua` to find the exact current content before editing.

- [ ] **Step 2: Update fxmanifest.lua**

Change version from `'9.0.0'` to `'9.1.0'`.

In `server_scripts`, after `'server/services/convoy_service.lua',`, add:
```lua
    'server/services/illegal_service.lua',
```

In `client_scripts`, after `'client/convoy.client.lua',`, add:
```lua
    'client/illegal.client.lua',
```

- [ ] **Step 3: Update CHANGELOG.md**

Add entry at the top of `CHANGELOG.md`:
```markdown
## [9.1.0] — 2026-03-19 — Fase 3B: Illegal Deliveries

### Added
- **Illegal cargo delivery system**: 5 cargo types (contraband ×2.0, animals ×2.5, minerals ×2.3, weapons ×3.0, drugs ×2.8)
- **5 physical contact points** across the map for picking up illegal jobs
- **4 clandestine delivery zones** for drop-off
- **Police/SALA alerts**: text-only broadcast to LSPD on all types; SALA additionally for animals/minerals; `[LSPD ⚠]` prefix for weapons/drugs
- **Seizure mechanic**: cops use ox_target "Lacrar Carga" on the truck → job cancelled + cash fine → server-side validation
- **Proximity polling**: cops who arrive late at a scene re-register the seizure target when the truck enters streaming range
- `illegal_type` column on `trucker_jobs` (NULL for legal jobs)
- `'illegal_seizure'` added to `trucker_infractions.infraction_type` ENUM

### Changed
- `JobService.Complete`: illegal hook after convoy hook
- `hud.client.lua`: `truckStateChanged` now passes plate as second argument
- `client.lua`: `AddEventHandler('AUST_trucker:client:triggerComplete', CompleteJob)` bridge for chunk isolation

### Migration
Run `sql/update_illegal_v9_1.sql` on existing databases.
```

- [ ] **Step 4: Verify fxmanifest**

Read `fxmanifest.lua` and confirm:
- `version '9.1.0'`
- `illegal_service.lua` after `convoy_service.lua` in server_scripts
- `illegal.client.lua` after `convoy.client.lua` in client_scripts

- [ ] **Step 5: Commit and push**
```bash
git add fxmanifest.lua CHANGELOG.md
git commit -m "feat(3b): fxmanifest v9.1.0 + CHANGELOG — Fase 3B Illegal Deliveries complete"
git push
```

---

## Manual Verification Checklist

After all tasks are complete, verify in a running FiveM server:

- [ ] Server starts without Lua errors (`server console — no red lines from AUST_trucker`)
- [ ] Approaching a contact point shows "Falar com Contato" via ox_target
- [ ] Menu shows cargo options with label, payment range and delivery area
- [ ] Accepting a job sends a police alert to online cops
- [ ] Entering a truck with active illegal job triggers `illegalRegisterPlate` (check server console with Config.Debug=true)
- [ ] Cop can see "Lacrar Carga" on the truck via ox_target
- [ ] Cop seizing cargo cancels the job and deducts cash from driver
- [ ] Driver arriving at delivery zone sees "Descarregar Carga Ilegal" only when `illegalJobActive = true`
- [ ] Completing delivery pays in cash, grants personal XP, does NOT grant company XP
- [ ] Legal jobs still work normally (no regression in `JobService.Complete`)
- [ ] `SELECT illegal_type FROM trucker_jobs WHERE illegal_type IS NOT NULL` returns rows after accepting an illegal job
