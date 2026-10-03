-- aurp_trucker — server/services/forklift_service.lua
-- ForkliftService: aluguel, devolução, trade point e cleanup

ForkliftService = {}

-- ============================================================
-- Rent: registra aluguel, debita custo e inicia timer server-side
-- src = server source do jogador (para TriggerClientEvent de timeout)
-- ============================================================

function ForkliftService.Rent(citizenId, src, locationId, mode, expected)
    VP_Trucker.ForkliftRentals[citizenId] = {
        locationId = locationId,
        mode       = mode,      -- 'tradepoint' | 'industry'
        src        = src,
        rentedAt   = os.time(),
        loaded     = 0,
        expected   = expected,
    }
    if mode == 'tradepoint' then
        VP_Trucker.TradePointActive[locationId] = citizenId

        -- Timer server-side: auto-cancel após timeLimit segundos
        local timeLimit = 180
        for _, tp in ipairs(Config.Forklift.TradePoints) do
            if tp.id == locationId then
                timeLimit = tp.timeLimit
                break
            end
        end

        -- Token do aluguel (identidade da tabela): um aluguel novo do mesmo jogador/local
        -- nunca deve ser cancelado pelo timer de um aluguel anterior
        local rentalToken = VP_Trucker.ForkliftRentals[citizenId]
        CreateThread(function()
            Wait(timeLimit * 1000)
            local rental = VP_Trucker.ForkliftRentals[citizenId]
            -- Cancelar somente se ainda for a mesma missão ativa
            if rental and rental == rentalToken and rental.locationId == locationId and rental.mode == 'tradepoint' then
                VP_Trucker.ForkliftRentals[citizenId] = nil
                if VP_Trucker.TradePointActive[locationId] == citizenId then
                    VP_Trucker.TradePointActive[locationId] = nil
                end
                -- Re-resolver src: jogador pode ter reconectado ou desconectado durante o timer
                local resolvedSrc = Framework.FindPlayerByCitizenId(citizenId)
                if resolvedSrc then
                    TriggerClientEvent('aurp_trucker:client:tradePointTimeout', resolvedSrc, locationId)
                end
                if Config.Debug then
                    print(('[aurp_trucker] ForkliftService: timeout para %s em %s'):format(citizenId, locationId))
                end
            end
        end)
    end
end

-- ============================================================
-- Return: devolução VOLUNTÁRIA — retorna refund $250
-- ============================================================

function ForkliftService.Return(citizenId)
    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if not rental then
        return { success = false, refund = 0, reason = 'Sem aluguel ativo' }
    end

    if rental.mode == 'tradepoint' and rental.locationId then
        VP_Trucker.TradePointActive[rental.locationId] = nil
    end
    VP_Trucker.ForkliftRentals[citizenId] = nil

    return { success = true, refund = Config.Forklift.RefundAmount }
end

-- ============================================================
-- Cleanup: limpeza interna SEM refund
-- Usar em: CompleteTradePoint (missão concluída), OnPlayerDropped
-- ============================================================

function ForkliftService.Cleanup(citizenId)
    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if not rental then return end

    if rental.mode == 'tradepoint' and rental.locationId then
        VP_Trucker.TradePointActive[rental.locationId] = nil
    end
    VP_Trucker.ForkliftRentals[citizenId] = nil
end

-- ============================================================
-- GetRental: retorna rental ativo ou nil
-- ============================================================

function ForkliftService.GetRental(citizenId)
    return VP_Trucker.ForkliftRentals[citizenId]
end

-- ============================================================
-- IsAvailable: retorna true se locationId não está ocupado
-- ============================================================

function ForkliftService.IsAvailable(locationId)
    return VP_Trucker.TradePointActive[locationId] == nil
end

-- ============================================================
-- CompleteTradePoint: calcula pagamento com speed_mult
-- ============================================================

function ForkliftService.CompleteTradePoint(citizenId, locationId, elapsedSeconds)
    local tp = nil
    for _, point in ipairs(Config.Forklift.TradePoints) do
        if point.id == locationId then
            tp = point
            break
        end
    end
    if not tp then return 0 end

    local speedMult
    if elapsedSeconds <= 90 then
        speedMult = 1.3
    elseif elapsedSeconds <= 150 then
        speedMult = 1.0
    else
        speedMult = 0.7
    end

    return math.floor(tp.basePay * tp.maxPallets * speedMult)
end

-- ============================================================
-- OnPlayerDropped: cleanup sem refund (player desconectou)
-- ============================================================

function ForkliftService.OnPlayerDropped(citizenId)
    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if not rental then return end

    -- H-03: deletar entidade física do forklift para evitar ghost no mundo
    if rental.forkliftNetId then
        local ent = NetworkGetEntityFromNetworkId(rental.forkliftNetId)
        if DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end

    ForkliftService.Cleanup(citizenId)

    if Config.Debug then
        print(('[aurp_trucker] ForkliftService.OnPlayerDropped: cleanup para %s'):format(citizenId))
    end
end
