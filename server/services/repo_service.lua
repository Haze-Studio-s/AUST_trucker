-- aurp_trucker — server/services/repo_service.lua
-- RepoService: Geração, aceitação, conclusão e falha de ordens de repossessão

RepoService = {}

-- Constantes lidas de Config.RepoMan
local POOL_INTERVAL     = Config.RepoMan.PoolInterval
local MAX_NPC_ORDERS    = Config.RepoMan.MaxNpcOrders
local NPC_ORDER_EXPIRY  = Config.RepoMan.NpcOrderExpiry
local LOAN_ORDER_EXPIRY = Config.RepoMan.LoanOrderExpiry
local PAYMENT_RATE      = Config.RepoMan.PaymentRate
local COMPANY_FEE_RATE  = Config.RepoMan.CompanyFeeRate
local TYPE_MULTIPLIERS  = Config.RepoMan.TypeMultipliers
local NPC_MISSION_WEIGHTS = Config.RepoMan.NpcMissionWeights

-- Helper: broadcast lista atualizada para todos os agentes repo online
-- NOTA: usa lookup de campo de tabela (RepoService.BroadcastAvailableOrders) — safe para chamar
--       em Accept/Complete/Fail mesmo sendo definido após essas funções, pois a atribuição abaixo
--       ocorre em load time antes de qualquer jogador conectar.
local function BroadcastAvailableOrders()
    local orders = DB_GetAvailableRepoOrders()
    for _, playerId in ipairs(GetPlayers()) do
        local pPlayer = Framework.GetPlayer(tonumber(playerId))
        local pCitizenId = pPlayer and Framework.GetCitizenId(pPlayer)
        if pCitizenId then
            local company = CompanyService.GetByMember(pCitizenId)
            if company and company.company_type == 'repo' then
                TriggerClientEvent('aurp_trucker:client:updateRepoOrders', tonumber(playerId), orders)
            end
        end
    end
end
RepoService.BroadcastAvailableOrders = BroadcastAvailableOrders

-- Helper: weighted random mission type from weights table
local function WeightedRandom(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local roll = math.random(1, total)
    local cumulative = 0
    for missionType, w in pairs(weights) do
        cumulative = cumulative + w
        if roll <= cumulative then return missionType end
    end
end

---Generates a repo order from a loan default.
---@param loan table  row from trucker_loans (remaining_balance = post-penalty)
function RepoService.GenerateFromLoan(loan)
    local vehiclePlate, vehicleModel, vehicleValue

    if loan.vehicle_plate then
        -- 6A: usar diretamente o veículo penhorado no empréstimo
        vehiclePlate = loan.vehicle_plate
        local vehRow = DB_GetVehicleModel(vehiclePlate)
        if not vehRow then
            -- Plate não encontrada em trucker_company_vehicles — abortar sem criar ordem inválida
            print(('[aurp_trucker] GenerateFromLoan: plate "%s" not found in company vehicles, skipping repo order for loan #%d')
                :format(vehiclePlate, loan.id or 0))
            return
        end
        vehicleModel = string.lower(vehRow.model or 'mule')
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

---Generates a random NPC repo order.
function RepoService.GenerateNPC()
    local npcVehicles = Config.RepoMan.NpcVehicles
    local npcZones    = Config.RepoMan.NpcZones
    local vehicle     = npcVehicles[math.random(#npcVehicles)]
    local zone        = npcZones[math.random(#npcZones)]
    local missionType = WeightedRandom(NPC_MISSION_WEIGHTS)
    local plate       = 'NPC-' .. math.random(100000, 999999)
    local payment     = math.floor(vehicle.value * PAYMENT_RATE * TYPE_MULTIPLIERS[missionType])
    local expiresAt   = os.time() + NPC_ORDER_EXPIRY

    DB_InsertRepoOrder(
        plate, vehicle.model, vehicle.value, nil,
        missionType, zone.name, payment, expiresAt, nil
    )
end

---Accepts a repo order for a player.
---@param src number  player server id
---@param orderId number
---@return table  { success, order?, reason? }
function RepoService.Accept(src, orderId)
    local Player = Framework.GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)

    -- Must belong to a repo company
    local company = CompanyService.GetByMember(citizenId)
    if not company or company.company_type ~= 'repo' then
        return { success = false, reason = 'Apenas membros de empresa Repo Man podem aceitar ordens' }
    end

    -- Cannot have another active order
    local active = DB_GetActiveRepoOrder(citizenId)
    if active then
        return { success = false, reason = 'Você já tem uma missão ativa' }
    end

    -- Atomic accept: returns 0 if order already taken (race condition guard)
    local affected = DB_AcceptRepoOrder(orderId, citizenId, company.id)
    if not affected or affected == 0 then
        return { success = false, reason = 'Ordem não disponível' }
    end

    local order = DB_GetRepoOrderById(orderId)
    TriggerClientEvent('aurp_trucker:client:startRepoMission', src, order)
    RepoService.BroadcastAvailableOrders()

    return { success = true, order = order }
end

---Completes an active repo mission.
---@param src number
---@param orderId number
---@return table  { success, payment?, companyFee?, reason? }
function RepoService.Complete(src, orderId)
    local Player = Framework.GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)

    local order = DB_GetRepoOrderById(orderId)
    if not order or order.status ~= 'active' or order.assigned_citizenid ~= citizenId then
        return { success = false, reason = 'Ordem não encontrada ou inválida' }
    end

    -- C-13: Atualização atômica — retorna 0 se outro coroutine já completou
    local affected = DB_CompleteRepoOrder(orderId, os.time())
    if not affected or affected == 0 then
        return { success = false, reason = 'Ordem já processada' }
    end

    local payment    = order.payment
    local companyFee = math.floor(payment * COMPANY_FEE_RATE)

    -- Pay agent
    Framework.AddMoney(Player, 'bank', payment, 'repo-completion')

    -- Pay company
    local newBal = DB_UpdateCompanyBalance(order.company_id, companyFee)
    if VP_Trucker.Companies[order.company_id] then
        VP_Trucker.Companies[order.company_id].balance = newBal or 0
    end

    -- Abate on loan if applicable
    if order.loan_id then
        local loan = DB_GetLoanById(order.loan_id)
        if loan and loan.status == 'active' then
            local newBalance = math.max(0, loan.remaining_balance - order.vehicle_value)
            local newStatus  = newBalance == 0 and 'paid' or 'active'
            local nextPayAt  = newBalance > 0
                and (os.time() + Config.Loans.InstallmentDays * 86400)
                or nil
            DB_UpdateLoanBalance(loan.id, newBalance, newStatus, nextPayAt)

            -- Notify loan owner if online
            local loanOwnerSrc = Framework.FindPlayerByCitizenId(loan.citizenid)
            if loanOwnerSrc then
                lib.notify(loanOwnerSrc, {
                    title       = 'Repossessão',
                    description = ('Veículo repossessado. Saldo do empréstimo reduzido em $%d'):format(
                        order.vehicle_value),
                    type     = 'warning',
                    duration = 8000,
                })
            end
        end
    end

    -- Notify vehicle owner if online and not NPC
    if order.vehicle_owner_citizenid then
        local ownerSrc = Framework.FindPlayerByCitizenId(order.vehicle_owner_citizenid)
        if ownerSrc then
            lib.notify(ownerSrc, {
                title       = 'Veículo Repossessado',
                description = 'Um agente Repo Man recolheu seu veículo inadimplente',
                type        = 'error',
                duration    = 8000,
            })
        end
    end

    RepoService.BroadcastAvailableOrders()

    -- Notificar agent client
    TriggerClientEvent('aurp_trucker:client:repoMissionEnded', src, {
        success = true,
        payment = payment,
    })
    -- Notificar dono do veículo (pvp/stealth — evento separado)
    if order.vehicle_owner_citizenid then
        local ownerSrc = Framework.FindPlayerByCitizenId(order.vehicle_owner_citizenid)
        if ownerSrc then
            TriggerClientEvent('aurp_trucker:client:repoOwnerMissionEnded', ownerSrc, { recovered = true })
        end
    end

    return { success = true, payment = payment, companyFee = companyFee }
end

---Fails (abandons) an active repo mission, returning order to available.
---@param src number
---@param orderId number
---@return table  { success }
function RepoService.Fail(src, orderId)
    local Player = Framework.GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Framework.GetCitizenId(Player)

    local order = DB_GetRepoOrderById(orderId)
    if not order or order.status ~= 'active' or order.assigned_citizenid ~= citizenId then
        return { success = false, reason = 'Missão não encontrada ou inválida' }
    end

    DB_UpdateRepoOrderStatus(orderId, 'available', nil, nil)
    RepoService.BroadcastAvailableOrders()

    -- Notificar agent client
    TriggerClientEvent('aurp_trucker:client:repoMissionEnded', src, { success = false })
    -- Notificar dono do veículo
    if order.vehicle_owner_citizenid then
        local ownerSrc = Framework.FindPlayerByCitizenId(order.vehicle_owner_citizenid)
        if ownerSrc then
            TriggerClientEvent('aurp_trucker:client:repoOwnerMissionEnded', ownerSrc, { recovered = false })
        end
    end

    return { success = true }
end

---Expires stale orders (called by thread).
function RepoService.CheckExpired()
    DB_ExpireRepoOrders()
end

-- Thread: NPC pool — keep up to MaxNpcOrders NPC orders available
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

-- Thread: Expire stale orders every 5 minutes
CreateThread(function()
    while not VP_Trucker.Ready do Wait(100) end
    while true do
        Wait(300 * 1000)
        RepoService.CheckExpired()
    end
end)
