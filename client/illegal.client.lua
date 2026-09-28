-- aurp_trucker — client/illegal.client.lua
-- Fase 3B: zonas de contato, menu de cargo ilegal, entrega, apreensão

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local illegalJobActive   = false
local illegalPlate       = nil

-- Placas com jobs ilegais ativos conhecidas por este client.
-- Populado por illegalJobStarted, removido por illegalJobEnded.
-- Usado pelo polling de re-registro para cops que chegam tarde.
local knownIllegalPlates = {}

-- ============================================================
-- ZONAS DE CONTATO
-- ============================================================

CreateThread(function()
    for _, contact in ipairs(Config.IllegalJobs.contacts) do
        local c = contact  -- captura local para closure

        exports.ox_target:addSphereZone({
            name    = 'illegal_contact_' .. c.id,
            coords  = c.coords,
            radius  = c.radius,
            options = {
                {
                    name    = 'illegal_talk_' .. c.id,
                    label   = 'Falar com Contato',
                    icon    = 'fas fa-handshake',
                    onSelect = function()
                        -- Buscar opções de cargo disponíveis neste contato
                        local options = lib.callback.await('aurp_trucker:getIllegalJobs', false, c.id)
                        if not options or #options == 0 then
                            lib.notify({ title = 'Contato', description = 'Nada disponível no momento.', type = 'inform' })
                            return
                        end

                        -- Construir menu ox_lib
                        local menuOptions = {}
                        for _, opt in ipairs(options) do
                            local o = opt  -- captura local
                            table.insert(menuOptions, {
                                title       = ('Carga: %s'):format(o.cargoLabel),
                                description = ('Pagamento estimado: %s | Destino: %s'):format(o.paymentEstimate, o.destArea),
                                onSelect    = function()
                                    local result = lib.callback.await('aurp_trucker:acceptIllegalJob', false, c.id, o.illegalType)
                                    if result and result.success then
                                        lib.notify({
                                            title       = 'Trabalho Aceito',
                                            description = ('Leve %s para %s. Pagamento: $%d.'):format(
                                                o.cargoLabel, result.jobData.destArea, result.jobData.payment),
                                            type        = 'success',
                                            duration    = 8000,
                                        })
                                        illegalJobActive = true
                                        -- Nota: plate só é registrado ao entrar no caminhão (truckStateChanged)
                                    else
                                        lib.notify({
                                            title       = 'Trabalho Indisponível',
                                            description = (result and result.reason) or 'Tente novamente.',
                                            type        = 'error',
                                        })
                                    end
                                end,
                            })
                        end

                        lib.registerContext({
                            id      = 'illegal_menu_' .. c.id,
                            title   = c.label,
                            options = menuOptions,
                        })
                        lib.showContext('illegal_menu_' .. c.id)
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- ZONAS DE ENTREGA
-- ============================================================

CreateThread(function()
    for _, delivery in ipairs(Config.IllegalJobs.deliveries) do
        local d = delivery  -- captura local

        exports.ox_target:addSphereZone({
            name    = 'illegal_delivery_' .. d.id,
            coords  = d.coords,
            radius  = d.radius,
            options = {
                {
                    name     = 'illegal_deliver_' .. d.id,
                    label    = 'Descarregar Carga Ilegal',
                    icon     = 'fas fa-boxes',
                    distance = 6.0,
                    -- Visível apenas quando job ilegal ativo (check local — não bypassable por design)
                    canInteract = function()
                        return illegalJobActive
                    end,
                    onSelect = function()
                        -- Aciona CompleteJob() em client.lua via bridge de evento (cruzamento de chunk)
                        TriggerEvent('aurp_trucker:client:triggerComplete')
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- REGISTRAR PLACA AO ENTRAR NO CAMINHÃO
-- ============================================================

-- truckStateChanged é emitido por hud.client.lua quando isTruck muda.
-- A partir da Fase 3B, o segundo argumento é a placa atual (SimState.currentPlate).
AddEventHandler('aurp_trucker:client:truckStateChanged', function(isInTruck, plate)
    if isInTruck and illegalJobActive and plate then
        TriggerServerEvent('aurp_trucker:illegalRegisterPlate', plate)
    end
end)

-- ============================================================
-- POLLING: RE-REGISTRO DE TARGET PARA COPS QUE CHEGAM TARDE
-- ============================================================

-- illegalJobStarted é broadcast único. Um cop fora de range não recebe o addLocalEntity.
-- Esta thread verifica a cada 5s se algum caminhão ilegal entrou em range de streaming.
CreateThread(function()
    while true do
        Wait(5000)
        for plate, _ in pairs(knownIllegalPlates) do
            local vehicle = GetVehicleWithNumberPlate(plate)
            if vehicle and vehicle ~= 0 then
                exports.ox_target:addLocalEntity(vehicle, {
                    {
                        name     = 'seize_illegal_cargo_' .. plate,
                        label    = 'Lacrar Carga',
                        icon     = 'fas fa-lock',
                        distance = 3.0,
                        onSelect = function()
                            TriggerServerEvent('aurp_trucker:seizeIllegalCargo', plate)
                        end,
                    }
                })
            end
        end
    end
end)

-- ============================================================
-- EVENTOS RECEBIDOS DO SERVIDOR
-- ============================================================

-- Broadcast: job ilegal iniciado — todos os clients registram ox_target no caminhão.
RegisterNetEvent('aurp_trucker:client:illegalJobStarted', function(data)
    if not data or not data.plate then return end

    -- Registrar placa no conjunto de placas conhecidas (para polling de cops tardios)
    knownIllegalPlates[data.plate] = true

    -- Atualizar estado do motorista
    local myServerId = GetPlayerServerId(PlayerId())
    if data.driverSrc == myServerId then
        illegalJobActive = true
        illegalPlate     = data.plate
    end

    -- Registrar ox_target no caminhão se já streamado
    -- Nota: GetVehicleWithNumberPlate (não GetVehicleWithPlate) é a função nativa correta
    local vehicle = GetVehicleWithNumberPlate(data.plate)
    if vehicle and vehicle ~= 0 then
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name     = 'seize_illegal_cargo_' .. data.plate,
                label    = 'Lacrar Carga',
                icon     = 'fas fa-lock',
                distance = 3.0,
                onSelect = function()
                    TriggerServerEvent('aurp_trucker:seizeIllegalCargo', data.plate)
                end,
            }
        })
    end
end)

-- Broadcast: job ilegal encerrado — todos os clients removem ox_target.
RegisterNetEvent('aurp_trucker:client:illegalJobEnded', function(data)
    if not data then return end

    -- Remover da lista de placas conhecidas
    if data.plate then
        knownIllegalPlates[data.plate] = nil

        -- Remover ox_target do caminhão (no-op se nunca foi registrado neste client)
        local vehicle = GetVehicleWithNumberPlate(data.plate)
        if vehicle and vehicle ~= 0 then
            exports.ox_target:removeLocalEntity(vehicle, { 'seize_illegal_cargo_' .. data.plate })
        end
    end

    -- Limpar estado local apenas no motorista
    local myServerId = GetPlayerServerId(PlayerId())
    if data.driverSrc == myServerId then
        illegalJobActive = false
        illegalPlate     = nil
    end
end)

-- Motorista: carga foi apreendida pelo cop
RegisterNetEvent('aurp_trucker:client:cargoSeized', function(data)
    illegalJobActive = false
    illegalPlate     = nil
    lib.notify({
        title       = 'Carga Apreendida',
        description = ('Sua carga foi lacrada e apreendida. Multa: $%d'):format(data.fine or 0),
        type        = 'error',
        duration    = 10000,
    })
end)

-- Cop: apreensão confirmada
RegisterNetEvent('aurp_trucker:client:seizureSuccess', function(data)
    local label = (Config.IllegalJobs.alertLabels and Config.IllegalJobs.alertLabels[data.illegalType])
               or data.illegalType or '?'
    lib.notify({
        title       = 'Apreensão Confirmada',
        description = ('Carga de %s lacrada com sucesso.'):format(label),
        type        = 'success',
        duration    = 6000,
    })
end)

-- ============================================================
-- CLEANUP no stop do resource
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, contact in ipairs(Config.IllegalJobs.contacts) do
        exports.ox_target:removeZone('illegal_contact_' .. contact.id)
    end
    for _, delivery in ipairs(Config.IllegalJobs.deliveries) do
        exports.ox_target:removeZone('illegal_delivery_' .. delivery.id)
    end
end)
