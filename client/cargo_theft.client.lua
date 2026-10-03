-- client/cargo_theft.client.lua
-- Vehicle-Bound Cargo + Theft client (v14.0.0)
-- Lua 5.4 chunk — comunica com hud.client.lua via local events (TriggerEvent/AddEventHandler)

-- =====================================================
-- ESTADO LOCAL
-- =====================================================

local isMonitoring     = false   -- true quando jogador tem job ativo e monitora plate
local registeredPlate  = nil     -- plate registrada no server
local isInTruck        = false   -- true quando está como motorista no caminhão

-- Entidades com ox_target de roubo registrado (evita duplicatas)
local TheftTargets     = {}      -- entity → plate

-- Blips de cargo vulnerável
local VulnerableBlips  = {}      -- plate → blipHandle

-- Blips temporários de alerta de roubo (auto-expiram em 30s; rastreados para cleanup no stop)
local TheftAlertBlips  = {}      -- lista de blipHandle

-- Estado pending do roubo (comunicação entre InitiateTheft e theftApproved)
local PendingTheftPlate   = nil
local PendingTheftMyPlate = nil
local PendingTheftEntity  = nil

-- =====================================================
-- UTILITÁRIOS
-- =====================================================

local function GetCurrentTruckPlate()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    -- Só considera veículos de carga (trucks/trailers com modelo válido)
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    return plate ~= '' and plate or nil
end

local function GetVehicleByPlate(plate)
    local vehicles = GetGamePool('CVehicle')
    for _, v in ipairs(vehicles) do
        local p = GetVehicleNumberPlateText(v):gsub('%s+', '')
        if p == plate then return v end
    end
    return nil
end

local function RemoveTheftTarget(entity)
    if TheftTargets[entity] then
        exports.ox_target:removeLocalEntity(entity)
        TheftTargets[entity] = nil
    end
end

local function RemoveVulnerableBlip(plate)
    if VulnerableBlips[plate] then
        RemoveBlip(VulnerableBlips[plate])
        VulnerableBlips[plate] = nil
    end
end

-- =====================================================
-- OWNER SIDE — monitoramento de plate
-- =====================================================

local function StopMonitoring()
    isMonitoring    = false
    registeredPlate = nil
    isInTruck       = false
end

-- Thread de monitoramento: detecta quando jogador entra/sai do caminhão
local function StartMonitoringThread()
    CreateThread(function()
        while isMonitoring do
            Wait(2000)
            if not isMonitoring then break end

            local plate = GetCurrentTruckPlate()
            local inTruck = plate ~= nil

            if inTruck and not isInTruck then
                -- Entrou no caminhão
                isInTruck = true
                if plate ~= registeredPlate then
                    registeredPlate = plate
                    TriggerServerEvent('aurp_trucker:registerTruckPlate', plate)
                end
                TriggerServerEvent('aurp_trucker:cargoPlayerReturned', plate)

            elseif not inTruck and isInTruck then
                -- Saiu do caminhão
                isInTruck = false
                if registeredPlate then
                    TriggerServerEvent('aurp_trucker:cargoPlayerLeft', registeredPlate)
                end
            end
        end
    end)
end

-- Server → client: job aceito, iniciar monitoramento
RegisterNetEvent('aurp_trucker:client:startCargoMonitoring')
AddEventHandler('aurp_trucker:client:startCargoMonitoring', function()
    if isMonitoring then return end
    isMonitoring = true
    StartMonitoringThread()
end)

-- Job concluído normalmente ou abandonado → parar monitoramento
RegisterNetEvent('aurp_trucker:client:jobCompleted', function()
    StopMonitoring()
end)

RegisterNetEvent('aurp_trucker:client:jobAbandoned', function()
    StopMonitoring()
end)

-- Cargo roubado — job falhou
RegisterNetEvent('aurp_trucker:client:cargoStolen', function()
    lib.notify({
        title       = 'Carga Roubada',
        description = 'Sua carga foi roubada! Job cancelado.',
        type        = 'error',
        duration    = 8000,
    })
    StopMonitoring()
    TriggerEvent('aurp_trucker:client:jobAbandoned')  -- atualiza HUD/SimState
end)

-- Alerta de roubo em andamento (GPS tracker)
RegisterNetEvent('aurp_trucker:client:cargoTheftAlert', function(plate)
    lib.notify({
        title       = 'Alerta GPS',
        description = ('Sua carga (%s) está sendo roubada!'):format(plate),
        type        = 'warning',
        duration    = 10000,
        icon        = 'satellite-dish',
    })
    -- Adicionar blip na posição do caminhão
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        local blip = AddBlipForEntity(veh)
        SetBlipSprite(blip, 596)
        SetBlipColour(blip, 1)  -- vermelho
        SetBlipScale(blip, 1.2)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Sua Carga!')
        EndTextCommandSetBlipName(blip)
        table.insert(TheftAlertBlips, blip)
        Citizen.SetTimeout(30000, function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            for i = #TheftAlertBlips, 1, -1 do
                if TheftAlertBlips[i] == blip then table.remove(TheftAlertBlips, i); break end
            end
        end)
    end
end)

-- Server mandou limpar estado de vulnerabilidade (dono voltou)
RegisterNetEvent('aurp_trucker:client:cargoClear', function(plate)
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        Entity(veh).state:set('ct_vulnerable', nil, true)
    end
    RemoveVulnerableBlip(plate)
end)

-- Server ativou vulnerabilidade — owner client seta StateBag
RegisterNetEvent('aurp_trucker:client:cargoVulnerable', function(plate)
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        Entity(veh).state:set('ct_vulnerable', plate, true)
    end
end)

-- Broadcast para outros players (blip de cargo vulnerável)
RegisterNetEvent('aurp_trucker:client:cargoVulnerableOther', function(plate)
    -- Tenta encontrar o veículo para criar blip
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        if not VulnerableBlips[plate] then
            local blip = AddBlipForEntity(veh)
            SetBlipSprite(blip, 67)   -- ícone de caminhão
            SetBlipColour(blip, 49)   -- laranja
            SetBlipScale(blip, 0.8)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Carga Abandonada')
            EndTextCommandSetBlipName(blip)
            VulnerableBlips[plate] = blip
        end
    end
end)

-- Alerta de roubo para policiais
RegisterNetEvent('aurp_trucker:client:policeCargoAlert', function(zoneName)
    lib.notify({
        title       = '[CAD] Roubo de Carga',
        description = ('Roubo de carga reportado próximo a: %s'):format(zoneName),
        type        = 'warning',
        duration    = 15000,
        icon        = 'truck',
    })
end)

-- =====================================================
-- THIEF SIDE — detecta trucks vulneráveis e executa roubo
-- =====================================================

-- StateBag listener: detecta quando qualquer veículo recebe ct_vulnerable
AddStateBagChangeHandler('ct_vulnerable', nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 then return end

    if value then
        -- Veículo ficou vulnerável: adicionar ox_target
        if TheftTargets[entity] then return end  -- já tem target

        local plate = value  -- value é a plate
        TheftTargets[entity] = plate

        exports.ox_target:addLocalEntity(entity, {
            {
                name     = 'aurp_trucker:stealCargo_' .. plate,
                label    = 'Transferir Carga',
                icon     = 'fas fa-truck-ramp-box',
                distance = 3.0,
                onSelect = function()
                    InitiateTheft(entity, plate)
                end,
            }
        })
    else
        -- Cargo já não é mais vulnerável: remover ox_target
        -- Ler plate ANTES de RemoveTheftTarget, que zera TheftTargets[entity]
        local plate = TheftTargets[entity]
        RemoveTheftTarget(entity)
        if plate then RemoveVulnerableBlip(plate) end
    end
end)

-- Inicia o processo de roubo
function InitiateTheft(truckEntity, truckPlate)
    -- Validar que o ladrão tem um veículo próximo
    local ped    = PlayerPedId()
    local myVeh  = GetVehiclePedIsIn(ped, false)
    if not myVeh or myVeh == 0 then
        lib.notify({ description = 'Você precisa de um veículo para transferir a carga.', type = 'error' })
        return
    end
    if GetPedInVehicleSeat(myVeh, -1) ~= ped then
        lib.notify({ description = 'Você precisa estar no banco do motorista.', type = 'error' })
        return
    end

    -- Verificar distância client-side (validação adicional server-side)
    local truckCoords = GetEntityCoords(truckEntity)
    local myCoords    = GetEntityCoords(myVeh)
    if #(truckCoords - myCoords) > Config.CargoTheft.TheftRange then
        lib.notify({ description = ('Aproxime seu veículo a menos de %.0fm do caminhão.'):format(Config.CargoTheft.TheftRange), type = 'error' })
        return
    end

    local truckNetId = NetworkGetNetworkIdFromEntity(truckEntity)
    local myNetId    = NetworkGetNetworkIdFromEntity(myVeh)
    local myPlate    = GetVehicleNumberPlateText(myVeh):gsub('%s+', '')

    -- Solicitar aprovação ao server
    TriggerServerEvent('aurp_trucker:startCargoTheft', truckNetId, myNetId, truckPlate)

    -- Aguardar aprovação (via evento 'theftApproved')
    -- A progress bar começa somente após server confirmar
    PendingTheftPlate   = truckPlate
    PendingTheftMyPlate = myPlate
    PendingTheftEntity  = truckEntity
end

-- Server aprovou o roubo → iniciar progress bar
RegisterNetEvent('aurp_trucker:client:theftApproved', function()
    local truckPlate  = PendingTheftPlate
    local myPlate     = PendingTheftMyPlate
    local truckEntity = PendingTheftEntity
    PendingTheftPlate   = nil
    PendingTheftMyPlate = nil
    PendingTheftEntity  = nil

    if not truckPlate then return end

    local completed = lib.progressBar({
        duration    = Config.CargoTheft.TheftDuration * 1000,
        label       = 'Transferindo carga...',
        useWhileDead = false,
        canCancel   = true,
        disable     = { move = false, car = true, combat = true },
    })

    if completed then
        TriggerServerEvent('aurp_trucker:completeCargoTheft', truckPlate, myPlate)
        -- Remover ox_target imediatamente (evita duplo roubo)
        if truckEntity then RemoveTheftTarget(truckEntity) end
    else
        -- Ladrão cancelou (pressionou ESC ou moveu)
        TriggerServerEvent('aurp_trucker:cancelCargoTheft', truckPlate)
    end
end)

-- Server cancelou o roubo (dono voltou ou inválido)
RegisterNetEvent('aurp_trucker:client:theftCancelled', function()
    lib.notify({ description = 'Roubo interrompido!', type = 'error', duration = 4000 })
    -- Nota: ox_lib não expõe API para cancelar lib.progressBar externamente.
    -- Este handler serve apenas para notificar; a barra expira naturalmente.
end)

-- =====================================================
-- THIEF DELIVERY — job roubado em andamento
-- =====================================================

local stolenJobBlip   = nil

RegisterNetEvent('aurp_trucker:client:stolenJobStarted', function(data)
    if data.destCoords then
        stolenJobBlip = AddBlipForCoord(data.destCoords.x, data.destCoords.y, data.destCoords.z)
        SetBlipSprite(stolenJobBlip, 67)
        SetBlipColour(stolenJobBlip, 1)  -- vermelho
        SetBlipScale(stolenJobBlip, 0.9)
        SetBlipRoute(stolenJobBlip, true)
        SetBlipRouteColour(stolenJobBlip, 1)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Entregar Carga: ' .. (data.destName or ''))
        EndTextCommandSetBlipName(stolenJobBlip)
    end

    lib.notify({
        title       = 'Carga Transferida',
        description = ('Entregue em: %s | Bônus: +%.0f%%'):format(data.destName or '?', Config.CargoTheft.TheftBonus * 100),
        type        = 'success',
        duration    = 10000,
    })

    -- Iniciar monitoramento como dono da carga roubada
    if not isMonitoring then
        isMonitoring    = true
        registeredPlate = GetCurrentTruckPlate()
        StartMonitoringThread()
    end
end)

-- Limpar blip de stolen job quando concluído
AddEventHandler('aurp_trucker:client:jobCompleted', function()
    if stolenJobBlip then
        RemoveBlip(stolenJobBlip)
        stolenJobBlip = nil
    end
end)

-- =====================================================
-- CLEANUP no stop do resource
-- =====================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for entity, _ in pairs(TheftTargets) do
        exports.ox_target:removeLocalEntity(entity)
    end
    for _, blip in pairs(VulnerableBlips) do
        RemoveBlip(blip)
    end
    for _, blip in ipairs(TheftAlertBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    if stolenJobBlip then RemoveBlip(stolenJobBlip) end
end)
