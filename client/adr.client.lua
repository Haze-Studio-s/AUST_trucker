-- aurp_trucker — client/adr.client.lua
-- Fase 5: NPC Examinador ADR, fluxo de exame e callbacks NUI

local examinerPed = nil

local function DoAdrExam(adrType)
    -- As perguntas são sorteadas pelo SERVIDOR (uso único); o client só as exibe e devolve as respostas
    local issued = lib.callback.await('aurp_trucker:getAdrExamQuestions', false, adrType)
    if not issued or not issued.success or type(issued.questions) ~= 'table' or #issued.questions < 3 then
        if issued and issued.reason == 'retry_cooldown' then
            local mins = math.ceil((issued.remainingSeconds or 1800) / 60)
            lib.notify({ title = 'ADR', description = ('Aguarde %d min antes de tentar novamente'):format(mins), type = 'error', duration = 8000 })
        else
            lib.notify({ title = 'ADR', description = (issued and issued.reason) or 'Não foi possível iniciar o exame', type = 'error' })
        end
        return
    end

    local picked = {}
    for _, sq in ipairs(issued.questions) do
        table.insert(picked, { qIdx = sq.qIdx, q = { q = sq.q, options = sq.options } })
    end

    -- Build lib.inputDialog rows
    local rows = {}
    for _, pq in ipairs(picked) do
        local q = pq.q
        local selectOptions = {}
        for i, opt in ipairs(q.options) do
            table.insert(selectOptions, { value = tostring(i), label = opt })
        end
        table.insert(rows, {
            type     = 'select',
            label    = q.q,
            options  = selectOptions,
            required = true,
        })
    end

    local label = Config.Adr.TypeLabels[adrType]
    local result = lib.inputDialog(('Exame ADR — %s ($%d)'):format(label, Config.Adr.ExamCost[adrType]), rows)
    if not result then return end  -- player cancelled

    -- Build answers list
    local answers = {}
    for i, pq in ipairs(picked) do
        table.insert(answers, { qIdx = pq.qIdx, answer = tonumber(result[i]) or 0 })
    end

    local response = lib.callback.await('aurp_trucker:submitAdrExam', false, { adrType = adrType, questions = answers })
    if not response then
        lib.notify({ title = 'ADR', description = 'Sem resposta do servidor', type = 'error' })
        return
    end

    if not response.success then
        if response.reason == 'retry_cooldown' then
            local mins = math.ceil((response.remainingSeconds or 1800) / 60)
            lib.notify({ title = 'ADR', description = ('Aguarde %d min antes de tentar novamente'):format(mins), type = 'error', duration = 8000 })
        else
            lib.notify({ title = 'ADR', description = response.reason or 'Erro', type = 'error' })
        end
        return
    end

    if response.passed then
        lib.notify({ title = 'ADR', description = ('Aprovado! Certificação válida por 30 dias.'), type = 'success', duration = 8000 })
        SendNUIMessage({ action = 'adrCertGranted', adrType = adrType, expiresAt = response.expiresAt })
    else
        local correct = response.correct or 0
        lib.notify({ title = 'ADR', description = ('Reprovado (%d/3 corretas). Cooldown: 30 min. Taxa não devolvida.'):format(correct), type = 'error', duration = 10000 })
    end
end

CreateThread(function()
    -- Spawn ped
    local model = Config.Adr.ExaminerPed
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end

    local loc = Config.Adr.ExaminerLocation
    examinerPed = CreatePed(4, model, loc.x, loc.y, loc.z - 1.0, Config.Adr.ExaminerHeading, false, false)
    FreezeEntityPosition(examinerPed, true)
    SetEntityInvincible(examinerPed, true)
    SetBlockingOfNonTemporaryEvents(examinerPed, true)
    SetModelAsNoLongerNeeded(model)

    -- ox_target sphere zone
    exports.ox_target:addSphereZone({
        name   = 'adr_examiner',
        coords = Config.Adr.ExaminerLocation,
        radius = Config.Adr.ExaminerRadius,
        options = {
            {
                name     = 'adr_exam',
                label    = 'Fazer Exame ADR',
                icon     = 'fas fa-certificate',
                distance = Config.Adr.ExaminerRadius,
                onSelect = function()
                    -- Build context menu to pick ADR type
                    local menuOptions = {}
                    for adrType, label in pairs(Config.Adr.TypeLabels) do
                        local t = adrType  -- capture
                        table.insert(menuOptions, {
                            title       = label,
                            description = ('Taxa: $%d'):format(Config.Adr.ExamCost[t] or 0),
                            icon        = 'fas fa-flask-vial',
                            onSelect    = function()
                                DoAdrExam(t)
                            end,
                        })
                    end
                    lib.registerContext({ id = 'adr_type_menu', title = 'Exame ADR — Escolha o Tipo', options = menuOptions })
                    lib.showContext('adr_type_menu')
                end,
            },
            {
                name     = 'adr_renew_npc',
                label    = 'Renovar Certificação ADR',
                icon     = 'fas fa-rotate',
                distance = Config.Adr.ExaminerRadius,
                onSelect = function()
                    -- Ask server which certs this player has (expired OR valid) — show renewal menu
                    local menuOptions = {}
                    for adrType, label in pairs(Config.Adr.TypeLabels) do
                        local t = adrType  -- capture
                        table.insert(menuOptions, {
                            title       = label,
                            description = ('Taxa renovação: $%d (sem re-exame)'):format(Config.Adr.RenewalCost[t] or 0),
                            icon        = 'fas fa-id-card',
                            onSelect    = function()
                                local response = lib.callback.await('aurp_trucker:renewAdrCert', false, t)
                                if not response then return end
                                if response.success then
                                    lib.notify({ title = 'ADR', description = ('Certificação %s renovada por 30 dias!'):format(label), type = 'success', duration = 8000 })
                                    SendNUIMessage({ action = 'adrCertGranted', adrType = t, expiresAt = response.expiresAt })
                                else
                                    lib.notify({ title = 'ADR', description = response.reason or 'Erro na renovação', type = 'error' })
                                end
                            end,
                        })
                    end
                    lib.registerContext({ id = 'adr_renew_menu', title = 'Renovar ADR — Escolha o Tipo', options = menuOptions })
                    lib.showContext('adr_renew_menu')
                end,
            },
        },
    })
end)

-- NUI → set GPS to examiner
RegisterNUICallback('setAdrGps', function(data, cb)
    local loc = Config.Adr.ExaminerLocation
    SetNewWaypoint(loc.x, loc.y)
    lib.notify({ title = 'ADR', description = 'GPS marcado para o Centro de Certificação', type = 'inform' })
    cb('ok')
end)

-- NUI → renew cert (direct from PDA, no NPC needed)
RegisterNUICallback('renewAdrCert', function(data, cb)
    local adrType = data and data.adrType
    if not adrType then cb({ success = false, reason = 'Tipo inválido' }) return end

    local response = lib.callback.await('aurp_trucker:renewAdrCert', false, adrType)
    if response and response.success then
        SendNUIMessage({ action = 'adrCertGranted', adrType = adrType, expiresAt = response.expiresAt })
    end
    cb(response or { success = false, reason = 'Sem resposta' })
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    if examinerPed and DoesEntityExist(examinerPed) then
        DeleteEntity(examinerPed)
    end
    exports.ox_target:removeZone('adr_examiner')
end)
