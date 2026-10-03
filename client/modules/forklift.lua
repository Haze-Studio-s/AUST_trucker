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

function ForkliftModule.GetSlotOffset(trailer, slotIndex)
    local tModel = ResolveTrailerModel(trailer)
    if tModel and Config and Config.TrailerSlots then
        -- 1. Verificação direta por hash numérico ou chave string
        local slotData = Config.TrailerSlots[tModel] or Config.TrailerSlots[tostring(tModel)]
        if slotData and slotData.pallets then
            local off = slotData.pallets[slotIndex] or slotData.pallets[tostring(slotIndex)]
            if off then
                local h = (type(off) == 'table' and off.heading) or 0.0
                return off, h
            end
        end
        -- 2. Varredura flexível por nome de modelo ou hash
        for modelKey, sData in pairs(Config.TrailerSlots) do
            local numKey = tonumber(modelKey)
            local keyHash = numKey or joaat(tostring(modelKey):lower())
            if keyHash == tModel and sData.pallets then
                local off = sData.pallets[slotIndex] or sData.pallets[tostring(slotIndex)]
                if off then
                    local h = (type(off) == 'table' and off.heading) or 0.0
                    return off, h
                end
            end
        end
    end
    if Config and Config.Polarix and Config.Polarix.CompatibleTrailers and tModel then
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
    -- Fallback sequencial em fileiras duplas (frente para trás)
    local col = ((slotIndex - 1) % 2 == 0) and -0.55 or 0.55
    local row = math.floor((slotIndex - 1) / 2)
    local yOffset = 3.6 - (row * 2.4)
    local fallback = { x = col, y = yOffset, z = 0.35, heading = 0.0 }
    return fallback, 0.0
end

function ForkliftModule.GetForkliftSlotOffset(trailer)
    local tModel = ResolveTrailerModel(trailer)
    if tModel and Config and Config.TrailerSlots then
        -- 1. Verificação direta por hash numérico ou chave string
        local slotData = Config.TrailerSlots[tModel] or Config.TrailerSlots[tostring(tModel)]
        if slotData and slotData.forklift then
            local off = slotData.forklift
            local h = (type(off) == 'table' and off.heading) or 0.0
            return off, h
        end
        -- 2. Varredura flexível por nome ou hash numérico
        for modelKey, sData in pairs(Config.TrailerSlots) do
            local numKey = tonumber(modelKey)
            local keyHash = numKey or joaat(tostring(modelKey):lower())
            if keyHash == tModel and sData.forklift then
                local off = sData.forklift
                local h = (type(off) == 'table' and off.heading) or 0.0
                return off, h
            end
        end
    end

    -- Fallback contextual para carretas longas comuns (trailers2, trailers)
    if tModel == joaat('trailers2') or tModel == joaat('trailers') then
        return { x = 0.0, y = -6.6, z = 0.35, heading = 0.0 }, 0.0
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

    -- BLINDAGEM HAVOK & COLISÃO COM O JOGADOR:
    -- Mantém colisão ativa com o jogador e o mundo (o player NÃO atravessa o palete e pode subir nele),
    -- enquanto isola 100% o contato com o trailer e o cavalo mecânico para eliminar a catapulta Havok.
    SetEntityAsMissionEntity(palletEntity, true, true)
    SetEntityLodDist(palletEntity, 0xFFFF)
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    SetEntityCollision(palletEntity, true, true)
    SetCanClimbOnEntity(palletEntity, true)
    SetEntityNoCollisionEntity(palletEntity, targetTrailer, false)
    SetEntityNoCollisionEntity(targetTrailer, palletEntity, false)
    local truck = _G.JobEntities and _G.JobEntities.truck
    if truck and DoesEntityExist(truck) then
        SetEntityNoCollisionEntity(palletEntity, truck, false)
        SetEntityNoCollisionEntity(truck, palletEntity, false)
    end

    -- BLINDAGEM ANTI-CLIPPING / ANTI-PRENDIMENTO:
    -- Anula a colisão física mútua com a empilhadeira para que os garfos possam recuar sem prender
    local currentForklift = ForkliftModule.GetPlayerForklift() or (_G.JobEntities and _G.JobEntities.forklift)
    if currentForklift and DoesEntityExist(currentForklift) then
        SetEntityNoCollisionEntity(palletEntity, currentForklift, false)
        SetEntityNoCollisionEntity(currentForklift, palletEntity, false)

        -- Thread de desobstrução segura: mantém sem colisão até a empilhadeira se afastar (ou timeout de 5s)
        CreateThread(function()
            local pEnt = palletEntity
            local fEnt = currentForklift
            local expire = GetGameTimer() + 5000
            while DoesEntityExist(pEnt) and DoesEntityExist(fEnt) and GetGameTimer() < expire do
                local dist = #(GetEntityCoords(pEnt) - GetEntityCoords(fEnt))
                if dist > 3.5 then
                    break
                end
                SetEntityNoCollisionEntity(pEnt, fEnt, false)
                SetEntityNoCollisionEntity(fEnt, pEnt, false)
                Wait(100)
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
                    if not Config.TrailerSlots[h] then Config.TrailerSlots[h] = { pallets = {}, forklift = nil } end
                    if not Config.TrailerSlots[mKey] then Config.TrailerSlots[mKey] = { pallets = {}, forklift = nil } end
                    if numKey and not Config.TrailerSlots[numKey] then Config.TrailerSlots[numKey] = { pallets = {}, forklift = nil } end
                    for idx, v in pairs(data.pallets or {}) do
                        local slotEntry = { x = tonumber(v.x) or 0.0, y = tonumber(v.y) or 0.0, z = tonumber(v.z) or 0.0, heading = tonumber(v.heading) or 0.0 }
                        Config.TrailerSlots[h].pallets[tonumber(idx)] = slotEntry
                        Config.TrailerSlots[mKey].pallets[tonumber(idx)] = slotEntry
                        if numKey then Config.TrailerSlots[numKey].pallets[tonumber(idx)] = slotEntry end
                    end
                    if data.forklift then
                        local slotEntry = { x = tonumber(data.forklift.x) or 0.0, y = tonumber(data.forklift.y) or 0.0, z = tonumber(data.forklift.z) or 0.0, heading = tonumber(data.forklift.heading) or 0.0 }
                        Config.TrailerSlots[h].forklift = slotEntry
                        Config.TrailerSlots[mKey].forklift = slotEntry
                        if numKey then Config.TrailerSlots[numKey].forklift = slotEntry end
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
                if awaitingForkliftDock then
                    -- Caso 3: Embarque Contínuo da Empilhadeira na Traseira via [G]
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
                                lib.showTextUI('[G] Embarcar Empilhadeira no Reboque', { position = 'left-center', icon = 'truck-ramp-box' })
                                TextUIShowing = 'dock_forklift'
                            end

                            if IsControlJustPressed(0, 47) then -- Tecla G (control 47)
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

                                    -- Notifica o servidor com autoridade de rede e offsets completos
                                    local pNetId = NetworkGetEntityIsNetworked(palletEntity) and NetworkGetNetworkIdFromEntity(palletEntity) or nil
                                    TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, stowedSlot, pNetId, slotOffset, slotHeading)

                                    if onLoadedCb then
                                        onLoadedCb('dropped', palletEntity, loadedCount, requiredCount, stowedSlot, slotOffset, slotHeading)
                                    end

                                    if loadedCount < requiredCount then
                                        -- Spawna o holograma no próximo slot sequencial de palete
                                        local nextOffset, nextHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                                        ForkliftModule.SpawnGhostProp(trailer, 'hei_prop_carrier_cargo_04b', nextOffset, nextHeading)
                                    else
                                        -- Todos os paletes estivados! O fantasma da empilhadeira surge IMEDIATAMENTE antes da amarração
                                        local currentFork = forklift or ForkliftModule.GetPlayerForklift() or (_G.JobEntities and _G.JobEntities.forklift)
                                        local hasForklift = (withForklift == true)
                                            or (_G.ActiveJob and _G.ActiveJob.withForklift)
                                            or (_G.JobEntities and _G.JobEntities.forklift and DoesEntityExist(_G.JobEntities.forklift))
                                            or (currentFork ~= nil and DoesEntityExist(currentFork))

                                        if hasForklift then
                                            -- GATILHO IMEDIATO DO FANTASMA DA EMPILHADEIRA (Embarque Contínuo)
                                            awaitingForkliftDock = true
                                            ForkliftModule.SpawnForkliftGhost(trailer)
                                            if _G.UpdateMissionObjective and trailer and DoesEntityExist(trailer) then
                                                local fOff = ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(trailer) or { x = 0.0, y = -6.0, z = 0.35 }
                                                local dockWorldPos = GetOffsetFromEntityInWorldCoords(trailer, fOff.x or 0.0, fOff.y or -6.0, (fOff.z or 0.35) + 0.6)
                                                _G.UpdateMissionObjective('forklift_dock', dockWorldPos, 'Embarcar Empilhadeira no Reboque [G]')
                                            end
                                            if _G.SendMissionNotify then
                                                _G.SendMissionNotify('Central Logística', 'Paletes estivados! Posicione a empilhadeira na traseira da carreta e pressione [G] para embarcar.', 'info')
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
