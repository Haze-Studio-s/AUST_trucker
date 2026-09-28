# Repo Man — Backend & NUI — Design Spec

**Fase:** 6 — Repo Man (Sub-spec 1: Backend & NUI)
**Versão alvo:** 6.0.0
**Data:** 2026-03-19

---

## Objetivo

Implementar o pipeline server-side e NUI do sistema Repo Man: geração de ordens de repossessão (por inadimplência de loan e por pool NPC), `RepoService` global, tipo de empresa `repo`, e aba "Missões Repo" na NUI. A gameplay client-side (flatbed, missões in-world) é coberta pela Sub-spec 2.

---

## Arquitetura

### Fluxo Principal

```
[Loan default — CheckOverdue]
  → RepoService.GenerateFromLoan(loan)
    → DB_GetVehicles(companyId) ou busca empresa do owner pessoal
    → DB_InsertRepoOrder(...)         ← vehicle_owner_citizenid = citizenid real, loanId = loan.id
    → mission_type = 'pvp'
    → INSERT IGNORE (deduplicado via UNIQUE KEY uq_loan_id)

[NPC Pool Thread — a cada PoolInterval]
  → DB_CountAvailableNpcOrders()     ← conta apenas ordens com vehicle_owner_citizenid IS NULL
  → se count < MaxNpcOrders: RepoService.GenerateNPC()
    → sorteia veículo de Config.RepoMan.NpcVehicles
    → sorteia zona de Config.RepoMan.NpcZones
    → DB_InsertRepoOrder(...)         ← vehicle_owner_citizenid = NULL, loanId = nil
    → vehicle_plate gerada como UUID curto único (evita duplicatas de modelo/zona)
    → mission_type = 'simple' ou 'npc_hostile' (peso configurável)

[NUI — empresa repo — aba "Missões"]
  → fetchNUI('getRepoOrders')
    → lib.callback.await('AUST_trucker:getRepoOrders')
      → DB_GetAvailableRepoOrders()
      → retorna lista para NUI

[Aceitar ordem]
  → fetchNUI('acceptRepoOrder', { orderId })
    → lib.callback.await('AUST_trucker:acceptRepoOrder')
      → RepoService.Accept(src, orderId)
        → valida empresa repo + sem missão ativa
        → DB_AcceptRepoOrder(orderId, citizenId, companyId)
          ← armazena company_id do agente na ordem para uso em Complete
        → TriggerClientEvent('AUST_trucker:client:startRepoMission', src, orderData)
        → retorna { success, order }

[Completar missão — Sub-spec 2 dispara]
  → TriggerServerEvent('AUST_trucker:completeRepoOrder', orderId)
    → RepoService.Complete(src, orderId)
      → DB_GetRepoOrderById(orderId) — valida assigned_citizenid + status='active'
      → se ordem não encontrada ou expirada: retorna erro graciosamente (sem crash)
      → DB_CompleteRepoOrder(orderId)
      → paga agente (bank) + empresa via order.company_id (já armazenado na ordem)
      → se loan_id != nil e loan ainda 'active': abate vehicle_value do loan
        (nota: o saldo do loan passado para GenerateFromLoan já é o saldo pós-multa de 15%)
      → se vehicle_owner_citizenid != nil e jogador online: lib.notify
      → TriggerClientEvent('AUST_trucker:client:repoMissionComplete', src, { payment })

[Falhar missão — Sub-spec 2 dispara]
  → TriggerServerEvent('AUST_trucker:failRepoOrder', orderId)
    → RepoService.Fail(src, orderId)
      → DB_UpdateRepoOrderStatus(orderId, 'available', nil, nil)
        ← limpa assigned_citizenid E company_id
      → sem penalidade ao agente

[Thread CheckExpired — a cada 5 min]
  → DB_ExpireRepoOrders()            ← WHERE expires_at < NOW() AND status IN ('available','active')
```

---

## Regras de Negócio

### Empresa Repo Man

| Regra | Detalhe |
|---|---|
| Criação | Jogador escolhe tipo ('logistics' ou 'repo') ao criar empresa — enviado no mesmo evento fire-and-forget `AUST_trucker:createCompany` com campo extra `companyType` |
| Imutabilidade | Tipo não pode ser alterado após criação |
| Roles | Owner → Manager → Driver (mesma hierarquia; "Driver" = "Agent" no contexto repo) |
| Jobs de entrega | Bloqueados para empresas repo |
| Ordens repo | Bloqueadas para empresas logistics |
| Empréstimo, garagem, frota | Funcionam para ambos os tipos |
| Cache in-memory | `VP_Trucker.Companies[id].company_type` deve ser populado tanto na criação quanto no carregamento — necessário para `RepoService.Accept` validar sem hit no DB |

### Geração de Ordens — Loan Default

- Chamado em `LoanService.CheckOverdue()` após aplicar a multa de 15%
- O `loan.remaining_balance` passado para `GenerateFromLoan` já é o saldo **pós-penalidade**; o abate em `Complete` ocorrerá sobre esse valor atualizado
- **Loan empresarial**: busca veículos da empresa inadimplente (`DB_GetVehicles(companyId)`). Se houver pelo menos 1, escolhe aleatoriamente
- **Loan pessoal**: busca empresa onde `owner_citizenid = citizenid` do inadimplente. Se existir e tiver veículo, escolhe aleatoriamente
- Se nenhum veículo encontrado: não gera repo order (a multa de 15% já foi aplicada)
- `vehicle_value`: lookup em `Config.RepoMan.VehicleValues[model]`; default `Config.RepoMan.DefaultVehicleValue` se modelo não mapeado
- `mission_type = 'pvp'` (dono real pode resistir)
- `expires_at = os.time() + Config.RepoMan.LoanOrderExpiry` (ex: 86400 s = 24h)
- `INSERT IGNORE` via `UNIQUE KEY uq_loan_id (loan_id)` — sem duplicatas entre ciclos de CheckOverdue para o mesmo loan

### Geração de Ordens — Pool NPC

- Thread conta apenas ordens NPC disponíveis via `DB_CountAvailableNpcOrders()` (`WHERE vehicle_owner_citizenid IS NULL AND status='available'`) — ordens de loan não contam para o limite
- Gera novas ordens enquanto `count < Config.RepoMan.MaxNpcOrders`
- `vehicle_plate` gerada como string única por ordem (ex: `'NPC-' .. math.random(100000,999999)`) — evita colisão entre ordens do mesmo modelo
- Sorteia veículo de `Config.RepoMan.NpcVehicles` (lista: `{ model, label, value }`)
- Sorteia zona de `Config.RepoMan.NpcZones` (lista: `{ name, coords, radius }`)
- `mission_type`: sorteio ponderado por `Config.RepoMan.NpcMissionWeights = { simple=70, npc_hostile=30 }`
- `vehicle_owner_citizenid = NULL`, `loanId = nil`
- `expires_at = os.time() + Config.RepoMan.NpcOrderExpiry` (ex: 7200 s = 2h)

### Pagamento

```
payment = math.floor(vehicle_value * PaymentRate * TypeMultiplier)
companyFee = math.floor(payment * CompanyFeeRate)
```

| mission_type | TypeMultiplier |
|---|---|
| simple | 1.0 |
| npc_hostile | 1.5 |
| pvp | 2.0 |
| stealth | 2.5 |

- `PaymentRate = Config.RepoMan.PaymentRate` (default: 0.15 — 15% do valor)
- Agente recebe `payment` em bank
- Empresa recebe `companyFee` via `DB_UpdateCompanyBalance(order.company_id, companyFee)` — `company_id` armazenado na ordem no momento do Accept

### Abate no Loan

Se o loan que gerou a ordem ainda estiver ativo (`status='active'`) quando a missão for completada:
- `newBalance = math.max(0, remaining_balance - vehicle_value)`
- Se `newBalance = 0`: `newStatus = 'paid'`, `nextPaymentAt = nil`
- Se `newBalance > 0`: `newStatus = 'active'`, `nextPaymentAt = loan.next_payment_at_unix + Config.Loans.InstallmentDays * 86400` (`next_payment_at_unix` = alias unix retornado por `DB_GetLoanById`)
- `DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)`
- Se jogador do loan estiver online: `lib.notify` informando abate

### Aceitação de Ordem

- Jogador deve ser membro de empresa `company_type = 'repo'` (validado via cache `VP_Trucker.Companies`)
- Jogador não pode ter outra ordem com `status='active'` e `assigned_citizenid = citizenId`
- Ordem deve ter `status = 'available'`
- Ao aceitar: `status = 'active'`, `assigned_citizenid = citizenId`, `company_id = companyId` (da empresa atual do agente)

### Resiliência em Complete

`RepoService.Complete` deve buscar a ordem por id **antes** de agir. Se a ordem não for encontrada (expirada pela thread ou não existe), retorna `{ success=false, reason='Ordem não encontrada' }` sem crash ou pagamento duplicado.

---

## Estrutura de Arquivos

### Novos arquivos

| Arquivo | Responsabilidade |
|---|---|
| `server/services/repo_service.lua` | `RepoService` global — GenerateFromLoan, GenerateNPC, Accept, Complete, Fail, CheckExpired |
| `html/src/types/repo.ts` | Interfaces TypeScript `RepoOrder`, `RepoMissionType`, `RepoOrderStatus` |
| `html/src/stores/useRepoStore.ts` | Zustand store — `repoOrders`, `activeRepoOrder` |
| `html/src/components/repo/RepoPanel.tsx` | Lista de ordens + ordem ativa |
| `html/src/components/repo/RepoCard.tsx` | Card individual de ordem disponível |

### Arquivos modificados

| Arquivo | Mudança |
|---|---|
| `config/config.lua` | Adiciona bloco `Config.RepoMan` |
| `import.sql` | Adiciona coluna `loan_id INT NULL` + `UNIQUE KEY uq_loan_id (loan_id)` ao CREATE TABLE `trucker_repo_orders` |
| `server/database.lua` | 9 novas funções `DB_Repo*` + `DB_GetLoanById`; atualiza `DB_CreateCompany` para aceitar `companyType` |
| `server/services/company_service.lua` | `CompanyService.Create` aceita `companyType`, passa para `DB_CreateCompany`, inclui `company_type` no cache `VP_Trucker.Companies[id]`; `CompanyService.Load` garante que `company_type` é populado no cache na inicialização |
| `server/services/loan_service.lua` | `CheckOverdue` chama `RepoService.GenerateFromLoan(loan)` após aplicar multa |
| `server/events.lua` | Eventos `completeRepoOrder`, `failRepoOrder`; `createCompany` aceita `companyType` no payload |
| `server/callbacks.lua` | Callbacks `getRepoOrders`, `acceptRepoOrder`; `getInitialData` inclui `repoOrders` e `activeRepoOrder` para empresas repo |
| `fxmanifest.lua` | Adiciona `repo_service.lua` na load order (após `loan_service.lua`) |
| `html/src/types/index.ts` | Adiciona `company_type: 'logistics' \| 'repo'` à interface `Company`; adiciona `'missions'` ao type `TabName` |
| `html/src/hooks/useNUI.ts` | Casos `updateRepoOrders`, `startRepoMission`; `open` case hidrata `repoOrders` e `activeRepoOrder`; `NUIMessage` inclui campos repo |
| `html/src/components/company/CompanyPanel.tsx` | Formulário de criação inclui seleção de tipo de empresa |
| `client/client.lua` | 3 `RegisterNetEvent` handlers (`updateRepoOrders`, `startRepoMission`, `repoMissionComplete`) + 2 `RegisterNUICallback` handlers (`acceptRepoOrder` via lib.callback; `failRepoOrder` fire-and-forget) |
| `html/src/App.tsx` (ou componente de nav) | Aba "Jobs"/"Missões": renderiza `<JobsPanel>` se `company_type === 'logistics'`, `<RepoPanel>` se `'repo'` |

---

## Schema — `import.sql`

> **Nota:** A coluna `company_type ENUM('logistics','repo') NOT NULL DEFAULT 'logistics'` em `trucker_companies` já existe no schema original do projeto (fase anterior). Nenhuma migração é necessária para essa coluna — `DB_CreateCompany` e `SELECT *` já a retornam corretamente.

Adicionar à definição de `trucker_repo_orders`:

```sql
CREATE TABLE trucker_repo_orders (
    id                      INT             AUTO_INCREMENT PRIMARY KEY,
    company_id              VARCHAR(50)     NULL,       -- empresa do agente (preenchido no Accept)
    vehicle_plate           VARCHAR(20)     NOT NULL,
    vehicle_owner_citizenid VARCHAR(50)     NULL,       -- NULL = dono NPC
    vehicle_model           VARCHAR(50)     NOT NULL,
    vehicle_value           BIGINT          NOT NULL,
    mission_type            ENUM('simple','npc_hostile','pvp','stealth') DEFAULT 'simple',
    location_zone           VARCHAR(50)     NOT NULL,
    status                  ENUM('available','active','completed','failed','expired') DEFAULT 'available',
    assigned_citizenid      VARCHAR(50)     NULL,
    payment                 BIGINT          NOT NULL,
    loan_id                 INT             NULL,       -- NOVO: referência ao loan que gerou a ordem
    created_at              DATETIME        DEFAULT CURRENT_TIMESTAMP,
    expires_at              DATETIME        NOT NULL,
    completed_at            DATETIME        NULL,
    INDEX idx_status            (status),
    INDEX idx_vehicle_owner     (vehicle_owner_citizenid),
    INDEX idx_status_expires    (status, expires_at),
    INDEX idx_company_id        (company_id),
    UNIQUE KEY uq_loan_id       (loan_id)              -- NOVO: deduplicação entre ciclos de CheckOverdue
);
```

---

## Config (`config/config.lua`)

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
        { name = 'Porto de LS',      coords = vector3(-670.0, -1450.0, 5.0),   radius = 80.0 },
        { name = 'Boneyard',         coords = vector3(1660.0, 3167.0, 41.0),   radius = 60.0 },
        { name = 'Sandy Shores',     coords = vector3(1820.0, 3692.0, 34.0),   radius = 70.0 },
        { name = 'Paleto Bay',       coords = vector3(-183.0, 6317.0, 31.0),   radius = 50.0 },
        { name = 'Grapeseed',        coords = vector3(1696.0, 4789.0, 42.0),   radius = 60.0 },
    },

    -- Impound (entrega — Sub-spec 2)
    ImpoundLocation     = vector3(400.0, -1640.0, 29.0),
    ImpoundHeading      = 90.0,
}
```

---

## Funções DB (`server/database.lua`)

```lua
-- Padrão de datas: escrita via FROM_UNIXTIME(?), leitura via UNIX_TIMESTAMP(col) as col_unix
-- Usar aliases distintos (_unix) para evitar conflito com SELECT *

function DB_CreateCompany(id, ownerCitizenId, name, companyType)
    -- companyType: 'logistics' | 'repo' (default 'logistics')
    -- INSERT INTO trucker_companies (id, owner_citizenid, name, company_type) VALUES (?, ?, ?, ?)

function DB_InsertRepoOrder(vehiclePlate, vehicleModel, vehicleValue, vehicleOwnerCitizenId,
                             missionType, locationZone, payment, expiresAt, companyId, loanId)
    -- INSERT IGNORE INTO trucker_repo_orders
    --   (vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
    --    mission_type, location_zone, payment, expires_at, company_id, loan_id, status)
    -- VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, 'available')
    -- companyId é SEMPRE nil ao inserir — preenchido via DB_AcceptRepoOrder; nenhum chamador passa valor não-nil
    -- Retorna id inserido (nil se INSERT IGNORE ignorou por loan_id duplicado)

function DB_GetAvailableRepoOrders()
    -- SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
    --        mission_type, location_zone, payment, status,
    --        UNIX_TIMESTAMP(expires_at) as expires_at_unix,
    --        UNIX_TIMESTAMP(created_at) as created_at_unix
    -- FROM trucker_repo_orders WHERE status = 'available' ORDER BY created_at DESC

function DB_CountAvailableNpcOrders()
    -- SELECT COUNT(*) FROM trucker_repo_orders
    -- WHERE status = 'available' AND vehicle_owner_citizenid IS NULL AND expires_at > NOW()
    -- Inclui expires_at > NOW() para não contar ordens expiradas ainda não varridas pelo thread
    -- Retorna número inteiro

function DB_GetActiveRepoOrder(citizenId)
    -- SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
    --        mission_type, location_zone, payment, status, company_id, loan_id,
    --        UNIX_TIMESTAMP(expires_at) as expires_at_unix
    -- FROM trucker_repo_orders
    -- WHERE assigned_citizenid = ? AND status = 'active' LIMIT 1

function DB_AcceptRepoOrder(orderId, citizenId, companyId)
    -- UPDATE trucker_repo_orders
    -- SET status = 'active', assigned_citizenid = ?, company_id = ?
    -- WHERE id = ? AND status = 'available'
    -- Retorna linhas afetadas (0 = já aceita por outro)

function DB_UpdateRepoOrderStatus(orderId, newStatus, assignedCitizenId, companyId)
    -- UPDATE trucker_repo_orders
    -- SET status = ?, assigned_citizenid = ?, company_id = ?
    -- WHERE id = ?

function DB_CompleteRepoOrder(orderId, completedAt)
    -- UPDATE trucker_repo_orders
    -- SET status = 'completed', completed_at = FROM_UNIXTIME(?) WHERE id = ?
    -- completedAt = os.time() passado pelo chamador (padrão do projeto: escrita via FROM_UNIXTIME)

function DB_ExpireRepoOrders()
    -- UPDATE trucker_repo_orders
    -- SET status = 'expired'
    -- WHERE expires_at < NOW() AND status IN ('available', 'active')

function DB_GetRepoOrderById(orderId)
    -- SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
    --        mission_type, location_zone, payment, status, company_id, loan_id,
    --        assigned_citizenid,
    --        UNIX_TIMESTAMP(expires_at) as expires_at_unix,
    --        UNIX_TIMESTAMP(created_at) as created_at_unix
    -- FROM trucker_repo_orders WHERE id = ? LIMIT 1
    -- (colunas explícitas + aliases _unix — consistente com DB_GetAvailableRepoOrders)

function DB_GetLoanById(loanId)
    -- SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at_unix
    -- FROM trucker_loans WHERE id = ? LIMIT 1
    -- Alias _unix evita colisão entre a coluna DATETIME raw e o valor inteiro unix
    -- Retorna linha ou nil (independente de status — Complete verifica status.active após busca)
```

---

> **Funções existentes reutilizadas pelo RepoService** (já implementadas em fases anteriores — não redefinir):
> - `DB_UpdateCompanyBalance(companyId, amount)` — em `server/database.lua` (Fase 4)
> - `DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)` — em `server/database.lua` (Fase 5 — Loans)

---

## RepoService (`server/services/repo_service.lua`)

```lua
RepoService = {}

-- Constantes lidas de Config.RepoMan
local POOL_INTERVAL, MAX_NPC_ORDERS, NPC_ORDER_EXPIRY, LOAN_ORDER_EXPIRY
local PAYMENT_RATE, COMPANY_FEE_RATE, TYPE_MULTIPLIERS, NPC_MISSION_WEIGHTS
-- NOTA: INSTALLMENT_SECONDS NÃO é local aqui — derivado de Config.Loans.InstallmentDays * 86400
-- Config é shared_script: acessível em todos os chunks sem necessidade de global extra

function RepoService.GenerateFromLoan(loan)
    -- 1. Busca veículos: empresa (loan.company_id) ou empresa cujo owner = loan.citizenid
    -- 2. Se nenhum veículo: return sem criar ordem
    -- 3. vehicle_value = Config.RepoMan.VehicleValues[vehicle.model] ou DefaultVehicleValue
    -- 4. payment = math.floor(vehicle_value * PAYMENT_RATE * TYPE_MULTIPLIERS['pvp'])
    -- 5. DB_InsertRepoOrder(vehicle.plate, vehicle.model, vehicle_value, loan.citizenid,
    --                        'pvp', 'Desconhecida', payment, os.time() + LOAN_ORDER_EXPIRY,
    --                        nil, loan.id)
    --    (company_id=nil; será preenchido no Accept)

function RepoService.GenerateNPC()
    -- 1. Sorteia NpcVehicles[math.random(#NpcVehicles)]
    -- 2. Sorteia NpcZones[math.random(#NpcZones)]
    -- 3. Sorteia mission_type por NpcMissionWeights
    -- 4. vehicle_plate = 'NPC-' .. math.random(100000, 999999)
    -- 5. payment = math.floor(vehicle.value * PAYMENT_RATE * TYPE_MULTIPLIERS[missionType])
    -- 6. DB_InsertRepoOrder(plate, vehicle.model, vehicle.value, nil,
    --                        missionType, zone.name, payment, os.time() + NPC_ORDER_EXPIRY,
    --                        nil, nil)

function RepoService.Accept(src, orderId)
    -- 1. GetPlayer + citizenId
    -- 2. company = CompanyService.GetByMember(citizenId)
    -- 3. Se não empresa ou company.company_type ~= 'repo': erro
    -- 4. activeOrder = DB_GetActiveRepoOrder(citizenId)
    --    Se existir: erro 'Você já tem uma missão ativa'
    -- 5. affected = DB_AcceptRepoOrder(orderId, citizenId, company.id)
    --    Se affected == 0: erro 'Ordem não disponível' (race condition)
    -- 6. order = DB_GetRepoOrderById(orderId)
    -- 7. TriggerClientEvent('AUST_trucker:client:startRepoMission', src, order)
    -- 8. RepoService.BroadcastAvailableOrders()   ← atualiza lista para todos os agentes repo online
    -- 9. Retorna { success=true, order }

function RepoService.Complete(src, orderId)
    -- 1. GetPlayer + citizenId
    -- 2. order = DB_GetRepoOrderById(orderId)
    --    Se não encontrada ou order.status ~= 'active' ou order.assigned_citizenid ~= citizenId:
    --      return { success=false, reason='Ordem não encontrada ou inválida' }
    -- 3. DB_CompleteRepoOrder(orderId, os.time())
    -- 4. payment = order.payment
    --    companyFee = math.floor(payment * COMPANY_FEE_RATE)
    -- 5. Player.Functions.AddMoney('bank', payment, 'repo-completion')
    -- 6. DB_UpdateCompanyBalance(order.company_id, companyFee)
    -- 7. Se order.loan_id != nil:
    --      loan = DB_GetLoanById(order.loan_id)   ← busca pelo loan_id armazenado na ordem (sem ambiguidade)
    --      Se loan e loan.status == 'active':
    --        newBalance = math.max(0, loan.remaining_balance - order.vehicle_value)
    --        newStatus = newBalance == 0 and 'paid' or 'active'
    --        nextPaymentAt = newBalance > 0 and (loan.next_payment_at_unix + Config.Loans.InstallmentDays * 86400) or nil
    --        DB_UpdateLoanBalance(loan.id, newBalance, newStatus, nextPaymentAt)
    -- 8. Se order.vehicle_owner_citizenid != nil e jogador online: lib.notify
    -- 9. RepoService.BroadcastAvailableOrders()   ← atualiza lista para todos os agentes repo online
    -- 10. Retorna { success=true, payment, companyFee }

function RepoService.Fail(src, orderId)
    -- 1. GetPlayer + citizenId
    -- 2. order = DB_GetRepoOrderById(orderId)
    --    Se não encontrada ou order.status ~= 'active' ou order.assigned_citizenid ~= citizenId:
    --      return { success=false }   ← evita ressuscitar ordem já expirada/completada
    -- 3. DB_UpdateRepoOrderStatus(orderId, 'available', nil, nil)
    -- 4. RepoService.BroadcastAvailableOrders()   ← reinsere ordem na lista de todos os agentes online
    -- 5. Retorna { success=true }

function RepoService.CheckExpired()
    -- DB_ExpireRepoOrders()

-- Helper: broadcast lista atualizada para todos os agentes repo online
-- NOTA: `RepoService.BroadcastAvailableOrders` é referenciado via campo de tabela em Accept/Complete/Fail.
-- Lookup de campo de tabela ocorre em tempo de CHAMADA (não de definição), então o helper pode ser
-- definido após as funções no arquivo — a atribuição abaixo ocorre em load time, antes de qualquer
-- thread chamar Accept/Complete/Fail. Não é necessário forward-declare.
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

-- Thread: Pool NPC
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

-- Thread: Expiração
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(300 * 1000) -- 5 min
        RepoService.CheckExpired()
    end
end)
```

---

## Modificações em `company_service.lua`

```lua
-- CompanyService.Create deve:
-- 1. Aceitar parâmetro companyType (string, default 'logistics')
-- 2. Validar companyType: apenas 'logistics' ou 'repo'
-- 3. Chamar DB_CreateCompany(id, citizenId, name, companyType)
-- 4. Popular cache com company_type:
VP_Trucker.Companies[companyId] = {
    id              = companyId,
    owner_citizenid = citizenId,
    name            = name,
    balance         = 0,
    is_recruiting   = 0,
    company_type    = companyType,   -- NOVO
}

-- CompanyService.Load (startup) — garantir que company_type está no cache.
-- DB_GetCompany / query de inicialização usa SELECT * (já retorna company_type).
-- O loop de inicialização DEVE incluir company_type explicitamente ao montar o cache:
--
--   for _, row in ipairs(MySQL.query.await('SELECT * FROM trucker_companies', {})) do
--       VP_Trucker.Companies[row.id] = {
--           id              = row.id,
--           owner_citizenid = row.owner_citizenid,
--           name            = row.name,
--           balance         = row.balance,
--           is_recruiting   = row.is_recruiting,
--           company_type    = row.company_type,   -- NOVO: obrigatório para RepoService.Accept
--       }
--   end
--
-- Sem este campo, company.company_type ~= 'repo' sempre falhará silenciosamente.

-- Evento createCompany (events.lua) já é fire-and-forget.
-- Payload do cliente passará a incluir { name, companyType }.
-- O handler server-side extrai e valida companyType antes de chamar CompanyService.Create.
```

---

## Interfaces TypeScript

```ts
// html/src/types/repo.ts
export type RepoMissionType = 'simple' | 'npc_hostile' | 'pvp' | 'stealth'
export type RepoOrderStatus  = 'available' | 'active' | 'completed' | 'failed' | 'expired'

export interface RepoOrder {
  id:                      number
  vehicle_plate:           string
  vehicle_model:           string
  vehicle_value:           number
  vehicle_owner_citizenid: string | null   // null = NPC
  mission_type:            RepoMissionType
  location_zone:           string          // nome da zona; coords reveladas ao aceitar (Sub-spec 2)
  payment:                 number
  status:                  RepoOrderStatus
  expires_at_unix:         number          // unix timestamp (alias do DB)
  created_at_unix:         number          // unix timestamp (alias do DB)
}
```

```ts
// html/src/types/index.ts — mudanças
// 1. Adicionar à interface Company:
company_type: 'logistics' | 'repo'

// 2. Adicionar ao type TabName:
export type TabName = 'jobs' | 'missions' | 'active' | 'company' | 'garage' | 'industries' | 'stats'
//                            ^^^^^^^^^^^ NOVO
```

---

## Zustand Store

```ts
// html/src/stores/useRepoStore.ts
import { create } from 'zustand'
import type { RepoOrder } from '../types/repo'

interface RepoStore {
  repoOrders:        RepoOrder[]
  activeRepoOrder:   RepoOrder | null
  setRepoOrders:     (orders: RepoOrder[]) => void
  setActiveRepoOrder:(order: RepoOrder | null) => void
}

export const useRepoStore = create<RepoStore>((set) => ({
  repoOrders:        [],
  activeRepoOrder:   null,
  setRepoOrders:     (repoOrders)      => set({ repoOrders }),
  setActiveRepoOrder:(activeRepoOrder) => set({ activeRepoOrder }),
}))
```

---

## Callbacks e Eventos

### Callbacks (`server/callbacks.lua`)

```lua
-- getInitialData: adicionar campos para empresa repo
-- Se company != nil e company.company_type == 'repo':
--   repoOrders      = DB_GetAvailableRepoOrders()
--   activeRepoOrder = DB_GetActiveRepoOrder(citizenId)
-- Caso contrário: repoOrders = nil, activeRepoOrder = nil

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

### Eventos (`server/events.lua`)

```lua
RegisterNetEvent('AUST_trucker:completeRepoOrder', function(orderId)
    local src    = source
    local result = RepoService.Complete(src, tonumber(orderId) or 0)
    if result.success then
        TriggerClientEvent('AUST_trucker:client:repoMissionComplete', src, result)
    else
        lib.notify(src, { title='Repo Man', description=result.reason, type='error' })
    end
end)

RegisterNetEvent('AUST_trucker:failRepoOrder', function(orderId)
    RepoService.Fail(source, tonumber(orderId) or 0)
end)
```

### Client events (`client/client.lua`)

```lua
-- Recebe lista atualizada de ordens após Accept/Complete/Fail de qualquer agente
RegisterNetEvent('AUST_trucker:client:updateRepoOrders', function(orders)
    SendNUIMessage({ action = 'updateRepoOrders', repoOrders = orders })
end)

-- Inicia missão ativa no NUI (enviado ao agente que aceitou)
RegisterNetEvent('AUST_trucker:client:startRepoMission', function(order)
    SendNUIMessage({ action = 'startRepoMission', repoOrder = order })
end)

-- Limpa ordem ativa no NUI após Complete (enviado ao agente que completou)
RegisterNetEvent('AUST_trucker:client:repoMissionComplete', function(result)
    SendNUIMessage({ action = 'repoMissionComplete', payment = result.payment })
end)

-- NUI callbacks (fetchNUI → client → servidor)
RegisterNUICallback('acceptRepoOrder', function(data, cb)
    -- lib.callback.await com retorno — NUI aguarda resposta
    local result = lib.callback.await('AUST_trucker:acceptRepoOrder', false, data.orderId)
    cb(result)
end)

RegisterNUICallback('failRepoOrder', function(data, cb)
    -- Fire-and-forget: sem retorno necessário; servidor processa Fail e broadcast async
    TriggerServerEvent('AUST_trucker:failRepoOrder', data.orderId)
    cb({ success = true })
end)
```

### NUI Message Dispatch (`html/src/hooks/useNUI.ts`)

```ts
// NUIMessage — adicionar campos:
repoOrders?:       RepoOrder[]
activeRepoOrder?:  RepoOrder | null
repoOrder?:        RepoOrder         // para startRepoMission
payment?:          number            // para repoMissionComplete

// case 'open': hidratar stores de repo
setRepoOrders(event.data.repoOrders ?? [])
setActiveRepoOrder(event.data.activeRepoOrder ?? null)

// Novos casos:
case 'updateRepoOrders':
    setRepoOrders(event.data.repoOrders ?? [])
    break
case 'startRepoMission':
    setActiveRepoOrder(event.data.repoOrder ?? null)
    break
case 'repoMissionComplete':
    setActiveRepoOrder(null)   // limpa ordem ativa; toast de pagamento tratado pelo RepoPanel
    break
```

---

## NUI — RepoPanel

```
RepoPanel (aba "Missões" — apenas empresa repo)
├── Lista de ordens disponíveis (repoOrders do store)
│   └── RepoCard por ordem:
│       ├── Badge colorido por mission_type:
│       │   SIMPLES (zinc) / HOSTIL (orange) / PVP (red) / STEALTH (purple)
│       ├── Modelo do veículo + valor estimado
│       ├── Zona de localização (nome — coords reveladas ao aceitar)
│       ├── Pagamento ao agente
│       ├── Countdown até expirar (expires_at_unix)
│       └── Botão "Aceitar" → fetchNUI('acceptRepoOrder', { orderId })
└── Ordem ativa (activeRepoOrder do store)
    ├── Veículo alvo + tipo de missão
    ├── Instrução: "Vá ao local e recolha o veículo" (Sub-spec 2 gerencia gameplay)
    └── Botão "Abandonar" → fetchNUI('failRepoOrder', { orderId })
```

**Roteamento de aba no nav:**
- `company.company_type === 'logistics'` → aba "Jobs" renderiza `<JobsPanel>`
- `company.company_type === 'repo'` → aba "Missões" renderiza `<RepoPanel>`
- Sem empresa → aba "Jobs" renderiza `<JobsPanel>` (comportamento atual inalterado)

---

## Testes Manuais

- [ ] Criar empresa tipo 'repo' → aba Jobs substituída por "Missões Repo"
- [ ] Criar empresa tipo 'logistics' → não vê aba Repo
- [ ] Pool NPC gera ordens automaticamente (até MaxNpcOrders, apenas ordens NPC contam)
- [ ] Aceitar ordem → status='active', ordem some da lista para todos
- [ ] Aceitar segunda ordem sem completar a primeira → bloqueado
- [ ] Completar ordem → agente recebe pagamento em bank, empresa recebe 20%
- [ ] Abandonar ordem → volta para 'available'
- [ ] Simular loan default: `UPDATE trucker_loans SET next_payment_at = DATE_SUB(NOW(), INTERVAL 1 HOUR)` → aguardar CheckOverdue → repo order criada com vehicle_owner_citizenid
- [ ] Completar repo order de loan → `remaining_balance` do loan reduz em `vehicle_value`
- [ ] Empresa logistics tenta aceitar repo → bloqueado
- [ ] Ordem expira enquanto ativa → Complete retorna erro gracioso sem crash
