-- =======================================================================
-- AUST_trucker — client/zones.lua
-- Sistema de Zonas, Pontos (ox_lib.points) e Alvos (ox_target)
-- Padrão QBOX / OneSync — Fusão Cirúrgica (oConteneur + oForklift)
-- =======================================================================

local Zones = {}
local activePoints = {}
local activeTargets = {}
local activeDeliveryZone = nil

-- Helper assíncrono seguro com timeout: aguarda entidade sincronizar via NetID
function Zones.WaitForNetEntity(netId, timeout)
    if not netId or netId == 0 then return 0 end
    timeout = timeout or 6000
    local start = GetGameTimer()
    while not NetworkDoesNetworkIdExist(netId) do
        if GetGameTimer() - start > timeout then return 0 end
        Wait(50)
    end
    local ent = NetworkGetEntityFromNetworkId(netId)
    while not DoesEntityExist(ent) do
        if GetGameTimer() - start > timeout then return 0 end
        Wait(50)
        ent = NetworkGetEntityFromNetworkId(netId)
    end
    return ent
end

-- Limpa todas as zonas, pontos e targets de contrato ativos
function Zones.Cleanup()
    for _, pt in pairs(activePoints) do
        if pt and pt.remove then pcall(function() pt:remove() end) end
    end
    activePoints = {}

    for _, targetData in ipairs(activeTargets) do
        if targetData.entity and DoesEntityExist(targetData.entity) then
            pcall(function() exports.ox_target:removeLocalEntity(targetData.entity, targetData.names) end)
        end
    end
    activeTargets = {}

    if activeDeliveryZone and activeDeliveryZone.remove then
        pcall(function() activeDeliveryZone:remove() end)
        activeDeliveryZone = nil
    end

    if lib and lib.hideTextUI then
        lib.hideTextUI()
    end
end

-- =======================================================================
-- ESTADO 2: INSPEÇÃO DE VEÍCULO (Vistoria de Pátio Obrigatória)
-- =======================================================================
function Zones.SetupVehicleInspection(truckEnt, jobId)
    if not truckEnt or not DoesEntityExist(truckEnt) then return end

    local inspectionDone = false
    local targetNames = { 'truck_inspect_wheel', 'truck_inspect_door' }

    exports.ox_target:addLocalEntity(truckEnt, {
        {
            name = 'truck_inspect_wheel',
            bones = { 'wheel_lf', 'wheel_rf' },
            icon = 'fa-solid fa-wrench',
            label = 'Inspecionar Pneus e Freios',
            canInteract = function()
                return not inspectionDone
            end,
            onSelect = function()
                local ok = lib.progressBar({
                    duration = 3500,
                    label = 'Realizando vistoria nos pneus e estepe...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
                })
                if ok then
                    lib.notify({
                        title = 'Pneus Inspecionados',
                        description = 'Pressão e banda de rodagem conformes! Verifique a porta do motorista.',
                        type = 'inform'
                    })
                end
            end
        },
        {
            name = 'truck_inspect_door',
            bones = { 'door_dside_f', 'door_pside_f' },
            icon = 'fa-solid fa-clipboard-check',
            label = 'Validar Cabine e Retirar Chave',
            canInteract = function()
                return not inspectionDone
            end,
            onSelect = function()
                local ok = lib.progressBar({
                    duration = 3000,
                    label = 'Checando documentação e retirando as chaves...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'mp_common', clip = 'givetake2_a' }
                })
                if ok then
                    inspectionDone = true
                    pcall(function() exports.ox_target:removeLocalEntity(truckEnt, targetNames) end)
                    TriggerServerEvent('aurp_trucker:server:vehicleInspected', jobId)
                end
            end
        }
    })

    table.insert(activeTargets, { entity = truckEnt, names = targetNames })
end

-- =======================================================================
-- ESTADO 3: CARREGAMENTO FÍSICO DINÂMICO (Handler & Forklift via lib.points)
-- =======================================================================
function Zones.SetupPhysicalLoading(data)
    if not data or not data.jobId then return end

    local pCfg = Config.PhysicalLoading or {}
    local isContainer = data.isContainer
    local isForklift = data.isForklift

    local machineEnt = Zones.WaitForNetEntity(data.machineNetId, 6000)
    local targetTrailer = Zones.WaitForNetEntity(data.trailerNetId, 6000)
    local targetTruck = Zones.WaitForNetEntity(data.truckNetId, 6000)

    -- -------------------------------------------------------------------
    -- MODO HANDLER (oConteneur) — GRUA PORTUÁRIA (Bone frame_2)
    -- -------------------------------------------------------------------
    if isContainer and pCfg.Handler then
        local hCfg = pCfg.Handler
        local containerEnt = Zones.WaitForNetEntity(data.containerNetId, 6000)

        if containerEnt ~= 0 and DoesEntityExist(containerEnt) then
            PlaceObjectOnGroundProperly(containerEnt)
            SetEntityCollision(containerEnt, true, true)
        end

        local loadingCenter = hCfg.ContainerStagingCoords and vector3(hCfg.ContainerStagingCoords.x, hCfg.ContainerStagingCoords.y, hCfg.ContainerStagingCoords.z) or vector3(1258.50, -3120.00, 5.80)

        -- Criação de ponto ox_lib.points com raio de 40m para performance zero
        activePoints['handler_loading'] = lib.points.new({
            coords = loadingCenter,
            distance = 45.0,
            onEnter = function()
                lib.notify({
                    title = 'Pátio de Contêineres',
                    description = 'Opere a Grua Handler: alinhe sobre o contêiner e pressione [G] para içar na grua.',
                    type = 'inform'
                })
            end,
            nearby = function(self)
                local curVeh = cache.vehicle
                if not curVeh or GetEntityModel(curVeh) ~= joaat(hCfg.VehicleModel or 'handler') then
                    return
                end

                local craneBone = GetEntityBoneIndexByName(curVeh, hCfg.CraneBone or 'frame_2')
                local cranePos = GetWorldPositionOfEntityBone(curVeh, craneBone)
                local attached = IsEntityAttachedToEntity(containerEnt, curVeh)

                if not attached then
                    if DoesEntityExist(containerEnt) then
                        local dist = #(cranePos - GetEntityCoords(containerEnt))
                        if dist <= (hCfg.InteractionRadius or 5.0) then
                            lib.showTextUI('[G] Acoplar Contêiner na Grua')
                            if IsControlJustPressed(0, 47) then -- Tecla G (INPUT_DETONATE)
                                lib.hideTextUI()
                                AttachEntityToEntity(containerEnt, curVeh, craneBone, 0.0, 1.78, -2.5, 0.0, 0.0, 90.0, false, false, true, false, 0, true)
                                PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)
                                lib.notify({
                                    title = 'Contêiner Içado',
                                    description = 'Posicione sobre a carreta prancha e pressione [G] para travar.',
                                    type = 'success'
                                })
                            end
                        else
                            lib.hideTextUI()
                        end
                    end
                else
                    -- Já içado: validar aproximação da carreta trflat
                    if targetTrailer ~= 0 and DoesEntityExist(targetTrailer) then
                        local trCoords = GetEntityCoords(targetTrailer)
                        local distTr = #(cranePos - trCoords)
                        if distTr <= 7.0 then
                            lib.showTextUI('[G] Travar Contêiner na Carreta')
                            if IsControlJustPressed(0, 47) then
                                lib.hideTextUI()
                                DetachEntity(containerEnt, false, true)
                                AttachEntityToEntity(containerEnt, targetTrailer, hCfg.TrailerBone or 0, 0.0, 0.0, 0.35, 0.0, 0.0, 0.0, 0, false, false, false, 0, true)
                                PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                                TriggerServerEvent('aurp_trucker:server:cargoItemAttached', data.jobId, 1, 1)
                                if self and self.remove then self:remove() end
                            end
                        else
                            lib.hideTextUI()
                        end
                    end
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
        return
    end

    -- -------------------------------------------------------------------
    -- MODO FORKLIFT (oForklift) — EMPILHADEIRA (Bone 3)
    -- -------------------------------------------------------------------
    if isForklift and pCfg.Forklift then
        local fCfg = pCfg.Forklift
        local palletEntities = {}
        for _, netId in ipairs(data.palletNetIds or {}) do
            local pEnt = Zones.WaitForNetEntity(netId, 6000)
            if pEnt ~= 0 and DoesEntityExist(pEnt) then
                PlaceObjectOnGroundProperly(pEnt)
                SetEntityCollision(pEnt, true, true)
                table.insert(palletEntities, pEnt)
            end
        end

        local loadingCenter = vector3(1262.50, -3125.00, 5.80)
        local loadedCount = 0
        local totalRequired = #palletEntities > 0 and #palletEntities or (data.requiredCount or 3)
        local attachedPallet = nil

        activePoints['forklift_loading'] = lib.points.new({
            coords = loadingCenter,
            distance = 45.0,
            onEnter = function()
                lib.notify({
                    title = 'Pátio de Paletes',
                    description = 'Opere a empilhadeira: erga os paletes nos garfos com [G] e acondicione no compartimento.',
                    type = 'inform'
                })
            end,
            nearby = function(self)
                local curVeh = cache.vehicle
                if not curVeh or GetEntityModel(curVeh) ~= joaat(fCfg.VehicleModel or 'forklift') then
                    return
                end

                local forkPos = GetOffsetFromEntityInWorldCoords(curVeh, 0.0, 1.8, 0.0)

                if not attachedPallet then
                    -- Buscar palete não acoplado mais próximo
                    local closestPallet, closestDist = nil, 4.0
                    for _, pEnt in ipairs(palletEntities) do
                        if DoesEntityExist(pEnt) and not IsEntityAttached(pEnt) then
                            local d = #(forkPos - GetEntityCoords(pEnt))
                            if d < closestDist then
                                closestDist = d
                                closestPallet = pEnt
                            end
                        end
                    end

                    if closestPallet then
                        lib.showTextUI('[G] Carregar Palete nos Garfos')
                        if IsControlJustPressed(0, 47) then
                            lib.hideTextUI()
                            AttachEntityToEntity(closestPallet, curVeh, fCfg.ForkBoneIndex or 3, 0.04001219901977, 1.1927500134294, -0.51866756839922, 0.0, 0.0, -0.17032877993561, false, false, false, false, 2, true)
                            attachedPallet = closestPallet
                            PlaySoundFrontend(-1, "ATTACH_CARGO", "HUD_AWARDS", 0)
                            lib.notify({
                                title = 'Palete Içado',
                                description = 'Leve até a traseira do caminhão/reboque e pressione [G] para acomodar.',
                                type = 'inform'
                            })
                        end
                    else
                        lib.hideTextUI()
                    end
                else
                    -- Já içado: depositar no compartimento de carga do caminhão/reboque
                    local depositTarget = (targetTrailer ~= 0 and DoesEntityExist(targetTrailer)) and targetTrailer or targetTruck
                    if depositTarget ~= 0 and DoesEntityExist(depositTarget) then
                        local bedPos = GetOffsetFromEntityInWorldCoords(depositTarget, 0.0, -3.5, 0.5)
                        local distBed = #(forkPos - bedPos)
                        if distBed <= 5.0 then
                            lib.showTextUI('[G] Acomodar Palete no Compartimento')
                            if IsControlJustPressed(0, 47) then
                                lib.hideTextUI()
                                DetachEntity(attachedPallet, false, true)
                                AttachEntityToEntity(attachedPallet, depositTarget, fCfg.MuleBone or 0, 0.13276851850662, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, false, 0, true)
                                attachedPallet = nil
                                loadedCount = loadedCount + 1
                                PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", 0)
                                TriggerServerEvent('aurp_trucker:server:cargoItemAttached', data.jobId, loadedCount, totalRequired)
                                if loadedCount >= totalRequired then
                                    if self and self.remove then self:remove() end
                                end
                            end
                        else
                            lib.hideTextUI()
                        end
                    end
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
    end
end

-- =======================================================================
-- ESTADO 4: FIXAÇÃO DE CINTAS & ROMANEIO (Traseira do Reboque)
-- =======================================================================
function Zones.SetupStrapAndManifest(trailerEnt, jobId)
    if not trailerEnt or not DoesEntityExist(trailerEnt) then return end

    local strapped = false
    local targetNames = { 'strap_cargo_manifest' }

    exports.ox_target:addLocalEntity(trailerEnt, {
        {
            name = 'strap_cargo_manifest',
            icon = 'fa-solid fa-lock',
            label = 'Fixar Cintas de Carga & Pegar Romaneio',
            canInteract = function()
                return not strapped
            end,
            onSelect = function()
                local ok = lib.progressBar({
                    duration = 3200,
                    label = 'Passando catracas, fixando cintas e assinando romaneio...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
                })
                if ok then
                    strapped = true
                    pcall(function() exports.ox_target:removeLocalEntity(trailerEnt, targetNames) end)
                    TriggerServerEvent('aurp_trucker:server:strapAndManifest', jobId)
                end
            end
        }
    })

    table.insert(activeTargets, { entity = trailerEnt, names = targetNames })
end

-- =======================================================================
-- ESTADO 5: ENTREGA E DESCARREGAMENTO (Zona de Destino Final)
-- =======================================================================
function Zones.SetupDeliveryDestination(coords, jobId, trailerEnt)
    if not coords then return end

    local destVec = vector3(coords.x, coords.y, coords.z)
    SetNewWaypoint(destVec.x, destVec.y)

    activePoints['delivery_destination'] = lib.points.new({
        coords = destVec,
        distance = 35.0,
        onEnter = function()
            lib.notify({
                title = 'Destino Atingido',
                description = 'Estacione o caminhão na vaga de descarregamento e solte as travas de segurança.',
                type = 'success'
            })
        end,
        nearby = function(self)
            local pCoords = cache.coords
            local dist = #(pCoords - destVec)

            if dist <= 6.0 then
                lib.showTextUI('[E] Descarregar e Entregar Carga')
                if IsControlJustPressed(0, 38) then -- Tecla E
                    lib.hideTextUI()
                    local ok = lib.progressBar({
                        duration = 4000,
                        label = 'Conferindo nota fiscal e descarregando reboque...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = 'mp_common', clip = 'givetake2_a' }
                    })
                    if ok then
                        if self and self.remove then self:remove() end
                        TriggerServerEvent('aurp_trucker:server:completeLCContract', jobId, true)
                    end
                end
            else
                lib.hideTextUI()
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
end

-- Exporta o módulo para o escopo global
_ENV.LogisticsZones = Zones
return Zones
