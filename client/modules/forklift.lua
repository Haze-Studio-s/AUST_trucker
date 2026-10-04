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
        if Config.Debug then print("[AUST_Trucker] ERRO: Trailer não encontrado para acoplamento do palete.") end
        return false
    end

    -- Garante que o alvo não seja a própria empilhadeira
    if _G.JobEntities and targetTrailer == _G.JobEntities.forklift then
        if Config.Debug then print("[AUST_Trucker] ERRO: Alvo de estiva detectado como empilhadeira! Abortando attach errôneo.") end
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

    -- BLINDAGEM HAVOK & ESTIVA SEGURA (Decisão do Usuário - v20.8.0):
    -- NUNCA congelar entidade anexada a veículo (FreezeEntityPosition = true em entidade com Attach causa
    -- conflito de restrição de coordenadas no Havok, gerando impulsos gigantescos que catapultam veículos).
    -- Mantém a carga imóvel relativamente ao reboque via Dynamic/Gravity false sem afetar a suspensão.
    SetEntityAsMissionEntity(palletEntity, true, true)
    SetEntityLodDist(palletEntity, 0xFFFF)
    FreezeEntityPosition(palletEntity, false)
    SetEntityDynamic(palletEntity, false)
    SetEntityHasGravity(palletEntity, false)
    SetEntityCollision(palletEntity, false, false)
    SetCanClimbOnEntity(palletEntity, false)

    -- Isolamento seletivo rigoroso do palete contra o trailer e o caminhão
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
                SetEntityNoCollisionEntity(pEnt, fEnt, true)
                SetEntityNoCollisionEntity(fEnt, pEnt, true)
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
                    -- OPERAÇÃO FÍSICA REAL (Sem AttachEntityToEntity entre empilhadeira e paletes)
                    local forkCoords, forkBone = GetForkliftForksCoords(forklift)

                    -- 1. Monitoramento da Carga e Elevação Z (Gatilho Dinâmico do Fantasma)
                    local activeCarried = nil
                    for _, p in pairs(ActiveMissionPallets) do
                        if p and DoesEntityExist(p) and not IsEntityAttached(p) then
                            local pCoords = GetEntityCoords(p)
                            
                            -- Registra Z de repouso no solo na primeira leitura
                            if not PalletBaseZ[p] then
                                PalletBaseZ[p] = pCoords.z
                            end

                            local relP = GetOffsetFromEntityGivenWorldCoords(forklift, pCoords.x, pCoords.y, pCoords.z)
                            -- Checagem física de posição sobre os garfos
                            if math.abs(relP.x) <= 0.85 and (relP.y >= 0.5 and relP.y <= 2.8) then
                                local forkRelP = GetOffsetFromEntityGivenWorldCoords(forklift, forkCoords.x, forkCoords.y, forkCoords.z)
                                if math.abs(relP.z - forkRelP.z) <= 0.65 then
                                    activeCarried = p
                                end
                            end

                            -- Se o palete subiu >= 0.12m do repouso ou está nos garfos
                            local zLift = pCoords.z - PalletBaseZ[p]
                            if (zLift >= 0.12 or activeCarried == p) and not activeCarried then
                                activeCarried = p
                            end
                        end
                    end
                    DetectedCarriedPallet = activeCarried

                    -- GATILHO DO FANTASMA: Só instancia quando a palete for levantada da terra
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

                    -- 2. Varredura de Alinhamento no Slot do Reboque
                    local slotPalletCandidate = nil
                    local isCandidateInSlot = false

                    if trailer and DoesEntityExist(trailer) and not isStowingPallet then
                        local slotOffset, slotHeading = ForkliftModule.GetSlotOffset(trailer, CurrentSlotIndex)
                        local ghostWorldCoords = GetOffsetFromEntityInWorldCoords(trailer, slotOffset.x, slotOffset.y, slotOffset.z)
                        local trailerCoords = GetEntityCoords(trailer)
                        local trailerH = GetEntityHeading(trailer)
                        local targetHeading = (trailerH + (slotHeading or 0.0)) % 360

                        for _, p in pairs(ActiveMissionPallets) do
                            if p and DoesEntityExist(p) and not IsEntityAttached(p) then
                                local pCoords = GetEntityCoords(p)
                                local dist3D = #(pCoords - ghostWorldCoords)
                                local distToTrailer = #(pCoords - trailerCoords)

                                -- Tolerância de 1.10m em relação ao slot no deck do reboque
                                if distToTrailer <= 5.5 then
                                    local curH = GetEntityHeading(p)
                                    local diffAngle = math.abs((curH - targetHeading) % 180)
                                    if diffAngle > 90 then diffAngle = 180 - diffAngle end

                                    local isNearDeck = math.abs(pCoords.z - ghostWorldCoords.z) <= 0.45
                                    if dist3D <= 1.10 and diffAngle <= 35.0 and isNearDeck then
                                        slotPalletCandidate = p
                                        isCandidateInSlot = true
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

                    -- 3. Nova Lógica de Snap (Fixação no Reboque) com Estabilização Havok Wait(500)
                    if slotPalletCandidate and DoesEntityExist(slotPalletCandidate) and not isStowingPallet then
                        sleep = 0
                        local pCoords = GetEntityCoords(slotPalletCandidate)
                        local distForksToPallet = #(forkCoords - pCoords)

                        if distForksToPallet < 1.80 then
                            -- Garfos ainda engatados sob a carga
                            if TextUIShowing ~= 'retract_forks' then
                                lib.showTextUI(('Palete no Slot %d! Abaixe os garfos e recue a empilhadeira para travar'):format(CurrentSlotIndex), { position = 'left-center', icon = 'arrow-down' })
                                TextUIShowing = 'retract_forks'
                            end
                        else
                            -- GARFOS RETIRADOS POR COMPLETO (distância >= 1.80m)!
                            isStowingPallet = true
                            if TextUIShowing then
                                lib.hideTextUI()
                                TextUIShowing = nil
                            end

                            local ghost = CurrentGhostEntity
                            if ghost and DoesEntityExist(ghost) then
                                SetEntityDrawOutline(ghost, false)
                            end

                            -- AGUARDA 500ms PARA A FÍSICA HAVOK ESTABILIZAR ANTES DO ATTACH DEFINITIVO
                            Wait(500)

                            local targetPalletToSnap = slotPalletCandidate
                            if DoesEntityExist(targetPalletToSnap) then
                                local ok, sOff, sHead = ForkliftModule.SnapPalletToCurrentSlot(targetPalletToSnap, trailer, CurrentSlotIndex)
                                if ok then
                                    local stowedSlot = CurrentSlotIndex
                                    DetectedCarriedPallet = nil
                                    loadedCount = loadedCount + 1
                                    CurrentSlotIndex = CurrentSlotIndex + 1

                                    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                                    PlaySoundFrontend(-1, "GARAGE_DOOR_SCRIPTED_CLOSE", "GTAO_SCRIPTED_DOOR_SOUNDS", 0)

                                    local pNetId = NetworkGetEntityIsNetworked(targetPalletToSnap) and NetworkGetNetworkIdFromEntity(targetPalletToSnap) or nil
                                    TriggerServerEvent('aurp_trucker:server:polarixPalletLoaded', jobId, stowedSlot, pNetId, sOff, sHead)

                                    if onLoadedCb then
                                        onLoadedCb('dropped', targetPalletToSnap, loadedCount, requiredCount, stowedSlot, sOff, sHead)
                                    end

                                    -- Elimina o holograma do slot recém ocupado; o próximo só surge quando a próxima carga for erguida
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

                                    CreateThread(function()
                                        Wait(1000)
                                        isStowingPallet = false
                                    end)
                                else
                                    isStowingPallet = false
                                end
                            else
                                isStowingPallet = false
                            end
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
                                    lib.showTextUI('Encaixe os garfos sob o palete e erga o mastro (Shift / NumPad 5)', { position = 'left-center', icon = 'pallet' })
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
