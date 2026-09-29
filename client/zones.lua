-- =======================================================================
-- AUST_trucker — client/zones.lua
-- Máquina de Estados: Zonas de Interação, ox_target e ox_lib.points
-- Padrão QBOX / OX: Zero Loops Wait(0), Interações Autorizadas
-- =======================================================================

Zones = {}

local ActivePoints = {}
local ActiveTargetEntities = {}
local InspectedParts = {}
local ShowingPrompt = false

-- =======================================================================
-- LIMPEZA GERAL DE ZONAS E TARGETS
-- =======================================================================
function Zones.Cleanup()
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

    InspectedParts = {}
end

-- =======================================================================
-- ESTADO 2: INSPEÇÃO DE SEGURANÇA (TRUCK INSPECTION VIA OX_TARGET)
-- =======================================================================
function Zones.SetupInspection(truck, jobId, onComplete)
    InspectedParts = {}

    if not truck or not DoesEntityExist(truck) then return end
    table.insert(ActiveTargetEntities, truck)

    -- Caminhão permanece trancado até a inspeção ser 100% concluída
    SetVehicleDoorsLocked(truck, 2)

    local checkpoints = (Config.Polarix and Config.Polarix.Inspection and Config.Polarix.Inspection.Checkpoints) or {
        { id = 'tires_front_left', label = 'Verificar Pneus Dianteiros', offset = vector3(-1.2, 2.5, 0.0) },
        { id = 'engine_hood', label = 'Checar Óleo & Radiador', offset = vector3(0.0, 3.2, 0.5) },
        { id = 'tires_rear', label = 'Verificar Rodas Traseiras', offset = vector3(-1.2, -1.5, 0.0) },
    }
    local totalRequired = #checkpoints

    for _, cp in ipairs(checkpoints) do
        exports.ox_target:addLocalEntity(truck, {
            {
                name = 'inspect_' .. cp.id,
                icon = 'fa-solid fa-magnifying-glass',
                label = cp.label,
                distance = 2.4,
                canInteract = function()
                    return not InspectedParts[cp.id]
                end,
                onSelect = function()
                    local anim = (Config.Polarix and Config.Polarix.Inspection and Config.Polarix.Inspection.Animation) or { dict = 'mini@repair', clip = 'fixing_a_ped' }
                    local success = lib.progressBar({
                        duration = (Config.Polarix and Config.Polarix.Inspection and Config.Polarix.Inspection.Duration) or 3000,
                        label = cp.label .. '...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = anim.dict, clip = anim.clip }
                    })

                    if success then
                        InspectedParts[cp.id] = true
                        PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", 0)

                        local inspectedCount = 0
                        for _ in pairs(InspectedParts) do inspectedCount = inspectedCount + 1 end

                        lib.notify({
                            title = 'Inspeção de Segurança',
                            description = ('Item verificado (%d/%d)!'):format(inspectedCount, totalRequired),
                            type = 'inform'
                        })

                        if inspectedCount >= totalRequired then
                            if onComplete then onComplete() end
                        end
                    end
                end
            }
        })
    end

    lib.notify({
        title = 'Inspeção Obrigatória (Estado 2)',
        description = 'Realize a checagem nos pneus e motor do caminhão antes de ligar o veículo!',
        type = 'warning',
        duration = 8000
    })
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

    ActivePoints['delivery_dest'] = lib.points.new({
        coords = vector3(coords.x, coords.y, coords.z),
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
                    if onUnload then onUnload() end
                end
            end
        end
    })
end

return Zones
