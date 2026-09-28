# NPC Drivers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar motoristas NPC contratáveis por empresas com skill, satisfação, demandas por tenure, simulação de rota e eventos aleatórios incluindo contrabando com alerta policial.

**Architecture:** Sistema server-side: `NpcDriverService` global gerencia toda a lógica via `SetInterval` a cada 5 minutos. Jobs NPC são simulados (sem veículo real) — apenas blips interpolados client-side. Eventos graves pausam o job e esperam resposta do jogador via NUI overlay com countdown.

**Tech Stack:** FiveM Lua 5.4, oxmysql, ox_lib, ox_target, qbx_core, React 18 + TypeScript + Zustand

**Spec:** `docs/superpowers/specs/2026-03-20-npc-drivers-design.md`

---

## Mapa de Arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|-----------------|
| MODIFICAR | `sql/import.sql` | Tabelas trucker_npc_drivers, trucker_npc_jobs + ALTER trucker_companies |
| MODIFICAR | `config/config.lua` | Config.NpcDrivers completo |
| MODIFICAR | `server/database.lua` | 14 novos DB helpers |
| MODIFICAR | `server/main.lua` | Cache VP_Trucker.NpcDrivers/NpcJobs/PendingEvents/AgencyProfiles + LoadFromDB call |
| CRIAR | `server/services/npc_driver_service.lua` | NpcDriverService global — toda a lógica de NPC drivers |
| MODIFICAR | `server/events.lua` | Handler npcContrabandAlert → alerta SALA (cops sasp) |
| MODIFICAR | `server/callbacks.lua` | 6 callbacks + estender getInitialData |
| CRIAR | `client/npc_driver.client.lua` | Blips de rota, peds na base, overlay de evento grave |
| MODIFICAR | `html/src/types/index.ts` | NpcDriver, AgencyProfile, NpcGraveEvent, TabName 'drivers' |
| CRIAR | `html/src/stores/useNpcDriverStore.ts` | Store Zustand para NPC drivers |
| MODIFICAR | `html/src/hooks/useNUI.ts` | Handlers de NUI messages de NPC drivers |
| CRIAR | `html/src/components/company/NpcDriverPanel.tsx` | Lista de drivers + botão contratar |
| CRIAR | `html/src/components/company/NpcDriverCard.tsx` | Card individual com satisfação, skill, demanda |
| CRIAR | `html/src/components/company/NpcHireModal.tsx` | Modal com 3 perfis da agência |
| CRIAR | `html/src/components/overlay/NpcEventAlert.tsx` | Overlay com countdown para eventos graves |
| MODIFICAR | `html/src/components/layout/TabBar.tsx` | Nova tab "Motoristas" |
| MODIFICAR | `html/src/App.tsx` | NpcDriverPanel + NpcEventAlert overlay |
| MODIFICAR | `fxmanifest.lua` | v10.0.0, novos scripts |
| MODIFICAR | `CHANGELOG.md` | Entrada [10.0.0] |

---

### Task 1: SQL Schema + Config

**Files:**
- Modify: `sql/import.sql`
- Modify: `config/config.lua`

- [ ] **Step 1: Adicionar tabelas e ALTER ao import.sql**

Abrir `sql/import.sql` e adicionar ao final (após a última tabela existente):

```sql
-- ============================================================
-- NPC DRIVERS (v10.0.0)
-- ============================================================

ALTER TABLE `trucker_companies`
    ADD COLUMN IF NOT EXISTS `reputation`        TINYINT(3) UNSIGNED NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS `allow_illegal_npc` TINYINT(1)          NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS `trucker_npc_drivers` (
    `id`                VARCHAR(36)  NOT NULL PRIMARY KEY,
    `company_id`        VARCHAR(36)  NOT NULL,
    `name`              VARCHAR(64)  NOT NULL,
    `skill_level`       ENUM('junior','pleno','senior') NOT NULL DEFAULT 'junior',
    `salary`            INT          NOT NULL DEFAULT 2000,
    `satisfaction`      TINYINT      NOT NULL DEFAULT 80,
    `xp`                INT          NOT NULL DEFAULT 0,
    `tenure_days`       INT          NOT NULL DEFAULT 0,
    `total_earnings`    INT          NOT NULL DEFAULT 0,
    `status`            ENUM('idle','working','resting','fired','quit') NOT NULL DEFAULT 'idle',
    `active_job_id`     VARCHAR(36)  NULL DEFAULT NULL,
    `hired_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_demand_at`    INT          NULL DEFAULT NULL,
    `last_tenure_check` INT          NULL DEFAULT NULL,
    `resting_until`     INT          NULL DEFAULT NULL,
    FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `trucker_npc_jobs` (
    `id`              VARCHAR(36)  NOT NULL PRIMARY KEY,
    `driver_id`       VARCHAR(36)  NOT NULL,
    `company_id`      VARCHAR(36)  NOT NULL,
    `origin_id`       VARCHAR(64)  NOT NULL,
    `dest_id`         VARCHAR(64)  NOT NULL,
    `cargo_item`      VARCHAR(64)  NOT NULL,
    `base_payment`    INT          NOT NULL DEFAULT 0,
    `distance`        FLOAT        NOT NULL DEFAULT 0,
    `illegal`         TINYINT(1)   NOT NULL DEFAULT 0,
    `assigned_at`     INT          NOT NULL,
    `expected_end_at` INT          NOT NULL,
    `status`          ENUM('active','completed','failed','event') NOT NULL DEFAULT 'active',
    `earnings`        INT          NOT NULL DEFAULT 0,
    FOREIGN KEY (`driver_id`) REFERENCES `trucker_npc_drivers`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

- [ ] **Step 2: Executar schema no banco de dados**

```sql
-- Execute no HeidiSQL / phpMyAdmin ou via terminal:
-- ALTER TABLE já é idempotente com IF NOT EXISTS
-- CREATE TABLE IF NOT EXISTS também é seguro de re-executar
```

Verificar: tabelas `trucker_npc_drivers` e `trucker_npc_jobs` existem; colunas `reputation` e `allow_illegal_npc` em `trucker_companies`.

- [ ] **Step 3: Adicionar Config.NpcDrivers ao config.lua**

Abrir `config/config.lua` e adicionar antes de `Config.RepoMan` (ou no final do arquivo antes do último `return` se houver):

```lua
-- ============================================================
-- NPC DRIVERS (v10.0.0)
-- ============================================================
Config.NpcDrivers = {
    maxDriversPerCompany = 5,
    agencyLocation       = vector3(-179.0, -1320.0, 31.3),
    agencyRadius         = 15.0,
    agencyHeading        = 270.0,
    agencyPedModel       = 's_m_m_trucker_01',
    basePedModel         = 's_m_m_trucker_01',
    agencyRefreshSeconds = 86400,
    cronIntervalMinutes  = 5,

    hireCost = {
        junior = 2000,
        pleno  = 6000,
        senior = 15000,
    },

    trainingCost = {
        junior_to_pleno = 5000,
        pleno_to_senior = 12000,
    },
    trainingJobsRequired = {
        junior_to_pleno = 20,
        pleno_to_senior = 50,
    },

    skillEfficiency = {
        junior = 0.80,
        pleno  = 0.95,
        senior = 1.10,
    },

    skillSpeedFactor = {
        junior = 0.80,
        pleno  = 0.95,
        senior = 1.00,
    },

    eventChance = {
        junior = 0.25,
        pleno  = 0.12,
        senior = 0.05,
    },

    satisfaction = {
        startValue            = 80,
        gainPerJob            = 3,
        decayPerDayLowSalary  = 1,
        penaltyDemandIgnored  = 5,
        penaltyEventIgnored   = 10,
        gainDemandGranted     = 8,
        lowThreshold          = 40,
        criticalThreshold     = 20,
    },

    tenureDemands = {
        { days = 15,  type = 'salary_raise',   value = 0.15 },
        { days = 30,  type = 'better_vehicle', value = nil  },
        { days = 60,  type = 'rest_day',       value = nil  },
        { days = 90,  type = 'profit_share',   value = 1000 },
    },
    demandExpiryDays = 3,

    minorEvents = {
        traffic_fine   = { costMin = 150, costMax = 300  },
        minor_accident = { integrityLoss = 10            },
        fuel_over      = { costMin = 100, costMax = 200  },
        delayed        = { extraMinutes = 30             },
    },

    graveEvents = {
        major_accident    = { repairMin = 800, repairMax = 2000 },
        cargo_stolen      = {},
        contraband_caught = { bribeAmount = 3000 },
    },
    graveEventTimerSeconds = 300,

    contraband = {
        reputationPenalty = 10,
        fineAmount        = 5000,
        driverRestSeconds = 86400,
        catchChance = {
            junior = 0.30,
            pleno  = 0.15,
            senior = 0.08,
        },
    },

    reputation = {
        gainPerNormalJob  = 1,
        gainPerLongJob    = 3,
        longJobDistanceKm = 30,
    },

    positionUpdateIntervalMs = 15000,
    blipSprite = 477,
    blipScale  = 0.7,
}
```

- [ ] **Step 4: Commit**

```bash
git add sql/import.sql config/config.lua
git commit -m "feat(npc-drivers): schema + Config.NpcDrivers (Task 1)"
```

---

### Task 2: DB Helpers (server/database.lua)

**Files:**
- Modify: `server/database.lua`

Adicionar ao final de `server/database.lua`, após os helpers existentes:

- [ ] **Step 1: Adicionar helpers de NPC Drivers**

```lua
-- ============================================================
-- NPC DRIVERS (v10.0.0)
-- ============================================================

function DB_InsertNpcDriver(driver)
    return MySQL.insert.await(
        [[INSERT INTO trucker_npc_drivers
          (id, company_id, name, skill_level, salary, satisfaction, last_tenure_check)
          VALUES (?, ?, ?, ?, ?, ?, ?)]],
        { driver.id, driver.company_id, driver.name, driver.skill_level,
          driver.salary, driver.satisfaction, os.time() }
    )
end

function DB_GetNpcDriversByCompany(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_npc_drivers WHERE company_id = ? AND status NOT IN (\'fired\',\'quit\')',
        { companyId }
    ) or {}
end

function DB_GetAllActiveNpcDrivers()
    return MySQL.query.await(
        "SELECT * FROM trucker_npc_drivers WHERE status IN ('idle','working','resting')"
    ) or {}
end

function DB_UpdateNpcDriverStatus(id, status, activeJobId)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET status = ?, active_job_id = ? WHERE id = ?',
        { status, activeJobId, id }
    )
end

-- xpGain e totalEarningsGain podem ser negativos; satisfactionDelta pode ser negativo
function DB_UpdateNpcDriverStats(id, xpGain, satisfactionDelta, totalEarningsGain)
    MySQL.update.await(
        [[UPDATE trucker_npc_drivers
          SET xp            = xp + ?,
              satisfaction  = GREATEST(0, LEAST(100, satisfaction + ?)),
              total_earnings = total_earnings + ?
          WHERE id = ?]],
        { xpGain, satisfactionDelta, totalEarningsGain, id }
    )
end

function DB_UpdateNpcDriverSatisfaction(id, satisfactionDelta)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET satisfaction = GREATEST(0, LEAST(100, satisfaction + ?)) WHERE id = ?',
        { satisfactionDelta, id }
    )
end

function DB_UpdateNpcDriverTenure(id, tenureDays, lastTenureCheck)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET tenure_days = ?, last_tenure_check = ? WHERE id = ?',
        { tenureDays, lastTenureCheck, id }
    )
end

function DB_UpdateNpcDriverSalary(id, salary)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET salary = ? WHERE id = ?',
        { salary, id }
    )
end

function DB_SetNpcDriverQuit(id)
    MySQL.update.await(
        "UPDATE trucker_npc_drivers SET status = 'quit', active_job_id = NULL WHERE id = ?",
        { id }
    )
end

function DB_SetNpcDriverResting(id, restingUntil)
    MySQL.update.await(
        "UPDATE trucker_npc_drivers SET status = 'resting', active_job_id = NULL, resting_until = ? WHERE id = ?",
        { restingUntil, id }
    )
end

function DB_UpdateNpcDriverSkill(id, skillLevel)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET skill_level = ? WHERE id = ?',
        { skillLevel, id }
    )
end

-- NPC Jobs

function DB_InsertNpcJob(npcJob)
    return MySQL.insert.await(
        [[INSERT INTO trucker_npc_jobs
          (id, driver_id, company_id, origin_id, dest_id, cargo_item,
           base_payment, distance, illegal, assigned_at, expected_end_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { npcJob.id, npcJob.driver_id, npcJob.company_id,
          npcJob.origin_id, npcJob.dest_id, npcJob.cargo_item,
          npcJob.base_payment, npcJob.distance, npcJob.illegal,
          npcJob.assigned_at, npcJob.expected_end_at }
    )
end

function DB_UpdateNpcJobStatus(id, status, earnings)
    MySQL.update.await(
        'UPDATE trucker_npc_jobs SET status = ?, earnings = ? WHERE id = ?',
        { status, earnings or 0, id }
    )
end

function DB_GetNpcJobsByStatus(status)
    return MySQL.query.await(
        'SELECT * FROM trucker_npc_jobs WHERE status = ?',
        { status }
    ) or {}
end

function DB_GetOneAvailableJobForNpc()
    return MySQL.single.await(
        "SELECT * FROM trucker_jobs WHERE status = 'available' ORDER BY RAND() LIMIT 1"
    )
end

function DB_GetOneAvailableIllegalJobForNpc()
    return MySQL.single.await(
        "SELECT tj.*, id.illegal_type FROM trucker_jobs tj JOIN trucker_illegal_deliveries id ON id.job_id = tj.id WHERE tj.status = 'available' AND id.illegal_type IS NOT NULL ORDER BY RAND() LIMIT 1"
    )
end

-- Empresa — Reputação

function DB_UpdateCompanyReputation(companyId, delta)
    MySQL.update.await(
        'UPDATE trucker_companies SET reputation = GREATEST(0, LEAST(100, reputation + ?)) WHERE id = ?',
        { delta, companyId }
    )
    local row = MySQL.single.await(
        'SELECT reputation FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
    if VP_Trucker.Companies[companyId] and row then
        VP_Trucker.Companies[companyId].reputation = row.reputation
    end
end

function DB_SetNpcAllowIllegal(companyId, allowed)
    MySQL.update.await(
        'UPDATE trucker_companies SET allow_illegal_npc = ? WHERE id = ?',
        { allowed and 1 or 0, companyId }
    )
end
```

- [ ] **Step 2: Verificar que o resource carrega sem erros**

Reiniciar resource: `restart AUST_trucker` no console do servidor.
Verificar no console: sem erros de syntax Lua. Digitar no F8: `AUST_trucker`.

- [ ] **Step 3: Commit**

```bash
git add server/database.lua
git commit -m "feat(npc-drivers): DB helpers (Task 2)"
```

---

### Task 3: Cache VP_Trucker + main.lua + npc_driver_service.lua skeleton + LoadFromDB

**Files:**
- Modify: `server/main.lua`
- Create: `server/services/npc_driver_service.lua`

- [ ] **Step 1: Adicionar cache VP_Trucker em main.lua**

Em `server/main.lua`, adicionar dentro de `VP_Trucker = { ... }` após `IllegalTargets`:

```lua
    -- Fase 4A: NPC Drivers
    NpcDrivers     = {},  -- { [driverId] = driverRow }
    NpcJobs        = {},  -- { [npcJobId] = npcJobRow }
    PendingEvents  = {},  -- { [eventId]  = { driver, npcJob, payload } }
    AgencyProfiles = {},  -- { profiles = [...], generatedAt = unixTimestamp }
```

Ainda em `main.lua`, dentro do `CreateThread` após `ConvoyService.LoadFromDB()`, adicionar:

```lua
            while not NpcDriverService do Wait(100) end
            NpcDriverService.LoadFromDB()
```

A seção ficará assim:

```lua
            IndustryOwnershipService.LoadCache()
            JobService.LoadFromDB()
            ConvoyService.LoadFromDB()
            while not NpcDriverService do Wait(100) end
            NpcDriverService.LoadFromDB()
            VP_Trucker.Ready = true
```

- [ ] **Step 2: Criar npc_driver_service.lua com UUID helper e LoadFromDB**

Criar `server/services/npc_driver_service.lua`:

```lua
-- AUST_trucker — server/services/npc_driver_service.lua
-- Gerencia motoristas NPC das empresas: lifecycle, jobs simulados, eventos, satisfação

NpcDriverService = {}

-- Helper: UUID v4 simples (mesmo padrão de party_service.lua)
local function NewUUID()
    local t = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' }
    local s = ''
    for i = 1, 32 do
        s = s .. t[math.random(16)]
        if i == 8 or i == 12 or i == 16 or i == 20 then s = s .. '-' end
    end
    return s
end

-- Helper: retorna src do owner de uma empresa (nil se offline)
local function GetOwnerSrc(companyId)
    local company = VP_Trucker.Companies[companyId]
    if not company then return nil end
    local ownerCid = company.owner_citizenid
    local players = exports.qbx_core:GetQBPlayers() or {}
    for _, p in pairs(players) do
        if p.PlayerData.citizenid == ownerCid then
            return p.PlayerData.source
        end
    end
    return nil
end

-- ============================================================
-- LOAD FROM DB (chamado em main.lua após Ready)
-- ============================================================

function NpcDriverService.LoadFromDB()
    -- 1. Carregar todos os drivers ativos
    local drivers = DB_GetAllActiveNpcDrivers() or {}
    for _, d in ipairs(drivers) do
        VP_Trucker.NpcDrivers[d.id] = d
    end

    local now = os.time()

    -- 2. Recuperar NPC jobs em status 'event' → auto-fail (evento perdido no restart)
    local eventJobs = DB_GetNpcJobsByStatus('event') or {}
    for _, j in ipairs(eventJobs) do
        DB_UpdateNpcJobStatus(j.id, 'failed', 0)
        -- Liberar trucker_job reservado
        MySQL.update.await(
            "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
            { 'npc_' .. j.driver_id }
        )
        local driver = VP_Trucker.NpcDrivers[j.driver_id]
        if driver then
            driver.status      = 'idle'
            driver.active_job_id = nil
            DB_UpdateNpcDriverStatus(j.driver_id, 'idle', nil)
        end
    end

    -- 3. Recuperar NPC jobs em status 'active'
    local activeJobs = DB_GetNpcJobsByStatus('active') or {}
    -- Nota: retorna TODOS os jobs ativos de todas empresas — aceitável (max 5 drivers/empresa)
    for _, j in ipairs(activeJobs) do
        VP_Trucker.NpcJobs[j.id] = j
        if j.expected_end_at <= now then
            -- Job expirou durante offline → completar sem evento
            local driver = VP_Trucker.NpcDrivers[j.driver_id]
            if driver then
                NpcDriverService._CompleteJob(driver, j)
            end
        end
    end

    -- 4. Drivers em 'resting' com resting_until passado → idle
    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.status == 'resting' and driver.resting_until and driver.resting_until <= now then
            driver.status = 'idle'
            driver.active_job_id = nil
            DB_UpdateNpcDriverStatus(id, 'idle', nil)
        end
    end

    if Config.Debug then
        local count = 0
        for _ in pairs(VP_Trucker.NpcDrivers) do count = count + 1 end
        print(('[AUST_trucker] NpcDriverService.LoadFromDB: %d drivers carregados'):format(count))
    end
end

-- ============================================================
-- PROCESS TICK (SetInterval 5min)
-- ============================================================

function NpcDriverService.ProcessTick()
    local now = os.time()

    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        -- Drivers resting: verificar se tempo acabou
        if driver.status == 'resting' and driver.resting_until and driver.resting_until <= now then
            driver.status = 'idle'
            driver.active_job_id = nil
            DB_UpdateNpcDriverStatus(id, 'idle', nil)
        end

        -- Drivers working: verificar se job concluiu (ignorar jobs pausados em 'event')
        if driver.status == 'working' and driver.active_job_id then
            local npcJob = VP_Trucker.NpcJobs[driver.active_job_id]
            if npcJob and npcJob.status ~= 'event' and now >= npcJob.expected_end_at then
                NpcDriverService._RollEvent(driver, npcJob)
            end
        end

        -- Drivers idle: tentar atribuir job
        if driver.status == 'idle' then
            NpcDriverService._TryAssignJob(driver)
        end

        -- Rotina diária
        local today     = math.floor(now / 86400)
        local lastCheck = math.floor((driver.last_tenure_check or 0) / 86400)
        if today > lastCheck then
            NpcDriverService._CheckTenure(driver)
            NpcDriverService._ApplySatisfactionDecay(driver)
            NpcDriverService._CheckQuitRisk(driver)
            driver.last_tenure_check = now
            DB_UpdateNpcDriverTenure(id, driver.tenure_days, now)
        end
    end

    NpcDriverService._BroadcastPositions()
end

-- ============================================================
-- STUBS (implementados nas Tasks seguintes)
-- ============================================================

function NpcDriverService._TryAssignJob(driver) end
function NpcDriverService._RollEvent(driver, npcJob) end
function NpcDriverService._HandleMinorEvent(driver, npcJob, eventType) end
function NpcDriverService._HandleGraveEvent(driver, npcJob, eventType) end
function NpcDriverService._CompleteJob(driver, npcJob) end
function NpcDriverService._CheckTenure(driver) end
function NpcDriverService._ApplySatisfactionDecay(driver) end
function NpcDriverService._CheckQuitRisk(driver) end
function NpcDriverService._BroadcastPositions() end
function NpcDriverService.GetAgencyProfiles() return {} end
function NpcDriverService.Hire(src, companyId, profileIndex, playerCoords) end
function NpcDriverService.Fire(src, companyId, driverId) end
function NpcDriverService.Train(src, companyId, driverId) end
function NpcDriverService.SetAllowIllegal(src, companyId, allowed) end
function NpcDriverService.RespondToEvent(src, eventId, response) end
function NpcDriverService.GetByCompany(companyId) return {} end

-- ============================================================
-- INTERVAL (registrado no final do arquivo — fora de funções)
-- ============================================================

SetInterval(Config.NpcDrivers.cronIntervalMinutes * 60 * 1000, function()
    NpcDriverService.ProcessTick()
end)
```

- [ ] **Step 3: Adicionar npc_driver_service.lua ao fxmanifest**

Em `fxmanifest.lua`, dentro de `server_scripts`, após `'server/services/illegal_service.lua'`:

```lua
    'server/services/npc_driver_service.lua',   -- após illegal_service
```

- [ ] **Step 4: Verificar que o resource carrega**

`restart AUST_trucker` → console deve mostrar `NpcDriverService.LoadFromDB: 0 drivers carregados` (ou o número real se já houver dados).

- [ ] **Step 5: Commit**

```bash
git add server/main.lua server/services/npc_driver_service.lua fxmanifest.lua
git commit -m "feat(npc-drivers): VP_Trucker cache + NpcDriverService skeleton + LoadFromDB (Task 3)"
```

---

### Task 4: _TryAssignJob + _CompleteJob

**Files:**
- Modify: `server/services/npc_driver_service.lua` (substituir stubs)

- [ ] **Step 1: Implementar _TryAssignJob**

Substituir `function NpcDriverService._TryAssignJob(driver) end` por:

```lua
function NpcDriverService._TryAssignJob(driver)
    local company = VP_Trucker.Companies[driver.company_id]
    if not company then return end

    -- Tentar job ilegal se empresa permite (com probabilidade baseada no skill)
    local job = nil
    if company.allow_illegal_npc == 1 then
        local catchChance = Config.NpcDrivers.contraband.catchChance[driver.skill_level] or 0.15
        if math.random() > catchChance then
            job = DB_GetOneAvailableIllegalJobForNpc()
        end
    end

    -- Fallback: job normal
    if not job then
        job = DB_GetOneAvailableJobForNpc()
    end
    if not job then return end  -- sem jobs disponíveis

    -- Reservar trucker_job (evita que jogador humano pegue o mesmo)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status='active', assigned_citizenid=? WHERE id=? AND status='available'",
        { 'npc_' .. driver.id, job.id }
    )

    -- Calcular duração: distância em km / 0.5 km/s (30 km/h simulado) / speed factor
    local baseDuration = math.max(60, (job.distance or 1) / 0.5)
    local duration = math.floor(baseDuration / (Config.NpcDrivers.skillSpeedFactor[driver.skill_level] or 1.0))

    local npcJobId = NewUUID()
    local now = os.time()
    local npcJob = {
        id             = npcJobId,
        driver_id      = driver.id,
        company_id     = driver.company_id,
        origin_id      = job.origin_id,
        dest_id        = job.dest_id,
        cargo_item     = job.cargo_item,
        base_payment   = job.base_payment,
        distance       = job.distance,
        illegal        = (job.illegal_type and 1) or 0,
        assigned_at    = now,
        expected_end_at = now + duration,
        status         = 'active',
        earnings       = 0,
    }

    DB_InsertNpcJob(npcJob)
    VP_Trucker.NpcJobs[npcJobId] = npcJob
    driver.status        = 'working'
    driver.active_job_id = npcJobId
    DB_UpdateNpcDriverStatus(driver.id, 'working', npcJobId)

    if Config.Debug then
        print(('[AUST_trucker] NPC %s → job %s (%s→%s, %ds)'):format(
            driver.name, npcJobId, job.origin_id, job.dest_id, duration))
    end
end
```

- [ ] **Step 2: Implementar _CompleteJob**

Substituir `function NpcDriverService._CompleteJob(driver, npcJob) end` por:

```lua
function NpcDriverService._CompleteJob(driver, npcJob)
    local earnings = math.floor((npcJob.base_payment or 0) * (Config.NpcDrivers.skillEfficiency[driver.skill_level] or 1.0))

    -- Creditar empresa (DB_UpdateCompanyBalance não atualiza cache — fazer manualmente)
    DB_UpdateCompanyBalance(npcJob.company_id, earnings)
    if VP_Trucker.Companies[npcJob.company_id] then
        VP_Trucker.Companies[npcJob.company_id].balance =
            (VP_Trucker.Companies[npcJob.company_id].balance or 0) + earnings
    end

    -- Reputação: apenas jobs legítimos
    if npcJob.illegal == 0 then
        local repGain = (npcJob.distance or 0) >= Config.NpcDrivers.reputation.longJobDistanceKm
            and Config.NpcDrivers.reputation.gainPerLongJob
            or  Config.NpcDrivers.reputation.gainPerNormalJob
        DB_UpdateCompanyReputation(npcJob.company_id, repGain)
    end

    -- Atualizar driver
    local satGain = Config.NpcDrivers.satisfaction.gainPerJob
    driver.xp            = (driver.xp or 0) + 1
    driver.satisfaction  = math.min(100, (driver.satisfaction or 80) + satGain)
    driver.total_earnings = (driver.total_earnings or 0) + earnings
    driver.status        = 'idle'
    driver.active_job_id = nil

    DB_UpdateNpcJobStatus(npcJob.id, 'completed', earnings)
    DB_UpdateNpcDriverStats(driver.id, 1, satGain, earnings)
    DB_UpdateNpcDriverStatus(driver.id, 'idle', nil)
    VP_Trucker.NpcJobs[npcJob.id] = nil

    -- Liberar trucker_job de volta para o pool
    MySQL.update.await(
        "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
        { 'npc_' .. driver.id }
    )

    -- Notificar owner online
    local ownerSrc = GetOwnerSrc(npcJob.company_id)
    if ownerSrc then
        TriggerClientEvent('AUST_trucker:client:npcDriverJobCompleted', ownerSrc, {
            driverName = driver.name,
            earnings   = earnings,
            skillLevel = driver.skill_level,
        })
    end

    if Config.Debug then
        print(('[AUST_trucker] NPC %s completou job — $%d'):format(driver.name, earnings))
    end
end
```

- [ ] **Step 3: Verificar em jogo**

Com `Config.Debug = true`, aguardar 5 minutos (ou reduzir `cronIntervalMinutes = 1` temporariamente no config). Console deve mostrar drivers recebendo jobs e completando.

- [ ] **Step 4: Commit**

```bash
git add server/services/npc_driver_service.lua
git commit -m "feat(npc-drivers): _TryAssignJob + _CompleteJob (Task 4)"
```

---

### Task 5: _RollEvent + _HandleMinorEvent + _HandleGraveEvent + RespondToEvent

**Files:**
- Modify: `server/services/npc_driver_service.lua`

- [ ] **Step 1: Implementar _RollEvent**

```lua
function NpcDriverService._RollEvent(driver, npcJob)
    local chance = Config.NpcDrivers.eventChance[driver.skill_level] or 0.15
    if (driver.satisfaction or 80) < Config.NpcDrivers.satisfaction.lowThreshold then
        chance = chance * 2
    end

    if math.random() < chance then
        local eventType
        if npcJob.illegal == 1 then
            -- Jobs ilegais só geram contraband_caught como evento grave
            eventType = 'contraband_caught'
        else
            -- Pool de eventos: 50% minor, 50% grave
            local graveTypes = { 'major_accident', 'cargo_stolen' }
            local minorTypes = { 'traffic_fine', 'minor_accident', 'fuel_over', 'delayed' }
            if math.random() < 0.5 then
                eventType = minorTypes[math.random(#minorTypes)]
            else
                eventType = graveTypes[math.random(#graveTypes)]
            end
        end

        local isGrave = eventType == 'major_accident'
                     or eventType == 'cargo_stolen'
                     or eventType == 'contraband_caught'

        if isGrave then
            NpcDriverService._HandleGraveEvent(driver, npcJob, eventType)
        else
            NpcDriverService._HandleMinorEvent(driver, npcJob, eventType)
        end
    else
        NpcDriverService._CompleteJob(driver, npcJob)
    end
end
```

- [ ] **Step 2: Implementar _HandleMinorEvent**

```lua
function NpcDriverService._HandleMinorEvent(driver, npcJob, eventType)
    local cfg = Config.NpcDrivers.minorEvents[eventType]
    if not cfg then
        NpcDriverService._CompleteJob(driver, npcJob)
        return
    end

    -- Ajustar earnings base com custo do evento
    if eventType == 'traffic_fine' or eventType == 'fuel_over' then
        local cost = math.random(cfg.costMin, cfg.costMax)
        npcJob.base_payment = math.max(0, (npcJob.base_payment or 0) - cost)
    elseif eventType == 'delayed' then
        npcJob.expected_end_at = (npcJob.expected_end_at or os.time()) + (cfg.extraMinutes * 60)
        -- Job continua ativo — sair sem completar
        DB_UpdateNpcJobStatus(npcJob.id, 'active', 0)  -- manter status active com novo expected_end
        return
    end
    -- minor_accident: reduz earnings via integrityLoss (aplicado no base_payment)
    if eventType == 'minor_accident' then
        local lossFactor = 1.0 - ((cfg.integrityLoss or 0) / 100)
        npcJob.base_payment = math.floor((npcJob.base_payment or 0) * lossFactor)
    end

    -- Completar normalmente após ajuste
    NpcDriverService._CompleteJob(driver, npcJob)
end
```

- [ ] **Step 3: Implementar _HandleGraveEvent**

```lua
function NpcDriverService._HandleGraveEvent(driver, npcJob, eventType)
    -- CRÍTICO: atualizar cache ANTES do DB para que ProcessTick não re-role no mesmo job
    npcJob.status = 'event'
    DB_UpdateNpcJobStatus(npcJob.id, 'event', 0)

    local eventId = NewUUID()
    local expiresAt = os.time() + Config.NpcDrivers.graveEventTimerSeconds

    local payload = {
        eventId    = eventId,
        driverId   = driver.id,
        driverName = driver.name,
        type       = eventType,
        expiresAt  = expiresAt,
    }

    if eventType == 'major_accident' then
        local cfg = Config.NpcDrivers.graveEvents.major_accident
        payload.repairCost = math.random(cfg.repairMin, cfg.repairMax)
    elseif eventType == 'contraband_caught' then
        payload.bribeAmount = Config.NpcDrivers.graveEvents.contraband_caught.bribeAmount
        -- Efeitos imediatos (independentes da decisão do jogador)
        DB_UpdateCompanyReputation(npcJob.company_id, -Config.NpcDrivers.contraband.reputationPenalty)
        DB_UpdateCompanyBalance(npcJob.company_id, -Config.NpcDrivers.contraband.fineAmount)
        if VP_Trucker.Companies[npcJob.company_id] then
            VP_Trucker.Companies[npcJob.company_id].balance =
                (VP_Trucker.Companies[npcJob.company_id].balance or 0) - Config.NpcDrivers.contraband.fineAmount
        end
        -- Alerta SALA
        local companyName = (VP_Trucker.Companies[npcJob.company_id] or {}).name or '?'
        local originName  = npcJob.origin_id  -- id da indústria; resolver para nome se necessário
        for _, o in ipairs(Config.PrimaryIndustries or {}) do
            if o.id == npcJob.origin_id then originName = o.name; break end
        end
        TriggerEvent('AUST_trucker:npcContrabandAlert', {
            companyName = companyName,
            driverName  = driver.name,
            area        = originName,
            illegalType = npcJob.cargo_item,
        })
    end

    VP_Trucker.PendingEvents[eventId] = { driver = driver, npcJob = npcJob, payload = payload }

    -- Notificar owner online
    local ownerSrc = GetOwnerSrc(npcJob.company_id)
    if ownerSrc then
        TriggerClientEvent('AUST_trucker:client:npcGraveEvent', ownerSrc, payload)
    end

    -- Auto-resolver como 'ignore' após timer
    SetTimeout(Config.NpcDrivers.graveEventTimerSeconds * 1000, function()
        if VP_Trucker.PendingEvents[eventId] then
            NpcDriverService.RespondToEvent(nil, eventId, 'ignore')
        end
    end)
end
```

- [ ] **Step 4: Implementar RespondToEvent**

```lua
function NpcDriverService.RespondToEvent(src, eventId, response)
    local pending = VP_Trucker.PendingEvents[eventId]
    if not pending then return { success = false, reason = 'Evento não encontrado' } end

    VP_Trucker.PendingEvents[eventId] = nil

    local driver = pending.driver
    local npcJob = pending.npcJob
    local payload = pending.payload

    if payload.type == 'major_accident' then
        if response == 'pay' and src then
            local Player = exports.qbx_core:GetPlayer(src)
            if Player then
                local cost = payload.repairCost or 1000
                if Player.Functions.RemoveMoney('bank', cost, 'npc-repair') then
                    -- Pago: completar job normalmente
                    NpcDriverService._CompleteJob(driver, npcJob)
                else
                    -- Sem dinheiro: tratar como ignored
                    response = 'ignore'
                end
            end
        end
        if response == 'ignore' then
            DB_UpdateNpcDriverSatisfaction(driver.id, -Config.NpcDrivers.satisfaction.penaltyEventIgnored)
            driver.satisfaction = math.max(0, (driver.satisfaction or 80) - Config.NpcDrivers.satisfaction.penaltyEventIgnored)
            npcJob.base_payment = 0
            NpcDriverService._CompleteJob(driver, npcJob)
        end

    elseif payload.type == 'cargo_stolen' then
        -- Sem escolha real: driver retorna sem mercadoria
        DB_UpdateNpcDriverSatisfaction(driver.id, -Config.NpcDrivers.satisfaction.penaltyEventIgnored)
        driver.satisfaction = math.max(0, (driver.satisfaction or 80) - Config.NpcDrivers.satisfaction.penaltyEventIgnored)
        npcJob.base_payment = 0
        NpcDriverService._CompleteJob(driver, npcJob)

    elseif payload.type == 'contraband_caught' then
        if response == 'pay' and src then
            local Player = exports.qbx_core:GetPlayer(src)
            if Player then
                local bribe = payload.bribeAmount or 3000
                Player.Functions.RemoveMoney('bank', bribe, 'npc-bribe')
            end
            -- Com suborno: completar normalmente
            NpcDriverService._CompleteJob(driver, npcJob)
        else
            -- Sem suborno: driver fica retido 24h
            local restingUntil = os.time() + Config.NpcDrivers.contraband.driverRestSeconds
            driver.status        = 'resting'
            driver.active_job_id = nil
            DB_SetNpcDriverResting(driver.id, restingUntil)
            DB_UpdateNpcJobStatus(npcJob.id, 'failed', 0)
            VP_Trucker.NpcJobs[npcJob.id] = nil
            MySQL.update.await(
                "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
                { 'npc_' .. driver.id }
            )
        end
    end

    -- Notificar owner sobre resolução
    local ownerSrc = GetOwnerSrc(npcJob.company_id)
    if ownerSrc then
        TriggerClientEvent('AUST_trucker:client:npcEventResolved', ownerSrc, {
            eventId    = eventId,
            resolution = response,
        })
    end

    return { success = true }
end
```

- [ ] **Step 5: Commit**

```bash
git add server/services/npc_driver_service.lua
git commit -m "feat(npc-drivers): RollEvent + HandleMinorEvent + HandleGraveEvent + RespondToEvent (Task 5)"
```

---

### Task 6: _CheckTenure + _ApplySatisfactionDecay + _CheckQuitRisk + _BroadcastPositions + Hire/Fire/Train/GetAgencyProfiles

**Files:**
- Modify: `server/services/npc_driver_service.lua`

- [ ] **Step 1: Nomes de NPC gerados aleatoriamente (helper local)**

Adicionar após `GetOwnerSrc`:

```lua
local NPC_NAMES = {
    'Carlos Souza', 'João Lima', 'Pedro Alves', 'Marcos Ferreira',
    'Rafael Costa', 'Bruno Oliveira', 'Diego Santos', 'Lucas Pereira',
    'André Rocha', 'Felipe Gomes', 'Thiago Martins', 'Rodrigo Nunes',
    'Eduardo Carvalho', 'Gabriel Silva', 'Mateus Ribeiro',
}

local SKILL_WEIGHTS = { junior = 6, pleno = 3, senior = 1 }

local function GenerateDriverProfile(index)
    local name = NPC_NAMES[math.random(#NPC_NAMES)]
    -- Selecionar skill ponderado
    local roll = math.random(10)
    local skill = roll <= 6 and 'junior' or (roll <= 9 and 'pleno' or 'senior')
    local salaryBase = Config.NpcDrivers.hireCost[skill] or 2000
    local salary = math.floor(salaryBase * (0.1 + math.random() * 0.1))  -- 10-20% do hire cost como salário/job
    return {
        index      = index,
        name       = name,
        skillLevel = skill,
        salary     = salary,
        hireCost   = Config.NpcDrivers.hireCost[skill],
    }
end
```

- [ ] **Step 2: Implementar GetAgencyProfiles**

```lua
function NpcDriverService.GetAgencyProfiles()
    local ap = VP_Trucker.AgencyProfiles
    local now = os.time()
    if ap.generatedAt and (now - ap.generatedAt) < Config.NpcDrivers.agencyRefreshSeconds and #(ap.profiles or {}) == 3 then
        return ap.profiles
    end
    local profiles = {}
    for i = 1, 3 do
        table.insert(profiles, GenerateDriverProfile(i))
    end
    VP_Trucker.AgencyProfiles = { profiles = profiles, generatedAt = now }
    return profiles
end
```

- [ ] **Step 3: Implementar Hire**

```lua
function NpcDriverService.Hire(src, companyId, profileIndex, playerCoords)
    -- Validar proximidade da agência
    local agency = Config.NpcDrivers.agencyLocation
    local dx = (playerCoords.x or 0) - agency.x
    local dy = (playerCoords.y or 0) - agency.y
    if math.sqrt(dx*dx + dy*dy) > Config.NpcDrivers.agencyRadius then
        return false, 'Você precisa estar na agência de emprego'
    end

    -- Validar empresa
    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end

    -- Verificar limite de motoristas
    local count = 0
    for _, d in pairs(VP_Trucker.NpcDrivers) do
        if d.company_id == companyId then count = count + 1 end
    end
    if count >= Config.NpcDrivers.maxDriversPerCompany then
        return false, ('Limite de %d motoristas atingido'):format(Config.NpcDrivers.maxDriversPerCompany)
    end

    -- Validar perfil
    local profiles = NpcDriverService.GetAgencyProfiles()
    local profile = profiles[profileIndex]
    if not profile then return false, 'Perfil inválido' end

    -- Cobrar contratação
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    if not Player.Functions.RemoveMoney('bank', profile.hireCost, 'npc-hire') then
        return false, 'Saldo bancário insuficiente'
    end

    -- Inserir no DB e cache
    local driverId = NewUUID()
    local driver = {
        id               = driverId,
        company_id       = companyId,
        name             = profile.name,
        skill_level      = profile.skillLevel,
        salary           = profile.salary,
        satisfaction     = Config.NpcDrivers.satisfaction.startValue,
        xp               = 0,
        tenure_days      = 0,
        total_earnings   = 0,
        status           = 'idle',
        active_job_id    = nil,
        last_tenure_check = os.time(),
        resting_until    = nil,
    }
    DB_InsertNpcDriver(driver)
    VP_Trucker.NpcDrivers[driverId] = driver

    -- Invalidar perfis da agência (substituir o contratado)
    VP_Trucker.AgencyProfiles.generatedAt = 0

    if Config.Debug then
        print(('[AUST_trucker] Contratado: %s (%s) para empresa %s'):format(driver.name, driver.skill_level, companyId))
    end
    return true, driver
end
```

- [ ] **Step 4: Implementar Fire**

```lua
function NpcDriverService.Fire(src, companyId, driverId)
    local driver = VP_Trucker.NpcDrivers[driverId]
    if not driver or driver.company_id ~= companyId then
        return false, 'Motorista não encontrado'
    end

    -- Liberar job ativo se houver
    if driver.active_job_id then
        local npcJob = VP_Trucker.NpcJobs[driver.active_job_id]
        if npcJob then
            DB_UpdateNpcJobStatus(npcJob.id, 'failed', 0)
            VP_Trucker.NpcJobs[npcJob.id] = nil
        end
        MySQL.update.await(
            "UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
            { 'npc_' .. driverId }
        )
    end

    DB_SetNpcDriverQuit(driverId)
    VP_Trucker.NpcDrivers[driverId] = nil
    return true
end
```

- [ ] **Step 5: Implementar Train**

```lua
function NpcDriverService.Train(src, companyId, driverId)
    local driver = VP_Trucker.NpcDrivers[driverId]
    if not driver or driver.company_id ~= companyId then
        return false, 'Motorista não encontrado'
    end

    local nextSkill, cost, jobsRequired
    if driver.skill_level == 'junior' then
        nextSkill    = 'pleno'
        cost         = Config.NpcDrivers.trainingCost.junior_to_pleno
        jobsRequired = Config.NpcDrivers.trainingJobsRequired.junior_to_pleno
    elseif driver.skill_level == 'pleno' then
        nextSkill    = 'senior'
        cost         = Config.NpcDrivers.trainingCost.pleno_to_senior
        jobsRequired = Config.NpcDrivers.trainingJobsRequired.pleno_to_senior
    else
        return false, 'Motorista já é Sênior'
    end

    if (driver.xp or 0) < jobsRequired then
        return false, ('Precisa de %d jobs completados (atual: %d)'):format(jobsRequired, driver.xp or 0)
    end

    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    if not Player.Functions.RemoveMoney('bank', cost, 'npc-training') then
        return false, 'Saldo bancário insuficiente'
    end

    driver.skill_level = nextSkill
    DB_UpdateNpcDriverSkill(driverId, nextSkill)
    return true, nextSkill
end
```

- [ ] **Step 6: Implementar SetAllowIllegal e GetByCompany**

```lua
function NpcDriverService.SetAllowIllegal(src, companyId, allowed)
    local company = VP_Trucker.Companies[companyId]
    if not company then return false end
    company.allow_illegal_npc = allowed and 1 or 0
    DB_SetNpcAllowIllegal(companyId, allowed)
    return true
end

function NpcDriverService.GetByCompany(companyId)
    local result = {}
    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.company_id == companyId then
            local d = {}
            for k, v in pairs(driver) do d[k] = v end  -- shallow copy
            if driver.active_job_id then
                d.activeJob = VP_Trucker.NpcJobs[driver.active_job_id]
            end
            table.insert(result, d)
        end
    end
    return result
end
```

- [ ] **Step 7: Implementar rotinas diárias**

```lua
function NpcDriverService._CheckTenure(driver)
    driver.tenure_days = (driver.tenure_days or 0) + 1

    -- Verificar se alguma demanda de tenure deve ser gerada
    local cfg = Config.NpcDrivers.tenureDemands
    local lastDemand = driver.last_demand_at or 0
    local now = os.time()

    for _, demand in ipairs(cfg) do
        if driver.tenure_days >= demand.days then
            -- Verificar se esta demanda já foi emitida (evitar duplicação)
            -- Usamos last_demand_at como marcador da última demanda emitida
            -- Simplificação: emite uma vez por ciclo se tenure == dias exatos
            if driver.tenure_days == demand.days then
                driver.last_demand_at = now

                local ownerSrc = GetOwnerSrc(driver.company_id)
                if ownerSrc then
                    TriggerClientEvent('AUST_trucker:client:npcDemandGenerated', ownerSrc, {
                        driverId   = driver.id,
                        driverName = driver.name,
                        demandType = demand.type,
                        value      = demand.value,
                        expiresAt  = now + (Config.NpcDrivers.demandExpiryDays * 86400),
                    })
                end
            end
        end
    end
end

function NpcDriverService._ApplySatisfactionDecay(driver)
    local company = VP_Trucker.Companies[driver.company_id]
    if not company then return end

    -- Verificar se salário está abaixo do esperado (salary esperado = 15% do hire cost)
    local expectedSalary = math.floor((Config.NpcDrivers.hireCost[driver.skill_level] or 2000) * 0.12)
    if (driver.salary or 0) < expectedSalary then
        local decay = Config.NpcDrivers.satisfaction.decayPerDayLowSalary
        driver.satisfaction = math.max(0, (driver.satisfaction or 80) - decay)
        DB_UpdateNpcDriverSatisfaction(driver.id, -decay)
    end
end

function NpcDriverService._CheckQuitRisk(driver)
    if (driver.satisfaction or 80) < Config.NpcDrivers.satisfaction.criticalThreshold then
        if math.random(100) <= 10 then  -- 10% de chance por dia
            driver.status = 'quit'
            DB_SetNpcDriverQuit(driver.id)
            VP_Trucker.NpcDrivers[driver.id] = nil

            local ownerSrc = GetOwnerSrc(driver.company_id)
            if ownerSrc then
                TriggerClientEvent('AUST_trucker:client:npcDriverQuit', ownerSrc, {
                    driverName = driver.name,
                })
            end
        end
    end
end

function NpcDriverService._BroadcastPositions()
    -- Agrupar drivers working por empresa
    local byCompany = {}
    local now = os.time()

    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.status == 'working' and driver.active_job_id then
            local npcJob = VP_Trucker.NpcJobs[driver.active_job_id]
            if npcJob and npcJob.status == 'active' then
                -- Interpolar posição entre origin e dest
                local elapsed  = now - (npcJob.assigned_at or now)
                local total    = math.max(1, (npcJob.expected_end_at or now) - (npcJob.assigned_at or now))
                local progress = math.min(1.0, elapsed / total)

                -- Buscar coords das indústrias pelo id
                local ox, oy, oz = 0, 0, 30
                local dx2, dy2, dz2 = 0, 0, 30
                for _, ind in ipairs(Config.PrimaryIndustries or {}) do
                    if ind.id == npcJob.origin_id then ox = ind.coords.x; oy = ind.coords.y; oz = ind.coords.z end
                end
                for _, ind in ipairs(Config.SecondaryIndustries or {}) do
                    if ind.id == npcJob.dest_id then dx2 = ind.coords.x; dy2 = ind.coords.y; dz2 = ind.coords.z end
                end

                local posX = ox + (dx2 - ox) * progress
                local posY = oy + (dy2 - oy) * progress
                local posZ = oz + (dz2 - oz) * progress

                local cid = driver.company_id
                if not byCompany[cid] then byCompany[cid] = {} end
                byCompany[cid][id] = {
                    x      = posX,
                    y      = posY,
                    z      = posZ,
                    name   = driver.name,
                    status = driver.status,
                }
            end
        end
    end

    -- Enviar para owners online
    for companyId, positions in pairs(byCompany) do
        local ownerSrc = GetOwnerSrc(companyId)
        if ownerSrc then
            TriggerClientEvent('AUST_trucker:client:npcPositionUpdate', ownerSrc, positions)
        end
    end
end
```

- [ ] **Step 8: Commit**

```bash
git add server/services/npc_driver_service.lua
git commit -m "feat(npc-drivers): full NpcDriverService (Hire/Fire/Train/Tenure/Events/Broadcast) (Task 6)"
```

---

### Task 7: events.lua (SALA) + callbacks.lua + getInitialData

**Files:**
- Modify: `server/events.lua`
- Modify: `server/callbacks.lua`

- [ ] **Step 1: Adicionar handler SALA em events.lua**

No final de `server/events.lua`:

```lua
-- =====================================================
-- NPC DRIVERS — SALA CONTRABAND ALERT
-- =====================================================

AddEventHandler('AUST_trucker:npcContrabandAlert', function(data)
    local label = (Config.IllegalJobs.alertLabels and Config.IllegalJobs.alertLabels[data.illegalType])
               or data.illegalType or '?'
    local msg = ('[SALA] Empresa %s — suspeita de contrabando (%s) na região de %s.'):format(
        data.companyName or '?', label, data.area or '?')

    local players = exports.qbx_core:GetQBPlayers() or {}
    for _, player in pairs(players) do
        if player.PlayerData.job and player.PlayerData.job.name == 'sasp' then
            TriggerClientEvent('AUST_trucker:client:policeAlert', player.PlayerData.source,
                { message = msg })
        end
    end
end)
```

- [ ] **Step 2: Adicionar 6 callbacks em callbacks.lua**

No final de `server/callbacks.lua` (após os callbacks de Repo Man existentes):

```lua
-- =====================================================
-- NPC DRIVERS (v10.0.0)
-- =====================================================

lib.callback.register('AUST_trucker:getNpcDriverData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    local citizenId = Player.PlayerData.citizenid
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local drivers  = NpcDriverService.GetByCompany(company.id)
    local profiles = NpcDriverService.GetAgencyProfiles()
    local rep      = (VP_Trucker.Companies[company.id] or {}).reputation or 100
    local illegal  = (VP_Trucker.Companies[company.id] or {}).allow_illegal_npc or 0

    return {
        success     = true,
        drivers     = drivers,
        profiles    = profiles,
        reputation  = rep,
        allowIllegal = illegal == 1,
    }
end)

lib.callback.register('AUST_trucker:hireNpcDriver', function(source, profileIndex, playerCoords)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    -- Verificar role: apenas owner e manager podem contratar
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Apenas owner/manager podem contratar' }
    end

    local ok, result = NpcDriverService.Hire(source, company.id, profileIndex, playerCoords or {})
    return { success = ok, reason = not ok and result or nil, driver = ok and result or nil }
end)

lib.callback.register('AUST_trucker:fireNpcDriver', function(source, driverId)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Apenas owner/manager podem demitir' }
    end

    local ok, err = NpcDriverService.Fire(source, company.id, driverId)
    return { success = ok, reason = err }
end)

lib.callback.register('AUST_trucker:trainNpcDriver', function(source, driverId)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local ok, result = NpcDriverService.Train(source, company.id, driverId)
    return { success = ok, reason = not ok and result or nil, newSkill = ok and result or nil }
end)

lib.callback.register('AUST_trucker:setNpcAllowIllegal', function(source, allowed)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid
    local company   = CompanyService.GetByMember(citizenId)
    if not company then return { success = false } end

    local member = DB_GetMember(citizenId)
    if not member or member.role ~= 'owner' then
        return { success = false, reason = 'Apenas owner pode configurar jobs ilegais' }
    end

    NpcDriverService.SetAllowIllegal(source, company.id, allowed)
    return { success = true }
end)

lib.callback.register('AUST_trucker:npcRespondEvent', function(source, eventId, response)
    local result = NpcDriverService.RespondToEvent(source, eventId, response)
    return result
end)
```

- [ ] **Step 3: Estender getInitialData para incluir dados de NPC drivers**

Em `server/callbacks.lua`, dentro de `lib.callback.register('AUST_trucker:getInitialData', ...)`, após a linha que define `companyPayload`, adicionar:

```lua
    -- NPC Drivers data (apenas se tiver empresa)
    local npcDriversPayload = nil
    if company then
        npcDriversPayload = {
            drivers     = NpcDriverService.GetByCompany(company.id),
            profiles    = NpcDriverService.GetAgencyProfiles(),
            reputation  = (VP_Trucker.Companies[company.id] or {}).reputation or 100,
            allowIllegal = ((VP_Trucker.Companies[company.id] or {}).allow_illegal_npc or 0) == 1,
        }
    end
```

E no `return` do callback, adicionar `npcDrivers = npcDriversPayload`:

```lua
    return {
        -- ... campos existentes ...
        npcDrivers = npcDriversPayload,
    }
```

- [ ] **Step 4: Verificar carregamento**

`restart AUST_trucker` → sem erros de syntax. Testar callback via F8: `AUST_trucker:getNpcDriverData` deve retornar dados.

- [ ] **Step 5: Commit**

```bash
git add server/events.lua server/callbacks.lua
git commit -m "feat(npc-drivers): SALA handler + 6 callbacks + getInitialData extension (Task 7)"
```

---

### Task 8: client/npc_driver.client.lua

**Files:**
- Create: `client/npc_driver.client.lua`
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Criar client/npc_driver.client.lua**

```lua
-- AUST_trucker — client/npc_driver.client.lua
-- Blips de rota, peds na base da empresa, overlay de evento grave

local NpcDriverState = {
    activeDriverBlips = {},  -- { [driverId] = blipHandle }
    basePeds          = {},  -- { [driverId] = pedHandle }
    baseZone          = nil, -- handle da zona ox_lib
    inBaseZone        = false,
}

-- ============================================================
-- BLIPS DE ROTA
-- ============================================================

RegisterNetEvent('AUST_trucker:client:npcPositionUpdate', function(positions)
    -- positions = { [driverId] = { x, y, z, name, status } }
    for driverId, pos in pairs(positions) do
        if pos.status == 'working' then
            local blip = NpcDriverState.activeDriverBlips[driverId]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(pos.x, pos.y, pos.z)
                SetBlipSprite(blip, Config.NpcDrivers.blipSprite)
                SetBlipColour(blip, 46)  -- azul claro
                SetBlipScale(blip, Config.NpcDrivers.blipScale)
                SetBlipAsShortRange(blip, false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(('[NPC] %s'):format(pos.name or driverId))
                EndTextCommandSetBlipName(blip)
                NpcDriverState.activeDriverBlips[driverId] = blip
            else
                SetBlipCoords(blip, pos.x, pos.y, pos.z)
            end
        else
            -- Driver não está mais em rota: remover blip
            local blip = NpcDriverState.activeDriverBlips[driverId]
            if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
            NpcDriverState.activeDriverBlips[driverId] = nil
        end
    end
end)

-- ============================================================
-- PEDS NA BASE DA EMPRESA
-- ============================================================

-- Chamado quando dados iniciais são carregados (via evento local emitido por client.lua)
AddEventHandler('AUST_trucker:client:companyLoaded', function(company)
    -- Criar zona na base da empresa se tiver coordenadas configuradas
    -- Nota: base_coords deve estar no company payload ou em Config.
    -- Se não houver campo específico, usar agencyLocation como fallback.
    -- Implementação futura: adicionar base_coords ao companyPayload do servidor.
    -- Por ora, pular criação de peds (zona pode ser adicionada quando base_coords for configurável).
end)

local function SpawnBasePeds(drivers)
    -- Remover peds anteriores
    for id, ped in pairs(NpcDriverState.basePeds) do
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    NpcDriverState.basePeds = {}

    local baseCoord = Config.NpcDrivers.agencyLocation  -- fallback: usar agência como base
    local spacing   = 1.5

    local idleDrivers = {}
    for _, d in ipairs(drivers or {}) do
        if d.status == 'idle' then table.insert(idleDrivers, d) end
    end

    for i, driver in ipairs(idleDrivers) do
        CreateThread(function()
            local model = GetHashKey(Config.NpcDrivers.basePedModel)
            RequestModel(model)
            while not HasModelLoaded(model) do Wait(50) end

            local offsetX = (i - 1) * spacing
            local ped = CreatePed(4, model, baseCoord.x + offsetX, baseCoord.y, baseCoord.z, 0.0, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            SetModelAsNoLongerNeeded(model)

            NpcDriverState.basePeds[driver.id] = ped

            exports.ox_target:addLocalEntity(ped, {
                {
                    name     = 'npc_driver_profile_' .. driver.id,
                    label    = ('[%s] %s — Ver Perfil'):format(driver.skill_level:upper(), driver.name),
                    icon     = 'fas fa-id-card',
                    distance = 3.0,
                    onSelect = function()
                        SendNUIMessage({ action = 'focusNpcDriver', driverId = driver.id })
                        SetNuiFocus(true, true)
                    end,
                },
            })
        end)
    end
end

local function DespawnBasePeds()
    for id, ped in pairs(NpcDriverState.basePeds) do
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped)
            DeletePed(ped)
        end
    end
    NpcDriverState.basePeds = {}
end

-- Zona na agência (substituindo base da empresa até termos base_coords configurável)
CreateThread(function()
    Wait(3000)  -- aguardar resource carregar
    local zone = lib.zones.sphere({
        coords = Config.NpcDrivers.agencyLocation,
        radius = Config.NpcDrivers.agencyRadius,
        onEnter = function()
            NpcDriverState.inBaseZone = true
            -- Buscar drivers da empresa via callback
            local result = lib.callback.await('AUST_trucker:getNpcDriverData', false)
            if result and result.success then
                SpawnBasePeds(result.drivers)
            end
        end,
        onExit = function()
            NpcDriverState.inBaseZone = false
            DespawnBasePeds()
        end,
    })
    NpcDriverState.baseZone = zone
end)

-- ============================================================
-- EVENTOS GRAVES
-- ============================================================

RegisterNetEvent('AUST_trucker:client:npcGraveEvent', function(data)
    SendNUIMessage({ action = 'npcGraveEvent', event = data })
    SetNuiFocus(true, true)
end)

RegisterNetEvent('AUST_trucker:client:npcEventResolved', function(data)
    SendNUIMessage({ action = 'npcEventResolved', eventId = data.eventId })
end)

-- ============================================================
-- NOTIFICAÇÕES SIMPLES
-- ============================================================

RegisterNetEvent('AUST_trucker:client:npcDriverJobCompleted', function(data)
    lib.notify({
        title       = 'Motorista NPC',
        description = ('%s completou uma entrega — $%d'):format(data.driverName or '?', data.earnings or 0),
        type        = 'success',
        duration    = 5000,
    })
end)

RegisterNetEvent('AUST_trucker:client:npcDriverQuit', function(data)
    lib.notify({
        title       = 'Motorista Saiu',
        description = ('%s pediu demissão por baixa satisfação.'):format(data.driverName or '?'),
        type        = 'error',
        duration    = 8000,
    })
end)

RegisterNetEvent('AUST_trucker:client:npcDemandGenerated', function(data)
    lib.notify({
        title       = 'Demanda do Motorista',
        description = ('%s tem uma nova demanda: %s'):format(data.driverName or '?', data.demandType or '?'),
        type        = 'inform',
        duration    = 8000,
    })
end)
```

- [ ] **Step 2: Adicionar ao fxmanifest.lua**

Em `client_scripts`, após `'client/repo.client.lua'`:

```lua
    'client/npc_driver.client.lua',
```

- [ ] **Step 3: Verificar carregamento**

`restart AUST_trucker` → sem erros. Ir à coordenada da agência em jogo → peds aparecem se empresa tiver drivers idle.

- [ ] **Step 4: Commit**

```bash
git add client/npc_driver.client.lua fxmanifest.lua
git commit -m "feat(npc-drivers): client — blips + base peds + grave event overlay (Task 8)"
```

---

### Task 9: TypeScript — types + store + useNUI handlers

**Files:**
- Modify: `html/src/types/index.ts`
- Create: `html/src/stores/useNpcDriverStore.ts`
- Modify: `html/src/hooks/useNUI.ts`

- [ ] **Step 1: Adicionar tipos em types/index.ts**

Adicionar após a última interface existente:

```typescript
// ============================================================
// NPC DRIVERS (v10.0.0)
// ============================================================

export type SkillLevel = 'junior' | 'pleno' | 'senior'
export type DriverStatus = 'idle' | 'working' | 'resting' | 'fired' | 'quit'
export type DemandType = 'salary_raise' | 'better_vehicle' | 'rest_day' | 'profit_share'

export interface NpcDriver {
  id: string
  name: string
  skill_level: SkillLevel
  salary: number
  satisfaction: number
  xp: number
  tenure_days: number
  total_earnings: number
  status: DriverStatus
  active_job_id?: string | null
  demand?: { type: DemandType; value?: number; expiresAt: number }
  activeJob?: { origin_id: string; dest_id: string; expected_end_at: number }
}

export interface AgencyProfile {
  index: number
  name: string
  skillLevel: SkillLevel
  salary: number
  hireCost: number
}

export interface NpcGraveEvent {
  eventId: string
  driverId: string
  driverName: string
  type: 'major_accident' | 'cargo_stolen' | 'contraband_caught'
  repairCost?: number
  bribeAmount?: number
  expiresAt: number
}

export interface NpcDriverData {
  drivers: NpcDriver[]
  profiles: AgencyProfile[]
  reputation: number
  allowIllegal: boolean
}
```

Adicionar `'drivers'` ao tipo `TabName` (buscar `type TabName` no arquivo e adicionar):

```typescript
export type TabName = 'jobs' | 'missions' | 'active' | 'company' | 'garage' | 'industries' | 'stats' | 'convoy' | 'drivers'
```

- [ ] **Step 2: Criar useNpcDriverStore.ts**

```typescript
import { create } from 'zustand'
import type { NpcDriver, AgencyProfile, NpcGraveEvent } from '../types'

interface NpcDriverStore {
  drivers:      NpcDriver[]
  profiles:     AgencyProfile[]
  reputation:   number
  allowIllegal: boolean
  pendingEvent: NpcGraveEvent | null

  setDrivers:      (drivers: NpcDriver[]) => void
  setProfiles:     (profiles: AgencyProfile[]) => void
  setReputation:   (rep: number) => void
  setAllowIllegal: (v: boolean) => void
  setPendingEvent: (ev: NpcGraveEvent | null) => void
  removeDriver:    (id: string) => void
}

export const useNpcDriverStore = create<NpcDriverStore>((set) => ({
  drivers:      [],
  profiles:     [],
  reputation:   100,
  allowIllegal: false,
  pendingEvent: null,

  setDrivers:      (drivers) => set({ drivers }),
  setProfiles:     (profiles) => set({ profiles }),
  setReputation:   (reputation) => set({ reputation }),
  setAllowIllegal: (allowIllegal) => set({ allowIllegal }),
  setPendingEvent: (pendingEvent) => set({ pendingEvent }),
  removeDriver:    (id) => set((s) => ({ drivers: s.drivers.filter(d => d.id !== id) })),
}))
```

- [ ] **Step 3: Adicionar handlers em useNUI.ts**

No topo de `useNUI.ts`, adicionar imports:

```typescript
import { useNpcDriverStore } from '../stores/useNpcDriverStore'
import type { NpcDriver, AgencyProfile, NpcGraveEvent, NpcDriverData } from '../types'
```

Dentro de `useNUI()`, adicionar store:

```typescript
  const { setDrivers, setProfiles, setReputation, setAllowIllegal, setPendingEvent, removeDriver } = useNpcDriverStore()
```

No `NUIMessage` interface, adicionar:

```typescript
  npcDrivers?:    NpcDriverData | null
  npcGraveEvent?: NpcGraveEvent
  driverId?:      string
  eventId?:       string
```

No `switch (action)`, dentro do `case 'open':` adicionar após `setParty(...)`:

```typescript
          if (event.data.npcDrivers) {
            setDrivers(event.data.npcDrivers.drivers ?? [])
            setProfiles(event.data.npcDrivers.profiles ?? [])
            setReputation(event.data.npcDrivers.reputation ?? 100)
            setAllowIllegal(event.data.npcDrivers.allowIllegal ?? false)
          }
```

Adicionar novos cases no switch:

```typescript
        case 'npcGraveEvent':
          if (event.data.npcGraveEvent) setPendingEvent(event.data.npcGraveEvent)
          break
        case 'npcEventResolved':
          setPendingEvent(null)
          break
        case 'npcDriverJobCompleted':
          // notificação já emitida via lib.notify — apenas atualizar drivers se necessário
          break
        case 'npcDriverQuit':
          if (event.data.driverId) removeDriver(event.data.driverId)
          break
        case 'updateNpcDrivers':
          if (event.data.npcDrivers) {
            setDrivers(event.data.npcDrivers.drivers ?? [])
            setReputation(event.data.npcDrivers.reputation ?? 100)
            setAllowIllegal(event.data.npcDrivers.allowIllegal ?? false)
          }
          break
```

- [ ] **Step 4: Commit**

```bash
git add html/src/types/index.ts html/src/stores/useNpcDriverStore.ts html/src/hooks/useNUI.ts
git commit -m "feat(npc-drivers): TypeScript types + store + useNUI handlers (Task 9)"
```

---

### Task 10: NUI Components

**Files:**
- Create: `html/src/components/company/NpcDriverPanel.tsx`
- Create: `html/src/components/company/NpcDriverCard.tsx`
- Create: `html/src/components/company/NpcHireModal.tsx`
- Create: `html/src/components/overlay/NpcEventAlert.tsx`

- [ ] **Step 1: Criar NpcDriverCard.tsx**

```tsx
import type { NpcDriver } from '../../../types'
import { fetchNUI } from '../../../hooks/useNUI'

interface Props {
  driver: NpcDriver
  canManage: boolean
  onUpdated: () => void
}

const SKILL_BADGE: Record<string, string> = {
  junior: 'bg-zinc-600 text-zinc-200',
  pleno:  'bg-blue-800 text-blue-200',
  senior: 'bg-yellow-700 text-yellow-100',
}

const STATUS_LABEL: Record<string, string> = {
  idle:    'Disponível',
  working: 'Em rota',
  resting: 'Retido',
}

export function NpcDriverCard({ driver, canManage, onUpdated }: Props) {
  const satColor = driver.satisfaction >= 60
    ? 'bg-green-500'
    : driver.satisfaction >= 30
    ? 'bg-yellow-500'
    : 'bg-red-500'

  async function handleFire() {
    if (!confirm(`Demitir ${driver.name}?`)) return
    const r = await fetchNUI<{ success: boolean; reason?: string }>('fireNpcDriver', driver.id)
    if (r.success) onUpdated()
  }

  async function handleTrain() {
    const r = await fetchNUI<{ success: boolean; reason?: string; newSkill?: string }>('trainNpcDriver', driver.id)
    if (!r.success) alert(r.reason ?? 'Erro ao treinar')
    else onUpdated()
  }

  return (
    <div className="bg-zinc-800 rounded-lg p-3 flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <span className={`text-xs font-bold px-2 py-0.5 rounded ${SKILL_BADGE[driver.skill_level] ?? ''}`}>
          {driver.skill_level.toUpperCase()}
        </span>
        <span className="text-zinc-100 text-sm font-medium flex-1">{driver.name}</span>
        <span className="text-zinc-400 text-xs">{STATUS_LABEL[driver.status] ?? driver.status}</span>
      </div>

      {/* Barra de satisfação */}
      <div className="flex items-center gap-2">
        <span className="text-zinc-400 text-xs w-20">Satisfação</span>
        <div className="flex-1 bg-zinc-700 rounded-full h-2">
          <div className={`h-2 rounded-full ${satColor}`} style={{ width: `${driver.satisfaction}%` }} />
        </div>
        <span className="text-zinc-300 text-xs w-8 text-right">{driver.satisfaction}%</span>
      </div>

      {/* Stats */}
      <div className="flex gap-4 text-xs text-zinc-400">
        <span>XP: {driver.xp}</span>
        <span>Tenure: {driver.tenure_days}d</span>
        <span>Total: ${driver.total_earnings.toLocaleString()}</span>
      </div>

      {/* Ações (apenas owners/managers) */}
      {canManage && (
        <div className="flex gap-2 mt-1">
          {driver.skill_level !== 'senior' && (
            <button
              onClick={handleTrain}
              className="flex-1 bg-blue-800 hover:bg-blue-700 text-blue-100 rounded px-2 py-1 text-xs"
            >
              Treinar
            </button>
          )}
          <button
            onClick={handleFire}
            className="bg-red-900 hover:bg-red-800 text-red-200 rounded px-2 py-1 text-xs"
          >
            Demitir
          </button>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Criar NpcHireModal.tsx**

```tsx
import { useState } from 'react'
import type { AgencyProfile } from '../../../types'
import { fetchNUI } from '../../../hooks/useNUI'

interface Props {
  profiles: AgencyProfile[]
  onClose: () => void
  onHired: () => void
}

const SKILL_LABEL: Record<string, string> = {
  junior: 'Junior',
  pleno:  'Pleno',
  senior: 'Sênior',
}

export function NpcHireModal({ profiles, onClose, onHired }: Props) {
  const [loading, setLoading] = useState(false)
  const [error, setError]     = useState<string | null>(null)

  async function handleHire(profile: AgencyProfile) {
    setLoading(true)
    setError(null)
    // Enviar coordenadas do player (client.lua as fornece via GetEntityCoords)
    const r = await fetchNUI<{ success: boolean; reason?: string }>(
      'hireNpcDriver', { profileIndex: profile.index }
    )
    setLoading(false)
    if (r.success) {
      onHired()
    } else {
      setError(r.reason ?? 'Erro ao contratar')
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-900 rounded-xl border border-zinc-700 w-[400px] p-4 flex flex-col gap-3">
        <div className="flex justify-between items-center">
          <h3 className="text-zinc-100 font-semibold">Agência de Emprego</h3>
          <button onClick={onClose} className="text-zinc-400 hover:text-zinc-100 text-lg">×</button>
        </div>

        {error && (
          <div className="bg-red-900/40 border border-red-700 text-red-300 rounded px-3 py-2 text-sm">
            {error}
          </div>
        )}

        <p className="text-zinc-400 text-xs">Vá até a agência para contratar. Perfis renovam a cada 24h.</p>

        <div className="flex flex-col gap-2">
          {profiles.map((p) => (
            <div key={p.index} className="bg-zinc-800 rounded-lg p-3 flex items-center justify-between gap-3">
              <div>
                <div className="text-zinc-100 text-sm font-medium">{p.name}</div>
                <div className="text-zinc-400 text-xs">
                  {SKILL_LABEL[p.skillLevel] ?? p.skillLevel} · Salário: ${p.salary}/job
                </div>
              </div>
              <button
                onClick={() => handleHire(p)}
                disabled={loading}
                className="bg-green-700 hover:bg-green-600 text-white rounded px-3 py-1 text-sm font-medium disabled:opacity-50"
              >
                ${p.hireCost.toLocaleString()}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Criar NpcDriverPanel.tsx**

```tsx
import { useState } from 'react'
import { useNpcDriverStore } from '../../../stores/useNpcDriverStore'
import { useCompanyStore } from '../../../stores/useCompanyStore'
import { fetchNUI } from '../../../hooks/useNUI'
import { NpcDriverCard } from './NpcDriverCard'
import { NpcHireModal } from './NpcHireModal'

export function NpcDriverPanel() {
  const { drivers, profiles, reputation, allowIllegal, setDrivers, setReputation, setAllowIllegal, setProfiles } =
    useNpcDriverStore()
  const { company } = useCompanyStore()
  const [showHire, setShowHire] = useState(false)
  const [loading, setLoading]   = useState(false)

  const canManage = company?.role === 'owner' || company?.role === 'manager'
  const isOwner   = company?.role === 'owner'

  async function refresh() {
    const r = await fetchNUI<{ success: boolean; drivers?: any[]; reputation?: number; allowIllegal?: boolean; profiles?: any[] }>('getNpcDriverData')
    if (r.success) {
      setDrivers(r.drivers ?? [])
      setReputation(r.reputation ?? 100)
      setAllowIllegal(r.allowIllegal ?? false)
      setProfiles(r.profiles ?? [])
    }
  }

  async function toggleIllegal() {
    setLoading(true)
    await fetchNUI('setNpcAllowIllegal', !allowIllegal)
    setAllowIllegal(!allowIllegal)
    setLoading(false)
  }

  const repColor = reputation >= 70 ? 'text-green-400' : reputation >= 40 ? 'text-yellow-400' : 'text-red-400'

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-zinc-100">Motoristas NPC</h2>
        <span className={`text-sm font-medium ${repColor}`}>
          Reputação: {reputation}/100
        </span>
      </div>

      {/* Toggle ilegal + botão contratar */}
      <div className="flex gap-2">
        {isOwner && (
          <button
            onClick={toggleIllegal}
            disabled={loading}
            className={`flex-1 rounded px-3 py-2 text-sm font-medium transition-colors ${
              allowIllegal
                ? 'bg-red-900 text-red-200 hover:bg-red-800'
                : 'bg-zinc-700 text-zinc-300 hover:bg-zinc-600'
            }`}
          >
            {allowIllegal ? 'Ilegais: ON' : 'Ilegais: OFF'}
          </button>
        )}
        {canManage && drivers.length < 5 && (
          <button
            onClick={() => setShowHire(true)}
            className="flex-1 bg-green-700 hover:bg-green-600 text-white rounded px-3 py-2 text-sm font-medium"
          >
            Contratar ({drivers.length}/5)
          </button>
        )}
      </div>

      {/* Lista de drivers */}
      {drivers.length === 0 ? (
        <p className="text-zinc-500 text-sm text-center py-4">Nenhum motorista contratado.</p>
      ) : (
        <div className="flex flex-col gap-2 overflow-auto max-h-[340px]">
          {drivers.map((d) => (
            <NpcDriverCard
              key={d.id}
              driver={d}
              canManage={canManage}
              onUpdated={refresh}
            />
          ))}
        </div>
      )}

      {showHire && (
        <NpcHireModal
          profiles={profiles}
          onClose={() => setShowHire(false)}
          onHired={() => { setShowHire(false); refresh() }}
        />
      )}
    </div>
  )
}
```

- [ ] **Step 4: Criar NpcEventAlert.tsx**

```tsx
import { useEffect, useState } from 'react'
import { useNpcDriverStore } from '../../../stores/useNpcDriverStore'
import { fetchNUI } from '../../../hooks/useNUI'

const EVENT_LABELS: Record<string, string> = {
  major_accident:    'Acidente Grave',
  cargo_stolen:      'Carga Roubada',
  contraband_caught: 'Contrabando Flagrado',
}

export function NpcEventAlert() {
  const { pendingEvent, setPendingEvent } = useNpcDriverStore()
  const [secondsLeft, setSecondsLeft]    = useState(0)
  const [loading, setLoading]            = useState(false)

  useEffect(() => {
    if (!pendingEvent) return
    const remaining = Math.max(0, pendingEvent.expiresAt - Math.floor(Date.now() / 1000))
    setSecondsLeft(remaining)
    const interval = setInterval(() => {
      setSecondsLeft((s) => {
        if (s <= 1) { clearInterval(interval); return 0 }
        return s - 1
      })
    }, 1000)
    return () => clearInterval(interval)
  }, [pendingEvent])

  if (!pendingEvent) return null

  async function respond(response: 'pay' | 'ignore') {
    if (!pendingEvent) return
    setLoading(true)
    await fetchNUI('npcRespondEvent', { eventId: pendingEvent.eventId, response })
    setPendingEvent(null)
    setLoading(false)
  }

  const mins = Math.floor(secondsLeft / 60)
  const secs = secondsLeft % 60
  const timeStr = `${mins}:${secs.toString().padStart(2, '0')}`

  return (
    <div className="fixed top-4 right-4 z-50 w-[340px] bg-zinc-900 border border-red-700 rounded-xl shadow-2xl p-4 flex flex-col gap-3 pointer-events-auto">
      <div className="flex justify-between items-center">
        <span className="text-red-400 font-bold text-sm">⚠ {EVENT_LABELS[pendingEvent.type] ?? pendingEvent.type}</span>
        <span className="text-zinc-400 text-xs font-mono">{timeStr}</span>
      </div>

      <p className="text-zinc-300 text-sm">
        <span className="font-medium text-zinc-100">{pendingEvent.driverName}</span>
        {pendingEvent.type === 'major_accident' && ` sofreu um acidente grave. Custo de reparo: $${pendingEvent.repairCost?.toLocaleString() ?? '?'}`}
        {pendingEvent.type === 'cargo_stolen'   && ` teve a carga roubada.`}
        {pendingEvent.type === 'contraband_caught' && ` foi flagrado com contrabando. Suborno: $${pendingEvent.bribeAmount?.toLocaleString() ?? '?'} (multa já aplicada)`}
      </p>

      <div className="flex gap-2">
        {pendingEvent.type === 'major_accident' && (
          <button
            onClick={() => respond('pay')}
            disabled={loading}
            className="flex-1 bg-blue-700 hover:bg-blue-600 text-white rounded px-3 py-2 text-sm font-medium disabled:opacity-50"
          >
            Pagar ${pendingEvent.repairCost?.toLocaleString()}
          </button>
        )}
        {pendingEvent.type === 'contraband_caught' && (
          <button
            onClick={() => respond('pay')}
            disabled={loading}
            className="flex-1 bg-blue-700 hover:bg-blue-600 text-white rounded px-3 py-2 text-sm font-medium disabled:opacity-50"
          >
            Pagar Suborno
          </button>
        )}
        <button
          onClick={() => respond('ignore')}
          disabled={loading}
          className="flex-1 bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded px-3 py-2 text-sm font-medium disabled:opacity-50"
        >
          Ignorar
        </button>
      </div>
    </div>
  )
}
```

- [ ] **Step 5: Commit**

```bash
git add html/src/components/company/NpcDriverPanel.tsx html/src/components/company/NpcDriverCard.tsx html/src/components/company/NpcHireModal.tsx html/src/components/overlay/NpcEventAlert.tsx
git commit -m "feat(npc-drivers): NUI components — NpcDriverPanel + NpcDriverCard + NpcHireModal + NpcEventAlert (Task 10)"
```

---

### Task 11: NUI Integration — TabBar + App.tsx

**Files:**
- Modify: `html/src/components/layout/TabBar.tsx`
- Modify: `html/src/App.tsx`

- [ ] **Step 1: Adicionar tab 'drivers' no TabBar.tsx**

Dentro de `const TABS: { id: TabName; label: string }[]`, adicionar após `{ id: 'convoy', label: 'Convoy' }`:

```tsx
    { id: 'drivers', label: 'Motoristas' },
```

- [ ] **Step 2: Adicionar NpcDriverPanel e NpcEventAlert no App.tsx**

No topo do arquivo, adicionar imports:

```tsx
import { NpcDriverPanel } from './components/company/NpcDriverPanel'
import { NpcEventAlert } from './components/overlay/NpcEventAlert'
```

Dentro do JSX, no `<div className="flex-1 overflow-auto p-4">`, adicionar linha:

```tsx
            {activeTab === 'drivers'    && <NpcDriverPanel />}
```

Antes do fechamento do `<>` externo (junto ao `<TruckHUD />`), adicionar:

```tsx
      <NpcEventAlert />
```

O App.tsx final ficará assim (apenas as partes modificadas):

```tsx
  return (
    <>
      <TruckHUD />
      <NpcEventAlert />
      <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
        <div className="pointer-events-auto w-[700px] h-[520px] bg-zinc-900 rounded-xl border border-zinc-700 shadow-2xl flex flex-col overflow-hidden">
          <TabBar />
          <div className="flex-1 overflow-auto p-4">
            {activeTab === 'jobs'       && <JobList />}
            {activeTab === 'missions'   && <RepoPanel />}
            {activeTab === 'active'     && <ActiveJob />}
            {activeTab === 'company'    && (company ? <CompanyPanel /> : <CompanySetup />)}
            {activeTab === 'garage'     && <GaragePanel />}
            {activeTab === 'industries' && <IndustryList />}
            {activeTab === 'stats'      && <StatsPanel />}
            {activeTab === 'convoy'     && <PartyPanel />}
            {activeTab === 'drivers'    && <NpcDriverPanel />}
          </div>
        </div>
      </div>
    </>
  )
```

- [ ] **Step 3: Commit**

```bash
git add html/src/components/layout/TabBar.tsx html/src/App.tsx
git commit -m "feat(npc-drivers): NUI integration — TabBar tab + App.tsx (Task 11)"
```

---

### Task 12: Build + fxmanifest v10.0.0 + CHANGELOG

**Files:**
- Modify: `fxmanifest.lua`
- Modify: `CHANGELOG.md`
- Build: `html/`

- [ ] **Step 1: Build da NUI**

```bash
cd html
npm run build
```

Verificar: sem erros TypeScript; `html/assets/` contém arquivos atualizados.

- [ ] **Step 2: Atualizar version em fxmanifest.lua**

Alterar:
```lua
version '6.1.0'
```
para:
```lua
version '10.0.0'
```

- [ ] **Step 3: Adicionar entrada no CHANGELOG.md**

Adicionar após a linha `# Changelog — AURP Trucker` e o separador inicial:

```markdown
## [10.0.0] — 2026-03-20

### Added
- **NPC Drivers (Fase 4 Sub-spec 1)**: sistema completo de motoristas NPC para empresas
  - Contratação via agência in-world (`agencyLocation`) com 3 perfis renovados a cada 24h
  - 3 níveis de skill: Junior (80% eficiência, 25% chance evento), Pleno (95%, 12%), Sênior (110%, 5%)
  - Evolução de nível via treinamento pago (+ requisito de XP por jobs completados)
  - Satisfação (0–100): sobe por jobs completados, cai por salário baixo/demandas ignoradas/eventos graves ignorados
  - Demandas por tenure: aumento salarial (15d), veículo melhor (30d), folga (60d), participação nos lucros (90d)
  - Eventos menores auto-resolvidos por skill (multa, acidente, combustível, atraso)
  - Eventos graves com decisão do jogador via overlay NUI com countdown de 5 minutos
  - Jobs ilegais opcionais por empresa com risco de flagrante (30%/15%/8% por nível)
  - Flagrante: multa automática + penalidade de reputação + alerta SALA para cops (job.name == 'sasp')
  - Reputação da empresa (0–100): sobe por deliveries legítimas (+1/+3), cai por contrabando flagrado (-10)
  - Blips animados de rota (interpolação server-side) para owners online
  - Peds ambientes na agência com ox_target para interação
  - Cron server-side a cada 5 minutos via SetInterval
  - Recuperação após restart: jobs em 'event' → failed; jobs expirados → CompleteJob automático
- `Config.NpcDrivers` block completo em `config/config.lua`
- 14 novos DB helpers em `server/database.lua`
- `server/services/npc_driver_service.lua` — global NpcDriverService
- `client/npc_driver.client.lua` — blips, peds, overlay de evento grave
- NUI: NpcDriverPanel, NpcDriverCard, NpcHireModal, NpcEventAlert, useNpcDriverStore
- Nova tab "Motoristas" no TabBar

### Modified
- `sql/import.sql`: tabelas `trucker_npc_drivers`, `trucker_npc_jobs`; colunas `reputation` e `allow_illegal_npc` em `trucker_companies`
- `server/events.lua`: handler `npcContrabandAlert` → alerta SALA via `AUST_trucker:client:policeAlert`
- `server/callbacks.lua`: 6 novos callbacks + `getInitialData` estendido com `npcDrivers`
- `server/main.lua`: cache `VP_Trucker.NpcDrivers/NpcJobs/PendingEvents/AgencyProfiles` + `NpcDriverService.LoadFromDB()`
- `fxmanifest.lua`: v10.0.0
```

- [ ] **Step 4: Commit final**

```bash
cd ..  # voltar para raiz do resource
git add html/assets/ html/index.html fxmanifest.lua CHANGELOG.md
git commit -m "feat(npc-drivers): build NUI + fxmanifest v10.0.0 + CHANGELOG (Task 12)"
```

- [ ] **Step 5: Verificação final in-game**

1. `restart AUST_trucker` — sem erros no console
2. Abrir PDA — tab "Motoristas" visível
3. Com empresa ativa: ir até `agencyLocation`, peds aparecem
4. Contratar motorista Junior → aparece na lista com satisfação 80
5. Aguardar 5 min (ou reduzir `cronIntervalMinutes = 1` temporariamente) → motorista recebe job, blip aparece no mapa
6. Aguardar conclusão do job → notificação "completou entrega — $X", balance da empresa sobe
7. Com `Config.Debug = true`: console mostra `NPC [nome] → job [id]` e `NPC [nome] completou job — $X`
