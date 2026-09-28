-- aurp_trucker — server/services/contract_service.lua
-- Sistema de Contratos com Relacionamento Empresa↔Cliente

print('[aurp_trucker] ContractService: arquivo carregado')

ContractService = {}

-- ============================================================
-- DATABASE HELPERS
-- ============================================================

local function DB_GetRelationship(companyId, clientId)
    return MySQL.single.await(
        "SELECT * FROM trucker_client_relationships WHERE company_id = ? AND client_id = ?",
        { companyId, clientId }
    )
end

local function DB_UpsertRelationship(companyId, clientId)
    MySQL.query.await(
        "INSERT IGNORE INTO trucker_client_relationships (company_id, client_id) VALUES (?, ?)",
        { companyId, clientId }
    )
    return DB_GetRelationship(companyId, clientId)
end

local function DB_GetCompanyRelationships(companyId)
    return MySQL.query.await(
        "SELECT * FROM trucker_client_relationships WHERE company_id = ?",
        { companyId }
    ) or {}
end

local function DB_UpdateRelationshipXP(id, xp, level, deliveries, revenue, streak)
    MySQL.update.await(
        "UPDATE trucker_client_relationships SET trust_xp = ?, trust_level = ?, total_deliveries = ?, total_revenue = ?, streak = ?, last_delivery_at = NOW() WHERE id = ?",
        { xp, level, deliveries, revenue, streak, id }
    )
end

local function DB_ResetStreak(id)
    MySQL.update.await(
        "UPDATE trucker_client_relationships SET streak = 0 WHERE id = ?",
        { id }
    )
end

local function DB_InsertContract(contract)
    MySQL.insert.await(
        [[INSERT INTO trucker_contracts (id, contract_type, total_payment, expires_at, client_id, relationship_id, bonus_percent, negotiated_payment)
          VALUES (?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, ?)]],
        { contract.id, contract.contract_type, contract.total_payment, contract.expires_at,
          contract.client_id, contract.relationship_id, contract.bonus_percent, contract.negotiated_payment }
    )
end

local function DB_InsertContractStop(stop)
    MySQL.insert.await(
        [[INSERT INTO trucker_contract_stops
          (contract_id, stop_order, location_id, location_name, coords_x, coords_y, coords_z, action, cargo_item, cargo_qty)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { stop.contract_id, stop.stop_order, stop.location_id, stop.location_name,
          stop.coords_x, stop.coords_y, stop.coords_z, stop.action, stop.cargo_item, stop.cargo_qty }
    )
end

local function DB_AcceptContract(contractId, citizenId, companyId)
    MySQL.update.await(
        "UPDATE trucker_contracts SET status = 'active', assigned_citizenid = ?, company_id = ?, accepted_at = NOW() WHERE id = ? AND status = 'available'",
        { citizenId, companyId, contractId }
    )
end

local function DB_CompleteContractStop(contractId, stopOrder)
    MySQL.update.await(
        "UPDATE trucker_contract_stops SET completed = 1 WHERE contract_id = ? AND stop_order = ?",
        { contractId, stopOrder }
    )
end

-- C-14: Retorna rowsAffected; WHERE status='active' garante idempotência atômica
local function DB_CompleteContract(contractId)
    return MySQL.update.await(
        "UPDATE trucker_contracts SET status = 'completed', completed_at = NOW() WHERE id = ? AND status = 'active'",
        { contractId }
    )
end

local function DB_GetActiveContract(citizenId)
    return MySQL.single.await(
        "SELECT * FROM trucker_contracts WHERE assigned_citizenid = ? AND status = 'active' LIMIT 1",
        { citizenId }
    )
end

local function DB_GetActiveContractCount(companyId)
    return MySQL.scalar.await(
        "SELECT COUNT(*) FROM trucker_contracts WHERE company_id = ? AND status = 'active'",
        { companyId }
    ) or 0
end

local function DB_GetContractStops(contractId)
    return MySQL.query.await(
        "SELECT * FROM trucker_contract_stops WHERE contract_id = ? ORDER BY stop_order ASC",
        { contractId }
    ) or {}
end

local function DB_GetAvailableContractsByCompany(companyId)
    return MySQL.query.await(
        "SELECT * FROM trucker_contracts WHERE company_id = ? AND status = 'available' AND expires_at > NOW()",
        { companyId }
    ) or {}
end

local function DB_ExpireContracts()
    MySQL.update.await(
        "UPDATE trucker_contracts SET status = 'expired' WHERE status = 'available' AND expires_at <= NOW()"
    )
end

-- ============================================================
-- TRUST & SECTOR LOGIC
-- ============================================================

local function GetTrustLevel(xp)
    local level = 1
    for i = 5, 1, -1 do
        if xp >= Config.TrustLevels[i].xpRequired then
            level = i
            break
        end
    end
    return level
end

local function GetSectorReputation(companyId, sectorType)
    local relationships = DB_GetCompanyRelationships(companyId)
    local total, count = 0, 0
    for _, rel in ipairs(relationships) do
        -- Find client sector
        for _, client in ipairs(Config.SecondaryIndustries) do
            if client.id == rel.client_id and client.type == sectorType then
                total = total + rel.trust_level
                count = count + 1
                break
            end
        end
    end
    return count > 0 and math.floor(total / count) or 0
end

local function GetMaxContracts(companyLevel)
    if companyLevel >= 21 then return 3 end
    if companyLevel >= 11 then return 2 end
    return 1
end

-- ============================================================
-- CLIENT LIST (para NUI)
-- ============================================================

function ContractService.GetClients(companyId, companyLevel)
    local ok, relationships = pcall(DB_GetCompanyRelationships, companyId)
    if not ok then relationships = {} end
    local relIndex = {}
    for _, rel in ipairs(relationships) do
        relIndex[rel.client_id] = rel
    end

    -- Calcular reputação por setor uma vez (evita N+1 queries)
    local sectorTotals = {}
    local sectorCounts = {}
    for _, rel in ipairs(relationships) do
        for _, client in ipairs(Config.SecondaryIndustries) do
            if client.id == rel.client_id then
                local st = client.type or 'mixed'
                sectorTotals[st] = (sectorTotals[st] or 0) + (rel.trust_level or 1)
                sectorCounts[st] = (sectorCounts[st] or 0) + 1
                break
            end
        end
    end

    local clients = {}
    for _, client in ipairs(Config.SecondaryIndustries) do
        local rel = relIndex[client.id]
        local sectorType = client.type or 'mixed'
        local sectorCfg = Config.ClientSectors[sectorType] or Config.ClientSectors.mixed
        local sectorRep = (sectorCounts[sectorType] and sectorCounts[sectorType] > 0)
            and math.floor(sectorTotals[sectorType] / sectorCounts[sectorType]) or 0
        local isPremium = sectorRep >= sectorCfg.premiumAt

        local locked = false
        if client.multiplier and client.multiplier >= 1.5 and not isPremium then
            locked = true
        end

        local trustLevel = rel and rel.trust_level or 0
        local trustXP = rel and rel.trust_xp or 0
        local trustCfg = Config.TrustLevels[math.max(1, trustLevel)] or Config.TrustLevels[1]

        clients[#clients + 1] = {
            id              = client.id,
            name            = client.name,
            sector          = sectorType,
            sectorLabel     = sectorCfg.label,
            trustLevel      = trustLevel,
            trustXP         = trustXP,
            trustLabel      = trustCfg.label,
            bonusPercent    = trustCfg.bonusPercent,
            totalDeliveries = rel and rel.total_deliveries or 0,
            totalRevenue    = rel and rel.total_revenue or 0,
            streak          = rel and rel.streak or 0,
            locked          = locked,
            sectorReputation = sectorRep,
            maxOptions      = trustCfg.maxOptions,
        }
    end

    return clients
end

-- ============================================================
-- NEGOTIATE & CREATE CONTRACT
-- ============================================================

function ContractService.Negotiate(src, clientId, terms)
    local Player = Framework.GetPlayer(src)
    if not Player then return false, 'Jogador não encontrado' end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company then return false, 'Você precisa estar em uma empresa' end

    -- Check contract limit
    local companyData = VP_Trucker.Companies[company.id]
    local companyLevel = companyData and companyData.company_level or 1
    local maxContracts = GetMaxContracts(companyLevel)
    local activeCount = DB_GetActiveContractCount(company.id)
    if activeCount >= maxContracts then
        return false, ('Limite de contratos atingido (%d/%d)'):format(activeCount, maxContracts)
    end

    -- Get or create relationship
    local rel = DB_UpsertRelationship(company.id, clientId)
    if not rel then return false, 'Erro ao criar relacionamento' end

    local trustLevel = rel.trust_level or 1
    local trustCfg = Config.TrustLevels[trustLevel] or Config.TrustLevels[1]

    -- Validate terms against trust level
    local volume = terms.volume or 1
    local prazo = terms.prazo or 30
    local frequencia = terms.frequencia or 1
    local maxOpt = trustCfg.maxOptions

    -- Clamp to allowed options
    local allowedVolumes = {}
    for i = 1, math.min(maxOpt, #Config.ContractNegotiation.volumes) do
        allowedVolumes[Config.ContractNegotiation.volumes[i]] = true
    end
    if not allowedVolumes[volume] then volume = Config.ContractNegotiation.volumes[1] end

    local allowedPrazos = {}
    for i = 1, math.min(maxOpt, #Config.ContractNegotiation.prazos) do
        allowedPrazos[Config.ContractNegotiation.prazos[i]] = true
    end
    if not allowedPrazos[prazo] then prazo = Config.ContractNegotiation.prazos[1] end

    local allowedFreq = {}
    for i = 1, math.min(maxOpt, #Config.ContractNegotiation.frequencias) do
        allowedFreq[Config.ContractNegotiation.frequencias[i]] = true
    end
    if not allowedFreq[frequencia] then frequencia = Config.ContractNegotiation.frequencias[1] end

    -- Find client config
    local clientCfg = nil
    for _, c in ipairs(Config.SecondaryIndustries) do
        if c.id == clientId then clientCfg = c; break end
    end
    if not clientCfg then return false, 'Cliente não encontrado' end

    -- Calculate payment
    local basePayment = 500  -- base por entrega
    local bonusPercent = trustCfg.bonusPercent
    local sectorType = clientCfg.type or 'mixed'
    local sectorRep = GetSectorReputation(company.id, sectorType)
    local sectorBonus = sectorRep * 5  -- +5% por nível de setor

    local paymentPerDelivery = math.floor(basePayment * volume * (clientCfg.multiplier or 1.0) * (1 + (bonusPercent + sectorBonus) / 100))
    local totalPayment = paymentPerDelivery * frequencia

    -- Create contract
    local contractId = 'contract_' .. os.time() .. '_' .. math.random(1000, 9999)
    local contract = {
        id                = contractId,
        contract_type     = frequencia > 1 and 'multi' or 'simple',
        total_payment     = totalPayment,
        expires_at        = os.time() + (prazo * 60),
        client_id         = clientId,
        relationship_id   = rel.id,
        bonus_percent     = bonusPercent + sectorBonus,
        negotiated_payment = paymentPerDelivery,
    }

    local ok, err = pcall(DB_InsertContract, contract)
    if not ok then return false, 'Erro ao criar contrato: ' .. tostring(err) end

    -- Create stops (pickup from random primary → deliver to client)
    for i = 1, frequencia do
        local origin = Config.PrimaryIndustries[math.random(#Config.PrimaryIndustries)]
        local product = origin.products[math.random(#origin.products)]

        -- Pickup
        pcall(DB_InsertContractStop, {
            contract_id   = contractId,
            stop_order    = (i - 1) * 2 + 1,
            location_id   = origin.id,
            location_name = origin.name,
            coords_x      = origin.coords.x,
            coords_y      = origin.coords.y,
            coords_z      = origin.coords.z,
            action        = 'pickup',
            cargo_item    = product.name,
            cargo_qty     = volume,
        })

        -- Delivery
        pcall(DB_InsertContractStop, {
            contract_id   = contractId,
            stop_order    = (i - 1) * 2 + 2,
            location_id   = clientId,
            location_name = clientCfg.name,
            coords_x      = clientCfg.coords.x,
            coords_y      = clientCfg.coords.y,
            coords_z      = clientCfg.coords.z,
            action        = 'delivery',
            cargo_item    = product.name,
            cargo_qty     = volume,
        })
    end

    -- Accept immediately
    DB_AcceptContract(contractId, citizenId, company.id)

    return true, ContractService.GetActive(citizenId)
end

-- ============================================================
-- ACTIVE CONTRACT
-- ============================================================

function ContractService.GetActive(citizenId)
    local contract = DB_GetActiveContract(citizenId)
    if not contract then return nil end

    local stops = DB_GetContractStops(contract.id)
    local currentStop = nil
    for _, s in ipairs(stops) do
        if s.completed == 0 then
            currentStop = s
            break
        end
    end

    -- Get client info
    local clientName = contract.client_id
    for _, c in ipairs(Config.SecondaryIndustries) do
        if c.id == contract.client_id then clientName = c.name; break end
    end

    return {
        id              = contract.id,
        contractType    = contract.contract_type,
        totalPayment    = contract.total_payment,
        bonusPercent    = contract.bonus_percent or 0,
        clientId        = contract.client_id,
        clientName      = clientName,
        stops           = stops,
        currentStop     = currentStop,
        totalStops      = #stops,
    }
end

-- ============================================================
-- COMPLETE STOP / CONTRACT
-- ============================================================

local function logContractSecurity(src, citizenId, reason, detail)
    local ac = Config.General and Config.General.contractAnticheat
    if not ac or ac.securityLog == false then return end
    print(('[^3AUST_trucker^7][security] CompleteStop denied | src=%s | cid=%s | %s | %s'):format(
        tostring(src or '?'),
        tostring(citizenId or '?'),
        tostring(reason),
        tostring(detail or '')
    ))
end

function ContractService.CompleteStop(citizenId, stopOrder)
    -- Back-compat: eventos antigos chamavam sem src. Se src não vier, só faz validações mínimas.
    local src = nil
    if type(stopOrder) == 'table' then
        -- Suporte caso chamador tenha migrado assinatura e mandou payload { stopOrder, src }
        src = tonumber(stopOrder.src)
        stopOrder = stopOrder.stopOrder
    end

    stopOrder = math.floor(tonumber(stopOrder) or 0)
    if stopOrder <= 0 then
        logContractSecurity(src, citizenId, 'invalid_stop_order', ('requested=%s'):format(tostring(stopOrder)))
        return false, 'Parada inválida'
    end

    local contract = DB_GetActiveContract(citizenId)
    if not contract then return false, 'Sem contrato ativo' end

    local stops = DB_GetContractStops(contract.id)
    if not stops or #stops == 0 then return false, 'Contrato inválido' end

    -- Regra: só pode concluir a PRÓXIMA parada pendente (sequencial).
    local currentStop = nil
    for _, s in ipairs(stops) do
        if s.completed == 0 then currentStop = s; break end
    end
    if not currentStop then
        return false, 'Contrato já concluído'
    end
    if tonumber(currentStop.stop_order) ~= stopOrder then
        logContractSecurity(src, citizenId, 'out_of_sequence',
            ('expected_stop=%s requested=%s'):format(tostring(currentStop.stop_order), tostring(stopOrder)))
        return false, 'Parada fora de ordem'
    end

    local ac = Config.General and Config.General.contractAnticheat or {}

    -- Validação de proximidade server-side (defesa contra TriggerServerEvent remoto).
    if src then
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then
            logContractSecurity(src, citizenId, 'invalid_ped', '')
            return false, 'Jogador inválido'
        end

        if ac.requireVehicle and not IsPedInAnyVehicle(ped, false) then
            logContractSecurity(src, citizenId, 'require_vehicle', 'not_in_vehicle')
            return false, 'Entre no veículo para registrar esta parada'
        end

        local pos = GetEntityCoords(ped)
        if pos.x == 0.0 and pos.y == 0.0 and pos.z == 0.0 then
            logContractSecurity(src, citizenId, 'invalid_position', '0,0,0')
            return false, 'Posição inválida'
        end
        local stopCoords = vector3(tonumber(currentStop.coords_x) or 0.0, tonumber(currentStop.coords_y) or 0.0, tonumber(currentStop.coords_z) or 0.0)
        local dist = #(pos - stopCoords)
        local baseDist = (Config.General and Config.General.interactionDistance) or 5.0
        local action = tostring(currentStop.action or 'delivery'):lower()
        local mult = ac.distanceMultiplier or 3.0
        if action == 'pickup' and ac.pickupDistanceMultiplier ~= nil then
            mult = ac.pickupDistanceMultiplier
        elseif action == 'delivery' and ac.deliveryDistanceMultiplier ~= nil then
            mult = ac.deliveryDistanceMultiplier
        end
        local maxAllowed = baseDist * mult
        if dist > maxAllowed then
            logContractSecurity(src, citizenId, 'too_far',
                ('dist=%.1f max=%.1f action=%s'):format(dist, maxAllowed, action))
            return false, 'Muito longe do local'
        end
    end

    DB_CompleteContractStop(contract.id, stopOrder)

    local allDone = true
    for _, s in ipairs(stops) do
        if tonumber(s.stop_order) == stopOrder then
            s.completed = 1
        end
        if s.completed == 0 then allDone = false end
    end

    if allDone then
        return ContractService.Complete(citizenId)
    end

    return true, 'stop_completed'
end

function ContractService.Complete(citizenId)
    local contract = DB_GetActiveContract(citizenId)
    if not contract then return false, 'Sem contrato ativo' end

    -- C-14: Atualização atômica — retorna 0 se outro coroutine já completou
    local affected = DB_CompleteContract(contract.id)
    if not affected or affected == 0 then
        return false, 'Contrato já processado'
    end

    -- Pay player
    local src = nil
    for _, playerId in ipairs(GetPlayers()) do
        local p = Framework.GetPlayer(tonumber(playerId))
        if p and Framework.GetCitizenId(p) == citizenId then
            src = tonumber(playerId)
            break
        end
    end

    if src then
        local Player = Framework.GetPlayer(src)
        if Player then
            Framework.AddMoney(Player, 'bank', contract.total_payment, 'contract-completion')
            pcall(DB_AddPlayerStats, citizenId, contract.total_payment, 0)
        end
    end

    -- Update relationship XP
    if contract.relationship_id then
        local rel = MySQL.single.await("SELECT * FROM trucker_client_relationships WHERE id = ?", { contract.relationship_id })
        if rel then
            local xpGain = 100 + (rel.streak * 10)  -- streak bonus
            local newXP = (rel.trust_xp or 0) + xpGain
            local newLevel = GetTrustLevel(newXP)
            local newDeliveries = (rel.total_deliveries or 0) + 1
            local newRevenue = (rel.total_revenue or 0) + contract.total_payment
            local newStreak = (rel.streak or 0) + 1

            DB_UpdateRelationshipXP(rel.id, newXP, newLevel, newDeliveries, newRevenue, newStreak)
        end
    end

    -- Company XP
    if contract.company_id then
        local companyBonus = math.floor(contract.total_payment * 0.1)
        pcall(CompanyService.AddBalance, contract.company_id, companyBonus)
    end

    -- Shop Stock Ecosystem: ressuprimento → atualizar estoque da loja
    if contract.contract_source == 'resupply' and contract.target_shop_id and contract.target_item then
        local deliveryQty = MySQL.scalar.await(
            "SELECT COALESCE(SUM(cargo_qty), 0) FROM trucker_contract_stops WHERE contract_id = ? AND action = 'delivery'",
            { contract.id }
        ) or 0
        if deliveryQty > 0 and ShopStockService then
            pcall(ShopStockService.OnDelivery, contract.target_shop_id, contract.target_item, deliveryQty)
        end
    end

    return true, 'contract_completed'
end

function ContractService.Abandon(citizenId)
    local contract = DB_GetActiveContract(citizenId)
    if not contract then return false end

    MySQL.update.await("UPDATE trucker_contracts SET status = 'expired' WHERE id = ?", { contract.id })

    -- Penalize relationship
    if contract.relationship_id then
        local rel = MySQL.single.await("SELECT * FROM trucker_client_relationships WHERE id = ?", { contract.relationship_id })
        if rel then
            local newXP = math.max(0, (rel.trust_xp or 0) - 200)
            local newLevel = GetTrustLevel(newXP)
            MySQL.update.await(
                "UPDATE trucker_client_relationships SET trust_xp = ?, trust_level = ?, streak = 0 WHERE id = ?",
                { newXP, newLevel, rel.id }
            )
        end
    end

    return true
end

-- ============================================================
-- RESUPPLY CONTRACTS (Shop Stock Ecosystem v16.0.0)
-- ============================================================

--- Cria contrato de ressuprimento para uma loja com estoque baixo.
--- Chamado por ShopStockService.CheckAndCreateContracts().
--- @return string|nil contractId
function ContractService.CreateResupplyContract(shopId, itemName, qty, shopName, shopCoords, originIndustry, paymentPerUnit)
    local contractId = 'resupply_' .. os.time() .. '_' .. math.random(1000, 9999)
    local totalPayment = qty * (paymentPerUnit or 15)
    local expiryMin = (Config.ShopStock and Config.ShopStock.ContractExpiryMinutes) or 120

    -- Insert contract
    local ok, err = pcall(MySQL.insert.await, [[
        INSERT INTO trucker_contracts (id, contract_type, total_payment, status, expires_at, contract_source, target_shop_id, target_item)
        VALUES (?, 'simple', ?, 'available', DATE_ADD(NOW(), INTERVAL ? MINUTE), 'resupply', ?, ?)
    ]], { contractId, totalPayment, expiryMin, shopId, itemName })

    if not ok then
        print(('[aurp_trucker] ContractService: ERRO ao criar contrato ressuprimento: %s'):format(tostring(err)))
        return nil
    end

    -- Pickup stop: da indústria
    pcall(MySQL.insert.await, [[
        INSERT INTO trucker_contract_stops (contract_id, stop_order, location_id, location_name, coords_x, coords_y, coords_z, action, cargo_item, cargo_qty)
        VALUES (?, 1, ?, ?, ?, ?, ?, 'pickup', ?, ?)
    ]], {
        contractId,
        originIndustry.id, originIndustry.name,
        originIndustry.coords.x, originIndustry.coords.y, originIndustry.coords.z,
        itemName, qty
    })

    -- Delivery stop: para a loja
    pcall(MySQL.insert.await, [[
        INSERT INTO trucker_contract_stops (contract_id, stop_order, location_id, location_name, coords_x, coords_y, coords_z, action, cargo_item, cargo_qty)
        VALUES (?, 2, ?, ?, ?, ?, ?, 'delivery', ?, ?)
    ]], {
        contractId,
        shopId, shopName,
        shopCoords.x, shopCoords.y, shopCoords.z,
        itemName, qty
    })

    if Config.Debug then
        print(('[aurp_trucker] Resupply contract %s: %dx %s | %s → %s | $%d'):format(
            contractId, qty, itemName, originIndustry.name, shopName, totalPayment
        ))
    end

    return contractId
end

print('[aurp_trucker] ContractService: pronto')
