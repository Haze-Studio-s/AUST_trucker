-- aurp_trucker — server/services/progression_service.lua
-- Sistema de progressão: XP, levels, ranks, skill tree e bônus de pagamento

ProgressionService = {}

-- XP acumulado necessário para atingir cada nível
-- Nível 1 = início (0 XP). Para chegar ao nível N, precisa de LEVEL_THRESHOLDS[N] XP total.
local LEVEL_THRESHOLDS = {
    [2]  = 100,   [3]  = 250,   [4]  = 500,   [5]  = 900,
    [6]  = 1400,  [7]  = 2100,  [8]  = 3000,  [9]  = 4200,
    [10] = 5800,  [11] = 7800,  [12] = 10300, [13] = 13300,
    [14] = 16900, [15] = 21200, [16] = 26300, [17] = 32300,
    [18] = 39300, [19] = 47500, [20] = 57000, [21] = 68000,
    [22] = 80500, [23] = 94500, [24] = 110000,[25] = 127500,
    [26] = 147000,[27] = 168500,[28] = 192000,[29] = 218000,
    [30] = 246500,
}

-- Rank 1-6 baseado no nível (1-5 → rank 1, 6-10 → rank 2, ...)
local function CalcRank(level)
    return math.min(6, math.ceil(level / 5))
end

-- XP ganho por entrega baseado na distância percorrida e multiplicador de XP
local function CalcXP(basePayment, timeMultiplier, distance)
    local mult = Config.exp_gain or Config.LC_ExpGain or 1.0
    local dist = tonumber(distance) or 1.0
    local xp = math.floor(dist * 10 * mult)
    return math.max(10, xp)
end

-- Calcula o nível correspondente ao XP total acumulado baseado em Config.required_xp_to_levelup
function ProgressionService.GetPlayerLevel(xp)
    xp = tonumber(xp) or 0
    local thresholds = Config.required_xp_to_levelup or Config.LC_RequiredXP or LEVEL_THRESHOLDS
    local level = 0
    for reqLevel, required in pairs(thresholds) do
        local rLvl = tonumber(reqLevel)
        local rXP = tonumber(required)
        if rLvl and rXP and xp >= rXP and rLvl > level then
            level = rLvl
        end
    end
    return level
end
ProgressionService.CalcLevel = ProgressionService.GetPlayerLevel
local CalcLevel = ProgressionService.CalcLevel

-- Retorna a quantidade atual de skill points do jogador
function ProgressionService.GetSkillPoints(citizenId)
    if not citizenId or citizenId == '' then return 0 end
    local stats = DB_GetPlayerStats(citizenId)
    return (stats and tonumber(stats.skill_points)) or 0
end

-- Concede XP ao jogador, processa level-ups atômicos, notifica o cliente
-- Returns: { xpGained, newLevel, levelsGained, totalXP, totalSkillPoints }
function ProgressionService.GrantXP(src, citizenId, basePayment, timeMultiplier, distance)
    local xpGained = CalcXP(basePayment, timeMultiplier, distance)
    local row = DB_AddXP(citizenId, xpGained)
    if not row then return { xpGained = xpGained, levelsGained = 0, newLevel = 1 } end

    local newLevel     = CalcLevel(row.xp)
    local oldLevel     = tonumber(row.level) or 0
    local levelsGained = math.max(0, newLevel - oldLevel)

    if levelsGained > 0 then
        local newRank = CalcRank(newLevel)
        DB_SetLevelData(citizenId, newLevel, newRank, levelsGained)
        if src and src > 0 then
            TriggerClientEvent('aurp_trucker:client:levelUp', src, {
                newLevel     = newLevel,
                newRank      = newRank,
                levelsGained = levelsGained,
                skillPoints  = levelsGained,  -- 1 ponto por nível ganho
            })
        end
    end

    local updatedStats = DB_GetPlayerStats(citizenId)

    return {
        xpGained         = xpGained,
        levelsGained     = levelsGained,
        newLevel         = (levelsGained > 0) and newLevel or oldLevel,
        totalXP          = updatedStats and updatedStats.xp or row.xp,
        totalSkillPoints = updatedStats and updatedStats.skill_points or row.skill_points,
    }
end

-- Retorna skills do jogador como mapa { [skill_type] = skill_level }
-- Tipos não adquiridos não aparecem (default 0 no cliente)
function ProgressionService.GetSkills(citizenId)
    local rows = DB_GetSkills(citizenId) or {}
    local skills = {}
    for _, row in ipairs(rows) do
        skills[row.skill_type] = row.skill_level
    end
    return skills
end

-- CalcBonus: multiplier contextual por tipo de skill
-- jobData = { distance, basePayment, cargoIntegrity }
-- returns { paymentMult, speedBonus }
function ProgressionService.CalcBonus(citizenId, jobData)
    local skills = ProgressionService.GetSkills(citizenId)
    local b      = Config.Skills.BonusPerLevel

    local paymentMult = 1.0

    if (skills.distance or 0) > 0 and (jobData.distance or 0) >= Config.Skills.DistanceThreshold then
        paymentMult = paymentMult + (skills.distance * b)
    end

    if (skills.valuable or 0) > 0 and (jobData.basePayment or 0) >= Config.Skills.ValuableThreshold then
        paymentMult = paymentMult + (skills.valuable * b)
    end

    if (skills.fragile or 0) > 0 and (jobData.cargoIntegrity or 100) >= Config.Skills.FragileThreshold then
        paymentMult = paymentMult + (skills.fragile * b)
    end

    local speedBonus = (skills.speed or 0) * b

    return { paymentMult = paymentMult, speedBonus = speedBonus }
end

-- Retorna bônus diretos de skill em formato de tabela para serviços independentes (v19/v20)
function ProgressionService.GetBonuses(citizenId)
    if not citizenId or citizenId == '' then
        return {
            speed       = 0,
            valuable    = 0,
            distance    = 0,
            fragile     = 0,
            paymentMult = 1.0,
        }
    end

    local skills = ProgressionService.GetSkills(citizenId) or {}
    local b = (Config.Skills and Config.Skills.BonusPerLevel) or 0.05

    local speedBonus    = (tonumber(skills.speed) or 0) * b
    local valuableBonus = (tonumber(skills.valuable) or 0) * b
    local distanceBonus = (tonumber(skills.distance) or 0) * b
    local fragileBonus  = (tonumber(skills.fragile) or 0) * b
    local paymentMult   = 1.0 + valuableBonus + distanceBonus

    return {
        speed       = speedBonus,
        valuable    = valuableBonus,
        distance    = distanceBonus,
        fragile     = fragileBonus,
        paymentMult = paymentMult,
    }
end

-- Compra um nível de skill gastando 1 skill point
-- Retorna: true | false, motivo (string)
function ProgressionService.PurchaseSkill(src, citizenId, skillType)
    local validTypes = {
        distance = true,
        valuable = true,
        fragile = true,
        fast = true,
        speed = true,
        illegal = true,
        product_type = true
    }
    if not validTypes[skillType] then
        return false, 'Tipo de skill inválido'
    end

    local stats = DB_GetPlayerStats(citizenId)
    if not stats then
        return false, 'Jogador não encontrado'
    end

    local currentSkills = ProgressionService.GetSkills(citizenId)
    local currentLevel  = currentSkills[skillType] or 0
    if currentLevel >= 6 then
        return false, 'Skill já está no nível máximo'
    end

    -- Gastar ponto ANTES de aplicar o nível (evita TOCTOU)
    -- Se skill_points = 0, affected rows = 0 e o else retorna erro
    local affected = DB_SpendSkillPoint(citizenId)
    if not affected or affected == 0 then
        return false, 'Sem skill points disponíveis'
    end

    DB_UpsertSkill(citizenId, skillType, currentLevel + 1)
    return true
end

-- Alias de compatibilidade com aurp_trucker:server:upgradeSkill
function ProgressionService.UpgradeSkill(citizenId, skillType)
    return ProgressionService.PurchaseSkill(nil, citizenId, skillType)
end
