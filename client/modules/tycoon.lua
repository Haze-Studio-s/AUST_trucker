-- aurp_trucker — client/modules/tycoon.lua
-- FASE 2: MÓDULO 2 - SISTEMA TYCOON (BASES PERSISTENTES & OFICINA PRIVADA)

local OwnedBases = {}
local BaseBlips = {}
local TycoonPoints = {}

-- Atualiza ou cria os blips das bases no mapa
local function RefreshBaseBlips()
    for _, blip in pairs(BaseBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    BaseBlips = {}

    for baseId, baseCfg in pairs(Config.TycoonBases or {}) do
        local isOwned = OwnedBases[baseId] == true
        local blip = AddBlipForCoord(baseCfg.coords.x, baseCfg.coords.y, baseCfg.coords.z)
        SetBlipSprite(blip, (baseCfg.blip and baseCfg.blip.sprite) or 357)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, (baseCfg.blip and baseCfg.blip.scale) or 0.85)
        SetBlipColour(blip, isOwned and 2 or 5) -- Verde se própria, amarelo/azul se à venda
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName((isOwned and "🏢 [Sua Base] " or "🏢 [À Venda] ") .. baseCfg.label)
        EndTextCommandSetBlipName(blip)
        BaseBlips[baseId] = blip
    end
end

-- Menu da Oficina Privada (Workshop)
local function OpenWorkshopMenu(baseId, baseCfg)
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        -- Se estiver a pé, tenta pegar o veículo mais próximo
        local pCoords = GetEntityCoords(ped)
        veh = lib.getClosestVehicle(pCoords, 5.0, false)
    end

    if not veh or veh == 0 or not DoesEntityExist(veh) then
        lib.notify({
            title = 'Oficina Privada',
            description = 'Traga um caminhão ou veículo até a área da oficina para realizar serviços.',
            type = 'warning'
        })
        return
    end

    local isTruck = false
    local vClass = GetVehicleClass(veh)
    if vClass == 10 or vClass == 11 or vClass == 20 then
        isTruck = true
    end

    local baseCost = (Config.WorkshopUpgrades and Config.WorkshopUpgrades.RepairBaseCost) or 1500
    local discount = baseCfg.repairDiscount or 0.40
    local discountedRepairCost = math.floor(baseCost * (1.0 - discount))

    local options = {
        {
            title = '🛠️ Reparo Completo & Restauração',
            description = ('Repara toda a lataria, motor e danos estruturais permanentes.\nCusto: $%d (com %d%% de desconto de proprietário)'):format(discountedRepairCost, math.floor(discount * 100)),
            icon = 'wrench',
            onSelect = function()
                lib.callback('aurp_trucker:server:repairVehicle', false, function(result)
                    if result and result.success then
                        if lib.progressBar then
                            lib.progressBar({
                                duration = 4000,
                                label = 'Oficina: Restaurando Veículo...',
                                useWhileDead = false,
                                canCancel = false,
                                disable = { car = true, move = true }
                            })
                        else
                            Wait(2000)
                        end

                        SetVehicleFixed(veh)
                        SetVehicleDeformationFixed(veh)
                        SetVehicleUndriveable(veh, false)
                        SetVehicleEngineHealth(veh, 1000.0)
                        SetVehicleBodyHealth(veh, 1000.0)
                        SetVehiclePetrolTankHealth(veh, 1000.0)

                        -- Restauração de integridade da Fase 1 se estiver em frete ativo
                        if ActiveJob then
                            ActiveJob.cargoHealth = 100
                            TriggerServerEvent('aurp_trucker:server:updateCargoHealth', ActiveJob.jobId, 100)
                        end

                        lib.notify({
                            title = 'Oficina Privada',
                            description = ('Veículo totalmente restaurado por $%d! Desconto de %d%% aplicado.'):format(result.cost, result.discount or 40),
                            type = 'success'
                        })
                    else
                        lib.notify({
                            title = 'Oficina Privada',
                            description = (result and result.message) or 'Falha ao realizar reparo.',
                            type = 'error'
                        })
                    end
                end, baseId)
            end
        }
    }

    -- Submenu de Upgrades de Performance e Chassi
    local upgradeCategories = {
        { id = 'Engine', label = 'Motor de Alta Potência', icon = 'gauge-high' },
        { id = 'Brakes', label = 'Freios Hidráulicos Reforçados', icon = 'stop' },
        { id = 'Transmission', label = 'Câmbio e Transmissão Pesada', icon = 'gears' },
        { id = 'Armor', label = 'Blindagem e Reforço de Chassi', icon = 'shield-halved' }
    }

    for _, cat in ipairs(upgradeCategories) do
        local catConfig = Config.WorkshopUpgrades and Config.WorkshopUpgrades[cat.id]
        if catConfig then
            table.insert(options, {
                title = cat.label,
                description = ('Visualizar upgrades disponíveis para %s'):format(cat.label),
                icon = cat.icon,
                arrow = true,
                onSelect = function()
                    local upgOptions = {}
                    for lvlIndex, upg in ipairs(catConfig) do
                        table.insert(upgOptions, {
                            title = upg.label,
                            description = ('Preço: $%d'):format(upg.price),
                            icon = 'circle-arrow-up',
                            onSelect = function()
                                lib.callback('aurp_trucker:server:applyUpgrade', false, function(res)
                                    if res and res.success then
                                        SetVehicleModKit(veh, 0)
                                        SetVehicleMod(veh, res.mod, res.level, false)
                                        lib.notify({
                                            title = 'Upgrade Instalado',
                                            description = ('%s instalado com sucesso no seu veículo!'):format(res.label),
                                            type = 'success'
                                        })
                                    else
                                        lib.notify({
                                            title = 'Oficina Privada',
                                            description = (res and res.message) or 'Falha ao instalar upgrade.',
                                            type = 'error'
                                        })
                                    end
                                end, baseId, cat.id, lvlIndex)
                            end
                        })
                    end

                    lib.registerContext({
                        id = 'trucker_workshop_cat_' .. cat.id,
                        title = cat.label,
                        menu = 'trucker_workshop_main',
                        options = upgOptions
                    })
                    lib.showContext('trucker_workshop_cat_' .. cat.id)
                end
            })
        end
    end

    lib.registerContext({
        id = 'trucker_workshop_main',
        title = ('🔧 Oficina Privada — %s'):format(baseCfg.label),
        options = options
    })
    lib.showContext('trucker_workshop_main')
end

-- Inicializa pontos de interação do Tycoon
local function SetupTycoonZones()
    -- Limpa pontos anteriores
    for _, pt in ipairs(TycoonPoints) do
        pcall(function() pt:remove() end)
    end
    TycoonPoints = {}

    for baseId, baseCfg in pairs(Config.TycoonBases or {}) do
        -- 1. Ponto de Compra / Gestão da Base
        local buyPoint = lib.points.new({
            coords = baseCfg.coords,
            distance = 3.0,
            onEnter = function()
                local isOwned = OwnedBases[baseId] == true
                if isOwned then
                    lib.showTextUI(('[E] - Gestão da Base: %s'):format(baseCfg.label), { position = 'left-center' })
                else
                    lib.showTextUI(('[E] - Comprar Base: %s ($%d)'):format(baseCfg.label, baseCfg.price), { position = 'left-center' })
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            nearby = function(self)
                DrawMarker(2, self.coords.x, self.coords.y, self.coords.z + 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.6, 30, 200, 120, 180, false, true, 2, false, nil, nil, false)
                if IsControlJustPressed(0, 38) then -- [E]
                    local isOwned = OwnedBases[baseId] == true
                    if isOwned then
                        lib.registerContext({
                            id = 'trucker_base_info_' .. baseId,
                            title = ('🏢 Base Própria — %s'):format(baseCfg.label),
                            options = {
                                {
                                    title = 'Propriedade Ativa',
                                    description = 'Você é o proprietário desta base logística comercial.',
                                    icon = 'check',
                                    readOnly = true
                                },
                                {
                                    title = 'Benefícios Ativos',
                                    description = ('• Desconto de combustível: %d%%\n• Desconto na oficina privada: %d%%'):format(
                                        math.floor((baseCfg.fuelDiscount or 0.25) * 100),
                                        math.floor((baseCfg.repairDiscount or 0.40) * 100)
                                    ),
                                    icon = 'percent',
                                    readOnly = true
                                },
                                {
                                    title = 'Ir para Oficina Privada',
                                    description = 'Acesse a oficina interna para reparos e melhorias da sua frota.',
                                    icon = 'wrench',
                                    onSelect = function()
                                        OpenWorkshopMenu(baseId, baseCfg)
                                    end
                                }
                            }
                        })
                        lib.showContext('trucker_base_info_' .. baseId)
                    else
                        local confirm = lib.alertDialog({
                            header = 'Adquirir Base Logística',
                            content = ('Deseja comprar a **%s** por **$%d**?\n\n**Benefícios permanentes:**\n- Oficina Privada própria\n- %d%% de desconto em combustível\n- %d%% de desconto em reparos e customizações de frota.'):format(
                                baseCfg.label,
                                baseCfg.price,
                                math.floor((baseCfg.fuelDiscount or 0.25) * 100),
                                math.floor((baseCfg.repairDiscount or 0.40) * 100)
                            ),
                            centered = true,
                            cancel = true,
                            labels = { confirm = 'Comprar Base', cancel = 'Cancelar' }
                        })

                        if confirm == 'confirm' then
                            lib.callback('aurp_trucker:server:buyBase', false, function(res)
                                if res and res.success then
                                    OwnedBases[baseId] = true
                                    RefreshBaseBlips()
                                    lib.notify({
                                        title = 'Nova Base Adquirida!',
                                        description = ('Parabéns! Você adquiriu a %s.'):format(baseCfg.label),
                                        type = 'success'
                                    })
                                else
                                    lib.notify({
                                        title = 'Falha na Compra',
                                        description = (res and res.message) or 'Não foi possível adquirir a base.',
                                        type = 'error'
                                    })
                                end
                            end, baseId)
                        end
                    end
                end
            end
        })
        table.insert(TycoonPoints, buyPoint)

        -- 2. Ponto de Oficina Privada (Workshop)
        if baseCfg.workshopCoords then
            local workshopPoint = lib.points.new({
                coords = baseCfg.workshopCoords,
                distance = 4.0,
                onEnter = function()
                    if OwnedBases[baseId] == true then
                        lib.showTextUI('[E] - Oficina Privada (Workshop)', { position = 'left-center' })
                    end
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                nearby = function(self)
                    if OwnedBases[baseId] == true then
                        DrawMarker(36, self.coords.x, self.coords.y, self.coords.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.8, 240, 180, 20, 200, false, true, 2, false, nil, nil, false)
                        if IsControlJustPressed(0, 38) then
                            OpenWorkshopMenu(baseId, baseCfg)
                        end
                    end
                end
            })
            table.insert(TycoonPoints, workshopPoint)
        end
    end
end

-- Inicialização e carregamento de dados do Tycoon
CreateThread(function()
    Wait(2000)
    lib.callback('aurp_trucker:server:getPlayerBases', false, function(bases)
        OwnedBases = bases or {}
        RefreshBaseBlips()
        SetupTycoonZones()
    end)
end)

-- Exportações
exports('GetOwnedBases', function() return OwnedBases end)
exports('OpenWorkshopMenu', OpenWorkshopMenu)
