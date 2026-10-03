-- =======================================================================
-- AUST_trucker — client/modules/car_carrier.lua
-- Sistema de Cegonha (Car Carrier): Transporte de Veículos com Reboque tr2
-- Rampas Móveis Dinâmicas, Fixação por Slots e Matriz de Colisão Híbrida
-- Baseado na engenharia reversa do 0r-trucker com arquitetura OneSync Server-Setter
-- =======================================================================

CarCarrierModule = {}
local OperationActive = false
local LoadedVehicles = {}
local SpawnedRamp = nil

-- Configuração dos 3 slots de veículos esportivos no reboque 'tr2'
CarCarrierModule.Slots = {
    [1] = {
        offset = vector3(0.0, 4.85, 0.84),
        rot = vector3(0.0, 0.0, 0.0),
        label = "Vaga Dianteira Superior",
        loaded = false,
        vehicle = nil
    },
    [2] = {
        offset = vector3(0.0, 0.25, 0.95),
        rot = vector3(-3.5, 0.0, 0.0),
        label = "Vaga Central Inferior",
        loaded = false,
        vehicle = nil
    },
    [3] = {
        offset = vector3(0.0, -4.7, 1.1),
        rot = vector3(3.0, 0.0, 0.0),
        label = "Vaga Traseira de Rampa",
        loaded = false,
        vehicle = nil
    }
}

-- Rampa móvel para subida e descida suave
function CarCarrierModule.DeployRamp(trailer)
    if SpawnedRamp and DoesEntityExist(SpawnedRamp) then return SpawnedRamp end
    if not trailer or not DoesEntityExist(trailer) then return nil end

    local rampModel = joaat('3fe_carramp')
    if not IsModelInCdimage(rampModel) or not IsModelValid(rampModel) then
        rampModel = joaat('prop_mp_ramp_01')
    end

    lib.requestModel(rampModel)
    local tCoords = GetEntityCoords(trailer)
    local ramp = CreateObject(rampModel, tCoords.x, tCoords.y, tCoords.z, false, false, false)
    SetEntityCollision(ramp, true, true)
    FreezeEntityPosition(ramp, false)

    -- Anexa na extremidade traseira do reboque tr2
    AttachEntityToEntity(
        ramp, trailer, 0,
        0.0, -7.8, -0.6,
        15.0, 0.0, 180.0,
        false, false, false, false, 0, true
    )

    SpawnedRamp = ramp
    return ramp
end

function CarCarrierModule.RemoveRamp()
    if SpawnedRamp and DoesEntityExist(SpawnedRamp) then
        DetachEntity(SpawnedRamp, true, true)
        DeleteEntity(SpawnedRamp)
        SpawnedRamp = nil
    end
end

-- Acopla um veículo em um slot específico com Matriz de Colisão Híbrida
function CarCarrierModule.AttachVehicleToSlot(trailer, slotIndex, vehicleEntity)
    if not trailer or not DoesEntityExist(trailer) then return false end
    if not vehicleEntity or not DoesEntityExist(vehicleEntity) then return false end
    local slot = CarCarrierModule.Slots[slotIndex]
    if not slot or slot.loaded then return false end

    NetworkRequestControlOfEntity(vehicleEntity)
    local timeout = 1000
    while not NetworkHasControlOfEntity(vehicleEntity) and timeout > 0 do
        Wait(50)
        timeout = timeout - 50
    end

    -- 1. Descongela e anexa com isolamento mútuo (collision = false, vertexIndex = 0)
    FreezeEntityPosition(vehicleEntity, false)
    SetEntityVelocity(vehicleEntity, 0.0, 0.0, 0.0)

    AttachEntityToEntity(
        vehicleEntity, trailer, 0,
        slot.offset.x, slot.offset.y, slot.offset.z,
        slot.rot.x, slot.rot.y, slot.rot.z,
        false, false, false, false, 0, true
    )

    -- 2. Reforço de colisão com o mundo (Pós-Attach)
    FreezeEntityPosition(vehicleEntity, false)
    SetEntityDynamic(vehicleEntity, false)
    SetEntityCollision(vehicleEntity, true, true)
    SetCanClimbOnEntity(vehicleEntity, true)
    SetEntityNoCollisionEntity(vehicleEntity, trailer, true)
    SetEntityNoCollisionEntity(trailer, vehicleEntity, true)

    -- 3. Blindagem de rodas e portas
    SetVehicleDoorsLocked(vehicleEntity, 4)
    for i = 0, 4 do
        SetVehicleTyreFixed(vehicleEntity, i)
    end

    slot.loaded = true
    slot.vehicle = vehicleEntity
    table.insert(LoadedVehicles, vehicleEntity)

    PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)
    return true
end

-- Desacopla todos os veículos para entrega no destino
function CarCarrierModule.DetachAllVehicles(trailer)
    for idx, slot in ipairs(CarCarrierModule.Slots) do
        if slot.vehicle and DoesEntityExist(slot.vehicle) then
            DetachEntity(slot.vehicle, true, true)
            FreezeEntityPosition(slot.vehicle, false)
            SetEntityDynamic(slot.vehicle, true)
            SetEntityCollision(slot.vehicle, true, true)
            SetVehicleDoorsLocked(slot.vehicle, 1)
            SetVehicleOnGroundProperly(slot.vehicle)
        end
        slot.loaded = false
        slot.vehicle = nil
    end
    LoadedVehicles = {}
    CarCarrierModule.RemoveRamp()
end

-- Retorna a lista de veículos carregados
function CarCarrierModule.GetLoadedVehicles()
    return LoadedVehicles
end

-- Inicia operação de carregamento interativo
function CarCarrierModule.StartLoadingOperation(jobId, trailer, vehiclesToLoad, onCompleted)
    OperationActive = true
    CarCarrierModule.DeployRamp(trailer)

    CreateThread(function()
        while OperationActive do
            local sleep = 350
            local ped = cache.ped or PlayerPedId()
            local currentVeh = GetVehiclePedIsIn(ped, false)

            if currentVeh ~= 0 and currentVeh ~= trailer then
                -- Checa se o veículo atual é um dos veículos designados para a missão
                local isMissionVeh = false
                for _, v in ipairs(vehiclesToLoad or {}) do
                    if v == currentVeh then isMissionVeh = true break end
                end

                if isMissionVeh then
                    local tCoords = GetEntityCoords(trailer)
                    local dist = #(GetEntityCoords(currentVeh) - tCoords)

                    if dist < 16.0 then
                        sleep = 0
                        -- Procura o próximo slot livre
                        local nextSlot = nil
                        for i = 1, #CarCarrierModule.Slots do
                            if not CarCarrierModule.Slots[i].loaded then
                                nextSlot = i
                                break
                            end
                        end

                        if nextSlot then
                            lib.showTextUI(('[E] Embarcar na %s'):format(CarCarrierModule.Slots[nextSlot].label), { position = 'left-center', icon = 'car' })

                            if IsControlJustPressed(0, 38) then -- Tecla E
                                lib.hideTextUI()
                                TaskLeaveVehicle(ped, currentVeh, 0)
                                Wait(1000)

                                local ok = CarCarrierModule.AttachVehicleToSlot(trailer, nextSlot, currentVeh)
                                if ok then
                                    SendMissionNotify('Central de Cargas', ('Veículo travado com sucesso na %s!'):format(CarCarrierModule.Slots[nextSlot].label), 'success')
                                    
                                    -- Verifica se todos os slots foram preenchidos
                                    local allLoaded = true
                                    for i = 1, #vehiclesToLoad do
                                        if not CarCarrierModule.Slots[i] or not CarCarrierModule.Slots[i].loaded then
                                            allLoaded = false
                                            break
                                        end
                                    end

                                    if allLoaded then
                                        CarCarrierModule.RemoveRamp()
                                        OperationActive = false
                                        if onCompleted then onCompleted() end
                                        break
                                    end
                                end
                            end
                        else
                            lib.hideTextUI()
                        end
                    else
                        lib.hideTextUI()
                    end
                end
            end

            Wait(sleep)
        end
    end)
end

function CarCarrierModule.StopLoadingOperation()
    OperationActive = false
    lib.hideTextUI()
    CarCarrierModule.RemoveRamp()
end

_G.CarCarrierModule = CarCarrierModule
return CarCarrierModule
