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

local CurrentGhostEntity = nil
local CurrentSlotIndex = 1
local TargetTrailerEntity = nil

function ForkliftModule.DeleteGhostProp()
    if CurrentGhostEntity and DoesEntityExist(CurrentGhostEntity) then
        DetachEntity(CurrentGhostEntity, true, true)
        DeleteEntity(CurrentGhostEntity)
    end
    CurrentGhostEntity = nil
end

function ForkliftModule.GetCurrentGhost()
    return CurrentGhostEntity
end

function ForkliftModule.GetCurrentSlotIndex()
    return CurrentSlotIndex
end

function ForkliftModule.GetSlotOffset(trailer, slotIndex)
    if trailer and DoesEntityExist(trailer) then
        local tModel = GetEntityModel(trailer)
        if Config and Config.TrailerSlots then
            -- 1. Verificação direta por hash da entidade
            if Config.TrailerSlots[tModel] and Config.TrailerSlots[tModel].pallets then
                local off = Config.TrailerSlots[tModel].pallets[slotIndex] or Config.TrailerSlots[tModel].pallets[tostring(slotIndex)]
                if off then
                    local h = (type(off) == 'table' and off.heading) or 0.0
                    return off, h
                end
            end
            -- 2. Varredura flexível por nome de modelo (string) ou hash numérico
            for modelKey, slotData in pairs(Config.TrailerSlots) do
                local keyHash = (type(modelKey) == 'number') and modelKey or joaat(tostring(modelKey):lower())
                if keyHash == tModel and slotData.pallets then
                    local off = slotData.pallets[slotIndex] or slotData.pallets[tostring(slotIndex)]
                    if off then
                        local h = (type(off) == 'table' and off.heading) or 0.0
                        return off, h
                    end
                end
            end
        end
        if Config and Config.Polarix and Config.Polarix.CompatibleTrailers then
            for modelName, tData in pairs(Config.Polarix.CompatibleTrailers) do
                if joaat(modelName) == tModel and tData.attachOffsets then
                    local off = tData.attachOffsets[slotIndex]
                    if off then
                        local h = (type(off) == 'table' and off.heading) or 0.0
                        return off, h
                    end
                end
            end
        end
    end
    -- Fallback sequencial em fileiras duplas (frente para trás)
    local col = ((slotIndex - 1) % 2 == 0) and -0.55 or 0.55
    local row = math.floor((slotIndex - 1) / 2)
    local yOffset = 3.6 - (row * 2.4)
    local fallback = { x = col, y = yOffset, z = 0.35, heading = 0.0 }
    return fallback, 0.0
end

function ForkliftModule.GetForkliftSlotOffset(trailer)
    if trailer and DoesEntityExist(trailer) then
        local tModel = GetEntityModel(trailer)
        if Config and Config.TrailerSlots then
            -- 1. Verificação direta por hash
            if Config.TrailerSlots[tModel] and Config.TrailerSlots[tModel].forklift then
                local off = Config.TrailerSlots[tModel].forklift
                local h = (type(off) == 'table' and off.heading) or 0.0
                return off, h
            end
            -- 2. Varredura flexível por nome ou hash
            for modelKey, slotData in pairs(Config.TrailerSlots) do
                local keyHash = (type(modelKey) == 'number') and modelKey or joaat(tostring(modelKey):lower())
                if keyHash == tModel and slotData.forklift then
                    local off = slotData.forklift
                    local h = (type(off) == 'table' and off.heading) or 0.0
                    return off, h
                end
            end
        end
    end
    local fallback = { x = 0.0, y = -5.2, z = 0.35, heading = 0.0 }
    return fallback, 0.0
end

function ForkliftModule.SpawnGhostProp(trailer, model, offset, heading)
    ForkliftModule.DeleteGhostProp()
    if not trailer or not DoesEntityExist(trailer) or not offset then return nil end

    local modelHash = type(model) == 'number' and model or joaat(model or 'hei_prop_carrier_cargo_04b')
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local t = 1000
        while not HasModelLoaded(modelHash) and t > 0 do
            Wait(20)
            t = t - 20
        end
    end

    local tCoords = GetEntityCoords(trailer)
    local ghost = nil
    if IsModelAVehicle(modelHash) then
        ghost = CreateVehicle(modelHash, tCoords.x, tCoords.y, tCoords.z, GetEntityHeading(trailer), false, false)
        if ghost and DoesEntityExist(ghost) then
            SetVehicleDoorsLocked(ghost, 2)
        end
    else
        ghost = CreateObject(modelHash, tCoords.x, tCoords.y, tCoords.z, false, false, false)
    end
    if not ghost or ghost == 0 or not DoesEntityExist(ghost) then return nil end

    -- Persistência de Memória & LOD Máximo (impede descarte e sumiço ao se aproximar)
    SetEntityAsMissionEntity(ghost, true, true)
    SetEntityLodDist(ghost, 0xFFFF)

    -- Holograma Fantasma: semi-transparente, sem colisão, invencível e imune
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    SetCanClimbOnEntity(ghost, false)
    FreezeEntityPosition(ghost, true)

    local finalH = heading or (type(offset) == 'table' and offset.heading) or 0.0

    AttachEntityToEntity(
        ghost, trailer, 0,
        offset.x, offset.y, offset.z,
        0.0, 0.0, finalH,
        false, false, false, false, 0, true
    )

    CurrentGhostEntity = ghost
    return ghost
end

function ForkliftModule.SpawnForkliftGhost(trailer)
    local off, h = ForkliftModule.GetForkliftSlotOffset(trailer)
    local ghostVeh = ForkliftModule.SpawnGhostProp(trailer, 'forklift', off, h)
    return ghostVeh
end

function ForkliftModule.SnapPalletToCurrentSlot(palletEntity, trailer, slotIndex)
    if not palletEntity or not DoesEntityExist(palletEntity) then
        return false
    end

    -- BLINDAGEM ESTRITA: Forçar estritamente o reboque (trailer) e JAMAIS a empilhadeira
    local targetTrailer = (trailer and DoesEntityExist(trailer) and trailer) or (_G.JobEntities and _G.JobEntities.trailer)
    if not targetTrailer or not DoesEntityExist(targetTrailer) then
        print("[AUST_Trucker] ERRO: Trailer não encontrado para acoplamento do palete.")
        return false
    end

    -- Garante que o alvo não seja a própria empilhadeira
    if _G.JobEntities and targetTrailer == _G.JobEntities.forklift then
        print("[AUST_Trucker] ERRO: Alvo de estiva detectado como empilhadeira! Abortando attach errôneo.")
        return false
    end

    local slotOffset, slotHeading = ForkliftModule.GetSlotOffset(targetTrailer, slotIndex)
    slotHeading = slotHeading or (type(slotOffset) == 'table' and slotOffset.heading) or 0.0

    -- Controle de rede antes do acoplamento
    local timeout = 1500
    while not NetworkHasControlOfEntity(palletEntity) and timeout > 0 do
        NetworkRequestControlOfEntity(palletEntity)
        Wait(30)
        timeout = timeout - 30
    end

    DetachEntity(palletEntity, true, true)

    -- Matriz Sólida Anti-Explosão Havok: Ancoragem na origem do trailer (bone 0) com trava rígida
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    AttachEntityToEntity(
        palletEntity, targetTrailer, 0,
        slotOffset.x, slotOffset.y, slotOffset.z,
        0.0, 0.0, slotHeading,
        false, false, false, false, 2, true
    )

    -- Colisão Sólida com Player/Mundo ativa durante o carregamento + Isolamento do chassi do reboque
    SetEntityAsMissionEntity(palletEntity, true, true)
    SetEntityLodDist(palletEntity, 0xFFFF)
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    SetEntityCollision(palletEntity, true, true)
    SetCanClimbOnEntity(palletEntity, true)
    SetEntityNoCollisionEntity(palletEntity, targetTrailer, false)
    SetEntityNoCollisionEntity(targetTrailer, palletEntity, false)

    -- Sincronização OneSync via Entity StateBags (Pilar 1)
    if NetworkGetEntityIsNetworked(targetTrailer) and NetworkGetEntityIsNetworked(palletEntity) then
        local pNet = NetworkGetNetworkIdFromEntity(palletEntity)
        local curSlots = Entity(targetTrailer).state.loadedSlots or {}
        curSlots[tostring(slotIndex)] = {
            palletNet = pNet,
            offset = { x = slotOffset.x, y = slotOffset.y, z = slotOffset.z },
            heading = slotHeading
        }
        Entity(targetTrailer).state:set('loadedSlots', curSlots, true)
    end

    -- Deleta o holograma do slot recém-ocupado
    ForkliftModule.DeleteGhostProp()
    return true, slotOffset, slotHeading
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
    FreezeEntityPosition(pallet, false)
    AttachEntityToEntity(
        pallet, 
        forklift, 
        forkBone, 
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0, 
        false, false, false, false, 0, true
    )
    return true
end

function ForkliftModule.StartOperation(jobId, trailer, requiredCount, onLoadedCb, onAllLoadedCb)
    OperationActive = true
    TargetTrailerEntity = trailer
    CurrentSlotIndex = 1
    local loadedCount = 0

    CreateThread(function()
        -- Lock 2: Coroutine Sequencial & Yield Bloqueante antes de Instanciar o Primeiro Fantasma
        if trailer and DoesEntityExist(trailer) then
            local tModel = GetEntityModel(trailer)
            local ok, res = pcall(function()
                return lib.callback.await('aurp_trucker:server:getTrailerOffsetsForModel', false, tModel)
            end)

            if ok and res and res.all then
                for mKey, data in pairs(res.all) do
                    local h = (type(mKey) == 'number') and mKey or joaat(tostring(mKey):lower())
                    if not Config.TrailerSlots[h] then Config.TrailerSlots[h] = { pallets = {}, forklift = nil } end
                    if not Config.TrailerSlots[mKey] then Config.TrailerSlots[mKey] = { pallets = {}, forklift = nil } end
                    for idx, v in pairs(data.pallets or {}) do
                        local slotEntry = { x = tonumber(v.x) or 0.0, y = tonumber(v.y) or 0.0, z = tonumber(v.z) or 0.0, heading = tonumber(v.heading) or 0.0 }
                        Config.TrailerSlots[h].pallets[tonumber(idx)] = slotEntry
                        Config.TrailerSlots[mKey].pallets[tonumber(idx)] = slotEntry
                    end
                    if data.forklift then
                        local slotEntry = { x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                        Config.TrailerSlots[h].forklift = slotEntry
                        Config.TrailerSlots[mKey].forklift = slotEntry
                    end
                end
                print("^2[AUST_Trucker Forklift] Lock 2 Sucesso: Offsets sincronizados antes de instanciar holograma!^7")
            end

            -- Yield defensivo para garantia de propagação atômica em memória
            Wait(50)

            local firstOffset, firstHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
            ForkliftModule.SpawnGhostProp(trailer, 'hei_prop_carrier_cargo_04b', firstOffset, firstHeading)
        end

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
                    -- Caso 2: Acomodar palete na carreta (Slot Sequencial com Ghost Preview)
                    if trailer and DoesEntityExist(trailer) then
                        local palletEntity = CurrentForkliftPallet
                        local pCoords = palletEntity and DoesEntityExist(palletEntity) and GetEntityCoords(palletEntity) or GetEntityCoords(forklift)
                        local relPos = GetOffsetFromEntityGivenWorldCoords(trailer, pCoords.x, pCoords.y, pCoords.z)

                        -- Validação de aproximação da caçamba do reboque
                        local isNearTrailerBed = (math.abs(relPos.x) <= 2.2) and (relPos.y >= -7.5 and relPos.y <= 6.2) and (relPos.z >= -1.0 and relPos.z <= 2.8)

                        if isNearTrailerBed and CurrentSlotIndex <= requiredCount then
                            sleep = 0
                            if TextUIShowing ~= 'drop' then
                                lib.showTextUI(('[G] Fixar Palete no Slot %d (Fantasma)'):format(CurrentSlotIndex), { position = 'left-center', icon = 'truck-ramp-box' })
                                TextUIShowing = 'drop'
                            end

                            if IsControlJustPressed(0, 47) then -- Tecla G (control 47)
                                local ok, slotOffset, slotHeading = ForkliftModule.SnapPalletToCurrentSlot(palletEntity, trailer, CurrentSlotIndex)
                                if ok then
                                    local stowedSlot = CurrentSlotIndex
                                    CurrentForkliftPallet = nil
                                    loadedCount = loadedCount + 1
                                    CurrentSlotIndex = CurrentSlotIndex + 1
                                    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

                                    if TextUIShowing then
                                        lib.hideTextUI()
                                        TextUIShowing = nil
                                    end

                                    -- Notifica o servidor
                                    TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, loadedCount)

                                    if onLoadedCb then
                                        onLoadedCb('dropped', palletEntity, loadedCount, requiredCount, stowedSlot, slotOffset, slotHeading)
                                    end

                                    if loadedCount < requiredCount then
                                        -- Spawna o holograma no próximo slot sequencial
                                        local nextOffset, nextHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                                        ForkliftModule.SpawnGhostProp(trailer, 'hei_prop_carrier_cargo_04b', nextOffset, nextHeading)
                                    else
                                        -- Todos os paletes carregados com sucesso
                                        ForkliftModule.StopOperation()
                                        if onAllLoadedCb then
                                            onAllLoadedCb()
                                        end
                                        break
                                    end
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
    ForkliftModule.DeleteGhostProp()
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        ForkliftModule.StopOperation()
    end
end)

_G.ForkliftModule = ForkliftModule
return ForkliftModule
