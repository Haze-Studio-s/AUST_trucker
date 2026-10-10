-- =======================================================================
-- AUST_trucker — client/modules/reach_stacker.lua
-- Módulo de Reach Stacker (Dock Handler) para Içamento de Contêineres
-- Padrão QBOX / OneSync: Trava Eletromagnética via Tecla [G]
-- =======================================================================

local ReachStackerModule = {}
local CurrentCarriedContainer = nil
local ActiveMissionContainer = nil
local ActiveMissionContainers = {}
local OperationActive = false
local TextUIShowing = nil
local LoadedContainersCount = 0
local TotalContainersCount = 1

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
    if containerEnt then
        ActiveMissionContainers = { containerEnt }
    else
        ActiveMissionContainers = {}
    end
end

function ReachStackerModule.SetMissionContainers(containersList)
    if type(containersList) == 'table' then
        ActiveMissionContainers = containersList
        ActiveMissionContainer = containersList[1]
    elseif containersList then
        ActiveMissionContainers = { containersList }
        ActiveMissionContainer = containersList
    else
        ActiveMissionContainers = {}
        ActiveMissionContainer = nil
    end
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

    if ActiveMissionContainers and #ActiveMissionContainers > 0 then
        for _, cEnt in ipairs(ActiveMissionContainers) do
            if DoesEntityExist(cEnt) and not IsEntityAttached(cEnt) then
                local cCoords = GetEntityCoords(cEnt)
                if #(spreaderCoords - cCoords) < 6.5 then
                    return cEnt
                end
            end
        end
    end

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
    local hOffX, hOffY, hOffZ = offset.x, offset.y, offset.z
    local hPitch, hRoll, hYaw = offset.rx or 0.0, offset.ry or 0.0, offset.rz or 90.0

    if GetVehiclePropOffset then
        local customOff, customRot = GetVehiclePropOffset(handlerVeh, GetEntityModel(container))
        if customOff then
            hOffX, hOffY, hOffZ = customOff.x, customOff.y, customOff.z
            if customRot then
                hPitch, hRoll, hYaw = customRot.x, customRot.y, customRot.z
            end
        end
    end

    AttachEntityToEntity(
        container,
        handlerVeh,
        boneIndex,
        hOffX, hOffY, hOffZ,
        hPitch, hRoll, hYaw,
        false, false, true, false, 0, true
    )
    return true
end

local function ResolveTrailerContainerSlot(trailer, containerEnt, slotIndex, totalContainers)
    local tModel = GetEntityModel(trailer)
    local uHash = tModel & 0xFFFFFFFF
    local sHash = (uHash >= 0x80000000) and (uHash - 0x100000000) or uHash
    local keys = { tModel, uHash, sHash, tostring(tModel), tostring(uHash), tostring(sHash) }
    if tModel == joaat('freighttrailer') then table.insert(keys, 'freighttrailer') end
    if tModel == joaat('docktrailer') then table.insert(keys, 'docktrailer') end
    if _G.ActiveJob and _G.ActiveJob.trailerModel then table.insert(keys, tostring(_G.ActiveJob.trailerModel):lower()) end

    -- 1. Prioridade Absoluta: Offsets salvos no banco e injetados na missão ativa (_G.ActiveJob)
    if _G.ActiveJob and _G.ActiveJob.trailerOffsets then
        local spec = _G.ActiveJob.trailerOffsets._specific
        if spec and spec.pallets then
            local s = spec.pallets[slotIndex] or spec.pallets[tonumber(slotIndex)] or spec.pallets[tostring(slotIndex)]
            if s then
                local rx = tonumber(s.rot_pitch) or tonumber(s.rx) or 0.0
                local ry = tonumber(s.rot_roll) or tonumber(s.ry) or 0.0
                local rz = tonumber(s.rot_yaw) or tonumber(s.heading) or 0.0
                return vector3(tonumber(s.x) or 0.0, tonumber(s.y) or 0.0, tonumber(s.z) or 0.35), vector3(rx, ry, rz)
            end
        end

        for _, k in ipairs(keys) do
            local jobData = _G.ActiveJob.trailerOffsets[k]
            if jobData and jobData.pallets then
                local s = jobData.pallets[slotIndex] or jobData.pallets[tonumber(slotIndex)] or jobData.pallets[tostring(slotIndex)]
                if s then
                    local rx = tonumber(s.rot_pitch) or tonumber(s.rx) or 0.0
                    local ry = tonumber(s.rot_roll) or tonumber(s.ry) or 0.0
                    local rz = tonumber(s.rot_yaw) or tonumber(s.heading) or 0.0
                    return vector3(tonumber(s.x) or 0.0, tonumber(s.y) or 0.0, tonumber(s.z) or 0.35), vector3(rx, ry, rz)
                end
            end
        end
    end

    -- 2. Resolução através de Config.TrailerSlots
    local cfg = nil
    if Config and Config.TrailerSlots then
        for _, k in ipairs(keys) do
            if Config.TrailerSlots[k] then
                cfg = Config.TrailerSlots[k]
                break
            end
        end
    end

    -- 2.1 Se houver slots dedicados a contêineres na tabela
    if cfg and cfg.containers then
        if totalContainers and totalContainers > 1 and cfg.containers.double then
            local s = cfg.containers.double[slotIndex] or cfg.containers.double[1]
            if s then
                return vector3(s.x or 0.0, s.y or 0.0, s.z or 0.35), vector3(s.rx or 0.0, s.ry or 0.0, s.heading or 0.0)
            end
        elseif cfg.containers.single then
            local s = cfg.containers.single[1]
            if s then
                return vector3(s.x or 0.0, s.y or 0.0, s.z or 0.35), vector3(s.rx or 0.0, s.ry or 0.0, s.heading or 0.0)
            end
        end
    end

    -- 2.2 Se houver slots calibrados no /truckeradmin (pallets table)
    if cfg and cfg.pallets then
        local s = cfg.pallets[slotIndex] or cfg.pallets[tonumber(slotIndex)] or cfg.pallets[tostring(slotIndex)] or cfg.pallets[1]
        if s then
            local rx = tonumber(s.rot_pitch) or tonumber(s.rx) or 0.0
            local ry = tonumber(s.rot_roll) or tonumber(s.ry) or 0.0
            local rz = tonumber(s.rot_yaw) or tonumber(s.heading) or 0.0
            return vector3(tonumber(s.x) or 0.0, tonumber(s.y) or 0.0, tonumber(s.z) or 0.35), vector3(rx, ry, rz)
        end
    end

    -- 3. Fallbacks inteligentes baseados no número de contêineres
    if totalContainers and totalContainers > 1 then
        if slotIndex == 1 then
            return vector3(0.0, 3.8, 0.35), vector3(0.0, 0.0, 0.0)
        else
            return vector3(0.0, -3.8, 0.35), vector3(0.0, 0.0, 0.0)
        end
    end

    return vector3(0.0, 0.0, 0.35), vector3(0.0, 0.0, 0.0)
end

function ReachStackerModule.StartOperation(jobId, trailer, onLoadedCb, onAllLoadedCb, missionContainers, totalExpected)
    OperationActive = true
    LoadedContainersCount = 0
    TotalContainersCount = totalExpected or (type(missionContainers) == 'table' and #missionContainers) or 1
    if missionContainers then
        ReachStackerModule.SetMissionContainers(missionContainers)
    end

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

                        if dist < 7.5 then
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

                                local slotIndex = LoadedContainersCount + 1
                                local slotOffset, slotRot = ResolveTrailerContainerSlot(trailer, containerEnt, slotIndex, TotalContainersCount)

                                -- Fixação nivelada na prancha da carreta
                                AttachEntityToEntity(
                                    containerEnt,
                                    trailer,
                                    0,
                                    slotOffset.x, slotOffset.y, slotOffset.z,
                                    slotRot.x, slotRot.y, slotRot.z,
                                    false, false, true, false, 0, true
                                )

                                -- Blindagem Havok Anti-Catapulta: Colisão com mundo preservada, isolamento mútuo estrito
                                SetEntityCollision(containerEnt, true, true)
                                SetEntityNoCollisionEntity(containerEnt, trailer, true)
                                SetEntityNoCollisionEntity(trailer, containerEnt, true)
                                SetEntityNoCollisionEntity(containerEnt, handlerVeh, true)
                                SetEntityNoCollisionEntity(handlerVeh, containerEnt, true)
                                FreezeEntityPosition(containerEnt, true)

                                LoadedContainersCount = LoadedContainersCount + 1
                                CurrentCarriedContainer = nil
                                PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end

                                local cNet = NetworkGetNetworkIdFromEntity(containerEnt)
                                TriggerServerEvent('aurp_trucker:server:heavyContainerLoaded', jobId, slotIndex, cNet)

                                if LoadedContainersCount < TotalContainersCount then
                                    if onLoadedCb then
                                        onLoadedCb('dropped_partial', containerEnt, LoadedContainersCount, TotalContainersCount)
                                    end
                                else
                                    if onLoadedCb then
                                        onLoadedCb('dropped', containerEnt, LoadedContainersCount, TotalContainersCount)
                                    end
                                    ReachStackerModule.StopOperation()
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
