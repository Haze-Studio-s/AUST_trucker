-- =======================================================================
-- AUST_trucker — client/cargo_dry.lua
-- Sistema de Carga Seca: Operação com Empilhadeira, Zonas ox_lib.points
-- Stack QBOX / OX: ox_lib, ox_target, OneSync Server-Side Truth
-- =======================================================================

local ForkliftModule = require('client.modules.forklift')

CargoDry = {}
local RearLoadingPoint = nil
local CurrentJobData = nil
local TrailerEntity = nil
local ShowingPrompt = false

-- =======================================================================
-- LIMPEZA DO MÓDULO DE CARGA SECA
-- =======================================================================
function CargoDry.Cleanup()
    if RearLoadingPoint then
        pcall(function() RearLoadingPoint:remove() end)
        RearLoadingPoint = nil
    end
    if ShowingPrompt then
        lib.hideTextUI()
        ShowingPrompt = false
    end
    CurrentJobData = nil
    TrailerEntity = nil
end

-- =======================================================================
-- INICIALIZAÇÃO DA CARGA SECA (CHAMADO APÓS APROVAÇÃO DA INSPEÇÃO)
-- =======================================================================
function CargoDry.Setup(jobData, trailer, truck)
    CargoDry.Cleanup()
    CurrentJobData = jobData
    TrailerEntity = trailer

    if not trailer or not DoesEntityExist(trailer) then return end

    -- Configuração do ox_target padrão da carreta para segurança adicional
    ForkliftModule.SetupTrailerTarget(trailer, jobData.jobId, function()
        return 'STATUS_LOADING', CurrentJobData.loadedCount or 0, CurrentJobData.requiredCount or 4
    end)

    -- ox_lib.points posicionado dinamicamente na traseira da carreta
    local trailerRearOffset = vector3(0.0, -5.5, 0.0)
    local initialCoords = GetOffsetFromEntityInWorldCoords(trailer, trailerRearOffset.x, trailerRearOffset.y, trailerRearOffset.z)

    RearLoadingPoint = lib.points.new({
        coords = initialCoords,
        distance = 5.0,
        onEnter = function()
            -- Entrou na proximidade da traseira
        end,
        onExit = function()
            if ShowingPrompt then
                lib.hideTextUI()
                ShowingPrompt = false
            end
        end,
        nearby = function(self)
            -- Atualiza coordenadas da zona caso a carreta tenha se movido
            if DoesEntityExist(TrailerEntity) then
                self.coords = GetOffsetFromEntityInWorldCoords(TrailerEntity, trailerRearOffset.x, trailerRearOffset.y, trailerRearOffset.z)
            end

            local inForklift = ForkliftModule.IsPlayerInForklift()
            local carriedPallet = ForkliftModule.GetCarriedPallet()

            if inForklift and carriedPallet and DoesEntityExist(carriedPallet) then
                if not ShowingPrompt then
                    lib.showTextUI('[E] Fixar Palete no Reboque', {
                        position = 'left-center',
                        icon = 'pallet'
                    })
                    ShowingPrompt = true
                    if Zones and Zones.SetObjective then
                        Zones.SetObjective(self.coords, "Acomodar Palete na Carreta", 479, 2, 2.5)
                    end
                end

                if IsControlJustPressed(0, 38) then -- Tecla E
                    lib.hideTextUI()
                    ShowingPrompt = false

                    local loaded = CurrentJobData.loadedCount or 0
                    local required = CurrentJobData.requiredCount or 4

                    local ok = ForkliftModule.LoadPalletOntoTrailer(TrailerEntity, CurrentJobData.jobId, loaded, required)
                    if ok then
                        if Zones and Zones.ClearObjective then Zones.ClearObjective() end
                    end
                end
            else
                if ShowingPrompt then
                    lib.hideTextUI()
                    ShowingPrompt = false
                end
            end
        end
    })

    lib.notify({
        title = 'Carregamento de Paletes',
        description = 'Opere a empilhadeira com cuidado e transporte os paletes até a traseira da carreta.',
        type = 'inform',
        duration = 7000
    })
end

-- =======================================================================
-- ATUALIZAÇÃO DE PROGRESSO E CONCLUSÃO
-- =======================================================================
RegisterNetEvent('aurp_trucker:client:dryProgressSync', function(loaded, required)
    if not CurrentJobData then return end
    CurrentJobData.loadedCount = loaded
    CurrentJobData.requiredCount = required

    lib.notify({
        title = 'Carga Seca: Palete Acomodado',
        description = ('Paletes Carregados: %d/%d'):format(loaded, required),
        type = 'inform'
    })

    if loaded < required then
        -- Aponta o objetivo visual para o próximo palete no chão
        local fl = ForkliftModule.GetPlayerForklift()
        if fl then
            local nextPallet = ForkliftModule.GetNearestGroundPallet(fl)
            if nextPallet and DoesEntityExist(nextPallet) and Zones and Zones.SetObjective then
                Zones.SetObjective(GetEntityCoords(nextPallet), "Pegar Próximo Palete", 478, 5, 1.2)
            end
        end
    else
        CargoDry.Cleanup()
        TriggerEvent('aurp_trucker:client:startStrappingStage', CurrentJobData.jobId)
    end
end)

RegisterNetEvent('aurp_trucker:client:cleanupCargoDry', function()
    CargoDry.Cleanup()
end)

return CargoDry
