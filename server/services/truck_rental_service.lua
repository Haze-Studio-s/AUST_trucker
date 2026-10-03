-- aurp_trucker — server/services/truck_rental_service.lua
-- Aluguel de caminhão com caução — versão blindada (sync do repo vp local, 2026-09-28).
--
-- Mantém o CONTRATO do client/UI atual (sem mexer neles):
--   * callback 'aurp_trucker:rental:rentTruck'(model) → { success, plate, model, deposit, fee, spawnCoords }
--     (o client cria o veículo e avisa o netId via 'aurp_trucker:rental:registerNetId')
--   * callback 'aurp_trucker:rental:returnTruck'(payload) → { success, deposit, damagePenalty, refund,
--     refundAmount, damageCost }  (os dois pares de nomes: a UI lê refundAmount/damageCost)
--   * TruckRentalService.GetRental / RegisterNetId / OnPlayerDropped (chamados por events.lua/callbacks.lua)
--
-- Correções em relação à versão anterior:
--   * dano da devolução lido NO SERVIDOR (payload.bodyHealth/engineHealth é ignorado);
--   * RegisterNetId só aceita veículo existente, com a placa e o modelo do aluguel, perto do spawn,
--     e só uma vez — antes qualquer netId (ex.: caminhão de outro jogador) era aceito e depois apagado;
--   * devolução confere a placa e a vaga; `Active` é limpo antes do pagamento (sem estorno duplo);
--   * trava por jogador + throttle contra spam/concorrência;
--   * desconexão: estorno calculado pelo dano e guardado em `refund_due`; restart: caução integral;
--     pago no próximo login ou no próximo aluguel (antes a caução era perdida).

TruckRentalService = {}

local Active   = {} -- [citizenId] = { plate, model, deposit, fee, rentedAt, netId }
local Busy     = {} -- [citizenId] = true durante uma operação
local LastCall = {} -- [src] = GetGameTimer()
local PendingLock = {} -- [citizenId] = true durante payPending/devolução (evita crédito duplo)
local NetBound = {}    -- [netId] = citizenId dono do aluguel (um netId pertence a um só cidadão)

local function bindNet(netId, citizenId)
    if not netId then return false end
    if NetBound[netId] and NetBound[netId] ~= citizenId then return false end
    NetBound[netId] = citizenId
    return true
end

local function unbindNet(netId, citizenId)
    if netId and NetBound[netId] == citizenId then NetBound[netId] = nil end
end

-- Gera placa única (contra aluguéis ativos e banco)
local function generatePlate()
    for _ = 1, 100 do
        local plate = ('ALUG%04d'):format(math.random(0, 9999))
        local used = false
        for _, r in pairs(Active) do
            if r.plate == plate then used = true break end
        end
        if not used then
            local row = MySQL.single.await('SELECT 1 AS x FROM trucker_rentals WHERE plate = ? LIMIT 1', { plate })
            if not row then return plate end
        end
    end
    return nil
end

local function cfg() return Config.TruckRental or {} end

local function throttled(src)
    local now = GetGameTimer()
    if LastCall[src] and now - LastCall[src] < (cfg().throttleMs or 2000) then return true end
    LastCall[src] = now
    return false
end

local function findTruck(model)
    for _, t in ipairs(cfg().trucks or {}) do
        if t.model == model then return t end
    end
end

local function plateOf(entity)
    return ((GetVehicleNumberPlateText(entity) or ''):gsub('%s+', ''))
end

local function validEntity(e) return e and e ~= 0 and DoesEntityExist(e) end

-- Estorno proporcional ao pior entre lataria e motor (1000 = intacto), lido no servidor.
-- `worstSeen`: pior saúde amostrada pelo servidor durante o aluguel (ver sampler abaixo). O dono da
-- entidade é o client, que poderia "curar" o veículo logo antes da devolução; usar o pior valor
-- observado impede que o reparo de última hora apague o dano já registrado.
local function computeRefund(entity, deposit, worstSeen)
    if not validEntity(entity) then return 0, deposit end
    local worst = math.max(0.0, math.min(1000.0, math.min(GetVehicleBodyHealth(entity) or 0.0,
                                                          GetVehicleEngineHealth(entity) or 0.0)))
    if tonumber(worstSeen) then worst = math.min(worst, math.max(0.0, tonumber(worstSeen))) end
    local penalty = 0
    if worst < (cfg().damageThreshold or 950.0) then
        penalty = math.min(deposit, math.floor(deposit * (1000.0 - worst) / 1000.0 + 0.5))
    end
    return deposit - penalty, penalty
end

-- Veículo do aluguel: pelo netId registrado; sem ele, procura no servidor pela placa + modelo.
local function rentalEntity(rental)
    if not rental then return nil end
    if rental.netId then
        local e = NetworkGetEntityFromNetworkId(rental.netId)
        if validEntity(e) and plateOf(e) == rental.plate then return e end
    end
    local hash = joaat(rental.model)
    for _, e in ipairs(GetAllVehicles()) do
        if validEntity(e) and GetEntityModel(e) == hash and plateOf(e) == rental.plate then
            local nid = NetworkGetNetworkIdFromEntity(e)
            -- netId já ligado a outro cidadão → não é deste aluguel
            if not rental.owner or bindNet(nid, rental.owner) then
                rental.netId = nid
                return e
            end
        end
    end
    return nil
end

-- Paga crédito pendente (desconexão/restart). DELETE com linhas afetadas: só quem apagou paga.
local function payPending(src, Player, citizenId)
    if PendingLock[citizenId] then return 0 end
    PendingLock[citizenId] = true
    local ok, res = pcall(function()
        local row = MySQL.single.await(
            'SELECT refund_due FROM trucker_rentals WHERE citizenid = ? AND refund_due IS NOT NULL', { citizenId })
        if not row then return 0 end
        local amount = tonumber(row.refund_due) or 0
        -- Credita ANTES de apagar a linha; se o crédito falhar a linha fica para a próxima tentativa
        if amount > 0 then
            if not Framework.AddMoney(Player, 'bank', amount, 'truck-rental-pending-refund') then
                print(('[AUST_trucker] payPending: falha ao creditar $%d para %s (mantido pendente)'):format(amount, tostring(citizenId)))
                return 0
            end
        end
        MySQL.update.await('DELETE FROM trucker_rentals WHERE citizenid = ? AND refund_due IS NOT NULL', { citizenId })
        if amount > 0 then
            TriggerClientEvent('aurp_trucker:notify', src,
                ('Estorno pendente da caução do aluguel: $%d'):format(amount), 'success')
        end
        return amount
    end)
    PendingLock[citizenId] = nil
    if not ok then
        print('[AUST_trucker] payPending erro: ' .. tostring(res))
        return 0
    end
    return res
end

function TruckRentalService.GetRental(citizenId)
    local r = Active[citizenId]
    return r and { plate = r.plate, model = r.model, deposit = r.deposit, fee = r.fee,
                   rentedAt = r.rentedAt, netId = r.netId } or nil
end

-- Chamado pelo evento do client após criar o veículo (e pelos eventos de início de job).
-- Aceita só o veículo do aluguel: existe, placa e modelo batem, perto do spawn e ainda não registrado.
function TruckRentalService.RegisterNetId(citizenId, netId)
    local rental = Active[citizenId]
    netId = tonumber(netId)
    if not rental or not netId then return false end
    if rental.netId and validEntity(NetworkGetEntityFromNetworkId(rental.netId)) then return false end

    local e = NetworkGetEntityFromNetworkId(netId)
    if not validEntity(e) then return false end
    if plateOf(e) ~= rental.plate then return false end
    if GetEntityModel(e) ~= joaat(rental.model) then return false end
    local sp = cfg().spawnCoords
    if sp and #(GetEntityCoords(e) - vector3(sp.x, sp.y, sp.z)) > (cfg().spawnCheckRadius or 60.0) then
        return false
    end

    -- netId só pode pertencer a um cidadão (impede registrar veículo de outro aluguel)
    if not bindNet(netId, citizenId) then return false end
    rental.netId = netId
    if VP_Trucker and VP_Trucker.PlayerJobEntities then
        VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}
        VP_Trucker.PlayerJobEntities[citizenId].truckNetId = netId
        VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = rental.plate
    end
    return true
end

lib.callback.register('aurp_trucker:rental:rentTruck', function(source, model)
    local c = cfg()
    if c.enabled == false then return { success = false, reason = 'Aluguel de caminhões desativado.' } end
    if type(model) ~= 'string' then return { success = false, reason = 'Modelo inválido.' } end
    if throttled(source) then return { success = false, reason = 'Aguarde um instante.' } end

    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    if Busy[citizenId] then return { success = false, reason = 'Operação em andamento.' } end
    if Active[citizenId] then
        return { success = false, reason = 'Você já possui um caminhão alugado ativo.' }
    end
    local truck = findTruck(model)
    if not truck then return { success = false, reason = 'Modelo de caminhão não disponível para aluguel.' } end

    Busy[citizenId] = true
    local ok, result = pcall(function()
        payPending(source, Player, citizenId)

        local fee     = truck.fee or c.rentalFee or 300
        local deposit = truck.deposit or c.depositAmount or 1500
        local total   = fee + deposit

        -- Placa única ANTES de cobrar
        local plate = generatePlate()
        if not plate then
            return { success = false, reason = 'Sem placas disponíveis no momento. Tente novamente.' }
        end

        local account = 'bank'
        if not Framework.RemoveMoney(Player, 'bank', total, 'truck-rental-deposit') then
            account = 'cash'
            if not Framework.RemoveMoney(Player, 'cash', total, 'truck-rental-deposit') then
                return { success = false, reason = ('Saldo insuficiente. Necessário: $%d (Taxa: $%d + Caução: $%d)'):format(total, fee, deposit) }
            end
        end

        Active[citizenId] = { plate = plate, model = model, deposit = deposit, fee = fee, rentedAt = os.time(), owner = citizenId }
        if VP_Trucker and VP_Trucker.PlayerJobEntities then
            VP_Trucker.PlayerJobEntities[citizenId] = VP_Trucker.PlayerJobEntities[citizenId] or {}
            VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = plate
        end

        local okIns, insErr = pcall(MySQL.insert.await,
            [[INSERT INTO trucker_rentals (citizenid, plate, model, deposit, fee, refund_due, rented_at)
              VALUES (?, ?, ?, ?, ?, NULL, NOW())
              ON DUPLICATE KEY UPDATE plate = VALUES(plate), model = VALUES(model), deposit = VALUES(deposit),
                                      fee = VALUES(fee), refund_due = NULL, rented_at = NOW()]],
            { citizenId, plate, model, deposit, fee })
        if not okIns then
            -- falha ao registrar: desfaz aluguel e devolve o valor cobrado
            print(('[AUST_trucker] rentTruck insert falhou (%s): %s - reembolsando'):format(tostring(citizenId), tostring(insErr)))
            Active[citizenId] = nil
            if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
                VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = nil
            end
            Framework.AddMoney(Player, account, total, 'truck-rental-refund')
            return { success = false, reason = 'Erro ao registrar aluguel. Valor reembolsado.' }
        end

        return { success = true, plate = plate, model = model, deposit = deposit, fee = fee,
                 spawnCoords = c.spawnCoords }
    end)
    Busy[citizenId] = nil

    if not ok then
        print(('[AUST_trucker] rentTruck erro: %s'):format(result))
        return { success = false, reason = 'Erro interno ao alugar.' }
    end
    return result
end)

lib.callback.register('aurp_trucker:rental:returnTruck', function(source, _payload)
    -- _payload (bodyHealth/engineHealth/netId) é IGNORADO: tudo é lido no servidor.
    local c = cfg()
    if throttled(source) then return { success = false, reason = 'Aguarde um instante.' } end

    local Player = Framework.GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador inválido' } end
    local citizenId = Framework.GetCitizenId(Player)

    local rental = Active[citizenId]
    if not rental then
        return { success = false, reason = 'Você não possui nenhum aluguel ativo registrado.' }
    end
    if Busy[citizenId] then return { success = false, reason = 'Operação em andamento.' } end

    local entity = rentalEntity(rental)
    if not entity then
        return { success = false, reason = 'Caminhão alugado não encontrado no mundo.' }
    end
    if #(GetEntityCoords(entity) - c.returnCoords) > (c.returnRadius or 20.0) then
        return { success = false, reason = 'Estacione o caminhão na vaga de devolução da empresa.' }
    end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - c.returnCoords) > (c.returnRadius or 20.0) + 10.0 then
        return { success = false, reason = 'Você precisa estar na vaga de devolução.' }
    end

    if PendingLock[citizenId] then return { success = false, reason = 'Operação em andamento.' } end
    Busy[citizenId] = true
    PendingLock[citizenId] = true
    local ok, result = pcall(function()
        local refund, penalty = computeRefund(entity, rental.deposit, rental.worstSeen)
        -- Grava o crédito ANTES de apagar a linha: se algo falhar depois, é pago no próximo login
        local okUpd = pcall(MySQL.update.await,
            'UPDATE trucker_rentals SET refund_due = ? WHERE citizenid = ?', { refund, citizenId })
        if not okUpd then
            return { success = false, reason = 'Erro ao registrar devolução. Tente novamente.' }
        end

        Active[citizenId] = nil -- antes de pagar: segunda chamada não acha aluguel
        unbindNet(rental.netId, citizenId)
        DeleteEntity(entity)
        if VP_Trucker and VP_Trucker.PlayerJobEntities and VP_Trucker.PlayerJobEntities[citizenId] then
            VP_Trucker.PlayerJobEntities[citizenId].truckNetId = nil
            VP_Trucker.PlayerJobEntities[citizenId].rentalPlate = nil
        end

        local paid = true
        if refund > 0 then
            paid = Framework.AddMoney(Player, 'bank', refund, 'truck-deposit-refund')
        end
        if paid then
            MySQL.update.await('DELETE FROM trucker_rentals WHERE citizenid = ?', { citizenId })
        else
            -- crédito falhou: mantém refund_due para pagamento no próximo login/aluguel
            print(('[AUST_trucker] returnTruck: falha ao creditar $%d para %s (mantido pendente)'):format(refund, tostring(citizenId)))
            TriggerClientEvent('aurp_trucker:notify', source,
                'Não foi possível creditar o estorno agora; será pago no próximo login.', 'error')
        end

        return { success = true, deposit = rental.deposit, damagePenalty = penalty, refund = refund,
                 refundAmount = refund, damageCost = penalty }
    end)
    Busy[citizenId] = nil
    PendingLock[citizenId] = nil

    if not ok then
        print('[AUST_trucker] returnTruck erro: ' .. tostring(result))
        return { success = false, reason = 'Erro interno ao devolver.' }
    end
    return result
end)

-- Desconexão: estorno pelo dano atual, apaga o caminhão e guarda o crédito (pago no próximo login).
function TruckRentalService.OnPlayerDropped(citizenId)
    local rental = Active[citizenId]
    if not rental then return end
    Active[citizenId] = nil
    local entity = rentalEntity(rental)
    unbindNet(rental.netId, citizenId)
    local refund = computeRefund(entity, rental.deposit, rental.worstSeen)
    -- caminhão nunca apareceu no mundo (spawn do client falhou) → caução integral
    if not entity and not rental.netId then refund = rental.deposit end
    if entity then DeleteEntity(entity) end
    CreateThread(function()
        MySQL.update.await('UPDATE trucker_rentals SET refund_due = ? WHERE citizenid = ?', { refund, citizenId })
    end)
end

function TruckRentalService.OnPlayerLoaded(src, citizenId)
    local Player = Framework.GetPlayer(src)
    if not Player or not citizenId then return end
    CreateThread(function() payPending(src, Player, citizenId) end)
end

-- Boot: aluguel sem crédito calculado é de antes do restart (caminhão sumiu) → caução integral.
function TruckRentalService.Init()
    MySQL.update.await('UPDATE trucker_rentals SET refund_due = deposit WHERE refund_due IS NULL')
end

AddEventHandler('playerDropped', function()
    LastCall[source] = nil
end)

-- Sampler: registra o pior estado (lataria/motor) de cada caminhão alugado a cada 3 s. Só diminui.
CreateThread(function()
    while true do
        Wait(3000)
        local ok, err = pcall(function()
            for _, rental in pairs(Active) do
                local e = rentalEntity(rental)
                if validEntity(e) then
                    local h = math.min(GetVehicleBodyHealth(e) or 1000.0, GetVehicleEngineHealth(e) or 1000.0)
                    if h == h and (not rental.worstSeen or h < rental.worstSeen) then
                        rental.worstSeen = math.max(0.0, h)
                    end
                end
            end
        end)
        if not ok then print(('[AUST_trucker] rental sampler erro: %s'):format(tostring(err))) end
    end
end)
