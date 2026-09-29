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

local ActiveObjectiveThread = nil

local function ClearObjective()
    ActiveObjectiveThread = nil
    if ActiveObjectivePoint then
        pcall(function() ActiveObjectivePoint:remove() end)
        ActiveObjectivePoint = nil
    end
    if ActiveObjectiveBlip and DoesBlipExist(ActiveObjectiveBlip) then
        RemoveBlip(ActiveObjectiveBlip)
        ActiveObjectiveBlip = nil
    end
end
Zones.ClearObjective = ClearObjective

local function SetObjective(data, label, sprite, color, markerOffsetZ)
    ClearObjective()
    if not data then return end

    local targetNetId = nil
    local targetCoords = nil
    local targetLabel = label or "Objetivo Atual"
    local targetSprite = sprite or 1
    local targetColor = color or 5
    local offsetZ = markerOffsetZ or 3.5
    local notifyMsg = nil

    if type(data) == 'table' and (data.netId or data.coords) then
        targetNetId = data.netId
        if data.coords then
            targetCoords = vector3(data.coords.x, data.coords.y, data.coords.z)
        end
        targetLabel = data.label or targetLabel
        targetSprite = data.sprite or targetSprite
        targetColor = data.color or targetColor
        offsetZ = data.offsetZ or offsetZ
        notifyMsg = data.notify
    elseif type(data) == 'vector3' or (type(data) == 'table' and data.x and data.y and data.z) then
        targetCoords = vector3(data.x, data.y, data.z)
    end

    -- Dispara notificação de 10 segundos caso informada
    if notifyMsg and notifyMsg ~= '' then
        lib.notify({
            title = 'Central de Cargas',
            description = notifyMsg,
            duration = 10000,
            type = 'inform'
        })
    end

    -- Blip inicial no mapa (caso tenha coordenadas fixas imediatas)
    if targetCoords and (not targetNetId or targetNetId == 0) then
        ActiveObjectiveBlip = AddBlipForCoord(targetCoords.x, targetCoords.y, targetCoords.z)
        SetBlipSprite(ActiveObjectiveBlip, targetSprite or 1)
        SetBlipColour(ActiveObjectiveBlip, targetColor or 5)
        SetBlipScale(ActiveObjectiveBlip, 0.95)
        SetBlipRoute(ActiveObjectiveBlip, true)
        SetBlipRouteColour(ActiveObjectiveBlip, targetColor or 5)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(targetLabel)
        EndTextCommandSetBlipName(ActiveObjectiveBlip)
    end

    -- Identificador único para a thread de monitoramento atual
    local pointId = math.random(1000, 999999)
    ActiveObjectiveThread = pointId

    local initialPos = targetCoords or vector3(0.0, 0.0, 0.0)
    ActiveObjectivePoint = lib.points.new({
        coords = initialPos,
        distance = 80.0,
        nearby = function(self)
            local pos = self.coords
            if targetNetId and targetNetId ~= 0 then
                if NetworkDoesNetworkIdExist(targetNetId) then
                    local ent = NetworkGetEntityFromNetworkId(targetNetId)
                    if DoesEntityExist(ent) then
                        pos = GetEntityCoords(ent)
                        self.coords = pos
                    end
                end
            end

            -- DrawMarker tipo 20: seta apontada para baixo flutuando suavemente exatamente acima do teto
            DrawMarker(
                20,
                pos.x, pos.y, pos.z + offsetZ,
                0.0, 0.0, 0.0,
                180.0, 0.0, 0.0,
                0.75, 0.75, 0.75,
                240, 200, 30, 220,
                true,   -- bobUpAndDown (flutua suavemente para cima/baixo)
                false, 2, true, nil, nil, false
            )
        end
    })

    -- Se o objetivo rastreia uma entidade móvel por NetId (Caminhão, Empilhadeira, etc.)
    if targetNetId and targetNetId ~= 0 then
        CreateThread(function()
            local waitTimeout = GetGameTimer() + 6000
            while not NetworkDoesNetworkIdExist(targetNetId) and GetGameTimer() < waitTimeout do
                Wait(100)
            end

            if ActiveObjectiveThread ~= pointId then return end

            local ent = NetworkDoesNetworkIdExist(targetNetId) and NetworkGetEntityFromNetworkId(targetNetId) or 0
            if ent ~= 0 and DoesEntityExist(ent) then
                local entPos = GetEntityCoords(ent)
                if ActiveObjectivePoint then
                    ActiveObjectivePoint.coords = entPos
                end

                if ActiveObjectiveBlip and DoesBlipExist(ActiveObjectiveBlip) then
                    RemoveBlip(ActiveObjectiveBlip)
                end
                ActiveObjectiveBlip = AddBlipForEntity(ent)
                SetBlipSprite(ActiveObjectiveBlip, targetSprite or 477)
                SetBlipColour(ActiveObjectiveBlip, targetColor or 5)
                SetBlipScale(ActiveObjectiveBlip, 0.95)
                SetBlipRoute(ActiveObjectiveBlip, true)
                SetBlipRouteColour(ActiveObjectiveBlip, targetColor or 5)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(targetLabel)
                EndTextCommandSetBlipName(ActiveObjectiveBlip)

                -- Sincronização periódica da posição macro do ox_lib.points
                while ActiveObjectiveThread == pointId and DoesEntityExist(ent) do
                    if ActiveObjectivePoint then
                        ActiveObjectivePoint.coords = GetEntityCoords(ent)
                    end
                    Wait(1000)
                end
            end
        end)
    end
end
Zones.SetObjective = SetObjective

RegisterNetEvent('aust_trucker:client:SetObjective', function(data)
    SetObjective(data)
end)

RegisterNetEvent('aust_trucker:client:ClearObjective', function()
    ClearObjective()
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
