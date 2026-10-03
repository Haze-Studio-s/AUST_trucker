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
    local bestEntity, bestDist = nil, 3.2

    -- 1. Verifica tabela de paletes cadastrados na missão
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

    -- 2. Varredura dinâmica de pool para paletes soltos próximos (caso tenha caído em trânsito)
    if not bestEntity then
        local PalletPropModels = {
            joaat('hei_prop_carrier_cargo_04b'),
            joaat('m24_1_prop_m24_1_carrier_cargo_04a'),
            joaat('sm3d_prop_pallet_1'),
            joaat('sm3d_prop_pallet_2'),
            joaat('sm3d_prop_pallet_1_rep'),
            joaat('sm3d_prop_pallet_1_open'),
        }
        for _, mHash in ipairs(PalletPropModels) do
            local nearbyObj = GetClosestObjectOfType(forkCoords.x, forkCoords.y, forkCoords.z, 3.2, mHash, false, false, false)
            if nearbyObj and nearbyObj ~= 0 and DoesEntityExist(nearbyObj) and not IsEntityAttached(nearbyObj) then
                local dist = #(forkCoords - GetEntityCoords(nearbyObj))
                if dist < bestDist then
                    bestDist = dist
                    bestEntity = nearbyObj
                end
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
        pcall(function() SetEntityDrawOutline(CurrentGhostEntity, false) end)
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

local function ResolveTrailerModel(trailer)
    if not trailer then return nil end
    if type(trailer) == 'number' then
        if DoesEntityExist(trailer) then
            return GetEntityModel(trailer)
        end
        return trailer
    elseif type(trailer) == 'string' then
        return tonumber(trailer) or joaat(trailer:lower())
    end
    return nil
end

local function GetTrailerHashKeys(trailer)
    local raw = ResolveTrailerModel(trailer)
    if not raw then return {} end
    local u = raw & 0xFFFFFFFF
    local s = (u >= 0x80000000) and (u - 0x100000000) or u
    return { raw, u, s, tostring(raw), tostring(u), tostring(s) }
end

function ForkliftModule.GetSlotOffset(trailer, slotIndex)
    local keys = GetTrailerHashKeys(trailer)
    if Config and Config.TrailerSlots then
        -- 1. Verificação direta por todas as variações de chaves (raw, unsigned, signed, strings)
        for _, k in ipairs(keys) do
            local slotData = Config.TrailerSlots[k]
            if slotData and slotData.pallets then
                local off = slotData.pallets[slotIndex] or slotData.pallets[tonumber(slotIndex)] or slotData.pallets[tostring(slotIndex)]
                if off then
                    local h = (type(off) == 'table' and off.heading) or 0.0
                    return off, h
                end
            end
        end
        -- 2. Varredura flexível por todas as entradas de Config.TrailerSlots comparando hash unsigned
        local targetU = keys[2]
        if targetU then
            for modelKey, sData in pairs(Config.TrailerSlots) do
                local numKey = tonumber(modelKey)
                local keyHash = numKey or joaat(tostring(modelKey):lower())
                local keyU = keyHash and (keyHash & 0xFFFFFFFF)
                if keyU == targetU and sData.pallets then
                    local off = sData.pallets[slotIndex] or sData.pallets[tonumber(slotIndex)] or sData.pallets[tostring(slotIndex)]
                    if off then
                        local h = (type(off) == 'table' and off.heading) or 0.0
                        return off, h
                    end
                end
            end
        end
    end
    local tModel = keys[1]
    if Config and Config.Polarix and Config.Polarix.CompatibleTrailers and tModel then
        for modelName, tData in pairs(Config.Polarix.CompatibleTrailers) do
            if (joaat(modelName) & 0xFFFFFFFF) == (tModel & 0xFFFFFFFF) and tData.attachOffsets then
                local off = tData.attachOffsets[slotIndex]
                if off then
                    local h = (type(off) == 'table' and off.heading) or 0.0
                    return off, h
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
    local keys = GetTrailerHashKeys(trailer)
    if Config and Config.TrailerSlots then
        -- 1. Verificação direta por todas as variações de chaves (raw, unsigned, signed, strings)
        for _, k in ipairs(keys) do
            local slotData = Config.TrailerSlots[k]
            if slotData and slotData.forklift then
                local off = slotData.forklift
                local h = (type(off) == 'table' and off.heading) or 0.0
                return off, h
            end
        end

        -- 2. Varredura flexível por todas as entradas de Config.TrailerSlots comparando hash unsigned
        local targetU = keys[2]
        if targetU then
            for modelKey, sData in pairs(Config.TrailerSlots) do
                local numKey = tonumber(modelKey)
                local keyHash = numKey or joaat(tostring(modelKey):lower())
                local keyU = keyHash and (keyHash & 0xFFFFFFFF)
                if keyU == targetU and sData.forklift then
                    local off = sData.forklift
                    local h = (type(off) == 'table' and off.heading) or 0.0
                    return off, h
                end
            end
        end
    end

    -- Fallback contextual para carretas longas comuns (trailers2, trailers)
    local targetU = keys[2]
    if targetU == (joaat('trailers2') & 0xFFFFFFFF) or targetU == (joaat('trailers') & 0xFFFFFFFF) then
        return { x = 0.0, y = -6.6, z = 0.35, heading = 0.0 }, 0.0
    end
    local fallback = { x = 0.0, y = -5.2, z = 0.35, heading = 0.0 }
    return fallback, 0.0
end

function ForkliftModule.GetGhostModelForSlot(trailer, slotIndex)
    local slotOff, _ = ForkliftModule.GetSlotOffset(trailer, slotIndex)
    if slotOff and slotOff.prop_model and slotOff.prop_model ~= '' then
        return slotOff.prop_model
    end
    if _G.ActiveJob and (_G.ActiveJob.cargoModel or _G.ActiveJob.cargo_model) then
        return _G.ActiveJob.cargoModel or _G.ActiveJob.cargo_model
    end
    return 'hei_prop_carrier_cargo_04b'
end

function ForkliftModule.SpawnGhostProp(trailer, model, offset, heading)
    ForkliftModule.DeleteGhostProp()
    if not trailer or not DoesEntityExist(trailer) or not offset then return nil end

    local rawModel = model
    if not rawModel or rawModel == '' then
        rawModel = 'hei_prop_carrier_cargo_04b'
    end

    local modelHash = 0
    if type(rawModel) == 'number' then
        modelHash = rawModel
    else
        modelHash = joaat(tostring(rawModel):lower())
    end

    if not IsModelInCdimage(modelHash) and type(rawModel) == 'string' then
        modelHash = joaat(rawModel)
    end

    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local t = 2500
        while not HasModelLoaded(modelHash) and t > 0 do
            Wait(25)
            t = t - 25
        end
    end

    if not HasModelLoaded(modelHash) then
        print(("[AUST_Trucker] AVISO: Falha ao carregar modelo de holograma %s, usando fallback."):format(tostring(rawModel)))
        modelHash = joaat('hei_prop_carrier_cargo_04b')
        RequestModel(modelHash)
        local t = 1000
        while not HasModelLoaded(modelHash) and t > 0 do Wait(20) t = t - 20 end
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

    -- Ancoragem padronizada rígida OneSync no Bone 0 (Root da Entidade) sem soft-pinning
    -- Garante correspondência 1:1 absoluta com as coordenadas do Gizmo 3D e do Holograma Fantasma
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    SetEntityHasGravity(palletEntity, false)
    SetEntityVelocity(palletEntity, 0.0, 0.0, 0.0)
    AttachEntityToEntity(
        palletEntity, targetTrailer, 0,
        slotOffset.x, slotOffset.y, slotOffset.z,
        0.0, 0.0, slotHeading,
        false, false, false, false, 2, true
    )

    -- BLINDAGEM HAVOK & COLISÃO COM O JOGADOR (Decisão do Usuário):
    -- Mantém colisão ativa com o jogador (o player NÃO atravessa o palete e pode subir nele).
    -- CRUCIAL: Congelar a entidade (FreezeEntityPosition = true) impede que o Havok calcule forças dinâmicas/torque de separação!
    SetEntityAsMissionEntity(palletEntity, true, true)
    SetEntityLodDist(palletEntity, 0xFFFF)
    FreezeEntityPosition(palletEntity, true)
    SetEntityDynamic(palletEntity, false)
    SetEntityCollision(palletEntity, true, true)
    SetCanClimbOnEntity(palletEntity, true)

    -- Drenagem de velocidades residuais para estancar impulsos Havok acumulados
    if targetTrailer and DoesEntityExist(targetTrailer) then
        SetEntityVelocity(targetTrailer, 0.0, 0.0, 0.0)
        SetVehicleForwardSpeed(targetTrailer, 0.0)
    end
    local currentForklift = ForkliftModule.GetPlayerForklift() or (_G.JobEntities and _G.JobEntities.forklift)
    if currentForklift and DoesEntityExist(currentForklift) then
        SetEntityVelocity(currentForklift, 0.0, 0.0, 0.0)
        SetVehicleForwardSpeed(currentForklift, 0.0)
    end

    -- Isolamento seletivo rigoroso contra o trailer e o caminhão
    SetEntityNoCollisionEntity(palletEntity, targetTrailer, false)
    SetEntityNoCollisionEntity(targetTrailer, palletEntity, false)
    local truck = _G.JobEntities and _G.JobEntities.truck
    if truck and DoesEntityExist(truck) then
        SetEntityNoCollisionEntity(palletEntity, truck, false)
        SetEntityNoCollisionEntity(truck, palletEntity, false)
    end

    -- BLINDAGEM ANTI-CLIPPING / ANTI-CATAPULTA FORKLIFT:
    -- Desativa colisão mútua por frame (Wait(0)) entre o palete, a empilhadeira e a carreta
    -- até os garfos recuarem completamente (distância > 3.8m ou timeout de 4 segundos)
    if currentForklift and DoesEntityExist(currentForklift) then
        SetEntityNoCollisionEntity(palletEntity, currentForklift, false)
        SetEntityNoCollisionEntity(currentForklift, palletEntity, false)
        SetEntityNoCollisionEntity(currentForklift, targetTrailer, false)
        SetEntityNoCollisionEntity(targetTrailer, currentForklift, false)

        CreateThread(function()
            local pEnt = palletEntity
            local fEnt = currentForklift
            local tEnt = targetTrailer
            local expire = GetGameTimer() + 4000
            while DoesEntityExist(pEnt) and DoesEntityExist(fEnt) and GetGameTimer() < expire do
                local dist = #(GetEntityCoords(pEnt) - GetEntityCoords(fEnt))
                if dist > 3.8 then
                    break
                end
                SetEntityNoCollisionEntity(pEnt, fEnt, true)
                SetEntityNoCollisionEntity(fEnt, pEnt, true)
                if DoesEntityExist(tEnt) then
                    SetEntityNoCollisionEntity(fEnt, tEnt, true)
                    SetEntityNoCollisionEntity(tEnt, fEnt, true)
                end
                Wait(0)
            end
        end)
    end

    -- Bloqueia migração de rede do OneSync para impedir rubberbanding (o motorista local governa a entidade)
    if NetworkGetEntityIsNetworked(palletEntity) then
        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(palletEntity), false)
    end

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

function ForkliftModule.SnapForkliftToSlot(forkliftEntity, trailer)
    if not forkliftEntity or not DoesEntityExist(forkliftEntity) then
        return false
    end

    local targetTrailer = (trailer and DoesEntityExist(trailer) and trailer) or (_G.JobEntities and _G.JobEntities.trailer)
    if not targetTrailer or not DoesEntityExist(targetTrailer) then
        print("[AUST_Trucker] ERRO: Trailer não encontrado para acoplamento da empilhadeira.")
        return false
    end

    local forkOffset, forkHeading = ForkliftModule.GetForkliftSlotOffset(targetTrailer)
    forkHeading = forkHeading or (type(forkOffset) == 'table' and forkOffset.heading) or 0.0

    -- Se o jogador estiver na empilhadeira, desembarca ordenadamente
    local ped = cache.ped or PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == forkliftEntity then
        TaskLeaveVehicle(ped, forkliftEntity, 16)
        Wait(400)
    end

    -- Controle de rede antes do acoplamento
    local timeout = 1500
    while not NetworkHasControlOfEntity(forkliftEntity) and timeout > 0 do
        NetworkRequestControlOfEntity(forkliftEntity)
        Wait(30)
        timeout = timeout - 30
    end

    DetachEntity(forkliftEntity, true, true)

    -- Ancoragem padronizada rígida OneSync no Bone 0 (Root) sem soft-pinning
    FreezeEntityPosition(forkliftEntity, false)
    SetEntityDynamic(forkliftEntity, false)
    SetEntityHasGravity(forkliftEntity, false)
    SetEntityVelocity(forkliftEntity, 0.0, 0.0, 0.0)
    AttachEntityToEntity(
        forkliftEntity, targetTrailer, 0,
        forkOffset.x, forkOffset.y, forkOffset.z,
        0.0, 0.0, forkHeading,
        false, false, false, false, 2, true
    )

    -- Blindagem Havok & Matriz de Colisão Híbrida:
    -- Mantém colisão ativa com o jogador para poder inspecionar/amarrar a pé
    -- e anula atrito e contato contra o trailer e o caminhão
    SetEntityAsMissionEntity(forkliftEntity, true, true)
    SetEntityLodDist(forkliftEntity, 0xFFFF)
    FreezeEntityPosition(forkliftEntity, false)
    SetEntityDynamic(forkliftEntity, false)
    SetEntityCollision(forkliftEntity, true, true)
    SetCanClimbOnEntity(forkliftEntity, true)
    SetEntityNoCollisionEntity(forkliftEntity, targetTrailer, false)
    SetEntityNoCollisionEntity(targetTrailer, forkliftEntity, false)
    local truck = _G.JobEntities and _G.JobEntities.truck
    if truck and DoesEntityExist(truck) then
        SetEntityNoCollisionEntity(forkliftEntity, truck, false)
        SetEntityNoCollisionEntity(truck, forkliftEntity, false)
    end

    if NetworkGetEntityIsNetworked(forkliftEntity) then
        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(forkliftEntity), false)
    end

    if NetworkGetEntityIsNetworked(targetTrailer) and NetworkGetEntityIsNetworked(forkliftEntity) then
        local fNet = NetworkGetNetworkIdFromEntity(forkliftEntity)
        Entity(targetTrailer).state:set('loadedForklift', {
            forkNet = fNet,
            offset = { x = forkOffset.x, y = forkOffset.y, z = forkOffset.z },
            heading = forkHeading
        }, true)
    end

    _G.ForkliftLoadedOnTrailer = true

    -- Deleta o holograma da empilhadeira
    ForkliftModule.DeleteGhostProp()
    return true, forkOffset, forkHeading
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

function ForkliftModule.StartOperation(jobId, trailer, requiredCount, onLoadedCb, onAllLoadedCb, withForklift)
    OperationActive = true
    TargetTrailerEntity = trailer
    CurrentSlotIndex = 1
    local loadedCount = 0
    local awaitingForkliftDock = false

    CreateThread(function()
        -- Lock 2: Coroutine Sequencial & Yield Bloqueante antes de Instanciar o Primeiro Fantasma
        if trailer and DoesEntityExist(trailer) then
            local tModel = GetEntityModel(trailer)
            local ok, res = pcall(function()
                return lib.callback.await('aurp_trucker:server:getTrailerOffsetsForModel', false, tModel)
            end)

            if ok and res and res.all then
                for mKey, data in pairs(res.all) do
                    local numKey = tonumber(mKey)
                    local h = numKey or joaat(tostring(mKey):lower())
                    local u = h & 0xFFFFFFFF
                    local s = (u >= 0x80000000) and (u - 0x100000000) or u
                    local storeKeys = { mKey, h, u, s, tostring(h), tostring(u), tostring(s) }
                    for _, sk in ipairs(storeKeys) do
                        if not Config.TrailerSlots[sk] then Config.TrailerSlots[sk] = { pallets = {}, forklift = nil } end
                        for idx, v in pairs(data.pallets or {}) do
                            local slotEntry = { id = v.id, label = v.label, prop_model = v.prop_model, x = tonumber(v.x) or 0.0, y = tonumber(v.y) or 0.0, z = tonumber(v.z) or 0.0, heading = tonumber(v.heading) or 0.0 }
                            Config.TrailerSlots[sk].pallets[tonumber(idx)] = slotEntry
                            Config.TrailerSlots[sk].pallets[tostring(idx)] = slotEntry
                        end
                        if data.forklift then
                            local slotEntry = { id = data.forklift.id, label = data.forklift.label, prop_model = data.forklift.prop_model or 'forklift', x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                            Config.TrailerSlots[sk].forklift = slotEntry
                        end
                    end
                end
                print("^2[AUST_Trucker Forklift] Lock 2 Sucesso: Offsets sincronizados antes de instanciar holograma!^7")
            end

            -- Yield defensivo para garantia de propagação atômica em memória
            Wait(50)

            if trailer and DoesEntityExist(trailer) then
                SetEntityCollision(trailer, true, true)
                SetCanClimbOnEntity(trailer, true)
            end
            local currentFork = ForkliftModule.GetPlayerForklift() or (_G.JobEntities and _G.JobEntities.forklift)
            if currentFork and DoesEntityExist(currentFork) then
                SetEntityCollision(currentFork, true, true)
                SetCanClimbOnEntity(currentFork, true)
            end

            local firstOffset, firstHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
            local ghostModel = ForkliftModule.GetGhostModelForSlot(trailer, CurrentSlotIndex)
            ForkliftModule.SpawnGhostProp(trailer, ghostModel, firstOffset, firstHeading)
        end

        while OperationActive do
            local sleep = 250
            local forklift = ForkliftModule.GetPlayerForklift()

            if forklift and DoesEntityExist(forklift) then
                if awaitingForkliftDock then
                    -- Caso 3: Embarque da Empilhadeira na Traseira do Reboque (Interação Controlada via [E] ou [G])
                    if trailer and DoesEntityExist(trailer) then
                        local fCoords = GetEntityCoords(forklift)
                        local relPos = GetOffsetFromEntityGivenWorldCoords(trailer, fCoords.x, fCoords.y, fCoords.z)
                        local fSlotOffset, fSlotHeading = ForkliftModule.GetForkliftSlotOffset(trailer)
                        local targetX = (type(fSlotOffset) == 'table' and fSlotOffset.x) or 0.0
                        local targetY = (type(fSlotOffset) == 'table' and fSlotOffset.y) or -5.5
                        local targetZ = (type(fSlotOffset) == 'table' and fSlotOffset.z) or 0.35

                        local dx = math.abs(relPos.x - targetX)
                        local dy = math.abs(relPos.y - targetY)
                        local dz = math.abs(relPos.z - targetZ)

                        if dx <= 2.2 and dy <= 3.2 and dz <= 2.5 then
                            sleep = 0
                            if TextUIShowing ~= 'dock_forklift' then
                                lib.showTextUI('[E] Embarcar Empilhadeira no Reboque', { position = 'left-center', icon = 'truck-ramp-box' })
                                TextUIShowing = 'dock_forklift'
                            end

                            if IsControlJustPressed(0, 38) or IsControlJustPressed(0, 47) then -- Tecla E (38) ou G (47)
                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end
                                local ok = ForkliftModule.SnapForkliftToSlot(forklift, trailer)
                                if ok then
                                    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                                    if _G.SendMissionNotify then
                                        _G.SendMissionNotify('Central Logística', 'Empilhadeira embarcada com sucesso! Ajuste as cintas de amarração.', 'success')
                                    end
                                    OperationActive = false
                                    if onAllLoadedCb then
                                        onAllLoadedCb()
                                    end
                                    break
                                end
                            end
                        else
                            if TextUIShowing == 'dock_forklift' then
                                lib.hideTextUI()
                                TextUIShowing = nil
                            end
                        end
                    end
                elseif not CurrentForkliftPallet then
                    -- Caso 1: Coleta Física do Palete no Chão (Sem botões / Auto-Attach por Elevação)
                    local targetPallet = ForkliftModule.GetNearestGroundPallet(forklift)
                    if targetPallet and DoesEntityExist(targetPallet) then
                        local forkCoords, forkBone = GetForkliftForksCoords(forklift)
                        local pCoords = GetEntityCoords(targetPallet)
                        local relPallet = GetOffsetFromEntityGivenWorldCoords(forklift, pCoords.x, pCoords.y, pCoords.z)

                        -- Alinhamento Angular entre a empilhadeira e o palete
                        local fHeading = GetEntityHeading(forklift)
                        local pHeading = GetEntityHeading(targetPallet)
                        local diffH = math.abs((fHeading - pHeading) % 180)
                        if diffH > 90 then diffH = 180 - diffH end
                        local isAngleAligned = (diffH <= 35.0)

                        -- Garfos encaixados sob a estrutura do palete:
                        -- Lateral: centrado entre os garfos (desvio <= 0.65m)
                        -- Longitudinal: penetração dos garfos sob a base do palete (Y entre 0.85m e 2.45m)
                        local isForksInside = (math.abs(relPallet.x) <= 0.65) and (relPallet.y >= 0.85 and relPallet.y <= 2.45)

                        if isForksInside and isAngleAligned then
                            sleep = 0
                            if TextUIShowing ~= 'forks_inserted' then
                                lib.showTextUI('Garfos encaixados: Erga o mastro para travar o palete (Shift / NumPad 5)', { position = 'left-center', icon = 'arrows-up-down' })
                                TextUIShowing = 'forks_inserted'
                            end

                            -- Gatilho de Elevação: comando de subida acionado ou elevação relativa dos garfos/palete
                            local isRaisingControl = IsControlPressed(0, 111) or IsControlPressed(0, 60) or IsControlPressed(0, 71)
                            local forkRelPos = GetOffsetFromEntityGivenWorldCoords(forklift, forkCoords.x, forkCoords.y, forkCoords.z)
                            local pHeightAboveGround = GetEntityHeightAboveGround(targetPallet)

                            -- Quando o jogador ergue o mastro e a carga descola do chão
                            local isLiftTriggered = (isRaisingControl and (forkRelPos.z > -0.38 or pHeightAboveGround > 0.15)) or (forkRelPos.z > -0.28) or (pHeightAboveGround > 0.22)

                            if isLiftTriggered then
                                if TextUIShowing then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end
                                local ok = AttachPalletToForklift(forklift, targetPallet)
                                if ok then
                                    CurrentForkliftPallet = targetPallet
                                    PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)
                                    PlaySoundFrontend(-1, "GARAGE_DOOR_SCRIPTED_CLOSE", "GTAO_SCRIPTED_DOOR_SOUNDS", 0)

                                    if onLoadedCb then
                                        onLoadedCb('picked', targetPallet, loadedCount, requiredCount)
                                    end
                                end
                            end
                        else
                            local dist = #(forkCoords - pCoords)
                            if dist <= 4.0 then
                                sleep = 0
                                if TextUIShowing ~= 'align_forks' then
                                    lib.showTextUI('Aproxime e encaixe os garfos nas canaletas do palete', { position = 'left-center', icon = 'pallet' })
                                    TextUIShowing = 'align_forks'
                                end
                            else
                                if TextUIShowing == 'align_forks' or TextUIShowing == 'forks_inserted' then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end
                            end
                        end
                    else
                        if TextUIShowing == 'align_forks' or TextUIShowing == 'forks_inserted' or TextUIShowing == 'pickup' then
                            lib.hideTextUI()
                            TextUIShowing = nil
                        end
                    end
                else
                    -- Caso 2: Acomodar Palete na Carreta (Auto-Snap Tridimensional ao Baixar a Carga no Fantasma)
                    if trailer and DoesEntityExist(trailer) then
                        local palletEntity = CurrentForkliftPallet
                        if not palletEntity or not DoesEntityExist(palletEntity) then
                            CurrentForkliftPallet = nil
                        else
                            -- Assegura que o holograma fantasma esteja ativo para o slot atual com o modelo do banco
                            if not CurrentGhostEntity or not DoesEntityExist(CurrentGhostEntity) then
                                local curSlotOff, curSlotHead = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                                local expectedModel = ForkliftModule.GetGhostModelForSlot(trailer, CurrentSlotIndex)
                                ForkliftModule.SpawnGhostProp(trailer, expectedModel, curSlotOff, curSlotHead)
                            end

                            local slotOffset, slotHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                            local ghostWorldCoords = GetOffsetFromEntityInWorldCoords(trailer, slotOffset.x, slotOffset.y, slotOffset.z)
                            local pCoords = GetEntityCoords(palletEntity)
                            local dist3D = #(pCoords - ghostWorldCoords)

                            -- Alinhamento angular entre o palete e o slot do reboque
                            local trailerH = GetEntityHeading(trailer)
                            local targetHeading = (trailerH + (slotHeading or 0.0)) % 360
                            local curH = GetEntityHeading(palletEntity)
                            local diffAngle = math.abs((curH - targetHeading) % 180)
                            if diffAngle > 90 then diffAngle = 180 - diffAngle end

                            -- Tolerância Balanceada: raio 3D <= 0.75m e ângulo <= 30°
                            local isAlignedInSlot = (dist3D <= 0.75) and (diffAngle <= 30.0)

                            local ghost = CurrentGhostEntity
                            if ghost and DoesEntityExist(ghost) then
                                if isAlignedInSlot then
                                    -- FEEDBACK VISUAL DINÂMICO: Verde Brilhante com Outline Shader
                                    SetEntityAlpha(ghost, 220, false)
                                    SetEntityDrawOutline(ghost, true)
                                    SetEntityDrawOutlineColor(30, 255, 60, 255)
                                    SetEntityDrawOutlineShader(1)
                                else
                                    -- Desalinhado / Em aproximação: Translúcido padrão sem outline
                                    SetEntityAlpha(ghost, 130, false)
                                    SetEntityDrawOutline(ghost, false)
                                end
                            end

                            if dist3D <= 2.5 then
                                sleep = 0
                                if isAlignedInSlot then
                                    if TextUIShowing ~= 'lower_forks' then
                                        lib.showTextUI(('Slot %d Alinhado: Abaixe os garfos para assentar (Ctrl / NumPad 8)'):format(CurrentSlotIndex), { position = 'left-center', icon = 'arrow-down' })
                                        TextUIShowing = 'lower_forks'
                                    end

                                    -- GATILHO DE AUTO-SNAP: O jogador começa a abaixar a carga sobre o slot
                                    local isLoweringControl = IsControlPressed(0, 110) or IsControlPressed(0, 61) or IsControlPressed(0, 72)
                                    local isCloseToDeck = (pCoords.z <= ghostWorldCoords.z + 0.18)

                                    if isLoweringControl or isCloseToDeck then
                                        if TextUIShowing then
                                            lib.hideTextUI()
                                            TextUIShowing = nil
                                        end

                                        if ghost and DoesEntityExist(ghost) then
                                            SetEntityDrawOutline(ghost, false)
                                        end

                                        local ok, sOff, sHead = ForkliftModule.SnapPalletToCurrentSlot(palletEntity, trailer, CurrentSlotIndex)
                                        if ok then
                                            local stowedSlot = CurrentSlotIndex
                                            CurrentForkliftPallet = nil
                                            loadedCount = loadedCount + 1
                                            CurrentSlotIndex = CurrentSlotIndex + 1

                                            PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                                            PlaySoundFrontend(-1, "GARAGE_DOOR_SCRIPTED_CLOSE", "GTAO_SCRIPTED_DOOR_SOUNDS", 0)

                                            -- Notifica o servidor com autoridade de rede e offsets completos
                                            local pNetId = NetworkGetEntityIsNetworked(palletEntity) and NetworkGetNetworkIdFromEntity(palletEntity) or nil
                                            TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, stowedSlot, pNetId, sOff, sHead)

                                            if onLoadedCb then
                                                onLoadedCb('dropped', palletEntity, loadedCount, requiredCount, stowedSlot, sOff, sHead)
                                            end

                                            if loadedCount < requiredCount then
                                                -- Spawna o holograma no próximo slot sequencial com o modelo homologado no banco
                                                local nextOffset, nextHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                                                local nextGhostModel = ForkliftModule.GetGhostModelForSlot(trailer, CurrentSlotIndex)
                                                ForkliftModule.SpawnGhostProp(trailer, nextGhostModel, nextOffset, nextHeading)
                                            else
                                                -- Todos os paletes estivados!
                                                local hasForklift = false
                                                if withForklift ~= nil then
                                                    hasForklift = (withForklift == true)
                                                elseif _G.ActiveJob and _G.ActiveJob.withForklift ~= nil then
                                                    hasForklift = (_G.ActiveJob.withForklift == true)
                                                else
                                                    local currentFork = forklift or ForkliftModule.GetPlayerForklift() or (_G.JobEntities and _G.JobEntities.forklift)
                                                    hasForklift = (currentFork ~= nil and DoesEntityExist(currentFork))
                                                end

                                                if hasForklift then
                                                    awaitingForkliftDock = true
                                                    ForkliftModule.SpawnForkliftGhost(trailer)
                                                    if _G.UpdateMissionObjective and trailer and DoesEntityExist(trailer) then
                                                        local fOff = ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(trailer) or { x = 0.0, y = -6.0, z = 0.35 }
                                                        local dockWorldPos = GetOffsetFromEntityInWorldCoords(trailer, fOff.x or 0.0, fOff.y or -6.0, (fOff.z or 0.35) + 0.6)
                                                        _G.UpdateMissionObjective('forklift_dock', dockWorldPos, 'Embarcar Empilhadeira no Reboque [E]')
                                                    end
                                                    if _G.SendMissionNotify then
                                                        _G.SendMissionNotify('Central Logística', 'Paletes estivados! Posicione a empilhadeira na traseira da carreta e pressione [E] para embarcar.', 'info')
                                                    end
                                                else
                                                    ForkliftModule.StopOperation()
                                                    if onAllLoadedCb then
                                                        onAllLoadedCb()
                                                    end
                                                    break
                                                end
                                            end
                                        end
                                    end
                                else
                                    if TextUIShowing ~= 'align_slot' then
                                        lib.showTextUI(('Alinhe a carga sobre o Fantasma do Slot %d'):format(CurrentSlotIndex), { position = 'left-center', icon = 'truck-ramp-box' })
                                        TextUIShowing = 'align_slot'
                                    end
                                end
                            else
                                if TextUIShowing == 'align_slot' or TextUIShowing == 'lower_forks' then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end
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

function ForkliftModule.SafeDetachWithDistanceCheck(entity, attachedTo, minDistance)
    if not entity or not DoesEntityExist(entity) then return end
    minDistance = minDistance or 2.5

    -- Desativa imediatamente colisões mútuas antes de descolar
    if attachedTo and DoesEntityExist(attachedTo) then
        SetEntityNoCollisionEntity(entity, attachedTo, false)
        SetEntityNoCollisionEntity(attachedTo, entity, false)
    end

    DetachEntity(entity, true, true)
    FreezeEntityPosition(entity, false)
    SetEntityDynamic(entity, true)

    if attachedTo and DoesEntityExist(attachedTo) then
        CreateThread(function()
            local e = entity
            local a = attachedTo
            local expire = GetGameTimer() + 4000
            while DoesEntityExist(e) and DoesEntityExist(a) and GetGameTimer() < expire do
                local dist = #(GetEntityCoords(e) - GetEntityCoords(a))
                if dist >= minDistance then
                    break
                end
                SetEntityNoCollisionEntity(e, a, false)
                SetEntityNoCollisionEntity(a, e, false)
                Wait(100)
            end
        end)
    end
end

function ForkliftModule.StopOperation()
    OperationActive = false
    if TextUIShowing then
        lib.hideTextUI()
        TextUIShowing = nil
    end
    if CurrentForkliftPallet and DoesEntityExist(CurrentForkliftPallet) then
        local forklift = ForkliftModule.GetPlayerForklift()
        ForkliftModule.SafeDetachWithDistanceCheck(CurrentForkliftPallet, forklift, 2.5)
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
