# Fase 5 — Anti-Cheat (v15.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar proteção anti-cheat server-authoritative cobrindo rate limiting por evento, validação de proximidade ao destino e velocidade máxima de viagem — finalizando completamente a Fase 5 do blueprint.

**Architecture:** Um novo serviço global `AntiCheatService` centraliza rate limiting (tabela in-memory `_cooldowns[citizenId][action] = expiry_timestamp`) e validação de entrega (posição do jogador via OneSync + elapsed server-side). `JobService.Complete` e `JobService.CompleteTheft` passam a usar elapsed **server-side** (`os.time() - accepted_at_unix`). Os handlers de `events.lua` delegam rate limiting para o serviço. `playerDropped` chama `CleanupPlayer` para evitar crescimento indefinido da tabela de cooldowns.

**Tech Stack:** Lua 5.4, FiveM OneSync (`GetPlayerPed`, `GetEntityCoords` server-side), QBX (`qbx_core`), sem novas queries MySQL.

---

## Contexto obrigatório para o implementador

### Stack e padrões críticos
- `lua54 'yes'` — cada arquivo é um chunk separado. Funções compartilhadas entre arquivos DEVEM ser globais (sem `local`).
- Globals server relevantes: `VP_Trucker`, `JobService`, `CompanyService`, `CargoTrackingService`, `ProgressionService`, `AntiCheatService` (novo)
- **NUNCA** chamar `MySQL.*` diretamente em services/events — usar funções `DB_*` de `server/database.lua`
- `accepted_at_unix` já é retornado por `DB_GetActiveJobByPlayer` como `UNIX_TIMESTAMP(accepted_at)`. É o timestamp server-side de quando o job foi aceito.
- `activeJob` em `JobService.Complete` é a **linha raw do DB** (retorno de `DB_GetActiveJobByPlayer`) — tem campos `dest_id`, `distance`, `accepted_at_unix`, `convoy_id`. Não confundir com o objeto enriquecido de `JobService.GetActiveByPlayer` (que usa `destCoords`/`destName`).
- `distance` no DB é em **quilômetros** (calculado como `sqrt(dx²+dy²) / 1000.0`). Ex: cross-map ≈ 10–15 km.

### Funcionamento do rate limiting
`_cooldowns[citizenId][action] = os.time() + cooldownSeconds`
Se `os.time() < expiry` → bloqueado. Ao liberar: escreve novo expiry. `CleanupPlayer` faz `_cooldowns[citizenId] = nil` (remove a key completa para evitar tabela esparsa).

### Comportamento de GetEntityCoords com OneSync
`GetPlayerPed(src)` + `GetEntityCoords(ped)` funcionam server-side com OneSync Infinity, mas podem retornar `vector3(0,0,0)` se a entidade não está roteada ao server no momento da chamada. **Sempre checar se coords == (0,0,0) e pular a validação nesses casos (fail-open).**

### Lógica do check de velocidade
O objetivo é **barrar teleporte** — rejeitar jobs completados em tempo impossível para a distância. A fórmula correta usa a **velocidade máxima possível** de um caminhão:

```
minSeconds = (distance_km / MaxSpeedKmh) * 3600
if elapsed < minSeconds → rejeitar (impossível chegar tão rápido)
```

Exemplo com `MaxSpeedKmh = 120` e dist = 10km → minSeconds = 300s.
Se o player entregou em 30s → impossível → bloqueado.
Se o player entregou em 350s → possível → liberado.

### Ordem de carregamento fxmanifest
```
server/services/cargo_tracking_service.lua   -- v14
server/services/anti_cheat_service.lua        -- v15: ANTES de job_service
server/services/job_service.lua
```

### Destinos
`Config.SecondaryIndustries` — lista com `id` (string) e `coords` (vector3). O campo `activeJob.dest_id` bate com `id`.

---

## Estrutura de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `config/config.lua` | Modificar | Adicionar `Config.AntiCheat` no final |
| `server/services/anti_cheat_service.lua` | Criar | Global `AntiCheatService` — rate limiting + validação de entrega |
| `fxmanifest.lua` | Modificar | Registrar `anti_cheat_service.lua` + version bump |
| `server/events.lua` | Modificar | Rate limiting em 6 handlers + CleanupPlayer no playerDropped |
| `server/services/job_service.lua` | Modificar | Elapsed server-side + ValidateDelivery em Complete e CompleteTheft |
| `CHANGELOG.md` | Modificar | Entrada v15.0.0 |

---

## Task 1: Config.AntiCheat ✅ (commit 2b1038c)

**Files:**
- Modify: `config/config.lua` (final do arquivo, após o bloco `Config.CargoTheft = { ... }`)

- [x] **Step 1: Adicionar bloco Config.AntiCheat**

Adicione no final de `config/config.lua`, após o bloco `Config.CargoTheft`:

```lua
-- ============================================================
-- ANTI-CHEAT (v15.0.0)
-- ============================================================

Config.AntiCheat = {
    Enabled = true,

    -- Raio máximo (metros) entre jogador e destino ao completar job.
    -- 80m cobre trailers compridos estacionados próximos à doca.
    DestinationRadius = 80.0,

    -- Velocidade MÁXIMA possível de um caminhão em km/h.
    -- Usado para calcular o tempo MÍNIMO de viagem.
    -- Se o player entregou mais rápido que isso → teleporte → bloqueado.
    -- 120 km/h é generoso (caminhões reais máx ~90 km/h no jogo).
    MaxSpeedKmh = 120.0,

    -- Cooldowns em segundos por evento (0 = sem cooldown)
    RateLimits = {
        acceptJob          = 3,
        completeJob        = 5,
        startCargoTheft    = 10,
        completeCargoTheft = 5,
        depositMoney       = 2,
        withdrawMoney      = 2,
    },
}
```

- [x] **Step 2: Verificar que o arquivo carrega sem erro**

`restart AUST_trucker` no txAdmin. Sem erros de syntax.

- [x] **Step 3: Commit**

```bash
git add config/config.lua
git commit -m "feat(anti-cheat): Config.AntiCheat block — rate limits + delivery validation params"
```

---

## Task 2: AntiCheatService ✅ (commit fe22b55)

**Files:**
- Create: `server/services/anti_cheat_service.lua`
- Modify: `fxmanifest.lua`

- [x] **Step 1: Criar server/services/anti_cheat_service.lua**

```lua
-- server/services/anti_cheat_service.lua
-- AntiCheatService — rate limiting por evento + validação de entrega
-- Sem dependências de outros services (carregado antes de job_service)

AntiCheatService = {}

-- _cooldowns[citizenId][action] = os.time() + cooldownSeconds
-- CleanupPlayer remove _cooldowns[citizenId] inteiramente para evitar tabela esparsa
local _cooldowns = {}

-- Verifica e aplica rate limit para uma ação.
-- Retorna true se permitido, false se bloqueado (cooldown ativo).
function AntiCheatService.RateLimit(citizenId, action)
    if not Config.AntiCheat.Enabled then return true end
    local cooldown = Config.AntiCheat.RateLimits[action]
    if not cooldown or cooldown <= 0 then return true end

    local now = os.time()
    _cooldowns[citizenId] = _cooldowns[citizenId] or {}
    local expiry = _cooldowns[citizenId][action]
    if expiry and now < expiry then
        if Config.Debug then
            print(('[AC] RateLimit bloqueou %s:%s (%.0fs restantes)'):format(
                citizenId, action, expiry - now))
        end
        return false
    end
    _cooldowns[citizenId][action] = now + cooldown
    return true
end

-- Valida se uma entrega é legítima.
-- activeJob: linha raw de DB_GetActiveJobByPlayer (campos: dest_id, distance, accepted_at_unix)
-- elapsedSeconds: os.time() - activeJob.accepted_at_unix (calculado pelo chamador)
-- src: player source (para GetPlayerPed + GetEntityCoords via OneSync)
-- Retorna: ok (bool), reason (string|nil)
function AntiCheatService.ValidateDelivery(src, citizenId, activeJob, elapsedSeconds)
    if not Config.AntiCheat.Enabled then return true, nil end

    -- 1. Velocidade máxima: rejeita se elapsed < tempo mínimo possível
    --    minSeconds = (distance_km / MaxSpeedKmh) * 3600
    local minSeconds = (activeJob.distance / Config.AntiCheat.MaxSpeedKmh) * 3600
    if elapsedSeconds < minSeconds then
        if Config.Debug then
            print(('[AC] ValidateDelivery FAIL velocidade: %s elapsed=%ds min=%ds dist=%.1fkm'):format(
                citizenId, elapsedSeconds, math.ceil(minSeconds), activeJob.distance))
        end
        return false, 'Velocidade de entrega inválida.'
    end

    -- 2. Proximidade ao destino (OneSync — pode retornar 0,0,0 se ped não roteado)
    local destCoords = nil
    for _, d in ipairs(Config.SecondaryIndustries) do
        if d.id == activeJob.dest_id then
            destCoords = d.coords
            break
        end
    end

    if destCoords then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pos = GetEntityCoords(ped)
            -- Falha de roteamento OneSync → coords (0,0,0): pular check (fail-open)
            if pos.x ~= 0.0 or pos.y ~= 0.0 or pos.z ~= 0.0 then
                local dist = #(pos - destCoords)
                if dist > Config.AntiCheat.DestinationRadius then
                    if Config.Debug then
                        print(('[AC] ValidateDelivery FAIL posição: %s dist_dest=%.1fm max=%.1fm'):format(
                            citizenId, dist, Config.AntiCheat.DestinationRadius))
                    end
                    return false, 'Você não está no destino de entrega.'
                end
            end
        end
    end

    return true, nil
end

-- Remove todos os cooldowns de um jogador ao desconectar.
-- IMPORTANTE: remove a key completa, não apenas as sub-keys, para evitar crescimento de tabela esparsa.
function AntiCheatService.CleanupPlayer(citizenId)
    _cooldowns[citizenId] = nil
end
```

- [x] **Step 2: Registrar no fxmanifest.lua**

Abra `fxmanifest.lua`. No bloco `server_scripts`, localize:
```lua
'server/services/cargo_tracking_service.lua',   -- v14: após forklift, antes de job_service
'server/services/job_service.lua',
```

Adicione a linha intermediária:
```lua
'server/services/cargo_tracking_service.lua',   -- v14: após forklift, antes de job_service
'server/services/anti_cheat_service.lua',        -- v15: após cargo_tracking, antes de job_service
'server/services/job_service.lua',
```

- [x] **Step 3: Verificar carregamento**

`restart AUST_trucker`. Execute no console server do txAdmin:
```
print(type(AntiCheatService))
```
Esperado: `table`

- [x] **Step 4: Commit**

```bash
git add server/services/anti_cheat_service.lua fxmanifest.lua
git commit -m "feat(anti-cheat): AntiCheatService — rate limiting + delivery validation (OneSync)"
```

---

## Task 3: Rate limiting em events.lua

**Files:**
- Modify: `server/events.lua`

O padrão de inserção é sempre o mesmo: após `local citizenId = Player.PlayerData.citizenid`, antes da lógica do handler.

- [ ] **Step 1: acceptJob**

Localize o handler `AUST_trucker:acceptJob`. Após `local citizenId = Player.PlayerData.citizenid`, adicione:

```lua
    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'acceptJob') then
        TriggerClientEvent('AUST_trucker:notify', src, 'Aguarde antes de aceitar outro job.', 'error')
        return
    end
```

- [ ] **Step 2: completeJob**

Localize o handler `AUST_trucker:completeJob`. Após `local citizenId = Player.PlayerData.citizenid`, adicione:

```lua
    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'completeJob') then return end
```

- [ ] **Step 3: depositMoney**

O handler `AUST_trucker:depositMoney` não declara `local citizenId` — vai direto de `local Player` para `local company`. O rate limit deve vir **logo após `if not Player then return end`**, ANTES da chamada `GetByMember` (evitar DB call desnecessária em spammer):

```lua
RegisterNetEvent('AUST_trucker:depositMoney', function(amount)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    -- v15: rate limit (antes de GetByMember para evitar DB call desnecessária)
    if not AntiCheatService.RateLimit(Player.PlayerData.citizenid, 'depositMoney') then
        TriggerClientEvent('AUST_trucker:notify', src, 'Aguarde antes de depositar novamente.', 'error')
        return
    end

    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return end
    -- ... restante inalterado
```

- [ ] **Step 4: withdrawMoney**

No handler `AUST_trucker:withdrawMoney`, após `local citizenId = Player.PlayerData.citizenid`:

```lua
    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'withdrawMoney') then
        TriggerClientEvent('AUST_trucker:notify', src, 'Aguarde antes de sacar novamente.', 'error')
        return
    end
```

- [ ] **Step 5: startCargoTheft**

No handler `AUST_trucker:startCargoTheft`, após `local citizenId = Player.PlayerData.citizenid`:

```lua
    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'startCargoTheft') then
        TriggerClientEvent('AUST_trucker:client:theftCancelled', src)
        return
    end
```

- [ ] **Step 6: completeCargoTheft**

No handler `AUST_trucker:completeCargoTheft`, após `local citizenId = Player.PlayerData.citizenid`:

```lua
    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'completeCargoTheft') then
        TriggerClientEvent('AUST_trucker:notify', src, 'Ação inválida.', 'error')
        return
    end
```

- [ ] **Step 7: playerDropped — CleanupPlayer**

No handler `playerDropped`, **dentro do bloco `if citizenid then` já existente** (que contém `ForkliftService.OnPlayerDropped`), adicione **após** `ForkliftService.OnPlayerDropped(citizenid)`:

```lua
    if citizenid then
        ForkliftService.OnPlayerDropped(citizenid)
        AntiCheatService.CleanupPlayer(citizenid)  -- v15: limpar cooldowns
        -- cargo cleanup existente abaixo — não alterar
        for plate, cargo in pairs(VP_Trucker.CargoByPlate) do
            ...
        end
    end
```

> **Atenção:** NÃO criar um segundo bloco `if citizenid then`. Inserir `AntiCheatService.CleanupPlayer` dentro do bloco existente, após `ForkliftService.OnPlayerDropped`.

- [ ] **Step 8: Testar rate limiting**

1. `restart AUST_trucker`
2. Aceitar job → imediatamente tentar aceitar outro
3. Esperado: notificação de erro na segunda tentativa dentro de 3s

- [ ] **Step 9: Commit**

```bash
git add server/events.lua
git commit -m "feat(anti-cheat): rate limiting em 6 eventos + CleanupPlayer no playerDropped"
```

---

## Task 4: Elapsed server-side + ValidateDelivery em JobService.Complete e CompleteTheft

**Files:**
- Modify: `server/services/job_service.lua`

Esta task corrige o padrão #8 ("tempo sempre server-side") em **dois lugares**:
1. `JobService.Complete` — entrega normal
2. `JobService.CompleteTheft` — entrega de carga roubada

E adiciona `AntiCheatService.ValidateDelivery` **apenas em `Complete`** (entrega de carga roubada não valida posição — o ladrão vai ao mesmo destino mas partindo de lugar diferente e sem tempo de referência confiável).

### Parte A — JobService.Complete

- [ ] **Step 1: Localizar o trecho de elapsed em JobService.Complete**

Abra `server/services/job_service.lua`. Localize `function JobService.Complete(src, payload)`.

Dentro da função, encontre o bloco do convoy early-return:
```lua
    -- Detectar se é job de convoy — delegar pagamento ao ConvoyService
    if activeJob.convoy_id and ConvoyService then
        ...
        return true, 0
    end

    -- Calcular multiplicador de tempo
    local elapsed    = payload.deliveryTime or 9999
```

- [ ] **Step 2: Inserir ValidateDelivery ANTES do convoy early-return**

Substitua **apenas** o trecho localizado no Step 1 pelo seguinte. O bloco de delegação illegal (`-- Fase 3B`) que existe **depois** do convoy branch **NÃO deve ser alterado** — preserve-o exatamente como está.

```lua
    -- v15: elapsed server-side (padrão #8 — nunca confiar no client para tempo)
    local elapsed = (activeJob.accepted_at_unix and activeJob.accepted_at_unix > 0)
                    and math.max(0, os.time() - activeJob.accepted_at_unix)
                    or  (tonumber(payload.deliveryTime) or 9999)

    -- v15: validação anti-cheat — executa ANTES do convoy branch
    -- (convoy jobs também passam pela validação de velocidade/posição)
    local acOk, acReason = AntiCheatService.ValidateDelivery(src, citizenId, activeJob, elapsed)
    if not acOk then
        TriggerClientEvent('AUST_trucker:notify', src, acReason or 'Entrega inválida.', 'error')
        return false
    end

    -- Detectar se é job de convoy — delegar pagamento ao ConvoyService
    if activeJob.convoy_id and ConvoyService then
        DB_CompleteJob(activeJob.id)
        DB_AddPlayerStats(citizenId, 0, activeJob.distance)
        ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, 1.0)
        ConvoyService.MemberComplete(src, activeJob.convoy_id, citizenId, activeJob)
        return true, 0
    end

    -- Calcular multiplicador de tempo (usa elapsed server-side já computado acima)
    local bonus    = Config.JobGeneration.timeBonus
    local timeMult = bonus.slow.multiplier
    if elapsed <= bonus.fast.time then
        timeMult = bonus.fast.multiplier
    elseif elapsed <= bonus.normal.time then
        timeMult = bonus.normal.multiplier
    end

    -- ⚠️ PRESERVAR INALTERADO: bloco de delegação illegal (Fase 3B, linhas ~323–326)
    -- O seguinte bloco já existe no arquivo e NÃO deve ser removido ou alterado:
    --
    --   -- Fase 3B: Delegar para IllegalService se job ilegal
    --   if activeJob.illegal_type and IllegalService then
    --       return IllegalService.OnComplete(src, activeJob, payload, timeMult)
    --   end
    --
    -- Ele deve continuar imediatamente após o bloco de timeMult acima.
    -- O restante da função (CalcBonus, companyMult, integrityMult, pagamento) também permanece inalterado.
```

> **Nota:** O fallback `tonumber(payload.deliveryTime)` é preservado para jobs criados antes da v15 que possam ter `accepted_at_unix = nil`. Em produção normal, `accepted_at_unix` sempre existe.

### Parte B — JobService.CompleteTheft

- [ ] **Step 3: Localizar o elapsed em CompleteTheft**

Localize `function JobService.CompleteTheft(src, cargoEntry, payload)`. Encontre:
```lua
    local elapsed  = tonumber(payload.deliveryTime) or 9999
```

- [ ] **Step 4: Substituir pelo elapsed server-side**

```lua
    -- v15: elapsed server-side (padrão #8)
    -- cargoEntry.theftStartedAt é o timestamp de início do roubo — usado como referência
    local elapsed = (cargoEntry.theftStartedAt and cargoEntry.theftStartedAt > 0)
                    and math.max(0, os.time() - cargoEntry.theftStartedAt)
                    or  (tonumber(payload.deliveryTime) or 9999)
```

> **Nota:** `theftStartedAt` é gravado em `CargoTrackingService.StartTheft` como `os.time()`. A validação de posição/distância **não** é aplicada em CompleteTheft (o ladrão parte de outro local sem destino inicial conhecido server-side).

- [ ] **Step 5: Verificar entrega normal funciona**

1. `restart AUST_trucker`
2. Aceitar job → dirigir ao destino → entregar
3. Esperado: pagamento correto, sem erros. Console com `Config.Debug = true` mostra o elapsed calculado.

- [ ] **Step 6: Verificar bloqueio de velocidade impossível (debug)**

Com `Config.Debug = true`:
1. Aceitar job curto (< 1km)
2. Teleportar ao destino via comando de dev imediatamente
3. Tentar completar job via menu
4. Esperado: notificação de erro, console loga `[AC] ValidateDelivery FAIL velocidade`

- [ ] **Step 7: Verificar bloqueio de posição**

1. Aceitar job
2. Aguardar tempo suficiente (> minSeconds)
3. Tentar completar em local errado via console client: `TriggerServerEvent('AUST_trucker:completeJob', {plate='TEST', deliveryTime=99999, cargoIntegrity=100})`
4. Esperado: notificação de erro, console loga `[AC] ValidateDelivery FAIL posição`

- [ ] **Step 8: Commit**

```bash
git add server/services/job_service.lua
git commit -m "feat(anti-cheat): elapsed server-side em Complete + CompleteTheft + ValidateDelivery gate"
```

---

## Task 5: CHANGELOG + version bump 15.0.0

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Atualizar CHANGELOG.md**

Adicione no topo, antes do bloco `## [14.0.0]`:

```markdown
## [15.0.0] — 2026-03-21 — Anti-Cheat (Fase 5 Completa)

### Added
- **AntiCheatService** (`server/services/anti_cheat_service.lua`)
  - `RateLimit(citizenId, action)` — cooldown in-memory por evento (`os.time() + cooldownSeconds`), configurável em `Config.AntiCheat.RateLimits`
  - `ValidateDelivery(src, citizenId, activeJob, elapsedSeconds)` — barras: velocidade impossível (`dist/MaxSpeedKmh*3600`) + proximidade ao destino via OneSync (`GetPlayerPed`+`GetEntityCoords`, fail-open se ped não roteado)
  - `CleanupPlayer(citizenId)` — remove entry completa de `_cooldowns` no `playerDropped`
- **Rate limiting** em 6 eventos: `acceptJob` (3s), `completeJob` (5s), `startCargoTheft` (10s), `completeCargoTheft` (5s), `depositMoney` (2s), `withdrawMoney` (2s)
- `Config.AntiCheat` em `config/config.lua` — `Enabled`, `DestinationRadius` (80m), `MaxSpeedKmh` (120), `RateLimits`

### Changed
- `server/services/job_service.lua`
  - `JobService.Complete` — elapsed agora calculado server-side (`os.time() - accepted_at_unix`), corrigindo padrão #8; `ValidateDelivery` executado antes do convoy branch
  - `JobService.CompleteTheft` — elapsed calculado via `os.time() - theftStartedAt` (server-side)
- `server/events.lua` — `playerDropped` chama `AntiCheatService.CleanupPlayer`
- `fxmanifest.lua` — `anti_cheat_service.lua` adicionado após `cargo_tracking_service.lua`

### Notes
- **Fase 5 do blueprint 100% concluída:** ADR ✅ Forklift ✅ Skills contextuais ✅ Cargo Theft ✅ Anti-Cheat ✅
```

- [ ] **Step 2: Atualizar versão no fxmanifest.lua**

Altere:
```lua
version '14.0.0'
```
para:
```lua
version '15.0.0'
```

- [ ] **Step 3: Commit e push**

```bash
git add CHANGELOG.md fxmanifest.lua
git commit -m "feat(anti-cheat): CHANGELOG + version bump 15.0.0 — Fase 5 completa"
git push origin HEAD
```

---

## Verificação Final

Após todas as tasks, confirme no jogo:

| Cenário | Esperado |
|---|---|
| Aceitar job duas vezes em 3s | 2ª tentativa bloqueada com notificação |
| Entregar job normalmente | Pagamento correto sem erro |
| Teleportar ao destino e completar em segundos | Bloqueado — `[AC] FAIL velocidade` no console |
| Completar job longe do destino | Bloqueado — `[AC] FAIL posição` no console |
| Reconectar após desconexão | Rate limit zerado (CleanupPlayer funcionou) |
| Entrega de carga roubada | Funciona normalmente (sem ValidateDelivery de posição) |

**Fase 5 completa:**
```
✅ ADR certs (v11)
✅ Forklift (v12)
✅ Skill tree contextual (v13)
✅ Vehicle-bound cargo + theft (v14)
✅ Anti-Cheat (v15)
```
