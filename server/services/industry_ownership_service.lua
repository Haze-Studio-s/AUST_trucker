-- aurp_trucker — server/services/industry_ownership_service.lua
-- Compra, lucro por venda e custo operacional de indústrias (Config.Industries)

IndustryOwnershipService = {}

-- ============================================================
-- HELPERS INTERNOS
-- ============================================================

local function GetCompanyOfPlayer(citizenId)
    local companyId = VP_Trucker.PlayerCompanies[citizenId]
    if not companyId then return nil end
    return VP_Trucker.Companies[companyId]
end

local function CountOwnedByCompany(companyId)
    local count = 0
    for _, owner in pairs(VP_Trucker.IndustryOwners) do
        if owner.company_id == companyId then count = count + 1 end
    end
    return count
end

-- ============================================================
-- INIT (chamado em main.lua após MySQL.ready)
-- ============================================================

function IndustryOwnershipService.LoadCache()
    local rows = DB_GetAllIndustryOwners() or {}
    for _, row in ipairs(rows) do
        VP_Trucker.IndustryOwners[row.industry_id] = row
    end
    if Config.Debug then
        print(('[aurp_trucker] IndustryOwnership: %d indústrias carregadas'):format(#rows))
    end
end

-- ============================================================
-- CONSULTA
-- ============================================================

function IndustryOwnershipService.GetOwner(industryId)
    return VP_Trucker.IndustryOwners[industryId]
end

-- Retorna lista de indústrias de uma empresa (enriquecidas com config)
function IndustryOwnershipService.GetCompanyOwned(companyId)
    local result = {}
    for industryId, owner in pairs(VP_Trucker.IndustryOwners) do
        if owner.company_id == companyId then
            local cfg = Config.Industries[industryId]
            table.insert(result, {
                industryId   = industryId,
                industryName = cfg and cfg.name or industryId,
                purchasePrice = owner.purchase_price,
                totalEarned   = owner.total_earned or 0,
                productionLevel = owner.production_level or 1,
                npcWorkers    = owner.npc_workers or 0,
            })
        end
    end
    return result
end

-- ============================================================
-- COMPRA
-- ============================================================

function IndustryOwnershipService.Buy(src, industryId)
    local Player = Framework.GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end

    local citizenId = Framework.GetCitizenId(Player)
    local company = GetCompanyOfPlayer(citizenId)
    if not company then
        return { success = false, reason = 'Você não pertence a uma empresa' }
    end
    if company.company_type ~= 'logistics' then
        return { success = false, reason = 'Apenas empresas de logística podem comprar indústrias' }
    end

    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Apenas Owner ou Manager podem comprar indústrias' }
    end

    -- Verificar se já tem dono
    if VP_Trucker.IndustryOwners[industryId] then
        return { success = false, reason = 'Esta indústria já pertence a outra empresa' }
    end

    -- Verificar limite por empresa
    local maxOwned = Config.IndustryOwnership.MaxOwnedPerCompany
    if CountOwnedByCompany(company.id) >= maxOwned then
        return { success = false, reason = ('Limite de %d indústrias por empresa atingido'):format(maxOwned) }
    end

    -- Calcular preço
    local cfg = Config.Industries[industryId]
    if not cfg or not cfg.production then
        return { success = false, reason = 'Indústria inválida ou não possui produção' }
    end
    local mult   = Config.IndustryOwnership.PurchasePriceMultiplier
    local price  = math.floor(cfg.production.basePrice * cfg.production.productionPerHour * mult)

    -- Debitar da empresa
    local companyRow = DB_GetCompany(company.id)
    if not companyRow or companyRow.balance < price then
        return { success = false, reason = ('Saldo insuficiente. Necessário: $%d'):format(price) }
    end

    -- Atômico: 1) reivindica a indústria (PK garante um único dono), 2) debita com
    -- 'balance >= preço'; se o débito falhar, libera a reivindicação.
    if not DB_TryClaimIndustry(industryId, citizenId, company.id, price) then
        return { success = false, reason = 'Esta indústria já pertence a outra empresa' }
    end

    local newBalance = DB_UpdateCompanyBalance(company.id, -price)
    if not newBalance then
        DB_ClearIndustryOwner(industryId)
        return { success = false, reason = ('Saldo insuficiente. Necessário: $%d'):format(price) }
    end
    if VP_Trucker.Companies[company.id] then
        VP_Trucker.Companies[company.id].balance = newBalance
    end

    -- Registrar no cache (DB já registrado pela reivindicação)
    VP_Trucker.IndustryOwners[industryId] = {
        industry_id     = industryId,
        owner_citizenid = citizenId,
        company_id      = company.id,
        purchase_price  = price,
        production_level = 1,
        npc_workers     = 0,
        total_earned    = 0,
    }

    if Config.Debug then
        print(('[aurp_trucker] IndustryOwnership: %s comprou %s por $%d'):format(company.id, industryId, price))
    end

    return { success = true, industryId = industryId, price = price }
end

-- ============================================================
-- HOOK DE PROFIT (chamado por IndustryService.BuyFrom)
-- ============================================================

-- Chamado após um jogador comprar itens da indústria.
-- Se a indústria tiver dono, 15% (configurável) vai para a empresa dona.
function IndustryOwnershipService.OnSale(industryId, totalSalePrice)
    local owner = VP_Trucker.IndustryOwners[industryId]
    if not owner or not owner.company_id then return end

    local profit = math.floor(totalSalePrice * Config.IndustryOwnership.OwnerProfitPercent)
    if profit <= 0 then return end

    -- DB_UpdateCompanyBalance retorna o saldo novo — usar o retorno para manter cache preciso
    local newBalance = DB_UpdateCompanyBalance(owner.company_id, profit)
    if VP_Trucker.Companies[owner.company_id] then
        VP_Trucker.Companies[owner.company_id].balance = newBalance
    end

    DB_AddOwnerEarnings(industryId, profit)
    if VP_Trucker.IndustryOwners[industryId] then
        VP_Trucker.IndustryOwners[industryId].total_earned =
            (VP_Trucker.IndustryOwners[industryId].total_earned or 0) + profit
    end
end

-- ============================================================
-- CUSTO OPERACIONAL (chamado pelo cron em industry_service.lua)
-- ============================================================

-- Deduz custo operacional de todas as empresas donas por ciclo de produção.
-- Se a empresa não tiver saldo, simplesmente não deduz (sem penalidade no MVP).
function IndustryOwnershipService.RunOperationalCosts()
    local cost = Config.IndustryOwnership.OperationalCostPerCycle
    if cost <= 0 then return end

    for industryId, owner in pairs(VP_Trucker.IndustryOwners) do
        if owner.company_id then
            local company = VP_Trucker.Companies[owner.company_id]
            if company and company.balance >= cost then
                local newBalance = DB_UpdateCompanyBalance(owner.company_id, -cost)
                if newBalance then
                    VP_Trucker.Companies[owner.company_id].balance = newBalance
                end
            end
        end
    end
end
