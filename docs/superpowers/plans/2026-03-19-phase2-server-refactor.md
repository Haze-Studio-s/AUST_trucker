# AUST_trucker — Fase 2: Server Refactor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Refatorar o `server.lua` monolítico (~2000 linhas) e `industries.server.lua` (~800 linhas) em serviços modulares, criar a camada de exports para `AUST_sala`, migrar callbacks para `ox_lib`, e garantir que jobs persistam entre restarts.

**Architecture:** Fase 2 de 3. Pré-requisito: Fase 1 concluída (QBX + oxmysql funcionando). Os dois arquivos monolíticos são decompostos em 4 services + callbacks + events + exports. A UI vanilla JS continua intacta até a Fase 3. Com `lua54 'yes'`, cada arquivo é um chunk isolado — todos os services são globais.

**Tech Stack:** Lua 5.4, qbx_core, ox_lib, oxmysql

---

## Contexto pré-Fase 2

```
server/
├── main.lua              — EXISTS (VP_Trucker global — modificação incremental permitida nas Tasks 3 e 7)
├── database.lua          — EXISTS (DB helpers — NÃO MODIFICAR)
├── server.lua            — DECOMPOR → services/ + events.lua
├── industries.server.lua — DECOMPOR → services/ + events.lua
├── exports.lua           — CRIAR
├── callbacks.lua         — CRIAR
├── events.lua            — CRIAR (RegisterNetEvent handlers apenas)
└── services/
    ├── company_service.lua   — CRIAR
    ├── job_service.lua       — CRIAR
    ├── economy_service.lua   — CRIAR
    └── industry_service.lua  — CRIAR
```

**Regra lua54:** Todos os services são tabelas globais (`CompanyService = {}`, etc.).
`VP_Trucker`, `DB_*` (database.lua) são globais — acessíveis em todos os arquivos.

## fxmanifest.lua — Load Order Final (após Fase 2)

Atualizar `fxmanifest.lua` ao iniciar esta fase:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/economy_service.lua',     -- antes de industry_service
    'server/services/industry_service.lua',
    'server/services/job_service.lua',         -- pode usar EconomyService
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
}
```

---

## Task 1: Atualizar fxmanifest + criar estrutura de pastas

**Files:**
- Modify: `fxmanifest.lua`
- Create: `server/services/` (diretório)

- [x] **Passo 1: Criar diretório services**

```bash
mkdir -p server/services
```

- [x] **Passo 2: Atualizar server_scripts no fxmanifest.lua**

Substituir o bloco `server_scripts` pelo load order abaixo.

**ATENÇÃO — risco de dupla execução:** Enquanto `server.lua` e `industries.server.lua` ainda existirem no fxmanifest junto com os novos services, os `RegisterNetEvent` dos arquivos antigos e os do novo `events.lua` executarão simultaneamente, causando handlers duplicados (double-fire). Para evitar isso: ao adicionar `events.lua` no fxmanifest, **comente ou remova todos os blocos `RegisterNetEvent` e `lib.callback.register` do `server.lua` e `industries.server.lua` primeiro** (mantenha apenas as funções helpers locais que ainda não foram migradas para services).

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/services/company_service.lua',
    'server/services/economy_service.lua',
    'server/services/industry_service.lua',
    'server/services/job_service.lua',
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
    -- Temporário durante refactor:
    -- server.lua e industries.server.lua são mantidos APENAS enquanto ainda há
    -- funções helper locais não migradas. Todos os RegisterNetEvent/callbacks
    -- devem estar comentados antes de adicionar events.lua acima.
    -- Remover completamente na Task 8.
    'server/server.lua',
    'server/industries.server.lua',
}
```

- [x] **Passo 3: Verificar**

`ensure AUST_trucker` — sem erros (server.lua e industries.server.lua ainda existem, com RegisterNetEvent comentados).

- [x] **Passo 4: Commit**

```bash
git add fxmanifest.lua
git commit -m "chore: update fxmanifest load order for Phase 2 services"
```

---

## Task 2: Criar company_service.lua

**Files:**
- Create: `server/services/company_service.lua`

- [x] **Passo 1: Criar o arquivo**

```lua
-- AUST_trucker — server/services/company_service.lua
-- Gerenciamento de empresas: CRUD, membros, veículos, financeiro

CompanyService = {}

local CREATION_COST = 150000
local SELL_PAYOUT   = 25000
local MAX_VEHICLES  = 2

-- Retorna empresa do cache ou nil
function CompanyService.Get(companyId)
    return VP_Trucker.Companies[companyId]
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

-- Cria nova empresa. Retorna companyId ou nil + mensagem de erro
function CompanyService.Create(src, name)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil, 'Jogador não encontrado' end

    local citizenId = Player.PlayerData.citizenid

    -- Verificar se já tem empresa
    if VP_Trucker.PlayerCompanies[citizenId] then
        return nil, 'Você já faz parte de uma empresa'
    end

    -- Verificar saldo
    if Player.PlayerData.money.cash < CREATION_COST then
        return nil, ('Você precisa de $%d para criar uma empresa'):format(CREATION_COST)
    end

    -- Cobrar
    if not Player.Functions.RemoveMoney('cash', CREATION_COST, 'company-creation') then
        return nil, 'Falha ao processar pagamento'
    end

    -- Criar no DB
    local companyId = ('company_%d_%d'):format(os.time(), math.random(1000, 9999))
    DB_CreateCompany(companyId, citizenId, name)
    DB_AddMember(companyId, citizenId, 'owner')

    -- Atualizar cache
    VP_Trucker.Companies[companyId] = {
        id = companyId, owner_citizenid = citizenId, name = name,
        balance = 0, is_recruiting = 0
    }
    VP_Trucker.PlayerCompanies[citizenId] = companyId

    return companyId, nil
end

-- Adiciona membro à empresa
function CompanyService.AddMember(companyId, citizenId)
    if VP_Trucker.PlayerCompanies[citizenId] then
        return false, 'Jogador já está em uma empresa'
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
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    if Player.PlayerData.money.cash < amount then return false, 'Saldo insuficiente' end

    Player.Functions.RemoveMoney('cash', amount, 'company-deposit')
    local newBalance = DB_UpdateCompanyBalance(companyId, amount)
    VP_Trucker.Companies[companyId].balance = newBalance or 0
    return true, nil
end

-- Saque do banco da empresa (apenas owner/manager)
function CompanyService.Withdraw(companyId, src, citizenId, amount)
    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end
    if company.balance < amount then return false, 'Saldo insuficiente na empresa' end

    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    local newBalance = DB_UpdateCompanyBalance(companyId, -amount)
    VP_Trucker.Companies[companyId].balance = newBalance or 0
    Player.Functions.AddMoney('cash', amount, 'company-withdrawal')
    return true, nil
end

-- Registrar veículo na empresa
function CompanyService.RegisterVehicle(companyId, plate, model, vehicleType)
    local vehicles = DB_GetVehicles(companyId)
    if #vehicles >= MAX_VEHICLES then
        return false, ('Limite de %d veículos atingido'):format(MAX_VEHICLES)
    end
    DB_RegisterVehicle(companyId, plate, model, vehicleType)
    return true, nil
end

-- Remover veículo da empresa
function CompanyService.RemoveVehicle(plate)
    DB_RemoveVehicle(plate)
end

-- Vender empresa (owner recebe SELL_PAYOUT, empresa é deletada)
function CompanyService.Sell(companyId, src)
    local company = VP_Trucker.Companies[companyId]
    if not company then return false, 'Empresa não encontrada' end

    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    -- Limpar cache de todos os membros
    local members = DB_GetMembers(companyId)
    for _, member in ipairs(members) do
        VP_Trucker.PlayerCompanies[member.citizenid] = nil
    end

    VP_Trucker.Companies[companyId] = nil
    DB_DeleteCompany(companyId)

    Player.Functions.AddMoney('cash', SELL_PAYOUT, 'company-sale')
    return true, nil
end
```

- [x] **Passo 2: Verificar**

`ensure AUST_trucker` — sem erros. `CompanyService` declarado como global mas ainda não usado (server.lua ainda tem a lógica original).

- [x] **Passo 3: Commit**

```bash
git add server/services/company_service.lua
git commit -m "feat: add CompanyService"
```

---

## Task 3: Criar job_service.lua

**Files:**
- Create: `server/services/job_service.lua`

- [x] **Passo 1: Criar o arquivo**

```lua
-- AUST_trucker — server/services/job_service.lua
-- Geração, aceitação, conclusão e abandono de jobs

JobService = {}

local MAX_JOBS = Config.JobGeneration.maxActiveJobs or 8

-- Gera um ID único para job
local function GenerateJobId()
    return ('job_%d_%d'):format(os.time(), math.random(10000, 99999))
end

-- Calcula distância 2D entre dois vector3
local function CalcDistance(c1, c2)
    local dx = c1.x - c2.x
    local dy = c1.y - c2.y
    return math.sqrt(dx*dx + dy*dy) / 1000.0  -- km
end

-- Calcula tempo de expiração: jobs mais lucrativos expiram mais rápido
local function CalcExpiresAt(payment)
    local cfg = Config.JobGeneration.jobExpiration
    local ratio = math.min(1.0, payment / cfg.basePayment)
    local duration = cfg.maxTime - (cfg.maxTime - cfg.minTime) * ratio
    return os.time() + duration
end

-- Seleciona produto aleatório de uma indústria primária
local function PickProduct(primaryIndustry)
    local products = primaryIndustry.products
    if not products or #products == 0 then return nil end
    return products[math.random(#products)]
end

-- Verifica se destino aceita o produto
local function DestAccepts(dest, productName)
    if not dest.acceptedProducts then return false end
    for _, accepted in ipairs(dest.acceptedProducts) do
        if accepted == productName then return true end
    end
    return false
end

-- Gera um job aleatório entre origin e dest compatíveis
local function GenerateOne()
    local origins = Config.PrimaryIndustries
    local dests   = Config.SecondaryIndustries

    -- Tentar até 20 combinações aleatórias
    for _ = 1, 20 do
        local origin = origins[math.random(#origins)]
        local product = PickProduct(origin)
        if not product then goto continue end

        local dest = dests[math.random(#dests)]
        if not DestAccepts(dest, product.name) then goto continue end

        local dist = CalcDistance(origin.coords, dest.coords)
        local payment = math.floor(product.basePrice + dist * Config.JobGeneration.distanceMultiplier * dest.multiplier)
        payment = math.min(payment, Config.General.payment.maxPayment)

        return {
            id            = GenerateJobId(),
            origin_id     = origin.id,
            dest_id       = dest.id,
            cargo_item    = product.name,
            trailer_model = product.trailer,
            base_payment  = payment,
            distance      = dist,
            expires_at    = CalcExpiresAt(payment),
        }

        ::continue::
    end
    return nil
end

-- Gera lote de jobs até MAX_JOBS ativos
function JobService.GenerateBatch()
    local current = DB_CountActiveJobs()
    local toGenerate = MAX_JOBS - current

    for i = 1, toGenerate do
        local job = GenerateOne()
        if job then
            DB_InsertJob(job)
            if Config.Debug then
                print(('[AUST_trucker] Job gerado: %s → %s (%s) $%d'):format(
                    job.origin_id, job.dest_id, job.cargo_item, job.base_payment))
            end
        end
    end
end

-- Retorna jobs disponíveis do DB (enriquecidos com nome de indústria)
function JobService.GetAvailable()
    local rows = DB_GetAvailableJobs()
    local result = {}

    -- Indexar indústrias por id para lookup rápido
    local originIndex = {}
    for _, o in ipairs(Config.PrimaryIndustries) do
        originIndex[o.id] = o
    end
    local destIndex = {}
    for _, d in ipairs(Config.SecondaryIndustries) do
        destIndex[d.id] = d
    end

    for _, row in ipairs(rows) do
        local origin = originIndex[row.origin_id]
        local dest   = destIndex[row.dest_id]
        if origin and dest then
            table.insert(result, {
                id           = row.id,
                originName   = origin.name,
                destName     = dest.name,
                cargoItem    = row.cargo_item,
                trailerModel = row.trailer_model,
                basePayment  = row.base_payment,
                distance     = row.distance,
                expiresAt    = row.expires_at_unix,
            })
        end
    end
    return result
end

-- Aceita job para um jogador
function JobService.Accept(jobId, citizenId, companyId)
    DB_AcceptJob(jobId, citizenId, companyId)
end

-- Retorna job ativo do jogador
function JobService.GetActiveByPlayer(citizenId)
    local row = DB_GetActiveJobByPlayer(citizenId)
    if not row then return nil end

    -- Enriquecer com nomes
    local originIndex = {}
    for _, o in ipairs(Config.PrimaryIndustries) do originIndex[o.id] = o end
    local destIndex = {}
    for _, d in ipairs(Config.SecondaryIndustries) do destIndex[d.id] = d end

    local origin = originIndex[row.origin_id]
    local dest   = destIndex[row.dest_id]

    return {
        jobId        = row.id,
        originName   = origin and origin.name or row.origin_id,
        originCoords = origin and origin.coords or nil,
        destName     = dest and dest.name or row.dest_id,
        destCoords   = dest and dest.coords or nil,
        cargoItem    = row.cargo_item,
        trailerModel = row.trailer_model,
        payment      = row.base_payment,
        acceptedAt   = row.accepted_at_unix,
    }
end

-- Retorna manifesto de transporte para o jogador
function JobService.GetManifest(citizenId)
    local job = JobService.GetActiveByPlayer(citizenId)
    if not job then return nil end

    local company = CompanyService.GetByMember(citizenId)

    return {
        cargo        = job.cargoItem,
        trailerModel = job.trailerModel,
        origin       = job.originName,
        destination  = job.destName,
        companyName  = company and company.name or 'Autônomo',
        issuedAt     = job.acceptedAt,
    }
end

-- Completa job e paga jogador
-- payload = { deliveryTime = seconds, plate = "PLATE" }
function JobService.Complete(src, payload)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false end

    local citizenId = Player.PlayerData.citizenid
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return false end

    -- Calcular bônus de tempo
    local elapsed = payload.deliveryTime or 9999
    local bonus = Config.JobGeneration.timeBonus
    local multiplier = bonus.slow.multiplier
    if elapsed <= bonus.fast.time then
        multiplier = bonus.fast.multiplier
    elseif elapsed <= bonus.normal.time then
        multiplier = bonus.normal.multiplier
    end

    local payment = math.floor(activeJob.base_payment * multiplier)

    -- Pagar jogador
    Player.Functions.AddMoney(Config.General.payment.currency, payment, 'aurp-trucker-job')

    -- Atualizar DB
    DB_CompleteJob(activeJob.id)
    DB_AddPlayerStats(citizenId, payment, activeJob.distance)

    -- Disparar evento para domínios externos (AUST_sala)
    local company = CompanyService.GetByMember(citizenId)
    TriggerEvent('AUST_trucker:jobCompleted', citizenId,
        company and company.id or nil,
        { jobId = activeJob.id, cargo = activeJob.cargo_item },
        payment)

    return true, payment
end

-- Abandona job ativo do jogador
function JobService.Abandon(citizenId)
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return end
    DB_AbandonJob(activeJob.id, citizenId)
end

-- Registra infração (chamado pelo AUST_sala via export)
function JobService.RecordInfraction(citizenId, infractionType, reason, issuedBy)
    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    local jobId = activeJob and activeJob.id or nil
    DB_RecordInfraction(citizenId, jobId, infractionType, reason, issuedBy)
    TriggerEvent('AUST_trucker:infractionRecorded', citizenId,
        { type = infractionType, reason = reason, issuedBy = issuedBy })
    return true
end

-- Expira jobs vencidos (cron)
function JobService.ExpireStale()
    DB_ExpireStaleJobs()
end

-- Carrega jobs ativos do DB no restart (chamado por main.lua)
function JobService.LoadFromDB()
    -- Jobs 'active' orphaned após restart: liberar de volta para 'available'
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'available', assigned_citizenid = NULL, company_id = NULL, accepted_at = NULL WHERE status = 'active' AND expires_at > NOW()"
    )
    -- Jobs ativos com expires_at passado → expirar
    JobService.ExpireStale()
    if Config.Debug then
        print('[AUST_trucker] Jobs loaded from DB')
    end
end
```

- [x] **Passo 2: Atualizar server/main.lua para chamar JobService.LoadFromDB**

No `MySQL.ready`, adicionar após `LoadCompanies()`:
```lua
MySQL.ready(function()
    LoadCompanies()
    -- JobService ainda não existe aqui no load order — usar callback
    CreateThread(function()
        while not JobService do Wait(100) end
        JobService.LoadFromDB()
        VP_Trucker.Ready = true
        if Config.Debug then print('[AUST_trucker] Server ready.') end
    end)
end)
```

**Remover** `VP_Trucker.Ready = true` da posição antiga (agora é definido após JobService.LoadFromDB).

- [x] **Passo 3: Verificar**

`ensure AUST_trucker`. `[AUST_trucker] Jobs loaded from DB` aparece no console.

- [x] **Passo 4: Commit**

```bash
git add server/services/job_service.lua server/main.lua
git commit -m "feat: add JobService with job generation, acceptance, completion"
```

---

## Task 4: Criar economy_service.lua e industry_service.lua

**Files:**
- Create: `server/services/economy_service.lua`
- Create: `server/services/industry_service.lua`

- [x] **Passo 1: Criar economy_service.lua**

```lua
-- AUST_trucker — server/services/economy_service.lua
-- Preços dinâmicos para Config.Industries (trading com ox_inventory)

EconomyService = {}

-- Cache de preços em memória: { [industryId] = { [item..entryType] = price } }
local priceCache = {}

local function cacheKey(industryId, item, entryType)
    return industryId .. ':' .. item .. ':' .. entryType
end

-- Inicializa cache a partir do DB
function EconomyService.Init()
    local rows = DB_GetAllIndustryState()
    for _, row in ipairs(rows) do
        local key = cacheKey(row.industry_id, row.item, row.entry_type)
        priceCache[key] = row.current_price
    end
    if Config.Debug then
        print(('[AUST_trucker] EconomyService: %d price entries loaded'):format(#rows))
    end
end

function EconomyService.GetPrice(industryId, item, entryType)
    local key = cacheKey(industryId, item, entryType)
    return priceCache[key]
end

-- Atualiza preços com base em supply/demand
function EconomyService.UpdatePrices()
    local cfg = Config.Economy
    local rows = DB_GetAllIndustryState()

    for _, row in ipairs(rows) do
        local industryConfig = Config.Industries[row.industry_id]
        if not industryConfig then goto continue end

        local maxStock, basePrice

        if row.entry_type == 'production' and industryConfig.production then
            maxStock  = industryConfig.production.maxStock
            basePrice = industryConfig.production.basePrice
        else
            -- encontrar item de consumo no config
            if industryConfig.consumption then
                for _, c in ipairs(industryConfig.consumption) do
                    if c.item == row.item then
                        maxStock  = c.maxStock
                        basePrice = c.basePrice
                        break
                    end
                end
            end
        end

        if not maxStock or maxStock == 0 or not basePrice then goto continue end

        local stockRatio = row.current_stock / maxStock  -- 0.0 a 1.0
        local targetMult

        if row.entry_type == 'production' then
            -- Mais stock → oferta alta → preço cai
            targetMult = cfg.priceCeiling - (cfg.priceCeiling - cfg.priceFloor) * stockRatio
        else
            -- Mais stock → demanda baixa → preço sobe (pagamos mais se temos pouco)
            targetMult = cfg.priceFloor + (cfg.priceCeiling - cfg.priceFloor) * (1 - stockRatio)
        end

        local currentMult = row.current_price / basePrice
        local newMult = currentMult + (targetMult - currentMult) * cfg.priceAdjustmentSpeed
        newMult = math.max(cfg.priceFloor, math.min(cfg.priceCeiling, newMult))

        local newPrice = math.floor(basePrice * newMult)
        DB_UpdateIndustryPrice(row.industry_id, row.item, row.entry_type, newPrice)

        local key = cacheKey(row.industry_id, row.item, row.entry_type)
        priceCache[key] = newPrice

        ::continue::
    end
end

function EconomyService.RecordSale(industryId, item, qty)
    -- Jogador vendeu item para indústria → stock de consumo aumenta
    DB_UpdateIndustryStock(industryId, item, 'consumption', qty)
    EconomyService.UpdatePrices()
end

function EconomyService.RecordPurchase(industryId, item, qty)
    -- Jogador comprou item da indústria → stock de produção diminui
    DB_UpdateIndustryStock(industryId, item, 'production', -qty)
    EconomyService.UpdatePrices()
end

-- Loop de atualização de preços
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    EconomyService.Init()

    while true do
        Wait(Config.Economy.priceUpdateInterval)
        EconomyService.UpdatePrices()
        if Config.Debug then print('[AUST_trucker] Economy prices updated') end
    end
end)
```

- [x] **Passo 2: Criar industry_service.lua**

```lua
-- AUST_trucker — server/services/industry_service.lua
-- Interações de trading: BuyFrom / SellTo / Produção

IndustryService = {}

-- Retorna estado atual de todas as indústrias de trading para a NUI
function IndustryService.GetAll()
    local rows = DB_GetAllIndustryState()

    -- Indexar por industryId+item+type
    local stateIndex = {}
    for _, row in ipairs(rows) do
        local k = row.industry_id .. ':' .. row.item .. ':' .. row.entry_type
        stateIndex[k] = row
    end

    local result = {}
    for industryId, industry in pairs(Config.Industries) do
        local entry = {
            id           = industryId,
            name         = industry.name,
            industryType = industry.type,
            coords       = industry.coords,
            production   = nil,
            consumption  = {},
        }

        if industry.production and industry.production.item then
            local key = industryId .. ':' .. industry.production.item .. ':production'
            local state = stateIndex[key]
            entry.production = {
                product          = industry.production.label,
                item             = industry.production.item,
                price            = state and state.current_price or industry.production.basePrice,
                currentStock     = state and state.current_stock or 0,
                maxStock         = industry.production.maxStock,
                unit             = industry.production.unit,
                productionPerHour = industry.production.productionPerHour,
            }
        end

        if industry.consumption then
            for _, c in ipairs(industry.consumption) do
                local key = industryId .. ':' .. c.item .. ':consumption'
                local state = stateIndex[key]
                table.insert(entry.consumption, {
                    product          = c.label,
                    item             = c.item,
                    price            = state and state.current_price or c.basePrice,
                    currentStock     = state and state.current_stock or 0,
                    maxStock         = c.maxStock,
                    unit             = c.unit,
                    consumptionPerHour = c.consumptionPerHour,
                })
            end
        end

        result[industryId] = entry
    end
    return result
end

function IndustryService.Get(industryId)
    local all = IndustryService.GetAll()
    return all[industryId]
end

-- Jogador compra item de produção da indústria
function IndustryService.BuyFrom(src, industryId, item, qty)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    local citizenId = Player.PlayerData.citizenid
    local state = MySQL.single.await(
        "SELECT * FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'production' LIMIT 1",
        { industryId, item }
    )

    if not state then return false, 'Produto não encontrado' end
    if state.current_stock < qty then return false, 'Stock insuficiente' end

    local totalPrice = state.current_price * qty
    if Player.PlayerData.money.cash < totalPrice then
        return false, ('Você precisa de $%d'):format(totalPrice)
    end

    -- Verificar e adicionar item ao inventário
    local ok = exports.ox_inventory:AddItem(src, item, qty)
    if not ok then return false, 'Inventário cheio' end

    Player.Functions.RemoveMoney('cash', totalPrice, 'industry-purchase')
    EconomyService.RecordPurchase(industryId, item, qty)
    return true, nil
end

-- Jogador vende item de consumo para a indústria
function IndustryService.SellTo(src, industryId, item, qty)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end

    local state = MySQL.single.await(
        "SELECT * FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'consumption' LIMIT 1",
        { industryId, item }
    )

    if not state then return false, 'Produto não aceito aqui' end

    local industryConfig = Config.Industries[industryId]
    if not industryConfig then return false, 'Indústria não encontrada' end

    -- Verificar limite de stock
    local maxStock
    for _, c in ipairs(industryConfig.consumption or {}) do
        if c.item == item then maxStock = c.maxStock; break end
    end
    if maxStock and state.current_stock + qty > maxStock then
        return false, 'Indústria não consegue receber mais desse produto'
    end

    -- Remover item do inventário
    local ok = exports.ox_inventory:RemoveItem(src, item, qty)
    if not ok then return false, 'Você não tem esse item' end

    local totalPrice = state.current_price * qty
    Player.Functions.AddMoney('cash', totalPrice, 'industry-sale')
    EconomyService.RecordSale(industryId, item, qty)
    return true, nil
end

-- Ciclo de produção das indústrias (cron)
-- ATENÇÃO: indústrias terciárias têm production = nil — pular produção
function IndustryService.RunProductionCycle(isPrimary)
    for industryId, industry in pairs(Config.Industries) do
        -- Produção: apenas industries primárias e secundárias (não terciárias)
        if industry.production ~= nil then
            local isPrimaryIndustry = industry.type == 'primary'
            local isSecondaryIndustry = industry.type == 'secondary'

            if (isPrimary and isPrimaryIndustry) or (not isPrimary and isSecondaryIndustry) then
                local state = MySQL.single.await(
                    "SELECT * FROM trucker_industry_state WHERE industry_id = ? AND item = ? AND entry_type = 'production' LIMIT 1",
                    { industryId, industry.production.item }
                )
                if state then
                    local maxStock = industry.production.maxStock
                    if state.current_stock < maxStock then
                        DB_UpdateIndustryStock(industryId, industry.production.item, 'production', 1)
                    end
                end
            end
        end
    end
end

-- Threads de produção
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(Config.Economy.primaryProductionInterval)
        IndustryService.RunProductionCycle(true)  -- primárias
    end
end)

CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(Config.Economy.secondaryProductionInterval)
        IndustryService.RunProductionCycle(false)  -- secundárias
    end
end)
```

- [x] **Passo 3: Verificar**

`ensure AUST_trucker`. Console mostra:
- `EconomyService: N price entries loaded`
- Sem erros de nil

- [x] **Passo 4: Commit**

```bash
git add server/services/economy_service.lua server/services/industry_service.lua
git commit -m "feat: add EconomyService and IndustryService"
```

---

## Task 5: Criar server/exports.lua

**Files:**
- Create: `server/exports.lua`

- [x] **Passo 1: Criar o arquivo**

```lua
-- AUST_trucker — server/exports.lua
-- API pública para integração com AUST_sala e outros domínios

-- Job ativo de um jogador (para inspeção SALA em tempo real)
-- @param citizenId string
-- @return table|nil { jobId, originName, destName, cargoItem, trailerModel, payment, acceptedAt }
exports('GetPlayerActiveJob', function(citizenId)
    return JobService.GetActiveByPlayer(citizenId)
end)

-- Manifesto de transporte (documento para fiscalização física)
-- @return table|nil { cargo, trailerModel, origin, destination, companyName, issuedAt }
exports('GetJobManifest', function(citizenId)
    return JobService.GetManifest(citizenId)
end)

-- Dados da empresa para auditoria SALA
-- @return table|nil { id, name, ownerCitizenId, balance, is_recruiting }
exports('GetCompanyInfo', function(companyId)
    return CompanyService.Get(companyId)
end)

-- Empresa de um jogador
-- @return table|nil
exports('GetPlayerCompany', function(citizenId)
    return CompanyService.GetByMember(citizenId)
end)

-- SALA registra infração
-- @param infractionType 'overload'|'no_manifest'|'expired_manifest'|'dangerous_cargo'
-- @param issuedBy citizenid do inspetor OU 'AUST_sala:auto'
-- @return boolean
exports('RecordInfraction', function(citizenId, infractionType, reason, issuedBy)
    return JobService.RecordInfraction(citizenId, infractionType, reason, issuedBy)
end)

-- Histórico de infrações para MDT SALA
-- @return table[]
exports('GetInfractions', function(citizenId)
    return DB_GetInfractions(citizenId)
end)
```

- [x] **Passo 2: Verificar**

Num resource de teste (ou console), executar:
```lua
local job = exports['AUST_trucker']:GetPlayerActiveJob('TEST_CITIZENID')
print(json.encode(job))  -- retorna nil (sem job ativo) — sem erro
```

- [x] **Passo 3: Commit**

```bash
git add server/exports.lua
git commit -m "feat: add server/exports.lua — AUST_sala integration API"
```

---

## Task 6: Criar server/callbacks.lua

**Files:**
- Create: `server/callbacks.lua`

- [x] **Passo 1: Criar o arquivo**

```lua
-- AUST_trucker — server/callbacks.lua
-- lib.callback.register (substitui QBCore.Functions.CreateCallback)

-- Dados iniciais para abrir a NUI
lib.callback.register('AUST_trucker:getInitialData', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    local citizenId = Player.PlayerData.citizenid

    return {
        jobs               = JobService.GetAvailable(),
        company            = CompanyService.GetByMember(citizenId),
        activeJob          = JobService.GetActiveByPlayer(citizenId),
        stats              = DB_GetPlayerStats(citizenId),
        recruitingCompanies = CompanyService.GetRecruiting(),
    }
end)

lib.callback.register('AUST_trucker:getCompanyMembers', function(source, companyId)
    return DB_GetMembers(companyId)
end)

lib.callback.register('AUST_trucker:getPlayerStats', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end
    return DB_GetPlayerStats(Player.PlayerData.citizenid)
end)

lib.callback.register('AUST_trucker:getIndustries', function(source)
    return IndustryService.GetAll()
end)

lib.callback.register('AUST_trucker:getIndustryData', function(source, industryId)
    return IndustryService.Get(industryId)
end)
```

- [x] **Passo 2: Verificar**

No client conectado, chamar o callback via console (F8):
```lua
-- client-side F8 debug:
local ok, data = pcall(lib.callback.await, 'AUST_trucker:getInitialData', false)
print(ok, json.encode(data))
```
Esperado: `true` + JSON com jobs, company=nil, activeJob=nil, stats, recruitingCompanies.

- [x] **Passo 3: Commit**

```bash
git add server/callbacks.lua
git commit -m "feat: add server/callbacks.lua — ox_lib callbacks"
```

---

## Task 7: Criar server/events.lua com geração automática de jobs

**Files:**
- Create: `server/events.lua`

- [x] **Passo 1: Criar o arquivo**

```lua
-- AUST_trucker — server/events.lua
-- RegisterNetEvent handlers (extraídos de server.lua)
-- Apenas lógica de validação + delegate para services

-- =====================================================
-- JOB HANDLERS
-- =====================================================

RegisterNetEvent('AUST_trucker:acceptJob', function(jobId)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    -- Verificar se já tem job ativo
    if JobService.GetActiveByPlayer(citizenId) then
        TriggerClientEvent('AUST_trucker:notify', src, 'Você já tem um job ativo', 'error')
        return
    end

    local company = CompanyService.GetByMember(citizenId)
    JobService.Accept(jobId, citizenId, company and company.id or nil)

    local jobData = JobService.GetActiveByPlayer(citizenId)
    TriggerClientEvent('AUST_trucker:client:jobStarted', src, jobData)
    TriggerEvent('AUST_trucker:jobAccepted', citizenId, company and company.id or nil, jobData)
end)

RegisterNetEvent('AUST_trucker:completeJob', function(payload)
    local src = source
    -- payload = { deliveryTime, plate }
    local ok, payment = JobService.Complete(src, payload)
    if ok then
        TriggerClientEvent('AUST_trucker:client:jobCompleted', src, payment)
        TriggerClientEvent('AUST_trucker:notify', src,
            ('Job concluído! Você recebeu $%d'):format(payment), 'success')
    end
end)

RegisterNetEvent('AUST_trucker:abandonJob', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    JobService.Abandon(Player.PlayerData.citizenid)
    TriggerClientEvent('AUST_trucker:client:jobAbandoned', src)
end)

-- =====================================================
-- COMPANY HANDLERS
-- =====================================================

RegisterNetEvent('AUST_trucker:createCompany', function(name)
    local src = source
    local companyId, err = CompanyService.Create(src, name)
    if err then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    local company = CompanyService.Get(companyId)
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, company)
    TriggerClientEvent('AUST_trucker:notify', src, 'Empresa criada com sucesso!', 'success')
end)

RegisterNetEvent('AUST_trucker:joinCompany', function(companyId)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local company = CompanyService.Get(companyId)
    if not company or company.is_recruiting == 0 then
        TriggerClientEvent('AUST_trucker:notify', src, 'Empresa não está recrutando', 'error')
        return
    end

    local ok, err = CompanyService.AddMember(companyId, citizenId)
    if not ok then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, CompanyService.Get(companyId))
    TriggerClientEvent('AUST_trucker:notify', src, 'Você entrou na empresa!', 'success')
end)

RegisterNetEvent('AUST_trucker:leaveCompany', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid
    local company = CompanyService.GetByMember(citizenId)
    if not company then return end

    -- Owner não pode sair sem vender/transferir
    if company.owner_citizenid == citizenId then
        TriggerClientEvent('AUST_trucker:notify', src, 'Owner deve vender a empresa para sair', 'error')
        return
    end

    CompanyService.RemoveMember(citizenId)
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, nil)
    TriggerClientEvent('AUST_trucker:notify', src, 'Você saiu da empresa', 'inform')
end)

RegisterNetEvent('AUST_trucker:kickMember', function(targetCitizenId)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid
    local company = CompanyService.GetByMember(citizenId)
    if not company or company.owner_citizenid ~= citizenId then
        TriggerClientEvent('AUST_trucker:notify', src, 'Sem permissão', 'error')
        return
    end
    CompanyService.RemoveMember(targetCitizenId)
    TriggerClientEvent('AUST_trucker:notify', src, 'Membro removido', 'success')
end)

RegisterNetEvent('AUST_trucker:toggleRecruiting', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return end
    local newState = company.is_recruiting == 0
    CompanyService.SetRecruiting(company.id, newState)
    TriggerClientEvent('AUST_trucker:notify', src,
        newState and 'Recrutamento ativado' or 'Recrutamento desativado', 'inform')
end)

RegisterNetEvent('AUST_trucker:depositMoney', function(amount)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return end
    local ok, err = CompanyService.Deposit(company.id, src, amount)
    if not ok then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, CompanyService.Get(company.id))
end)

RegisterNetEvent('AUST_trucker:withdrawMoney', function(amount)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid
    local company = CompanyService.GetByMember(citizenId)
    if not company then return end
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        TriggerClientEvent('AUST_trucker:notify', src, 'Sem permissão para sacar', 'error')
        return
    end
    local ok, err = CompanyService.Withdraw(company.id, src, citizenId, amount)
    if not ok then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, CompanyService.Get(company.id))
end)

RegisterNetEvent('AUST_trucker:registerVehicle', function(plate, model, vehicleType)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return end
    local ok, err = CompanyService.RegisterVehicle(company.id, plate, model, vehicleType)
    if not ok then
        TriggerClientEvent('AUST_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('AUST_trucker:notify', src, 'Veículo registrado!', 'success')
end)

RegisterNetEvent('AUST_trucker:removeVehicle', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return end
    CompanyService.RemoveVehicle(plate)
    TriggerClientEvent('AUST_trucker:notify', src, 'Veículo removido', 'inform')
end)

RegisterNetEvent('AUST_trucker:sellCompany', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid
    local company = CompanyService.GetByMember(citizenId)
    if not company or company.owner_citizenid ~= citizenId then
        TriggerClientEvent('AUST_trucker:notify', src, 'Apenas o owner pode vender', 'error')
        return
    end
    CompanyService.Sell(company.id, src)
    TriggerClientEvent('AUST_trucker:client:companyUpdated', src, nil)
    TriggerClientEvent('AUST_trucker:notify', src, 'Empresa vendida por $25.000', 'success')
end)

-- =====================================================
-- INDUSTRY TRADING HANDLERS
-- =====================================================

RegisterNetEvent('AUST_trucker:buyFromIndustry', function(industryId, item, qty)
    local src = source
    local ok, err = IndustryService.BuyFrom(src, industryId, item, qty)
    if not ok then
        TriggerClientEvent('AUST_trucker:notify', src, err or 'Erro na compra', 'error')
    else
        TriggerClientEvent('AUST_trucker:notify', src, ('Comprado: %dx %s'):format(qty, item), 'success')
    end
end)

RegisterNetEvent('AUST_trucker:sellToIndustry', function(industryId, item, qty)
    local src = source
    local ok, err = IndustryService.SellTo(src, industryId, item, qty)
    if not ok then
        TriggerClientEvent('AUST_trucker:notify', src, err or 'Erro na venda', 'error')
    else
        TriggerClientEvent('AUST_trucker:notify', src, ('Vendido: %dx %s'):format(qty, item), 'success')
    end
end)

-- =====================================================
-- PLAYER LIFECYCLE
-- =====================================================

AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    DB_UpsertPlayerStats(Player.PlayerData.citizenid)
end)

-- =====================================================
-- JOB GENERATION CRON
-- =====================================================

CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    -- Gera batch inicial
    JobService.GenerateBatch()

    while true do
        Wait(Config.JobGeneration.refreshInterval)
        JobService.ExpireStale()
        JobService.GenerateBatch()
        -- Notificar todos os clientes sobre novos jobs
        TriggerClientEvent('AUST_trucker:client:jobsUpdated', -1)
    end
end)
```

- [x] **Passo 2: Verificar**

`ensure AUST_trucker`. Após 2s, verificar:
```sql
SELECT COUNT(*) FROM trucker_jobs WHERE status = 'available';
```
Esperado: até 8 jobs gerados.

- [x] **Passo 3: Commit**

```bash
git add server/events.lua
git commit -m "feat: add server/events.lua — all RegisterNetEvent handlers + job generation cron"
```

---

## Task 8: Remover server.lua e industries.server.lua

**Files:**
- Delete: `server/server.lua`
- Delete: `server/industries.server.lua`
- Modify: `fxmanifest.lua`

- [x] **Passo 1: Verificar que todos os handlers foram migrados**

Comparar eventos de `server.lua` com os do `events.lua`:
```bash
grep -n "RegisterNetEvent\|CreateCallback" server/server.lua
grep -n "RegisterNetEvent\|lib.callback.register" server/events.lua server/callbacks.lua
```
Cada `RegisterNetEvent` de `server.lua` deve ter correspondente em `events.lua`.

- [x] **Passo 2: Remover arquivos do fxmanifest**

No bloco `server_scripts`, remover:
```lua
-- Remover estas duas linhas:
'server/server.lua',
'server/industries.server.lua',
```

- [x] **Passo 3: Testar SEM os arquivos antigos**

`ensure AUST_trucker`. Verificar que o resource inicia sem erros.

Se houver erros de função não definida → algum handler ainda referencia função local do server.lua antigo → adicionar ao service correspondente.

- [x] **Passo 4: Deletar os arquivos**

```bash
rm server/server.lua server/industries.server.lua
```

- [x] **Passo 5: Teste de integração completo**

1. Criar empresa → persiste
2. Aceitar job → blips aparecem no client
3. Completar job → stats atualizadas, $$ recebido
4. Abrir indústria → menu ox_lib com preços dinâmicos
5. `restart AUST_trucker` → jobs não somem (recarregados do DB)
6. Verificar exports: `exports['AUST_trucker']:GetPlayerCompany('TEST')` retorna nil sem erros

- [x] **Passo 6: Commit final Fase 2**

```bash
git add -A
git commit -m "feat: Phase 2 complete — server refactored into services, exports ready for AUST_sala"
```

---

## Checklist de Verificação Final da Fase 2

- [x] `ensure AUST_trucker` inicia sem erros
- [x] `grep -rn "server\.lua\|industries\.server" fxmanifest.lua` → 0 resultados
- [x] Jobs gerados no startup e persistem após restart
- [x] Todos os 5 exports funcionam (testar com `/lua` ou resource de teste)
- [x] `TriggerEvent('AUST_trucker:jobAccepted', ...)` disparado ao aceitar job
- [x] Empresas, jobs e stats persistem após `restart AUST_trucker`

---

## Próxima Fase

Após concluir todos os itens:
**→ Plano 3: React UI** (`docs/superpowers/plans/2026-03-19-phase3-react-ui.md`)
