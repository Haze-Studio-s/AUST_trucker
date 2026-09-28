# Fase Final — Comercial (v17.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar AUST_trucker comercialmente distribuível: suporte a ESX/QBCore via bridge de framework, auto-criação de tabelas no boot, performance 0.00ms idle, e documentação de instalação completa.

**Architecture:** (A) `server/framework.lua` global `Framework = {}` implementado por config; substituição mecânica via sed + edits manuais. (B) `server/schema.lua` com `SchemaService.EnsureTables()` chamado em `MySQL.ready`. (C) Auditoria de threads. (D) Docs.

**Tech Stack:** FiveM lua54, QBX/QBCore/ESX (bridge), oxmysql, ox_lib.

**Spec:** `docs/superpowers/specs/2026-03-21-fase-final-comercial-design.md`

---

## File Map

| Arquivo | Papel |
|---|---|
| `server/framework.lua` | NEW — Framework global com implementações QBX/QBCore/ESX |
| `server/schema.lua` | NEW — SchemaService.EnsureTables() |
| `server/main.lua` | Chamar SchemaService no boot |
| `config/config.lua` | + Config.Framework = 'qbx' |
| `fxmanifest.lua` | + framework.lua + schema.lua; qbx_core opcional |
| `server/events.lua` | Replace framework calls |
| `server/callbacks.lua` | Replace framework calls |
| `server/services/*.lua` | Replace framework calls (13 arquivos) |
| `README.md` | Reescrever |
| `GUIA_JOGADOR.md` | Atualizar |
| `GUIA_STAFF.md` | Atualizar |
| `CHANGELOG.md` | v17.0.0 |

---

## Task 1: Config.Framework + fxmanifest

**Files:**
- Modify: `config/config.lua`
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Adicionar Config.Framework**

No início de `config/config.lua`, após `Config = {}`:
```lua
-- Framework suportado: 'qbx' | 'qbcore' | 'esx'
Config.Framework = 'qbx'
```

- [ ] **Step 2: Atualizar fxmanifest**

Remover `'qbx_core'` de `dependencies`.
Adicionar `'server/framework.lua'` e `'server/schema.lua'` como primeiros server_scripts
(antes de `server/main.lua`):

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',     -- ← NOVO (antes de main)
    'server/schema.lua',        -- ← NOVO (antes de main)
    'server/main.lua',
    ...
}
```

- [ ] **Step 3: Commit**
```bash
git add config/config.lua fxmanifest.lua
git commit -m "feat(17): Config.Framework; add framework.lua and schema.lua to fxmanifest"
```

---

## Task 2: server/framework.lua — Framework global

**Files:**
- Create: `server/framework.lua`

- [ ] **Step 1: Criar o arquivo**

```lua
-- AUST_trucker — server/framework.lua
-- Camada de abstração de framework: QBX | QBCore | ESX
-- Carregado antes de todos os services (ver fxmanifest load order)
-- IMPORTANTE: Config.Framework deve estar definido em config/config.lua

Framework = {}

local fw = Config.Framework or 'qbx'

-- ============================================================
-- QBX / QBCore
-- ============================================================
if fw == 'qbx' or fw == 'qbcore' then

    local core = fw == 'qbx'
        and exports.qbx_core
        or QBCore and QBCore.Functions

    local function GetCorePlayer(src)
        if fw == 'qbx' then
            return exports.qbx_core:GetPlayer(src)
        else
            return QBCore.Functions.GetPlayer(src)
        end
    end

    Framework.GetPlayer = function(src)
        return GetCorePlayer(src)
    end

    Framework.FindPlayerByCitizenId = function(citizenId)
        for _, pid in ipairs(GetPlayers()) do
            local P = GetCorePlayer(tonumber(pid))
            if P and P.PlayerData.citizenid == citizenId then
                return tonumber(pid)
            end
        end
        return nil
    end

    Framework.GetCitizenId = function(player)
        return player and player.PlayerData.citizenid
    end

    Framework.GetCharInfo = function(player)
        if not player then return nil end
        return player.PlayerData.charinfo
    end

    Framework.GetJob = function(player)
        return player and player.PlayerData.job or { name = '', label = '' }
    end

    Framework.AddMoney = function(player, account, amount, reason)
        if not player then return end
        player.Functions.AddMoney(account, amount, reason)
    end

    Framework.RemoveMoney = function(player, account, amount, reason)
        if not player then return false end
        return player.Functions.RemoveMoney(account, amount, reason)
    end

    Framework.GetMoney = function(player, account)
        if not player then return 0 end
        return player.Functions.GetMoney(account) or 0
    end

    Framework.HasMoney = function(player, account, amount)
        return Framework.GetMoney(player, account) >= amount
    end

-- ============================================================
-- ESX
-- ============================================================
elseif fw == 'esx' then

    local ESX = nil
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

    -- Fallback se TriggerEvent não preencheu (ESX Legacy usa exports)
    if not ESX then
        ESX = exports['es_extended']:getSharedObject()
    end

    Framework.GetPlayer = function(src)
        return ESX.GetPlayerFromId(src)
    end

    Framework.FindPlayerByCitizenId = function(citizenId)
        for _, pid in ipairs(GetPlayers()) do
            local xP = ESX.GetPlayerFromId(tonumber(pid))
            if xP and xP.getIdentifier() == citizenId then
                return tonumber(pid)
            end
        end
        return nil
    end

    Framework.GetCitizenId = function(player)
        return player and player.getIdentifier()
    end

    Framework.GetCharInfo = function(player)
        if not player then return nil end
        local name = player.getName()
        local parts = {}
        for part in name:gmatch('%S+') do parts[#parts + 1] = part end
        return {
            firstname = parts[1] or '',
            lastname  = parts[2] or '',
        }
    end

    Framework.GetJob = function(player)
        return player and player.job or { name = '', label = '' }
    end

    Framework.AddMoney = function(player, account, amount, reason)
        if not player then return end
        if account == 'cash' then
            player.addMoney(amount)
        else
            player.addAccountMoney('bank', amount)
        end
    end

    Framework.RemoveMoney = function(player, account, amount, reason)
        if not player then return false end
        local have = Framework.GetMoney(player, account)
        if have < amount then return false end
        if account == 'cash' then
            player.removeMoney(amount)
        else
            player.removeAccountMoney('bank', amount)
        end
        return true
    end

    Framework.GetMoney = function(player, account)
        if not player then return 0 end
        if account == 'cash' then return player.getMoney() or 0 end
        local acc = player.getAccount('bank')
        return acc and acc.money or 0
    end

    Framework.HasMoney = function(player, account, amount)
        return Framework.GetMoney(player, account) >= amount
    end

else
    error(('[AUST_trucker] Config.Framework inválido: "%s". Use "qbx", "qbcore" ou "esx"'):format(fw))
end

if Config.Debug then
    print(('[AUST_trucker] Framework: %s'):format(fw))
end
```

- [ ] **Step 2: Commit**
```bash
git add server/framework.lua
git commit -m "feat(17A): Framework global — QBX/QBCore/ESX abstraction layer"
```

---

## Task 3: Substituição mecânica de framework calls (sed)

**Files:**
- Modify: todos os `server/**/*.lua`

Executar os comandos a seguir na raiz do resource. Cada sed opera em todos os arquivos Lua server-side.

- [ ] **Step 1: Substituir GetPlayer**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/exports\.qbx_core:GetPlayer(\(.*\))/Framework.GetPlayer(\1)/g' {} \;
```

- [ ] **Step 2: Substituir AddMoney**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/\([A-Za-z_][A-Za-z0-9_]*\)\.Functions\.AddMoney(/Framework.AddMoney(\1, /g' {} \;
```

- [ ] **Step 3: Substituir RemoveMoney**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/\([A-Za-z_][A-Za-z0-9_]*\)\.Functions\.RemoveMoney(/Framework.RemoveMoney(\1, /g' {} \;
```

- [ ] **Step 4: Substituir GetMoney**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/\([A-Za-z_][A-Za-z0-9_]*\)\.Functions\.GetMoney(/Framework.GetMoney(\1, /g' {} \;
```

- [ ] **Step 5: Substituir .PlayerData.citizenid**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/\([A-Za-z_][A-Za-z0-9_]*\)\.PlayerData\.citizenid/Framework.GetCitizenId(\1)/g' {} \;
```

- [ ] **Step 6: Substituir .PlayerData.charinfo**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/\([A-Za-z_][A-Za-z0-9_]*\)\.PlayerData\.charinfo/Framework.GetCharInfo(\1)/g' {} \;
```

- [ ] **Step 7: Substituir .PlayerData.money.cash**
```bash
find "server" -name "*.lua" -exec sed -i \
  "s/\([A-Za-z_][A-Za-z0-9_]*\)\.PlayerData\.money\.cash/Framework.GetMoney(\1, 'cash')/g" {} \;
```

- [ ] **Step 8: Substituir .PlayerData.job.name**
```bash
find "server" -name "*.lua" -exec sed -i \
  's/\([A-Za-z_][A-Za-z0-9_]*\)\.PlayerData\.job\.name/Framework.GetJob(\1).name/g' {} \;
```

- [ ] **Step 9: Verificar que não restaram referências diretas**
```bash
grep -rn "qbx_core\|\.PlayerData\.\|\.Functions\." server/ --include="*.lua" | grep -v "framework.lua"
```
Esperado: zero resultados (ou apenas comentários).

- [ ] **Step 10: Commit**
```bash
git add server/
git commit -m "feat(17A): replace all direct framework calls with Framework.* API"
```

---

## Task 4: FindPlayerByCitizenId — substituir broadcast loops

**Files:**
- Modify: `server/services/repo_service.lua`, `server/services/loan_service.lua`,
  `server/events.lua`, `server/callbacks.lua`

Identificar todos os blocos:
```lua
local players = GetPlayers()
for _, pid in ipairs(players) do
    local P = Framework.GetPlayer(tonumber(pid))
    if P and Framework.GetCitizenId(P) == targetCid then
        -- ação pontual com tonumber(pid)
        break
    end
end
```
E substituir por:
```lua
local targetPid = Framework.FindPlayerByCitizenId(targetCid)
if targetPid then
    -- ação pontual com targetPid
end
```

**NOTA:** Loops que iteram TODOS os players (ex: `BroadcastAvailableOrders`) NÃO devem ser convertidos — apenas os loops que buscam UM player específico por citizenId.

- [ ] **Step 1: Localizar e substituir em repo_service.lua**

Os blocos de `Complete`, `Fail`, `CheckOverdue notify` usam este padrão para:
- Notificar dono do veículo (`vehicle_owner_citizenid`)
- Notificar dono do empréstimo (`loan.citizenid`)

Substituir cada bloco "find player by citizenId + notify + break" pela forma compacta.

- [ ] **Step 2: Localizar e substituir em loan_service.lua**

`CheckOverdue` notifica o player do empréstimo — substituir loop por `FindPlayerByCitizenId`.

- [ ] **Step 3: Localizar e substituir em events.lua e callbacks.lua**

Buscar outros padrões `GetPlayers() + GetPlayer(pid) + citizenid == X + break`.

- [ ] **Step 4: Verificar manualmente charinfo edge case em events.lua**

O handler `repoNotifyOwner` usa:
```lua
local agentName = Framework.GetCharInfo(Player)
    and (Framework.GetCharInfo(Player).firstname .. ' ' .. Framework.GetCharInfo(Player).lastname)
    or 'Agente'
```
Otimizar para:
```lua
local charInfo  = Framework.GetCharInfo(Player)
local agentName = charInfo and (charInfo.firstname .. ' ' .. charInfo.lastname) or 'Agente'
```

- [ ] **Step 5: Commit**
```bash
git add server/
git commit -m "feat(17A): replace targeted GetPlayers loops with Framework.FindPlayerByCitizenId"
```

---

## Task 5: server/schema.lua — auto-create tables

**Files:**
- Create: `server/schema.lua`
- Modify: `server/main.lua`

- [ ] **Step 1: Criar server/schema.lua**

Extrair todos os `CREATE TABLE` do `import.sql` e converter para `CREATE TABLE IF NOT EXISTS`.
Incluir também os `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` das migrations.

```lua
-- AUST_trucker — server/schema.lua
-- Auto-cria tabelas no primeiro boot. Elimina necessidade de executar import.sql manualmente.

SchemaService = {}

local TABLES = {
    [[CREATE TABLE IF NOT EXISTS `trucker_companies` (
        `id`              VARCHAR(50)     PRIMARY KEY,
        `owner_citizenid` VARCHAR(50)     NOT NULL,
        `name`            VARCHAR(100)    NOT NULL UNIQUE,
        `balance`         BIGINT          DEFAULT 0,
        `is_recruiting`   TINYINT(1)      DEFAULT 0,
        `company_type`    ENUM('logistics','repo') DEFAULT 'logistics',
        `company_level`   TINYINT         DEFAULT 1 CHECK (company_level BETWEEN 1 AND 30),
        `company_xp`      INT             DEFAULT 0,
        `reputation`      TINYINT(3) UNSIGNED NOT NULL DEFAULT 100,
        `allow_illegal_npc` TINYINT(1)   NOT NULL DEFAULT 0,
        `created_at`      DATETIME        DEFAULT CURRENT_TIMESTAMP,
        `fleet_upgrades`  JSON            DEFAULT ('{}')
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_company_members` (
        `citizenid`   VARCHAR(50) PRIMARY KEY,
        `company_id`  VARCHAR(50) NOT NULL,
        `role`        ENUM('owner','manager','driver') DEFAULT 'driver',
        `joined_at`   DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE,
        INDEX `idx_company_id` (`company_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_company_vehicles` (
        `plate`          VARCHAR(20)  PRIMARY KEY,
        `company_id`     VARCHAR(50)  NOT NULL,
        `model`          VARCHAR(50)  NOT NULL,
        `vehicle_type`   VARCHAR(50)  NOT NULL,
        `status`         ENUM('stored','out') DEFAULT 'stored',
        `added_at`       DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `fuel_level`     FLOAT        DEFAULT 100.0,
        `has_gps_tracker` TINYINT(1)  NOT NULL DEFAULT 0,
        FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_jobs` (
        `id`                 VARCHAR(50)  PRIMARY KEY,
        `origin_id`          VARCHAR(50)  NOT NULL,
        `dest_id`            VARCHAR(50)  NOT NULL,
        `cargo_item`         VARCHAR(100) NOT NULL,
        `trailer_model`      VARCHAR(50)  NOT NULL,
        `base_payment`       INT          NOT NULL,
        `distance`           DECIMAL(10,2) NOT NULL,
        `status`             ENUM('available','active','completed','expired','npc_completed') DEFAULT 'available',
        `assigned_citizenid` VARCHAR(50)  NULL,
        `company_id`         VARCHAR(50)  NULL,
        `convoy_id`          VARCHAR(36)  NULL DEFAULT NULL,
        `illegal_type`       VARCHAR(20)  NULL DEFAULT NULL,
        `cargo_qty`          TINYINT UNSIGNED NOT NULL DEFAULT 1,
        `truck_plate`        VARCHAR(20)  DEFAULT NULL,
        `expires_at`         DATETIME     NOT NULL,
        `accepted_at`        DATETIME     NULL,
        `completed_at`       DATETIME     NULL,
        `created_at`         DATETIME     DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_status`         (`status`),
        INDEX `idx_assigned`       (`assigned_citizenid`),
        INDEX `idx_status_expires` (`status`, `expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_industry_state` (
        `industry_id`          VARCHAR(50)  NOT NULL,
        `item`                 VARCHAR(50)  NOT NULL,
        `entry_type`           ENUM('production','consumption') NOT NULL,
        `current_price`        INT          NOT NULL,
        `current_stock`        INT          DEFAULT 0,
        `next_production_time` DATETIME     NULL,
        `last_npc_fill_at`     DATETIME     NULL DEFAULT NULL,
        `updated_at`           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`industry_id`, `item`, `entry_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_industry_ownership` (
        `industry_id`      VARCHAR(50)  PRIMARY KEY,
        `owner_citizenid`  VARCHAR(50)  NOT NULL,
        `company_id`       VARCHAR(50)  NULL,
        `purchase_price`   BIGINT       NOT NULL,
        `production_level` TINYINT      DEFAULT 1,
        `npc_workers`      TINYINT      DEFAULT 0,
        `balance`          BIGINT       DEFAULT 0,
        `total_earned`     BIGINT       DEFAULT 0,
        `purchased_at`     DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `updated_at`       DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX `idx_owner`      (`owner_citizenid`),
        INDEX `idx_company_id` (`company_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_player_progression` (
        `citizenid`       VARCHAR(50)    PRIMARY KEY,
        `level`           INT            DEFAULT 1,
        `xp`              INT            DEFAULT 0,
        `rank`            TINYINT        DEFAULT 1,
        `reputation`      INT            DEFAULT 0,
        `skill_points`    INT            DEFAULT 0,
        `total_earnings`  BIGINT         DEFAULT 0,
        `total_deliveries` INT           DEFAULT 0,
        `total_distance`  DECIMAL(12,2)  DEFAULT 0,
        `joined_at`       DATETIME       DEFAULT CURRENT_TIMESTAMP,
        `last_seen`       DATETIME       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `fatigue`         FLOAT          DEFAULT 0.0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_player_skills` (
        `citizenid`   VARCHAR(50) NOT NULL,
        `skill_type`  ENUM('distance','valuable','fragile','speed') NOT NULL,
        `skill_level` TINYINT DEFAULT 0,
        PRIMARY KEY (`citizenid`, `skill_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_player_certifications` (
        `citizenid`  VARCHAR(50) NOT NULL,
        `cert_type`  ENUM('explosive','flammable_gas','flammable_liquid',
                         'flammable_solid','toxic','corrosive') NOT NULL,
        `acquired_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`citizenid`, `cert_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_loans` (
        `id`                INT     AUTO_INCREMENT PRIMARY KEY,
        `citizenid`         VARCHAR(50)  NOT NULL,
        `company_id`        VARCHAR(50)  NULL,
        `vehicle_plate`     VARCHAR(20)  NULL,
        `amount`            BIGINT       NOT NULL,
        `interest_rate`     FLOAT        NOT NULL DEFAULT 0.05,
        `remaining_balance` BIGINT       NOT NULL,
        `monthly_payment`   BIGINT       NOT NULL,
        `status`            ENUM('active','paid','defaulted') DEFAULT 'active',
        `created_at`        DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `next_payment_at`   DATETIME     NOT NULL,
        INDEX `idx_citizenid` (`citizenid`),
        INDEX `idx_status`    (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_npc_drivers` (
        `id`               VARCHAR(36) NOT NULL PRIMARY KEY,
        `company_id`       VARCHAR(50) NOT NULL,
        `name`             VARCHAR(64) NOT NULL,
        `skill_level`      ENUM('junior','pleno','senior') NOT NULL DEFAULT 'junior',
        `salary`           INT  NOT NULL DEFAULT 2000,
        `satisfaction`     TINYINT NOT NULL DEFAULT 80,
        `xp`               INT  NOT NULL DEFAULT 0,
        `tenure_days`      INT  NOT NULL DEFAULT 0,
        `total_earnings`   INT  NOT NULL DEFAULT 0,
        `status`           ENUM('idle','working','resting','fired','quit') NOT NULL DEFAULT 'idle',
        `active_job_id`    VARCHAR(36) NULL DEFAULT NULL,
        `hired_at`         TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `last_demand_at`   INT NULL DEFAULT NULL,
        `last_tenure_check` INT NULL DEFAULT NULL,
        `resting_until`    INT NULL DEFAULT NULL,
        FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_npc_jobs` (
        `id`             VARCHAR(36) NOT NULL PRIMARY KEY,
        `driver_id`      VARCHAR(36) NOT NULL,
        `company_id`     VARCHAR(50) NOT NULL,
        `origin_id`      VARCHAR(64) NOT NULL,
        `dest_id`        VARCHAR(64) NOT NULL,
        `cargo_item`     VARCHAR(64) NOT NULL,
        `base_payment`   INT  NOT NULL DEFAULT 0,
        `distance`       FLOAT NOT NULL DEFAULT 0,
        `illegal`        TINYINT(1) NOT NULL DEFAULT 0,
        `assigned_at`    INT  NOT NULL,
        `expected_end_at` INT NOT NULL,
        `status`         ENUM('active','completed','failed','event') NOT NULL DEFAULT 'active',
        `earnings`       INT  NOT NULL DEFAULT 0,
        FOREIGN KEY (`driver_id`) REFERENCES `trucker_npc_drivers`(`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_repo_orders` (
        `id`                      INT  AUTO_INCREMENT PRIMARY KEY,
        `company_id`              VARCHAR(50)  NULL,
        `vehicle_plate`           VARCHAR(20)  NOT NULL,
        `vehicle_owner_citizenid` VARCHAR(50)  NULL,
        `vehicle_model`           VARCHAR(50)  NOT NULL,
        `vehicle_value`           BIGINT       NOT NULL,
        `mission_type`            ENUM('simple','npc_hostile','pvp','stealth') DEFAULT 'simple',
        `location_zone`           VARCHAR(50)  NOT NULL,
        `status`                  ENUM('available','active','completed','failed','expired') DEFAULT 'available',
        `assigned_citizenid`      VARCHAR(50)  NULL,
        `payment`                 BIGINT       NOT NULL,
        `loan_id`                 INT          NULL,
        `created_at`              DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `expires_at`              DATETIME     NOT NULL,
        `completed_at`            DATETIME     NULL,
        INDEX `idx_status`            (`status`),
        INDEX `idx_vehicle_owner`     (`vehicle_owner_citizenid`),
        INDEX `idx_status_expires`    (`status`, `expires_at`),
        INDEX `idx_company_id`        (`company_id`),
        UNIQUE KEY `uq_loan_id`       (`loan_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_infractions` (
        `id`             INT  AUTO_INCREMENT PRIMARY KEY,
        `citizenid`      VARCHAR(50) NOT NULL,
        `job_id`         VARCHAR(50) NULL,
        `infraction_type` ENUM('overload','no_manifest','expired_manifest',
                              'dangerous_cargo','illegal_seizure') NOT NULL,
        `reason`         TEXT        NOT NULL,
        `issued_by`      VARCHAR(100) NOT NULL,
        `created_at`     DATETIME    DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_citizenid` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_parties` (
        `id`         VARCHAR(36) PRIMARY KEY,
        `leader_cid` VARCHAR(50) NOT NULL,
        `members`    JSON        NOT NULL DEFAULT '[]',
        `max_size`   INT         NOT NULL DEFAULT 6,
        `status`     ENUM('forming','active','disbanded') NOT NULL DEFAULT 'forming',
        `created_at` DATETIME    NOT NULL DEFAULT NOW()
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_convoy_jobs` (
        `id`           VARCHAR(36) PRIMARY KEY,
        `party_id`     VARCHAR(36) NOT NULL,
        `status`       ENUM('forming','active','completed','cancelled') NOT NULL DEFAULT 'forming',
        `bonus_mult`   FLOAT       NOT NULL DEFAULT 1.5,
        `active_count` INT         NOT NULL DEFAULT 0,
        `total_count`  INT         NOT NULL DEFAULT 0,
        `started_at`   DATETIME    NULL,
        `completed_at` DATETIME    NULL,
        FOREIGN KEY (`party_id`) REFERENCES `trucker_parties`(`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_convoy_members` (
        `convoy_id`  VARCHAR(36) NOT NULL,
        `citizenid`  VARCHAR(50) NOT NULL,
        `job_id`     VARCHAR(50) NOT NULL,
        `status`     ENUM('pending','active','completed','abandoned') NOT NULL DEFAULT 'pending',
        PRIMARY KEY (`convoy_id`, `citizenid`),
        FOREIGN KEY (`convoy_id`) REFERENCES `trucker_convoy_jobs`(`id`),
        FOREIGN KEY (`job_id`)    REFERENCES `trucker_jobs`(`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_adr_certs` (
        `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        `citizenid`  VARCHAR(50) NOT NULL,
        `adr_type`   ENUM('flammable_liquid','flammable_gas','toxic','corrosive',
                         'explosive','environmental') NOT NULL,
        `expires_at` INT UNSIGNED NOT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `uq_citizen_type` (`citizenid`, `adr_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Migrations: colunas adicionadas em versões anteriores
-- ADD COLUMN IF NOT EXISTS é suportado desde MariaDB 10.0 / MySQL 8.0
local MIGRATIONS = {
    -- v14: truck_plate em trucker_jobs
    "ALTER TABLE `trucker_jobs` ADD COLUMN IF NOT EXISTS `truck_plate` VARCHAR(20) DEFAULT NULL",
    -- v14: has_gps_tracker em trucker_company_vehicles
    "ALTER TABLE `trucker_company_vehicles` ADD COLUMN IF NOT EXISTS `has_gps_tracker` TINYINT(1) NOT NULL DEFAULT 0",
    -- v16: vehicle_plate em trucker_loans
    "ALTER TABLE `trucker_loans` ADD COLUMN IF NOT EXISTS `vehicle_plate` VARCHAR(20) NULL AFTER company_id",
}

---Garante que todas as tabelas e colunas existam. Chamado em MySQL.ready antes de LoadCompanies.
function SchemaService.EnsureTables()
    for _, sql in ipairs(TABLES) do
        local ok, err = pcall(MySQL.query.await, sql)
        if not ok then
            print(('[AUST_trucker] SchemaService ERROR creating table: %s'):format(tostring(err)))
        end
    end
    for _, sql in ipairs(MIGRATIONS) do
        local ok, err = pcall(MySQL.query.await, sql)
        if not ok then
            -- Ignorar erro "Duplicate column" — coluna já existe
            if not tostring(err):find('Duplicate column') then
                print(('[AUST_trucker] SchemaService WARN migration: %s'):format(tostring(err)))
            end
        end
    end
    if Config.Debug then print('[AUST_trucker] SchemaService: tables ensured.') end
end
```

- [ ] **Step 2: Atualizar main.lua — chamar SchemaService.EnsureTables()**

```lua
MySQL.ready(function()
    math.randomseed(os.time())
    SchemaService.EnsureTables()   -- ← NOVO: garantir schema antes de queries
    LoadCompanies()
    ...
end)
```

- [ ] **Step 3: Commit**
```bash
git add server/schema.lua server/main.lua
git commit -m "feat(17B): SchemaService.EnsureTables() — auto-create all tables on boot"
```

---

## Task 6: Performance Audit

**Files:**
- Modify: `server/services/*.lua` (onde necessário)

- [ ] **Step 1: Identificar todos os CreateThread**
```bash
grep -rn "CreateThread\|Wait(" server/ --include="*.lua" | grep -v "framework\|schema" | grep "Wait(0\|Wait(100\|Wait(200\|Wait(500)" | grep -v "startup\|Ready"
```

- [ ] **Step 2: Para cada Wait pequeno em loop idle — aumentar intervalo**

Padrão problemático:
```lua
CreateThread(function()
    while true do
        -- lógica que só importa com player ativo
        Wait(100)  -- ← 100ms = 10 ticks/s desnecessário se não há player
    end
end)
```

Fix: adicionar gate de player ou aumentar para `Wait(1000)` no mínimo quando não há player ativo.

- [ ] **Step 3: Verificar TruckSimulationService**

Threads de simulação (fuel, fadiga) devem ter `Wait(5000)` no idle.

- [ ] **Step 4: Commit**
```bash
git add server/services/
git commit -m "perf(17C): increase idle Wait intervals to 0.00ms resmon target"
```

---

## Task 7: Docs (README, guias, CHANGELOG)

- [ ] **Step 1: Reescrever README.md**

```markdown
# AUST_trucker — Sistema de Caminhoneiros

Sistema completo de logística para FiveM. Suporta QBX, QBCore e ESX.

## Dependências
- oxmysql
- ox_lib
- ox_inventory
- ox_target
- **QBX**: qbx_core | **QBCore**: qb-core | **ESX**: es_extended

## Instalação

1. Adicionar `AUST_trucker` na pasta `resources`
2. Editar `config/config.lua`:
   - `Config.Framework = 'qbx'` (ou `'qbcore'` ou `'esx'`)
3. As tabelas são criadas **automaticamente** no primeiro start
4. Adicionar `ensure AUST_trucker` no `server.cfg`

> **Atualização de versão anterior**: execute `sql/update_loan_collateral_v16.sql`
> se vier de v15 ou anterior (apenas para instalações existentes).

## Configuração rápida
- `Config.Framework` — framework do servidor
- `Config.Debug` — logs detalhados (desativar em produção)

## Versão: 17.0.0
```

- [ ] **Step 2: Atualizar GUIA_JOGADOR.md e GUIA_STAFF.md**

Adicionar seções sobre:
- Repo Man (missões, tipos, colateral de veículo)
- Sistema de empréstimos com vehicle_plate
- Cargo Theft (blip de agente)

- [ ] **Step 3: CHANGELOG v17.0.0**

Adicionar entrada no topo do CHANGELOG.

- [ ] **Step 4: Commit**
```bash
git add README.md GUIA_JOGADOR.md GUIA_STAFF.md CHANGELOG.md
git commit -m "docs(17D): multi-framework install guide, player guide v16+, staff guide"
```

---

## Verificação Final

- [ ] `restart AUST_trucker` — verificar console sem erros Lua
- [ ] Verificar log `[AUST_trucker] Framework: qbx`
- [ ] Verificar log `[AUST_trucker] SchemaService: tables ensured.`
- [ ] Testar job completo (accept → deliver → payment) com QBX
- [ ] Testar criar loan com vehicle_plate → esperar CheckOverdue → confirmar repo order correta
- [ ] Verificar resmon com 0 players trucking: `0.00ms`
