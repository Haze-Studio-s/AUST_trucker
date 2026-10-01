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

    -- Carrega o offset inicial da tabela atual
    local hash = joaat(trailerModel)
    local curVec = nil
    if Config.TrailerSlots and Config.TrailerSlots[hash] then
        if isForklift then
            curVec = Config.TrailerSlots[hash].forklift
        elseif Config.TrailerSlots[hash].pallets then
            curVec = Config.TrailerSlots[hash].pallets[slotIndex]
        end
    end

    if curVec then
        CurrentOffsets = { x = curVec.x, y = curVec.y, z = curVec.z, heading = 0.0 }
    else
        CurrentOffsets = { x = 0.0, y = isForklift and -5.5 or (4.5 - (slotIndex - 1) * 1.5), z = isForklift and 0.4 or 0.05, heading = 0.0 }
    end

    -- Fecha NUI temporariamente para focar na tela 3D
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'admin_minimize' })

    local ped = cache.ped or PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local pHeading = GetEntityHeading(ped)

    -- Verifica se já há um trailer próximo ou spawna um para visualização
    local tHash = joaat(trailerModel)
    lib.requestModel(tHash)

    local trailer = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 15.0, tHash, 70)
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

    -- Spawna o objeto holográfico fantasma
    local gHash = joaat(propModel)
    lib.requestModel(gHash)
    local ghost = nil
    if isForklift then
        local tPos = GetEntityCoords(trailer)
        ghost = CreateVehicle(gHash, tPos.x, tPos.y, tPos.z, pHeading, false, false)
    else
        local tPos = GetEntityCoords(trailer)
        ghost = CreateObject(gHash, tPos.x, tPos.y, tPos.z, false, false, false)
    end

    SetEntityAsMissionEntity(ghost, true, true)
    SetEntityAlpha(ghost, 175, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)

    AttachEntityToEntity(
        ghost, trailer, 0,
        CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z,
        0.0, 0.0, CurrentOffsets.heading,
        false, false, false, false, 0, true
    )
    CalibGhost = ghost
    IsCalibrating = true

    lib.notify({
        title = 'Modo Calibração 3D Ativo',
        description = ('Calibrando %s (%s %d).\nUse [WASD], [Q/E], [Z/C]. [ENTER] Salva | [BACKSPACE] Cancela'):format(
            trailerModel, isForklift and 'Empilhadeira' or 'Palete Slot', slotIndex
        ),
        type = 'info',
        duration = 7000
    })

    -- Loop de controle e renderização HUD
    CreateThread(function()
        while IsCalibrating do
            Wait(0)

            -- Modificadores de sensibilidade
            local step = 0.02
            local rotStep = 2.0
            if IsControlPressed(0, 21) then -- SHIFT: Rápido
                step = 0.10
                rotStep = 10.0
            elseif IsControlPressed(0, 19) then -- ALT: Precisão cirúrgica
                step = 0.005
                rotStep = 0.5
            end

            local changed = false

            -- Movimentação X (Esquerda / Direita)
            if IsControlPressed(0, 34) then -- A
                CurrentOffsets.x = CurrentOffsets.x - step
                changed = true
            elseif IsControlPressed(0, 35) then -- D
                CurrentOffsets.x = CurrentOffsets.x + step
                changed = true
            end

            -- Movimentação Y (Frente / Trás na caçamba)
            if IsControlPressed(0, 32) then -- W
                CurrentOffsets.y = CurrentOffsets.y + step
                changed = true
            elseif IsControlPressed(0, 33) then -- S
                CurrentOffsets.y = CurrentOffsets.y - step
                changed = true
            end

            -- Altura Z (Cima / Baixo)
            if IsControlPressed(0, 44) then -- Q (Sobe)
                CurrentOffsets.z = CurrentOffsets.z + step
                changed = true
            elseif IsControlPressed(0, 38) then -- E (Desce)
                CurrentOffsets.z = CurrentOffsets.z - step
                changed = true
            end

            -- Rotação Heading (Z / C)
            if IsControlPressed(0, 20) then -- Z (Gira Esquerda)
                CurrentOffsets.heading = (CurrentOffsets.heading - rotStep) % 360
                changed = true
            elseif IsControlPressed(0, 26) then -- C (Gira Direita)
                CurrentOffsets.heading = (CurrentOffsets.heading + rotStep) % 360
                changed = true
            end

            if changed and CalibGhost and CalibTrailer then
                AttachEntityToEntity(
                    CalibGhost, CalibTrailer, 0,
                    CurrentOffsets.x, CurrentOffsets.y, CurrentOffsets.z,
                    0.0, 0.0, CurrentOffsets.heading,
                    false, false, false, false, 0, true
                )
            end

            -- RENDERIZAÇÃO DO HUD FLUTUANTE DE AJUSTE
            local hudText = ('~g~[CALIBRAÇÃO DE REBOQUE 3D]~s~\n' ..
                'Trailer: ~y~%s~s~ | Alvo: ~y~%s~s~\n' ..
                'Offset: ~b~X: %.3f  |  Y: %.3f  |  Z: %.3f~s~\n' ..
                'Rotação: ~b~%.1f°~s~\n' ..
                '~w~[WASD] Mover X/Y  |  [Q/E] Altura Z  |  [Z/C] Girar\n' ..
                '[SHIFT] Veloz  |  [ALT] Fino  |  ~g~[ENTER] Salvar~s~  |  ~r~[BACKSPACE] Sair~s~'):format(
                trailerModel, isForklift and 'Empilhadeira' or ('Slot ' .. slotIndex),
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
            DrawText(0.015, 0.65)

            -- CONFIRMAÇÃO COM ENTER
            if IsControlJustPressed(0, 18) or IsControlJustPressed(0, 201) then -- ENTER
                TriggerServerEvent('aurp_trucker:server:adminSaveTrailerOffset', {
                    trailerModel = CalibParams.trailerModel,
                    slotIndex = CalibParams.slotIndex,
                    isForklift = CalibParams.isForklift,
                    x = CurrentOffsets.x,
                    y = CurrentOffsets.y,
                    z = CurrentOffsets.z,
                    heading = CurrentOffsets.heading
                })

                OffsetEditor.StopCalibration(createdTrailer)
                SendNUIMessage({ action = 'admin_restore' })
                SetNuiFocus(true, true)
                break
            end

            -- CANCELAMENTO COM BACKSPACE
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then -- BACKSPACE / ESC
                OffsetEditor.StopCalibration(createdTrailer)
                SendNUIMessage({ action = 'admin_restore' })
                SetNuiFocus(true, true)
                lib.notify({ title = 'Calibração', description = 'Edição cancelada.', type = 'warning' })
                break
            end
        end
    end)
end

function OffsetEditor.StopCalibration(deleteTrailer)
    IsCalibrating = false
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

RegisterNetEvent('aurp_trucker:client:adminSyncOffsets', function(trailerModel, slotIndex, isForklift, offsetVec, heading)
    trailerModel = trailerModel:lower()
    local hash = joaat(trailerModel)
    if not Config.TrailerSlots[hash] then
        Config.TrailerSlots[hash] = { pallets = {}, forklift = nil }
    end
    if isForklift then
        Config.TrailerSlots[hash].forklift = offsetVec
    else
        Config.TrailerSlots[hash].pallets[slotIndex] = offsetVec
    end
    print(("^2[AUST_Trucker Client] Offset do reboque %s (Slot %s) sincronizado em tempo real!^7"):format(trailerModel, tostring(slotIndex)))
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
