-- aurp_trucker — client/modules/offset_editor.lua
-- Módulo In-Game de Calibração Visual 3D de Offsets de Reboque e Gerenciamento de Spawns/NPCs
-- Motor de Gizmo 3D (Three.js + TransformControls) adaptado do vp_staff_studio (Haze-Studio-s)

OffsetEditor = {}

local IsCalibrating = false
local CalibTrailer = nil
local CalibGhost = nil
local CurrentOffsets = { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
local CalibParams = { trailerModel = 'trailers2', slotIndex = 1, isForklift = false, propModel = 'hei_prop_carrier_cargo_04b' }
local CurrentGizmoMode = 'translate' -- 'translate' | 'rotate'
local IsGizmoCursorActive = false

local ActiveCreatedTrailer = false
local ActiveCalibCam = nil

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
        print("[AUST_Trucker] Falha crítica ao spawnar entidade fantasma para calibração.")
        return nil
    end

    SetEntityAsMissionEntity(ghost, true, true)
    SetEntityLodDist(ghost, 0xFFFF)
    SetEntityAlpha(ghost, 190, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)

    CalibGhost = ghost
    return ghost
end

-- ============================================================
-- NUI CALLBACKS: MANIPULAÇÃO DO GIZMO 3D (THREE.JS)
-- ============================================================

RegisterNUICallback('moveGizmoOffset', function(data, cb)
    if not IsCalibrating or not CalibTrailer or not DoesEntityExist(CalibTrailer) or not CalibGhost or not DoesEntityExist(CalibGhost) then
        if cb then cb({ ok = false }) end
        return
    end

    local worldPos = data.position
    local worldRot = data.rotation

    if worldPos then
        -- 1. Converte coordenadas globais (World) do Gizmo para Offset Relativo ao reboque
        local relOffset = GetOffsetFromEntityGivenWorldCoords(CalibTrailer, worldPos.x, worldPos.y, worldPos.z)
        local tRot = GetEntityRotation(CalibTrailer, 2)
        local relHeading = 0.0
        if worldRot and worldRot.z then
            relHeading = (worldRot.z - tRot.z) % 360.0
        end

        CurrentOffsets = {
            x = tonumber(string.format("%.3f", relOffset.x)),
            y = tonumber(string.format("%.3f", relOffset.y)),
            z = tonumber(string.format("%.3f", relOffset.z)),
            heading = tonumber(string.format("%.1f", relHeading))
        }

        -- 2. Atualiza entidade fantasma em tempo real
        SetEntityCoordsNoOffset(CalibGhost, worldPos.x, worldPos.y, worldPos.z, false, false, false)
        if worldRot and worldRot.z then
            SetEntityHeading(CalibGhost, worldRot.z)
        end
    end

    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('confirmGizmoSlot', function(data, cb)
    if IsCalibrating then
        OffsetEditor.ConfirmCurrentSlot()
    end
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('cancelGizmo', function(data, cb)
    if IsCalibrating then
        OffsetEditor.CancelCalibration()
    end
    if cb then cb({ ok = true }) end
end)

-- ============================================================
-- CONFIRMAÇÃO E PROGRESSÃO CONTÍNUA DE SLOTS
-- ============================================================

function OffsetEditor.ConfirmCurrentSlot()
    if not IsCalibrating then return end

    -- 1. Dispara salvamento no banco de dados
    TriggerServerEvent('aurp_trucker:server:adminSaveTrailerOffset', {
        trailerModel = CalibParams.trailerModel,
        slotIndex = CalibParams.slotIndex,
        isForklift = CalibParams.isForklift,
        x = tonumber(string.format("%.3f", CurrentOffsets.x)),
        y = tonumber(string.format("%.3f", CurrentOffsets.y)),
        z = tonumber(string.format("%.3f", CurrentOffsets.z)),
        heading = tonumber(string.format("%.1f", CurrentOffsets.heading))
    })
    PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)

    -- 2. Determina o limite de slots de palete
    local maxPallets = 6
    local curHash = joaat(CalibParams.trailerModel)
    if Config.TrailerSlots and Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].pallets then
        local pCount = #Config.TrailerSlots[curHash].pallets
        if pCount > maxPallets then maxPallets = pCount end
    end

    -- 3. Transição contínua entre slots
    if not CalibParams.isForklift then
        if CalibParams.slotIndex < maxPallets then
            local prevSlot = CalibParams.slotIndex
            CalibParams.slotIndex = CalibParams.slotIndex + 1
            lib.notify({
                title = 'Slot Salvo no Banco!',
                description = ('Slot %d registrado com sucesso. Avançando para o Slot %d.'):format(prevSlot, CalibParams.slotIndex),
                type = 'success',
                duration = 3500
            })

            local nextVec = (Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].pallets and Config.TrailerSlots[curHash].pallets[CalibParams.slotIndex])
            if not nextVec then
                nextVec = ForkliftModule.GetSlotOffset(CalibTrailer, CalibParams.slotIndex)
            end
            CurrentOffsets = { x = nextVec.x, y = nextVec.y, z = nextVec.z, heading = 0.0 }
            SpawnCalibGhost(CalibTrailer, false, CalibParams.propModel, nextVec, 0.0)

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

            local forkVec = (Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].forklift) or ForkliftModule.GetForkliftSlotOffset(CalibTrailer)
            CurrentOffsets = { x = forkVec.x, y = forkVec.y, z = forkVec.z, heading = 0.0 }
            SpawnCalibGhost(CalibTrailer, true, 'forklift', forkVec, 0.0)

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

function OffsetEditor.StartCalibration(trailerModel, slotIndex, isForklift, propModel)
    if IsCalibrating then return end
    IsCalibrating = true
    IsGizmoCursorActive = false
    CurrentGizmoMode = 'translate'

    trailerModel = (trailerModel or 'trailers2'):lower()
    slotIndex = tonumber(slotIndex) or 1
    isForklift = isForklift or false
    propModel = propModel or (isForklift and 'forklift' or 'hei_prop_carrier_cargo_04b')

    CalibParams = {
        trailerModel = trailerModel,
        slotIndex = slotIndex,
        isForklift = isForklift,
        propModel = propModel
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

            -- 7. SALVAMENTO E FLUXO CONTÍNUO (SEAMLESS SEQUENCING) ESTRITAMENTE VIA TECLADO ENTER
            -- NOTA: Controles 18 e 24 (Cliques de Mouse) são estritamente excluídos para não acidentar no Gizmo
            local isKeyboardEnter = (IsDisabledControlJustPressed(0, 191) or IsControlJustPressed(0, 191))
                and not IsDisabledControlPressed(0, 24)
                and not IsDisabledControlJustPressed(0, 24)
                and not IsDisabledControlPressed(0, 18)
                and not IsDisabledControlJustPressed(0, 18)

            if isKeyboardEnter then
                OffsetEditor.ConfirmCurrentSlot()
            end

            -- 8. CANCELAMENTO OU FINALIZAÇÃO ANTECIPADA COM BACKSPACE / ESC
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
    if not Config.TrailerSlots[hash] then
        Config.TrailerSlots[hash] = { pallets = {}, forklift = nil }
    end
    if not Config.TrailerSlots[trailerModel] then
        Config.TrailerSlots[trailerModel] = { pallets = {}, forklift = nil }
    end
    if isForklift then
        Config.TrailerSlots[hash].forklift = offsetVec
        Config.TrailerSlots[trailerModel].forklift = offsetVec
    else
        Config.TrailerSlots[hash].pallets[slotIndex] = offsetVec
        Config.TrailerSlots[trailerModel].pallets[slotIndex] = offsetVec
    end

    -- Se o pacote completo do banco foi enviado, sincroniza e atualiza imediatamente a UI
    if updatedOffsets then
        SendNUIMessage({
            action = 'admin_update_offsets',
            offsets = updatedOffsets
        })
    end

    print(("^2[AUST_Trucker Client] Offset do reboque %s (%s) sincronizado em tempo real!^7"):format(
        trailerModel, isForklift and 'Empilhadeira' or ('Slot ' .. tostring(slotIndex))
    ))
end)

RegisterNetEvent('aurp_trucker:client:adminSyncNPCs', function(npcList)
    -- Remove NPCs dinâmicos antigos
    for _, data in pairs(DynamicAdminPeds) do
        if data.ped and DoesEntityExist(data.ped) then
            pcall(function() exports.ox_target:removeLocalEntity(data.ped) end)
            DeleteEntity(data.ped)
        end
        if data.blip and DoesBlipExist(data.blip) then
            RemoveBlip(data.blip)
        end
    end
    DynamicAdminPeds = {}

    -- Cria ou atualiza novos despachantes
    for id, npc in pairs(npcList or {}) do
        if npc.is_active ~= 0 and npc.coords then
            CreateThread(function()
                local modelHash = joaat(npc.model or 's_m_m_dockwork_01')
                lib.requestModel(modelHash)
                local ped = CreatePed(4, modelHash, npc.coords.x, npc.coords.y, npc.coords.z - 1.0, npc.heading or 0.0, false, false)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCombatAttributes(ped, 17, true)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)

                exports.ox_target:addLocalEntity(ped, {
                    {
                        name = 'admin_dispatcher_' .. id,
                        icon = 'fas fa-truck-ramp-box',
                        label = 'Abrir Central de Fretes (' .. (npc.name or 'Logística') .. ')',
                        distance = 2.5,
                        onSelect = function()
                            ExecuteCommand('trucker')
                        end
                    }
                })

                local blip = AddBlipForCoord(npc.coords.x, npc.coords.y, npc.coords.z)
                SetBlipSprite(blip, npc.blip_sprite or 477)
                SetBlipColour(blip, npc.blip_color or 2)
                SetBlipScale(blip, 0.85)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(npc.name or 'Central Logística')
                EndTextCommandSetBlipName(blip)

                DynamicAdminPeds[id] = { ped = ped, blip = blip }
            end)
        end
    end
end)
