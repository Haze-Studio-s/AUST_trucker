-- aurp_trucker — client/modules/early_game.lua
-- FASE 2: MÓDULO 3 - TIERS INICIAIS (CAIXAS MANUAIS & PALETEIRA MANUAL)

EarlyGameModule = {}

local CarriedBoxObj = nil
local IsCarryingBox = false
local CarriedBoxIndex = 0
local CurrentJobId = nil
local TargetTrailer = nil
local RequiredBoxes = 6
local LoadedBoxes = 0
local BoxEntities = {}
local EarlyGamePoints = {}

-- Desativa corrida e pulo enquanto carrega a caixa pesada
local function StartCarryControlsWatcher()
    CreateThread(function()
        while IsCarryingBox do
            DisableControlAction(0, 21, true) -- Disable Sprint (Shift)
            DisableControlAction(0, 22, true) -- Disable Jump (Space)
            DisableControlAction(0, 24, true) -- Disable Attack (LMB)
            DisableControlAction(0, 25, true) -- Disable Aim (RMB)
            DisableControlAction(0, 140, true) -- Disable Melee Light
            DisableControlAction(0, 141, true) -- Disable Melee Heavy
            DisableControlAction(0, 142, true) -- Disable Melee Alternate

            local ped = cache.ped or PlayerPedId()
            if not IsEntityPlayingAnim(ped, 'anim@heists@box_carry@', 'idle', 3) then
                TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 3.0, 3.0, -1, 49, 0, false, false, false)
            end
            Wait(0)
        end
    end)
end

-- Pega uma caixa da pilha de carga
local function PickupBox(boxIndex, boxEntity)
    if IsCarryingBox then return end

    local ped = cache.ped or PlayerPedId()
    local animDict = 'anim@heists@box_carry@'
    lib.requestAnimDict(animDict)

    local modelHash = joaat((Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.PropModel) or 'prop_cardbordbox_02a')
    lib.requestModel(modelHash)

    TaskPlayAnim(ped, animDict, 'idle', 3.0, 3.0, -1, 49, 0, false, false, false)

    local coords = GetEntityCoords(ped)
    local boxObj = CreateObject(modelHash, coords.x, coords.y, coords.z, true, true, false)
    SetEntityCollision(boxObj, false, false)

    local bone = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.AttachBone) or 60309
    local offset = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.AttachOffset) or vector3(0.08, 0.08, 0.0)
    local rot = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.AttachRot) or vector3(-90.0, 0.0, 0.0)

    AttachEntityToEntity(boxObj, ped, GetPedBoneIndex(ped, bone), offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)

    CarriedBoxObj = boxObj
    IsCarryingBox = true
    CarriedBoxIndex = boxIndex

    -- Oculta ou remove visualmente a caixa do chão
    if boxEntity and DoesEntityExist(boxEntity) then
        SetEntityVisible(boxEntity, false)
    end

    StartCarryControlsWatcher()

    -- Aponta seta para a traseira do veículo/reboque
    if TargetTrailer and DoesEntityExist(TargetTrailer) then
        local rearCoords = GetOffsetFromEntityInWorldCoords(TargetTrailer, 0.0, -5.5, 0.5)
        UpdateMissionObjective('trailer_rear', rearCoords, 'Deposite a caixa na traseira da carreta')
    end

    lib.notify({
        title = 'Carga Pesada',
        description = 'Você pegou uma caixa pesada. Transporte-a até a traseira do caminhão.',
        type = 'info'
    })
end

-- Deposita a caixa no compartimento de carga
local function DepositBox()
    if not IsCarryingBox then return end

    local ped = cache.ped or PlayerPedId()

    if lib.progressBar then
        lib.progressBar({
            duration = 1500,
            label = 'Embarcando Caixa no Baú...',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true }
        })
    else
        Wait(1500)
    end

    IsCarryingBox = false
    ClearPedTasks(ped)

    if CarriedBoxObj and DoesEntityExist(CarriedBoxObj) then
        DetachEntity(CarriedBoxObj, true, true)
        DeleteEntity(CarriedBoxObj)
        CarriedBoxObj = nil
    end

    LoadedBoxes = LoadedBoxes + 1
    TriggerServerEvent('aurp_trucker:server:boxLoaded', CurrentJobId, CarriedBoxIndex)

    if LoadedBoxes < RequiredBoxes then
        lib.notify({
            title = 'Caixa Carregada',
            description = ('Caixa embarcada! (%d/%d caixas carregadas)'):format(LoadedBoxes, RequiredBoxes),
            type = 'success'
        })
    end
end

-- Inicia o ciclo do Tier 1: Caixas Fracionadas
function EarlyGameModule.StartBoxesLoading(jobId, trailer, totalBoxes, boxEntities)
    CurrentJobId = jobId
    TargetTrailer = trailer
    RequiredBoxes = totalBoxes or 6
    LoadedBoxes = 0
    BoxEntities = boxEntities or {}

    -- Limpa pontos anteriores
    for _, pt in ipairs(EarlyGamePoints) do
        pcall(function() pt:remove() end)
    end
    EarlyGamePoints = {}

    -- Ponto de Coleta das Caixas
    local stagingCoords = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.LoadingStaging) or vector3(1243.50, -3168.20, 5.50)
    local pickupPoint = lib.points.new({
        coords = stagingCoords,
        distance = 3.5,
        onEnter = function()
            if not IsCarryingBox and LoadedBoxes < RequiredBoxes then
                lib.showTextUI('[E] - Pegar Caixa de Carga', { position = 'left-center' })
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        nearby = function(self)
            if not IsCarryingBox and LoadedBoxes < RequiredBoxes then
                DrawMarker(2, self.coords.x, self.coords.y, self.coords.z + 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 255, 165, 0, 200, false, true, 2, false, nil, nil, false)
                if IsControlJustPressed(0, 38) then -- [E]
                    local targetBox = BoxEntities[LoadedBoxes + 1]
                    PickupBox(LoadedBoxes + 1, targetBox)
                end
            end
        end
    })
    table.insert(EarlyGamePoints, pickupPoint)

    -- Ponto de Depósito na Traseira do Caminhão/Trailer
    CreateThread(function()
        while LoadedBoxes < RequiredBoxes and CurrentJobId == jobId do
            if TargetTrailer and DoesEntityExist(TargetTrailer) then
                local rearCoords = GetOffsetFromEntityInWorldCoords(TargetTrailer, 0.0, -5.5, 0.0)
                local ped = cache.ped or PlayerPedId()
                local dist = #(GetEntityCoords(ped) - rearCoords)

                if dist < 3.0 and IsCarryingBox then
                    lib.showTextUI('[E] - Embarcar Caixa no Caminhão', { position = 'left-center' })
                    DrawMarker(2, rearCoords.x, rearCoords.y, rearCoords.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.6, 50, 200, 50, 200, false, true, 2, false, nil, nil, false)
                    if IsControlJustPressed(0, 38) then
                        lib.hideTextUI()
                        DepositBox()
                    end
                end
            end
            Wait(0)
        end
    end)

    lib.notify({
        title = 'Carregamento Manual',
        description = ('Pegue as caixas na pilha do pátio e leve-as até a traseira do caminhão (%d caixas no total).'):format(RequiredBoxes),
        type = 'info'
    })
    UpdateMissionObjective('boxes', stagingCoords, 'Pilha de Caixas de Carga')
end

-- Inicia o ciclo do Tier 2: Paleteira Manual
function EarlyGameModule.StartPalletJackLoading(jobId, trailer, totalBatches, entities)
    CurrentJobId = jobId
    TargetTrailer = trailer
    RequiredBoxes = totalBatches or 4
    LoadedBoxes = 0

    local stagingCoords = (Config.EarlyGame and Config.EarlyGame.Boxes and Config.EarlyGame.Boxes.LoadingStaging) or vector3(1243.50, -3168.20, 5.50)

    -- Ponto de manuseio da paleteira
    local jackPoint = lib.points.new({
        coords = stagingCoords,
        distance = 4.0,
        onEnter = function()
            if LoadedBoxes < RequiredBoxes then
                lib.showTextUI('[E] - Operar Paleteira Manual', { position = 'left-center' })
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        nearby = function(self)
            if LoadedBoxes < RequiredBoxes then
                DrawMarker(2, self.coords.x, self.coords.y, self.coords.z + 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.6, 255, 215, 0, 200, false, true, 2, false, nil, nil, false)
                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    if lib.progressBar then
                        lib.progressBar({
                            duration = 3000,
                            label = 'Manuseando Paleteira Manual...',
                            useWhileDead = false,
                            canCancel = false,
                            disable = { move = true, car = true }
                        })
                    else
                        Wait(3000)
                    end

                    LoadedBoxes = LoadedBoxes + 1
                    TriggerServerEvent('aurp_trucker:server:palletJackBatchLoaded', CurrentJobId, LoadedBoxes)

                    if LoadedBoxes < RequiredBoxes then
                        lib.notify({
                            title = 'Lote Embarcado',
                            description = ('Lote %d/%d embarcado com a paleteira!'):format(LoadedBoxes, RequiredBoxes),
                            type = 'success'
                        })
                    end
                end
            end
        end
    })
    table.insert(EarlyGamePoints, jackPoint)

    lib.notify({
        title = 'Paleteira Manual',
        description = ('Opere a paleteira manual no pátio para embarcar os lotes na carreta (%d lotes).'):format(RequiredBoxes),
        type = 'info'
    })
    UpdateMissionObjective('pallet_jack', stagingCoords, 'Área de Lotes da Paleteira')
end

-- Sincronização multi-cliente de caixas e paletes carregados
RegisterNetEvent('aurp_trucker:client:boxLoadedSync', function(loadedCount, requiredCount, boxIndex)
    LoadedBoxes = loadedCount
    RequiredBoxes = requiredCount
    if BoxEntities[boxIndex] and DoesEntityExist(BoxEntities[boxIndex]) then
        SetEntityVisible(BoxEntities[boxIndex], false)
    end
end)

RegisterNetEvent('aurp_trucker:client:palletJackBatchSync', function(loadedCount, requiredCount, batchIndex)
    LoadedBoxes = loadedCount
    RequiredBoxes = requiredCount
end)

-- Limpeza ao encerrar frete
function EarlyGameModule.Cleanup()
    IsCarryingBox = false
    if CarriedBoxObj and DoesEntityExist(CarriedBoxObj) then
        DetachEntity(CarriedBoxObj, true, true)
        DeleteEntity(CarriedBoxObj)
        CarriedBoxObj = nil
    end
    for _, pt in ipairs(EarlyGamePoints) do
        pcall(function() pt:remove() end)
    end
    EarlyGamePoints = {}
    BoxEntities = {}
    LoadedBoxes = 0
end

