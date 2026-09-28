# Fase 2 — Economia: Fail-safe NPC + Geração por Demanda + Propriedade de Indústrias

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar a Fase 2 do blueprint: indústrias do sistema de trading passam a ter proprietários (comprado por empresa, lucro por venda, custo operacional), jobs de logistics passam a ser gerados com peso por demanda real, e um NPC fail-safe previne que indústrias de trading travem sem insumos.

**Architecture:** Três sistemas independentes que se integram no `IndustryService` existente. `IndustryOwnershipService` é um novo service global. O hook de profit se encaixa em `IndustryService.BuyFrom`. O fail-safe roda numa thread a cada 5 min dentro de `industry_service.lua`. A geração ponderada substitui a seleção aleatória em `job_service.lua`.

**Tech Stack:** Lua 5.4, oxmysql (MySQL.query.await), QBX (exports.qbx_core:GetPlayer), React 18 + TypeScript (NUI), Zustand store, lua54 chunk isolation (globais cruzam arquivos, `local` não).

---

## Contexto crítico para subagentes

- **Dois sistemas de indústria distintos:**
  - `Config.Industries` (trading): com banco de dados (`trucker_industry_state`), suporta ownership, compra/venda de itens ox_inventory via `IndustryService.BuyFrom/SellTo`
  - `Config.PrimaryIndustries` / `Config.SecondaryIndustries` (logistics): sem banco, são origens e destinos dos jobs de entrega de caminhão
- **Propriedade** se aplica a `Config.Industries`, **geração ponderada** se aplica ao sistema de logistics
- **lua54**: cada `server_scripts` é chunk separado — `local` vars de um arquivo não existem em outro; globais sim
- **Ordem no fxmanifest** (server): `main.lua` → `database.lua` → `company_service.lua` → `loan_service.lua` → `repo_service.lua` → `economy_service.lua` → `industry_service.lua` → `progression_service.lua` → `job_service.lua` → `truck_simulation_service.lua` → `exports.lua` → `callbacks.lua` → `events.lua`
- **`IndustryOwnershipService`** deve ser inserido APÓS `economy_service.lua` e ANTES de `industry_service.lua` (industry_service chama métodos de ownership)
- **VP_Trucker** é o global de estado em `server/main.lua` — adicionar `VP_Trucker.IndustryOwners = {}`
- **Tipo de empresa**: apenas empresas do tipo `'logistics'` podem comprar indústrias. Role mínimo: `'owner'` ou `'manager'`.

---

## Arquivo de referência — schema existente

```sql
-- trucker_industry_ownership (já existe no import.sql)
CREATE TABLE trucker_industry_ownership (
    industry_id         VARCHAR(50)     PRIMARY KEY,
    owner_citizenid     VARCHAR(50)     NOT NULL,  -- buyer (obrigatório pelo schema)
    company_id          VARCHAR(50)     NULL,       -- empresa dona (nullable para futuro)
    purchase_price      BIGINT          NOT NULL,
    production_level    TINYINT         DEFAULT 1,
    npc_workers         TINYINT         DEFAULT 0,
    balance             BIGINT          DEFAULT 0,
    purchased_at        DATETIME        DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- trucker_industry_state (já existe)
-- Precisa de: last_npc_fill_at DATETIME NULL

-- trucker_jobs (já existe)
-- Precisa de: 'npc_completed' no ENUM de status
```

---

## Mapa de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `config/config.lua` | Modificar | Adicionar `Config.IndustryOwnership`, `Config.Economy.NpcFailsafeDelay/Amount`, `Config.JobGeneration.DemandWeighting` |
| `sql/update_economy_v8.sql` | Criar | Migrações seguras para servidores existentes |
| `import.sql` | Modificar | Adicionar colunas novas ao schema fresh |
| `server/main.lua` | Modificar | `VP_Trucker.IndustryOwners = {}` + `LoadIndustryOwners()` |
| `server/database.lua` | Modificar | 6 funções DB_ para ownership + 2 para fail-safe |
| `server/services/industry_ownership_service.lua` | Criar | `IndustryOwnershipService` global |
| `server/services/industry_service.lua` | Modificar | Hook de profit em `BuyFrom`, fail-safe thread, `RunNpcFailsafe()` |
| `server/services/job_service.lua` | Modificar | `GenerateOne()` com peso por demanda |
| `server/callbacks.lua` | Modificar | `getIndustryOwnership`, `buyIndustry` |
| `server/events.lua` | Modificar | Nenhum novo evento necessário (ownership usa callback) |
| `fxmanifest.lua` | Modificar | Inserir `industry_ownership_service.lua`, bump versão 8.0.0 |
| `html/src/types/index.ts` | Modificar | `IndustryOwnership` interface + `ownedBy` em `Industry` |
| `html/src/hooks/useNUI.ts` | Modificar | Handler `updateIndustryOwnership` |
| `html/src/stores/useIndustryStore.ts` | Criar | Zustand store para ownership |
| `html/src/components/industries/IndustriesPanel.tsx` | Modificar | Badge de dono + botão "Comprar" |
| `CHANGELOG.md` | Modificar | Entrada `[8.0.0]` |

---

## Task 1: Config + SQL

**Files:**
- Modify: `config/config.lua` (no final, antes do bloco TruckSimulation)
- Create: `sql/update_economy_v8.sql`
- Modify: `import.sql`

- [ ] **Step 1: Adicionar Config.IndustryOwnership e parâmetros de economia**

Abrir `config/config.lua`. Localizar `Config.Economy = {` e adicionar dois campos dentro:

```lua
Config.Economy = {
    priceUpdateInterval          = 1200000,
    primaryProductionInterval    = 60000,
    secondaryProductionInterval  = 600000,
    priceFloor   = 0.5,
    priceCeiling = 2.0,
    priceAdjustmentSpeed = 0.15,
    -- NPC fail-safe (novo):
    NpcFailsafeDelay  = 1800,   -- segundos sem insumos antes de NPC abastecer (30min)
    NpcFailsafeAmount = 10,     -- unidades que o NPC entrega por ativação
}
```

Depois, em `Config.JobGeneration = {`, adicionar no final:

```lua
Config.JobGeneration = {
    maxActiveJobs = 8,
    refreshInterval = 1800000,
    jobExpiration = { minTime = 600, maxTime = 2400, basePayment = 1000 },
    distanceMultiplier = 0.05,
    timeBonus = {
        fast   = { time = 300, multiplier = 1.2 },
        normal = { time = 600, multiplier = 1.0 },
        slow   = { time = 900, multiplier = 0.8 },
    },
    DemandWeighting = true,  -- pesa geração de jobs por demanda real (novo)
}
```

Depois de `Config.FleetUpgrades`, adicionar:

```lua
-- ================================================
-- PROPRIEDADE DE INDÚSTRIAS
-- ================================================
Config.IndustryOwnership = {
    PurchasePriceMultiplier = 10,    -- preço = basePrice * productionPerHour * mult
    OperationalCostPerCycle = 500,   -- deducted da empresa por ciclo de produção (server)
    OwnerProfitPercent      = 0.15,  -- 15% de cada venda vai para a empresa dona
    MaxOwnedPerCompany      = 3,     -- máximo de indústrias por empresa
}
```

- [ ] **Step 2: Criar sql/update_economy_v8.sql**

```sql
-- AUST_trucker — migração v7.x → v8.0.0
-- Execute APENAS se já tiver o banco instalado.
-- Servidores novos usam o import.sql atualizado.

-- 1. Adicionar last_npc_fill_at à tabela de estado de indústrias
ALTER TABLE trucker_industry_state
    ADD COLUMN IF NOT EXISTS last_npc_fill_at DATETIME NULL DEFAULT NULL;

-- 2. Adicionar 'npc_completed' ao enum de status dos jobs
ALTER TABLE trucker_jobs
    MODIFY COLUMN status
        ENUM('available','active','completed','expired','npc_completed')
        DEFAULT 'available';

-- 3. Adicionar total_earned à tabela de ownership (não existia no import original)
ALTER TABLE trucker_industry_ownership
    ADD COLUMN IF NOT EXISTS total_earned BIGINT DEFAULT 0;
```

- [ ] **Step 3: Atualizar import.sql para fresh installs**

Em `import.sql`, no `CREATE TABLE trucker_industry_state`, adicionar antes de `PRIMARY KEY`:
```sql
    last_npc_fill_at    DATETIME        NULL DEFAULT NULL,
```

No `CREATE TABLE trucker_jobs`, modificar o campo status:
```sql
    status  ENUM('available','active','completed','expired','npc_completed') DEFAULT 'available',
```

No `CREATE TABLE trucker_industry_ownership`, adicionar antes de `purchased_at`:
```sql
    total_earned        BIGINT          DEFAULT 0,
```

- [ ] **Step 4: Commit**

```bash
git add config/config.lua sql/update_economy_v8.sql import.sql
git commit -m "feat(economy): Config.IndustryOwnership + NPC fail-safe config + demand weighting toggle"
```

---

## Task 2: DB Functions — Ownership + Fail-safe

**Files:**
- Modify: `server/database.lua` (append ao final)

- [ ] **Step 1: Adicionar funções de ownership ao final de database.lua**

```lua
-- ============================================================
-- INDUSTRY OWNERSHIP
-- ============================================================

-- Retorna o ownership de uma indústria (ou nil se não tem dono)
function DB_GetIndustryOwner(industryId)
    return MySQL.single.await(
        'SELECT * FROM trucker_industry_ownership WHERE industry_id = ? LIMIT 1',
        { industryId }
    )
end

-- Insere ownership de uma nova compra.
-- USA INSERT ... ON DUPLICATE KEY UPDATE para NÃO zerar production_level/npc_workers/total_earned
-- em caso de reutilização futura. REPLACE INTO é perigoso pois reseta todos os campos ao default.
function DB_SetIndustryOwner(industryId, ownerCitizenId, companyId, purchasePrice)
    MySQL.insert.await(
        [[INSERT INTO trucker_industry_ownership
            (industry_id, owner_citizenid, company_id, purchase_price)
          VALUES (?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            owner_citizenid = VALUES(owner_citizenid),
            company_id      = VALUES(company_id),
            purchase_price  = VALUES(purchase_price)]],
        { industryId, ownerCitizenId, companyId, purchasePrice }
    )
end

-- Remove ownership (venda/abandono)
function DB_ClearIndustryOwner(industryId)
    MySQL.query.await(
        'DELETE FROM trucker_industry_ownership WHERE industry_id = ?',
        { industryId }
    )
end

-- Soma ao total_earned da indústria
function DB_AddOwnerEarnings(industryId, amount)
    MySQL.update.await(
        'UPDATE trucker_industry_ownership SET total_earned = total_earned + ? WHERE industry_id = ?',
        { amount, industryId }
    )
end

-- Retorna todas as indústrias de uma empresa
function DB_GetOwnedByCompany(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_industry_ownership WHERE company_id = ?',
        { companyId }
    )
end

-- Retorna todas as ownerships (para cache no init)
function DB_GetAllIndustryOwners()
    return MySQL.query.await('SELECT * FROM trucker_industry_ownership')
end

-- ============================================================
-- NPC FAIL-SAFE
-- ============================================================

-- Retorna itens de consumo com stock = 0 e last_npc_fill_at expirado (ou NULL)
-- threshold = segundos mínimos desde o último fill para poder refill
-- NOTA: MySQL não aceita ? como quantidade em INTERVAL. Usar TIMESTAMPADD(SECOND, -?, NOW()).
function DB_GetStarvedConsumptionItems(thresholdSeconds)
    return MySQL.query.await(
        [[SELECT industry_id, item, current_stock, last_npc_fill_at
          FROM trucker_industry_state
          WHERE entry_type = 'consumption'
            AND current_stock = 0
            AND (last_npc_fill_at IS NULL
                 OR last_npc_fill_at < TIMESTAMPADD(SECOND, -?, NOW()))]],
        { thresholdSeconds }
    )
end

-- Marca o momento do NPC fill para evitar spam de refill
function DB_SetNpcFillTime(industryId, item)
    MySQL.update.await(
        [[UPDATE trucker_industry_state
          SET last_npc_fill_at = NOW()
          WHERE industry_id = ? AND item = ? AND entry_type = 'consumption']],
        { industryId, item }
    )
end
```

- [ ] **Step 2: Commit**

```bash
git add server/database.lua
git commit -m "feat(economy): DB functions for industry ownership and NPC fail-safe"
```

---

## Task 3: IndustryOwnershipService

**Files:**
- Create: `server/services/industry_ownership_service.lua`
- Modify: `server/main.lua` (adicionar `VP_Trucker.IndustryOwners` e loader)

- [ ] **Step 1: Criar server/services/industry_ownership_service.lua**

```lua
-- AUST_trucker — server/services/industry_ownership_service.lua
-- Compra, lucro por venda e custo operacional de indústrias (Config.Industries)

IndustryOwnershipService = {}

-- ============================================================
-- HELPERS INTERNOS
-- ============================================================

local function GetCompanyOfPlayer(citizenId)
    local companyId = VP_Trucker.PlayerCompanies[citizenId]
    if not companyId then return nil end
    return VP_Trucker.Companies[companyId]
end

local function CountOwnedByCompany(companyId)
    local count = 0
    for _, owner in pairs(VP_Trucker.IndustryOwners) do
        if owner.company_id == companyId then count = count + 1 end
    end
    return count
end

-- ============================================================
-- INIT (chamado em main.lua após MySQL.ready)
-- ============================================================

function IndustryOwnershipService.LoadCache()
    local rows = DB_GetAllIndustryOwners() or {}
    for _, row in ipairs(rows) do
        VP_Trucker.IndustryOwners[row.industry_id] = row
    end
    if Config.Debug then
        print(('[AUST_trucker] IndustryOwnership: %d indústrias carregadas'):format(#rows))
    end
end

-- ============================================================
-- CONSULTA
-- ============================================================

function IndustryOwnershipService.GetOwner(industryId)
    return VP_Trucker.IndustryOwners[industryId]
end

-- Retorna lista de indústrias de uma empresa (enriquecidas com config)
function IndustryOwnershipService.GetCompanyOwned(companyId)
    local result = {}
    for industryId, owner in pairs(VP_Trucker.IndustryOwners) do
        if owner.company_id == companyId then
            local cfg = Config.Industries[industryId]
            table.insert(result, {
                industryId   = industryId,
                industryName = cfg and cfg.name or industryId,
                purchasePrice = owner.purchase_price,
                totalEarned   = owner.total_earned or 0,
                productionLevel = owner.production_level or 1,
                npcWorkers    = owner.npc_workers or 0,
            })
        end
    end
    return result
end

-- ============================================================
-- COMPRA
-- ============================================================

function IndustryOwnershipService.Buy(src, industryId)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end

    local citizenId = Player.PlayerData.citizenid
    local company = GetCompanyOfPlayer(citizenId)
    if not company then
        return { success = false, reason = 'Você não pertence a uma empresa' }
    end
    if company.company_type ~= 'logistics' then
        return { success = false, reason = 'Apenas empresas de logística podem comprar indústrias' }
    end

    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Apenas Owner ou Manager podem comprar indústrias' }
    end

    -- Verificar se já tem dono
    if VP_Trucker.IndustryOwners[industryId] then
        return { success = false, reason = 'Esta indústria já pertence a outra empresa' }
    end

    -- Verificar limite por empresa
    local maxOwned = Config.IndustryOwnership.MaxOwnedPerCompany
    if CountOwnedByCompany(company.id) >= maxOwned then
        return { success = false, reason = ('Limite de %d indústrias por empresa atingido'):format(maxOwned) }
    end

    -- Calcular preço
    local cfg = Config.Industries[industryId]
    if not cfg or not cfg.production then
        return { success = false, reason = 'Indústria inválida ou não possui produção' }
    end
    local mult   = Config.IndustryOwnership.PurchasePriceMultiplier
    local price  = math.floor(cfg.production.basePrice * cfg.production.productionPerHour * mult)

    -- Debitar da empresa
    local companyRow = DB_GetCompany(company.id)
    if not companyRow or companyRow.balance < price then
        return { success = false, reason = ('Saldo insuficiente. Necessário: $%d'):format(price) }
    end

    local newBalance = DB_UpdateCompanyBalance(company.id, -price)
    if VP_Trucker.Companies[company.id] then
        VP_Trucker.Companies[company.id].balance = newBalance
    end

    -- Registrar no DB e cache
    DB_SetIndustryOwner(industryId, citizenId, company.id, price)
    VP_Trucker.IndustryOwners[industryId] = {
        industry_id     = industryId,
        owner_citizenid = citizenId,
        company_id      = company.id,
        purchase_price  = price,
        production_level = 1,
        npc_workers     = 0,
        total_earned    = 0,
    }

    if Config.Debug then
        print(('[AUST_trucker] IndustryOwnership: %s comprou %s por $%d'):format(company.id, industryId, price))
    end

    return { success = true, industryId = industryId, price = price }
end

-- ============================================================
-- HOOK DE PROFIT (chamado por IndustryService.BuyFrom)
-- ============================================================

-- Chamado após um jogador comprar itens da indústria.
-- Se a indústria tiver dono, 15% (configurável) vai para a empresa dona.
function IndustryOwnershipService.OnSale(industryId, totalSalePrice)
    local owner = VP_Trucker.IndustryOwners[industryId]
    if not owner or not owner.company_id then return end

    local profit = math.floor(totalSalePrice * Config.IndustryOwnership.OwnerProfitPercent)
    if profit <= 0 then return end

    -- DB_UpdateCompanyBalance retorna o saldo novo — usar o retorno para manter cache preciso
    local newBalance = DB_UpdateCompanyBalance(owner.company_id, profit)
    if VP_Trucker.Companies[owner.company_id] then
        VP_Trucker.Companies[owner.company_id].balance = newBalance
    end

    DB_AddOwnerEarnings(industryId, profit)
    if VP_Trucker.IndustryOwners[industryId] then
        VP_Trucker.IndustryOwners[industryId].total_earned =
            (VP_Trucker.IndustryOwners[industryId].total_earned or 0) + profit
    end
end

-- ============================================================
-- CUSTO OPERACIONAL (chamado pelo cron em industry_service.lua)
-- ============================================================

-- Deduz custo operacional de todas as empresas donas por ciclo de produção.
-- Se a empresa não tiver saldo, simplesmente não deduz (sem penalidade no MVP).
function IndustryOwnershipService.RunOperationalCosts()
    local cost = Config.IndustryOwnership.OperationalCostPerCycle
    if cost <= 0 then return end

    for industryId, owner in pairs(VP_Trucker.IndustryOwners) do
        if owner.company_id then
            local company = VP_Trucker.Companies[owner.company_id]
            if company and company.balance >= cost then
                local newBalance = DB_UpdateCompanyBalance(owner.company_id, -cost)
                VP_Trucker.Companies[owner.company_id].balance = newBalance
            end
        end
    end
end
```

- [ ] **Step 2: Modificar server/main.lua — adicionar IndustryOwners**

Localizar a declaração `VP_Trucker = {` e adicionar o campo:
```lua
VP_Trucker = {
    Ready           = false,
    Companies       = {},
    PlayerCompanies = {},
    ActiveJobs      = {},
    PlayerJobs      = {},
    IndustryOwners  = {},   -- cache: industryId → ownership row (Fase 2)
}
```

Localizar onde `LoadCompanies()` é chamado dentro de `MySQL.ready(function()` e adicionar `IndustryOwnershipService.LoadCache()` DEPOIS (IndustryOwnershipService é carregado após main.lua):

```lua
MySQL.ready(function()
    LoadCompanies()
    CreateThread(function()
        while not JobService do Wait(100) end
        -- Aguardar IndustryOwnershipService (carregado após job_service no fxmanifest)
        while not IndustryOwnershipService do Wait(100) end
        IndustryOwnershipService.LoadCache()
        JobService.LoadFromDB()
        VP_Trucker.Ready = true
        if Config.Debug then print('[AUST_trucker] Server ready.') end
    end)
end)
```

- [ ] **Step 3: Commit**

```bash
git add server/services/industry_ownership_service.lua server/main.lua
git commit -m "feat(economy): IndustryOwnershipService — Buy, OnSale profit hook, RunOperationalCosts"
```

---

## Task 4: IndustryService — NPC Fail-safe + Ownership Hooks

**Files:**
- Modify: `server/services/industry_service.lua`

- [ ] **Step 1: Adicionar RunNpcFailsafe() ao IndustryService**

Logo após `IndustryService = {}` (linha 4), adicionar:

```lua
-- ============================================================
-- NPC FAIL-SAFE: abastece indústrias de consumo sem insumos
-- ============================================================

function IndustryService.RunNpcFailsafe()
    local cfg    = Config.Economy
    local delay  = cfg.NpcFailsafeDelay  or 1800
    local amount = cfg.NpcFailsafeAmount or 10

    local starved = DB_GetStarvedConsumptionItems(delay)
    for _, row in ipairs(starved) do
        -- Verificar se a indústria existe no config
        if Config.Industries[row.industry_id] then
            DB_UpdateIndustryStock(row.industry_id, row.item, 'consumption', amount)
            DB_SetNpcFillTime(row.industry_id, row.item)
            if Config.Debug then
                print(('[AUST_trucker] NPC fail-safe: +%d %s → %s'):format(
                    amount, row.item, row.industry_id))
            end
        end
    end
end
```

- [ ] **Step 2: Adicionar custo operacional ao ciclo de produção**

Em `IndustryService.RunProductionCycle(isPrimary)`, após o `DB_UpdateIndustryStock(...)`, adicionar:

```lua
-- Custo operacional por ciclo para indústrias com dono
IndustryOwnershipService.RunOperationalCosts()
```

NOTA: Esta chamada ocorre dentro do loop for de indústrias — queremos executar apenas uma vez por ciclo, não por indústria. Mover para fora do loop. A função `RunProductionCycle` deve ficar:

```lua
function IndustryService.RunProductionCycle(isPrimary)
    for industryId, industry in pairs(Config.Industries) do
        if industry.production ~= nil then
            local isPrimaryIndustry   = industry.type == 'primary'
            local isSecondaryIndustry = industry.type == 'secondary'

            if (isPrimary and isPrimaryIndustry) or (not isPrimary and isSecondaryIndustry) then
                local state = MySQL.single.await(
                    "SELECT * FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'production' LIMIT 1",
                    { industryId, industry.production.item }
                )
                if state then
                    local maxStock = industry.production.maxStock
                    if state.current_stock < maxStock then
                        DB_UpdateIndustryStock(industryId, industry.production.item, 'production', 1)
                    end
                end
            end
        end
    end
    -- Custo operacional deduzido uma vez por ciclo (apenas em ciclos primários para evitar dobrar)
    if isPrimary then
        IndustryOwnershipService.RunOperationalCosts()
    end
end
```

- [ ] **Step 3: Adicionar hook de profit em IndustryService.BuyFrom**

Em `IndustryService.BuyFrom`, após `EconomyService.RecordPurchase(...)`:

```lua
    EconomyService.RecordPurchase(industryId, item, qty)
    -- Lucro da venda vai para a empresa dona (se houver)
    IndustryOwnershipService.OnSale(industryId, totalPrice)
    return true, nil
```

- [ ] **Step 4: Adicionar thread de fail-safe no final de industry_service.lua**

Após as threads de produção existentes, adicionar:

```lua
-- Thread NPC fail-safe (a cada 5 minutos)
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(300000)  -- 5 minutos
        IndustryService.RunNpcFailsafe()
    end
end)
```

- [ ] **Step 5: Commit**

```bash
git add server/services/industry_service.lua
git commit -m "feat(economy): NPC fail-safe thread + ownership profit hook + operational cost per cycle"
```

---

## Task 5: JobService — Geração Ponderada por Demanda

**Files:**
- Modify: `server/services/job_service.lua`

O objetivo é substituir a seleção puramente aleatória de origem/destino por uma seleção ponderada: destinos com menos jobs pendentes têm maior chance de ser selecionados, impedindo concentração de jobs no mesmo destino.

- [ ] **Step 1: Adicionar helper de peso por demanda**

Logo após `local MAX_JOBS = ...` (linha 6), adicionar:

```lua
-- Retorna tabela { [destId] = pendingCount } para todos os destinos com jobs ativos/disponíveis
local function GetDestPendingCounts()
    local rows = MySQL.query.await(
        "SELECT dest_id, COUNT(*) as cnt FROM trucker_jobs WHERE status IN ('available','active') GROUP BY dest_id"
    )
    local counts = {}
    for _, row in ipairs(rows) do
        counts[row.dest_id] = row.cnt
    end
    return counts
end

-- Seleção ponderada: elementos com menos ocorrências têm maior peso.
-- Retorna nil se items estiver vazio — o chamador deve checar o retorno.
local function WeightedRandom(items, weightFn)
    if #items == 0 then return nil end  -- guarda para lista vazia
    local totalWeight = 0
    local weights = {}
    for i, item in ipairs(items) do
        local w = weightFn(item)
        weights[i] = w
        totalWeight = totalWeight + w
    end
    if totalWeight <= 0 then return items[math.random(#items)] end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for i, item in ipairs(items) do
        cumulative = cumulative + weights[i]
        if roll <= cumulative then return item end
    end
    return items[#items]
end
```

- [ ] **Step 2: Modificar GenerateOne() para usar peso**

Substituir a função `GenerateOne()` completa:

```lua
local function GenerateOne()
    local origins = Config.PrimaryIndustries
    local dests   = Config.SecondaryIndustries

    -- Mapa de produtos aceitos por destino (para filtragem rápida)
    local destByProduct = {}
    for _, dest in ipairs(dests) do
        for _, product in ipairs(dest.acceptedProducts or {}) do
            if not destByProduct[product] then destByProduct[product] = {} end
            table.insert(destByProduct[product], dest)
        end
    end

    -- Contagem de jobs pendentes por destino (para ponderação)
    local pendingByDest = {}
    if Config.JobGeneration.DemandWeighting then
        pendingByDest = GetDestPendingCounts()
    end

    -- Tentar até 20 combinações
    for _ = 1, 20 do
        local origin  = origins[math.random(#origins)]
        local product = PickProduct(origin)
        if not product then goto continue end

        local validDests = destByProduct[product.name]
        if not validDests or #validDests == 0 then goto continue end

        local dest
        if Config.JobGeneration.DemandWeighting then
            -- Peso inverso: destinos com menos jobs pendentes têm mais chance
            dest = WeightedRandom(validDests, function(d)
                local pending = pendingByDest[d.id] or 0
                return 1.0 / (1.0 + pending)  -- nunca zero
            end)
        else
            dest = validDests[math.random(#validDests)]
        end
        if not dest then goto continue end  -- guarda: WeightedRandom retorna nil para lista vazia

        local dist    = CalcDistance(origin.coords, dest.coords)
        local payment = math.floor(product.basePrice + dist * Config.JobGeneration.distanceMultiplier * dest.multiplier)
        payment = math.min(payment, Config.General.payment.maxPayment)

        return {
            id            = GenerateJobId(),
            origin_id     = origin.id,
            dest_id       = dest.id,
            cargo_item    = product.name,
            trailer_model = product.trailer,
            base_payment  = payment,
            distance      = dist,
            expires_at    = CalcExpiresAt(payment),
        }

        ::continue::
    end
    return nil
end
```

- [ ] **Step 3: Commit**

```bash
git add server/services/job_service.lua
git commit -m "feat(economy): demand-weighted job generation — prefer destinations with fewer pending jobs"
```

---

## Task 6: Server Callbacks

**Files:**
- Modify: `server/callbacks.lua`

- [ ] **Step 1: Adicionar dois callbacks ao final de callbacks.lua**

```lua
-- ============================================================
-- INDUSTRY OWNERSHIP
-- ============================================================

-- Retorna indústrias possuídas pela empresa do jogador
lib.callback.register('AUST_trucker:getIndustryOwnership', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return {} end
    return IndustryOwnershipService.GetCompanyOwned(company.id)
end)

-- Compra uma indústria para a empresa do jogador
lib.callback.register('AUST_trucker:buyIndustry', function(source, industryId)
    if type(industryId) ~= 'string' or industryId == '' then
        return { success = false, reason = 'ID de indústria inválido' }
    end
    if not Config.Industries[industryId] then
        return { success = false, reason = 'Indústria não existe' }
    end
    return IndustryOwnershipService.Buy(source, industryId)
end)
```

- [ ] **Step 2: Enriquecer getIndustries para incluir ownedBy**

Em `server/callbacks.lua`, localizar:
```lua
lib.callback.register('AUST_trucker:getIndustries', function(source)
    return IndustryService.GetAll()
end)
```

Substituir por:
```lua
lib.callback.register('AUST_trucker:getIndustries', function(source)
    local industries = IndustryService.GetAll()
    -- Enriquecer com info de ownership
    for industryId, data in pairs(industries) do
        local owner = IndustryOwnershipService.GetOwner(industryId)
        data.ownedByCompanyId   = owner and owner.company_id   or nil
        data.ownedByCompanyName = nil
        if owner and owner.company_id and VP_Trucker.Companies[owner.company_id] then
            data.ownedByCompanyName = VP_Trucker.Companies[owner.company_id].name
        end
    end
    return industries
end)
```

- [ ] **Step 3: Commit**

```bash
git add server/callbacks.lua
git commit -m "feat(economy): callbacks getIndustryOwnership + buyIndustry + ownedBy enrichment"
```

---

## Task 7: TypeScript + NUI

**Files:**
- Modify: `html/src/types/index.ts`
- Create: `html/src/stores/useIndustryStore.ts`
- Modify: `html/src/hooks/useNUI.ts`
- Modify: `html/src/components/industries/IndustriesPanel.tsx` (ler o arquivo antes de modificar)

**IMPORTANTE**: Antes de modificar `IndustriesPanel.tsx`, ler o arquivo para entender a estrutura atual. O subagente deve adaptar ao padrão existente.

- [ ] **Step 1: Adicionar tipos em html/src/types/index.ts**

Localizar o final do arquivo e adicionar:

```typescript
export interface IndustryOwnership {
  industryId:      string
  industryName:    string
  purchasePrice:   number
  totalEarned:     number
  productionLevel: number
  npcWorkers:      number
}

// Estender o tipo existente de Industry para incluir campos de ownership
// (ler o tipo Industry existente e adicionar os campos)
// Adicionar ao tipo Industry existente:
//   ownedByCompanyId?:   string | null
//   ownedByCompanyName?: string | null
```

Ler o arquivo para encontrar onde `Industry` é declarado e adicionar os dois campos opcionais a ele.

- [ ] **Step 2: Criar html/src/stores/useIndustryStore.ts**

```typescript
import { create } from 'zustand'
import { IndustryOwnership } from '../types'

interface IndustryStore {
  ownedIndustries: IndustryOwnership[]
  setOwnedIndustries: (owned: IndustryOwnership[]) => void
  addOwnedIndustry: (owned: IndustryOwnership) => void
}

export const useIndustryStore = create<IndustryStore>((set) => ({
  ownedIndustries: [],
  setOwnedIndustries: (owned) => set({ ownedIndustries: owned }),
  addOwnedIndustry: (owned) =>
    set((state) => ({ ownedIndustries: [...state.ownedIndustries, owned] })),
}))
```

- [ ] **Step 3: Adicionar handler em html/src/hooks/useNUI.ts**

Localizar o switch/if de actions e adicionar:

```typescript
case 'setOwnedIndustries':
  useIndustryStore.getState().setOwnedIndustries(data.industries ?? [])
  break
```

- [ ] **Step 4: Modificar IndustriesPanel.tsx**

Ler o arquivo `html/src/components/industries/IndustriesPanel.tsx` antes de editar.

Adicionar:
1. Import: `import { useIndustryStore } from '../../stores/useIndustryStore'`
2. Import: `import { fetchNui } from '../../utils/fetchNui'` (ou equivalente já importado — ler o arquivo para confirmar o nome correto)
3. Hooks para dados da empresa atual (ler o arquivo para confirmar qual store/hook fornece o companyId do jogador — provavelmente `useAppStore` ou `useNUI` já expõe `company.id`):
   ```typescript
   const { ownedIndustries } = useIndustryStore()
   // currentCompanyId vem do store de empresa — ler o arquivo para confirmar o hook correto.
   // Padrão esperado: const company = useAppStore(s => s.company) → company?.id
   ```
4. Para cada indústria exibida: mostrar badge "Sua empresa" se `industry.ownedByCompanyId === currentCompanyId`
5. Botão "Comprar Indústria ($X)" visível quando: a indústria não tem dono E o jogador é owner/manager E `ownedIndustries.length < 3` (máximo hardcoded do Config.IndustryOwnership.MaxOwnedPerCompany)
6. Handler de clique do botão:

```typescript
const handleBuyIndustry = async (industryId: string) => {
  const result = await fetchNui('buyIndustry', { industryId })
  if (result?.success) {
    // Adicionar ao store localmente para feedback imediato
    useIndustryStore.getState().addOwnedIndustry({
      industryId,
      industryName: industries[industryId]?.name ?? industryId,
      purchasePrice: result.price ?? 0,
      totalEarned: 0,
      productionLevel: 1,
      npcWorkers: 0,
    })
    // Exibir notificação de sucesso no client (NUI não tem acesso ao lib.notify do servidor)
    // Usar o mecanismo de notificação já existente no projeto — ler o arquivo para confirmar.
    // Padrão esperado: TriggerEvent ou via useNUI notification handler já implementado.
  } else {
    // Exibir mensagem de erro ao usuário (toast, alert, ou campo de erro existente)
    console.warn('[buyIndustry] falhou:', result?.reason)
  }
}
```

**NOTA**: Adaptar ao padrão de fetchNui e tipos já existentes no projeto. Não recriar o painel inteiro — apenas adicionar os elementos de ownership. A notificação de sucesso deve usar o mecanismo já existente no projeto (ler o arquivo para identificar qual é).

- [ ] **Step 5: Carregar ownedIndustries no getInitialData**

Em `server/callbacks.lua`, no callback `AUST_trucker:getInitialData`, adicionar ao objeto de retorno:

```lua
ownedIndustries = company and IndustryOwnershipService.GetCompanyOwned(company.id) or nil,
```

Em `html/src/hooks/useNUI.ts`, no handler `setInitialData` (ou equivalente), adicionar:

```typescript
if (data.ownedIndustries) {
  useIndustryStore.getState().setOwnedIndustries(data.ownedIndustries)
}
```

- [ ] **Step 6: Commit**

```bash
git add html/src/types/index.ts html/src/stores/useIndustryStore.ts html/src/hooks/useNUI.ts html/src/components/
git commit -m "feat(economy): TypeScript types + useIndustryStore + ownership UI in IndustriesPanel"
```

---

## Task 8: fxmanifest + Build + CHANGELOG + Push

**Files:**
- Modify: `fxmanifest.lua`
- Build: `cd html && npm run build`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Atualizar fxmanifest.lua**

Inserir `server/services/industry_ownership_service.lua` após `economy_service.lua` e ANTES de `industry_service.lua`:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/loan_service.lua',
    'server/services/repo_service.lua',
    'server/services/economy_service.lua',
    'server/services/industry_ownership_service.lua',  -- ← NOVO (após economy, antes de industry)
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',
    'server/services/job_service.lua',
    'server/services/truck_simulation_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}
```

Bumpar versão: `version '8.0.0'`

- [ ] **Step 2: Build NUI**

```bash
cd html
npm run build
```

Verificar que não há erros de TypeScript. Se houver, corrigir antes de continuar.

- [ ] **Step 3: Adicionar entrada ao CHANGELOG.md**

Inserir no topo (após o cabeçalho):

```markdown
## [8.0.0] — 2026-03-19

### Added — Fase 2: Economia Completa
- **Propriedade de Indústrias**: empresas logísticas podem comprar indústrias de `Config.Industries`. Preço = `basePrice × productionPerHour × PurchasePriceMultiplier` (padrão 10×). Máximo 3 indústrias por empresa (configurável)
- **Lucro por venda**: quando um jogador compra itens de uma indústria com dono, 15% do valor vai para a empresa dona (configurável via `Config.IndustryOwnership.OwnerProfitPercent`)
- **Custo operacional**: $500 debitado da empresa por ciclo de produção primário (configurável via `Config.IndustryOwnership.OperationalCostPerCycle`)
- **NPC Fail-safe**: indústrias de trading (`Config.Industries`) com itens de consumo zerados por 30+ minutos recebem abastecimento automático de 10 unidades (NPC invisível), evitando travamento da economia com poucos jogadores online
- **Geração de jobs por demanda**: destinos de entrega com menos jobs pendentes têm maior probabilidade de receber novos jobs (`Config.JobGeneration.DemandWeighting = true`)
- `sql/update_economy_v8.sql` — migração segura para servidores existentes

### Migration (v7.x → v8.0.0)
Execute `sql/update_economy_v8.sql` antes de reiniciar o resource.
```

- [ ] **Step 4: Atualizar GUIA_STAFF.md**

Em `GUIA_STAFF.md`, localizar a seção de banco de dados e adicionar:
```markdown
> **Atualização v7.x → v8.x:** Execute `sql/update_economy_v8.sql` para adicionar `last_npc_fill_at` à `trucker_industry_state`, `npc_completed` ao enum de jobs, e `total_earned` à `trucker_industry_ownership`.
```

- [ ] **Step 5: Commit e push**

```bash
git add fxmanifest.lua CHANGELOG.md GUIA_STAFF.md html/assets/
git commit -m "feat: economy Fase 2 v8.0.0 — ownership, NPC fail-safe, demand-weighted jobs"
git push origin main
```

---

## Verificação manual (sem test suite)

Após deployment em servidor de desenvolvimento:

1. **NPC Fail-safe**: no banco, setar `current_stock = 0` e `last_npc_fill_at = NULL` para um item de consumo → aguardar 5 min → verificar que `current_stock = 10` e `last_npc_fill_at` foi atualizado
2. **Propriedade**: como owner/manager de empresa logistics, abrir NUI → Indústrias → clicar "Comprar" → verificar que saldo da empresa diminuiu e indústria aparece com badge
3. **Lucro**: fazer uma transação de compra na indústria com dono → verificar que empresa dona recebeu 15% no saldo
4. **Custo operacional**: aguardar um ciclo de produção primário → verificar que empresa dona perdeu $500
5. **Ponderação de jobs**: no banco, criar vários jobs para o mesmo `dest_id` → iniciar `GenerateBatch()` → verificar distribuição mais uniforme entre destinos
