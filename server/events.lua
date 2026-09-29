-- aurp_trucker — server/events.lua
-- RegisterNetEvent handlers (extraídos de server.lua)
-- Apenas lógica de validação + delegate para services

local function netEntityExists(netId)
    netId = tonumber(netId)
    if not netId then return false end
    local e = NetworkGetEntityFromNetworkId(netId)
    return e ~= 0 and DoesEntityExist(e)
end

-- =====================================================
-- JOB HANDLERS
-- =====================================================

RegisterNetEvent('aurp_trucker:acceptJob', function(jobId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- Crude oil order: just set GPS to well, no formal job entry
    if tostring(jobId):sub(1, 6) == 'crude_' then
        -- Still block if player has an active regular job
        if JobService.GetActiveByPlayer(citizenId) then
            TriggerClientEvent('aurp_trucker:notify', src, 'Você já tem um job ativo', 'error')
            return
        end

        -- Permit: transport_commercial obrigatória para Modo B
        local hasPermit = true
        pcall(function()
            hasPermit = exports['AUST_governo']:HasPermit(citizenId, 'transport_commercial')
        end)
        if not hasPermit then
            TriggerClientEvent('aurp_trucker:notify', src, 'Licença de transporte comercial necessária', 'error')
            return
        end

        -- DEFCON: bloca Modo B em nível 2 ou inferior
        local defcon = 5
        pcall(function() defcon = exports['AUST_governo']:GetCurrentDefcon() end)
        if defcon <= 2 then
            TriggerClientEvent('aurp_trucker:notify', src, 'Transportes suspensos — DEFCON ' .. defcon, 'error')
            return
        end

        local wellId = tonumber(tostring(jobId):sub(7))
        local ok, orders = pcall(function() return exports['AUST_oilfield']:GetPostedOrders() end)
        if ok and orders then
            for _, o in ipairs(orders) do
                if o.wellId == wellId and o.coords and o.coords.x then
                    TriggerClientEvent('aurp_trucker:client:setCrudeGPS', src, o.coords)
                    break
                end
            end
        end
        return
    end

    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'acceptJob') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Aguarde antes de aceitar outro job.', 'error')
        return
    end

    -- Verificar se já tem job ativo
    if JobService.GetActiveByPlayer(citizenId) then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você já tem um job ativo', 'error')
        return
    end

    local company = CompanyService.GetByMember(citizenId)
    local accepted = JobService.Accept(jobId, citizenId, company and company.id or nil)
    if not accepted then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você não possui a certificação ADR necessária para este cargo', 'error')
        return
    end

    local jobData = JobService.GetActiveByPlayer(citizenId)
    TriggerClientEvent('aurp_trucker:client:jobStarted', src, jobData)
    TriggerClientEvent('aurp_trucker:client:startCargoMonitoring', src)   -- v14
    TriggerEvent('aurp_trucker:jobAccepted', citizenId, company and company.id or nil, jobData)
end)

RegisterNetEvent('aurp_trucker:completeJob', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    -- payload = { deliveryTime, plate, cargoIntegrity }

    -- Verifica se é entrega de carga roubada
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'completeJob') then return end

    local cargoEntry = CargoTrackingService.ClaimDelivery(payload.plate, citizenId)
    if cargoEntry and cargoEntry.isStolen then
        -- Caminho de carga roubada
        local payment = JobService.CompleteTheft(src, cargoEntry, payload)
        if payment then
            TriggerClientEvent('aurp_trucker:client:jobCompleted', src, payment)
            TriggerClientEvent('aurp_trucker:notify', src,
                ('Carga entregue! [ROUBADA] $%d recebidos'):format(payment), 'success')
        end
        return
    end

    -- Caminho normal
    local ok, payment = JobService.Complete(src, payload)
    if ok then
        local integrityPct = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
        TriggerClientEvent('aurp_trucker:client:jobCompleted', src, payment)
        TriggerClientEvent('aurp_trucker:notify', src,
            ('Job concluído! Carga: %d%% — $%d recebidos'):format(integrityPct, payment), 'success')
    end
end)

RegisterNetEvent('aurp_trucker:abandonJob', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    JobService.Abandon(citizenId)

    -- Limpeza estrita de entidades (caminhão e trailer) no servidor
    if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
        local jobEnts = VP_Trucker.PlayerJobEntities[citizenId]
        if jobEnts.truckNetId then
            local truck = NetworkGetEntityFromNetworkId(jobEnts.truckNetId)
            if truck and DoesEntityExist(truck) then DeleteEntity(truck) end
        end
        if jobEnts.trailerNetId then
            local trailer = NetworkGetEntityFromNetworkId(jobEnts.trailerNetId)
            if trailer and DoesEntityExist(trailer) then DeleteEntity(trailer) end
        end
        VP_Trucker.PlayerJobEntities[citizenId] = nil
    end

    TriggerClientEvent('aurp_trucker:client:jobAbandoned', src)
end)

-- Registra netId de caminhão e trailer do jogador para tracking e cleanup autoritativo
RegisterNetEvent('aurp_trucker:server:registerJobEntities', function(truckNetId, trailerNetId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    VP_Trucker.PlayerJobEntities = VP_Trucker.PlayerJobEntities or {}
    VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}

    if truckNetId and tonumber(truckNetId) then
        VP_Trucker.PlayerJobEntities[citizenId].truckNetId = tonumber(truckNetId)
        if TruckRentalService then
            TruckRentalService.RegisterNetId(citizenId, truckNetId)
        end
        local truckEnt = NetworkGetEntityFromNetworkId(tonumber(truckNetId))
        if truckEnt and DoesEntityExist(truckEnt) then
            pcall(function()
                if exports['qbx_vehiclekeys'] then
                    exports['qbx_vehiclekeys']:GiveKeys(src, truckEnt)
                end
            end)
        end
    end
    if trailerNetId and tonumber(trailerNetId) then
        VP_Trucker.PlayerJobEntities[citizenId].trailerNetId = tonumber(trailerNetId)
    end
end)

RegisterNetEvent('aurp_trucker:rental:registerNetId', function(netId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    if netId and tonumber(netId) then
        if TruckRentalService then
            TruckRentalService.RegisterNetId(citizenId, netId)
        end
        local veh = NetworkGetEntityFromNetworkId(tonumber(netId))
        if veh and DoesEntityExist(veh) then
            pcall(function()
                if exports['qbx_vehiclekeys'] then
                    exports['qbx_vehiclekeys']:GiveKeys(src, veh)
                end
            end)
        end
    end
end)

-- Limpeza ao morrer durante a rota
RegisterNetEvent('aurp_trucker:server:onPlayerDeath', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
        local jobEnts = VP_Trucker.PlayerJobEntities[citizenId]
        if jobEnts.truckNetId then
            local truck = NetworkGetEntityFromNetworkId(jobEnts.truckNetId)
            if truck and DoesEntityExist(truck) then DeleteEntity(truck) end
        end
        if jobEnts.trailerNetId then
            local trailer = NetworkGetEntityFromNetworkId(jobEnts.trailerNetId)
            if trailer and DoesEntityExist(trailer) then DeleteEntity(trailer) end
        end
        VP_Trucker.PlayerJobEntities[citizenId] = nil
    end

    if JobService.GetActiveByPlayer(citizenId) then
        JobService.Abandon(citizenId)
        TriggerClientEvent('aurp_trucker:client:jobAbandoned', src)
    end
end)

-- =====================================================
-- COMPANY HANDLERS
-- =====================================================

RegisterNetEvent('aurp_trucker:createCompany', function(name, companyType)
    local src = source
    local companyId, err = CompanyService.Create(src, name, companyType)
    if err then
        TriggerClientEvent('aurp_trucker:notify', src, err, 'error')
        return
    end
    local company = CompanyService.Get(companyId)
    TriggerClientEvent('aurp_trucker:client:companyUpdated', src, company)
    TriggerClientEvent('aurp_trucker:notify', src, 'Empresa criada com sucesso!', 'success')
end)

RegisterNetEvent('aurp_trucker:joinCompany', function(companyId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local company = CompanyService.Get(companyId)
    if not company or company.is_recruiting == 0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Empresa não está recrutando', 'error')
        return
    end

    local ok, err = CompanyService.AddMember(companyId, citizenId)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('aurp_trucker:client:companyUpdated', src, CompanyService.Get(companyId))
    TriggerClientEvent('aurp_trucker:notify', src, 'Você entrou na empresa!', 'success')
end)

RegisterNetEvent('aurp_trucker:leaveCompany', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company then return end

    -- Owner não pode sair sem vender/transferir
    if company.owner_citizenid == citizenId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Owner deve vender a empresa para sair', 'error')
        return
    end

    CompanyService.RemoveMember(citizenId)
    TriggerClientEvent('aurp_trucker:client:companyUpdated', src, nil)
    TriggerClientEvent('aurp_trucker:notify', src, 'Você saiu da empresa', 'inform')
end)

RegisterNetEvent('aurp_trucker:kickMember', function(targetCitizenId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company or company.owner_citizenid ~= citizenId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Sem permissão', 'error')
        return
    end
    -- S-01: Verificar que target pertence à MESMA empresa
    local targetMember = DB_GetMember(targetCitizenId)
    if not targetMember or targetMember.company_id ~= company.id then
        TriggerClientEvent('aurp_trucker:notify', src, 'Membro não pertence à sua empresa', 'error')
        return
    end
    CompanyService.RemoveMember(targetCitizenId)
    TriggerClientEvent('aurp_trucker:notify', src, 'Membro removido', 'success')
end)

RegisterNetEvent('aurp_trucker:toggleRecruiting', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    -- C-03: Role check — apenas owner/manager
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then return end
    local company = CompanyService.GetByMember(citizenId)
    if not company then return end
    local newState = company.is_recruiting == 0
    CompanyService.SetRecruiting(company.id, newState)
    TriggerClientEvent('aurp_trucker:notify', src,
        newState and 'Recrutamento ativado' or 'Recrutamento desativado', 'inform')
end)

RegisterNetEvent('aurp_trucker:depositMoney', function(amount)
    local src = source
    -- #4: Validar amount (previne exploit com valores negativos/zero)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local Player = Framework.GetPlayer(src)
    if not Player then return end

    -- v15: rate limit (antes de GetByMember para evitar DB call desnecessária)
    if not AntiCheatService.RateLimit(Framework.GetCitizenId(Player), 'depositMoney') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Aguarde antes de depositar novamente.', 'error')
        return
    end

    local company = CompanyService.GetByMember(Framework.GetCitizenId(Player))
    if not company then return end
    local ok, err = CompanyService.Deposit(company.id, src, amount)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('aurp_trucker:client:companyUpdated', src, CompanyService.Get(company.id))
end)

RegisterNetEvent('aurp_trucker:withdrawMoney', function(amount)
    local src = source
    -- #5: Validar amount (previne exploit com valores negativos/zero)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'withdrawMoney') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Aguarde antes de sacar novamente.', 'error')
        return
    end

    local company = CompanyService.GetByMember(citizenId)
    if not company then return end
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Sem permissão para sacar', 'error')
        return
    end
    local ok, err = CompanyService.Withdraw(company.id, src, citizenId, amount)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('aurp_trucker:client:companyUpdated', src, CompanyService.Get(company.id))
end)

RegisterNetEvent('aurp_trucker:registerVehicle', function(plate, model, vehicleType)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    -- C-04: Role check — apenas owner/manager
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then return end
    local company = CompanyService.GetByMember(citizenId)
    if not company then return end
    -- H-02: Whitelist de vehicleType — previne data poisoning no banco
    local VALID_VEHICLE_TYPES = { truck = true, van = true, trailer = true }
    vehicleType = type(vehicleType) == 'string' and vehicleType or 'truck'
    if not VALID_VEHICLE_TYPES[vehicleType] then
        TriggerClientEvent('aurp_trucker:notify', src, 'Tipo de veículo inválido', 'error')
        return
    end
    local ok, err = CompanyService.RegisterVehicle(company.id, plate, model, vehicleType)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err, 'error')
        return
    end
    TriggerClientEvent('aurp_trucker:notify', src, 'Veículo registrado!', 'success')
end)

RegisterNetEvent('aurp_trucker:removeVehicle', function(plate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    -- C-04 + S-02: Role check + validar que plate pertence à empresa do caller
    local member = DB_GetMember(citizenId)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then return end
    local company = CompanyService.GetByMember(citizenId)
    if not company then return end
    -- S-02: Verificar que o veículo pertence a esta empresa
    local vehicles = CompanyService.GetVehicles and CompanyService.GetVehicles(company.id)
    if vehicles then
        local found = false
        for _, v in ipairs(vehicles) do if v.plate == plate then found = true; break end end
        if not found then return end
    end
    CompanyService.RemoveVehicle(plate)
    TriggerClientEvent('aurp_trucker:notify', src, 'Veículo removido', 'inform')
end)

RegisterNetEvent('aurp_trucker:sellCompany', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local company = CompanyService.GetByMember(citizenId)
    if not company or company.owner_citizenid ~= citizenId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Apenas o owner pode vender', 'error')
        return
    end
    local ok, err = CompanyService.Sell(company.id, src)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Falha ao vender empresa', 'error')
        return
    end
    TriggerClientEvent('aurp_trucker:client:companyUpdated', src, nil)
    TriggerClientEvent('aurp_trucker:notify', src, 'Empresa vendida por $25.000', 'success')
end)

-- =====================================================
-- INDUSTRY TRADING HANDLERS
-- =====================================================

RegisterNetEvent('aurp_trucker:buyFromIndustry', function(industryId, item, qty)
    local src = source
    -- H-04: Sanitizar qty — previne exploit de qty negativa/zero/overflow
    qty = math.floor(tonumber(qty) or 0)
    if qty <= 0 or qty > 500 then return end
    local ok, err = IndustryService.BuyFrom(src, industryId, item, qty)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Erro na compra', 'error')
    else
        TriggerClientEvent('aurp_trucker:notify', src, ('Comprado: %dx %s'):format(qty, item), 'success')
    end
end)

RegisterNetEvent('aurp_trucker:sellToIndustry', function(industryId, item, qty)
    local src = source
    -- H-04: Sanitizar qty — previne exploit de qty negativa (RemoveItem(-n) pode adicionar itens)
    qty = math.floor(tonumber(qty) or 0)
    if qty <= 0 or qty > 500 then return end
    local ok, err = IndustryService.SellTo(src, industryId, item, qty)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Erro na venda', 'error')
    else
        TriggerClientEvent('aurp_trucker:notify', src, ('Vendido: %dx %s'):format(qty, item), 'success')
    end
end)

-- =====================================================
-- CONTRACT HANDLERS (Relacionamento Empresa↔Cliente)
-- =====================================================

RegisterNetEvent('aurp_trucker:negotiateContract', function(clientId, terms)
    local src = source
    if not clientId or not terms then return end
    local ok, result = ContractService.Negotiate(src, clientId, terms)
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, result or 'Erro ao negociar contrato', 'error')
        return
    end
    TriggerClientEvent('aurp_trucker:client:contractStarted', src, result)
end)

RegisterNetEvent('aurp_trucker:completeContractStop', function(stopOrder)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    if not AntiCheatService.RateLimit(citizenId, 'completeContractStop') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Aguarde antes de registrar outra parada.', 'error')
        return
    end

    -- Passar src para validação de proximidade server-side
    local ok, status = ContractService.CompleteStop(citizenId, { stopOrder = stopOrder, src = src })
    if not ok then
        TriggerClientEvent('aurp_trucker:notify', src, status or 'Erro na parada', 'error')
        return
    end

    if status == 'contract_completed' then
        TriggerClientEvent('aurp_trucker:notify', src, 'Contrato concluído! Pagamento depositado.', 'success')
        TriggerClientEvent('aurp_trucker:client:contractCompleted', src)
    else
        local contract = ContractService.GetActive(citizenId)
        TriggerClientEvent('aurp_trucker:client:contractStopCompleted', src, contract)
    end
end)

RegisterNetEvent('aurp_trucker:abandonContract', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    ContractService.Abandon(citizenId)
    TriggerClientEvent('aurp_trucker:notify', src, 'Contrato abandonado. Reputação perdida.', 'error')
    TriggerClientEvent('aurp_trucker:client:contractCompleted', src)
end)

-- =====================================================
-- PLAYER LIFECYCLE
-- =====================================================

AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    -- DB_UpsertPlayerStats DEVE rodar antes de TruckSimulationService.OnPlayerLoaded
    -- para garantir que a linha de progressão existe antes de DB_GetFatigue
    local citizenId = Framework.GetCitizenId(Player)
    DB_UpsertPlayerStats(citizenId)
    TruckSimulationService.OnPlayerLoaded(src)
    if PartyService then
        PartyService.OnPlayerReconnect(src, citizenId)
    end
end)

-- L1: Equivalente ESX para QBCore:Server:OnPlayerLoaded
-- esx:playerLoaded signature: (playerId, xPlayer, isNew)
if Config.Framework == 'esx' then
    AddEventHandler('esx:playerLoaded', function(playerId)
        local src    = playerId
        local Player = Framework.GetPlayer(src)
        if not Player then return end
        local citizenId = Framework.GetCitizenId(Player)
        DB_UpsertPlayerStats(citizenId)
        TruckSimulationService.OnPlayerLoaded(src)
        if PartyService then
            PartyService.OnPlayerReconnect(src, citizenId)
        end
    end)
end

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
        TriggerClientEvent('aurp_trucker:client:jobsUpdated', -1)
    end
end)

-- ============================================================
-- LOANS
-- ============================================================

RegisterNetEvent('aurp_trucker:requestLoan', function(amount, isCompanyLoan, vehiclePlate)
    amount = math.floor(tonumber(amount) or 0)
    local src       = source
    local Player    = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- Normalizar plate (6A)
    vehiclePlate = type(vehiclePlate) == 'string' and vehiclePlate:upper() or nil

    local companyId = nil
    if isCompanyLoan then
        local company = CompanyService.GetByMember(citizenId)
        if not company then
            lib.notify(src, { title = 'Empréstimo', description = 'Você não pertence a uma empresa', type = 'error' })
            return
        end
        local member = DB_GetMember(citizenId)
        if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
            lib.notify(src, { title = 'Empréstimo', description = 'Apenas Owner ou Manager podem contratar empréstimo empresarial', type = 'error' })
            return
        end
        companyId = company.id

        -- Validar que a plate pertence à empresa, se fornecida (6A)
        if vehiclePlate then
            local vehicles = DB_GetVehicles(companyId) or {}
            local valid = false
            for _, v in ipairs(vehicles) do
                if v.plate == vehiclePlate then valid = true; break end
            end
            if not valid then
                lib.notify(src, { title = 'Empréstimo', description = 'Veículo não pertence à sua empresa', type = 'error' })
                return
            end
        end
    else
        -- Empréstimo pessoal: vehicle_plate só válido se player tem empresa e veículo pertence a ela (fix #7)
        if vehiclePlate then
            local playerCompanyId = VP_Trucker.PlayerCompanies[citizenId]
            if playerCompanyId then
                local vehicles = DB_GetVehicles(playerCompanyId) or {}
                local valid = false
                for _, v in ipairs(vehicles) do
                    if v.plate == vehiclePlate then valid = true; break end
                end
                if not valid then
                    lib.notify(src, { title = 'Empréstimo', description = 'Veículo não encontrado', type = 'error' })
                    return
                end
            else
                -- Sem empresa: não é possível penhorar veículo
                vehiclePlate = nil
            end
        end
    end

    local result = LoanService.Create(src, citizenId, companyId, amount, vehiclePlate)

    if not result.success then
        lib.notify(src, { title = 'Empréstimo', description = result.reason, type = 'error' })
        return
    end

    lib.notify(src, {
        title       = 'Empréstimo Aprovado',
        description = ('$%s creditado na sua conta'):format(amount),
        type        = 'success',
        duration    = 6000,
    })

    TriggerClientEvent('aurp_trucker:client:loanUpdate', src, result.loan)
end)

-- ============================================================
-- REPO MAN
-- ============================================================

RegisterNetEvent('aurp_trucker:completeRepoOrder', function(orderId)
    local src = source

    -- Validação server-side: jogador deve estar próximo ao impound (6B)
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) or ped == 0 then
        lib.notify(src, { title = 'Repo Man', description = 'Jogador inválido', type = 'error' })
        return
    end
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

    local result = RepoService.Complete(src, tonumber(orderId) or 0)
    if not result.success then
        lib.notify(src, { title = 'Repo Man', description = result.reason, type = 'error' })
    end
end)

RegisterNetEvent('aurp_trucker:failRepoOrder', function(orderId)
    local src    = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local result = RepoService.Fail(src, tonumber(orderId) or 0)
    if not result.success and result.reason then
        lib.notify(src, { title = 'Repo Man', description = result.reason, type = 'error' })
    end
end)

RegisterNetEvent('aurp_trucker:repoAgentPositionUpdate')
AddEventHandler('aurp_trucker:repoAgentPositionUpdate', function(orderId, coords)
    local src    = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end

    -- Buscar ordem e descobrir dono
    local order = DB_GetRepoOrderById(tonumber(orderId) or 0)
    if not order or order.status ~= 'active' then return end
    if not order.vehicle_owner_citizenid then return end
    if order.assigned_citizenid ~= Framework.GetCitizenId(Player) then return end

    -- Relay coords ao dono (se online)
    local ownerSrc = Framework.FindPlayerByCitizenId(order.vehicle_owner_citizenid)
    if ownerSrc then
        TriggerClientEvent('aurp_trucker:client:repoAgentUpdate', ownerSrc, { coords = coords })
    end
end)

RegisterNetEvent('aurp_trucker:repoNotifyOwner')
AddEventHandler('aurp_trucker:repoNotifyOwner', function(orderId, spawnCoords)
    local src    = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end

    local order = DB_GetRepoOrderById(tonumber(orderId) or 0)
    if not order or not order.vehicle_owner_citizenid then return end
    if order.assigned_citizenid ~= Framework.GetCitizenId(Player) then return end

    local charInfo  = Framework.GetCharInfo(Player)
    local agentName = charInfo and (charInfo.firstname .. ' ' .. charInfo.lastname) or 'Agente'

    -- spawnCoords vem do client — H-06: sanitizar coordenadas para prevenir GPS spoofing
    local coords
    if type(spawnCoords) == 'table' then
        coords = {
            x = math.floor(tonumber(spawnCoords.x) or 0),
            y = math.floor(tonumber(spawnCoords.y) or 0),
            z = math.floor(tonumber(spawnCoords.z) or 0),
        }
    else
        coords = { x = 0, y = 0, z = 0 }
    end

    local ownerSrc = Framework.FindPlayerByCitizenId(order.vehicle_owner_citizenid)
    if ownerSrc then
        TriggerClientEvent('aurp_trucker:client:repoTargetNotify', ownerSrc, {
            agentName   = agentName,
            zone_coords = coords,
        })
    end
end)

-- ============================================================
-- FASE 5: FORKLIFT — pallet loading
-- ============================================================

-- Atualiza expected no rental quando client inicia industry load com qty real
RegisterNetEvent('aurp_trucker:updateForkliftExpected', function(qty)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if rental and rental.mode == 'industry' then
        -- #14: Validar qty — mínimo 1, máximo o original
        local newQty = math.floor(tonumber(qty) or 0)
        if newQty >= 1 and newQty <= (rental.expected or 99) then
            rental.expected = newQty
        end
    end
end)

-- H-03: registrar netId do forklift para limpeza de entidade em playerDropped
RegisterNetEvent('aurp_trucker:forklift:setNetId', function(netId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if rental then
        rental.forkliftNetId = tonumber(netId)
    end
end)

RegisterNetEvent('aurp_trucker:palletLoaded', function(netId, locationId)
    local src = source

    -- Validar existência da entidade na rede
    if not netEntityExists(netId) then return end
    local obj = NetworkGetEntityFromNetworkId(netId)

    -- H-07: Confirmar que é um objeto (type 3), não um ped ou veículo
    if GetEntityType(obj) ~= 3 then return end

    -- Validar ownership via StateBag: client armazena tostring(GetPlayerServerId(PlayerId()))
    -- que é o mesmo que tostring(src) no server
    if Entity(obj).state.forklift_owner ~= tostring(src) then return end

    -- Lookup Player e rental ANTES de deletar — evita desync se player desconectar entre a
    -- checagem do StateBag e o GetPlayer (entidade seria deletada mas loaded nunca incrementado)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if not rental then return end

    -- Seguro deletar agora
    DeleteEntity(obj)

    rental.loaded = rental.loaded + 1

    -- Notificar client se todos os pallets foram carregados
    if rental.loaded >= rental.expected then
        TriggerClientEvent('aurp_trucker:client:allPalletsLoaded', src, locationId)
    end
end)

-- =====================================================
-- TRUCK SIMULATION
-- =====================================================

AddEventHandler('playerDropped', function()
    local src = source
    -- Capturar citizenid ANTES de src ficar stale
    local Player = Framework.GetPlayer(src)
    local citizenid = Player and Framework.GetCitizenId(Player)
    if citizenid then
        ForkliftService.OnPlayerDropped(citizenid)
        AntiCheatService.CleanupPlayer(citizenid)  -- v15: limpar cooldowns
        -- Limpar cargo tracking: owner desconectado → remover entrada; thief desconectado → cancelar roubo
        for plate, cargo in pairs(VP_Trucker.CargoByPlate) do
            if cargo.citizenId == citizenid then
                CargoTrackingService.RemoveCargo(plate)
            elseif cargo.theftBy == citizenid then
                CargoTrackingService.CancelTheft(plate, citizenid)
            end
        end
    end
    TruckSimulationService.OnPlayerDropped(src)
        if citizenid and PartyService then
        PartyService.OnPlayerDisconnect(src, citizenid)
    end
    -- audit C-03: Container Handler cleanup (v20) — centralizado aqui em vez de handler separado
    if citizenid then
        pcall(ContainerHandlerService.OnPlayerDropped, citizenid)

        -- Limpeza estrita de entidades órfãs (caminhão e trailer) via DeleteEntity
        if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenid] then
            local jobEnts = VP_Trucker.PlayerJobEntities[citizenid]
            if jobEnts.truckNetId then
                local truck = NetworkGetEntityFromNetworkId(jobEnts.truckNetId)
                if truck and DoesEntityExist(truck) then DeleteEntity(truck) end
            end
            if jobEnts.trailerNetId then
                local trailer = NetworkGetEntityFromNetworkId(jobEnts.trailerNetId)
                if trailer and DoesEntityExist(trailer) then DeleteEntity(trailer) end
            end
            VP_Trucker.PlayerJobEntities[citizenid] = nil
        end
        if TruckRentalService then
            TruckRentalService.OnPlayerDropped(citizenid)
        end
    end
end)

RegisterNetEvent('aurp_trucker:syncSimulation', function(payload)
    TruckSimulationService.OnSync(source, payload)
end)

RegisterNetEvent('aurp_trucker:vehicleDestroyed', function(payload)
    TruckSimulationService.OnVehicleDestroyed(source, payload)
end)

RegisterNetEvent('aurp_trucker:spawnVehicle', function(plate)
    TruckSimulationService.OnVehicleSpawn(source, plate)
end)

RegisterNetEvent('aurp_trucker:purchaseFleetUpgrade', function(upgradeKey)
    local result = TruckSimulationService.PurchaseUpgrade(source, upgradeKey)
    TriggerClientEvent('aurp_trucker:client:upgradeResult', source, result)
end)

-- ============================================================
-- FASE 3B: Illegal Deliveries
-- ============================================================

-- Cop: lacra a carga de um caminhão ilegal via ox_target
RegisterNetEvent('aurp_trucker:seizeIllegalCargo', function(plate)
    local src = source
    if not plate then return end
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local jobName = Framework.GetJob(Player).name
    if jobName ~= 'police' and jobName ~= 'sasp' then return end

    -- C-15: Validação de proximidade server-side (ox_target tem range client-side,
    -- mas um cliente malicioso pode disparar o evento à distância arbitrária)
    local target = VP_Trucker.IllegalTargets and VP_Trucker.IllegalTargets[plate]
    if target and target.src then
        local copCoords    = GetEntityCoords(GetPlayerPed(src))
        local driverCoords = GetEntityCoords(GetPlayerPed(target.src))
        if copCoords and driverCoords then
            local dx   = copCoords.x - driverCoords.x
            local dy   = copCoords.y - driverCoords.y
            local dz   = copCoords.z - driverCoords.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist > Config.IllegalJobs.SeizeRange then
                TriggerClientEvent('aurp_trucker:notify', src, 'Muito longe do veículo', 'error')
                return
            end
        end
    end

    if IllegalService then
        IllegalService.Seize(src, plate)
    end
end)

-- Motorista entra no caminhão com job ilegal ativo — registra placa para apreensão
RegisterNetEvent('aurp_trucker:illegalRegisterPlate', function(plate)
    local src = source
    if not plate then return end
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local cid = Framework.GetCitizenId(Player)
    local activeJob = DB_GetActiveJobByPlayer(cid)
    if not activeJob or not activeJob.illegal_type then return end
    if IllegalService then
        IllegalService.RegisterSeizureTarget(src, activeJob.id, plate, activeJob.illegal_type)
    end
end)

-- =====================================================
-- NPC DRIVERS — SALA CONTRABAND ALERT (v10.0.0)
-- =====================================================

AddEventHandler('aurp_trucker:npcContrabandAlert', function(data)
    local label = (Config.IllegalJobs and Config.IllegalJobs.alertLabels and Config.IllegalJobs.alertLabels[data.illegalType])
               or data.illegalType or '?'
    local msg = ('[SALA] Empresa %s — suspeita de contrabando (%s) na região de %s.'):format(
        data.companyName or '?', label, data.area or '?')

    local players = Framework.GetAllPlayers() or {}
    for _, player in pairs(players) do
        if Framework.GetJob(player).name == 'sasp' then
            TriggerClientEvent('aurp_trucker:client:policeAlert', Framework.GetSource(player),
                { message = msg })
        end
    end
end)

-- =====================================================
-- CARGO THEFT HANDLERS (v14.0.0)
-- =====================================================

-- Jogador entra no caminhão com job ativo → registra plate no CargoTracking
RegisterNetEvent('aurp_trucker:registerTruckPlate', function(plate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return end

    -- Evita re-registro se já existe e é o mesmo job
    local existing = VP_Trucker.CargoByPlate[plate]
    if existing and existing.jobId == activeJob.id then return end

    local gpsEnabled = DB_GetVehicleGps(plate)
    CargoTrackingService.RegisterCargo(plate, activeJob.id, citizenId, activeJob.base_payment, gpsEnabled)
end)

-- Jogador saiu do caminhão com cargo ativo → inicia timer de vulnerabilidade
RegisterNetEvent('aurp_trucker:cargoPlayerLeft', function(plate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo or cargo.citizenId ~= citizenId then return end

    CargoTrackingService.OnPlayerLeft(plate, src)
end)

-- Jogador voltou ao caminhão → cancela timer/roubo
RegisterNetEvent('aurp_trucker:cargoPlayerReturned', function(plate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo or cargo.citizenId ~= citizenId then return end

    CargoTrackingService.OnPlayerReturned(plate)
    -- Remove StateBag de vulnerabilidade via owner's client
    TriggerClientEvent('aurp_trucker:client:cargoClear', src, plate)
end)

-- Ladrão inicia roubo
RegisterNetEvent('aurp_trucker:startCargoTheft', function(truckNetId, thiefNetId, truckPlate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'startCargoTheft') then
        TriggerClientEvent('aurp_trucker:client:theftCancelled', src)
        return
    end

    -- Valida entidades networked
    if not netEntityExists(truckNetId) then return end
    if not netEntityExists(thiefNetId) then return end

    local truckEntity = NetworkGetEntityFromNetworkId(truckNetId)
    local thiefEntity = NetworkGetEntityFromNetworkId(thiefNetId)
    if truckEntity == 0 or thiefEntity == 0 then return end

    -- Validar que o solicitante é de fato o motorista do thiefEntity (fail-closed)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local currentVeh = GetVehiclePedIsIn(ped, false)
    if currentVeh == 0 or currentVeh ~= thiefEntity or GetPedInVehicleSeat(currentVeh, -1) ~= ped then
        TriggerClientEvent('aurp_trucker:client:theftCancelled', src)
        return
    end

    local truckCoords = GetEntityCoords(truckEntity)
    local thiefCoords = GetEntityCoords(thiefEntity)

    -- Valida proximidade server-side
    if #(truckCoords - thiefCoords) > Config.CargoTheft.TheftRange then
        TriggerClientEvent('aurp_trucker:client:theftCancelled', src)
        return
    end

    local ok, reason = CargoTrackingService.StartTheft(truckPlate, citizenId, src, truckCoords)
    if ok then
        TriggerClientEvent('aurp_trucker:client:theftApproved', src)
    else
        TriggerClientEvent('aurp_trucker:notify', src, reason or 'Roubo inválido.', 'error')
    end
end)

-- Ladrão completa o roubo (progress bar terminou)
RegisterNetEvent('aurp_trucker:completeCargoTheft', function(truckPlate, thiefPlate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- v15: rate limit
    if not AntiCheatService.RateLimit(citizenId, 'completeCargoTheft') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Ação inválida.', 'error')
        return
    end

    -- Validar que o jogador ainda está no veículo no banco do motorista e obter placa autoritativa
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local thiefVeh = GetVehiclePedIsIn(ped, false)
    if thiefVeh == 0 or GetPedInVehicleSeat(thiefVeh, -1) ~= ped then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você precisa estar no banco do motorista.', 'error')
        return
    end

    local authoritativePlate = GetVehicleNumberPlateText(thiefVeh):gsub('%s+', '')
    if authoritativePlate == '' then
        TriggerClientEvent('aurp_trucker:notify', src, 'Veículo sem placa válida.', 'error')
        return
    end

    local thiefCoords = GetEntityCoords(thiefVeh)
    local result = CargoTrackingService.CompleteTheft(truckPlate, authoritativePlate, citizenId, thiefCoords)
    if not result then
        TriggerClientEvent('aurp_trucker:notify', src, 'Roubo inválido ou expirado.', 'error')
        return
    end

    -- Informa o destino ao ladrão para navegação
    local destData = nil
    for _, d in ipairs(Config.SecondaryIndustries) do
        if d.id == result.destId then destData = d; break end
    end

    TriggerClientEvent('aurp_trucker:client:stolenJobStarted', src, {
        destCoords  = destData and destData.coords or nil,
        destName    = destData and destData.name or result.destId,
        basePayment = result.basePayment,
    })

    -- Limpar StateBag ct_vulnerable do caminhão roubado para todos os clients
    -- (remove ox_target visível em outros jogadores após roubo bem-sucedido)
    TriggerClientEvent('aurp_trucker:client:cargoClear', -1, truckPlate)
end)

-- Ladrão cancela o roubo (progress bar cancelada)
RegisterNetEvent('aurp_trucker:cancelCargoTheft', function(truckPlate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    CargoTrackingService.CancelTheft(truckPlate, citizenId)
end)

-- =====================================================
-- CONTAINER HANDLER (v20)
-- =====================================================

-- Abandono voluntário: client solicita cancelamento sem pagamento
RegisterNetEvent('aurp_trucker:containerHandler:cancel', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    ContainerHandlerService.Cancel(citizenId)
end)

-- audit C-03: ContainerHandler.OnPlayerDropped foi movido para o handler centralizado (linha ~647)

-- =====================================================
-- LC LOGISTICS: QUICK JOBS & FREIGHT CONTRACTS
-- =====================================================

local ActiveLCContracts = {}
local StartingJobLock    = {}
local LastNotifyTime     = {}

local function StartLCContractForPlayer(src, contractId)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local now = os.time()
    if StartingJobLock[citizenId] or ActiveLCContracts[citizenId] or JobService.GetActiveByPlayer(citizenId) then
        if not LastNotifyTime[citizenId] or (now - LastNotifyTime[citizenId] >= 3) then
            LastNotifyTime[citizenId] = now
            TriggerClientEvent('aurp_trucker:notify', src, 'Você já possui uma entrega ativa!', 'error')
        end
        return
    end

    StartingJobLock[citizenId] = true

    if not contractId then
        StartingJobLock[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Frete Inválido', 'Nenhum frete selecionado.', 'error')
        return
    end

    contractId = tonumber(contractId)
    if not contractId or contractId <= 0 then
        StartingJobLock[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Frete Inválido', 'Identificador de carga inválido.', 'error')
        return
    end

    local availableLoads = (Config.LC_Jobs and Config.LC_Jobs.available_loads) or {}
    local load = availableLoads[contractId]
    if not load then
        StartingJobLock[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Frete Indisponível', 'Este frete não está mais disponível no mercado.', 'error')
        return
    end

    -- Local de entrega autoritativo
    local deliveryLocs = Config.LC_DeliveryLocations or { vector4(1452.67, 6552.02, 14.89, 138.69) }
    if #deliveryLocs == 0 then
        StartingJobLock[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Erro de Rota', 'Nenhum destino de entrega configurado.', 'error')
        return
    end

    local destIndex = ((contractId - 1) % #deliveryLocs) + 1
    local dest = deliveryLocs[destIndex] or deliveryLocs[1]
    if not dest then
        StartingJobLock[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Erro de Rota', 'Destino do frete inacessível.', 'error')
        return
    end

    -- Ponto de origem: Buccaneer Way (Sede Principal)
    local origin = Config.LC_Headquarters and Config.LC_Headquarters.coords or vector3(1208.83, -3115.0, 5.54)
    local rawDist = #(vector3(dest.x, dest.y, dest.z) - origin) / 1000.0
    local dist = tonumber(string.format("%.2f", rawDist)) or 1.0
    if dist <= 0 then dist = 1.0 end

    -- Cálculo autoritativo de pagamento com bônus e taxa da firma (Quick Job)
    local def = load.def or {0,0,0,0}
    local adr = def[1] or 0
    local fragile = def[2] or 0
    local valuable = def[3] or 0
    local illegal = def[4] or 0
    local fast = (contractId % 3 == 0) and 1 or 0

    local contractCheck = {
        distance = dist,
        cargo_type = adr,
        fragile = fragile,
        valuable = valuable,
        fast = fast,
        illegal = illegal
    }

    -- Validação estrita de habilidades requeridas (Fail-Closed)
    if ProgressionService and ProgressionService.CanPlayerAcceptContract then
        local canAccept, reason, detailedReason = ProgressionService.CanPlayerAcceptContract(citizenId, contractCheck)
        if not canAccept then
            StartingJobLock[citizenId] = nil
            local errorMsg = detailedReason or (reason == 'distance' and ('Distância da rota (%.2f km) excede o limite da sua habilidade.'):format(dist) or ('Requisito de habilidade não atendido: ' .. tostring(reason)))
            TriggerClientEvent('aurp_trucker:notify', src, 'Frete Bloqueado', errorMsg, 'error')
            return
        end
    end

    local bonusInfo = (ProgressionService and ProgressionService.CalculateContractBonuses) and ProgressionService.CalculateContractBonuses(citizenId, contractCheck) or { moneyMultiplier = 1.0, expMultiplier = 1.0 }

    local baseRate = 1250 + (valuable * 450) + (fragile * 350) + (adr > 0 and 600 or 0)
    -- Quick Job desconta taxa de aluguel de veículo fornecido pela firma (15%)
    local rentalFeePct = (Config.LC_Jobs and Config.LC_Jobs.truck_rental and Config.LC_Jobs.truck_rental.rental_fee_percent) or 15
    local rawPayment = math.floor(dist * baseRate + 1200)
    local basePayment = math.floor(rawPayment * (1 - (rentalFeePct / 100)))
    local payment = math.floor(basePayment * (bonusInfo.moneyMultiplier or 1.0))

    -- Sorteio de vagas livres de spawn na doca
    local garageSpawns = Config.LC_Headquarters and Config.LC_Headquarters.garage_spawns or { vector4(1250.55, -3162.4, 5.88, 270.00) }
    local trailerSpawns = Config.LC_Headquarters and Config.LC_Headquarters.trailer_spawns or { vector4(1274.21, -3186.43, 5.91, 90.00) }
    local truckSpawn = garageSpawns[((contractId - 1) % #garageSpawns) + 1]
    local trailerSpawn = trailerSpawns[((contractId - 1) % #trailerSpawns) + 1]

    local rentalTrucks = { "hauler", "phantom", "packer", "blacktop", "brickades" }
    local truckModel = rentalTrucks[((contractId - 1) % #rentalTrucks) + 1]

    local jobId = ('lc_%d_%d'):format(os.time(), math.random(1000, 9999))
    MySQL.insert.await([[
        INSERT INTO trucker_jobs (
            id, status, assigned_citizenid, origin_id, dest_id, cargo_item,
            trailer_model, base_payment, distance, expires_at, created_at,
            contract_type, cargo_type, fragile, valuable, fast, illegal
        ) VALUES (?, 'active', ?, 'buccaneer_hq', ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 2 HOUR), NOW(), 0, ?, ?, ?, ?, ?)
    ]], {
        jobId, citizenId, ('dest_%d'):format(destIndex), load.name,
        load.trailer, payment, dist, adr, fragile, valuable, fast, illegal
    })

    ActiveLCContracts[citizenId] = jobId
    StartingJobLock[citizenId] = nil

    local payload = {
        jobId = jobId,
        cargoName = load.name,
        truckModel = truckModel,
        trailerModel = load.trailer,
        truckSpawn = truckSpawn,
        trailerSpawn = trailerSpawn,
        deliveryCoords = dest,
        payment = payment,
        distance = dist,
    }

    TriggerClientEvent('aurp_trucker:client:startLCContract', src, payload)
end

RegisterNetEvent('aurp_trucker:server:startLCContract', function(contractId)
    StartLCContractForPlayer(source, contractId)
end)

RegisterNetEvent('truck_logistics:startContract', function(location, data)
    local contractId = nil
    if type(data) == 'table' then
        contractId = data.id or data.contract_id or data.contractId or data.jobId
    elseif type(data) == 'number' or type(data) == 'string' then
        contractId = data
    elseif type(location) == 'number' or (type(location) == 'string' and tonumber(location)) then
        contractId = location
    end
    StartLCContractForPlayer(source, contractId)
end)

RegisterNetEvent('truck_logistics:makeContract', function(location, data)
    local contractId = nil
    if type(data) == 'table' then
        contractId = data.id or data.contract_id or data.contractId or data.jobId
    elseif type(data) == 'number' or type(data) == 'string' then
        contractId = data
    elseif type(location) == 'number' or (type(location) == 'string' and tonumber(location)) then
        contractId = location
    end
    StartLCContractForPlayer(source, contractId)
end)

RegisterNetEvent('truck_logistics:deliveredCargo', function()
    -- Confirma entrega do frete
end)

local CompletingContractsLock = {}

local function FinalizeLCContract(src, jobId, parkedManually)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    if CompletingContractsLock[citizenId] then return end
    CompletingContractsLock[citizenId] = true

    local row = nil
    if jobId then
        row = MySQL.single.await([[
            SELECT * FROM trucker_jobs WHERE id = ? AND assigned_citizenid = ? AND status = 'active' LIMIT 1
        ]], { jobId, citizenId })
    else
        row = MySQL.single.await([[
            SELECT * FROM trucker_jobs WHERE assigned_citizenid = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1
        ]], { citizenId })
    end

    if not row then
        CompletingContractsLock[citizenId] = nil
        return
    end

    -- Mutação atômica fail-closed: se já foi finalizado concorrentemente, affectedRows será 0
    local affected = MySQL.update.await([[
        UPDATE trucker_jobs SET status = 'completed', completed_at = NOW() WHERE id = ? AND status = 'active'
    ]], { row.id })

    if not affected or affected == 0 then
        CompletingContractsLock[citizenId] = nil
        return
    end

    local contractData = {
        distance = row.distance or 2.5,
        cargo_type = row.cargo_type or 0,
        fragile = row.fragile or 0,
        valuable = row.valuable or 0,
        fast = row.fast or 0,
        illegal = row.illegal or 0,
    }

    local bonuses = (ProgressionService and ProgressionService.CalculateContractBonuses) and ProgressionService.CalculateContractBonuses(citizenId, contractData) or { moneyMultiplier = 1.0, expMultiplier = 1.0, moneyBonusPct = 0, expBonusPct = 0 }
    local payment = row.base_payment or 2500
    local dist = row.distance or 2.5

    if parkedManually then
        payment = math.floor(payment * 1.05)
    end

    Framework.AddMoney(Player, 'bank', payment, 'aurp-trucker-lc-contract')
    DB_AddPlayerStats(citizenId, payment, dist)

    local xpMultiplier = bonuses and bonuses.expMultiplier or 1.0
    local xpResult = ProgressionService.GrantXP(src, citizenId, payment, xpMultiplier, dist)

    ActiveLCContracts[citizenId] = nil
    StartingJobLock[citizenId] = nil

    TriggerClientEvent('aurp_trucker:client:lcContractFinished', src, {
        payment = payment,
        distance = dist,
        parkedManually = parkedManually,
        xpGained = xpResult and xpResult.xpGained or 0,
        newLevel = xpResult and xpResult.newLevel or 1,
        levelsGained = xpResult and xpResult.levelsGained or 0,
        moneyBonusPct = bonuses and bonuses.moneyBonusPct or 0,
        expBonusPct = bonuses and bonuses.expBonusPct or 0,
    })

    SetTimeout(3000, function()
        CompletingContractsLock[citizenId] = nil
    end)
end

RegisterNetEvent('truck_logistics:finishContract', function(engine, body, trailerBody)
    FinalizeLCContract(source, nil, true)
end)

RegisterNetEvent('truck_logistics:buyTruck', function(location, data)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local truckModel = data and (data.truck_name or data.model or data.name)
    if not truckModel then return end
    local ok, res = TruckFleetService.BuyTruck(src, citizenId, truckModel)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Caminhão comprado com sucesso!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res or 'Falha ao comprar caminhão', 'error')
    end
end)

RegisterNetEvent('truck_logistics:sellTruck', function(location, data)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    local truckId = data and (data.truck_id or data.truckId or data.id)
    if not truckId then return end
    local ok, refund = TruckFleetService.SellTruck(src, citizenId, truckId)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, ('Caminhão vendido por $%d!'):format(refund or 0), 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, refund or 'Falha ao vender caminhão', 'error')
    end
end)

RegisterNetEvent('aurp_trucker:server:completeLCContract', function(jobId, parkedManually)
    FinalizeLCContract(source, jobId, parkedManually)
end)

-- =====================================================
-- NUI LC TRUCK LOGISTICS INTEGRATION EVENTS
-- =====================================================

-- Concessionária: Comprar Caminhão
RegisterNetEvent('aurp_trucker:fleet:buyTruck', function(truckModel)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player or not truckModel then return end
    local citizenId = Framework.GetCitizenId(Player)
    local ok, res = TruckFleetService.BuyTruck(src, citizenId, truckModel)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Caminhão comprado com sucesso!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res or 'Falha ao comprar caminhão', 'error')
    end
end)

-- Concessionária: Vender Caminhão
RegisterNetEvent('aurp_trucker:fleet:sellTruck', function(truckId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player or not truckId then return end
    local citizenId = Framework.GetCitizenId(Player)
    local ok, res = TruckFleetService.SellTruck(src, citizenId, tonumber(truckId))
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Caminhão vendido com sucesso!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res or 'Falha ao vender caminhão', 'error')
    end
end)

-- Oficina: Reparo Completo de Caminhão
RegisterNetEvent('aurp_trucker:fleet:repairTruck', function(truckId, part)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player or not truckId then return end
    local citizenId = Framework.GetCitizenId(Player)
    local truck = MySQL.single.await('SELECT * FROM trucker_trucks WHERE truck_id = ? AND user_id = ?', { tonumber(truckId), citizenId })
    if not truck then return end

    local cfg = Config.LC_RepairPrice or { engine = 100, transmission = 100, wheels = 100, body = 100 }
    local cost = math.floor(((1000 - truck.body) / 10 * cfg.body) + ((1000 - truck.engine) / 10 * cfg.engine) + ((1000 - truck.transmission) / 10 * cfg.transmission) + ((1000 - truck.wheels) / 10 * cfg.wheels))
    if cost <= 0 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Caminhão já está em perfeitas condições!', 'info')
        return
    end

    local balance = Framework.GetPlayerMoney(src, 'bank')
    if balance < cost then
        TriggerClientEvent('aurp_trucker:notify', src, 'Saldo bancário insuficiente para o reparo!', 'error')
        return
    end

    Framework.RemovePlayerMoney(src, 'bank', cost, 'Reparo de caminhão')
    MySQL.update.await('UPDATE trucker_trucks SET body = 1000, engine = 1000, transmission = 1000, wheels = 1000 WHERE truck_id = ?', { tonumber(truckId) })
    TriggerClientEvent('aurp_trucker:notify', src, ('Caminhão totalmente reparado por $%s!'):format(cost), 'success')
end)

-- Árvore de Habilidades: Upgrade de Skill
RegisterNetEvent('aurp_trucker:server:upgradeSkill', function(skillType)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player or not skillType then return end
    local citizenId = Framework.GetCitizenId(Player)

    local ok, reason = ProgressionService.UpgradeSkill(citizenId, skillType)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, ('Habilidade [%s] aprimorada!'):format(skillType), 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, reason or 'Não foi possível aprimorar', 'error')
    end
end)

-- Empréstimo: Contratar Plano
RegisterNetEvent('aurp_trucker:loan:takePlan', function(planIndex)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    planIndex = (tonumber(planIndex) or 0) + 1
    local plans = Config.LC_Loans and Config.LC_Loans.plans
    local plan = plans and plans[planIndex]
    if not plan then
        TriggerClientEvent('aurp_trucker:notify', src, 'Plano de empréstimo inválido!', 'error')
        return
    end

    local res = LoanService.Create(src, citizenId, nil, plan.loan_amount)
    if res.success then
        TriggerClientEvent('aurp_trucker:notify', src, ('Empréstimo de $%s concedido!'):format(plan.loan_amount), 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res.reason or 'Falha ao solicitar empréstimo', 'error')
    end
end)

-- Empréstimo: Quitar Empréstimo
RegisterNetEvent('aurp_trucker:loan:payOff', function(loanId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    loanId = tonumber(loanId)
    local loan = DB_GetLoanById(loanId)
    if not loan or loan.citizenid ~= citizenId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Empréstimo não encontrado', 'error')
        return
    end

    local res = LoanService.Pay(src, citizenId, nil, loanId, loan.remaining_balance)
    if res.success then
        TriggerClientEvent('aurp_trucker:notify', src, 'Empréstimo totalmente quitado!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res.reason or 'Falha ao quitar', 'error')
    end
end)

-- RH: Contratar Motorista da Agência
RegisterNetEvent('aurp_trucker:driver:hireAgency', function(driverIndex)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    driverIndex = tonumber(driverIndex) or 1
    local ok, res = NpcDriverService.HireAgencyDriver(src, citizenId, driverIndex)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, ('Motorista %s contratado com sucesso!'):format(res.name), 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res or 'Falha ao contratar motorista', 'error')
    end
end)

-- RH: Demitir Motorista
RegisterNetEvent('aurp_trucker:driver:fireHired', function(driverId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    driverId = tonumber(driverId)
    local ok = NpcDriverService.FireHiredDriver(src, citizenId, driverId)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Motorista dispensado.', 'info')
    else
        TriggerClientEvent('aurp_trucker:notify', src, 'Falha ao dispensar motorista', 'error')
    end
end)

-- RH: Atribuir Caminhão a Motorista
RegisterNetEvent('aurp_trucker:driver:setTruck', function(driverId, truckId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    driverId = tonumber(driverId)
    truckId = tonumber(truckId)
    local ok, msg = NpcDriverService.AssignTruck(src, citizenId, driverId, truckId)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Atribuição de caminhão atualizada!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, msg or 'Falha ao atribuir caminhão', 'error')
    end
end)

-- Banco: Depósito
RegisterNetEvent('aurp_trucker:bank:deposit', function(amount)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local company = CompanyService.GetByMember(citizenId)
    if not company then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você não possui empresa registrada para depósito.', 'error')
        return
    end

    local ok, err = CompanyService.Deposit(company.id, src, amount)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, ('Depositado $%s na conta da empresa!'):format(amount), 'success')
        TriggerClientEvent('aurp_trucker:client:companyUpdated', src, CompanyService.Get(company.id))
    else
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Falha ao realizar depósito.', 'error')
    end
end)

-- Banco: Saque
RegisterNetEvent('aurp_trucker:bank:withdraw', function(amount)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local company = CompanyService.GetByMember(citizenId)
    if not company then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você não possui empresa registrada.', 'error')
        return
    end

    local ok, err = CompanyService.Withdraw(company.id, src, citizenId, amount)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, ('Sacado $%s da conta da empresa!'):format(amount), 'success')
        TriggerClientEvent('aurp_trucker:client:companyUpdated', src, CompanyService.Get(company.id))
    else
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Saldo da empresa insuficiente ou sem permissão!', 'error')
    end
end)

-- Party: Criar Grupo
RegisterNetEvent('aurp_trucker:party:create', function()
    local src = source
    local partyId, err = PartyService.Create(src)
    if partyId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Grupo de transporte criado!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Falha ao criar grupo', 'error')
    end
end)

-- Party: Sair do Grupo
RegisterNetEvent('aurp_trucker:party:leave', function()
    local src = source
    PartyService.Leave(src)
    TriggerClientEvent('aurp_trucker:notify', src, 'Você saiu do grupo.', 'info')
end)
