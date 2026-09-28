-- Industries Client
-- Handles industry/economy UI interactions

RegisterNUICallback('getIndustries', function(data, cb)
    local ok, industries = pcall(lib.callback.await, 'aurp_trucker:getIndustries', false)
    cb(ok and industries or nil)
end)

RegisterNUICallback('industryGPS', function(data, cb)
    local industryId = data.industryId
    if not industryId then cb('ok') return end

    local industry = Config.Industries[industryId]
    if not industry or not industry.coords then
        lib.notify({ title = 'GPS', description = 'Indústria não encontrada', type = 'error' })
        cb('ok')
        return
    end

    SetWaypointOff()
    SetNewWaypoint(industry.coords.x + 0.0, industry.coords.y + 0.0)
    lib.notify({
        title = 'GPS',
        description = 'Rota marcada para ' .. (data.name or industry.name),
        type = 'inform'
    })
    cb('ok')
end)

RegisterNetEvent('aurp_trucker:updateIndustries', function(industries)
    SendNUIMessage({
        action = 'updateIndustries',
        industries = industries
    })
end)