-- =======================================================================
-- AUST_trucker — client/zones.lua
-- Máquina de Estados: Zonas de Interação, ox_target e ox_lib.points
-- Padrão QBOX / OX: Zero Loops Wait(0), Interações Autorizadas
-- =======================================================================

local Zones = {}
_G.Zones = Zones

local ActivePoints = {}
local ActiveTargetEntities = {}
local ShowingPrompt = false
local ActiveObjectivePoint = nil
local ActiveObjectiveBlip = nil

-- =======================================================================
-- GUIA VISUAL EXCLUSIVO: BLIPS E SETA FLUTUANTE (OX_LIB.POINTS)
-- =======================================================================

local TrackedObjectives = {}

function Zones.Notify(description, notifyType)
    lib.notify({
        title = 'Central Logística',
        description = description,
        type = notifyType or 'info',
        duration = 10000
    })
end

local function ClearObjective(id)
    if not id then
        for _, obj in pairs(TrackedObjectives) do
            if obj.point then pcall(function() obj.point:remove() end) end
            if obj.blip and DoesBlipExist(obj.blip) then RemoveBlip(obj.blip) end
            obj.active = false
        end
        TrackedObjectives = {}
        return
    end

    if TrackedObjectives[id] then
        local obj = TrackedObjectives[id]
        if obj.point then pcall(function() obj.point:remove() end) end
        if obj.blip and DoesBlipExist(obj.blip) then RemoveBlip(obj.blip) end
        obj.active = false
        TrackedObjectives[id] = nil
    end
end
Zones.ClearObjective = ClearObjective
Zones.ClearAllObjectives = function() ClearObjective(nil) end

local function TrackObjective(id, data)
    if not id or not data then return end
    ClearObjective(id)

    local targetNetId = data.netId
    local targetEntity = data.entity
    local targetCoords = nil
    if data.coords then
        targetCoords = vector3(data.coords.x, data.coords.y, data.coords.z)
    end
    local targetLabel = data.label or "Objetivo"
    local targetSprite = data.sprite or 1
    local targetColor = data.color or 2 -- 2 = Verde oficial do FiveM
    local offsetZ = data.offsetZ or 2.8
    local renderMarker = (data.marker ~= false)
    local hasRoute = (data.route == true)

    local objData = {
        id = id,
        active = true,
        point = nil,
        blip = nil
    }
    TrackedObjectives[id] = objData

    -- Dispara notificação de 10 segundos caso informada
    if data.notify and data.notify ~= '' then
        Zones.Notify(data.notify, data.notifyType or 'info')
    end

    -- 1. Blip exclusivo client-side
    if targetCoords and not targetNetId and not targetEntity then
        local blip = AddBlipForCoord(targetCoords.x, targetCoords.y, targetCoords.z)
        SetBlipSprite(blip, targetSprite)
        SetBlipColour(blip, targetColor)
        SetBlipScale(blip, 0.85)
        if hasRoute then
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, targetColor)
        end
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(targetLabel)
        EndTextCommandSetBlipName(blip)
        objData.blip = blip
    end

    -- 2. Seta Flutuante 3D Verde (DrawMarker 20, 0, 255, 0, 180) via ox_lib.points (0.00ms quando distante)
    if renderMarker then
        local initialPos = targetCoords or vector3(0.0, 0.0, 0.0)
        objData.point = lib.points.new({
            coords = initialPos,
            distance = 80.0,
            nearby = function(self)
                local pos = self.coords
                local ent = targetEntity
                if not ent or not DoesEntityExist(ent) then
                    if targetNetId and targetNetId ~= 0 and NetworkDoesNetworkIdExist(targetNetId) then
                        ent = NetworkGetEntityFromNetworkId(targetNetId)
                    end
                end

                if ent and DoesEntityExist(ent) then
                    pos = GetEntityCoords(ent)
                    self.coords = pos
                end

                -- Chevron / Arrow apontando para baixo flutuando suavemente e rotacionando
                DrawMarker(
                    20,
                    pos.x, pos.y, pos.z + offsetZ,
                    0.0, 0.0, 0.0,
                    180.0, 0.0, 0.0,
                    0.6, 0.6, 0.6,
                    0, 255, 0, 180,
                    true,  -- bobUpAndDown
                    false, -- faceCamera
                    2,
                    true,  -- rotate
                    nil, nil, false
                )
            end
        })
    end

    -- 3. Resolução OneSync para Entidade
    if (targetNetId and targetNetId ~= 0) or (targetEntity and DoesEntityExist(targetEntity)) then
        CreateThread(function()
            local ent = targetEntity
            if not ent or not DoesEntityExist(ent) then
                local waitTimeout = GetGameTimer() + 6000
                while not NetworkDoesNetworkIdExist(targetNetId) and GetGameTimer() < waitTimeout and objData.active do
                    Wait(100)
                end
                if not objData.active then return end
                if NetworkDoesNetworkIdExist(targetNetId) then
                    ent = NetworkGetEntityFromNetworkId(targetNetId)
                end
            end

            if ent and DoesEntityExist(ent) and objData.active then
                if objData.point then
                    objData.point.coords = GetEntityCoords(ent)
                end

                if objData.blip and DoesBlipExist(objData.blip) then
                    RemoveBlip(objData.blip)
                end

                local blip = AddBlipForEntity(ent)
                SetBlipSprite(blip, targetSprite)
                SetBlipColour(blip, targetColor)
                SetBlipScale(blip, 0.85)
                if hasRoute then
                    SetBlipRoute(blip, true)
                    SetBlipRouteColour(blip, targetColor)
                end
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(targetLabel)
                EndTextCommandSetBlipName(blip)
                objData.blip = blip

                -- Sincronização periódica da posição macro à distância
                while objData.active and DoesEntityExist(ent) do
                    if objData.point then
                        objData.point.coords = GetEntityCoords(ent)
                    end
                    Wait(1000)
                end
            end
        end)
    end
end
Zones.TrackObjective = TrackObjective

local function SetObjective(data, label, sprite, color, markerOffsetZ)
    local id = (type(data) == 'table' and data.id) or 'main'
    if type(data) ~= 'table' then
        data = { coords = data, label = label, sprite = sprite, color = color, offsetZ = markerOffsetZ }
    end
    TrackObjective(id, data)
end
Zones.SetObjective = SetObjective

RegisterNetEvent('aust_trucker:client:SetObjective', function(data)
    SetObjective(data)
end)

RegisterNetEvent('aust_trucker:client:ClearObjective', function(id)
    ClearObjective(id)
end)

-- =======================================================================
-- LIMPEZA GERAL DE ZONAS E TARGETS
-- =======================================================================
function Zones.Cleanup()
    ClearObjective()

    for _, pt in pairs(ActivePoints) do
        if pt then pcall(function() pt:remove() end) end
    end
    ActivePoints = {}

    for _, ent in ipairs(ActiveTargetEntities) do
        if ent and DoesEntityExist(ent) then
            pcall(function() exports.ox_target:removeLocalEntity(ent) end)
        end
    end
    ActiveTargetEntities = {}

    if ShowingPrompt then
        lib.hideTextUI()
        ShowingPrompt = false
    end
end

-- =======================================================================
-- ETAPA DE INSPEÇÃO REMOVIDA (LIBERAÇÃO DIRETA)
-- =======================================================================
function Zones.SetupInspection(truck, jobId, onComplete)
    if onComplete then onComplete() end
end

-- =======================================================================
-- ESTADO 3 (SECA): ZONA TRASEIRA DA CARRETA (OX_LIB.POINTS)
-- =======================================================================
function Zones.SetupDryRearZone(trailer, jobId, getJobStateCb, onLoadPallet)
    if not trailer or not DoesEntityExist(trailer) then return end

    local trailerRearOffset = vector3(0.0, -5.5, 0.0)
    local initialCoords = GetOffsetFromEntityInWorldCoords(trailer, trailerRearOffset.x, trailerRearOffset.y, trailerRearOffset.z)

    if ActivePoints['dry_rear'] then
        pcall(function() ActivePoints['dry_rear']:remove() end)
    end

    ActivePoints['dry_rear'] = lib.points.new({
        coords = initialCoords,
        distance = 5.0,
        onExit = function()
            if ShowingPrompt then
                lib.hideTextUI()
                ShowingPrompt = false
            end
        end,
        nearby = function(self)
            if DoesEntityExist(trailer) then
                self.coords = GetOffsetFromEntityInWorldCoords(trailer, trailerRearOffset.x, trailerRearOffset.y, trailerRearOffset.z)
            end

            local isEligible, carriedPallet = false, nil
            if getJobStateCb then
                isEligible, carriedPallet = getJobStateCb()
            end

            if isEligible and carriedPallet and DoesEntityExist(carriedPallet) then
                if not ShowingPrompt then
                    lib.showTextUI('[E] Fixar Palete no Reboque', {
                        position = 'left-center',
                        icon = 'pallet'
                    })
                    ShowingPrompt = true
                end

                if IsControlJustPressed(0, 38) then -- Tecla E
                    lib.hideTextUI()
                    ShowingPrompt = false
                    if onLoadPallet then onLoadPallet() end
                end
            else
                if ShowingPrompt then
                    lib.hideTextUI()
                    ShowingPrompt = false
                end
            end
        end
    })
end

-- =======================================================================
-- ESTADO 4: FIXAÇÃO DE CINTAS E ROMANEIO (OX_TARGET NO REBOQUE)
-- =======================================================================
function Zones.SetupStrappingAndManifest(trailer, jobId, onComplete)
    if not trailer or not DoesEntityExist(trailer) then return end
    table.insert(ActiveTargetEntities, trailer)

    local rearCoords = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -5.5, 0.5)
    Zones.SetObjective(rearCoords, "Fixar Cintas e Romaneio", 479, 3, 2.0)

    exports.ox_target:addLocalEntity(trailer, {
        {
            name = 'strap_cargo_and_sign_manifest',
            icon = 'fa-solid fa-clipboard-check',
            label = 'Fixar Cintas de Carga e Assinar Romaneio',
            distance = 3.5,
            canInteract = function()
                local ped = cache.ped or PlayerPedId()
                return not IsPedInAnyVehicle(ped, false)
            end,
            onSelect = function()
                local anim = (Config.Polarix and Config.Polarix.Strapping and Config.Polarix.Strapping.Animation) or { dict = 'mini@repair', clip = 'fixing_a_ped' }
                local success = lib.progressBar({
                    duration = (Config.Polarix and Config.Polarix.Strapping and Config.Polarix.Strapping.Duration) or 4500,
                    label = 'Fixando cintas de catraca e validando romaneio...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = anim.dict, clip = anim.clip }
                })

                if success then
                    Zones.ClearObjective()
                    if onComplete then onComplete() end
                end
            end
        }
    })

    lib.notify({
        title = 'Carregamento Completo (Estado 4)',
        description = 'Vá a pé até a traseira da carreta para fixar as cintas e assinar o romaneio de carga.',
        type = 'success',
        duration = 9000
    })
end

-- =======================================================================
-- ESTADO 5: DESTINO FINAL & DESCARREGAMENTO (OX_LIB.POINTS)
-- =======================================================================
function Zones.SetupDeliveryPoint(coords, jobId, onUnload)
    if ActivePoints['delivery_dest'] then
        pcall(function() ActivePoints['delivery_dest']:remove() end)
    end

    local destCoords = vector3(coords.x, coords.y, coords.z)
    Zones.SetObjective(destCoords, "Local de Descarregamento", 477, 2, 2.5)

    ActivePoints['delivery_dest'] = lib.points.new({
        coords = destCoords,
        distance = 15.0,
        onEnter = function()
            lib.showTextUI('[E] Descarregar Mercadoria e Concluir Frete')
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        nearby = function()
            if IsControlJustPressed(0, 38) then -- Tecla E
                local ped = cache.ped or PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 then
                    lib.notify({ title = 'Entrega', description = 'Estacione o caminhão e desembarque para descarregar!', type = 'error' })
                    return
                end

                lib.hideTextUI()
                local ok = lib.progressCircle({
                    duration = 6000,
                    position = 'bottom',
                    label = 'Descarregando mercadoria e finalizando serviço...',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
                })

                if ok then
                    Zones.ClearObjective()
                    if onUnload then onUnload() end
                end
            end
        end
    })
end

return Zones
