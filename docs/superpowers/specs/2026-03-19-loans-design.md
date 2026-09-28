# Empréstimos (Loans) — Design Spec

**Fase:** 4 — Empresas
**Versão alvo:** 5.0.0
**Data:** 2026-03-19

---

## Objetivo

Adicionar sistema de empréstimos financeiros ao AUST_trucker, permitindo que jogadores individuais e empresas contraiam dívidas junto a um NPC bancário. O sistema cobre contratação, acompanhamento, pagamento manual, inadimplência com penalidade e gatilho para o sistema Repo Man (Fase 6).

---

## Arquitetura

### Fluxo Principal

```
NPC Banqueiro (ox_target) — ÚNICA origem de requestLoan; NUI não tem botão "Solicitar"
  → ox_lib menu: Solicitar / Ver saldo
  → input de valor ($10k–$500k)
  → simulação (total + parcelas)
  → TriggerServerEvent('AUST_trucker:requestLoan')  ← fire-and-forget (world menu, não NUI)
    → LoanService.Create()
      → DB_CreateLoan()
      → exports.qbx_core: AddMoney (credita o valor do empréstimo ao jogador)
      → sucesso: TriggerClientEvent('AUST_trucker:client:loanUpdate', loanData) → SendNUIMessage
      → erro:    lib.notify ao src (já tem empréstimo ativo, valor inválido, etc.)

NUI (aba Empresa / Estatísticas) — APENAS para acompanhar saldo e pagar parcelas
  → botão "Pagar $X"
  → fetchNUI('payLoan', { loanId, amount })
    → lib.callback.await('AUST_trucker:payLoan')
      → LoanService.Pay()
        → remove dinheiro do jogador
        → se pagamento parcial: avança next_payment_at = os.time() + INSTALLMENT_SECONDS
        → se remaining_balance ≤ 0: status 'paid', next_payment_at = nil
        → DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)
        → retorna { success, remaining_balance, status } ao NUI

Thread servidor (a cada 5 min)
  → LoanService.CheckOverdue()
    → DB_GetOverdueLoans()
    → para cada vencido:
      → aplica multa 15% ao remaining_balance
      → insere em trucker_repo_orders
      → notifica jogador (se online) via lib.notify
      → atualiza next_payment_at (+ 7 dias, para próxima janela)
```

---

## Regras de Negócio

### Limites

| Parâmetro | Valor padrão |
|---|---|
| Valor mínimo | $10.000 |
| Valor máximo | $500.000 |
| Taxa de juros | 5% |
| Número de parcelas | 4 |
| Intervalo entre parcelas | 7 dias (604.800 s) |
| Multa por atraso | 15% sobre saldo devedor |
| Máx. empréstimos ativos por entidade | 1 |

### Cálculo

```
total_a_pagar = amount * 1.05
monthly_payment = ceil(total_a_pagar / 4)
next_payment_at = NOW() + INTERVAL 7 DAY
```

### Restrições de Acesso

- Empréstimo **pessoal**: qualquer jogador; `company_id = NULL`
- Empréstimo **empresarial**: apenas Owner ou Manager da empresa; `company_id` = id da empresa
- Limite de **1 empréstimo ativo por entidade**: pessoal (por `citizenid`) e empresarial (por `company_id`) são entidades distintas. Um jogador pode ter simultaneamente 1 empréstimo pessoal + 1 empréstimo empresarial (desde que seja Owner/Manager). A verificação em `LoanService.Create` consulta `DB_GetActiveLoan(citizenId)` apenas para empréstimos pessoais, ou `DB_GetActiveCompanyLoan(companyId)` apenas para empresariais — nunca um bloqueando o outro.

### Pagamento

- Valor mínimo por pagamento: `monthly_payment`
- Valor máximo: `remaining_balance` (quitação antecipada permitida)
- Pagamento reduz `remaining_balance`
- Se `remaining_balance ≤ 0` após pagamento → `status = 'paid'`
- Dinheiro removido via `exports.qbx_core:RemoveMoney` (cash primeiro, depois bank)

### Inadimplência (Default)

- Detectada quando `next_payment_at < NOW()` e `status = 'active'`
- Ação: `remaining_balance = ceil(remaining_balance * 1.15)`
- Gera registro em `trucker_repo_orders` (`{ loan_id, citizenid, company_id, amount = remaining_balance }`)
- `next_payment_at` atualizado para +7 dias (nova janela; empréstimo não é encerrado automaticamente)
- Status só muda para `'defaulted'` se owner abandonar/vender empresa com empréstimo empresarial ativo

---

## Estrutura de Arquivos

### Novos arquivos

| Arquivo | Responsabilidade |
|---|---|
| `server/services/loan_service.lua` | `LoanService` global — Create, Pay, CheckOverdue |
| `html/src/components/loans/LoanPanel.tsx` | Componente NUI de empréstimo (pessoal + empresarial) |
| `html/src/types/loan.ts` | Interface TypeScript `LoanData` |

### Arquivos modificados

| Arquivo | Mudança |
|---|---|
| `config/config.lua` | Adiciona bloco `Config.Loans` |
| `server/database.lua` | 5 novas funções `DB_Loan*` |
| `server/callbacks.lua` | Callbacks `AUST_trucker:getLoanData`, `AUST_trucker:payLoan` |
| `server/events.lua` | Evento `requestLoan`; thread `CheckOverdue` |
| `fxmanifest.lua` | Adiciona `loan_service.lua` na load order (antes de `job_service.lua`) |
| `client/client.lua` | Blip + ox_target NPC banqueiro; handler `AUST_trucker:client:loanUpdate` |
| `html/src/stores/useStatsStore.ts` | Adiciona `personalLoan?: LoanData` ao store |
| `html/src/stores/useCompanyStore.ts` | Adiciona `companyLoan?: LoanData` ao store |
| `html/src/hooks/useNUI.ts` | Caso `updateLoan`: despacha para store correto via `loan.is_company_loan` |
| `html/src/components/stats/StatsPanel.tsx` | Seção "Empréstimo Pessoal" abaixo das estatísticas |
| `html/src/components/company/CompanyPanel.tsx` | Seção "Empréstimo Empresarial" visível para Owner/Manager |

---

## Interfaces TypeScript

```ts
// html/src/types/loan.ts
export type LoanStatus = 'active' | 'paid' | 'defaulted'

export interface LoanData {
  id: number
  amount: number             // valor original
  remaining_balance: number  // saldo devedor atual
  monthly_payment: number    // parcela mínima
  next_payment_at: number    // unix timestamp UTC
  status: LoanStatus
  is_company_loan: boolean   // true se company_id != null
}
```

---

## Config

```lua
-- config/config.lua — bloco a adicionar
Config.Loans = {
    MinAmount        = 10000,      -- valor mínimo de empréstimo
    MaxAmount        = 500000,     -- valor máximo
    InterestRate     = 0.05,       -- juros (5%)
    NumInstallments  = 4,          -- número de parcelas
    InstallmentDays  = 7,          -- dias entre parcelas
    PenaltyRate      = 0.15,       -- multa por atraso (15%)
    CheckInterval    = 300,        -- segundos entre verificações de atraso
    BankerLocation   = vector3(-2962.6, 485.6, 15.7),  -- Paleto Bay bank
    BankerPed        = 'ig_bankman',
    BankerHeading    = 90.0,
}
```

---

## Funções DB (`server/database.lua`)

```lua
-- next_payment_at é DATETIME no DB.
-- Escrita: sempre usar FROM_UNIXTIME(os.time()) — mesmo padrão de DB_InsertJob para expires_at.
-- Leitura: sempre alias UNIX_TIMESTAMP(next_payment_at) as next_payment_at — para satisfazer
--          LoanData.next_payment_at: number no TypeScript.

function DB_CreateLoan(citizenId, companyId, amount, interestRate, monthlyPayment, nextPaymentAt)
    -- INSERT INTO trucker_loans (..., next_payment_at) VALUES (..., FROM_UNIXTIME(?))
    -- nextPaymentAt = os.time() + INSTALLMENT_SECONDS
    -- Retorna id do loan criado (MySQL.insert.await)

function DB_GetActiveLoan(citizenId)
    -- SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
    -- FROM trucker_loans WHERE citizenid = ? AND company_id IS NULL AND status = 'active' LIMIT 1
    -- Retorna linha ou nil

function DB_GetActiveCompanyLoan(companyId)
    -- SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
    -- FROM trucker_loans WHERE company_id = ? AND status = 'active' LIMIT 1

function DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)
    -- UPDATE trucker_loans
    -- SET remaining_balance=?, status=?, next_payment_at=FROM_UNIXTIME(?)
    -- WHERE id=?
    -- nextPaymentAt = os.time() + INSTALLMENT_SECONDS para pagamentos parciais
    -- nextPaymentAt = nil para pagamentos que quitam (status='paid')
    -- NOTA: oxmysql vincula Lua nil → SQL NULL; FROM_UNIXTIME(NULL) → NULL em MySQL
    --       Isso é o comportamento correto para quitação — sem próxima parcela.

function DB_GetOverdueLoans()
    -- SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
    -- FROM trucker_loans WHERE next_payment_at < NOW() AND status = 'active'
```

---

## LoanService (`server/services/loan_service.lua`)

```lua
LoanService = {}

-- Constantes (lidas de Config.Loans)
local MIN_AMOUNT, MAX_AMOUNT, INTEREST_RATE, NUM_INSTALLMENTS
local INSTALLMENT_SECONDS, PENALTY_RATE, CHECK_INTERVAL

function LoanService.Create(src, citizenId, companyId, amount)
    -- Valida amount (MIN–MAX)
    -- Verifica empréstimo ativo existente (pessoal ou empresarial)
    -- Calcula total = amount * (1 + INTEREST_RATE), monthly = ceil(total / NUM_INSTALLMENTS)
    -- DB_CreateLoan(citizenId, companyId, amount, INTEREST_RATE, monthly, os.time() + INSTALLMENT_SECONDS)
    -- Retorna { success, loan } ou { success=false, reason }

function LoanService.Pay(src, citizenId, companyId, loanId, amount)
    -- Busca loan ativo por loanId COM filtro status='active':
    --   se companyId != nil: SELECT ... WHERE id=? AND company_id=? AND status='active'
    --   se companyId == nil: SELECT ... WHERE id=? AND citizenid=? AND status='active'
    -- Retorna nil se não encontrado (inclui loans 'paid' ou 'defaulted') → retorna erro
    -- Valida que pertence a citizenId ou companyId
    -- Valida amount >= monthly_payment e <= remaining_balance
    -- Remove dinheiro do jogador (cash primeiro, depois bank)
    -- Calcula novo saldo:
    --   newBalance = remaining_balance - amount
    --   se newBalance <= 0: newStatus='paid', newBalance=0, nextPaymentAt=nil
    --   se newBalance > 0:  newStatus='active', nextPaymentAt=os.time()+INSTALLMENT_SECONDS
    --     (CRÍTICO: avançar next_payment_at para evitar penalidade imediata no próximo ciclo)
    -- DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)
    -- Retorna { success, remaining_balance, status }

function LoanService.CheckOverdue()
    -- DB_GetOverdueLoans()
    -- Para cada loan vencido:
    --   newBalance = ceil(remaining * (1 + PENALTY_RATE))
    --   DB_UpdateLoanBalance(id, newBalance, 'active', os.time() + INSTALLMENT_SECONDS)
    --   Insere em trucker_repo_orders
    --   Notifica jogador se online

-- Thread de verificação
CreateThread(function()
    while true do
        Wait(CHECK_INTERVAL * 1000)
        LoanService.CheckOverdue()
    end
end)
```

---

## fxmanifest — Load Order

`loan_service.lua` deve ser carregado **após** `company_service.lua` (usa `CompanyService.Get`) e **antes** de `job_service.lua`:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/loan_service.lua',    -- NOVO — após company_service (usa CompanyService.Get)
    'server/services/economy_service.lua',
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',
    'server/services/job_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}
```

---

## NUI — Componente LoanPanel

```tsx
// Exibe para empréstimo ativo:
// - Saldo devedor atual (formatado em $)
// - Parcela mínima
// - Vencimento com countdown ("vence em Xd Yh")
// - Input de valor (min = monthly_payment, max = remaining_balance)
// - Botão "Pagar"
// - Badge de status: ATIVO (verde) / ATRASADO (vermelho) / QUITADO (zinc)

// Exibe para sem empréstimo ativo:
// - Mensagem "Nenhum empréstimo ativo"
// - Nota: "Visite o banco em Paleto Bay para solicitar"
```

---

## Eventos e Callbacks

### Server events (`server/events.lua`)

```lua
-- Fire-and-forget: cliente não espera retorno; servidor responde via TriggerClientEvent
RegisterNetEvent('AUST_trucker:requestLoan', function(amount, isCompanyLoan)
    -- Valida, chama LoanService.Create
    -- Se sucesso: TriggerClientEvent('AUST_trucker:client:loanUpdate', src, loanData)
    -- Se erro: lib.notify ao src
```

### Server callbacks (`server/callbacks.lua`)

```lua
-- Chamado pelo NUI via fetchNUI → RegisterNUICallback → lib.callback.await
lib.callback.register('AUST_trucker:getLoanData', function(source)
    -- Retorna { personalLoan, companyLoan } para o cliente logado

-- Chamado pelo NUI via fetchNUI → RegisterNUICallback → lib.callback.await
-- Precisa retornar resultado ao NUI (sucesso/erro + novo saldo)
lib.callback.register('AUST_trucker:payLoan', function(source, loanId, amount)
    -- Chama LoanService.Pay(source, citizenId, companyId, loanId, amount)
    -- Retorna { success, remaining_balance, status } ou { success=false, reason }
```

### Client events (`client/client.lua`)

```lua
RegisterNetEvent('AUST_trucker:client:loanUpdate', function(loanData)
    -- SendNUIMessage({ action = 'updateLoan', loan = loanData })
    -- loanData inclui is_company_loan (bool) para o useNUI.ts saber qual store atualizar
```

### NUI message dispatch (`html/src/hooks/useNUI.ts`)

```ts
case 'updateLoan': {
    const loan = msg.loan as LoanData
    if (loan.is_company_loan) {
        useCompanyStore.getState().setCompanyLoan(loan)
    } else {
        useStatsStore.getState().setPersonalLoan(loan)
    }
    break
}
```

---

## Integração com Repo Man (Fase 6)

Ao detectar inadimplência, `LoanService.CheckOverdue()` insere em `trucker_repo_orders`:

```sql
-- INSERT IGNORE evita duplicatas se o mesmo loan ficar overdue em múltiplos ciclos de CheckOverdue
-- Requer UNIQUE KEY (loan_id) em trucker_repo_orders (adicionar em import.sql / migration)
INSERT IGNORE INTO trucker_repo_orders
    (citizenid, company_id, loan_id, amount, status, created_at)
VALUES
    (?, ?, ?, ?, 'pending', NOW())
```

O sistema Repo Man (Fase 6) consumirá essas ordens. Nesta fase, apenas a inserção é feita — nenhuma lógica de Repo Man é implementada ainda.

> **Schema note:** adicionar `UNIQUE KEY uq_loan_id (loan_id)` em `trucker_repo_orders` para que `INSERT IGNORE` funcione como deduplicador entre ciclos de `CheckOverdue`.

---

## Testes Manuais

- [ ] Solicitar empréstimo pessoal no NPC → aparece na aba Estatísticas
- [ ] Solicitar 2º empréstimo → bloqueado com mensagem de erro
- [ ] Pagar parcela mínima → saldo reduz corretamente
- [ ] Quitar antecipadamente → status muda para 'paid', seção some
- [ ] Simular atraso (alterar `next_payment_at` no DB) → multa aplicada, repo order criada
- [ ] Solicitar empréstimo empresarial como Driver → bloqueado
- [ ] Solicitar empréstimo empresarial como Owner → aparece na aba Empresa
