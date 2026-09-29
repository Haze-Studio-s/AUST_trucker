-- =======================================================================
-- AUST_trucker — client/modules/forklift.lua
-- Módulo de Empilhadeira e Manipulação Física de Paletes (Stack Polarix / OX)
-- Zero Loops Obsoletos (Wait(0)) — Gerenciado via ox_lib.points e ox_target
-- =======================================================================

local ForkliftModule = {}
local CurrentForkliftPallet = nil
local CurrentTargetTrailer = nil
local ActiveMissionPallets = {}
local ForkliftPromptActive = false

-- =======================================================================
-- HELPERS DE ESTADO
-- =======================================================================

function ForkliftModule.IsPlayerInForklift()
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return false end
    return GetEntityModel(veh) == joaat(Config.Polarix.Forklift.VehicleModel or 'forklift')
end

function ForkliftModule.GetPlayerForklift()
    if not ForkliftModule.IsPlayerInForklift() then return nil end
    local ped = cache.ped or PlayerPedId()
    return GetVehiclePedIsIn(ped, false)
end

function ForkliftModule.GetCarriedPallet()
    return CurrentForkliftPallet
end

function ForkliftModule.SetMissionPallets(palletsTable)
    ActiveMissionPallets = palletsTable or {}
end

-- =======================================================================
-- BONE E COORDENADAS DOS GARFOS
-- =======================================================================

local function GetForkliftForksCoords(forklift)
    local boneName = Config.Polarix.Forklift.AttachBone or 'forks_attach'
    local boneIndex = GetEntityBoneIndexByName(forklift, boneName)
    if boneIndex == -1 then
        boneIndex = Config.Polarix.Forklift.ForkBoneIndex or 3
    end
    local coords = GetWorldPositionOfEntityBone(forklift, boneIndex)
    if coords == vector3(0, 0, 0) then
        return GetOffsetFromEntityInWorldCoords(forklift, 0.0, 1.8, 0.0), boneIndex
    end
    return coords, boneIndex
end

-- =======================================================================
-- CAPTURA DE PALETE DO CHÃO (LIFTING)
-- =======================================================================

function ForkliftModule.GetNearestGroundPallet(forklift)
    if not forklift or not DoesEntityExist(forklift) then return nil end
    local forkCoords = GetForkliftForksCoords(forklift)
    local bestEntity, bestDist = nil, 2.5

    for _, pallet in pairs(ActiveMissionPallets) do
        if pallet and DoesEntityExist(pallet) and not IsEntityAttached(pallet) then
            local pCoords = GetEntityCoords(pallet)
            local dist = #(forkCoords - pCoords)
            if dist < bestDist then
                bestDist = dist
                bestEntity = pallet
            end
        end
    end
    return bestEntity
end

function ForkliftModule.PickupPallet(targetPallet)
    local forklift = ForkliftModule.GetPlayerForklift()
    if not forklift then
        lib.notify({ title = 'Empilhadeira', description = 'Você deve estar operando a empilhadeira para içar a carga!', type = 'error' })
        return false
    end

    if CurrentForkliftPallet and DoesEntityExist(CurrentForkliftPallet) then
        lib.notify({ title = 'Empilhadeira', description = 'Já existe um palete engatado nos garfos!', type = 'error' })
        return false
    end

    targetPallet = targetPallet or ForkliftModule.GetNearestGroundPallet(forklift)
    if not targetPallet or not DoesEntityExist(targetPallet) then
        lib.notify({ title = 'Empilhadeira', description = 'Aproxime os garfos sob o palete para levantá-lo.', type = 'inform' })
        return false
    end

    local _, boneIndex = GetForkliftForksCoords(forklift)
    local offset = Config.Polarix.Forklift.AttachOffset or { x = 0.0, y = 1.25, z = -0.15 }

    FreezeEntityPosition(targetPallet, false)
    SetEntityCollision(targetPallet, true, true)

    AttachEntityToEntity(
        targetPallet, forklift, boneIndex,
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0,
        false, false, false, false, 2, true
    )

    SetEntityNoCollisionEntity(targetPallet, forklift, true)
    SetEntityNoCollisionEntity(forklift, targetPallet, true)

    CurrentForkliftPallet = targetPallet
    PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)

    lib.notify({
        title = 'Palete Içado',
        description = 'Carga travada nos garfos! Transporte até a carreta para acomodá-la.',
        type = 'success'
    })
    return true
end

-- =======================================================================
-- ACOPLAMENTO DO PALETE NA CARRETA (SLOT OFFSET CALIBRATION)
-- =======================================================================

function ForkliftModule.LoadPalletOntoTrailer(trailer, jobId, currentLoadedCount, maxAllowed)
    if not CurrentForkliftPallet or not DoesEntityExist(CurrentForkliftPallet) then
        lib.notify({ title = 'Carregamento', description = 'Nenhum palete carregado nos garfos da empilhadeira!', type = 'error' })
        return false
    end

    if not trailer or not DoesEntityExist(trailer) then
        lib.notify({ title = 'Carregamento', description = 'Reboque de carga não identificado nas proximidades.', type = 'error' })
        return false
    end

    local trModel = GetEntityModel(trailer)
    local trailerConfig = nil
    for modelName, cfg in pairs(Config.Polarix.CompatibleTrailers) do
        if joaat(modelName) == trModel then
            trailerConfig = cfg
            break
        end
    end

    if not trailerConfig then
        trailerConfig = Config.Polarix.CompatibleTrailers['trailers2']
    end

    local targetSlot = (currentLoadedCount or 0) + 1
    if targetSlot > (maxAllowed or (trailerConfig and trailerConfig.maxPallets) or 8) then
        lib.notify({ title = 'Capacidade Máxima', description = 'O compartimento da carreta está com a lotação máxima atingida!', type = 'error' })
        return false
    end

    -- REQUIREMENT 3: DYNAMIC PALLET PLACEMENT INSIDE SPAWNED VEHICLE
    -- Cálculo matemático dinâmico para organização dos volumes sem sobreposição
    local offset = nil
    if trailerConfig and trailerConfig.attachOffsets and trailerConfig.attachOffsets[targetSlot] then
        offset = trailerConfig.attachOffsets[targetSlot]
    else
        local isBoxTruck = (trModel == joaat('mule') or trModel == joaat('mule2') or trModel == joaat('mule3') or trModel == joaat('mule4') or trModel == joaat('mule5') or trModel == joaat('pounder') or trModel == joaat('pounder2') or trModel == joaat('biff'))

        if isBoxTruck then
            -- Caminhões tipo Baú (ex: Mule): Y = 0.0, Y = -1.5, Y = -3.0
            local startY = 0.0
            local stepY = 1.5
            local posY = startY - ((targetSlot - 1) * stepY)
            offset = { x = 0.0, y = posY, z = 0.15, rx = 0.0, ry = 0.0, rz = 0.0 }
        else
            -- Semirreboques e carretas convencionais: 2 colunas lado a lado
            local col = (targetSlot - 1) % 2
            local row = math.floor((targetSlot - 1) / 2)
            local posX = (col == 0) and -0.55 or 0.55
            local startY = 3.6
            local stepY = 2.4
            local posY = startY - (row * stepY)
            local posZ = (trailerConfig and trailerConfig.bedZ) or -0.85
            offset = { x = posX, y = posY, z = posZ, rx = 0.0, ry = 0.0, rz = 0.0 }
        end
    end

    local success = lib.progressCircle({
        duration = 3500,
        position = 'bottom',
        label = ('Acomodando palete no slot %d/%d...'):format(targetSlot, maxAllowed or (trailerConfig and trailerConfig.maxPallets) or 8),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    if not success then return false end

    if not CurrentForkliftPallet or not DoesEntityExist(CurrentForkliftPallet) then return false end

    local palletEntity = CurrentForkliftPallet
    DetachEntity(palletEntity, true, true)

    AttachEntityToEntity(
        palletEntity, trailer, 0,
        offset.x, offset.y, offset.z,
        offset.rx or 0.0, offset.ry or 0.0, offset.rz or 0.0,
        false, false, false, false, 2, true
    )

    SetEntityCollision(palletEntity, true, true)
    SetEntityNoCollisionEntity(palletEntity, trailer, true)
    SetEntityNoCollisionEntity(trailer, palletEntity, true)

    CurrentForkliftPallet = nil
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    -- Notifica o servidor para validar e persistir o estado do lobby
    TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, targetSlot)
    return true
end

-- =======================================================================
-- DESCARREGAMENTO DE PALETES NO DESTINO FINAL
-- =======================================================================

function ForkliftModule.UnloadPalletFromTrailer(trailer, jobId, slotIndex)
    if CurrentForkliftPallet and DoesEntityExist(CurrentForkliftPallet) then
        lib.notify({ title = 'Empilhadeira', description = 'Desocupe os garfos antes de retirar outro volume.', type = 'error' })
        return false
    end

    local forklift = ForkliftModule.GetPlayerForklift()
    if not forklift then
        lib.notify({ title = 'Empilhadeira', description = 'Você precisa estar na empilhadeira para descarregar!', type = 'error' })
        return false
    end

    local success = lib.progressCircle({
        duration = 3000,
        position = 'bottom',
        label = 'Retirando palete da carreta...',
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    })

    if not success then return false end

    -- Solicita ao servidor desanexação segura
    TriggerServerEvent('aurp_trucker:server:polarixPalletUnloaded', jobId, slotIndex)
    return true
end

-- =======================================================================
-- REGISTRO DE INTERAÇÕES OX_TARGET NA EMPILHADEIRA E CARRETA
-- =======================================================================

function ForkliftModule.SetupTrailerTarget(trailer, jobId, getJobStateCb)
    if not trailer or not DoesEntityExist(trailer) then return end

    exports.ox_target:addLocalEntity(trailer, {
        {
            name = 'polarix_load_pallet_trailer',
            icon = 'fa-solid fa-pallet',
            label = 'Acomodar Palete na Carreta',
            distance = Config.Polarix.Forklift.InteractionRadiusVehicle or 5.5,
            canInteract = function()
                local state = getJobStateCb and getJobStateCb()
                return state == 'STATUS_LOADING' and ForkliftModule.IsPlayerInForklift() and ForkliftModule.GetCarriedPallet() ~= nil
            end,
            onSelect = function()
                local state, loaded, req = getJobStateCb and getJobStateCb()
                ForkliftModule.LoadPalletOntoTrailer(trailer, jobId, loaded, req)
            end
        }
    })
end

-- Tecla G de conveniência quando os garfos estiverem alinhados
lib.addKeybind({
    name = 'aust_forklift_pickup_pallet',
    description = 'Içar Palete com a Empilhadeira',
    defaultKey = 'G',
    onPressed = function()
        if ForkliftModule.IsPlayerInForklift() and not ForkliftModule.GetCarriedPallet() then
            local target = ForkliftModule.GetNearestGroundPallet(ForkliftModule.GetPlayerForklift())
            if target then
                ForkliftModule.PickupPallet(target)
            end
        end
    end
})

return ForkliftModule
