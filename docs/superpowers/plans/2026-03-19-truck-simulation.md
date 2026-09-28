# Truck Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar simulação de viagem EuroTruck-inspired ao AUST_trucker — combustível persistente por veículo, fadiga persistente por motorista, integridade de carga linear e Dashboard HUD configurável.

**Architecture:** Híbrida — client gerencia estado local e display em tempo real; servidor valida e persiste em checkpoints (job complete, guardar veículo, desconexão). Anticheat leve por validação de teto/piso de consumo.

**Tech Stack:** Lua 5.4, FiveM (QBX/qbx_core), oxmysql, ox_lib, ox_target, React 18 + TypeScript, Tailwind CSS

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `sql/update_simulation.sql` | Criar | Migração ALTER TABLE (servidores existentes) |
| `import.sql` | Modificar | Adicionar colunas nas definições CREATE TABLE |
| `config/config.lua` | Modificar | Config.TruckSimulation + Config.FleetUpgrades |
| `server/database.lua` | Modificar | 6 novas funções DB |
| `server/services/truck_simulation_service.lua` | Criar | TruckSimulationService global |
| `server/services/job_service.lua` | Modificar | integrityMult na fórmula de pagamento |
| `server/events.lua` | Modificar | syncSimulation, vehicleDestroyed, purchaseFleetUpgrade |
| `server/exports.lua` | Modificar | GetPlayerFuel, GetPlayerFatigue |
| `client/hud.client.lua` | Criar | Todas as threads client-side + ox_target + bridge sendIntegrity |
| `client/client.lua` | Modificar | Redirecionar CompleteJob() via bridge de integridade |
| `html/src/types/index.ts` | Modificar | Interface HUDData |
| `html/src/hooks/useNUI.ts` | Modificar | Case updateHUD |
| `html/src/components/hud/TruckHUD.tsx` | Criar | Componente HUD persistente |
| `html/src/App.tsx` | Modificar | Montar TruckHUD na raiz |
| `fxmanifest.lua` | Modificar | Novos arquivos + versão 7.0.0 |
| `CHANGELOG.md` | Modificar | Entrada v7.0.0 |

---

## Task 1: Schema + Config

**Files:**
- Create: `sql/update_simulation.sql`
- Modify: `import.sql`
- Modify: `config/config.lua`

- [ ] **Step 1: Criar arquivo de migração**

Crie `sql/update_simulation.sql`:
```sql
-- AUST_trucker — Migration: truck simulation columns
-- Safe to run multiple times — IF NOT EXISTS ensures no errors on re-run.

ALTER TABLE trucker_company_vehicles
    ADD COLUMN IF NOT EXISTS fuel_level FLOAT DEFAULT 100.0;

ALTER TABLE trucker_player_progression
    ADD COLUMN IF NOT EXISTS fatigue FLOAT DEFAULT 0.0;

ALTER TABLE trucker_companies
    ADD COLUMN IF NOT EXISTS fleet_upgrades JSON DEFAULT ('{}');
```

- [ ] **Step 2: Executar migração no banco**

```bash
# Execute no seu cliente MySQL ou via oxmysql console do txAdmin:
# SOURCE sql/update_simulation.sql;
# Verifique:
# DESCRIBE trucker_company_vehicles;  → deve ter fuel_level
# DESCRIBE trucker_player_progression; → deve ter fatigue
# DESCRIBE trucker_companies; → deve ter fleet_upgrades
```

- [ ] **Step 3: Adicionar colunas ao import.sql**

No `import.sql`, dentro do `CREATE TABLE trucker_company_vehicles`, adicione após a última coluna existente:
```sql
  fuel_level FLOAT DEFAULT 100.0,
```

Dentro do `CREATE TABLE trucker_player_progression`:
```sql
  fatigue FLOAT DEFAULT 0.0,
```

Dentro do `CREATE TABLE trucker_companies`:
```sql
  fleet_upgrades JSON DEFAULT ('{}'),
```

- [ ] **Step 4: Adicionar Config.TruckSimulation ao config/config.lua**

Ao final de `config/config.lua`, adicione:
```lua
-- ============================================================
-- SIMULAÇÃO DE VIAGEM (EuroTruck-inspired)
-- ============================================================

Config.TruckSimulation = {
    -- Modelos que ativam o HUD e as threads de simulação
    TruckModels = {
        'flatbed', 'hauler', 'phantom', 'mule', 'bison',
    },

    HUD = {
        Enabled  = true,           -- false = desativa display; sistemas continuam rodando e exports funcionam
        Position = 'bottom-left',  -- bottom-left | bottom-right | top-left | top-right
        Scale    = 1.0,
    },

    Fuel = {
        ConsumptionRate    = 0.015,  -- % de tanque por segundo em velocidade normal
        LoadedMultiplier   = 1.4,    -- consumo extra com job ativo
        LowFuelThreshold   = 20.0,   -- % para alerta no HUD
        SyncInterval       = 30000,  -- ms entre syncs periódicos com servidor
        FuelPricePerUnit   = 20,     -- $ por % de tanque abastecido
        GasStations        = {
            -- ATENÇÃO: substitua vector3(0,0,0) por coordenadas reais antes de deploy
            { coords = vector3(0, 0, 0), name = "Posto Sandy", radius = 5.0 },
        },
    },

    Fatigue = {
        IncreaseRate      = 0.02,  -- % por segundo dirigindo
        RestoreRate       = 0.5,   -- % por segundo em parada de descanso
        RestDuration      = 1.2,   -- segundos de barra por % de fadiga (80% fadiga = 96s de barra)
        WarnThreshold     = 50.0,
        HeavyThreshold    = 75.0,
        CriticalThreshold = 90.0,
        MinSpeedForSleep  = 5.0,   -- m/s mínimo para disparar perda de controle (evita griefing parado)
        RestStops         = {
            -- ATENÇÃO: substitua vector3(0,0,0) por coordenadas reais antes de deploy
            { coords = vector3(0, 0, 0), name = "Parada I-95", radius = 8.0 },
        },
    },

    Cargo = {
        ImpactThreshold  = 8.0,    -- m/s² de desaceleração para detectar colisão
        ImpactDamage     = 15.0,   -- % de integridade perdida por colisão forte
        SpeedDamageRate  = 0.005,  -- % por segundo acima do SpeedLimit
        SpeedLimit       = 30.0,   -- m/s (~108 km/h)
        MinPaymentRate   = 0.10,   -- pagamento mínimo (10%) se integridade = 0%
    },
}

Config.FleetUpgrades = {
    anti_sleep = {
        label       = 'Sistema Anti-Sono (ADAS)',
        price       = 150000,
        description = 'Freio automático ao detectar fadiga crítica do motorista.',
    },
}
```

- [ ] **Step 5: Commit**

```bash
git add sql/update_simulation.sql import.sql config/config.lua
git commit -m "feat(simulation): schema migration + Config.TruckSimulation"
```

---

## Task 2: Funções DB

**Files:**
- Modify: `server/database.lua`

- [ ] **Step 1: Adicionar funções de combustível**

Ao final da seção `-- VEHICLES` em `server/database.lua`, adicione:
```lua
-- ============================================================
-- TRUCK SIMULATION — FUEL / FATIGUE / FLEET UPGRADES
-- ============================================================

function DB_GetVehicleFuel(plate)
    local row = MySQL.single.await(
        'SELECT fuel_level FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
    return row and row.fuel_level or 100.0
end

function DB_SetVehicleFuel(plate, fuel)
    MySQL.update.await(
        'UPDATE trucker_company_vehicles SET fuel_level = ? WHERE plate = ?',
        { math.max(0.0, math.min(100.0, fuel)), plate }
    )
end

function DB_GetFatigue(citizenId)
    local row = MySQL.single.await(
        'SELECT fatigue FROM trucker_player_progression WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
    return row and row.fatigue or 0.0
end

function DB_SetFatigue(citizenId, fatigue)
    MySQL.update.await(
        'UPDATE trucker_player_progression SET fatigue = ? WHERE citizenid = ?',
        { math.max(0.0, math.min(100.0, fatigue)), citizenId }
    )
end

function DB_GetFleetUpgrades(companyId)
    local row = MySQL.single.await(
        'SELECT fleet_upgrades FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
    if not row or not row.fleet_upgrades then return {} end
    return json.decode(row.fleet_upgrades) or {}
end

function DB_SetFleetUpgrades(companyId, upgrades)
    MySQL.update.await(
        'UPDATE trucker_companies SET fleet_upgrades = ? WHERE id = ?',
        { json.encode(upgrades), companyId }
    )
end
```

- [ ] **Step 2: Verificar no console do servidor**

Reinicie o resource e verifique que não há erros de syntax:
```
ensure AUST_trucker
```
Nenhuma mensagem de erro deve aparecer.

- [ ] **Step 3: Commit**

```bash
git add server/database.lua
git commit -m "feat(simulation): DB helpers — fuel, fatigue, fleet upgrades"
```

---

## Task 3: TruckSimulationService

**Files:**
- Create: `server/services/truck_simulation_service.lua`

- [ ] **Step 1: Criar o service**

Crie `server/services/truck_simulation_service.lua`:
```lua
-- AUST_trucker — server/services/truck_simulation_service.lua
-- Gerencia sincronização de combustível, fadiga e upgrades de frota

TruckSimulationService = {}

-- Estado em memória por jogador: { lastFuel, lastFatigue, lastSyncTime, vehicleWasMoving }
local SimState = {}

-- ============================================================
-- INICIALIZAÇÃO DO JOGADOR
-- ============================================================

-- Chamado quando jogador conecta (via evento QBCore:Server:OnPlayerLoaded)
function TruckSimulationService.OnPlayerLoaded(src)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local fatigue = DB_GetFatigue(citizenId)
    SimState[src] = {
        lastFuel         = 100.0,
        lastFatigue      = fatigue,
        lastSyncTime     = GetGameTimer(),
        vehicleWasMoving = false,
        currentPlate     = nil,
    }

    TriggerClientEvent('AUST_trucker:client:setFatigue', src, { fatigue = fatigue })
end

-- ============================================================
-- SPAWN DE VEÍCULO
-- ============================================================

-- Chamado quando jogador pega veículo da empresa
function TruckSimulationService.OnVehicleSpawn(src, plate)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local fuel = DB_GetVehicleFuel(plate)
    if SimState[src] then
        SimState[src].lastFuel     = fuel
        SimState[src].currentPlate = plate
    end

    -- Enviar config de upgrades junto com o fuel
    local company   = CompanyService.GetByMember(Player.PlayerData.citizenid)
    local upgrades  = company and DB_GetFleetUpgrades(company.id) or {}
    local hasAntiSleep = upgrades.anti_sleep == true

    TriggerClientEvent('AUST_trucker:client:setVehicleFuel', src, { plate = plate, fuel = fuel })
    TriggerClientEvent('AUST_trucker:client:setSimConfig',   src, { hasAntiSleep = hasAntiSleep })
end

-- ============================================================
-- SYNC PERIÓDICO
-- ============================================================

-- payload = { fuel, fatigue, vehicleWasMoving, plate }
function TruckSimulationService.OnSync(src, payload)
    local state = SimState[src]
    if not state then return end

    local now      = GetGameTimer()
    local elapsed  = (now - state.lastSyncTime) / 1000.0  -- segundos
    state.lastSyncTime = now

    -- Validar combustível: teto e piso
    local reportedFuel = tonumber(payload.fuel) or state.lastFuel
    local cfg          = Config.TruckSimulation.Fuel
    local maxDrop      = cfg.ConsumptionRate * cfg.LoadedMultiplier * elapsed * 1.2
    local minDrop      = cfg.ConsumptionRate * elapsed * 0.5
    local actualDrop   = state.lastFuel - reportedFuel

    local savedFuel
    if actualDrop > maxDrop then
        savedFuel = state.lastFuel - maxDrop
    elseif actualDrop < minDrop and payload.vehicleWasMoving then
        savedFuel = state.lastFuel - (cfg.ConsumptionRate * elapsed)
    else
        savedFuel = reportedFuel
    end
    savedFuel = math.max(0.0, math.min(100.0, savedFuel))

    -- Validar fadiga: aceita qualquer valor entre 0-100 (acúmulo client-side é confiável)
    local savedFatigue = math.max(0.0, math.min(100.0, tonumber(payload.fatigue) or state.lastFatigue))

    -- Persistir
    local plate = payload.plate or state.currentPlate
    if plate then DB_SetVehicleFuel(plate, savedFuel) end

    local Player = exports.qbx_core:GetPlayer(src)
    if Player then DB_SetFatigue(Player.PlayerData.citizenid, savedFatigue) end

    state.lastFuel         = savedFuel
    state.lastFatigue      = savedFatigue
    state.vehicleWasMoving = payload.vehicleWasMoving or false
end

-- ============================================================
-- CHECKPOINTS OBRIGATÓRIOS
-- ============================================================

function TruckSimulationService.OnVehicleDestroyed(src, payload)
    -- Força sync do estado atual; job será marcado como failed pelo JobService
    TruckSimulationService.OnSync(src, payload)
end

function TruckSimulationService.OnPlayerDropped(src)
    local state   = SimState[src]
    if not state then return end
    local Player  = exports.qbx_core:GetPlayer(src)
    -- Persistir último estado conhecido
    if Player then DB_SetFatigue(Player.PlayerData.citizenid, state.lastFatigue) end
    if state.currentPlate then DB_SetVehicleFuel(state.currentPlate, state.lastFuel) end
    SimState[src] = nil
end

-- ============================================================
-- FLEET UPGRADES
-- ============================================================

-- Retorna true se empresa tem o upgrade
function TruckSimulationService.HasUpgrade(companyId, upgradeKey)
    local upgrades = DB_GetFleetUpgrades(companyId)
    return upgrades[upgradeKey] == true
end

-- Compra upgrade — retorna { success, reason }
function TruckSimulationService.PurchaseUpgrade(src, upgradeKey)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end

    local upgrade = Config.FleetUpgrades[upgradeKey]
    if not upgrade then return { success = false, reason = 'Upgrade inválido' } end

    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return { success = false, reason = 'Sem empresa' } end

    local member = DB_GetMember(Player.PlayerData.citizenid)
    if not member or (member.role ~= 'owner' and member.role ~= 'manager') then
        return { success = false, reason = 'Sem permissão' }
    end

    local upgrades = DB_GetFleetUpgrades(company.id)
    if upgrades[upgradeKey] then
        return { success = false, reason = 'Upgrade já adquirido' }
    end

    local companyData = CompanyService.Get(company.id)
    if not companyData or companyData.balance < upgrade.price then
        return { success = false, reason = 'Saldo insuficiente' }
    end

    -- Deduzir do saldo da empresa
    DB_UpdateCompanyBalance(company.id, -upgrade.price)
    VP_Trucker.Companies[company.id].balance = (VP_Trucker.Companies[company.id].balance or 0) - upgrade.price

    -- Salvar upgrade
    upgrades[upgradeKey] = true
    DB_SetFleetUpgrades(company.id, upgrades)

    -- Notificar membros online que estão nesta empresa
    for _, playerSrc in ipairs(GetPlayers()) do
        local src = tonumber(playerSrc)
        local p = exports.qbx_core:GetPlayer(src)
        if p then
            local memberCompany = CompanyService.GetByMember(p.PlayerData.citizenid)
            if memberCompany and memberCompany.id == company.id then
                TriggerClientEvent('AUST_trucker:client:setSimConfig', src, { hasAntiSleep = true })
            end
        end
    end

    return { success = true }
end

-- Retorna estado de sim de um jogador (para exports)
function TruckSimulationService.GetState(src)
    return SimState[src]
end
```

- [ ] **Step 2: Registrar eventos de lifecycle em server/events.lua**

Adicione ao final de `server/events.lua`:
```lua
-- =====================================================
-- TRUCK SIMULATION
-- =====================================================

AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    TruckSimulationService.OnPlayerLoaded(source)
end)

AddEventHandler('playerDropped', function()
    TruckSimulationService.OnPlayerDropped(source)
end)

RegisterNetEvent('AUST_trucker:syncSimulation', function(payload)
    TruckSimulationService.OnSync(source, payload)
end)

RegisterNetEvent('AUST_trucker:vehicleDestroyed', function(payload)
    TruckSimulationService.OnVehicleDestroyed(source, payload)
end)

RegisterNetEvent('AUST_trucker:spawnVehicle', function(plate)
    TruckSimulationService.OnVehicleSpawn(source, plate)
end)

RegisterNetEvent('AUST_trucker:purchaseFleetUpgrade', function(upgradeKey)
    local result = TruckSimulationService.PurchaseUpgrade(source, upgradeKey)
    TriggerClientEvent('AUST_trucker:client:upgradeResult', source, result)
end)
```

- [ ] **Step 3: Commit**

```bash
git add server/services/truck_simulation_service.lua server/events.lua
git commit -m "feat(simulation): TruckSimulationService — sync, validation, fleet upgrades"
```

---

## Task 4: JobService — Cargo Integrity

**Files:**
- Modify: `server/services/job_service.lua`
- Modify: `server/events.lua`

- [ ] **Step 1: Atualizar comentário e fórmula em JobService.Complete**

Em `server/services/job_service.lua`, localize `JobService.Complete` (linha ~180).

Substitua o comentário e a linha de payment:
```lua
-- payload = { deliveryTime, plate }
function JobService.Complete(src, payload)
```
Por:
```lua
-- payload = { deliveryTime, plate, cargoIntegrity }
-- cargoIntegrity: 0–100 (reportado pelo client; validado/clamped antes de chegar aqui)
function JobService.Complete(src, payload)
```

- [ ] **Step 2: Adicionar integrityMult na fórmula de pagamento**

Localize a linha:
```lua
local payment = math.floor(activeJob.base_payment * timeMult * skillMult * companyMult)
```
Substitua por:
```lua
local rawIntegrity  = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
local integrityMult = math.max(
    Config.TruckSimulation.Cargo.MinPaymentRate,
    rawIntegrity / 100
)
local payment = math.floor(activeJob.base_payment * timeMult * skillMult * companyMult * integrityMult)
```

- [ ] **Step 3: Registrar infração se integridade < 30%**

Logo após a linha `DB_CompleteJob(activeJob.id)`, adicione:
```lua
if rawIntegrity < 30 then
    DB_RecordInfraction(citizenId, activeJob.id, 'cargo_damage',
        ('Carga entregue com %d%% de integridade'):format(rawIntegrity),
        'AUST_trucker:auto')
end
```

- [ ] **Step 4: Notificar com integridade no client**

Localize a mensagem de notificação no handler `AUST_trucker:completeJob` em `server/events.lua`:
```lua
TriggerClientEvent('AUST_trucker:notify', src,
    ('Job concluído! Você recebeu $%d'):format(payment), 'success')
```
Substitua por:
```lua
local integrityPct = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
TriggerClientEvent('AUST_trucker:notify', src,
    ('Job concluído! Carga: %d%% — $%d recebidos'):format(integrityPct, payment), 'success')
```

- [ ] **Step 5: Commit**

```bash
git add server/services/job_service.lua server/events.lua
git commit -m "feat(simulation): apply cargo integrity multiplier to job payment"
```

---

## Task 5: Client Simulation (hud.client.lua)

**Files:**
- Create: `client/hud.client.lua`
- Modify: `client/client.lua`

- [ ] **Step 1: Criar hud.client.lua — state e helpers**

Crie `client/hud.client.lua`:
```lua
-- AUST_trucker — client/hud.client.lua
-- Simulação de viagem: combustível, fadiga, integridade de carga, HUD

-- ============================================================
-- ESTADO LOCAL
-- ============================================================

local SimState = {
    -- Veículo
    currentVehicle   = nil,
    currentPlate     = nil,
    isTruck          = false,

    -- Combustível
    fuel             = 100.0,
    lastSyncTime     = 0,

    -- Fadiga
    fatigue          = 0.0,
    hasAntiSleep     = false,
    sleepTriggered   = false,  -- evita re-trigger no mesmo ciclo

    -- Integridade de carga
    integrity        = 100.0,
    hasActiveJob     = false,
    prevSpeed        = 0.0,

    -- Movimento (para anticheat piso)
    vehicleWasMoving = false,
}

-- ============================================================
-- HELPERS
-- ============================================================

local function IsTruckModel(model)
    for _, name in ipairs(Config.TruckSimulation.TruckModels) do
        if model == GetHashKey(name) then return true end
    end
    return false
end

local function GetSkillMultiplier(skillType)
    -- Busca skill local (ProgressionService não existe client-side)
    -- O client recebe skills via 'updateSkills' NUI message — mas para simplifidade
    -- aqui usamos lib.callback.await para buscar do servidor apenas na mudança de veículo
    return 1.0  -- padrão; a redução real é aplicada server-side (skills afetam via config)
end

local function SendHUDUpdate()
    if not Config.TruckSimulation.HUD.Enabled then return end
    SendNUIMessage({
        action    = 'updateHUD',
        visible   = SimState.isTruck,
        speed     = SimState.isTruck and math.floor(GetEntitySpeed(SimState.currentVehicle) * 3.6) or 0,
        fuel      = SimState.fuel,
        position  = Config.TruckSimulation.HUD.Position,
        fatigue   = SimState.fatigue,
        integrity = SimState.hasActiveJob and SimState.integrity or nil,
    })
end

local function SyncToServer()
    TriggerServerEvent('AUST_trucker:syncSimulation', {
        fuel             = SimState.fuel,
        fatigue          = SimState.fatigue,
        vehicleWasMoving = SimState.vehicleWasMoving,
        plate            = SimState.currentPlate,
    })
    SimState.lastSyncTime = GetGameTimer()
end

-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

RegisterNetEvent('AUST_trucker:client:setVehicleFuel', function(data)
    if data.plate == SimState.currentPlate then
        SimState.fuel = data.fuel
        if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
            SetVehicleFuelLevel(SimState.currentVehicle, (SimState.fuel / 100.0) * 65.0)
        end
    end
end)

RegisterNetEvent('AUST_trucker:client:setFatigue', function(data)
    SimState.fatigue = math.max(0.0, math.min(100.0, data.fatigue or 0.0))
end)

RegisterNetEvent('AUST_trucker:client:setSimConfig', function(data)
    if data.hasAntiSleep ~= nil then
        SimState.hasAntiSleep = data.hasAntiSleep
    end
end)

RegisterNetEvent('AUST_trucker:client:upgradeResult', function(result)
    if result.success then
        lib.notify({ title = 'Upgrade', description = 'Upgrade adquirido com sucesso!', type = 'success' })
    else
        lib.notify({ title = 'Erro', description = result.reason or 'Erro desconhecido', type = 'error' })
    end
end)

-- Job iniciado: reinicia integridade
RegisterNetEvent('AUST_trucker:client:jobStarted', function()
    SimState.integrity   = 100.0
    SimState.hasActiveJob = true
    SimState.prevSpeed   = 0.0
end)

-- Job concluído (confirmação do servidor): reseta estado
RegisterNetEvent('AUST_trucker:client:jobCompleted', function()
    SimState.hasActiveJob = false
    SimState.integrity   = 100.0
end)

-- Veículo destruído: sync + notifica servidor
local function OnVehicleDestroyed()
    if not SimState.isTruck then return end
    TriggerServerEvent('AUST_trucker:vehicleDestroyed', {
        fuel             = SimState.fuel,
        fatigue          = SimState.fatigue,
        vehicleWasMoving = SimState.vehicleWasMoving,
        plate            = SimState.currentPlate,
    })
    SimState.currentVehicle = nil
    SimState.currentPlate   = nil
    SimState.isTruck        = false
    SimState.hasActiveJob   = false
    SimState.integrity      = 100.0
end

-- ============================================================
-- THREAD: DETECÇÃO DE VEÍCULO (1s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 then
            local model   = GetEntityModel(vehicle)
            local isTruck = IsTruckModel(model)

            if isTruck then
                -- Veículo mudou?
                if vehicle ~= SimState.currentVehicle then
                    -- Sync do anterior se existia
                    if SimState.currentVehicle then SyncToServer() end

                    local plate = GetVehicleNumberPlateText(vehicle)
                    SimState.currentVehicle = vehicle
                    SimState.currentPlate   = plate
                    SimState.isTruck        = true
                    SimState.sleepTriggered = false

                    -- Notificar servidor para carregar fuel e config
                    TriggerServerEvent('AUST_trucker:spawnVehicle', plate)
                end

                -- Verificar se veículo foi destruído
                if IsVehicleDriveable(vehicle, false) == false or GetEntityHealth(vehicle) <= 0 then
                    OnVehicleDestroyed()
                end

                SimState.vehicleWasMoving = GetEntitySpeed(vehicle) > 2.0
            else
                -- Saiu do caminhão
                if SimState.isTruck then SyncToServer() end
                SimState.currentVehicle   = nil
                SimState.currentPlate     = nil
                SimState.isTruck          = false
                SimState.vehicleWasMoving = false
            end
        else
            -- A pé
            if SimState.isTruck then SyncToServer() end
            SimState.currentVehicle   = nil
            SimState.currentPlate     = nil
            SimState.isTruck          = false
            SimState.vehicleWasMoving = false
        end
    end
end)

-- ============================================================
-- THREAD: COMBUSTÍVEL (1s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        if not SimState.isTruck then goto continue end

        local cfg    = Config.TruckSimulation.Fuel
        local loaded = SimState.hasActiveJob and cfg.LoadedMultiplier or 1.0
        local consume = cfg.ConsumptionRate * loaded
        SimState.fuel = math.max(0.0, SimState.fuel - consume)

        -- Aplicar ao veículo GTA
        if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
            SetVehicleFuelLevel(SimState.currentVehicle, (SimState.fuel / 100.0) * 65.0)

            -- Sem combustível: cortar potência
            if SimState.fuel <= 0.0 then
                SetVehicleEnginePowerMultiplier(SimState.currentVehicle, 0.1)
            else
                SetVehicleEnginePowerMultiplier(SimState.currentVehicle, 1.0)
            end
        end

        -- Sync periódico
        if (GetGameTimer() - SimState.lastSyncTime) >= cfg.SyncInterval then
            SyncToServer()
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: FADIGA (1s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        if not SimState.isTruck then goto continue end
        if not SimState.currentVehicle then goto continue end

        local speed = GetEntitySpeed(SimState.currentVehicle)
        if speed < 2.0 then goto continue end  -- parado não acumula fadiga

        local cfg = Config.TruckSimulation.Fatigue
        SimState.fatigue = math.min(100.0, SimState.fatigue + cfg.IncreaseRate)

        -- Efeitos visuais
        if SimState.fatigue >= cfg.HeavyThreshold then
            SetTimecycleModifier('HighContrast')
            SetTimecycleModifierStrength(0.6)
        elseif SimState.fatigue >= cfg.WarnThreshold then
            SetTimecycleModifier('HighContrast')
            SetTimecycleModifierStrength(0.3)
        else
            ClearTimecycleModifier()
        end

        -- Aviso crítico a cada 30s
        if SimState.fatigue >= cfg.CriticalThreshold then
            if (GetGameTimer() % 30000) < 1100 then
                lib.notify({ title = 'Fadiga Crítica!', description = 'Pare para descansar imediatamente!', type = 'error', duration = 5000 })
            end
        end

        -- Adormecer aos 100%
        if SimState.fatigue >= 100.0 and not SimState.sleepTriggered then
            if speed >= cfg.MinSpeedForSleep then
                SimState.sleepTriggered = true
                CreateThread(function()
                    DoScreenFadeOut(500)
                    Wait(500)

                    local vehicle = SimState.currentVehicle
                    if SimState.hasAntiSleep then
                        -- ADAS: para o veículo suavemente
                        if vehicle and DoesEntityExist(vehicle) then
                            SetVehicleEnginePowerMultiplier(vehicle, 0.0)
                            local ped = PlayerPedId()
                            TaskVehicleTempAction(ped, vehicle, 1, 3000)
                        end
                        Wait(2000)
                        DoScreenFadeIn(500)
                        lib.notify({ title = 'Sistema Anti-Sono', description = 'Sistema ADAS ativado — veículo parado com segurança.', type = 'warning', duration = 5000 })
                    else
                        -- Sem ADAS: acelera descontrolado
                        if vehicle and DoesEntityExist(vehicle) then
                            SetVehicleEnginePowerMultiplier(vehicle, 2.0)
                        end
                        Wait(3000)
                        if vehicle and DoesEntityExist(vehicle) then
                            SetVehicleEnginePowerMultiplier(vehicle, 1.0)
                        end
                        DoScreenFadeIn(500)
                        -- Causar dano extra na carga
                        if SimState.hasActiveJob then
                            SimState.integrity = math.max(0.0, SimState.integrity - (Config.TruckSimulation.Cargo.ImpactDamage * 2))
                        end
                    end

                    SimState.sleepTriggered = false
                    ClearTimecycleModifier()
                end)
            end
        elseif SimState.fatigue < 100.0 then
            SimState.sleepTriggered = false
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: INTEGRIDADE DE CARGA (0.5s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(500)
        if not SimState.isTruck or not SimState.hasActiveJob then
            SimState.prevSpeed = 0.0
            goto continue
        end
        if not SimState.currentVehicle then goto continue end

        local cfg      = Config.TruckSimulation.Cargo
        local speed    = GetEntitySpeed(SimState.currentVehicle)
        local prevSpd  = SimState.prevSpeed
        SimState.prevSpeed = speed

        -- Detector de impacto
        local decel = prevSpd - speed
        if decel > cfg.ImpactThreshold then
            SimState.integrity = math.max(0.0, SimState.integrity - cfg.ImpactDamage)
            lib.notify({ title = 'Carga Danificada!', description = ('Impacto detectado — Integridade: %d%%'):format(math.floor(SimState.integrity)), type = 'error', duration = 3000 })
        end

        -- Excesso de velocidade
        if speed > cfg.SpeedLimit then
            SimState.integrity = math.max(0.0, SimState.integrity - (cfg.SpeedDamageRate * 0.5))
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD: HUD UPDATE (0.5s)
-- ============================================================

CreateThread(function()
    while true do
        Wait(500)
        SendHUDUpdate()
    end
end)

-- ============================================================
-- BRIDGE: completeJob → servidor com cargoIntegrity injetado
-- ============================================================
-- client.lua dispara TriggerEvent('AUST_trucker:client:sendIntegrity', deliveryTime)
-- Este handler (em hud.client.lua, mesmo resource) pode acessar SimState diretamente.
-- NOTA lua54: named events cruzam chunks do mesmo resource (apenas `local` vars não cruzam).

AddEventHandler('AUST_trucker:client:sendIntegrity', function(deliveryTime)
    -- Usar currentPlate do SimState (plate já foi synced quando jogador saiu do caminhão)
    TriggerServerEvent('AUST_trucker:completeJob', {
        deliveryTime   = deliveryTime,
        plate          = SimState.currentPlate,  -- pode ser nil se jogador já saiu do caminhão; OK — fuel já foi synced
        cargoIntegrity = math.floor(SimState.integrity),
    })
end)

-- ============================================================
-- OX_TARGET: POSTOS DE COMBUSTÍVEL
-- ============================================================

CreateThread(function()
    while not exports['ox_target'] do Wait(100) end

    for _, station in ipairs(Config.TruckSimulation.Fuel.GasStations) do
        exports.ox_target:addSphereZone({
            name    = 'gas_station_' .. station.name,
            coords  = station.coords,
            radius  = station.radius or 5.0,
            options = {
                {
                    name        = 'refuel_truck',
                    label       = 'Abastecer Caminhão',
                    icon        = 'fas fa-gas-pump',
                    distance    = 3.0,
                    canInteract = function() return SimState.isTruck and SimState.fuel < 99.0 end,
                    onSelect    = function()
                        local needed   = 100.0 - SimState.fuel
                        local price    = math.ceil(needed * Config.TruckSimulation.Fuel.FuelPricePerUnit)
                        local confirmed = lib.alertDialog({
                            header  = 'Abastecer',
                            content = ('Tanque: %.0f%% → 100%%\nCusto: $%d'):format(SimState.fuel, price),
                            centered = true,
                            cancel   = true,
                        })
                        if confirmed ~= 'confirm' then return end

                        local ok, err = lib.callback.await('AUST_trucker:payForFuel', false, price)
                        if ok then
                            SimState.fuel = 100.0
                            if SimState.currentVehicle and DoesEntityExist(SimState.currentVehicle) then
                                SetVehicleFuelLevel(SimState.currentVehicle, 65.0)
                            end
                            SyncToServer()
                            lib.notify({ title = 'Abastecido', description = 'Tanque cheio!', type = 'success' })
                        else
                            lib.notify({ title = 'Erro', description = err or 'Saldo insuficiente', type = 'error' })
                        end
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- OX_TARGET: PARADAS DE DESCANSO
-- ============================================================

CreateThread(function()
    while not exports['ox_target'] do Wait(100) end

    for _, stop in ipairs(Config.TruckSimulation.Fatigue.RestStops) do
        exports.ox_target:addSphereZone({
            name    = 'rest_stop_' .. stop.name,
            coords  = stop.coords,
            radius  = stop.radius or 8.0,
            options = {
                {
                    name        = 'rest_driver',
                    label       = 'Descansar (' .. stop.name .. ')',
                    icon        = 'fas fa-bed',
                    distance    = 4.0,
                    canInteract = function() return SimState.fatigue > 5.0 end,
                    onSelect    = function()
                        local cfg       = Config.TruckSimulation.Fatigue
                        local duration  = math.ceil(SimState.fatigue * cfg.RestDuration)
                        local startedAt = GetGameTimer()

                        lib.progressBar({
                            duration = duration * 1000,
                            label    = ('Descansando... (%.0f%% fadiga)'):format(SimState.fatigue),
                            canCancel = true,
                            disable   = { car = true, combat = true },
                            anim      = { dict = 'amb@world_human_seat_wall@male@base', clip = 'base' },
                        }, function(completed)
                            -- Restauração proporcional ao tempo realmente decorrido
                            local elapsed    = (GetGameTimer() - startedAt) / 1000.0
                            local actualTime = completed and duration or elapsed
                            local reduction  = cfg.RestoreRate * actualTime
                            SimState.fatigue = math.max(0.0, SimState.fatigue - reduction)
                            ClearTimecycleModifier()
                            SyncToServer()

                            if completed then
                                lib.notify({ title = 'Descansado!', description = 'Fadiga zerada.', type = 'success' })
                            else
                                lib.notify({ title = 'Descanso interrompido', description = ('Fadiga: %.0f%%'):format(SimState.fatigue), type = 'warning' })
                            end
                        end)
                    end,
                },
            },
        })
    end
end)

-- ============================================================
-- EXPORT CLIENT-SIDE
-- ============================================================

exports('GetCargoIntegrity', function()
    if not SimState.hasActiveJob then return nil end
    return math.floor(SimState.integrity)
end)
```

- [ ] **Step 2: Modificar client.lua — roteamento via bridge de integridade**

> **CONTEXTO CRÍTICO (lua54 chunk isolation):** `SimState` em `hud.client.lua` não é visível em `client.lua`. Mas **named events** cruzam chunks do mesmo resource — `TriggerEvent` (local) dispara para todos os `AddEventHandler` no resource, independente do chunk. O handler em `hud.client.lua` acessa `SimState.integrity` diretamente por ser no mesmo arquivo.
>
> Adicionalmente, `CompleteJob()` em `client.lua` dispara `'aurp-trucker:completeJob'` (hífen) — evento que **não tem handler no servidor**. Esta substituição corrige essa falha pré-existente.

Em `client/client.lua`, localize a função `CompleteJob()` (~linha 800). Encontre:
```lua
    -- Enviar para servidor para pagamento
    TriggerServerEvent('aurp-trucker:completeJob', {
        jobId = currentJob.id,
        payment = finalPayment,
        deliveryTime = deliveryTime,
        timeMultiplier = timeMultiplier,
        companyTax = currentJob.companyTax or 0
    })
```

Substitua **apenas essa chamada `TriggerServerEvent`** por:
```lua
    -- Roteamento via hud.client.lua para injetar cargoIntegrity
    -- Named events cruzam chunks lua54 no mesmo resource
    TriggerEvent('AUST_trucker:client:sendIntegrity', deliveryTime)
```

> **Nota:** `hud.client.lua` usa `SimState.currentPlate` diretamente (sem precisar de parâmetro, pois está no mesmo arquivo). O combustível já foi sincronizado quando o jogador saiu do caminhão. O pagamento é recalculado server-authoritative e confirmado via `AUST_trucker:client:jobCompleted`.

- [ ] **Step 3: Adicionar callback payForFuel em server/callbacks.lua**

Ao final de `server/callbacks.lua`, adicione:
```lua
lib.callback.register('AUST_trucker:payForFuel', function(source, price)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return false, 'Jogador não encontrado' end
    price = math.floor(tonumber(price) or 0)
    if price <= 0 then return false, 'Preço inválido' end
    if not Player.Functions.RemoveMoney('cash', price, 'aurp-trucker-fuel') then
        return false, 'Saldo insuficiente'
    end
    return true
end)
```

- [ ] **Step 4: Commit**

```bash
git add client/hud.client.lua client/client.lua server/callbacks.lua
git commit -m "feat(simulation): client simulation threads — fuel, fatigue, cargo, HUD, ox_target"
```

---

## Task 6: TypeScript — HUDData + useNUI

**Files:**
- Modify: `html/src/types/index.ts`
- Modify: `html/src/hooks/useNUI.ts`

- [ ] **Step 1: Adicionar interface HUDData em html/src/types/index.ts**

Ao final de `html/src/types/index.ts`, adicione:
```typescript
export interface HUDData {
  visible:   boolean
  speed:     number
  fuel:      number        // 0–100
  fatigue:   number        // 0–100
  integrity: number | null // 0–100 com job ativo, null sem job
  position:  string        // 'bottom-left' | 'bottom-right' | 'top-left' | 'top-right'
}
```

- [ ] **Step 2: Adicionar store de HUD — criar html/src/stores/useHUDStore.ts**

Crie `html/src/stores/useHUDStore.ts`:
```typescript
import { create } from 'zustand'
import type { HUDData } from '../types'

interface HUDStore {
  hud: HUDData
  setHUD: (data: HUDData) => void
}

const defaultHUD: HUDData = {
  visible:   false,
  speed:     0,
  fuel:      100,
  fatigue:   0,
  integrity: null,
  position:  'bottom-left',
}

export const useHUDStore = create<HUDStore>((set) => ({
  hud:    defaultHUD,
  setHUD: (data) => set({ hud: data }),
}))
```

- [ ] **Step 3: Adicionar case updateHUD em html/src/hooks/useNUI.ts**

Adicione o import no topo:
```typescript
import { useHUDStore } from '../stores/useHUDStore'
```

Dentro da função `useNUI`, adicione após os outros stores:
```typescript
const { setHUD } = useHUDStore()
```

Adicione o case no switch:
```typescript
case 'updateHUD':
  setHUD({
    visible:   event.data.visible   ?? false,
    speed:     event.data.speed     ?? 0,
    fuel:      event.data.fuel      ?? 100,
    fatigue:   event.data.fatigue   ?? 0,
    integrity: event.data.integrity ?? null,
    position:  event.data.position  ?? 'bottom-left',
  })
  break
```

Adicione também `hud?: HUDData` na interface `NUIMessage`:
```typescript
hud?:      HUDData
```

E os campos individuais usados (o switch usa `event.data.*` diretamente, então adicione ao NUIMessage):
```typescript
visible?:  boolean
speed?:    number
```

- [ ] **Step 4: Commit parcial**

```bash
git add html/src/types/index.ts html/src/stores/useHUDStore.ts html/src/hooks/useNUI.ts
git commit -m "feat(simulation): TypeScript HUDData type + useHUDStore + useNUI updateHUD"
```

---

## Task 7: TruckHUD Component + App.tsx

**Files:**
- Create: `html/src/components/hud/TruckHUD.tsx`
- Modify: `html/src/App.tsx`

- [ ] **Step 1: Criar componente TruckHUD**

Crie `html/src/components/hud/TruckHUD.tsx`:
```tsx
import { useHUDStore } from '../../stores/useHUDStore'

const positionClasses: Record<string, string> = {
  'bottom-left':  'bottom-6 left-6',
  'bottom-right': 'bottom-6 right-6',
  'top-left':     'top-6 left-6',
  'top-right':    'top-6 right-6',
}

function Bar({ value, low, high, label, icon }: {
  value:  number
  low?:   number
  high?:  number
  label?: string
  icon:   string
}) {
  const pct   = Math.max(0, Math.min(100, value))
  const color = high !== undefined && pct >= high
    ? 'bg-red-500'
    : low !== undefined && pct <= low
    ? 'bg-yellow-400'
    : 'bg-green-400'

  return (
    <div className="flex items-center gap-2 text-white text-xs">
      <span className="w-4 text-center">{icon}</span>
      <div className="w-24 h-2 bg-white/20 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${color}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="w-8 text-right tabular-nums">{Math.floor(pct)}%</span>
      {label && <span className="text-white/50">{label}</span>}
    </div>
  )
}

export function TruckHUD() {
  const { hud } = useHUDStore()

  if (!hud.visible) return null

  const pos = positionClasses[hud.position ?? 'bottom-left'] ?? positionClasses['bottom-left']

  return (
    <div
      className={`fixed ${pos} pointer-events-none select-none`}
      style={{ zIndex: 9998 }}
    >
      <div className="bg-black/60 backdrop-blur-sm rounded-xl px-3 py-2 flex flex-col gap-1.5 min-w-[180px]">
        {/* Velocidade */}
        <div className="flex items-center gap-2 text-white text-sm font-semibold">
          <span>🚛</span>
          <span className="tabular-nums">{hud.speed} km/h</span>
        </div>

        {/* Combustível */}
        <Bar
          value={hud.fuel}
          low={20}
          icon="⛽"
        />

        {/* Fadiga */}
        <Bar
          value={hud.fatigue}
          high={90}
          low={0}
          icon="😴"
        />

        {/* Integridade da carga (só com job ativo) */}
        {hud.integrity !== null && (
          <>
            <div className="border-t border-white/20 my-0.5" />
            <Bar
              value={hud.integrity}
              low={50}
              icon="📦"
            />
          </>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Montar TruckHUD em App.tsx**

Em `html/src/App.tsx`, adicione o import:
```typescript
import { TruckHUD } from './components/hud/TruckHUD'
```

Dentro do JSX retornado, adicione `<TruckHUD />` antes ou após o painel principal:
```tsx
return (
  <>
    <TruckHUD />
    {/* ... resto do App existente ... */}
  </>
)
```

- [ ] **Step 3: Commit**

```bash
git add html/src/components/hud/TruckHUD.tsx html/src/App.tsx
git commit -m "feat(simulation): TruckHUD React component + mount in App.tsx"
```

---

## Task 8: Exports do Servidor

**Files:**
- Modify: `server/exports.lua`

- [ ] **Step 1: Adicionar exports de simulação**

Ao final de `server/exports.lua`, adicione:
```lua
-- ============================================================
-- TRUCK SIMULATION — para HUDs externas e integração
-- ============================================================

-- Último combustível sincronizado do jogador (0–100)
-- Use quando Config.TruckSimulation.HUD.Enabled = false e tiver HUD própria
exports('GetPlayerFuel', function(source)
    local state = TruckSimulationService.GetState(source)
    return state and state.lastFuel or 100.0
end)

-- Última fadiga sincronizada do jogador (0–100)
exports('GetPlayerFatigue', function(source)
    local state = TruckSimulationService.GetState(source)
    return state and state.lastFatigue or 0.0
end)
```

- [ ] **Step 2: Commit**

```bash
git add server/exports.lua
git commit -m "feat(simulation): server exports GetPlayerFuel + GetPlayerFatigue"
```

---

## Task 9: fxmanifest + Build + Docs

**Files:**
- Modify: `fxmanifest.lua`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Atualizar fxmanifest.lua**

Em `fxmanifest.lua`:

1. Altere a versão:
```lua
version '7.0.0'
```

2. Adicione em `server_scripts`, **após `'server/services/job_service.lua'` e antes de `'server/exports.lua'`** (deve ter acesso a CompanyService, DB funcs e VP_Trucker.Companies):
```lua
'server/services/truck_simulation_service.lua',
```

3. Adicione em `client_scripts`, após `'client/client.lua'`:
```lua
'client/hud.client.lua',
```

- [ ] **Step 2: Atualizar CHANGELOG.md**

Adicione ao topo de `CHANGELOG.md`:
```markdown
## [7.0.0] — 2026-03-19

### Added — Truck Simulation (EuroTruck-inspired)
- Sistema de combustível persistente por veículo (`trucker_company_vehicles.fuel_level`)
- Sistema de fadiga persistente por motorista (`trucker_player_progression.fatigue`)
- Integridade de carga linear — colisões e excesso de velocidade degradam, pagamento proporcional
- Dashboard HUD in-world (velocidade, combustível, fadiga, integridade) — toggle via `Config.TruckSimulation.HUD.Enabled`
- Upgrade de frota "Sistema Anti-Sono (ADAS)" — empresa paga $150k, previne perda de controle por fadiga
- Postos de combustível e paradas de descanso configuráveis via `Config.TruckSimulation`
- Server exports `GetPlayerFuel(source)` e `GetPlayerFatigue(source)` para HUDs externas
- Client export `GetCargoIntegrity()` para scripts externos
- Migration: `sql/update_simulation.sql`

### Changed
- `JobService.Complete`: pagamento multiplica por `integrityMult` (integridade / 100)
- Infração `cargo_damage` registrada automaticamente quando integridade < 30% na entrega
- `fxmanifest.lua`: v7.0.0, adiciona `truck_simulation_service.lua` e `hud.client.lua`

---
```

- [ ] **Step 3: Build do frontend**

```bash
cd html
npm run build
cd ..
```

Verifique que `html/assets/` foi atualizado sem erros.

- [ ] **Step 4: Atualizar GUIA_STAFF.md**

Na seção "Banco de dados", adicione nota de migração:
```
> **Atualização v6.x → v7.x:** Execute `sql/update_simulation.sql` para adicionar `fuel_level`, `fatigue` e `fleet_upgrades`.
```

- [ ] **Step 5: Commit final + push**

```bash
git add fxmanifest.lua CHANGELOG.md GUIA_STAFF.md html/assets/
git commit -m "feat: truck simulation v7.0.0 — build, manifest, changelog"
git push
```

---

## Teste Manual Completo

Após implementar todas as tasks:

1. **Combustível**: Pegue veículo da empresa → HUD deve mostrar fuel → aguarde 2 min → fuel deve cair → abastecimento no posto → fuel volta a 100%

2. **Fadiga**: Dirija por 5 min contínuos → vinheta deve aparecer → vá para parada de descanso → barra de progresso → fadiga deve cair

3. **Integridade**: Aceite job → barra aparece no HUD → bata em uma parede → barra deve cair 15% → entregue → mensagem com integridade e pagamento proporcional

4. **ADAS**: Empresa compra upgrade → dirija até 100% fadiga → veículo deve parar suavemente em vez de acelerar

5. **Persistência**: Feche o jogo com 50% fuel e 30% fadiga → entre novamente → valores devem ser restaurados
