-- aurp_trucker — client/modules/offset_editor.lua
-- Módulo In-Game de Calibração Visual 3D de Offsets de Reboque e Gerenciamento de Spawns/NPCs

OffsetEditor = {}

local IsCalibrating = false
local CalibTrailer = nil
local CalibGhost = nil
local CurrentOffsets = { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
local CalibParams = { trailerModel = 'trailers2', slotIndex = 1, isForklift = false, propModel = 'hei_prop_carrier_cargo_04b' }

-- Cache de NPCs dinâmicos criados pelo Admin
local DynamicAdminPeds = {}

-- ============================================================
-- FERRAMENTA VISUAL IN-GAME DE OFFSETS (GIZMO / NUDGE TOOL)
-- ============================================================

-- ============================================================
-- MATRIX BUFFERS PARA IMGUIZMO (NATIVE 0xEB2EDCA2)
-- ============================================================

local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    local view = DataView.ArrayBuffer(60)
    view:SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
    return view
end

local function applyEntityMatrix(entity, view)
    SetEntityMatrix(entity,
        view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24),
        view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8),
        view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40),
        view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)
    )
end

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
    SetEntityAlpha(ghost, 175, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)

    CalibGhost = ghost
    return ghost
end

-- ============================================================
-- FERRAMENTA VISUAL IN-GAME DE OFFSETS (GIZMO 3D & FREECAM)
-- ============================================================

function OffsetEditor.StartCalibration(trailerModel, slotIndex, isForklift, propModel)
    if IsCalibrating then return end
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

    -- Fecha NUI temporariamente para focar na tela 3D
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'admin_minimize' })

    local ped = cache.ped or PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local pHeading = GetEntityHeading(ped)

    -- Verifica se já há um trailer próximo ou spawna um para visualização
    local tHash = joaat(trailerModel)
    lib.requestModel(tHash, 5000)

    local trailer = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 18.0, tHash, 70)
    local createdTrailer = false
    if not trailer or trailer == 0 then
        local spawnPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 7.0, 0.2)
        trailer = CreateVehicle(tHash, spawnPos.x, spawnPos.y, spawnPos.z, pHeading, false, false)
        SetEntityAsMissionEntity(trailer, true, true)
        SetVehicleOnGroundProperly(trailer)
        FreezeEntityPosition(trailer, true)
        createdTrailer = true
    end
    CalibTrailer = trailer

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

    -- Criação da Câmera Livre (Blender / Unreal Engine Style)
    local tCoords = GetEntityCoords(trailer)
    local tHeadingRad = math.rad(GetEntityHeading(trailer))
    local camX = tCoords.x - math.sin(tHeadingRad) * 9.0
    local camY = tCoords.y - math.cos(tHeadingRad) * 9.0
    local camZ = tCoords.z + 4.5
    local camRot = vector3(-18.0, 0.0, GetEntityHeading(trailer))
    local calibCam = CreateCameraWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, camZ, camRot.x, camRot.y, camRot.z, 55.0, true, 2)
    SetCamActive(calibCam, true)
    RenderScriptCams(true, true, 600, true, true)

    -- Ativa modo cursor e inicializa Gizmo em Translação
    EnterCursorMode()
    CreateThread(function()
        Wait(50)
        ExecuteCommand('+gizmoTranslation')
        Wait(10)
        ExecuteCommand('-gizmoTranslation')
    end)

    local isGizmoCursorActive = false

    lib.notify({
        title = 'Gizmo 3D & Câmera Livre Ativos',
        description = 'Teclado [WASD] voa a câmera livre.\n[SEGURE ALT] para ativar o mouse e arrastar o Gizmo.',
        type = 'info',
        duration = 7000
    })

    -- LOOP PRINCIPAL DE GIZMO E FREECAM
    CreateThread(function()
        while IsCalibrating do
            Wait(0)

            -- Desabilita ações do ped
            DisableControlAction(0, 24, true)  -- Attack / Left Click
            DisableControlAction(0, 25, true)  -- Aim / Right Click
            DisableControlAction(0, 30, true)  -- Move LR
            DisableControlAction(0, 31, true)  -- Move UD
            DisableControlAction(0, 32, true)  -- W
            DisableControlAction(0, 33, true)  -- S
            DisableControlAction(0, 34, true)  -- A
            DisableControlAction(0, 35, true)  -- D
            DisableControlAction(0, 44, true)  -- Cover (Q)
            DisableControlAction(0, 38, true)  -- E
            DisableControlAction(0, 45, true)  -- R
            DisableControlAction(0, 245, true) -- T
            DisableControlAction(0, 19, true)  -- Left Alt
            DisablePlayerFiring(PlayerId(), true)

            -- CONTROLE DE CURSOR vs MOUSE LOOK VIA TECLA ALT (HOLD)
            local isAltHeld = IsDisabledControlPressed(0, 19) or IsControlPressed(0, 19)
            if isAltHeld then
                if not isGizmoCursorActive then
                    isGizmoCursorActive = true
                    SetNuiFocus(true, true)
                    SetNuiFocusKeepInput(true)
                end
            else
                if isGizmoCursorActive then
                    isGizmoCursorActive = false
                    SetNuiFocus(false, false)
                end

                -- Rotação de câmera suave pelo mouse (somente quando ALT não estiver pressionado)
                DisableControlAction(0, 1, true) -- Look LR
                DisableControlAction(0, 2, true) -- Look UD
                local mouseX = GetDisabledControlNormal(0, 1)
                local mouseY = GetDisabledControlNormal(0, 2)
                camRot = camRot - vector3(mouseY * 5.0, 0.0, mouseX * 5.0)
                camRot = vector3(math.min(math.max(camRot.x, -85.0), 85.0), 0.0, camRot.z % 360.0)
                SetCamRot(calibCam, camRot.x, camRot.y, camRot.z, 2)
            end

            -- VOO DA CÂMERA LIVRE VIA TECLADO (WASD / Space / LCtrl / Shift) — SEMPRE ATIVO
            local radP = math.rad(camRot.x)
            local radY = math.rad(camRot.z)
            local fwd = vector3(-math.sin(radY) * math.cos(radP), math.cos(radY) * math.cos(radP), math.sin(radP))
            local rgt = vector3(math.cos(radY), math.sin(radY), 0.0)
            local up = vector3(0.0, 0.0, 1.0)

            local spd = 0.16
            if IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21) then spd = 0.45 end -- Shift (Rápido)

            local moved = false
            local camPos = GetCamCoord(calibCam)
            if IsDisabledControlPressed(0, 32) or IsControlPressed(0, 32) then camPos = camPos + fwd * spd; moved = true end -- W
            if IsDisabledControlPressed(0, 33) or IsControlPressed(0, 33) then camPos = camPos - fwd * spd; moved = true end -- S
            if IsDisabledControlPressed(0, 34) or IsControlPressed(0, 34) then camPos = camPos - rgt * spd; moved = true end -- A
            if IsDisabledControlPressed(0, 35) or IsControlPressed(0, 35) then camPos = camPos + rgt * spd; moved = true end -- D
            if IsDisabledControlPressed(0, 22) or IsControlPressed(0, 22) or IsDisabledControlPressed(0, 203) or IsControlPressed(0, 203) then camPos = camPos + up * spd; moved = true end -- Space
            if IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36) then camPos = camPos - up * spd; moved = true end -- LCtrl
            if moved then
                SetCamCoord(calibCam, camPos.x, camPos.y, camPos.z)
            end

            -- ALTERNÂNCIA DE MODOS DO GIZMO COM AS TECLAS T E R
            if IsDisabledControlJustPressed(0, 245) or IsControlJustPressed(0, 245) then -- T
                ExecuteCommand('+gizmoTranslation')
                Wait(10)
                ExecuteCommand('-gizmoTranslation')
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Translação (Setas)', type = 'info', duration = 1200 })
            elseif IsDisabledControlJustPressed(0, 45) or IsControlJustPressed(0, 45) then -- R
                ExecuteCommand('+gizmoRotation')
                Wait(10)
                ExecuteCommand('-gizmoRotation')
                lib.notify({ title = 'Gizmo 3D', description = 'Modo: Rotação (Anéis)', type = 'info', duration = 1200 })
            end

            -- RENDERIZAÇÃO E MANIPULAÇÃO DO GIZMO NATIVO FIVEM (0xEB2EDCA2)
            if CalibGhost and DoesEntityExist(CalibGhost) then
                local matrixBuffer = makeEntityMatrix(CalibGhost)
                local changed = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'AustGizmo', Citizen.ReturnResultAnyway())
                if changed then
                    applyEntityMatrix(CalibGhost, matrixBuffer)
                end
            end

            -- CÁLCULO DAS COORDENADAS RELATIVAS AO REBOQUE (BONE 0)
            if CalibGhost and DoesEntityExist(CalibGhost) and CalibTrailer and DoesEntityExist(CalibTrailer) then
                local gCoords = GetEntityCoords(CalibGhost)
                local relOffset = GetOffsetFromEntityGivenWorldCoords(CalibTrailer, gCoords.x, gCoords.y, gCoords.z)
                local gRot = GetEntityRotation(CalibGhost, 2)
                local tRot = GetEntityRotation(CalibTrailer, 2)
                local relHeading = (gRot.z - tRot.z) % 360.0
                CurrentOffsets = { x = relOffset.x, y = relOffset.y, z = relOffset.z, heading = relHeading }
            end

            -- HUD INFORMATIVO NA TELA
            local targetLabel = CalibParams.isForklift and '~y~Empilhadeira (Tie-Down)~s~' or ('~y~Palete Slot %d~s~'):format(CalibParams.slotIndex)
            local modeStatus = isAltHeld and '~g~[CURSOR GIZMO ATIVO]~s~' or '~b~[CÂMERA LIVRE]~s~'
            local hudText = ('~g~[GIZMO 3D & FREECAM]~s~ %s\n' ..
                'Trailer: ~w~%s~s~ | Alvo: %s\n' ..
                'Offset: ~b~X: %.3f  |  Y: %.3f  |  Z: %.3f~s~  |  Rot: ~b~%.1f°~s~\n' ..
                '~w~[WASD/Space/Ctrl] Voo Livre  |  [Shift] Acelera\n' ..
                '~y~[SEGURE ALT]~w~ Ativa Mouse para Arrastar o Gizmo\n' ..
                '[T] Setas Translação  |  [R] Anéis Rotação\n' ..
                '~g~[ENTER] Salvar & Próximo Slot~s~  |  ~r~[BACKSPACE] Finalizar~s~'):format(
                modeStatus,
                CalibParams.trailerModel, targetLabel,
                CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z, CurrentOffsets.heading
            )

            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.36, 0.36)
            SetTextColour(255, 255, 255, 230)
            SetTextDropshadow(1, 0, 0, 0, 200)
            SetTextEdge(1, 0, 0, 0, 250)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(hudText)
            DrawText(0.015, 0.62)

            -- SALVAMENTO E FLUXO CONTÍNUO (SEAMLESS SEQUENCING) COM ENTER
            if IsControlJustPressed(0, 18) or IsControlJustPressed(0, 201) or IsDisabledControlJustPressed(0, 18) or IsDisabledControlJustPressed(0, 201) then
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

                -- 3. Transição contínua
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
                    end
                else
                    -- Slot da empilhadeira finalizado! Ciclo completo!
                    lib.notify({
                        title = 'Calibração Concluída!',
                        description = 'Configuração completa de slots e empilhadeira gravada com sucesso!',
                        type = 'success',
                        duration = 6000
                    })
                    OffsetEditor.StopCalibration(createdTrailer, calibCam)
                    SendNUIMessage({
                        action = 'admin_restore',
                        savedSlot = CalibParams.slotIndex,
                        isForklift = CalibParams.isForklift,
                        trailerModel = CalibParams.trailerModel
                    })
                    SetNuiFocus(true, true)
                    break
                end
            end

            -- CANCELAMENTO COM BACKSPACE / ESC
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
                OffsetEditor.StopCalibration(createdTrailer, calibCam)
                SendNUIMessage({ action = 'admin_restore' })
                SetNuiFocus(true, true)
                lib.notify({ title = 'Calibração', description = 'Edição finalizada.', type = 'info' })
                break
            end
        end
    end)
end

function OffsetEditor.StopCalibration(deleteTrailer, cam)
    IsCalibrating = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    LeaveCursorMode()
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
