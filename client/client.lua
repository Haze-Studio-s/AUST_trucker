-- =======================================
-- AURP_TRUCKER CLIENT - SISTEMA COM BLIPS
-- =======================================

-- =======================================
-- VARIÁVEIS GLOBAIS
-- =======================================

local currentJob = nil
local currentTrailer = nil
local jobProgress = {
    stage = nil, -- 'none', 'pickup', 'delivering'
    startTime = nil,
    pickupBlip = nil,
    deliveryBlip = nil
}
local playerStats = {
    totalEarnings = 0,
    totalDeliveries = 0,
    totalDistance = 0
}
local blips = {}
local locationBlips = { pickup = nil, delivery = nil }
local isNUIOpen = false
local nearbyInteractions = {}

-- Fase 5: Forklift — escritos por forklift.client.lua
VP_Trucker_ForkliftActive       = nil  -- { locationId, mode } | nil
VP_Trucker_CurrentJobOriginId   = nil  -- origin_id do job ativo | nil

-- =======================================
-- FUNÇÕES UTILITÁRIAS
-- =======================================

local function ShowNotification(title, description, type, duration)
    SendNUIMessage({
        action = 'showNotification',
        title = title,
        description = description,
        type = type or 'info',
        duration = duration or 5000
    })
end

local function SafeGetNetworkId(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local timeout = 100
    while not NetworkGetEntityIsNetworked(entity) and timeout > 0 do
        NetworkRegisterEntityAsNetworked(entity)
        Wait(10)
        timeout = timeout - 1
    end
    if NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if netId and netId ~= 0 then
            SetNetworkIdCanMigrate(netId, true)
            SetNetworkIdExistsOnAllMachines(netId, true)
            return netId
        end
    end
    return nil
end

local pickupPoint = nil
local deliveryPoint = nil
local contractStopPoint = nil
local lcActiveJob = nil
local lcDeliveryPoint = nil
local lcDeliveryBlip = nil
local isStartingJob = false

local function CleanupLCContract()
    isStartingJob = false
    if lcDeliveryPoint then
        pcall(function() lcDeliveryPoint:remove() end)
        lcDeliveryPoint = nil
    end
    if lcDeliveryBlip and DoesBlipExist(lcDeliveryBlip) then
        RemoveBlip(lcDeliveryBlip)
        lcDeliveryBlip = nil
    end
    SetWaypointOff()
    if lib and lib.hideTextUI then
        lib.hideTextUI()
    end

    if lcActiveJob then
        if lcActiveJob.trailer and DoesEntityExist(lcActiveJob.trailer) then
            DeleteEntity(lcActiveJob.trailer)
        end
        if lcActiveJob.truck and DoesEntityExist(lcActiveJob.truck) then
            DeleteEntity(lcActiveJob.truck)
        end
        lcActiveJob = nil
    end
end

local function ClearJobPoints()
    CleanupLCContract()
    if pickupPoint then
        pcall(function() pickupPoint:remove() end)
        pickupPoint = nil
    end
    if deliveryPoint then
        pcall(function() deliveryPoint:remove() end)
        deliveryPoint = nil
    end
    if lib and lib.hideTextUI then
        lib.hideTextUI()
    end
end

local function CreateBlip(coords, sprite, color, label, scale, route)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, scale or 0.8)
    SetBlipColour(blip, color)
    SetBlipAsShortRange(blip, not route)

    if route then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, color)
    end

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function CreateGroundMarker(coords, r, g, b, a)
    DrawMarker(
        1, -- tipo: cilindro (marker padrão do GTA)
        coords.x, coords.y, coords.z - 1.0, -- no chão
        0.0, 0.0, 0.0, -- direction
        0.0, 0.0, 0.0, -- rotation
        2.0, 2.0, 1.0, -- scale (diâmetro e altura)
        r, g, b, a, -- color
        false, true, 2, false, nil, nil, false
    )
end

-- Detecção autoritativa de desobstrução de vaga de spawn (anti-sobreposição)
local function GetSafeSpawnCoords(baseCoords, radius)
    radius = radius or 4.5
    if not IsPositionOccupied(baseCoords.x, baseCoords.y, baseCoords.z, radius, false, true, true, false, false, 0, false) then
        return baseCoords
    end

    local offsets = {
        vector4(baseCoords.x + 3.5, baseCoords.y, baseCoords.z, baseCoords.w or 0.0),
        vector4(baseCoords.x - 3.5, baseCoords.y, baseCoords.z, baseCoords.w or 0.0),
        vector4(baseCoords.x, baseCoords.y + 6.0, baseCoords.z, baseCoords.w or 0.0),
        vector4(baseCoords.x, baseCoords.y - 6.0, baseCoords.z, baseCoords.w or 0.0),
        vector4(baseCoords.x + 5.0, baseCoords.y + 5.0, baseCoords.z, baseCoords.w or 0.0),
    }

    for _, testPos in ipairs(offsets) do
        if not IsPositionOccupied(testPos.x, testPos.y, testPos.z, radius, false, true, true, false, false, 0, false) then
            return testPos
        end
    end

    return nil
end

-- Concessão autoritativa de chaves (qbx_vehiclekeys/qb-vehiclekeys) e combustível (ox_fuel/cdn-fuel/StateBag)
local function GiveVehicleKeysAndFuel(vehicle, plate, fuelLevel)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    fuelLevel = fuelLevel or 100.0

    -- 1. Combustível
    Entity(vehicle).state.fuel = fuelLevel
    SetVehicleFuelLevel(vehicle, fuelLevel)
    if GetResourceState('ox_fuel') == 'started' then
        pcall(function() exports['ox_fuel']:setFuel(vehicle, fuelLevel) end)
    elseif GetResourceState('cdn-fuel') == 'started' then
        pcall(function() exports['cdn-fuel']:SetFuel(vehicle, fuelLevel) end)
    end

    -- 2. Chaves
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(plate) end)
        if netId and netId ~= 0 then
            TriggerServerEvent('qbx_vehiclekeys:server:tookKeys', netId)
        end
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
    end
end

local function SpawnTrailer(model, coords)
    -- Verificar ocupação de vaga
    local safeCoords = GetSafeSpawnCoords(coords, 5.0)
    if not safeCoords then
        lib.notify({
            title = 'Doca Bloqueada',
            description = 'A vaga de spawn está ocupada por outro veículo. Desobstrua a área.',
            type = 'error',
            duration = 7000
        })
        return nil
    end

    local modelHash = GetHashKey(model)
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 5000 do
        Wait(100)
        timeout = timeout + 100
    end

    if not HasModelLoaded(modelHash) then
        if Config.Debug then
            print("^1[AURP_TRUCKER ERROR]^7 Falha ao carregar modelo: " .. model)
        end
        return nil
    end

    local trailer = CreateVehicle(modelHash, safeCoords.x, safeCoords.y, safeCoords.z, safeCoords.w, true, false)

    if trailer and trailer ~= 0 then
        local plate = "AURP" .. math.random(1000, 9999)
        SetVehicleEngineOn(trailer, false, false, false)
        SetVehicleNumberPlateText(trailer, plate)
        SetEntityAsMissionEntity(trailer, true, true)
        SetModelAsNoLongerNeeded(modelHash)

        -- Registrar entidades no servidor para cleanup autoritativo em playerDropped ou abandono
        local trlNetId = SafeGetNetworkId(trailer)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local vehNetId = (veh ~= 0 and DoesEntityExist(veh)) and SafeGetNetworkId(veh) or nil
        TriggerServerEvent('aurp_trucker:server:registerJobEntities', vehNetId, trlNetId)

        return trailer
    else
        SetModelAsNoLongerNeeded(modelHash)
        return nil
    end
end

local function GetPlayerTrailer()
    -- 1. Se houver trailer criado no ciclo atual
    if currentTrailer and DoesEntityExist(currentTrailer) then
        return currentTrailer
    end

    -- 2. Checagem autoritativa do veículo acoplado via natives do GTA
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle and vehicle ~= 0 then
        local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)
        if (hasTrailer == 1 or hasTrailer == true) and trailer and trailer ~= 0 and DoesEntityExist(trailer) then
            currentTrailer = trailer
            return trailer
        end
        if IsVehicleAttachedToTrailer(vehicle) then
            local _, attachedTrl = GetVehicleTrailerVehicle(vehicle)
            if attachedTrl and attachedTrl ~= 0 and DoesEntityExist(attachedTrl) then
                currentTrailer = attachedTrl
                return attachedTrl
            end
        end
    end

    return nil
end

local function GetTrailerType(trailer)
    if not trailer or not DoesEntityExist(trailer) then
        if Config.Debug then
            print("^1[AURP_TRUCKER]^7 DEBUG GetTrailerType: Trailer inválido ou não existe")
        end
        return nil
    end

    local trailerModel = GetEntityModel(trailer)
    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 DEBUG GetTrailerType: Modelo do trailer = " .. tostring(trailerModel))
    end

    local modelHashes = {
        [GetHashKey('tanker')] = 'tanker',
        [GetHashKey('trailers')] = 'trailers',
        [GetHashKey('trailers2')] = 'trailers2'
    }

    local detectedType = modelHashes[trailerModel]
    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 DEBUG GetTrailerType: Tipo detectado = " .. tostring(detectedType))
        if not detectedType then
            print("^1[AURP_TRUCKER]^7 DEBUG GetTrailerType: Modelo não reconhecido! Hash = " .. tostring(trailerModel))
            print("^1[AURP_TRUCKER]^7 DEBUG GetTrailerType: Hash esperados: tanker=" .. GetHashKey('tanker') .. ", trailers=" .. GetHashKey('trailers') .. ", trailers2=" .. GetHashKey('trailers2'))
        end
    end

    return detectedType
end

local function ShowHelpText(text)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function DrawText3D(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z + 1.0)
    local pX, pY, pZ = table.unpack(GetGameplayCamCoords())

    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(true)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

-- =======================================
-- SISTEMA DE SINCRONIZAÇÃO COM SERVIDOR
-- =======================================

local serverJobs = {}

-- Função para solicitar jobs do servidor
-- ============================================================
-- EVENTOS DO SERVIDOR (v17 — prefixo aurp_trucker:)
-- ============================================================

-- Job aceito pelo servidor — iniciar no cliente
RegisterNetEvent('aurp_trucker:client:jobStarted', function(job)
    -- Mapear campos do server para o formato que StartJob espera
    local mapped = {
        id         = job.jobId or job.id,
        cargo      = job.cargoItem or job.cargo,
        trailer    = job.trailerModel or job.trailer,
        payment    = job.payment,
        distance   = job.distance or 0,
        originId   = job.originId,
        cargoQty   = job.cargoQty or 1,
        weight     = job.weight or 80,
        loadTime   = job.loadTime or 6000,
        unloadTime = job.unloadTime or 6000,
        pickup   = job.pickup or {
            name   = job.originName,
            coords = job.originCoords,
        },
        delivery = job.delivery or {
            name   = job.destName,
            coords = job.destCoords,
        },
        company  = job.company,
    }
    local success = StartJob(mapped)
    if not success then
        -- StartJob falhou (trailer incompatível, etc.) — liberar slot no servidor
        TriggerServerEvent('aurp_trucker:abandonJob')
    end
end)

-- Notificação genérica do servidor (suporta chamadas com 2 ou 3 argumentos)
RegisterNetEvent('aurp_trucker:notify', function(arg1, arg2, arg3)
    local title, message, notifType
    if arg3 ~= nil then
        title = tostring(arg1 or 'Logística')
        message = tostring(arg2 or '')
        notifType = arg3 or 'inform'
    else
        message = tostring(arg1 or '')
        notifType = arg2 or 'inform'
        if notifType == 'error' then
            title = 'Erro de Logística'
        elseif notifType == 'success' then
            title = 'Sucesso'
        else
            title = 'Aviso'
        end
    end
    lib.notify({ title = title, description = message, type = notifType })
end)

-- Atualização de empresa: companyInfo = tabela → entrou/atualizou; nil → saiu
RegisterNetEvent('aurp_trucker:client:companyUpdated', function(companyInfo)
    SendNUIMessage({ action = 'updateCompany', company = companyInfo or nil })
end)


-- =======================================
-- SISTEMA NUI
-- =======================================



local function CloseJobBoard()
    isNUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', hidemenu = true })
end

local function OpenJobBoard()
    if isNUIOpen then return end

    -- Buscar dados ANTES de ativar NUI focus
    local ok, data = pcall(lib.callback.await, 'aurp_trucker:getInitialData', false)
    if not ok or not data then
        lib.notify({ title = 'Erro', description = 'Não foi possível conectar ao servidor.', type = 'error' })
        return
    end

    isNUIOpen = true
    SetNuiFocus(true, true)

    local lcDados = data.lc_dados or data
    if type(lcDados) ~= 'table' then lcDados = {} end
    if not lcDados.config then
        lcDados.config = {
            cooldown = 2,
            max_emprestimo = 400000,
            party = { price_to_create = 500, max_members = 4, price_per_member = 100 },
            loans = { plans = {}, payment_interval_hours = 24 },
            dealership = Config.LC_Dealership or {},
            repair_price = Config.LC_RepairPrice or { engine = 100, transmission = 100, wheels = 100, body = 100, fuel = 10 },
            player_level = 0,
        }
    end
    if (not lcDados.trucker_available_contracts or #lcDados.trucker_available_contracts == 0) and data.jobs and #data.jobs > 0 then
        lcDados.trucker_available_contracts = {}
        for i, j in ipairs(data.jobs) do
            table.insert(lcDados.trucker_available_contracts, {
                contract_id = i,
                contract_name = (j.originName and j.destName) and (j.originName .. " -> " .. j.destName) or (j.cargoItem or "Carga Geral"),
                contract_type = (i % 2 == 0) and 1 or 0,
                distance = tonumber(j.distance) or 5.0,
                reward = tonumber(j.basePayment) or 1500,
                truck = "hauler",
                trailer = j.trailerModel or "docktrailer",
                cargo_type = 0,
                fragile = 0,
                valuable = 0,
                fast = 0,
                illegal = 0,
            })
        end
    end

    -- Detectar idioma e formato ativo (Prioridade: config vinda do servidor -> Config.locale -> Config.lang -> "br")
    local activeLocale = (lcDados and lcDados.config and lcDados.config.locale) or Config.locale or Config.lang or "br"
    local activeFormat = (lcDados and lcDados.config and lcDados.config.format) or Config.format or { lang = activeLocale, currency = "USD", location = "pt-BR" }

    -- Enviar para a interface oficial LC Truck Logistics
    SendNUIMessage({
        showmenu     = true,
        update       = false,
        dados        = lcDados,
        utils        = {
            config = {
                locale = activeLocale,
                format = activeFormat,
            },
            lang = {}
        },
        resourceName = GetCurrentResourceName(),
        -- Retrocompatibilidade
        action       = 'open',
        jobs         = data.jobs or {},
        company      = data.company,
        activeJob    = data.activeJob,
        stats        = data.stats,
        playerName   = data.playerName,
        playerMoney  = data.playerMoney,
    })
end

-- Backspace fecha a UI (ESC é reservado pelo FiveM para pause menu)
RegisterCommand('+trucker_close_ui', function()
    if isNUIOpen then
        CloseJobBoard()
    end
end, false)
RegisterCommand('-trucker_close_ui', function() end, false)
RegisterKeyMapping('+trucker_close_ui', 'Fechar painel caminhoneiro', 'keyboard', 'BACK')

local function RefreshNUIData()
    if not isNUIOpen then return end
    SetTimeout(350, function()
        if not isNUIOpen then return end
        local ok, data = pcall(lib.callback.await, 'aurp_trucker:getInitialData', false)
        if ok and data then
            local lc = data.lc_dados or data
            local activeLocale = (lc and lc.config and lc.config.locale) or Config.locale or Config.lang or "br"
            local activeFormat = (lc and lc.config and lc.config.format) or Config.format or { lang = activeLocale, currency = "USD", location = "pt-BR" }
            SendNUIMessage({
                update = true,
                dados = lc,
                utils = {
                    config = {
                        locale = activeLocale,
                        format = activeFormat,
                    }
                }
            })
        end
    end)
end

-- NUI Callbacks: Protocolo LC Logistics (Utils.post)
RegisterNUICallback('post', function(body, cb)
    local event = body and body.event
    local data  = body and body.data

    if event == "close" then
        CloseJobBoard()
        SetNuiFocus(false, false)
        cb(200)
        return
    end

    if event == "startContract" then
        CloseJobBoard()
        SetNuiFocus(false, false)
        if lcActiveJob or isStartingJob then return cb(200) end
        isStartingJob = true
        SetTimeout(3000, function() isStartingJob = false end)
        local contractId = data and (data.id or data.contract_id or data.contractId or data.jobId)
        TriggerServerEvent('aurp_trucker:server:startLCContract', contractId)
        cb(200)
        return
    end

    if event == "cancelContract" then
        ExecuteCommand('canceljob')
        TriggerServerEvent('truck_logistics:cancelContract', 'buccaneer_hq', data)
        cb(200)
        return
    end

    if event == "buyTruck" then
        local truckName = data and (data.truck_name or data.model or data.name)
        TriggerServerEvent('aurp_trucker:fleet:buyTruck', truckName)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "sellTruck" then
        local truckId = data and (data.truck_id or data.truckId or data.id)
        TriggerServerEvent('aurp_trucker:fleet:sellTruck', truckId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "repairTruck" then
        local truckId = data and (data.id or data.truck_id)
        TriggerServerEvent('aurp_trucker:fleet:repairTruck', truckId, 'all')
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "upgradeSkill" then
        local skillId = data and data.id
        TriggerServerEvent('aurp_trucker:server:upgradeSkill', skillId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "loan" then
        local planId = data and data.loan_id
        TriggerServerEvent('aurp_trucker:loan:takePlan', planId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "payLoan" then
        local loanId = data and data.loan_id
        TriggerServerEvent('aurp_trucker:loan:payOff', loanId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "hireDriver" then
        local driverId = data and data.driver_id
        TriggerServerEvent('aurp_trucker:driver:hireAgency', driverId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "fireDriver" then
        local driverId = data and data.driver_id
        TriggerServerEvent('aurp_trucker:driver:fireHired', driverId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "setDriver" then
        local driverId = data and data.driver_id
        local truckId = data and data.truck_id
        TriggerServerEvent('aurp_trucker:driver:setTruck', driverId, truckId)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "depositMoney" then
        local amount = data and data.amount
        TriggerServerEvent('aurp_trucker:bank:deposit', amount)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "withdrawMoney" then
        local amount = data and data.amount
        TriggerServerEvent('aurp_trucker:bank:withdraw', amount)
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "createParty" then
        TriggerServerEvent('aurp_trucker:party:create')
        RefreshNUIData()
        cb(200)
        return
    end

    if event == "quitParty" or event == "deleteParty" then
        TriggerServerEvent('aurp_trucker:party:leave')
        RefreshNUIData()
        cb(200)
        return
    end

    cb(200)
end)

RegisterNUICallback('startJob', function(data, cb)
    CloseJobBoard()
    SetNuiFocus(false, false)
    if lcActiveJob or isStartingJob then return cb('ok') end
    isStartingJob = true
    SetTimeout(3000, function() isStartingJob = false end)
    local contractId = data and (data.id or data.contract_id or data.contractId or data.jobId)
    TriggerServerEvent('aurp_trucker:server:startLCContract', contractId)
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    CloseJobBoard()
    cb('ok')
end)

RegisterNUICallback('closeUI', function(data, cb)
    CloseJobBoard()
    cb('ok')
end)

RegisterNUICallback('rentTruck', function(data, cb)
    local model = data and data.model
    if not model then return cb({ ok = false, reason = 'Modelo inválido' }) end
    local ok, res = pcall(lib.callback.await, 'aurp_trucker:rental:rentTruck', false, model)
    if ok and res and res.success then
        local spawnCoords = res.spawnCoords or Config.TruckRental.spawnCoords
        local heading = spawnCoords.w or 0.0
        lib.requestModel(model)
        local veh = CreateVehicle(joaat(model), spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, false)
        SetVehicleNumberPlateText(veh, res.plate)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleHasBeenOwnedByPlayer(veh, true)
        SetVehicleNeedsToBeHotwired(veh, false)
        if exports.qbx_vehiclekeys then pcall(function() exports.qbx_vehiclekeys:GiveKeys(veh) end) end
        if exports.ox_fuel then pcall(function() exports.ox_fuel:SetFuel(veh, 100.0) end) end
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('aurp_trucker:rental:registerNetId', netId)
        lib.notify({ title = 'Locadora', description = ('Caminhão alugado! Placa: %s'):format(res.plate), type = 'success' })
        cb({ ok = true, rental = res })
    else
        local reason = (res and res.reason) or 'Falha ao alugar caminhão'
        lib.notify({ title = 'Locadora', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('returnTruck', function(data, cb)
    local ped = cache.ped
    local veh = GetVehiclePedIsIn(ped, false)
    local bodyHealth = 1000.0
    local engineHealth = 1000.0
    if veh ~= 0 then
        bodyHealth = GetVehicleBodyHealth(veh)
        engineHealth = GetVehicleEngineHealth(veh)
    end
    local ok, res = pcall(lib.callback.await, 'aurp_trucker:rental:returnTruck', false, {
        bodyHealth = bodyHealth,
        engineHealth = engineHealth,
    })
    if ok and res and res.success then
        if veh ~= 0 then
            DeleteEntity(veh)
        end
        lib.notify({
            title = 'Locadora',
            description = ('Caminhão devolvido!\nCaução estornada: R$ %d (Avarias deduzidas: R$ %d)'):format(res.refundAmount, res.damageCost),
            type = 'success'
        })
        cb({ ok = true, result = res })
    else
        local reason = (res and res.reason) or 'Nenhum caminhão alugado para devolver.'
        lib.notify({ title = 'Locadora', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('acceptJob', function(data, cb)
    local jobId = data.jobId

    if not jobId then
        lib.notify({ title = 'Erro', description = 'ID do trabalho inválido', type = 'error' })
        cb('ok')
        return
    end

    -- Fechar UI imediatamente para jogador ver o mapa
    CloseJobBoard()

    -- Enviar para servidor para aceitar o job
    TriggerServerEvent('aurp_trucker:acceptJob', jobId)

    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 Solicitando job ao servidor: " .. jobId)
    end

    cb('ok')
end)

RegisterNUICallback('spawnTrailer', function(data, cb)
    local model = data.model
    SpawnPlayerTrailer(model)
    cb('ok')
end)

RegisterNUICallback('markLocation', function(data, cb)
    local coords = data.coords
    local label = data.label
    local blipType = data.type

    -- Remover blips antigos do mesmo tipo
    if blipType == 'pickup' and locationBlips.pickup then
        RemoveBlip(locationBlips.pickup)
        locationBlips.pickup = nil
    elseif blipType == 'delivery' and locationBlips.delivery then
        RemoveBlip(locationBlips.delivery)
        locationBlips.delivery = nil
    end

    -- Criar novo blip
    local sprite = blipType == 'pickup' and 478 or 473
    local color = blipType == 'pickup' and 2 or 3
    local blip = CreateBlip(coords, sprite, color, label, 0.8, true)

    -- Guardar referência ao blip
    if blipType == 'pickup' then
        locationBlips.pickup = blip
    else
        locationBlips.delivery = blip
    end

    ShowNotification(
        'Localização Marcada',
        'Verifique o GPS para a rota até ' .. label,
        'success'
    )

    cb('ok')
end)

RegisterNUICallback('createCompany', function(data, cb)
    local name = data.name or ''
    local companyType = data.companyType or 'logistics'

    if name == '' then
        cb('ok')
        return
    end

    TriggerServerEvent('aurp_trucker:createCompany', name, companyType)
    cb('ok')
end)

RegisterNUICallback('joinCompany', function(data, cb)
    local companyId = data.companyId

    if not companyId then
        ShowNotification(
            'Erro',
            'ID da empresa inválido',
            'error'
        )
        cb('ok')
        return
    end

    TriggerServerEvent('aurp_trucker:joinCompany', companyId)
    cb('ok')
end)

RegisterNUICallback('toggleRecruiting', function(data, cb)
    -- L-01: data.isRecruiting não é enviado ao server (estado é derivado server-side)
    TriggerServerEvent('aurp_trucker:toggleRecruiting')
    cb('ok')
end)

-- =======================================
-- NUI CALLBACKS: LC TRUCK LOGISTICS
-- =======================================

RegisterNUICallback('buyTruck', function(data, cb)
    local model = data and (data.model or data.truck_name or data.name)
    if not model then return cb({ ok = false, reason = 'Modelo inválido' }) end
    local ok, res, extra = pcall(lib.callback.await, 'aurp_trucker:buyTruck', false, model)
    if ok and res then
        lib.notify({ title = 'Concessionária', description = 'Caminhão adquirido com sucesso!', type = 'success' })
        RefreshNUIData()
        cb({ ok = true, truck = extra })
    else
        local reason = (type(extra) == 'string' and extra) or (type(res) == 'string' and res) or 'Erro ao comprar caminhão'
        lib.notify({ title = 'Concessionária', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('sellTruck', function(data, cb)
    local truckId = data and (data.truckId or data.truck_id or data.id)
    if not truckId then return cb({ ok = false, reason = 'ID inválido' }) end
    local ok, res, refund = pcall(lib.callback.await, 'aurp_trucker:sellTruck', false, truckId)
    if ok and res then
        lib.notify({ title = 'Garagem', description = ('Caminhão vendido por $%d!'):format(refund or 0), type = 'success' })
        RefreshNUIData()
        cb({ ok = true, refund = refund })
    else
        local reason = (type(refund) == 'string' and refund) or 'Erro ao vender veículo'
        lib.notify({ title = 'Garagem', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('repairTruck', function(data, cb)
    local truckId = data and data.truckId
    local part = data and data.part or 'all'
    if not truckId then return cb({ ok = false, reason = 'ID inválido' }) end
    local ok, res, info = pcall(lib.callback.await, 'aurp_trucker:repairTruck', false, truckId, part)
    if ok and res then
        lib.notify({ title = 'Oficina', description = ('Veículo reparado! Custo: $%d'):format(info and info.cost or 0), type = 'success' })
        cb({ ok = true, info = info })
    else
        local reason = (type(info) == 'string' and info) or 'Erro ao reparar veículo'
        lib.notify({ title = 'Oficina', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('takeLoanPlan', function(data, cb)
    local planIndex = data and data.planIndex or 1
    local ok, res = pcall(lib.callback.await, 'aurp_trucker:takeLoanPlan', false, planIndex)
    if ok and res and res.success then
        lib.notify({ title = 'Banco', description = ('Empréstimo de $%d creditado em sua conta!'):format(res.loan.amount), type = 'success' })
        cb({ ok = true, loan = res.loan })
    else
        local reason = (res and res.reason) or 'Falha ao solicitar empréstimo'
        lib.notify({ title = 'Banco', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('hireAgencyDriver', function(data, cb)
    local driverIndex = data and data.driverIndex or 1
    local ok, res, info = pcall(lib.callback.await, 'aurp_trucker:hireAgencyDriver', false, driverIndex)
    if ok and res then
        lib.notify({ title = 'RH & Motoristas', description = ('Motorista %s contratado com sucesso!'):format(info and info.name or ''), type = 'success' })
        cb({ ok = true, driver = info })
    else
        local reason = (type(info) == 'string' and info) or 'Erro ao contratar motorista'
        lib.notify({ title = 'RH & Motoristas', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('assignDriverTruck', function(data, cb)
    local driverId = data and data.driverId
    local truckId = data and data.truckId
    local ok, res, err = pcall(lib.callback.await, 'aurp_trucker:assignDriverTruck', false, driverId, truckId)
    if ok and res then
        lib.notify({ title = 'Frota', description = 'Atribuição atualizada com sucesso!', type = 'success' })
        cb({ ok = true })
    else
        local reason = (type(err) == 'string' and err) or 'Erro ao vincular caminhão'
        lib.notify({ title = 'Frota', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('fireAgencyDriver', function(data, cb)
    local driverId = data and data.driverId
    local ok, res, err = pcall(lib.callback.await, 'aurp_trucker:fireAgencyDriver', false, driverId)
    if ok and res then
        lib.notify({ title = 'RH & Motoristas', description = 'Motorista desligado da frota.', type = 'info' })
        cb({ ok = true })
    else
        local reason = (type(err) == 'string' and err) or 'Erro ao demitir motorista'
        lib.notify({ title = 'RH & Motoristas', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

RegisterNUICallback('upgradeSkill', function(data, cb)
    local skillType = data and data.skillType
    if not skillType then return cb({ ok = false, reason = 'Skill inválida' }) end
    local ok, res, err = pcall(lib.callback.await, 'aurp_trucker:upgradeSkill', false, skillType)
    if ok and res then
        lib.notify({ title = 'Especializações', description = ('Habilidade %s aprimorada!'):format(skillType), type = 'success' })
        cb({ ok = true })
    else
        local reason = (type(err) == 'string' and err) or 'Erro ao aprimorar habilidade'
        lib.notify({ title = 'Especializações', description = reason, type = 'error' })
        cb({ ok = false, reason = reason })
    end
end)

-- =======================================
-- SISTEMA DE TRABALHOS
-- =======================================

function StartJob(job)
    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 DEBUG StartJob: Iniciando job " .. job.cargo .. " (ID: " .. job.id .. ")")
    end

    if currentJob then
        if Config.Debug then
            print("^1[AURP_TRUCKER]^7 DEBUG StartJob: FALHA - Já possui trabalho ativo")
        end
        lib.notify({ title = 'Erro', description = 'Você já possui um trabalho ativo', type = 'error' })
        return false
    end

    -- Verificar capacidade de carga do veículo
    local jobWeight = job.weight or 80
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 then
        local vehClass = GetVehicleClass(vehicle)
        local capacity = Config.VehicleCapacity[vehClass]

        if capacity and capacity.maxWeight == 0 then
            lib.notify({
                title = 'Veículo Incompatível',
                description = 'Você não pode transportar carga neste tipo de veículo (' .. capacity.label .. ')',
                type = 'error',
                duration = 8000
            })
            return false
        end

        if capacity and jobWeight > capacity.maxWeight then
            local maxQty = math.max(1, math.floor((capacity.maxWeight / jobWeight) * (job.cargoQty or 1)))
            local originalQty = job.cargoQty or 1
            if maxQty < originalQty then
                job.cargoQty = maxQty
                lib.notify({
                    title = 'Carga Reduzida',
                    description = string.format(
                        'Seu %s suporta %dkg — carga reduzida de %d para %d unidades',
                        capacity.label, capacity.maxWeight, originalQty, maxQty
                    ),
                    type = 'warning',
                    duration = 8000
                })
            end
        end
    else
        lib.notify({
            title = 'Trabalho Aceito',
            description = 'Entre em um veículo para iniciar a entrega. Siga o GPS!',
            type = 'inform',
            duration = 8000
        })
    end

    currentJob = job
    VP_Trucker_CurrentJobOriginId = job.originId or nil
    activeJob = {
        id = job.id,
        cargo = job.cargo,
        company = job.company,
        trailer = job.trailer,
        payment = job.payment,
        distance = job.distance,
        pickup = job.pickup,
        delivery = job.delivery,
        stage = 'pickup',
        startTime = GetGameTimer()
    }
    jobProgress.stage = 'pickup'
    jobProgress.startTime = GetGameTimer()

    -- Atualizar NUI se estiver aberta
    if isNUIOpen then
        local currentActiveJob = activeJob
        currentActiveJob.elapsedTime = math.floor((GetGameTimer() - currentActiveJob.startTime) / 1000)
        SendNUIMessage({
            action = 'updateActiveJob',
            activeJob = currentActiveJob
        })
    end

    -- Criar blip para pickup
    jobProgress.pickupBlip = CreateBlip(
        job.pickup.coords,
        478, -- factory icon
        2, -- green
        "CARREGAR: " .. job.pickup.name,
        1.0,
        true -- route
    )

    -- Criar ponto ox_lib otimizado para a doca de carregamento (Resmon 0.00ms fora do raio)
    ClearJobPoints()
    if job.pickup and job.pickup.coords then
        pickupPoint = lib.points.new({
            coords = job.pickup.coords,
            distance = 45.0,
            nearby = function(self)
                if not currentJob or jobProgress.stage ~= 'pickup' then return end
                DrawMarker(1, self.coords.x, self.coords.y, self.coords.z - 1.0,
                    0, 0, 0, 0, 0, 0, 3.5, 3.5, 1.2, 0, 255, 0, 140, false, true, 2, false, nil, nil, false)

                local playerPed = PlayerPedId()
                local inVeh = IsPedInAnyVehicle(playerPed, false)
                if self.currentDistance <= 4.0 then
                    if inVeh then
                        lib.showTextUI('[E] Carregar ' .. (currentJob.cargo or 'Mercadoria'))
                        if IsControlJustPressed(0, 38) then
                            lib.hideTextUI()
                            StartLoading()
                        end
                    else
                        lib.showTextUI('Entre no veículo para carregar')
                    end
                else
                    lib.hideTextUI()
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
    end

    local vehicleHint = job.trailer == 'van'
        and 'Use qualquer veículo'
        or 'Trailer: OK'
    lib.notify({
        title = 'Trabalho Aceito!',
        description = string.format(
            'Carga: %s | Destino: %s | %s | $%d',
            job.cargo, job.pickup.name, vehicleHint, job.payment
        ),
        type = 'success',
        duration = 10000
    })

    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 Trabalho iniciado: " .. job.cargo)
        print("^2[AURP_TRUCKER]^7 DEBUG StartJob: SUCESSO - currentJob definido, activeJob definido, blip criado")
    end

    return true
end

-- Lógica executada após carregamento completo (forklift OU progressBar)
-- DEVE ser declarada ANTES de StartLoading()
local function _CompleteLoading()
    if not currentJob then return end
    jobProgress.stage = 'delivering'

    if activeJob then
        activeJob.stage = 'delivering'
        if isNUIOpen then
            local currentActiveJob = activeJob
            currentActiveJob.elapsedTime = math.floor((GetGameTimer() - currentActiveJob.startTime) / 1000)
            SendNUIMessage({ action = 'updateActiveJob', activeJob = currentActiveJob })
        end
    end

    if jobProgress.pickupBlip then
        RemoveBlip(jobProgress.pickupBlip)
        jobProgress.pickupBlip = nil
    end

    -- Limpar ponto de carregamento e criar ponto de entrega otimizado
    ClearJobPoints()
    if currentJob.delivery and currentJob.delivery.coords then
        deliveryPoint = lib.points.new({
            coords = currentJob.delivery.coords,
            distance = 45.0,
            nearby = function(self)
                if not currentJob or jobProgress.stage ~= 'delivering' then return end
                DrawMarker(1, self.coords.x, self.coords.y, self.coords.z - 1.0,
                    0, 0, 0, 0, 0, 0, 4.0, 4.0, 1.5, 0, 150, 255, 140, false, true, 2, false, nil, nil, false)

                local playerPed = PlayerPedId()
                local inVeh = IsPedInAnyVehicle(playerPed, false)
                if self.currentDistance <= 5.0 then
                    if inVeh then
                        lib.showTextUI('[E] Entregar ' .. (currentJob.cargo or 'Mercadoria'))
                        if IsControlJustPressed(0, 38) then
                            lib.hideTextUI()
                            StartUnloading()
                        end
                    else
                        lib.showTextUI('Entre no caminhão para entregar')
                    end
                else
                    lib.hideTextUI()
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
    end

    jobProgress.deliveryBlip = CreateBlip(
        currentJob.delivery.coords,
        473, 3,
        'ENTREGAR: ' .. currentJob.delivery.name,
        1.0, true
    )
    TriggerEvent('aurp_trucker:client:jobStartedConvoy', jobProgress.deliveryBlip)

    ShowNotification(
        'Carregamento Completo!',
        string.format(
            'Carga: %s (CARREGADA) - Destino: %s - Pagamento: $%d - Dirija com cuidado! Siga a rota GPS azul',
            currentJob.cargo, currentJob.delivery.name, currentJob.payment
        ),
        'success', 12000
    )

    if Config.Debug then
        print('^2[AURP_TRUCKER]^7 Carga carregada: ' .. currentJob.cargo)
    end
end

function StartLoading()
    if not currentJob or jobProgress.stage ~= 'pickup' then return end

    local playerPed = PlayerPedId()
    if not IsPedInAnyVehicle(playerPed, false) then
        ShowNotification('Erro', 'Você precisa estar dentro do caminhão para carregar a mercadoria', 'error')
        return
    end

    local pickupCoords = currentJob.pickup.coords
    if currentJob.trailer == 'van' then
        -- Entrega de van: verifica posição do veículo do jogador
        local vehiclePos = GetEntityCoords(GetVehiclePedIsIn(playerPed, false))
        if #(vehiclePos - pickupCoords) > 15.0 then
            ShowNotification('Erro', 'Você precisa chegar ao local de coleta (marker verde)', 'error')
            return
        end
    else
        local trailer = GetPlayerTrailer()
        if not trailer then
            ShowNotification('Erro', 'Você precisa estar com um trailer conectado', 'error')
            return
        end

        local trailerCoords = GetEntityCoords(trailer)
        if #(trailerCoords - pickupCoords) > 10.0 then
            ShowNotification('Erro', 'Você precisa posicionar o trailer no local de carregamento (marker verde)', 'error')
            return
        end
    end

    local qty = currentJob.cargoQty or 1

    -- Branch: forklift ativo e job com múltiplos pacotes
    -- IMPORTANTE: trailer é capturado AGORA (player ainda está no truck), antes de entrar no forklift
    if VP_Trucker_ForkliftActive ~= nil and qty > 1 then
        TriggerEvent('aurp_trucker:forklift:startIndustryLoad', qty, trailer)
        -- forklift.client.lua dispara 'aurp_trucker:forklift:industryLoadComplete' quando concluído
        return
    end

    -- Branch manual: qty progressBars sequenciais com feedback por pacote
    ShowNotification(
        'Iniciando Carregamento',
        string.format('Local: %s - Carga: %s (%d pacotes) - Aguarde...', currentJob.pickup.name, currentJob.cargo, qty),
        'info', 5000
    )

    for i = 1, qty do
        lib.showTextUI(('[%d/%d] Carregando %s...'):format(i, qty, currentJob.cargo))
        local success = lib.progressBar({
            duration     = currentJob.loadTime,
            label        = string.format('Carregando %s (%d/%d)...', currentJob.cargo, i, qty),
            useWhileDead = false,
            canCancel    = false,
            disable      = { car = true, move = true, combat = true },
        })
        lib.hideTextUI()
        if not success then return end
    end

    _CompleteLoading()
end

-- Receber sinal de carregamento forklift concluído (de forklift.client.lua)
AddEventHandler('aurp_trucker:forklift:industryLoadComplete', function()
    _CompleteLoading()
end)

function StartUnloading()
    if not currentJob or jobProgress.stage ~= 'delivering' then return end

    -- Verificar se o jogador está dentro do caminhão
    local playerPed = PlayerPedId()
    if not IsPedInAnyVehicle(playerPed, false) then
        ShowNotification(
            'Erro',
            'Você precisa estar dentro do caminhão para descarregar a mercadoria',
            'error'
        )
        return
    end

    local deliveryCoords = currentJob.delivery.coords
    if currentJob.trailer == 'van' then
        -- Entrega de van: verifica posição do veículo do jogador
        local vehiclePos = GetEntityCoords(GetVehiclePedIsIn(playerPed, false))
        if #(vehiclePos - deliveryCoords) > 15.0 then
            ShowNotification('Erro', 'Você precisa chegar ao local de entrega (marker azul)', 'error')
            return
        end
    else
        local trailer = GetPlayerTrailer()
        if not trailer then
            ShowNotification('Erro', 'Você não possui carga para entregar', 'error')
            return
        end

        local trailerCoords = GetEntityCoords(trailer)
        if #(trailerCoords - deliveryCoords) > 10.0 then
            ShowNotification('Erro', 'Você precisa posicionar o trailer no local de entrega (marker azul)', 'error')
            return
        end
    end

    -- Processo de descarregamento
    ShowNotification(
        'Iniciando Entrega',
        string.format(
            'Local: %s - Entregando: %s - Aguarde o descarregamento...',
            currentJob.delivery.name,
            currentJob.cargo
        ),
        'info',
        5000
    )

    local success = lib.progressBar({
        duration = currentJob.unloadTime,
        label = '📦 Descarregando ' .. currentJob.cargo .. '...',
        useWhileDead = false,
        canCancel = false,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })

    if success then
        CompleteJob()
    end
end

function CompleteJob()
    if not currentJob then return end

    local deliveryTime = (GetGameTimer() - jobProgress.startTime) / 1000
    local basePayment = currentJob.payment

    -- Bônus por tempo
    local timeMultiplier = 1.0
    if deliveryTime <= 300 then -- 5 min
        timeMultiplier = 1.2
    elseif deliveryTime <= 600 then -- 10 min
        timeMultiplier = 1.0
    else
        timeMultiplier = 0.8
    end

    local finalPayment = math.floor(basePayment * timeMultiplier)

    -- Atualizar estatísticas
    playerStats.totalEarnings = playerStats.totalEarnings + finalPayment
    playerStats.totalDeliveries = playerStats.totalDeliveries + 1
    playerStats.totalDistance = playerStats.totalDistance + currentJob.distance

    -- Roteamento via hud.client.lua para injetar cargoIntegrity
    -- Named events cruzam chunks lua54 no mesmo resource
    TriggerEvent('aurp_trucker:client:sendIntegrity', deliveryTime)

    -- Calcular tempo de entrega em minutos
    local deliveryMinutes = math.floor(deliveryTime / 60)
    local deliverySeconds = math.floor(deliveryTime % 60)
    local timeText = string.format("%dm %ds", deliveryMinutes, deliverySeconds)

    -- Texto do bônus
    local bonusText = ""
    if timeMultiplier > 1.0 then
        bonusText = " - Bônus de Velocidade: +" .. math.floor((timeMultiplier - 1) * 100) .. "%"
    elseif timeMultiplier < 1.0 then
        bonusText = " - Penalidade por Demora: " .. math.floor((timeMultiplier - 1) * 100) .. "%"
    end

    ShowNotification(
        'Trabalho Completo!',
        string.format(
            'Entrega realizada com sucesso! Pagamento: $%s - Tempo: %s - Carga: %s - De: %s - Para: %s%s - Trailer mantido para reutilização!',
            finalPayment,
            timeText,
            currentJob.cargo,
            currentJob.pickup.name,
            currentJob.delivery.name,
            bonusText
        ),
        'success',
        15000
    )

    -- Limpar job
    if jobProgress.deliveryBlip then
        RemoveBlip(jobProgress.deliveryBlip)
        jobProgress.deliveryBlip = nil
    end

    -- NÃO deletar o trailer - permitir reutilização em outro trabalho
    -- if currentTrailer and DoesEntityExist(currentTrailer) then
    --     DeleteEntity(currentTrailer)
    -- end
    ClearJobPoints()

    currentJob = nil
    VP_Trucker_CurrentJobOriginId = nil
    activeJob = nil -- Limpar activeJob para atualizar a NUI
    jobProgress = {
        stage = nil,
        startTime = nil,
        pickupBlip = nil,
        deliveryBlip = nil
    }

    -- Limpar blips de localização marcados
    if locationBlips.pickup then
        RemoveBlip(locationBlips.pickup)
        locationBlips.pickup = nil
    end
    if locationBlips.delivery then
        RemoveBlip(locationBlips.delivery)
        locationBlips.delivery = nil
    end

    -- Atualizar NUI se estiver aberta informando que não há trabalho ativo
    if isNUIOpen then
        SendNUIMessage({
            action = 'updateActiveJob',
            activeJob = nil
        })
    end

    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 Trabalho completado: $" .. finalPayment)
    end
end

-- Bridge para illegal.client.lua cruzar o isolamento de chunk lua54
-- illegal.client.lua não pode chamar CompleteJob diretamente (chunk separado)
AddEventHandler('aurp_trucker:client:triggerComplete', CompleteJob)

-- =======================================
-- SPAWNAR TRAILER
-- =======================================

function SpawnPlayerTrailer(model)
    -- Remover trailer anterior se existir
    if currentTrailer and DoesEntityExist(currentTrailer) then
        DeleteEntity(currentTrailer)
        currentTrailer = nil

        ShowNotification(
            'Trailer Substituído',
            'Trailer anterior foi removido.',
            'info',
            3000
        )
        Wait(1000)
    end

    local coords = Config.TrailerCompany.spawnCoords
    currentTrailer = SpawnTrailer(model, coords)

    if currentTrailer then
        local trailerNames = {
            ['tanker'] = 'Caminhão Tanque',
            ['trailers'] = 'Container',
            ['trailers2'] = 'Container Duplo'
        }

        ShowNotification(
            'Trailer Preparado!',
            string.format(
                'Tipo: %s - Localização: Spawned - Conecte-o ao seu caminhão para começar a trabalhar.',
                trailerNames[model] or model
            ),
            'success',
            8000
        )

        if Config.Debug then
            print("^2[AURP_TRUCKER]^7 Trailer spawned: " .. model)
        end
    else
        ShowNotification(
            'Erro',
            'Não foi possível preparar o trailer',
            'error'
        )
    end
end

-- =======================================
-- SISTEMA DE INTERAÇÕES E FÍSICA DE TRAILERS
-- =======================================

local isTrailerDetached = false
local detachedBlip = nil

-- Monitoramento e recuperação autoritativa de desengate de trailer (IsVehicleAttachedToTrailer)
CreateThread(function()
    while true do
        if currentJob and currentJob.trailer ~= 'van' and jobProgress.stage == 'delivering' then
            local playerPed = PlayerPedId()
            local veh = GetVehiclePedIsIn(playerPed, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                local hasTrailer, attachedTrailer = GetVehicleTrailerVehicle(veh)
                local isAttached = (hasTrailer == 1 or hasTrailer == true) or IsVehicleAttachedToTrailer(veh)

                if not isAttached then
                    if not isTrailerDetached then
                        isTrailerDetached = true
                        lib.notify({
                            title = 'Atenção: Trailer Desengatado!',
                            description = 'Seu trailer se soltou! Retorne e acople o caminhão de ré para prosseguir.',
                            type = 'warning',
                            duration = 10000
                        })
                        local trl = currentTrailer
                        if trl and DoesEntityExist(trl) then
                            if not detachedBlip or not DoesBlipExist(detachedBlip) then
                                detachedBlip = AddBlipForEntity(trl)
                                SetBlipSprite(detachedBlip, 479)
                                SetBlipColour(detachedBlip, 5)
                                SetBlipRoute(detachedBlip, true)
                                SetBlipRouteColour(detachedBlip, 5)
                                BeginTextCommandSetBlipName("STRING")
                                AddTextComponentString("Recuperar Trailer")
                                EndTextCommandSetBlipName(detachedBlip)
                            end
                        end
                    end
                else
                    if isTrailerDetached then
                        isTrailerDetached = false
                        if detachedBlip and DoesBlipExist(detachedBlip) then
                            RemoveBlip(detachedBlip)
                            detachedBlip = nil
                        end
                        lib.notify({
                            title = 'Trailer Reconectado!',
                            description = 'Carga engatada com sucesso. Prossiga até o destino final.',
                            type = 'success',
                            duration = 6000
                        })
                    end
                end
            end
            Wait(1500)
        else
            if detachedBlip and DoesBlipExist(detachedBlip) then
                RemoveBlip(detachedBlip)
                detachedBlip = nil
            end
            isTrailerDetached = false
            Wait(3500)
        end
    end
end)

-- Limpeza autoritativa ao morrer em serviço
AddEventHandler('gameEventTriggered', function(event, data)
    if event == 'CEventNetworkEntityDamage' then
        local victim = data[1]
        if victim == PlayerPedId() and IsEntityDead(victim) then
            if currentJob or activeJob then
                TriggerServerEvent('aurp_trucker:server:onPlayerDeath')
            end
        end
    end
end)

-- Limpeza ao cancelar/abandonar rota
RegisterNetEvent('aurp_trucker:client:jobAbandoned', function()
    if jobProgress.pickupBlip then RemoveBlip(jobProgress.pickupBlip); jobProgress.pickupBlip = nil end
    if jobProgress.deliveryBlip then RemoveBlip(jobProgress.deliveryBlip); jobProgress.deliveryBlip = nil end
    if detachedBlip and DoesBlipExist(detachedBlip) then RemoveBlip(detachedBlip); detachedBlip = nil end
    if currentTrailer and DoesEntityExist(currentTrailer) then
        DeleteEntity(currentTrailer)
        currentTrailer = nil
    end
    currentJob = nil
    activeJob = nil
    VP_Trucker_CurrentJobOriginId = nil
    ClearJobPoints()
    lib.notify({ title = 'Trabalho Cancelado', description = 'A rota de entrega foi encerrada.', type = 'inform' })
    if isNUIOpen then
        SendNUIMessage({ action = 'updateActiveJob', activeJob = nil })
    end
end)

-- Loop leve (2.5s) apenas para remoção de blips manuais
CreateThread(function()
    while true do
        Wait(2500)
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        if locationBlips.pickup and currentJob then
            if #(playerCoords - currentJob.pickup.coords) <= 40.0 then
                RemoveBlip(locationBlips.pickup)
                locationBlips.pickup = nil
            end
        end

        if locationBlips.delivery and currentJob then
            if #(playerCoords - currentJob.delivery.coords) <= 40.0 then
                RemoveBlip(locationBlips.delivery)
                locationBlips.delivery = nil
            end
        end
    end
end)

-- Funções da Locadora de Caminhões com Retenção de Caução
local function OpenRentalMenu()
    local options = {}
    for _, truck in ipairs(Config.TruckRental.trucks or {}) do
        table.insert(options, {
            title = truck.label,
            description = ('Aluguel: $%d | Caução: $%d (Total: $%d)'):format(
                truck.fee, truck.deposit, truck.fee + truck.deposit),
            icon = 'truck',
            onSelect = function()
                local confirmed = lib.alertDialog({
                    header = 'Confirmar Locação',
                    content = ('Deseja alugar o caminhão **%s**?\n\n- Taxa de Uso: **$%d**\n- Caução Retida: **$%d**\n- Total Debitado: **$%d**\n\n*A caução será devolvida ao entregar o veículo sem avarias na doca.*'):format(
                        truck.label, truck.fee, truck.deposit, truck.fee + truck.deposit),
                    centered = true,
                    cancel = true
                })
                if confirmed == 'confirm' then
                    local ok, res = pcall(lib.callback.await, 'aurp_trucker:rental:rentTruck', false, truck.model)
                    if ok and res and res.success then
                        local spawnCoords = res.spawnCoords or Config.TruckRental.spawnCoords
                        local safeCoords = GetSafeSpawnCoords(spawnCoords, 5.0) or spawnCoords
                        local modelHash = GetHashKey(res.model)
                        RequestModel(modelHash)
                        while not HasModelLoaded(modelHash) do Wait(10) end

                        local veh = CreateVehicle(modelHash, safeCoords.x, safeCoords.y, safeCoords.z, safeCoords.w or 0.0, true, false)
                        SetVehicleNumberPlateText(veh, res.plate)
                        SetEntityAsMissionEntity(veh, true, true)
                        SetModelAsNoLongerNeeded(modelHash)

                        GiveVehicleKeysAndFuel(veh, res.plate, 100.0)

                        local netId = NetworkGetNetworkIdFromEntity(veh)
                        TriggerServerEvent('aurp_trucker:server:registerJobEntities', netId, nil)

                        lib.notify({
                            title = 'Caminhão Liberado!',
                            description = ('Seu %s (Placa: %s) está pronto na vaga. Cuide bem dele!'):format(truck.label, res.plate),
                            type = 'success',
                            duration = 8000
                        })
                    else
                        lib.notify({
                            title = 'Aluguel Não Autorizado',
                            description = res and res.reason or 'Falha ao processar locação.',
                            type = 'error'
                        })
                    end
                end
            end
        })
    end

    lib.registerContext({
        id = 'truck_rental_menu',
        title = 'Locadora de Caminhões — AURP',
        options = options
    })
    lib.showContext('truck_rental_menu')
end

local function ReturnRentedTruck()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        local pos = GetEntityCoords(ped)
        local closeVeh = GetClosestVehicle(pos.x, pos.y, pos.z, 20.0, 0, 71)
        if closeVeh ~= 0 and DoesEntityExist(closeVeh) then
            veh = closeVeh
        end
    end

    if veh == 0 or not DoesEntityExist(veh) then
        lib.notify({
            title = 'Devolução',
            description = 'Nenhum veículo alugado encontrado próximo a você.',
            type = 'error'
        })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    local bodyHealth = GetVehicleBodyHealth(veh)
    local engineHealth = GetVehicleEngineHealth(veh)

    local ok, res = pcall(lib.callback.await, 'aurp_trucker:rental:returnTruck', false, {
        netId        = netId,
        bodyHealth   = bodyHealth,
        engineHealth = engineHealth
    })

    if ok and res and res.success then
        if res.damagePenalty > 0 then
            lib.notify({
                title = 'Devolução com Avarias',
                description = ('Caução: $%d | Danos: -$%d | Estorno recebido: $%d'):format(
                    res.deposit, res.damagePenalty, res.refund),
                type = 'warning',
                duration = 9000
            })
        else
            lib.notify({
                title = 'Devolução Concluída!',
                description = ('Veículo entregue impecável! Estorno total da caução: $%d'):format(res.refund),
                type = 'success',
                duration = 8000
            })
        end
    else
        lib.notify({
            title = 'Devolução Recusada',
            description = res and res.reason or 'Não foi possível devolver o veículo.',
            type = 'error'
        })
    end
end

-- =======================================
-- INICIALIZAÇÃO: MARCADORES VISUAIS & INTERAÇÃO [E]
-- =======================================

local function SafeRequestModel(modelHash, timeoutMs)
    if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then return false end
    RequestModel(modelHash)
    local t = 0
    while not HasModelLoaded(modelHash) and t < (timeoutMs or 3000) do
        Wait(50)
        t = t + 50
    end
    return HasModelLoaded(modelHash)
end

local hqLocations = {}
if Config.LC_Headquarters and Config.LC_Headquarters.coords then
    table.insert(hqLocations, {
        coords = Config.LC_Headquarters.coords, -- Buccaneer Way: vector3(1208.83, -3115.0, 5.54)
        name   = Config.LC_Headquarters.name or 'Central de Fretes (Buccaneer Way)',
    })
end

-- Thread dedicada para Marcadores Visuais no Chão e Tecla [E] (Resmon < 0.01ms)
CreateThread(function()
    local textUiShown = false
    while true do
        local sleep = 1500
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local inRangeAny = false

        for _, loc in ipairs(hqLocations) do
            local dist = #(pCoords - loc.coords)
            if dist < 35.0 then
                sleep = 0
                -- 1. Cilindro no chão com brilho esmeralda
                DrawMarker(1, loc.coords.x, loc.coords.y, loc.coords.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    2.0, 2.0, 0.6,
                    16, 185, 129, 140, false, false, 2, false, nil, nil, false)

                -- 2. Chevron giratório flutuante
                DrawMarker(21, loc.coords.x, loc.coords.y, loc.coords.z + 0.35,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.75, 0.75, 0.75,
                    16, 185, 129, 200, false, true, 2, true, nil, nil, false)

                -- 3. Texto 3D no local
                DrawText3D(loc.coords, "~g~[E]~w~ Central de Logística")

                if dist < 2.5 then
                    inRangeAny = true
                    if not textUiShown then
                        lib.showTextUI('[E] Acessar Central Logística', { icon = 'truck-fast', position = 'left-center' })
                        textUiShown = true
                    end
                    if IsControlJustPressed(0, 38) then
                        CreateThread(OpenJobBoard)
                    end
                end
            end
        end

        if not inRangeAny and textUiShown then
            lib.hideTextUI()
            textUiShown = false
        end

        Wait(sleep)
    end
end)

-- Thread de Blips e NPCs Despachantes (com ox_target secundário)
CreateThread(function()
    Wait(500)

    -- Sede Original lc_truck_logistics: Terminal Buccaneer Way / Porto de Los Santos
    if Config.LC_Headquarters then
        local hq = Config.LC_Headquarters
        blips.lcHq = CreateBlip(
            hq.coords,
            hq.blip.sprite or 478,
            hq.blip.color or 4,
            hq.blip.label or hq.name,
            hq.blip.scale or 0.65
        )

        local lcPedCoords = hq.pedCoords or vector4(hq.coords.x, hq.coords.y, hq.coords.z, 90.0)
        local lcModel = GetHashKey('s_m_y_dockwork_01') -- Modelo válido GTA V dockworker
        if SafeRequestModel(lcModel, 4000) then
            local lcDispatcher = CreatePed(4, lcModel, lcPedCoords.x, lcPedCoords.y, lcPedCoords.z, lcPedCoords.w, false, true)
            if lcDispatcher and lcDispatcher ~= 0 and DoesEntityExist(lcDispatcher) then
                SetEntityInvincible(lcDispatcher, true)
                SetBlockingOfNonTemporaryEvents(lcDispatcher, true)
                FreezeEntityPosition(lcDispatcher, true)
                SetModelAsNoLongerNeeded(lcModel)

                exports.ox_target:addLocalEntity(lcDispatcher, {
                    {
                        name     = 'open_lc_job_board',
                        icon     = 'fas fa-truck-loading',
                        label    = 'Central de Fretes (Buccaneer Way)',
                        distance = 3.0,
                        onSelect = function() CreateThread(OpenJobBoard) end,
                    },
                    {
                        name     = 'rent_truck_lc',
                        icon     = 'fas fa-truck-moving',
                        label    = 'Locadora de Caminhões',
                        distance = 3.0,
                        onSelect = function() OpenRentalMenu() end,
                    },
                    {
                        name     = 'return_truck_lc',
                        icon     = 'fas fa-undo-alt',
                        label    = 'Devolver Caminhão Alugado',
                        distance = 3.0,
                        onSelect = function() ReturnRentedTruck() end,
                    },
                })

                AddEventHandler('onResourceStop', function(res)
                    if res ~= GetCurrentResourceName() then return end
                    if lcDispatcher and DoesEntityExist(lcDispatcher) then
                        exports.ox_target:removeLocalEntity(lcDispatcher)
                        DeleteEntity(lcDispatcher)
                    end
                end)
            end
        end
    end
end)

-- Thread para atualizar trabalho ativo na NUI
CreateThread(function()
    while true do
        Wait(5000) -- Atualizar a cada 5 segundos

        if isNUIOpen and activeJob then
            local currentActiveJob = {
                id = activeJob.id,
                cargo = activeJob.cargo,
                company = activeJob.company,
                trailer = activeJob.trailer,
                payment = activeJob.payment,
                distance = activeJob.distance,
                pickup = activeJob.pickup,
                delivery = activeJob.delivery,
                stage = activeJob.stage,
                startTime = activeJob.startTime,
                elapsedTime = math.floor((GetGameTimer() - activeJob.startTime) / 1000)
            }
            SendNUIMessage({
                action = 'updateActiveJob',
                activeJob = currentActiveJob
            })
        end
    end
end)

-- =======================================
-- COMANDOS DE DEBUG
-- =======================================

RegisterCommand('truckerui', function()
    OpenJobBoard()
end, false)

RegisterCommand('trucker', function()
    OpenJobBoard()
end, false)

RegisterCommand('canceljob', function()
    ExecuteCommand('clearjob')
end, false)


RegisterCommand('checkactivejob', function()
    if activeJob then
        print("^2[AURP_TRUCKER]^7 Trabalho Ativo:")
        print("^2[AURP_TRUCKER]^7 Cargo: " .. activeJob.cargo)
        print("^2[AURP_TRUCKER]^7 Empresa: " .. activeJob.company)
        print("^2[AURP_TRUCKER]^7 Estágio: " .. activeJob.stage)
        print("^2[AURP_TRUCKER]^7 Pagamento: $" .. activeJob.payment)
    else
        print("^1[AURP_TRUCKER]^7 Nenhum trabalho ativo")
    end
end, false)

RegisterCommand('cleartrailer', function()
    if currentTrailer and DoesEntityExist(currentTrailer) then
        DeleteEntity(currentTrailer)
        currentTrailer = nil
        ShowNotification(
            'Trailer Removido',
            'Seu trailer foi removido',
            'success'
        )
    else
        ShowNotification(
            'Nenhum Trailer',
            'Você não possui trailer ativo',
            'error'
        )
    end
end, false)

RegisterCommand('checktrailer', function()
    local trailer = GetPlayerTrailer()
    if trailer then
        local trailerType = GetTrailerType(trailer)
        local trailerNames = {
            ['tanker'] = 'Caminhão Tanque',
            ['trailers'] = 'Container',
            ['trailers2'] = 'Container Duplo'
        }

        ShowNotification(
            'Trailer Detectado',
            string.format(
                'Tipo: %s - Entity: %s - Model: %s - Status: %s',
                trailerNames[trailerType] or (trailerType or 'Desconhecido'),
                trailer,
                GetEntityModel(trailer),
                trailer == currentTrailer and 'Sistema' or 'Acoplado'
            ),
            'info',
            8000
        )
    else
        ShowNotification(
            'Nenhum Trailer',
            'Nenhum trailer detectado. Vá até a Central de Trabalhos para pegar um.',
            'error',
            5000
        )
    end
end, false)

RegisterCommand('clearjob', function()
    if currentJob then
        if jobProgress.pickupBlip then
            RemoveBlip(jobProgress.pickupBlip)
        end
        if jobProgress.deliveryBlip then
            RemoveBlip(jobProgress.deliveryBlip)
        end

        -- Limpar blips de localização marcados
        if locationBlips.pickup then
            RemoveBlip(locationBlips.pickup)
            locationBlips.pickup = nil
        end
        if locationBlips.delivery then
            RemoveBlip(locationBlips.delivery)
            locationBlips.delivery = nil
        end

        currentJob = nil
        VP_Trucker_CurrentJobOriginId = nil
        activeJob = nil -- Limpar activeJob também
        jobProgress = {
            stage = nil,
            startTime = nil,
            pickupBlip = nil,
            deliveryBlip = nil
        }

        -- Atualizar NUI se estiver aberta
        if isNUIOpen then
            SendNUIMessage({
                action = 'updateActiveJob',
                activeJob = nil
            })
        end

        ShowNotification(
            'Trabalho Cancelado',
            'Seu trabalho foi cancelado',
            'info'
        )
    else
        ShowNotification(
            'Nenhum Trabalho',
            'Você não possui trabalho ativo',
            'error'
        )
    end
end, false)

RegisterNetEvent('aurp_trucker:client:levelUp', function(data)
    -- data = { newLevel, newRank, levelsGained, skillPoints }
    lib.notify({
        title       = 'Level Up!',
        description = ('Nível %d alcançado! Rank %d\n+%d Skill Point(s) disponíveis'):format(
            data.newLevel, data.newRank, data.skillPoints),
        type        = 'success',
        duration    = 8000,
    })
    -- Atualizar stats na NUI para refletir novo level/skill_points
    SendNUIMessage({
        action = 'updateSkills',
        refreshStats = true,
    })
end)

-- NUI Callbacks para gestão de empresas
RegisterNUICallback('depositMoney', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('aurp_trucker:depositMoney', amount)
    end
    cb('ok')
end)

RegisterNUICallback('withdrawMoney', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('aurp_trucker:withdrawMoney', amount)
    end
    cb('ok')
end)

RegisterNUICallback('leaveCompany', function(data, cb)
    TriggerServerEvent('aurp_trucker:leaveCompany')
    cb('ok')
end)

RegisterNUICallback('kickMember', function(data, cb)
    local citizenid = data.citizenid
    if citizenid then
        TriggerServerEvent('aurp_trucker:kickMember', citizenid)
    end
    cb('ok')
end)

RegisterNUICallback('sellCompany', function(data, cb)
    TriggerServerEvent('aurp_trucker:sellCompany')
    cb('ok')
end)

RegisterNUICallback('registerVehicle', function(data, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        ShowNotification(
            'Erro',
            'Você precisa estar dentro de um veículo',
            'error'
        )
        cb('ok')
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") -- trim whitespace
    end

    local vehicleModel = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(vehicleModel)

    TriggerServerEvent('aurp_trucker:registerVehicle', plate, modelName, 'truck')
    cb('ok')
end)

RegisterNUICallback('removeVehicle', function(data, cb)
    local plate = data.plate
    if plate then
        TriggerServerEvent('aurp_trucker:removeVehicle', plate)
    end
    cb('ok')
end)

-- Membros da empresa (chamado por MemberList.tsx)
RegisterNUICallback('getCompanyMembers', function(data, cb)
    local ok, members = pcall(lib.callback.await, 'aurp_trucker:getCompanyMembers', false)
    cb(ok and members or {})
end)

-- Veículos da empresa (chamado por GaragePanel.tsx)
RegisterNUICallback('getVehicles', function(data, cb)
    local ok, vehicles = pcall(lib.callback.await, 'aurp_trucker:getCompanyVehicles', false)
    cb(ok and vehicles or {})
end)

-- Retirar veículo da garagem
RegisterNUICallback('retrieveVehicle', function(data, cb)
    local plate = data.plate
    if not plate then cb({ success = false }) return end

    -- Fechar UI para spawnar veículo
    CloseJobBoard()

    local ok, result = pcall(lib.callback.await, 'aurp_trucker:retrieveVehicle', false, plate)
    if not ok or not result or not result.success then
        lib.notify({
            title = 'Garagem',
            description = result and result.error or 'Erro ao retirar veículo',
            type = 'error'
        })
        cb({ success = false })
        return
    end

    -- Spawnar veículo perto do jogador
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local modelHash = GetHashKey(result.model)

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 5000 do
        Wait(100)
        timeout = timeout + 100
    end

    if not HasModelLoaded(modelHash) then
        lib.notify({ title = 'Garagem', description = 'Falha ao carregar modelo do veículo', type = 'error' })
        cb({ success = false })
        return
    end

    -- Spawn com detecção autoritativa de desobstrução de vaga
    local forward = GetEntityForwardVector(ped)
    local rawSpawnPos = coords + forward * 5.0
    local spawnPos = GetSafeSpawnCoords(vector4(rawSpawnPos.x, rawSpawnPos.y, rawSpawnPos.z, heading), 4.5)
    if not spawnPos then
        lib.notify({ title = 'Vaga Ocupada', description = 'A área de saída está obstruída. Libere espaço na garagem.', type = 'error' })
        cb({ success = false })
        return
    end

    local vehicle = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)

    if vehicle and vehicle ~= 0 then
        SetVehicleNumberPlateText(vehicle, result.plate)
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleEngineOn(vehicle, false, false, false)
        SetVehicleDoorsLocked(vehicle, 1) -- destrancado
        SetModelAsNoLongerNeeded(modelHash)

        -- Combustível e chaves universais (qbx_vehiclekeys, ox_fuel)
        GiveVehicleKeysAndFuel(vehicle, result.plate, 100.0)

        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        TriggerServerEvent('aurp_trucker:server:registerJobEntities', netId, nil)

        -- Adicionar ox_target para guardar o veículo no mundo
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name = 'store_company_vehicle_' .. result.plate,
                label = 'Guardar Veículo na Garagem',
                icon = 'fas fa-warehouse',
                distance = 3.0,
                onSelect = function()
                    local veh = vehicle
                    local plt = result.plate
                    local ok2, res2 = pcall(lib.callback.await, 'aurp_trucker:storeVehicle', false, plt)
                    if ok2 and res2 and res2.success then
                        local p = PlayerPedId()
                        if GetVehiclePedIsIn(p, false) == veh then
                            TaskLeaveVehicle(p, veh, 0)
                            Wait(2000)
                        end
                        if DoesEntityExist(veh) then
                            exports.ox_target:removeLocalEntity(veh)
                            DeleteEntity(veh)
                        end
                        lib.notify({ title = 'Garagem', description = 'Veículo guardado!', type = 'success' })
                    else
                        lib.notify({ title = 'Garagem', description = 'Erro ao guardar veículo', type = 'error' })
                    end
                end,
            },
        })

        lib.notify({
            title = 'Garagem',
            description = 'Veículo retirado! Use ox_target (olhe para o veículo) para guardar.',
            type = 'success',
            duration = 8000
        })
    else
        lib.notify({ title = 'Garagem', description = 'Falha ao criar veículo', type = 'error' })
    end

    cb({ success = true })
end)

-- Guardar veículo na garagem (via NUI — procura veículo por placa no mundo)
RegisterNUICallback('storeVehicle', function(data, cb)
    local plate = data.plate
    if not plate then cb({ success = false }) return end

    CloseJobBoard()

    -- Procurar veículo com essa placa próximo ao jogador
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local foundVehicle = nil

    -- Primeiro checar se está dentro do veículo
    local inVeh = GetVehiclePedIsIn(ped, false)
    if inVeh ~= 0 then
        local vehPlate = string.gsub(GetVehicleNumberPlateText(inVeh), "^%s*(.-)%s*$", "%1")
        if vehPlate == plate then
            foundVehicle = inVeh
        end
    end

    -- Se não está dentro, procurar por perto
    if not foundVehicle then
        local vehicles = GetGamePool('CVehicle')
        for _, veh in ipairs(vehicles) do
            local vehPlate = string.gsub(GetVehicleNumberPlateText(veh), "^%s*(.-)%s*$", "%1")
            if vehPlate == plate then
                local vehCoords = GetEntityCoords(veh)
                if #(playerCoords - vehCoords) < 30.0 then
                    foundVehicle = veh
                    break
                end
            end
        end
    end

    if not foundVehicle then
        lib.notify({ title = 'Garagem', description = 'Veículo não encontrado por perto', type = 'error' })
        cb({ success = false })
        return
    end

    local ok, result = pcall(lib.callback.await, 'aurp_trucker:storeVehicle', false, plate)
    if ok and result and result.success then
        if GetVehiclePedIsIn(ped, false) == foundVehicle then
            TaskLeaveVehicle(ped, foundVehicle, 0)
            Wait(2000)
        end
        if DoesEntityExist(foundVehicle) then
            pcall(exports.ox_target.removeLocalEntity, exports.ox_target, foundVehicle)
            DeleteEntity(foundVehicle)
        end
        lib.notify({ title = 'Garagem', description = 'Veículo guardado!', type = 'success' })
    else
        local reason = (result and result.error) or 'Erro ao guardar veículo'
        lib.notify({ title = 'Garagem', description = reason, type = 'error' })
    end
    cb({ success = ok and result and result.success or false })
end)

-- Indústrias (chamado por IndustryList.tsx)
RegisterNUICallback('getIndustries', function(data, cb)
    local ok, industries = pcall(lib.callback.await, 'aurp_trucker:getIndustries', false)
    cb(ok and industries or {})
end)

RegisterNUICallback('purchaseSkill', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:purchaseSkill', false, data)
    cb(ok and result or { success = false, error = 'Sem resposta do servidor' })
end)

RegisterNUICallback('getPlayerStats', function(data, cb)
    cb('ok') -- liberar JS imediatamente
    CreateThread(function()
        local ok, stats = pcall(lib.callback.await, 'aurp_trucker:getPlayerStats', false)
        if ok and stats then
            SendNUIMessage({ action = 'updateStats', stats = stats })
        end
        local ok2, skills = pcall(lib.callback.await, 'aurp_trucker:getPlayerSkills', false)
        if ok2 and skills then
            SendNUIMessage({ action = 'updateSkills', skills = skills })
        end
    end)
end)

RegisterNUICallback('getCompanyHistory', function(data, cb)
    cb('ok') -- liberar JS imediatamente
    CreateThread(function()
        local ok, history = pcall(lib.callback.await, 'aurp_trucker:getCompanyHistory', false)
        if ok and history then
            SendNUIMessage({ action = 'updateCompanyHistory', history = history })
        end
    end)
end)

RegisterNUICallback('getConvoyHistory', function(data, cb)
    cb('ok') -- liberar JS imediatamente
    CreateThread(function()
        local ok, history = pcall(lib.callback.await, 'aurp_trucker:getConvoyHistory', false)
        if ok and history then
            SendNUIMessage({ action = 'updateConvoyHistory', convoyHistory = history })
        end
    end)
end)

-- Auto-refresh da lista de jobs quando o servidor gera novos
RegisterNetEvent('aurp_trucker:client:jobsUpdated', function()
    if isNUIOpen or (IsNUIFocused and IsNUIFocused()) then
        RefreshNUIData()
    end
end)

-- =======================================
-- EVENTOS DE LIMPEZA
-- =======================================

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    CloseJobBoard()

    if jobProgress.pickupBlip then
        RemoveBlip(jobProgress.pickupBlip)
    end
    if jobProgress.deliveryBlip then
        RemoveBlip(jobProgress.deliveryBlip)
    end

    -- Limpar blips de localização marcados
    if locationBlips.pickup then
        RemoveBlip(locationBlips.pickup)
        locationBlips.pickup = nil
    end
    if locationBlips.delivery then
        RemoveBlip(locationBlips.delivery)
        locationBlips.delivery = nil
    end

    if currentTrailer and DoesEntityExist(currentTrailer) then
        DeleteEntity(currentTrailer)
    end
    currentTrailer = nil
    currentJob = nil
    VP_Trucker_CurrentJobOriginId = nil
    activeJob = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CleanupLCContract()
        CloseJobBoard()

        if jobProgress.pickupBlip then
            RemoveBlip(jobProgress.pickupBlip)
        end
        if jobProgress.deliveryBlip then
            RemoveBlip(jobProgress.deliveryBlip)
        end
        if blips.lcHq then
            RemoveBlip(blips.lcHq)
        end

        -- Limpar blips de localização marcados
        if locationBlips.pickup then
            RemoveBlip(locationBlips.pickup)
            locationBlips.pickup = nil
        end
        if locationBlips.delivery then
            RemoveBlip(locationBlips.delivery)
            locationBlips.delivery = nil
        end

        if currentTrailer and DoesEntityExist(currentTrailer) then
            DeleteEntity(currentTrailer)
        end
        currentTrailer = nil
        currentJob = nil
        VP_Trucker_CurrentJobOriginId = nil
        activeJob = nil
    end
end)

-- ============================================================
-- BANKER NPC (LOANS)
-- ============================================================

local bankerPed = nil

local function SpawnBankerNPC()
    local model = GetHashKey(Config.Loans.BankerPed)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end

    bankerPed = CreatePed(4, model, Config.Loans.BankerLocation.x, Config.Loans.BankerLocation.y,
        Config.Loans.BankerLocation.z - 1.0, Config.Loans.BankerHeading, false, true)

    if not bankerPed or bankerPed == 0 or not DoesEntityExist(bankerPed) then
        bankerPed = nil
        return
    end

    SetEntityInvincible(bankerPed, true)
    SetBlockingOfNonTemporaryEvents(bankerPed, true)
    FreezeEntityPosition(bankerPed, true)

    local function requestLoanFlow(isCompanyLoan)
        local input = lib.inputDialog('Solicitar Empréstimo', {
            { type = 'number', label = 'Valor ($10.000 – $500.000)', min = Config.Loans.MinAmount, max = Config.Loans.MaxAmount, required = true },
        })
        if not input or not input[1] then return end

        local amount         = math.floor(tonumber(input[1]) or 0)
        local totalToPay     = math.ceil(amount * (1 + Config.Loans.InterestRate))
        local monthlyPayment = math.ceil(totalToPay / Config.Loans.NumInstallments)

        local confirmed = lib.alertDialog({
            header  = 'Simulação de Empréstimo',
            content = ('**Valor solicitado:** $%s\n**Total a pagar:** $%s\n**Parcela mínima:** $%s (×%s semanas)'):format(
                amount, totalToPay, monthlyPayment, Config.Loans.NumInstallments),
            centered = true,
            cancel   = true,
        })

        if confirmed ~= 'confirm' then return end

        TriggerServerEvent('aurp_trucker:requestLoan', amount, isCompanyLoan)
    end

    exports.ox_target:addLocalEntity(bankerPed, {
        {
            name     = 'loan_personal',
            label    = 'Solicitar Empréstimo Pessoal',
            icon     = 'fas fa-hand-holding-usd',
            distance = 2.5,
            onSelect = function()
                requestLoanFlow(false)
            end,
        },
        {
            name     = 'loan_company',
            label    = 'Solicitar Empréstimo Empresarial',
            icon     = 'fas fa-building',
            distance = 2.5,
            onSelect = function()
                requestLoanFlow(true)
            end,
        },
    })
end

CreateThread(function()
    while not VP_Trucker or not VP_Trucker.Ready do Wait(100) end
    SpawnBankerNPC()
end)

-- Cleanup separado: bankerPed é declarado aqui, depois do onResourceStop principal (linha ~1399)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if bankerPed and DoesEntityExist(bankerPed) then
        exports.ox_target:removeLocalEntity(bankerPed)
        DeleteEntity(bankerPed)
        bankerPed = nil
    end
end)

-- ============================================================
-- LOAN NUI BRIDGE
-- ============================================================

RegisterNUICallback('payLoan', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:payLoan', false, data.loanId, data.amount, data.isCompanyLoan)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

-- ============================================================
-- LOAN CLIENT EVENTS
-- ============================================================

RegisterNetEvent('aurp_trucker:client:loanUpdate', function(loanData)
    SendNUIMessage({ action = 'updateLoan', loan = loanData })
end)

-- ============================================================
-- REPO MAN — NUI BRIDGE
-- ============================================================

RegisterNUICallback('acceptRepoOrder', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:acceptRepoOrder', false, data.orderId)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('failRepoOrder', function(data, cb)
    -- Fire-and-forget: server processes Fail + broadcasts async
    TriggerServerEvent('aurp_trucker:failRepoOrder', data.orderId)
    cb({ success = true })
end)

-- ============================================================
-- REPO MAN — CLIENT EVENTS
-- ============================================================

RegisterNetEvent('aurp_trucker:client:updateRepoOrders', function(orders)
    SendNUIMessage({ action = 'updateRepoOrders', repoOrders = orders })
end)

RegisterNetEvent('aurp_trucker:client:startRepoMission', function(order)
    SendNUIMessage({ action = 'startRepoMission', repoOrder = order })
end)

RegisterNetEvent('aurp_trucker:client:repoMissionComplete', function(result)
    SendNUIMessage({ action = 'repoMissionComplete', payment = result and result.payment })
end)

-- ============================================================
-- NUI CALLBACKS: PARTY / CONVOY
-- ============================================================

RegisterNUICallback('partyCreate', function(data, cb)
    -- M-01: pcall previne crash silencioso da thread se o server-callback lançar erro/timeout
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:partyCreate', false)
    cb((ok and result) or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('partyInvite', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:partyInvite', false, data.targetName)
    cb((ok and result) or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('partyLeave', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:partyLeave', false)
    cb((ok and result) or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('partyDisband', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:partyDisband', false)
    cb((ok and result) or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('convoyStart', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:convoyStart', false)
    cb((ok and result) or { success = false, reason = 'Sem resposta do servidor' })
end)

-- ============================================================
-- NUI CALLBACKS: NPC DRIVERS
-- ============================================================

RegisterNUICallback('hireNpcDriver', function(data, cb)
    local coords = GetEntityCoords(PlayerPedId())
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:hireNpcDriver', false, data.profileIndex, coords)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('fireNpcDriver', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:fireNpcDriver', false, data.driverId)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('trainNpcDriver', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:trainNpcDriver', false, data.driverId)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('setNpcAllowIllegal', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:setNpcAllowIllegal', false, data.allowed)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

RegisterNUICallback('npcRespondEvent', function(data, cb)
    local ok, result = pcall(lib.callback.await, 'aurp_trucker:npcRespondEvent', false, data.eventId, data.response)
    cb(ok and result or { success = false, reason = 'Sem resposta do servidor' })
end)

-- ============================================================
-- NUI CALLBACKS: JOB ACTIONS
-- ============================================================

RegisterNUICallback('abandonJob', function(data, cb)
    TriggerServerEvent('aurp_trucker:abandonJob')
    cb({ success = true })
end)

-- =======================================
-- SISTEMA DE CONTRATOS (Entregas de Empresa)
-- =======================================

local currentContract = nil
local contractBlip = nil

RegisterNUICallback('negotiateContract', function(data, cb)
    local clientId = data.clientId
    local terms = data.terms
    if not clientId or not terms then cb('ok') return end
    CloseJobBoard()
    cb('ok')

    -- Usar callback síncrono para receber o contrato e marcar GPS
    CreateThread(function()
        local ok, result = pcall(lib.callback.await, 'aurp_trucker:negotiateContract', false, clientId, terms)
        if ok and result and result.success then
            local contract = result.contract
            if contract then
                currentContract = contract
                SetContractGPS(contract.currentStop)
                lib.notify({
                    title = 'Contrato Aceito!',
                    description = string.format('Pagamento: $%d | Siga o GPS!', contract.totalPayment or 0),
                    type = 'success',
                    duration = 10000
                })
            end
        elseif ok and result and result.error then
            lib.notify({ title = 'Erro', description = result.error, type = 'error' })
        end
    end)
end)

RegisterNUICallback('getClients', function(data, cb)
    local ok, clients = pcall(lib.callback.await, 'aurp_trucker:getClients', false)
    cb(ok and clients or {})
end)

RegisterNUICallback('contractGPS', function(data, cb)
    local locationId = data.locationId
    if not locationId then cb('ok') return end

    -- Buscar coords pelo location_id no Config
    local coords = nil
    for _, ind in ipairs(Config.PrimaryIndustries) do
        if ind.id == locationId then coords = ind.coords break end
    end
    if not coords then
        for _, ind in ipairs(Config.SecondaryIndustries) do
            if ind.id == locationId then coords = ind.coords break end
        end
    end

    if coords then
        SetWaypointOff()
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        lib.notify({ title = 'GPS', description = 'Rota marcada no GPS', type = 'inform' })
    else
        lib.notify({ title = 'GPS', description = 'Local não encontrado', type = 'error' })
    end
    cb('ok')
end)

RegisterNUICallback('abandonContract', function(data, cb)
    CloseJobBoard()
    TriggerServerEvent('aurp_trucker:abandonContract')
    cb('ok')
end)

local function SetContractGPS(stop)
    -- Remover blip anterior
    if contractBlip and DoesBlipExist(contractBlip) then
        RemoveBlip(contractBlip)
        contractBlip = nil
    end

    if not stop then return end

    local x = tonumber(stop.coords_x)
    local y = tonumber(stop.coords_y)
    local z = tonumber(stop.coords_z)
    if not x or not y then return end

    -- Blip no mapa
    local blip = AddBlipForCoord(x, y, z or 0.0)
    SetBlipSprite(blip, stop.action == 'pickup' and 478 or 473)
    SetBlipColour(blip, stop.action == 'pickup' and 2 or 3)
    SetBlipScale(blip, 1.0)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, stop.action == 'pickup' and 2 or 3)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString((stop.action == 'pickup' and 'COLETAR: ' or 'ENTREGAR: ') .. (stop.location_name or 'Local'))
    EndTextCommandSetBlipName(blip)
    contractBlip = blip

    -- Waypoint direto no GPS (mais confiável)
    SetNewWaypoint(x, y)

    -- Configurar ponto ox_lib otimizado (Resmon 0.00ms idle)
    UpdateContractPoint(stop)
end

function UpdateContractPoint(stop)
    if contractStopPoint then
        pcall(function() contractStopPoint:remove() end)
        contractStopPoint = nil
    end
    if lib and lib.hideTextUI then lib.hideTextUI() end
    if not stop then return end

    local sx = tonumber(stop.coords_x)
    local sy = tonumber(stop.coords_y)
    local sz = tonumber(stop.coords_z)
    if not sx or not sy then return end

    local stopCoords = vector3(sx, sy, sz or 0.0)
    contractStopPoint = lib.points.new({
        coords = stopCoords,
        distance = 35.0,
        nearby = function(self)
            if not currentContract or not currentContract.currentStop then return end
            DrawMarker(1, self.coords.x, self.coords.y, self.coords.z - 1.0,
                0, 0, 0, 0, 0, 0, 4.0, 4.0, 1.5,
                stop.action == 'pickup' and 0 or 0,
                stop.action == 'pickup' and 200 or 100,
                stop.action == 'pickup' and 0 or 255,
                120, false, true, 2, false, nil, nil, false)

            if self.currentDistance <= 5.0 then
                lib.showTextUI(stop.action == 'pickup'
                    and '[E] Coletar ' .. (stop.cargo_item or 'carga')
                    or '[E] Entregar ' .. (stop.cargo_item or 'carga'))

                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    if lib.progressBar({
                        duration = 5000,
                        label = stop.action == 'pickup' and 'Coletando carga...' or 'Entregando carga...',
                        useWhileDead = false,
                        canCancel = false,
                        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
                    }) then
                        TriggerServerEvent('aurp_trucker:completeContractStop', stop.stop_order)
                    end
                end
            else
                lib.hideTextUI()
            end
        end,
        onExit = function()
            if lib and lib.hideTextUI then lib.hideTextUI() end
        end
    })
end

RegisterNetEvent('aurp_trucker:client:contractStarted', function(contract)
    if not contract then return end
    currentContract = contract
    SetContractGPS(contract.currentStop)
    lib.notify({
        title = 'Contrato Aceito!',
        description = string.format('Pagamento: $%d | Siga o GPS!', contract.totalPayment or 0),
        type = 'success',
        duration = 10000
    })
end)

RegisterNetEvent('aurp_trucker:client:contractStopCompleted', function(contract)
    currentContract = contract
    SetContractGPS(contract and contract.currentStop)
    lib.notify({
        title = 'Parada Concluída!',
        description = 'Siga o GPS para a próxima parada',
        type = 'success'
    })
end)

RegisterNetEvent('aurp_trucker:client:contractCompleted', function()
    currentContract = nil
    if contractBlip and DoesBlipExist(contractBlip) then RemoveBlip(contractBlip) end
    contractBlip = nil
    UpdateContractPoint(nil)
    SetWaypointOff()
    lib.notify({ title = 'Contrato Concluído!', description = 'Pagamento depositado na sua conta.', type = 'success', duration = 8000 })
end)

-- =====================================================
-- LC LOGISTICS: QUICK JOBS EXECUTION
-- =====================================================

local function createVehicleMarkersThread(truck, trailer)
    CreateThread(function()
        local timer = 2000
        local tkMaxZ = 2.0
        local trMaxZ = 2.0

        if DoesEntityExist(truck) then
            local _, maxDim = GetModelDimensions(GetEntityModel(truck))
            if maxDim then tkMaxZ = maxDim.z end
        end

        if DoesEntityExist(trailer) then
            local _, maxDim = GetModelDimensions(GetEntityModel(trailer))
            if maxDim then trMaxZ = maxDim.z end
        end

        while lcActiveJob and (DoesEntityExist(truck) or DoesEntityExist(trailer)) do
            timer = 2000
            local ped = cache.ped or PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            local isAttached = (DoesEntityExist(truck) and DoesEntityExist(trailer)) and (
                IsEntityAttachedToEntity(trailer, truck) or 
                IsEntityAttachedToEntity(truck, trailer) or 
                IsVehicleAttachedToTrailer(truck)
            )

            if not isAttached then
                local hoverOffset = math.sin(GetGameTimer() / 200.0) * 0.2

                if DoesEntityExist(truck) then
                    local tkCoords = GetEntityCoords(truck)
                    local distTruck = #(pCoords - tkCoords)
                    if distTruck < 50.0 and GetVehiclePedIsIn(ped, false) ~= truck then
                        timer = 2
                        local pos = GetOffsetFromEntityInWorldCoords(truck, 0.0, 0.0, tkMaxZ + 1.2 + hoverOffset)
                        DrawMarker(0, pos.x, pos.y, pos.z,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            1.0, 1.0, 1.0,
                            0, 100, 255, 180, false, true, 2, false, nil, nil, false)
                    end
                end

                if DoesEntityExist(trailer) then
                    local trCoords = GetEntityCoords(trailer)
                    local distTrailer = #(pCoords - trCoords)
                    if distTrailer < 50.0 then
                        timer = 2
                        local pos = GetOffsetFromEntityInWorldCoords(trailer, 0.0, 0.0, trMaxZ + 1.2 + hoverOffset)
                        DrawMarker(0, pos.x, pos.y, pos.z,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            1.0, 1.0, 1.0,
                            0, 100, 255, 180, false, true, 2, false, nil, nil, false)
                    end
                end
            else
                break
            end

            Wait(timer)
        end
    end)
end

RegisterNetEvent('aurp_trucker:client:startLCContract', function(contract)
    if not contract or lcActiveJob then return end
    isStartingJob = true
    lcActiveJob = contract

    -- 1. Spawn do caminhão da firma
    local truckModel = contract.truckModel or 'hauler'
    local truckHash = joaat(truckModel)
    if not IsModelInCdimage(truckHash) or not IsModelValid(truckHash) then
        truckModel = 'hauler'
        truckHash = joaat('hauler')
    end
    lib.requestModel(truckHash)
    local tspawn = contract.truckSpawn or vector4(1250.55, -3162.4, 5.88, 270.00)
    local truck = CreateVehicle(truckHash, tspawn.x, tspawn.y, tspawn.z, tspawn.w, true, false)
    SetEntityHeading(truck, tspawn.w)
    SetVehicleOnGroundProperly(truck)
    SetVehicleNumberPlateText(truck, 'LC' .. math.random(1000, 9999))
    SetEntityAsMissionEntity(truck, true, true)
    SetVehicleHasBeenOwnedByPlayer(truck, true)
    if exports.qbx_vehiclekeys then pcall(function() exports.qbx_vehiclekeys:GiveKeys(truck) end) end
    if exports.ox_fuel then pcall(function() exports.ox_fuel:SetFuel(truck, 100.0) end) end

    -- 2. Spawn do reboque designado
    local trailerModel = contract.trailerModel or 'docktrailer'
    local trailerHash = joaat(trailerModel)
    if not IsModelInCdimage(trailerHash) or not IsModelValid(trailerHash) then
        trailerModel = 'docktrailer'
        trailerHash = joaat('docktrailer')
    end
    lib.requestModel(trailerHash)
    local trspawn = contract.trailerSpawn or vector4(1274.21, -3186.43, 5.91, 90.00)
    local trailer = CreateVehicle(trailerHash, trspawn.x, trspawn.y, trspawn.z, trspawn.w, true, false)
    SetEntityHeading(trailer, trspawn.w)
    SetVehicleOnGroundProperly(trailer)
    SetEntityAsMissionEntity(trailer, true, true)

    lcActiveJob.truck = truck
    lcActiveJob.trailer = trailer
    createVehicleMarkersThread(truck, trailer)

    -- 3. Marcar GPS e Blip de Destino
    local dest = contract.deliveryCoords
    SetNewWaypoint(dest.x, dest.y)

    if lcDeliveryBlip and DoesBlipExist(lcDeliveryBlip) then RemoveBlip(lcDeliveryBlip) end
    lcDeliveryBlip = AddBlipForCoord(dest.x, dest.y, dest.z)
    SetBlipSprite(lcDeliveryBlip, 477)
    SetBlipColour(lcDeliveryBlip, 3)
    SetBlipScale(lcDeliveryBlip, 0.9)
    SetBlipRoute(lcDeliveryBlip, true)
    SetBlipRouteColour(lcDeliveryBlip, 3)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Entrega: " .. (contract.cargoName or "Carga"))
    EndTextCommandSetBlipName(lcDeliveryBlip)

    lib.notify({
        title = 'Quick Job Iniciado!',
        description = ('Carga: %s | Recompensa: $%d\nCaminhão e reboque liberados na doca!'):format(contract.cargoName, contract.payment),
        type = 'success',
        duration = 8000
    })

    -- 4. Registro de Entidades e Chaves no Servidor
    CreateThread(function()
        local truckNetId = SafeGetNetworkId(truck)
        local trailerNetId = SafeGetNetworkId(trailer)
        if truckNetId or trailerNetId then
            TriggerServerEvent('aurp_trucker:server:registerJobEntities', truckNetId, trailerNetId)
        end
    end)

    -- 5. Loop de Entrega com DrawMarker 30 autoritativo (Padrão LC Truck Logistics)
    CreateThread(function()
        local destX, destY, destZ = dest.x, dest.y, dest.z
        local destH = dest.w or 0.0
        local thisJobId = contract.jobId
        local currentTextUi = nil
        while lcActiveJob and lcActiveJob.jobId == thisJobId and not isFinished do
            local timer = 1000
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local pCoords = GetEntityCoords(ped)
            local distance = #(pCoords - vector3(destX, destY, destZ))

            if distance <= 50.0 then
                timer = 2
                local tr = (lcActiveJob and lcActiveJob.trailer) or 0
                local tk = (lcActiveJob and lcActiveJob.truck) or veh

                local vehH = (veh ~= 0) and GetEntityHeading(veh) or 0.0
                local trH = (tr ~= 0 and DoesEntityExist(tr)) and GetEntityHeading(tr) or vehH
                local isAttached = (tr == 0 or not DoesEntityExist(tr)) or IsEntityAttachedToEntity(veh, tr)

                local vehDiff = math.abs((vehH - destH + 180) % 360 - 180)
                local trDiff = math.abs((trH - destH + 180) % 360 - 180)
                local isAligned = (vehDiff <= 10.0) and (trDiff <= 10.0) and isAttached

                if distance <= 4.0 and isAligned then
                    DrawMarker(30,destX,destY,destZ-0.6,0,0,0,90.0,destH,0.0,3.0,1.0,10.0,0,255,0,50,0,0,0,0)
                    if currentTextUi ~= 'park' then
                        lib.showTextUI('[E] Estacionar e Descarregar Carga')
                        currentTextUi = 'park'
                    end
                    if IsControlJustPressed(0, 38) and not isFinished then
                        isFinished = true
                        if currentTextUi ~= nil then
                            lib.hideTextUI()
                            currentTextUi = nil
                        end
                        BringVehicleToHalt(tk, 2.5, 1, false)
                        Wait(10)
                        DoScreenFadeOut(500)
                        Wait(500)
                        local trailerBody = (tr ~= 0 and DoesEntityExist(tr)) and GetVehicleBodyHealth(tr) or 1000
                        local truckEngine = (tk ~= 0 and DoesEntityExist(tk)) and GetVehicleEngineHealth(tk) or 1000
                        local truckBody = (tk ~= 0 and DoesEntityExist(tk)) and GetVehicleBodyHealth(tk) or 1000

                        TriggerServerEvent("truck_logistics:deliveredCargo")
                        TriggerServerEvent('aurp_trucker:server:completeLCContract', thisJobId, true)

                        PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                        Wait(1000)
                        DoScreenFadeIn(1000)
                        break
                    end
                else
                    if distance <= 15.0 then
                        if currentTextUi ~= 'align' then
                            lib.showTextUI('Alinhe o caminhão e o reboque na vaga demarcada')
                            currentTextUi = 'align'
                        end
                    else
                        if currentTextUi ~= nil then
                            lib.hideTextUI()
                            currentTextUi = nil
                        end
                    end
                    DrawMarker(30,destX,destY,destZ-0.6,0,0,0,90.0,destH,0.0,3.0,1.0,10.0,255,0,0,50,0,0,0,0)
                end
            else
                if currentTextUi ~= nil then
                    lib.hideTextUI()
                    currentTextUi = nil
                end
            end
            Wait(timer)
        end
        if currentTextUi ~= nil then
            lib.hideTextUI()
            currentTextUi = nil
        end
    end)
end)

RegisterNetEvent('truck_logistics:closeUIToStartContract', function()
    CloseJobBoard()
    SetNuiFocus(false, false)
end)

RegisterNetEvent('aurp_trucker:client:lcContractFinished', function(result)
    CleanupLCContract()

    local xpText = (result.xpGained and result.xpGained > 0) and (' | +%d XP'):format(result.xpGained) or ''
    local bonusText = ''
    if result.moneyBonusPct and result.moneyBonusPct > 0 then
        bonusText = (' (Bônus Habilidade: +%d%% $)'):format(result.moneyBonusPct)
    end
    lib.notify({
        title = 'Entrega Concluída!',
        description = ('Recebido: $%d%s%s | Distância: %.2f km\nVeículo da firma recolhido com sucesso!'):format(result.payment or 0, bonusText, xpText, result.distance or 0.0),
        type = 'success',
        duration = 10000
    })

    RefreshNUIData()
end)

RegisterNetEvent('truck_logistics:open', function(dados, utils)
    if isNUIOpen then return end
    isNUIOpen = true
    SetNuiFocus(true, true)
    local activeLocale = (utils and utils.config and utils.config.locale) or (dados and dados.config and dados.config.locale) or Config.locale or Config.lang or "br"
    local activeFormat = (utils and utils.config and utils.config.format) or (dados and dados.config and dados.config.format) or Config.format or { lang = activeLocale, currency = "USD", location = "pt-BR" }
    SendNUIMessage({
        showmenu     = true,
        update       = false,
        dados        = dados,
        utils        = {
            config = {
                locale = activeLocale,
                format = activeFormat,
            },
            lang = {}
        },
        resourceName = GetCurrentResourceName(),
        action       = 'open',
    })
end)

RegisterNetEvent('aurp_trucker:client:levelUp', function(data)
    lib.notify({
        title = 'Subiu de Nível!',
        description = ('Parabéns! Você alcançou o Nível %d!\nGanhou %d ponto(s) de habilidade.'):format(data.newLevel or 1, data.skillPoints or 1),
        type = 'success',
        duration = 8000
    })
    RefreshNUIData()
end)