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

local function SpawnTrailer(model, coords)
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

    local trailer = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, true, false)

    if trailer and trailer ~= 0 then
        SetVehicleEngineOn(trailer, false, false, false)
        SetVehicleNumberPlateText(trailer, "AURP" .. math.random(1000, 9999))
        SetEntityAsMissionEntity(trailer, true, true)
        SetModelAsNoLongerNeeded(modelHash)
        return trailer
    else
        SetModelAsNoLongerNeeded(modelHash)
        return nil
    end
end

local function GetPlayerTrailer()
    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 DEBUG GetPlayerTrailer: Verificando trailer...")
    end

    -- Primeiro verificar se existe um trailer spawned pelo sistema
    if currentTrailer and DoesEntityExist(currentTrailer) then
        if Config.Debug then
            print("^2[AURP_TRUCKER]^7 DEBUG GetPlayerTrailer: Encontrado currentTrailer = " .. tostring(currentTrailer))
        end
        return currentTrailer
    else
        if Config.Debug then
            print("^2[AURP_TRUCKER]^7 DEBUG GetPlayerTrailer: currentTrailer = " .. tostring(currentTrailer) .. " | Existe = " .. tostring(currentTrailer and DoesEntityExist(currentTrailer)))
        end
    end

    -- Se não há trailer do sistema, verificar se há um acoplado
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 DEBUG GetPlayerTrailer: Veículo do jogador = " .. tostring(vehicle))
    end

    if vehicle and vehicle ~= 0 then
        local trailer = GetVehicleTrailerVehicle(vehicle)
        if Config.Debug then
            print("^2[AURP_TRUCKER]^7 DEBUG GetPlayerTrailer: Trailer acoplado = " .. tostring(trailer))
        end
        if trailer and trailer ~= 0 then
            return trailer
        end
    end

    if Config.Debug then
        print("^1[AURP_TRUCKER]^7 DEBUG GetPlayerTrailer: Nenhum trailer encontrado")
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

-- Notificação genérica do servidor
RegisterNetEvent('aurp_trucker:notify', function(title, message, notifType)
    lib.notify({ title = title, description = message, type = notifType or 'inform' })
end)

-- Atualização de empresa: companyInfo = tabela → entrou/atualizou; nil → saiu
RegisterNetEvent('aurp_trucker:client:companyUpdated', function(companyInfo)
    SendNUIMessage({ action = 'updateCompany', company = companyInfo or nil })
end)


-- =======================================
-- SISTEMA NUI
-- =======================================

local function CloseJobBoard()
    if not isNUIOpen then return end

    isNUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
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

    -- action 'open' é a única que o NUI React reconhece para abrir a tela
    SendNUIMessage({
        action              = 'open',
        jobs                = data.jobs or {},
        company             = data.company,
        activeJob           = data.activeJob,
        stats               = data.stats,
        recruitingCompanies = data.recruitingCompanies or {},
        skills              = data.skills,
        personalLoan        = data.personalLoan,
        companyLoan         = data.companyLoan,
        repoOrders          = data.repoOrders,
        activeRepoOrder     = data.activeRepoOrder,
        ownedIndustries     = data.ownedIndustries,
        currentParty        = data.currentParty,
        npcDrivers          = data.npcDrivers,
        adrCerts            = data.adrCerts,
        clients             = data.clients or {},
        activeContract      = data.activeContract,
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

-- NUI Callbacks
RegisterNUICallback('closeUI', function(data, cb)
    CloseJobBoard()
    cb('ok')
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
    -- currentTrailer = nil -- Manter o trailer para reutilização

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
-- SISTEMA DE INTERAÇÕES COM BLIPS
-- =======================================

CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local isNearInteraction = false

        -- interação com empresa via NPC + ox_target (sem proximity manual)

        -- Verificar proximidade com blips marcados manualmente e removê-los ao chegar perto
        if locationBlips.pickup and currentJob then
            local pickupDist = #(playerCoords - currentJob.pickup.coords)
            if pickupDist <= 50.0 then
                RemoveBlip(locationBlips.pickup)
                locationBlips.pickup = nil
            end
        end

        if locationBlips.delivery and currentJob then
            local deliveryDist = #(playerCoords - currentJob.delivery.coords)
            if deliveryDist <= 50.0 then
                RemoveBlip(locationBlips.delivery)
                locationBlips.delivery = nil
            end
        end

        -- Verificar proximidade com pickup do trabalho atual
        if currentJob and jobProgress.stage == 'pickup' then
            local pickupDistance = #(playerCoords - currentJob.pickup.coords)
            if pickupDistance <= 50.0 then
                isNearInteraction = true
                CreateGroundMarker(currentJob.pickup.coords, 0, 255, 0, 150) -- Verde

                local inVehicle = IsPedInAnyVehicle(playerPed, false)
                if inVehicle then
                    DrawText3D(currentJob.pickup.coords, "[E] Carregar " .. currentJob.cargo)
                else
                    DrawText3D(currentJob.pickup.coords, "Entre no caminhão para carregar")
                end

                if pickupDistance <= 3.0 and IsControlJustPressed(0, 38) then -- E key
                    StartLoading()
                end
            end
        end

        -- Verificar proximidade com delivery do trabalho atual
        if currentJob and jobProgress.stage == 'delivering' then
            local deliveryDistance = #(playerCoords - currentJob.delivery.coords)
            if deliveryDistance <= 50.0 then
                isNearInteraction = true
                CreateGroundMarker(currentJob.delivery.coords, 0, 150, 255, 150) -- Azul

                local inVehicle = IsPedInAnyVehicle(playerPed, false)
                if inVehicle then
                    DrawText3D(currentJob.delivery.coords, "[E] Entregar " .. currentJob.cargo)
                else
                    DrawText3D(currentJob.delivery.coords, "Entre no caminhão para entregar")
                end

                if deliveryDistance <= 3.0 and IsControlJustPressed(0, 38) then -- E key
                    StartUnloading()
                end
            end
        end

        -- Mostrar help text se estiver perto de alguma interação
        if isNearInteraction then
            ShowHelpText("Pressione ~INPUT_CONTEXT~ para interagir")
        end

        Wait(isNearInteraction and 0 or 500)
    end
end)

-- =======================================
-- INICIALIZAÇÃO
-- =======================================

CreateThread(function()
    Wait(2000)

    -- Criar blip da empresa
    blips.trailerCompany = CreateBlip(
        Config.TrailerCompany.coords,
        477, -- truck icon
        5, -- yellow
        Config.TrailerCompany.name,
        0.8
    )

    -- Spawnar NPC despachante na central
    local coords  = Config.TrailerCompany.coords
    local heading = Config.TrailerCompany.spawnCoords and Config.TrailerCompany.spawnCoords.w or 180.0
    local model = GetHashKey('a_m_m_business_01')
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local dispatcherPed = CreatePed(4, model, coords.x, coords.y, coords.z, heading, false, true)
    SetEntityInvincible(dispatcherPed, true)
    SetBlockingOfNonTemporaryEvents(dispatcherPed, true)
    FreezeEntityPosition(dispatcherPed, true)
    SetModelAsNoLongerNeeded(model)

    if dispatcherPed and dispatcherPed ~= 0 and DoesEntityExist(dispatcherPed) then
        exports.ox_target:addLocalEntity(dispatcherPed, {
            {
                name     = 'open_job_board',
                icon     = 'fas fa-clipboard-list',
                label    = 'Central de Trabalhos',
                distance = 3.0,
                onSelect = function()
                    CreateThread(OpenJobBoard)
                end,
            },
        })
    end

    -- Cleanup ao parar o recurso
    AddEventHandler('onResourceStop', function(res)
        if res ~= GetCurrentResourceName() then return end
        if dispatcherPed and DoesEntityExist(dispatcherPed) then
            exports.ox_target:removeLocalEntity(dispatcherPed)
            DeleteEntity(dispatcherPed)
        end
    end)

    if Config.Debug then
        print("^2[AURP_TRUCKER]^7 NPC despachante criado na central de trabalhos")
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

    -- Spawn à frente do jogador
    local forward = GetEntityForwardVector(ped)
    local spawnPos = coords + forward * 5.0
    local vehicle = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)

    if vehicle and vehicle ~= 0 then
        SetVehicleNumberPlateText(vehicle, result.plate)
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleEngineOn(vehicle, false, false, false)
        SetVehicleDoorsLocked(vehicle, 1) -- destrancado
        SetModelAsNoLongerNeeded(modelHash)

        -- Dar chave ao jogador via qbx_vehiclekeys
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId and netId ~= 0 then
            TriggerServerEvent('qbx_vehiclekeys:server:tookKeys', netId)
        end

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
AddEventHandler('aurp_trucker:client:jobsUpdated', function()
    if not IsNUIFocused() then return end
    local ok, data = pcall(lib.callback.await, 'aurp_trucker:getInitialData', false)
    if ok and data and data.jobs then
        SendNUIMessage({ action = 'updateJobs', jobs = data.jobs })
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
    if blips.trailerCompany then
        RemoveBlip(blips.trailerCompany)
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
        CloseJobBoard()

        if jobProgress.pickupBlip then
            RemoveBlip(jobProgress.pickupBlip)
        end
        if jobProgress.deliveryBlip then
            RemoveBlip(jobProgress.deliveryBlip)
        end
        if blips.trailerCompany then
            RemoveBlip(blips.trailerCompany)
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
    SetWaypointOff()
    lib.notify({ title = 'Contrato Concluído!', description = 'Pagamento depositado na sua conta.', type = 'success', duration = 8000 })
end)

-- Loop de detecção de chegada nas paradas do contrato
CreateThread(function()
    while true do
        Wait(2000)
        if currentContract and currentContract.currentStop then
            local stop = currentContract.currentStop
            local sx = tonumber(stop.coords_x)
            local sy = tonumber(stop.coords_y)
            local sz = tonumber(stop.coords_z)
            if sx and sy then
                local ped = PlayerPedId()
                local playerCoords = GetEntityCoords(ped)
                local stopCoords = vector3(sx, sy, sz or 0.0)
                local dist = #(playerCoords - stopCoords)

                if dist <= 30.0 then
                    -- Mostrar marcador e texto
                    while dist <= 30.0 and currentContract and currentContract.currentStop do
                        Wait(0)
                        local pCoords = GetEntityCoords(PlayerPedId())
                        dist = #(pCoords - stopCoords)

                        DrawMarker(1, stopCoords.x, stopCoords.y, stopCoords.z - 1.0,
                            0, 0, 0, 0, 0, 0,
                            4.0, 4.0, 2.0,
                            stop.action == 'pickup' and 0 or 0,
                            stop.action == 'pickup' and 200 or 100,
                            stop.action == 'pickup' and 0 or 255,
                            100, false, true, 2, false, nil, nil, false)

                        if dist <= 5.0 then
                            lib.showTextUI(stop.action == 'pickup'
                                and '[E] Coletar ' .. (stop.cargo_item or 'carga')
                                or '[E] Entregar ' .. (stop.cargo_item or 'carga'))

                            if IsControlJustPressed(0, 38) then -- E key
                                lib.hideTextUI()

                                -- Progress bar
                                if lib.progressBar({
                                    duration = stop.action == 'pickup' and 5000 or 5000,
                                    label = stop.action == 'pickup' and 'Coletando carga...' or 'Entregando carga...',
                                    useWhileDead = false,
                                    canCancel = false,
                                    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
                                }) then
                                    -- Completar parada no server
                                    TriggerServerEvent('aurp_trucker:completeContractStop', stop.stop_order)
                                end
                                break
                            end
                        else
                            lib.hideTextUI()
                        end
                    end
                    lib.hideTextUI()
                end
            end
        end
    end
end)