-- aurp_trucker — server/framework.lua
-- Camada de abstração de framework: QBX | QBCore | ESX
-- Carregado antes de todos os services (ver fxmanifest load order)
-- IMPORTANTE: Config.Framework deve estar definido em config/config.lua

Framework = {}

local fw = Config.Framework or 'qbx'

-- ============================================================
-- QBX / QBCore
-- ============================================================
if fw == 'qbx' or fw == 'qbcore' then

    local function GetCorePlayer(src)
        if fw == 'qbx' then
            return exports.qbx_core:GetPlayer(src)
        else
            return QBCore.Functions.GetPlayer(src)
        end
    end

    Framework.GetPlayer = function(src)
        return GetCorePlayer(src)
    end

    Framework.FindPlayerByCitizenId = function(citizenId)
        for _, pid in ipairs(GetPlayers()) do
            local P = GetCorePlayer(tonumber(pid))
            if P and P.PlayerData.citizenid == citizenId then
                return tonumber(pid)
            end
        end
        return nil
    end

    Framework.GetCitizenId = function(player)
        return player and player.PlayerData.citizenid
    end

    Framework.GetCharInfo = function(player)
        if not player then return nil end
        return player.PlayerData.charinfo
    end

    Framework.GetCharName = function(player)
        if not player then return 'Motorista' end
        local ci = player.PlayerData and player.PlayerData.charinfo
        if ci and (ci.firstname or ci.lastname) then
            return ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s*(.-)%s*$', '%1')
        end
        return GetPlayerName(player.PlayerData and player.PlayerData.source or 0) or 'Motorista'
    end

    Framework.GetJob = function(player)
        return player and player.PlayerData.job or { name = '', label = '' }
    end

    Framework.AddMoney = function(player, account, amount, reason)
        if type(player) == 'number' then player = Framework.GetPlayer(player) end
        if not player then return end
        account = (account == 'cash') and 'cash' or 'bank'
        if fw == 'qbx' then
            exports.qbx_core:AddMoney(player.PlayerData.source, account, amount, reason or '')
        else
            player.Functions.AddMoney(account, amount, reason)
        end
    end

    Framework.RemoveMoney = function(player, account, amount, reason)
        if type(player) == 'number' then player = Framework.GetPlayer(player) end
        if not player then return false end
        account = (account == 'cash') and 'cash' or 'bank'
        if fw == 'qbx' then
            return exports.qbx_core:RemoveMoney(player.PlayerData.source, account, amount, reason or '')
        else
            return player.Functions.RemoveMoney(account, amount, reason)
        end
    end

    Framework.GetMoney = function(player, account)
        if type(player) == 'number' then player = Framework.GetPlayer(player) end
        if not player then return 0 end
        account = (account == 'cash') and 'cash' or 'bank'
        if fw == 'qbx' then
            return exports.qbx_core:GetMoney(player.PlayerData.source, account) or 0
        else
            return player.Functions.GetMoney(account) or 0
        end
    end

    Framework.HasMoney = function(player, account, amount)
        return Framework.GetMoney(player, account) >= amount
    end

    -- Returns { [src] = playerTable } for all connected players
    Framework.GetAllPlayers = function()
        if fw == 'qbx' then
            return exports.qbx_core:GetQBPlayers() or {}
        else
            return QBCore.Functions.GetQBPlayers() or {}
        end
    end

    -- Returns the server source ID from a player table
    Framework.GetSource = function(player)
        return player and player.PlayerData.source
    end

-- ============================================================
-- ESX
-- ============================================================
elseif fw == 'esx' then

    local ESX = nil
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

    -- Fallback se TriggerEvent não preencheu (ESX Legacy usa exports)
    if not ESX then
        ESX = exports['es_extended']:getSharedObject()
    end

    Framework.GetPlayer = function(src)
        return ESX.Player(src)
    end

    Framework.FindPlayerByCitizenId = function(citizenId)
        for _, pid in ipairs(GetPlayers()) do
            local xP = ESX.Player(tonumber(pid))
            if xP and xP.getIdentifier() == citizenId then
                return tonumber(pid)
            end
        end
        return nil
    end

    Framework.GetCitizenId = function(player)
        return player and player.getIdentifier()
    end

    Framework.GetCharInfo = function(player)
        if not player then return nil end
        local name = player.name or ''
        local parts = {}
        for part in name:gmatch('%S+') do parts[#parts + 1] = part end
        return {
            firstname = parts[1] or '',
            lastname  = parts[2] or '',
        }
    end

    Framework.GetCharName = function(player)
        if not player then return 'Motorista' end
        local name = player.getName and player.getName()
        return name or player.name or 'Motorista'
    end

    Framework.GetJob = function(player)
        return player and player.job or { name = '', label = '' }
    end

    Framework.AddMoney = function(player, account, amount, reason)
        if not player then return end
        if account == 'cash' then
            player.addAccountMoney('money', amount)
        else
            player.addAccountMoney('bank', amount)
        end
    end

    Framework.RemoveMoney = function(player, account, amount, reason)
        if not player then return false end
        local have = Framework.GetMoney(player, account)
        if have < amount then return false end
        if account == 'cash' then
            player.removeAccountMoney('money', amount)
        else
            player.removeAccountMoney('bank', amount)
        end
        return true
    end

    Framework.GetMoney = function(player, account)
        if not player then return 0 end
        local accName = (account == 'cash') and 'money' or 'bank'
        local acc = player.getAccount(accName)
        return acc and acc.money or 0
    end

    Framework.HasMoney = function(player, account, amount)
        return Framework.GetMoney(player, account) >= amount
    end

    -- Returns { [src] = playerTable } for all connected players
    Framework.GetAllPlayers = function()
        local result = {}
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            local xP = ESX.Player(src)
            if xP then result[src] = xP end
        end
        return result
    end

    -- Returns the server source ID from a player table
    Framework.GetSource = function(player)
        return player and player.source
    end

else
    error(('[aurp_trucker] Config.Framework inválido: "%s". Use "qbx", "qbcore" ou "esx"'):format(fw))
end

-- ============================================================
-- Universal Player-Source Money Wrappers (aceita src ou Player)
-- ============================================================
Framework.GetPlayerMoney = function(src, account)
    local player = (type(src) == 'table') and src or Framework.GetPlayer(src)
    if not player then return 0 end
    return Framework.GetMoney(player, account)
end

Framework.AddPlayerMoney = function(src, account, amount, reason)
    local player = (type(src) == 'table') and src or Framework.GetPlayer(src)
    if not player then return false end
    return Framework.AddMoney(player, account, amount, reason)
end

Framework.RemovePlayerMoney = function(src, account, amount, reason)
    local player = (type(src) == 'table') and src or Framework.GetPlayer(src)
    if not player then return false end
    return Framework.RemoveMoney(player, account, amount, reason)
end

if Config.Debug then
    print(('[aurp_trucker] Framework: %s'):format(fw))
end

