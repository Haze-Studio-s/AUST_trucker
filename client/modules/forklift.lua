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
                    -- Caso 2: Acomodar palete na carreta (Sem verificação de portas - direto na caçamba/reboque)
                    if trailer and DoesEntityExist(trailer) then
                        local trailerRear = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -5.5, 0.0)
                        local distToRear = #(GetEntityCoords(forklift) - trailerRear)

                        if distToRear < 5.2 then
                            sleep = 0
                            if TextUIShowing ~= 'drop' then
                                lib.showTextUI('[G] Posicionar no Caminhão', { position = 'left-center', icon = 'truck-ramp-box' })
                                TextUIShowing = 'drop'
                            end

                            if IsControlJustPressed(0, 47) then -- Tecla G (control 47)
                                local palletEntity = CurrentForkliftPallet

                                -- Garante controle de rede antes de desanexar/anexar
                                local timeout = 2000
                                while not NetworkHasControlOfEntity(palletEntity) and timeout > 0 do
                                    NetworkRequestControlOfEntity(palletEntity)
                                    Wait(50)
                                    timeout = timeout - 50
                                end

                                DetachEntity(palletEntity, true, true)

                                -- Fixação calculada do palete na caçamba do reboque
                                local ox, oy, oz = GetTrailerAttachOffset(trailer, loadedCount)
                                AttachEntityToEntity(
                                    palletEntity, trailer, 0,
                                    ox, oy, oz,
                                    0.0, 0.0, 0.0,
                                    false, false, true, false, 2, true
                                )
                                SetEntityCollision(palletEntity, true, true)
                                SetEntityNoCollisionEntity(palletEntity, trailer, true)
                                SetEntityNoCollisionEntity(trailer, palletEntity, true)
                                FreezeEntityPosition(palletEntity, true)

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
