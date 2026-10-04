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

-- XP ganho por entrega baseado na distância percorrida, multiplicador de XP e bônus de skill
local function CalcXP(basePayment, timeMultiplier, distance, expMultiplier)
    local mult = Config.exp_gain or Config.LC_ExpGain or 1.0
    local dist = tonumber(distance) or 1.0
    local baseXP = math.floor(dist * 10 * mult)
    local finalXP = math.floor(baseXP * (expMultiplier or 1.0) * (timeMultiplier or 1.0))
    return math.max(10, finalXP)
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

-- Trava por cidadão: level-up é leitura-modificação-escrita separada por awaits de DB.
-- Chamadas concorrentes aguardam (máx ~5s) e então executam em série.
local ProgLocks = {}

local function WithProgLock(citizenId, fn, ...)
    local waited = 0
    while ProgLocks[citizenId] and waited < 5000 do
        Wait(10)
        waited = waited + 10
    end
    ProgLocks[citizenId] = true
    local ok, res = pcall(fn, ...)
    ProgLocks[citizenId] = nil
    if not ok then
        print(('[aurp_trucker] ProgressionService erro (%s): %s'):format(tostring(citizenId), tostring(res)))
        return nil
    end
    return res
end

-- Concede XP ao jogador, processa level-ups atômicos, notifica o cliente
-- Returns: { xpGained, newLevel, levelsGained, totalXP, totalSkillPoints }
local function GrantXPUnlocked(src, citizenId, basePayment, timeMultiplier, distance, expMultiplier)
    local xpGained = CalcXP(basePayment, timeMultiplier, distance, expMultiplier)
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

function ProgressionService.GrantXP(src, citizenId, basePayment, timeMultiplier, distance, expMultiplier)
    return WithProgLock(citizenId, GrantXPUnlocked, src, citizenId, basePayment, timeMultiplier, distance, expMultiplier)
        or { xpGained = 0, levelsGained = 0, newLevel = 1 }
end

-- Concede XP direto/exato ao jogador (usado em fretes Polarix / Quick Jobs com valor pré-calculado)
-- Returns: { xpGained, newLevel, levelsGained, totalXP, totalSkillPoints }
local function AddDirectXPUnlocked(src, citizenId, exactXP)
    local xpGained = math.max(0, math.floor(tonumber(exactXP) or 0))
    if xpGained <= 0 then return { xpGained = 0, levelsGained = 0, newLevel = 1 } end

    pcall(DB_UpsertPlayerStats, citizenId)
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
function ProgressionService.AddDirectXP(src, citizenId, exactXP)
    return WithProgLock(citizenId, AddDirectXPUnlocked, src, citizenId, exactXP)
        or { xpGained = 0, levelsGained = 0, newLevel = 1 }
end
ProgressionService.AddXP = ProgressionService.AddDirectXP

-- Retorna skills do jogador como mapa { [skill_type] = skill_level }
function ProgressionService.GetSkills(citizenId)
    local rows = DB_GetSkills(citizenId) or {}
    local skills = {}
    for _, row in ipairs(rows) do
        skills[row.skill_type] = tonumber(row.skill_level) or 0
    end
    -- Fallback robusto para colunas da tabela trucker_player_progression
    local stats = DB_GetPlayerStats(citizenId)
    if stats then
        skills.product_type = skills.product_type or tonumber(stats.product_type) or 0
        skills.distance     = skills.distance or tonumber(stats.distance_skill) or 0
        skills.valuable     = skills.valuable or tonumber(stats.valuable_skill) or 0
        skills.fragile      = skills.fragile or tonumber(stats.fragile_skill) or 0
        skills.fast         = skills.fast or skills.speed or tonumber(stats.fast_skill) or 0
        skills.speed        = skills.speed or skills.fast
        skills.illegal      = skills.illegal or tonumber(stats.illegal_skill) or 0
    end
    return skills
end

-- Calcula os bônus percentuais de dinheiro e XP com base nas skills do jogador e na carga
function ProgressionService.CalculateContractBonuses(citizenId, contractData)
    local skills = ProgressionService.GetSkills(citizenId) or {}
    local bonusConfig = Config.bonus or Config.LC_Bonus or {}

    local moneyBonusPct = 0
    local expBonusPct = 0

    -- Bônus de Longa Distância
    local distLvl = tonumber(skills.distance) or 0
    if distLvl > 0 and bonusConfig.distance then
        local bonusTable = bonusConfig.distance
        moneyBonusPct = moneyBonusPct + (bonusTable.money_bonus_percentage and bonusTable.money_bonus_percentage[distLvl] or 0)
        expBonusPct   = expBonusPct   + (bonusTable.exp_bonus_percentage and bonusTable.exp_bonus_percentage[distLvl] or 0)
    end

    -- Bônus de Carga Valiosa
    local valLvl = tonumber(skills.valuable) or 0
    if valLvl > 0 and (contractData.valuable == 1 or contractData.valuable == true) and bonusConfig.valuable then
        local bonusTable = bonusConfig.valuable
        moneyBonusPct = moneyBonusPct + (bonusTable.money_bonus_percentage and bonusTable.money_bonus_percentage[valLvl] or 0)
        expBonusPct   = expBonusPct   + (bonusTable.exp_bonus_percentage and bonusTable.exp_bonus_percentage[valLvl] or 0)
    end

    -- Bônus de Carga Frágil
    local fragLvl = tonumber(skills.fragile) or 0
    if fragLvl > 0 and (contractData.fragile == 1 or contractData.fragile == true) and bonusConfig.fragile then
        local bonusTable = bonusConfig.fragile
        moneyBonusPct = moneyBonusPct + (bonusTable.money_bonus_percentage and bonusTable.money_bonus_percentage[fragLvl] or 0)
        expBonusPct   = expBonusPct   + (bonusTable.exp_bonus_percentage and bonusTable.exp_bonus_percentage[fragLvl] or 0)
    end

    -- Bônus de Entrega Urgente / Rápida
    local fastLvl = tonumber(skills.fast or skills.speed) or 0
    if fastLvl > 0 and (contractData.fast == 1 or contractData.fast == true) and bonusConfig.fast then
        local bonusTable = bonusConfig.fast
        moneyBonusPct = moneyBonusPct + (bonusTable.money_bonus_percentage and bonusTable.money_bonus_percentage[fastLvl] or 0)
        expBonusPct   = expBonusPct   + (bonusTable.exp_bonus_percentage and bonusTable.exp_bonus_percentage[fastLvl] or 0)
    end

    -- Bônus de Carga Ilegal / Contrabando
    local illLvl = tonumber(skills.illegal) or 0
    if illLvl > 0 and (contractData.illegal == 1 or contractData.illegal == true) and bonusConfig.illegal then
        local bonusTable = bonusConfig.illegal
        moneyBonusPct = moneyBonusPct + (bonusTable.money_bonus_percentage and bonusTable.money_bonus_percentage[illLvl] or 0)
        expBonusPct   = expBonusPct   + (bonusTable.exp_bonus_percentage and bonusTable.exp_bonus_percentage[illLvl] or 0)
    end

    return {
        moneyMultiplier = 1.0 + (moneyBonusPct / 100.0),
        expMultiplier   = 1.0 + (expBonusPct / 100.0),
        moneyBonusPct   = moneyBonusPct,
        expBonusPct     = expBonusPct,
        skills          = skills,
    }
end

-- Valida rigorosamente se o jogador cumpre os requisitos de habilidade para a carga
function ProgressionService.CanPlayerAcceptContract(citizenId, contractData)
    local skills = ProgressionService.GetSkills(citizenId) or {}
    local distSkill = tonumber(skills.distance) or 0
    local distMap = Config.distance_skill or Config.LC_DistanceSkill or {
        [0] = 6.0, [1] = 6.5, [2] = 7.0, [3] = 7.5, [4] = 8.0, [5] = 8.5, [6] = 999.0
    }
    local maxDist = distMap[distSkill] or 6.0
    local contractDist = tonumber(contractData.distance) or 0.0

    if contractDist > maxDist then
        return false, 'distance', ('Distância de entrega (%.2f km) excede o limite da sua habilidade (máx: %.1f km).'):format(contractDist, maxDist)
    end

    -- ADR / Hazardous / Product Type
    local adrReq = tonumber(contractData.cargo_type) or 0
    local adrSkill = tonumber(skills.product_type) or 0
    if adrReq > 0 and adrSkill < adrReq then
        return false, 'adr', ('Carga perigosa bloqueada! Requer Certificado ADR Classe %d (seu nível: %d).'):format(adrReq, adrSkill)
    end

    -- Fragile
    if (contractData.fragile == 1 or contractData.fragile == true) and (tonumber(skills.fragile) or 0) < 1 then
        return false, 'fragile', 'Carga frágil bloqueada! Requer no mínimo Nível 1 em Cargas Frágeis.'
    end

    -- Valuable
    if (contractData.valuable == 1 or contractData.valuable == true) and (tonumber(skills.valuable) or 0) < 1 then
        return false, 'valuable', 'Carga de alto valor bloqueada! Requer no mínimo Nível 1 em Cargas Valiosas.'
    end

    -- Fast / Urgent
    if (contractData.fast == 1 or contractData.fast == true) and (tonumber(skills.fast or skills.speed) or 0) < 1 then
        return false, 'fast', 'Entrega urgente bloqueada! Requer no mínimo Nível 1 em Entregas Urgentes.'
    end

    -- Illegal
    if (contractData.illegal == 1 or contractData.illegal == true) and (tonumber(skills.illegal) or 0) < 1 then
        return false, 'illegal', 'Carga ilícita bloqueada! Requer especialização em Cargas Ilegais.'
    end

    return true, nil, nil
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

-- Compatibilidade unificada com JobService e IllegalService (v13/v15/v20)
function ProgressionService.CalcBonus(citizenId, opts)
    local bonuses = ProgressionService.GetBonuses(citizenId)
    return {
        speedBonus  = bonuses.speed or 0.0,
        paymentMult = bonuses.paymentMult or 1.0,
        valuable    = bonuses.valuable or 0.0,
        distance    = bonuses.distance or 0.0,
        fragile     = bonuses.fragile or 0.0,
    }
end

-- Compra um nível de skill gastando 1 skill point
-- Retorna: true | false, motivo (string)
local function PurchaseSkillUnlocked(src, citizenId, skillType)
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

    local okUp, errUp = pcall(DB_UpsertSkill, citizenId, skillType, currentLevel + 1)
    if not okUp then
        -- Estorna o ponto gasto para não perder o skill point
        print(('[aurp_trucker] PurchaseSkill falha ao gravar skill (%s): %s'):format(tostring(citizenId), tostring(errUp)))
        pcall(function()
            MySQL.update.await('UPDATE trucker_player_progression SET skill_points = skill_points + 1 WHERE citizenid = ?', { citizenId })
        end)
        return false, 'Erro ao aplicar skill'
    end
    return true
end

function ProgressionService.PurchaseSkill(src, citizenId, skillType)
    local lockResult = {}
    local ran = WithProgLock(citizenId, function()
        local ok, reason = PurchaseSkillUnlocked(src, citizenId, skillType)
        lockResult.ok, lockResult.reason = ok, reason
        return true
    end)
    if not ran then return false, 'Erro ao processar compra' end
    return lockResult.ok, lockResult.reason
end

-- Alias de compatibilidade com aurp_trucker:server:upgradeSkill
function ProgressionService.UpgradeSkill(citizenId, skillType)
    return ProgressionService.PurchaseSkill(nil, citizenId, skillType)
end
