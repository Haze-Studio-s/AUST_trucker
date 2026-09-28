-- =============================================================
-- AUST_trucker / server/services/parcel_service.lua
-- Parcel Delivery — Rotas multi-parada (v20.0.0)
-- Features integradas do nek_deliveryjob:
--   • Rotas com múltiplas paradas sequenciais
--   • Multiplicador de pagamento por paradas
--   • ActiveWorkers export (GetParcelWorkers / IsWorking)
--   • Webhook Discord opcional por evento
-- =============================================================

local ParcelState        = {} -- [citizenId] = { status, routeIndex, routeLabel, stops, currentStop, totalStops, startTime }
local ParcelCooldowns    = {} -- [citizenId] = os.time()
local NextStopCooldowns  = {} -- [citizenId] = GetGameTimer() — rate limit: nextStop mín 3s
local ActiveWorkers      = {} -- [citizenId] = { source, name, routeLabel, completedStops }

ParcelService = {}

---@param src number
---@return boolean ok
---@return vector3|nil pos
local function GetPlayerPositionFailClosed(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, nil
    end
    local pos = GetEntityCoords(ped)
    if pos.x == 0.0 and pos.y == 0.0 and pos.z == 0.0 then
        return false, nil
    end
    return true, pos
end

-- =====================
-- WEBHOOK (opcional)
-- =====================

local function SendParcelWebhook(title, description, color, citizenId, playerName)
    local cfg = Config.ParcelDelivery.Webhook
    if not cfg or not cfg.Enabled or not cfg.URL or cfg.URL == '' then return end

    local fields = {}
    if citizenId then
        table.insert(fields, { name = 'Jogador', value = playerName or 'Desconhecido', inline = true })
        table.insert(fields, { name = 'CID',     value = '||' .. citizenId .. '||',    inline = true })
    end

    local payload = json.encode({
        username = cfg.CommunityName or 'AURP Trucker',
        embeds   = {{
            title       = title,
            description = description,
            color       = color or 3447003,
            fields      = fields,
            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }},
    })

    PerformHttpRequest(cfg.URL, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

-- =====================
-- CALLBACKS
-- =====================

-- Aceitar missão (routeIndex = índice da rota escolhida, nil = rota aleatória 1-stop)
-- [FIX 5] Removido callback parcel:getRoutes (código morto — cliente lê config diretamente)
lib.callback.register('aurp_trucker:parcel:accept', function(source, routeIndex)
    if not GetPlayerName(source) then return nil, 'jogador_invalido' end

    local Player = Framework.GetPlayer(source)
    if not Player then return nil, 'jogador_invalido' end
    local citizenId = Framework.GetCitizenId(Player)

    -- Cooldown
    local now = os.time()
    if ParcelCooldowns[citizenId] and (now - ParcelCooldowns[citizenId]) < Config.ParcelDelivery.Cooldown then
        local remain = Config.ParcelDelivery.Cooldown - (now - ParcelCooldowns[citizenId])
        return nil, 'Aguarde ' .. remain .. 's para a próxima entrega'
    end

    -- Já em missão?
    if ParcelState[citizenId] and ParcelState[citizenId].status == 'active' then
        return nil, 'Você já tem uma entrega ativa'
    end

    -- [FIX 3] Verificar MinLevel / MaxLevel (usa DB_GetPlayerStats — global de database.lua)
    local minLv = Config.ParcelDelivery.MinLevel or 0
    local maxLv = Config.ParcelDelivery.MaxLevel or 0
    if minLv > 0 or maxLv > 0 then
        local stats = DB_GetPlayerStats(citizenId)
        local playerLevel = (stats and stats.level) or 1
        if minLv > 0 and playerLevel < minLv then
            return nil, ('Nível mínimo necessário: %d (você está no nível %d)'):format(minLv, playerLevel)
        end
        if maxLv > 0 and playerLevel > maxLv then
            return nil, ('Entregas de encomenda são para nível até %d'):format(maxLv)
        end
    end

    -- Selecionar rota
    local routes = Config.ParcelDelivery.Routes or {}
    local route, selectedIndex

    if routeIndex and routes[routeIndex] then
        route         = routes[routeIndex]
        selectedIndex = routeIndex
    else
        -- Fallback: entrega rápida com ponto aleatório (DeliveryPoints)
        local points = Config.ParcelDelivery.DeliveryPoints
        local dest   = points[math.random(1, #points)]
        route         = { label = 'Entrega Rápida', stops = { dest } }
        selectedIndex = 0
    end

    local firstStop = route.stops[1]

    ParcelState[citizenId] = {
        status      = 'active',
        routeIndex  = selectedIndex,
        routeLabel  = route.label,
        stops       = route.stops,
        currentStop = 1,
        totalStops  = #route.stops,
        startTime   = now,
    }

    -- Registrar no ActiveWorkers
    local playerName = (GetCharName and GetCharName(source)) or GetPlayerName(source) or 'Desconhecido'
    ActiveWorkers[citizenId] = {
        source         = source,
        name           = playerName,
        routeLabel     = route.label,
        completedStops = 0,
    }

    if Config.Debug then
        print(('[ParcelService] %s aceitou rota "%s" (%d paradas)'):format(
            citizenId, route.label, #route.stops))
    end

    -- Webhook: início (cor lida dentro de SendParcelWebhook para evitar crash se Webhook=nil)
    local wh = Config.ParcelDelivery.Webhook
    SendParcelWebhook(
        'Entrega Iniciada',
        ('**%s** iniciou a rota **%s** com **%d parada(s)**'):format(playerName, route.label, #route.stops),
        wh and wh.Color and wh.Color.Start or 3066993,
        citizenId, playerName
    )

    return {
        x           = firstStop.x,
        y           = firstStop.y,
        z           = firstStop.z,
        totalStops  = #route.stops,
        routeLabel  = route.label,
        currentStop = 1,
    }
end)

-- Registrar conclusão de parada e retornar coords da próxima (nil = rota completa)
lib.callback.register('aurp_trucker:parcel:nextStop', function(source)
    if not GetPlayerName(source) then return false, 'jogador_invalido' end

    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'jogador_invalido' end
    local citizenId = Framework.GetCitizenId(Player)

    -- [WARNING] Rate limit: previne spam de nextStop (mín 3 s entre chamadas)
    local now = GetGameTimer()
    if NextStopCooldowns[citizenId] and (now - NextStopCooldowns[citizenId]) < 3000 then
        return false, 'Aguarde antes de registrar a próxima parada'
    end
    NextStopCooldowns[citizenId] = now

    local state = ParcelState[citizenId]
    if not state or state.status ~= 'active' then
        return false, 'Sem entrega ativa'
    end

    -- Validar proximidade da parada atual (server-side) — fail-closed sem ped/pos válidos
    local currentDest = state.stops[state.currentStop]
    local posOk, pos = GetPlayerPositionFailClosed(source)
    if not posOk or not pos then
        return false, 'Posição inválida — tente novamente'
    end
    local stopRadius = tonumber(Config.ParcelDelivery.StopRadius) or 15.0
    local dist = #(pos - vec3(currentDest.x, currentDest.y, currentDest.z))
    if dist > stopRadius then
        return false, 'Você não está no destino'
    end

    -- Avançar parada
    state.currentStop = state.currentStop + 1

    -- Atualizar ActiveWorkers
    if ActiveWorkers[citizenId] then
        ActiveWorkers[citizenId].completedStops = state.currentStop - 1
    end

    -- Todas as paradas concluídas?
    if state.currentStop > state.totalStops then
        return true, nil  -- sinaliza ao client que é para ir ao depósito
    end

    local next = state.stops[state.currentStop]
    return true, { x = next.x, y = next.y, z = next.z, stop = state.currentStop }
end)

-- Finalizar rota completa e pagar
lib.callback.register('aurp_trucker:parcel:complete', function(source)
    if not GetPlayerName(source) then return false, 'jogador_invalido' end

    local Player = Framework.GetPlayer(source)
    if not Player then return false, 'jogador_invalido' end
    local citizenId = Framework.GetCitizenId(Player)

    local state = ParcelState[citizenId]
    if not state or state.status ~= 'active' then
        return false, 'Sem entrega ativa'
    end

    -- Todas as paradas devem ter sido concluídas
    if state.currentStop <= state.totalStops then
        return false, 'Rota incompleta'
    end

    -- Validar proximidade do depósito (server-side) — fail-closed sem ped/pos válidos
    local depot = Config.ParcelDelivery.DepotCoords
    local posOk, pos = GetPlayerPositionFailClosed(source)
    if not posOk or not pos then
        return false, 'Posição inválida — tente novamente'
    end
    local depotRadius = tonumber(Config.ParcelDelivery.DepotRadius) or 20.0
    local dist = #(pos - vec3(depot.x, depot.y, depot.z))
    if dist > depotRadius then
        return false, 'Você não está no depósito'
    end

    -- Capturar dados antes de limpar state
    local routeLabel = state.routeLabel
    local totalStops = state.totalStops
    ParcelState[citizenId]   = nil
    ActiveWorkers[citizenId] = nil
    ParcelCooldowns[citizenId] = os.time()

    -- Calcular pagamento: base * multiplicador de paradas
    local base = math.random(
        Config.ParcelDelivery.BasePayment.min,
        Config.ParcelDelivery.BasePayment.max
    )

    -- Escala de multiplicador por número de paradas
    local stopMults = { [1]=1.0, [2]=1.5, [3]=2.0, [4]=2.8, [5]=3.5 }
    local stopMult  = stopMults[totalStops] or (1.0 + (totalStops - 1) * 0.5)
    base = math.floor(base * stopMult)

    -- Decreto governamental: freight_pay modifier
    local freightMod = 1.0
    pcall(function() freightMod = exports['AUST_governo']:GetDecreeModifier('freight_pay') end)
    if freightMod ~= 1.0 then base = math.floor(base * freightMod) end

    -- Skill bonus via ProgressionService
    local skillBonus = 1.0
    if ProgressionService and ProgressionService.GetBonuses then
        local bonuses = ProgressionService.GetBonuses(citizenId)
        if bonuses and bonuses.paymentMult then
            skillBonus = bonuses.paymentMult
        end
    end

    local finalReward = math.floor(base * skillBonus)

    -- Pagar
    Framework.AddMoney(Player, Config.General.payment.currency or 'cash', finalReward, 'parcel-delivery')

    -- XP
    if ProgressionService and ProgressionService.GrantXP then
        ProgressionService.GrantXP(source, citizenId, finalReward, 1.0)
    end

    local playerName = (GetCharName and GetCharName(source)) or GetPlayerName(source) or 'Desconhecido'

    -- Webhook: conclusão
    local wh = Config.ParcelDelivery.Webhook
    SendParcelWebhook(
        'Rota Concluida',
        ('**%s** concluiu a rota **%s** (%d paradas) — Pagamento: **$%d**'):format(
            playerName, routeLabel, totalStops, finalReward),
        wh and wh.Color and wh.Color.Complete or 5763719,
        citizenId, playerName
    )

    if Config.Debug then
        print(('[ParcelService] %s completou "%s" — $%d (x%.1f paradas, skill=%.2f, decreto=%.2f)'):format(
            citizenId, routeLabel, finalReward, stopMult, skillBonus, freightMod))
    end

    return true, finalReward
end)

-- Cancelar missão ativa
lib.callback.register('aurp_trucker:parcel:cancel', function(source)
    if not GetPlayerName(source) then return false end

    local Player = Framework.GetPlayer(source)
    if not Player then return false end
    local citizenId = Framework.GetCitizenId(Player)

    local state = ParcelState[citizenId]
    if state then
        local playerName = (GetCharName and GetCharName(source)) or GetPlayerName(source) or 'Desconhecido'
        local wh = Config.ParcelDelivery.Webhook
        SendParcelWebhook(
            'Entrega Cancelada',
            ('**%s** cancelou a rota **%s**'):format(playerName, state.routeLabel or 'Desconhecida'),
            wh and wh.Color and wh.Color.Cancel or 15158332,
            citizenId, playerName
        )
    end

    ParcelState[citizenId]   = nil
    ActiveWorkers[citizenId] = nil
    return true
end)

-- =====================
-- ACTIVE WORKERS API
-- =====================

---Retorna todos os entregadores de encomendas ativos no momento
---@return table[]  [{ citizenId, source, name, routeLabel, completedStops }]
function ParcelService.GetActiveWorkers()
    local result = {}
    for cid, data in pairs(ActiveWorkers) do
        table.insert(result, {
            citizenId      = cid,
            source         = data.source,
            name           = data.name,
            routeLabel     = data.routeLabel,
            completedStops = data.completedStops,
        })
    end
    return result
end

---Verifica se um cidadão está atualmente fazendo entrega de encomendas
---@param citizenId string
---@return boolean
function ParcelService.IsWorking(citizenId)
    return ActiveWorkers[citizenId] ~= nil
end

-- =====================
-- CLEANUP
-- =====================

-- Limpar state quando o jogador sai do servidor
AddEventHandler('playerDropped', function()
    local src = source
    for cid, data in pairs(ActiveWorkers) do
        if data.source == src then
            ParcelState[cid]        = nil
            ActiveWorkers[cid]      = nil
            NextStopCooldowns[cid]  = nil
            if Config.Debug then print('[ParcelService] Player dropped — state limpo: ' .. cid) end
            break
        end
    end
end)

-- Limpar states órfãos (>30 min sem concluir)
CreateThread(function()
    while true do
        Wait(300000) -- verifica a cada 5 min
        local now = os.time()
        for cid, state in pairs(ParcelState) do
            if state.startTime and (now - state.startTime) > 1800 then
                ParcelState[cid]       = nil
                ActiveWorkers[cid]     = nil
                NextStopCooldowns[cid] = nil
                if Config.Debug then print('[ParcelService] State orfao limpo: ' .. cid) end
            end
        end
    end
end)
