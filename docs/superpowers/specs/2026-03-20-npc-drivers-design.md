# NPC Drivers — Design Spec

**Fase:** 4 — Empresas (Sub-spec 1: NPC Drivers)
**Versão alvo:** 10.0.0
**Data:** 2026-03-20
**Depende de:** company_service.lua, loan_service.lua, illegal_service.lua (já implementados)

---

## Objetivo

Implementar motoristas NPC contratáveis pelas empresas de transporte: sistema de skill (Junior/Pleno/Sênior), satisfação/relacionamento, demandas por tempo de casa, simulação de rota server-side com blip animado, eventos aleatórios (menores auto-resolvidos, graves com decisão do jogador), integração com jobs ilegais e alerta SALA para contrabando, e presença in-world de peds na base da empresa.

---

## Arquitetura Geral

### Novos arquivos

| Ação | Arquivo |
|------|---------|
| CRIAR | `server/services/npc_driver_service.lua` |
| CRIAR | `client/npc_driver.client.lua` |

### Arquivos modificados

| Ação | Arquivo |
|------|---------|
| MODIFICAR | `server/database.lua` — novos DB helpers (listados abaixo) |
| MODIFICAR | `server/callbacks.lua` — callbacks hire/fire/respond/profile |
| MODIFICAR | `server/events.lua` — handler de alerta SALA de contrabando |
| MODIFICAR | `server/main.lua` — cache VP_Trucker.NpcDrivers/NpcJobs/PendingEvents/AgencyProfiles + chamar NpcDriverService.LoadFromDB() |
| MODIFICAR | `config/config.lua` — Config.NpcDrivers block |
| MODIFICAR | `html/src/` — NUI: seção Motoristas no CompanyPanel + NpcEventAlert overlay |
| MODIFICAR | `fxmanifest.lua` — v10.0.0, novo server/client script |
| MODIFICAR | `sql/import.sql` — novas tabelas + ALTER TABLE |

### Posição no fxmanifest (load order)

```lua
-- server_scripts (após illegal_service, antes de truck_simulation_service):
'server/services/illegal_service.lua',
'server/services/npc_driver_service.lua',   -- ← NOVO aqui
'server/services/truck_simulation_service.lua',

-- client_scripts (após repo.client.lua):
'client/repo.client.lua',
'client/npc_driver.client.lua',             -- ← NOVO aqui
'client/industries.client.lua',
```

`npc_driver_service.lua` depende de `CompanyService`, `IllegalService`, `DB_UpdateCompanyBalance` (todos carregados anteriormente). Não precisa de startup guard — `NpcDriverService.LoadFromDB()` é chamado em `main.lua` após `VP_Trucker.Ready = true`, antes de registrar o interval.

O `SetInterval` é registrado no **final de `npc_driver_service.lua`** (fora de qualquer função):
```lua
SetInterval(Config.NpcDrivers.cronIntervalMinutes * 60 * 1000, function()
    NpcDriverService.ProcessTick()
end)
```

---

## Schema SQL

```sql
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
    `active_job_id`     VARCHAR(36)  NULL DEFAULT NULL,  -- FK para trucker_npc_jobs.id
    `hired_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_demand_at`    INT          NULL DEFAULT NULL,   -- UNIX timestamp
    `last_tenure_check` INT          NULL DEFAULT NULL,   -- UNIX timestamp (dia UTC)
    `resting_until`     INT          NULL DEFAULT NULL,   -- UNIX timestamp (contrabando)
    FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- trucker_npc_jobs armazena os dados completos do job simulado (NÃO é FK de trucker_jobs).
-- Jobs NPC são virtuais: não são inseridos em trucker_jobs nem competem com jobs de jogadores.
CREATE TABLE IF NOT EXISTS `trucker_npc_jobs` (
    `id`              VARCHAR(36)  NOT NULL PRIMARY KEY,
    `driver_id`       VARCHAR(36)  NOT NULL,
    `company_id`      VARCHAR(36)  NOT NULL,
    `origin_id`       VARCHAR(64)  NOT NULL,   -- id da indústria de origem (Config.PrimaryIndustries)
    `dest_id`         VARCHAR(64)  NOT NULL,   -- id do destino (Config.SecondaryIndustries)
    `cargo_item`      VARCHAR(64)  NOT NULL,
    `base_payment`    INT          NOT NULL DEFAULT 0,
    `distance`        FLOAT        NOT NULL DEFAULT 0,
    `illegal`         TINYINT(1)   NOT NULL DEFAULT 0,
    `assigned_at`     INT          NOT NULL,   -- UNIX timestamp
    `expected_end_at` INT          NOT NULL,   -- UNIX timestamp
    `status`          ENUM('active','completed','failed','event') NOT NULL DEFAULT 'active',
    `earnings`        INT          NOT NULL DEFAULT 0,
    FOREIGN KEY (`driver_id`) REFERENCES `trucker_npc_drivers`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Colunas adicionais em `trucker_companies`:**
```sql
ALTER TABLE `trucker_companies`
    ADD COLUMN IF NOT EXISTS `reputation`        TINYINT(3) UNSIGNED NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS `allow_illegal_npc` TINYINT(1)          NOT NULL DEFAULT 0;
```

---

## DB Helpers (server/database.lua)

Todos os helpers seguem o padrão do projeto: `MySQL.query.await` / `MySQL.update.await` / `MySQL.insert.await`.

```lua
-- NPC Drivers
function DB_InsertNpcDriver(driver)           -- INSERT INTO trucker_npc_drivers
function DB_GetNpcDriversByCompany(companyId) -- SELECT WHERE company_id = ?
function DB_GetAllActiveNpcDrivers()          -- SELECT WHERE status IN ('idle','working','resting')
function DB_UpdateNpcDriverStatus(id, status, activeJobId)  -- UPDATE status + active_job_id
function DB_UpdateNpcDriverStats(id, xpGain, satisfactionDelta, totalEarningsGain)
function DB_UpdateNpcDriverSatisfaction(id, satisfaction)
function DB_UpdateNpcDriverTenure(id, tenureDays, lastTenureCheck)
function DB_UpdateNpcDriverSalary(id, salary)
function DB_SetNpcDriverQuit(id)              -- UPDATE status = 'quit', active_job_id = NULL
function DB_SetNpcDriverResting(id, restingUntil)

-- NPC Jobs
function DB_InsertNpcJob(npcJob)              -- INSERT INTO trucker_npc_jobs
function DB_UpdateNpcJobStatus(id, status, earnings)
function DB_GetNpcJobsByStatus(status)        -- para LoadFromDB recovery

-- Empresa
function DB_UpdateCompanyReputation(companyId, delta)
-- Implementação: UPDATE SET reputation = GREATEST(0, LEAST(100, reputation + ?) WHERE id = ?
-- Após update: ler valor novo e atualizar VP_Trucker.Companies[companyId].reputation
-- Nota: DB_UpdateCompanyBalance (já existente) é usado em CompleteJob para creditar earnings
```

---

## Config.NpcDrivers

```lua
Config.NpcDrivers = {
    maxDriversPerCompany = 5,
    agencyLocation       = vector3(-179.0, -1320.0, 31.3),  -- Configurável
    agencyRadius         = 15.0,   -- raio de validação para contratação
    agencyHeading        = 270.0,
    agencyPedModel       = 's_m_m_trucker_01',
    basePedModel         = 's_m_m_trucker_01',
    agencyRefreshSeconds = 86400,  -- 24h em segundos para renovar perfis
    cronIntervalMinutes  = 5,      -- frequência do ProcessTick

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

    -- Divisor de duração do job (job_duration / speedFactor = duração real do NPC)
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
        startValue           = 80,
        gainPerJob           = 3,
        decayPerDayLowSalary = 1,
        penaltyDemandIgnored = 5,
        penaltyEventIgnored  = 10,
        gainDemandGranted    = 8,
        lowThreshold         = 40,   -- abaixo: eventChance dobra
        criticalThreshold    = 20,   -- abaixo: 10%/dia de pedir demissão
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
        driverRestSeconds = 86400,   -- 24h em segundos
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

---

## NpcDriverService

### Cache em `VP_Trucker` (inicializado em `main.lua`)

```lua
VP_Trucker.NpcDrivers     = {}  -- { [driverId] = driverRow }
VP_Trucker.NpcJobs        = {}  -- { [npcJobId] = npcJobRow }
VP_Trucker.PendingEvents  = {}  -- { [eventId]  = { driverId, type, expiresAt, ... } }
VP_Trucker.AgencyProfiles = {}  -- { profiles = [...], generatedAt = unixTimestamp }
```

`driverRow` no cache inclui todos os campos da tabela mais `activeJobId` (alias de `active_job_id`).

### LoadFromDB — recuperação após restart

Chamado em `main.lua` após `VP_Trucker.Ready = true`:

```lua
function NpcDriverService.LoadFromDB()
    -- 1. Carregar todos os drivers ativos no cache
    local drivers = DB_GetAllActiveNpcDrivers() or {}
    for _, d in ipairs(drivers) do
        VP_Trucker.NpcDrivers[d.id] = d
    end

    -- 2. Recuperar NPC jobs em status 'event' → auto-fail (evento perdido no restart)
    local eventJobs = DB_GetNpcJobsByStatus('event') or {}
    for _, j in ipairs(eventJobs) do
        DB_UpdateNpcJobStatus(j.id, 'failed', 0)
        local driver = VP_Trucker.NpcDrivers[j.driver_id]
        if driver then
            driver.status      = 'idle'
            driver.activeJobId = nil
            DB_UpdateNpcDriverStatus(j.driver_id, 'idle', nil)
        end
    end

    -- 3. Recuperar NPC jobs em status 'active' com expected_end_at passado → processar como completo
    -- Nota: DB_GetNpcJobsByStatus('active') retorna TODOS os jobs ativos de todas as empresas.
    -- Isso é aceitável pois o limite é 5 drivers × N empresas (escala controlada).
    local activeJobs = DB_GetNpcJobsByStatus('active') or {}
    local now = os.time()
    for _, j in ipairs(activeJobs) do
        VP_Trucker.NpcJobs[j.id] = j
        if j.expected_end_at <= now then
            -- Job expirado durante offline: completar sem evento (benefício da dúvida)
            local driver = VP_Trucker.NpcDrivers[j.driver_id]
            if driver then
                NpcDriverService._CompleteJob(driver, j)
            end
        end
    end

    -- 4. Verificar drivers 'resting' com resting_until passado → voltar para 'idle'
    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        if driver.status == 'resting' and driver.resting_until and driver.resting_until <= now then
            driver.status = 'idle'
            DB_UpdateNpcDriverStatus(id, 'idle', nil)
        end
    end
end
```

### API pública

```lua
NpcDriverService = {}

function NpcDriverService.LoadFromDB()
function NpcDriverService.ProcessTick()
function NpcDriverService.Hire(src, companyId, profileIndex)     -- valida, desconta, insere
function NpcDriverService.Fire(src, companyId, driverId)
function NpcDriverService.GetAgencyProfiles()                    -- renova se agencyRefreshSeconds expirado
function NpcDriverService.GetByCompany(companyId)               -- retorna drivers + jobs ativos
function NpcDriverService.RespondToEvent(src, eventId, response) -- response: 'pay'|'ignore'
function NpcDriverService.Train(src, companyId, driverId)
function NpcDriverService.SetAllowIllegal(src, companyId, allowed)

-- Privadas (prefixo _):
function NpcDriverService._TryAssignJob(driver)
function NpcDriverService._RollEvent(driver, npcJob)
function NpcDriverService._HandleMinorEvent(driver, npcJob, eventType)
function NpcDriverService._HandleGraveEvent(driver, npcJob, eventType)
function NpcDriverService._CompleteJob(driver, npcJob)
function NpcDriverService._CheckTenure(driver)
function NpcDriverService._ApplySatisfactionDecay(driver)
function NpcDriverService._CheckQuitRisk(driver)
function NpcDriverService._BroadcastPositions()
```

### ProcessTick

```lua
function NpcDriverService.ProcessTick()
    local now = os.time()

    for id, driver in pairs(VP_Trucker.NpcDrivers) do
        -- Drivers em resting: verificar se tempo acabou
        if driver.status == 'resting' and driver.resting_until and driver.resting_until <= now then
            driver.status = 'idle'
            DB_UpdateNpcDriverStatus(id, 'idle', nil)
        end

        -- Drivers working: verificar se job concluiu (ignorar jobs pausados em 'event')
        if driver.status == 'working' and driver.activeJobId then
            local npcJob = VP_Trucker.NpcJobs[driver.activeJobId]
            if npcJob and npcJob.status ~= 'event' and now >= npcJob.expected_end_at then
                NpcDriverService._RollEvent(driver, npcJob)
            end
        end

        -- Drivers idle: tentar atribuir job
        if driver.status == 'idle' then
            NpcDriverService._TryAssignJob(driver)
        end

        -- Rotina diária (last_tenure_check = dia em UNIX — comparado por dia, não hora)
        local today = math.floor(now / 86400)  -- dia UTC
        local lastCheck = math.floor((driver.last_tenure_check or 0) / 86400)
        if today > lastCheck then
            NpcDriverService._CheckTenure(driver)
            NpcDriverService._ApplySatisfactionDecay(driver)
            NpcDriverService._CheckQuitRisk(driver)
            driver.last_tenure_check = now
            DB_UpdateNpcDriverTenure(id, driver.tenure_days, now)
        end
    end

    -- Broadcast de posições para owners online com drivers working
    NpcDriverService._BroadcastPositions()
end
```

### _TryAssignJob

```lua
function NpcDriverService._TryAssignJob(driver)
    local company = VP_Trucker.Companies[driver.company_id]  -- cache existente
    if not company then return end

    -- Buscar job disponível (ilegal se empresa permite)
    local job = nil
    if company.allow_illegal_npc == 1 then
        -- Tentar job ilegal com probabilidade proporcional ao skill
        -- ... lógica similar ao GenerateOne() mas escolhe de pool available incluindo illegal
    end
    if not job then
        -- Fallback: job normal da pool available
        job = DB_GetOneAvailableJobForNpc()  -- SELECT FROM trucker_jobs WHERE status='available' LIMIT 1
    end
    if not job then return end

    -- Marcar trucker_job como 'active' com assigned_citizenid = 'npc_' .. driver.id
    -- (evita que jogador humano pegue o mesmo job enquanto NPC executa)
    local baseDuration = job.distance / 0.5  -- segundos estimados (30km/h média)
    local duration = math.floor(baseDuration / Config.NpcDrivers.skillSpeedFactor[driver.skill_level])

    local npcJobId = NewUUID()
    local npcJob = {
        id             = npcJobId,
        driver_id      = driver.id,
        company_id     = driver.company_id,
        origin_id      = job.origin_id,
        dest_id        = job.dest_id,
        cargo_item     = job.cargo_item,
        base_payment   = job.base_payment,
        distance       = job.distance,
        illegal        = job.illegal_type and 1 or 0,
        assigned_at    = os.time(),
        expected_end_at = os.time() + duration,
        status         = 'active',
        earnings       = 0,
    }

    DB_InsertNpcJob(npcJob)
    VP_Trucker.NpcJobs[npcJobId] = npcJob
    driver.status      = 'working'
    driver.activeJobId = npcJobId
    DB_UpdateNpcDriverStatus(driver.id, 'working', npcJobId)
end
```

### _CompleteJob

```lua
function NpcDriverService._CompleteJob(driver, npcJob)
    local earnings = math.floor(npcJob.base_payment * Config.NpcDrivers.skillEfficiency[driver.skill_level])

    -- Creditar empresa: DB_UpdateCompanyBalance NÃO atualiza o cache automaticamente.
    -- O implementor deve atualizar o cache manualmente após o UPDATE (padrão do projeto).
    DB_UpdateCompanyBalance(npcJob.company_id, earnings)
    if VP_Trucker.Companies[npcJob.company_id] then
        VP_Trucker.Companies[npcJob.company_id].balance =
            (VP_Trucker.Companies[npcJob.company_id].balance or 0) + earnings
    end

    -- Reputação (apenas jobs legítimos)
    if npcJob.illegal == 0 then
        local repGain = npcJob.distance >= Config.NpcDrivers.reputation.longJobDistanceKm
            and Config.NpcDrivers.reputation.gainPerLongJob
            or  Config.NpcDrivers.reputation.gainPerNormalJob
        DB_UpdateCompanyReputation(npcJob.company_id, repGain)
    end

    -- Atualizar driver
    local xpGain    = 1
    local satGain   = Config.NpcDrivers.satisfaction.gainPerJob
    driver.xp            = driver.xp + xpGain
    driver.satisfaction  = math.min(100, driver.satisfaction + satGain)
    driver.total_earnings = driver.total_earnings + earnings
    driver.status        = 'idle'
    driver.activeJobId   = nil

    DB_UpdateNpcJobStatus(npcJob.id, 'completed', earnings)
    DB_UpdateNpcDriverStats(driver.id, xpGain, satGain, earnings)
    DB_UpdateNpcDriverStatus(driver.id, 'idle', nil)
    VP_Trucker.NpcJobs[npcJob.id] = nil

    -- Liberar trucker_job de volta para pool
    MySQL.update.await("UPDATE trucker_jobs SET status='available', assigned_citizenid=NULL WHERE assigned_citizenid=?",
        { 'npc_' .. driver.id })

    -- Notificar owner online
    local company = VP_Trucker.Companies[npcJob.company_id]
    if company and company.owner_src then  -- owner_src resolvido via GetPlayers() lookup
        TriggerClientEvent('AUST_trucker:client:npcDriverJobCompleted', company.owner_src, {
            driverName = driver.name,
            earnings   = earnings,
            skillLevel = driver.skill_level,
        })
    end
end
```

### _HandleGraveEvent

```lua
function NpcDriverService._HandleGraveEvent(driver, npcJob, eventType)
    local eventId = NewUUID()
    local expiresAt = os.time() + Config.NpcDrivers.graveEventTimerSeconds

    -- Atualizar status do job para 'event' (pausado aguardando resposta)
    -- CRÍTICO: atualizar cache também para que ProcessTick não re-role evento no mesmo job
    npcJob.status = 'event'
    DB_UpdateNpcJobStatus(npcJob.id, 'event', 0)

    -- Preparar payload
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
        -- Efeitos imediatos do contrabando (independente da decisão do jogador)
        DB_UpdateCompanyReputation(npcJob.company_id, -Config.NpcDrivers.contraband.reputationPenalty)
        DB_UpdateCompanyBalance(npcJob.company_id, -Config.NpcDrivers.contraband.fineAmount)
        if VP_Trucker.Companies[npcJob.company_id] then
            VP_Trucker.Companies[npcJob.company_id].balance =
                (VP_Trucker.Companies[npcJob.company_id].balance or 0) - Config.NpcDrivers.contraband.fineAmount
        end
        -- Alerta SALA — mesmo padrão de IllegalService.BroadcastAlert
        local companyName = VP_Trucker.Companies[npcJob.company_id] and
                            VP_Trucker.Companies[npcJob.company_id].name or '?'
        local originCfg = nil
        for _, o in ipairs(Config.PrimaryIndustries) do
            if o.id == npcJob.origin_id then originCfg = o; break end
        end
        local areaName = originCfg and originCfg.name or npcJob.origin_id
        TriggerEvent('AUST_trucker:npcContrabandAlert', {
            companyName = companyName,
            driverName  = driver.name,
            area        = areaName,
            illegalType = npcJob.cargo_item,
        })
    end

    VP_Trucker.PendingEvents[eventId] = { driver = driver, npcJob = npcJob, payload = payload }

    -- Notificar owner online
    local company = VP_Trucker.Companies[npcJob.company_id]
    if company and company.owner_src then
        TriggerClientEvent('AUST_trucker:client:npcGraveEvent', company.owner_src, payload)
    end

    -- Auto-resolver como 'ignore' após timer
    SetTimeout(Config.NpcDrivers.graveEventTimerSeconds * 1000, function()
        if VP_Trucker.PendingEvents[eventId] then
            NpcDriverService.RespondToEvent(nil, eventId, 'ignore')
        end
    end)
end
```

---

## Alerta SALA (server/events.lua)

Usa o mesmo padrão de `IllegalService.BroadcastAlert` — itera jogadores online filtrando por job `sasp`:

```lua
-- Em server/events.lua:
AddEventHandler('AUST_trucker:npcContrabandAlert', function(data)
    local label = (Config.IllegalJobs.alertLabels and Config.IllegalJobs.alertLabels[data.illegalType])
               or data.illegalType or '?'
    local msg = ('[SALA] Empresa %s — suspeita de contrabando (%s) na região de %s.')
        :format(data.companyName, label, data.area)

    local players = exports.qbx_core:GetQBPlayers() or {}
    for _, player in pairs(players) do
        if player.PlayerData.job and player.PlayerData.job.name == 'sasp' then
            TriggerClientEvent('AUST_trucker:client:policeAlert', player.PlayerData.source,
                { message = msg })
        end
    end
end)
```

> **Nota:** reutiliza o evento `AUST_trucker:client:policeAlert` já registrado em `illegal.client.lua` — sem novo handler client-side necessário.

---

## Validação de Proximidade para Contratação

O callback `hireNpcDriver` recebe as coordenadas do player enviadas pelo client:

```lua
-- Client (npc_driver.client.lua):
lib.callback.await('AUST_trucker:hireNpcDriver', false, profileIndex, {
    x = GetEntityCoords(PlayerPedId()).x,
    y = GetEntityCoords(PlayerPedId()).y,
    z = GetEntityCoords(PlayerPedId()).z,
})

-- Server (callbacks.lua):
lib.callback.register('AUST_trucker:hireNpcDriver', function(source, profileIndex, playerCoords)
    local agency = Config.NpcDrivers.agencyLocation
    local dx = playerCoords.x - agency.x
    local dy = playerCoords.y - agency.y
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist > Config.NpcDrivers.agencyRadius then
        return { success = false, reason = 'Você precisa estar na agência de emprego' }
    end
    -- ... NpcDriverService.Hire(...)
end)
```

> Coordenadas vêm do client mas a validação é server-side contra Config fixo — risco de spoofing aceitável para esta feature (não é transação financeira crítica).

---

## Client — `client/npc_driver.client.lua`

### Estado local

```lua
local NpcDriverState = {
    activeDriverBlips = {},  -- { [driverId] = blipHandle }
    basePeds          = {},  -- { [driverId] = pedHandle }
    inBaseZone        = false,
    baseZoneId        = nil,
}
```

### Blips de rota

- Recebe `AUST_trucker:client:npcPositionUpdate` com `{ [driverId] = { x, y, z, name, status } }`
- Cria blip se `status == 'working'`, remove se não
- Blip: sprite `Config.NpcDrivers.blipSprite`, escala `Config.NpcDrivers.blipScale`, label = nome do driver

### Peds na base

- Zona `lib.zones.sphere` no `company.base_coords` (raio 20m) criada quando `getInitialData` retorna empresa
- `onEnter`: buscar drivers idle via `lib.callback.await('AUST_trucker:getNpcDriverData')`, spawn peds
- `onExit`: delete peds via `DeletePed`, limpar `basePeds`
- ox_target por ped:
  - `"Ver Perfil"` → `SendNUIMessage({ action = 'focusNpcDriver', driverId = id })`
  - `"Negociar"` → `SendNUIMessage({ action = 'openNpcDemand', driverId = id })` (só se demanda ativa)

### Evento grave — painel NUI flutuante

- `AUST_trucker:client:npcGraveEvent` → `SendNUIMessage({ action = 'npcGraveEvent', event = data })`
- NUI exibe overlay com countdown regressivo (5 min), descrição, botões de decisão
- Resposta → `lib.callback.await('AUST_trucker:npcRespondEvent', false, eventId, response)`
- `AUST_trucker:client:npcEventResolved` → `SendNUIMessage({ action = 'npcEventResolved', eventId = id })`

---

## Callbacks Server (server/callbacks.lua)

```lua
lib.callback.register('AUST_trucker:getNpcDriverData', function(source)
    -- valida empresa, retorna { profiles, drivers, companyReputation, allowIllegal }
end)

lib.callback.register('AUST_trucker:hireNpcDriver', function(source, profileIndex, playerCoords)
    -- valida raio, valida empresa, NpcDriverService.Hire(...)
end)

lib.callback.register('AUST_trucker:fireNpcDriver', function(source, driverId)
    -- NpcDriverService.Fire(src, companyId, driverId)
end)

lib.callback.register('AUST_trucker:trainNpcDriver', function(source, driverId)
    -- NpcDriverService.Train(src, companyId, driverId)
end)

lib.callback.register('AUST_trucker:setNpcAllowIllegal', function(source, allowed)
    -- NpcDriverService.SetAllowIllegal(src, companyId, allowed)
end)

lib.callback.register('AUST_trucker:npcRespondEvent', function(source, eventId, response)
    -- NpcDriverService.RespondToEvent(src, eventId, response)
end)
```

---

## Eventos de Rede

### Server → Client (owner da empresa)

| Evento | Payload | Quando |
|--------|---------|--------|
| `AUST_trucker:client:npcPositionUpdate` | `{ [driverId] = {x,y,z,name,status} }` | A cada 15s via ProcessTick |
| `AUST_trucker:client:npcGraveEvent` | `{ eventId, driverId, driverName, type, repairCost?, bribeAmount?, expiresAt }` | Evento grave ocorre |
| `AUST_trucker:client:npcEventResolved` | `{ eventId, resolution }` | Após resposta ou timeout |
| `AUST_trucker:client:npcDriverJobCompleted` | `{ driverName, earnings, skillLevel }` | Job concluído sem evento |
| `AUST_trucker:client:npcDriverQuit` | `{ driverName }` | Driver pediu demissão |
| `AUST_trucker:client:npcDemandGenerated` | `{ driverName, demandType }` | Nova demanda de tenure |

### Server → Cops (via AUST_trucker:client:policeAlert — já existente)

Emitido pelo handler de `AUST_trucker:npcContrabandAlert` em `events.lua` para todos os jogadores `job.name == 'sasp'`. Reutiliza handler client-side já registrado em `illegal.client.lua`.

---

## NUI — Mudanças no Frontend

### Novos tipos TypeScript

```typescript
type SkillLevel = 'junior' | 'pleno' | 'senior'
type DriverStatus = 'idle' | 'working' | 'resting' | 'fired' | 'quit'
type DemandType = 'salary_raise' | 'better_vehicle' | 'rest_day' | 'profit_share'

interface NpcDriver {
  id: string
  name: string
  skillLevel: SkillLevel
  salary: number
  satisfaction: number      // 0–100
  xp: number
  tenureDays: number
  totalEarnings: number     // acumulado em trucker_npc_drivers.total_earnings
  status: DriverStatus
  demand?: { type: DemandType; value?: number; expiresAt: number }
  activeJob?: { origin: string; dest: string; expectedEndAt: number }
}

interface AgencyProfile {
  index: number
  name: string
  skillLevel: SkillLevel
  salary: number
  hireCost: number
}

interface NpcGraveEvent {
  eventId: string
  driverId: string
  driverName: string
  type: 'major_accident' | 'cargo_stolen' | 'contraband_caught'
  repairCost?: number
  bribeAmount?: number
  expiresAt: number
}
```

### Novos componentes

| Arquivo | Responsabilidade |
|---------|-----------------|
| `html/src/components/company/NpcDriverPanel.tsx` | Lista de drivers, botão contratar, badge reputação |
| `html/src/components/company/NpcDriverCard.tsx` | Card: barra de satisfação, badge skill, demanda ativa, toggle treinar/demitir |
| `html/src/components/company/NpcHireModal.tsx` | Modal com 3 perfis da agência |
| `html/src/components/overlay/NpcEventAlert.tsx` | Overlay flutuante com countdown e botões de decisão |

### Store

- `html/src/stores/useNpcDriverStore.ts`:
  ```typescript
  { drivers, agencyProfiles, pendingEvent, companyReputation, allowIllegal, setDrivers, setPendingEvent, ... }
  ```

### Integração no App

- Nova tab "Motoristas" no `TabBar` com ícone `fas fa-id-card`
- `NpcDriverPanel` renderizado quando tab ativa
- `NpcEventAlert` renderizado **sempre** (overlay fixo, independente de tab ativa)
- Badge de reputação da empresa visível no header do `CompanyPanel`

---

## Fora de Escopo

- Rotas físicas reais (veículo dirigindo no mapa) — futuro
- Sistema de seguro de carga — futuro
- Múltiplos turnos/horários de trabalho — futuro
- Dashboard financeiro com gráficos e histórico — spec separado (Fase 4 Sub-spec 2)
