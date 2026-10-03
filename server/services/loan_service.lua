LoanService = {}

local MIN_AMOUNT        = Config.Loans.MinAmount
local MAX_AMOUNT        = Config.Loans.MaxAmount
local INTEREST_RATE     = Config.Loans.InterestRate
local NUM_INSTALLMENTS  = Config.Loans.NumInstallments
local INSTALLMENT_SECONDS = Config.Loans.InstallmentDays * 86400
local PENALTY_RATE      = Config.Loans.PenaltyRate
local CHECK_INTERVAL    = Config.Loans.CheckInterval

-- Travas em memória (chave = 'p:<citizen>' | 'c:<empresa>' | 'l:<emprestimo>'): as checagens
-- de "já tem empréstimo"/saldo e as escritas ficam separadas por awaits de DB, então sem
-- trava chamadas simultâneas criariam vários empréstimos ou pagariam duas vezes.
local LoanLocks = {}

local function WithLoanLock(key, fn, ...)
    if LoanLocks[key] then
        return { success = false, reason = 'Operação em andamento, tente novamente' }
    end
    LoanLocks[key] = true
    local ok, result = pcall(fn, ...)
    LoanLocks[key] = nil
    if not ok then
        print(('[aurp_trucker] LoanService erro (%s): %s'):format(key, tostring(result)))
        return { success = false, reason = 'Erro interno ao processar empréstimo' }
    end
    return result
end

local function IsValidNumber(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

---Creates a new loan and credits the player.
---@param src number  player server id
---@param citizenId string
---@param companyId number|nil  nil for personal loans
---@param amount number
---@param vehiclePlate string|nil  optional collateral vehicle plate (6A)
---@return table  { success: boolean, loan?: table, reason?: string }
local function CreateUnlocked(src, citizenId, companyId, amount, vehiclePlate)
    -- Validate amount (rejeita NaN/inf/não numérico vindo do client)
    amount = tonumber(amount)
    if not IsValidNumber(amount) then
        return { success = false, reason = 'Valor inválido' }
    end
    amount = math.floor(amount)
    if amount < MIN_AMOUNT or amount > MAX_AMOUNT then
        return { success = false, reason = ('Valor fora do intervalo permitido ($%s–$%s)'):format(
            MIN_AMOUNT, MAX_AMOUNT) }
    end

    -- Teto por nível do motorista (mesma regra dos planos)
    local info = LoanService.GetPlans(citizenId)
    if amount > info.maxAllowed then
        return { success = false, reason = ('Nível de motorista insuficiente: limite atual $%s'):format(info.maxAllowed) }
    end

    -- Check for existing active loan
    local existing
    if companyId then
        existing = DB_GetActiveCompanyLoan(companyId)
    else
        existing = DB_GetActiveLoan(citizenId)
    end

    if existing then
        local loanType = companyId and 'empresarial' or 'pessoal'
        return { success = false, reason = ('Você já tem um empréstimo %s ativo'):format(loanType) }
    end

    -- Validate player exists before creating loan
    local Player = Framework.GetPlayer(src)
    if not Player then
        return { success = false, reason = 'Jogador não encontrado' }
    end

    -- Calculate totals
    local totalToPay     = math.ceil(amount * (1 + INTEREST_RATE))
    local monthlyPayment = math.ceil(totalToPay / NUM_INSTALLMENTS)
    local nextPaymentAt  = os.time() + INSTALLMENT_SECONDS

    local loanId = DB_CreateLoan(citizenId, companyId, vehiclePlate, amount, totalToPay, monthlyPayment, nextPaymentAt)
    if not loanId then
        return { success = false, reason = 'Erro interno ao criar empréstimo' }
    end

    -- Desembolso: empréstimo empresarial vai para o cofre da empresa; pessoal para o jogador.
    -- Se o crédito falhar, desfaz o empréstimo (não deixa dívida sem dinheiro recebido).
    if companyId then
        local newCompanyBalance = DB_UpdateCompanyBalance(companyId, amount)
        if not newCompanyBalance then
            DB_DeleteLoan(loanId)
            return { success = false, reason = 'Erro ao creditar a empresa' }
        end
        if VP_Trucker.Companies[companyId] then
            VP_Trucker.Companies[companyId].balance = newCompanyBalance
        end
    else
        if not Framework.AddMoney(Player, 'cash', amount, 'loan-disbursement') then
            DB_DeleteLoan(loanId)
            return { success = false, reason = 'Erro ao creditar o valor' }
        end
    end

    local loan = {
        id               = loanId,
        amount           = amount,
        remaining_balance = totalToPay,
        monthly_payment  = monthlyPayment,
        next_payment_at  = nextPaymentAt,
        status           = 'active',
        is_company_loan  = companyId ~= nil,
        vehicle_plate    = vehiclePlate or nil,
    }

    return { success = true, loan = loan }
end

function LoanService.Create(src, citizenId, companyId, amount, vehiclePlate)
    local key = companyId and ('c:' .. tostring(companyId)) or ('p:' .. tostring(citizenId))
    return WithLoanLock(key, CreateUnlocked, src, citizenId, companyId, amount, vehiclePlate)
end

---Processes a loan payment.
---@param src number
---@param citizenId string
---@param companyId number|nil
---@param loanId number
---@param amount number
---@return table  { success: boolean, remaining_balance?: number, status?: string, reason?: string }
local function PayUnlocked(src, citizenId, companyId, loanId, amount)
    -- Fetch the active loan (filter by status='active' via the correct lookup)
    local loan
    if companyId then
        -- Verify this is the active company loan with the matching id
        local activeLoan = DB_GetActiveCompanyLoan(companyId)
        if activeLoan and activeLoan.id == loanId then
            loan = activeLoan
        end
    else
        local activeLoan = DB_GetActiveLoan(citizenId)
        if activeLoan and activeLoan.id == loanId then
            loan = activeLoan
        end
    end

    if not loan then
        return { success = false, reason = 'Empréstimo não encontrado ou já quitado' }
    end

    -- Validate payment amount
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return { success = false, reason = 'Valor inválido' }
    end
    if amount < loan.monthly_payment and amount < loan.remaining_balance then
        return { success = false, reason = ('Valor mínimo: $%s'):format(loan.monthly_payment) }
    end
    if amount > loan.remaining_balance then
        amount = loan.remaining_balance
    end

    local Player = Framework.GetPlayer(src)
    if not Player then
        return { success = false, reason = 'Jogador não encontrado' }
    end

    -- Validar fundos totais ANTES de qualquer débito (Fail-Closed)
    local cash = Framework.GetMoney(Player, 'cash') or 0
    local bank = Framework.GetMoney(Player, 'bank') or 0
    if (cash + bank) < amount then
        return { success = false, reason = 'Fundos insuficientes (dinheiro + banco)' }
    end

    -- Débito transacional com suporte a rollback (cash primeiro, depois banco)
    local cashPaid = math.min(cash, amount)
    local bankPaid = amount - cashPaid

    if cashPaid > 0 then
        local okCash = Framework.RemoveMoney(Player, 'cash', cashPaid, 'loan-payment')
        if not okCash then
            return { success = false, reason = 'Falha ao debitar dinheiro em mãos' }
        end
    end

    if bankPaid > 0 then
        local okBank = Framework.RemoveMoney(Player, 'bank', bankPaid, 'loan-payment')
        if not okBank then
            -- Estorno de segurança do valor em mãos se o banco falhar
            if cashPaid > 0 then
                Framework.AddMoney(Player, 'cash', cashPaid, 'loan-payment-refund')
            end
            return { success = false, reason = 'Falha ao debitar saldo bancário' }
        end
    end

    -- Calculate new balance
    local newBalance = loan.remaining_balance - amount
    local newStatus, nextPaymentAt

    if newBalance <= 0 then
        newBalance    = 0
        newStatus     = 'paid'
        nextPaymentAt = nil
    else
        newStatus     = 'active'
        -- Advance from stored next_payment_at, not os.time()
        nextPaymentAt = (loan.next_payment_at or os.time()) + INSTALLMENT_SECONDS
    end

    local affected = DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)
    if not affected or affected == 0 then
        -- Empréstimo mudou/quitou entre a leitura e a escrita: devolve o que foi debitado
        if cashPaid > 0 then Framework.AddMoney(Player, 'cash', cashPaid, 'loan-payment-refund') end
        if bankPaid > 0 then Framework.AddMoney(Player, 'bank', bankPaid, 'loan-payment-refund') end
        return { success = false, reason = 'Empréstimo não encontrado ou já quitado' }
    end

    return { success = true, remaining_balance = newBalance, status = newStatus }
end

function LoanService.Pay(src, citizenId, companyId, loanId, amount)
    loanId = tonumber(loanId)
    if not loanId then return { success = false, reason = 'Empréstimo inválido' } end
    return WithLoanLock('l:' .. loanId, PayUnlocked, src, citizenId, companyId, loanId, amount)
end

---Checks all overdue loans and applies 15% penalty.
function LoanService.CheckOverdue()
    local loans = DB_GetOverdueLoans()
    if not loans or #loans == 0 then return end

    for _, loan in ipairs(loans) do
      -- pcall por empréstimo: uma linha ruim não pode abortar o ciclo nem matar a thread
      local okLoan, errLoan = pcall(function()
        local newBalance    = math.ceil(loan.remaining_balance * (1 + PENALTY_RATE))
        local nextPaymentAt = os.time() + INSTALLMENT_SECONDS

        DB_UpdateLoanBalance(loan.id, newBalance, 'active', nextPaymentAt)

        -- Generate repo order for the defaulted loan (post-penalty balance)
        if RepoService then
            loan.remaining_balance = newBalance   -- pass post-penalty balance
            RepoService.GenerateFromLoan(loan)
        end

        print(('[aurp_trucker] Loan #%d overdue — penalty applied. New balance: $%d'):format(
            loan.id, newBalance))

        -- Notify player if online
        local loanPlayerSrc = Framework.FindPlayerByCitizenId(loan.citizenid)
        if loanPlayerSrc then
            lib.notify(loanPlayerSrc, {
                title       = 'Empréstimo em Atraso',
                description = ('Multa de 15%% aplicada. Novo saldo: $%s'):format(newBalance),
                type        = 'error',
                duration    = 8000,
            })
        end
      end)
      if not okLoan then
        print(('[aurp_trucker] CheckOverdue erro no empréstimo #%s: %s'):format(tostring(loan.id), tostring(errLoan)))
      end
    end
end

-- Planos do lc_truck_logistics
function LoanService.GetPlans(citizenId)
    local plans = Config.LC_Loans and Config.LC_Loans.plans or {
        { loan_amount = 20000,  interest_rate = 20.0, repayment_days = 15 },
        { loan_amount = 50000,  interest_rate = 17.5, repayment_days = 20 },
        { loan_amount = 100000, interest_rate = 15.0, repayment_days = 25 },
        { loan_amount = 400000, interest_rate = 12.5, repayment_days = 30 },
    }
    local playerStats = DB_GetPlayerStats(citizenId)
    local level = playerStats and playerStats.level or 1
    local maxAllowed = 40000
    if level >= 30 then maxAllowed = 600000
    elseif level >= 20 then maxAllowed = 250000
    elseif level >= 10 then maxAllowed = 100000 end

    local activeLoan = DB_GetActiveLoan(citizenId)

    return {
        plans = plans,
        maxAllowed = maxAllowed,
        currentLevel = level,
        activeLoan = activeLoan
    }
end

local function TakePlanUnlocked(src, citizenId, planIndex)
    local info = LoanService.GetPlans(citizenId)
    local plan = info.plans[planIndex]
    if not plan then
        return { success = false, reason = 'Plano de empréstimo não encontrado' }
    end

    if plan.loan_amount > info.maxAllowed then
        return { success = false, reason = 'Nível de motorista insuficiente para este plano' }
    end

    local existing = DB_GetActiveLoan(citizenId)
    if existing then
        return { success = false, reason = 'Você já possui um empréstimo ativo' }
    end

    local totalToPay = math.ceil(plan.loan_amount * (1 + (plan.interest_rate / 100)))
    local dailyPayment = math.ceil(totalToPay / plan.repayment_days)
    local nextPaymentAt = os.time() + 86400

    local loanId = DB_CreateLoan(citizenId, nil, nil, plan.loan_amount, totalToPay, dailyPayment, nextPaymentAt)
    if not loanId then
        return { success = false, reason = 'Erro ao processar empréstimo no banco de dados' }
    end

    if not Framework.AddPlayerMoney(src, 'bank', plan.loan_amount, 'Empréstimo Logística: Plano #' .. planIndex) then
        DB_DeleteLoan(loanId)
        return { success = false, reason = 'Erro ao creditar o valor do empréstimo' }
    end

    return {
        success = true,
        loan = {
            id = loanId,
            amount = plan.loan_amount,
            remaining_balance = totalToPay,
            daily_payment = dailyPayment,
            days = plan.repayment_days
        }
    }
end

function LoanService.TakePlan(src, citizenId, planIndex)
    planIndex = tonumber(planIndex)
    if not planIndex or planIndex ~= planIndex then
        return { success = false, reason = 'Plano de empréstimo não encontrado' }
    end
    -- Mesma trava do Create pessoal: planos e empréstimos livres não podem correr juntos
    return WithLoanLock('p:' .. tostring(citizenId), TakePlanUnlocked, src, citizenId, math.floor(planIndex))
end

-- Background thread: check overdue loans every CheckInterval seconds
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(CHECK_INTERVAL * 1000)
        local ok, err = pcall(LoanService.CheckOverdue)
        if not ok then
            print(('[aurp_trucker] CheckOverdue falhou: %s'):format(tostring(err)))
        end
    end
end)
