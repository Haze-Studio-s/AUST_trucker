-- =======================================================================
-- AUST_trucker — client/zones.lua
-- Máquina de Estados: Zonas de Interação, ox_target e ox_lib.points
-- Padrão QBOX / OX: Zero Loops Wait(0), Interações Autorizadas
-- =======================================================================

Zones = {}
_G.Zones = Zones

local ActivePoints = {}
local ActiveTargetEntities = {}
local ShowingPrompt = false
local ActiveObjectivePoint = nil
local ActiveObjectiveBlip = nil

-- =======================================================================
-- GUIA VISUAL EXCLUSIVO: BLIPS E SETA FLUTUANTE (OX_LIB.POINTS)
-- =======================================================================

function Zones.ClearObjective()
    if ActiveObjectivePoint then
        pcall(function() ActiveObjectivePoint:remove() end)
        ActiveObjectivePoint = nil
    end
    if ActiveObjectiveBlip and DoesBlipExist(ActiveObjectiveBlip) then
        RemoveBlip(ActiveObjectiveBlip)
        ActiveObjectiveBlip = nil
    end
end

function Zones.SetObjective(coords, label, sprite, color, markerOffsetZ)
    Zones.ClearObjective()
    if not coords then return end

    local targetCoords = vector3(coords.x, coords.y, coords.z)
    local offsetZ = markerOffsetZ or 1.6

    -- 1. Blip exclusivo client-side no radar/mapa com rota GPS
    ActiveObjectiveBlip = AddBlipForCoord(targetCoords.x, targetCoords.y, targetCoords.z)
    SetBlipSprite(ActiveObjectiveBlip, sprite or 1)
    SetBlipColour(ActiveObjectiveBlip, color or 5)
    SetBlipScale(ActiveObjectiveBlip, 0.95)
    SetBlipRoute(ActiveObjectiveBlip, true)
    SetBlipRouteColour(ActiveObjectiveBlip, color or 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(label or "Objetivo Atual")
    EndTextCommandSetBlipName(ActiveObjectiveBlip)

    -- 2. Seta Flutuante 3D (DrawMarker tipo 2) via ox_lib.points (0.00ms quando distante)
    ActiveObjectivePoint = lib.points.new({
        coords = targetCoords,
        distance = 60.0,
        nearby = function(self)
            local pos = self.coords
            DrawMarker(
                2,
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
end

-- =======================================================================
-- LIMPEZA GERAL DE ZONAS E TARGETS
-- =======================================================================
function Zones.Cleanup()
    Zones.ClearObjective()

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
