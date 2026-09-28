# AUST_trucker — Fase 1: Backend Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Migrar AUST_trucker de QBCore + JSON + lation_ui para QBX (qbx_core) + oxmysql + ox_lib, mantendo a UI vanilla JS intacta e o resource 100% funcional ao final desta fase.

**Architecture:** Fase 1 de 3. Não refatora estrutura de arquivos — apenas troca as dependências. O `server.lua` e `client.lua` monolíticos continuam existindo; os sistemas JSON são substituídos por queries oxmysql. O resource deve iniciar e funcionar sem erros após cada tarefa.

**Tech Stack:** qbx_core, ox_lib, ox_inventory, ox_target, oxmysql, Lua 5.4

---

## Contexto do Codebase

```
AUST_trucker/
├── fxmanifest.lua          — MODIFICAR (deps, load order, lua54)
├── import.sql              — CRIAR (schema DB)
├── config/config.lua       — NÃO TOCAR
├── data/
│   ├── companies.json      — DELETAR ao final
│   ├── industries.json     — DELETAR ao final
│   └── player_stats.json   — DELETAR ao final
├── server/
│   ├── server.lua          — MODIFICAR (QBCore→QBX, JSON→DB)
│   ├── industries.server.lua — MODIFICAR (QBCore→QBX, JSON→DB)
│   ├── main.lua            — CRIAR (VP_Trucker global, init)
│   └── database.lua        — CRIAR (helpers oxmysql)
└── client/
    ├── client.lua               — MODIFICAR (QBCore→QBX)
    ├── industries.client.lua    — MODIFICAR (QBCore→QBX)
    └── industries_npc.client.lua — MODIFICAR (QBCore→QBX, lation_ui→ox_lib)
```

## Padrões de Migração QBCore → QBX

**Server-side:**
```lua
-- ANTES (QBCore):
local QBCore = exports['qb-core']:GetCoreObject()
local Player = QBCore.Functions.GetPlayer(src)
Player.Functions.GetMoney('cash')
Player.Functions.AddMoney('cash', amount, 'reason')
Player.Functions.RemoveMoney('cash', amount, 'reason')
Player.PlayerData.citizenid
QBCore.Functions.GetPlayers()  -- retorna array de sources

-- DEPOIS (QBX):
-- NÃO precisa de GetCoreObject — usar exports diretamente
local Player = exports.qbx_core:GetPlayer(src)
Player.PlayerData.money.cash
Player.Functions.AddMoney('cash', amount, 'reason')
Player.Functions.RemoveMoney('cash', amount, 'reason')
Player.PlayerData.citizenid
exports.qbx_core:GetQBPlayers()  -- retorna table: source → Player
```

**Client-side:**
```lua
-- ANTES:
local QBCore = exports['qb-core']:GetCoreObject()
QBCore.Functions.TriggerCallback('name', function(result) ... end, param)
QBCore.Functions.Notify('msg', 'error')

-- DEPOIS:
-- TriggerCallback → lib.callback.await (com pcall)
local ok, result = pcall(lib.callback.await, 'AUST_trucker:name', false, param)
if not ok or not result then return end
-- Notify → lib.notify
lib.notify({ title = 'AURP Trucker', description = 'msg', type = 'error' })
```

**Callbacks:**
```lua
-- ANTES (server):
QBCore.Functions.CreateCallback('aurp-trucker:name', function(source, cb, param)
    cb(result)
end)

-- DEPOIS (server):
lib.callback.register('AUST_trucker:name', function(source, param)
    return result
end)
```

**Nota:** QBX ainda dispara `QBCore:Server:OnPlayerLoaded` e `QBCore:Client:OnPlayerUnload` por compatibilidade — esses eventos NÃO precisam ser alterados nesta fase.

---

## Task 1: Criar import.sql

**Files:**
- Create: `import.sql`

- [x] **Passo 1: Criar o arquivo import.sql**

> **Schema completo (blueprint-ready):** 13 tabelas cobrindo toda a visão do produto.
> **Prefixo:** `trucker_` — banco novo, sem dados existentes.

```sql
-- AUST_trucker v3.0.0 — Full Schema (blueprint-ready)
-- Execute: SOURCE import.sql;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS trucker_repo_orders;
DROP TABLE IF EXISTS trucker_npc_drivers;
DROP TABLE IF EXISTS trucker_loans;
DROP TABLE IF EXISTS trucker_player_certifications;
DROP TABLE IF EXISTS trucker_player_skills;
DROP TABLE IF EXISTS trucker_player_progression;
DROP TABLE IF EXISTS trucker_infractions;
DROP TABLE IF EXISTS trucker_industry_ownership;
DROP TABLE IF EXISTS trucker_industry_state;
DROP TABLE IF EXISTS trucker_jobs;
DROP TABLE IF EXISTS trucker_company_vehicles;
DROP TABLE IF EXISTS trucker_company_members;
DROP TABLE IF EXISTS trucker_companies;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================
-- EMPRESAS
-- =============================================

CREATE TABLE trucker_companies (
    id              VARCHAR(50)     PRIMARY KEY,
    owner_citizenid VARCHAR(50)     NOT NULL,
    name            VARCHAR(100)    NOT NULL UNIQUE,
    balance         BIGINT          DEFAULT 0,
    is_recruiting   TINYINT(1)      DEFAULT 0,
    company_type    ENUM('logistics','repo') DEFAULT 'logistics',
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trucker_company_members (
    citizenid       VARCHAR(50)     PRIMARY KEY,
    company_id      VARCHAR(50)     NOT NULL,
    role            ENUM('owner','manager','driver') DEFAULT 'driver',
    joined_at       TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (company_id) REFERENCES trucker_companies(id) ON DELETE CASCADE
);

CREATE TABLE trucker_company_vehicles (
    plate           VARCHAR(20)     PRIMARY KEY,
    company_id      VARCHAR(50)     NOT NULL,
    model           VARCHAR(50)     NOT NULL,
    vehicle_type    VARCHAR(50)     NOT NULL,
    status          ENUM('stored','out') DEFAULT 'stored',
    added_at        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (company_id) REFERENCES trucker_companies(id) ON DELETE CASCADE
);

-- =============================================
-- JOBS DE ENTREGA
-- =============================================

-- cargo_item = nome string do produto (ex: "Containers"), NÃO chave ox_inventory
-- trailer_model = modelo GTA do trailer requerido
CREATE TABLE trucker_jobs (
    id                  VARCHAR(50)     PRIMARY KEY,
    origin_id           VARCHAR(50)     NOT NULL,
    dest_id             VARCHAR(50)     NOT NULL,
    cargo_item          VARCHAR(100)    NOT NULL,
    trailer_model       VARCHAR(50)     NOT NULL,
    base_payment        INT             NOT NULL,
    distance            FLOAT           NOT NULL,
    status              ENUM('available','active','completed','expired') DEFAULT 'available',
    assigned_citizenid  VARCHAR(50)     NULL,
    company_id          VARCHAR(50)     NULL,
    expires_at          TIMESTAMP       NOT NULL,
    accepted_at         TIMESTAMP       NULL,
    completed_at        TIMESTAMP       NULL,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_status    (status),
    INDEX idx_assigned  (assigned_citizenid)
);

-- =============================================
-- INDÚSTRIAS
-- =============================================

-- Config.Industries (trading com ox_inventory items, DB-backed)
-- NÃO cobre PrimaryIndustries/SecondaryIndustries (config-only, sem DB)
CREATE TABLE trucker_industry_state (
    industry_id         VARCHAR(50)     NOT NULL,
    item                VARCHAR(50)     NOT NULL,
    entry_type          ENUM('production','consumption') NOT NULL,
    current_price       INT             NOT NULL,
    current_stock       INT             DEFAULT 0,
    next_production_time TIMESTAMP      NULL,
    PRIMARY KEY (industry_id, item, entry_type)
);

-- Propriedade de indústrias primárias/secundárias por jogadores
CREATE TABLE trucker_industry_ownership (
    industry_id         VARCHAR(50)     PRIMARY KEY,
    owner_citizenid     VARCHAR(50)     NOT NULL,
    company_id          VARCHAR(50)     NULL,
    purchase_price      INT             NOT NULL,
    production_level    TINYINT         DEFAULT 1,  -- fórmula: Base + level×2
    npc_workers         TINYINT         DEFAULT 0,  -- máx 10, +1 unid/ciclo cada
    balance             BIGINT          DEFAULT 0,
    purchased_at        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_owner     (owner_citizenid)
);

-- =============================================
-- PROGRESSÃO DO JOGADOR
-- =============================================

-- Unifica stats + XP + rank + reputação em uma tabela
CREATE TABLE trucker_player_progression (
    citizenid           VARCHAR(50)     PRIMARY KEY,
    level               INT             DEFAULT 1,   -- 1-30
    xp                  INT             DEFAULT 0,
    rank                TINYINT         DEFAULT 1,   -- 1=Aprendiz Courier … 6=Trucker Pro
    reputation          INT             DEFAULT 0,
    skill_points        INT             DEFAULT 0,   -- pontos não alocados
    total_earnings      BIGINT          DEFAULT 0,
    total_deliveries    INT             DEFAULT 0,
    total_distance      FLOAT           DEFAULT 0,
    joined_at           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    last_seen           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Árvore de habilidades: 4 tipos × até 6 níveis (+2%…+12% no pagamento por tipo)
CREATE TABLE trucker_player_skills (
    citizenid           VARCHAR(50)     NOT NULL,
    skill_type          ENUM('distance','valuable','fragile','speed') NOT NULL,
    skill_level         TINYINT         DEFAULT 0,
    PRIMARY KEY (citizenid, skill_type)
);

-- Certificações ADR (necessárias para certas cargas)
CREATE TABLE trucker_player_certifications (
    citizenid           VARCHAR(50)     NOT NULL,
    cert_type           ENUM('explosive','flammable_gas','flammable_liquid',
                             'flammable_solid','toxic','corrosive') NOT NULL,
    acquired_at         TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid, cert_type)
);

-- =============================================
-- SISTEMA FINANCEIRO
-- =============================================

CREATE TABLE trucker_loans (
    id                  INT             AUTO_INCREMENT PRIMARY KEY,
    citizenid           VARCHAR(50)     NOT NULL,
    company_id          VARCHAR(50)     NULL,
    amount              INT             NOT NULL,
    interest_rate       FLOAT           NOT NULL DEFAULT 0.05,
    remaining_balance   INT             NOT NULL,
    monthly_payment     INT             NOT NULL,
    status              ENUM('active','paid','defaulted') DEFAULT 'active',
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    next_payment_at     TIMESTAMP       NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_status    (status)
);

-- =============================================
-- MOTORISTAS NPC
-- =============================================

CREATE TABLE trucker_npc_drivers (
    id                  INT             AUTO_INCREMENT PRIMARY KEY,
    owner_citizenid     VARCHAR(50)     NOT NULL,
    company_id          VARCHAR(50)     NULL,
    name                VARCHAR(100)    NOT NULL,
    skill_level         TINYINT         DEFAULT 1,
    salary              INT             NOT NULL,
    fuel_consumed       INT             DEFAULT 0,
    last_income_at      TIMESTAMP       NULL,
    hired_at            TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_owner     (owner_citizenid)
);

-- =============================================
-- REPO MAN — RETOMADA DE VEÍCULOS
-- =============================================

CREATE TABLE trucker_repo_orders (
    id                      INT             AUTO_INCREMENT PRIMARY KEY,
    company_id              VARCHAR(50)     NULL,
    vehicle_plate           VARCHAR(20)     NOT NULL,
    vehicle_owner_citizenid VARCHAR(50)     NULL,  -- NULL = dono NPC
    vehicle_model           VARCHAR(50)     NOT NULL,
    vehicle_value           INT             NOT NULL,
    mission_type            ENUM('simple','npc_hostile','pvp','stealth') DEFAULT 'simple',
    location_zone           VARCHAR(50)     NOT NULL,
    status                  ENUM('available','active','completed','failed','expired') DEFAULT 'available',
    assigned_citizenid      VARCHAR(50)     NULL,
    payment                 INT             NOT NULL,
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    expires_at              TIMESTAMP       NOT NULL,
    completed_at            TIMESTAMP       NULL,
    INDEX idx_status        (status),
    INDEX idx_vehicle_owner (vehicle_owner_citizenid)
);

-- =============================================
-- INFRAÇÕES (integração AUST_sala)
-- =============================================

CREATE TABLE trucker_infractions (
    id              INT             AUTO_INCREMENT PRIMARY KEY,
    citizenid       VARCHAR(50)     NOT NULL,
    job_id          VARCHAR(50)     NULL,
    infraction_type VARCHAR(50)     NOT NULL,
    reason          TEXT            NOT NULL,
    issued_by       VARCHAR(100)    NOT NULL,  -- citizenid do fiscal ou 'AUST_sala:auto'
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_citizenid (citizenid)
);
```

- [x] **Passo 2: Verificar**

Abrir cliente SQL (HeidiSQL, DBeaver, etc.) e executar:
```sql
SOURCE /caminho/para/AUST_trucker/import.sql;
SHOW TABLES LIKE 'trucker_%';
```
Esperado: 13 tabelas listadas.

- [x] **Passo 3: Commit**

```bash
git add import.sql
git commit -m "feat: add full trucker schema (13 tables, blueprint-ready)"
```

---

## Task 2: Atualizar fxmanifest.lua

**Files:**
- Modify: `fxmanifest.lua`

- [x] **Passo 1: Substituir fxmanifest.lua completo**

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'AURP Development Team'
description 'Sistema de Caminhoneiros — Empresas, Jobs e Economia Dinâmica'
version '3.0.0'

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
    'server/server.lua',
    'server/industries.server.lua',
}

client_scripts {
    'client/client.lua',
    'client/industries.client.lua',
    'client/industries_npc.client.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style_new.css',
    'html/script.js',
}
```

**Notas importantes:**
- `@ox_lib/init.lua` vai para `shared_scripts` (substitui `@lation_ui/init.lua`)
- `@oxmysql/lib/MySQL.lua` vai para `server_scripts` (ANTES de server/main.lua)
- `server/main.lua` e `server/database.lua` são NOVOS arquivos criados nas próximas tasks — o fxmanifest já os declara aqui; o resource não iniciará até eles existirem
- `lua54 'yes'` mantido: funções globais entre arquivos funcionam (VP_Trucker definido em main.lua é visível em server.lua)

- [x] **Passo 2: Verificar sintaxe**

No console do servidor após `ensure AUST_trucker`:
Esperado: erro sobre arquivo `server/main.lua` não encontrado (correto — será criado na Task 3)
NÃO esperado: erros de sintaxe no fxmanifest

- [x] **Passo 3: Commit**

```bash
git add fxmanifest.lua
git commit -m "chore: update fxmanifest — qbx_core, oxmysql, ox_lib, remove lation_ui"
```

---

## Task 3: Criar server/main.lua

**Files:**
- Create: `server/main.lua`

- [x] **Passo 1: Criar server/main.lua**

```lua
-- AUST_trucker — server/main.lua
-- Global state e inicialização do resource

-- Estado global (acessível por todos os arquivos server-side devido ao lua54)
-- NOTA: modificações incrementais a VP_Trucker são permitidas nas Fases 2 e 3
VP_Trucker = {
    Ready           = false,
    Companies       = {},   -- cache: companyId → { id, owner_citizenid, name, balance, is_recruiting }
    PlayerCompanies = {},   -- cache: citizenid → companyId
    ActiveJobs      = {},   -- cache: jobId → data (reservado para Fase 2 — JobService)
    PlayerJobs      = {},   -- cache: citizenid → jobId (reservado para Fase 2 — JobService)
}

-- Carrega todas as empresas do DB para o cache em memória
local function LoadCompanies()
    local companies = MySQL.query.await('SELECT * FROM trucker_companies')
    for _, company in ipairs(companies) do
        VP_Trucker.Companies[company.id] = company
    end

    local members = MySQL.query.await('SELECT citizenid, company_id FROM trucker_company_members')
    for _, member in ipairs(members) do
        VP_Trucker.PlayerCompanies[member.citizenid] = member.company_id
    end

    if Config.Debug then
        print(('[AUST_trucker] Loaded %d companies into cache'):format(#companies))
    end
end

-- Inicialização: aguarda oxmysql estar pronto
CreateThread(function()
    -- oxmysql dispara 'oxmysql:ready' quando conectado
    -- Aguardamos via MySQL.ready para garantir conexão antes de queries
    MySQL.ready(function()
        LoadCompanies()
        VP_Trucker.Ready = true
        if Config.Debug then
            print('[AUST_trucker] Server ready.')
        end
    end)
end)

-- Expõe função de reload do cache para outros arquivos
function ReloadCompanyCache()
    VP_Trucker.Companies = {}
    VP_Trucker.PlayerCompanies = {}
    LoadCompanies()
end
```

- [x] **Passo 2: Verificar**

`ensure AUST_trucker` no console do servidor.
Esperado: sem erros; `[AUST_trucker] Server ready.` aparece no console (se Config.Debug = true).
NÃO esperado: `attempt to index nil value` ou erros de MySQL.

- [x] **Passo 3: Commit**

```bash
git add server/main.lua
git commit -m "feat: add server/main.lua with VP_Trucker global and DB cache init"
```

---

## Task 4: Criar server/database.lua

**Files:**
- Create: `server/database.lua`

- [x] **Passo 1: Criar server/database.lua**

```lua
-- AUST_trucker — server/database.lua
-- Helpers centralizados de banco de dados
-- Todas as funções são globais (lua54: acessíveis por server.lua e industries.server.lua)

-- ============================================================
-- COMPANIES
-- ============================================================

function DB_CreateCompany(id, ownerCitizenId, name)
    return MySQL.insert.await(
        'INSERT INTO trucker_companies (id, owner_citizenid, name) VALUES (?, ?, ?)',
        { id, ownerCitizenId, name }
    )
end

function DB_GetCompany(companyId)
    return MySQL.single.await(
        'SELECT * FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
end

function DB_UpdateCompanyBalance(companyId, amount)
    -- amount pode ser negativo (saque) ou positivo (depósito)
    MySQL.update.await(
        'UPDATE trucker_companies SET balance = balance + ? WHERE id = ?',
        { amount, companyId }
    )
    return MySQL.scalar.await(
        'SELECT balance FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
end

function DB_SetCompanyRecruiting(companyId, isRecruiting)
    MySQL.update.await(
        'UPDATE trucker_companies SET is_recruiting = ? WHERE id = ?',
        { isRecruiting and 1 or 0, companyId }
    )
end

function DB_DeleteCompany(companyId)
    -- CASCADE deleta members e vehicles automaticamente
    MySQL.query.await('DELETE FROM trucker_companies WHERE id = ?', { companyId })
end

function DB_GetRecruitingCompanies()
    return MySQL.query.await(
        'SELECT c.*, COUNT(m.citizenid) as member_count FROM trucker_companies c LEFT JOIN trucker_company_members m ON m.company_id = c.id WHERE c.is_recruiting = 1 GROUP BY c.id'
    )
end

-- ============================================================
-- MEMBERS
-- ============================================================

function DB_AddMember(companyId, citizenId, role)
    role = role or 'driver'
    return MySQL.insert.await(
        'INSERT INTO trucker_company_members (citizenid, company_id, role) VALUES (?, ?, ?)',
        { citizenId, companyId, role }
    )
end

function DB_RemoveMember(citizenId)
    MySQL.query.await(
        'DELETE FROM trucker_company_members WHERE citizenid = ?',
        { citizenId }
    )
end

function DB_GetMembers(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_company_members WHERE company_id = ?',
        { companyId }
    )
end

function DB_GetMember(citizenId)
    return MySQL.single.await(
        'SELECT * FROM trucker_company_members WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
end

-- ============================================================
-- VEHICLES
-- ============================================================

function DB_RegisterVehicle(companyId, plate, model, vehicleType)
    return MySQL.insert.await(
        'INSERT INTO trucker_company_vehicles (plate, company_id, model, vehicle_type) VALUES (?, ?, ?, ?)',
        { plate, companyId, model, vehicleType }
    )
end

function DB_RemoveVehicle(plate)
    MySQL.query.await(
        'DELETE FROM trucker_company_vehicles WHERE plate = ?',
        { plate }
    )
end

function DB_GetVehicles(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_company_vehicles WHERE company_id = ?',
        { companyId }
    )
end

function DB_SetVehicleStatus(plate, status)
    MySQL.update.await(
        'UPDATE trucker_company_vehicles SET status = ? WHERE plate = ?',
        { status, plate }
    )
end

-- ============================================================
-- JOBS
-- ============================================================

function DB_InsertJob(job)
    -- job = { id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at }
    return MySQL.insert.await(
        [[INSERT INTO trucker_jobs
          (id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))]],
        { job.id, job.origin_id, job.dest_id, job.cargo_item, job.trailer_model,
          job.base_payment, job.distance, job.expires_at }
    )
end

function DB_GetAvailableJobs()
    return MySQL.query.await(
        "SELECT *, UNIX_TIMESTAMP(expires_at) as expires_at_unix, UNIX_TIMESTAMP(created_at) as created_at_unix FROM trucker_jobs WHERE status = 'available' AND expires_at > NOW()"
    )
end

function DB_GetActiveJobByPlayer(citizenId)
    return MySQL.single.await(
        "SELECT *, UNIX_TIMESTAMP(expires_at) as expires_at_unix, UNIX_TIMESTAMP(accepted_at) as accepted_at_unix FROM trucker_jobs WHERE assigned_citizenid = ? AND status = 'active' LIMIT 1",
        { citizenId }
    )
end

function DB_AcceptJob(jobId, citizenId, companyId)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'active', assigned_citizenid = ?, company_id = ?, accepted_at = NOW() WHERE id = ? AND status = 'available'",
        { citizenId, companyId, jobId }
    )
end

function DB_CompleteJob(jobId)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'completed', completed_at = NOW() WHERE id = ?",
        { jobId }
    )
end

function DB_AbandonJob(jobId, citizenId)
    -- Se expirado → 'expired'; senão → 'available' de volta
    MySQL.update.await(
        [[UPDATE trucker_jobs
          SET status = IF(expires_at < NOW(), 'expired', 'available'),
              assigned_citizenid = NULL,
              company_id = NULL,
              accepted_at = NULL
          WHERE id = ? AND assigned_citizenid = ?]],
        { jobId, citizenId }
    )
end

function DB_ExpireStaleJobs()
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'expired' WHERE status IN ('available','active') AND expires_at < NOW()"
    )
end

function DB_CountActiveJobs()
    return MySQL.scalar.await(
        "SELECT COUNT(*) FROM trucker_jobs WHERE status = 'available'"
    ) or 0
end

-- ============================================================
-- PLAYER STATS
-- ============================================================

function DB_GetPlayerStats(citizenId)
    return MySQL.single.await(
        'SELECT * FROM trucker_player_progression WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
end

function DB_UpsertPlayerStats(citizenId)
    -- Cria registro se não existir (chamado no onPlayerLoaded)
    MySQL.insert.await(
        'INSERT IGNORE INTO trucker_player_progression (citizenid) VALUES (?)',
        { citizenId }
    )
end

function DB_AddPlayerStats(citizenId, earnings, distance)
    MySQL.update.await(
        [[UPDATE trucker_player_progression
          SET total_earnings = total_earnings + ?,
              total_deliveries = total_deliveries + 1,
              total_distance = total_distance + ?
          WHERE citizenid = ?]],
        { earnings, distance, citizenId }
    )
end

-- ============================================================
-- INDUSTRY STATE (Config.Industries — trading com ox_inventory)
-- ============================================================

function DB_GetIndustryState(industryId)
    return MySQL.query.await(
        'SELECT * FROM trucker_industry_state WHERE industry_id = ?',
        { industryId }
    )
end

function DB_GetAllIndustryState()
    return MySQL.query.await('SELECT * FROM trucker_industry_state')
end

function DB_UpsertIndustryState(industryId, item, entryType, price, stock)
    MySQL.insert.await(
        [[INSERT INTO trucker_industry_state (industry_id, item, entry_type, current_price, current_stock)
          VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE current_price = VALUES(current_price), current_stock = VALUES(current_stock)]],
        { industryId, item, entryType, price, stock }
    )
end

function DB_UpdateIndustryStock(industryId, item, entryType, deltaStock)
    MySQL.update.await(
        [[UPDATE trucker_industry_state
          SET current_stock = GREATEST(0, current_stock + ?)
          WHERE industry_id = ? AND item = ? AND entry_type = ?]],
        { deltaStock, industryId, item, entryType }
    )
end

function DB_UpdateIndustryPrice(industryId, item, entryType, newPrice)
    MySQL.update.await(
        'UPDATE trucker_industry_state SET current_price = ? WHERE industry_id = ? AND item = ? AND entry_type = ?',
        { newPrice, industryId, item, entryType }
    )
end

-- ============================================================
-- INFRACTIONS
-- ============================================================

function DB_RecordInfraction(citizenId, jobId, infractionType, reason, issuedBy)
    return MySQL.insert.await(
        'INSERT INTO trucker_infractions (citizenid, job_id, infraction_type, reason, issued_by) VALUES (?, ?, ?, ?, ?)',
        { citizenId, jobId, infractionType, reason, issuedBy }
    )
end

function DB_GetInfractions(citizenId)
    return MySQL.query.await(
        'SELECT * FROM trucker_infractions WHERE citizenid = ? ORDER BY created_at DESC',
        { citizenId }
    )
end
```

- [x] **Passo 2: Verificar**

`ensure AUST_trucker`. Console deve mostrar `[AUST_trucker] Server ready.` sem erros.
Nenhuma das funções DB_ é chamada ainda — apenas declaradas.

- [x] **Passo 3: Commit**

```bash
git add server/database.lua
git commit -m "feat: add server/database.lua with all oxmysql helpers"
```

---

## Task 5: Migrar server/server.lua — QBCore → QBX

**Files:**
- Modify: `server/server.lua`

Contexto: `server.lua` tem ~2000 linhas. A migração é de padrões — substituições cirúrgicas, NÃO refatoração de lógica.

- [x] **Passo 1: Remover a linha de GetCoreObject**

Localizar e remover a linha 5:
```lua
local QBCore = exports['qb-core']:GetCoreObject()
```

- [x] **Passo 2: Substituir todos os GetPlayer**

Buscar: `QBCore.Functions.GetPlayer(`
Substituir por: `exports.qbx_core:GetPlayer(`

Deve haver ~12 ocorrências. Verificar com:
```bash
grep -n "QBCore.Functions.GetPlayer" server/server.lua
```
Esperado após substituição: 0 resultados.

- [x] **Passo 3: Substituir GetPlayers (retorno diferente!)**

Buscar ocorrências de `QBCore.Functions.GetPlayers()` (linha ~565, ~1646, ~1686).

O retorno muda: QBCore retornava array de sources; QBX retorna `table: source → Player`.

**ANTES:**
```lua
for _, player in pairs(QBCore.Functions.GetPlayers()) do
    local targetPlayer = QBCore.Functions.GetPlayer(player)
    local citizenId = targetPlayer.PlayerData.citizenid
    ...
end
```

**DEPOIS:**
```lua
for playerSrc, targetPlayer in pairs(exports.qbx_core:GetQBPlayers()) do
    local citizenId = targetPlayer.PlayerData.citizenid
    ...
end
```

Adaptar cada bloco manualmente (são 3 blocos).

- [x] **Passo 4: Substituir GetMoney**

Buscar: `Player.Functions.GetMoney('cash')`
Substituir por: `Player.PlayerData.money.cash`

- [x] **Passo 5: Substituir CreateCallback → lib.callback.register**

Buscar todas as ocorrências de `QBCore.Functions.CreateCallback` (há 2 — linhas ~1404 e ~1807; a de 1807 é duplicata e deve ser removida).

**ANTES:**
```lua
QBCore.Functions.CreateCallback('aurp-trucker:getPlayerStats', function(source, cb)
    local citizenId = GetPlayerCitizenId(source)
    local stats = GetPlayerStats(citizenId)
    cb(stats)
end)
```

**DEPOIS:**
```lua
lib.callback.register('AUST_trucker:getPlayerStats', function(source)
    local citizenId = GetPlayerCitizenId(source)
    local stats = GetPlayerStats(citizenId)
    return stats
end)
```

**Nota:** Remover a duplicata na linha ~1807.

- [x] **Passo 6: Verificar**

```bash
grep -n "QBCore" server/server.lua
```
Esperado: 0 resultados (apenas o evento `QBCore:Server:OnPlayerLoaded` é permitido manter).

`ensure AUST_trucker` no console — sem erros de nil em `QBCore`.

- [x] **Passo 7: Commit**

```bash
git add server/server.lua
git commit -m "refactor: server/server.lua — migrate QBCore → qbx_core"
```

---

## Task 6: Migrar server/server.lua — JSON → DB (Companies)

**Files:**
- Modify: `server/server.lua`

Contexto: `server.lua` usa `loadData`/`saveData` para `companies.json`. Vamos substituir por chamadas ao `database.lua`.

- [x] **Passo 1: Remover variáveis JSON no topo do arquivo**

Localizar e remover as linhas com:
```lua
local dataFilePath = GetResourcePath(GetCurrentResourceName()) .. '/data/companies.json'
local companiesData = { companies = {}, players = {} }
```
E as funções `loadData`, `saveData`, `loadCompaniesData` se existirem no topo.

- [x] **Passo 2: Substituir leituras de companiesData por cache e DB**

O `companiesData.companies[companyId]` → `VP_Trucker.Companies[companyId]`
O `companiesData.players[citizenId]` → `VP_Trucker.PlayerCompanies[citizenId]`

- [x] **Passo 3: Substituir escritas (create/join/leave/sell company)**

Cada função que chamava `saveData(dataFilePath, companiesData)` deve agora:
1. Chamar a função `DB_*` correspondente de `database.lua`
2. Atualizar o cache `VP_Trucker.Companies` e `VP_Trucker.PlayerCompanies`

**Exemplo — CreateCompany:**
```lua
-- ANTES:
local companyId = 'company_' .. os.time() .. '_' .. math.random(1000, 9999)
companiesData.companies[companyId] = {
    id = companyId, owner = citizenId, ...
}
companiesData.players[citizenId] = { companyId = companyId, role = 'owner' }
saveData(dataFilePath, companiesData)

-- DEPOIS:
local companyId = 'company_' .. os.time() .. '_' .. math.random(1000, 9999)
DB_CreateCompany(companyId, citizenId, name)
DB_AddMember(companyId, citizenId, 'owner')
-- Atualizar cache
VP_Trucker.Companies[companyId] = {
    id = companyId, owner_citizenid = citizenId, name = name,
    balance = 0, is_recruiting = 0
}
VP_Trucker.PlayerCompanies[citizenId] = companyId
```

- [x] **Passo 4: Substituir leitura de vehicles**

Buscas por veículos de empresa (`companiesData.companies[companyId].vehicles`) → `DB_GetVehicles(companyId)`

- [x] **Passo 5: Verificar**

```bash
grep -n "companiesData\|saveData\|loadData\|companies\.json" server/server.lua
```
Esperado: 0 resultados.

`ensure AUST_trucker` + criar uma empresa em jogo → verificar no DB:
```sql
SELECT * FROM trucker_companies;
SELECT * FROM trucker_company_members;
```

- [x] **Passo 6: Commit**

```bash
git add server/server.lua
git commit -m "refactor: server/server.lua — migrate companies JSON → oxmysql"
```

---

## Task 7: Migrar server/server.lua — JSON → DB (Player Stats)

**Files:**
- Modify: `server/server.lua`

- [x] **Passo 1: Remover variáveis de player_stats JSON**

Localizar e remover:
```lua
local playerStatsFilePath = GetResourcePath(GetCurrentResourceName()) .. '/data/player_stats.json'
local playerStatsData = { players = {} }
```
E funções `loadPlayerStatsData`, `savePlayerStatsData` se existirem.

- [x] **Passo 2: Substituir leitura de stats**

`playerStatsData.players[citizenId]` → `DB_GetPlayerStats(citizenId)`

- [x] **Passo 3: Substituir escrita de stats (após completar job)**

**ANTES:**
```lua
if not playerStatsData.players[citizenId] then
    playerStatsData.players[citizenId] = { totalEarnings = 0, totalDeliveries = 0, ... }
end
playerStatsData.players[citizenId].totalEarnings += payment
playerStatsData.players[citizenId].totalDeliveries += 1
savePlayerStatsData()
```

**DEPOIS:**
```lua
DB_AddPlayerStats(citizenId, payment, distance)
```

- [x] **Passo 4: Criar stats no onPlayerLoaded**

No handler de `QBCore:Server:OnPlayerLoaded`, adicionar:
```lua
local citizenId = Player.PlayerData.citizenid
DB_UpsertPlayerStats(citizenId)
```

- [x] **Passo 5: Verificar**

```bash
grep -n "playerStatsData\|player_stats\.json\|playerStatsFilePath" server/server.lua
```
Esperado: 0 resultados.

Completar um job em jogo e verificar no DB:
```sql
SELECT * FROM trucker_player_progression;
```

- [x] **Passo 6: Commit**

```bash
git add server/server.lua
git commit -m "refactor: server/server.lua — migrate player_stats JSON → oxmysql"
```

---

## Task 8: Migrar server/industries.server.lua — QBCore + JSON → DB

**Files:**
- Modify: `server/industries.server.lua`

- [x] **Passo 1: Remover GetCoreObject e variáveis JSON**

```lua
-- Remover:
local QBCore = exports['qb-core']:GetCoreObject()
local industriesDataPath = GetResourcePath(...) .. '/data/industries.json'
local industriesData = {}
```

- [x] **Passo 2: Substituir padrões QBCore**

Mesmo padrão da Task 5:
- `QBCore.Functions.GetPlayer(src)` → `exports.qbx_core:GetPlayer(src)`
- `Player.Functions.GetMoney` → `Player.PlayerData.money.cash`
- `Player.Functions.AddMoney` → mantém igual
- `Player.Functions.RemoveMoney` → mantém igual

- [x] **Passo 3: Criar seed do estado de indústrias no startup**

Adicionar função de seed que lê `Config.Industries` e inicializa `trucker_industry_state` se vazio:

```lua
local function SeedIndustryState()
    for industryId, industry in pairs(Config.Industries) do
        -- Produção
        if industry.production and industry.production.item then
            local existing = MySQL.single.await(
                "SELECT 1 FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'production' LIMIT 1",
                { industryId, industry.production.item }
            )
            if not existing then
                DB_UpsertIndustryState(industryId, industry.production.item, 'production',
                    industry.production.basePrice,
                    math.floor(industry.production.maxStock * 0.5))
            end
        end
        -- Consumo
        if industry.consumption then
            for _, consItem in ipairs(industry.consumption) do
                local existing = MySQL.single.await(
                    "SELECT 1 FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'consumption' LIMIT 1",
                    { industryId, consItem.item }
                )
                if not existing then
                    DB_UpsertIndustryState(industryId, consItem.item, 'consumption',
                        consItem.basePrice,
                        math.floor(consItem.maxStock * 0.5))
                end
            end
        end
    end
end

CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    SeedIndustryState()
end)
```

- [x] **Passo 4: Substituir leituras/escritas do estado de indústrias**

Onde o código lia `industriesData[industryId]` → usar `DB_GetIndustryState(industryId)`
Onde o código escrevia stock/preço → usar `DB_UpdateIndustryStock` ou `DB_UpdateIndustryPrice`

- [x] **Passo 5: Verificar**

```bash
grep -n "QBCore\|industriesData\|industries\.json" server/industries.server.lua
```
Esperado: 0 resultados.

`ensure AUST_trucker` e verificar:
```sql
SELECT * FROM trucker_industry_state;
```
Esperado: ~7 linhas (seed das 5 indústrias de Config.Industries)

- [x] **Passo 6: Commit**

```bash
git add server/industries.server.lua
git commit -m "refactor: industries.server.lua — migrate QBCore → qbx_core and JSON → oxmysql"
```

---

## Task 9: Migrar client files

**Files:**
- Modify: `client/client.lua`
- Modify: `client/industries.client.lua`
- Modify: `client/industries_npc.client.lua`

### client/client.lua

- [x] **Passo 1: Remover GetCoreObject**

Remover linha:
```lua
local QBCore = exports['qb-core']:GetCoreObject()
```

- [x] **Passo 2: Substituir TriggerCallback**

Localizar linha ~1325:
```lua
QBCore.Functions.TriggerCallback('aurp-trucker:getPlayerStats', function(success, stats)
    ...
end)
```

Substituir por:
```lua
local ok, stats = pcall(lib.callback.await, 'AUST_trucker:getPlayerStats', false)
if ok and stats then
    SendNUIMessage({ action = 'updateStats', stats = stats })
end
```

- [x] **Passo 3: Verificar**

```bash
grep -n "QBCore" client/client.lua
```
Esperado: apenas `QBCore:Client:OnPlayerUnload` (evento compatível, pode manter).

### client/industries.client.lua

- [x] **Passo 4: Substituir TriggerCallback**

Remover `local QBCore = exports['qb-core']:GetCoreObject()`

Linha 8 — substituir:
```lua
-- ANTES:
QBCore.Functions.TriggerCallback('aurp-trucker:getIndustries', function(industries)
    cb(industries)
end)

-- DEPOIS:
local ok, industries = pcall(lib.callback.await, 'AUST_trucker:getIndustries', false)
cb(ok and industries or nil)
```

### client/industries_npc.client.lua

- [x] **Passo 5: Remover GetCoreObject e substituir Notify**

Remover: `local QBCore = exports['qb-core']:GetCoreObject()`

Linha ~49: `QBCore.Functions.Notify(...)` → `lib.notify({ title = 'AURP Trucker', description = '...', type = 'error' })`

- [x] **Passo 6: Substituir TriggerCallback**

Linha ~47:
```lua
-- ANTES:
QBCore.Functions.TriggerCallback('aurp-trucker:getIndustryData', function(industryData)
    if not industryData then
        QBCore.Functions.Notify('Indústria não encontrada', 'error')
        return
    end
    ...
end, industryId)

-- DEPOIS:
local ok, industryData = pcall(lib.callback.await, 'AUST_trucker:getIndustryData', false, industryId)
if not ok or not industryData then
    lib.notify({ title = 'AURP Trucker', description = 'Indústria não encontrada', type = 'error' })
    return
end
```

- [x] **Passo 7: Substituir lation_ui → ox_lib (linhas 125-132)**

```lua
-- ANTES:
exports.lation_ui:registerMenu({
    id = 'industry_' .. industryId,
    title = industryData.name,
    subtitle = 'Economia Dinâmica',
    options = menuOptions
})
exports.lation_ui:showMenu('industry_' .. industryId)

-- DEPOIS:
lib.registerContext({
    id = 'trucker_industry_' .. industryId,
    title = industryData.name,
    options = menuOptions
})
lib.showContext('trucker_industry_' .. industryId)
```

**Nota:** ox_lib não tem `subtitle` — remover esse campo. O array `menuOptions` já tem estrutura compatível com `lib.registerContext` (title, description, icon, iconColor, readOnly, metadata, onSelect).

- [x] **Passo 8: Verificar**

```bash
grep -n "QBCore\|lation_ui\|lation\." client/client.lua client/industries.client.lua client/industries_npc.client.lua
```
Esperado: 0 resultados.

Conectar ao servidor, ir até uma indústria de Config.Industries, abrir menu — deve abrir sem erros.

- [x] **Passo 9: Commit**

```bash
git add client/client.lua client/industries.client.lua client/industries_npc.client.lua
git commit -m "refactor: client files — migrate QBCore → qbx_core, lation_ui → ox_lib"
```

---

## Task 10: Limpeza Final

**Files:**
- Delete: `data/companies.json`
- Delete: `data/industries.json`
- Delete: `data/player_stats.json`
- Modify: `config/config.lua` — corrigir ID duplicado `airport_warehouse`

- [x] **Passo 1: Deletar arquivos JSON**

```bash
rm data/companies.json data/industries.json data/player_stats.json
rmdir data/ 2>/dev/null || true
```

- [x] **Passo 2: Corrigir IDs duplicados em config/config.lua**

No `Config.PrimaryIndustries`, localizar a entrada com `id = "airport_warehouse"` (Armazém LSIA) e renomear para `id = "lsia_warehouse_cargo"`.

No `Config.SecondaryIndustries`, localizar a entrada com `id = "airport_warehouse"` (Armazém LSIA Sul) e renomear para `id = "lsia_warehouse_south"`.

```bash
grep -n "airport_warehouse" config/config.lua
```
Esperado após correção: 0 resultados.

- [x] **Passo 3: Verificar ausência total de referências JSON e QBCore**

```bash
grep -rn "QBCore\|lation_ui\|companies\.json\|industries\.json\|player_stats\.json\|loadData\|saveData" server/ client/
```
Esperado: 0 resultados.

- [x] **Passo 4: Teste de integração completo**

1. `ensure AUST_trucker` — sem erros no console
2. Conectar com jogador — `[AUST_trucker] Server ready.` visível
3. Abrir UI (F6) — interface abre
4. Criar empresa ($150k) — verificar `SELECT * FROM trucker_companies`
5. Aceitar um job — verificar `SELECT * FROM trucker_jobs WHERE status = 'active'`
6. Completar job — verificar `SELECT * FROM trucker_player_progression`
7. Reiniciar servidor (`restart AUST_trucker`) — empresa ainda existe após restart

- [x] **Passo 5: Commit final da Fase 1**

```bash
git add -A
git commit -m "feat: Phase 1 complete — QBX + oxmysql + ox_lib migration done"
```

---

## Checklist de Verificação Final da Fase 1

Antes de passar para a Fase 2, confirmar:

- [x] `ensure AUST_trucker` inicia sem erros no console do servidor
- [x] `grep -rn "QBCore\|lation_ui\|qb-core" server/ client/ fxmanifest.lua` retorna 0 resultados (exceto evento OnPlayerLoaded/OnPlayerUnload)
- [x] `grep -rn "\.json\|loadData\|saveData" server/` retorna 0 resultados
- [x] `data/` directory não existe mais
- [x] Criar empresa → persiste no DB após `restart AUST_trucker`
- [x] Completar job → stats registradas em `trucker_player_progression`
- [x] Abrir menu de indústria (ox_lib) → abre sem erros
- [x] UI NUI abre e mostra dados corretos (jobs, empresa se tiver)

---

## Próxima Fase

Após concluir e verificar todos os itens acima:
**→ Plano 2: Server Refactor** (`docs/superpowers/plans/2026-03-19-phase2-server-refactor.md`)
