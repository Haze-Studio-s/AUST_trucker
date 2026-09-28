# Repo Man — Backend & NUI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add the Repo Man system pipeline: repo order generation (loan defaults + NPC pool), RepoService, `company_type` routing, and a "Missões" NUI tab for repo companies.

**Architecture:** A new global `RepoService` (Lua, server-side) handles order generation, acceptance, completion, and failure. Orders are stored in `trucker_repo_orders` (modified schema). The NUI gains a `useRepoStore` + `RepoPanel` that replaces the Jobs tab for `company_type = 'repo'` companies. All datetime writes use `FROM_UNIXTIME(?)`, reads use `UNIX_TIMESTAMP(col) as col_unix`.

**Tech Stack:** Lua 5.4 (oxmysql, ox_lib, qbx_core, ox_target), React 18 + TypeScript 5 + Tailwind CSS 3 + Zustand 4, Vite 5.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `import.sql` | Modify | Add `loan_id` column + `UNIQUE KEY uq_loan_id` to `trucker_repo_orders` |
| `config/config.lua` | Modify | Append `Config.RepoMan` block |
| `server/database.lua` | Modify | Update `DB_CreateCompany`; add `DB_InsertRepoOrder`, `DB_GetAvailableRepoOrders`, `DB_CountAvailableNpcOrders`, `DB_GetActiveRepoOrder`, `DB_AcceptRepoOrder`, `DB_UpdateRepoOrderStatus`, `DB_CompleteRepoOrder`, `DB_ExpireRepoOrders`, `DB_GetRepoOrderById`, `DB_GetLoanById` |
| `server/services/company_service.lua` | Modify | `CompanyService.Create` accepts `companyType`; populates cache with `company_type` |
| `server/events.lua` | Modify | Fix `createCompany` handler to accept `companyType`; add `completeRepoOrder`, `failRepoOrder` handlers |
| `server/services/loan_service.lua` | Modify | `CheckOverdue` calls `RepoService.GenerateFromLoan(loan)` after penalty |
| `server/services/repo_service.lua` | Create | `RepoService` global: `GenerateFromLoan`, `GenerateNPC`, `Accept`, `Complete`, `Fail`, `CheckExpired`, `BroadcastAvailableOrders`; NPC pool thread; expiry thread |
| `fxmanifest.lua` | Modify | Add `repo_service.lua` after `loan_service.lua` |
| `server/callbacks.lua` | Modify | Update `getInitialData` for repo fields; add `getRepoOrders`, `acceptRepoOrder` |
| `client/client.lua` | Modify | Fix `createCompany` NUI callback; add `acceptRepoOrder`, `failRepoOrder` NUI callbacks; add 3 `RegisterNetEvent` handlers for repo |
| `html/src/types/repo.ts` | Create | `RepoOrder`, `RepoMissionType`, `RepoOrderStatus` TypeScript types |
| `html/src/types/index.ts` | Modify | Add `company_type` to `Company`; add `'missions'` to `TabName` |
| `html/src/stores/useRepoStore.ts` | Create | Zustand store: `repoOrders`, `activeRepoOrder` |
| `html/src/hooks/useNUI.ts` | Modify | Add repo to NUIMessage; `open` case hydration; `updateRepoOrders`, `startRepoMission`, `repoMissionComplete` cases |
| `html/src/components/repo/RepoCard.tsx` | Create | Card for a single available repo order |
| `html/src/components/repo/RepoPanel.tsx` | Create | Available orders list + active mission panel |
| `html/src/components/company/CompanySetup.tsx` | Modify | Add company type radio selection before create button |
| `html/src/components/layout/TabBar.tsx` | Modify | Show "Missões" tab (id `missions`) instead of "Jobs" for repo companies |
| `html/src/App.tsx` | Modify | Route `activeTab === 'missions'` to `<RepoPanel />`; route `activeTab === 'jobs'` to `<JobList />` |

---

## Task 1: Schema — add loan_id to trucker_repo_orders

**Files:**
- Modify: `import.sql`

The existing `trucker_repo_orders` CREATE TABLE is missing `loan_id INT NULL` and `UNIQUE KEY uq_loan_id(loan_id)`. These are required so `LoanService.CheckOverdue` can link repo orders to loans, and `INSERT IGNORE` deduplicates across CheckOverdue cycles.

- [x] **Step 1: Locate the CREATE TABLE in import.sql**

Open `import.sql` and find the `CREATE TABLE trucker_repo_orders` block (around line 191). It currently ends with `INDEX idx_company_id (company_id)`.

- [x] **Step 2: Add loan_id column and UNIQUE KEY**

Replace the closing of the CREATE TABLE:

```sql
-- BEFORE (existing lines at end of trucker_repo_orders):
    payment                 BIGINT          NOT NULL,
    created_at              DATETIME        DEFAULT CURRENT_TIMESTAMP,
    expires_at              DATETIME        NOT NULL,
    completed_at            DATETIME        NULL,
    INDEX idx_status            (status),
    INDEX idx_vehicle_owner     (vehicle_owner_citizenid),
    INDEX idx_status_expires    (status, expires_at),
    INDEX idx_company_id        (company_id)
);
```

```sql
-- AFTER:
    payment                 BIGINT          NOT NULL,
    loan_id                 INT             NULL,
    created_at              DATETIME        DEFAULT CURRENT_TIMESTAMP,
    expires_at              DATETIME        NOT NULL,
    completed_at            DATETIME        NULL,
    INDEX idx_status            (status),
    INDEX idx_vehicle_owner     (vehicle_owner_citizenid),
    INDEX idx_status_expires    (status, expires_at),
    INDEX idx_company_id        (company_id),
    UNIQUE KEY uq_loan_id       (loan_id)
);
```

- [x] **Step 3: Verify diff is minimal**

Confirm only the `loan_id` line and the `UNIQUE KEY` line were added (+ comma after `idx_company_id` index).

- [x] **Step 4: Commit**

```bash
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker"
git add import.sql
git commit -m "feat(schema): add loan_id + UNIQUE KEY to trucker_repo_orders"
```

---

## Task 2: Config — add Config.RepoMan

**Files:**
- Modify: `config/config.lua` (append after `Config.Loans` block, around line 634)

- [x] **Step 1: Append Config.RepoMan at end of config.lua**

Add this block after the closing `}` of `Config.Loans`:

```lua
Config.RepoMan = {
    -- Geração de ordens
    PoolInterval        = 1800,      -- segundos entre verificações do pool NPC (30 min)
    MaxNpcOrders        = 5,         -- máximo de ordens NPC disponíveis simultaneamente
    NpcOrderExpiry      = 7200,      -- segundos até expirar ordem NPC (2h)
    LoanOrderExpiry     = 86400,     -- segundos até expirar ordem de loan (24h)
    NpcMissionWeights   = { simple = 70, npc_hostile = 30 },

    -- Pagamento
    PaymentRate         = 0.15,      -- 15% do vehicle_value
    CompanyFeeRate      = 0.20,      -- empresa recebe 20% do pagamento do agente
    TypeMultipliers     = {
        simple      = 1.0,
        npc_hostile = 1.5,
        pvp         = 2.0,
        stealth     = 2.5,
    },

    -- Veículos (lookup de valor por modelo)
    DefaultVehicleValue = 50000,
    VehicleValues = {
        flatbed     = 80000,
        hauler      = 120000,
        phantom     = 150000,
        mule        = 60000,
        bison       = 45000,
    },

    -- Veículos NPC (pool)
    NpcVehicles = {
        { model = 'mule',    label = 'Mule',    value = 60000 },
        { model = 'bison',   label = 'Bison',   value = 45000 },
        { model = 'flatbed', label = 'Flatbed', value = 80000 },
    },

    -- Zonas NPC (coordenadas de localização dos veículos NPC no mapa)
    NpcZones = {
        { name = 'Porto de LS',  coords = vector3(-670.0, -1450.0, 5.0),  radius = 80.0 },
        { name = 'Boneyard',     coords = vector3(1660.0, 3167.0, 41.0),  radius = 60.0 },
        { name = 'Sandy Shores', coords = vector3(1820.0, 3692.0, 34.0),  radius = 70.0 },
        { name = 'Paleto Bay',   coords = vector3(-183.0, 6317.0, 31.0),  radius = 50.0 },
        { name = 'Grapeseed',    coords = vector3(1696.0, 4789.0, 42.0),  radius = 60.0 },
    },

    -- Impound (entrega — Sub-spec 2)
    ImpoundLocation     = vector3(400.0, -1640.0, 29.0),
    ImpoundHeading      = 90.0,
}
```

- [x] **Step 2: Verify Config.Debug mode and resource restart won't crash**

Config is a `shared_script` — any syntax error will prevent the resource from loading. Count all braces/brackets in the new block to confirm they're balanced.

- [x] **Step 3: Commit**

```bash
git add config/config.lua
git commit -m "feat(config): add Config.RepoMan block"
```

---

## Task 3: DB functions — add DB_Repo* and DB_GetLoanById

**Files:**
- Modify: `server/database.lua` (append after the `-- LOANS` section at the end)

Also update `DB_CreateCompany` (line 9) to accept `companyType`.

- [x] **Step 1: Update DB_CreateCompany signature**

In `server/database.lua`, replace the existing `DB_CreateCompany`:

```lua
-- BEFORE (line 9):
function DB_CreateCompany(id, ownerCitizenId, name)
    return MySQL.insert.await(
        'INSERT INTO trucker_companies (id, owner_citizenid, name) VALUES (?, ?, ?)',
        { id, ownerCitizenId, name }
    )
end
```

```lua
-- AFTER:
function DB_CreateCompany(id, ownerCitizenId, name, companyType)
    companyType = companyType or 'logistics'
    return MySQL.insert.await(
        'INSERT INTO trucker_companies (id, owner_citizenid, name, company_type) VALUES (?, ?, ?, ?)',
        { id, ownerCitizenId, name, companyType }
    )
end
```

- [x] **Step 2: Append REPO MAN section after the LOANS section**

At the very end of `server/database.lua`, add:

```lua
-- ============================================================
-- REPO MAN
-- ============================================================

function DB_InsertRepoOrder(vehiclePlate, vehicleModel, vehicleValue, vehicleOwnerCitizenId,
                             missionType, locationZone, payment, expiresAt, loanId)
    -- companyId always nil at insert — set via DB_AcceptRepoOrder
    return MySQL.insert.await(
        [[INSERT IGNORE INTO trucker_repo_orders
            (vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
             mission_type, location_zone, payment, expires_at, loan_id, status)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, 'available')]],
        { vehiclePlate, vehicleModel, vehicleValue, vehicleOwnerCitizenId,
          missionType, locationZone, payment, expiresAt, loanId }
    )
end

function DB_GetAvailableRepoOrders()
    return MySQL.query.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders
          WHERE status = 'available'
          ORDER BY created_at DESC]]
    )
end

function DB_CountAvailableNpcOrders()
    return MySQL.scalar.await(
        [[SELECT COUNT(*) FROM trucker_repo_orders
          WHERE status = 'available' AND vehicle_owner_citizenid IS NULL AND expires_at > NOW()]]
    ) or 0
end

function DB_GetActiveRepoOrder(citizenId)
    return MySQL.single.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status, company_id, loan_id,
                 assigned_citizenid,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders
          WHERE assigned_citizenid = ? AND status = 'active' LIMIT 1]],
        { citizenId }
    )
end

function DB_AcceptRepoOrder(orderId, citizenId, companyId)
    return MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'active', assigned_citizenid = ?, company_id = ?
          WHERE id = ? AND status = 'available']],
        { citizenId, companyId, orderId }
    )
end

function DB_UpdateRepoOrderStatus(orderId, newStatus, assignedCitizenId, companyId)
    MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = ?, assigned_citizenid = ?, company_id = ?
          WHERE id = ?]],
        { newStatus, assignedCitizenId, companyId, orderId }
    )
end

function DB_CompleteRepoOrder(orderId, completedAt)
    MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'completed', completed_at = FROM_UNIXTIME(?)
          WHERE id = ?]],
        { completedAt, orderId }
    )
end

function DB_ExpireRepoOrders()
    MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'expired'
          WHERE expires_at < NOW() AND status IN ('available', 'active')]]
    )
end

function DB_GetRepoOrderById(orderId)
    return MySQL.single.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status, company_id, loan_id,
                 assigned_citizenid,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders WHERE id = ? LIMIT 1]],
        { orderId }
    )
end

function DB_GetLoanById(loanId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at_unix
          FROM trucker_loans WHERE id = ? LIMIT 1]],
        { loanId }
    )
end
```

- [x] **Step 3: Verify function count**

Count functions in the REPO MAN section: should be exactly 10 (`DB_InsertRepoOrder`, `DB_GetAvailableRepoOrders`, `DB_CountAvailableNpcOrders`, `DB_GetActiveRepoOrder`, `DB_AcceptRepoOrder`, `DB_UpdateRepoOrderStatus`, `DB_CompleteRepoOrder`, `DB_ExpireRepoOrders`, `DB_GetRepoOrderById`, `DB_GetLoanById`).

- [x] **Step 4: Commit**

```bash
git add server/database.lua
git commit -m "feat(db): add DB_Repo* functions + update DB_CreateCompany for companyType"
```

---

## Task 4: CompanyService + createCompany event — support companyType

**Files:**
- Modify: `server/services/company_service.lua` (lines 28–61)
- Modify: `server/events.lua` (lines 52–62)
- Modify: `client/client.lua` (lines 444–459 — createCompany NUI callback)

### 4a — CompanyService.Create

In `server/services/company_service.lua`, replace `CompanyService.Create`:

- [x] **Step 1: Update CompanyService.Create signature and cache entry**

```lua
-- BEFORE (line 28):
function CompanyService.Create(src, name)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end

    local citizenId = Player.PlayerData.citizenid

    -- Verificar se já tem empresa
    if VP_Trucker.PlayerCompanies[citizenId] then
        return nil, 'Você já faz parte de uma empresa'
    end

    -- Verificar saldo
    if Player.PlayerData.money.cash < CREATION_COST then
        return nil, ('Você precisa de $%d para criar uma empresa'):format(CREATION_COST)
    end

    -- Cobrar
    if not Player.Functions.RemoveMoney('cash', CREATION_COST, 'company-creation') then
        return nil, 'Falha ao processar pagamento'
    end

    -- Criar no DB
    local companyId = ('company_%d_%d'):format(os.time(), math.random(1000, 9999))
    DB_CreateCompany(companyId, citizenId, name)
    DB_AddMember(companyId, citizenId, 'owner')

    -- Atualizar cache
    VP_Trucker.Companies[companyId] = {
        id = companyId, owner_citizenid = citizenId, name = name,
        balance = 0, is_recruiting = 0
    }
    VP_Trucker.PlayerCompanies[citizenId] = companyId

    return companyId, nil
end
```

```lua
-- AFTER:
function CompanyService.Create(src, name, companyType)
    companyType = (companyType == 'repo') and 'repo' or 'logistics'

    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end

    local citizenId = Player.PlayerData.citizenid

    -- Verificar se já tem empresa
    if VP_Trucker.PlayerCompanies[citizenId] then
        return nil, 'Você já faz parte de uma empresa'
    end

    -- Verificar saldo
    if Player.PlayerData.money.cash < CREATION_COST then
        return nil, ('Você precisa de $%d para criar uma empresa'):format(CREATION_COST)
    end

    -- Cobrar
    if not Player.Functions.RemoveMoney('cash', CREATION_COST, 'company-creation') then
        return nil, 'Falha ao processar pagamento'
    end

    -- Criar no DB
    local companyId = ('company_%d_%d'):format(os.time(), math.random(1000, 9999))
    DB_CreateCompany(companyId, citizenId, name, companyType)
    DB_AddMember(companyId, citizenId, 'owner')

    -- Atualizar cache (inclui company_type para RepoService.Accept)
    VP_Trucker.Companies[companyId] = {
        id              = companyId,
        owner_citizenid = citizenId,
        name            = name,
        balance         = 0,
        is_recruiting   = 0,
        company_type    = companyType,
    }
    VP_Trucker.PlayerCompanies[citizenId] = companyId

    return companyId, nil
end
```

### 4b — events.lua createCompany handler

In `server/events.lua`, replace the `AUST_trucker:createCompany` handler:

- [x] **Step 2: Update createCompany event to extract companyType**

```lua
-- BEFORE (line 52):
RegisterNetEvent('AUST_trucker:createCompany', function(name)
    local src = source
    local companyId, err = CompanyService.Create(src, name)
    if err then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    local company = CompanyService.Get(companyId)
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, company)
    TriggerClientEvent('AUST_trucker:notify', src, 'Empresa criada com sucesso!', 'success')
end)
```

```lua
-- AFTER:
RegisterNetEvent('AUST_trucker:createCompany', function(name, companyType)
    local src = source
    local companyId, err = CompanyService.Create(src, name, companyType)
    if err then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    local company = CompanyService.Get(companyId)
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, company)
    TriggerClientEvent('AUST_trucker:notify', src, 'Empresa criada com sucesso!', 'success')
end)
```

### 4c — client.lua createCompany NUI callback

In `client/client.lua`, replace the `createCompany` RegisterNUICallback (around line 444):

- [x] **Step 3: Fix createCompany NUI callback**

```lua
-- BEFORE (lines 444–459):
RegisterNUICallback('createCompany', function(data, cb)
    local companyName = data.companyName

    if not companyName or companyName == "" then
        ShowNotification(
            'Erro',
            'Nome da empresa é obrigatório',
            'error'
        )
        cb('ok')
        return
    end

    TriggerServerEvent('aurp-trucker:createCompany', companyName)
    cb('ok')
end)
```

```lua
-- AFTER:
RegisterNUICallback('createCompany', function(data, cb)
    local name = data.name or ''
    local companyType = data.companyType or 'logistics'

    if name == '' then
        cb('ok')
        return
    end

    TriggerServerEvent('AUST_trucker:createCompany', name, companyType)
    cb('ok')
end)
```

- [x] **Step 4: Commit**

```bash
git add server/services/company_service.lua server/events.lua client/client.lua
git commit -m "feat(company): add companyType to Create + fix createCompany event prefix"
```

---

## Task 5: LoanService — hook CheckOverdue into RepoService

**Files:**
- Modify: `server/services/loan_service.lua` (lines 142–169, `LoanService.CheckOverdue`)

`RepoService` will be loaded after `loan_service.lua` (via fxmanifest), so `RepoService` global is available when `CheckOverdue` runs. The call must be guarded (`if RepoService then`) because during resource startup `loan_service.lua` loads before `repo_service.lua`.

- [x] **Step 1: Update CheckOverdue to call RepoService.GenerateFromLoan**

In `server/services/loan_service.lua`, inside `LoanService.CheckOverdue`, add the GenerateFromLoan call after `DB_UpdateLoanBalance`:

```lua
-- BEFORE (lines 147–151 inside the for loop):
    for _, loan in ipairs(loans) do
        local newBalance    = math.ceil(loan.remaining_balance * (1 + PENALTY_RATE))
        local nextPaymentAt = os.time() + INSTALLMENT_SECONDS

        DB_UpdateLoanBalance(loan.id, newBalance, 'active', nextPaymentAt)

        print(('[AUST_trucker] Loan #%d overdue — penalty applied. New balance: $%d'):format(
            loan.id, newBalance))
```

```lua
-- AFTER:
    for _, loan in ipairs(loans) do
        local newBalance    = math.ceil(loan.remaining_balance * (1 + PENALTY_RATE))
        local nextPaymentAt = os.time() + INSTALLMENT_SECONDS

        DB_UpdateLoanBalance(loan.id, newBalance, 'active', nextPaymentAt)

        -- Generate repo order for the defaulted loan (post-penalty balance)
        if RepoService then
            loan.remaining_balance = newBalance   -- pass post-penalty balance
            RepoService.GenerateFromLoan(loan)
        end

        print(('[AUST_trucker] Loan #%d overdue — penalty applied. New balance: $%d'):format(
            loan.id, newBalance))
```

- [x] **Step 2: Commit**

```bash
git add server/services/loan_service.lua
git commit -m "feat(loans): hook CheckOverdue into RepoService.GenerateFromLoan"
```

---

## Task 6: repo_service.lua + fxmanifest

**Files:**
- Create: `server/services/repo_service.lua`
- Modify: `fxmanifest.lua`

- [x] **Step 1: Create server/services/repo_service.lua**

```lua
-- AUST_trucker — server/services/repo_service.lua
-- RepoService: Geração, aceitação, conclusão e falha de ordens de repossessão

RepoService = {}

-- Constantes lidas de Config.RepoMan
local POOL_INTERVAL     = Config.RepoMan.PoolInterval
local MAX_NPC_ORDERS    = Config.RepoMan.MaxNpcOrders
local NPC_ORDER_EXPIRY  = Config.RepoMan.NpcOrderExpiry
local LOAN_ORDER_EXPIRY = Config.RepoMan.LoanOrderExpiry
local PAYMENT_RATE      = Config.RepoMan.PaymentRate
local COMPANY_FEE_RATE  = Config.RepoMan.CompanyFeeRate
local TYPE_MULTIPLIERS  = Config.RepoMan.TypeMultipliers
local NPC_MISSION_WEIGHTS = Config.RepoMan.NpcMissionWeights

-- Helper: broadcast lista atualizada para todos os agentes repo online
-- NOTA: usa lookup de campo de tabela (RepoService.BroadcastAvailableOrders) — safe para chamar
--       em Accept/Complete/Fail mesmo sendo definido após essas funções, pois a atribuição abaixo
--       ocorre em load time antes de qualquer jogador conectar.
local function BroadcastAvailableOrders()
    local orders = DB_GetAvailableRepoOrders()
    for _, playerId in ipairs(GetPlayers()) do
        local pPlayer = exports.qbx_core:GetPlayer(tonumber(playerId))
        local pCitizenId = pPlayer and pPlayer.PlayerData.citizenid
        if pCitizenId then
            local company = CompanyService.GetByMember(pCitizenId)
            if company and company.company_type == 'repo' then
                TriggerClientEvent('AUST_trucker:client:updateRepoOrders', tonumber(playerId), orders)
            end
        end
    end
end
RepoService.BroadcastAvailableOrders = BroadcastAvailableOrders

-- Helper: weighted random mission type from weights table
local function WeightedRandom(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local roll = math.random(1, total)
    local cumulative = 0
    for missionType, w in pairs(weights) do
        cumulative = cumulative + w
        if roll <= cumulative then return missionType end
    end
end

---Generates a repo order from a loan default.
---@param loan table  row from trucker_loans (remaining_balance = post-penalty)
function RepoService.GenerateFromLoan(loan)
    local vehicles
    if loan.company_id then
        vehicles = DB_GetVehicles(loan.company_id)
    else
        -- Find the owner's company
        local companyId = VP_Trucker.PlayerCompanies[loan.citizenid]
        if companyId then
            vehicles = DB_GetVehicles(companyId)
        end
    end

    if not vehicles or #vehicles == 0 then return end

    local vehicle     = vehicles[math.random(#vehicles)]
    local vehicleModel = string.lower(vehicle.model or '')
    local vehicleValue = Config.RepoMan.VehicleValues[vehicleModel] or Config.RepoMan.DefaultVehicleValue
    local payment      = math.floor(vehicleValue * PAYMENT_RATE * TYPE_MULTIPLIERS['pvp'])
    local expiresAt    = os.time() + LOAN_ORDER_EXPIRY

    DB_InsertRepoOrder(
        vehicle.plate, vehicleModel, vehicleValue, loan.citizenid,
        'pvp', 'Desconhecida', payment, expiresAt, loan.id
    )
end

---Generates a random NPC repo order.
function RepoService.GenerateNPC()
    local npcVehicles = Config.RepoMan.NpcVehicles
    local npcZones    = Config.RepoMan.NpcZones
    local vehicle     = npcVehicles[math.random(#npcVehicles)]
    local zone        = npcZones[math.random(#npcZones)]
    local missionType = WeightedRandom(NPC_MISSION_WEIGHTS)
    local plate       = 'NPC-' .. math.random(100000, 999999)
    local payment     = math.floor(vehicle.value * PAYMENT_RATE * TYPE_MULTIPLIERS[missionType])
    local expiresAt   = os.time() + NPC_ORDER_EXPIRY

    DB_InsertRepoOrder(
        plate, vehicle.model, vehicle.value, nil,
        missionType, zone.name, payment, expiresAt, nil
    )
end

---Accepts a repo order for a player.
---@param src number  player server id
---@param orderId number
---@return table  { success, order?, reason? }
function RepoService.Accept(src, orderId)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid

    -- Must belong to a repo company
    local company = CompanyService.GetByMember(citizenId)
    if not company or company.company_type ~= 'repo' then
        return { success = false, reason = 'Apenas membros de empresa Repo Man podem aceitar ordens' }
    end

    -- Cannot have another active order
    local active = DB_GetActiveRepoOrder(citizenId)
    if active then
        return { success = false, reason = 'Você já tem uma missão ativa' }
    end

    -- Atomic accept: returns 0 if order already taken (race condition guard)
    local affected = DB_AcceptRepoOrder(orderId, citizenId, company.id)
    if not affected or affected == 0 then
        return { success = false, reason = 'Ordem não disponível' }
    end

    local order = DB_GetRepoOrderById(orderId)
    TriggerClientEvent('AUST_trucker:client:startRepoMission', src, order)
    RepoService.BroadcastAvailableOrders()

    return { success = true, order = order }
end

---Completes an active repo mission.
---@param src number
---@param orderId number
---@return table  { success, payment?, companyFee?, reason? }
function RepoService.Complete(src, orderId)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid

    local order = DB_GetRepoOrderById(orderId)
    if not order or order.status ~= 'active' or order.assigned_citizenid ~= citizenId then
        return { success = false, reason = 'Ordem não encontrada ou inválida' }
    end

    DB_CompleteRepoOrder(orderId, os.time())

    local payment    = order.payment
    local companyFee = math.floor(payment * COMPANY_FEE_RATE)

    -- Pay agent
    Player.Functions.AddMoney('bank', payment, 'repo-completion')

    -- Pay company
    DB_UpdateCompanyBalance(order.company_id, companyFee)
    if VP_Trucker.Companies[order.company_id] then
        local newBal = MySQL.scalar.await(
            'SELECT balance FROM trucker_companies WHERE id = ? LIMIT 1',
            { order.company_id }
        )
        VP_Trucker.Companies[order.company_id].balance = newBal or 0
    end

    -- Abate on loan if applicable
    if order.loan_id then
        local loan = DB_GetLoanById(order.loan_id)
        if loan and loan.status == 'active' then
            local newBalance = math.max(0, loan.remaining_balance - order.vehicle_value)
            local newStatus  = newBalance == 0 and 'paid' or 'active'
            local nextPayAt  = newBalance > 0
                and (loan.next_payment_at_unix + Config.Loans.InstallmentDays * 86400)
                or nil
            DB_UpdateLoanBalance(loan.id, newBalance, newStatus, nextPayAt)

            -- Notify loan owner if online
            local players = GetPlayers()
            for _, pid in ipairs(players) do
                local P = exports.qbx_core:GetPlayer(tonumber(pid))
                if P and P.PlayerData.citizenid == loan.citizenid then
                    lib.notify(tonumber(pid), {
                        title       = 'Repossessão',
                        description = ('Veículo repossessado. Saldo do empréstimo reduzido em $%d'):format(
                            order.vehicle_value),
                        type     = 'warning',
                        duration = 8000,
                    })
                    break
                end
            end
        end
    end

    -- Notify vehicle owner if online and not NPC
    if order.vehicle_owner_citizenid then
        local players = GetPlayers()
        for _, pid in ipairs(players) do
            local P = exports.qbx_core:GetPlayer(tonumber(pid))
            if P and P.PlayerData.citizenid == order.vehicle_owner_citizenid then
                lib.notify(tonumber(pid), {
                    title       = 'Veículo Repossessado',
                    description = 'Um agente Repo Man recolheu seu veículo inadimplente',
                    type        = 'error',
                    duration    = 8000,
                })
                break
            end
        end
    end

    RepoService.BroadcastAvailableOrders()

    return { success = true, payment = payment, companyFee = companyFee }
end

---Fails (abandons) an active repo mission, returning order to available.
---@param src number
---@param orderId number
---@return table  { success }
function RepoService.Fail(src, orderId)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid

    local order = DB_GetRepoOrderById(orderId)
    if not order or order.status ~= 'active' or order.assigned_citizenid ~= citizenId then
        return { success = false }
    end

    DB_UpdateRepoOrderStatus(orderId, 'available', nil, nil)
    RepoService.BroadcastAvailableOrders()

    return { success = true }
end

---Expires stale orders (called by thread).
function RepoService.CheckExpired()
    DB_ExpireRepoOrders()
end

-- Thread: NPC pool — keep up to MaxNpcOrders NPC orders available
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        local count = DB_CountAvailableNpcOrders()
        while count < MAX_NPC_ORDERS do
            RepoService.GenerateNPC()
            count = count + 1
        end
        Wait(POOL_INTERVAL * 1000)
    end
end)

-- Thread: Expire stale orders every 5 minutes
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(300 * 1000)
        RepoService.CheckExpired()
    end
end)
```

- [x] **Step 2: Add repo_service.lua to fxmanifest.lua**

In `fxmanifest.lua`, add `repo_service.lua` after `loan_service.lua`:

```lua
-- BEFORE:
    'server/services/loan_service.lua',
    'server/services/economy_service.lua',
```

```lua
-- AFTER:
    'server/services/loan_service.lua',
    'server/services/repo_service.lua',    -- após loan_service (usa LoanService via CheckOverdue)
    'server/services/economy_service.lua',
```

- [x] **Step 3: Verify RepoService is global**

`RepoService = {}` at the top of the file — not `local`. Under `lua54 'yes'`, this makes it accessible to all other server scripts.

- [x] **Step 4: Commit**

```bash
git add server/services/repo_service.lua fxmanifest.lua
git commit -m "feat(repo): add RepoService + fxmanifest load order"
```

---

## Task 7: Server events + callbacks

**Files:**
- Modify: `server/events.lua` (append at end)
- Modify: `server/callbacks.lua` (update getInitialData + append 2 new callbacks)

### 7a — events.lua

- [x] **Step 1: Append repo events at the end of server/events.lua**

```lua
-- ============================================================
-- REPO MAN
-- ============================================================

RegisterNetEvent('AUST_trucker:completeRepoOrder', function(orderId)
    local src    = source
    local result = RepoService.Complete(src, tonumber(orderId) or 0)
    if result.success then
        TriggerClientEvent('AUST_trucker:client:repoMissionComplete', src, result)
    else
        lib.notify(src, { title = 'Repo Man', description = result.reason, type = 'error' })
    end
end)

RegisterNetEvent('AUST_trucker:failRepoOrder', function(orderId)
    RepoService.Fail(source, tonumber(orderId) or 0)
end)
```

### 7b — callbacks.lua

- [x] **Step 2: Update getInitialData to include repo fields**

In `server/callbacks.lua`, replace the `AUST_trucker:getInitialData` callback:

```lua
-- BEFORE:
lib.callback.register('AUST_trucker:getInitialData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    local citizenId = Player.PlayerData.citizenid

    local company = CompanyService.GetByMember(citizenId)
    return {
        jobs                = JobService.GetAvailable(),
        company             = company,
        activeJob           = JobService.GetActiveByPlayer(citizenId),
        stats               = DB_GetPlayerStats(citizenId),
        recruitingCompanies = CompanyService.GetRecruiting(),
        skills              = ProgressionService.GetSkills(citizenId),
        personalLoan        = DB_GetActiveLoan(citizenId),
        companyLoan         = company and DB_GetActiveCompanyLoan(company.id) or nil,
    }
end)
```

```lua
-- AFTER:
lib.callback.register('AUST_trucker:getInitialData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    local citizenId = Player.PlayerData.citizenid

    local company = CompanyService.GetByMember(citizenId)
    local repoOrders, activeRepoOrder
    if company and company.company_type == 'repo' then
        repoOrders      = DB_GetAvailableRepoOrders()
        activeRepoOrder = DB_GetActiveRepoOrder(citizenId)
    end

    return {
        jobs                = JobService.GetAvailable(),
        company             = company,
        activeJob           = JobService.GetActiveByPlayer(citizenId),
        stats               = DB_GetPlayerStats(citizenId),
        recruitingCompanies = CompanyService.GetRecruiting(),
        skills              = ProgressionService.GetSkills(citizenId),
        personalLoan        = DB_GetActiveLoan(citizenId),
        companyLoan         = company and DB_GetActiveCompanyLoan(company.id) or nil,
        repoOrders          = repoOrders,
        activeRepoOrder     = activeRepoOrder,
    }
end)
```

- [x] **Step 3: Append repo callbacks at end of server/callbacks.lua**

```lua
-- ============================================================
-- REPO MAN
-- ============================================================

lib.callback.register('AUST_trucker:getRepoOrders', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company or company.company_type ~= 'repo' then return {} end
    return DB_GetAvailableRepoOrders()
end)

lib.callback.register('AUST_trucker:acceptRepoOrder', function(source, orderId)
    return RepoService.Accept(source, tonumber(orderId) or 0)
end)
```

- [x] **Step 4: Commit**

```bash
git add server/events.lua server/callbacks.lua
git commit -m "feat(repo): add server events + callbacks for repo orders"
```

---

## Task 8: TypeScript types + useRepoStore

**Files:**
- Create: `html/src/types/repo.ts`
- Modify: `html/src/types/index.ts`
- Create: `html/src/stores/useRepoStore.ts`

- [x] **Step 1: Create html/src/types/repo.ts**

```ts
export type RepoMissionType  = 'simple' | 'npc_hostile' | 'pvp' | 'stealth'
export type RepoOrderStatus  = 'available' | 'active' | 'completed' | 'failed' | 'expired'

export interface RepoOrder {
  id:                      number
  vehicle_plate:           string
  vehicle_model:           string
  vehicle_value:           number
  vehicle_owner_citizenid: string | null  // null = NPC owner
  mission_type:            RepoMissionType
  location_zone:           string         // zone name; coords revealed in Sub-spec 2
  payment:                 number
  status:                  RepoOrderStatus
  expires_at_unix:         number         // unix timestamp
  created_at_unix:         number         // unix timestamp
}
```

- [x] **Step 2: Update html/src/types/index.ts — add company_type and missions tab**

Add `company_type` field to the `Company` interface and add `'missions'` to `TabName`:

```ts
// BEFORE:
export interface Company {
  id: string
  name: string
  balance: number
  is_recruiting: number
  owner_citizenid: string
  role: 'owner' | 'manager' | 'driver'
}

// ...

export type TabName = 'jobs' | 'active' | 'company' | 'garage' | 'industries' | 'stats'
```

```ts
// AFTER:
export interface Company {
  id: string
  name: string
  balance: number
  is_recruiting: number
  owner_citizenid: string
  role: 'owner' | 'manager' | 'driver'
  company_type: 'logistics' | 'repo'
}

// ...

export type TabName = 'jobs' | 'missions' | 'active' | 'company' | 'garage' | 'industries' | 'stats'
```

- [x] **Step 3: Create html/src/stores/useRepoStore.ts**

```ts
import { create } from 'zustand'
import type { RepoOrder } from '../types/repo'

interface RepoStore {
  repoOrders:         RepoOrder[]
  activeRepoOrder:    RepoOrder | null
  setRepoOrders:      (orders: RepoOrder[]) => void
  setActiveRepoOrder: (order: RepoOrder | null) => void
}

export const useRepoStore = create<RepoStore>((set) => ({
  repoOrders:         [],
  activeRepoOrder:    null,
  setRepoOrders:      (repoOrders)      => set({ repoOrders }),
  setActiveRepoOrder: (activeRepoOrder) => set({ activeRepoOrder }),
}))
```

- [x] **Step 4: Commit**

```bash
git add html/src/types/repo.ts html/src/types/index.ts html/src/stores/useRepoStore.ts
git commit -m "feat(ui): add RepoOrder types + useRepoStore"
```

---

## Task 9: useNUI.ts + client.lua — repo NUI integration

**Files:**
- Modify: `html/src/hooks/useNUI.ts`
- Modify: `client/client.lua` (append at end)

### 9a — useNUI.ts

- [x] **Step 1: Replace html/src/hooks/useNUI.ts**

```ts
import { useEffect } from 'react'
import { useAppStore } from '../stores/useAppStore'
import { useJobStore } from '../stores/useJobStore'
import { useCompanyStore } from '../stores/useCompanyStore'
import { useIndustryStore } from '../stores/useIndustryStore'
import { useStatsStore } from '../stores/useStatsStore'
import { useRepoStore } from '../stores/useRepoStore'
import type { Job, ActiveJob, Company, Member, Vehicle, Industry, Stats, Skills } from '../types'
import type { LoanData } from '../types/loan'
import type { RepoOrder } from '../types/repo'

interface NUIMessage {
  action:               string
  jobs?:                Job[]
  company?:             Company | null
  activeJob?:           ActiveJob | null
  stats?:               Stats | null
  skills?:              Partial<Skills>
  recruitingCompanies?: Company[]
  members?:             Member[]
  vehicles?:            Vehicle[]
  industries?:          Record<string, Industry>
  refreshStats?:        boolean
  // Loans
  loan?:                LoanData
  personalLoan?:        LoanData | null
  companyLoan?:         LoanData | null
  // Repo
  repoOrders?:          RepoOrder[]
  activeRepoOrder?:     RepoOrder | null
  repoOrder?:           RepoOrder
  payment?:             number
}

export function useNUI() {
  const { setOpen }                                                    = useAppStore()
  const { setJobs, setActiveJob }                                      = useJobStore()
  const { setCompany, setRecruitingList, setMembers, setVehicles, setCompanyLoan } = useCompanyStore()
  const { setIndustries }                                              = useIndustryStore()
  const { setStats, setSkills, setPersonalLoan }                       = useStatsStore()
  const { setRepoOrders, setActiveRepoOrder }                          = useRepoStore()

  useEffect(() => {
    const handler = (event: MessageEvent<NUIMessage>) => {
      const { action } = event.data
      switch (action) {
        case 'open':
          setJobs(event.data.jobs ?? [])
          setCompany(event.data.company ?? null)
          setActiveJob(event.data.activeJob ?? null)
          setStats(event.data.stats ?? null)
          setRecruitingList(event.data.recruitingCompanies ?? [])
          if (event.data.skills) setSkills(event.data.skills)
          setPersonalLoan(event.data.personalLoan ?? null)
          setCompanyLoan(event.data.companyLoan ?? null)
          setRepoOrders(event.data.repoOrders ?? [])
          setActiveRepoOrder(event.data.activeRepoOrder ?? null)
          setOpen(true)
          break
        case 'close':
          setOpen(false)
          break
        case 'updateJobs':
          setJobs(event.data.jobs ?? [])
          break
        case 'updateActiveJob':
          setActiveJob(event.data.activeJob ?? null)
          break
        case 'updateCompany':
          setCompany(event.data.company ?? null)
          break
        case 'updateMembers':
          setMembers(event.data.members ?? [])
          break
        case 'updateVehicles':
          setVehicles(event.data.vehicles ?? [])
          break
        case 'updateStats':
          setStats(event.data.stats ?? null)
          break
        case 'updateSkills':
          if (event.data.skills) setSkills(event.data.skills)
          break
        case 'updateIndustries':
          setIndustries(event.data.industries ?? {})
          break
        case 'updateLoan': {
          const loan = event.data.loan
          if (!loan) break
          if (loan.is_company_loan) {
            setCompanyLoan(loan)
          } else {
            setPersonalLoan(loan)
          }
          break
        }
        case 'updateRepoOrders':
          setRepoOrders(event.data.repoOrders ?? [])
          break
        case 'startRepoMission':
          setActiveRepoOrder(event.data.repoOrder ?? null)
          break
        case 'repoMissionComplete':
          setActiveRepoOrder(null)
          break
      }
    }
    window.addEventListener('message', handler)
    return () => window.removeEventListener('message', handler)
  }, [])
}

// Utilitário: chama endpoint Lua via NUI fetch
export async function fetchNUI<T = unknown>(
  endpoint: string,
  data?: unknown
): Promise<T> {
  const response = await fetch(`https://AUST_trucker/${endpoint}`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(data ?? {}),
  })
  return response.json() as Promise<T>
}
```

### 9b — client.lua

- [x] **Step 2: Append repo NUI callbacks + client events at end of client/client.lua**

```lua
-- ============================================================
-- REPO MAN — NUI BRIDGE
-- ============================================================

RegisterNUICallback('acceptRepoOrder', function(data, cb)
    local result = lib.callback.await('AUST_trucker:acceptRepoOrder', false, data.orderId)
    cb(result or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('failRepoOrder', function(data, cb)
    -- Fire-and-forget: server processes Fail + broadcasts async
    TriggerServerEvent('AUST_trucker:failRepoOrder', data.orderId)
    cb({ success = true })
end)

-- ============================================================
-- REPO MAN — CLIENT EVENTS
-- ============================================================

RegisterNetEvent('AUST_trucker:client:updateRepoOrders', function(orders)
    SendNUIMessage({ action = 'updateRepoOrders', repoOrders = orders })
end)

RegisterNetEvent('AUST_trucker:client:startRepoMission', function(order)
    SendNUIMessage({ action = 'startRepoMission', repoOrder = order })
end)

RegisterNetEvent('AUST_trucker:client:repoMissionComplete', function(result)
    SendNUIMessage({ action = 'repoMissionComplete', payment = result and result.payment })
end)
```

- [x] **Step 3: Commit**

```bash
git add html/src/hooks/useNUI.ts client/client.lua
git commit -m "feat(ui): add repo cases to useNUI + client event handlers"
```

---

## Task 10: RepoCard + RepoPanel components

**Files:**
- Create: `html/src/components/repo/RepoCard.tsx`
- Create: `html/src/components/repo/RepoPanel.tsx`

- [x] **Step 1: Create html/src/components/repo/RepoCard.tsx**

```tsx
import type { RepoOrder, RepoMissionType } from '../../types/repo'
import { fetchNUI } from '../../hooks/useNUI'

interface RepoCardProps {
  order: RepoOrder
}

const MISSION_BADGE: Record<RepoMissionType, { label: string; className: string }> = {
  simple:      { label: 'SIMPLES',  className: 'bg-zinc-700 text-zinc-300' },
  npc_hostile: { label: 'HOSTIL',   className: 'bg-orange-900/40 text-orange-400' },
  pvp:         { label: 'PVP',      className: 'bg-red-900/40 text-red-400' },
  stealth:     { label: 'STEALTH',  className: 'bg-purple-900/40 text-purple-400' },
}

function formatCountdown(unixTs: number): string {
  const diff = unixTs - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'EXPIRADO'
  const hours = Math.floor(diff / 3600)
  const mins  = Math.floor((diff % 3600) / 60)
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export function RepoCard({ order }: RepoCardProps) {
  const badge = MISSION_BADGE[order.mission_type]

  async function handleAccept() {
    await fetchNUI('acceptRepoOrder', { orderId: order.id })
  }

  return (
    <div className="bg-zinc-800/60 border border-zinc-700/50 rounded-lg p-3">
      <div className="flex items-center justify-between mb-2">
        <span className={`text-xs px-2 py-0.5 rounded font-medium ${badge.className}`}>
          {badge.label}
        </span>
        <span className="text-xs text-zinc-500">{formatCountdown(order.expires_at_unix)}</span>
      </div>

      <div className="grid grid-cols-3 gap-2 text-center mb-3">
        <div>
          <p className="text-sm font-bold text-zinc-100 uppercase">{order.vehicle_model}</p>
          <p className="text-[10px] text-zinc-500">Veículo</p>
        </div>
        <div>
          <p className="text-sm font-bold text-zinc-300">{order.location_zone}</p>
          <p className="text-[10px] text-zinc-500">Zona</p>
        </div>
        <div>
          <p className="text-sm font-bold text-green-400">${order.payment.toLocaleString()}</p>
          <p className="text-[10px] text-zinc-500">Pagamento</p>
        </div>
      </div>

      <button
        onClick={handleAccept}
        className="w-full py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded text-sm font-medium transition-colors"
      >
        Aceitar Missão
      </button>
    </div>
  )
}
```

- [x] **Step 2: Create html/src/components/repo/RepoPanel.tsx**

```tsx
import { useRepoStore } from '../../stores/useRepoStore'
import { fetchNUI } from '../../hooks/useNUI'
import { RepoCard } from './RepoCard'
import type { RepoMissionType } from '../../types/repo'

const MISSION_LABEL: Record<RepoMissionType, string> = {
  simple:      'Simples',
  npc_hostile: 'Hostil',
  pvp:         'PVP',
  stealth:     'Stealth',
}

function formatCountdown(unixTs: number): string {
  const diff = unixTs - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'EXPIRADO'
  const hours = Math.floor(diff / 3600)
  const mins  = Math.floor((diff % 3600) / 60)
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export function RepoPanel() {
  const { repoOrders, activeRepoOrder, setActiveRepoOrder } = useRepoStore()

  async function handleAbandon() {
    if (!activeRepoOrder) return
    await fetchNUI('failRepoOrder', { orderId: activeRepoOrder.id })
    setActiveRepoOrder(null)
  }

  return (
    <div className="space-y-4">
      {/* Active mission */}
      {activeRepoOrder && (
        <div className="bg-blue-900/20 border border-blue-500/30 rounded-lg p-3">
          <p className="text-xs text-blue-400 uppercase tracking-wider font-medium mb-2">Missão Ativa</p>
          <div className="grid grid-cols-3 gap-2 text-center mb-3">
            <div>
              <p className="text-sm font-bold text-zinc-100 uppercase">{activeRepoOrder.vehicle_model}</p>
              <p className="text-[10px] text-zinc-500">Veículo</p>
            </div>
            <div>
              <p className="text-sm font-bold text-zinc-300">{MISSION_LABEL[activeRepoOrder.mission_type]}</p>
              <p className="text-[10px] text-zinc-500">Tipo</p>
            </div>
            <div>
              <p className="text-sm font-bold text-green-400">${activeRepoOrder.payment.toLocaleString()}</p>
              <p className="text-[10px] text-zinc-500">Recompensa</p>
            </div>
          </div>
          <p className="text-xs text-zinc-400 mb-3 text-center">
            Vá ao local e recolha o veículo — entregue no depósito (Sub-spec 2)
          </p>
          <p className="text-xs text-zinc-500 text-center mb-2">
            Expira em {formatCountdown(activeRepoOrder.expires_at_unix)}
          </p>
          <button
            onClick={handleAbandon}
            className="w-full py-1.5 bg-zinc-700 hover:bg-red-900/40 text-zinc-300 hover:text-red-400 border border-zinc-600 hover:border-red-500/30 rounded text-sm transition-colors"
          >
            Abandonar Missão
          </button>
        </div>
      )}

      {/* Available orders */}
      <div>
        <p className="text-xs text-zinc-500 uppercase tracking-wider mb-2">
          Ordens Disponíveis ({repoOrders.length})
        </p>
        {repoOrders.length === 0 ? (
          <div className="bg-zinc-800/30 border border-zinc-700/30 rounded-lg p-4 text-center">
            <p className="text-xs text-zinc-500">Nenhuma ordem disponível no momento</p>
            <p className="text-[10px] text-zinc-600 mt-0.5">Novas ordens são geradas automaticamente</p>
          </div>
        ) : (
          <div className="space-y-2">
            {repoOrders.map(order => (
              <RepoCard key={order.id} order={order} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
```

- [x] **Step 3: Commit**

```bash
git add html/src/components/repo/
git commit -m "feat(ui): add RepoCard + RepoPanel components"
```

---

## Task 11: App + TabBar + CompanySetup — routing

**Files:**
- Modify: `html/src/App.tsx`
- Modify: `html/src/components/layout/TabBar.tsx`
- Modify: `html/src/components/company/CompanySetup.tsx`

### 11a — App.tsx

- [x] **Step 1: Add RepoPanel import and missions tab routing**

```tsx
// BEFORE:
import { useNUI } from './hooks/useNUI'
import { useAppStore } from './stores/useAppStore'
import { useCompanyStore } from './stores/useCompanyStore'
import { TabBar } from './components/layout/TabBar'
import { JobList } from './components/jobs/JobList'
import { ActiveJob } from './components/jobs/ActiveJob'
import { CompanySetup } from './components/company/CompanySetup'
import { CompanyPanel } from './components/company/CompanyPanel'
import { GaragePanel } from './components/garage/GaragePanel'
import { IndustryList } from './components/industries/IndustryList'
import { StatsPanel } from './components/stats/StatsPanel'

export default function App() {
  useNUI()

  const { isOpen, activeTab } = useAppStore()
  const { company } = useCompanyStore()

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
      <div className="pointer-events-auto w-[700px] h-[520px] bg-zinc-900 rounded-xl border border-zinc-700 shadow-2xl flex flex-col overflow-hidden">
        <TabBar />
        <div className="flex-1 overflow-auto p-4">
          {activeTab === 'jobs'       && <JobList />}
          {activeTab === 'active'     && <ActiveJob />}
          {activeTab === 'company'    && (company ? <CompanyPanel /> : <CompanySetup />)}
          {activeTab === 'garage'     && <GaragePanel />}
          {activeTab === 'industries' && <IndustryList />}
          {activeTab === 'stats'      && <StatsPanel />}
        </div>
      </div>
    </div>
  )
}
```

```tsx
// AFTER:
import { useNUI } from './hooks/useNUI'
import { useAppStore } from './stores/useAppStore'
import { useCompanyStore } from './stores/useCompanyStore'
import { TabBar } from './components/layout/TabBar'
import { JobList } from './components/jobs/JobList'
import { ActiveJob } from './components/jobs/ActiveJob'
import { CompanySetup } from './components/company/CompanySetup'
import { CompanyPanel } from './components/company/CompanyPanel'
import { GaragePanel } from './components/garage/GaragePanel'
import { IndustryList } from './components/industries/IndustryList'
import { StatsPanel } from './components/stats/StatsPanel'
import { RepoPanel } from './components/repo/RepoPanel'

export default function App() {
  useNUI()

  const { isOpen, activeTab } = useAppStore()
  const { company } = useCompanyStore()

  if (!isOpen) return null

  return (
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
        </div>
      </div>
    </div>
  )
}
```

### 11b — TabBar.tsx

- [x] **Step 2: Update TabBar to show Jobs vs Missões based on company_type**

```tsx
// BEFORE:
import { useAppStore } from '../../stores/useAppStore'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import type { TabName } from '../../types'
import clsx from 'clsx'

const TABS: { id: TabName; label: string }[] = [
  { id: 'jobs',       label: 'Jobs' },
  { id: 'active',     label: 'Entrega' },
  { id: 'company',    label: 'Empresa' },
  { id: 'garage',     label: 'Garagem' },
  { id: 'industries', label: 'Indústrias' },
  { id: 'stats',      label: 'Stats' },
]

export function TabBar() {
  const { activeTab, setTab } = useAppStore()
  const { activeJob } = useJobStore()
  const { company } = useCompanyStore()

  return (
    <div className="flex border-b border-zinc-700 bg-zinc-900">
      {TABS.map((tab) => {
        const disabled = (tab.id === 'active' && !activeJob)
          || (tab.id === 'garage' && !company)
        return (
          <button
            key={tab.id}
            onClick={() => !disabled && setTab(tab.id)}
            disabled={disabled}
            className={clsx(
              'px-4 py-3 text-sm font-medium transition-colors',
              activeTab === tab.id
                ? 'text-blue-400 border-b-2 border-blue-400'
                : 'text-zinc-400 hover:text-zinc-100',
              disabled && 'opacity-30 cursor-not-allowed'
            )}
          >
            {tab.label}
            {tab.id === 'active' && activeJob && (
              <span className="ml-1 w-2 h-2 bg-green-500 rounded-full inline-block" />
            )}
          </button>
        )
      })}
    </div>
  )
}
```

```tsx
// AFTER:
import { useAppStore } from '../../stores/useAppStore'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { useRepoStore } from '../../stores/useRepoStore'
import type { TabName } from '../../types'
import clsx from 'clsx'

export function TabBar() {
  const { activeTab, setTab } = useAppStore()
  const { activeJob }        = useJobStore()
  const { company }          = useCompanyStore()
  const { activeRepoOrder }  = useRepoStore()

  const isRepo = company?.company_type === 'repo'

  const TABS: { id: TabName; label: string }[] = [
    { id: isRepo ? 'missions' : 'jobs', label: isRepo ? 'Missões' : 'Jobs' },
    { id: 'active',     label: 'Entrega' },
    { id: 'company',    label: 'Empresa' },
    { id: 'garage',     label: 'Garagem' },
    { id: 'industries', label: 'Indústrias' },
    { id: 'stats',      label: 'Stats' },
  ]

  return (
    <div className="flex border-b border-zinc-700 bg-zinc-900">
      {TABS.map((tab) => {
        const disabled = (tab.id === 'active' && !activeJob)
          || (tab.id === 'garage' && !company)
        return (
          <button
            key={tab.id}
            onClick={() => !disabled && setTab(tab.id)}
            disabled={disabled}
            className={clsx(
              'px-4 py-3 text-sm font-medium transition-colors',
              activeTab === tab.id
                ? 'text-blue-400 border-b-2 border-blue-400'
                : 'text-zinc-400 hover:text-zinc-100',
              disabled && 'opacity-30 cursor-not-allowed'
            )}
          >
            {tab.label}
            {tab.id === 'active' && activeJob && (
              <span className="ml-1 w-2 h-2 bg-green-500 rounded-full inline-block" />
            )}
            {tab.id === 'missions' && activeRepoOrder && (
              <span className="ml-1 w-2 h-2 bg-blue-500 rounded-full inline-block" />
            )}
          </button>
        )
      })}
    </div>
  )
}
```

### 11c — CompanySetup.tsx

- [x] **Step 3: Add company type selection to CompanySetup.tsx**

```tsx
// BEFORE:
import { useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

export function CompanySetup() {
  const { recruitingList } = useCompanyStore()
  const [name, setName] = useState('')
  const [creating, setCreating] = useState(false)

  async function handleCreate() {
    if (!name.trim()) return
    setCreating(true)
    await fetchNUI('createCompany', { name: name.trim() })
    setCreating(false)
  }

  return (
    <div className="space-y-6">
      {/* Criar empresa */}
      <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 className="text-zinc-100 font-semibold mb-3">Criar Empresa</h3>
        <p className="text-zinc-400 text-sm mb-3">Custo: <span className="text-green-400 font-medium">$150.000</span></p>
        <input
          type="text"
          placeholder="Nome da empresa"
          value={name}
          onChange={e => setName(e.target.value)}
          maxLength={50}
          className="w-full bg-zinc-900 border border-zinc-700 rounded-lg px-3 py-2 text-zinc-100 text-sm placeholder-zinc-500 focus:outline-none focus:border-blue-500 mb-3"
        />
        <button
          onClick={handleCreate}
          disabled={!name.trim() || creating}
          className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white rounded-lg font-medium transition-colors text-sm"
        >
          {creating ? 'Criando...' : 'Criar Empresa ($150k)'}
        </button>
      </div>
      ...
    </div>
  )
}
```

```tsx
// AFTER (replace the full component):
import { useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

type CompanyType = 'logistics' | 'repo'

const TYPE_OPTIONS: { value: CompanyType; label: string; desc: string }[] = [
  { value: 'logistics', label: 'Logística', desc: 'Aceita jobs de entrega de carga' },
  { value: 'repo',      label: 'Repo Man',  desc: 'Aceita missões de repossessão' },
]

export function CompanySetup() {
  const { recruitingList } = useCompanyStore()
  const [name, setName]             = useState('')
  const [companyType, setCompanyType] = useState<CompanyType>('logistics')
  const [creating, setCreating]     = useState(false)

  async function handleCreate() {
    if (!name.trim()) return
    setCreating(true)
    await fetchNUI('createCompany', { name: name.trim(), companyType })
    setCreating(false)
  }

  return (
    <div className="space-y-6">
      {/* Criar empresa */}
      <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 className="text-zinc-100 font-semibold mb-3">Criar Empresa</h3>
        <p className="text-zinc-400 text-sm mb-3">Custo: <span className="text-green-400 font-medium">$150.000</span></p>

        <input
          type="text"
          placeholder="Nome da empresa"
          value={name}
          onChange={e => setName(e.target.value)}
          maxLength={50}
          className="w-full bg-zinc-900 border border-zinc-700 rounded-lg px-3 py-2 text-zinc-100 text-sm placeholder-zinc-500 focus:outline-none focus:border-blue-500 mb-3"
        />

        <p className="text-xs text-zinc-500 uppercase tracking-wider mb-2">Tipo de Empresa</p>
        <div className="grid grid-cols-2 gap-2 mb-3">
          {TYPE_OPTIONS.map(opt => (
            <button
              key={opt.value}
              onClick={() => setCompanyType(opt.value)}
              className={`p-2 rounded-lg border text-left transition-colors ${
                companyType === opt.value
                  ? 'border-blue-500 bg-blue-600/10 text-blue-300'
                  : 'border-zinc-700 bg-zinc-900 text-zinc-400 hover:border-zinc-500'
              }`}
            >
              <p className="text-sm font-medium">{opt.label}</p>
              <p className="text-[10px] mt-0.5 opacity-70">{opt.desc}</p>
            </button>
          ))}
        </div>

        <button
          onClick={handleCreate}
          disabled={!name.trim() || creating}
          className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white rounded-lg font-medium transition-colors text-sm"
        >
          {creating ? 'Criando...' : 'Criar Empresa ($150k)'}
        </button>
      </div>

      {/* Entrar em empresa */}
      {recruitingList.length > 0 && (
        <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
          <h3 className="text-zinc-100 font-semibold mb-3">Empresas Recrutando</h3>
          <div className="space-y-2">
            {recruitingList.map(company => (
              <div key={company.id} className="flex justify-between items-center bg-zinc-900 rounded p-2">
                <div>
                  <p className="text-zinc-100 text-sm">{company.name}</p>
                  <p className="text-zinc-500 text-[10px]">{company.company_type === 'repo' ? 'Repo Man' : 'Logística'}</p>
                </div>
                <button
                  onClick={() => fetchNUI('joinCompany', { companyId: company.id })}
                  className="text-blue-400 hover:text-blue-300 text-xs border border-blue-500/30 px-2 py-1 rounded transition-colors"
                >
                  Entrar
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
```

- [x] **Step 4: Commit**

```bash
git add html/src/App.tsx html/src/components/layout/TabBar.tsx html/src/components/company/CompanySetup.tsx
git commit -m "feat(ui): add repo routing in App + TabBar + CompanySetup type selection"
```

---

## Task 12: Frontend build

**Files:**
- `html/` — build output

- [x] **Step 1: Install deps if needed and build**

```bash
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker\html"
npm install
npm run build
```

Expected output: `✓ built in Xms` with no TypeScript errors. Built files land in `html/assets/`.

- [x] **Step 2: Verify build output**

```bash
ls html/assets/
```

Should show `.js` and `.css` files with hashed names.

- [x] **Step 3: Commit**

```bash
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker"
git add html/assets/
git commit -m "build: compile frontend for Repo Man NUI (Sub-spec 1)"
```

---

## Manual Test Checklist (in-game)

After restarting the resource (`restart AUST_trucker`):

- [x] Server starts without Lua errors in txAdmin console
- [x] `DB_CountAvailableNpcOrders()` thread fills pool — check `trucker_repo_orders` table shows NPC orders (vehicle_owner_citizenid IS NULL)
- [x] Create a `logistics` company → aba "Jobs" still appears
- [x] Create a `repo` company → aba "Missões" appears instead of "Jobs"
- [x] Repo company member opens NUI → sees available orders list
- [x] Accept an order → order disappears from list; active mission panel appears; other agents get list refresh
- [x] Try to accept second order → blocked with "Você já tem uma missão ativa"
- [x] Logistics company member tries to accept → blocked with "Apenas membros de empresa Repo Man"
- [x] Abandon mission → order returns to available; other agents see it reappear
- [x] Simulate loan default: `UPDATE trucker_loans SET next_payment_at = DATE_SUB(NOW(), INTERVAL 1 HOUR) WHERE status = 'active' LIMIT 1;` → wait CheckInterval (5 min) → new repo order appears with vehicle_owner_citizenid set
- [x] Confirm `loan_id` is set in the generated repo order and `INSERT IGNORE` prevents duplicates on next cycle
- [x] NPC order expires after 2h (or set `expires_at = NOW() - INTERVAL 1 SECOND` and restart) → order becomes 'expired', new NPC order fills pool
