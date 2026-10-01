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
    SetEntityAlpha(ghost, 185, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)

    CalibGhost = ghost
    return ghost
end

-- ============================================================
-- RENDERIZAÇÃO DE GIZMO 3D VISUAL (RGB AXES & ROTATION RING)
-- ============================================================

local function DrawVisualGizmo(ghost, trailer)
    if not ghost or not DoesEntityExist(ghost) or not trailer or not DoesEntityExist(trailer) then return end

    local gCoords = GetEntityCoords(ghost)
    local tHeading = GetEntityHeading(trailer)
    local tRad = math.rad(tHeading)

    -- Vetores unitários alinhados com o reboque
    local tFwd = vector3(-math.sin(tRad), math.cos(tRad), 0.0)
    local tRgt = vector3(math.cos(tRad), math.sin(tRad), 0.0)
    local tUp  = vector3(0.0, 0.0, 1.0)

    local axisLen = 1.1

    -- Eixo X (Vermelho): Lateral do Reboque (Esquerda / Direita)
    local xEnd = gCoords + tRgt * axisLen
    DrawLine(gCoords.x, gCoords.y, gCoords.z, xEnd.x, xEnd.y, xEnd.z, 240, 50, 50, 240)
    DrawMarker(28, xEnd.x, xEnd.y, xEnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.07, 0.07, 0.07, 240, 50, 50, 220, false, false, 2, false, nil, nil, false)

    -- Eixo Y (Verde): Comprimento do Reboque (Frente / Trás)
    local yEnd = gCoords + tFwd * axisLen
    DrawLine(gCoords.x, gCoords.y, gCoords.z, yEnd.x, yEnd.y, yEnd.z, 50, 240, 50, 240)
    DrawMarker(28, yEnd.x, yEnd.y, yEnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.07, 0.07, 0.07, 50, 240, 50, 220, false, false, 2, false, nil, nil, false)

    -- Eixo Z (Azul): Altura do Reboque (Cima / Baixo)
    local zEnd = gCoords + tUp * axisLen
    DrawLine(gCoords.x, gCoords.y, gCoords.z, zEnd.x, zEnd.y, zEnd.z, 60, 150, 255, 240)
    DrawMarker(28, zEnd.x, zEnd.y, zEnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.07, 0.07, 0.07, 60, 150, 255, 220, false, false, 2, false, nil, nil, false)

    -- Anel de Rotação (Amarelo / Dourado) na base
    DrawMarker(23, gCoords.x, gCoords.y, gCoords.z - 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.25, 1.25, 0.04, 255, 215, 0, 140, false, false, 2, false, nil, nil, false)
end

-- ============================================================
-- FERRAMENTA VISUAL IN-GAME DE OFFSETS (FREECAM & 3D GIZMO)
-- ============================================================

function OffsetEditor.StartCalibration(trailerModel, slotIndex, isForklift, propModel)
    if IsCalibrating then return end
    IsCalibrating = true

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

    -- Fecha NUI temporariamente para liberar tela e controles 3D
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

    lib.notify({
        title = 'Calibração 3D Ativa',
        description = 'WASD + Mouse: Voar câmera livre.\nSetas + Q/E + R/F: Posicionar a carga.\nENTER: Salvar e Avançar.',
        type = 'info',
        duration = 8000
    })

    -- LOOP PRINCIPAL DE CONTROLES, GIZMO E FREECAM
    CreateThread(function()
        while IsCalibrating do
            Wait(0)

            -- Desabilita ações normais do jogo para isolar o controle da câmera e da carga
            DisableAllControlActions(0)

            -- 1. ROTAÇÃO DA CÂMERA LIVRE PELO MOUSE (LOOK AROUND)
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

            -- 2. VOO LIVRE DA CÂMERA (WASD / Space / LCtrl)
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
            if IsDisabledControlPressed(0, 19) then camSpeed = 0.04 end -- LAlt (Precision / Voo Lento)

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

            -- 3. MANIPULAÇÃO DO OBJETO FANTASMA (SETAS + Q/E + R/F)
            local moveStep = 0.02
            local rotStep = 1.0

            if IsDisabledControlPressed(0, 21) then -- Shift (Rápido)
                moveStep = 0.08
                rotStep = 3.5
            elseif IsDisabledControlPressed(0, 19) then -- Alt (Micro-ajuste milimétrico)
                moveStep = 0.003
                rotStep = 0.2
            end

            local objChanged = false

            -- Setas Cima / Baixo: Eixo Y (Frente / Trás do reboque)
            if IsDisabledControlPressed(0, 172) or IsDisabledControlPressed(0, 27) then -- Seta Cima
                CurrentOffsets.y = CurrentOffsets.y + moveStep
                objChanged = true
            end
            if IsDisabledControlPressed(0, 173) then -- Seta Baixo
                CurrentOffsets.y = CurrentOffsets.y - moveStep
                objChanged = true
            end

            -- Setas Esquerda / Direita: Eixo X (Lateral do reboque)
            if IsDisabledControlPressed(0, 174) then -- Seta Esquerda
                CurrentOffsets.x = CurrentOffsets.x - moveStep
                objChanged = true
            end
            if IsDisabledControlPressed(0, 175) then -- Seta Direita
                CurrentOffsets.x = CurrentOffsets.x + moveStep
                objChanged = true
            end

            -- Q / E: Eixo Z (Altura / Cima / Baixo)
            if IsDisabledControlPressed(0, 44) then -- Q (Baixo)
                CurrentOffsets.z = CurrentOffsets.z - moveStep
                objChanged = true
            end
            if IsDisabledControlPressed(0, 38) then -- E (Cima)
                CurrentOffsets.z = CurrentOffsets.z + moveStep
                objChanged = true
            end

            -- R / F: Rotação (Heading)
            if IsDisabledControlPressed(0, 45) then -- R (Anti-horário)
                CurrentOffsets.heading = (CurrentOffsets.heading - rotStep) % 360.0
                objChanged = true
            end
            if IsDisabledControlPressed(0, 23) or IsDisabledControlPressed(0, 49) then -- F (Horário)
                CurrentOffsets.heading = (CurrentOffsets.heading + rotStep) % 360.0
                objChanged = true
            end

            -- Aplica nova posição e rotação ao fantasma no mundo
            if objChanged and CalibGhost and DoesEntityExist(CalibGhost) and CalibTrailer and DoesEntityExist(CalibTrailer) then
                local worldPos = GetOffsetFromEntityInWorldCoords(CalibTrailer, CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z)
                SetEntityCoordsNoOffset(CalibGhost, worldPos.x, worldPos.y, worldPos.z, false, false, false)
                local tHeading = GetEntityHeading(CalibTrailer)
                SetEntityHeading(CalibGhost, (tHeading + CurrentOffsets.heading) % 360.0)
            end

            -- 4. RENDERIZAÇÃO DO GIZMO 3D VISUAL (EIXOS RGB + ANEL DE ROTAÇÃO)
            DrawVisualGizmo(CalibGhost, CalibTrailer)

            -- 5. HUD INFORMATIVO NA TELA
            local targetLabel = CalibParams.isForklift and '~y~Empilhadeira (Slot Final)~s~' or ('~y~Palete Slot %d~s~'):format(CalibParams.slotIndex)
            local speedLabel = IsDisabledControlPressed(0, 21) and '~r~[TURBO]~s~' or (IsDisabledControlPressed(0, 19) and '~y~[PRECISÃO MILIMÉTRICA]~s~' or '~b~[NORMAL]~s~')

            local hudText = ('~g~[CALIBRAÇÃO 3D & FREECAM]~s~ %s\n' ..
                'Trailer: ~w~%s~s~  |  Alvo: %s\n' ..
                'Offset: ~b~X: %.3f  |  Y: %.3f  |  Z: %.3f~s~  |  Rot: ~b~%.1f°~s~\n' ..
                '~w~[WASD] Voo Livre  |  [Mouse] Girar Câmera  |  [Space/LCtrl] Subir/Descer\n' ..
                '~y~[Setas ↑↓←→] Mover Carga (X/Y)  |  [Q / E] Altura (Z)  |  [R / F] Girar\n' ..
                '~c~[Shift] Turbo  |  [Alt] Micro-ajuste milimétrico~s~\n' ..
                '~g~[ENTER] Salvar & Próximo Slot~s~  |  ~r~[BACKSPACE] Finalizar~s~'):format(
                speedLabel,
                CalibParams.trailerModel, targetLabel,
                CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z, CurrentOffsets.heading
            )

            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.35, 0.35)
            SetTextColour(255, 255, 255, 230)
            SetTextDropshadow(1, 0, 0, 0, 200)
            SetTextEdge(1, 0, 0, 0, 250)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(hudText)
            DrawText(0.015, 0.65)

            -- 6. SALVAMENTO E FLUXO CONTÍNUO (SEAMLESS SEQUENCING) COM ENTER
            if IsDisabledControlJustPressed(0, 18) or IsDisabledControlJustPressed(0, 201) then
                -- Dispara salvamento no banco de dados
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

                -- Determina o limite de slots de palete
                local maxPallets = 6
                local curHash = joaat(CalibParams.trailerModel)
                if Config.TrailerSlots and Config.TrailerSlots[curHash] and Config.TrailerSlots[curHash].pallets then
                    local pCount = #Config.TrailerSlots[curHash].pallets
                    if pCount > maxPallets then maxPallets = pCount end
                end

                -- Transição contínua entre slots
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

            -- 7. CANCELAMENTO OU FINALIZAÇÃO ANTECIPADA COM BACKSPACE / ESC
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
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
