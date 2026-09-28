# Skill Tree — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the 4 contextual skill bonuses (Distance, Valuable, Fragile, Speed) into job payment at completion, replacing the existing flat `GetPaymentMultiplier` with a new `CalcBonus` function that applies bonuses conditionally based on job data.

**Architecture:** No new files. `CalcBonus(citizenId, jobData)` is added to `progression_service.lua` and called from both `job_service.lua` (legal) and `illegal_service.lua` (illegal). Speed bonus offsets the existing `timeMult`; the other three add to a `paymentMult` conditionally. The NUI, DB, callbacks, and skill purchase flow are already complete and unchanged.

**Tech Stack:** Lua 5.4 (FiveM), QBX (qbx_core), oxmysql, React 18 + TypeScript (NUI, description strings only)

---

## Files Modified

| File | Change |
|---|---|
| `config/config.lua` | Append `Config.Skills` block |
| `server/services/progression_service.lua` | Add `CalcBonus`, remove `GetPaymentMultiplier` |
| `server/services/job_service.lua` | Replace `GetPaymentMultiplier` call with `CalcBonus` |
| `server/services/illegal_service.lua` | Replace `GetPaymentMultiplier` call with `CalcBonus` |
| `html/src/components/progression/SkillTree.tsx` | Update 4 description strings |
| `CHANGELOG.md` | Add v13.0.0 entry |
| `fxmanifest.lua` | Bump version to `13.0.0` |

---

## Task 1: Config.Skills block

**Files:**
- Modify: `config/config.lua` (append after line 1257)

- [ ] **Step 1: Append `Config.Skills` to the end of `config/config.lua`**

```lua
-- ============================================================
-- SKILL TREE (v13.0.0)
-- ============================================================

Config.Skills = {
    BonusPerLevel     = 0.02,   -- +2% por nível de skill ativo (ex: lv3 = +6%)
    DistanceThreshold = 10.0,   -- km mínimos para Distance ser ativada
    ValuableThreshold = 5000,   -- $ mínimos no basePayment para Valuable ser ativada
    FragileThreshold  = 85,     -- % mínimos de integridade entregue para Fragile ser ativada
}
```

- [ ] **Step 2: Verify the config loads without Lua errors**

Start the FiveM server and check the server console. Expected: no `[AUST_trucker]` Lua errors on startup.

- [ ] **Step 3: Commit**

```bash
git add config/config.lua
git commit -m "feat(skills): add Config.Skills block with contextual thresholds"
```

---

## Task 2: CalcBonus in progression_service.lua

**Files:**
- Modify: `server/services/progression_service.lua` (lines 84-91 — replace `GetPaymentMultiplier` with `CalcBonus`)

Context: `GetPaymentMultiplier` currently at lines 84-91:
```lua
function ProgressionService.GetPaymentMultiplier(citizenId)
    local skills = ProgressionService.GetSkills(citizenId)
    local total  = 0
    for _, lvl in pairs(skills) do
        total = total + lvl
    end
    return 1.0 + (total * 0.02)
end
```

- [ ] **Step 1: Replace `GetPaymentMultiplier` with `CalcBonus` in `progression_service.lua`**

Delete the entire `GetPaymentMultiplier` block (lines 84-91) and replace with:

```lua
-- CalcBonus: multiplier contextual por tipo de skill
-- jobData = { distance, basePayment, cargoIntegrity }
-- returns { paymentMult, speedBonus }
function ProgressionService.CalcBonus(citizenId, jobData)
    local skills = ProgressionService.GetSkills(citizenId)
    local b      = Config.Skills.BonusPerLevel

    local paymentMult = 1.0

    if (skills.distance or 0) > 0 and (jobData.distance or 0) >= Config.Skills.DistanceThreshold then
        paymentMult = paymentMult + (skills.distance * b)
    end

    if (skills.valuable or 0) > 0 and (jobData.basePayment or 0) >= Config.Skills.ValuableThreshold then
        paymentMult = paymentMult + (skills.valuable * b)
    end

    if (skills.fragile or 0) > 0 and (jobData.cargoIntegrity or 100) >= Config.Skills.FragileThreshold then
        paymentMult = paymentMult + (skills.fragile * b)
    end

    local speedBonus = (skills.speed or 0) * b

    return { paymentMult = paymentMult, speedBonus = speedBonus }
end
```

- [ ] **Step 2: Verify no references to `GetPaymentMultiplier` remain in the file**

Search the file for `GetPaymentMultiplier` — expected: zero occurrences.

- [ ] **Step 3: Check server starts without errors**

Restart resource. Expected: no Lua errors in server console.

- [ ] **Step 4: Commit**

```bash
git add server/services/progression_service.lua
git commit -m "feat(skills): replace GetPaymentMultiplier with contextual CalcBonus"
```

---

## Task 3: Wire CalcBonus into job_service.lua and illegal_service.lua

**Files:**
- Modify: `server/services/job_service.lua` (lines 328-342)
- Modify: `server/services/illegal_service.lua` (lines 246-248)

### job_service.lua

Current code at lines 328-342:
```lua
    -- Aplicar bônus de skills (cada nível de skill = +2%)
    local skillMult = ProgressionService.GetPaymentMultiplier(citizenId)

    -- Aplicar bônus de empresa (nivel da empresa aumenta o multiplicador)
    local company     = CompanyService.GetByMember(citizenId)
    local companyMult = 1.0
    if company then
        companyMult = CompanyService.GetPerks(company.id).bonus
    end
    local rawIntegrity  = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
    local integrityMult = math.max(
        Config.TruckSimulation.Cargo.MinPaymentRate,
        rawIntegrity / 100
    )
    local payment = math.floor(activeJob.base_payment * timeMult * skillMult * companyMult * integrityMult)
```

- [ ] **Step 1: Update `job_service.lua` — replace `skillMult` with `CalcBonus`, apply `speedBonus` to `timeMult`**

Replace those lines with:

```lua
    -- Aplicar bônus de skills contextual (v13)
    local skillBonus = ProgressionService.CalcBonus(citizenId, {
        distance       = activeJob.distance,
        basePayment    = activeJob.base_payment,
        cargoIntegrity = tonumber(payload.cargoIntegrity) or 100,
    })
    timeMult = timeMult + skillBonus.speedBonus

    -- Aplicar bônus de empresa (nivel da empresa aumenta o multiplicador)
    local company     = CompanyService.GetByMember(citizenId)
    local companyMult = 1.0
    if company then
        companyMult = CompanyService.GetPerks(company.id).bonus
    end
    local rawIntegrity  = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
    local integrityMult = math.max(
        Config.TruckSimulation.Cargo.MinPaymentRate,
        rawIntegrity / 100
    )
    local payment = math.floor(activeJob.base_payment * skillBonus.paymentMult * timeMult * companyMult * integrityMult)
```

### illegal_service.lua

Current code at lines 245-248 (replace ONLY lines 246-248 — preserve line 245 `local citizenid`):
```lua
    local citizenid = Player.PlayerData.citizenid           -- linha 245: NÃO ALTERAR
    local mult      = Config.IllegalJobs.paymentMultipliers[activeJob.illegal_type] or 1.0  -- linha 246
    local skillMult = ProgressionService.GetPaymentMultiplier(citizenid)                    -- linha 247
    local payment   = math.floor(activeJob.base_payment * mult * timeMult * skillMult)     -- linha 248
```

- [ ] **Step 2: Update `illegal_service.lua` — replace lines 246-248 only with `CalcBonus` (manter linha 245 intacta)**

Replace only those 3 lines (246-248) with:

```lua
    local mult       = Config.IllegalJobs.paymentMultipliers[activeJob.illegal_type] or 1.0
    local skillBonus = ProgressionService.CalcBonus(citizenid, {
        distance       = activeJob.distance,
        basePayment    = activeJob.base_payment,
        cargoIntegrity = tonumber(payload.cargoIntegrity) or 100,
    })
    timeMult = timeMult + skillBonus.speedBonus
    local payment = math.floor(activeJob.base_payment * mult * timeMult * skillBonus.paymentMult)
```

Note: no `companyMult` or `integrityMult` in the illegal path — intentional design.

- [ ] **Step 3: Verify `GetPaymentMultiplier` no longer appears in either file**

Search both files for `GetPaymentMultiplier` — expected: zero occurrences in each.

- [ ] **Step 4: Manual verification — complete a legal job and check payment**

In-game, accept a job with distance ≥10km and basePayment ≥$5.000. Ensure you have Distance lv1 and Valuable lv1. Complete the delivery with high integrity.

Expected: payment is higher than `base_payment × timeMult` alone. Check server console or add a temporary `print` in `job_service.lua` after the payment line:
```lua
print(('[skill-debug] paymentMult=%.3f speedBonus=%.3f timeMult=%.3f payment=%d'):format(
    skillBonus.paymentMult, skillBonus.speedBonus, timeMult, payment))
```
Remove the debug print before committing.

- [ ] **Step 5: Commit**

```bash
git add server/services/job_service.lua server/services/illegal_service.lua
git commit -m "feat(skills): wire CalcBonus into job and illegal payment calculation"
```

---

## Task 4: NUI descriptions + CHANGELOG + version bump

**Files:**
- Modify: `html/src/components/progression/SkillTree.tsx` (lines 6-9)
- Modify: `CHANGELOG.md`
- Modify: `fxmanifest.lua`

### SkillTree.tsx

Current SKILL_META at lines 6-9:
```tsx
  distance: { label: 'Distância',  icon: '🛣️', desc: '+2% p/ nível em rotas longas'   },
  valuable: { label: 'Valioso',    icon: '💎', desc: '+2% p/ nível em carga de valor'  },
  fragile:  { label: 'Frágil',     icon: '📦', desc: '+2% p/ nível em carga delicada'  },
  speed:    { label: 'Velocidade', icon: '⚡', desc: '+2% p/ nível no bônus de tempo'  },
```

- [ ] **Step 1: Update the 4 description strings in `SkillTree.tsx`**

Replace those 4 lines with:

```tsx
  distance: { label: 'Distância',  icon: '🛣️', desc: '+2% p/ nível em rotas ≥10km'              },
  valuable: { label: 'Valioso',    icon: '💎', desc: '+2% p/ nível em jobs ≥$5.000'             },
  fragile:  { label: 'Frágil',     icon: '📦', desc: '+2% p/ nível com integridade ≥85%'        },
  speed:    { label: 'Velocidade', icon: '⚡', desc: '+2% p/ nível no multiplicador de tempo'   },
```

- [ ] **Step 2: Build the NUI**

```bash
cd html && npm run build
```

Expected: build completes with zero TypeScript errors. Output written to `html/assets/`.

- [ ] **Step 3: Add v13.0.0 entry to `CHANGELOG.md`**

Insert before the `## [12.0.0]` line:

```markdown
## [13.0.0] — 2026-03-21 — Skill Tree Contextual Bonuses

### Changed
- **Skill bonuses now contextual** (`server/services/progression_service.lua`)
  - `GetPaymentMultiplier(citizenId)` replaced by `CalcBonus(citizenId, jobData)` → `{ paymentMult, speedBonus }`
  - **Distance** (+2%/lv): active when `job.distance >= Config.Skills.DistanceThreshold` (default 10km)
  - **Valuable** (+2%/lv): active when `job.basePayment >= Config.Skills.ValuableThreshold` (default $5.000)
  - **Fragile** (+2%/lv): active when `cargoIntegrity >= Config.Skills.FragileThreshold` (default 85%)
  - **Speed** (+2%/lv): adds to `timeMult` directly instead of `paymentMult`; reduces slow-delivery penalty
- `server/services/job_service.lua` — applies `CalcBonus` (preserves `companyMult` + `integrityMult`)
- `server/services/illegal_service.lua` — applies `CalcBonus` (preserves `mult`; no `companyMult`/`integrityMult`)
- `html/src/components/progression/SkillTree.tsx` — description strings updated to show real thresholds

### Added
- `Config.Skills` block in `config/config.lua` — all thresholds and `BonusPerLevel` are operator-configurable

---
```

- [ ] **Step 4: Bump version in `fxmanifest.lua`**

Change:
```lua
version '12.0.0'
```
To:
```lua
version '13.0.0'
```

- [ ] **Step 5: Commit**

```bash
git add html/src/components/progression/SkillTree.tsx html/assets/ CHANGELOG.md fxmanifest.lua
git commit -m "feat(skills): contextual skill tree v13.0.0 — descriptions, changelog, version bump"
```
