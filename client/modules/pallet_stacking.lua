-- =======================================================================
-- AUST_trucker — client/modules/pallet_stacking.lua
-- Módulo Cliente de Stacking Pallet (CarrySystem + ox_target + Havok Shield)
-- Zero Resmon em repouso (<0.01ms) — Gestão Atômica de Props e Interações
-- =======================================================================

local PalletStackingModule = {}
local ActiveSession = nil
local TargetZoneIds = {}
local RegisteredEntityTargets = {}

---Inicia a sessão de montagem no cliente
RegisterNetEvent('aurp_trucker:client:startStackingSession', function(data)
    ActiveSession = {
        jobId = data.jobId,
        requiredPallets = data.requiredPallets,
        palletNetIds = data.palletNetIds or {},
        stockpileNetId = data.stockpileNetId,
        stockpileCoords = data.stockpileCoords,
        consolidatedPallets = {}
    }

    -- 1. Alvo ox_target no Estoque de Peças (Stockpile)
    if data.stockpileNetId and data.stockpileNetId ~= 0 then
        local stockEnt = NetworkGetEntityFromNetworkId(data.stockpileNetId)
        if DoesEntityExist(stockEnt) then
            exports.ox_target:addLocalEntity(stockEnt, {
                {
                    name = 'aust_stockpile_pickup',
                    icon = 'fas fa-box-open',
                    label = 'Pegar Peça para Empilhar',
                    distance = 2.5,
                    canInteract = function()
                        return ActiveSession ~= nil and not CarrySystem.IsCarrying()
                    end,
                    onSelect = function()
                        local carryType = Config.Stacking.CarryType or 'small_box'
                        local ok = CarrySystem.Start(carryType)
                        if ok then
                            PlaySoundFrontend(-1, "PICK_UP", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)
                            lib.notify({
                                title = 'Carga Manual',
                                description = 'Você pegou uma peça! Leve-a até a base do palete.',
                                type = 'info'
                            })
                        end
                    end
                }
            })
            table.insert(RegisteredEntityTargets, stockEnt)
        end
    end

    -- 2. Alvos ox_target nas Bases dos Paletes
    PalletStackingModule.RefreshPalletTargets()

    lib.notify({
        title = 'Preparação de Carga',
        description = ('Monte os %d paletes no pátio para garantir o bônus de +20%% no frete!'):format(data.requiredPallets),
        type = 'success',
        duration = 7000
    })
end)

---Atualiza os alvos do ox_target para os paletes ativos
function PalletStackingModule.RefreshPalletTargets()
    if not ActiveSession then return end

    local targetModels = {
        joaat(Config.Stacking.BasePalletModel or 'prop_biotech_pallet'),
        joaat('prop_boxpile_07d'),
        joaat('prop_boxpile_07c'),
        joaat('prop_boxpile_07b')
    }

    exports.ox_target:addModel(targetModels, {
        {
            name = 'aust_stack_piece_manual',
            icon = 'fas fa-layer-group',
            label = 'Adicionar Peça ao Palete',
            distance = 2.5,
            canInteract = function(entity)
                if not ActiveSession then return false end
                local entState = Entity(entity).state
                return entState.isStackingPallet and CarrySystem.IsCarrying()
            end,
            onSelect = function(data)
                local entity = data.entity
                local netId = NetworkGetNetworkIdFromEntity(entity)

                local ped = cache.ped or PlayerPedId()
                TaskTurnPedToFaceEntity(ped, entity, 500)
                Wait(500)

                local success = lib.progressBar({
                    duration = Config.Stacking.ProgressDuration or 2500,
                    label = 'Empilhando peça no palete...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = {
                        dict = 'anim@heists@load_box',
                        clip = 'lift_box'
                    }
                })

                if success then
                    CarrySystem.Stop()
                    PlaySoundFrontend(-1, "Put_Down", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)
                    TriggerServerEvent('aurp_trucker:server:addPieceToStack', netId, false)
                end
            end
        },
        {
            name = 'aust_stack_piece_quick',
            icon = 'fas fa-industry',
            label = 'Montagem Rápida (Esteira)',
            distance = 2.5,
            canInteract = function(entity)
                if not ActiveSession then return false end
                local entState = Entity(entity).state
                return entState.isStackingPallet and not CarrySystem.IsCarrying()
            end,
            onSelect = function(data)
                local entity = data.entity
                local netId = NetworkGetNetworkIdFromEntity(entity)

                local success = lib.progressBar({
                    duration = Config.Stacking.QuickStackDuration or 4000,
                    label = 'Processando montagem industrial da peça...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = {
                        dict = 'amb@prop_human_bum_bin@idle_b',
                        clip = 'idle_d'
                    }
                })

                if success then
                    PlaySoundFrontend(-1, "Remote_Explosive_Detonate", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0)
                    TriggerServerEvent('aurp_trucker:server:addPieceToStack', netId, true)
                end
            end
        }
    })
end

---Atualiza o NetID de uma base substituída
RegisterNetEvent('aurp_trucker:client:updatePalletNetId', function(oldNet, newNet, pieces)
    if not ActiveSession then return end
    for idx, net in ipairs(ActiveSession.palletNetIds) do
        if net == oldNet then
            ActiveSession.palletNetIds[idx] = newNet
            break
        end
    end
end)

---Recebe a consolidação de um palete individual
RegisterNetEvent('aurp_trucker:client:palletConsolidated', function(finalNetId, finishedCount, totalRequired)
    if not ActiveSession then return end

    local finalEnt = NetworkGetEntityFromNetworkId(finalNetId)
    if DoesEntityExist(finalEnt) then
        SetEntityAsMissionEntity(finalEnt, true, true)
        SetEntityLodDist(finalEnt, 0xFFFF)
        SetEntityCollision(finalEnt, true, true)
        FreezeEntityPosition(finalEnt, true)

        table.insert(ActiveSession.consolidatedPallets, finalEnt)

        -- Adiciona imediatamente à lista da empilhadeira
        ForkliftModule.SetMissionPallets(ActiveSession.consolidatedPallets)
        PlaySoundFrontend(-1, "CHALLENGE_UNLOCKED", "HUD_AWARDS", 0)
    end
end)

---Todos os paletes foram finalizados
RegisterNetEvent('aurp_trucker:client:allPalletsConsolidated', function(finalNetIds)
    if not ActiveSession then return end

    local allEntities = {}
    for _, netId in ipairs(finalNetIds) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            SetEntityLodDist(ent, 0xFFFF)
            SetEntityCollision(ent, true, true)
            FreezeEntityPosition(ent, true)
            table.insert(allEntities, ent)
        end
    end

    ActiveSession.consolidatedPallets = allEntities
    JobEntities.pallets = allEntities
    ForkliftModule.SetMissionPallets(allEntities)

    PlaySoundFrontend(-1, "BASE_JUMP_PASSED", "HUD_AWARDS", 0)

    lib.notify({
        title = 'Montagem 100% Concluída!',
        description = 'Todos os paletes estão prontos e consolidados! Use a empilhadeira para embarcá-los no trailer.',
        type = 'success',
        duration = 8000
    })

    PalletStackingModule.Cleanup()
end)

---Limpeza de alvos e sessão
function PalletStackingModule.Cleanup()
    for _, ent in ipairs(RegisteredEntityTargets) do
        if DoesEntityExist(ent) then
            exports.ox_target:removeLocalEntity(ent, { 'aust_stockpile_pickup' })
        end
    end
    RegisteredEntityTargets = {}
    ActiveSession = nil
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    PalletStackingModule.Cleanup()
end)

RegisterNetEvent('aurp_trucker:client:cancelStacking', function()
    PalletStackingModule.Cleanup()
end)
