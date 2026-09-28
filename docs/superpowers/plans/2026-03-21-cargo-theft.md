# Cargo Theft (Vehicle-Bound Cargo) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind cargo to the player's truck when a job is accepted; allow other players to steal it via a 20s progress bar after the truck sits empty for 30s; fail the owner's job on theft and pay the thief full base_payment × timeMult × 1.25; notify owner + police if GPS tracker is installed.

**Architecture:** Hybrid in-memory + DB. `VP_Trucker.CargoByPlate[plate]` tracks live cargo state; `trucker_jobs.truck_plate` persists for server restarts. `CargoTrackingService` (new server service) owns all theft logic. `client/cargo_theft.client.lua` handles vehicle monitoring, StateBag-based vulnerability detection, ox_target, and the thief's progress bar.

**Tech Stack:** Lua 5.4 (FiveM), QBX (qbx_core), oxmysql, ox_lib (progressBar, notify), ox_target (addLocalEntity / removeLocalEntity), StateBags (OneSync)

---

## Files Modified / Created

| File | Change |
|---|---|
| `sql/update_cargo_theft_v14.sql` | **Create** — migration for existing installs |
| `import.sql` | Modify — add columns to fresh-install schema |
| `config/config.lua` | Modify — append `Config.CargoTheft` block |
| `server/database.lua` | Modify — add 5 new DB functions |
| `server/main.lua` | Modify — add `VP_Trucker.CargoByPlate = {}`; wire LoadFromDB |
| `server/services/cargo_tracking_service.lua` | **Create** — `CargoTrackingService` global |
| `server/services/job_service.lua` | Modify — add `JobService.CompleteTheft()` |
| `server/events.lua` | Modify — add 5 new event handlers; modify `acceptJob` + `completeJob` |
| `server/callbacks.lua` | Modify — add `purchaseGpsTracker` callback |
| `client/cargo_theft.client.lua` | **Create** — owner monitoring + thief mechanics |
| `fxmanifest.lua` | Modify — add new files to load order; bump version to `14.0.0` |
| `CHANGELOG.md` | Modify — add v14.0.0 entry |

---

## Task 1: SQL + Config.CargoTheft

**Files:**
- Create: `sql/update_cargo_theft_v14.sql`
- Modify: `import.sql`
- Modify: `config/config.lua` (append after line 1268 — end of file)

- [ ] **Step 1: Create migration file `sql/update_cargo_theft_v14.sql`**

```sql
-- Migration v13 → v14: Vehicle-Bound Cargo + Theft
ALTER TABLE trucker_jobs
    ADD COLUMN IF NOT EXISTS truck_plate VARCHAR(20) DEFAULT NULL;

ALTER TABLE trucker_company_vehicles
    ADD COLUMN IF NOT EXISTS has_gps_tracker TINYINT(1) NOT NULL DEFAULT 0;
```

- [ ] **Step 2: Add columns to `import.sql` (fresh install schema)**

Find the `CREATE TABLE trucker_jobs` block in `import.sql`. Add `truck_plate VARCHAR(20) DEFAULT NULL,` as a new column (anywhere inside the table, before the closing parenthesis).

Find the `CREATE TABLE trucker_company_vehicles` block. Add `has_gps_tracker TINYINT(1) NOT NULL DEFAULT 0,` as a new column.

- [ ] **Step 3: Append `Config.CargoTheft` to the end of `config/config.lua`**

The current last line of `config/config.lua` is `}` (closing `Config.Skills`). Append after it:

```lua

-- ============================================================
-- CARGO THEFT (v14.0.0)
-- ============================================================

Config.CargoTheft = {
    VulnerableDelay  = 30,       -- segundos parado sem motorista para ativar vulnerabilidade
    TheftDuration    = 20,       -- segundos do progress bar de roubo
    TheftRange       = 15.0,     -- distância máxima entre caminhões para transferência (metros)
    TheftBonus       = 0.25,     -- +25% sobre base_payment para carga roubada entregue
    GpsTrackerPrice  = 5000,     -- $ para instalar GPS tracker num veículo de empresa
    VulnerableBlip   = true,     -- mostrar blip para todos os jogadores quando cargo é vulnerável
    PoliceJob        = 'police', -- job dos policiais que recebem alertas de roubo
    PoliceZones      = {
        { name = 'Porto',           coords = vec3(361.0,   -2545.0,  5.7),   radius = 300.0 },
        { name = 'Zona Industrial', coords = vec3(100.0,   -1700.0, 29.0),   radius = 400.0 },
        { name = 'Aeroporto',       coords = vec3(-1037.0, -2737.0, 13.0),   radius = 500.0 },
        { name = 'Centro',          coords = vec3(195.0,    -930.0, 30.0),   radius = 400.0 },
        { name = 'Los Santos Sul',  coords = vec3(80.0,    -1620.0, 29.0),   radius = 350.0 },
    },
}
```

- [ ] **Step 4: Verify config loads without errors**

Start the FiveM server. Expected: no `[AUST_trucker]` Lua errors in the server console.

- [ ] **Step 5: Commit**

```bash
git add sql/update_cargo_theft_v14.sql import.sql config/config.lua
git commit -m "feat(cargo-theft): SQL migration + Config.CargoTheft block"
```

---

## Task 2: DB Functions

**Files:**
- Modify: `server/database.lua` (append after existing DB functions)

Context: existing DB functions follow this pattern:
```lua
function DB_SomeName(param)
    return MySQL.query.await('SELECT ...', { param })
end
```

- [ ] **Step 1: Append 5 new DB functions to `server/database.lua`**

Append at the end of the file:

```lua
-- =====================================================
-- CARGO THEFT DB FUNCTIONS (v14.0.0)
-- =====================================================

-- Salva a plate do caminhão no job ativo (chamado quando jogador entra no truck)
function DB_SetTruckPlate(jobId, plate)
    MySQL.update.await(
        'UPDATE trucker_jobs SET truck_plate = ? WHERE id = ?',
        { plate, jobId }
    )
end

-- Busca job ativo pela plate do caminhão (para roubo e validação)
function DB_GetActiveJobByPlate(plate)
    return MySQL.single.await(
        "SELECT * FROM trucker_jobs WHERE truck_plate = ? AND status = 'active' LIMIT 1",
        { plate }
    )
end

-- Busca qualquer job pelo ID (para cálculo de pagamento do ladrão)
function DB_GetJobById(jobId)
    return MySQL.single.await(
        'SELECT * FROM trucker_jobs WHERE id = ? LIMIT 1',
        { jobId }
    )
end

-- Marca job como falhado (carga roubada)
function DB_SetCargoFailed(jobId)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'failed' WHERE id = ?",
        { jobId }
    )
end

-- Atualiza GPS tracker de um veículo de empresa (por plate)
function DB_SetGpsTracker(plate, enabled)
    MySQL.update.await(
        'UPDATE trucker_company_vehicles SET has_gps_tracker = ? WHERE plate = ?',
        { enabled and 1 or 0, plate }
    )
end

-- Retorna se um veículo tem GPS tracker instalado
function DB_GetVehicleGps(plate)
    local row = MySQL.single.await(
        'SELECT has_gps_tracker FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
    return row and row.has_gps_tracker == 1
end
```

- [ ] **Step 2: Verify no Lua errors on server start**

Restart resource. Expected: no errors. The new functions are globals accessible by all server files.

- [ ] **Step 3: Commit**

```bash
git add server/database.lua
git commit -m "feat(cargo-theft): add DB functions for plate tracking and GPS"
```

---

## Task 3: main.lua + fxmanifest load order

**Files:**
- Modify: `server/main.lua` (lines 6–28 — VP_Trucker table and init thread)
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Add `CargoByPlate` to VP_Trucker in `server/main.lua`**

In `server/main.lua`, find the `VP_Trucker = { ... }` block (lines 6-28). Add `CargoByPlate` after `TradePointActive`:

```lua
    -- Fase 5: Forklift
    ForkliftRentals  = {},  -- citizenId → { locationId, mode, src, rentedAt, loaded, expected }
    TradePointActive = {},  -- locationId → citizenId (um player por trade point)
    -- Fase 5: Cargo Theft
    CargoByPlate     = {},  -- plate → { jobId, citizenId, gpsEnabled, isStolen, basePayment, vulnerableSince, theftBy, theftStartedAt }
```

- [ ] **Step 2: Wire `CargoTrackingService.LoadFromDB()` into the init thread**

In `server/main.lua`, find the init thread (lines 55-65). After `ConvoyService.LoadFromDB()`, add:

```lua
            while not CargoTrackingService do Wait(100) end
            CargoTrackingService.LoadFromDB()
```

The complete init thread should look like:
```lua
        CreateThread(function()
            while not JobService do Wait(100) end
            while not IndustryOwnershipService do Wait(100) end
            while not ConvoyService do Wait(100) end
            IndustryOwnershipService.LoadCache()
            JobService.LoadFromDB()
            ConvoyService.LoadFromDB()
            while not CargoTrackingService do Wait(100) end
            CargoTrackingService.LoadFromDB()
            while not NpcDriverService do Wait(100) end
            NpcDriverService.LoadFromDB()
            VP_Trucker.Ready = true
            if Config.Debug then print('[AUST_trucker] Server ready.') end
        end)
```

- [ ] **Step 3: Update `fxmanifest.lua` — add new files to load order**

In `server_scripts`, add `cargo_tracking_service.lua` **after** `forklift_service.lua` and **before** `job_service.lua`:

```lua
    'server/services/forklift_service.lua',
    'server/services/cargo_tracking_service.lua',   -- v14: após forklift, antes de job_service
    'server/services/job_service.lua',
```

In `client_scripts`, add `cargo_theft.client.lua` after `forklift.client.lua`:

```lua
    'client/forklift.client.lua',
    'client/cargo_theft.client.lua',    -- v14: cargo theft mechanics
```

- [ ] **Step 4: Verify server starts without errors**

The new service files don't exist yet so the resource will fail to load — that's expected. Just verify the fxmanifest syntax is correct (no Lua parse errors in the manifest itself).

- [ ] **Step 5: Commit**

```bash
git add server/main.lua fxmanifest.lua
git commit -m "feat(cargo-theft): main.lua CargoByPlate + fxmanifest load order"
```

---

## Task 4: CargoTrackingService

**Files:**
- Create: `server/services/cargo_tracking_service.lua`

- [ ] **Step 1: Create `server/services/cargo_tracking_service.lua`**

```lua
-- server/services/cargo_tracking_service.lua
-- CargoTrackingService: gerencia cargo vinculado a veículos e mecânicas de roubo (v14.0.0)

CargoTrackingService = {}

-- Timers pendentes de vulnerabilidade: plate → true (ativo) / false (cancelado)
local PendingVulnerability = {}

-- -------------------------------------------------------
-- Helpers internos
-- -------------------------------------------------------

-- Retorna o source FiveM de um citizenId (ou nil se offline)
local function GetSrcByCitizenId(citizenId)
    local players = exports.qbx_core:GetQBPlayers()
    for src, Player in pairs(players) do
        if Player.PlayerData.citizenid == citizenId then
            return src
        end
    end
    return nil
end

-- Retorna o nome da zona mais próxima das coordenadas dadas
function CargoTrackingService.GetNearestZoneName(coords)
    local nearest, dist = 'local desconhecido', math.huge
    for _, zone in ipairs(Config.CargoTheft.PoliceZones) do
        local d = #(coords - zone.coords)
        if d < dist then
            nearest = zone.name
            dist    = d
        end
    end
    return nearest
end

-- Notifica todos os policiais online com alerta vago de roubo
local function NotifyPolice(zoneName)
    local players = exports.qbx_core:GetQBPlayers()
    for src, Player in pairs(players) do
        if Player.PlayerData.job and Player.PlayerData.job.name == Config.CargoTheft.PoliceJob then
            TriggerClientEvent('AUST_trucker:client:policeCargoAlert', src, zoneName)
        end
    end
end

-- -------------------------------------------------------
-- API pública
-- -------------------------------------------------------

-- Registra cargo quando o jogador entra no caminhão com job ativo
-- Chamado de: events.lua (registerTruckPlate)
function CargoTrackingService.RegisterCargo(plate, jobId, citizenId, basePayment, gpsEnabled)
    VP_Trucker.CargoByPlate[plate] = {
        jobId           = jobId,
        citizenId       = citizenId,
        gpsEnabled      = gpsEnabled,
        isStolen        = false,
        basePayment     = basePayment,
        vulnerableSince = nil,
        theftBy         = nil,
        theftStartedAt  = nil,
    }
    DB_SetTruckPlate(jobId, plate)
end

-- Inicia o timer de vulnerabilidade quando jogador sai do caminhão
-- Chamado de: events.lua (cargoPlayerLeft)
function CargoTrackingService.OnPlayerLeft(plate, ownerSrc)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo or cargo.isStolen then return end

    PendingVulnerability[plate] = true

    SetTimeout(Config.CargoTheft.VulnerableDelay * 1000, function()
        if not PendingVulnerability[plate] then return end  -- foi cancelado
        PendingVulnerability[plate] = nil

        local c = VP_Trucker.CargoByPlate[plate]
        if not c then return end

        c.vulnerableSince = os.time()

        -- Avisa o client do dono para setar StateBag no vehicle
        TriggerClientEvent('AUST_trucker:client:cargoVulnerable', ownerSrc, plate)

        -- Broadcast blip para todos (se configurado)
        if Config.CargoTheft.VulnerableBlip then
            local players = exports.qbx_core:GetQBPlayers()
            for src, _ in pairs(players) do
                if src ~= ownerSrc then
                    TriggerClientEvent('AUST_trucker:client:cargoVulnerableOther', src, plate)
                end
            end
        end
    end)
end

-- Cancela timer/roubo quando jogador volta ao caminhão
-- Chamado de: events.lua (cargoPlayerReturned)
function CargoTrackingService.OnPlayerReturned(plate)
    PendingVulnerability[plate] = false  -- cancela timer pendente

    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return end

    -- Cancela roubo em andamento
    if cargo.theftBy then
        local thiefSrc = GetSrcByCitizenId(cargo.theftBy)
        if thiefSrc then
            TriggerClientEvent('AUST_trucker:client:theftCancelled', thiefSrc)
        end
    end

    cargo.vulnerableSince = nil
    cargo.theftBy         = nil
    cargo.theftStartedAt  = nil
end

-- Inicia um roubo de carga
-- Retorna true on success, false + msg on failure
-- Chamado de: events.lua (startCargoTheft)
function CargoTrackingService.StartTheft(plate, thiefCitizenId, thiefSrc, truckCoords)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return false, 'Carga não encontrada.' end
    if not cargo.vulnerableSince then return false, 'Carga não está vulnerável.' end
    if cargo.theftBy then return false, 'Roubo já em andamento.' end
    if cargo.citizenId == thiefCitizenId then return false, 'Não pode roubar sua própria carga.' end

    cargo.theftBy        = thiefCitizenId
    cargo.theftStartedAt  = os.time()

    -- Notificação GPS
    if cargo.gpsEnabled then
        local ownerSrc = GetSrcByCitizenId(cargo.citizenId)
        if ownerSrc then
            TriggerClientEvent('AUST_trucker:client:cargoTheftAlert', ownerSrc, plate)
        end
        local zoneName = CargoTrackingService.GetNearestZoneName(truckCoords)
        NotifyPolice(zoneName)
    end

    return true
end

-- Completa o roubo — transfere cargo para o ladrão
-- Retorna { destId, basePayment } on success, nil on failure
-- Chamado de: events.lua (completeCargoTheft)
function CargoTrackingService.CompleteTheft(plate, thiefPlate, thiefCitizenId)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return nil end
    if cargo.theftBy ~= thiefCitizenId then return nil end

    -- Validação de timing server-side (evita exploit de conclusão prematura)
    local elapsed = os.time() - (cargo.theftStartedAt or 0)
    if elapsed < (Config.CargoTheft.TheftDuration - 2) then
        return nil  -- muito rápido: cheat
    end

    -- Falha o job original
    DB_SetCargoFailed(cargo.jobId)

    -- Notifica o dono
    local ownerSrc = GetSrcByCitizenId(cargo.citizenId)
    if ownerSrc then
        TriggerClientEvent('AUST_trucker:client:cargoStolen', ownerSrc)
    end

    -- Busca dados do job para montar entrada do ladrão
    local job = DB_GetJobById(cargo.jobId)
    local result = {
        jobId       = cargo.jobId,
        destId      = job and job.dest_id or nil,
        basePayment = cargo.basePayment,
    }

    -- Remove entrada do dono
    VP_Trucker.CargoByPlate[plate] = nil
    PendingVulnerability[plate]    = nil

    -- Registra cargo sob a plate do ladrão
    VP_Trucker.CargoByPlate[thiefPlate] = {
        jobId           = cargo.jobId,
        citizenId       = thiefCitizenId,
        gpsEnabled      = false,
        isStolen        = true,
        basePayment     = cargo.basePayment,
        vulnerableSince = nil,
        theftBy         = nil,
        theftStartedAt  = nil,
    }

    return result
end

-- Cancela roubo (chamado quando ladrão desiste ou dono voltou)
function CargoTrackingService.CancelTheft(plate, thiefCitizenId)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return end
    if cargo.theftBy ~= thiefCitizenId then return end
    cargo.theftBy        = nil
    cargo.theftStartedAt  = nil
end

-- Reivindica entrega — valida que o plate e citizenId batem
-- Retorna cargo entry (e remove do mapa) on success, nil on failure
-- Chamado de: events.lua (completeJob)
function CargoTrackingService.ClaimDelivery(plate, citizenId)
    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo then return nil end
    if cargo.citizenId ~= citizenId then return nil end
    VP_Trucker.CargoByPlate[plate] = nil
    PendingVulnerability[plate]    = nil
    return cargo
end

-- Remove entrada (job abandonado ou falhou por outro motivo)
function CargoTrackingService.RemoveCargo(plate)
    VP_Trucker.CargoByPlate[plate] = nil
    PendingVulnerability[plate]    = nil
end

-- Recupera cargo ativo do DB no startup (jobs que estavam ativos quando o server caiu)
function CargoTrackingService.LoadFromDB()
    local rows = MySQL.query.await(
        "SELECT id, truck_plate, assigned_citizenid, base_payment FROM trucker_jobs WHERE status = 'active' AND truck_plate IS NOT NULL"
    ) or {}
    for _, row in ipairs(rows) do
        VP_Trucker.CargoByPlate[row.truck_plate] = {
            jobId           = row.id,
            citizenId       = row.assigned_citizenid,
            gpsEnabled      = false,  -- GPS state não é persistido; conservador: sem notificação pós-restart
            isStolen        = false,
            basePayment     = row.base_payment,
            vulnerableSince = nil,
            theftBy         = nil,
            theftStartedAt  = nil,
        }
    end
    if Config.Debug then
        print(('[AUST_trucker] CargoTracking: recovered %d active cargo entries'):format(#rows))
    end
end
```

- [ ] **Step 2: Verify resource starts without Lua errors**

Restart resource. Expected: no `[AUST_trucker]` errors in server console. `CargoTrackingService` global is now accessible.

- [ ] **Step 3: Commit**

```bash
git add server/services/cargo_tracking_service.lua
git commit -m "feat(cargo-theft): add CargoTrackingService"
```

---

## Task 5: events.lua — 5 new handlers + modify acceptJob + completeJob

**Files:**
- Modify: `server/events.lua`

Context: current `acceptJob` handler is at lines 9–31. Current `completeJob` handler is at lines 33–43.

- [ ] **Step 1: Modify `acceptJob` handler (lines 9–31) to tell client to start cargo monitoring**

After `TriggerClientEvent('AUST_trucker:client:jobStarted', src, jobData)` on line 29, add:

```lua
    -- Informa o client para iniciar monitoramento de plate (cargo tracking v14)
    TriggerClientEvent('AUST_trucker:client:startCargoMonitoring', src)
```

The complete handler becomes:
```lua
RegisterNetEvent('AUST_trucker:acceptJob', function(jobId)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    if JobService.GetActiveByPlayer(citizenId) then
        TriggerClientEvent('AUST_trucker:notify', src, 'Você já tem um job ativo', 'error')
        return
    end

    local company = CompanyService.GetByMember(citizenId)
    local accepted = JobService.Accept(jobId, citizenId, company and company.id or nil)
    if not accepted then
        TriggerClientEvent('AUST_trucker:notify', src, 'Você não possui a certificação ADR necessária para este cargo', 'error')
        return
    end

    local jobData = JobService.GetActiveByPlayer(citizenId)
    TriggerClientEvent('AUST_trucker:client:jobStarted', src, jobData)
    TriggerClientEvent('AUST_trucker:client:startCargoMonitoring', src)   -- v14
    TriggerEvent('AUST_trucker:jobAccepted', citizenId, company and company.id or nil, jobData)
end)
```

- [ ] **Step 2: Modify `completeJob` handler (lines 33–43) to route stolen cargo to CompleteTheft**

Replace the existing `completeJob` handler with:

```lua
RegisterNetEvent('AUST_trucker:completeJob', function(payload)
    local src = source
    -- payload = { deliveryTime, plate, cargoIntegrity }

    -- Verifica se é entrega de carga roubada
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local cargoEntry = CargoTrackingService.ClaimDelivery(payload.plate, citizenId)
    if cargoEntry and cargoEntry.isStolen then
        -- Caminho de carga roubada
        local payment = JobService.CompleteTheft(src, cargoEntry, payload)
        if payment then
            TriggerClientEvent('AUST_trucker:client:jobCompleted', src, payment)
            TriggerClientEvent('AUST_trucker:notify', src,
                ('Carga entregue! [ROUBADA] $%d recebidos'):format(payment), 'success')
        end
        return
    end

    -- Caminho normal
    local ok, payment = JobService.Complete(src, payload)
    if ok then
        local integrityPct = math.max(0, math.min(100, tonumber(payload.cargoIntegrity) or 100))
        TriggerClientEvent('AUST_trucker:client:jobCompleted', src, payment)
        TriggerClientEvent('AUST_trucker:notify', src,
            ('Job concluído! Carga: %d%% — $%d recebidos'):format(integrityPct, payment), 'success')
    end
end)
```

- [ ] **Step 3: Append 5 new event handlers to `server/events.lua`**

Append after the existing `abandonJob` handler (after line 51):

```lua
-- =====================================================
-- CARGO THEFT HANDLERS (v14.0.0)
-- =====================================================

-- Jogador entra no caminhão com job ativo → registra plate no CargoTracking
RegisterNetEvent('AUST_trucker:registerTruckPlate', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local activeJob = DB_GetActiveJobByPlayer(citizenId)
    if not activeJob then return end

    -- Evita re-registro se já existe e é o mesmo job
    local existing = VP_Trucker.CargoByPlate[plate]
    if existing and existing.jobId == activeJob.id then return end

    local gpsEnabled = DB_GetVehicleGps(plate)
    CargoTrackingService.RegisterCargo(plate, activeJob.id, citizenId, activeJob.base_payment, gpsEnabled)
end)

-- Jogador saiu do caminhão com cargo ativo → inicia timer de vulnerabilidade
RegisterNetEvent('AUST_trucker:cargoPlayerLeft', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo or cargo.citizenId ~= citizenId then return end

    CargoTrackingService.OnPlayerLeft(plate, src)
end)

-- Jogador voltou ao caminhão → cancela timer/roubo
RegisterNetEvent('AUST_trucker:cargoPlayerReturned', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local cargo = VP_Trucker.CargoByPlate[plate]
    if not cargo or cargo.citizenId ~= citizenId then return end

    CargoTrackingService.OnPlayerReturned(plate)
    -- Remove StateBag de vulnerabilidade via owner's client
    TriggerClientEvent('AUST_trucker:client:cargoClear', src, plate)
end)

-- Ladrão inicia roubo
RegisterNetEvent('AUST_trucker:startCargoTheft', function(truckNetId, thiefNetId, truckPlate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    -- Valida entidades networked
    if not NetworkDoesEntityExistWithNetworkId(truckNetId) then return end
    if not NetworkDoesEntityExistWithNetworkId(thiefNetId) then return end

    local truckEntity = NetworkGetEntityFromNetworkId(truckNetId)
    local thiefEntity = NetworkGetEntityFromNetworkId(thiefNetId)
    local truckCoords = GetEntityCoords(truckEntity)
    local thiefCoords = GetEntityCoords(thiefEntity)

    -- Valida proximidade server-side
    if #(truckCoords - thiefCoords) > Config.CargoTheft.TheftRange then
        TriggerClientEvent('AUST_trucker:client:theftCancelled', src)
        return
    end

    local ok, reason = CargoTrackingService.StartTheft(truckPlate, citizenId, src, truckCoords)
    if ok then
        TriggerClientEvent('AUST_trucker:client:theftApproved', src)
    else
        TriggerClientEvent('AUST_trucker:notify', src, reason or 'Roubo inválido.', 'error')
    end
end)

-- Ladrão completa o roubo (progress bar terminou)
RegisterNetEvent('AUST_trucker:completeCargoTheft', function(truckPlate, thiefPlate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    local result = CargoTrackingService.CompleteTheft(truckPlate, thiefPlate, citizenId)
    if not result then
        TriggerClientEvent('AUST_trucker:notify', src, 'Roubo inválido ou expirado.', 'error')
        return
    end

    -- Informa o destino ao ladrão para navegação
    local destData = nil
    for _, d in ipairs(Config.SecondaryIndustries) do
        if d.id == result.destId then destData = d; break end
    end

    TriggerClientEvent('AUST_trucker:client:stolenJobStarted', src, {
        destCoords  = destData and destData.coords or nil,
        destName    = destData and destData.name or result.destId,
        basePayment = result.basePayment,
    })
end)
```

- [ ] **Step 4: Verify server starts and all existing job functions still work**

Restart resource. Check no Lua errors. Test accepting a normal job — should work as before.

- [ ] **Step 5: Commit**

```bash
git add server/events.lua
git commit -m "feat(cargo-theft): wire CargoTrackingService into events.lua"
```

---

## Task 6: job_service.lua — JobService.CompleteTheft

**Files:**
- Modify: `server/services/job_service.lua` (append after `JobService.Complete` function)

Context: `JobService.Complete` ends around line 370. Append after it.

- [ ] **Step 1: Add `JobService.CompleteTheft` to `server/services/job_service.lua`**

Append after the `JobService.Complete` function:

```lua
-- Conclui entrega de carga roubada — usado quando isStolen = true
-- cargoEntry = { jobId, basePayment, ... }  (da CargoTrackingService.ClaimDelivery)
-- payload    = { deliveryTime, plate }
-- Retorna payment (number) on success, nil on failure
function JobService.CompleteTheft(src, cargoEntry, payload)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil end

    local citizenId = Player.PlayerData.citizenid

    -- Calcular pagamento: base_payment × timeMult × TheftBonus
    -- timeMult baseado no tempo de entrega do ladrão (desde que assumiu o cargo)
    local timeMult   = GetTimeMultiplier(tonumber(payload.deliveryTime) or 9999)
    local payment    = math.floor(cargoEntry.basePayment * timeMult * (1.0 + Config.CargoTheft.TheftBonus))

    Player.Functions.AddMoney('bank', payment, 'cargo_theft_delivery')

    -- XP pelo job roubado (menor que entrega normal — sem multiplicadores extras)
    ProgressionService.GrantXP(src, citizenId, 1, 0)  -- 1 job concluído, 0 distance (roubado)

    if Config.Debug then
        print(('[cargo-theft] Ladrão %s entregou carga roubada — $%d'):format(citizenId, payment))
    end

    return payment
end
```

- [ ] **Step 2: Verify `GetTimeMultiplier` is accessible**

`GetTimeMultiplier` is a local function in `job_service.lua`. Since `CompleteTheft` is in the same file, it has access. Confirm by searching: `grep -n "local function GetTimeMultiplier\|function GetTimeMultiplier" server/services/job_service.lua` — expected: found.

- [ ] **Step 3: Commit**

```bash
git add server/services/job_service.lua
git commit -m "feat(cargo-theft): add JobService.CompleteTheft for stolen cargo delivery"
```

---

## Task 7: purchaseGpsTracker callback

**Files:**
- Modify: `server/callbacks.lua` (append)

- [ ] **Step 1: Append `purchaseGpsTracker` callback to `server/callbacks.lua`**

```lua
-- =====================================================
-- GPS TRACKER (v14.0.0)
-- =====================================================

lib.callback.register('AUST_trucker:purchaseGpsTracker', function(src, plate)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, 'Jogador inválido.' end
    local citizenId = Player.PlayerData.citizenid

    -- Validar que o veículo pertence à empresa do jogador
    local company = CompanyService.GetByMember(citizenId)
    if not company then return false, 'Você não é membro de uma empresa.' end

    local vehicles = DB_GetVehicles(company.id) or {}
    local vehicle  = nil
    for _, v in ipairs(vehicles) do
        if v.plate == plate then vehicle = v; break end
    end
    if not vehicle then return false, 'Veículo não pertence à sua empresa.' end

    if vehicle.has_gps_tracker == 1 then
        return false, 'Este veículo já tem GPS tracker instalado.'
    end

    -- Cobrar da conta da empresa
    local price = Config.CargoTheft.GpsTrackerPrice
    if company.balance < price then
        return false, ('Saldo insuficiente. Necessário: $%d'):format(price)
    end

    CompanyService.UpdateBalance(company.id, -price)
    DB_SetGpsTracker(plate, true)

    return true, ('GPS Tracker instalado em %s — $%d debitados da empresa.'):format(plate, price)
end)
```

- [ ] **Step 2: Verify callback is registered**

Restart resource, check no Lua errors.

- [ ] **Step 3: Commit**

```bash
git add server/callbacks.lua
git commit -m "feat(cargo-theft): purchaseGpsTracker callback"
```

---

## Task 8: client/cargo_theft.client.lua

**Files:**
- Create: `client/cargo_theft.client.lua`

This file handles two roles:
1. **Owner role** — monitors plate when job is active; fires server events on enter/exit truck
2. **Thief role** — detects vulnerable trucks via StateBag; shows ox_target; handles progress bar

- [ ] **Step 1: Create `client/cargo_theft.client.lua`**

```lua
-- client/cargo_theft.client.lua
-- Vehicle-Bound Cargo + Theft client (v14.0.0)
-- Lua 5.4 chunk — comunica com hud.client.lua via local events (TriggerEvent/AddEventHandler)

-- =====================================================
-- ESTADO LOCAL
-- =====================================================

local isMonitoring     = false   -- true quando jogador tem job ativo e monitora plate
local registeredPlate  = nil     -- plate registrada no server
local lastVehicle      = nil     -- entity do caminhão atual
local isInTruck        = false   -- true quando está como motorista no caminhão

-- Entidades com ox_target de roubo registrado (evita duplicatas)
local TheftTargets     = {}      -- entity → plate

-- Blips de cargo vulnerável
local VulnerableBlips  = {}      -- plate → blipHandle

-- =====================================================
-- UTILITÁRIOS
-- =====================================================

local function GetCurrentTruckPlate()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    -- Só considera veículos de carga (trucks/trailers com modelo válido)
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    return plate ~= '' and plate or nil
end

local function GetVehicleByPlate(plate)
    local vehicles = GetGamePool('CVehicle')
    for _, v in ipairs(vehicles) do
        local p = GetVehicleNumberPlateText(v):gsub('%s+', '')
        if p == plate then return v end
    end
    return nil
end

local function RemoveTheftTarget(entity)
    if TheftTargets[entity] then
        exports.ox_target:removeLocalEntity(entity)
        TheftTargets[entity] = nil
    end
end

local function RemoveVulnerableBlip(plate)
    if VulnerableBlips[plate] then
        RemoveBlip(VulnerableBlips[plate])
        VulnerableBlips[plate] = nil
    end
end

-- =====================================================
-- OWNER SIDE — monitoramento de plate
-- =====================================================

local function StopMonitoring()
    isMonitoring    = false
    registeredPlate = nil
    lastVehicle     = nil
    isInTruck       = false
end

-- Thread de monitoramento: detecta quando jogador entra/sai do caminhão
local function StartMonitoringThread()
    CreateThread(function()
        while isMonitoring do
            Wait(2000)
            if not isMonitoring then break end

            local plate = GetCurrentTruckPlate()
            local inTruck = plate ~= nil

            if inTruck and not isInTruck then
                -- Entrou no caminhão
                isInTruck = true
                if plate ~= registeredPlate then
                    registeredPlate = plate
                    TriggerServerEvent('AUST_trucker:registerTruckPlate', plate)
                end
                TriggerServerEvent('AUST_trucker:cargoPlayerReturned', plate)

            elseif not inTruck and isInTruck then
                -- Saiu do caminhão
                isInTruck = false
                if registeredPlate then
                    TriggerServerEvent('AUST_trucker:cargoPlayerLeft', registeredPlate)
                end
            end
        end
    end)
end

-- Server → client: job aceito, iniciar monitoramento
AddEventHandler('AUST_trucker:client:startCargoMonitoring', function()
    if isMonitoring then return end
    isMonitoring = true
    StartMonitoringThread()
end)

-- Job concluído normalmente ou abandonado → parar monitoramento
AddEventHandler('AUST_trucker:client:jobCompleted', function()
    StopMonitoring()
end)

AddEventHandler('AUST_trucker:client:jobAbandoned', function()
    if registeredPlate then
        CargoTrackingService = nil  -- não existe client-side; apenas limpa local
    end
    StopMonitoring()
end)

-- Cargo roubado — job falhou
RegisterNetEvent('AUST_trucker:client:cargoStolen', function()
    lib.notify({
        title       = 'Carga Roubada',
        description = 'Sua carga foi roubada! Job cancelado.',
        type        = 'error',
        duration    = 8000,
    })
    StopMonitoring()
    TriggerEvent('AUST_trucker:client:jobAbandoned')  -- atualiza HUD/SimState
end)

-- Alerta de roubo em andamento (GPS tracker)
RegisterNetEvent('AUST_trucker:client:cargoTheftAlert', function(plate)
    lib.notify({
        title       = 'Alerta GPS',
        description = ('Sua carga (%s) está sendo roubada!'):format(plate),
        type        = 'warning',
        duration    = 10000,
        icon        = 'satellite-dish',
    })
    -- Adicionar blip na posição do caminhão (o StateBag já está setado com a vulnerabilidade)
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        local blip = AddBlipForEntity(veh)
        SetBlipSprite(blip, 596)
        SetBlipColour(blip, 1)  -- vermelho
        SetBlipScale(blip, 1.2)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Sua Carga!')
        EndTextCommandSetBlipName(blip)
        Citizen.SetTimeout(30000, function() RemoveBlip(blip) end)
    end
end)

-- Server mandou limpar StateBag de vulnerabilidade (dono voltou)
RegisterNetEvent('AUST_trucker:client:cargoClear', function(plate)
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        Entity(veh).state:set('ct_vulnerable', nil, true)
    end
    RemoveVulnerableBlip(plate)
end)

-- Server ativou vulnerabilidade — owner client seta StateBag
RegisterNetEvent('AUST_trucker:client:cargoVulnerable', function(plate)
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        Entity(veh).state:set('ct_vulnerable', plate, true)
    end
end)

-- Broadcast para outros players (blip de cargo vulnerável)
RegisterNetEvent('AUST_trucker:client:cargoVulnerableOther', function(plate)
    -- Tenta encontrar o veículo para criar blip
    local veh = GetVehicleByPlate(plate)
    if veh and veh ~= 0 then
        if not VulnerableBlips[plate] then
            local blip = AddBlipForEntity(veh)
            SetBlipSprite(blip, 67)   -- ícone de caminhão
            SetBlipColour(blip, 49)   -- laranja
            SetBlipScale(blip, 0.8)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Carga Abandonada')
            EndTextCommandSetBlipName(blip)
            VulnerableBlips[plate] = blip
        end
    end
end)

-- Alerta de roubo para policiais
RegisterNetEvent('AUST_trucker:client:policeCargoAlert', function(zoneName)
    lib.notify({
        title       = '[CAD] Roubo de Carga',
        description = ('Roubo de carga reportado próximo a: %s'):format(zoneName),
        type        = 'warning',
        duration    = 15000,
        icon        = 'truck',
    })
end)

-- =====================================================
-- THIEF SIDE — detecta trucks vulneráveis e executa roubo
-- =====================================================

-- StateBag listener: detecta quando qualquer veículo recebe ct_vulnerable
AddStateBagChangeHandler('ct_vulnerable', nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 then return end

    if value then
        -- Veículo ficou vulnerável: adicionar ox_target
        if TheftTargets[entity] then return end  -- já tem target

        local plate = value  -- value é a plate
        TheftTargets[entity] = plate

        exports.ox_target:addLocalEntity(entity, {
            {
                name     = 'AUST_trucker:stealCargo_' .. plate,
                label    = 'Transferir Carga',
                icon     = 'fas fa-truck-ramp-box',
                distance = 3.0,
                onSelect = function()
                    InitiateTheft(entity, plate)
                end,
            }
        })
    else
        -- Cargo já não é mais vulnerável: remover ox_target
        RemoveTheftTarget(entity)
        -- Remover blip se existir
        local plate = TheftTargets[entity]
        if plate then RemoveVulnerableBlip(plate) end
    end
end)

-- Inicia o processo de roubo
function InitiateTheft(truckEntity, truckPlate)
    -- Validar que o ladrão tem um veículo próximo
    local ped    = PlayerPedId()
    local myVeh  = GetVehiclePedIsIn(ped, false)
    if not myVeh or myVeh == 0 then
        lib.notify({ description = 'Você precisa de um veículo para transferir a carga.', type = 'error' })
        return
    end
    if GetPedInVehicleSeat(myVeh, -1) ~= ped then
        lib.notify({ description = 'Você precisa estar no banco do motorista.', type = 'error' })
        return
    end

    -- Verificar distância client-side (validação adicional server-side)
    local truckCoords = GetEntityCoords(truckEntity)
    local myCoords    = GetEntityCoords(myVeh)
    if #(truckCoords - myCoords) > Config.CargoTheft.TheftRange then
        lib.notify({ description = ('Aproxime seu veículo a menos de %.0fm do caminhão.'):format(Config.CargoTheft.TheftRange), type = 'error' })
        return
    end

    local truckNetId = NetworkGetNetworkIdFromEntity(truckEntity)
    local myNetId    = NetworkGetNetworkIdFromEntity(myVeh)
    local myPlate    = GetVehicleNumberPlateText(myVeh):gsub('%s+', '')

    -- Solicitar aprovação ao server
    TriggerServerEvent('AUST_trucker:startCargoTheft', truckNetId, myNetId, truckPlate)

    -- Aguardar aprovação (via evento 'theftApproved')
    -- A progress bar começa somente após server confirmar
    _G.PendingTheftPlate     = truckPlate
    _G.PendingTheftMyPlate   = myPlate
    _G.PendingTheftEntity    = truckEntity
end

-- Server aprovou o roubo → iniciar progress bar
RegisterNetEvent('AUST_trucker:client:theftApproved', function()
    local truckPlate  = _G.PendingTheftPlate
    local myPlate     = _G.PendingTheftMyPlate
    local truckEntity = _G.PendingTheftEntity
    _G.PendingTheftPlate    = nil
    _G.PendingTheftMyPlate  = nil
    _G.PendingTheftEntity   = nil

    if not truckPlate then return end

    local completed = lib.progressBar({
        duration    = Config.CargoTheft.TheftDuration * 1000,
        label       = 'Transferindo carga...',
        useWhileDead = false,
        canCancel   = true,
        disable     = { move = false, car = true, combat = true },
    })

    if completed then
        TriggerServerEvent('AUST_trucker:completeCargoTheft', truckPlate, myPlate)
        -- Remover ox_target imediatamente (evita duplo roubo)
        if truckEntity then RemoveTheftTarget(truckEntity) end
    else
        -- Ladrão cancelou (pressionou ESC ou moveu)
        TriggerServerEvent('AUST_trucker:cancelCargoTheft', truckPlate)
    end
end)

-- Server cancelou o roubo (dono voltou ou inválido)
RegisterNetEvent('AUST_trucker:client:theftCancelled', function()
    lib.notify({ description = 'Roubo interrompido!', type = 'error', duration = 4000 })
    -- A progress bar é interrompida automaticamente se o server dispara canCancel
    -- ou via lib.progressBar internamente — não há API para cancelar externamente em ox_lib
    -- O handler de theftCancelled serve para notificação; a barra expira naturalmente
end)

-- =====================================================
-- THIEF DELIVERY — job roubado em andamento
-- =====================================================

local stolenJobActive = false
local stolenJobBlip   = nil

RegisterNetEvent('AUST_trucker:client:stolenJobStarted', function(data)
    stolenJobActive = true

    if data.destCoords then
        stolenJobBlip = AddBlipForCoord(data.destCoords.x, data.destCoords.y, data.destCoords.z)
        SetBlipSprite(stolenJobBlip, 67)
        SetBlipColour(stolenJobBlip, 1)  -- vermelho
        SetBlipScale(stolenJobBlip, 0.9)
        SetBlipRoute(stolenJobBlip, true)
        SetBlipRouteColour(stolenJobBlip, 1)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Entregar Carga: ' .. (data.destName or ''))
        EndTextCommandSetBlipName(stolenJobBlip)
    end

    lib.notify({
        title       = 'Carga Transferida',
        description = ('Entregue em: %s | Bônus: +%.0f%%'):format(data.destName or '?', Config.CargoTheft.TheftBonus * 100),
        type        = 'success',
        duration    = 10000,
    })

    -- Iniciar monitoramento como dono da carga roubada
    isMonitoring    = true
    registeredPlate = GetCurrentTruckPlate()
    StartMonitoringThread()
end)

-- Limpar blip de stolen job quando concluído
AddEventHandler('AUST_trucker:client:jobCompleted', function()
    if stolenJobBlip then
        RemoveBlip(stolenJobBlip)
        stolenJobBlip = nil
    end
    stolenJobActive = false
end)

-- =====================================================
-- CLEANUP no stop do resource
-- =====================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for entity, _ in pairs(TheftTargets) do
        exports.ox_target:removeLocalEntity(entity)
    end
    for _, blip in pairs(VulnerableBlips) do
        RemoveBlip(blip)
    end
    if stolenJobBlip then RemoveBlip(stolenJobBlip) end
end)
```

- [ ] **Step 2: Add `AUST_trucker:cancelCargoTheft` handler to `server/events.lua`**

Append to events.lua (the client sends this when the progress bar is cancelled):

```lua
RegisterNetEvent('AUST_trucker:cancelCargoTheft', function(truckPlate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid
    CargoTrackingService.CancelTheft(truckPlate, citizenId)
end)
```

- [ ] **Step 3: Verify resource starts without client Lua errors**

Restart resource, join game. Check F8 console: no `[AUST_trucker]` errors.

- [ ] **Step 4: Manual smoke test — owner side**

1. Accept a job in-game
2. Get into a truck
3. Check server console: should see `CargoTracking: RegisterCargo` (add a debug print in CargoTrackingService.RegisterCargo if needed)
4. Exit the truck, wait 35 seconds
5. Re-enter: expected — `cargoPlayerReturned` logged server-side, no vulnerability

- [ ] **Step 5: Commit**

```bash
git add client/cargo_theft.client.lua server/events.lua
git commit -m "feat(cargo-theft): client vehicle monitoring + theft mechanics"
```

---

## Task 9: CHANGELOG + version bump

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Add v14.0.0 entry to `CHANGELOG.md`**

Insert before the `## [13.0.0]` line:

```markdown
## [14.0.0] — 2026-03-21 — Vehicle-Bound Cargo + Theft

### Added
- **Cargo vinculado ao veículo** (`server/services/cargo_tracking_service.lua`)
  - Cargo registrado em `VP_Trucker.CargoByPlate[plate]` quando jogador entra no caminhão
  - Persistido em `trucker_jobs.truck_plate` para recuperação pós-restart
- **Roubo de carga**: caminhão parado sem motorista por 30s → vulnerável
  - ox_target via StateBag `ct_vulnerable` detectado por todos os clients
  - Progress bar de 20s (server-authoritative timing)
  - Transferência para veículo do ladrão (validação de proximidade ≤15m server-side)
- **Job do ladrão**: pagamento = `base_payment × timeMult × 1.25` (sem companyMult/integrityMult)
- **GPS Tracker**: upgrade de $5.000 para veículos de empresa
  - Dono notificado com blip exato quando roubo inicia
  - Policiais notificados com referência vaga de zona (`Config.CargoTheft.PoliceZones`)
- `Config.CargoTheft` block em `config/config.lua`
- Migration: `sql/update_cargo_theft_v14.sql`

### Changed
- `server/events.lua` — `acceptJob` envia `startCargoMonitoring`; `completeJob` roteia carga roubada para `CompleteTheft`
- `server/services/job_service.lua` — `JobService.CompleteTheft()` para pagamento de cargo roubado
- `server/callbacks.lua` — callback `purchaseGpsTracker`

---

```

- [ ] **Step 2: Bump version in `fxmanifest.lua`**

Change `version '13.0.0'` to `version '14.0.0'`.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md fxmanifest.lua
git commit -m "feat(cargo-theft): v14.0.0 — changelog and version bump"
```

---

## What Already Exists (não reimplementar)

- `DB_GetActiveJobByPlayer(citizenId)` — já existe em `database.lua`
- `DB_GetVehicles(companyId)` — já existe, usado no purchaseGpsTracker
- `CompanyService.UpdateBalance(companyId, amount)` — já existe em `company_service.lua`
- `CompanyService.GetByMember(citizenId)` — já existe
- `GetTimeMultiplier(deliveryTime)` — local function em `job_service.lua`; `CompleteTheft` está no mesmo arquivo
- `ProgressionService.GrantXP(src, citizenId, jobsCompleted, distance)` — já existe
- `lib.progressBar()`, `lib.notify()` — ox_lib, já usado no forklift system
- `exports.ox_target:addLocalEntity()`, `removeLocalEntity()` — já usado em `adr.client.lua`
- `AddStateBagChangeHandler` — FiveM nativo OneSync, sem dependências
- `exports.qbx_core:GetQBPlayers()` — já usado em vários serviços

## Notas de Segurança

- **Plate validada server-side**: `completeJob` verifica `CargoByPlate[plate].citizenId == requester`
- **Timing de roubo server-side**: `os.time() - theftStartedAt` verificado em `CompleteTheft` (tolerance de 2s)
- **Proximidade server-side**: `#(truckCoords - thiefCoords) > TheftRange` usando coords de entidades networked
- **Ownership do roubo**: `cargo.theftBy == thiefCitizenId` verificado em `CompleteTheft`
- **Ladrão não pode roubar própria carga**: `cargo.citizenId == thiefCitizenId` rejeitado em `StartTheft`
