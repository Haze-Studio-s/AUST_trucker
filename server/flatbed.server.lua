-- aurp_trucker — server/flatbed.server.lua
-- Sistema de flatbed integrado (adaptado de gs_flatbed sv_main.lua)
-- Gerencia criação/destruição do bed prop e relay de operações de attach/lower

local FLATBED_MODEL = GetHashKey(Config.Flatbed.model)
local BED_MODEL     = Config.Flatbed.bedModel

local function netEntityExists(netId)
    netId = tonumber(netId)
    if not netId then return false end
    local e = NetworkGetEntityFromNetworkId(netId)
    return e ~= 0 and DoesEntityExist(e)
end

-- Cria bed prop ao detectar flatbed3 no mundo
AddEventHandler('entityCreated', function(entity)
    if not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return end

    local bedNetId = Entity(entity).state.bedProp
    if bedNetId and DoesEntityExist(NetworkGetEntityFromNetworkId(bedNetId)) then return end
    Entity(entity).state.bedProp = nil

    local flatbedNetId = NetworkGetNetworkIdFromEntity(entity)
    TriggerEvent('aurp_trucker:flatbed:CreateBedEntity', flatbedNetId)
end)

-- Remove bed prop ao destruir flatbed
AddEventHandler('entityRemoved', function(entity)
    if GetEntityType(entity) ~= 2 then return end
    if GetEntityModel(entity) ~= FLATBED_MODEL then return end

    local bedNetId = Entity(entity).state.bedProp
    if not bedNetId then return end
    local bedEnt = NetworkGetEntityFromNetworkId(bedNetId)
    if DoesEntityExist(bedEnt) then DeleteEntity(bedEnt) end
end)

-- Evento interno do servidor (não exposto para clientes prevenindo injeção de props)
AddEventHandler('aurp_trucker:flatbed:CreateBedEntity', function(flatbedNetId)
    -- IMPORTANTE: usar CreateThread pois Wait() não pode ser chamado diretamente em AddEventHandler
    Citizen.CreateThread(function()
        local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
        if not DoesEntityExist(flatbedVehicle) then return end
        if GetEntityModel(flatbedVehicle) ~= FLATBED_MODEL then return end

        local existingBedNetId = Entity(flatbedVehicle).state.bedProp
        if existingBedNetId then
            if DoesEntityExist(NetworkGetEntityFromNetworkId(existingBedNetId)) then return end
        end

        local vehicleCoords = GetEntityCoords(flatbedVehicle)
        local bedEntity = CreateObjectNoOffset(BED_MODEL,
            vehicleCoords.x, vehicleCoords.y, vehicleCoords.z - 3.0, true, 0, 1)

        local startTime = GetGameTimer()
        while not DoesEntityExist(bedEntity) do
            if GetGameTimer() - startTime > 5000 then
                if DoesEntityExist(bedEntity) then DeleteEntity(bedEntity) end
                return
            end
            Wait(10)
        end

        local flatbedOwner = NetworkGetEntityOwner(flatbedVehicle)
        local bedOwner     = NetworkGetEntityOwner(bedEntity)
        startTime = GetGameTimer()
        while flatbedOwner ~= bedOwner and GetGameTimer() - startTime < 500 do
            Wait(100)
            flatbedOwner = NetworkGetEntityOwner(flatbedVehicle)
            bedOwner     = NetworkGetEntityOwner(bedEntity)
        end

        if flatbedOwner ~= bedOwner then
            DeleteEntity(bedEntity)
            return
        end

        if not DoesEntityExist(flatbedVehicle) or not DoesEntityExist(bedEntity) then
            if DoesEntityExist(bedEntity) then DeleteEntity(bedEntity) end
            return
        end

        local bedNetId = NetworkGetNetworkIdFromEntity(bedEntity)
        Entity(flatbedVehicle).state.bedProp         = bedNetId
        Entity(flatbedVehicle).state.attachedVehicle = -1
        Entity(flatbedVehicle).state.bedLowered      = false
        Entity(flatbedVehicle).state.bedMoving       = false

        if flatbedOwner ~= -1 then
            TriggerClientEvent('aurp_trucker:flatbed:AttachBedToVehicle', flatbedOwner, flatbedNetId, bedNetId)
        end
    end)
end)

RegisterNetEvent('aurp_trucker:flatbed:DeleteBedEntity')
AddEventHandler('aurp_trucker:flatbed:DeleteBedEntity', function(flatbedNetId, bedNetId)
    local src = source
    if not Framework.GetPlayer(src) then return end

    flatbedNetId = tonumber(flatbedNetId)
    if not flatbedNetId or not netEntityExists(flatbedNetId) then return end

    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    if not DoesEntityExist(flatbedVehicle) or GetEntityType(flatbedVehicle) ~= 2 then return end
    if GetEntityModel(flatbedVehicle) ~= FLATBED_MODEL then return end

    -- Validar proximidade física do solicitante (máx. 30m)
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) or #(GetEntityCoords(ped) - GetEntityCoords(flatbedVehicle)) > 30.0 then
        return
    end

    -- Obter a cama autoritativamente pelo StateBag do veículo
    local existingBedNetId = Entity(flatbedVehicle).state.bedProp
    if not existingBedNetId then return end

    -- Se o cliente enviou bedNetId, DEVE coincidir estritamente com o StateBag
    if bedNetId and tonumber(bedNetId) ~= tonumber(existingBedNetId) then
        return
    end

    local bedEntity = NetworkGetEntityFromNetworkId(existingBedNetId)
    if DoesEntityExist(bedEntity) and GetEntityType(bedEntity) == 3 then
        DeleteEntity(bedEntity)
    end
    Entity(flatbedVehicle).state.bedProp = nil
end)

RegisterNetEvent('aurp_trucker:flatbed:LowerFlatbed')
AddEventHandler('aurp_trucker:flatbed:LowerFlatbed', function(flatbedNetId)
    -- C-10: Validar origem
    if not Framework.GetPlayer(source) then return end
    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    if not DoesEntityExist(flatbedVehicle) then return end
    local owner = NetworkGetEntityOwner(flatbedVehicle)
    if owner ~= -1 then
        TriggerClientEvent('aurp_trucker:flatbed:LowerFlatbedClient', owner, flatbedNetId)
    end
end)

RegisterNetEvent('aurp_trucker:flatbed:RaiseFlatbed')
AddEventHandler('aurp_trucker:flatbed:RaiseFlatbed', function(flatbedNetId)
    -- C-10: Validar origem
    if not Framework.GetPlayer(source) then return end
    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    if not DoesEntityExist(flatbedVehicle) then return end
    local owner = NetworkGetEntityOwner(flatbedVehicle)
    if owner ~= -1 then
        TriggerClientEvent('aurp_trucker:flatbed:RaiseFlatbedClient', owner, flatbedNetId)
    end
end)

RegisterNetEvent('aurp_trucker:flatbed:AttachVehicle')
AddEventHandler('aurp_trucker:flatbed:AttachVehicle', function(flatbedNetId, vehicleToAttachNetId)
    local src = source
    if not Framework.GetPlayer(src) then return end
    flatbedNetId = tonumber(flatbedNetId)
    vehicleToAttachNetId = tonumber(vehicleToAttachNetId)
    if not flatbedNetId or not vehicleToAttachNetId then return end
    if not netEntityExists(flatbedNetId) or not netEntityExists(vehicleToAttachNetId) then return end

    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    local attachEntity   = NetworkGetEntityFromNetworkId(vehicleToAttachNetId)
    if not DoesEntityExist(flatbedVehicle) or not DoesEntityExist(attachEntity) then return end
    if GetEntityType(flatbedVehicle) ~= 2 or GetEntityType(attachEntity) ~= 2 then return end

    -- Impedir auto-acoplamento (veículo acoplado a si mesmo)
    if flatbedNetId == vehicleToAttachNetId or flatbedVehicle == attachEntity then return end

    -- Impedir acoplamento se o flatbed já possui veículo anexado
    local currentAttached = Entity(flatbedVehicle).state.attachedVehicle
    if currentAttached and tonumber(currentAttached) ~= -1 then return end

    -- Validar proximidade física do solicitante até o flatbed (máx 20m)
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) or #(GetEntityCoords(ped) - GetEntityCoords(flatbedVehicle)) > 20.0 then
        return
    end

    -- Validar proximidade física entre o flatbed e o veículo a acoplar (máx 18m)
    if #(GetEntityCoords(flatbedVehicle) - GetEntityCoords(attachEntity)) > 18.0 then
        return
    end

    Entity(flatbedVehicle).state.attachedVehicle = vehicleToAttachNetId
    local attachOwner = NetworkGetEntityOwner(attachEntity)
    if attachOwner ~= -1 then
        TriggerClientEvent('aurp_trucker:flatbed:AttachVehicleClient', attachOwner, flatbedNetId, vehicleToAttachNetId)
    end
end)

RegisterNetEvent('aurp_trucker:flatbed:DetachVehicle')
AddEventHandler('aurp_trucker:flatbed:DetachVehicle', function(flatbedNetId, vehicleToAttachNetId)
    local src = source
    if not Framework.GetPlayer(src) then return end
    flatbedNetId = tonumber(flatbedNetId)
    vehicleToAttachNetId = tonumber(vehicleToAttachNetId)
    if not flatbedNetId or not vehicleToAttachNetId then return end
    if not netEntityExists(flatbedNetId) or not netEntityExists(vehicleToAttachNetId) then return end

    local flatbedVehicle = NetworkGetEntityFromNetworkId(flatbedNetId)
    local attachEntity   = NetworkGetEntityFromNetworkId(vehicleToAttachNetId)
    if not DoesEntityExist(flatbedVehicle) or not DoesEntityExist(attachEntity) then return end

    -- Validar proximidade física do solicitante até o flatbed
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) or #(GetEntityCoords(ped) - GetEntityCoords(flatbedVehicle)) > 20.0 then
        return
    end

    -- Validar que o veículo a ser desanexado é o atualmente acoplado no StateBag
    local currentAttached = Entity(flatbedVehicle).state.attachedVehicle
    if not currentAttached or tonumber(currentAttached) ~= vehicleToAttachNetId then
        return
    end

    Entity(flatbedVehicle).state.attachedVehicle = -1
    local attachOwner = NetworkGetEntityOwner(attachEntity)
    if attachOwner ~= -1 then
        TriggerClientEvent('aurp_trucker:flatbed:DetachVehicleClient', attachOwner, vehicleToAttachNetId)
    end
end)
