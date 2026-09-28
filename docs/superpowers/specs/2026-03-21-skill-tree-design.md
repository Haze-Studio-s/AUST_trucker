# Skill Tree — Implementation Design

> **For agentic workers:** This spec describes wiring an already-built skill tree infrastructure into the job payment flow. Most DB, NUI, and service code already exists — focus on `CalcBonus`, `JobService.Complete`, `IllegalService`, and the Config block.

---

## Goal

Apply the 4 contextual skill bonuses (Distance, Valuable, Fragile, Speed) to job payment at completion. The skill infrastructure (DB, NUI, callbacks, PurchaseSkill) is fully implemented — what is missing is the bonus calculation and its application in `JobService.Complete` and `IllegalService`.

## Architecture

No new files. No SQL migrations. Changes touch 5 existing files:

| File | Change |
|---|---|
| `server/services/progression_service.lua` | Add `CalcBonus(citizenId, jobData)` alongside existing `GetPaymentMultiplier` (keep the old one as alias for illegal service compatibility) |
| `server/services/job_service.lua` | Replace `skillMult = GetPaymentMultiplier(citizenId)` with `CalcBonus`; apply `speedBonus` to `timeMult` |
| `server/services/illegal_service.lua` | Replace `GetPaymentMultiplier(citizenId)` with `CalcBonus` (or alias) — must not be left calling old signature |
| `config/config.lua` | Add `Config.Skills` block |
| `html/src/components/progression/SkillTree.tsx` | Update skill descriptions to show actual thresholds |

---

## Existing Payment Formulas (do not break)

The two paths have **different** multiplier sets:

**`job_service.lua` (legal jobs):**
```lua
-- Current:
local payment = math.floor(activeJob.base_payment * timeMult * skillMult * companyMult * integrityMult)
-- New (replace skillMult, adjust timeMult):
local bonus        = ProgressionService.CalcBonus(citizenId, jobData)
local timeMult     = GetTimeMultiplier(payload.deliveryTime) + bonus.speedBonus
local finalPayment = math.floor(activeJob.base_payment * bonus.paymentMult * timeMult * companyMult * integrityMult)
```
Preserve `companyMult` and `integrityMult` — they exist only in the legal path.

**`illegal_service.lua` (illegal jobs):**
```lua
-- Current:
local payment = math.floor(activeJob.base_payment * mult * timeMult * skillMult)
-- New (replace skillMult, adjust timeMult):
local bonus        = ProgressionService.CalcBonus(citizenId, jobData)
local timeMult     = GetTimeMultiplier(payload.deliveryTime) + bonus.speedBonus
local finalPayment = math.floor(activeJob.base_payment * mult * timeMult * bonus.paymentMult)
```
`mult` is the illegal type multiplier from `Config.IllegalJobs.paymentMultipliers`. There is no `companyMult` or `integrityMult` in the illegal path — do not add them.

---

## Existing timeMultiplier Thresholds (from Config.TruckSimulation.timeBonus)

```lua
-- Actual config values (do NOT use 90s/1.3× — those are from the Forklift system):
fast   = { time = 300, multiplier = 1.2 }   -- ≤300s → 1.2×
normal = { time = 600, multiplier = 1.0 }   -- ≤600s → 1.0×
slow   = { time = 900, multiplier = 0.8 }   -- >900s → 0.8×
```

---

## Skill Bonus Formula

### `CalcBonus(citizenId, jobData)` → `{ paymentMult, speedBonus }`

```lua
function ProgressionService.CalcBonus(citizenId, jobData)
    local skills = ProgressionService.GetSkills(citizenId)
    -- GetSkills does a DB round-trip (MySQL.query.await) — acceptable, same as existing GetPaymentMultiplier
    local b = Config.Skills.BonusPerLevel   -- default 0.02

    local paymentMult = 1.0

    if (skills.distance or 0) > 0 and jobData.distance >= Config.Skills.DistanceThreshold then
        paymentMult = paymentMult + (skills.distance * b)
    end

    if (skills.valuable or 0) > 0 and jobData.basePayment >= Config.Skills.ValuableThreshold then
        paymentMult = paymentMult + (skills.valuable * b)
    end

    if (skills.fragile or 0) > 0 and (jobData.cargoIntegrity or 100) >= Config.Skills.FragileThreshold then
        paymentMult = paymentMult + (skills.fragile * b)
    end

    local speedBonus = (skills.speed or 0) * b

    return { paymentMult = paymentMult, speedBonus = speedBonus }
end
```

### Speed skill — applied to timeMult

Speed does not add to `paymentMult`. Instead, it offsets the `timeMult`:

```lua
local timeMult = GetTimeMultiplier(payload.deliveryTime) + bonus.speedBonus
```

Examples with Speed lv6 (`speedBonus = 0.12`):
- Fast (≤300s): `1.20 + 0.12 = 1.32`
- Normal (≤600s): `1.00 + 0.12 = 1.12`
- Slow (>900s): `0.80 + 0.12 = 0.92` (penalidade cai de -20% para -8%)

### Maximum theoretical bonus (all conditions met, all skills lv6)

```
paymentMult    = 1.0 + 0.12 + 0.12 + 0.12 = 1.36
timeMult       = 1.20 + 0.12 = 1.32
finalPayment   ≈ basePayment × 1.36 × 1.32 × companyMult × integrityMult ≈ 1.80× base
```

---

## Config Block

```lua
Config.Skills = {
    BonusPerLevel     = 0.02,   -- +2% por nível de skill ativo (ex: lv3 = +6%)
    DistanceThreshold = 10.0,   -- km mínimos para Distance ser ativada
    ValuableThreshold = 5000,   -- $ mínimos no basePayment para Valuable ser ativada
    FragileThreshold  = 85,     -- % mínimos de integridade entregue para Fragile ser ativada
}
```

---

## illegal_service.lua

`GetPaymentMultiplier(citizenId)` is currently called in `illegal_service.lua`. It must be replaced with `CalcBonus`. The `jobData` available in that context:

```lua
local bonus    = ProgressionService.CalcBonus(citizenId, {
    distance       = activeJob.distance,
    basePayment    = activeJob.base_payment,
    cargoIntegrity = payload.cargoIntegrity or 100,
})
local timeMult = GetTimeMultiplier(payload.deliveryTime) + bonus.speedBonus
```

---

## Data Flow — Job Completion

```
client: TriggerServerEvent('AUST_trucker:completeJob', {
    deliveryTime, plate, cargoIntegrity
})
  ↓
server/events.lua → JobService.Complete(src, payload)
  ├─ DB_GetActiveJobByPlayer(citizenId) → job { distance, base_payment }
  ├─ ProgressionService.CalcBonus(citizenId, {
  │       distance       = job.distance,
  │       basePayment    = job.base_payment,
  │       cargoIntegrity = payload.cargoIntegrity
  │  }) → { paymentMult, speedBonus }
  ├─ timeMult     = GetTimeMultiplier(payload.deliveryTime) + bonus.speedBonus
  ├─ finalPayment = floor(job.base_payment × bonus.paymentMult × timeMult × companyMult × integrityMult)
  ├─ Player.Functions.AddMoney('bank', finalPayment)
  └─ ProgressionService.GrantXP(src, citizenId, ...) ← ALREADY called, no change needed
        ↓ on level-up
        TriggerClientEvent('AUST_trucker:client:levelUp', src, { newLevel, newRank, levelsGained, skillPoints })
          ↓
        client/client.lua: handler already exists — sends:
            lib.notify(...)
            SendNUIMessage({ action = 'updateSkills', refreshStats = true })
          ↓
        useNUI.ts: case 'updateSkills' already handles refreshStats = true → calls getPlayerStats callback
```

**Note:** The `levelUp` → NUI flow is already fully implemented. No changes to `client/client.lua` or `useNUI.ts` are needed. Do NOT add a `case 'levelUp'` to `useNUI.ts` — it does not exist and is not sent.

---

## NUI Changes

### SkillTree.tsx — description strings only

Update the 4 hardcoded description strings to show real thresholds:

```tsx
// Before:
{ desc: '+2% p/ nível em rotas longas' }
{ desc: '+2% p/ nível em carga de valor' }
{ desc: '+2% p/ nível em carga delicada' }
{ desc: '+2% p/ nível no bônus de tempo' }

// After:
{ desc: '+2% p/ nível em rotas ≥10km' }
{ desc: '+2% p/ nível em jobs ≥$5.000' }
{ desc: '+2% p/ nível com integridade ≥85%' }
{ desc: '+2% p/ nível no multiplicador de tempo' }
```

**Known limitation:** The `totalBonus` badge in `SkillTree.tsx` (`Object.values(skills).reduce(sum + lvl) * 2`) still shows a flat total regardless of which job conditions are met. This is a UX inaccuracy introduced by contextual skills. Out of scope for this version — acceptable trade-off.

---

## What Already Exists (do not reimplement)

- `DB_GetSkills`, `DB_UpsertSkill`, `DB_SpendSkillPoint` — `database.lua`
- `ProgressionService.PurchaseSkill`, `ProgressionService.GetSkills`, `ProgressionService.GrantXP`
- `purchaseSkill`, `getSkills`, `getInitialData` (includes skills) — `callbacks.lua`
- `SkillTree.tsx`, `StatsPanel.tsx` — NUI components (no logic changes)
- `useStatsStore` with `setSkillLevel`, `setSkills`, `setStats`
- `trucker_player_skills`, `trucker_player_progression` — DB schema
- `levelUp` event handler in `client/client.lua` + `updateSkills` case in `useNUI.ts`

---

## Implementation Checklist

- [ ] Add `Config.Skills` block to `config/config.lua`
- [ ] Add `CalcBonus(citizenId, jobData)` to `progression_service.lua`
- [ ] Replace `GetPaymentMultiplier` with `CalcBonus` in `job_service.lua`; apply `speedBonus` to `timeMult`; preserve `companyMult` and `integrityMult`
- [ ] Replace `GetPaymentMultiplier` with `CalcBonus` in `illegal_service.lua`; apply `speedBonus` to `timeMult`; preserve `mult` (illegal type multiplier); do NOT add `companyMult` or `integrityMult` — they do not exist in the illegal path
- [ ] Remove `GetPaymentMultiplier` from `progression_service.lua` after both callers are migrated
- [ ] Update 4 description strings in `SkillTree.tsx`
- [ ] Update `CHANGELOG.md` and bump `fxmanifest.lua` version to `13.0.0`
