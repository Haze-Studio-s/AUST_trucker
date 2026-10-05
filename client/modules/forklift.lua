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

local DetectedCarriedPallet = nil

function ForkliftModule.GetCarriedPallet()
    return DetectedCarriedPallet
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

-- ============================================================
-- HELPER GLOBAL E EXPORT: OFFSETS DO PROPEDITOR (6DoF)
-- ============================================================
function GetVehiclePropOffset(vehicle, propModel)
    if not vehicle or not DoesEntityExist(vehicle) or not propModel then return nil, nil end
    local vHash = GetEntityModel(vehicle)
    local pHash = type(propModel) == 'number' and propModel or joaat(tostring(propModel):lower())

    if Config and Config.VehiclePropOffsets then
        local vUnsigned = vHash & 0xFFFFFFFF
        local vSigned = (vUnsigned >= 0x80000000) and (vUnsigned - 0x100000000) or vUnsigned
        local pUnsigned = pHash & 0xFFFFFFFF

        local vKeys = { vHash, vUnsigned, vSigned, tostring(vHash), tostring(vUnsigned) }
        local pKeys = { pHash, pUnsigned, tostring(pHash), tostring(propModel):lower() }

        for _, vk in ipairs(vKeys) do
            local vehGroup = Config.VehiclePropOffsets[vk]
            if vehGroup then
                for _, pk in ipairs(pKeys) do
                    local entry = vehGroup[pk]
                    if entry then
                        local pos = vector3(entry.offset_x or (entry.offset and entry.offset.x) or 0.0,
                                            entry.offset_y or (entry.offset and entry.offset.y) or 0.0,
                                            entry.offset_z or (entry.offset and entry.offset.z) or 0.0)
                        local rot = vector3(entry.rot_pitch or (entry.rotation and entry.rotation.x) or 0.0,
                                            entry.rot_roll  or (entry.rotation and entry.rotation.y) or 0.0,
                                            entry.rot_yaw   or (entry.rotation and entry.rotation.z) or 0.0)
                        return pos, rot
                    end
                end
            end
        end
    end
    return nil, nil
end
exports('GetVehiclePropOffset', GetVehiclePropOffset)

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
    -- 1. Se a empilhadeira já estiver transportando um palete, o fantasma reflete 1:1 essa carga
    if DetectedCarriedPallet and DoesEntityExist(DetectedCarriedPallet) then
        return GetEntityModel(DetectedCarriedPallet)
    end
    if CurrentForkliftPallet and DoesEntityExist(CurrentForkliftPallet) then
        return GetEntityModel(CurrentForkliftPallet)
    end
    -- 2. Se os garfos estiverem vazios, projeta o prop configurado no banco para este slot
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
    SetEntityVisible(ghost, true)
    ResetEntityAlpha(ghost)
    DisableCamCollisionForEntity(ghost)

    -- Holograma Fantasma: semi-transparente, sem colisão, invencível e imune
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    SetCanClimbOnEntity(ghost, false)
    FreezeEntityPosition(ghost, true)

    local finalOff = offset
    local finalPitch, finalRoll = 0.0, 0.0
    local finalYaw = heading or (type(offset) == 'table' and offset.heading) or 0.0

    -- Se houver micro-ajuste angular no PropEditor para este prop, aplica apenas nas rotações secundárias
    local customPropOffset, customPropRot = GetVehiclePropOffset(trailer, modelHash)
    if customPropRot then
        finalPitch, finalRoll = customPropRot.x, customPropRot.y
    end

    AttachEntityToEntity(
        ghost, trailer, 0,
        finalOff.x, finalOff.y, finalOff.z,
        finalPitch, finalRoll, finalYaw,
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
        if Config.Debug then print("[AUST_Trucker] ERRO: Trailer não encontrado para acoplamento do palete.") end
        return false
    end

    -- Garante que o alvo não seja a própria empilhadeira
    if _G.JobEntities and targetTrailer == _G.JobEntities.forklift then
        if Config.Debug then print("[AUST_Trucker] ERRO: Alvo de estiva detectado como empilhadeira! Abortando attach errôneo.") end
        return false
    end

    -- RESGATE PRIORITÁRIO DE OFFSETS DOS SLOTS DO REBOQUE (A Única Fonte de Verdade)
    -- Os slots configurados pelo Admin na aba Offsets Trailer 3D (Config.TrailerSlots)
    -- governam estritamente a posição (X, Y, Z) e rotação base (Heading/Yaw) de cada slot individual (1..N).
    local slotOff, slotHead = ForkliftModule.GetSlotOffset(targetTrailer, slotIndex)
    local finalX = (type(slotOff) == 'table' and slotOff.x) or 0.0
    local finalY = (type(slotOff) == 'table' and slotOff.y) or 0.0
    local finalZ = (type(slotOff) == 'table' and slotOff.z) or 0.35
    local finalPitch, finalRoll = 0.0, 0.0
    local finalYaw = slotHead or (type(slotOff) == 'table' and slotOff.heading) or 0.0

    -- Micro-ajustes angulares do prop (PropEditor nunca sobrescreve posição X/Y/Z dos slots de trailer)
    local pModel = GetEntityModel(palletEntity)
    local _, adminRot = GetVehiclePropOffset(targetTrailer, pModel)
    if adminRot then
        finalPitch, finalRoll = adminRot.x, adminRot.y
    end

    -- Controle de rede antes do acoplamento
    local timeout = 1500
    while not NetworkHasControlOfEntity(palletEntity) and timeout > 0 do
        NetworkRequestControlOfEntity(palletEntity)
        Wait(30)
        timeout = timeout - 30
    end

    DetachEntity(palletEntity, true, true)

    -- ANCORAGEM RIGOROSA 6DoF NO OFFSET DO ADMIN (Sobrescrita total de física e pose dinâmica)
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    SetEntityHasGravity(palletEntity, false)
    SetEntityVelocity(palletEntity, 0.0, 0.0, 0.0)
    AttachEntityToEntity(
        palletEntity, targetTrailer, 0,
        finalX, finalY, finalZ,
        finalPitch, finalRoll, finalYaw,
        false, false, true, false, 2, true
    )

    -- BLINDAGEM HAVOK & ESTIVA SEGURA (Decisão do Usuário - v20.8.0):
    -- NUNCA congelar entidade anexada a veículo (FreezeEntityPosition = true em entidade com Attach causa
    -- conflito de restrição de coordenadas no Havok, gerando impulsos gigantescos que catapultam veículos).
    -- Mantém a carga imóvel relativamente ao reboque via Dynamic/Gravity false sem afetar a suspensão.
    SetEntityAsMissionEntity(palletEntity, true, true)
    SetEntityLodDist(palletEntity, 0xFFFF)
    SetEntityVisible(palletEntity, true)
    ResetEntityAlpha(palletEntity)
    DisableCamCollisionForEntity(palletEntity)
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    SetEntityHasGravity(palletEntity, false)
    -- COLISÃO FÍSICA SÓLIDA PARA JOGADORES E VEÍCULOS (Diretriz 3):
    SetEntityCollision(palletEntity, true, true)
    SetCanClimbOnEntity(palletEntity, true)

    -- Isolamento seletivo rigoroso do palete contra a chapa do trailer para evitar interferência na suspensão
    SetEntityNoCollisionEntity(palletEntity, targetTrailer, false)
    SetEntityNoCollisionEntity(targetTrailer, palletEntity, false)
    local truck = _G.JobEntities and _G.JobEntities.truck
    if truck and DoesEntityExist(truck) then
        SetEntityNoCollisionEntity(palletEntity, truck, false)
        SetEntityNoCollisionEntity(truck, palletEntity, false)
    end

    -- BLINDAGEM ANTI-CLIPPING FORKLIFT (Decisões A1, A2 e A3 do Usuário):
    -- NUNCA forçar SetEntityVelocity(forklift, 0,0,0) ou desligar a colisão entre currentForklift e targetTrailer!
    -- A empilhadeira opera sobre a prancha metálica da carreta e precisa manter suporte físico sólido e suspensão raycast ativa.
    -- Desativa-se o contato entre a empilhadeira e o palete recém-assentado para desacoplamento suave sem tração.
    local currentForklift = ForkliftModule.GetPlayerForklift() or (_G.JobEntities and _G.JobEntities.forklift)
    if currentForklift and DoesEntityExist(currentForklift) then
        SetEntityNoCollisionEntity(palletEntity, currentForklift, false)
        SetEntityNoCollisionEntity(currentForklift, palletEntity, false)

        -- Supressão de Input de Descida por 800ms: impede que o condutor force a ponta dos garfos contra a chapa do assoalho
        CreateThread(function()
            local endSuppression = GetGameTimer() + 800
            while GetGameTimer() < endSuppression do
                DisableControlAction(0, 110, true) -- INPUT_VEH_FLY_PITCH_DOWN (Ctrl)
                DisableControlAction(0, 61, true)  -- INPUT_VEH_SUB_PITCH_DOWN
                DisableControlAction(0, 72, true)  -- INPUT_VEH_BRAKE
                Wait(0)
            end
        end)

        CreateThread(function()
            local pEnt = palletEntity
            local fEnt = currentForklift
            local expire = GetGameTimer() + 4000
            while DoesEntityExist(pEnt) and DoesEntityExist(fEnt) and GetGameTimer() < expire do
                local dist = #(GetEntityCoords(pEnt) - GetEntityCoords(fEnt))
                if dist > 3.5 then
                    break
                end
                SetEntityNoCollisionEntity(pEnt, fEnt, false)
                SetEntityNoCollisionEntity(fEnt, pEnt, false)
                Wait(50)
            end
        end)
    end

    -- Bloqueia migração de rede do OneSync para impedir rubberbanding (o motorista local governa a entidade)
    if NetworkGetEntityIsNetworked(palletEntity) then
        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(palletEntity), false)
    end

    local finalOffsetVec = vector3(finalX or 0.0, finalY or 0.0, finalZ or 0.0)
    local finalRotVec = vector3(finalPitch or 0.0, finalRoll or 0.0, finalYaw or 0.0)

    -- Sincronização OneSync via Entity StateBags (Pilar 1)
    if NetworkGetEntityIsNetworked(targetTrailer) and NetworkGetEntityIsNetworked(palletEntity) then
        local pNet = NetworkGetNetworkIdFromEntity(palletEntity)
        local curSlots = Entity(targetTrailer).state.loadedSlots or {}
        curSlots[tostring(slotIndex)] = {
            palletNet = pNet,
            offset = { x = finalX, y = finalY, z = finalZ },
            heading = finalYaw,
            rotation = { pitch = finalPitch, roll = finalRoll, yaw = finalYaw }
        }
        Entity(targetTrailer).state:set('loadedSlots', curSlots, true)
    end

    -- Deleta o holograma do slot recém-ocupado
    ForkliftModule.DeleteGhostProp()
    return true, finalOffsetVec, finalRotVec
end

function ForkliftModule.SnapForkliftToSlot(forkliftEntity, trailer)
    if not forkliftEntity or not DoesEntityExist(forkliftEntity) then
        return false
    end

    local targetTrailer = (trailer and DoesEntityExist(trailer) and trailer) or (_G.JobEntities and _G.JobEntities.trailer)
    if not targetTrailer or not DoesEntityExist(targetTrailer) then
        if Config.Debug then print("[AUST_Trucker] ERRO: Trailer não encontrado para acoplamento da empilhadeira.") end
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

function ForkliftModule.StartOperation(jobId, trailer, requiredCount, onLoadedCb, onAllLoadedCb, withForklift)
    OperationActive = true
    TargetTrailerEntity = trailer
    CurrentSlotIndex = 1
    local loadedCount = 0
    local awaitingForkliftDock = false
    local isStowingPallet = false

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
                if Config.Debug then print("^2[AUST_Trucker Forklift] Lock 2 Sucesso: Offsets sincronizados antes de instanciar holograma!^7") end
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

            -- Não gera holograma inicial no reboque: o reboque permanece limpo até a carga ser erguida
        end

        local PalletBaseZ = {} -- Mapeia o Z de descanso inicial de cada palete
        local PalletPhysState = {} -- Controla transições atômicas para blindar contra Reliable network event overflow
        local PalletReengageCooldown = {} -- Cooldown para evitar que paletes soltos no reboque sejam reengatados imediatamente

        while OperationActive do
            local sleep = 150
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
                else
                    -- OPERAÇÃO COM ACOPLAMENTO TEMPORÁRIO NOS GARFOS (Blindagem Anti-Overflow de Rede)
                    local forkCoords, forkBone = GetForkliftForksCoords(forklift)

                    -- 1. Gerenciamento de Acoplamento Temporário por Altura (TRAVA DE CARGA ÚNICA - Diretriz 1)
                    local activeCarried = DetectedCarriedPallet

                    -- Valida se a empilhadeira já carrega um palete ativo nos garfos
                    local isAlreadyCarrying = false
                    if activeCarried and DoesEntityExist(activeCarried) and IsEntityAttachedToEntity(activeCarried, forklift) then
                        isAlreadyCarrying = true
                    else
                        activeCarried = nil
                        DetectedCarriedPallet = nil
                    end

                    -- Se já estiver carregando, bloqueia completamente a busca e novos engates (Diretriz 1)
                    if not isAlreadyCarrying then
                        -- Monta lista de paletes candidatos soltos (tabela da missão + palete mais próximo no solo)
                        local candidatePallets = {}
                        local seenPallets = {}
                        for _, p in pairs(ActiveMissionPallets) do
                            if p and DoesEntityExist(p) and not seenPallets[p] and not IsEntityAttached(p) then
                                seenPallets[p] = true
                                candidatePallets[#candidatePallets + 1] = p
                            end
                        end
                        local nearestP = ForkliftModule.GetNearestGroundPallet(forklift)
                        if nearestP and DoesEntityExist(nearestP) and not seenPallets[nearestP] and not IsEntityAttached(nearestP) then
                            seenPallets[nearestP] = true
                            candidatePallets[#candidatePallets + 1] = nearestP
                        end

                        -- FILTRO DE ENTIDADE ÚNICA (Diretriz 2): Ordena da menor para a maior distância até os garfos
                        if #candidatePallets > 1 then
                            table.sort(candidatePallets, function(a, b)
                                local distA = #(forkCoords - GetEntityCoords(a))
                                local distB = #(forkCoords - GetEntityCoords(b))
                                return distA < distB
                            end)
                        end

                        for _, p in ipairs(candidatePallets) do
                            if p and DoesEntityExist(p) then
                                local pCoords = GetEntityCoords(p)

                                if not PalletBaseZ[p] then
                                    PalletBaseZ[p] = pCoords.z
                                end

                                -- SENTINELA ANTI-LIMBO (Garantia de Colisão e Solo Firme):
                                -- Se a física ou colisão falhar e o palete afundar > 0.35m abaixo do nível de solo seguro,
                                -- intercepta e reposiciona imediatamente no piso com colisão ativa e sem afundamento.
                                if not IsEntityAttached(p) and PalletBaseZ[p] and (pCoords.z < (PalletBaseZ[p] - 0.35)) then
                                    SetEntityVelocity(p, 0.0, 0.0, 0.0)
                                    SetEntityCoordsNoOffset(p, pCoords.x, pCoords.y, PalletBaseZ[p], false, false, false)
                                    SetEntityCollision(p, true, true)
                                    SetCanClimbOnEntity(p, true)
                                    FreezeEntityPosition(p, true)
                                    pCoords = GetEntityCoords(p)
                                end

                                local pState = PalletPhysState[p] or 'frozen'

                                if pState == 'attached_to_forks' then
                                    activeCarried = p
                                    break
                                elseif pState == 'recoil_zone' or (PalletReengageCooldown[p] and GetGameTimer() < PalletReengageCooldown[p]) then
                                    -- Palete em processo de desengate/recuo: proibido reengatar nos garfos
                                else
                                    -- Só processa engate se a carga não estiver estivada no reboque
                                    if not IsEntityAttached(p) then
                                        -- DETECÇÃO 3D NO ESPAÇO LOCAL DO PALETE (PONTAS DOS GARFOS NO VÃO INFERIOR)
                                        local relToPal = GetOffsetFromEntityGivenWorldCoords(p, forkCoords.x, forkCoords.y, forkCoords.z)

                                        -- DETECÇÃO 3D NO ESPAÇO LOCAL DO PALETE (PONTAS DOS GARFOS NO VÃO INFERIOR):
                                        -- Alinhamento Angular: perdoa até 45 graus (incluindo ré/trás por simetria a 180°)
                                        local forkH = GetEntityHeading(forklift)
                                        local palH  = GetEntityHeading(p)
                                        local diffAngle = math.abs((forkH - palH) % 180)
                                        if diffAngle > 90 then diffAngle = 180 - diffAngle end
                                        local isAngleAligned = (diffAngle <= 45.0)

                                        -- Encaixe Físico dos Garfos dentro do Palete:
                                        -- Eixo X (Centralização lateral): tolerância de até ±0.80m (janela total de 1.60m)
                                        -- Eixo Y (Penetração dos garfos): limite de até ±1.10m do centro do palete
                                        -- Eixo Z (Altura vertical dos garfos): entrada entre -0.60m e +0.60m (janela total de 1.20m)
                                        local isEngagedWithForks = isAngleAligned
                                            and (math.abs(relToPal.x) <= 0.80)
                                            and (math.abs(relToPal.y) <= 1.10)
                                            and (relToPal.z >= -0.60 and relToPal.z <= 0.60)

                                        if isEngagedWithForks then
                                            -- GATILHO ATÔMICO DE ACOPLAMENTO AUTOMÁTICO DIRETO (Diretriz 2 & Decisão A2)
                                            if NetworkGetEntityIsNetworked(p) and not NetworkHasControlOfEntity(p) then
                                                NetworkRequestControlOfEntity(p)
                                            end

                                            -- Descongela e anexa instantaneamente aos garfos da empilhadeira
                                            SetEntityVelocity(p, 0.0, 0.0, 0.0)
                                            FreezeEntityPosition(p, false)
                                            SetEntityDynamic(p, false)
                                            SetEntityHasGravity(p, false)

                                            local forkOffX, forkOffY, forkOffZ = 0.0, 0.95, -0.05
                                            local forkPitch, forkRoll, forkYaw = 0.0, 0.0, 0.0

                                            local customForkOff, customForkRot = GetVehiclePropOffset(forklift, GetEntityModel(p))
                                            if customForkOff then
                                                forkOffX, forkOffY, forkOffZ = customForkOff.x, customForkOff.y, customForkOff.z
                                                if customForkRot then
                                                    forkPitch, forkRoll, forkYaw = customForkRot.x, customForkRot.y, customForkRot.z
                                                end
                                            end

                                            AttachEntityToEntity(
                                                p, forklift, forkBone,
                                                forkOffX, forkOffY, forkOffZ,
                                                forkPitch, forkRoll, forkYaw,
                                                false, false, false, false, 2, true
                                            )

                                            PalletPhysState[p] = 'attached_to_forks'
                                            activeCarried = p
                                            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)

                                            -- INTERRUPÇÃO IMEDIATA DO LAÇO (Diretriz 3): impede engate em cascata
                                            break
                                        else
                                            -- ESTABILIDADE E COLISÃO SÓLIDA NO SOLO:
                                            -- Mantém o palete perfeitamente firme e assentado no chão para manobra precisa da empilhadeira.
                                            -- NUNCA chamar SetEntityCompletelyDisableCollision em loop (destrói cache de manifolds Havok)!
                                            if pState ~= 'frozen' then
                                                SetEntityCollision(p, true, true)
                                                SetCanClimbOnEntity(p, true)
                                                FreezeEntityPosition(p, true)
                                                SetEntityDynamic(p, false)
                                                SetEntityHasGravity(p, true)
                                                SetEntityVelocity(p, 0.0, 0.0, 0.0)
                                                PalletPhysState[p] = 'frozen'
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    DetectedCarriedPallet = activeCarried

                    -- GATILHO DO FANTASMA: Instancia assim que o palete for acoplado aos garfos
                    if trailer and DoesEntityExist(trailer) then
                        if DetectedCarriedPallet then
                            local carriedModel = GetEntityModel(DetectedCarriedPallet)
                            local curGhostModel = CurrentGhostEntity and DoesEntityExist(CurrentGhostEntity) and GetEntityModel(CurrentGhostEntity) or nil
                            local carriedU = carriedModel & 0xFFFFFFFF
                            local ghostU = curGhostModel and (curGhostModel & 0xFFFFFFFF) or nil
                            if not CurrentGhostEntity or not DoesEntityExist(CurrentGhostEntity) or (ghostU ~= carriedU) then
                                local curSlotOff, curSlotHead = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                                ForkliftModule.SpawnGhostProp(trailer, carriedModel, curSlotOff, curSlotHead)
                            end
                        end
                    end

                    -- 2. Monitoramento 3D de Alinhamento e Desacoplamento Automático no Fantasma
                    local slotPalletCandidate = nil
                    local isCandidateInSlot = false

                    if trailer and DoesEntityExist(trailer) and not isStowingPallet then
                        local slotOffset, slotHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                        local ghostWorldCoords = GetOffsetFromEntityInWorldCoords(trailer, slotOffset.x, slotOffset.y, slotOffset.z)
                        local trailerCoords = GetEntityCoords(trailer)
                        local trailerH = GetEntityHeading(trailer)
                        local targetHeading = (trailerH + (slotHeading or 0.0)) % 360

                        for _, p in pairs(ActiveMissionPallets) do
                            if p and DoesEntityExist(p) then
                                local pCoords = GetEntityCoords(p)
                                local distToTrailer = #(pCoords - trailerCoords)
                                local pState = PalletPhysState[p] or 'frozen'

                                -- Tolerância de área de trabalho em relação ao trailer
                                if distToTrailer <= 5.5 then
                                    local distXY = #(vector2(pCoords.x, pCoords.y) - vector2(ghostWorldCoords.x, ghostWorldCoords.y))
                                    local deltaZ = pCoords.z - ghostWorldCoords.z

                                    local curH = GetEntityHeading(p)
                                    local diffAngle = math.abs((curH - targetHeading) % 180)
                                    if diffAngle > 90 then diffAngle = 180 - diffAngle end

                                    -- FAIXA DE ALINHAMENTO AMPLA (Diretriz 1 - Decisão do Usuário):
                                    -- Raio horizontal XY <= 0.65m, altura Z entre -0.25m e +0.25m e ângulo <= 25 graus
                                    local isAlignedWithGhost = (distXY <= 0.65) and (deltaZ >= -0.25 and deltaZ <= 0.25) and (diffAngle <= 25.0)

                                    if isAlignedWithGhost or pState == 'stowed_awaiting_recoil' then
                                        slotPalletCandidate = p
                                        isCandidateInSlot = true

                                        -- SNAP IMEDIATO E MANDATÓRIO NO FANTASMA (Diretriz do Usuário):
                                        -- Desanexa instantaneamente dos garfos e acopla no trailer nas coordenadas e rotação exatas do fantasma
                                        if pState == 'attached_to_forks' and isAlignedWithGhost and not isStowingPallet then
                                            isStowingPallet = true

                                            -- Elimina o holograma fantasma imediatamente
                                            ForkliftModule.DeleteGhostProp()

                                            -- Força encaixe atômico direto no trailer pelo slot
                                            local ok, sOff, sHead = ForkliftModule.SnapPalletToCurrentSlot(p, trailer, CurrentSlotIndex)
                                            if ok then
                                                PalletPhysState[p] = 'stowed_awaiting_recoil'
                                                DetectedCarriedPallet = nil

                                                -- Desativa colisão mútua imediata com a empilhadeira para manobra livre de ré
                                                SetEntityNoCollisionEntity(p, forklift, false)
                                                SetEntityNoCollisionEntity(forklift, p, false)

                                                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)
                                            else
                                                isStowingPallet = false
                                            end
                                        end

                                        break
                                    end
                                end
                            end
                        end

                        local ghost = CurrentGhostEntity
                        if ghost and DoesEntityExist(ghost) then
                            if isCandidateInSlot then
                                SetEntityAlpha(ghost, 220, false)
                                SetEntityDrawOutline(ghost, true)
                                SetEntityDrawOutlineColor(30, 255, 60, 255)
                                SetEntityDrawOutlineShader(1)
                            else
                                SetEntityAlpha(ghost, 130, false)
                                SetEntityDrawOutline(ghost, false)
                            end
                        end
                    end

                    -- 3. Zona de Recuo Livre & Reativação de Colisão Sólida (distância >= 1.0m)
                    if slotPalletCandidate and DoesEntityExist(slotPalletCandidate) and PalletPhysState[slotPalletCandidate] == 'stowed_awaiting_recoil' then
                        sleep = 0
                        local pCoords = GetEntityCoords(slotPalletCandidate)
                        local distForksToPallet = #(forkCoords - pCoords)

                        if distForksToPallet < 1.0 then
                            -- Empilhadeira ainda dentro da Zona de Recuo (< 1.0 metro)
                            if TextUIShowing ~= 'retract_forks' then
                                lib.showTextUI(('Palete estivado no Slot %d! Recue a empilhadeira 1 metro'):format(CurrentSlotIndex), { position = 'left-center', icon = 'arrow-down' })
                                TextUIShowing = 'retract_forks'
                            end
                            -- Mantém colisões desativadas enquanto os garfos estão sob/perto da carga
                            SetEntityNoCollisionEntity(slotPalletCandidate, forklift, false)
                            SetEntityNoCollisionEntity(forklift, slotPalletCandidate, false)
                        else
                            -- RECUO COMPLETO (Distância >= 1.0m) -> REATIVA COLISÃO E AVANÇA O SLOT
                            if TextUIShowing then
                                lib.hideTextUI()
                                TextUIShowing = nil
                            end

                            local stowedPallet = slotPalletCandidate
                            local stowedSlot = CurrentSlotIndex

                            -- Reativa colisão física completa com a empilhadeira e com o jogador
                            SetEntityNoCollisionEntity(stowedPallet, forklift, true)
                            SetEntityNoCollisionEntity(forklift, stowedPallet, true)
                            SetEntityCollision(stowedPallet, true, true)
                            SetCanClimbOnEntity(stowedPallet, true)

                            PalletPhysState[stowedPallet] = 'stowed'
                            DetectedCarriedPallet = nil
                            loadedCount = loadedCount + 1
                            CurrentSlotIndex = CurrentSlotIndex + 1

                            PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                            PlaySoundFrontend(-1, "GARAGE_DOOR_SCRIPTED_CLOSE", "GTAO_SCRIPTED_DOOR_SOUNDS", 0)

                            local pNetId = NetworkGetEntityIsNetworked(stowedPallet) and NetworkGetNetworkIdFromEntity(stowedPallet) or nil
                            local curSlotOff, curSlotHead = ForkliftModule.GetSlotOffset(trailer, stowedSlot)
                            TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, stowedSlot, pNetId, curSlotOff, curSlotHead)

                            if onLoadedCb then
                                onLoadedCb('dropped', stowedPallet, loadedCount, requiredCount, stowedSlot, curSlotOff, curSlotHead)
                            end

                            -- Elimina o holograma do slot recém ocupado
                            ForkliftModule.DeleteGhostProp()

                            if loadedCount >= requiredCount then
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

                            slotPalletCandidate = nil
                            isStowingPallet = false
                        end
                    else
                        if TextUIShowing == 'retract_forks' then
                            lib.hideTextUI()
                            TextUIShowing = nil
                        end

                        -- Feedback visual suave se estiver manobrando próximo a um palete no chão
                        local targetPallet = ForkliftModule.GetNearestGroundPallet(forklift)
                        if targetPallet and DoesEntityExist(targetPallet) and not DetectedCarriedPallet then
                            local pCoords = GetEntityCoords(targetPallet)
                            local dist = #(forkCoords - pCoords)
                            if dist <= 3.5 then
                                sleep = 0
                                if TextUIShowing ~= 'forks_guide' then
                                    lib.showTextUI('Alinhe e insira os garfos por baixo do vão do palete', { position = 'left-center', icon = 'pallet' })
                                    TextUIShowing = 'forks_guide'
                                end
                            else
                                if TextUIShowing == 'forks_guide' then
                                    lib.hideTextUI()
                                    TextUIShowing = nil
                                end
                            end
                        else
                            if TextUIShowing == 'forks_guide' then
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
