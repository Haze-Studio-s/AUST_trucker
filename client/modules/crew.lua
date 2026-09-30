-- aurp_trucker — client/modules/crew.lua
-- FASE 2: MÓDULO 1 - CREW MULTIPLAYER (CO-OP LOGÍSTICO)

local CurrentCrew = nil

-- Abre o menu de gerenciamento da Crew
local function OpenCrewMenu()
    lib.callback('aurp_trucker:server:getCrewData', false, function(crewData)
        if not crewData or not crewData.inCrew then
            lib.registerContext({
                id = 'trucker_crew_none',
                title = '🚚 Equipe de Logística (Co-op)',
                options = {
                    {
                        title = 'Criar Nova Equipe',
                        description = 'Crie um grupo para compartilhar contratos de transporte e ganhar +15% de bônus.',
                        icon = 'users-rectangle',
                        arrow = true,
                        onSelect = function()
                            TriggerServerEvent('aurp_trucker:server:createCrew')
                        end
                    }
                }
            })
            lib.showContext('trucker_crew_none')
            return
        end

        CurrentCrew = crewData
        local options = {}

        -- Lista de Membros
        local memberItems = {}
        for _, m in ipairs(crewData.members or {}) do
            local subtitle = m.isLeader and '👑 Líder' or 'Operador'
            if m.src == GetPlayerServerId(PlayerId()) then
                subtitle = subtitle .. ' (Você)'
            end
            table.insert(options, {
                title = m.name,
                description = subtitle,
                icon = m.isLeader and 'crown' or 'user',
                readOnly = true
            })
        end

        -- Opções de Liderança
        if crewData.isLeader then
            local canInvite = #(crewData.members or {}) < (crewData.maxMembers or 4)
            table.insert(options, {
                title = 'Convidar Jogador Próximo',
                description = canInvite and 'Convide caminhoneiros próximos (raio de 20m) para sua equipe.' or 'A equipe já atingiu o limite de membros.',
                icon = 'user-plus',
                disabled = not canInvite,
                arrow = true,
                onSelect = function()
                    local myPed = cache.ped or PlayerPedId()
                    local myCoords = GetEntityCoords(myPed)
                    local nearbyPlayers = {}

                    local activePlayers = GetActivePlayers()
                    for _, player in ipairs(activePlayers) do
                        if player ~= PlayerId() then
                            local tPed = GetPlayerPed(player)
                            if DoesEntityExist(tPed) then
                                local dist = #(myCoords - GetEntityCoords(tPed))
                                if dist <= (Config.Crew and Config.Crew.InviteDistance or 20.0) then
                                    local serverId = GetPlayerServerId(player)
                                    table.insert(nearbyPlayers, {
                                        title = ('Caminhoneiro #%d'):format(serverId),
                                        description = ('Distância: %.1fm'):format(dist),
                                        icon = 'user',
                                        onSelect = function()
                                            TriggerServerEvent('aurp_trucker:server:invitePlayer', serverId)
                                        end
                                    })
                                end
                            end
                        end
                    end

                    if #nearbyPlayers == 0 then
                        lib.notify({
                            title = 'Nenhum Jogador',
                            description = 'Nenhum outro jogador encontrado em um raio de 20 metros.',
                            type = 'warning'
                        })
                        return
                    end

                    lib.registerContext({
                        id = 'trucker_crew_invite_list',
                        title = 'Convidar para Equipe',
                        menu = 'trucker_crew_manage',
                        options = nearbyPlayers
                    })
                    lib.showContext('trucker_crew_invite_list')
                end
            })

            table.insert(options, {
                title = 'Desfazer Equipe',
                description = 'Encerra permanentemente o grupo de entrega.',
                icon = 'trash-can',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Desfazer Equipe?',
                        content = 'Tem certeza que deseja encerrar a equipe? Todos os membros serão removidos.',
                        centered = true,
                        cancel = true
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('aurp_trucker:server:disbandCrew')
                    end
                end
            })
        else
            table.insert(options, {
                title = 'Sair da Equipe',
                description = 'Deixe a equipe atual e volte ao trabalho solo.',
                icon = 'right-from-bracket',
                onSelect = function()
                    TriggerServerEvent('aurp_trucker:server:leaveCrew')
                end
            })
        end

        lib.registerContext({
            id = 'trucker_crew_manage',
            title = ('🚚 Equipe Logística (%d/%d)'):format(#(crewData.members or {}), crewData.maxMembers or 4),
            options = options
        })
        lib.showContext('trucker_crew_manage')
    end)
end

-- Recebimento de convite via alertDialog
RegisterNetEvent('aurp_trucker:client:receiveCrewInvite', function(crewId, inviterName)
    CreateThread(function()
        local alert = lib.alertDialog({
            header = 'Convite de Equipe Logística',
            content = ('O caminhoneiro **%s** convidou você para ingressar na equipe de transporte!\n\nVocês trabalharão juntos nos mesmos fretes e dividirão o pagamento com um **bônus exclusivo de +15%%**.'):format(inviterName),
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Aceitar Convite',
                cancel = 'Recusar'
            }
        })

        if alert == 'confirm' then
            TriggerServerEvent('aurp_trucker:server:respondCrewInvite', crewId, true)
        else
            TriggerServerEvent('aurp_trucker:server:respondCrewInvite', crewId, false)
        end
    end)
end)

-- Atualização reativa de dados da Crew
RegisterNetEvent('aurp_trucker:client:crewUpdated', function(crewData)
    CurrentCrew = crewData
end)

-- Comando oficial /truckercrew
RegisterCommand('truckercrew', function()
    OpenCrewMenu()
end, false)

-- Exportação para outros módulos da UI
exports('OpenCrewMenu', OpenCrewMenu)
