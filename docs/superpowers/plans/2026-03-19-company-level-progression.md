# Company Level Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a company level system (30 levels) where XP earned from member deliveries unlocks more vehicle slots, larger member caps, and a payment bonus multiplier.

**Architecture:** Config-driven `Config.CompanyLevels` table holds all thresholds and perks. `CompanyService.AddXP` checks for level-ups (loop) after each delivery. `CompanyService.GetPerks` resolves current perks from cache. `JobService.Complete` calls both functions. `AUST_trucker:getInitialData` sends enriched company payload to NUI. `CompanyPanel` gains a level/XP bar using absolute-to-relative XP conversion (`xp_level_start` field).

**Tech Stack:** Lua 5.4 (server), oxmysql, React 18 + TypeScript 5 + Tailwind CSS 3

---

## File Map

| File | Action | Change |
|---|---|---|
| `import.sql` | Modify | Add `company_level`, `company_xp` columns with CHECK constraint |
| `sql/update_company_levels.sql` | Create | Migration for existing databases |
| `config/config.lua` | Modify | Add `Config.CompanyLevels` (30 entries) + `Config.CompanyXpPerDelivery` |
| `server/database.lua` | Modify | Add `DB_AddCompanyXP`, `DB_SetCompanyLevel` |
| `server/services/company_service.lua` | Modify | Add `AddXP`, `GetPerks`; update `Create`, `RegisterVehicle`, `AddMember` |
| `server/services/job_service.lua` | Modify | Hook company bonus multiplier and `AddXP` call in `Complete` |
| `server/callbacks.lua` | Modify | Enrich company payload in `AUST_trucker:getInitialData` |
| `html/src/types/index.ts` | Modify | Add `level`, `xp`, `xp_next`, `xp_level_start`, `perks` to `Company` |
| `html/src/components/company/CompanyPanel.tsx` | Modify | Add level/XP bar section |
| `fxmanifest.lua` | Modify | Bump version to `6.0.0` |

---

## Task 1: Schema — add level/xp columns

**Files:**
- Modify: `import.sql`
- Create: `sql/update_company_levels.sql`

- [ ] **Step 1: Add columns to `import.sql`**

In the `CREATE TABLE trucker_companies` block, add after `company_type`:
```sql
    company_level   TINYINT         DEFAULT 1 CHECK (company_level BETWEEN 1 AND 30),
    company_xp      INT             DEFAULT 0,
```

The final column list becomes:
```sql
CREATE TABLE trucker_companies (
    id              VARCHAR(50)     PRIMARY KEY,
    owner_citizenid VARCHAR(50)     NOT NULL,
    name            VARCHAR(100)    NOT NULL UNIQUE,
    balance         BIGINT          DEFAULT 0,
    is_recruiting   TINYINT(1)      DEFAULT 0,
    company_type    ENUM('logistics','repo') DEFAULT 'logistics',
    company_level   TINYINT         DEFAULT 1 CHECK (company_level BETWEEN 1 AND 30),
    company_xp      INT             DEFAULT 0,
    created_at      DATETIME        DEFAULT CURRENT_TIMESTAMP
);
```

- [ ] **Step 2: Create migration script**

Create `sql/update_company_levels.sql`:
```sql
-- AUST_trucker — Migration: add company level/xp columns
-- Run once on existing databases. Safe to run multiple times (IF NOT EXISTS).

ALTER TABLE trucker_companies
    ADD COLUMN IF NOT EXISTS company_level TINYINT  DEFAULT 1 CHECK (company_level BETWEEN 1 AND 30),
    ADD COLUMN IF NOT EXISTS company_xp    INT      DEFAULT 0;
```

- [ ] **Step 3: Commit**
```bash
git add import.sql sql/update_company_levels.sql
git commit -m "feat(schema): add company_level and company_xp columns to trucker_companies"
```

---

## Task 2: Config — add `Config.CompanyLevels`

**Files:**
- Modify: `config/config.lua`

- [ ] **Step 1: Add table at the end of `config/config.lua`**

Add before the final blank line:
```lua
-- =======================================
-- EMPRESA — PROGRESSÃO DE NÍVEL
-- =======================================
-- 30 níveis. xpRequired = XP acumulado para atingir este nível.
-- vehicles = slots de veículos, members = membros máximos, bonus = multiplicador de pagamento
-- AVISO: Config.CompanyXpPerDelivery não deve exceder 50 (gap mínimo entre nível 1 e 2).
-- Se aumentado, ajuste AddXP — o loop já suporta multi-level-up.
Config.CompanyLevels = {
    -- level  xpRequired  vehicles  members  bonus
    { level = 1,  xpRequired = 0,    vehicles = 2, members = 5,  bonus = 1.00 },
    { level = 2,  xpRequired = 50,   vehicles = 2, members = 6,  bonus = 1.00 },
    { level = 3,  xpRequired = 150,  vehicles = 2, members = 7,  bonus = 1.01 },
    { level = 4,  xpRequired = 300,  vehicles = 2, members = 7,  bonus = 1.01 },
    { level = 5,  xpRequired = 500,  vehicles = 3, members = 8,  bonus = 1.01 },
    { level = 6,  xpRequired = 750,  vehicles = 3, members = 9,  bonus = 1.02 },
    { level = 7,  xpRequired = 1050, vehicles = 3, members = 9,  bonus = 1.02 },
    { level = 8,  xpRequired = 1400, vehicles = 3, members = 10, bonus = 1.02 },
    { level = 9,  xpRequired = 1800, vehicles = 3, members = 11, bonus = 1.02 },
    { level = 10, xpRequired = 2250, vehicles = 4, members = 12, bonus = 1.03 },
    { level = 11, xpRequired = 2750, vehicles = 4, members = 12, bonus = 1.03 },
    { level = 12, xpRequired = 3300, vehicles = 4, members = 13, bonus = 1.03 },
    { level = 13, xpRequired = 3900, vehicles = 4, members = 13, bonus = 1.03 },
    { level = 14, xpRequired = 4550, vehicles = 4, members = 14, bonus = 1.04 },
    { level = 15, xpRequired = 5250, vehicles = 4, members = 15, bonus = 1.04 },
    { level = 16, xpRequired = 6000, vehicles = 4, members = 15, bonus = 1.04 },
    { level = 17, xpRequired = 6800, vehicles = 4, members = 16, bonus = 1.04 },
    { level = 18, xpRequired = 7650, vehicles = 4, members = 16, bonus = 1.04 },
    { level = 19, xpRequired = 8550, vehicles = 4, members = 17, bonus = 1.05 },
    { level = 20, xpRequired = 9500, vehicles = 5, members = 17, bonus = 1.05 },
    { level = 21, xpRequired = 10500,vehicles = 5, members = 18, bonus = 1.05 },
    { level = 22, xpRequired = 11550,vehicles = 5, members = 18, bonus = 1.05 },
    { level = 23, xpRequired = 12650,vehicles = 5, members = 18, bonus = 1.05 },
    { level = 24, xpRequired = 13800,vehicles = 5, members = 19, bonus = 1.05 },
    { level = 25, xpRequired = 15000,vehicles = 5, members = 19, bonus = 1.06 },
    { level = 26, xpRequired = 16250,vehicles = 5, members = 19, bonus = 1.06 },
    { level = 27, xpRequired = 17550,vehicles = 5, members = 20, bonus = 1.06 },
    { level = 28, xpRequired = 18900,vehicles = 5, members = 20, bonus = 1.06 },
    { level = 29, xpRequired = 20300,vehicles = 5, members = 20, bonus = 1.06 },
    { level = 30, xpRequired = 21750,vehicles = 5, members = 20, bonus = 1.06 },
}

-- XP concedido à empresa por entrega concluída de um membro
Config.CompanyXpPerDelivery = 50
```

- [ ] **Step 2: Commit**
```bash
git add config/config.lua
git commit -m "feat(config): add Config.CompanyLevels table and CompanyXpPerDelivery"
```

---

## Task 3: DB helpers — `DB_AddCompanyXP` / `DB_SetCompanyLevel`

**Files:**
- Modify: `server/database.lua`

- [ ] **Step 1: Add two functions at the end of the COMPANIES section (after `DB_GetRecruitingCompanies`)**

```lua
-- Adiciona XP à empresa e retorna { company_xp, company_level } atuais
function DB_AddCompanyXP(companyId, xp)
    MySQL.update.await(
        'UPDATE trucker_companies SET company_xp = company_xp + ? WHERE id = ?',
        { xp, companyId }
    )
    return MySQL.single.await(
        'SELECT company_xp, company_level FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
end

-- Atualiza level mantendo XP acumulado intacto (chamado no level-up)
function DB_SetCompanyLevel(companyId, level)
    MySQL.update.await(
        'UPDATE trucker_companies SET company_level = ? WHERE id = ?',
        { level, companyId }
    )
end
```

- [ ] **Step 2: Commit**
```bash
git add server/database.lua
git commit -m "feat(db): add DB_AddCompanyXP and DB_SetCompanyLevel helpers"
```

---

## Task 4: CompanyService — `AddXP`, `GetPerks`, enforce limits

**Files:**
- Modify: `server/services/company_service.lua`

- [ ] **Step 1: Remove `MAX_VEHICLES` constant and add `GetPerksForLevel` local helper**

Delete the line:
```lua
local MAX_VEHICLES  = 2
```

Then add a new local helper after `local SELL_PAYOUT = 25000`:

```lua
-- Retorna perks da empresa a partir do nível (busca linear na tabela de config)
local function GetPerksForLevel(level)
    local levels = Config.CompanyLevels
    for _, entry in ipairs(levels) do
        if entry.level == level then return entry end
    end
    return levels[1]  -- fallback seguro
end
```

- [ ] **Step 2: Add `CompanyService.GetPerks` public method**

After `CompanyService.Get`:
```lua
-- Retorna perks (vehicles, members, bonus) da empresa com base no nível em cache
function CompanyService.GetPerks(companyId)
    local company = VP_Trucker.Companies[companyId]
    local level   = (company and company.company_level) or 1
    return GetPerksForLevel(level)
end
```

- [ ] **Step 3: Add `CompanyService.AddXP` public method (with level-up loop)**

After `CompanyService.GetPerks`:
```lua
-- Concede XP de entrega à empresa; aplica level-up(s) se necessário (loop)
function CompanyService.AddXP(companyId, xp)
    local company = VP_Trucker.Companies[companyId]
    if not company then return end

    local row = DB_AddCompanyXP(companyId, xp)
    if not row then return end

    -- Atualizar cache de XP
    company.company_xp    = row.company_xp
    company.company_level = row.company_level

    -- Loop de level-up: um único job pode cruzar múltiplos thresholds se o XP/job for alto
    local levels   = Config.CompanyLevels
    local maxLevel = #levels
    local changed  = false

    while company.company_level < maxLevel do
        local nextEntry = levels[company.company_level + 1]
        if nextEntry and company.company_xp >= nextEntry.xpRequired then
            company.company_level = company.company_level + 1
            changed = true
            if Config.Debug then
                print(('[AUST_trucker] Company %s → nível %d'):format(companyId, company.company_level))
            end
        else
            break
        end
    end

    if changed then
        DB_SetCompanyLevel(companyId, company.company_level)
    end
end
```

- [ ] **Step 4: Update `CompanyService.Create` — add level/xp to cache entry**

In `CompanyService.Create`, the cache entry block becomes:
```lua
    VP_Trucker.Companies[companyId] = {
        id              = companyId,
        owner_citizenid = citizenId,
        name            = name,
        balance         = 0,
        is_recruiting   = 0,
        company_type    = companyType,
        company_level   = 1,
        company_xp      = 0,
    }
```

- [ ] **Step 5: Update `CompanyService.AddMember` — enforce member limit**

Replace the existing function with:
```lua
function CompanyService.AddMember(companyId, citizenId)
    if VP_Trucker.PlayerCompanies[citizenId] then
        return false, 'Jogador já está em uma empresa'
    end

    local perks   = CompanyService.GetPerks(companyId)
    local members = DB_GetMembers(companyId)
    if #members >= perks.members then
        return false, ('Limite de %d membros atingido para o nível atual'):format(perks.members)
    end

    DB_AddMember(companyId, citizenId, 'driver')
    VP_Trucker.PlayerCompanies[citizenId] = companyId
    return true, nil
end
```

- [ ] **Step 6: Update `CompanyService.RegisterVehicle` — use level-based limit**

Replace the existing function with:
```lua
function CompanyService.RegisterVehicle(companyId, plate, model, vehicleType)
    local perks    = CompanyService.GetPerks(companyId)
    local vehicles = DB_GetVehicles(companyId)
    if #vehicles >= perks.vehicles then
        return false, ('Limite de %d veículos atingido para o nível atual'):format(perks.vehicles)
    end
    DB_RegisterVehicle(companyId, plate, model, vehicleType)
    return true, nil
end
```

- [ ] **Step 7: Commit**
```bash
git add server/services/company_service.lua
git commit -m "feat(company): add level progression — AddXP, GetPerks, enforce level-based limits"
```

---

## Task 5: JobService — hook XP grant and payment bonus

**Files:**
- Modify: `server/services/job_service.lua`

- [ ] **Step 1: Replace the `payment` calculation and add XP grant in `JobService.Complete`**

In `JobService.Complete`, find the block:
```lua
    -- Aplicar bônus de skills (cada nível de skill = +2%)
    local skillMult = ProgressionService.GetPaymentMultiplier(citizenId)
    local payment   = math.floor(activeJob.base_payment * timeMult * skillMult)
```

Replace it with:
```lua
    -- Aplicar bônus de skills (cada nível de skill = +2%)
    local skillMult = ProgressionService.GetPaymentMultiplier(citizenId)

    -- Aplicar bônus de empresa (nivel da empresa aumenta o multiplicador)
    local company     = CompanyService.GetByMember(citizenId)
    local companyMult = 1.0
    if company then
        companyMult = CompanyService.GetPerks(company.id).bonus
    end
    local payment = math.floor(activeJob.base_payment * timeMult * skillMult * companyMult)
```

- [ ] **Step 2: Remove the duplicate `local company` declaration and add XP grant**

Find further down in the same function:
```lua
    -- Evento externo (AUST_sala e outros recursos)
    local company = CompanyService.GetByMember(citizenId)
    TriggerEvent('AUST_trucker:jobCompleted', citizenId,
        company and company.id or nil,
        { jobId = activeJob.id, cargo = activeJob.cargo_item },
        payment)
```

Replace with (remove `local company =` since it's already declared above):
```lua
    -- Evento externo (AUST_sala e outros recursos)
    TriggerEvent('AUST_trucker:jobCompleted', citizenId,
        company and company.id or nil,
        { jobId = activeJob.id, cargo = activeJob.cargo_item },
        payment)

    -- XP de empresa
    if company then
        CompanyService.AddXP(company.id, Config.CompanyXpPerDelivery)
    end
```

- [ ] **Step 3: Verify the final `JobService.Complete` has no duplicate `local company`**

Do a quick scan of the function — `company` should appear only once as a `local` declaration (the one added in Step 1).

- [ ] **Step 4: Commit**
```bash
git add server/services/job_service.lua
git commit -m "feat(jobs): apply company bonus multiplier and grant company XP on delivery"
```

---

## Task 6: NUI types — extend `Company` interface

**Files:**
- Modify: `html/src/types/index.ts`

> **Note:** The TypeScript build will only succeed after Task 7 sends the new fields. Don't run the standalone build after this task alone — run it only in Task 9 after all server and NUI changes are done.

- [ ] **Step 1: Add `CompanyPerks` type and extend `Company`**

Replace the `Company` interface:
```typescript
export interface CompanyPerks {
  vehicles: number
  members: number
  bonus: number
}

export interface Company {
  id: string
  name: string
  balance: number
  is_recruiting: number
  owner_citizenid: string
  role: 'owner' | 'manager' | 'driver'
  company_type: 'logistics' | 'repo'
  company_level: number
  company_xp: number
  xp_next: number         // XP required for next level (0 if at max level 30)
  xp_level_start: number  // XP threshold of the current level (for bar calculation)
  perks: CompanyPerks
}
```

- [ ] **Step 2: Commit**
```bash
git add html/src/types/index.ts
git commit -m "feat(types): add company_level, xp, xp_next, xp_level_start, perks to Company interface"
```

---

## Task 7: Server — enrich company payload in `AUST_trucker:getInitialData`

**Files:**
- Modify: `server/callbacks.lua`

The callback is `AUST_trucker:getInitialData` at the top of `server/callbacks.lua` (line 5). Currently it passes `company = company` where `company` is the raw cache entry. Replace it with an enriched table.

- [ ] **Step 1: Replace `company = company` with enriched payload**

Find:
```lua
    return {
        jobs                = JobService.GetAvailable(),
        company             = company,
        activeJob           = JobService.GetActiveByPlayer(citizenId),
```

Replace with:
```lua
    -- Enriquecer company com dados de nível para a NUI
    local companyPayload = nil
    if company then
        local levels  = Config.CompanyLevels
        local lvl     = company.company_level or 1
        local perks   = CompanyService.GetPerks(company.id)
        local xpNext  = (lvl < #levels) and levels[lvl + 1].xpRequired or 0
        local xpStart = levels[lvl] and levels[lvl].xpRequired or 0

        companyPayload = {
            id              = company.id,
            owner_citizenid = company.owner_citizenid,
            name            = company.name,
            balance         = company.balance,
            is_recruiting   = company.is_recruiting,
            company_type    = company.company_type,
            company_level   = lvl,
            company_xp      = company.company_xp or 0,
            xp_next         = xpNext,
            xp_level_start  = xpStart,
            perks           = { vehicles = perks.vehicles, members = perks.members, bonus = perks.bonus },
        }
    end

    return {
        jobs                = JobService.GetAvailable(),
        company             = companyPayload,
        activeJob           = JobService.GetActiveByPlayer(citizenId),
```

> **Note:** The `role` field (owner/manager/driver) is NOT in the cache — it is injected client-side from the player's own member record. Do not add it here; the existing NUI hook already handles this separately via a different call or the members list.

- [ ] **Step 2: Commit**
```bash
git add server/callbacks.lua
git commit -m "feat(server): include company level/xp/perks in NUI company payload"
```

---

## Task 8: NUI — add level/XP bar to `CompanyPanel`

**Files:**
- Modify: `html/src/components/company/CompanyPanel.tsx`

The XP bar uses `xp_level_start` to convert absolute XP to within-level progress:
```
progress = (company_xp - xp_level_start) / (xp_next - xp_level_start)
```

- [ ] **Step 1: Add level/XP bar section after the header div**

After the closing `</div>` of the header block (the one containing Depositar/Sacar/Recrutar buttons), insert:

```tsx
      {/* Nível da empresa */}
      <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <div className="flex justify-between items-center mb-2">
          <p className="text-zinc-100 text-sm font-semibold">
            Nível {company.company_level}
            {company.company_level < 30 && (
              <span className="text-zinc-400 font-normal ml-1">
                → {company.company_level + 1}
              </span>
            )}
          </p>
          {company.xp_next > 0 ? (
            <p className="text-zinc-400 text-xs">
              {company.company_xp - company.xp_level_start} / {company.xp_next - company.xp_level_start} XP
            </p>
          ) : (
            <p className="text-yellow-400 text-xs font-medium">Nível máximo</p>
          )}
        </div>

        {/* Barra de XP — progress relativo ao nível atual */}
        {company.xp_next > 0 && (
          <div className="w-full bg-zinc-700 rounded-full h-1.5">
            <div
              className="bg-blue-500 h-1.5 rounded-full transition-all"
              style={{
                width: `${Math.min(100, ((company.company_xp - company.xp_level_start) / (company.xp_next - company.xp_level_start)) * 100)}%`
              }}
            />
          </div>
        )}

        {/* Perks atuais */}
        <div className="grid grid-cols-3 gap-2 mt-3 text-center">
          <div className="bg-zinc-900 rounded p-2">
            <p className="text-blue-400 font-bold text-sm">{company.perks.vehicles}</p>
            <p className="text-zinc-500 text-[10px]">Veículos</p>
          </div>
          <div className="bg-zinc-900 rounded p-2">
            <p className="text-blue-400 font-bold text-sm">{company.perks.members}</p>
            <p className="text-zinc-500 text-[10px]">Membros</p>
          </div>
          <div className="bg-zinc-900 rounded p-2">
            <p className="text-blue-400 font-bold text-sm">
              {company.perks.bonus > 1.0
                ? `+${((company.perks.bonus - 1) * 100).toFixed(0)}%`
                : '0%'}
            </p>
            <p className="text-zinc-500 text-[10px]">Bônus</p>
          </div>
        </div>
      </div>
```

- [ ] **Step 2: Commit**
```bash
git add html/src/components/company/CompanyPanel.tsx
git commit -m "feat(ui): add company level XP bar and perks display to CompanyPanel"
```

---

## Task 9: Frontend build + version bump + push

**Files:**
- `html/` (build output)
- `fxmanifest.lua`
- `CHANGELOG.md`

- [ ] **Step 1: Build frontend**
```bash
cd "E:/Users/Vinicius/Downloads/txData/Qbox_753251.base/resources/[standalone]/AUST_trucker/html" && npm run build
```
Expected: no TypeScript errors, build succeeds with new assets in `html/assets/`.

- [ ] **Step 2: Bump manifest version**

In `fxmanifest.lua`, change:
```lua
version '5.1.0'
```
to:
```lua
version '6.0.0'
```

- [ ] **Step 3: Update `CHANGELOG.md`**

Add entry at the top (after the `## [Unreleased]` line or as the new most recent version):
```markdown
## [6.0.0] — 2026-03-19

### Added
- Company level progression system (30 levels)
- XP earned per member delivery (50 XP, configurable via `Config.CompanyXpPerDelivery`)
- `Config.CompanyLevels` table: vehicle slots (2→5), max members (5→20), payment bonus (0%→+6%)
- `CompanyService.AddXP(companyId, xp)` and `CompanyService.GetPerks(companyId)` server functions
- Level/XP bar and perks display in Company panel (NUI)
- Migration script: `sql/update_company_levels.sql`

### Changed
- `CompanyService.RegisterVehicle`: vehicle slot limit is now level-based (was hardcoded to 2)
- `CompanyService.AddMember`: enforces level-based member cap
- `JobService.Complete`: applies company bonus multiplier to payment calculation
```

- [ ] **Step 4: Commit and push**
```bash
git add html/assets/ fxmanifest.lua CHANGELOG.md
git commit -m "feat: company level progression v6.0.0 — build, manifest, changelog"
git push
```

---

## Notes for implementer

- **lua54 chunk isolation**: `CompanyService` is a global table; `GetPerksForLevel` is `local` inside `company_service.lua` only. `DB_AddCompanyXP`/`DB_SetCompanyLevel` are globals in `database.lua`. Load order in `fxmanifest.lua` already has `database.lua` before `company_service.lua` — no manifest changes needed for server_scripts.
- **`LoadCompanies()` in `main.lua`** uses `SELECT *` — `company_level` and `company_xp` columns will populate the cache automatically after the migration runs. Only `Create()` needs explicit field initialization (Task 4, Step 4).
- **`role` field in Company**: The `role` field (owner/manager/driver) is NOT in `trucker_companies` — it lives in `trucker_company_members`. It is injected separately by the existing NUI flow and is not affected by this plan.
- **XP bar formula**: uses `xp_level_start` (the floor of the current level's required XP) to convert from absolute cumulative XP to a within-level percentage. Without this, the bar would show `~87%` on a level 10 company with barely any XP into level 11.
- **Multi level-up**: `AddXP` uses a `while` loop so a company can gain multiple levels in one delivery (relevant if `Config.CompanyXpPerDelivery` is raised by the server admin). The loop breaks as soon as no further threshold is crossed.
