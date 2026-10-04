-- aurp_trucker — server/services/company_service.lua
-- Gerenciamento de empresas: CRUD, membros, veículos, financeiro

CompanyService = {}

local CREATION_COST = 150000
local SELL_PAYOUT   = 25000

-- Retorna perks da empresa a partir do nível (busca linear na tabela de config)
local function GetPerksForLevel(level)
    local levels = Config.CompanyLevels
    for _, entry in ipairs(levels) do
        if entry.level == level then return entry end
    end
    return levels[1]  -- fallback seguro
end

-- Retorna empresa do cache ou nil
function CompanyService.Get(companyId)
    return VP_Trucker.Companies[companyId]
end

-- Retorna perks (vehicles, members, bonus) da empresa com base no nível em cache
function CompanyService.GetPerks(companyId)
    local company = VP_Trucker.Companies[companyId]
    local level   = (company and company.company_level) or 1
    return GetPerksForLevel(level)
end

-- Concede XP de entrega à empresa; aplica level-up(s) se necessário (loop)
function CompanyService.AddXP(companyId, xp)
    local company = VP_Trucker.Companies[companyId]
    if not company then return end

    local row = DB_AddCompanyXP(companyId, xp)
    if not row then return end

    -- Atualizar cache de XP
    company.company_xp    = row.company_xp
    company.company_level = row.company_level

    -- Loop de level-up: um único job pode cruzar múltiplos thresholds se o XP/job for alto
    local levels   = Config.CompanyLevels
    local maxLevel = #levels
    local changed  = false

    while company.company_level < maxLevel do
        local nextEntry = levels[company.company_level + 1]
        if nextEntry and company.company_xp >= nextEntry.xpRequired then
            company.company_level = company.company_level + 1
            changed = true
            if Config.Debug then
                print(('[aurp_trucker] Company %s → nível %d'):format(companyId, company.company_level))
            end
        else
            break
        end
    end

    if changed then
        DB_SetCompanyLevel(companyId, company.company_level)
    end
end

-- Retorna empresa do jogador pelo citizenId
function CompanyService.GetByMember(citizenId)
    local companyId = VP_Trucker.PlayerCompanies[citizenId]
    if not companyId then return nil end
    return VP_Trucker.Companies[companyId]
end

-- Retorna lista de empresas recrutando
function CompanyService.GetRecruiting()
    return DB_GetRecruitingCompanies()
end

local CreatingCompanyLock = {}
local SellingCompanyLock = {}

-- Valida/normaliza nome: string, sem caracteres de controle, trim, 3-30 chars
local function SanitizeCompanyName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #name < 3 or #name > 30 then return nil end
    return name
end

local function NewCompanyId()
    local t = {}
    for i = 1, 8 do t[i] = ('%x'):format(math.random(0, 15)) end
    return ('company_%d_%s'):format(os.time(), table.concat(t))
end

local function CreateUnlocked(src, Player, citizenId, name, companyType)
    -- Verificar se já tem empresa
    if VP_Trucker.PlayerCompanies[citizenId] then
        return nil, 'Você já faz parte de uma empresa'
    end

    -- Verificar saldo
    if Framework.GetMoney(Player, 'cash') < CREATION_COST then
        return nil, ('Você precisa de $%d para criar uma empresa'):format(CREATION_COST)
    end

    -- Cobrar
    if not Framework.RemoveMoney(Player, 'cash', CREATION_COST, 'company-creation') then
        return nil, 'Falha ao processar pagamento'
    end

    -- Criar no DB (estorna se falhar)
    local companyId = NewCompanyId()
    local ok, err = pcall(function()
        DB_CreateCompany(companyId, citizenId, name, companyType)
        DB_AddMember(companyId, citizenId, 'owner')
    end)
    if not ok then
        print(('[aurp_trucker] CompanyService.Create erro (%s): %s - estornando'):format(tostring(citizenId), tostring(err)))
        pcall(DB_DeleteCompany, companyId)
        Framework.AddMoney(Player, 'cash', CREATION_COST, 'company-creation-refund')
        return nil, 'Falha ao criar empresa. Valor estornado.'
    end

    -- Atualizar cache (inclui company_type para RepoService.Accept)
    VP_Trucker.Companies[companyId] = {
        id              = companyId,
        owner_citizenid = citizenId,
        name            = name,
        balance         = 0,
        is_recruiting   = 0,
        company_type    = companyType,
        company_level   = 1,
        company_xp      = 0,
    }
    VP_Trucker.PlayerCompanies[citizenId] = companyId

    return companyId, nil
end

-- Cria nova empresa. Retorna companyId ou nil + mensagem de erro
function CompanyService.Create(src, name, companyType)
    companyType = (companyType == 'repo') and 'repo' or 'logistics'

    name = SanitizeCompanyName(name)
    if not name then return nil, 'Nome inválido (3 a 30 caracteres)' end

    local Player = Framework.GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end

    local citizenId = Framework.GetCitizenId(Player)

    -- Lock por jogador: impede criação dupla concorrente
    if CreatingCompanyLock[citizenId] then
        return nil, 'Operação em andamento, aguarde'
    end
    CreatingCompanyLock[citizenId] = true
    local ok, companyId, err = pcall(CreateUnlocked, src, Player, citizenId, name, companyType)
    CreatingCompanyLock[citizenId] = nil
    if not ok then
        print('[aurp_trucker] CompanyService.Create erro: ' .. tostring(companyId))
        return nil, 'Erro interno ao criar empresa'
    end
    return companyId, err
end

-- Adiciona membro à empresa
function CompanyService.AddMember(companyId, citizenId)
    if VP_Trucker.PlayerCompanies[citizenId] then
        return false, 'Jogador já está em uma empresa'
    end

    local perks   = CompanyService.GetPerks(companyId)
    local members = DB_GetMembers(companyId) or {}
    if #members >= perks.members then
        return false, ('Limite de %d membros atingido para o nível atual'):format(perks.members)
    end

    DB_AddMember(companyId, citizenId, 'driver')
    VP_Trucker.PlayerCompanies[citizenId] = companyId
    return true, nil
end

-- Remove membro da empresa
function CompanyService.RemoveMember(citizenId)
    VP_Trucker.PlayerCompanies[citizenId] = nil
    DB_RemoveMember(citizenId)
end

-- Toggle recrutamento
function CompanyService.SetRecruiting(companyId, isRecruiting)
    local company = VP_Trucker.Companies[companyId]
    if not company then return end
    company.is_recruiting = isRecruiting and 1 or 0
    DB_SetCompanyRecruiting(companyId, isRecruiting)
end

-- Depósito no banco da empresa
function CompanyService.Deposit(companyId, src, amount)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    -- #2: Validar amount + verificar retorno RemoveMoney (TOCTOU fix)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Valor inválido' end
    if Framework.GetMoney(Player, 'cash') < amount then return false, 'Saldo insuficiente' end

    local removed = Framework.RemoveMoney(Player, 'cash', amount, 'company-deposit')
    if not removed then return false, 'Falha ao remover dinheiro' end

    local newBalance = DB_UpdateCompanyBalance(companyId, amount)
    if not newBalance then
        -- Crédito na empresa falhou: devolve o dinheiro ao jogador
        Framework.AddMoney(Player, 'cash', amount, 'company-deposit-refund')
        return false, 'Falha ao depositar na empresa'
    end
    if VP_Trucker.Companies[companyId] then
        VP_Trucker.Companies[companyId].balance = newBalance
    end
    return true, nil
end

-- Saque do banco da empresa (apenas owner/manager)
function CompanyService.Withdraw(companyId, src, citizenId, amount)
    -- #3: Validar amount (previne exploit negativo)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Valor inválido' end

    -- C-05: Validação de role na camada de serviço (defesa em profundidade)
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return false, 'Sem permissão para sacar'
    end

    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end
    if company.balance < amount then return false, 'Saldo insuficiente na empresa' end

    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    -- #3: Debitar empresa (atômico: só debita se balance >= amount), creditar jogador,
    -- estorno em falha. O jogador só recebe depois de o débito ser confirmado no DB.
    local newBalance = DB_UpdateCompanyBalance(companyId, -amount)
    if not newBalance then return false, 'Saldo insuficiente na empresa' end
    VP_Trucker.Companies[companyId].balance = newBalance
    local added = Framework.AddMoney(Player, 'cash', amount, 'company-withdrawal')
    if not added then
        -- Estorno: devolver à empresa
        local restored = DB_UpdateCompanyBalance(companyId, amount)
        if restored then VP_Trucker.Companies[companyId].balance = restored end
        return false, 'Falha ao creditar jogador'
    end
    return true, nil
end

-- Registrar veículo na empresa
function CompanyService.RegisterVehicle(companyId, plate, model, vehicleType)
    if DB_VehicleExists(plate) then
        return false, 'Este veículo já está registrado em uma empresa'
    end
    local perks    = CompanyService.GetPerks(companyId)
    local vehicles = DB_GetVehicles(companyId) or {}
    if #vehicles >= perks.vehicles then
        return false, ('Limite de %d veículos atingido para o nível atual'):format(perks.vehicles)
    end
    DB_RegisterVehicle(companyId, plate, model, vehicleType)
    return true, nil
end

-- Remover veículo da empresa
function CompanyService.RemoveVehicle(plate)
    DB_RemoveVehicle(plate)
end

-- Credita/débita saldo da empresa e atualiza cache.
-- amount pode ser positivo (crédito) ou negativo (débito).
-- Retorna (true, newBalance) em sucesso; (false, reason) em falha.
function CompanyService.AddBalance(companyId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return false, 'Valor inválido' end

    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end

    -- Fail-closed para evitar saldo negativo por corrida/estado desatualizado.
    if amount < 0 then
        local current = tonumber(company.balance) or 0
        if current < math.abs(amount) then
            return false, 'Saldo insuficiente'
        end
    end

    local newBalance = DB_UpdateCompanyBalance(companyId, amount)
    if newBalance == nil then
        return false, 'Falha ao atualizar saldo'
    end
    company.balance = newBalance
    return true, newBalance
end

local function SellUnlocked(companyId, src)
    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end

    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    if Framework.GetCitizenId(Player) ~= company.owner_citizenid then
        return false, 'Apenas o dono pode vender a empresa'
    end

    -- HARDENING: Verificar se há veículos da frota em uso
    local vehicles = DB_GetVehicles(companyId) or {}
    for _, v in ipairs(vehicles) do
        if v.status == 'out' then
            return false, 'Guarde todos os veículos da frota antes de vender a empresa.'
        end
    end

    local members = DB_GetMembers(companyId) or {}

    -- Re-checa o cache após os awaits: outra chamada pode ter vendido a empresa
    if VP_Trucker.Companies[companyId] ~= company then
        return false, 'Empresa não encontrada'
    end

    -- HARDENING: reivindica a venda atomicamente — o DELETE só ocorre se NÃO houver
    -- empréstimo empresarial ativo; só quem apagou a linha recebe o pagamento.
    local affected = DB_DeleteCompanyIfNoActiveLoan(companyId)
    if not affected or affected < 1 then
        return false, 'A empresa possui empréstimo ativo. Quite-o antes de vender.'
    end

    local balanceRefund = math.max(0, tonumber(company.balance) or 0)
    local totalPayout = SELL_PAYOUT + balanceRefund

    -- Limpar cache de todos os membros
    for _, member in ipairs(members) do
        VP_Trucker.PlayerCompanies[member.citizenid] = nil
    end
    VP_Trucker.Companies[companyId] = nil

    if not Framework.AddMoney(Player, 'cash', totalPayout, 'company-sale') then
        print(('[aurp_trucker] ERRO: empresa %s vendida mas pagamento de $%d falhou para %s'):format(
            tostring(companyId), totalPayout, tostring(company.owner_citizenid)))
    end
    return true, nil
end

-- Vender empresa (owner recebe SELL_PAYOUT, empresa é deletada)
function CompanyService.Sell(companyId, src)
    if SellingCompanyLock[companyId] then
        return false, 'Operação em andamento, aguarde'
    end
    SellingCompanyLock[companyId] = true
    local ok, res, err = pcall(SellUnlocked, companyId, src)
    SellingCompanyLock[companyId] = nil
    if not ok then
        print('[aurp_trucker] CompanyService.Sell erro: ' .. tostring(res))
        return false, 'Erro interno ao vender empresa'
    end
    return res, err
end
