# Fase 6 — Repo Man Avançado (v16.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar a Fase 6 do blueprint: colateral de veículo em empréstimos (6A), validação server-side de conclusão de missão repo + fix do blip de agente (6B), sincronização do flatbed entre clientes (6C), e garantir campos completos no payload NUI de ordens (6D).

**Architecture:** Mudança incremental em camadas existentes — schema DB → service layer → server events → client events. Nenhum arquivo novo; todos os padrões seguem os já estabelecidos no projeto (DB_* convention, lua54 chunk isolation, StateBag OneSync).

**Tech Stack:** FiveM (lua54), QBX/qbx_core, ox_lib, ox_inventory, ox_target, oxmysql, OneSync StateBags.

**Spec:** `docs/superpowers/specs/2026-03-21-fase6-repo-avancado-design.md`

---

## File Map

| Arquivo | Papel na tarefa |
|---|---|
| `import.sql` | Schema canônico — add `vehicle_plate` em `trucker_loans` (6A) |
| `sql/update_loan_collateral_v16.sql` | NEW — migration para servidores existentes (6A) |
| `server/database.lua` | DB_CreateLoan + queries de loan + DB_GetAvailableRepoOrders (6A, 6D) |
| `server/services/loan_service.lua` | LoanService.Create aceita vehiclePlate (6A) |
| `server/services/repo_service.lua` | GenerateFromLoan usa vehicle_plate se presente (6A) |
| `server/callbacks.lua` | createLoan extrai vehicle_plate do payload NUI (6A) |
| `server/events.lua` | completeRepoOrder valida proximidade ao impound (6B) |
| `client/repo.client.lua` | repoAgentUpdate com blip real; limpar em missionEnded (6B) |
| `client/flatbed.client.lua` | AddStateBagChangeHandler('attachedVehicle') para sync (6C) |
| `CHANGELOG.md` | entrada v16.0.0 |

---

## Task 1: Schema — vehicle_plate em trucker_loans (6A)

**Files:**
- Modify: `import.sql`
- Create: `sql/update_loan_collateral_v16.sql`

- [ ] **Step 1: Adicionar coluna em import.sql**

Em `import.sql`, localizar a definição de `trucker_loans` e adicionar `vehicle_plate` após `company_id`:

```sql
CREATE TABLE trucker_loans (
    id                  INT             AUTO_INCREMENT PRIMARY KEY,
    citizenid           VARCHAR(50)     NOT NULL,
    company_id          VARCHAR(50)     NULL,
    vehicle_plate       VARCHAR(20)     NULL,          -- ← NOVO (6A)
    amount              BIGINT          NOT NULL,
    interest_rate       FLOAT           NOT NULL DEFAULT 0.05,
    remaining_balance   BIGINT          NOT NULL,
    monthly_payment     BIGINT          NOT NULL,
    status              ENUM('active','paid','defaulted') DEFAULT 'active',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP,
    next_payment_at     DATETIME        NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_status    (status)
);
```

- [ ] **Step 2: Criar migration para servidores existentes**

Criar `sql/update_loan_collateral_v16.sql`:

```sql
-- AUST_trucker v16.0.0 — Migration: vehicle_plate collateral em trucker_loans
-- Execute apenas em servidores existentes (fresh install usa import.sql)
ALTER TABLE trucker_loans
    ADD COLUMN IF NOT EXISTS vehicle_plate VARCHAR(20) NULL AFTER company_id;
```

- [ ] **Step 3: Verificar SQL**

Executar no MySQL/MariaDB do servidor de dev:
```bash
mysql -u root -p trucker_db < sql/update_loan_collateral_v16.sql
mysql -u root -p trucker_db -e "DESCRIBE trucker_loans"
```
Esperado: coluna `vehicle_plate` aparece entre `company_id` e `amount`.

- [ ] **Step 4: Commit**

```bash
git add import.sql sql/update_loan_collateral_v16.sql
git commit -m "feat(6A): add vehicle_plate collateral column to trucker_loans"
```

---

## Task 2: DB layer — queries de loan incluem vehicle_plate (6A)

**Files:**
- Modify: `server/database.lua`

- [ ] **Step 1: Atualizar DB_CreateLoan**

Localizar `DB_CreateLoan` (~linha 351) e adicionar `vehiclePlate` como terceiro parâmetro:

```lua
function DB_CreateLoan(citizenId, companyId, vehiclePlate, amount, totalToPay, monthlyPayment, nextPaymentAt)
    return MySQL.insert.await(
        [[INSERT INTO trucker_loans
            (citizenid, company_id, vehicle_plate, amount, remaining_balance, monthly_payment, status, next_payment_at)
          VALUES (?, ?, ?, ?, ?, ?, 'active', FROM_UNIXTIME(?))]],
        { citizenId, companyId, vehiclePlate, amount, totalToPay, monthlyPayment, nextPaymentAt }
    )
end
```

- [ ] **Step 2: Atualizar DB_GetActiveLoan para incluir vehicle_plate no resultado**

```lua
function DB_GetActiveLoan(citizenId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
          FROM trucker_loans
          WHERE citizenid = ? AND company_id IS NULL AND status = 'active'
          LIMIT 1]],
        { citizenId }
    )
end
```
(O `SELECT *` já inclui `vehicle_plate` — nenhuma mudança necessária aqui se já usa `*`.)

- [ ] **Step 3: Verificar DB_GetOverdueLoans e DB_GetLoanById**

Confirmar que ambas usam `SELECT *` ou incluem `vehicle_plate`. Se usam `SELECT *`, nenhuma mudança necessária. Se listam colunas explícitas, adicionar `vehicle_plate`.

`DB_GetOverdueLoans` (linha ~391): usa `SELECT *` → OK.
`DB_GetLoanById` (linha ~495): usa `SELECT *` → OK.

- [ ] **Step 4: Atualizar DB_GetAvailableRepoOrders para incluir loan_id (6D)**

Localizar `DB_GetAvailableRepoOrders` (~linha 416) e adicionar `loan_id` ao SELECT:

```lua
function DB_GetAvailableRepoOrders()
    return MySQL.query.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status, loan_id,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders
          WHERE status = 'available' AND expires_at > NOW()
          ORDER BY created_at DESC]]
    )
end
```

- [ ] **Step 5: Commit**

```bash
git add server/database.lua
git commit -m "feat(6A,6D): DB_CreateLoan accepts vehiclePlate; repo orders expose loan_id"
```

---

## Task 3: LoanService.Create — parâmetro vehiclePlate (6A)

**Files:**
- Modify: `server/services/loan_service.lua`

- [ ] **Step 1: Adicionar vehiclePlate à assinatura de LoanService.Create**

Localizar `function LoanService.Create(src, citizenId, companyId, amount)` e adicionar `vehiclePlate`:

```lua
---Creates a new loan and credits the player.
---@param src number  player server id
---@param citizenId string
---@param companyId number|nil  nil for personal loans
---@param amount number
---@param vehiclePlate string|nil  optional collateral vehicle plate
---@return table  { success: boolean, loan?: table, reason?: string }
function LoanService.Create(src, citizenId, companyId, amount, vehiclePlate)
```

- [ ] **Step 2: Passar vehiclePlate para DB_CreateLoan**

Localizar a chamada `DB_CreateLoan(citizenId, companyId, amount, ...)` (~linha 48) e adicionar `vehiclePlate`:

```lua
local loanId = DB_CreateLoan(citizenId, companyId, vehiclePlate, amount, totalToPay, monthlyPayment, nextPaymentAt)
```

- [ ] **Step 3: Incluir vehicle_plate no retorno**

No bloco `local loan = { ... }` (~linha 56), adicionar:

```lua
local loan = {
    id                = loanId,
    amount            = amount,
    remaining_balance = totalToPay,
    monthly_payment   = monthlyPayment,
    next_payment_at   = nextPaymentAt,
    status            = 'active',
    is_company_loan   = companyId ~= nil,
    vehicle_plate     = vehiclePlate or nil,   -- ← NOVO
}
```

- [ ] **Step 4: Verificar que LoanService.CheckOverdue ainda funciona**

`CheckOverdue` chama `RepoService.GenerateFromLoan(loan)` onde `loan` vem de `DB_GetOverdueLoans()` que usa `SELECT *` — o `vehicle_plate` já virá preenchido automaticamente. Nenhuma mudança necessária aqui.

- [ ] **Step 5: Commit**

```bash
git add server/services/loan_service.lua
git commit -m "feat(6A): LoanService.Create accepts vehiclePlate collateral"
```

---

## Task 4: RepoService.GenerateFromLoan — usar colateral direto (6A)

**Files:**
- Modify: `server/services/repo_service.lua`

- [ ] **Step 1: Reescrever GenerateFromLoan para usar vehicle_plate se presente**

Localizar `function RepoService.GenerateFromLoan(loan)` (~linha 49) e substituir:

```lua
---Generates a repo order from a loan default.
---@param loan table  row from trucker_loans (remaining_balance = post-penalty)
function RepoService.GenerateFromLoan(loan)
    local vehiclePlate = loan.vehicle_plate
    local vehicleModel, vehicleValue

    if vehiclePlate then
        -- 6A: usar diretamente o veículo penhorado
        local vehRow = MySQL.single.await(
            'SELECT model FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
            { vehiclePlate }
        )
        vehicleModel = vehRow and string.lower(vehRow.model or '') or 'mule'
        vehicleValue = Config.RepoMan.VehicleValues[vehicleModel] or Config.RepoMan.DefaultVehicleValue
    else
        -- fallback: escolher veículo aleatório da frota da empresa
        local vehicles
        if loan.company_id then
            vehicles = DB_GetVehicles(loan.company_id)
        else
            local companyId = VP_Trucker.PlayerCompanies[loan.citizenid]
            if companyId then
                vehicles = DB_GetVehicles(companyId)
            end
        end

        if not vehicles or #vehicles == 0 then return end

        local vehicle = vehicles[math.random(#vehicles)]
        vehiclePlate  = vehicle.plate
        vehicleModel  = string.lower(vehicle.model or '')
        vehicleValue  = Config.RepoMan.VehicleValues[vehicleModel] or Config.RepoMan.DefaultVehicleValue
    end

    local payment   = math.floor(vehicleValue * PAYMENT_RATE * TYPE_MULTIPLIERS['pvp'])
    local expiresAt = os.time() + LOAN_ORDER_EXPIRY

    DB_InsertRepoOrder(
        vehiclePlate, vehicleModel, vehicleValue, loan.citizenid,
        'pvp', 'Desconhecida', payment, expiresAt, loan.id
    )
end
```

**IMPORTANTE:** A query `MySQL.single.await` dentro de `GenerateFromLoan` é uma chamada direta.
Seguindo a convenção DB_*, criar função auxiliar em `database.lua` ao invés de chamar MySQL diretamente:

Em `server/database.lua`, adicionar:

```lua
function DB_GetVehicleModel(plate)
    return MySQL.single.await(
        'SELECT model FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
end
```

E em `repo_service.lua` usar `DB_GetVehicleModel(vehiclePlate)`.

- [ ] **Step 2: Adicionar DB_GetVehicleModel em database.lua**

Adicionar após `DB_GetVehicleFuel` (~linha 507):

```lua
---Retorna o model de um veículo da empresa pelo plate.
function DB_GetVehicleModel(plate)
    return MySQL.single.await(
        'SELECT model FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
end
```

- [ ] **Step 3: Atualizar repo_service.lua para usar DB_GetVehicleModel**

No bloco `if vehiclePlate then`:

```lua
local vehRow     = DB_GetVehicleModel(vehiclePlate)
vehicleModel     = vehRow and string.lower(vehRow.model or '') or 'mule'
vehicleValue     = Config.RepoMan.VehicleValues[vehicleModel] or Config.RepoMan.DefaultVehicleValue
```

- [ ] **Step 4: Verificar in-game**

No servidor de dev, criar um empréstimo via NUI com `vehicle_plate = 'ABC1234'` (plate existente na `trucker_company_vehicles`). Esperar o ciclo de CheckOverdue (ou reduzir `Config.Loans.CheckInterval` para 10s no dev). Confirmar no console: `[AUST_trucker] Loan #X overdue — penalty applied.` e verificar que a `trucker_repo_orders` tem o `vehicle_plate = 'ABC1234'` correto.

- [ ] **Step 5: Commit**

```bash
git add server/database.lua server/services/repo_service.lua
git commit -m "feat(6A): GenerateFromLoan uses pledged vehicle_plate when present (DB_GetVehicleModel)"
```

---

## Task 5: Callback createLoan — passar vehicle_plate (6A)

**Files:**
- Modify: `server/callbacks.lua`

- [ ] **Step 1: Localizar callback createLoan**

Buscar `createLoan` em `server/callbacks.lua`. O callback atual deve ter assinatura similar a:

```lua
lib.callback.register('AUST_trucker:createLoan', function(source, data)
    ...
    local result = LoanService.Create(src, citizenId, companyId, data.amount)
    ...
end)
```

- [ ] **Step 2: Extrair e passar vehicle_plate**

```lua
lib.callback.register('AUST_trucker:createLoan', function(source, data)
    local src      = source
    local Player   = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid

    local companyId    = data.company_loan and VP_Trucker.PlayerCompanies[citizenId] or nil
    local vehiclePlate = type(data.vehicle_plate) == 'string' and data.vehicle_plate:upper() or nil

    -- Validar plate se fornecida (deve pertencer à empresa do jogador)
    if vehiclePlate and companyId then
        local vehicles = DB_GetVehicles(companyId) or {}
        local valid = false
        for _, v in ipairs(vehicles) do
            if v.plate == vehiclePlate then valid = true; break end
        end
        if not valid then
            return { success = false, reason = 'Veículo não pertence à sua empresa' }
        end
    end

    return LoanService.Create(src, citizenId, companyId, data.amount, vehiclePlate)
end)
```

**Nota:** Se o callback atual já valida player/citizenId de forma diferente, preservar a estrutura existente e apenas adicionar a extração de `vehicle_plate` e a chamada `LoanService.Create` com o novo parâmetro.

- [ ] **Step 3: Verificar in-game**

Via DevTools da NUI (F8 client console), enviar callback `createLoan` com `vehicle_plate = 'TESTPLATE'`. Verificar no MySQL: `SELECT vehicle_plate FROM trucker_loans WHERE citizenid = 'X' ORDER BY id DESC LIMIT 1` → deve retornar `'TESTPLATE'`.

- [ ] **Step 4: Commit**

```bash
git add server/callbacks.lua
git commit -m "feat(6A): createLoan callback extracts and validates vehicle_plate"
```

---

## Task 6: completeRepoOrder — validação server-side de proximidade (6B)

**Files:**
- Modify: `server/events.lua`

- [ ] **Step 1: Localizar handler completeRepoOrder (~linha 359)**

```lua
RegisterNetEvent('AUST_trucker:completeRepoOrder', function(orderId)
    local src    = source
    local result = RepoService.Complete(src, tonumber(orderId) or 0)
    if not result.success then
        lib.notify(src, { title = 'Repo Man', description = result.reason, type = 'error' })
    end
end)
```

- [ ] **Step 2: Adicionar validação de proximidade antes de RepoService.Complete**

```lua
RegisterNetEvent('AUST_trucker:completeRepoOrder', function(orderId)
    local src = source

    -- Validação server-side: jogador deve estar próximo ao impound
    local ped    = GetPlayerPed(src)
    if DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        local dist   = #(coords - Config.RepoMan.ImpoundLocation)
        if dist > Config.RepoMan.impoundRadius * 2 then
            lib.notify(src, {
                title       = 'Repo Man',
                description = 'Muito longe do impound',
                type        = 'error',
            })
            return
        end
    end

    local result = RepoService.Complete(src, tonumber(orderId) or 0)
    if not result.success then
        lib.notify(src, { title = 'Repo Man', description = result.reason, type = 'error' })
    end
end)
```

**Por que `impoundRadius * 2`:** O zone check client-side usa `impoundRadius` exato. O server usa `* 2` para dar tolerância de latência (jogador pode ter saído ligeiramente da zona antes do evento chegar ao servidor).

- [ ] **Step 3: Verificar in-game**

Tentar chamar `completeRepoOrder` via console do servidor sem estar próximo ao impound. Esperado: notificação "Muito longe do impound" e missão não completada.

- [ ] **Step 4: Commit**

```bash
git add server/events.lua
git commit -m "feat(6B): completeRepoOrder validates server-side proximity to impound"
```

---

## Task 7: repoAgentUpdate — fix stub com blip real (6B)

**Files:**
- Modify: `client/repo.client.lua`

- [ ] **Step 1: Localizar o stub (~linha 599)**

```lua
RegisterNetEvent('AUST_trucker:client:repoAgentUpdate')
AddEventHandler('AUST_trucker:client:repoAgentUpdate', function(data)
    -- Placeholder: atualizar posição do agent para o dono
    -- Para produção: manter handle do blip via AddBlipForCoord + SetBlipCoords
end)
```

- [ ] **Step 2: Adicionar variável local para o blip**

Adicionar junto às outras variáveis locais no topo do arquivo, após `local ActiveRepoMission = nil`:

```lua
local repoAgentBlip = nil   -- blip do agente visível apenas para o dono do veículo (6B)
```

- [ ] **Step 3: Substituir o stub pelo handler real**

```lua
RegisterNetEvent('AUST_trucker:client:repoAgentUpdate')
AddEventHandler('AUST_trucker:client:repoAgentUpdate', function(data)
    if not data or not data.coords then return end
    if not repoAgentBlip then
        repoAgentBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(repoAgentBlip, 1)
        SetBlipColour(repoAgentBlip, 1)   -- vermelho
        SetBlipFlashes(repoAgentBlip, true)
        SetBlipAsShortRange(repoAgentBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Agente Repo')
        EndTextCommandSetBlipName(repoAgentBlip)
    else
        SetBlipCoords(repoAgentBlip, data.coords.x, data.coords.y, data.coords.z)
    end
end)
```

- [ ] **Step 4: Limpar o blip em repoOwnerMissionEnded**

Localizar o handler `repoOwnerMissionEnded` (~linha 605) e adicionar cleanup do blip:

```lua
RegisterNetEvent('AUST_trucker:client:repoOwnerMissionEnded')
AddEventHandler('AUST_trucker:client:repoOwnerMissionEnded', function(data)
    -- Limpar blip do agente (6B)
    if repoAgentBlip and DoesBlipExist(repoAgentBlip) then
        RemoveBlip(repoAgentBlip)
        repoAgentBlip = nil
    end

    if data and data.recovered then
        lib.notify({ title = 'Veículo Repossessado',
            description = 'Seu veículo foi recolhido pelo agente', type = 'error' })
    else
        lib.notify({ title = 'Veículo Salvo',
            description = 'A tentativa de repossessão falhou', type = 'success' })
    end
end)
```

- [ ] **Step 5: Verificar in-game**

Iniciar missão pvp. O servidor chama `repoAgentPositionUpdate` periodicamente (~10s). Verificar que o dono do veículo vê um blip piscante vermelho com label "Agente Repo" apontando para o agente, e que o blip some quando a missão termina.

- [ ] **Step 6: Commit**

```bash
git add client/repo.client.lua
git commit -m "feat(6B): repoAgentUpdate creates/updates blip for vehicle owner; cleanup on mission end"
```

---

## Task 8: Flatbed sync multi-client via StateBagChangeHandler (6C)

**Files:**
- Modify: `client/flatbed.client.lua`

- [ ] **Step 1: Entender o problema**

Atualmente, `OriginAttach` chama `AttachEntityToEntity` apenas no entity owner.
Outros clientes próximos têm `attachedVehicle` StateBag atualizado, mas nenhum handler reage a essa mudança para chamar `AttachEntityToEntity` localmente.

- [ ] **Step 2: Adicionar StateBagChangeHandler ao final do arquivo**

Adicionar APÓS as definições de `Flatbed.*` (antes do último `end` ou no final do arquivo):

```lua
-- ============================================================
-- SYNC: reagir a mudanças de attachedVehicle para todos os clientes (6C)
-- ============================================================

AddStateBagChangeHandler('attachedVehicle', nil, function(bagName, _, value, _, _)
    -- Identificar a entidade flatbed pelo bagName
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or not DoesEntityExist(entity) then return end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return end

    -- Não processar se somos o entity owner (já fizemos o attach/detach localmente)
    if NetworkGetEntityOwner(entity) == PlayerId() then return end

    if value and value ~= -1 then
        -- Attach: outro cliente carregou um veículo no flatbed
        local targetVeh = NetToVeh(value)
        if DoesEntityExist(targetVeh) then
            AttachVehicleLocal(entity, targetVeh)
        end
    else
        -- Detach: veículo descarregado do flatbed
        -- Precisamos encontrar qual veículo estava attachado para detachar
        -- Iterar entidades próximas e verificar IsEntityAttachedToEntity
        local bedNetId = Entity(entity).state.bedProp
        if not bedNetId then return end
        local bedEnt = NetworkGetEntityFromNetworkId(bedNetId)
        if not DoesEntityExist(bedEnt) then return end

        local nearbyVehs = {}
        -- Verificar veículos que possam estar attachados ao bed
        local allVehs = GetGamePool('CVehicle')
        for _, veh in ipairs(allVehs) do
            if IsEntityAttachedToEntity(veh, bedEnt) then
                DetachVehicleLocal(veh)
                break
            end
        end
    end
end)
```

**Por que verificar `NetworkGetEntityOwner(entity) == PlayerId()`:** O entity owner já executou o attach/detach localmente via `OriginAttach`/`OriginDetach`. Sem esse guard, haveria double-attach.

**Performance note:** `GetGamePool('CVehicle')` é chamado apenas no caso de detach (que é raro). No caso de attach, usamos diretamente `NetToVeh(value)` — O(1).

- [ ] **Step 3: Verificar in-game (multi-client)**

Com dois clientes no mesmo servidor:
- Cliente A faz missão repo com flatbed
- Cliente B se aproxima
- Cliente A carrega o veículo alvo no flatbed
- Cliente B deve ver o veículo carregado no flatbed (não flutuando separado)

- [ ] **Step 4: Commit**

```bash
git add client/flatbed.client.lua
git commit -m "feat(6C): AddStateBagChangeHandler for attachedVehicle syncs flatbed across all clients"
```

---

## Task 9: CHANGELOG e fxmanifest (v16.0.0)

**Files:**
- Modify: `CHANGELOG.md`
- Verify: `fxmanifest.lua` (nenhum arquivo novo — não requer mudança)

- [ ] **Step 1: Adicionar entrada v16.0.0 no CHANGELOG**

No topo do changelog, após o cabeçalho, adicionar:

```markdown
## [16.0.0] — 2026-03-21 — Repo Man Avançado (Fase 6)

### Added
- **6A — Colateral de veículo em empréstimos** (`trucker_loans.vehicle_plate VARCHAR(20) NULL`)
  - `LoanService.Create` aceita `vehiclePlate` opcional — penhor de veículo específico ao criar empréstimo
  - `RepoService.GenerateFromLoan`: se `loan.vehicle_plate` → usa direto via `DB_GetVehicleModel`; fallback: veículo aleatório da empresa (comportamento anterior)
  - `DB_GetAvailableRepoOrders` expõe `loan_id` para NUI diferenciar ordens de empréstimo vs. NPC
  - Migration: `sql/update_loan_collateral_v16.sql`
- **6B — Server-side validation + owner blip**
  - `completeRepoOrder` server event valida `dist <= impoundRadius * 2` via `GetEntityCoords(GetPlayerPed(src))`
  - `client/repo.client.lua`: `repoAgentUpdate` agora cria/atualiza blip vermelho piscante ("Agente Repo") para o dono; limpo em `repoOwnerMissionEnded`
- **6C — Flatbed sync multi-client**
  - `AddStateBagChangeHandler('attachedVehicle')` em `flatbed.client.lua` propaga attach/detach para todos os clientes via OneSync StateBag
  - Guard: entity owner ignorado (já processou localmente)

### Changed
- `server/database.lua`: `DB_CreateLoan` novo param `vehiclePlate`; `DB_GetAvailableRepoOrders` inclui `loan_id`; nova `DB_GetVehicleModel`
- `server/services/loan_service.lua`: `LoanService.Create` novo param `vehiclePlate`
- `server/services/repo_service.lua`: `GenerateFromLoan` reescrito com branch colateral vs. fallback
- `server/callbacks.lua`: `createLoan` extrai e valida `vehicle_plate`
- `server/events.lua`: `completeRepoOrder` valida proximidade
- `client/repo.client.lua`: stub `repoAgentUpdate` substituído; `repoOwnerMissionEnded` limpa blip
- `client/flatbed.client.lua`: StateBagChangeHandler para sync

### Notes
- **Fase 6 do blueprint**: 6A ✅ 6B ✅ 6C ✅ 6D ✅ (loan_id já exposto no payload existente)
```

- [ ] **Step 2: Verificar fxmanifest**

Confirmar que nenhum novo arquivo foi criado que precise ser registrado. Os arquivos modificados já estão na lista. Nenhuma mudança necessária.

- [ ] **Step 3: Commit final**

```bash
git add CHANGELOG.md
git commit -m "chore: v16.0.0 changelog — Fase 6 Repo Man Avancado complete"
```

---

## Verificação Final

- [ ] Reiniciar resource: `restart AUST_trucker` no txAdmin console
- [ ] Verificar console sem erros Lua
- [ ] Teste 6A: criar empréstimo com plate válida → vencer no ciclo → confirmar `trucker_repo_orders.vehicle_plate` correto
- [ ] Teste 6B: aceitar ordem PvP → dono recebe blip de agente → agente entrega → blip some
- [ ] Teste 6B: tentar `completeRepoOrder` longe do impound → receber notificação de erro
- [ ] Teste 6C: dois clientes → Agent carrega veículo no flatbed → segundo cliente vê o veículo carregado
- [ ] Teste 6D: `BroadcastAvailableOrders` → verificar que `loan_id` chega na NUI para ordens de empréstimo
