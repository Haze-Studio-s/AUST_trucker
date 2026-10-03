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
-- HELPERS DE VALIDAÇÃO COMPARTILHADOS
-- =====================================================

-- Inteiro positivo finito e <= max (rejeita NaN/inf/não-número/<=0). Retorna nil se inválido.
local function posInt(x, max)
    if type(x) ~= 'number' then x = tonumber(x) end
    if type(x) ~= 'number' or x ~= x or x == math.huge or x == -math.huge then return nil end
    x = math.floor(x)
    if x <= 0 then return nil end
    if x > (max or 10000000) then return nil end
    return x
end

-- Placa sem espaços (mesma convenção do CargoTrackingService / client: gsub('%s+', ''))
local function stripPlate(p)
    if type(p) ~= 'string' then return nil end
    local s2 = p:gsub('%s+', '')
    if s2 == '' or #s2 > 12 then return nil end
    return s2
end

-- Placa normalizada para armazenar (trim + upper, <= 12 chars, só alfanumérico/espaço)
local function normPlate(p)
    if type(p) ~= 'string' then return nil end
    local t = p:gsub('^%s+', ''):gsub('%s+$', '')
    t = t:upper()
    if t == '' or #t > 12 or t:find('[^%w ]') then return nil end
    return t
end

-- Veículo em que o jogador é motorista (nil se nenhum) + placa lida no servidor (sem espaços)
local function getDriverVehicle(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    local plate = stripPlate(GetVehicleNumberPlateText(veh) or '')
    if not plate then return nil end
    return veh, plate
end

-- Rate limit local por chave (ms). Retorna true se liberado.
local _rl = {}
local function rateLimit(key, ms)
    local now = GetGameTimer()
    local last = _rl[key]
    if last and (now - last) < ms then return false end
    _rl[key] = now
    return true
end
AddEventHandler('playerDropped', function()
    local suffix = ':' .. tostring(source)
    for k in pairs(_rl) do
        if type(k) == 'string' and k:sub(-#suffix) == suffix then _rl[k] = nil end
    end
end)

-- Aguarda entidade existir com timeout (padrão 5s). Retorna true/false.
local function waitEntity(ent, timeoutMs)
    local t0 = GetGameTimer()
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and (GetGameTimer() - t0 < (timeoutMs or 5000)) do
        Wait(10)
    end
    return ent ~= nil and ent ~= 0 and DoesEntityExist(ent)
end

-- Estado dos contratos LC (declarado aqui para ser visível aos handlers de entidades acima)
local ActiveLCContracts    = {}
local ActiveLCContractData = {}
local StartingJobLock      = {}
local LastNotifyTime       = {}

-- Valida um netId vindo do cliente. expectType: 2 = veículo, 3 = objeto.
-- Retorna entity, netId, verified (verified = batida com entidade registrada pelo servidor).
local function validateJobEntity(src, citizenId, rawNetId, expectType)
    local netId = tonumber(rawNetId)
    if not netId or netId ~= netId or netId <= 0 or netId > 65535 or netId % 1 ~= 0 then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if GetEntityType(ent) ~= expectType then return nil end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    if #(GetEntityCoords(ped) - GetEntityCoords(ent)) > 250.0 then return nil end

    local verified = false
    -- 1) Entidade spawnada pelo servidor para o lobby Polarix do jogador (main.lua)
    if PolarixOwnsEntity then
        local hasLobby, matches = PolarixOwnsEntity(citizenId, ent)
        if hasLobby then
            if not matches then return nil end
            verified = true
        end
    end
    -- 2) Caminhão spawnado pelo servidor para contrato LC
    if not verified then
        local jid = ActiveLCContracts[citizenId]
        local info = jid and ActiveLCContractData[jid]
        if info and info.truckEntity and info.truckEntity == ent then verified = true end
    end
    -- 3) Entidade criada pelo próprio client: exige que o jogador seja o dono de rede
    if not verified then
        local okOwner, owner = pcall(NetworkGetEntityOwner, ent)
        if not okOwner or owner ~= src then return nil end
    end
    return ent, netId, verified
end

-- Alguém (que não o dono) está dentro do veículo?
local function vehicleHasOtherPlayer(veh, ownerSrc)
    if GetEntityType(veh) ~= 2 then return false end
    for seat = -1, 4 do
        local pedIn = GetPedInVehicleSeat(veh, seat)
        if pedIn and pedIn ~= 0 and DoesEntityExist(pedIn) and IsPedAPlayer(pedIn) then
            if not ownerSrc or pedIn ~= GetPlayerPed(ownerSrc) then return true end
        end
    end
    return false
end

-- Remove com segurança uma entidade registrada em PlayerJobEntities:
-- só apaga se foi validada no registro (mesmo modelo) e não há outro jogador dentro.
local function safeDeleteJobEntity(jobEnts, netId, ownerSrc)
    netId = tonumber(netId)
    if not netId or not jobEnts then return end
    local verified = jobEnts.verified and jobEnts.verified[netId]
    local trustedRental = (netId == jobEnts.truckNetId and jobEnts.rentalPlate ~= nil)
    if not verified and not trustedRental then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    if type(verified) == 'number' and GetEntityModel(ent) ~= verified then return end
    if vehicleHasOtherPlayer(ent, ownerSrc) then return end
    DeleteEntity(ent)
end

local function safeDeleteAllJobEntities(jobEnts, ownerSrc)
    if not jobEnts then return end
    safeDeleteJobEntity(jobEnts, jobEnts.truckNetId, ownerSrc)
    safeDeleteJobEntity(jobEnts, jobEnts.trailerNetId, ownerSrc)
    safeDeleteJobEntity(jobEnts, jobEnts.forkliftNetId, ownerSrc)
    if type(jobEnts.palletNetIds) == 'table' then
        for _, pNet in ipairs(jobEnts.palletNetIds) do
            safeDeleteJobEntity(jobEnts, pNet, ownerSrc)
        end
    end
end

-- =====================================================
-- JOB HANDLERS
-- =====================================================

RegisterNetEvent('aurp_trucker:acceptJob', function(jobId)
    local src = source
    if Config.Debug then print(("^2[AUST_Trucker Server] aurp_trucker:acceptJob received from src %s with jobId: %s^7"):format(tostring(src), tostring(jobId))) end
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- Crude oil order: just set GPS to well, no formal job entry
    if tostring(jobId):sub(1, 6) == 'crude_' then
        -- Rate limit (evita spam do GPS/consultas ao AUST_oilfield)
        if not rateLimit('crudeGPS:' .. src, 2000) then return end
        -- Still block if player has an active regular job
        if JobService.GetActiveByPlayer(citizenId) then
            TriggerClientEvent('aurp_trucker:notify', src, 'Você já tem um job ativo', 'error')
            return
        end

        -- Permit: transport_commercial obrigatória para Modo B
        -- Fail-closed: se o resource governo está iniciado e a consulta falha, NÃO libera.
        -- Só mantém liberado quando o resource não existe/não está rodando neste servidor.
        local hasPermit = true
        local govState = GetResourceState and GetResourceState('AUST_governo') or 'missing'
        if govState == 'started' or govState == 'starting' then
            local okPermit, permitRes = pcall(function()
                return exports['AUST_governo']:HasPermit(citizenId, 'transport_commercial')
            end)
            hasPermit = (okPermit and permitRes == true)
        end
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

    -- Limpeza estrita das entidades do trabalho: só apaga entidades validadas no registro
    -- (servidor spawnou / jogador era o dono de rede) — nunca netIds arbitrários do cliente
    if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
        safeDeleteAllJobEntities(VP_Trucker.PlayerJobEntities[citizenId], src)
        VP_Trucker.PlayerJobEntities[citizenId] = nil
    end

    TriggerClientEvent('aurp_trucker:client:jobAbandoned', src)
end)

-- Registra netIds de caminhão, trailer, empilhadeira e paletes para tracking e garbage collection
RegisterNetEvent('aurp_trucker:server:registerJobEntities', function(truckNetId, trailerNetId, forkliftNetId, palletNetIds)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- Cancela qualquer timer de limpeza pendente caso o jogador tenha acabado de reconectar
    JobService.PendingCleanups = JobService.PendingCleanups or {}
    if JobService.PendingCleanups[citizenId] then
        JobService.PendingCleanups[citizenId].cancelled = true
        JobService.PendingCleanups[citizenId] = nil
        if Config.Debug then print(("^2[AUST_Trucker GC] Grace period cancelado para %s (jogador reconectou com sucesso).^7"):format(tostring(citizenId))) end
    end

    VP_Trucker.PlayerJobEntities = VP_Trucker.PlayerJobEntities or {}
    VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}
    local jobEnts = VP_Trucker.PlayerJobEntities[citizenId]
    jobEnts.verified = jobEnts.verified or {}

    -- Valida cada netId do cliente (existe, tipo esperado, perto do jogador, e se o servidor
    -- spawnou, bate com a entidade registrada). Entidades inválidas são ignoradas por completo:
    -- sem registro, sem LockEntityNetworkOwner e sem GiveKeys.
    local function accept(rawNetId, expectType)
        local ent, netId, verified = validateJobEntity(src, citizenId, rawNetId, expectType)
        if not ent then return nil end
        jobEnts.verified[netId] = GetEntityModel(ent)
        if LockEntityNetworkOwner then LockEntityNetworkOwner(ent, src) end
        return ent, netId
    end

    if truckNetId then
        -- Aluguel: RegisterNetId faz a própria validação (placa/modelo/spawn); só confia se retornou sucesso
        local rentalOk = false
        if TruckRentalService then
            rentalOk = TruckRentalService.RegisterNetId(citizenId, truckNetId) == true
            if not rentalOk and TruckRentalService.GetRental then
                local r = TruckRentalService.GetRental(citizenId)
                rentalOk = (r and r.netId ~= nil and r.netId == tonumber(truckNetId)) or false
            end
        end
        local truckEnt, tNet = accept(truckNetId, 2)
        if truckEnt then
            jobEnts.truckNetId = tNet
            pcall(function()
                if exports['qbx_vehiclekeys'] then
                    exports['qbx_vehiclekeys']:GiveKeys(src, truckEnt)
                end
            end)
        elseif rentalOk then
            local e = NetworkGetEntityFromNetworkId(tonumber(truckNetId))
            if e and e ~= 0 and DoesEntityExist(e) then
                jobEnts.truckNetId = tonumber(truckNetId)
                if LockEntityNetworkOwner then LockEntityNetworkOwner(e, src) end
                pcall(function()
                    if exports['qbx_vehiclekeys'] then
                        exports['qbx_vehiclekeys']:GiveKeys(src, e)
                    end
                end)
            end
        end
    end
    if trailerNetId then
        local _, tNet = accept(trailerNetId, 2)
        if tNet then jobEnts.trailerNetId = tNet end
    end
    if forkliftNetId then
        local _, fNet = accept(forkliftNetId, 2)
        if fNet then jobEnts.forkliftNetId = fNet end
    end
    if type(palletNetIds) == 'table' then
        local accepted = {}
        for i, pNet in ipairs(palletNetIds) do
            if i > 16 then break end -- limite de crescimento
            local _, pId = accept(pNet, 3)
            if pId then accepted[#accepted + 1] = pId end
        end
        jobEnts.palletNetIds = accepted
    end
end)

-- ============================================================
-- GARBAGE COLLECTION: GRACE PERIOD DE 3 MINUTOS (PILAR 3)
-- ============================================================
AddEventHandler('playerDropped', function(reason)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    if not citizenId then return end

    if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
        local jobEnts = VP_Trucker.PlayerJobEntities[citizenId]
        if Config.Debug then print(("^3[AUST_Trucker GC] Jogador %s desconectou (%s). Iniciando Grace Period de 3 minutos para limpeza de entidades.^7"):format(tostring(citizenId), tostring(reason))) end

        JobService.PendingCleanups = JobService.PendingCleanups or {}
        if JobService.PendingCleanups[citizenId] then
            JobService.PendingCleanups[citizenId].cancelled = true
        end

        local cleanupRef = { cancelled = false, entities = jobEnts }
        JobService.PendingCleanups[citizenId] = cleanupRef

        SetTimeout(180000, function()
            if cleanupRef.cancelled then
                    if Config.Debug then print(("^2[AUST_Trucker GC] Limpeza cancelada para %s: jogador retornou a tempo.^7"):format(tostring(citizenId))) end
                return
            end

            if Config.Debug then print(("^1[AUST_Trucker GC] Grace period expirado (3 min) para %s. Deletando entidades órfãs no servidor.^7"):format(tostring(citizenId))) end
            -- Apenas entidades validadas no registro (o dono já desconectou: ownerSrc nil)
            safeDeleteAllJobEntities(jobEnts, nil)

            VP_Trucker.PlayerJobEntities[citizenId] = nil
            JobService.PendingCleanups[citizenId] = nil
            JobService.Abandon(citizenId)
        end)
    end
end)

RegisterNetEvent('aurp_trucker:rental:registerNetId', function(netId)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    if not (netId and tonumber(netId)) or not TruckRentalService then return end
    if not rateLimit('rentalNet:' .. src, 1000) then return end

    -- Só entrega chaves se o serviço de aluguel aceitou o netId (placa/modelo/posição conferidos)
    local registered = TruckRentalService.RegisterNetId(citizenId, netId)
    if registered ~= true then return end

    local veh = NetworkGetEntityFromNetworkId(tonumber(netId))
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        pcall(function()
            if exports['qbx_vehiclekeys'] then
                exports['qbx_vehiclekeys']:GiveKeys(src, veh)
            end
        end)
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
        -- Só caminhão/trailer validados no registro (nunca netIds arbitrários)
        safeDeleteJobEntity(jobEnts, jobEnts.truckNetId, src)
        safeDeleteJobEntity(jobEnts, jobEnts.trailerNetId, src)
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
    if type(targetCitizenId) ~= 'string' or targetCitizenId == '' or #targetCitizenId > 50 then return end
    -- Não permite expulsar a si mesmo nem o owner da empresa
    if targetCitizenId == citizenId or targetCitizenId == company.owner_citizenid then
        TriggerClientEvent('aurp_trucker:notify', src, 'Não é possível expulsar o dono da empresa', 'error')
        return
    end
    -- S-01: Verificar que target pertence à MESMA empresa
    local targetMember = DB_GetMember(targetCitizenId)
    if not targetMember or targetMember.company_id ~= company.id then
        TriggerClientEvent('aurp_trucker:notify', src, 'Membro não pertence à sua empresa', 'error')
        return
    end
    if targetMember.role == 'owner' then
        TriggerClientEvent('aurp_trucker:notify', src, 'Não é possível expulsar o dono da empresa', 'error')
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
    -- #4: Validar amount (previne exploit com valores negativos/zero/NaN/inf)
    amount = posInt(amount, 10000000)
    if not amount then return end

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
    -- #5: Validar amount (previne exploit com valores negativos/zero/NaN/inf)
    amount = posInt(amount, 10000000)
    if not amount then return end

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
    if not rateLimit('registerVehicle:' .. src, 1500) then return end

    -- Placa: string normalizada (<= 12 chars) e o jogador precisa estar em/perto desse veículo
    plate = normPlate(plate)
    if not plate then
        TriggerClientEvent('aurp_trucker:notify', src, 'Placa inválida', 'error')
        return
    end
    if type(model) ~= 'string' or #model == 0 or #model > 32 or model:find('[^%w_%-%s]') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Modelo inválido', 'error')
        return
    end
    local function samePlate(a, b) return a and b and a:gsub('%s+', ''):upper() == b:gsub('%s+', ''):upper() end
    local found = false
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local cur = GetVehiclePedIsIn(ped, false)
        if cur and cur ~= 0 and DoesEntityExist(cur) and samePlate(GetVehicleNumberPlateText(cur), plate) then
            found = true
        elseif GetAllVehicles then
            local pc = GetEntityCoords(ped)
            for _, v in ipairs(GetAllVehicles()) do
                if DoesEntityExist(v) and #(GetEntityCoords(v) - pc) <= 20.0
                    and samePlate(GetVehicleNumberPlateText(v), plate) then
                    found = true
                    break
                end
            end
        end
    end
    if not found then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você precisa estar no veículo para registrá-lo', 'error')
        return
    end
    -- Limita crescimento da tabela de veículos da empresa
    local existingVehicles = DB_GetVehicles and DB_GetVehicles(company.id)
    if existingVehicles and #existingVehicles >= 100 then
        TriggerClientEvent('aurp_trucker:notify', src, 'Limite de veículos da empresa atingido', 'error')
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

-- Valida indústria/item/proximidade: item precisa existir na config da indústria (produção p/ compra,
-- consumo p/ venda) e o jogador precisa estar no raio da indústria. Retorna true ou false+motivo.
local function validateIndustryTrade(src, industryId, item, isBuy)
    if type(industryId) ~= 'string' or type(item) ~= 'string' or #item > 64 or #industryId > 64 then
        return false, 'Dados inválidos'
    end
    local ind = Config.Industries and Config.Industries[industryId]
    if not ind then return false, 'Indústria não encontrada' end
    local allowed = false
    if isBuy then
        allowed = ind.production and ind.production.item == item
    else
        for _, c in ipairs(ind.consumption or {}) do
            if c.item == item then allowed = true break end
        end
    end
    if not allowed then return false, 'Produto não disponível nesta indústria' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'Jogador inválido' end
    if ind.coords and #(GetEntityCoords(ped) - vector3(ind.coords.x, ind.coords.y, ind.coords.z)) > ((ind.radius or 15.0) + 5.0) then
        return false, 'Muito longe da indústria'
    end
    return true
end

RegisterNetEvent('aurp_trucker:buyFromIndustry', function(industryId, item, qty)
    local src = source
    -- H-04: Sanitizar qty — previne exploit de qty negativa/zero/overflow/NaN
    qty = posInt(qty, 500)
    if not qty then return end
    if not rateLimit('industryTrade:' .. src, 750) then return end
    local valid, why = validateIndustryTrade(src, industryId, item, true)
    if not valid then
        TriggerClientEvent('aurp_trucker:notify', src, why or 'Erro na compra', 'error')
        return
    end
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
    qty = posInt(qty, 500)
    if not qty then return end
    if not rateLimit('industryTrade:' .. src, 750) then return end
    local valid, why = validateIndustryTrade(src, industryId, item, false)
    if not valid then
        TriggerClientEvent('aurp_trucker:notify', src, why or 'Erro na venda', 'error')
        return
    end
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
    if TruckRentalService and TruckRentalService.OnPlayerLoaded then
        TruckRentalService.OnPlayerLoaded(src, citizenId) -- estorno pendente da caução
    end
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
    amount = posInt(amount, 100000000)
    if not amount then return end
    local src       = source
    local Player    = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    -- Normalizar plate (6A)
    vehiclePlate = type(vehiclePlate) == 'string' and #vehiclePlate <= 12 and vehiclePlate:upper() or nil

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
        -- Só aceita se for um veículo do modelo de empilhadeira, perto do jogador e criado por ele
        local ent, validNet = validateJobEntity(src, citizenId, netId, 2)
        local fkModel = Config.Forklift and Config.Forklift.ForkliftModel
        if ent and fkModel and GetEntityModel(ent) == joaat(fkModel) then
            rental.forkliftNetId = validNet
        end
    end
end)

-- Modelos de palete aceitos (Config.Forklift.PalletModel + pools)
local function isAllowedPalletModel(hash)
    local f = Config.Forklift or {}
    if f.PalletModel and joaat(f.PalletModel) == hash then return true end
    if type(f.PalletModels) == 'table' then
        for _, pool in pairs(f.PalletModels) do
            if type(pool) == 'table' then
                for _, m in ipairs(pool) do
                    if type(m) == 'string' and joaat(m) == hash then return true end
                end
            elseif type(pool) == 'string' and joaat(pool) == hash then
                return true
            end
        end
    end
    return false
end

RegisterNetEvent('aurp_trucker:palletLoaded', function(netId, locationId)
    local src = source

    -- Rate limit (um palete a cada 400ms no máximo)
    if not rateLimit('palletLoaded:' .. src, 400) then return end

    -- Validar existência da entidade na rede
    netId = tonumber(netId)
    if not netId or not netEntityExists(netId) then return end
    local obj = NetworkGetEntityFromNetworkId(netId)

    -- H-07: Confirmar que é um objeto (type 3), não um ped ou veículo
    if GetEntityType(obj) ~= 3 then return end

    -- Modelo precisa ser de palete configurado (client não pode mandar objeto qualquer)
    if not isAllowedPalletModel(GetEntityModel(obj)) then return end

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

    -- Não conta além do esperado
    if rental.loaded >= (rental.expected or 0) then return end

    -- Proximidade: jogador perto do palete e perto do local do aluguel
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local pCoords = GetEntityCoords(ped)
    if #(pCoords - GetEntityCoords(obj)) > 40.0 then return end
    local locCoords = nil
    if rental.mode == 'tradepoint' and Config.Forklift and Config.Forklift.TradePoints then
        for _, tp in ipairs(Config.Forklift.TradePoints) do
            if tp.id == rental.locationId then locCoords = tp.coords break end
        end
    elseif Config.Industries and Config.Industries[rental.locationId] then
        locCoords = Config.Industries[rental.locationId].coords
    end
    if locCoords and #(pCoords - vector3(locCoords.x, locCoords.y, locCoords.z)) > 150.0 then return end

    -- Seguro deletar agora
    DeleteEntity(obj)

    rental.loaded = rental.loaded + 1

    -- Notificar client se todos os pallets foram carregados
    if rental.loaded >= rental.expected then
        TriggerClientEvent('aurp_trucker:client:allPalletsLoaded', src, rental.locationId)
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
            -- Só entidades validadas no registro; o dono já saiu (ownerSrc nil)
            safeDeleteJobEntity(jobEnts, jobEnts.truckNetId, nil)
            safeDeleteJobEntity(jobEnts, jobEnts.trailerNetId, nil)
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

-- Claim em memória: duas apreensões simultâneas da mesma placa não multam duas vezes
local SeizingPlates = {}

-- Localiza o alvo de apreensão por variações da placa (client envia a placa como no broadcast)
local function findIllegalTarget(plate)
    local targets = VP_Trucker.IllegalTargets or {}
    if targets[plate] then return plate, targets[plate] end
    local stripped = stripPlate(plate)
    if stripped then
        for key, t in pairs(targets) do
            if type(key) == 'string' and key:gsub('%s+', ''):upper() == stripped:upper() then
                return key, t
            end
        end
    end
    return nil
end

-- Cop: lacra a carga de um caminhão ilegal via ox_target
RegisterNetEvent('aurp_trucker:seizeIllegalCargo', function(plate)
    local src = source
    if type(plate) ~= 'string' or #plate > 12 or plate == '' then return end
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local jobName = Framework.GetJob(Player).name
    if jobName ~= 'police' and jobName ~= 'sasp' then return end
    if SeizingPlates[stripPlate(plate) or plate] then return end

    -- C-15: Validação de proximidade server-side (ox_target tem range client-side,
    -- mas um cliente malicioso pode disparar o evento à distância arbitrária)
    local copPed = GetPlayerPed(src)
    if not copPed or copPed == 0 or not DoesEntityExist(copPed) then return end
    local copCoords = GetEntityCoords(copPed)

    local key, target = findIllegalTarget(plate)

    -- Placa nunca registrada pelo client: se há motorista com job ilegal ativo dirigindo
    -- um veículo com essa placa (lida no servidor), registra o alvo agora
    if not target and IllegalService then
        local stripped = stripPlate(plate)
        if stripped then
            for _, pid in ipairs(GetPlayers()) do
                local dSrc = tonumber(pid)
                local dPed = dSrc and GetPlayerPed(dSrc)
                if dSrc and dSrc ~= src and dPed and dPed ~= 0 and DoesEntityExist(dPed) then
                    local dVeh = GetVehiclePedIsIn(dPed, false)
                    if dVeh and dVeh ~= 0 and DoesEntityExist(dVeh) and GetPedInVehicleSeat(dVeh, -1) == dPed
                        and (GetVehicleNumberPlateText(dVeh) or ''):gsub('%s+', ''):upper() == stripped:upper() then
                        local dPlayer = Framework.GetPlayer(dSrc)
                        local dCid = dPlayer and Framework.GetCitizenId(dPlayer)
                        local dJob = dCid and DB_GetActiveJobByPlayer(dCid)
                        if dJob and dJob.illegal_type then
                            IllegalService.RegisterSeizureTarget(dSrc, dJob.id, plate, dJob.illegal_type)
                            key, target = findIllegalTarget(plate)
                        end
                        break
                    end
                end
            end
        end
    end
    if not target then
        TriggerClientEvent('aurp_trucker:notify', src, 'Carga não encontrada.', 'error')
        return
    end

    local dPed = target.src and GetPlayerPed(target.src)
    if not dPed or dPed == 0 or not DoesEntityExist(dPed) then return end
    if #(copCoords - GetEntityCoords(dPed)) > Config.IllegalJobs.SeizeRange then
        TriggerClientEvent('aurp_trucker:notify', src, 'Muito longe do veículo', 'error')
        return
    end

    -- CLAIM: trava a placa até a apreensão terminar (Seize cede a thread em chamadas ao DB)
    local lockKey = stripPlate(plate) or plate
    SeizingPlates[lockKey] = true
    local okSeize, errSeize = pcall(function()
        if IllegalService then
            IllegalService.Seize(src, key or plate)
        end
    end)
    SeizingPlates[lockKey] = nil
    if not okSeize and Config.Debug then
        print(('[AUST_Trucker] Erro em IllegalService.Seize: %s'):format(tostring(errSeize)))
    end
end)

-- Motorista entra no caminhão com job ilegal ativo — registra placa para apreensão
RegisterNetEvent('aurp_trucker:illegalRegisterPlate', function(plate)
    local src = source
    if type(plate) ~= 'string' or #plate > 12 or plate == '' then return end
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local cid = Framework.GetCitizenId(Player)
    if not rateLimit('illegalRegPlate:' .. src, 1500) then return end

    -- A placa precisa ser a do veículo que o jogador dirige (lida no servidor)
    local veh, serverPlate = getDriverVehicle(src)
    if not veh or serverPlate:upper() ~= (stripPlate(plate) or ''):upper() then return end

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

    if not rateLimit('regTruckPlate:' .. src, 1500) then return end

    -- Placa autoritativa: lida do veículo em que o jogador é motorista (servidor).
    -- A placa enviada pelo client só é aceita se bater com a da entidade.
    local _, serverPlate = getDriverVehicle(src)
    if not serverPlate then return end
    local clientPlate = stripPlate(plate)
    if not clientPlate or clientPlate:upper() ~= serverPlate:upper() then return end
    plate = serverPlate

    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return end

    -- Evita re-registro se já existe e é o mesmo job
    local existing = VP_Trucker.CargoByPlate[plate]
    if existing and existing.jobId == activeJob.id then return end

    -- Limita crescimento: um job = uma placa de carga. Remove registro anterior do mesmo job
    -- (não mexe em cargas roubadas / com roubo em andamento)
    for oldPlate, cargo in pairs(VP_Trucker.CargoByPlate) do
        if oldPlate ~= plate and cargo.citizenId == citizenId and cargo.jobId == activeJob.id
            and not cargo.isStolen and not cargo.theftBy then
            CargoTrackingService.RemoveCargo(oldPlate)
        end
    end

    local gpsEnabled = DB_GetVehicleGps(plate)
    CargoTrackingService.RegisterCargo(plate, activeJob.id, citizenId, activeJob.base_payment, gpsEnabled)
end)

-- Jogador saiu do caminhão com cargo ativo → inicia timer de vulnerabilidade
RegisterNetEvent('aurp_trucker:cargoPlayerLeft', function(plate)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    if type(plate) ~= 'string' then return end
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

    if type(plate) ~= 'string' then return end
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
    truckNetId = tonumber(truckNetId)
    thiefNetId = tonumber(thiefNetId)
    if not truckNetId or not thiefNetId then return end
    if not netEntityExists(truckNetId) then return end
    if not netEntityExists(thiefNetId) then return end

    local truckEntity = NetworkGetEntityFromNetworkId(truckNetId)
    local thiefEntity = NetworkGetEntityFromNetworkId(thiefNetId)
    if truckEntity == 0 or thiefEntity == 0 or truckEntity == thiefEntity then return end
    if GetEntityType(truckEntity) ~= 2 then return end

    -- Placa do caminhão alvo derivada da entidade no servidor; placa do client precisa bater
    local derivedPlate = stripPlate(GetVehicleNumberPlateText(truckEntity) or '')
    if not derivedPlate then return end
    local clientTruckPlate = stripPlate(truckPlate)
    if clientTruckPlate and clientTruckPlate:upper() ~= derivedPlate:upper() then
        TriggerClientEvent('aurp_trucker:client:theftCancelled', src)
        return
    end
    truckPlate = derivedPlate

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

    local authoritativePlate = (GetVehicleNumberPlateText(thiefVeh) or ''):gsub('%s+', '')
    if authoritativePlate == '' then
        TriggerClientEvent('aurp_trucker:notify', src, 'Veículo sem placa válida.', 'error')
        return
    end

    -- truckPlate precisa ser uma placa válida e o roubo precisa ter sido iniciado por este jogador
    truckPlate = stripPlate(truckPlate)
    if not truckPlate then return end
    local pendingCargo = VP_Trucker.CargoByPlate[truckPlate]
    if not pendingCargo or pendingCargo.theftBy ~= citizenId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Roubo inválido ou expirado.', 'error')
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
    truckPlate = stripPlate(truckPlate)
    if not truckPlate then return end
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

-- ID único de contrato LC (nunca colide com contrato ativo nem com chave existente no DB)
local LCSeq = 0
local function newLCJobId(prefix)
    local id
    repeat
        LCSeq = LCSeq + 1
        id = ('%s_%d_%d_%d'):format(prefix, os.time(), LCSeq, math.random(100, 999))
    until not ActiveLCContractData[id]
    return id
end

-- O jogador possui ao menos um caminhão próprio? (fail-closed: sem serviço = não possui)
local function playerOwnsTruck(citizenId)
    if not (TruckFleetService and TruckFleetService.GetPlayerTrucks) then return false end
    local trucks = TruckFleetService.GetPlayerTrucks(citizenId)
    return trucks ~= nil and #trucks > 0
end

local function StartLCContractForPlayer(src, contractId, contractTypeOverride)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)
    -- Rate limit de início de contrato (spawn de caminhão/chaves)
    if not rateLimit('lcStart:' .. src, 3000) then return end
    if Config.Debug then
        print(("^2[AUST_Trucker Server] StartLCContractForPlayer: src=%s, citizenId=%s, contractId=%s, typeOverride=%s^7"):format(
            tostring(src), tostring(citizenId), tostring(contractId), tostring(contractTypeOverride)
        ))
    end

    local now = os.time()
    if StartingJobLock[citizenId] or ActiveLCContracts[citizenId] or JobService.GetActiveByPlayer(citizenId) then
        if Config.Debug then
            print(("^3[AUST_Trucker Server] Player %s BLOCKED: Already has active contract (ActiveLC: %s, JobService: %s, Lock: %s)^7"):format(
                tostring(citizenId), tostring(ActiveLCContracts[citizenId]), tostring(JobService.GetActiveByPlayer(citizenId) ~= nil), tostring(StartingJobLock[citizenId])
            ))
        end
        if not LastNotifyTime[citizenId] or (now - LastNotifyTime[citizenId] >= 3) then
            LastNotifyTime[citizenId] = now
            TriggerClientEvent('aurp_trucker:notify', src, 'Você já possui uma entrega ativa! Conclua-a ou digite /clearjob.', 'error')
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

    -- Determinar se é Trabalho Rápido (0) ou Caminhão Próprio (1)
    -- O tipo NÃO é escolhido livremente pelo client: tipo 1 só vale se o jogador possui caminhão;
    -- sem override válido, é derivado do id do contrato.
    local isQuickJob = true
    local ownsTruck = playerOwnsTruck(citizenId)
    local override = tonumber(contractTypeOverride)
    if override == 1 then
        isQuickJob = not ownsTruck
        if isQuickJob then
            StartingJobLock[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Caminhão Próprio Requerido', 'Você precisa adquirir um caminhão próprio na concessionária para aceitar este frete!', 'error')
            return
        end
    elseif override == 0 then
        isQuickJob = true
    else
        isQuickJob = (contractId % 2 ~= 0)
        if not isQuickJob and not ownsTruck then isQuickJob = true end
    end
    local contractType = isQuickJob and 0 or 1

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
    local rawPayment = math.floor(dist * baseRate + 1200)

    -- Quick Job desconta taxa de aluguel de veículo fornecido pela firma (15%), enquanto Caminhão Próprio recebe 100% integral
    local rentalFeePct = isQuickJob and ((Config.LC_Jobs and Config.LC_Jobs.truck_rental and Config.LC_Jobs.truck_rental.rental_fee_percent) or 15) or 0
    local basePayment = math.floor(rawPayment * (1 - (rentalFeePct / 100)))
    local payment = math.floor(basePayment * (bonusInfo.moneyMultiplier or 1.0))

    -- Sorteio de vagas livres de spawn na doca
    local garageSpawns = Config.LC_Headquarters and Config.LC_Headquarters.garage_spawns or { vector4(1250.55, -3162.4, 5.88, 270.00) }
    local trailerSpawns = Config.LC_Headquarters and Config.LC_Headquarters.trailer_spawns or { vector4(1274.21, -3186.43, 5.91, 90.00) }
    local truckSpawn = garageSpawns[((contractId - 1) % #garageSpawns) + 1]
    local trailerSpawn = trailerSpawns[((contractId - 1) % #trailerSpawns) + 1]

    local rentalTrucks = { "hauler", "phantom", "packer", "hauler2", "brickades" }
    local truckModel = rentalTrucks[((contractId - 1) % #rentalTrucks) + 1]

    local jobId = newLCJobId('lc')
    local singleInsertOk = pcall(MySQL.insert.await, [[
        INSERT INTO trucker_jobs (
            id, status, assigned_citizenid, origin_id, dest_id, cargo_item,
            trailer_model, base_payment, distance, expires_at, created_at,
            contract_type, cargo_type, fragile, valuable, fast, illegal
        ) VALUES (?, 'active', ?, 'buccaneer_hq', ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 2 HOUR), NOW(), ?, ?, ?, ?, ?, ?)
    ]], {
        jobId, citizenId, ('dest_%d'):format(destIndex), load.name,
        load.trailer, payment, dist, contractType, adr, fragile, valuable, fast, illegal
    })
    if not singleInsertOk then
        StartingJobLock[citizenId] = nil
        TriggerClientEvent('aurp_trucker:notify', src, 'Erro', 'Falha ao registrar o contrato.', 'error')
        return
    end

    -- OneSync Server-Side Spawn & Dual-Layer Key Management
    local truckNetId = nil
    local truckPlate = nil
    local truckEntity = nil

    if isQuickJob and truckSpawn then
        local modelHash = joaat(truckModel or 'hauler')
        truckEntity = CreateVehicle(modelHash, truckSpawn.x, truckSpawn.y, truckSpawn.z, truckSpawn.w, true, true)
        if not waitEntity(truckEntity, 5000) then
            -- Falha ao instanciar: aborta, expira o job recém-criado e libera o lock
            if truckEntity and truckEntity ~= 0 and DoesEntityExist(truckEntity) then DeleteEntity(truckEntity) end
            pcall(DB_ExpireJob, jobId)
            StartingJobLock[citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', src, 'Pátio Bloqueado', 'Falha ao instanciar o caminhão. Tente novamente.', 'error')
            return
        end

        truckPlate = ("TRK%05d"):format(math.random(10000, 99999))
        SetVehicleNumberPlateText(truckEntity, truckPlate)
        SetVehicleDoorsLocked(truckEntity, 1)

        if Config.Debug then print(("[AUST_Trucker] Quick Job truck spawned with plate: %s for player %s"):format(truckPlate, tostring(src))) end

        -- Dual-Layer Key Assignment:
        -- 1. ox_inventory physical item
        local keyMetadata = {
            plate = truckPlate,
            description = "Chave do Veículo - " .. truckPlate
        }
        local added = exports.ox_inventory:AddItem(src, 'keys', 1, keyMetadata)
        if not added then
            exports.ox_inventory:AddItem(src, 'vehiclekey', 1, keyMetadata)
        end

        -- 2. Framework key registration
        if exports.qbx_vehiclekeys then
            pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, truckEntity) end)
        elseif exports['qb-vehiclekeys'] then
            pcall(function() exports['qb-vehiclekeys']:GiveKeys(truckPlate) end)
        end
        TriggerClientEvent('aurp_trucker:client:giveVehicleKeys', src, truckPlate)

        truckNetId = NetworkGetNetworkIdFromEntity(truckEntity)
    elseif not isQuickJob then
        local myTrucks = TruckFleetService and TruckFleetService.GetPlayerTrucks and TruckFleetService.GetPlayerTrucks(citizenId)
        local ownedPlate = (myTrucks and myTrucks[1] and myTrucks[1].plate) or nil
        if ownedPlate then
            TriggerClientEvent('aurp_trucker:client:giveVehicleKeys', src, ownedPlate)
        end
    end

    ActiveLCContracts[citizenId] = jobId
    ActiveLCContractData[jobId] = {
        jobId = jobId,
        citizenId = citizenId,
        src = src,
        stage = 'STATUS_IN_TRANSIT',
        isParty = false,
        deliveryCoords = dest,
        cargoName = load.name,
        truckPlate = truckPlate,
        truckEntity = truckEntity,
        truckNetId = truckNetId,
    }
    StartingJobLock[citizenId] = nil

    local returnCoords = (Config.LC_Headquarters and Config.LC_Headquarters.garage_spawns and Config.LC_Headquarters.garage_spawns[1]) or vector4(1250.55, -3162.4, 5.88, 270.00)

    local payload = {
        jobId = jobId,
        cargoName = load.name,
        isQuickJob = isQuickJob,
        contractType = contractType,
        truckModel = isQuickJob and truckModel or nil,
        truckNetId = truckNetId,
        truckPlate = truckPlate,
        trailerModel = load.trailer,
        truckSpawn = isQuickJob and truckSpawn or nil,
        trailerSpawn = trailerSpawn,
        deliveryCoords = dest,
        returnCoords = returnCoords,
        payment = payment,
        distance = dist,
        stage = 'STATUS_IN_TRANSIT',
    }

    TriggerClientEvent('aurp_trucker:client:startLCContract', src, payload)
end

-- ========================================================
-- EXECUÇÃO DE CONTRATOS EM GRUPO (COMBOIO / MULTIPLAYER)
-- ========================================================
local function StartPartyLCContract(leaderSrc, contractId, contractTypeOverride)
    local leaderPlayer = Framework.GetPlayer(leaderSrc)
    if not leaderPlayer then return end
    -- Rate limit de início de contrato em grupo
    if not rateLimit('lcStart:' .. leaderSrc, 3000) then return end
    local leaderCid = Framework.GetCitizenId(leaderPlayer)

    -- 1. Verificação de Permissão do Líder (Fail-Closed)
    local partyId = PartyService and PartyService.GetPartyBySrc(leaderSrc)
    if not partyId or not (VP_Trucker and VP_Trucker.Parties and VP_Trucker.Parties[partyId]) then
        TriggerClientEvent('aurp_trucker:notify', leaderSrc, 'Grupo Inexistente', 'Você precisa estar em um grupo ativo para iniciar serviços em comboio.', 'error')
        return
    end

    local party = VP_Trucker.Parties[partyId]
    if party.leader ~= leaderCid then
        TriggerClientEvent('aurp_trucker:notify', leaderSrc, 'Acesso Negado', 'Apenas o líder do grupo possui permissão para aceitar e iniciar o serviço em grupo!', 'error')
        return
    end

    -- 2. Escalonamento por Número de Membros Ativos (N)
    local activeMembers = {}
    for mCid, mInfo in pairs(party.members) do
        if mInfo.src and GetPlayerPing(mInfo.src) > 0 then
            local pObj = Framework.GetPlayer(mInfo.src)
            if pObj then
                table.insert(activeMembers, {
                    src = mInfo.src,
                    citizenId = mCid,
                    name = GetCharName(mInfo.src) or mCid,
                    isLeader = (mCid == leaderCid)
                })
            end
        end
    end

    local N = #activeMembers
    if N == 0 then
        TriggerClientEvent('aurp_trucker:notify', leaderSrc, 'Grupo Vazio', 'Nenhum membro ativo ou online encontrado no grupo.', 'error')
        return
    end

    -- 3. Verificação de Ocupação/Jobs Ativos de Cada Membro
    for _, member in ipairs(activeMembers) do
        if StartingJobLock[member.citizenId] or ActiveLCContracts[member.citizenId] or (JobService and JobService.GetActiveByPlayer and JobService.GetActiveByPlayer(member.citizenId)) then
            local busyMsg = ('O membro %s já possui uma entrega em andamento. Todos devem estar livres para iniciar o serviço em grupo!'):format(member.name)
            for _, m in ipairs(activeMembers) do
                TriggerClientEvent('aurp_trucker:notify', m.src, 'Membro Ocupado', busyMsg, 'error')
            end
            return
        end
    end

    -- 4. Carregar Dados do Contrato Selecionado
    contractId = tonumber(contractId)
    if not contractId or contractId <= 0 then
        TriggerClientEvent('aurp_trucker:notify', leaderSrc, 'Frete Inválido', 'Identificador de carga inválido.', 'error')
        return
    end

    local availableLoads = (Config.LC_Jobs and Config.LC_Jobs.available_loads) or {}
    local load = availableLoads[contractId]
    if not load then
        TriggerClientEvent('aurp_trucker:notify', leaderSrc, 'Frete Indisponível', 'Este frete não está mais disponível no mercado.', 'error')
        return
    end

    -- 5. Identificar Tipo de Contrato (Trabalho Rápido vs Caminhão Próprio)
    -- Tipo 1 só vale se TODOS os membros possuem caminhão; caso contrário é derivado/negado.
    local isQuickJob = true
    local override = tonumber(contractTypeOverride)
    if override == 1 then
        isQuickJob = false
    elseif override == 0 then
        isQuickJob = true
    else
        isQuickJob = (contractId % 2 ~= 0)
    end
    local contractType = isQuickJob and 0 or 1

    -- 6. Validação Estrita de Caminhão Próprio para TODOS os N membros (fail-closed)
    if not isQuickJob then
        for _, member in ipairs(activeMembers) do
            local myTrucks = TruckFleetService and TruckFleetService.GetPlayerTrucks and TruckFleetService.GetPlayerTrucks(member.citizenId)
            if not myTrucks or #myTrucks == 0 then
                local noTruckMsg = ('O membro %s não possui um caminhão registrado na sua frota! O contrato em grupo requer caminhão próprio para todos.'):format(member.name)
                for _, m in ipairs(activeMembers) do
                    TriggerClientEvent('aurp_trucker:notify', m.src, 'Caminhão Necessário', noTruckMsg, 'error')
                end
                return
            end
        end
    end

    -- 7. Local de Entrega Base Central
    local deliveryLocs = Config.LC_DeliveryLocations or { vector4(1452.67, 6552.02, 14.89, 138.69) }
    local destIndex = ((contractId - 1) % #deliveryLocs) + 1
    local baseDest = deliveryLocs[destIndex] or deliveryLocs[1]
    local origin = Config.LC_Headquarters and Config.LC_Headquarters.coords or vector3(1208.83, -3115.0, 5.54)
    local rawDist = #(vector3(baseDest.x, baseDest.y, baseDest.z) - origin) / 1000.0
    local dist = tonumber(string.format("%.2f", rawDist)) or 1.0
    if dist <= 0 then dist = 1.0 end

    -- Definição de taxas e valores base
    local def = load.def or {0,0,0,0}
    local adr = def[1] or 0
    local fragile = def[2] or 0
    local valuable = def[3] or 0
    local illegal = def[4] or 0
    local fast = (contractId % 3 == 0) and 1 or 0

    -- Validação de habilidades requeridas por membro (mesma regra do caminho individual, fail-closed)
    if ProgressionService and ProgressionService.CanPlayerAcceptContract then
        local checkTbl = { distance = dist, cargo_type = adr, fragile = fragile, valuable = valuable, fast = fast, illegal = illegal }
        for _, member in ipairs(activeMembers) do
            local canAccept, reason, detailedReason = ProgressionService.CanPlayerAcceptContract(member.citizenId, checkTbl)
            if not canAccept then
                local blockMsg = ('O membro %s não atende aos requisitos: %s'):format(
                    member.name, tostring(detailedReason or reason or 'habilidade insuficiente'))
                for _, m in ipairs(activeMembers) do
                    TriggerClientEvent('aurp_trucker:notify', m.src, 'Frete Bloqueado', blockMsg, 'error')
                end
                return
            end
        end
    end

    local baseRate = 1250 + (valuable * 450) + (fragile * 350) + (adr > 0 and 600 or 0)
    local rawPayment = math.floor(dist * baseRate + 1200)
    local rentalFeePct = isQuickJob and ((Config.LC_Jobs and Config.LC_Jobs.truck_rental and Config.LC_Jobs.truck_rental.rental_fee_percent) or 15) or 0
    local basePayment = math.floor(rawPayment * (1 - (rentalFeePct / 100)))

    -- Vagas de garagem e reboques configuradas na base
    local garageSpawns = (Config.LC_Headquarters and Config.LC_Headquarters.garage_spawns) or { vector4(1250.55, -3162.4, 5.88, 270.00) }
    local trailerSpawns = (Config.LC_Headquarters and Config.LC_Headquarters.trailer_spawns) or { vector4(1274.21, -3186.43, 5.91, 90.00) }
    local rentalTrucks = { "hauler", "phantom", "packer", "hauler2", "brickades" }
    local returnCoords = (Config.LC_Headquarters and Config.LC_Headquarters.garage_spawns and Config.LC_Headquarters.garage_spawns[1]) or vector4(1250.55, -3162.4, 5.88, 270.00)

    -- Geometria de Tolerância de Coordenadas de Entrega (no máximo 5 metros ao redor do destino)
    local destH = baseDest.w or 0.0
    local destHeadingRad = math.rad(destH + 90.0)
    local perpX = math.cos(destHeadingRad)
    local perpY = math.sin(destHeadingRad)

    -- 8. Loop de Despacho e Multiplicação de Ativos (N instâncias)
    local timeStamp = os.time()
    for i, member in ipairs(activeMembers) do
        -- Bloqueio preventivo
        StartingJobLock[member.citizenId] = true

        -- Bônus individual de skills por membro + 10% bônus de comboio
        local memberContractCheck = {
            distance = dist,
            cargo_type = adr,
            fragile = fragile,
            valuable = valuable,
            fast = fast,
            illegal = illegal
        }
        local bonusInfo = (ProgressionService and ProgressionService.CalculateContractBonuses) and ProgressionService.CalculateContractBonuses(member.citizenId, memberContractCheck) or { moneyMultiplier = 1.0, expMultiplier = 1.0 }
        local partyBonusMult = 1.10
        local memberPayment = math.floor(basePayment * (bonusInfo.moneyMultiplier or 1.0) * partyBonusMult)

        -- Cálculo do offset lateral de entrega (no máximo 5 metros no total)
        local spreadOffset = 0.0
        if N > 1 then
            spreadOffset = ((i - 1) / (N - 1) - 0.5) * 5.0
        end
        local memberDest = vector4(
            baseDest.x + (perpX * spreadOffset),
            baseDest.y + (perpY * spreadOffset),
            baseDest.z,
            baseDest.w
        )

        -- Alocação de vaga física distinta para evitar sobreposição nos spawns da base
        local gIdx = ((i - 1) % #garageSpawns) + 1
        local tIdx = ((i - 1) % #trailerSpawns) + 1
        local truckSpawn = garageSpawns[gIdx]
        local trailerSpawn = trailerSpawns[tIdx]

        -- Modelo de caminhão de aluguer (varia entre os membros, mas reboque e carga são idênticos)
        local truckModel = rentalTrucks[((i + contractId - 2) % #rentalTrucks) + 1]

        local jobId = newLCJobId('lc_party')
        local insertOk, insertErr = pcall(MySQL.insert.await, [[
            INSERT INTO trucker_jobs (
                id, status, assigned_citizenid, origin_id, dest_id, cargo_item,
                trailer_model, base_payment, distance, expires_at, created_at,
                contract_type, cargo_type, fragile, valuable, fast, illegal
            ) VALUES (?, 'active', ?, 'buccaneer_hq', ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 2 HOUR), NOW(), ?, ?, ?, ?, ?, ?)
        ]], {
            jobId, member.citizenId, ('dest_%d'):format(destIndex), load.name,
            load.trailer, memberPayment, dist, contractType, adr, fragile, valuable, fast, illegal
        })
        if not insertOk then
            -- Sempre libera o lock do membro, mesmo se o INSERT falhar
            StartingJobLock[member.citizenId] = nil
            TriggerClientEvent('aurp_trucker:notify', member.src, 'Erro', 'Falha ao registrar o contrato em grupo.', 'error')
            goto continue_member
        end

        ActiveLCContracts[member.citizenId] = jobId
        ActiveLCContractData[jobId] = {
            jobId = jobId,
            citizenId = member.citizenId,
            src = member.src,
            stage = 'STATUS_IN_TRANSIT',
            isParty = true,
            partyId = partyId,
            deliveryCoords = memberDest,
            cargoName = load.name,
        }
        StartingJobLock[member.citizenId] = nil

        local memberPayload = {
            jobId = jobId,
            cargoName = load.name,
            isQuickJob = isQuickJob,
            contractType = contractType,
            truckModel = isQuickJob and truckModel or nil,
            trailerModel = load.trailer,
            truckSpawn = isQuickJob and truckSpawn or nil,
            trailerSpawn = trailerSpawn,
            deliveryCoords = memberDest,
            returnCoords = returnCoords,
            payment = memberPayment,
            distance = dist,
            isParty = true,
            partyMemberIndex = i,
            totalMembers = N,
            stage = 'STATUS_IN_TRANSIT',
        }

        TriggerClientEvent('aurp_trucker:client:startLCContract', member.src, memberPayload)
        ::continue_member::
    end

    -- Notificar todos os membros sobre a saída do comboio
    for _, m in ipairs(activeMembers) do
        TriggerClientEvent('aurp_trucker:notify', m.src, 'Comboio Despachado!', ('Serviço em grupo iniciado para %d membros. Siga a rota de entrega no GPS!'):format(N), 'success')
    end
end

RegisterNetEvent('aurp_trucker:server:startLCContract', function(contractId, contractType, isParty)
    local src = source
    if Config.Debug then
        print(("^2[AUST_Trucker Server] aurp_trucker:server:startLCContract received from src %s (contractId: %s, type: %s, isParty: %s)^7"):format(
            tostring(src), tostring(contractId), tostring(contractType), tostring(isParty)
        ))
    end
    if not rateLimit('lcStartEvt:' .. src, 2000) then return end
    if GlobalStartTruckDelivery then
        GlobalStartTruckDelivery(src, {
            id = contractId,
            contractId = contractId,
            contractType = contractType,
            isParty = isParty
        })
    elseif isParty then
        StartPartyLCContract(src, contractId, contractType)
    else
        StartLCContractForPlayer(src, contractId, contractType)
    end
end)

RegisterNetEvent('aurp_trucker:server:cancelActiveLCContract', function()
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    if not rateLimit('lcCancel:' .. src, 2000) then return end
    local citizenId = Framework.GetCitizenId(Player)

    local jobId = ActiveLCContracts[citizenId]
    if jobId and ActiveLCContractData[jobId] then
        local contractInfo = ActiveLCContractData[jobId]
        local truckPlate = contractInfo.truckPlate
        if truckPlate then
            pcall(function()
                local removed = exports.ox_inventory:RemoveItem(src, 'keys', 1, { plate = truckPlate })
                if not removed then
                    exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, { plate = truckPlate })
                end
            end)
            if exports.qbx_vehiclekeys and contractInfo.truckEntity and DoesEntityExist(contractInfo.truckEntity) then
                pcall(function() exports.qbx_vehiclekeys:RemoveKeys(src, contractInfo.truckEntity) end)
            end
            if Config.Debug then print(("[AUST_Trucker] Cancelled job: key stripped for plate %s"):format(truckPlate)) end
        end
        if contractInfo.truckEntity and DoesEntityExist(contractInfo.truckEntity) then
            DeleteEntity(contractInfo.truckEntity)
        end
        ActiveLCContractData[jobId] = nil
    end

    ActiveLCContracts[citizenId] = nil
    StartingJobLock[citizenId] = nil
    if Config.Debug then print(("[AUST_Trucker Server] Cancelled active contract for player %s (src: %s)"):format(tostring(citizenId), tostring(src))) end
    TriggerClientEvent('aurp_trucker:notify', src, 'Contrato Cancelado', 'Sua entrega foi cancelada e os veículos foram removidos.', 'info')
end)

RegisterNetEvent('truck_logistics:cancelContract', function(location, data)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    if not rateLimit('lcCancel:' .. src, 2000) then return end
    local citizenId = Framework.GetCitizenId(Player)

    local jobId = ActiveLCContracts[citizenId]
    if jobId and ActiveLCContractData[jobId] then
        local contractInfo = ActiveLCContractData[jobId]
        local truckPlate = contractInfo.truckPlate
        if truckPlate then
            pcall(function()
                local removed = exports.ox_inventory:RemoveItem(src, 'keys', 1, { plate = truckPlate })
                if not removed then
                    exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, { plate = truckPlate })
                end
            end)
            if exports.qbx_vehiclekeys and contractInfo.truckEntity and DoesEntityExist(contractInfo.truckEntity) then
                pcall(function() exports.qbx_vehiclekeys:RemoveKeys(src, contractInfo.truckEntity) end)
            end
        end
        if contractInfo.truckEntity and DoesEntityExist(contractInfo.truckEntity) then
            DeleteEntity(contractInfo.truckEntity)
        end
        ActiveLCContractData[jobId] = nil
    end

    ActiveLCContracts[citizenId] = nil
    StartingJobLock[citizenId] = nil
    if Config.Debug then print(("[AUST_Trucker Server] truck_logistics:cancelContract processed for player %s"):format(tostring(citizenId))) end
    TriggerClientEvent('aurp_trucker:notify', src, 'Contrato Cancelado', 'Sua entrega foi cancelada.', 'info')
end)

RegisterNetEvent('truck_logistics:startContract', function(location, data)
    local src = source
    if Config.Debug then print(("^2[AUST_Trucker Server] truck_logistics:startContract received from src %s^7"):format(tostring(src))) end
    local contractId = nil
    local contractType = nil
    local isParty = false
    if type(data) == 'table' then
        contractId = data.id or data.contract_id or data.contractId or data.jobId
        contractType = data.contract_type or data.contractType
        isParty = (data.party == true or data.isParty == true)
    elseif type(data) == 'number' or type(data) == 'string' then
        contractId = data
    elseif type(location) == 'number' or (type(location) == 'string' and tonumber(location)) then
        contractId = location
    end
    if isParty then
        StartPartyLCContract(src, contractId, contractType)
    else
        StartLCContractForPlayer(src, contractId, contractType)
    end
end)

RegisterNetEvent('truck_logistics:makeContract', function(location, data)
    local src = source
    if Config.Debug then print(("^2[AUST_Trucker Server] truck_logistics:makeContract received from src %s^7"):format(tostring(src))) end
    local contractId = nil
    local contractType = nil
    local isParty = false
    if type(data) == 'table' then
        contractId = data.id or data.contract_id or data.contractId or data.jobId
        contractType = data.contract_type or data.contractType
        isParty = (data.party == true or data.isParty == true)
    elseif type(data) == 'number' or type(data) == 'string' then
        contractId = data
    elseif type(location) == 'number' or (type(location) == 'string' and tonumber(location)) then
        contractId = location
    end
    if isParty then
        StartPartyLCContract(src, contractId, contractType)
    else
        StartLCContractForPlayer(src, contractId, contractType)
    end
end)

RegisterNetEvent('truck_logistics:deliveredCargo', function()
    -- Confirma entrega do frete no destino
end)

local CompletingContractsLock = {}

-- ========================================================
-- PROVA DE ENTREGA (contratos LC / quick job / caminhão próprio)
-- Os eventos finishQuickJobContract / finishOwnedTruckContract / completeLCContract são
-- disparáveis pelo client; sem esta validação bastava iniciar um contrato e finalizá-lo
-- de qualquer lugar, na hora. Falha fechada: sem destino resolvido, não paga.
-- ========================================================
local LC_DELIVERY_RADIUS      = 35.0    -- m, jogador até o ponto de entrega
local LC_TRUCK_RADIUS         = 75.0    -- m, caminhão (quando rastreado pelo servidor) até o ponto
local LC_MIN_SECONDS          = 20      -- piso do tempo mínimo de contrato
local LC_MAX_SPEED_MS         = 50.0    -- m/s (~180 km/h) usado no tempo mínimo por distância

local function ResolveLCDestination(row)
    local info = ActiveLCContractData[row.id]
    if info and info.deliveryCoords then
        local c = info.deliveryCoords
        if c.x and c.y and c.z then return vector3(c.x, c.y, c.z), tonumber(c.w) end
    end
    -- Reconstrói do índice gravado no job (dest_N), igual à criação do contrato
    local idx = tonumber(tostring(row.dest_id or ''):match('^dest_(%d+)$'))
    local locs = Config.LC_DeliveryLocations
    if idx and locs and locs[idx] then
        local c = locs[idx]
        return vector3(c.x, c.y, c.z), tonumber(c.w)
    end
    return nil
end

-- Bônus de estacionamento manual (+5%): verificado NO SERVIDOR. O client só dispara o fim do
-- contrato; a flag `parkedManually` que ele manda é ignorada (antes era sempre `true`).
-- Mesmos critérios do marcador da vaga no client: veículo na baía, alinhado ao heading da vaga
-- e praticamente parado.
local PARK_MAX_DIST    = 6.0    -- m do centro da baía (client exige 4 m do ped)
local PARK_MAX_HEADING = 15.0   -- graus de diferença para o heading da vaga (client exige 10)
local PARK_MAX_SPEED   = 3.0    -- m/s

local function VerifyParkedInBay(src, row)
    local dest, heading = ResolveLCDestination(row)
    if not dest or not heading then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        local info = ActiveLCContractData[row.id]
        veh = info and info.truckEntity
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

    if #(GetEntityCoords(veh) - dest) > PARK_MAX_DIST then return false end
    local diff = math.abs((GetEntityHeading(veh) - heading + 180.0) % 360.0 - 180.0)
    if diff > PARK_MAX_HEADING then return false end
    if (GetEntitySpeed(veh) or 0.0) > PARK_MAX_SPEED then return false end
    return true
end

-- Retorna true, ou false + motivo (texto para log; o jogador recebe mensagem genérica)
local function ValidateLCDelivery(src, citizenId, row)
    -- Só contratos LC (ids lc_ / lc_party_); jobs normais passam por JobService.Complete
    if type(row.id) ~= 'string' or row.id:sub(1, 3) ~= 'lc_' then
        return false, 'job não é contrato LC'
    end

    local dest = ResolveLCDestination(row)
    if not dest then return false, 'destino não resolvido' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'ped inexistente' end
    local pDist = #(GetEntityCoords(ped) - dest)
    if pDist > LC_DELIVERY_RADIUS then
        return false, ('jogador a %.1fm do destino'):format(pDist)
    end

    local info = ActiveLCContractData[row.id]
    if info and info.truckEntity and DoesEntityExist(info.truckEntity) then
        local tDist = #(GetEntityCoords(info.truckEntity) - dest)
        if tDist > LC_TRUCK_RADIUS then
            return false, ('caminhão a %.1fm do destino'):format(tDist)
        end
    end

    local elapsed = MySQL.scalar.await(
        'SELECT TIMESTAMPDIFF(SECOND, created_at, NOW()) FROM trucker_jobs WHERE id = ? LIMIT 1',
        { row.id }
    )
    elapsed = tonumber(elapsed)
    if not elapsed then return false, 'tempo de contrato indisponível' end
    local minSeconds = math.max(LC_MIN_SECONDS, math.floor(((tonumber(row.distance) or 0) * 1000.0) / LC_MAX_SPEED_MS))
    if elapsed < minSeconds then
        return false, ('concluído em %ds (mínimo %ds)'):format(elapsed, minSeconds)
    end

    return true
end

-- ========================================================
-- CONCLUSÃO: TRABALHO RÁPIDO (QUICK JOB) COM VISTORIA DE DANOS
-- ========================================================
-- Vistoria de danos lida NO SERVIDOR a partir do caminhão que o servidor spawnou para o
-- contrato (replicado via OneSync). O client não informa mais engine/body/pneus: antes o
-- payload do evento definia a dedução e permitia reportar "0 de dano" sempre.
-- Sem entidade rastreada (ex.: reinício do resource), devolve nil e o chamador assume sem dano.
local function ReadServerDamages(contractId)
    local info = ActiveLCContractData[contractId]
    local veh = info and info.truckEntity
    if not veh or not DoesEntityExist(veh) then return nil end

    local engine = tonumber(GetVehicleEngineHealth(veh)) or 1000.0
    local body = tonumber(GetVehicleBodyHealth(veh)) or 1000.0
    local burst = 0
    for tyre = 0, 5 do
        if IsVehicleTyreBurst(veh, tyre, false) then burst = burst + 1 end
    end
    return { engineHealth = engine, bodyHealth = body, burstTires = burst }
end

-- O 3º parâmetro é ignorado de propósito (mantido só por compatibilidade de assinatura).
local function FinishQuickJobContract(src, jobId, _ignoredClientDamages)
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

    local proofOk, proofReason = ValidateLCDelivery(src, citizenId, row)
    if not proofOk then
        CompletingContractsLock[citizenId] = nil
        print(('[AUST_Trucker Anti-Cheat] Finalização recusada para %s (src %s, job %s): %s'):format(
            tostring(citizenId), tostring(src), tostring(row.id), proofReason or '?'))
        TriggerClientEvent('aurp_trucker:notify', src, 'Entrega não validada. Leve a carga até o ponto de entrega.', 'error')
        return
    end

    -- Mutação atômica fail-closed
    local affected = MySQL.update.await([[
        UPDATE trucker_jobs SET status = 'completed', completed_at = NOW() WHERE id = ? AND status = 'active'
    ]], { row.id })

    if not affected or affected == 0 then
        CompletingContractsLock[citizenId] = nil
        return
    end

    local grossPayment = row.base_payment or 2500
    local dist = row.distance or 2.5

    -- Cálculo de Vistoria de Danos Mecânicos e Lataria (leitura autoritativa do servidor)
    -- Lido aqui, antes de qualquer remoção do caminhão mais abaixo.
    local damages = ReadServerDamages(row.id)
    if not damages then
        if Config.Debug then print(('[AUST_Trucker] Vistoria sem caminhão rastreado para o job %s: assumindo sem danos'):format(tostring(row.id))) end
        damages = {}
    end
    local engineHealth = tonumber(damages.engineHealth) or 1000.0
    local bodyHealth = tonumber(damages.bodyHealth) or 1000.0
    local burstTires = tonumber(damages.burstTires) or 0
    -- Valor vem do client: rejeita NaN/inf e limita a 0..10 (negativo geraria dinheiro)
    if burstTires ~= burstTires or burstTires == math.huge or burstTires == -math.huge then burstTires = 0 end
    burstTires = math.floor(math.max(0, math.min(10, burstTires)))
    if engineHealth ~= engineHealth then engineHealth = 1000.0 end
    if bodyHealth ~= bodyHealth then bodyHealth = 1000.0 end

    if engineHealth > 1000.0 then engineHealth = 1000.0 end
    if bodyHealth > 1000.0 then bodyHealth = 1000.0 end
    if engineHealth < 0.0 then engineHealth = 0.0 end
    if bodyHealth < 0.0 then bodyHealth = 0.0 end

    local engineLoss = math.max(0.0, (1000.0 - engineHealth) / 1000.0)
    local bodyLoss = math.max(0.0, (1000.0 - bodyHealth) / 1000.0)
    local damageRatio = (engineLoss * 0.6) + (bodyLoss * 0.4)

    local rawPenalty = math.floor(grossPayment * damageRatio * 0.45) + (burstTires * 150)
    -- Teto seguro de penalidade: máximo de 50% de dedução
    local maxPenalty = math.floor(grossPayment * 0.50)
    local damageDeduction = math.max(0, math.min(rawPenalty, maxPenalty))

    -- Mínimo de 10% garantido para assegurar fail-closed sem saldo nulo/negativo
    local minGuaranteed = math.floor(grossPayment * 0.10)
    local netPayment = math.max(grossPayment - damageDeduction, minGuaranteed)

    Framework.AddMoney(Player, 'bank', netPayment, 'aurp-trucker-quick-job')
    DB_AddPlayerStats(citizenId, netPayment, dist)

    local contractData = {
        distance = dist,
        cargo_type = row.cargo_type or 0,
        fragile = row.fragile or 0,
        valuable = row.valuable or 0,
        fast = row.fast or 0,
        illegal = row.illegal or 0,
    }
    local bonuses = (ProgressionService and ProgressionService.CalculateContractBonuses) and ProgressionService.CalculateContractBonuses(citizenId, contractData) or { expMultiplier = 1.0, moneyBonusPct = 0, expBonusPct = 0 }
    local xpMultiplier = bonuses and bonuses.expMultiplier or 1.0
    local xpResult = ProgressionService and ProgressionService.GrantXP(src, citizenId, netPayment, xpMultiplier, dist)

    -- Logística 2.0: Persistência em aust_trucker_stats
    pcall(DB_UpdateAustTruckerStats, citizenId, xpResult and xpResult.xpGained or 200, 1)

    -- Step C: Key Removal & Vehicle Deletion on Finish
    local contractInfo = ActiveLCContractData[row.id]
    local truckPlate = contractInfo and contractInfo.truckPlate
    if truckPlate then
        pcall(function()
            local removed = exports.ox_inventory:RemoveItem(src, 'keys', 1, { plate = truckPlate })
            if not removed then
                exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, { plate = truckPlate })
            end
        end)
        if exports.qbx_vehiclekeys and contractInfo.truckEntity and DoesEntityExist(contractInfo.truckEntity) then
            pcall(function() exports.qbx_vehiclekeys:RemoveKeys(src, contractInfo.truckEntity) end)
        end
        if Config.Debug then print(("[AUST_Trucker] Vehicle key stripped for plate %s from player %s"):format(truckPlate, tostring(src))) end
    end
    if contractInfo and contractInfo.truckEntity and DoesEntityExist(contractInfo.truckEntity) then
        DeleteEntity(contractInfo.truckEntity)
    end
    ActiveLCContractData[row.id] = nil

    ActiveLCContracts[citizenId] = nil
    StartingJobLock[citizenId] = nil

    TriggerClientEvent('aurp_trucker:client:quickJobFinished', src, {
        grossPayment = grossPayment,
        damageDeduction = damageDeduction,
        netPayment = netPayment,
        distance = dist,
        engineHealth = engineHealth,
        bodyHealth = bodyHealth,
        burstTires = burstTires,
        xpGained = xpResult and xpResult.xpGained or 0,
        newLevel = xpResult and xpResult.newLevel or 1,
        levelsGained = xpResult and xpResult.levelsGained or 0,
    })

    SetTimeout(3000, function()
        CompletingContractsLock[citizenId] = nil
    end)
end

-- ========================================================
-- CONCLUSÃO: CAMINHÃO PRÓPRIO (OWNED TRUCK / FREIGHT) 100% INTEGRAL
-- ========================================================
local function FinishOwnedTruckContract(src, jobId, parkedManually)
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

    local proofOk, proofReason = ValidateLCDelivery(src, citizenId, row)
    if not proofOk then
        CompletingContractsLock[citizenId] = nil
        print(('[AUST_Trucker Anti-Cheat] Finalização recusada para %s (src %s, job %s): %s'):format(
            tostring(citizenId), tostring(src), tostring(row.id), proofReason or '?'))
        TriggerClientEvent('aurp_trucker:notify', src, 'Entrega não validada. Leve a carga até o ponto de entrega.', 'error')
        return
    end

    -- Mutação atômica fail-closed
    local affected = MySQL.update.await([[
        UPDATE trucker_jobs SET status = 'completed', completed_at = NOW() WHERE id = ? AND status = 'active'
    ]], { row.id })

    if not affected or affected == 0 then
        CompletingContractsLock[citizenId] = nil
        return
    end

    local payment = row.base_payment or 2500
    local dist = row.distance or 2.5

    -- Bônus de 5% por alinhamento e estacionamento manual na vaga (verificado no servidor;
    -- o argumento do client é ignorado)
    parkedManually = VerifyParkedInBay(src, row)
    if parkedManually then
        payment = math.floor(payment * 1.05)
    end

    -- Pagamento 100% integral sem desconto de aluguel ou reparos
    Framework.AddMoney(Player, 'bank', payment, 'aurp-trucker-owned-freight')
    DB_AddPlayerStats(citizenId, payment, dist)

    local contractData = {
        distance = dist,
        cargo_type = row.cargo_type or 0,
        fragile = row.fragile or 0,
        valuable = row.valuable or 0,
        fast = row.fast or 0,
        illegal = row.illegal or 0,
    }
    local bonuses = (ProgressionService and ProgressionService.CalculateContractBonuses) and ProgressionService.CalculateContractBonuses(citizenId, contractData) or { expMultiplier = 1.0, moneyBonusPct = 0, expBonusPct = 0 }
    local xpMultiplier = bonuses and bonuses.expMultiplier or 1.0
    local xpResult = ProgressionService and ProgressionService.GrantXP(src, citizenId, payment, xpMultiplier, dist)

    -- Logística 2.0: Persistência em aust_trucker_stats
    pcall(DB_UpdateAustTruckerStats, citizenId, xpResult and xpResult.xpGained or 250, 1)

    ActiveLCContractData[row.id] = nil
    ActiveLCContracts[citizenId] = nil
    StartingJobLock[citizenId] = nil

    TriggerClientEvent('aurp_trucker:client:ownedTruckContractFinished', src, {
        payment = payment,
        distance = dist,
        parkedManually = parkedManually,
        xpGained = xpResult and xpResult.xpGained or 0,
        newLevel = xpResult and xpResult.newLevel or 1,
        levelsGained = xpResult and xpResult.levelsGained or 0,
    })

    SetTimeout(3000, function()
        CompletingContractsLock[citizenId] = nil
    end)
end

-- Roteamento Retrocompatível & Blindagem Anti-Cheat (Pilar 2)
local function FinalizeLCContract(src, jobId, parkedManually)
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local citizenId = Framework.GetCitizenId(Player)

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local pCoords = GetEntityCoords(ped)

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
        print(('[AUST_Trucker Anti-Cheat] DROP aplicado em %s (src %s): tentativa de finalizar contrato sem job ativo.'):format(tostring(citizenId), tostring(src)))
        DropPlayer(src, '[AUST_Trucker Anti-Cheat] Violação de segurança: finalização sem contrato ativo.')
        return
    end

    -- Validação de proximidade geográfica autoritativa
    local destCoords = nil
    if row.dest_coords and type(row.dest_coords) == 'string' then
        pcall(function() destCoords = json.decode(row.dest_coords) end)
    end
    if not destCoords and row.dest_id then
        local sec = Config.SecondaryIndustries or {}
        for _, ind in ipairs(sec) do
            if ind.id == row.dest_id then
                destCoords = ind.coords
                break
            end
        end
    end

    if destCoords and destCoords.x then
        local dVec = vector3(destCoords.x, destCoords.y, destCoords.z)
        local dist = #(pCoords - dVec)
        if dist > 35.0 then
            print(('[AUST_Trucker Anti-Cheat] DROP aplicado em %s (src %s): finalização fora da baía de entrega (%.1fm > 35.0m)'):format(
                tostring(citizenId), tostring(src), dist))
            DropPlayer(src, ('[AUST_Trucker Anti-Cheat] Violação de segurança: finalização acionada a %.1f metros do ponto de entrega.'):format(dist))
            return
        end
    end

    if row and row.contract_type == 1 then
        FinishOwnedTruckContract(src, jobId, parkedManually)
    else
        FinishQuickJobContract(src, jobId)
    end
end

RegisterNetEvent('aurp_trucker:server:finishQuickJobContract', function(jobId)
    FinishQuickJobContract(source, jobId)
end)

RegisterNetEvent('aurp_trucker:server:finishOwnedTruckContract', function(jobId, parkedManually)
    FinishOwnedTruckContract(source, jobId, parkedManually)
end)

RegisterNetEvent('aurp_trucker:server:completeLCContract', function(jobId, parkedManually)
    FinalizeLCContract(source, jobId, parkedManually)
end)

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
    truckId = posInt(truckId, 2147483647)
    if not truckId then return end
    local truck = MySQL.single.await('SELECT * FROM trucker_trucks WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })
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

    if not Framework.RemovePlayerMoney(src, 'bank', cost, 'Reparo de caminhão') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Saldo bancário insuficiente para o reparo!', 'error')
        return
    end
    MySQL.update.await('UPDATE trucker_trucks SET body = 1000, engine = 1000, transmission = 1000, wheels = 1000 WHERE truck_id = ? AND user_id = ?', { truckId, citizenId })
    TriggerClientEvent('aurp_trucker:notify', src, ('Caminhão totalmente reparado por $%s!'):format(cost), 'success')
end)

-- Árvore de Habilidades: Upgrade de Skill
RegisterNetEvent('aurp_trucker:server:upgradeSkill', function(skillType)
    local src = source
    local Player = Framework.GetPlayer(src)
    if not Player or type(skillType) ~= 'string' or #skillType > 32 then return end
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

    -- TakePlan aplica teto por nível e os termos do plano (juros/prazo); Create ignorava os dois
    local res = LoanService.TakePlan(src, citizenId, planIndex)
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

    amount = posInt(amount, 10000000)
    if not amount then return end
    if not rateLimit('bank:' .. src, 1000) then return end

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

    amount = posInt(amount, 10000000)
    if not amount then return end
    if not rateLimit('bank:' .. src, 1000) then return end

    local company = CompanyService.GetByMember(citizenId)
    if not company then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você não possui empresa registrada.', 'error')
        return
    end
    -- Apenas owner/manager podem sacar da conta da empresa
    local bankMember = DB_GetMember(citizenId)
    if not bankMember or (bankMember.role ~= 'owner' and bankMember.role ~= 'manager') then
        TriggerClientEvent('aurp_trucker:notify', src, 'Sem permissão para sacar', 'error')
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
RegisterNetEvent('aurp_trucker:party:create', function(data)
    local src = source
    local partyId, err = PartyService.Create(src, data)
    if partyId then
        TriggerClientEvent('aurp_trucker:notify', src, 'Grupo de transporte criado!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Falha ao criar grupo', 'error')
    end
end)

-- Party: Entrar no Grupo (por nome/código e senha)
RegisterNetEvent('aurp_trucker:party:join', function(data)
    local src = source
    local nameOrCode = data and (data.name or data.code or data.nameOrCode or data.target)
    local pass = data and (data.pass or data.password)
    local ok, res = PartyService.Join(src, nameOrCode, pass)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Você ingressou no grupo com sucesso!', 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, res or 'Falha ao ingressar no grupo.', 'error')
    end
end)

-- Party: Convidar Jogador por ID
RegisterNetEvent('aurp_trucker:party:invite', function(targetId)
    local src = source
    local targetSrc = tonumber(targetId)
    if not targetSrc then
        TriggerClientEvent('aurp_trucker:notify', src, 'ID de jogador inválido.', 'error')
        return
    end
    local ok, err = PartyService.Invite(src, targetSrc)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, ('Convite enviado ao jogador ID %d!'):format(targetSrc), 'success')
    else
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Falha ao enviar convite.', 'error')
    end
end)

-- Party: Expulsar Membro do Grupo
RegisterNetEvent('aurp_trucker:party:kick', function(targetCid)
    local src = source
    local ok, err = PartyService.Kick(src, targetCid)
    if ok then
        TriggerClientEvent('aurp_trucker:notify', src, 'Membro removido do grupo.', 'info')
    else
        TriggerClientEvent('aurp_trucker:notify', src, err or 'Falha ao expulsar membro.', 'error')
    end
end)

-- Party: Sair do Grupo
RegisterNetEvent('aurp_trucker:party:leave', function()
    local src = source
    PartyService.Leave(src)
    TriggerClientEvent('aurp_trucker:notify', src, 'Você saiu do grupo.', 'info')
end)
