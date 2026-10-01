-- =======================================================================
-- AUST_trucker — client/modules/forklift.lua
-- Módulo de Empilhadeira e Mecânica da Tecla [G] (Padrão Polarix / QBOX)
-- Zero Loops Ineficientes — Thread Dinâmica e Sincronização Server-Side
-- =======================================================================

local ForkliftModule = {}
local CurrentForkliftPallet = nil
local ActiveMissionPallets = {}
local OperationActive = false
local TextUIShowing = nil

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

local function GetForkliftForksCoords(forklift)
    local boneIndex = GetEntityBoneIndexByName(forklift, 'forks')
    if boneIndex == -1 then
        boneIndex = GetEntityBoneIndexByName(forklift, 'forks_attach')
    end
    if boneIndex == -1 then
        boneIndex = Config.Polarix.Forklift.ForkBoneIndex or 3
    end
    local coords = GetWorldPositionOfEntityBone(forklift, boneIndex)
    if coords == vector3(0, 0, 0) then
        return GetOffsetFromEntityInWorldCoords(forklift, 0.0, 1.8, 0.0), boneIndex
    end
    return coords, boneIndex
end

function ForkliftModule.GetNearestGroundPallet(forklift)
    if not forklift or not DoesEntityExist(forklift) then return nil end
    local forkCoords = GetForkliftForksCoords(forklift)
    local bestEntity, bestDist = nil, 2.8

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

local function GetTrailerAttachOffset(trailer, loadedIndex)
    if trailer and DoesEntityExist(trailer) and Config and Config.Polarix and Config.Polarix.CompatibleTrailers then
        local model = GetEntityModel(trailer)
        for tName, tData in pairs(Config.Polarix.CompatibleTrailers) do
            if joaat(tName) == model and tData.attachOffsets then
                local offset = tData.attachOffsets[loadedIndex + 1]
                if offset then
                    return offset.x, offset.y, offset.z
                end
            end
        end
    end
    -- Fallback dinâmico organizado em fileiras duplas
    local col = (loadedIndex % 2 == 0) and -0.55 or 0.55
    local row = math.floor(loadedIndex / 2)
    local yOffset = 2.8 - (row * 2.8)
    return col, yOffset, 0.35
end

local function AttachPalletToForklift(forklift, pallet)
    -- 1. Garante controle de rede sobre o prop
    local timeout = 2000
    while not NetworkHasControlOfEntity(pallet) and timeout > 0 do
        NetworkRequestControlOfEntity(pallet)
        Wait(50)
        timeout = timeout - 50
    end

    if not NetworkHasControlOfEntity(pallet) then
        print(("[AUST_Trucker] Falha ao obter controle de rede do palete %s"):format(tostring(pallet)))
        return false
    end

    -- 2. Descongela a posição no mundo
    FreezeEntityPosition(pallet, false)

    -- 3. Desativa colisões temporariamente para não colidir com os garfos/chassi
    SetEntityCollision(pallet, false, false)

    -- 4. Anexa ao bone 'forks' da empilhadeira com offset Z rebaixado
    local forkBone = GetEntityBoneIndexByName(forklift, 'forks')
    if forkBone == -1 then forkBone = 0 end

    local offset = Config.ForkliftAttachOffset or vector3(0.0, 1.2, -0.42)
    AttachEntityToEntity(
        pallet, 
        forklift, 
        forkBone, 
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0, 
        false, false, false, false, 2, true
    )
    return true
end

function ForkliftModule.StartOperation(jobId, trailer, requiredCount, onLoadedCb, onAllLoadedCb)
    OperationActive = true
    local loadedCount = 0

    CreateThread(function()
        while OperationActive do
            local sleep = 250
            local forklift = ForkliftModule.GetPlayerForklift()

            if forklift and DoesEntityExist(forklift) then
                if not CurrentForkliftPallet then
                    -- Caso 1: Buscar palete no chão
                    local targetPallet = ForkliftModule.GetNearestGroundPallet(forklift)
                    if targetPallet and DoesEntityExist(targetPallet) then
                        sleep = 0
                        if TextUIShowing ~= 'pickup' then
                            lib.showTextUI('[G] Pegar Pallet', { position = 'left-center', icon = 'pallet' })
                            TextUIShowing = 'pickup'
                        end

                        if IsControlJustPressed(0, 47) then -- Tecla G (control 47)
                            local ok = AttachPalletToForklift(forklift, targetPallet)
                            if ok then
                                CurrentForkliftPallet = targetPallet
                                PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)

                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end

                                if onLoadedCb then
                                    onLoadedCb('picked', targetPallet, loadedCount, requiredCount)
                                end
                            end
                        end
                    else
                        if TextUIShowing == 'pickup' then
                            lib.hideTextUI()
                            TextUIShowing = nil
                        end
                    end
                else
                    -- Caso 2: Acomodar palete na carreta (Estiva Manual / Posicionamento Livre na Caçamba)
                    if trailer and DoesEntityExist(trailer) then
                        local palletEntity = CurrentForkliftPallet
                        local pCoords = palletEntity and DoesEntityExist(palletEntity) and GetEntityCoords(palletEntity) or GetEntityCoords(forklift)
                        local relPos = GetOffsetFromEntityGivenWorldCoords(trailer, pCoords.x, pCoords.y, pCoords.z)

                        -- Validação da zona da caçamba do reboque:
                        -- Largura X [-1.45, 1.45], Comprimento Y [-6.2, 5.0], Altura Z [-0.5, 1.8]
                        local isOverTrailerBed = (math.abs(relPos.x) <= 1.55) and (relPos.y >= -6.5 and relPos.y <= 5.2) and (relPos.z >= -0.8 and relPos.z <= 2.2)

                        if isOverTrailerBed then
                            sleep = 0
                            if TextUIShowing ~= 'drop' then
                                lib.showTextUI('[G] Soltar / Estivar Palete na Carreta', { position = 'left-center', icon = 'truck-ramp-box' })
                                TextUIShowing = 'drop'
                            end

                            if IsControlJustPressed(0, 47) then -- Tecla G (control 47)
                                -- Garante controle de rede antes de desanexar/anexar
                                local timeout = 2000
                                while not NetworkHasControlOfEntity(palletEntity) and timeout > 0 do
                                    NetworkRequestControlOfEntity(palletEntity)
                                    Wait(50)
                                    timeout = timeout - 50
                                end

                                DetachEntity(palletEntity, true, true)

                                -- Rotação e orientação relativas ao reboque para respeitar o ângulo solto pelo jogador
                                local tRot = GetEntityRotation(trailer, 2)
                                local pRot = GetEntityRotation(palletEntity, 2)
                                local relHeading = pRot.z - tRot.z

                                -- Estiva manual com Trava do Eixo Z (Z-Axis Clamp) e Gap de 1cm anti-clipping:
                                local deckZ = (_G.GetTrailerDeckZ and _G.GetTrailerDeckZ(trailer))
                                if not deckZ then
                                    local _, tMax = GetModelDimensions(GetEntityModel(trailer))
                                    deckZ = tMax.z - 0.14
                                end
                                local safeZ = deckZ + 0.01 -- Gap de 1cm para evitar clipping e capotamento por Havok

                                -- 1. PREPARAÇÃO DA ENTIDADE (ANTES DO ATTACH)
                                SetEntityDynamic(palletEntity, false)
                                SetEntityNoCollisionEntity(palletEntity, trailer, false)
                                SetEntityNoCollisionEntity(trailer, palletEntity, false)
                                SetEntityCollision(palletEntity, true, true)

                                -- 2. ANEXAÇÃO SEGURA (ATTACH)
                                AttachEntityToEntity(
                                    palletEntity, trailer, 0,
                                    relPos.x, relPos.y, safeZ,
                                    0.0, 0.0, relHeading,
                                    false, false, false, false, 2, true
                                )
                                FreezeEntityPosition(palletEntity, false)

                                CurrentForkliftPallet = nil
                                loadedCount = loadedCount + 1
                                PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end

                                -- Notifica o servidor
                                TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, loadedCount)

                                if onLoadedCb then
                                    onLoadedCb('dropped', palletEntity, loadedCount, requiredCount)
                                end

                                if loadedCount >= requiredCount then
                                    ForkliftModule.StopOperation()
                                    if onAllLoadedCb then
                                        onAllLoadedCb()
                                    end
                                    break
                                end
                            end
                        else
                            if TextUIShowing == 'drop' then
                                lib.hideTextUI()
                                TextUIShowing = nil
                            end
                        end
                    end
                end
            else
                if TextUIShowing then
                    lib.hideTextUI()
                    TextUIShowing = nil
                end
            end

            Wait(sleep)
        end

        if TextUIShowing then
            lib.hideTextUI()
            TextUIShowing = nil
        end
    end)
end

function ForkliftModule.StopOperation()
    OperationActive = false
    if TextUIShowing then
        lib.hideTextUI()
        TextUIShowing = nil
    end
    if CurrentForkliftPallet and DoesEntityExist(CurrentForkliftPallet) then
        DetachEntity(CurrentForkliftPallet, true, true)
        CurrentForkliftPallet = nil
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        ForkliftModule.StopOperation()
    end
end)

_G.ForkliftModule = ForkliftModule
return ForkliftModule
