# Loans System (Empréstimos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a financial loan system to AUST_trucker allowing players and companies to borrow money from an NPC banker, track repayments in the NUI, and process overdue penalties automatically.

**Architecture:** New `LoanService` global (server/services/loan_service.lua) handles all loan logic; 5 `DB_Loan*` helpers in database.lua; NPC banker (ox_target) fires `requestLoan` event; NUI `payLoan` callback handles repayment; background thread applies 15% penalty on overdue loans.

**Tech Stack:** Lua 5.4 (lua54, chunk isolation — all shared functions must be global), QBX (qbx_core), oxmysql (MySQL.insert/single/query/update.await), ox_lib (lib.callback, lib.notify, lib.inputDialog, ox_target), React 18 + TypeScript 5 + Tailwind CSS + Zustand 4.

> **Schema note (Fase 6 deferred):** `trucker_repo_orders` was designed for vehicle repo missions — it has required NOT NULL columns (`vehicle_plate`, `vehicle_model`, etc.) incompatible with loan defaults. The `CheckOverdue` thread applies the 15% penalty but **does not insert into `trucker_repo_orders` yet**. That integration requires a Fase 6 schema migration.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `config/config.lua` | Modify (append) | `Config.Loans` block |
| `server/database.lua` | Modify (append) | 5 new `DB_Loan*` functions |
| `server/services/loan_service.lua` | **Create** | `LoanService` global — Create, Pay, CheckOverdue |
| `server/callbacks.lua` | Modify | `getLoanData`, `payLoan` callbacks; update `getInitialData` |
| `server/events.lua` | Modify | `requestLoan` event + overdue thread |
| `fxmanifest.lua` | Modify | Insert `loan_service.lua` after `company_service.lua` |
| `client/client.lua` | Modify | Blip, ox_target NPC banker, `loanUpdate` client event |
| `html/src/types/loan.ts` | **Create** | `LoanData` TypeScript interface |
| `html/src/stores/useStatsStore.ts` | Modify | Add `personalLoan?: LoanData` state |
| `html/src/stores/useCompanyStore.ts` | Modify | Add `companyLoan?: LoanData` state |
| `html/src/hooks/useNUI.ts` | Modify | Add `updateLoan` case; update `NUIMessage` type |
| `html/src/components/loans/LoanPanel.tsx` | **Create** | Loan status + payment UI component |
| `html/src/components/stats/StatsPanel.tsx` | Modify | Add `<LoanPanel isCompany={false} />` section |
| `html/src/components/company/CompanyPanel.tsx` | Modify | Add `<LoanPanel isCompany={true} />` for owner/manager |

---

## Task 1: Config.Loans block

**Files:**
- Modify: `config/config.lua` (append to end of file)

- [x] **Step 1: Append Config.Loans to config.lua**

Open `config/config.lua` and append at the very end:

```lua
-- =======================================
-- EMPRÉSTIMOS (LOANS)
-- =======================================
Config.Loans = {
    MinAmount        = 10000,     -- valor mínimo de empréstimo
    MaxAmount        = 500000,    -- valor máximo
    InterestRate     = 0.05,      -- juros (5%)
    NumInstallments  = 4,         -- número de parcelas
    InstallmentDays  = 7,         -- dias entre parcelas
    PenaltyRate      = 0.15,      -- multa por atraso (15%)
    CheckInterval    = 300,       -- segundos entre verificações de atraso (5 min)
    BankerLocation   = vector3(-2962.6, 485.6, 15.7),  -- Paleto Bay Bank
    BankerPed        = 'ig_bankman',
    BankerHeading    = 90.0,
}
```

- [x] **Step 2: Verify the file parses without error**

Start the FiveM server (or use `ensure AUST_trucker` in txAdmin console). If there's a parse error, the resource will fail to start and print a Lua syntax error. Confirm no errors in the console.

- [x] **Step 3: Commit**

```bash
git add config/config.lua
git commit -m "feat(loans): add Config.Loans block"
```

---

## Task 2: DB functions

**Files:**
- Modify: `server/database.lua` (append new LOANS section)

- [x] **Step 1: Append DB_Loan* functions to database.lua**

Open `server/database.lua` and append the following section at the end:

```lua
-- ============================================================
-- LOANS (Empréstimos)
-- ============================================================
-- NOTA: next_payment_at é DATETIME no DB.
-- Escrita: FROM_UNIXTIME(os.time() + seconds) — padrão de DB_InsertJob.
-- Leitura: UNIX_TIMESTAMP(next_payment_at) as next_payment_at — retorna número para o TS.
-- oxmysql vincula Lua nil → SQL NULL; FROM_UNIXTIME(NULL) → NULL (correto para status='paid').

function DB_CreateLoan(citizenId, companyId, amount, interestRate, monthlyPayment, nextPaymentAt)
    -- remaining_balance começa em total_a_pagar = amount * (1 + interestRate)
    -- para que a soma das parcelas (4 × monthlyPayment) corresponda exatamente ao saldo devedor inicial
    local totalToPay = math.ceil(amount * (1 + interestRate))
    return MySQL.insert.await(
        [[INSERT INTO trucker_loans
          (citizenid, company_id, amount, interest_rate, remaining_balance, monthly_payment, next_payment_at)
          VALUES (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))]],
        { citizenId, companyId, amount, interestRate, totalToPay, monthlyPayment, nextPaymentAt }
    )
end

-- Empréstimo pessoal ativo (company_id IS NULL)
function DB_GetActiveLoan(citizenId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
          FROM trucker_loans
          WHERE citizenid = ? AND company_id IS NULL AND status = 'active'
          LIMIT 1]],
        { citizenId }
    )
end

-- Empréstimo empresarial ativo
function DB_GetActiveCompanyLoan(companyId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
          FROM trucker_loans
          WHERE company_id = ? AND status = 'active'
          LIMIT 1]],
        { companyId }
    )
end

-- Atualiza saldo, status e próximo vencimento
-- nextPaymentAt = os.time() + seconds para parcial; nil para quitação
function DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)
    MySQL.update.await(
        [[UPDATE trucker_loans
          SET remaining_balance = ?, status = ?, next_payment_at = FROM_UNIXTIME(?)
          WHERE id = ?]],
        { newBalance, newStatus, nextPaymentAt, loanId }
    )
end

-- Retorna todos os empréstimos ativos com vencimento passado
function DB_GetOverdueLoans()
    return MySQL.query.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
          FROM trucker_loans
          WHERE next_payment_at < NOW() AND status = 'active']])
end
```

- [x] **Step 2: Manually verify DB functions exist after resource start**

In txAdmin console, run `ensure AUST_trucker`. Confirm no errors. Test `DB_GetOverdueLoans` is accessible by calling it from another server script in console.

- [x] **Step 3: Commit**

```bash
git add server/database.lua
git commit -m "feat(loans): add DB_Loan* functions to database.lua"
```

---

## Task 3: LoanService + fxmanifest

**Files:**
- Create: `server/services/loan_service.lua`
- Modify: `fxmanifest.lua`

- [x] **Step 1: Create server/services/loan_service.lua**

```lua
-- AUST_trucker — server/services/loan_service.lua
-- LoanService: empréstimos pessoais e empresariais
-- Depende de: CompanyService (company_service.lua deve estar antes na load order)

LoanService = {}

-- Constantes (lidas de Config.Loans na inicialização)
local MIN_AMOUNT, MAX_AMOUNT, INTEREST_RATE, NUM_INSTALLMENTS
local INSTALLMENT_SECONDS, PENALTY_RATE, CHECK_INTERVAL

-- Inicializa constantes a partir do Config (disponível via shared_scripts)
local function InitConstants()
    local c = Config.Loans
    MIN_AMOUNT         = c.MinAmount
    MAX_AMOUNT         = c.MaxAmount
    INTEREST_RATE      = c.InterestRate
    NUM_INSTALLMENTS   = c.NumInstallments
    INSTALLMENT_SECONDS = c.InstallmentDays * 86400  -- dias → segundos
    PENALTY_RATE       = c.PenaltyRate
    CHECK_INTERVAL     = c.CheckInterval
end
InitConstants()

-- Cria um novo empréstimo para o jogador ou empresa.
-- companyId = nil para empréstimo pessoal.
-- Retorna: { success=true, loan={...} } ou { success=false, reason='...' }
function LoanService.Create(src, citizenId, companyId, amount)
    -- Validar valor
    if amount < MIN_AMOUNT or amount > MAX_AMOUNT then
        return { success = false, reason = ('Valor deve ser entre $%d e $%d'):format(MIN_AMOUNT, MAX_AMOUNT) }
    end

    -- Verificar empréstimo ativo existente (pessoal e empresarial são entidades separadas)
    if companyId then
        if DB_GetActiveCompanyLoan(companyId) then
            return { success = false, reason = 'Esta empresa já tem um empréstimo ativo' }
        end
    else
        if DB_GetActiveLoan(citizenId) then
            return { success = false, reason = 'Você já tem um empréstimo pessoal ativo' }
        end
    end

    -- Calcular parcelas
    local total          = math.ceil(amount * (1 + INTEREST_RATE))
    local monthlyPayment = math.ceil(total / NUM_INSTALLMENTS)
    local nextPaymentAt  = os.time() + INSTALLMENT_SECONDS

    -- Criar no banco
    local loanId = DB_CreateLoan(citizenId, companyId, amount, INTEREST_RATE, monthlyPayment, nextPaymentAt)
    if not loanId then
        return { success = false, reason = 'Erro ao criar empréstimo' }
    end

    -- Creditar dinheiro ao jogador
    local Player = exports.qbx_core:GetPlayer(src)
    if Player then
        Player.Functions.AddMoney('cash', amount, 'loan-disbursement')
    end

    -- Retornar dados do loan criado
    local loan = {
        id                = loanId,
        amount            = amount,
        remaining_balance = total,   -- total = math.ceil(amount * 1.05), reflete o DB
        monthly_payment   = monthlyPayment,
        next_payment_at   = nextPaymentAt,
        status            = 'active',
        is_company_loan   = companyId ~= nil,
    }

    return { success = true, loan = loan }
end

-- Processa um pagamento manual.
-- companyId = nil para empréstimo pessoal.
-- amount = valor a pagar (>= monthly_payment, <= remaining_balance).
-- Retorna: { success=true, remaining_balance=N, status='active'|'paid' }
--       ou { success=false, reason='...' }
function LoanService.Pay(src, citizenId, companyId, loanId, amount)
    -- Buscar loan ativo com filtro de status='active' (proteção contra paid/defaulted)
    local loan
    if companyId then
        loan = MySQL.single.await(
            "SELECT * FROM trucker_loans WHERE id = ? AND company_id = ? AND status = 'active' LIMIT 1",
            { loanId, companyId }
        )
    else
        loan = MySQL.single.await(
            "SELECT * FROM trucker_loans WHERE id = ? AND citizenid = ? AND company_id IS NULL AND status = 'active' LIMIT 1",
            { loanId, citizenId }
        )
    end

    if not loan then
        return { success = false, reason = 'Empréstimo não encontrado ou já quitado' }
    end

    -- Validar valor do pagamento
    if amount < loan.monthly_payment then
        return { success = false, reason = ('Pagamento mínimo é $%d'):format(loan.monthly_payment) }
    end
    if amount > loan.remaining_balance then
        amount = loan.remaining_balance  -- limita ao saldo; permite quitação antecipada
    end

    -- Verificar e remover dinheiro do jogador (cash primeiro, depois bank)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end

    local cash = Player.PlayerData.money['cash'] or 0
    local bank = Player.PlayerData.money['bank'] or 0
    if cash + bank < amount then
        return { success = false, reason = 'Saldo insuficiente' }
    end

    -- Deduzir: cash primeiro, depois bank
    local fromCash = math.min(cash, amount)
    local fromBank = amount - fromCash
    if fromCash > 0 then Player.Functions.RemoveMoney('cash', fromCash, 'loan-payment') end
    if fromBank > 0 then Player.Functions.RemoveMoney('bank', fromBank, 'loan-payment') end

    -- Calcular novo saldo
    local newBalance = loan.remaining_balance - amount
    local newStatus, nextPaymentAt

    if newBalance <= 0 then
        newBalance     = 0
        newStatus      = 'paid'
        nextPaymentAt  = nil  -- oxmysql nil → SQL NULL (FROM_UNIXTIME(NULL) → NULL)
    else
        newStatus      = 'active'
        -- Avança a partir do vencimento original para manter datas fixas (não de os.time())
        -- Pagamento antecipado não reescreve o clock
        nextPaymentAt  = loan.next_payment_at + INSTALLMENT_SECONDS
    end

    DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)

    return { success = true, remaining_balance = newBalance, status = newStatus }
end

-- Verifica empréstimos vencidos e aplica multa de 15%.
-- Chamado pela thread periódica.
-- NOTA: Inserção em trucker_repo_orders adiada para Fase 6 (schema incompatível).
function LoanService.CheckOverdue()
    local overdue = DB_GetOverdueLoans()
    if not overdue or #overdue == 0 then return end

    for _, loan in ipairs(overdue) do
        local newBalance  = math.ceil(loan.remaining_balance * (1 + PENALTY_RATE))
        local nextPaymentAt = os.time() + INSTALLMENT_SECONDS

        DB_UpdateLoanBalance(loan.id, newBalance, 'active', nextPaymentAt)

        -- TODO Fase 6: inserir em trucker_repo_orders após migração do schema
        -- O schema atual de repo_orders foi projetado para missões de veículos,
        -- não suporta loan_id/citizenid sem migração.

        -- Notificar jogador se online
        local players = GetPlayers()
        for _, pid in ipairs(players) do
            local p = exports.qbx_core:GetPlayer(tonumber(pid))
            if p and p.PlayerData.citizenid == loan.citizenid then
                lib.notify(tonumber(pid), {
                    title       = 'Empréstimo em atraso',
                    description = ('Multa de 15%% aplicada. Novo saldo: $%d'):format(newBalance),
                    type        = 'error',
                    duration    = 8000,
                })
                break
            end
        end

        print(('[AUST_trucker] Loan #%d overdue — penalty applied. New balance: $%d'):format(loan.id, newBalance))
    end
end

-- Thread periódica de verificação de inadimplência
-- Aguarda VP_Trucker.Ready (padrão do projeto: todas as threads DB aguardam init)
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(CHECK_INTERVAL * 1000)
        LoanService.CheckOverdue()
    end
end)
```

- [x] **Step 2: Update fxmanifest.lua — insert loan_service.lua after company_service.lua**

Open `fxmanifest.lua`. The current `server_scripts` block is:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/economy_service.lua',
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',
    'server/services/job_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}
```

Replace with:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/loan_service.lua',
    'server/services/economy_service.lua',
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',
    'server/services/job_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}
```

- [x] **Step 3: Ensure resource starts clean**

Run `ensure AUST_trucker` in txAdmin console. Confirm:
- No "attempt to index a nil value 'LoanService'" errors
- No "attempt to call a nil value 'DB_CreateLoan'" errors
- Console shows no Lua errors from the new file

- [x] **Step 4: Commit**

```bash
git add server/services/loan_service.lua fxmanifest.lua
git commit -m "feat(loans): add LoanService global and register in fxmanifest"
```

---

## Task 4: Server events + callbacks

**Files:**
- Modify: `server/events.lua` (append)
- Modify: `server/callbacks.lua` (append + update getInitialData)

- [x] **Step 1: Append requestLoan event to server/events.lua**

Open `server/events.lua` and append at the end:

```lua
-- =====================================================
-- LOAN HANDLERS
-- =====================================================

RegisterNetEvent('AUST_trucker:requestLoan', function(amount, isCompanyLoan)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local citizenId = Player.PlayerData.citizenid
    local companyId = nil

    if isCompanyLoan then
        -- CompanyService.GetByMember retorna VP_Trucker.Companies[id] — NÃO tem campo .role
        -- O role está em trucker_company_members; usar DB_GetMember para verificar
        local company = CompanyService.GetByMember(citizenId)
        if not company then
            lib.notify(src, { title = 'Empréstimo', description = 'Você não pertence a uma empresa', type = 'error' })
            return
        end
        local member = DB_GetMember(citizenId)
        if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
            lib.notify(src, { title = 'Empréstimo', description = 'Apenas Owner ou Manager pode contratar empréstimo empresarial', type = 'error' })
            return
        end
        companyId = company.id
    end

    local result = LoanService.Create(src, citizenId, companyId, tonumber(amount) or 0)

    if result.success then
        TriggerClientEvent('AUST_trucker:client:loanUpdate', src, result.loan)
        lib.notify(src, {
            title       = 'Empréstimo aprovado',
            description = ('$%d creditado. Parcela mínima: $%d'):format(result.loan.amount, result.loan.monthly_payment),
            type        = 'success',
            duration    = 7000,
        })
    else
        lib.notify(src, { title = 'Empréstimo recusado', description = result.reason, type = 'error' })
    end
end)
```

- [x] **Step 2: Append getLoanData and payLoan callbacks to server/callbacks.lua**

Open `server/callbacks.lua` and append at the end:

```lua
-- Dados de empréstimo do jogador (pessoal + empresarial)
lib.callback.register('AUST_trucker:getLoanData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { personalLoan = nil, companyLoan = nil } end

    local citizenId    = Player.PlayerData.citizenid
    local personalLoan = DB_GetActiveLoan(citizenId)
    local companyLoan  = nil

    local company = CompanyService.GetByMember(citizenId)
    if company then
        companyLoan = DB_GetActiveCompanyLoan(company.id)
    end

    -- Adiciona is_company_loan para o NUI despachar para o store correto
    if personalLoan then personalLoan.is_company_loan = false end
    if companyLoan  then companyLoan.is_company_loan  = true  end

    return { personalLoan = personalLoan, companyLoan = companyLoan }
end)

-- Pagar parcela de empréstimo (chamado pelo NUI via fetchNUI → lib.callback.await)
lib.callback.register('AUST_trucker:payLoan', function(source, data)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end

    local citizenId = Player.PlayerData.citizenid
    local companyId = nil

    if data.isCompanyLoan then
        -- Verificar role: apenas owner/manager pode pagar empréstimo empresarial
        local member = DB_GetMember(citizenId)
        if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
            return { success = false, reason = 'Sem permissão para pagar empréstimo empresarial' }
        end
        local company = CompanyService.GetByMember(citizenId)
        if company then companyId = company.id end
    end

    return LoanService.Pay(source, citizenId, companyId, data.loanId, tonumber(data.amount) or 0)
end)
```

- [x] **Step 3: Update getInitialData to include loan data**

Open `server/callbacks.lua`. **Replace the entire `getInitialData` callback** (lines 5–18) with this complete version:

```lua
lib.callback.register('AUST_trucker:getInitialData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    local citizenId = Player.PlayerData.citizenid

    -- company computed once, reused for both 'company' field and companyLoan lookup
    local co = CompanyService.GetByMember(citizenId)

    local personalLoan = DB_GetActiveLoan(citizenId)
    if personalLoan then personalLoan.is_company_loan = false end

    local companyLoan = nil
    if co then
        companyLoan = DB_GetActiveCompanyLoan(co.id)
        if companyLoan then companyLoan.is_company_loan = true end
    end

    return {
        jobs                = JobService.GetAvailable(),
        company             = co,
        activeJob           = JobService.GetActiveByPlayer(citizenId),
        stats               = DB_GetPlayerStats(citizenId),
        recruitingCompanies = CompanyService.GetRecruiting(),
        skills              = ProgressionService.GetSkills(citizenId),
        personalLoan        = personalLoan,
        companyLoan         = companyLoan,
    }
end)
```

- [x] **Step 4: Verify resource starts without errors**

Run `ensure AUST_trucker`. Confirm no errors for the new callbacks/events.

- [x] **Step 5: Manual DB test — verify requestLoan creates a loan row**

In txAdmin console, trigger the event as a player or use:
```sql
SELECT * FROM trucker_loans ORDER BY id DESC LIMIT 1;
```
After a loan request, verify `next_payment_at` is a valid future DATETIME (not NULL or 0000-00-00).

- [x] **Step 6: Commit**

```bash
git add server/events.lua server/callbacks.lua
git commit -m "feat(loans): add requestLoan event and getLoanData/payLoan callbacks"
```

---

## Task 5: Client side — NPC banker + loanUpdate handler

**Files:**
- Modify: `client/client.lua` (append)

- [x] **Step 1: Append banker blip, ox_target zone, and loanUpdate handler to client/client.lua**

Open `client/client.lua` and append at the end:

```lua
-- =======================================
-- SISTEMA DE EMPRÉSTIMOS — BANKER NPC
-- =======================================

local bankerPed    = nil
local bankerBlip   = nil
local BANKER_LOC   = Config.Loans.BankerLocation
local BANKER_MODEL = Config.Loans.BankerPed

-- Spawn NPC banqueiro e registra interação
CreateThread(function()
    -- Aguardar o recurso estar pronto
    while not exports.AUST_trucker do Wait(500) end

    -- Carregar modelo
    local hash = GetHashKey(BANKER_MODEL)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 5000 do Wait(100); t = t + 100 end

    -- Criar ped
    bankerPed = CreatePed(4, hash, BANKER_LOC.x, BANKER_LOC.y, BANKER_LOC.z - 1.0, Config.Loans.BankerHeading, false, true)
    SetEntityInvincible(bankerPed, true)
    SetBlockingOfNonTemporaryEvents(bankerPed, true)
    FreezeEntityPosition(bankerPed, true)
    SetModelAsNoLongerNeeded(hash)

    -- Blip
    bankerBlip = AddBlipForCoord(BANKER_LOC.x, BANKER_LOC.y, BANKER_LOC.z)
    SetBlipSprite(bankerBlip, 207)   -- ícone de banco
    SetBlipColour(bankerBlip, 2)     -- verde
    SetBlipScale(bankerBlip, 0.8)
    SetBlipAsShortRange(bankerBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Banco — Empréstimos")
    EndTextCommandSetBlipName(bankerBlip)

    -- Função auxiliar: pede valor e confirma o empréstimo
    -- lib.alertDialog retorna 'confirm' ou nil (nunca 'cancel')
    -- Para escolher tipo, usamos 2 entradas no ox_target (uma pessoal, uma empresarial)
    local function HandleLoanRequest(isCompanyLoan)
        local input = lib.inputDialog('Valor do empréstimo', {
            { type = 'number', label = ('Valor ($%d–$%d)'):format(Config.Loans.MinAmount, Config.Loans.MaxAmount),
              default = 50000, min = Config.Loans.MinAmount, max = Config.Loans.MaxAmount, required = true },
        })
        if not input or not input[1] then return end

        local amount = tonumber(input[1])

        -- Simulação antes de confirmar
        local total   = math.ceil(amount * 1.05)
        local parcela = math.ceil(total / Config.Loans.NumInstallments)
        local confirm = lib.alertDialog({
            header  = 'Confirmar empréstimo',
            content = ('Valor: $%d\nJuros (5%%): $%d\nTotal a pagar: $%d\n%d parcelas de $%d'):format(
                amount, total - amount, total, Config.Loans.NumInstallments, parcela),
            labels  = { confirm = 'Contratar', cancel = 'Cancelar' },
        })
        if confirm ~= 'confirm' then return end

        TriggerServerEvent('AUST_trucker:requestLoan', amount, isCompanyLoan)
    end

    -- ox_target: 2 entradas separadas para pessoal e empresarial
    -- Evita usar lib.alertDialog como seletor de tipo (retorna nil para o botão cancel)
    exports.ox_target:addLocalEntity(bankerPed, {
        {
            name     = 'aurp_banker_personal',
            label    = 'Empréstimo Pessoal',
            icon     = 'fas fa-user',
            distance = 2.0,
            onSelect = function() HandleLoanRequest(false) end,
        },
        {
            name     = 'aurp_banker_company',
            label    = 'Empréstimo Empresarial',
            icon     = 'fas fa-building',
            distance = 2.0,
            onSelect = function() HandleLoanRequest(true) end,
        },
    })
end)

-- Bridge NUI fetch → servidor callback (OBRIGATÓRIO — sem isso fetchNUI('payLoan') retorna {} vazio)
-- Padrão idêntico ao RegisterNUICallback('purchaseSkill', ...) já existente no arquivo
RegisterNUICallback('payLoan', function(data, cb)
    local result = lib.callback.await('AUST_trucker:payLoan', false, data)
    cb(result or { success = false, reason = 'Erro de comunicação' })
end)

-- Recebe atualização de loan do servidor e encaminha para o NUI
RegisterNetEvent('AUST_trucker:client:loanUpdate', function(loanData)
    SendNUIMessage({ action = 'updateLoan', loan = loanData })
end)
```

- [x] **Step 2: Verify NPC spawns and blip appears**

Join the server, travel to Paleto Bay Bank coordinates (-2962.6, 485.6, 15.7). Confirm:
- Blip "Banco — Empréstimos" appears on map
- NPC ped spawns and is frozen
- ox_target interaction "Banco — Empréstimos" appears at 2m range

- [x] **Step 3: Commit**

```bash
git add client/client.lua
git commit -m "feat(loans): add NPC banker blip, ox_target, and loanUpdate client handler"
```

---

## Task 6: TypeScript types + Zustand stores

**Files:**
- Create: `html/src/types/loan.ts`
- Modify: `html/src/stores/useStatsStore.ts`
- Modify: `html/src/stores/useCompanyStore.ts`

- [x] **Step 1: Create html/src/types/loan.ts**

```ts
// html/src/types/loan.ts
export type LoanStatus = 'active' | 'paid' | 'defaulted'

export interface LoanData {
  id: number
  amount: number             // valor original solicitado
  remaining_balance: number  // saldo devedor atual
  monthly_payment: number    // parcela mínima
  next_payment_at: number    // unix timestamp UTC (segundos)
  status: LoanStatus
  is_company_loan: boolean   // true se company_id != null no DB
}
```

- [x] **Step 2: Update useStatsStore.ts — add personalLoan state**

Open `html/src/stores/useStatsStore.ts`. The current content is:

```ts
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

Replace with:

```ts
import { create } from 'zustand'
import type { Stats, Skills, SkillType } from '../types'
import type { LoanData } from '../types/loan'

const DEFAULT_SKILLS: Skills = { distance: 0, valuable: 0, fragile: 0, speed: 0 }

interface StatsStore {
  stats:          Stats | null
  skills:         Skills
  personalLoan:   LoanData | null
  setStats:       (stats: Stats | null) => void
  setSkills:      (skills: Partial<Skills>) => void
  setSkillLevel:  (type: SkillType, level: number) => void
  setPersonalLoan:(loan: LoanData | null) => void
}

export const useStatsStore = create<StatsStore>((set) => ({
  stats:        null,
  skills:       { ...DEFAULT_SKILLS },
  personalLoan: null,

  setStats:       (stats)  => set({ stats }),
  setSkills:      (skills) => set((state) => ({ skills: { ...state.skills, ...skills } })),
  setSkillLevel:  (type, level) => set((state) => ({ skills: { ...state.skills, [type]: level } })),
  setPersonalLoan:(loan) => set({ personalLoan: loan }),
}))
```

- [x] **Step 3: Update useCompanyStore.ts — add companyLoan state**

Open `html/src/stores/useCompanyStore.ts`. Replace with:

```ts
import { create } from 'zustand'
import type { Company, Member, Vehicle } from '../types'
import type { LoanData } from '../types/loan'

interface CompanyStore {
  company:        Company | null
  members:        Member[]
  vehicles:       Vehicle[]
  recruitingList: Company[]
  companyLoan:    LoanData | null
  setCompany:     (company: Company | null) => void
  setMembers:     (members: Member[]) => void
  setVehicles:    (vehicles: Vehicle[]) => void
  setRecruitingList:(list: Company[]) => void
  setCompanyLoan: (loan: LoanData | null) => void
}

export const useCompanyStore = create<CompanyStore>((set) => ({
  company:        null,
  members:        [],
  vehicles:       [],
  recruitingList: [],
  companyLoan:    null,
  setCompany:       (company)       => set({ company }),
  setMembers:       (members)       => set({ members }),
  setVehicles:      (vehicles)      => set({ vehicles }),
  setRecruitingList:(recruitingList)=> set({ recruitingList }),
  setCompanyLoan:   (loan)          => set({ companyLoan: loan }),
}))
```

- [x] **Step 4: Commit**

```bash
git add html/src/types/loan.ts html/src/stores/useStatsStore.ts html/src/stores/useCompanyStore.ts
git commit -m "feat(loans): add LoanData type and personalLoan/companyLoan to stores"
```

---

## Task 7: useNUI hook — updateLoan case + open hydration

**Files:**
- Modify: `html/src/hooks/useNUI.ts`

- [x] **Step 1: Update useNUI.ts**

Open `html/src/hooks/useNUI.ts`. Apply these changes:

1. Add `LoanData` import
2. Add `loan?`, `personalLoan?`, `companyLoan?` fields to `NUIMessage`
3. Add `updateLoan` case to the switch
4. Update `open` case to hydrate loan stores from `getInitialData`

Replace the entire file with:

```ts
import { useEffect } from 'react'
import { useAppStore } from '../stores/useAppStore'
import { useJobStore } from '../stores/useJobStore'
import { useCompanyStore } from '../stores/useCompanyStore'
import { useIndustryStore } from '../stores/useIndustryStore'
import { useStatsStore } from '../stores/useStatsStore'
import type { Job, ActiveJob, Company, Member, Vehicle, Industry, Stats, Skills } from '../types'
import type { LoanData } from '../types/loan'

interface NUIMessage {
  action:               string
  jobs?:                Job[]
  company?:             Company | null
  activeJob?:           ActiveJob | null
  stats?:               Stats | null
  skills?:              Partial<Skills>
  recruitingCompanies?: Company[]
  members?:             Member[]
  vehicles?:            Vehicle[]
  industries?:          Record<string, Industry>
  refreshStats?:        boolean
  // Loans
  loan?:                LoanData
  personalLoan?:        LoanData | null
  companyLoan?:         LoanData | null
}

export function useNUI() {
  const { setOpen }                                                    = useAppStore()
  const { setJobs, setActiveJob }                                      = useJobStore()
  const { setCompany, setRecruitingList, setMembers, setVehicles, setCompanyLoan } = useCompanyStore()
  const { setIndustries }                                              = useIndustryStore()
  const { setStats, setSkills, setPersonalLoan }                       = useStatsStore()

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
          // Hydrate loan state from getInitialData
          setPersonalLoan(event.data.personalLoan ?? null)
          setCompanyLoan(event.data.companyLoan ?? null)
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
          break
        case 'updateIndustries':
          setIndustries(event.data.industries ?? {})
          break
        case 'updateLoan': {
          // Despacha para o store correto baseado em is_company_loan
          const loan = event.data.loan
          if (!loan) break
          if (loan.is_company_loan) {
            setCompanyLoan(loan)
          } else {
            setPersonalLoan(loan)
          }
          break
        }
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

- [x] **Step 2: Verify TypeScript compiles**

```bash
cd html
npm run build
```

Expected: build succeeds with no TypeScript errors. If there are errors about missing types, check that `LoanData` is correctly exported from `html/src/types/loan.ts`.

- [x] **Step 3: Commit**

```bash
git add html/src/hooks/useNUI.ts
git commit -m "feat(loans): update useNUI hook with updateLoan case and open hydration"
```

---

## Task 8: LoanPanel component

**Files:**
- Create: `html/src/components/loans/LoanPanel.tsx`

- [x] **Step 1: Create the LoanPanel component**

Create the directory `html/src/components/loans/` and the file `LoanPanel.tsx`:

```tsx
import { useState } from 'react'
import { useStatsStore } from '../../stores/useStatsStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { LoanData, LoanStatus } from '../../types/loan'

interface LoanPanelProps {
  isCompany: boolean
}

function formatCountdown(unixTs: number): string {
  const diff = unixTs - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'VENCIDO'
  const days  = Math.floor(diff / 86400)
  const hours = Math.floor((diff % 86400) / 3600)
  if (days > 0) return `${days}d ${hours}h`
  const mins = Math.floor((diff % 3600) / 60)
  return `${hours}h ${mins}m`
}

function statusBadge(status: LoanStatus) {
  if (status === 'paid')      return <span className="text-xs px-2 py-0.5 rounded bg-zinc-700 text-zinc-400">QUITADO</span>
  if (status === 'defaulted') return <span className="text-xs px-2 py-0.5 rounded bg-red-900/40 text-red-400">INADIMPLENTE</span>
  return <span className="text-xs px-2 py-0.5 rounded bg-green-900/40 text-green-400">ATIVO</span>
}

function LoanCard({ loan, isCompany }: { loan: LoanData; isCompany: boolean }) {
  const [payAmount, setPayAmount]   = useState(String(loan.monthly_payment))
  const [loading, setLoading]       = useState(false)
  const [error, setError]           = useState<string | null>(null)
  const { setPersonalLoan }         = useStatsStore()
  const { setCompanyLoan }          = useCompanyStore()

  const isOverdue = loan.next_payment_at < Math.floor(Date.now() / 1000)

  const handlePay = async () => {
    const amount = parseInt(payAmount, 10)
    if (isNaN(amount) || amount < loan.monthly_payment) {
      setError(`Mínimo: $${loan.monthly_payment.toLocaleString()}`)
      return
    }
    setLoading(true)
    setError(null)

    const result = await fetchNUI<{ success: boolean; remaining_balance?: number; status?: string; reason?: string }>(
      'payLoan',
      { loanId: loan.id, amount, isCompanyLoan: isCompany }
    )

    setLoading(false)

    if (!result.success) {
      setError(result.reason ?? 'Erro ao processar pagamento')
      return
    }

    // Atualizar store local com novo saldo
    const updated: LoanData = {
      ...loan,
      remaining_balance: result.remaining_balance ?? 0,
      status: (result.status as LoanData['status']) ?? loan.status,
    }

    if (isCompany) setCompanyLoan(updated.status === 'paid' ? null : updated)
    else           setPersonalLoan(updated.status === 'paid' ? null : updated)
  }

  return (
    <div className={`rounded-lg p-3 border ${isOverdue ? 'border-red-500/40 bg-red-900/10' : 'border-zinc-700/50 bg-zinc-800/60'}`}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-zinc-400 font-medium uppercase tracking-wider">
          {isCompany ? 'Empréstimo Empresarial' : 'Empréstimo Pessoal'}
        </span>
        {statusBadge(loan.status)}
      </div>

      <div className="grid grid-cols-3 gap-2 mb-3 text-center">
        <div>
          <p className="text-lg font-bold text-zinc-100">${loan.remaining_balance.toLocaleString()}</p>
          <p className="text-[10px] text-zinc-500 uppercase">Saldo Devedor</p>
        </div>
        <div>
          <p className="text-lg font-bold text-amber-400">${loan.monthly_payment.toLocaleString()}</p>
          <p className="text-[10px] text-zinc-500 uppercase">Parcela Mín.</p>
        </div>
        <div>
          <p className={`text-lg font-bold ${isOverdue ? 'text-red-400' : 'text-zinc-300'}`}>
            {formatCountdown(loan.next_payment_at)}
          </p>
          <p className="text-[10px] text-zinc-500 uppercase">Vencimento</p>
        </div>
      </div>

      {loan.status === 'active' && (
        <div className="flex gap-2">
          <input
            type="number"
            value={payAmount}
            onChange={(e) => setPayAmount(e.target.value)}
            min={loan.monthly_payment}
            max={loan.remaining_balance}
            className="flex-1 bg-zinc-700/50 border border-zinc-600 rounded px-2 py-1.5 text-sm text-zinc-100 focus:outline-none focus:border-amber-500/50"
            placeholder={`$${loan.monthly_payment.toLocaleString()}`}
          />
          <button
            onClick={handlePay}
            disabled={loading}
            className="px-4 py-1.5 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-white rounded text-sm transition-colors font-medium"
          >
            {loading ? '...' : 'Pagar'}
          </button>
        </div>
      )}

      {error && <p className="text-xs text-red-400 mt-1.5">{error}</p>}
    </div>
  )
}

export function LoanPanel({ isCompany }: LoanPanelProps) {
  const { personalLoan } = useStatsStore()
  const { companyLoan }  = useCompanyStore()

  const loan = isCompany ? companyLoan : personalLoan

  if (!loan || loan.status === 'paid') {
    return (
      <div className="rounded-lg p-3 border border-zinc-700/30 bg-zinc-800/30 text-center">
        <p className="text-xs text-zinc-500">Nenhum empréstimo ativo</p>
        <p className="text-[10px] text-zinc-600 mt-0.5">Visite o banco em Paleto Bay para solicitar</p>
      </div>
    )
  }

  return <LoanCard loan={loan} isCompany={isCompany} />
}
```

- [x] **Step 2: Verify TypeScript compiles**

```bash
cd html
npm run build
```

Expected: no TypeScript errors. Common issue: if `LoanData` type isn't exported correctly, check `html/src/types/loan.ts`.

- [x] **Step 3: Commit**

```bash
git add html/src/components/loans/LoanPanel.tsx
git commit -m "feat(loans): add LoanPanel React component"
```

---

## Task 9: Integration into StatsPanel + CompanyPanel, final build

**Files:**
- Modify: `html/src/components/stats/StatsPanel.tsx`
- Modify: `html/src/components/company/CompanyPanel.tsx`

- [x] **Step 1: Add LoanPanel to StatsPanel.tsx**

Open `html/src/components/stats/StatsPanel.tsx`. Add the import at the top:

```ts
import { LoanPanel } from '../loans/LoanPanel'
```

Then find the closing `</div>` of the main `<div className="space-y-4 h-full overflow-auto">` wrapper and add the LoanPanel just before the closing tag (after SkillTree section):

```tsx
      {/* Empréstimo Pessoal */}
      <LoanPanel isCompany={false} />
```

- [x] **Step 2: Add LoanPanel to CompanyPanel.tsx**

Open `html/src/components/company/CompanyPanel.tsx`. Add the import at the top:

```ts
import { LoanPanel } from '../loans/LoanPanel'
```

Find the section with `{isOwner && (` at the bottom (sell company button). Add the LoanPanel **before** that block, but **after** `<MemberList />`, only for owner/manager:

```tsx
      {/* Empréstimo Empresarial — visível para Owner e Manager */}
      {isManager && (
        <div>
          <p className="text-xs text-zinc-500 uppercase tracking-wider mb-2">Empréstimo</p>
          <LoanPanel isCompany={true} />
        </div>
      )}
```

- [x] **Step 3: Production build**

```bash
cd html
npm run build
```

Expected: build completes, outputs `html/assets/index-[hash].js` and `html/assets/index-[hash].css`. No TypeScript errors.

- [x] **Step 4: Manual end-to-end test**

With the FiveM server running, test the full flow:

```
1. Go to Paleto Bay Bank (-2962.6, 485.6, 15.7)
2. Interact with NPC banker → "Solicitar empréstimo" (pessoal)
3. Enter $100.000 → confirm simulation → Contratar
   Expected: lib.notify "Empréstimo aprovado — $100.000 creditado"
   Expected: aba Estatísticas shows "Saldo Devedor: $100.000, Parcela Mín.: $26.250"

4. Open NUI (Estatísticas) → enter payment $26.250 → Pagar
   Expected: remaining_balance reduces to $73.750

5. Try to take a second personal loan
   Expected: "Você já tem um empréstimo pessoal ativo"

6. Force overdue via DB:
   UPDATE trucker_loans SET next_payment_at = DATE_SUB(NOW(), INTERVAL 1 HOUR)
   WHERE id = <your loan id>;
   Wait 5 minutes (or reduce Config.Loans.CheckInterval to 10 for testing)
   Expected: Console shows "Loan #N overdue — penalty applied"
   Expected: remaining_balance in DB = original * 1.15

7. Pay off fully (enter remaining_balance as payment)
   Expected: status = 'paid', LoanPanel shows "Nenhum empréstimo ativo"
```

- [x] **Step 5: Commit final build**

```bash
git add html/src/components/stats/StatsPanel.tsx html/src/components/company/CompanyPanel.tsx html/assets/
git commit -m "feat(loans): integrate LoanPanel into StatsPanel and CompanyPanel, production build"
```

---

## Task 10: Documentation update

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `fxmanifest.lua` (version bump)

- [x] **Step 1: Add v5.0.0 entry to CHANGELOG.md**

Open `CHANGELOG.md` and prepend before the `## [4.0.0]` section:

```markdown
## [5.0.0] — 2026-03-19

### Empréstimos (Loans) — Fase 4

**Adicionado**
- `server/services/loan_service.lua` — `LoanService` global: `Create`, `Pay`, `CheckOverdue`
- `server/database.lua` — 5 funções `DB_Loan*`: `DB_CreateLoan`, `DB_GetActiveLoan`, `DB_GetActiveCompanyLoan`, `DB_UpdateLoanBalance`, `DB_GetOverdueLoans`
- `html/src/types/loan.ts` — interface TypeScript `LoanData` com `LoanStatus`
- `html/src/components/loans/LoanPanel.tsx` — componente de empréstimo com countdown de vencimento, input de pagamento, badge de status
- NPC banqueiro em Paleto Bay com blip e ox_target (coordenadas configuráveis em `Config.Loans.BankerLocation`)
- Thread de verificação de inadimplência (a cada `Config.Loans.CheckInterval` segundos) com penalidade de 15%

**Modificado**
- `config/config.lua` — bloco `Config.Loans` adicionado
- `server/callbacks.lua` — callbacks `getLoanData`, `payLoan`; `getInitialData` retorna `personalLoan` e `companyLoan`
- `server/events.lua` — evento `requestLoan` (fire-and-forget do NPC)
- `fxmanifest.lua` — `loan_service.lua` na load order (após `company_service.lua`)
- `html/src/stores/useStatsStore.ts` — `personalLoan?: LoanData`
- `html/src/stores/useCompanyStore.ts` — `companyLoan?: LoanData`
- `html/src/hooks/useNUI.ts` — caso `updateLoan` + hidratação em `open`
- `html/src/components/stats/StatsPanel.tsx` — seção "Empréstimo Pessoal"
- `html/src/components/company/CompanyPanel.tsx` — seção "Empréstimo Empresarial" (owner/manager)

**Regras de negócio**

| Parâmetro | Valor |
|---|---|
| Valor mínimo | $10.000 |
| Valor máximo | $500.000 |
| Juros | 5% |
| Parcelas | 4 semanais |
| Multa por atraso | 15% sobre saldo devedor |
| Limite por entidade | 1 ativo (pessoal e empresarial são independentes) |

**Nota Fase 6:** Integração com `trucker_repo_orders` na inadimplência aguarda migração de schema (Fase 6 — Repo Man).
```

- [x] **Step 2: Bump version in fxmanifest.lua**

Change `version '4.0.0'` to `version '5.0.0'`.

- [x] **Step 3: Commit**

```bash
git add CHANGELOG.md fxmanifest.lua
git commit -m "chore: bump version to 5.0.0, add loans CHANGELOG entry"
```
