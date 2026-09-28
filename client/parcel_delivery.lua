-- =============================================================
-- AUST_trucker / client/parcel_delivery.lua
-- Parcel Delivery — Rotas multi-parada com NUI tracker
-- Features integradas do nek_deliveryjob:
--   • Menu de seleção de rota (ox_lib context)
--   • N paradas sequenciais por rota
--   • NUI tracker com checklist de paradas
--   • Blip atualizado por parada
-- =============================================================

if not Config.ParcelDelivery or not Config.ParcelDelivery.Enabled then return end

local ParcelActive   = false
local ParcelBlip     = nil
local DepotBlip      = nil
local DepotNPC       = nil
local CurrentStop    = 0
local TotalStops     = 0
local DeliveryZoneId = nil
local ReturnZoneId   = nil  -- [FIX] módulo-level para garantir cleanup em CancelParcelMission

-- =====================
-- NUI TRACKER
-- =====================

local function NUI_StartRoute(routeLabel, stopCount)
    SendNUIMessage({ action = 'parcel_start', routeLabel = routeLabel, amount = stopCount })
end

local function NUI_UpdateStop(stopIndex)
    -- stopIndex é 1-based no Lua; JS espera 0-based para calcular o id
    SendNUIMessage({ action = 'parcel_update_stop', index = stopIndex - 1 })
end

local function NUI_AddReturn()
    SendNUIMessage({ action = 'parcel_add_return' })
end

local function NUI_Close()
    SendNUIMessage({ action = 'parcel_close' })
end

-- =====================
-- HELPERS
-- =====================

local function ShowNotif(title, msg, nType, duration)
    lib.notify({ title = title, description = msg, type = nType or 'inform', duration = duration or 5000 })
end

local function RemoveDeliveryZone()
    if DeliveryZoneId then
        exports.ox_target:removeZone(DeliveryZoneId)
        DeliveryZoneId = nil
    end
end

local function CleanupParcel()
    if CarrySystem.IsCarrying() then CarrySystem.Stop() end
    if ParcelBlip then RemoveBlip(ParcelBlip); ParcelBlip = nil end
    RemoveDeliveryZone()
    -- [FIX] Remover zona de retorno ao depósito se ainda existir (ex: player cancela após completar stops)
    if ReturnZoneId then
        exports.ox_target:removeZone(ReturnZoneId)
        ReturnZoneId = nil
    end
    ParcelActive = false
    CurrentStop  = 0
    TotalStops   = 0
    NUI_Close()
end

local function SetDestBlip(coords, label)
    if ParcelBlip then RemoveBlip(ParcelBlip) end
    ParcelBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(ParcelBlip, 501)
    SetBlipColour(ParcelBlip, 5)
    SetBlipRoute(ParcelBlip, true)
    SetBlipScale(ParcelBlip, 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Entregar Encomenda')
    EndTextCommandSetBlipName(ParcelBlip)
end

-- =====================
-- DELIVERY STOP FLOW
-- =====================

---Configura blip + ox_target para a parada stopNum
local function GoToNextStop(stopCoords, stopNum, total)
    SetDestBlip(
        vec3(stopCoords.x, stopCoords.y, stopCoords.z),
        ('[%d/%d] Entregar Encomenda'):format(stopNum, total)
    )
    ShowNotif('Encomendas', ('[%d/%d] Leve o pacote ao destino!'):format(stopNum, total), 'inform', 6000)

    RemoveDeliveryZone()
    DeliveryZoneId = exports.ox_target:addSphereZone({
        name    = 'parcel_deliver_' .. stopNum,
        coords  = vec3(stopCoords.x, stopCoords.y, stopCoords.z),
        radius  = 2.5,
        options = {{
            name        = 'parcel_deliver',
            icon        = 'fa-solid fa-hand-holding-box',
            label       = ('[%d/%d] Entregar Encomenda'):format(stopNum, total),
            onSelect    = DeliverCurrentStop,
            canInteract = function() return ParcelActive and CarrySystem.IsCarrying() end,
        }},
    })
end

---Pickup do próximo pacote com progress bar (simulação de "tirar do saco")
local function PickupNextPackage(nextStopCoords, nextStopNum, total)
    local ok = lib.progressBar({
        duration     = (Config.ManualLoading and Config.ManualLoading.PickupDuration) or 2500,
        label        = 'Pegando próximo pacote...',
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'pickup_object', clip = 'pickup_low' },
    })

    if not ok or not ParcelActive then return end

    -- [FIX] Verificar retorno: se modelo falhar, cancelar para evitar missão presa
    if not CarrySystem.Start('small_box') then
        lib.callback.await('aurp_trucker:parcel:cancel', false)
        CleanupParcel()
        ShowNotif('Encomendas', 'Erro ao carregar pacote. Missão cancelada.', 'error')
        return
    end

    GoToNextStop(nextStopCoords, nextStopNum, total)
end

---Chamada pelo ox_target na zona de entrega de cada parada
function DeliverCurrentStop()
    if not ParcelActive or not CarrySystem.IsCarrying() then return end

    local ok = lib.progressBar({
        duration     = (Config.ManualLoading and Config.ManualLoading.DepositDuration) or 2000,
        label        = 'Entregando encomenda...',
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'anim@heists@narcotics@trash', clip = 'drop_off' },
    })

    if not ok then return end

    CarrySystem.Stop()
    RemoveDeliveryZone()
    if ParcelBlip then RemoveBlip(ParcelBlip); ParcelBlip = nil end

    -- Notificar servidor: parada concluída, obter próxima
    local cbOk, success, nextStop = pcall(lib.callback.await, 'aurp_trucker:parcel:nextStop', false)

    if not cbOk or not success then
        ShowNotif('Encomendas', (not cbOk and 'Servidor indisponível') or nextStop or 'Erro ao registrar entrega', 'error')
        CleanupParcel()
        return
    end

    -- Marcar parada atual como concluída no NUI
    NUI_UpdateStop(CurrentStop)
    CurrentStop = CurrentStop + 1

    -- nextStop == nil → todas as paradas concluídas, retornar ao depósito
    if nextStop == nil then
        NUI_AddReturn()
        ShowNotif('Encomendas', 'Rota concluída! Retorne ao depósito.', 'success', 8000)

        local depot = Config.ParcelDelivery.DepotCoords
        SetDestBlip(vec3(depot.x, depot.y, depot.z), 'Retornar ao Depósito')

        -- Zona de devolução no depósito — armazenada em ReturnZoneId para cleanup seguro
        ReturnZoneId = exports.ox_target:addSphereZone({
            name    = 'parcel_return',
            coords  = vec3(depot.x, depot.y, depot.z),
            radius  = 5.0,
            options = {{
                name        = 'parcel_return_confirm',
                icon        = 'fa-solid fa-clipboard-check',
                label       = 'Finalizar Rota de Entregas',
                onSelect    = function()
                    local zoneRef = ReturnZoneId
                    ReturnZoneId  = nil
                    FinishRoute(zoneRef)
                end,
                canInteract = function() return ParcelActive end,
            }},
        })
        return
    end

    -- Há próxima parada: pickup do pacote seguinte
    ShowNotif('Encomendas', ('[%d/%d] Pegue o próximo pacote!'):format(CurrentStop, TotalStops), 'inform', 4000)
    PickupNextPackage(nextStop, CurrentStop, TotalStops)
end

---Finalizar rota após retornar ao depósito
function FinishRoute(returnZoneId)
    if not ParcelActive then return end

    exports.ox_target:removeZone(returnZoneId)
    if ParcelBlip then RemoveBlip(ParcelBlip); ParcelBlip = nil end

    local cbOk, ok, reward = pcall(lib.callback.await, 'aurp_trucker:parcel:complete', false)
    if not cbOk then
        ShowNotif('Encomendas', 'Servidor indisponível ao finalizar rota', 'error')
    elseif ok then
        ShowNotif('Encomendas', ('Rota concluída! Ganhou $%d'):format(reward or 0), 'success', 8000)
    else
        ShowNotif('Encomendas', reward or 'Erro ao finalizar rota', 'error')
    end

    CleanupParcel()
end

-- =====================
-- ACCEPT MISSION
-- =====================

function AcceptParcelMission(routeIndex)
    if ParcelActive then
        return ShowNotif('Encomendas', 'Você já tem uma entrega ativa!', 'error')
    end

    local cbOk, result, err = pcall(lib.callback.await, 'aurp_trucker:parcel:accept', false, routeIndex)
    if not cbOk or not result then
        return ShowNotif('Encomendas', (not cbOk and 'Servidor indisponível') or err or 'Erro ao aceitar missão', 'error')
    end

    ParcelActive = true
    CurrentStop  = 1
    TotalStops   = result.totalStops

    -- Iniciar NUI tracker
    NUI_StartRoute(result.routeLabel, result.totalStops)
    ShowNotif('Encomendas', ('Rota "%s" iniciada! %d paradas.'):format(result.routeLabel, result.totalStops), 'success', 6000)

    -- Pickup do primeiro pacote no depósito
    local pickupOk = lib.progressBar({
        duration     = (Config.ManualLoading and Config.ManualLoading.PickupDuration) or 3000,
        label        = 'Pegando primeiro pacote...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'pickup_object', clip = 'pickup_low' },
    })

    if not pickupOk then
        lib.callback.await('aurp_trucker:parcel:cancel', false)
        CleanupParcel()
        return ShowNotif('Encomendas', 'Entrega cancelada.', 'error')
    end

    -- [FIX] Verificar retorno: modelo pode falhar em casos raros
    if not CarrySystem.Start('small_box') then
        lib.callback.await('aurp_trucker:parcel:cancel', false)
        CleanupParcel()
        return ShowNotif('Encomendas', 'Erro ao carregar pacote. Tente novamente.', 'error')
    end

    GoToNextStop(vec3(result.x, result.y, result.z), 1, result.totalStops)
end

-- =====================
-- ROUTE SELECTION MENU
-- =====================

local function OpenRouteMenu()
    if ParcelActive then
        return ShowNotif('Encomendas', 'Você já tem uma entrega ativa!', 'error')
    end

    local routes = Config.ParcelDelivery.Routes or {}

    -- Sem rotas configuradas: fallback para ponto aleatório
    if #routes == 0 then
        AcceptParcelMission(nil)
        return
    end

    local options = {}
    for i, route in ipairs(routes) do
        local n = #route.stops
        -- Multiplicadores espelhando a lógica do servidor
        local mults = { [1]=1.0, [2]=1.5, [3]=2.0, [4]=2.8, [5]=3.5 }
        local mult  = mults[n] or (1.0 + (n - 1) * 0.5)
        local minPay = math.floor(Config.ParcelDelivery.BasePayment.min * mult)
        local maxPay = math.floor(Config.ParcelDelivery.BasePayment.max * mult)

        table.insert(options, {
            title       = route.label,
            description = (n == 1) and '1 parada' or (n .. ' paradas'),
            icon        = route.icon or 'fa-solid fa-route',
            metadata    = {
                { label = 'Paradas',   value = n },
                { label = 'Pagamento', value = ('$%d – $%d'):format(minPay, maxPay) },
            },
            onSelect = function() AcceptParcelMission(i) end,
        })
    end

    lib.registerContext({ id = 'parcel_route_select', title = 'Selecionar Rota de Entrega', options = options })
    lib.showContext('parcel_route_select')
end

function CancelParcelMission()
    pcall(lib.callback.await, 'aurp_trucker:parcel:cancel', false)
    CleanupParcel()
    ShowNotif('Encomendas', 'Entrega cancelada.', 'error')
end

-- Morte em jogo cancela a missão ativa para evitar deadlock (caixa some, zona inacessível)
AddEventHandler('baseevents:onPlayerKilled', function()
    if not ParcelActive then return end
    pcall(lib.callback.await, 'aurp_trucker:parcel:cancel', false)
    CleanupParcel()
    ShowNotif('Encomendas', 'Você foi eliminado. Entrega perdida.', 'error')
end)

-- =====================
-- DEPOT SETUP
-- =====================

local function SetupDepot()
    local cfg = Config.ParcelDelivery

    -- Blip permanente do depósito
    DepotBlip = AddBlipForCoord(cfg.DepotCoords.x, cfg.DepotCoords.y, cfg.DepotCoords.z)
    SetBlipSprite(DepotBlip, cfg.DepotBlip.sprite)
    SetBlipColour(DepotBlip, cfg.DepotBlip.color)
    SetBlipScale(DepotBlip, cfg.DepotBlip.scale)
    SetBlipAsShortRange(DepotBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.DepotBlip.label)
    EndTextCommandSetBlipName(DepotBlip)

    -- NPC
    local model = joaat(cfg.DepotNPC)
    lib.requestModel(model, 5000)
    DepotNPC = CreatePed(4, model,
        cfg.DepotCoords.x, cfg.DepotCoords.y, cfg.DepotCoords.z - 1.0,
        cfg.DepotCoords.w, false, true)
    SetEntityAsMissionEntity(DepotNPC, true, true)
    SetBlockingOfNonTemporaryEvents(DepotNPC, true)
    FreezeEntityPosition(DepotNPC, true)
    SetEntityInvincible(DepotNPC, true)
    SetModelAsNoLongerNeeded(model)

    -- ox_target no NPC: menu de rotas + cancelar
    exports.ox_target:addLocalEntity(DepotNPC, {
        {
            name        = 'parcel_start',
            icon        = 'fa-solid fa-box',
            label       = 'Aceitar Rota de Encomendas',
            onSelect    = OpenRouteMenu,
            canInteract = function() return not ParcelActive end,
        },
        {
            name        = 'parcel_cancel',
            icon        = 'fa-solid fa-xmark',
            label       = 'Cancelar Entrega',
            onSelect    = CancelParcelMission,
            canInteract = function() return ParcelActive end,  -- [FIX] permite cancelar mesmo carregando caixa; CleanupParcel() já chama CarrySystem.Stop()
        },
    })
end

-- =====================
-- INIT / CLEANUP
-- =====================

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetupDepot()
end)

AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CleanupParcel()
    if DepotBlip then RemoveBlip(DepotBlip) end
    if DepotNPC and DoesEntityExist(DepotNPC) then
        exports.ox_target:removeLocalEntity(DepotNPC)
        DeleteEntity(DepotNPC)
    end
end)
