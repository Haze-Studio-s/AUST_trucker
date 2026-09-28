# AUST_trucker — Plano de Qualidade Geral (Audit Restante)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir todos os problemas pendentes identificados nos audits client e server para garantir zero memory leaks, zero globals desnecessários e robustez em restarts.

**Architecture:** Quatro fases independentes: (A) cleanup de zones/peds client restantes, (B) framework-decoupling no client, (C) audit do DB layer server, (D) verificação do fxmanifest. Cada fase produz código testável isoladamente.

**Tech Stack:** FiveM Lua 5.4, ox_target, ox_lib, oxmysql, QBX/QBCore/ESX (Framework abstraction v17)

---

## Estado Atual

### Já corrigido (sessão atual)
- ✅ `cargo_theft.client.lua` — `TheftAlertBlips` + remoção de `_G.PendingTheft*`
- ✅ `convoy.client.lua` — `Wait(0)` → `Wait(500)` no CB Radio thread
- ✅ `npc_driver.client.lua` — `onResourceStop` + stagger de peds
- ✅ `flatbed.client.lua` — `resourceStopping` guard no StateBagChangeHandler
- ✅ `repo.client.lua` — `onResourceStop` com `CleanupMission()`
- ✅ Server — `or {}` em todos DB calls, `FindPlayerByCitizenId`, Framework abstraction

### Pendente (este plano)
| Fase | Arquivo | Problema | Severidade |
|---|---|---|---|
| A | `illegal.client.lua` | `addSphereZone` sem `onResourceStop` | HIGH |
| A | `client.lua` | `bankerPed` ox_target não limpo no stop (declarado após o handler) | HIGH |
| B | `convoy.client.lua` | `QBX.PlayerData.citizenid` hardcoded → nil em ESX/QBCore | MEDIUM |
| C | `server/database.lua` | Verificar `MySQL.scalar` vs `MySQL.query` e `or {}` internos | MEDIUM |
| D | `fxmanifest.lua` | Confirmar load order server + client após v17 | LOW |

---

## Fase A — Cleanup de Zones e Peds Restantes

### Task 1: `illegal.client.lua` — onResourceStop para sphere zones

**Problema:** As zonas criadas com `addSphereZone` para contatos e entregas ilegais nunca são removidas quando o resource reinicia. ox_target não limpa automaticamente zonas de outros resources.

**Arquivo:** `client/illegal.client.lua`

- [ ] **Step 1: Adicionar `onResourceStop` ao final de `illegal.client.lua`**

```lua
-- ============================================================
-- CLEANUP no stop do resource
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, contact in ipairs(Config.IllegalJobs.contacts) do
        exports.ox_target:removeZone('illegal_contact_' .. contact.id)
    end
    for _, delivery in ipairs(Config.IllegalJobs.deliveries) do
        exports.ox_target:removeZone('illegal_delivery_' .. delivery.id)
    end
end)
```

Inserir após a última linha do arquivo (após o handler `AUST_trucker:client:seizureSuccess`).

- [ ] **Step 2: Verificar que os nomes batem com os usados em `addSphereZone`**

Confirmar que `'illegal_contact_' .. c.id` e `'illegal_delivery_' .. d.id` são os mesmos nomes passados em `addSphereZone` (linhas ~25 e ~94). Devem ser idênticos.

- [ ] **Step 3: Testar restart**

No jogo: `/restart AUST_trucker` enquanto próximo a uma zona de contato. Os prompts do ox_target devem desaparecer e não re-aparecer duplicados.

---

### Task 2: `client.lua` — bankerPed cleanup em onResourceStop

**Problema:** `local bankerPed = nil` é declarado na linha ~1437 — DEPOIS do `AddEventHandler('onResourceStop', ...)` na linha ~1399. Por isso, o handler existente não pode acessar `bankerPed` (Lua 5.4: upvalue não existia no momento do closure). O ped e seu ox_target vazam em restarts.

**Arquivo:** `client/client.lua`

- [ ] **Step 1: Localizar o final da seção BANKER NPC**

Encontrar a última linha relacionada ao banker (após `SpawnBankerNPC()` e callbacks de loan/repo). Visualmente: em torno da linha 1545+.

- [ ] **Step 2: Adicionar handler separado após a declaração de `bankerPed`**

Inserir ao final da seção BANKER NPC (após `SpawnBankerNPC` e `CreateThread`):

```lua
-- Cleanup do banker NPC (handler separado: bankerPed é declarado após o onResourceStop principal)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if bankerPed and DoesEntityExist(bankerPed) then
        exports.ox_target:removeLocalEntity(bankerPed)
        DeleteEntity(bankerPed)
        bankerPed = nil
    end
end)
```

Inserir logo após o `CreateThread(function() ... SpawnBankerNPC() ... end)` da linha ~1495.

- [ ] **Step 3: Verificar que não duplica cleanup do ped já existente**

O `onResourceStop` principal (linha ~1399) limpa `currentTrailer`, `blips.*`, `jobProgress.*`. Ele NÃO menciona `bankerPed`. O novo handler é aditivo, sem duplicata.

---

## Fase B — Framework Decoupling Client

### Task 3: `convoy.client.lua` — citizenid sem hardcode de QBX

**Problema:** `localCitizenId` é populado apenas via `QBX.PlayerData.citizenid` no evento `QBCore:Client:OnPlayerLoaded`. Em ESX, `QBX` é nil → `localCitizenId` nunca é definido → o jogador sempre vê um blip de si mesmo nos blips de convoy (bug visual menor, não crash).

**Arquivo:** `client/convoy.client.lua`

- [ ] **Step 1: Substituir o bloco de captura de citizenid**

Localizar (linhas ~27–32):
```lua
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    -- QBX popula PlayerData antes deste evento
    if QBX and QBX.PlayerData then
        localCitizenId = QBX.PlayerData.citizenid
    end
end)
```

Substituir por versão multi-framework:
```lua
-- Captura citizenid de forma compatível com QBX, QBCore e ESX
local function CaptureLocalCitizenId()
    if QBX and QBX.PlayerData then
        localCitizenId = QBX.PlayerData.citizenid
    elseif QBCore then
        local pd = QBCore.Functions.GetPlayerData()
        localCitizenId = pd and pd.citizenid
    elseif ESX then
        local pd = ESX.GetPlayerData()
        localCitizenId = pd and pd.identifier
    end
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', CaptureLocalCitizenId)
AddEventHandler('esx:playerLoaded', CaptureLocalCitizenId)
AddEventHandler('esx:setPlayerData', CaptureLocalCitizenId)

-- Tentar capturar imediatamente (player pode já estar carregado)
CreateThread(function()
    Wait(500)
    CaptureLocalCitizenId()
end)
```

- [ ] **Step 2: Verificar comportamento com `localCitizenId = nil`**

Na linha ~113: `if cid ~= localCitizenId then` — se `localCitizenId` for nil após 500ms, o blip do próprio jogador aparecerá. Aceitar como fallback gracioso (pior caso: blip self visível temporariamente).

---

## Fase C — Audit DB Layer Server

### Task 4: Verificar funções `DB_*` sem `or {}` internos

**Contexto:** As funções em `server/database.lua` retornam diretamente o resultado de `MySQL.query.await`. Os callers nos services já têm `or {}` (corrigido anteriormente). Mas alguns callbacks em `server/callbacks.lua` podem chamar DB_* diretamente sem guard.

**Arquivo:** `server/callbacks.lua`, `server/events.lua`

- [ ] **Step 1: Buscar todos os DB_* calls em callbacks.lua e events.lua sem `or {}`**

```bash
grep -n "DB_Get\|DB_Fetch\|DB_List" server/callbacks.lua server/events.lua
```

Para cada linha encontrada, verificar se o resultado é passado a `ipairs` sem `or {}`.

- [ ] **Step 2: Verificar uso correto de `MySQL.scalar` vs `MySQL.query` em database.lua**

Regra: `MySQL.scalar.await` = retorna valor único (número/string). `MySQL.single.await` = retorna uma row. `MySQL.query.await` = retorna array de rows.

Verificar que:
- `DB_UpdateCompanyBalance` → usa `MySQL.scalar.await('SELECT balance ...')` ✓
- `DB_AddCompanyXP` → usa `MySQL.single.await('SELECT company_xp, company_level ...')` ✓
- `DB_GetMembers` → usa `MySQL.query.await(...)` ✓

Se alguma função usa `MySQL.query.await` para valor único, corrigir para `MySQL.scalar.await` ou `MySQL.single.await`.

- [ ] **Step 3: Verificar `DB_GetRecruitingCompanies` no callback que a usa**

`CompanyService.GetRecruiting()` retorna `DB_GetRecruitingCompanies()` diretamente. O caller em `callbacks.lua` deve ter `or {}`:

```lua
local companies = CompanyService.GetRecruiting() or {}
```

Se ausente, adicionar.

---

## Fase D — Verificação do fxmanifest

### Task 5: Confirmar load order após v17

**Arquivo:** `fxmanifest.lua`

- [ ] **Step 1: Verificar dependências de server_scripts**

Confirmar a ordem atual:
```
server/framework.lua         ← DEVE ser primeiro (usado por todos)
server/schema.lua            ← DEVE ser segundo (MySQL.ready)
server/main.lua              ← DEVE ser terceiro (define VP_Trucker, inicia cache)
server/database.lua          ← DEVE vir após main.lua (usa MySQL global)
server/services/*.lua        ← Todos dependem de VP_Trucker e DB_*
server/exports.lua           ← Após services
server/callbacks.lua         ← Após exports
server/events.lua            ← Por último
```

- [ ] **Step 2: Verificar dependências de client_scripts**

Confirmar a ordem atual:
```
client/client.lua            ← Define VP_Trucker_ForkliftActive (global lido por forklift.client.lua)
client/hud.client.lua        ← Define SimState, dispara truckStateChanged
client/adr.client.lua        ← Independente
client/forklift.client.lua   ← Lê VP_Trucker_ForkliftActive de client.lua
client/cargo_theft.client.lua ← Independente
client/convoy.client.lua     ← Lê truckStateChanged de hud.client.lua (evento, não global direto)
client/illegal.client.lua    ← Independente
client/flatbed.client.lua    ← Define global Flatbed (usado por repo.client.lua)
client/repo.client.lua       ← Usa Flatbed de flatbed.client.lua
client/npc_driver.client.lua ← Independente
client/industries.client.lua ← Independente
client/industries_npc.client.lua ← Independente
```

- [ ] **Step 3: Confirmar que `server/services/repo_service.lua` está após `loan_service.lua`**

`RepoService` usa `LoanService` internamente. Confirmar no fxmanifest que `loan_service.lua` aparece ANTES de `repo_service.lua`. (Já verificado na v17 — confirmar não houve regressão.)

---

## Resumo de Arquivos Afetados

| Fase | Arquivo | Tipo de Mudança |
|---|---|---|
| A | `client/illegal.client.lua` | Adicionar `onResourceStop` |
| A | `client/client.lua` | Adicionar segundo `onResourceStop` para bankerPed |
| B | `client/convoy.client.lua` | Substituir bloco de citizenid QBX-only |
| C | `server/callbacks.lua` | Adicionar `or {}` onde necessário |
| D | `fxmanifest.lua` | Leitura/verificação apenas (sem alteração esperada) |

**Total estimado:** 5 tasks, ~30-45 minutos de execução.

---

## Critérios de Conclusão

- [ ] `/restart AUST_trucker` não deixa zones de ox_target órfãs para contatos/entregas ilegais
- [ ] `/restart AUST_trucker` deleta o banker NPC e remove seu ox_target
- [ ] Em servidor ESX, `convoy.client.lua` não trava e localCitizenId é populado
- [ ] Nenhum `ipairs(nil)` em callbacks.lua ao chamar DB_* com DB vazio
- [ ] Load order do fxmanifest confirmado correto
