-- aurp_trucker — client/modules/offset_editor.lua
-- Módulo In-Game de Calibração Visual 3D de Offsets de Reboque e Gerenciamento de Spawns/NPCs
-- Motor de Gizmo 3D (Three.js + TransformControls) adaptado do vp_staff_studio (Haze-Studio-s)

OffsetEditor = {}

local IsCalibrating = false
local CalibTrailer = nil
local CalibGhost = nil
local SavedGhosts = {}
local SavedSlotOffsets = {}
local LastSavedSlotIndex = nil
local CurrentOffsets = { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
local CalibParams = { trailerModel = 'trailers2', slotIndex = 1, isForklift = false, propModel = 'hei_prop_carrier_cargo_04b' }
local CurrentGizmoMode = 'translate' -- 'translate' | 'rotate'
local IsGizmoCursorActive = false

-- Alvo de Calibração 3D em Offsets de Trailer: Carga vs Cinta Catraca
local CalibTarget = 'cargo' -- 'cargo' | 'strap'
local CalibStrapGhost = nil
local CurrentStrapOffsets = { x = 0.0, y = 0.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 }
local CurrentSlotStraps = {}

-- Estado de Posicionamento Sequencial em Lote (Spawns Dinâmicos)
local BatchSpawnState = {
    active = false,
    total = 1,
    current = 1,
    baseData = nil,
    confirmedItems = {},
    previewEntities = {}
}

local ActiveCreatedTrailer = false
local ActiveCalibCam = nil

-- Variáveis de Calibração Visual de Pontos de Spawn (Visibilidade Global no Módulo)
local IsCalibratingSpawn = false
local SpawnGhostEnt = nil
local SpawnCam = nil
local ActiveDuplicationData = nil
local ActiveCalibSpawnData = nil
local CurrentSpawnCoords = { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
local ActivePreviewEntities = {}
local ActivePreviewMarkers = {}
local IsPreviewActive = false

-- Cache de NPCs dinâmicos criados pelo Admin
local DynamicAdminPeds = {}

-- ============================================================
-- SPAWN E GERENCIAMENTO DO FANTASMA
-- ============================================================

local function SpawnCalibGhost(trailer, isForklift, propModel, offsetVec, heading)
    if CalibGhost and DoesEntityExist(CalibGhost) then
        DeleteEntity(CalibGhost)
        CalibGhost = nil
    end

    local tCoords = GetEntityCoords(trailer)
    local tHeading = GetEntityHeading(trailer)
    local worldPos = GetOffsetFromEntityInWorldCoords(trailer, offsetVec.x, offsetVec.y, offsetVec.z)
    local targetRotZ = (tHeading + (heading or 0.0)) % 360.0

    local ghost = nil
    if isForklift then
        local forkHash = joaat('forklift')
        lib.requestModel(forkHash, 5000)
        ghost = CreateVehicle(forkHash, worldPos.x, worldPos.y, worldPos.z, targetRotZ, false, false)
        if ghost and DoesEntityExist(ghost) then
            SetVehicleDoorsLocked(ghost, 2)
        end
    else
        local pHash = joaat(propModel or 'hei_prop_carrier_cargo_04b')
        lib.requestModel(pHash, 5000)
        ghost = CreateObject(pHash, worldPos.x, worldPos.y, worldPos.z, false, false, false)
        if ghost and DoesEntityExist(ghost) then
            SetEntityHeading(ghost, targetRotZ)
        end
    end

    if not ghost or ghost == 0 or not DoesEntityExist(ghost) then
        if Config.Debug then print("[AUST_Trucker] Falha crítica ao spawnar entidade fantasma para calibração.") end
        return nil
    end

    SetEntityAsMissionEntity(ghost, true, true)
    SetEntityLodDist(ghost, 0xFFFF)
    SetEntityAlpha(ghost, 200, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)

    CalibGhost = ghost
    return ghost
end

-- ============================================================
-- NUI CALLBACKS: MANIPULAÇÃO DO GIZMO 3D (THREE.JS)
-- ============================================================

function OffsetEditor.SwitchCalibrationTarget(target)
    if not IsCalibrating or not CalibTrailer or not DoesEntityExist(CalibTrailer) then return end
    target = target or 'cargo'

    if target == 'strap' then
        if not CalibGhost or not DoesEntityExist(CalibGhost) then return end
        CalibTarget = 'strap'

        if not CalibStrapGhost or not DoesEntityExist(CalibStrapGhost) then
            local strapHash = joaat('prop_ratchet_strap')
            lib.requestModel(strapHash, 5000)
            local gCoords = GetEntityCoords(CalibGhost)
            local gHeading = GetEntityHeading(CalibGhost)

            local strapObj = CreateObject(strapHash, gCoords.x, gCoords.y, gCoords.z + 0.05, false, false, false)
            if strapObj and DoesEntityExist(strapObj) then
                SetEntityAsMissionEntity(strapObj, true, true)
                SetEntityAlpha(strapObj, 220, false)
                SetEntityCollision(strapObj, false, false)
                SetEntityInvincible(strapObj, true)
                FreezeEntityPosition(strapObj, true)
                SetEntityHeading(strapObj, gHeading)
                CalibStrapGhost = strapObj
            end
        end

        if CalibStrapGhost and DoesEntityExist(CalibStrapGhost) then
            local sPos = GetEntityCoords(CalibStrapGhost)
            local sRot = GetEntityRotation(CalibStrapGhost, 2)
            SendNUIMessage({
                action = 'setGizmoEntity',
                data = {
                    position = { x = sPos.x, y = sPos.y, z = sPos.z },
                    rotation = { x = sRot.x, y = sRot.y, z = sRot.z }
                }
            })
            SendNUIMessage({ action = 'setGizmoTarget', data = { target = 'strap', showToggle = true } })
            lib.notify({ title = 'Gizmo: Cinta de Amarração', description = 'Ajuste a cinta sobre a carga. [ENTER] para confirmar.', type = 'info', duration = 3000 })
        end
    else
        CalibTarget = 'cargo'
        if CalibGhost and DoesEntityExist(CalibGhost) then
            local cPos = GetEntityCoords(CalibGhost)
            local cRot = GetEntityRotation(CalibGhost, 2)
            SendNUIMessage({
                action = 'setGizmoEntity',
                data = {
                    position = { x = cPos.x, y = cPos.y, z = cPos.z },
                    rotation = { x = cRot.x, y = cRot.y, z = cRot.z }
                }
            })
            SendNUIMessage({ action = 'setGizmoTarget', data = { target = 'cargo', showToggle = true } })
            lib.notify({ title = 'Gizmo: Prop da Carga', description = 'Ajuste o posicionamento da carga no reboque.', type = 'info', duration = 3000 })
        end
    end
end

RegisterNUICallback('switchGizmoTarget', function(data, cb)
    local target = (data and data.target) or 'cargo'
    OffsetEditor.SwitchCalibrationTarget(target)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('moveGizmoOffset', function(data, cb)
    if not IsCalibrating or not CalibTrailer or not DoesEntityExist(CalibTrailer) then
        if cb then cb({ ok = false }) end
        return
    end

    local worldPos = data.position
    local worldRot = data.rotation

    if worldPos then
        local tRot = GetEntityRotation(CalibTrailer, 2)
        local relOffset = GetOffsetFromEntityGivenWorldCoords(CalibTrailer, worldPos.x, worldPos.y, worldPos.z)
        local relHeading = 0.0
        if worldRot and worldRot.z then
            relHeading = (worldRot.z - tRot.z) % 360.0
        end

        if CalibTarget == 'strap' then
            if CalibStrapGhost and DoesEntityExist(CalibStrapGhost) then
                CurrentStrapOffsets = {
                    x = tonumber(string.format("%.3f", relOffset.x)),
                    y = tonumber(string.format("%.3f", relOffset.y)),
                    z = tonumber(string.format("%.3f", relOffset.z)),
                    rx = tonumber(string.format("%.1f", ((worldRot and worldRot.x or 0.0) - tRot.x) % 360.0)),
                    ry = tonumber(string.format("%.1f", ((worldRot and worldRot.y or 0.0) - tRot.y) % 360.0)),
                    rz = tonumber(string.format("%.1f", relHeading)),
                    heading = tonumber(string.format("%.1f", relHeading))
                }
                SetEntityCoordsNoOffset(CalibStrapGhost, worldPos.x, worldPos.y, worldPos.z, false, false, false)
                if worldRot then
                    SetEntityRotation(CalibStrapGhost, worldRot.x or 0.0, worldRot.y or 0.0, worldRot.z or 0.0, 2, true)
                end
            end
        else
            if CalibGhost and DoesEntityExist(CalibGhost) then
                CurrentOffsets = {
                    x = tonumber(string.format("%.3f", relOffset.x)),
                    y = tonumber(string.format("%.3f", relOffset.y)),
                    z = tonumber(string.format("%.3f", relOffset.z)),
                    heading = tonumber(string.format("%.1f", relHeading))
                }
                SetEntityCoordsNoOffset(CalibGhost, worldPos.x, worldPos.y, worldPos.z, false, false, false)
                if worldRot and worldRot.z then
                    SetEntityHeading(CalibGhost, worldRot.z)
                end
            end
        end
    end

    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('confirmGizmoSlot', function(data, cb)
    if IsCalibrating then
        OffsetEditor.ConfirmCurrentSlot()
    elseif IsPropEditorActive then
        OffsetEditor.ConfirmPropEditorSlot()
    elseif IsCalibratingSpawn then
        OffsetEditor.StopSpawnCalibration(SpawnCam, true)
    end
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('copyGizmoSlot', function(data, cb)
    if IsCalibrating then
        OffsetEditor.CopyPreviousSlot()
    end
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('cancelGizmo', function(data, cb)
    if IsCalibrating then
        OffsetEditor.CancelCalibration()
    elseif IsPropEditorActive then
        OffsetEditor.CancelPropEditorSession()
    elseif IsCalibratingSpawn then
        OffsetEditor.StopSpawnCalibration(SpawnCam, false)
    end
    if cb then cb({ ok = true }) end
end)

-- ============================================================
-- CÓPIA DE ALTURA E ROTAÇÃO DE PROPS JÁ SALVOS
-- ============================================================

function OffsetEditor.CopyPreviousSlot()
    if not IsCalibrating or not CalibTrailer or not DoesEntityExist(CalibTrailer) or not CalibGhost or not DoesEntityExist(CalibGhost) then
        return
    end

    local refSlot = nil
    if CalibParams.slotIndex and CalibParams.slotIndex > 1 and SavedSlotOffsets[CalibParams.slotIndex - 1] then
        refSlot = CalibParams.slotIndex - 1
    elseif LastSavedSlotIndex and SavedSlotOffsets[LastSavedSlotIndex] then
        refSlot = LastSavedSlotIndex
    end

    if not refSlot or not SavedSlotOffsets[refSlot] then
        lib.notify({
            title = 'Cópia Indisponível',
            description = 'Nenhum slot anterior salvo nesta sessão para copiar a altura e rotação.',
            type = 'error',
            duration = 3500
        })
        return
    end

    local src = SavedSlotOffsets[refSlot]
    CurrentOffsets.z = src.z
    CurrentOffsets.heading = src.heading

    local worldPos = GetOffsetFromEntityInWorldCoords(CalibTrailer, CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z)
    SetEntityCoordsNoOffset(CalibGhost, worldPos.x, worldPos.y, worldPos.z, false, false, false)
    local tHeading = GetEntityHeading(CalibTrailer)
    SetEntityHeading(CalibGhost, (tHeading + CurrentOffsets.heading) % 360.0)

    local gWorldRot = GetEntityRotation(CalibGhost, 2)
    SendNUIMessage({
        action = 'setGizmoEntity',
        data = {
            position = { x = worldPos.x, y = worldPos.y, z = worldPos.z },
            rotation = { x = gWorldRot.x, y = gWorldRot.y, z = gWorldRot.z }
        }
    })

    PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)
    lib.notify({
        title = 'Offset Clonado!',
        description = ('Altura (Z: %.3f) e Rotação (%.1f°) copiadas do Slot %d.'):format(src.z, src.heading, refSlot),
        type = 'info',
        duration = 3000
    })
end

-- ============================================================
-- CONFIRMAÇÃO E PROGRESSÃO CONTÍNUA DE SLOTS
-- ============================================================

function OffsetEditor.ConfirmCurrentSlot()
    if not IsCalibrating then return end

    local strapsPayload = nil
    if CalibStrapGhost and DoesEntityExist(CalibStrapGhost) then
        strapsPayload = { CurrentStrapOffsets }
    end

    -- 1. Dispara salvamento no banco de dados
    TriggerServerEvent('aurp_trucker:server:adminSaveTrailerOffset', {
        trailerModel = CalibParams.trailerModel,
        slotIndex = CalibParams.slotIndex,
        isForklift = CalibParams.isForklift,
        propModel = CalibParams.propModel,
        label = CalibParams.label,
        customName = CalibParams.customName,
        propCount = CalibParams.propCount,
        folderName = CalibParams.folderName,
        x = tonumber(string.format("%.3f", CurrentOffsets.x)),
        y = tonumber(string.format("%.3f", CurrentOffsets.y)),
        z = tonumber(string.format("%.3f", CurrentOffsets.z)),
        heading = tonumber(string.format("%.1f", CurrentOffsets.heading)),
        straps = strapsPayload
    })
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    -- Grava no cache de sessão para cópia e herança
    SavedSlotOffsets[CalibParams.slotIndex] = {
        x = tonumber(string.format("%.3f", CurrentOffsets.x)),
        y = tonumber(string.format("%.3f", CurrentOffsets.y)),
        z = tonumber(string.format("%.3f", CurrentOffsets.z)),
        heading = tonumber(string.format("%.1f", CurrentOffsets.heading)),
        straps = strapsPayload
    }
    LastSavedSlotIndex = CalibParams.slotIndex

    -- 2. Determina o limite de slots de palete
    local maxPallets = 6
    local curHash = joaat(CalibParams.trailerModel)
    if Config.TrailerSlots and Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].pallets then
        local pCount = #Config.TrailerSlots[curHash].pallets
        if pCount > maxPallets then maxPallets = pCount end
    end

    -- 3. Preserva o fantasma do slot recém-calibrado como guia visual translúcido
    if CalibGhost and DoesEntityExist(CalibGhost) then
        SetEntityAlpha(CalibGhost, 110, false)
        table.insert(SavedGhosts, CalibGhost)
        CalibGhost = nil
    end

    if CalibStrapGhost and DoesEntityExist(CalibStrapGhost) then
        SetEntityAlpha(CalibStrapGhost, 110, false)
        table.insert(SavedGhosts, CalibStrapGhost)
        CalibStrapGhost = nil
    end
    CalibTarget = 'cargo'

    -- 4. Transição contínua entre slots
    if not CalibParams.isForklift then
        if CalibParams.slotIndex < maxPallets then
            local prevSlot = CalibParams.slotIndex
            CalibParams.slotIndex = CalibParams.slotIndex + 1

            -- Auto-sugere label para o próximo slot mantendo coerência
            if CalibParams.label and CalibParams.label ~= '' then
                local basePrefix = CalibParams.label:match("^(.-)%s*%d+$")
                if basePrefix and basePrefix ~= '' then
                    CalibParams.label = ("%s %d"):format(basePrefix, CalibParams.slotIndex)
                else
                    CalibParams.label = ("Slot %d"):format(CalibParams.slotIndex)
                end
            else
                CalibParams.label = ("Slot %d"):format(CalibParams.slotIndex)
            end

            lib.notify({
                title = 'Slot Salvo no Banco!',
                description = ('Slot %d salvo. Calibrando Slot %d (%s).'):format(prevSlot, CalibParams.slotIndex, CalibParams.propModel or 'Padrão'),
                type = 'success',
                duration = 3500
            })

            local nextVec = (Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].pallets and Config.TrailerSlots[curHash].pallets[CalibParams.slotIndex])
            local nextHeading = 0.0
            if not nextVec then
                nextVec, nextHeading = ForkliftModule.GetSlotOffset(CalibTrailer, CalibParams.slotIndex)
            else
                nextHeading = (type(nextVec) == 'table' and nextVec.heading) or 0.0
            end

            -- HERANÇA AUTOMÁTICA INTELIGENTE: herda Z e Heading do slot anterior
            local inheritOffset = SavedSlotOffsets[prevSlot]
            local targetZ = (inheritOffset and inheritOffset.z) or nextVec.z
            local targetHeading = (inheritOffset and inheritOffset.heading) or nextHeading

            CurrentOffsets = { x = nextVec.x, y = nextVec.y, z = targetZ, heading = targetHeading }
            SpawnCalibGhost(CalibTrailer, false, CalibParams.propModel, vector3(nextVec.x, nextVec.y, targetZ), targetHeading)

            -- Reposiciona o Gizmo Three.js no novo fantasma
            local nextGhostPos = GetEntityCoords(CalibGhost)
            local nextGhostRot = GetEntityRotation(CalibGhost, 2)
            SendNUIMessage({
                action = 'setGizmoEntity',
                data = {
                    position = { x = nextGhostPos.x, y = nextGhostPos.y, z = nextGhostPos.z },
                    rotation = { x = nextGhostRot.x, y = nextGhostRot.y, z = nextGhostRot.z }
                }
            })
        else
            -- Todos os paletes calibrados! Avança automaticamente para a Empilhadeira!
            CalibParams.isForklift = true
            CalibParams.slotIndex = maxPallets + 1
            lib.notify({
                title = 'Paletes Finalizados!',
                description = 'Todos os slots de paletes foram calibrados! Agora ajustando o Slot da Empilhadeira.',
                type = 'info',
                duration = 5000
            })

            local forkVec, forkHeading = (Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].forklift), 0.0
            if not forkVec then
                forkVec, forkHeading = ForkliftModule.GetForkliftSlotOffset(CalibTrailer)
            else
                forkHeading = (type(forkVec) == 'table' and forkVec.heading) or 0.0
            end
            CurrentOffsets = { x = forkVec.x, y = forkVec.y, z = forkVec.z, heading = forkHeading }
            SpawnCalibGhost(CalibTrailer, true, 'forklift', forkVec, forkHeading)

            local forkPos = GetEntityCoords(CalibGhost)
            local forkRot = GetEntityRotation(CalibGhost, 2)
            SendNUIMessage({
                action = 'setGizmoEntity',
                data = {
                    position = { x = forkPos.x, y = forkPos.y, z = forkPos.z },
                    rotation = { x = forkPos.x, y = forkRot.y, z = forkRot.z }
                }
            })
        end
    else
        -- Slot da empilhadeira finalizado! Ciclo completo!
        lib.notify({
            title = 'Calibração Concluída!',
            description = 'Configuração completa de slots e empilhadeira gravada com sucesso!',
            type = 'success',
            duration = 6000
        })
        OffsetEditor.StopCalibration(ActiveCreatedTrailer, ActiveCalibCam)
        SendNUIMessage({
            action = 'admin_restore',
            savedSlot = CalibParams.slotIndex,
            isForklift = CalibParams.isForklift,
            trailerModel = CalibParams.trailerModel
        })
        SetNuiFocus(true, true)
    end
end

function OffsetEditor.CancelCalibration()
    OffsetEditor.StopCalibration(ActiveCreatedTrailer, ActiveCalibCam)
    SendNUIMessage({ action = 'admin_restore' })
    SetNuiFocus(true, true)
    lib.notify({ title = 'Calibração', description = 'Edição finalizada.', type = 'info' })
end

-- ============================================================
-- FERRAMENTA VISUAL IN-GAME DE OFFSETS (FREECAM & 3D GIZMO)
-- ============================================================

function OffsetEditor.StartCalibration(trailerModel, slotIndex, isForklift, propModel, label, customName, propCount, folderName)
    if IsCalibrating then return end
    IsCalibrating = true
    IsGizmoCursorActive = false
    CurrentGizmoMode = 'translate'

    -- Limpa lista e entidades de sessões anteriores
    for _, gEnt in ipairs(SavedGhosts) do
        if gEnt and DoesEntityExist(gEnt) then
            DeleteEntity(gEnt)
        end
    end
    SavedGhosts = {}
    SavedSlotOffsets = {}
    LastSavedSlotIndex = nil

    trailerModel = (trailerModel or 'trailers2'):lower()
    slotIndex = tonumber(slotIndex) or 1
    isForklift = isForklift or false
    propModel = propModel or (isForklift and 'forklift' or 'hei_prop_carrier_cargo_04b')

    CalibParams = {
        trailerModel = trailerModel,
        slotIndex = slotIndex,
        isForklift = isForklift,
        propModel = propModel,
        label = label or (isForklift and 'Empilhadeira Traseira' or ('Slot ' .. tostring(slotIndex))),
        customName = customName,
        propCount = tonumber(propCount) or 1,
        folderName = folderName or 'Geral'
    }

    -- Minimiza o menu administrativo principal
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'admin_minimize' })

    local ped = cache.ped or PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local pHeading = GetEntityHeading(ped)

    -- Protege o ped durante a calibração
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    -- Verifica se já há um trailer próximo ou spawna um para visualização
    local tHash = joaat(trailerModel)
    lib.requestModel(tHash, 5000)

    -- Carrega slots já conhecidos do trailer para memória de cópia rápida
    if Config.TrailerSlots and Config.TrailerSlots[tHash] and Config.TrailerSlots[tHash].pallets then
        for sIdx, sVec in pairs(Config.TrailerSlots[tHash].pallets) do
            if type(sVec) == 'vector3' then
                SavedSlotOffsets[sIdx] = { x = sVec.x, y = sVec.y, z = sVec.z, heading = 0.0 }
            elseif type(sVec) == 'table' then
                SavedSlotOffsets[sIdx] = { x = sVec.x or 0.0, y = sVec.y or 0.0, z = sVec.z or 0.0, heading = sVec.heading or 0.0 }
            end
        end
    end

    local trailer = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 20.0, tHash, 70)
    local createdTrailer = false
    if not trailer or trailer == 0 then
        local spawnPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 7.5, 0.2)
        trailer = CreateVehicle(tHash, spawnPos.x, spawnPos.y, spawnPos.z, pHeading, false, false)
        SetEntityAsMissionEntity(trailer, true, true)
        SetVehicleOnGroundProperly(trailer)
        FreezeEntityPosition(trailer, true)
        createdTrailer = true
    end
    CalibTrailer = trailer
    ActiveCreatedTrailer = createdTrailer

    -- Carrega o offset inicial da tabela
    local curVec = nil
    if Config.TrailerSlots and Config.TrailerSlots[tHash] then
        if isForklift then
            curVec = Config.TrailerSlots[tHash].forklift
        elseif Config.TrailerSlots[tHash].pallets then
            curVec = Config.TrailerSlots[tHash].pallets[slotIndex]
        end
    end
    if not curVec then
        if isForklift then
            curVec = (ForkliftModule.GetForkliftSlotOffset and ForkliftModule.GetForkliftSlotOffset(trailer)) or vector3(0.0, -5.2, 0.35)
        else
            curVec = (ForkliftModule.GetSlotOffset and ForkliftModule.GetSlotOffset(trailer, slotIndex)) or vector3(0.0, 0.0, 0.35)
        end
    end

    CurrentOffsets = { x = curVec.x, y = curVec.y, z = curVec.z, heading = 0.0 }

    -- Cria o primeiro fantasma
    SpawnCalibGhost(trailer, isForklift, propModel, curVec, 0.0)

    -- Configuração e ativação da Câmera Livre (Scripted Camera)
    local tCoords = GetEntityCoords(trailer)
    local tHeadingRad = math.rad(GetEntityHeading(trailer))
    local camX = tCoords.x - math.sin(tHeadingRad) * 9.0
    local camY = tCoords.y - math.cos(tHeadingRad) * 9.0
    local camZ = tCoords.z + 4.2
    local camRot = vector3(-18.0, 0.0, GetEntityHeading(trailer))

    local calibCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, camZ, camRot.x, camRot.y, camRot.z, 55.0, true, 2)
    SetCamActive(calibCam, true)
    RenderScriptCams(true, false, 0, true, true)
    ActiveCalibCam = calibCam

    -- Inicializa o Gizmo 3D (Three.js + TransformControls) sobreposto na tela
    local gWorldCoords = GetEntityCoords(CalibGhost)
    local gWorldRot = GetEntityRotation(CalibGhost, 2)
    SendNUIMessage({
        action = 'initGizmo',
        data = {
            position = { x = gWorldCoords.x, y = gWorldCoords.y, z = gWorldCoords.z },
            rotation = { x = gWorldRot.x, y = gWorldRot.y, z = gWorldRot.z }
        }
    })
    SendNUIMessage({
        action = 'setGizmoTarget',
        data = { target = 'cargo', showToggle = (not isForklift) }
    })

    lib.notify({
        title = 'Gizmo 3D Ativo',
        description = 'WASD: Voo Livre.\nSegure [ALT] para liberar o mouse e arrastar o Gizmo.\n[ENTER] ou Botão: Confirmar Slot.',
        type = 'info',
        duration = 8000
    })

    -- LOOP PRINCIPAL DE CONTROLES, GIZMO E FREECAM
    CreateThread(function()
        while IsCalibrating do
            Wait(0)

            -- Desabilita ações normais do jogo (garante isolamento total)
            DisableAllControlActions(0)

            -- 1. SINCRONIZAÇÃO DA CÂMERA FIVEM COM O THREE.JS (FRAME A FRAME)
            local finalCamPos = GetFinalRenderedCamCoord()
            local finalCamRot = GetFinalRenderedCamRot(2)
            SendNUIMessage({
                action = 'setCameraPosition',
                data = {
                    position = { x = finalCamPos.x, y = finalCamPos.y, z = finalCamPos.z },
                    rotation = { x = finalCamRot.x, y = finalCamRot.y, z = finalCamRot.z }
                }
            })

            -- 2. ALTERNÂNCIA DE CURSOR VS MOUSE LOOK VIA TECLA ALT (HOLD)
            local isAltHeld = IsDisabledControlPressed(0, 19) or IsControlPressed(0, 19)
            if isAltHeld then
                if not IsGizmoCursorActive then
                    IsGizmoCursorActive = true
                    SetNuiFocus(true, true)
                    SetNuiFocusKeepInput(true)
                    SendNUIMessage({ action = 'setGizmoCursor', data = { active = true } })
                end
            else
                if IsGizmoCursorActive then
                    IsGizmoCursorActive = false
                    SetNuiFocus(false, false)
                    SetNuiFocusKeepInput(false)
                    SendNUIMessage({ action = 'setGizmoCursor', data = { active = false } })
                end

                -- Rotação de câmera suave pelo mouse (somente quando ALT não estiver segurado)
                local mouseX = GetDisabledControlNormal(0, 1) -- Look LR
                local mouseY = GetDisabledControlNormal(0, 2) -- Look UD
                if mouseX ~= 0.0 or mouseY ~= 0.0 then
                    local camSens = 4.0
                    camRot = vector3(
                        math.max(-85.0, math.min(85.0, camRot.x - mouseY * camSens)),
                        0.0,
                        (camRot.z - mouseX * camSens) % 360.0
                    )
                    SetCamRot(calibCam, camRot.x, camRot.y, camRot.z, 2)
                end
            end

            -- 3. VOO LIVRE DA CÂMERA (WASD / Space / LCtrl / Shift) — SEMPRE ATIVO
            local radX = math.rad(camRot.x)
            local radZ = math.rad(camRot.z)
            local cosX = math.cos(radX)
            local sinX = math.sin(radX)
            local cosZ = math.cos(radZ)
            local sinZ = math.sin(radZ)

            local fwd = vector3(-sinZ * cosX, cosZ * cosX, sinX)
            local rgt = vector3(cosZ, sinZ, 0.0)
            local up  = vector3(0.0, 0.0, 1.0)

            local camSpeed = 0.16
            if IsDisabledControlPressed(0, 21) then camSpeed = 0.45 end -- LShift (Turbo)

            local camPos = GetCamCoord(calibCam)
            local camMoved = false

            if IsDisabledControlPressed(0, 32) then camPos = camPos + fwd * camSpeed; camMoved = true end -- W
            if IsDisabledControlPressed(0, 33) then camPos = camPos - fwd * camSpeed; camMoved = true end -- S
            if IsDisabledControlPressed(0, 34) then camPos = camPos - rgt * camSpeed; camMoved = true end -- A
            if IsDisabledControlPressed(0, 35) then camPos = camPos + rgt * camSpeed; camMoved = true end -- D
            if IsDisabledControlPressed(0, 22) then camPos = camPos + up  * camSpeed; camMoved = true end -- Space (Subir)
            if IsDisabledControlPressed(0, 36) then camPos = camPos - up  * camSpeed; camMoved = true end -- LCtrl (Descer)

            if camMoved then
                SetCamCoord(calibCam, camPos.x, camPos.y, camPos.z)
            end

            -- 4. ALTERNÂNCIA DE MODO DO GIZMO COM AS TECLAS T E R
            if IsDisabledControlJustPressed(0, 245) or IsControlJustPressed(0, 245) then -- T
                CurrentGizmoMode = 'translate'
                SendNUIMessage({ action = 'setGizmoMode', data = { mode = 'translate' } })
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Translação (Setas)', type = 'info', duration = 1200 })
            elseif IsDisabledControlJustPressed(0, 45) or IsControlJustPressed(0, 45) then -- R
                CurrentGizmoMode = 'rotate'
                SendNUIMessage({ action = 'setGizmoMode', data = { mode = 'rotate' } })
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Rotação (Anéis)', type = 'info', duration = 1200 })
            end

            -- 5. AJUSTE FINO AUXILIAR VIA TECLADO (SETAS + Q/E)
            local moveStep = 0.015
            local rotStep = 1.0
            if IsDisabledControlPressed(0, 21) then
                moveStep = 0.06
                rotStep = 3.5
            end

            local kbMoved = false
            if IsDisabledControlPressed(0, 172) or IsDisabledControlPressed(0, 27) then CurrentOffsets.y = CurrentOffsets.y + moveStep; kbMoved = true end
            if IsDisabledControlPressed(0, 173) then CurrentOffsets.y = CurrentOffsets.y - moveStep; kbMoved = true end
            if IsDisabledControlPressed(0, 174) then CurrentOffsets.x = CurrentOffsets.x - moveStep; kbMoved = true end
            if IsDisabledControlPressed(0, 175) then CurrentOffsets.x = CurrentOffsets.x + moveStep; kbMoved = true end
            if IsDisabledControlPressed(0, 44) then CurrentOffsets.z = CurrentOffsets.z - moveStep; kbMoved = true end -- Q
            if IsDisabledControlPressed(0, 38) then CurrentOffsets.z = CurrentOffsets.z + moveStep; kbMoved = true end -- E

            if kbMoved and CalibGhost and DoesEntityExist(CalibGhost) and CalibTrailer and DoesEntityExist(CalibTrailer) then
                local worldPos = GetOffsetFromEntityInWorldCoords(CalibTrailer, CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z)
                SetEntityCoordsNoOffset(CalibGhost, worldPos.x, worldPos.y, worldPos.z, false, false, false)
                local tHeading = GetEntityHeading(CalibTrailer)
                SetEntityHeading(CalibGhost, (tHeading + CurrentOffsets.heading) % 360.0)

                -- Notifica o Three.js para sincronizar a posição do Gizmo
                SendNUIMessage({
                    action = 'setGizmoEntity',
                    data = {
                        position = { x = worldPos.x, y = worldPos.y, z = worldPos.z },
                        rotation = { x = 0, y = 0, z = (tHeading + CurrentOffsets.heading) % 360.0 }
                    }
                })
            end

            -- 6. HUD INFORMATIVO NA TELA
            local targetLabel = CalibParams.isForklift and '~y~Empilhadeira (Slot Final)~s~' or ('~y~Palete Slot %d~s~'):format(CalibParams.slotIndex)
            local modeStatus = IsGizmoCursorActive and '~g~[CURSOR GIZMO ATIVO]~s~' or '~b~[CÂMERA LIVRE]~s~'
            local gizmoModeLabel = CurrentGizmoMode == 'translate' and '~w~Translação (Setas)~s~' or '~w~Rotação (Anéis)~s~'

            local hudText = ('~g~[GIZMO 3D vp_staff_studio]~s~ %s\n' ..
                'Trailer: ~w~%s~s~  |  Alvo: %s  |  Gizmo: %s\n' ..
                'Offset: ~b~X: %.3f  |  Y: %.3f  |  Z: %.3f~s~  |  Rot: ~b~%.1f°~s~\n' ..
                '~w~[WASD] Voo Livre  |  [Mouse] Girar Câmera  |  [Shift] Turbo\n' ..
                '~y~[SEGURE ALT]~w~ Ativa Cursor para Arrastar o Gizmo\n' ..
                '~y~[C ou Botão]~w~ Copiar Altura (Z) e Rotação do Anterior\n' ..
                '[T] Setas Translação  |  [R] Anéis Rotação\n' ..
                '~g~[ENTER ou Botão] Salvar & Próximo Slot~s~  |  ~r~[ESC] Finalizar~s~'):format(
                modeStatus,
                CalibParams.trailerModel, targetLabel, gizmoModeLabel,
                CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z, CurrentOffsets.heading
            )

            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.35, 0.35)
            SetTextColour(255, 255, 255, 235)
            SetTextDropshadow(1, 0, 0, 0, 200)
            SetTextEdge(1, 0, 0, 0, 250)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(hudText)
            DrawText(0.015, 0.65)

            -- 7. COPIAR ALTURA E ROTAÇÃO DO SLOT ANTERIOR VIA TECLA [C]
            if IsDisabledControlJustPressed(0, 26) or IsControlJustPressed(0, 26) then
                OffsetEditor.CopyPreviousSlot()
            end

            -- 8. SALVAMENTO E FLUXO CONTÍNUO (SEAMLESS SEQUENCING) VIA TECLADO ENTER
            local isKeyboardEnter = (
                IsDisabledControlJustPressed(0, 191) or IsControlJustPressed(0, 191) or
                IsDisabledControlJustPressed(0, 201) or IsControlJustPressed(0, 201) or
                IsDisabledControlJustPressed(0, 18)  or IsControlJustPressed(0, 18)
            )
            and not IsDisabledControlPressed(0, 24)
            and not IsDisabledControlJustPressed(0, 24)

            if isKeyboardEnter then
                OffsetEditor.ConfirmCurrentSlot()
            end

            -- 9. CANCELAMENTO OU FINALIZAÇÃO ANTECIPADA COM BACKSPACE / ESC
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
                OffsetEditor.CancelCalibration()
                break
            end
        end
    end)
end

function OffsetEditor.StopCalibration(deleteTrailer, cam)
    IsCalibrating = false
    IsGizmoCursorActive = false

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hideGizmo' })

    if cam and DoesCamExist(cam) then
        DestroyCam(cam, false)
    end
    RenderScriptCams(false, true, 500, true, true)

    local ped = cache.ped or PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)

    if CalibGhost and DoesEntityExist(CalibGhost) then
        DeleteEntity(CalibGhost)
        CalibGhost = nil
    end
    if CalibStrapGhost and DoesEntityExist(CalibStrapGhost) then
        DeleteEntity(CalibStrapGhost)
        CalibStrapGhost = nil
    end
    CalibTarget = 'cargo'
    for _, gEnt in ipairs(SavedGhosts) do
        if gEnt and DoesEntityExist(gEnt) then
            DeleteEntity(gEnt)
        end
    end
    SavedGhosts = {}
    if deleteTrailer and CalibTrailer and DoesEntityExist(CalibTrailer) then
        DeleteEntity(CalibTrailer)
        CalibTrailer = nil
    end
end

-- ============================================================
-- FERRAMENTA DE CAPTURA DE COORDENADAS DINÂMICAS
-- ============================================================

function OffsetEditor.CaptureCurrentCoords()
    local ped = cache.ped or PlayerPedId()
    local veh = cache.vehicle or GetVehiclePedIsIn(ped, false)
    local ent = (veh ~= 0) and veh or ped

    local coords = GetEntityCoords(ent)
    local heading = GetEntityHeading(ent)

    return {
        x = tonumber(string.format("%.2f", coords.x)),
        y = tonumber(string.format("%.2f", coords.y)),
        z = tonumber(string.format("%.2f", coords.z)),
        heading = tonumber(string.format("%.2f", heading)),
        w = tonumber(string.format("%.2f", heading))
    }
end

-- ============================================================
-- SINCRONIZAÇÃO EM TEMPO REAL NO CLIENTE (HOT-RELOAD)
-- ============================================================

RegisterNetEvent('aurp_trucker:client:adminSyncOffsets', function(trailerModel, slotIndex, isForklift, offsetVec, heading, updatedOffsets)
    trailerModel = trailerModel:lower()
    local hash = joaat(trailerModel)
    local u = hash & 0xFFFFFFFF
    local s = (u >= 0x80000000) and (u - 0x100000000) or u

    local keys = { trailerModel, hash, u, s, tostring(hash), tostring(u), tostring(s) }
    local slotEntry = {
        label = (type(offsetVec) == 'table' and offsetVec.label) or nil,
        prop_model = (type(offsetVec) == 'table' and offsetVec.prop_model) or nil,
        x = tonumber(offsetVec.x) or 0.0,
        y = tonumber(offsetVec.y) or 0.0,
        z = tonumber(offsetVec.z) or 0.0,
        heading = tonumber(heading) or (type(offsetVec) == 'table' and offsetVec.heading) or 0.0,
        straps = (type(offsetVec) == 'table' and offsetVec.straps) or nil
    }

    for _, k in ipairs(keys) do
        if not Config.TrailerSlots[k] then
            Config.TrailerSlots[k] = { pallets = {}, forklift = nil }
        end
        if isForklift then
            Config.TrailerSlots[k].forklift = slotEntry
        else
            Config.TrailerSlots[k].pallets[slotIndex] = slotEntry
            Config.TrailerSlots[k].pallets[tonumber(slotIndex)] = slotEntry
            Config.TrailerSlots[k].pallets[tostring(slotIndex)] = slotEntry
        end
    end

    -- Sincronização em tempo real com a missão ativa (_G.ActiveJob)
    if _G.ActiveJob and _G.ActiveJob.trailerOffsets then
        local jobTrailer = _G.ActiveJob.trailerModel and tostring(_G.ActiveJob.trailerModel):lower()
        if not jobTrailer or jobTrailer == trailerModel or jobTrailer == '' or joaat(jobTrailer) == hash then
            if not _G.ActiveJob.trailerOffsets._specific then
                _G.ActiveJob.trailerOffsets._specific = { pallets = {}, forklift = nil }
            end
            if isForklift then
                _G.ActiveJob.trailerOffsets._specific.forklift = slotEntry
            else
                _G.ActiveJob.trailerOffsets._specific.pallets[slotIndex] = slotEntry
                _G.ActiveJob.trailerOffsets._specific.pallets[tonumber(slotIndex)] = slotEntry
                _G.ActiveJob.trailerOffsets._specific.pallets[tostring(slotIndex)] = slotEntry
            end
            for _, k in ipairs(keys) do
                if not _G.ActiveJob.trailerOffsets[k] then
                    _G.ActiveJob.trailerOffsets[k] = { pallets = {}, forklift = nil }
                end
                if isForklift then
                    _G.ActiveJob.trailerOffsets[k].forklift = slotEntry
                else
                    _G.ActiveJob.trailerOffsets[k].pallets[slotIndex] = slotEntry
                    _G.ActiveJob.trailerOffsets[k].pallets[tonumber(slotIndex)] = slotEntry
                    _G.ActiveJob.trailerOffsets[k].pallets[tostring(slotIndex)] = slotEntry
                end
            end
        end
    end

    -- Recarrega instantaneamente o fantasma de alinhamento da empilhadeira com o novo offset
    if ForkliftModule and ForkliftModule.DeleteGhostProp then
        ForkliftModule.DeleteGhostProp()
    end

    -- Se o pacote completo do banco foi enviado, sincroniza e atualiza imediatamente a UI
    if updatedOffsets then
        SendNUIMessage({
            action = 'admin_update_offsets',
            offsets = updatedOffsets
        })
    end

    if Config.Debug then print(("^2[AUST_Trucker Client] Offset do reboque %s (%s) sincronizado em tempo real!^7"):format(
        trailerModel, isForklift and 'Empilhadeira' or ('Slot ' .. tostring(slotIndex))
    )) end
end)

RegisterNetEvent('aurp_trucker:client:adminSyncVehiclePropOffsets', function(rawMap, dualMap)
    if not Config.VehiclePropOffsets then Config.VehiclePropOffsets = {} end
    if dualMap then
        Config.VehiclePropOffsets = dualMap
    end

    if rawMap then
        SendNUIMessage({
            action = 'admin_update_vehicle_prop_offsets',
            offsets = rawMap
        })
    end

    if Config.Debug then
        print("^2[AUST_Trucker Client] Offsets do PropEditor (veículo <-> prop) sincronizados em tempo real sem restart!^7")
    end
end)

RegisterNetEvent('aurp_trucker:client:adminSyncProps', function(propsList)
    SendNUIMessage({
        action = 'admin_update_props',
        props = propsList
    })
    if Config.Debug then print(("^2[AUST_Trucker Client] Props homologados sincronizados em tempo real! (%d props)^7"):format(type(propsList) == 'table' and #propsList or 0)) end
end)

local isSyncingAdminNPCs = false

RegisterNetEvent('aurp_trucker:client:adminSyncNPCs', function(npcList)
    if isSyncingAdminNPCs then
        Wait(100)
    end
    isSyncingAdminNPCs = true
    _G.HasDynamicAdminNPCs = true

    -- 1. Destrói o despachante estático legado se existir no mapa
    if _G.CleanupStaticDispatcherPed then
        pcall(_G.CleanupStaticDispatcherPed)
    end

    -- 2. Remove com segurança todos os NPCs dinâmicos e blips previamente rastreados
    for _, data in pairs(DynamicAdminPeds or {}) do
        if data.ped and DoesEntityExist(data.ped) then
            pcall(function() exports.ox_target:removeLocalEntity(data.ped) end)
            DeleteEntity(data.ped)
        end
        if data.blip and DoesBlipExist(data.blip) then
            RemoveBlip(data.blip)
        end
    end
    DynamicAdminPeds = {}

    -- 3. Criação sequencial e síncrona sem disparar múltiplas threads concorrentes
    CreateThread(function()
        for id, npc in pairs(npcList or {}) do
            if npc and (npc.is_active ~= 0 and npc.is_active ~= false) and npc.coords then
                local coords = type(npc.coords) == 'string' and json.decode(npc.coords) or npc.coords
                if coords and coords.x and coords.y and coords.z then
                    local cx = tonumber(coords.x)
                    local cy = tonumber(coords.y)
                    local cz = tonumber(coords.z)
                    local ch = tonumber(npc.heading or coords.heading or coords.w or coords.h or 0.0)

                    if cx and cy and cz and (cx ~= 0.0 or cy ~= 0.0) then
                        -- Limpeza preventiva de peds órfãos/clipping no raio de 1.8 metros
                        local nearbyPeds = lib.getNearbyPeds(vector3(cx, cy, cz), 1.8)
                        for _, np in ipairs(nearbyPeds or {}) do
                            if np.ped and DoesEntityExist(np.ped) and not IsPedAPlayer(np.ped) then
                                pcall(function() exports.ox_target:removeLocalEntity(np.ped) end)
                                DeleteEntity(np.ped)
                            end
                        end

                        local modelHash = joaat(npc.model or npc.npc_model or 's_m_m_dockwork_01')
                        lib.requestModel(modelHash, 4000)

                        local ped = CreatePed(4, modelHash, cx, cy, cz - 1.0, ch, false, false)
                        if ped and DoesEntityExist(ped) then
                            SetEntityAsMissionEntity(ped, true, true)
                            SetBlockingOfNonTemporaryEvents(ped, true)
                            SetPedFleeAttributes(ped, 0, false)
                            SetPedCombatAttributes(ped, 17, true)
                            SetPedCanRagdoll(ped, false)
                            FreezeEntityPosition(ped, true)
                            SetEntityInvincible(ped, true)

                            exports.ox_target:addLocalEntity(ped, {
                                {
                                    name = 'admin_dispatcher_' .. tostring(id),
                                    icon = 'fas fa-truck-ramp-box',
                                    label = 'Abrir Central de Fretes (' .. (npc.name or npc.npc_name or 'Logística') .. ')',
                                    distance = 2.5,
                                    onSelect = function()
                                        TriggerEvent('truck_logistics:openJobBoard', tostring(id))
                                    end
                                }
                            })

                            local blip = AddBlipForCoord(cx, cy, cz)
                            SetBlipSprite(blip, npc.blip_sprite or 477)
                            SetBlipColour(blip, npc.blip_color or 2)
                            SetBlipScale(blip, 0.85)
                            SetBlipAsShortRange(blip, true)
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString(npc.name or npc.npc_name or 'Central Logística')
                            EndTextCommandSetBlipName(blip)

                            DynamicAdminPeds[tostring(id)] = { ped = ped, blip = blip }
                        end
                    end
                end
            end
        end

        isSyncingAdminNPCs = false

        -- Sincroniza a interface administrativa NUI em tempo real caso esteja aberta
        SendNUIMessage({
            action = 'adminSyncNPCs',
            npcs = npcList
        })
    end)
end)

-- ============================================================
-- GIZMO 3D: CALIBRAÇÃO VISUAL DE PONTOS DE SPAWN
-- ============================================================


function OffsetEditor.StartSpawnCalibration(data)
    if IsCalibrating then return end
    if IsCalibratingSpawn or SpawnGhostEnt or SpawnCam then
        OffsetEditor.StopSpawnCalibration(SpawnCam, false)
        Wait(50)
    end
    IsCalibratingSpawn = true

    data = data or {}
    ActiveCalibSpawnData = data
    ActiveDuplicationData = (data.is_duplication and data.duplicate_data) or nil

    -- Inicializa Posicionamento Sequencial em Lote se quantity > 1
    local qty = tonumber(data.quantity) or 1
    if qty > 1 then
        BatchSpawnState.active = true
        BatchSpawnState.total = math.floor(qty)
        BatchSpawnState.current = 1
        BatchSpawnState.baseData = data
        BatchSpawnState.confirmedItems = {}
        BatchSpawnState.previewEntities = {}
        SendNUIMessage({
            action = 'updateGizmoBatch',
            data = { current = 1, total = BatchSpawnState.total }
        })
    else
        BatchSpawnState.active = false
        BatchSpawnState.total = 1
        BatchSpawnState.current = 1
        BatchSpawnState.baseData = nil
        BatchSpawnState.confirmedItems = {}
        BatchSpawnState.previewEntities = {}
        SendNUIMessage({ action = 'updateGizmoBatch', data = { total = 0 } })
    end

    local spawnType = tostring(data.spawn_type or 'truck'):lower()
    local isNpc = (data.is_npc or spawnType == 'npc' or spawnType == 'ped')
    local isDelivery = (data.is_delivery == true or spawnType == 'delivery_bay' or spawnType == 'delivery')
    local isMarker = not isNpc and (isDelivery or spawnType == 'load_bay' or spawnType == 'delivery_bay' or spawnType == 'marker' or spawnType == 'drawmarker' or spawnType == 'bay')
    local modelStr = data.model
    local isVeh = not isMarker and not isNpc

    if not modelStr or modelStr == '' then
        if isNpc then modelStr = 's_m_m_dockwork_01'
        elseif spawnType == 'truck' then modelStr = 'hauler'
        elseif spawnType == 'trailer' then modelStr = 'trailers2'
        elseif spawnType == 'forklift' then modelStr = 'forklift'
        elseif spawnType == 'handler' then modelStr = 'handler'
        elseif spawnType == 'pallet' or spawnType == 'prop' then modelStr = 'prop_wood_pallet_01'; isVeh = false
        else modelStr = 'hei_prop_carrier_cargo_04b'; isVeh = false end
    else
        if isNpc or spawnType == 'pallet' or spawnType == 'prop' or isMarker then isVeh = false end
    end

    local ped = cache.ped or PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local pHeading = GetEntityHeading(ped)
    local forward = GetEntityForwardVector(ped)
    -- Posição padrão: imediatamente à frente do administrador (2.5m de distância)
    local spawnPos = pCoords + forward * 2.5
    local hasCustomCoords = false

    -- Só aceita coordenadas pré-definidas se NÃO for um novo cadastro e se os dados forem válidos
    local isNewItem = (data.is_new == true) or (not data.id and not data.npc_id and not data.route_id and not data.duplicate_data and not data.is_duplication)
    if not isNewItem and data.coords and data.coords.x and data.coords.y and data.coords.z then
        local cx = tonumber(data.coords.x)
        local cy = tonumber(data.coords.y)
        local cz = tonumber(data.coords.z)
        if cx and cy and cz and (cx ~= 0.0 or cy ~= 0.0) then
            spawnPos = vector3(cx + 0.0, cy + 0.0, cz + 0.0)
            pHeading = tonumber(data.coords.heading or data.coords.w or data.coords.h or pHeading)
            hasCustomCoords = true
        end
    end

    -- Minimiza o menu administrativo principal
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'admin_minimize' })

    local hash = joaat(modelStr)
    lib.requestModel(hash, 5000)

    local ghost = nil
    if isNpc then
        ghost = CreatePed(4, hash, spawnPos.x, spawnPos.y, spawnPos.z, pHeading, false, false)
        if ghost and DoesEntityExist(ghost) then
            SetBlockingOfNonTemporaryEvents(ghost, true)
            SetPedCanRagdoll(ghost, false)
        end
    elseif isVeh then
        ghost = CreateVehicle(hash, spawnPos.x, spawnPos.y, spawnPos.z, pHeading, false, false)
        if ghost and DoesEntityExist(ghost) then SetVehicleDoorsLocked(ghost, 2) end
    else
        ghost = CreateObject(hash, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
    end

    if not ghost or not DoesEntityExist(ghost) then
        IsCalibratingSpawn = false
        ActiveDuplicationData = nil
        lib.notify({ title = 'Erro', description = 'Falha ao instanciar holograma para calibração.', type = 'error' })
        SendNUIMessage({ action = 'admin_restore' })
        SetNuiFocus(true, true)
        return
    end

    SetEntityAsMissionEntity(ghost, true, true)
    SetEntityLodDist(ghost, 0xFFFF)
    if isMarker then
        SetEntityVisible(ghost, false, false)
        SetEntityAlpha(ghost, 0, false)
    else
        SetEntityAlpha(ghost, 190, false)
    end
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)
    SetEntityHeading(ghost, pHeading)

    SpawnGhostEnt = ghost
    CurrentSpawnCoords = {
        x = tonumber(string.format("%.2f", spawnPos.x)),
        y = tonumber(string.format("%.2f", spawnPos.y)),
        z = tonumber(string.format("%.2f", spawnPos.z)),
        heading = tonumber(string.format("%.1f", pHeading))
    }

    -- Câmera orbital focada na posição da entidade
    local camPos = nil
    if hasCustomCoords then
        local radH = math.rad(pHeading)
        camPos = spawnPos + vector3(math.sin(radH) * -6.0, math.cos(radH) * -6.0, 3.0)
    else
        -- Para novas criações locais aos pés do admin: câmera suave posicionada atrás do admin olhando para o holograma
        camPos = spawnPos + vector3(-forward.x * 4.5, -forward.y * 4.5, 2.0)
    end
    SpawnCam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", camPos.x, camPos.y, camPos.z, -15.0, 0.0, pHeading, 60.0, true, 2)
    SetCamActive(SpawnCam, true)
    RenderScriptCams(true, true, 500, true, true)

    -- Inicia o Gizmo Three.js sincronizado
    SendNUIMessage({
        action = 'initGizmo',
        data = {
            position = { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z },
            rotation = { x = 0.0, y = 0.0, z = pHeading },
            mode = 'translate',
            context = 'spawn'
        }
    })

    lib.notify({
        title = 'Gizmo 3D (Calibração de Spawn)',
        description = 'Segure [ALT] para liberar o mouse e ajustar.\n[T]: Mover | [R]: Girar\n[ENTER]: Confirmar Coords | [ESC]: Cancelar',
        type = 'info',
        duration = 8000
    })

    local camRot = vector3(-15.0, 0.0, pHeading)
    local isAltCursor = false

    CreateThread(function()
        while IsCalibratingSpawn do
            Wait(0)
            DisableAllControlActions(0)

            local finalCamPos = GetFinalRenderedCamCoord()
            local finalCamRot = GetFinalRenderedCamRot(2)
            SendNUIMessage({
                action = 'setCameraPosition',
                data = {
                    position = { x = finalCamPos.x, y = finalCamPos.y, z = finalCamPos.z },
                    rotation = { x = finalCamRot.x, y = finalCamRot.y, z = finalCamRot.z }
                }
            })

            local isAltHeld = IsDisabledControlPressed(0, 19) or IsControlPressed(0, 19)
            if isAltHeld then
                if not isAltCursor then
                    isAltCursor = true
                    SetNuiFocus(true, true)
                    SetNuiFocusKeepInput(true)
                    SendNUIMessage({ action = 'setGizmoCursor', data = { active = true } })
                end
            else
                if isAltCursor then
                    isAltCursor = false
                    SetNuiFocus(false, false)
                    SetNuiFocusKeepInput(false)
                    SendNUIMessage({ action = 'setGizmoCursor', data = { active = false } })
                end

                local mouseX = GetDisabledControlNormal(0, 1)
                local mouseY = GetDisabledControlNormal(0, 2)
                if mouseX ~= 0.0 or mouseY ~= 0.0 then
                    camRot = vector3(
                        math.max(-85.0, math.min(85.0, camRot.x - mouseY * 4.0)),
                        0.0,
                        (camRot.z - mouseX * 4.0) % 360.0
                    )
                    SetCamRot(SpawnCam, camRot.x, camRot.y, camRot.z, 2)
                end
            end

            -- Movimentação WASD
            local radX, radZ = math.rad(camRot.x), math.rad(camRot.z)
            local cosX, sinX = math.cos(radX), math.sin(radX)
            local cosZ, sinZ = math.cos(radZ), math.sin(radZ)
            local fwd = vector3(-sinZ * cosX, cosZ * cosX, sinX)
            local rgt = vector3(cosZ, sinZ, 0.0)
            local up  = vector3(0.0, 0.0, 1.0)
            local camSpeed = IsDisabledControlPressed(0, 21) and 0.45 or 0.16
            local cPos = GetCamCoord(SpawnCam)
            local moved = false

            if IsDisabledControlPressed(0, 32) then cPos = cPos + fwd * camSpeed; moved = true end
            if IsDisabledControlPressed(0, 33) then cPos = cPos - fwd * camSpeed; moved = true end
            if IsDisabledControlPressed(0, 34) then cPos = cPos - rgt * camSpeed; moved = true end
            if IsDisabledControlPressed(0, 35) then cPos = cPos + rgt * camSpeed; moved = true end
            if IsDisabledControlPressed(0, 22) then cPos = cPos + up  * camSpeed; moved = true end
            if IsDisabledControlPressed(0, 36) then cPos = cPos - up  * camSpeed; moved = true end
            if moved then SetCamCoord(SpawnCam, cPos.x, cPos.y, cPos.z) end

            -- Alternância Modo Gizmo (T / R)
            if IsDisabledControlJustPressed(0, 245) or IsControlJustPressed(0, 245) then
                SendNUIMessage({ action = 'setGizmoMode', data = { mode = 'translate' } })
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Translação (Setas)', type = 'info', duration = 1000 })
            elseif IsDisabledControlJustPressed(0, 45) or IsControlJustPressed(0, 45) then
                SendNUIMessage({ action = 'setGizmoMode', data = { mode = 'rotate' } })
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Rotação (Anéis)', type = 'info', duration = 1000 })
            end

            -- Renderização Visual da Baia e Ponto de Entrega (Sincronizado com o Script)
            if isMarker then
                local markerZ = CurrentSpawnCoords.z - 0.45
                local foundGround, groundZ = GetGroundZFor_3dCoord(CurrentSpawnCoords.x, CurrentSpawnCoords.y, CurrentSpawnCoords.z + 2.0, false)
                if foundGround and groundZ > 0.0 then
                    markerZ = groundZ + 0.05
                end

                if isDelivery then
                    -- Vaga Zebrada 30 Oficial da Entrega (Dimensões oficiais da carreta de 10m x 3m do script de entrega)
                    DrawMarker(
                        30,
                        CurrentSpawnCoords.x, CurrentSpawnCoords.y, markerZ,
                        0.0, 0.0, 0.0,
                        90.0, CurrentSpawnCoords.heading or 0.0, 0.0,
                        3.0, 1.0, 10.0,
                        0, 255, 136, 85,
                        0, 0, 0, 0
                    )
                else
                    -- Vaga Zebrada DrawMarker 30 (Faixas no solo padrão)
                    DrawMarker(
                        30,
                        CurrentSpawnCoords.x, CurrentSpawnCoords.y, markerZ,
                        0.0, 0.0, 0.0,
                        90.0, CurrentSpawnCoords.heading or 0.0, 0.0,
                        3.0, 1.0, 10.0,
                        255, 60, 60, 75,
                        0, 0, 0, 0
                    )
                end
            end

            -- HUD
            local titleTag = isDelivery and "~g~[GIZMO 3D - PONTO DE ENTREGA]~s~\n~c~(Vaga Zebrada & Marcador Oficial de Entrega)~s~"
                or (isMarker and "~g~[GIZMO 3D - BAIA DE CARGA]~s~\n~c~(Marcador Visual DrawMarker)~s~")
                or "~g~[GIZMO DE SPAWN 3D]~s~"
            local hudText = string.format(
                "%s\n" ..
                "X: ~y~%.2f~s~ | Y: ~y~%.2f~s~ | Z: ~y~%.2f~s~\n" ..
                "Heading: ~y~%.1f°~s~\n\n" ..
                "[ALT]: Liberar Cursor Gizmo\n" ..
                "[ENTER]: Confirmar Coordenadas\n" ..
                "[ESC]: Cancelar",
                titleTag,
                CurrentSpawnCoords.x, CurrentSpawnCoords.y, CurrentSpawnCoords.z, CurrentSpawnCoords.heading
            )
            SetTextFont(0)
            SetTextScale(0.35, 0.35)
            SetTextColour(255, 255, 255, 235)
            SetTextDropshadow(1, 0, 0, 0, 200)
            SetTextEdge(1, 0, 0, 0, 250)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(hudText)
            DrawText(0.015, 0.65)

            -- Confirmar com ENTER (Frontend R-Down 191, Accept 201, Enter 18)
            local isEnter = (
                IsDisabledControlJustPressed(0, 191) or IsControlJustPressed(0, 191) or
                IsDisabledControlJustPressed(0, 201) or IsControlJustPressed(0, 201) or
                IsDisabledControlJustPressed(0, 18)  or IsControlJustPressed(0, 18)
            )
            and not IsDisabledControlPressed(0, 24)
            and not IsDisabledControlJustPressed(0, 24)

            if isEnter then
                OffsetEditor.StopSpawnCalibration(SpawnCam, true)
                if not IsCalibratingSpawn then
                    break
                else
                    Wait(250)
                end
            end

            -- Cancelar com ESC / Backspace
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
                OffsetEditor.StopSpawnCalibration(SpawnCam, false)
                if not IsCalibratingSpawn then
                    break
                end
            end
        end
    end)
end

function OffsetEditor.SpawnNextBatchItem()
    if not BatchSpawnState.active or not IsCalibratingSpawn then return end

    local bData = BatchSpawnState.baseData or {}
    local spawnType = tostring(bData.spawn_type or 'truck'):lower()
    local isMarker = (spawnType == 'load_bay' or spawnType == 'delivery_bay' or spawnType == 'marker' or spawnType == 'drawmarker' or spawnType == 'bay')
    local modelStr = bData.model
    local isVeh = not isMarker

    if not modelStr or modelStr == '' then
        if spawnType == 'truck' then modelStr = 'hauler'
        elseif spawnType == 'trailer' then modelStr = 'trailers2'
        elseif spawnType == 'forklift' then modelStr = 'forklift'
        elseif spawnType == 'handler' then modelStr = 'handler'
        elseif spawnType == 'pallet' or spawnType == 'prop' then modelStr = 'prop_wood_pallet_01'; isVeh = false
        else modelStr = 'hei_prop_carrier_cargo_04b'; isVeh = false end
    else
        if spawnType == 'pallet' or spawnType == 'prop' or isMarker then isVeh = false end
    end

    local hash = joaat(modelStr)
    lib.requestModel(hash, 5000)

    -- Desloca suavemente para a posição à frente para visualização clara
    local radH = math.rad(CurrentSpawnCoords.heading or 0.0)
    local nextX = CurrentSpawnCoords.x + math.cos(radH) * 2.0
    local nextY = CurrentSpawnCoords.y + math.sin(radH) * 2.0
    local nextZ = CurrentSpawnCoords.z

    local ghost = nil
    if isVeh then
        ghost = CreateVehicle(hash, nextX, nextY, nextZ, CurrentSpawnCoords.heading, false, false)
        if ghost and DoesEntityExist(ghost) then SetVehicleDoorsLocked(ghost, 2) end
    else
        ghost = CreateObject(hash, nextX, nextY, nextZ, false, false, false)
    end

    if ghost and DoesEntityExist(ghost) then
        SetEntityAsMissionEntity(ghost, true, true)
        SetEntityLodDist(ghost, 0xFFFF)
        if isMarker then
            SetEntityVisible(ghost, false, false)
            SetEntityAlpha(ghost, 0, false)
        else
            SetEntityAlpha(ghost, 190, false)
        end
        SetEntityCollision(ghost, false, false)
        SetEntityInvincible(ghost, true)
        FreezeEntityPosition(ghost, true)
        SetEntityHeading(ghost, CurrentSpawnCoords.heading)

        SpawnGhostEnt = ghost
        CurrentSpawnCoords = {
            x = tonumber(string.format("%.2f", nextX)),
            y = tonumber(string.format("%.2f", nextY)),
            z = tonumber(string.format("%.2f", nextZ)),
            heading = CurrentSpawnCoords.heading
        }

        SendNUIMessage({
            action = 'setGizmoEntity',
            data = {
                position = { x = nextX, y = nextY, z = nextZ },
                rotation = { x = 0.0, y = 0.0, z = CurrentSpawnCoords.heading }
            }
        })
    end
end

function OffsetEditor.StopSpawnCalibration(cam, confirmed)
    if confirmed then
        if BatchSpawnState.active then
            local idx = BatchSpawnState.current
            local bData = BatchSpawnState.baseData or {}
            local baseName = bData.base_name
            if not baseName or baseName == '' then baseName = 'Ponto de Spawn' end
            local baseId = bData.base_id
            local sId = (baseId and baseId ~= '' and (baseId .. '_' .. tostring(idx))) or ('spawn_' .. tostring(GetGameTimer()) .. '_' .. tostring(idx))

            local itemPayload = {
                id = sId,
                name = baseName,
                spawn_type = bData.spawn_type or 'truck',
                model = bData.model or '',
                folder_name = bData.folder_name or 'Geral',
                coords = {
                    x = CurrentSpawnCoords.x,
                    y = CurrentSpawnCoords.y,
                    z = CurrentSpawnCoords.z,
                    heading = CurrentSpawnCoords.heading,
                    w = CurrentSpawnCoords.heading
                }
            }
            table.insert(BatchSpawnState.confirmedItems, itemPayload)

            -- Preserva entidade atual como preview transparente no chão
            if SpawnGhostEnt and DoesEntityExist(SpawnGhostEnt) then
                SetEntityAlpha(SpawnGhostEnt, 120, false)
                table.insert(BatchSpawnState.previewEntities, SpawnGhostEnt)
                SpawnGhostEnt = nil
            end

            -- Verifica se ainda há mais itens no lote
            if BatchSpawnState.current < BatchSpawnState.total then
                local nextIdx = BatchSpawnState.current + 1
                BatchSpawnState.current = nextIdx

                PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)
                lib.notify({
                    title = 'Lote de Spawns',
                    description = ('Item %d de %d confirmado! Posicione o Item %d...'):format(idx, BatchSpawnState.total, nextIdx),
                    type = 'info',
                    duration = 3000
                })

                SendNUIMessage({
                    action = 'updateGizmoBatch',
                    data = { current = nextIdx, total = BatchSpawnState.total }
                })

                OffsetEditor.SpawnNextBatchItem()
                return -- Continua na mesma sessão do Gizmo sem fechar!
            else
                -- Lote completo finalizado com sucesso!
                TriggerServerEvent('aurp_trucker:server:adminSaveBatchSpawns', BatchSpawnState.confirmedItems)
                lib.notify({
                    title = 'Lote Concluído',
                    description = ('Todos os %d itens foram salvos na pasta "%s"!'):format(#BatchSpawnState.confirmedItems, bData.folder_name or 'Geral'),
                    type = 'success',
                    duration = 4500
                })
            end
        elseif ActiveDuplicationData then
            ActiveDuplicationData.coords = {
                x = CurrentSpawnCoords.x,
                y = CurrentSpawnCoords.y,
                z = CurrentSpawnCoords.z,
                heading = CurrentSpawnCoords.heading,
                w = CurrentSpawnCoords.heading
            }
            TriggerServerEvent('aurp_trucker:server:adminSaveSpawn', ActiveDuplicationData)
            lib.notify({
                title = 'Spawn Duplicado com Sucesso',
                description = ('Ponto "%s" salvo na pasta "%s"!'):format(ActiveDuplicationData.name or 'Clone', ActiveDuplicationData.folder_name or 'Geral'),
                type = 'success',
                duration = 4500
            })
            ActiveDuplicationData = nil
            ActiveCalibSpawnData = nil
            OffsetEditor.StopPreview()
        elseif (ActiveCalibSpawnData and (ActiveCalibSpawnData.is_npc or ActiveCalibSpawnData.spawn_type == 'npc' or ActiveCalibSpawnData.spawn_type == 'ped')) then
            local nData = ActiveCalibSpawnData
            local isNewNpc = (nData.is_new == true) or not nData.id or nData.id == '' or nData.id == 'null'
            local npcId = not isNewNpc and (nData.id or nData.npc_id) or nil
            local npcName = nData.name or nData.npc_name or 'Despachante Logístico'
            local npcModel = nData.model or nData.npc_model or 's_m_m_dockwork_01'

            local npcPayload = {
                id = npcId,
                npc_id = npcId,
                is_new = isNewNpc,
                name = npcName,
                npc_name = npcName,
                model = npcModel,
                npc_model = npcModel,
                coords = {
                    x = CurrentSpawnCoords.x,
                    y = CurrentSpawnCoords.y,
                    z = CurrentSpawnCoords.z,
                    heading = CurrentSpawnCoords.heading,
                    w = CurrentSpawnCoords.heading
                },
                heading = CurrentSpawnCoords.heading,
                blip_sprite = nData.blip_sprite or 477,
                blip_color = nData.blip_color or 2,
                is_active = (nData.is_active ~= false and nData.is_active ~= 0) and 1 or 0
            }

            -- GRAVAÇÃO AUTOMÁTICA NO BANCO E SINCRONIZAÇÃO EM TEMPO REAL
            TriggerServerEvent('aurp_trucker:server:adminSaveNPC', npcPayload)
            PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

            lib.notify({
                title = 'NPC Salvo no Banco!',
                description = ('Despachante "%s" posicionado e salvo com sucesso!'):format(npcName),
                type = 'success',
                duration = 4500
            })

            SendNUIMessage({
                action = 'admin_npc_coords_calibrated',
                coords = CurrentSpawnCoords,
                npc = npcPayload
            })
            ActiveCalibSpawnData = nil
            OffsetEditor.StopPreview()
        elseif (ActiveCalibSpawnData and (ActiveCalibSpawnData.is_delivery or ActiveCalibSpawnData.spawn_type == 'delivery_bay' or ActiveCalibSpawnData.spawn_type == 'delivery')) then
            local dData = ActiveCalibSpawnData
            local deliveryPayload = {
                route_id = dData.route_id or dData.id,
                coords = {
                    x = CurrentSpawnCoords.x,
                    y = CurrentSpawnCoords.y,
                    z = CurrentSpawnCoords.z,
                    heading = CurrentSpawnCoords.heading,
                    h = CurrentSpawnCoords.heading,
                    w = CurrentSpawnCoords.heading
                }
            }

            PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

            lib.notify({
                title = 'Ponto de Entrega Calibrado',
                description = ('Vaga e coordenadas calibradas com sucesso!\nX: %.2f | Y: %.2f | Z: %.2f | Ângulo: %.1f°'):format(
                    CurrentSpawnCoords.x, CurrentSpawnCoords.y, CurrentSpawnCoords.z, CurrentSpawnCoords.heading
                ),
                type = 'success',
                duration = 4500
            })

            SendNUIMessage({
                action = 'admin_delivery_coords_calibrated',
                coords = CurrentSpawnCoords,
                delivery = deliveryPayload
            })
            ActiveCalibSpawnData = nil
            OffsetEditor.StopPreview()
        else
            local bData = ActiveCalibSpawnData or {}
            local rawId = bData.id or bData.spawn_id or bData.base_id
            local sId = (rawId and rawId ~= '') and rawId or ('spawn_' .. tostring(GetGameTimer()) .. '_' .. math.random(100, 999))
            local sName = bData.name or bData.spawn_name or bData.base_name or sId
            local sType = bData.spawn_type or 'truck'
            local sModel = bData.model or ''
            local sFolder = bData.folder_name or bData.folderName or bData.folder or 'Geral'

            local singlePayload = {
                id = sId,
                spawn_id = sId,
                name = sName,
                spawn_name = sName,
                spawn_type = sType,
                model = sModel,
                folder_name = sFolder,
                folder = sFolder,
                folderName = sFolder,
                coords = {
                    x = CurrentSpawnCoords.x,
                    y = CurrentSpawnCoords.y,
                    z = CurrentSpawnCoords.z,
                    heading = CurrentSpawnCoords.heading,
                    w = CurrentSpawnCoords.heading
                },
                heading = CurrentSpawnCoords.heading
            }

            -- GRAVAÇÃO OBRIGATÓRIA AUTOMÁTICA NO BANCO E SINCRONIZAÇÃO EM TEMPO REAL
            TriggerServerEvent('aurp_trucker:server:adminSaveSpawn', singlePayload)
            PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

            lib.notify({
                title = 'Spawn Salvo no Banco!',
                description = ('Ponto "%s" salvo na pasta "%s" e sincronizado em tempo real!'):format(sName, sFolder),
                type = 'success',
                duration = 4500
            })

            SendNUIMessage({
                action = 'admin_spawn_coords_calibrated',
                coords = CurrentSpawnCoords,
                spawn = singlePayload
            })
            ActiveCalibSpawnData = nil
            OffsetEditor.StopPreview()
        end
    else
        if BatchSpawnState.active then
            if #BatchSpawnState.confirmedItems > 0 then
                TriggerServerEvent('aurp_trucker:server:adminSaveBatchSpawns', BatchSpawnState.confirmedItems)
                lib.notify({
                    title = 'Lote Salvo Parcialmente',
                    description = ('Posicionamento finalizado. %d item(ns) salvos na pasta "%s".'):format(#BatchSpawnState.confirmedItems, (BatchSpawnState.baseData and BatchSpawnState.baseData.folder_name) or 'Geral'),
                    type = 'warning',
                    duration = 4500
                })
            else
                lib.notify({ title = 'Calibração', description = 'Calibração de lote cancelada.', type = 'info' })
            end
        elseif ActiveDuplicationData then
            ActiveDuplicationData = nil
            OffsetEditor.StopPreview()
            lib.notify({ title = 'Calibração', description = 'Calibração cancelada.', type = 'info' })
        elseif ActiveCalibSpawnData and (ActiveCalibSpawnData.is_delivery or ActiveCalibSpawnData.spawn_type == 'delivery_bay' or ActiveCalibSpawnData.spawn_type == 'delivery') then
            ActiveCalibSpawnData = nil
            OffsetEditor.StopPreview()
            lib.notify({ title = 'Calibração', description = 'Posicionamento do ponto de entrega cancelado.', type = 'info' })
        else
            ActiveCalibSpawnData = nil
            lib.notify({ title = 'Calibração', description = 'Calibração cancelada.', type = 'info' })
        end
    end

    -- Limpeza completa de encerramento
    IsCalibratingSpawn = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hideGizmo' })
    SendNUIMessage({ action = 'updateGizmoBatch', data = { total = 0 } })

    local activeCam = cam or SpawnCam
    if activeCam and DoesCamExist(activeCam) then
        DestroyCam(activeCam, false)
    end
    SpawnCam = nil
    RenderScriptCams(false, true, 500, true, true)

    if SpawnGhostEnt and DoesEntityExist(SpawnGhostEnt) then
        DeleteEntity(SpawnGhostEnt)
        SpawnGhostEnt = nil
    end

    if #BatchSpawnState.previewEntities > 0 then
        for _, pEnt in ipairs(BatchSpawnState.previewEntities) do
            if pEnt and DoesEntityExist(pEnt) then
                DeleteEntity(pEnt)
            end
        end
        BatchSpawnState.previewEntities = {}
    end
    BatchSpawnState.active = false
    BatchSpawnState.confirmedItems = {}

    SendNUIMessage({ action = 'admin_restore' })
    SetNuiFocus(true, true)
end

RegisterNUICallback('moveGizmoSpawn', function(data, cb)
    if not IsCalibratingSpawn or not SpawnGhostEnt or not DoesEntityExist(SpawnGhostEnt) then
        if cb then cb({ ok = false }) end
        return
    end

    local pos = data.position
    local rot = data.rotation

    if pos then
        SetEntityCoordsNoOffset(SpawnGhostEnt, pos.x, pos.y, pos.z, false, false, false)
        local h = (rot and rot.z) or CurrentSpawnCoords.heading or 0.0
        SetEntityHeading(SpawnGhostEnt, h)

        CurrentSpawnCoords = {
            x = tonumber(string.format("%.2f", pos.x)),
            y = tonumber(string.format("%.2f", pos.y)),
            z = tonumber(string.format("%.2f", pos.z)),
            heading = tonumber(string.format("%.1f", h))
        }
    end

    if cb then cb({ ok = true }) end
end)

-- ============================================================
-- AMBIENTE DE TESTE / PREVIEW SEGURO DE PONTOS DE SPAWN
-- ============================================================

function OffsetEditor.StartPreview(spawnsList)
    if IsPreviewActive then
        OffsetEditor.StopPreview()
    end

    if not spawnsList or #spawnsList == 0 then
        lib.notify({ title = 'Preview de Spawns', description = 'Nenhum ponto de spawn disponível para visualização.', type = 'warning' })
        return
    end

    IsPreviewActive = true
    ActivePreviewEntities = {}
    ActivePreviewMarkers = {}

    -- Minimiza NUI para o admin caminhar pelo pátio
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'admin_minimize' })

    for _, s in ipairs(spawnsList) do
        local c = s.coords
        if c then
            local sType = tostring(s.spawn_type or 'truck'):lower()
            local isMarker = (sType == 'load_bay' or sType == 'delivery_bay' or sType == 'marker' or sType == 'drawmarker' or sType == 'bay')

            if isMarker then
                table.insert(ActivePreviewMarkers, {
                    coords = c,
                    type = sType,
                    name = s.name or s.spawn_name or 'Baia'
                })
            else
                local modelStr = s.model
                local isVeh = not isMarker

                if not modelStr or modelStr == '' then
                    if sType == 'truck' then modelStr = 'hauler'
                    elseif sType == 'trailer' then modelStr = 'trailers2'
                    elseif sType == 'forklift' then modelStr = 'forklift'
                    elseif sType == 'handler' then modelStr = 'handler'
                    else modelStr = 'hei_prop_carrier_cargo_04b'; isVeh = false end
                else
                    if sType == 'pallet' or sType == 'prop' or isMarker then isVeh = false end
                end

                local h = joaat(modelStr)
                lib.requestModel(h, 5000)

                local ent = nil
                if isVeh then
                    ent = CreateVehicle(h, c.x, c.y, c.z, c.heading or c.w or 0.0, false, false)
                    if ent and DoesEntityExist(ent) then SetVehicleDoorsLocked(ent, 2) end
                else
                    ent = CreateObject(h, c.x, c.y, c.z, false, false, false)
                end

                if ent and DoesEntityExist(ent) then
                    SetEntityAsMissionEntity(ent, true, true)
                    SetEntityAlpha(ent, 185, false)
                    SetEntityCollision(ent, false, false)
                    SetEntityInvincible(ent, true)
                    FreezeEntityPosition(ent, true)
                    SetEntityHeading(ent, c.heading or c.w or 0.0)
                    table.insert(ActivePreviewEntities, ent)
                end
            end
        end
    end

    lib.showTextUI('[BACKSPACE] Encerrar Teste / Preview de Spawns', {
        position = 'top-center',
        icon = 'eye',
        style = {
            borderRadius = 8,
            backgroundColor = '#059669',
            color = '#ffffff'
        }
    })

    local totalPreview = #ActivePreviewEntities + #ActivePreviewMarkers
    lib.notify({
        title = 'Modo Preview Ativo',
        description = ('Visualizando %d pontos de spawn (veículos e baias) com segurança.'):format(totalPreview),
        type = 'success',
        duration = 5000
    })

    CreateThread(function()
        while IsPreviewActive do
            Wait(0)

            -- Renderiza marcadores visuais das baias no pátio (DrawMarker 30 Zebrado Oficial)
            for _, m in ipairs(ActivePreviewMarkers) do
                local mc = m.coords
                local mZ = mc.z - 0.45
                local foundG, gZ = GetGroundZFor_3dCoord(mc.x, mc.y, mc.z + 2.0, false)
                if foundG and gZ > 0.0 then
                    mZ = gZ + 0.05
                end
                local targetHeading = mc.heading or mc.w or 0.0

                DrawMarker(
                    30,
                    mc.x, mc.y, mZ,
                    0.0, 0.0, 0.0,
                    90.0, targetHeading, 0.0,
                    3.0, 1.0, 10.0,
                    255, 60, 60, 75,
                    0, 0, 0, 0
                )
            end

            if IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 177) then -- Backspace / ESC
                OffsetEditor.StopPreview()
                break
            end
        end
    end)
end

function OffsetEditor.StopPreview()
    if not IsPreviewActive then return end
    IsPreviewActive = false

    lib.hideTextUI()

    for _, ent in ipairs(ActivePreviewEntities) do
        if ent and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end
    ActivePreviewEntities = {}
    ActivePreviewMarkers = {}

    SendNUIMessage({ action = 'admin_restore' })
    SetNuiFocus(true, true)
    lib.notify({ title = 'Preview Finalizado', description = 'Ambiente de teste encerrado com sucesso.', type = 'info' })
end

-- ============================================================
-- SUBMÓDULO: PROP EDITOR (6 GRAUS DE LIBERDADE: X, Y, Z, P, R, Y)
-- ============================================================
local IsPropEditorActive = false
local PropEditorVeh = nil
local PropEditorProp = nil
local PropEditorVehModel = nil
local PropEditorPropModel = nil
local PropEditorBoneIndex = 0
local PropEditorOffsets = { x = 0.0, y = 0.0, z = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 }
local PropEditorListenThread = false
local PropEditorCam = nil
local PropEditorGizmoActive = false

-- Determina o Bone Index adequado para o veículo de carregamento
local function GetVehicleLoadingBoneIndex(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return 0 end
    local vModel = GetEntityModel(vehicle)
    local forkHash = joaat('forklift')
    local handlerHash = joaat('handler')

    if vModel == forkHash then
        local bIdx = GetEntityBoneIndexByName(vehicle, 'forks')
        if bIdx == -1 then bIdx = GetEntityBoneIndexByName(vehicle, 'forks_attach') end
        if bIdx == -1 and Config and Config.Polarix and Config.Polarix.Forklift then
            bIdx = Config.Polarix.Forklift.ForkBoneIndex or 3
        end
        return (bIdx ~= -1 and bIdx) or 0
    elseif vModel == handlerHash then
        local craneBoneName = (Config and Config.ContainerHandler and Config.ContainerHandler.CraneBone) or 'frame_2'
        local bIdx = GetEntityBoneIndexByName(vehicle, craneBoneName)
        return (bIdx ~= -1 and bIdx) or 0
    end
    return 0
end

-- Calcula posição relativa ao Bone Index (se for 0 usa GetOffsetFromEntityGivenWorldCoords)
local function GetOffsetFromBoneGivenWorldCoords(vehicle, boneIndex, wx, wy, wz)
    if not vehicle or not DoesEntityExist(vehicle) then return vector3(0.0, 0.0, 0.0) end
    if not boneIndex or boneIndex == 0 then
        return GetOffsetFromEntityGivenWorldCoords(vehicle, wx, wy, wz)
    end
    local bCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    if bCoords == vector3(0.0, 0.0, 0.0) then
        return GetOffsetFromEntityGivenWorldCoords(vehicle, wx, wy, wz)
    end
    local vFwd, vRight, vUp, _ = GetEntityMatrix(vehicle)
    local d = vector3(wx, wy, wz) - bCoords
    local rx = (d.x * vRight.x) + (d.y * vRight.y) + (d.z * vRight.z)
    local ry = (d.x * vFwd.x) + (d.y * vFwd.y) + (d.z * vFwd.z)
    local rz = (d.x * vUp.x) + (d.y * vUp.y) + (d.z * vUp.z)
    return vector3(rx, ry, rz)
end

-- 1. SPAWN DE ENTIDADES NO MUNDO COM FÍSICA E NETWORK
RegisterNUICallback('adminPropEditorSpawn', function(data, cb)
    local vModel = data.vehicleModel and tostring(data.vehicleModel):lower()
    local pModel = data.propModel and tostring(data.propModel):lower()

    if not vModel or not pModel then
        if cb then cb({ ok = false, error = 'Modelos inválidos' }) end
        return
    end

    -- Limpa entidades anteriores se existirem
    if PropEditorProp and DoesEntityExist(PropEditorProp) then DeleteEntity(PropEditorProp); PropEditorProp = nil end
    if PropEditorVeh and DoesEntityExist(PropEditorVeh) then DeleteEntity(PropEditorVeh); PropEditorVeh = nil end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local pHeading = GetEntityHeading(ped)

    -- Calcula spawn à frente do admin
    local fwd = GetEntityForwardVector(ped)
    local vehSpawnCoords = pCoords + (fwd * 6.0)
    local propSpawnCoords = pCoords + (fwd * 12.0)

    -- 1. Spawna Veículo
    local vHash = joaat(vModel)
    if not IsModelInCdimage(vHash) or not IsModelAVehicle(vHash) then
        lib.notify({ title = 'PropEditor', description = 'Modelo de veículo não encontrado no jogo.', type = 'error' })
        if cb then cb({ ok = false }) end
        return
    end
    lib.requestModel(vHash, 5000)
    local veh = CreateVehicle(vHash, vehSpawnCoords.x, vehSpawnCoords.y, vehSpawnCoords.z + 0.5, pHeading, true, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDoorsLocked(veh, 1)

    -- 2. Spawna Prop com física
    local pHash = joaat(pModel)
    if not IsModelInCdimage(pHash) then
        lib.notify({ title = 'PropEditor', description = 'Modelo de prop não encontrado no jogo.', type = 'error' })
        DeleteEntity(veh)
        if cb then cb({ ok = false }) end
        return
    end
    lib.requestModel(pHash, 5000)
    local prop = CreateObject(pHash, vehSpawnCoords.x, vehSpawnCoords.y, vehSpawnCoords.z + 1.0, true, false, false)
    SetEntityAsMissionEntity(prop, true, true)
    SetEntityLodDist(prop, 0xFFFF)
    SetEntityVisible(prop, true)
    ResetEntityAlpha(prop)
    DisableCamCollisionForEntity(prop)
    SetEntityDynamic(prop, false)
    SetEntityHasGravity(prop, false)
    SetEntityCollision(prop, false, false)

    PropEditorVeh = veh
    PropEditorProp = prop
    PropEditorVehModel = vModel
    PropEditorPropModel = pModel
    IsPropEditorActive = true
    PropEditorGizmoActive = false

    PropEditorBoneIndex = GetVehicleLoadingBoneIndex(veh)

    -- 3. FASE 1: ACOPLAMENTO AUTOMÁTICO IMEDIATO NO SURGIMENTO
    -- Verifica se já existe offset prévio salvo no banco para carregar; caso contrário, acopla no centro/garfos padrão
    local prevOffset, prevRot = GetVehiclePropOffset(veh, pHash)
    local initX, initY, initZ = 0.0, 0.0, 0.0
    local initPitch, initRoll, initYaw = 0.0, 0.0, 0.0

    if prevOffset then
        initX, initY, initZ = prevOffset.x, prevOffset.y, prevOffset.z
        if prevRot then
            initPitch, initRoll, initYaw = prevRot.x, prevRot.y, prevRot.z
        end
    else
        -- Valores default ergonômicos conforme o veículo de carregamento
        if vHash == joaat('forklift') then
            initX, initY, initZ = 0.0, 0.95, -0.05
        elseif vHash == joaat('handler') then
            local defH = (Config and Config.ContainerHandler and Config.ContainerHandler.AttachOffset)
                or (Config and Config.Polarix and Config.Polarix.Handler and Config.Polarix.Handler.AttachOffset)
                or { x = 0.0, y = 1.78, z = -2.5, rx = 0.0, ry = 0.0, rz = 90.0 }
            initX, initY, initZ = defH.x or 0.0, defH.y or 1.78, defH.z or -2.5
            initPitch, initRoll, initYaw = defH.rx or 0.0, defH.ry or 0.0, defH.rz or 90.0
        else
            initZ = 0.5
        end
    end

    AttachEntityToEntity(
        prop, veh, PropEditorBoneIndex,
        initX, initY, initZ,
        initPitch, initRoll, initYaw,
        false, false, false, false, 2, true
    )

    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)

    -- 4. FASE 2: ATIVAÇÃO VISUAL IMEDIATA DO GIZMO 3D (6DoF)
    OffsetEditor.ActivatePropEditorGizmo()

    lib.notify({
        title = 'Acoplamento Automático!',
        description = ('Veículo (%s) e Prop (%s) gerados e acoplados no Bone %d! Gizmo 3D (6DoF) ativado.'):format(vModel, pModel, PropEditorBoneIndex),
        type = 'success',
        duration = 5000
    })

    if cb then cb({ ok = true }) end
end)

-- 3. FASE DE EDIÇÃO VISUAL COM GIZMO 3D (6DoF) COM FREECAM 1:1 IDÊNTICA AO TRAILER 3D
function OffsetEditor.ActivatePropEditorGizmo()
    if not PropEditorVeh or not DoesEntityExist(PropEditorVeh) or not PropEditorProp or not DoesEntityExist(PropEditorProp) then return end
    PropEditorGizmoActive = true

    -- Minimiza o painel administrativo principal estilo Offsets Trailer 3D
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'admin_minimize' })

    local ped = cache.ped or PlayerPedId()
    -- Protege e oculta o ped durante a calibração
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    -- Configuração e ativação da Câmera Livre (Scripted Camera) focada no veículo e prop
    local vCoords = GetEntityCoords(PropEditorVeh)
    local vHeadingRad = math.rad(GetEntityHeading(PropEditorVeh))
    local camX = vCoords.x - math.sin(vHeadingRad) * 8.5
    local camY = vCoords.y - math.cos(vHeadingRad) * 8.5
    local camZ = vCoords.z + 3.8
    local camRot = vector3(-15.0, 0.0, GetEntityHeading(PropEditorVeh))

    if PropEditorCam and DoesCamExist(PropEditorCam) then
        DestroyCam(PropEditorCam, false)
        PropEditorCam = nil
    end

    local propCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, camZ, camRot.x, camRot.y, camRot.z, 55.0, true, 2)
    SetCamActive(propCam, true)
    RenderScriptCams(true, false, 0, true, true)
    PropEditorCam = propCam

    -- Calcula offsets relativos iniciais baseados no Bone correto
    local pCoords = GetEntityCoords(PropEditorProp)
    local relPos = GetOffsetFromBoneGivenWorldCoords(PropEditorVeh, PropEditorBoneIndex, pCoords.x, pCoords.y, pCoords.z)
    local vRot = GetEntityRotation(PropEditorVeh, 2)
    local pRot = GetEntityRotation(PropEditorProp, 2)

    local relPitch = (pRot.x - vRot.x) % 360.0
    local relRoll  = (pRot.y - vRot.y) % 360.0
    local relYaw   = (pRot.z - vRot.z) % 360.0

    PropEditorOffsets = {
        x = tonumber(string.format("%.3f", relPos.x)),
        y = tonumber(string.format("%.3f", relPos.y)),
        z = tonumber(string.format("%.3f", relPos.z)),
        pitch = tonumber(string.format("%.1f", relPitch)),
        roll = tonumber(string.format("%.1f", relRoll)),
        yaw = tonumber(string.format("%.1f", relYaw))
    }

    SendNUIMessage({
        action = 'admin_propeditor_status',
        text = ('Gizmo 3D (6DoF) Ativo no Bone %d! Use FreeCam e Gizmo.'):format(PropEditorBoneIndex),
        type = 'attached'
    })

    SendNUIMessage({
        action = 'admin_propeditor_update_values',
        data = PropEditorOffsets
    })

    -- Abre o Gizmo Overlay Three.js com suporte a 6DoF
    SendNUIMessage({
        action = 'initGizmo',
        data = {
            context = 'propeditor',
            position = { x = pCoords.x, y = pCoords.y, z = pCoords.z },
            rotation = { x = pRot.x, y = pRot.y, z = pRot.z }
        }
    })

    lib.notify({
        title = 'Gizmo 3D PropEditor Ativo!',
        description = 'WASD: Voo Livre.\nSegure [ALT] para liberar o mouse e arrastar o Gizmo.\n[ENTER]: Salvar  |  [ESC]: Finalizar.',
        type = 'info',
        duration = 8000
    })

    -- Inicia o laço de controle de câmera / mouse / teclado idêntico a Offsets Trailer 3D
    OffsetEditor.RunPropGizmoCameraLoop(propCam)
end

function OffsetEditor.RunPropGizmoCameraLoop(propCam)
    CreateThread(function()
        local isCursorActive = false

        while IsPropEditorActive and PropEditorGizmoActive and propCam and DoesCamExist(propCam) do
            Wait(0)

            -- Desabilita ações normais do jogo (isolamento total)
            DisableAllControlActions(0)

            -- 1. SINCRONIZAÇÃO DA CÂMERA COM O THREE.JS
            local camPos = GetCamCoord(propCam)
            local camRot = GetCamRot(propCam, 2)
            SendNUIMessage({
                action = 'setCameraPosition',
                data = {
                    position = { x = camPos.x, y = camPos.y, z = camPos.z },
                    rotation = { x = camRot.x, y = camRot.y, z = camRot.z }
                }
            })

            -- 2. ALTERNÂNCIA DE CURSOR VS MOUSE LOOK VIA TECLA ALT (HOLD) — IDÊNTICO AO TRAILER 3D
            local isAltHeld = IsDisabledControlPressed(0, 19) or IsControlPressed(0, 19)
            if isAltHeld then
                if not isCursorActive then
                    isCursorActive = true
                    SetNuiFocus(true, true)
                    SetNuiFocusKeepInput(true)
                    SendNUIMessage({ action = 'setGizmoCursor', data = { active = true } })
                end
            else
                if isCursorActive then
                    isCursorActive = false
                    SetNuiFocus(false, false)
                    SetNuiFocusKeepInput(false)
                    SendNUIMessage({ action = 'setGizmoCursor', data = { active = false } })
                end

                -- Rotação de câmera suave pelo mouse (somente quando ALT não estiver segurado)
                local mouseX = GetDisabledControlNormal(0, 1)
                local mouseY = GetDisabledControlNormal(0, 2)
                if mouseX ~= 0.0 or mouseY ~= 0.0 then
                    local camSens = 4.0
                    camRot = vector3(
                        math.max(-85.0, math.min(85.0, camRot.x - mouseY * camSens)),
                        0.0,
                        (camRot.z - mouseX * camSens) % 360.0
                    )
                    SetCamRot(propCam, camRot.x, camRot.y, camRot.z, 2)
                end
            end

            -- 3. VOO LIVRE DA CÂMERA (WASD / Space / LCtrl / Shift) — IDÊNTICO AO TRAILER 3D
            local radX = math.rad(camRot.x)
            local radZ = math.rad(camRot.z)
            local cosX = math.cos(radX)
            local sinX = math.sin(radX)
            local cosZ = math.cos(radZ)
            local sinZ = math.sin(radZ)

            local fwd = vector3(-sinZ * cosX, cosZ * cosX, sinX)
            local rgt = vector3(cosZ, sinZ, 0.0)
            local up  = vector3(0.0, 0.0, 1.0)

            local camSpeed = 0.16
            if IsDisabledControlPressed(0, 21) then camSpeed = 0.45 end -- LShift (Turbo)

            local cPos = GetCamCoord(propCam)
            local camMoved = false

            if IsDisabledControlPressed(0, 32) then cPos = cPos + fwd * camSpeed; camMoved = true end -- W
            if IsDisabledControlPressed(0, 33) then cPos = cPos - fwd * camSpeed; camMoved = true end -- S
            if IsDisabledControlPressed(0, 34) then cPos = cPos - rgt * camSpeed; camMoved = true end -- A
            if IsDisabledControlPressed(0, 35) then cPos = cPos + rgt * camSpeed; camMoved = true end -- D
            if IsDisabledControlPressed(0, 22) then cPos = cPos + up  * camSpeed; camMoved = true end -- Space
            if IsDisabledControlPressed(0, 36) then cPos = cPos - up  * camSpeed; camMoved = true end -- LCtrl

            if camMoved then
                SetCamCoord(propCam, cPos.x, cPos.y, cPos.z)
            end

            -- 4. ALTERNÂNCIA DE MODO DO GIZMO COM AS TECLAS T E R
            if IsDisabledControlJustPressed(0, 245) or IsControlJustPressed(0, 245) then -- T
                CurrentGizmoMode = 'translate'
                SendNUIMessage({ action = 'setGizmoMode', data = { mode = 'translate' } })
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Translação (Setas)', type = 'info', duration = 1200 })
            elseif IsDisabledControlJustPressed(0, 45) or IsControlJustPressed(0, 45) then -- R
                CurrentGizmoMode = 'rotate'
                SendNUIMessage({ action = 'setGizmoMode', data = { mode = 'rotate' } })
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Rotação (Anéis)', type = 'info', duration = 1200 })
            end

            -- 5. SALVAMENTO VIA TECLADO ENTER (Controles FiveM 201, 191, 176 - INPUT_FRONTEND_ACCEPT / RDOWN / CELLPHONE_SELECT)
            -- Exclui clique esquerdo do mouse (controle 24) para evitar salvamento involuntário durante o arrasto do Gizmo
            local isKeyboardEnter = (IsDisabledControlJustPressed(0, 201) or IsControlJustPressed(0, 201)
                or IsDisabledControlJustPressed(0, 191) or IsControlJustPressed(0, 191)
                or IsDisabledControlJustPressed(0, 176) or IsControlJustPressed(0, 176))
                and not IsDisabledControlPressed(0, 24)
                and not IsDisabledControlJustPressed(0, 24)

            if isKeyboardEnter then
                OffsetEditor.ConfirmPropEditorSlot()
                break
            end

            -- 6. TECLA ESC OU BACKSPACE: FINALIZAR / CANCELAR E RESTAURAR
            if IsDisabledControlJustPressed(0, 177) or IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
                OffsetEditor.CancelPropEditorSession()
                break
            end

            -- 7. HUD FLUTUANTE EM TEMPO REAL ESTILO OFFSETS TRAILER 3D
            local modeStatus = isCursorActive and '~g~[CURSOR GIZMO ATIVO]~s~' or '~b~[CÂMERA LIVRE]~s~'
            local gizmoModeLabel = CurrentGizmoMode == 'translate' and '~w~Translação (Setas)~s~' or '~w~Rotação (Anéis)~s~'
            local hudText = ('~g~[PROP EDITOR 6DoF]~s~ %s\n' ..
                'Veículo: ~w~%s~s~  |  Prop: ~y~%s~s~  |  Modo: %s\n' ..
                'Offset: ~b~X: %.3f  |  Y: %.3f  |  Z: %.3f~s~\n' ..
                'Rotação: ~y~Pitch: %.1f°  |  Roll: %.1f°  |  Yaw: %.1f°~s~\n' ..
                '~w~[WASD] Voo Livre  |  [Mouse] Girar Câmera  |  [Shift] Turbo\n' ..
                '~y~[SEGURE ALT]~w~ Ativa Cursor para Arrastar o Gizmo / Clicar\n' ..
                '[T] Setas Translação  |  [R] Anéis Rotação\n' ..
                '~g~[ENTER ou Botão] Salvar no Banco~s~  |  ~r~[ESC] Finalizar~s~'):format(
                modeStatus,
                PropEditorVehModel or 'desconhecido',
                PropEditorPropModel or 'desconhecido',
                gizmoModeLabel,
                PropEditorOffsets.x or 0.0, PropEditorOffsets.y or 0.0, PropEditorOffsets.z or 0.0,
                PropEditorOffsets.pitch or 0.0, PropEditorOffsets.roll or 0.0, PropEditorOffsets.yaw or 0.0
            )

            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.34, 0.34)
            SetTextColour(255, 255, 255, 255)
            SetTextDropshadow(0, 0, 0, 0, 255)
            SetTextEdge(1, 0, 0, 0, 205)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(hudText)
            DrawText(0.015, 0.02)
        end
    end)
end

function OffsetEditor.ConfirmPropEditorSlot()
    if not IsPropEditorActive then return end

    -- Garante cálculo atualizado se PropEditorOffsets estiver vazio ou desatualizado
    if PropEditorVeh and DoesEntityExist(PropEditorVeh) and PropEditorProp and DoesEntityExist(PropEditorProp) then
        local pCoords = GetEntityCoords(PropEditorProp)
        local relPos = GetOffsetFromBoneGivenWorldCoords(PropEditorVeh, PropEditorBoneIndex, pCoords.x, pCoords.y, pCoords.z)
        local vRot = GetEntityRotation(PropEditorVeh, 2)
        local pRot = GetEntityRotation(PropEditorProp, 2)

        local relPitch = (pRot.x - vRot.x) % 360.0
        local relRoll  = (pRot.y - vRot.y) % 360.0
        local relYaw   = (pRot.z - vRot.z) % 360.0

        PropEditorOffsets = PropEditorOffsets or {}
        PropEditorOffsets.x = tonumber(string.format("%.3f", relPos.x))
        PropEditorOffsets.y = tonumber(string.format("%.3f", relPos.y))
        PropEditorOffsets.z = tonumber(string.format("%.3f", relPos.z))
        PropEditorOffsets.pitch = tonumber(string.format("%.1f", relPitch))
        PropEditorOffsets.roll = tonumber(string.format("%.1f", relRoll))
        PropEditorOffsets.yaw = tonumber(string.format("%.1f", relYaw))
    end

    local payload = {
        vehicleModel = PropEditorVehModel,
        propModel = PropEditorPropModel,
        x = (PropEditorOffsets and PropEditorOffsets.x) or 0.0,
        y = (PropEditorOffsets and PropEditorOffsets.y) or 0.0,
        z = (PropEditorOffsets and PropEditorOffsets.z) or 0.0,
        pitch = (PropEditorOffsets and PropEditorOffsets.pitch) or 0.0,
        roll = (PropEditorOffsets and PropEditorOffsets.roll) or 0.0,
        yaw = (PropEditorOffsets and PropEditorOffsets.yaw) or 0.0
    }

    -- Dispara evento de gravação no banco de dados
    TriggerServerEvent('aurp_trucker:server:adminSaveVehiclePropOffset', payload)

    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    lib.notify({
        title = 'PropEditor',
        description = ('Offset de %s + %s salvo com sucesso no Bone %d!'):format(tostring(payload.vehicleModel), tostring(payload.propModel), PropEditorBoneIndex),
        type = 'success',
        duration = 4000
    })

    -- Encerra Gizmo e FreeCam, restaura ped e painel administrativo
    OffsetEditor.CancelPropEditorSession()
end

-- Callback acionado a cada alteração do Gizmo Three.js em tempo real
RegisterNUICallback('moveGizmoPropOffset', function(data, cb)
    if not IsPropEditorActive or not PropEditorVeh or not DoesEntityExist(PropEditorVeh) or not PropEditorProp or not DoesEntityExist(PropEditorProp) then
        if cb then cb({ ok = false }) end
        return
    end

    local worldPos = data.position
    local worldRot = data.rotation

    if worldPos and worldRot then
        -- Converte coordenadas mundiais para offset e rotação relativa ao Bone do veículo
        local relOffset = GetOffsetFromBoneGivenWorldCoords(PropEditorVeh, PropEditorBoneIndex, worldPos.x, worldPos.y, worldPos.z)
        local vRot = GetEntityRotation(PropEditorVeh, 2)

        local relPitch = (worldRot.x - vRot.x) % 360.0
        local relRoll  = (worldRot.y - vRot.y) % 360.0
        local relYaw   = (worldRot.z - vRot.z) % 360.0

        PropEditorOffsets = {
            x = tonumber(string.format("%.3f", relOffset.x)),
            y = tonumber(string.format("%.3f", relOffset.y)),
            z = tonumber(string.format("%.3f", relOffset.z)),
            pitch = tonumber(string.format("%.1f", relPitch)),
            roll = tonumber(string.format("%.1f", relRoll)),
            yaw = tonumber(string.format("%.1f", relYaw))
        }

        -- Reanexa em tempo real com os novos offsets de 6 graus de liberdade no Bone correto
        AttachEntityToEntity(
            PropEditorProp, PropEditorVeh, PropEditorBoneIndex,
            PropEditorOffsets.x, PropEditorOffsets.y, PropEditorOffsets.z,
            PropEditorOffsets.pitch, PropEditorOffsets.roll, PropEditorOffsets.yaw,
            false, false, false, false, 2, true
        )

        -- Atualiza valores numéricos na NUI
        SendNUIMessage({
            action = 'admin_propeditor_update_values',
            data = PropEditorOffsets
        })
    end

    if cb then cb({ ok = true }) end
end)

-- Callback quando o usuário digita nos inputs numéricos
RegisterNUICallback('adminPropEditorManualChange', function(data, cb)
    if not IsPropEditorActive or not PropEditorVeh or not DoesEntityExist(PropEditorVeh) or not PropEditorProp or not DoesEntityExist(PropEditorProp) then
        if cb then cb({ ok = false }) end
        return
    end

    PropEditorOffsets = {
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0,
        z = tonumber(data.z) or 0.0,
        pitch = tonumber(data.pitch) or 0.0,
        roll = tonumber(data.roll) or 0.0,
        yaw = tonumber(data.yaw) or 0.0
    }

    AttachEntityToEntity(
        PropEditorProp, PropEditorVeh, PropEditorBoneIndex,
        PropEditorOffsets.x, PropEditorOffsets.y, PropEditorOffsets.z,
        PropEditorOffsets.pitch, PropEditorOffsets.roll, PropEditorOffsets.yaw,
        false, false, false, false, 2, true
    )

    -- Atualiza posição do Gizmo Three.js
    local pCoords = GetEntityCoords(PropEditorProp)
    local pRot = GetEntityRotation(PropEditorProp, 2)
    SendNUIMessage({
        action = 'setGizmoEntity',
        data = {
            position = { x = pCoords.x, y = pCoords.y, z = pCoords.z },
            rotation = { x = pRot.x, y = pRot.y, z = pRot.z }
        }
    })

    if cb then cb({ ok = true }) end
end)

-- 4. FASE DE SALVAMENTO E SINCRONIZAÇÃO DEFINITIVA
RegisterNUICallback('adminPropEditorSave', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminSaveVehiclePropOffset', {
        vehicleModel = data.vehicleModel or PropEditorVehModel,
        propModel = data.propModel or PropEditorPropModel,
        x = tonumber(data.x) or PropEditorOffsets.x,
        y = tonumber(data.y) or PropEditorOffsets.y,
        z = tonumber(data.z) or PropEditorOffsets.z,
        pitch = tonumber(data.pitch) or PropEditorOffsets.pitch,
        roll = tonumber(data.roll) or PropEditorOffsets.roll,
        yaw = tonumber(data.yaw) or PropEditorOffsets.yaw
    })

    SendNUIMessage({
        action = 'admin_propeditor_status',
        text = 'Offsets gravados permanentemente no banco!',
        type = 'success'
    })

    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
    if cb then cb({ ok = true }) end
end)

-- Exclusão de offset
RegisterNUICallback('adminDeleteVehiclePropOffset', function(data, cb)
    TriggerServerEvent('aurp_trucker:server:adminDeleteVehiclePropOffset', data)
    if cb then cb({ ok = true }) end
end)

-- Cancelamento da sessão
RegisterNUICallback('adminPropEditorCancel', function(data, cb)
    OffsetEditor.CancelPropEditorSession()
    if cb then cb({ ok = true }) end
end)

function OffsetEditor.CancelPropEditorSession()
    IsPropEditorActive = false
    PropEditorGizmoActive = false

    SendNUIMessage({ action = 'hideGizmo' })
    SendNUIMessage({ action = 'admin_restore' })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    -- Destrói câmera livre e restaura câmera do ped
    if PropEditorCam and DoesCamExist(PropEditorCam) then
        DestroyCam(PropEditorCam, false)
        PropEditorCam = nil
    end
    RenderScriptCams(false, false, 0, true, true)

    -- Restaura ped do jogador
    local ped = cache.ped or PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetPlayerControl(PlayerId(), true, 0)

    if PropEditorProp and DoesEntityExist(PropEditorProp) then DeleteEntity(PropEditorProp); PropEditorProp = nil end
    if PropEditorVeh and DoesEntityExist(PropEditorVeh) then DeleteEntity(PropEditorVeh); PropEditorVeh = nil end
end

-- Limpeza ao parar o resource: entidades fantasma, trailer de calibração, NPCs/blips admin, câmera e foco NUI
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    local function delEnt(ent)
        if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
    end

    delEnt(CalibGhost); CalibGhost = nil
    for _, g in ipairs(SavedGhosts) do delEnt(g) end
    SavedGhosts = {}
    delEnt(CalibTrailer); CalibTrailer = nil
    delEnt(SpawnGhostEnt); SpawnGhostEnt = nil
    delEnt(PropEditorProp); PropEditorProp = nil
    delEnt(PropEditorVeh); PropEditorVeh = nil
    for _, e in ipairs(ActivePreviewEntities) do delEnt(e) end
    ActivePreviewEntities = {}

    for _, data in pairs(DynamicAdminPeds) do
        if data.ped and DoesEntityExist(data.ped) then
            pcall(function() exports.ox_target:removeLocalEntity(data.ped) end)
            DeleteEntity(data.ped)
        end
        if data.blip and DoesBlipExist(data.blip) then RemoveBlip(data.blip) end
    end
    DynamicAdminPeds = {}

    if ActiveCalibCam and DoesCamExist(ActiveCalibCam) then DestroyCam(ActiveCalibCam, false) end
    ActiveCalibCam = nil
    if PropEditorCam and DoesCamExist(PropEditorCam) then DestroyCam(PropEditorCam, false) end
    PropEditorCam = nil

    if IsCalibrating or IsCalibratingSpawn or IsPreviewActive or IsPropEditorActive then
        RenderScriptCams(false, false, 0, true, true)
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetEntityVisible(ped, true, false)
        SetPlayerControl(PlayerId(), true, 0)
    end
    IsCalibrating, IsCalibratingSpawn, IsPreviewActive, IsPropEditorActive, PropEditorGizmoActive = false, false, false, false, false
end)

-- Solicitação inicial dos NPCs despachantes ao iniciar o script no client
CreateThread(function()
    Wait(1500)
    TriggerServerEvent('aurp_trucker:server:adminRequestNPCs')
end)
