# AUST_trucker — Fase 4: Progression System

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implementar o sistema de progressão completo: XP concedido em cada entrega, level-up automático com rank, árvore de skills (4 tipos × 6 níveis) com bônus aplicados no pagamento, e interface React de skill tree no painel Stats.

**Architecture:** Novo `ProgressionService` (`server/services/progression_service.lua`) encapsula toda lógica de XP/level/skill. Hook em `JobService.Complete()` aplica bônus de skill ao pagamento e concede XP. React `SkillTree.tsx` exibe e permite comprar skills com skill points. O DB já tem as tabelas `trucker_player_progression` e `trucker_player_skills` prontas.

**Tech Stack:** Lua 5.4, qbx_core, oxmysql, React 18, TypeScript 5, Zustand 4

---

## Contexto: o que já existe

```
trucker_player_progression   — citizenid, level, xp, rank, reputation, skill_points (DB ✅, lógica ❌)
trucker_player_skills        — citizenid, skill_type, skill_level (DB ✅, lógica ❌)
DB_GetPlayerStats()          — retorna linha completa com level/xp/rank (DB ✅)
DB_AddPlayerStats()          — só atualiza earnings/deliveries/distance (sem XP ❌)
Stats TypeScript             — só 3 campos (sem level/xp/rank/skill_points ❌)
StatsPanel.tsx               — só exibe 3 campos básicos ❌
JobService.Complete()        — pagamento sem bônus de skill, sem XP ❌
```

## File Map

**Criar:**
- `server/services/progression_service.lua` — XP, level-up, rank, skill tree

**Modificar:**
- `server/database.lua` — adicionar DB_AddXP, DB_SetLevelData, DB_GetSkills, DB_UpsertSkill, DB_SpendSkillPoint
- `server/services/job_service.lua` — hook XP + skill bonus em Complete()
- `server/callbacks.lua` — adicionar getSkills, purchaseSkill; adicionar skills ao getInitialData
- `server/events.lua` — nenhuma mudança necessária
- `fxmanifest.lua` — adicionar progression_service.lua na load order (ANTES de job_service)
- `client/client.lua` — handler RegisterNetEvent para level-up + SendNUIMessage
- `html/src/types/index.ts` — Skills type, atualizar Stats
- `html/src/hooks/useNUI.ts` — adicionar skills ao NUIMessage + handlers open/updateSkills/levelUp
- `html/src/stores/useStatsStore.ts` — adicionar skills state + setSkills + setSkillLevel
- `html/src/components/stats/StatsPanel.tsx` — adicionar level/xp/rank display + SkillTree

**Criar (React):**
- `html/src/components/progression/SkillTree.tsx` — grid 4×6 de skills com compra

---

## Task 1: DB helpers para XP e skills

**Files:**
- Modify: `server/database.lua` (após seção `PLAYER STATS`, linha ~213)

- [x] Abrir `server/database.lua`
- [x] Adicionar logo após `DB_AddPlayerStats()` (linha ~213):

```lua
-- ============================================================
-- PROGRESSION (XP, Level, Skills)
-- ============================================================

-- Adiciona XP e retorna o estado atual do jogador
function DB_AddXP(citizenId, xp)
    MySQL.update.await(
        'UPDATE trucker_player_progression SET xp = xp + ? WHERE citizenid = ?',
        { xp, citizenId }
    )
    return MySQL.single.await(
        'SELECT xp, level, rank, skill_points FROM trucker_player_progression WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
end

-- Atualiza level, rank e concede skill points (chamado no level-up)
function DB_SetLevelData(citizenId, level, rank, skillPointsToAdd)
    MySQL.update.await(
        [[UPDATE trucker_player_progression
          SET level = ?, rank = ?, skill_points = skill_points + ?
          WHERE citizenid = ?]],
        { level, rank, skillPointsToAdd, citizenId }
    )
end

-- Retorna todas as skills do jogador
function DB_GetSkills(citizenId)
    return MySQL.query.await(
        'SELECT skill_type, skill_level FROM trucker_player_skills WHERE citizenid = ?',
        { citizenId }
    )
end

-- Insere ou atualiza nível de skill
function DB_UpsertSkill(citizenId, skillType, newLevel)
    MySQL.insert.await(
        [[INSERT INTO trucker_player_skills (citizenid, skill_type, skill_level)
          VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE skill_level = VALUES(skill_level)]],
        { citizenId, skillType, newLevel }
    )
end

-- Gasta 1 skill point
function DB_SpendSkillPoint(citizenId)
    MySQL.update.await(
        'UPDATE trucker_player_progression SET skill_points = GREATEST(0, skill_points - 1) WHERE citizenid = ?',
        { citizenId }
    )
end
```

- [x] Verificar: `ensure AUST_trucker` no txAdmin console — sem erros

---

## Task 2: ProgressionService

**Files:**
- Create: `server/services/progression_service.lua`

- [x] Criar `server/services/progression_service.lua`:

```lua
-- AUST_trucker — server/services/progression_service.lua
-- Sistema de progressão: XP, levels, ranks, skill tree e bônus de pagamento

ProgressionService = {}

-- XP acumulado necessário para atingir cada nível
-- Nível 1 = início (0 XP). Para chegar ao nível N, precisa de LEVEL_THRESHOLDS[N] XP total.
local LEVEL_THRESHOLDS = {
    [2]  = 100,   [3]  = 250,   [4]  = 500,   [5]  = 900,
    [6]  = 1400,  [7]  = 2100,  [8]  = 3000,  [9]  = 4200,
    [10] = 5800,  [11] = 7800,  [12] = 10300, [13] = 13300,
    [14] = 16900, [15] = 21200, [16] = 26300, [17] = 32300,
    [18] = 39300, [19] = 47500, [20] = 57000, [21] = 68000,
    [22] = 80500, [23] = 94500, [24] = 110000,[25] = 127500,
    [26] = 147000,[27] = 168500,[28] = 192000,[29] = 218000,
    [30] = 246500,
}

-- Rank 1-6 baseado no nível (1-5 → rank 1, 6-10 → rank 2, ...)
local function CalcRank(level)
    return math.min(6, math.ceil(level / 5))
end

-- XP ganho por entrega = base_payment / 10, ajustado pelo multiplicador de tempo
local function CalcXP(basePayment, timeMultiplier)
    return math.max(5, math.floor((basePayment / 10) * timeMultiplier))
end

-- Calcula o nível correspondente ao XP total acumulado
local function CalcLevel(xp)
    local level = 1
    for lvl = 2, 30 do
        if (LEVEL_THRESHOLDS[lvl] or math.huge) <= xp then
            level = lvl
        else
            break
        end
    end
    return level
end

-- Concede XP ao jogador, processa level-ups, notifica o cliente
-- Returns: { xpGained, newLevel, levelsGained }
function ProgressionService.GrantXP(src, citizenId, basePayment, timeMultiplier)
    local xpGained = CalcXP(basePayment, timeMultiplier)
    local row = DB_AddXP(citizenId, xpGained)
    if not row then return { xpGained = xpGained, levelsGained = 0 } end

    local newLevel    = CalcLevel(row.xp)
    local oldLevel    = row.level
    local levelsGained = newLevel - oldLevel

    if levelsGained > 0 then
        local newRank = CalcRank(newLevel)
        DB_SetLevelData(citizenId, newLevel, newRank, levelsGained)
        TriggerClientEvent('AUST_trucker:client:levelUp', src, {
            newLevel     = newLevel,
            newRank      = newRank,
            levelsGained = levelsGained,
            skillPoints  = levelsGained,  -- 1 ponto por nível ganho
        })
    end

    return {
        xpGained     = xpGained,
        levelsGained = levelsGained,
        newLevel     = (levelsGained > 0) and newLevel or oldLevel,
    }
end

-- Retorna skills do jogador como mapa { [skill_type] = skill_level }
-- Tipos não adquiridos não aparecem (default 0 no cliente)
function ProgressionService.GetSkills(citizenId)
    local rows = DB_GetSkills(citizenId)
    local skills = {}
    for _, row in ipairs(rows) do
        skills[row.skill_type] = row.skill_level
    end
    return skills
end

-- Multiplicador de pagamento total das skills (cada nível = +2%)
-- Ex: distance 3 + valuable 2 = +10% → retorna 1.10
function ProgressionService.GetPaymentMultiplier(citizenId)
    local skills = ProgressionService.GetSkills(citizenId)
    local total = 0
    for _, level in pairs(skills) do
        total = total + level
    end
    return 1.0 + (total * 0.02)
end

-- Compra um nível de skill gastando 1 skill point
-- Retorna: true | false, motivo (string)
function ProgressionService.PurchaseSkill(src, citizenId, skillType)
    local validTypes = { distance = true, valuable = true, fragile = true, speed = true }
    if not validTypes[skillType] then
        return false, 'Tipo de skill inválido'
    end

    local stats = DB_GetPlayerStats(citizenId)
    if not stats or stats.skill_points < 1 then
        return false, 'Sem skill points disponíveis'
    end

    local currentSkills = ProgressionService.GetSkills(citizenId)
    local currentLevel  = currentSkills[skillType] or 0
    if currentLevel >= 6 then
        return false, 'Skill já está no nível máximo'
    end

    DB_UpsertSkill(citizenId, skillType, currentLevel + 1)
    DB_SpendSkillPoint(citizenId)
    return true
end
```

- [x] Verificar: arquivo salvo

---

## Task 3: Atualizar fxmanifest.lua

**Files:**
- Modify: `fxmanifest.lua`

> **ATENÇÃO:** `progression_service.lua` deve carregar ANTES de `job_service.lua` porque `Complete()` chama `ProgressionService.GetPaymentMultiplier()`.

- [x] Abrir `fxmanifest.lua`
- [x] Substituir o bloco `server_scripts`:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/economy_service.lua',
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',  -- NOVO: antes de job_service
    'server/services/job_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}
```

- [x] `ensure AUST_trucker` — verificar que `ProgressionService` não é nil

---

## Task 4: Hook em JobService.Complete()

**Files:**
- Modify: `server/services/job_service.lua` (função `JobService.Complete`, linha ~180)

- [x] Abrir `server/services/job_service.lua`
- [x] Substituir `JobService.Complete()` inteira:

```lua
-- Completa job, aplica bônus de skill e concede XP
-- payload = { deliveryTime = seconds, plate = "PLATE" }
function JobService.Complete(src, payload)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false end

    local citizenId = Player.PlayerData.citizenid
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return false end

    -- Calcular multiplicador de tempo
    local elapsed    = payload.deliveryTime or 9999
    local bonus      = Config.JobGeneration.timeBonus
    local timeMult   = bonus.slow.multiplier
    if elapsed <= bonus.fast.time then
        timeMult = bonus.fast.multiplier
    elseif elapsed <= bonus.normal.time then
        timeMult = bonus.normal.multiplier
    end

    -- Aplicar bônus de skills (cada nível de skill = +2%)
    local skillMult = ProgressionService.GetPaymentMultiplier(citizenId)
    local payment   = math.floor(activeJob.base_payment * timeMult * skillMult)

    -- Pagar jogador
    Player.Functions.AddMoney(Config.General.payment.currency, payment, 'aurp-trucker-job')

    -- Atualizar DB de stats e conceder XP
    DB_CompleteJob(activeJob.id)
    DB_AddPlayerStats(citizenId, payment, activeJob.distance)
    ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, timeMult)

    -- Evento externo (AUST_sala e outros recursos)
    local company = CompanyService.GetByMember(citizenId)
    TriggerEvent('AUST_trucker:jobCompleted', citizenId,
        company and company.id or nil,
        { jobId = activeJob.id, cargo = activeJob.cargo_item },
        payment)

    return true, payment
end
```

- [x] Verificar: completar entrega no servidor — sem erros no console

---

## Task 5: Callbacks de skills + atualizar getInitialData

**Files:**
- Modify: `server/callbacks.lua`

- [x] Abrir `server/callbacks.lua`
- [x] Substituir `lib.callback.register('AUST_trucker:getInitialData', ...)` para incluir skills:

```lua
lib.callback.register('AUST_trucker:getInitialData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    local citizenId = Player.PlayerData.citizenid

    return {
        jobs                = JobService.GetAvailable(),
        company             = CompanyService.GetByMember(citizenId),
        activeJob           = JobService.GetActiveByPlayer(citizenId),
        stats               = DB_GetPlayerStats(citizenId),
        recruitingCompanies = CompanyService.GetRecruiting(),
        skills              = ProgressionService.GetSkills(citizenId),  -- NOVO
    }
end)
```

- [x] Adicionar ao final do arquivo:

```lua
-- Skills do jogador
lib.callback.register('AUST_trucker:getSkills', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return {} end
    return ProgressionService.GetSkills(Player.PlayerData.citizenid)
end)

-- Comprar nível de skill
lib.callback.register('AUST_trucker:purchaseSkill', function(source, data)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, error = 'Jogador não encontrado' } end
    local ok, err = ProgressionService.PurchaseSkill(source, Player.PlayerData.citizenid, data.skillType)
    if ok then
        return { success = true }
    else
        return { success = false, error = err }
    end
end)
```

- [x] `ensure AUST_trucker` — sem erros

---

## Task 6: Handler de level-up no cliente

**Files:**
- Modify: `client/client.lua`

- [x] Abrir `client/client.lua` e localizar a seção de `RegisterNetEvent`
- [x] Adicionar handler para o evento `AUST_trucker:client:levelUp`:

```lua
RegisterNetEvent('AUST_trucker:client:levelUp', function(data)
    -- data = { newLevel, newRank, levelsGained, skillPoints }
    lib.notify({
        title       = 'Level Up!',
        description = ('Nível %d alcançado! Rank %d\n+%d Skill Point(s) disponíveis'):format(
            data.newLevel, data.newRank, data.skillPoints),
        type        = 'success',
        duration    = 8000,
    })
    -- Atualizar stats na NUI para refletir novo level/skill_points
    SendNUIMessage({
        action = 'updateSkills',
        -- O cliente React vai re-fetch stats para atualizar level/xp/skill_points
        refreshStats = true,
    })
end)
```

- [x] Verificar: no console do servidor, executar:
  ```
  TriggerClientEvent('AUST_trucker:client:levelUp', GetPlayers()[1], {newLevel=5,newRank=1,levelsGained=1,skillPoints=1})
  ```
  Deve exibir lib.notify no cliente

---

## Task 7: Atualizar tipos TypeScript

**Files:**
- Modify: `html/src/types/index.ts`

- [x] Abrir `html/src/types/index.ts`
- [x] Substituir a interface `Stats` e adicionar `Skills`:

```typescript
// Tipo de skill disponível
export type SkillType = 'distance' | 'valuable' | 'fragile' | 'speed'

// Mapa de skills (ausente = nível 0)
export interface Skills {
  distance: number
  valuable: number
  fragile:  number
  speed:    number
}

// Stats completas (reflete trucker_player_progression)
export interface Stats {
  citizenid:        string
  level:            number
  xp:               number
  rank:             number
  reputation:       number
  skill_points:     number
  total_earnings:   number
  total_deliveries: number
  total_distance:   number
}
```

- [x] Build: `cd html && npm run build` — deve dar erros de tipo em StatsPanel (esperado, corrige na Task 11)

---

## Task 8: Atualizar useNUI.ts

**Files:**
- Modify: `html/src/hooks/useNUI.ts`

- [x] Abrir `html/src/hooks/useNUI.ts`
- [x] Substituir o arquivo inteiro:

```typescript
import { useEffect } from 'react'
import { useAppStore } from '../stores/useAppStore'
import { useJobStore } from '../stores/useJobStore'
import { useCompanyStore } from '../stores/useCompanyStore'
import { useIndustryStore } from '../stores/useIndustryStore'
import { useStatsStore } from '../stores/useStatsStore'
import type { Job, ActiveJob, Company, Member, Vehicle, Industry, Stats, Skills } from '../types'

interface NUIMessage {
  action:              string
  jobs?:               Job[]
  company?:            Company | null
  activeJob?:          ActiveJob | null
  stats?:              Stats | null
  skills?:             Partial<Skills>
  recruitingCompanies?: Company[]
  members?:            Member[]
  vehicles?:           Vehicle[]
  industries?:         Record<string, Industry>
  refreshStats?:       boolean
}

export function useNUI() {
  const { setOpen }                                             = useAppStore()
  const { setJobs, setActiveJob }                              = useJobStore()
  const { setCompany, setRecruitingList, setMembers, setVehicles } = useCompanyStore()
  const { setIndustries }                                      = useIndustryStore()
  const { setStats, setSkills }                                = useStatsStore()

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
          // refreshStats = true indica para re-fetch stats frescos do servidor
          // (feito pelo SkillTree.tsx após purchaseSkill / pelo handler de levelUp)
          break
        case 'updateIndustries':
          setIndustries(event.data.industries ?? {})
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

- [x] Build sem erros de import

---

## Task 9: Atualizar useStatsStore.ts

**Files:**
- Modify: `html/src/stores/useStatsStore.ts`

- [x] Substituir `html/src/stores/useStatsStore.ts` inteiro:

```typescript
import { create } from 'zustand'
import type { Stats, Skills, SkillType } from '../types'

const DEFAULT_SKILLS: Skills = { distance: 0, valuable: 0, fragile: 0, speed: 0 }

interface StatsStore {
  stats:         Stats | null
  skills:        Skills
  setStats:      (stats: Stats | null) => void
  setSkills:     (skills: Partial<Skills>) => void
  setSkillLevel: (type: SkillType, level: number) => void
}

export const useStatsStore = create<StatsStore>((set) => ({
  stats:  null,
  skills: { ...DEFAULT_SKILLS },

  setStats:  (stats)  => set({ stats }),

  setSkills: (skills) => set((state) => ({
    skills: { ...state.skills, ...skills },
  })),

  setSkillLevel: (type, level) => set((state) => ({
    skills: { ...state.skills, [type]: level },
  })),
}))
```

- [x] Build sem erros

---

## Task 10: Criar SkillTree.tsx

**Files:**
- Create: `html/src/components/progression/SkillTree.tsx`

- [x] Criar pasta `html/src/components/progression/`
- [x] Criar `html/src/components/progression/SkillTree.tsx`:

```tsx
import { useStatsStore } from '../../stores/useStatsStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { SkillType, Stats } from '../../types'

const SKILL_META: Record<SkillType, { label: string; icon: string; desc: string }> = {
  distance: { label: 'Distância',  icon: '🛣️', desc: '+2% p/ nível em rotas longas'  },
  valuable: { label: 'Valioso',    icon: '💎', desc: '+2% p/ nível em carga de valor' },
  fragile:  { label: 'Frágil',     icon: '📦', desc: '+2% p/ nível em carga delicada' },
  speed:    { label: 'Velocidade', icon: '⚡', desc: '+2% p/ nível no bônus de tempo' },
}

const SKILL_TYPES: SkillType[] = ['distance', 'valuable', 'fragile', 'speed']
const MAX_LEVEL = 6

interface SkillTreeProps {
  onStatsRefresh: () => void
}

export function SkillTree({ onStatsRefresh }: SkillTreeProps) {
  const { stats, skills, setSkillLevel } = useStatsStore()
  const skillPoints = stats?.skill_points ?? 0

  const handlePurchase = async (skillType: SkillType) => {
    const currentLevel = skills[skillType]
    if (currentLevel >= MAX_LEVEL || skillPoints < 1) return

    const result = await fetchNUI<{ success: boolean; error?: string }>(
      'purchaseSkill',
      { skillType }
    )
    if (result.success) {
      setSkillLevel(skillType, currentLevel + 1)
      onStatsRefresh()  // re-fetch stats para atualizar skill_points no store
    } else {
      console.warn('[AUST_trucker] purchaseSkill failed:', result.error)
    }
  }

  const totalBonus = Object.values(skills).reduce((sum, lvl) => sum + lvl, 0) * 2

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">
          Árvore de Skills
        </span>
        <div className="flex items-center gap-2">
          {totalBonus > 0 && (
            <span className="text-[10px] text-emerald-400 font-medium">
              +{totalBonus}% bônus total
            </span>
          )}
          <span className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${
            skillPoints > 0
              ? 'bg-amber-500/20 text-amber-400'
              : 'bg-zinc-700 text-zinc-500'
          }`}>
            {skillPoints} ponto{skillPoints !== 1 ? 's' : ''}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-4 gap-2">
        {SKILL_TYPES.map((skillType) => {
          const meta         = SKILL_META[skillType]
          const level        = skills[skillType]
          const canUpgrade   = skillPoints > 0 && level < MAX_LEVEL
          const isMaxed      = level >= MAX_LEVEL

          return (
            <div
              key={skillType}
              className="bg-zinc-800/60 border border-zinc-700/50 rounded-lg p-2.5 flex flex-col gap-2"
            >
              {/* Cabeçalho */}
              <div className="text-center">
                <div className="text-xl leading-none mb-0.5">{meta.icon}</div>
                <div className="text-[11px] font-semibold text-zinc-200">{meta.label}</div>
                <div className="text-[9px] text-zinc-500 leading-tight mt-0.5">{meta.desc}</div>
              </div>

              {/* Barra de nível */}
              <div className="flex justify-center gap-0.5">
                {Array.from({ length: MAX_LEVEL }, (_, i) => (
                  <div
                    key={i}
                    className={`w-5 h-2 rounded-sm transition-colors ${
                      i < level
                        ? 'bg-amber-500'
                        : 'bg-zinc-700'
                    }`}
                  />
                ))}
              </div>

              {/* Status / botão */}
              <div className="text-center">
                {isMaxed ? (
                  <span className="text-[10px] text-emerald-400 font-semibold">
                    MÁXIMO (+{level * 2}%)
                  </span>
                ) : canUpgrade ? (
                  <button
                    onClick={() => handlePurchase(skillType)}
                    className="w-full text-[10px] bg-amber-500/20 hover:bg-amber-500/30 text-amber-400 py-1 rounded transition-colors font-medium"
                  >
                    Nível {level + 1} (+{(level + 1) * 2}%)
                  </button>
                ) : (
                  <span className="text-[10px] text-zinc-600">
                    {level > 0 ? `Nível ${level} (+${level * 2}%)` : 'Nenhum ponto'}
                  </span>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
```

- [x] Build: `npm run build` — sem erros

---

## Task 11: Atualizar StatsPanel.tsx

**Files:**
- Modify: `html/src/components/stats/StatsPanel.tsx`

- [x] Substituir `html/src/components/stats/StatsPanel.tsx` inteiro:

```tsx
import { useStatsStore } from '../../stores/useStatsStore'
import { fetchNUI } from '../../hooks/useNUI'
import { SkillTree } from '../progression/SkillTree'
import type { Stats } from '../../types'

const RANK_LABELS = ['', 'Aprendiz', 'Motorista', 'Veterano', 'Especialista', 'Elite', 'Lenda']

export function StatsPanel() {
  const { stats, setStats, setSkills } = useStatsStore()

  const handleStatsRefresh = async () => {
    const fresh = await fetchNUI<Stats>('getPlayerStats')
    if (fresh) setStats(fresh)
  }

  if (!stats) return (
    <div className="flex items-center justify-center h-full text-zinc-500">
      <p>Sem estatísticas ainda</p>
    </div>
  )

  const xpCurrent   = stats.xp ?? 0
  const level       = stats.level ?? 1
  const rank        = stats.rank ?? 1
  const skillPoints = stats.skill_points ?? 0

  // XP para o próximo nível (aproximação linear baseada na progressão do servidor)
  const XP_PER_LEVEL_APPROX = 150
  const xpToNext = Math.max(1, level * XP_PER_LEVEL_APPROX)
  const xpProgress = Math.min(100, Math.round((xpCurrent % xpToNext) / xpToNext * 100))

  return (
    <div className="space-y-4 h-full overflow-auto">
      {/* Header: Level + Rank */}
      <div className="flex items-center gap-4 bg-zinc-800/60 rounded-lg p-3 border border-zinc-700/50">
        <div className="text-center px-3">
          <p className="text-3xl font-bold text-amber-400">{level}</p>
          <p className="text-[10px] text-zinc-500 uppercase tracking-wider">Nível</p>
        </div>
        <div className="flex-1">
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs font-semibold text-zinc-300">
              {RANK_LABELS[rank] ?? `Rank ${rank}`}
            </span>
            <span className="text-[10px] text-zinc-500">
              {skillPoints > 0 && (
                <span className="text-amber-400 font-medium">{skillPoints} pts disponíveis · </span>
              )}
              {xpCurrent.toLocaleString()} XP
            </span>
          </div>
          {/* Barra de XP */}
          <div className="h-1.5 bg-zinc-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-amber-500 rounded-full transition-all duration-500"
              style={{ width: `${xpProgress}%` }}
            />
          </div>
        </div>
      </div>

      {/* Stats básicas */}
      <div className="grid grid-cols-3 gap-2">
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700 text-center">
          <p className="text-green-400 font-bold text-lg">${stats.total_earnings.toLocaleString()}</p>
          <p className="text-zinc-400 text-[10px] mt-0.5">Total Ganho</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700 text-center">
          <p className="text-blue-400 font-bold text-lg">{stats.total_deliveries}</p>
          <p className="text-zinc-400 text-[10px] mt-0.5">Entregas</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700 text-center">
          <p className="text-zinc-100 font-bold text-lg">{stats.total_distance.toFixed(0)} km</p>
          <p className="text-zinc-400 text-[10px] mt-0.5">Distância</p>
        </div>
      </div>

      {/* Skill Tree */}
      <div className="border-t border-zinc-700/50 pt-3">
        <SkillTree onStatsRefresh={handleStatsRefresh} />
      </div>
    </div>
  )
}
```

- [x] Build: `cd html && npm run build` — sem erros TypeScript
- [x] Checar saída em `html/assets/` — dois arquivos novos gerados

---

## Task 12: Atualizar client.lua — NUI callback purchaseSkill

**Files:**
- Modify: `client/client.lua`

> O React chama `fetchNUI('purchaseSkill', { skillType })` via HTTP, então precisa de um `RegisterNUICallback` correspondente no cliente Lua.

- [x] Abrir `client/client.lua` e localizar a seção de `RegisterNUICallback`
- [x] Adicionar:

```lua
RegisterNUICallback('purchaseSkill', function(data, cb)
    local result = lib.callback.await('AUST_trucker:purchaseSkill', false, data)
    cb(result or { success = false, error = 'Sem resposta do servidor' })
end)

RegisterNUICallback('getPlayerStats', function(data, cb)
    local result = lib.callback.await('AUST_trucker:getPlayerStats', false)
    cb(result or {})
end)
```

- [x] Verificar: `ensure AUST_trucker` — sem erros

---

## Task 13: Teste manual end-to-end

- [x] `ensure AUST_trucker` no txAdmin
- [x] Entrar no servidor, abrir NUI (`F5` ou keybind configurado)
- [x] Aba **Stats**: verificar que mostra nível, rank, barra de XP, stats básicas e SkillTree
- [x] Completar uma entrega → log no console do servidor deve mostrar XP concedido (`ProgressionService.GrantXP` — adicionar `print` temporário se necessário)
- [x] DB check: `SELECT citizenid, level, xp, rank, skill_points FROM trucker_player_progression;`
  - XP deve ter aumentado
- [x] Forçar level-up via console:
  ```
  -- MySQL: UPDATE trucker_player_progression SET xp = 100 WHERE citizenid = 'SEU_ID';
  -- Então completar outra entrega (qualquer XP adicional deve acionar level-up)
  ```
- [x] Verificar: lib.notify "Level Up!" aparece no cliente
- [x] Na aba Stats: skill point (badge âmbar) deve aparecer
- [x] Clicar botão de compra de skill → nível acende (dourado) e badge decrementa
- [x] DB check: `SELECT * FROM trucker_player_skills;` — registro inserido
- [x] Completar outra entrega → pagamento deve ter bônus de skill
  - Logar temporariamente: `print('[debug] skillMult:', skillMult, 'payment:', payment)` em job_service.lua

---

## Task 14: Commit

- [x] Remover quaisquer `print` de debug temporários
- [x] Build final: `cd html && npm run build`

```bash
git add server/services/progression_service.lua
git add server/database.lua
git add server/services/job_service.lua
git add server/callbacks.lua
git add fxmanifest.lua
git add client/client.lua
git add html/src/types/index.ts
git add html/src/hooks/useNUI.ts
git add html/src/stores/useStatsStore.ts
git add html/src/components/progression/SkillTree.tsx
git add html/src/components/stats/StatsPanel.tsx
git add html/assets/
git commit -m "feat: add progression system (XP, level-up, rank, skill tree)"
```

---

## Referência: fórmulas e constantes

| Conceito | Valor |
|---|---|
| XP por entrega | `floor(base_payment / 10 * time_multiplier)`, mínimo 5 |
| Multiplicador de tempo fast | 1.2× (≤5 min) |
| Multiplicador de tempo normal | 1.0× (≤10 min) |
| Multiplicador de tempo slow | 0.8× (>10 min) |
| Nível máximo | 30 |
| Rank fórmula | `ceil(level / 5)` → rank 1-6 |
| Skill types | distance, valuable, fragile, speed |
| Skill max level | 6 |
| Bônus por nível de skill | +2% do pagamento base |
| Skill points por level-up | 1 ponto por nível ganho |
| XP para level 2 | 100 XP total |
| XP para level 5 | 900 XP total |
| XP para level 10 | 5.800 XP total |
| XP para level 20 | 57.000 XP total |
| XP para level 30 | 246.500 XP total |
