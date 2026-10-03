-- aurp_trucker — client/convoy.client.lua
-- Client-side: party UI, convoy blips, GPS suppression, CB radio HUD
-- Carrega APÓS hud.client.lua (usa evento aurp_trucker:client:truckStateChanged de lá)

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local localCitizenId = nil  -- populado no OnPlayerLoaded

local ConvoyState = {
    partyId      = nil,
    isLeader     = false,
    members      = {},     -- lista: { citizenid, name, isLeader, online }
    convoyActive = false,
    isInTruck    = false,  -- atualizado via truckStateChanged de hud.client.lua
    gpsBlocked   = false,
    memberBlips  = {},     -- { [citizenid] = blipHandle }
    cbLog        = {},     -- últimas 5 mensagens: { sender, text, timestamp }
    maxSize      = 6,
}

-- ============================================================
-- CAPTURA DO CITIZENID LOCAL
-- ============================================================

-- Captura citizenid de forma compatível com QBX, QBCore e ESX
local function CaptureLocalCitizenId()
    if QBX and QBX.PlayerData then
        localCitizenId = QBX.PlayerData.citizenid
    elseif QBCore then
        local pd = QBCore.Functions.GetPlayerData()
        localCitizenId = pd and pd.citizenid
    elseif ESX then
        local pd = ESX.GetPlayerData()
        localCitizenId = pd and pd.identifier
    end
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', CaptureLocalCitizenId)
AddEventHandler('esx:playerLoaded', CaptureLocalCitizenId)
AddEventHandler('esx:setPlayerData', CaptureLocalCitizenId)

-- Tentar capturar imediatamente caso o player já esteja carregado
CreateThread(function()
    Wait(500)
    CaptureLocalCitizenId()
end)

-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

-- Atualização de estado do party (broadcast após qualquer mudança)
RegisterNetEvent('aurp_trucker:client:partyUpdate', function(data)
    if not data or not data.party then return end
    local party = data.party
    ConvoyState.partyId  = party.partyId
    ConvoyState.isLeader = party.isLeader
    ConvoyState.members  = party.members or {}
    ConvoyState.maxSize  = party.maxSize or 6

    -- Sincronizar convoyActive sem sobrescrever se já true (pode chegar antes do convoyStarted)
    if party.convoyActive ~= nil then
        ConvoyState.convoyActive = party.convoyActive
    end

    -- Notificar NUI
    SendNUIMessage({ action = 'partyUpdate', party = party })
    TriggerEvent('aurp_trucker:client:refreshNUI')
end)

-- Party dissolvido pelo líder
RegisterNetEvent('aurp_trucker:client:partyDisbanded', function()
    ConvoyState.partyId      = nil
    ConvoyState.isLeader     = false
    ConvoyState.members      = {}
    ConvoyState.convoyActive = false
    ConvoyState.gpsBlocked   = false
    -- Limpar blips
    for cid, blip in pairs(ConvoyState.memberBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    ConvoyState.memberBlips = {}
    SendNUIMessage({ action = 'partyUpdate', party = nil })
    TriggerEvent('aurp_trucker:client:refreshNUI')
end)

-- Convoy iniciado pelo líder
RegisterNetEvent('aurp_trucker:client:convoyStarted', function(data)
    ConvoyState.convoyActive = true
    SendNUIMessage({ action = 'convoyStarted' })
    lib.notify({ title = 'Convoy', description = 'Convoy iniciado! Siga as instruções pelo rádio CB.', type = 'info' })
end)

-- Convoy concluído ou cancelado
RegisterNetEvent('aurp_trucker:client:convoyEnded', function()
    ConvoyState.convoyActive = false
    ConvoyState.gpsBlocked   = false
    -- Limpar blips de membros
    for cid, blip in pairs(ConvoyState.memberBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    ConvoyState.memberBlips = {}
    SendNUIMessage({ action = 'convoyEnded' })
end)

-- Convite de party recebido
RegisterNetEvent('aurp_trucker:client:partyInvite', function(data)
    -- data = { partyId, partyName, leaderName }
    CreateThread(function()
        local confirm = lib.alertDialog({
            header   = 'Convite de Grupo de Transporte',
            content  = ('%s convidou você para o grupo "%s". Deseja aceitar o convite?'):format(data.leaderName or 'Um motorista', data.partyName or 'Logística'),
            centered = true,
            cancel   = true,
        })
        if confirm == 'confirm' then
            local ok, result = pcall(lib.callback.await, 'aurp_trucker:partyAccept', false, data.partyId)
            if not ok then
                lib.notify({ title = 'Grupos', description = 'Falha ao conectar ao servidor', type = 'error' })
            elseif result and not result.success then
                lib.notify({ title = 'Grupos', description = result.reason or 'Erro ao entrar no grupo', type = 'error' })
            else
                lib.notify({ title = 'Grupos', description = 'Você ingressou no grupo com sucesso!', type = 'success' })
                TriggerEvent('aurp_trucker:client:refreshNUI')
            end
        end
    end)
end)

-- Posições dos membros para blips
RegisterNetEvent('aurp_trucker:client:positionsUpdate', function(positions)
    -- positions = { [citizenid] = { x, y, z, name, isTruck } }
    for cid, pos in pairs(positions) do
        if cid ~= localCitizenId then
            local blip = ConvoyState.memberBlips[cid]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(pos.x, pos.y, pos.z)
                SetBlipSprite(blip, 477)   -- caminhão
                SetBlipColour(blip, 5)     -- amarelo
                SetBlipScale(blip, 0.8)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(pos.name or cid)
                EndTextCommandSetBlipName(blip)
                ConvoyState.memberBlips[cid] = blip
            else
                SetBlipCoords(blip, pos.x, pos.y, pos.z)
            end
        end
    end
end)

-- Mensagem CB radio recebida
RegisterNetEvent('aurp_trucker:client:cbMessage', function(data)
    -- data = { sender, message, timestamp }
    table.insert(ConvoyState.cbLog, {
        sender    = data.sender,
        text      = data.message,
        timestamp = GetGameTimer(),
    })
    -- Manter apenas as últimas 5
    while #ConvoyState.cbLog > 5 do
        table.remove(ConvoyState.cbLog, 1)
    end
end)

-- ============================================================
-- GPS SUPPRESSION (Blind Driver)
-- ============================================================

-- hud.client.lua dispara este evento quando isTruck muda
AddEventHandler('aurp_trucker:client:truckStateChanged', function(isTruck)
    ConvoyState.isInTruck = isTruck
end)

-- client.lua dispara este evento quando cria o blip de destino em StartLoading()
AddEventHandler('aurp_trucker:client:jobStartedConvoy', function(blipHandle)
    if not ConvoyState.convoyActive then return end
    -- Apenas drivers (isInTruck = true) ficam cegos; escorts mantêm GPS
    if not ConvoyState.isInTruck then return end

    if DoesBlipExist(blipHandle) then
        RemoveBlip(blipHandle)
    end
    ConvoyState.gpsBlocked = true
    lib.notify({ title = 'Convoy', description = 'GPS bloqueado — use o rádio CB para navegação!', type = 'warning', duration = 8000 })
end)

-- Limpar gpsBlocked quando job concluído
RegisterNetEvent('aurp_trucker:client:jobCompleted', function()
    ConvoyState.gpsBlocked = false
end)

-- ============================================================
-- THREAD: HUD CB RADIO (500ms)
-- ============================================================

CreateThread(function()
    while true do
        Wait(500)
        if #ConvoyState.cbLog == 0 then goto continue end

        local now = GetGameTimer()
        local duration = Config.Party.cbMessageDuration * 1000

        -- Remover mensagens expiradas
        local i = 1
        while i <= #ConvoyState.cbLog do
            if (now - ConvoyState.cbLog[i].timestamp) >= duration then
                table.remove(ConvoyState.cbLog, i)
            else
                i = i + 1
            end
        end

        -- Renderizar mensagens restantes
        local y = 0.88
        for _, msg in ipairs(ConvoyState.cbLog) do
            local text = ('[CB] %s: %s'):format(msg.sender, msg.text)
            SetTextFont(0)
            SetTextScale(0.35, 0.35)
            SetTextColour(255, 230, 100, 220)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(0.02, y)
            y = y - 0.025
        end

        ::continue::
    end
end)

-- ============================================================
-- TECLA CB RADIO
-- ============================================================

-- Mapeamento key string → controle GTA input group 0
local _KEY_CTRL = { Z=20, Y=246, X=73, G=47, H=74, B=29, N=249, TAB=37 }
local cbRadioControl = _KEY_CTRL[(Config.Party.cbRadioKey or 'Z'):upper()] or 20

CreateThread(function()
    while true do
        -- Dormir 500ms quando fora de convoy/truck para não consumir frame budget
        if not ConvoyState.convoyActive or not ConvoyState.isInTruck then
            Wait(500)
            goto continue
        end

        Wait(0)  -- frame tick apenas quando convoy ativo e em truck

        if IsControlJustPressed(0, cbRadioControl) then
            CreateThread(function()
                local input = lib.inputDialog('Rádio CB', {
                    { type = 'input', label = 'Mensagem', placeholder = 'Digite sua mensagem...', maxLength = 100 }
                })
                if input and input[1] and input[1] ~= '' then
                    lib.callback.await('aurp_trucker:cbRadioSend', false, input[1])
                end
            end)
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: INDICADOR GPS BLOQUEADO (Blind Driver)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        if not ConvoyState.gpsBlocked then goto continue end

        -- Aviso persistente no canto da tela
        SetTextFont(0)
        SetTextScale(0.4, 0.4)
        SetTextColour(255, 80, 80, 200)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName('GPS BLOQUEADO — Use o Rádio CB [Z]')
        EndTextCommandDisplayText(0.02, 0.93)

        ::continue::
    end
end)

-- Limpeza ao parar o resource: remove blips dos membros do comboio
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, blip in pairs(ConvoyState.memberBlips or {}) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    ConvoyState.memberBlips = {}
end)
