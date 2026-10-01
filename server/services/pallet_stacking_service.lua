-- =======================================================================
-- AUST_trucker — server/services/pallet_stacking_service.lua
-- Serviço Autoritativo de Stacking Pallet (OneSync StateBags + Havok Fail-Closed)
-- Inspirado na engenharia de consolidação industrial do plt_lumberjack
-- =======================================================================

PalletStackingService = {}
local StackingSessions = {}

---Inicia uma sessão de montagem física de paletes para um frete
---@param citizenId string
---@param src number
---@param jobId string|number
---@param warehouse table
---@param requiredPallets number
function PalletStackingService.StartSession(citizenId, src, jobId, warehouse, requiredPallets)
    if not Config.Stacking or not Config.Stacking.Enabled then return false end
    requiredPallets = math.min(12, math.max(1, tonumber(requiredPallets) or 4))

    -- Limpa sessão anterior se houver
    PalletStackingService.Cleanup(citizenId)

    local palletBases = {}
    local palletBaseNetIds = {}
    local maxPieces = Config.Stacking.PiecesPerPallet or 4

    -- Coordenadas de spawn para montagem
    local palletSpawns = warehouse.PalletSpawns or {}
    local anchor = warehouse.PalletStagingAnchor or vector3(1225.0, -3180.0, 4.53)
    local rad = math.rad(warehouse.PalletStagingHeading or 90.0)
    local rowDir = vector3(math.cos(rad), math.sin(rad), 0.0)
    local colDir = vector3(-math.sin(rad), math.cos(rad), 0.0)

    for i = 1, requiredPallets do
        local pos
        if palletSpawns[i] then
            pos = vector3(palletSpawns[i].x, palletSpawns[i].y, palletSpawns[i].z)
        else
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            pos = anchor + rowDir * (col * 2.2) + colDir * (row * 2.2)
        end

        local baseModel = joaat(Config.Stacking.BasePalletModel or 'prop_biotech_pallet')
        local baseObj = CreateObject(baseModel, pos.x, pos.y, pos.z + 0.05, true, true, false)
        local timeout = GetGameTimer() + 3000
        while not DoesEntityExist(baseObj) and GetGameTimer() < timeout do Wait(20) end

        if DoesEntityExist(baseObj) then
            FreezeEntityPosition(baseObj, true)
            SetEntityDistanceCullingRadius(baseObj, 0.0)

            local pNet = NetworkGetNetworkIdFromEntity(baseObj)
            local entState = Entity(baseObj).state

            entState:set('isStackingPallet', true, true)
            entState:set('stackPieces', 0, true)
            entState:set('maxPieces', maxPieces, true)
            entState:set('sessionOwner', citizenId, true)
            entState:set('slotIdx', i, true)
            entState:set('baseCoords', { x = pos.x, y = pos.y, z = pos.z }, true)

            table.insert(palletBases, baseObj)
            table.insert(palletBaseNetIds, pNet)
        end
    end

    -- Cria o Stockpile (estoque de itens/caixas para pegar)
    local stockpilePos = warehouse.PalletSpawns and warehouse.PalletSpawns[1] and (vector3(warehouse.PalletSpawns[1].x - 3.5, warehouse.PalletSpawns[1].y, warehouse.PalletSpawns[1].z)) or (anchor - vector3(3.0, 0.0, 0.0))
    local stockModel = joaat(Config.Stacking.ItemStockpileModel or 'prop_boxpile_07d')
    local stockpileObj = CreateObject(stockModel, stockpilePos.x, stockpilePos.y, stockpilePos.z, true, true, false)
    local stockTimeout = GetGameTimer() + 3000
    while not DoesEntityExist(stockpileObj) and GetGameTimer() < stockTimeout do Wait(20) end

    local stockpileNetId = 0
    if DoesEntityExist(stockpileObj) then
        FreezeEntityPosition(stockpileObj, true)
        SetEntityDistanceCullingRadius(stockpileObj, 0.0)
        Entity(stockpileObj).state:set('isStockpile', true, true)
        Entity(stockpileObj).state:set('sessionOwner', citizenId, true)
        stockpileNetId = NetworkGetNetworkIdFromEntity(stockpileObj)
    end

    StackingSessions[citizenId] = {
        jobId = jobId,
        src = src,
        requiredPallets = requiredPallets,
        palletBases = palletBases,
        palletBaseNetIds = palletBaseNetIds,
        stockpileObj = stockpileObj,
        finishedPallets = {},
        finishedNetIds = {},
        isComplete = false
    }

    -- Notifica o cliente para registrar as zonas de ox_target
    TriggerClientEvent('aurp_trucker:client:startStackingSession', src, {
        jobId = jobId,
        requiredPallets = requiredPallets,
        palletNetIds = palletBaseNetIds,
        stockpileNetId = stockpileNetId,
        stockpileCoords = stockpilePos
    })

    print(("[AUST_Trucker Stacking] Sessão iniciada para %s com %d bases de paletes."):format(citizenId, #palletBases))
    return true
end

---Adiciona uma peça a uma base de palete (Server Authority + Fail-Closed)
---@param src number
---@param palletNetId number
---@param isQuickStack? boolean
RegisterNetEvent('aurp_trucker:server:addPieceToStack', function(palletNetId, isQuickStack)
    local src = source
    local player = Framework.GetPlayerFromId(src)
    if not player then return end
    local citizenId = player.PlayerData and player.PlayerData.citizenid or player.identifier or tostring(src)

    local session = StackingSessions[citizenId]
    if not session or session.isComplete then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Nenhuma sessão de empilhamento ativa.' })
        return
    end

    local pallet = NetworkGetEntityFromNetworkId(palletNetId)
    if not pallet or not DoesEntityExist(pallet) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Palete não encontrado no mapa.' })
        return
    end

    -- Verificação de autoridade e proximidade
    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)
    local palletCoords = GetEntityCoords(pallet)
    if #(pCoords - palletCoords) > 6.0 and not isQuickStack then
        print(("[AUST_Trucker AntiCheat] Jogador %s tentou empilhar palete fora de alcance (%0.2fm)"):format(citizenId, #(pCoords - palletCoords)))
        return
    end

    local entState = Entity(pallet).state
    if entState.sessionOwner ~= citizenId then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Este palete pertence a outro frete.' })
        return
    end

    local current = (entState.stackPieces or 0) + 1
    local maxPieces = entState.maxPieces or Config.Stacking.PiecesPerPallet or 4

    if current < maxPieces then
        -- Transição visual parcial via StateBag
        entState:set('stackPieces', current, true)

        -- Substituição controlada do prop parcial (Fail-Closed Havok)
        local stageModelStr = Config.Stacking.StageProps[current]
        if stageModelStr then
            local stageModel = joaat(stageModelStr)
            local rot = GetEntityRotation(pallet, 2)
            local baseCoords = palletCoords

            local nextObj = CreateObject(stageModel, baseCoords.x, baseCoords.y, baseCoords.z, true, true, false)
            local timeout = GetGameTimer() + 2000
            while not DoesEntityExist(nextObj) and GetGameTimer() < timeout do Wait(20) end

            if DoesEntityExist(nextObj) then
                SetEntityRotation(nextObj, rot.x, rot.y, rot.z, 2, true)
                FreezeEntityPosition(nextObj, true)
                SetEntityDistanceCullingRadius(nextObj, 0.0)

                local nextNet = NetworkGetNetworkIdFromEntity(nextObj)
                local nextState = Entity(nextObj).state
                nextState:set('isStackingPallet', true, true)
                nextState:set('stackPieces', current, true)
                nextState:set('maxPieces', maxPieces, true)
                nextState:set('sessionOwner', citizenId, true)
                nextState:set('slotIdx', entState.slotIdx, true)

                -- Atualiza na tabela da sessão
                for idx, ent in ipairs(session.palletBases) do
                    if ent == pallet then
                        session.palletBases[idx] = nextObj
                        session.palletBaseNetIds[idx] = nextNet
                        break
                    end
                end

                DeleteEntity(pallet)
                TriggerClientEvent('aurp_trucker:client:updatePalletNetId', src, palletNetId, nextNet, current)
            end
        end

        TriggerClientEvent('ox_lib:notify', src, {
            type = 'info',
            title = 'Montagem de Palete',
            description = ('Peça adicionada! Progresso: %d/%d'):format(current, maxPieces)
        })
    else
        -- TRANSIÇÃO ATÔMICA CONSOLIDADA (100% montado):
        -- Deleta prop temporário e gera o Palete Consolidado Oficial
        local finalModelStr = Config.Stacking.StageProps[4] or Config.Polarix.DefaultPalletModel
        local finalModel = joaat(finalModelStr)
        local rot = GetEntityRotation(pallet, 2)
        local finalCoords = palletCoords

        local finalObj = CreateObject(finalModel, finalCoords.x, finalCoords.y, finalCoords.z, true, true, false)
        local timeout = GetGameTimer() + 3000
        while not DoesEntityExist(finalObj) and GetGameTimer() < timeout do Wait(20) end

        if DoesEntityExist(finalObj) then
            SetEntityRotation(finalObj, rot.x, rot.y, rot.z, 2, true)
            FreezeEntityPosition(finalObj, true)
            SetEntityDistanceCullingRadius(finalObj, 0.0)

            local finalNet = NetworkGetNetworkIdFromEntity(finalObj)
            local finalState = Entity(finalObj).state
            finalState:set('isMissionPallet', true, true)
            finalState:set('isConsolidated', true, true)
            finalState:set('sessionOwner', citizenId, true)

            -- Remove da lista de bases e insere na lista de paletes finalizados
            for idx, ent in ipairs(session.palletBases) do
                if ent == pallet then
                    table.remove(session.palletBases, idx)
                    table.remove(session.palletBaseNetIds, idx)
                    break
                end
            end

            table.insert(session.finishedPallets, finalObj)
            table.insert(session.finishedNetIds, finalNet)

            -- Deleta a base provisória
            DeleteEntity(pallet)

            -- Registra no PlayerJobEntities para o pipeline de frete
            if VP_Trucker.PlayerJobEntities[citizenId] then
                VP_Trucker.PlayerJobEntities[citizenId].palletNetIds = VP_Trucker.PlayerJobEntities[citizenId].palletNetIds or {}
                table.insert(VP_Trucker.PlayerJobEntities[citizenId].palletNetIds, finalNet)
            end

            TriggerClientEvent('ox_lib:notify', src, {
                type = 'success',
                title = 'Palete Consolidado!',
                description = ('Palete %d/%d finalizado com sucesso!'):format(#session.finishedNetIds, session.requiredPallets)
            })

            TriggerClientEvent('aurp_trucker:client:palletConsolidated', src, finalNet, #session.finishedNetIds, session.requiredPallets)

            -- Se todos os paletes foram consolidados:
            if #session.finishedNetIds >= session.requiredPallets then
                session.isComplete = true

                -- Remove o stockpile
                if session.stockpileObj and DoesEntityExist(session.stockpileObj) then
                    DeleteEntity(session.stockpileObj)
                    session.stockpileObj = nil
                end

                -- Registra flag de bônus no job ativo
                if VP_Trucker.ActiveJobs and VP_Trucker.ActiveJobs[citizenId] then
                    VP_Trucker.ActiveJobs[citizenId].stackedWithBonus = true
                end

                TriggerClientEvent('aurp_trucker:client:allPalletsConsolidated', src, session.finishedNetIds)
                print(("[AUST_Trucker Stacking] Todos os %d paletes foram consolidados com bônus para %s."):format(session.requiredPallets, citizenId))
            end
        end
    end
end)

---Limpeza de entidades de stacking em caso de cancelamento ou queda
---@param citizenId string
function PalletStackingService.Cleanup(citizenId)
    local session = StackingSessions[citizenId]
    if not session then return end

    if session.palletBases then
        for _, ent in ipairs(session.palletBases) do
            if DoesEntityExist(ent) then DeleteEntity(ent) end
        end
    end

    if session.stockpileObj and DoesEntityExist(session.stockpileObj) then
        DeleteEntity(session.stockpileObj)
    end

    StackingSessions[citizenId] = nil
end

AddEventHandler('playerDropped', function()
    local src = source
    local player = Framework.GetPlayerFromId(src)
    if player then
        local citizenId = player.PlayerData and player.PlayerData.citizenid or player.identifier or tostring(src)
        PalletStackingService.Cleanup(citizenId)
    end
end)

RegisterNetEvent('aurp_trucker:server:cancelStacking', function()
    local src = source
    local player = Framework.GetPlayerFromId(src)
    if player then
        local citizenId = player.PlayerData and player.PlayerData.citizenid or player.identifier or tostring(src)
        PalletStackingService.Cleanup(citizenId)
    end
end)
