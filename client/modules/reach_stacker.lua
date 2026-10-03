-- =======================================================================
-- AUST_trucker — client/modules/reach_stacker.lua
-- Módulo de Reach Stacker (Dock Handler) para Içamento de Contêineres
-- Padrão QBOX / OneSync: Trava Eletromagnética via Tecla [G]
-- =======================================================================

local ReachStackerModule = {}
local CurrentCarriedContainer = nil
local ActiveMissionContainer = nil
local OperationActive = false
local TextUIShowing = nil

function ReachStackerModule.IsPlayerInHandler()
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return false end
    return GetEntityModel(veh) == joaat(Config.Polarix.Handler.VehicleModel or 'handler')
end

function ReachStackerModule.GetPlayerHandler()
    if not ReachStackerModule.IsPlayerInHandler() then return nil end
    local ped = cache.ped or PlayerPedId()
    return GetVehiclePedIsIn(ped, false)
end

function ReachStackerModule.GetCarriedContainer()
    return CurrentCarriedContainer
end

function ReachStackerModule.SetMissionContainer(containerEnt)
    ActiveMissionContainer = containerEnt
end

local function GetHandlerSpreaderCoords(handlerVeh)
    local boneName = Config.Polarix.Handler.CraneBone or 'frame_2'
    local boneIndex = GetEntityBoneIndexByName(handlerVeh, boneName)
    if boneIndex == -1 then
        boneIndex = 0
    end
    local coords = GetWorldPositionOfEntityBone(handlerVeh, boneIndex)
    if coords == vector3(0, 0, 0) then
        return GetOffsetFromEntityInWorldCoords(handlerVeh, 0.0, 3.5, 1.5), boneIndex
    end
    return coords, boneIndex
end

function ReachStackerModule.GetNearestGroundContainer(handlerVeh)
    if not handlerVeh or not DoesEntityExist(handlerVeh) then return nil end
    local spreaderCoords = GetHandlerSpreaderCoords(handlerVeh)

    if ActiveMissionContainer and DoesEntityExist(ActiveMissionContainer) and not IsEntityAttached(ActiveMissionContainer) then
        local cCoords = GetEntityCoords(ActiveMissionContainer)
        if #(spreaderCoords - cCoords) < 6.5 then
            return ActiveMissionContainer
        end
    end
    return nil
end

local function AttachContainerToHandler(handlerVeh, container)
    local timeout = 2000
    while not NetworkHasControlOfEntity(container) and timeout > 0 do
        NetworkRequestControlOfEntity(container)
        Wait(50)
        timeout = timeout - 50
    end

    if not NetworkHasControlOfEntity(container) then
        if Config.Debug then print(("[AUST_Trucker] Falha de controle OneSync sobre o contêiner %s"):format(tostring(container))) end
        return false
    end

    FreezeEntityPosition(container, false)
    SetEntityCollision(container, false, false)

    local _, boneIndex = GetHandlerSpreaderCoords(handlerVeh)
    local offset = Config.Polarix.Handler.AttachOffset or { x = 0.0, y = 1.78, z = -2.5, rx = 0.0, ry = 0.0, rz = 90.0 }

    AttachEntityToEntity(
        container,
        handlerVeh,
        boneIndex,
        offset.x, offset.y, offset.z,
        offset.rx, offset.ry, offset.rz,
        false, false, true, false, 0, true
    )
    return true
end

function ReachStackerModule.StartOperation(jobId, trailer, onLoadedCb, onAllLoadedCb)
    OperationActive = true

    CreateThread(function()
        while OperationActive do
            local sleep = 250
            local handlerVeh = ReachStackerModule.GetPlayerHandler()

            if handlerVeh and DoesEntityExist(handlerVeh) then
                if not CurrentCarriedContainer then
                    -- Caso 1: Buscar contêiner no chão
                    local targetContainer = ReachStackerModule.GetNearestGroundContainer(handlerVeh)
                    if targetContainer and DoesEntityExist(targetContainer) then
                        sleep = 0
                        if TextUIShowing ~= 'pickup' then
                            lib.showTextUI('[G] Travar Contêiner no Spreader', { position = 'left-center', icon = 'boxes-stacked' })
                            TextUIShowing = 'pickup'
                        end

                        if IsControlJustPressed(0, 47) then -- Tecla G
                            local ok = AttachContainerToHandler(handlerVeh, targetContainer)
                            if ok then
                                CurrentCarriedContainer = targetContainer
                                PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)

                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end

                                if onLoadedCb then
                                    onLoadedCb('picked', targetContainer)
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
                    -- Caso 2: Acoplar na prancha da carreta
                    if trailer and DoesEntityExist(trailer) then
                        local trailerCenter = GetOffsetFromEntityInWorldCoords(trailer, 0.0, 0.0, 0.5)
                        local spreaderPos = GetHandlerSpreaderCoords(handlerVeh)
                        local dist = #(spreaderPos - trailerCenter)

                        if dist < 6.8 then
                            sleep = 0
                            if TextUIShowing ~= 'drop' then
                                lib.showTextUI('[G] Travar Contêiner na Prancha', { position = 'left-center', icon = 'truck-ramp-box' })
                                TextUIShowing = 'drop'
                            end

                            if IsControlJustPressed(0, 47) then -- Tecla G
                                local containerEnt = CurrentCarriedContainer

                                local timeout = 2000
                                while not NetworkHasControlOfEntity(containerEnt) and timeout > 0 do
                                    NetworkRequestControlOfEntity(containerEnt)
                                    Wait(50)
                                    timeout = timeout - 50
                                end

                                DetachEntity(containerEnt, true, true)

                                -- Fixação nivelada na prancha da carreta
                                AttachEntityToEntity(
                                    containerEnt,
                                    trailer,
                                    0,
                                    0.0, 0.0, 0.35,
                                    0.0, 0.0, 0.0,
                                    false, false, true, false, 0, true
                                )
                                SetEntityCollision(containerEnt, true, true)
                                SetEntityNoCollisionEntity(containerEnt, trailer, true)
                                SetEntityNoCollisionEntity(trailer, containerEnt, true)
                                FreezeEntityPosition(containerEnt, true)

                                CurrentCarriedContainer = nil
                                PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end

                                TriggerServerEvent('aurp_trucker:server:heavyContainerLoaded', jobId)

                                if onLoadedCb then
                                    onLoadedCb('dropped', containerEnt)
                                end

                                ReachStackerModule.StopOperation()
                                if onAllLoadedCb then
                                    onAllLoadedCb()
                                end
                                break
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

function ReachStackerModule.StopOperation()
    OperationActive = false
    if TextUIShowing then
        lib.hideTextUI()
        TextUIShowing = nil
    end
    if CurrentCarriedContainer and DoesEntityExist(CurrentCarriedContainer) then
        DetachEntity(CurrentCarriedContainer, true, true)
        CurrentCarriedContainer = nil
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        ReachStackerModule.StopOperation()
    end
end)

_G.ReachStackerModule = ReachStackerModule
return ReachStackerModule
