-- aurp_trucker — server/services/container_handler_service.lua
-- v20: Serviço de Handler Portuário (integração oConteneur)
-- Sem tabela DB — estado efêmero em VP_Trucker.ContainerJobs
-- Pagamento: basePayment × skillMult × (1 + companyBonus%)

ContainerHandlerService = {}

-- Guard: garantir que o campo exista mesmo se main.lua carregar antes
if not VP_Trucker.ContainerJobs then
    VP_Trucker.ContainerJobs = {}
end

-- ============================================================
-- Start: registra job ativo e sorteia location/slot/cargo
-- Retorna { success, containerLoc, deliverySlot, cargo }
--         ou { success = false, reason }
-- ============================================================

function ContainerHandlerService.Start(citizenId, src)
    if not Config.ContainerHandler or not Config.ContainerHandler.Enabled then
        return { success = false, reason = 'Sistema de Handler desativado' }
    end

    if VP_Trucker.ContainerJobs[citizenId] then
        return { success = false, reason = 'Você já tem uma missão de contêiner ativa' }
    end

    local locs  = Config.ContainerHandler.ContainerLocations
    local slots = Config.ContainerHandler.DeliverySlots
    local types = Config.ContainerHandler.CargoTypes

    if not locs or #locs == 0 or not slots or #slots == 0 then
        return { success = false, reason = 'Configuração de ContainerHandler incompleta' }
    end

    local loc   = locs[math.random(#locs)]
    local slot  = slots[math.random(#slots)]
    local cargo = types[math.random(#types)]

    VP_Trucker.ContainerJobs[citizenId] = {
        src          = src,
        startedAt    = os.time(),
        containerLoc = loc,
        deliverySlot = slot,
        cargo        = cargo,
    }

    if Config.Debug then
        print(('[aurp_trucker] ContainerHandler.Start: %s → loc=%s slot=%s cargo=%s'):format(
            citizenId, loc.name, slot.name, cargo.name))
    end

    return {
        success      = true,
        containerLoc = loc,
        deliverySlot = slot,
        cargo        = cargo,
    }
end

-- ============================================================
-- Complete: valida proximidade, paga, concede XP e limpa job
-- coords: { x, y, z } enviados pelo client (posição do slot)
-- ============================================================

function ContainerHandlerService.Complete(citizenId, src, coords)
    local job = VP_Trucker.ContainerJobs[citizenId]
    if not job then
        return { success = false, reason = 'Sem missão de contêiner ativa' }
    end

    -- Validação 1: proximidade do jogador ao slot registrado pelo SERVER
    -- (usamos as coords do job, não as enviadas pelo client, para evitar spoofing)
    local playerPos = GetEntityCoords(GetPlayerPed(src))
    local slotPos   = vector3(job.deliverySlot.x, job.deliverySlot.y, job.deliverySlot.z)
    local dist      = #(playerPos - slotPos)

    if dist > Config.ContainerHandler.MaxDeliveryRadius then
        if Config.Debug then
            print(('[aurp_trucker] ContainerHandler.Complete NEGADO: %s dist=%.1f'):format(citizenId, dist))
        end
        return { success = false, reason = 'Muito longe do slot de entrega (' .. math.floor(dist) .. 'm)' }
    end

    -- Calcular pagamento com cadeia completa: base × skill × company
    local cfg         = Config.ContainerHandler
    local basePayment = math.random(cfg.Payment.min, cfg.Payment.max)
    local skillMult   = 1.0
    local companyBonus = 0

    -- Bônus de skill (speed + valuable se aplicável)
    local okSkill, bonuses = pcall(ProgressionService.GetBonuses, citizenId)
    if okSkill and bonuses then
        skillMult = 1.0
            + (bonuses.speed    or 0)
            + (bonuses.valuable or 0)
    end

    -- Bônus de empresa (company_level perks)
    local company = CompanyService.GetByMember(citizenId)
    local companyMult = 1.0
    if company then
        local okPerks, perks = pcall(CompanyService.GetPerks, company.id)
        if okPerks and perks and perks.bonus then
            companyMult = perks.bonus
        end
    end

    local finalPayment = math.floor(basePayment * skillMult * companyMult)

    -- Pagar jogador (banco)
    local Player = Framework.GetPlayer(src)
    if Player then
        Framework.AddMoney(Player, 'bank', finalPayment, 'container_handler_delivery')
    end

    -- Conceder XP de progressão individual
    pcall(ProgressionService.GrantXP, src, citizenId, finalPayment, 1.0)

    -- Conceder XP de empresa se vinculado
    if company then
        pcall(CompanyService.AddXP, company.id, math.floor(finalPayment / 10))
    end

    -- Limpar job
    VP_Trucker.ContainerJobs[citizenId] = nil

    if Config.Debug then
        print(('[aurp_trucker] ContainerHandler.Complete: %s pagamento=$%d (base=%d skill=%.2f company=%.2f)'):format(
            citizenId, finalPayment, basePayment, skillMult, companyMult))
    end

    return { success = true, payment = finalPayment }
end

-- ============================================================
-- Cancel: limpa job sem pagamento (abandono ou erro client)
-- ============================================================

function ContainerHandlerService.Cancel(citizenId)
    VP_Trucker.ContainerJobs[citizenId] = nil
end

-- ============================================================
-- GetActive: retorna job ativo ou nil
-- ============================================================

function ContainerHandlerService.GetActive(citizenId)
    return VP_Trucker.ContainerJobs[citizenId]
end

-- ============================================================
-- OnPlayerDropped: cleanup quando jogador desconecta
-- ============================================================

function ContainerHandlerService.OnPlayerDropped(citizenId)
    if VP_Trucker.ContainerJobs[citizenId] then
        VP_Trucker.ContainerJobs[citizenId] = nil
        if Config.Debug then
            print(('[aurp_trucker] ContainerHandler.OnPlayerDropped: cleanup para %s'):format(citizenId))
        end
    end
end
