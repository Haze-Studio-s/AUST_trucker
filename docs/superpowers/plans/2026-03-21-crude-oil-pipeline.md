# Phase 1: Crude Oil Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect AUST_oilfield and AUST_trucker so truckers with tanker vehicles and ADR `flammable_liquid` cert can pick up crude oil barrels at wells and deliver to the refinery, with optional price-setting by well owners.

**Architecture:** AUST_oilfield exposes server-side exports for barrel consumption and manifest management via a new `server/crude_pipeline.lua`; AUST_trucker calls these exports server-side and manages cargo tracking in a standalone `ActiveCrudeJobs` in-memory table. Client interaction (pickup progressBar) lives in AUST_oilfield; delivery progressBar lives in AUST_trucker. Communication between resources is always via `pcall`-wrapped export calls — no shared global state.

> **Nota de desvio do spec:** O spec mencionava modificar `server/transport.lua` e `client/transport.lua`. O plano cria arquivos novos (`crude_pipeline.lua`) em vez disso, para não tocar no sistema de manifesto de inventário existente. Comportamento equivalente, separação mais limpa.

> **Fora de escopo neste plano:** Persistência de `ActiveCrudeJobs` no banco de dados (recuperação ao reconectar após desconexão com carga). O spec menciona esse edge case, mas é diferido para uma fase de hardening. Atualmente, desconexão com carga = perda do job (barris NÃO são devolvidos automaticamente — ficam consumidos no DB e o manifesto expira em ~1h).

**Tech Stack:** Lua 5.4, FiveM/QBox (qbx_core), ox_lib (progressBar, inputDialog, target), ox_target, oxmysql (MySQL.single/update/insert/query.await), AUST_oilfield v2.5.4+, AUST_trucker v17.x

---

## File Map

### AUST_oilfield (`E:\...\AUST_oilfield\`)
| File | Action | Responsibility |
|---|---|---|
| `server/main.lua` | MODIFY (~line 1) | Add `CREATE TABLE` + `ALTER TABLE` at startup |
| `server/crude_pipeline.lua` | CREATE | All server exports + net events for crude transport |
| `client/crude_pipeline.lua` | CREATE | ox_target zones on wells, progressBar loading, Mode B price-setting |
| `config.lua` | MODIFY | Add `Config.CrudeOilPipeline` block |

> AUST_oilfield uses `server/*` and `client/*` wildcards — new files are auto-loaded. No fxmanifest change needed.

### AUST_trucker (`E:\...\AUST_trucker\`)
| File | Action | Responsibility |
|---|---|---|
| `config/config.lua` | MODIFY | Add `Config.CrudeOil` block with refinery coords |
| `server/crude_oil.lua` | CREATE | `StartCrudeJob` export, `CheckPlayerAdr` export, delivery handler, `ActiveCrudeJobs` state |
| `server/exports.lua` | MODIFY | Add `GetActiveJobByPlate(plate)` export |
| `server/callbacks.lua` | MODIFY | `getInitialData` merges crude oil posted wells |
| `client/crude_oil.lua` | CREATE | ox_target at refineries, progressBar unloading, GPS event handler |
| `fxmanifest.lua` | MODIFY | Add `server/crude_oil.lua` and `client/crude_oil.lua` |

---

## Task 1: Database Migration (AUST_oilfield)

**Files:**
- Modify: `server/main.lua` — add SQL at the very top, before any other startup code

The `lm_transport_manifests` table tracks all crude oil transport jobs. `transport_price_per` on `lm_wells` stores the owner's custom price offer (NULL = use config base price, which means no job board listing).

- [ ] **Step 1: Add CREATE TABLE to server/main.lua**

Open `server/main.lua`. At the very top of the file (line 1, before any `local` declarations), add:

```lua
-- Crude Oil Pipeline schema
MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS `lm_transport_manifests` (
        `id`          INT AUTO_INCREMENT PRIMARY KEY,
        `well_id`     INT NOT NULL,
        `trucker_id`  VARCHAR(64) NOT NULL,
        `quantity`    TINYINT UNSIGNED NOT NULL,
        `price_per`   INT NOT NULL,
        `mode`        ENUM('open','posted') DEFAULT 'open',
        `status`      ENUM('pending','active','delivered','expired','stolen') DEFAULT 'active',
        `expires_at`  BIGINT NOT NULL,
        `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_well_id` (`well_id`),
        INDEX `idx_trucker_id` (`trucker_id`),
        INDEX `idx_status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]], {})

MySQL.query.await([[
    ALTER TABLE `lm_wells`
    ADD COLUMN IF NOT EXISTS `transport_price_per` INT DEFAULT NULL
]], {})
```

- [ ] **Step 2: Verify migration runs cleanly**

Start the resource and check server console. Expected output: no SQL errors. Then verify in DB:

```sql
DESCRIBE lm_transport_manifests;
SHOW COLUMNS FROM lm_wells LIKE 'transport_price_per';
```

Expected: table exists with 10 columns; column exists.

- [ ] **Step 3: Commit**

```bash
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_oilfield"
git add server/main.lua
git commit -m "feat: add lm_transport_manifests table and transport_price_per column to lm_wells"
```

---

## Task 2: Config Block (AUST_oilfield)

**Files:**
- Modify: `config.lua`

- [ ] **Step 1: Add Config.CrudeOilPipeline to config.lua**

Find the end of `config.lua` and append:

```lua
Config.CrudeOilPipeline = {
    BasePrice      = 150,    -- $/barrel for open pickup (no owner price set)
    ManifestExpiry = 3600,   -- seconds until manifest expires
    LoadTimePerBarrel = 3000, -- ms per barrel (progressBar)
    UnloadTimePerBarrel = 2000, -- ms per barrel at refinery
    PickupRadius   = 8.0,    -- meters for ox_target sphere on well
    TankerModels   = { 'tanker', 'tanker2', 'flatbed' },
    MaxBarrels     = {       -- max barrels per tanker model
        tanker  = 20,
        tanker2 = 16,
        flatbed = 10,
        default = 8,
    },
}
```

- [ ] **Step 2: Commit**

```bash
git add config.lua
git commit -m "feat: add Config.CrudeOilPipeline block"
```

---

## Task 3: Server Pipeline Exports (AUST_oilfield)

**Files:**
- Create: `server/crude_pipeline.lua`

This file defines private DB helpers, exports for AUST_trucker to call, and net events for pickup coordination.

- [ ] **Step 1: Create server/crude_pipeline.lua**

```lua
-- server/crude_pipeline.lua
-- Crude Oil Pipeline — server-side exports and event handlers
-- Called by AUST_trucker via pcall(exports['AUST_oilfield']:...) on the server.

----------------------------------------
-- Private DB helpers
----------------------------------------

local function DB_GetWell(wellId)
    return MySQL.single.await(
        'SELECT id, barrels_stored, transport_price_per, coords, zone_id, status, owner FROM lm_wells WHERE id = ? LIMIT 1',
        { wellId }
    )
end

local function DB_ConsumeBarrels(wellId, qty)
    -- Atomic: only subtracts if enough barrels remain
    local affected = MySQL.update.await(
        'UPDATE lm_wells SET barrels_stored = barrels_stored - ? WHERE id = ? AND barrels_stored >= ? AND status IN ("producing","idle")',
        { qty, wellId, qty }
    )
    return (affected or 0) > 0
end

local function DB_ReturnBarrels(wellId, qty)
    MySQL.update.await(
        'UPDATE lm_wells SET barrels_stored = barrels_stored + ? WHERE id = ?',
        { qty, wellId }
    )
end

local function DB_CreateManifest(wellId, truckerId, qty, pricePerBarrel, mode)
    local expiresAt = os.time() + (Config.CrudeOilPipeline.ManifestExpiry or 3600)
    return MySQL.insert.await(
        'INSERT INTO lm_transport_manifests (well_id, trucker_id, quantity, price_per, mode, status, expires_at) VALUES (?, ?, ?, ?, ?, "active", ?)',
        { wellId, truckerId, qty, pricePerBarrel, mode or 'open', expiresAt }
    )
end

----------------------------------------
-- EXPORTS (called by AUST_trucker server via pcall)
----------------------------------------

--- Returns current barrels_stored for a well.
exports('GetWellBarrels', function(wellId)
    return MySQL.scalar.await(
        'SELECT barrels_stored FROM lm_wells WHERE id = ?', { wellId }
    ) or 0
end)

--- Atomically removes qty barrels. Returns true if successful.
exports('ConsumeBarrels', DB_ConsumeBarrels)

--- Returns barrels to well (used on job abandon).
exports('ReturnBarrels', DB_ReturnBarrels)

--- Creates a manifest record and returns its ID.
exports('CreateCrudeManifest', DB_CreateManifest)

--- Returns the full manifest row by ID.
exports('GetCrudeManifest', function(manifestId)
    return MySQL.single.await(
        'SELECT * FROM lm_transport_manifests WHERE id = ?', { manifestId }
    )
end)

--- Validates manifest belongs to truckerId and is still active+unexpired.
exports('ValidateCrudeManifest', function(manifestId, truckerId)
    local row = MySQL.single.await(
        'SELECT id, expires_at FROM lm_transport_manifests WHERE id = ? AND trucker_id = ? AND status = "active" LIMIT 1',
        { manifestId, truckerId }
    )
    if not row then return false end
    if row.expires_at < os.time() then
        MySQL.update.await('UPDATE lm_transport_manifests SET status = "expired" WHERE id = ?', { manifestId })
        return false
    end
    return true
end)

--- Marks manifest as delivered. Returns true if it was active.
exports('CompleteTransportDelivery', function(manifestId)
    local affected = MySQL.update.await(
        'UPDATE lm_transport_manifests SET status = "delivered" WHERE id = ? AND status = "active"',
        { manifestId }
    )
    return (affected or 0) > 0
end)

--- Marks manifest as expired immediately (called on job abandon).
exports('ExpireManifest', function(manifestId)
    MySQL.update.await(
        'UPDATE lm_transport_manifests SET status = "expired" WHERE id = ? AND status = "active"',
        { manifestId }
    )
end)

--- Returns wells with transport_price_per set and barrels available (Mode B job board).
exports('GetPostedOrders', function()
    local wells = MySQL.query.await(
        'SELECT id, barrels_stored, transport_price_per, coords FROM lm_wells WHERE barrels_stored > 0 AND transport_price_per IS NOT NULL AND status IN ("producing","idle")',
        {}
    ) or {}
    local result = {}
    for _, w in ipairs(wells) do
        local c = json.decode(w.coords or '{}') or {}
        result[#result + 1] = {
            wellId         = w.id,
            barrels        = w.barrels_stored,
            pricePerBarrel = w.transport_price_per,
            coords         = c,
        }
    end
    return result
end)

--- Returns Config.Refineries list with coords for AUST_trucker client GPS.
exports('GetRefineries', function()
    local result = {}
    for _, r in ipairs(Config.Refineries or {}) do
        if r.coords and r.coords[1] then
            result[#result + 1] = {
                id     = r.id,
                name   = r.name,
                type   = r.type,
                coords = r.coords[1],
            }
        end
    end
    return result
end)

----------------------------------------
-- SERVER CALLBACKS (called from AUST_oilfield client)
----------------------------------------

--- Validates pickup eligibility and returns pricing.
--- Called by client before starting progressBar.
lib.callback.register('AUST_oilfield:crudePipeline:validatePickup', function(src, wellId, requestedQty)
    local plr = exports.qbx_core:GetPlayer(src)
    if not plr then return { ok = false, reason = 'Jogador não encontrado' } end
    local citizenId = plr.PlayerData.citizenid

    local well = DB_GetWell(wellId)
    if not well or (well.status ~= 'producing' and well.status ~= 'idle') then
        return { ok = false, reason = 'Poço inativo' }
    end
    if well.barrels_stored < 1 then
        return { ok = false, reason = 'Sem barris disponíveis neste poço' }
    end

    -- Check ADR cert via AUST_trucker export
    local ok, hasAdr = pcall(function()
        return exports['AUST_trucker']:CheckPlayerAdr(citizenId, 'flammable_liquid')
    end)
    if not ok or not hasAdr then
        if Config.Debug then print('[crude_pipeline] ADR check failed:', hasAdr) end
        return { ok = false, reason = 'Certificado ADR flammable_liquid necessário' }
    end

    local maxQty   = math.min(well.barrels_stored, requestedQty or 20)
    local price    = well.transport_price_per or Config.CrudeOilPipeline.BasePrice
    local mode     = well.transport_price_per and 'posted' or 'open'

    return { ok = true, maxQty = maxQty, pricePerBarrel = price, mode = mode }
end)

--- Returns list of wells with barrels for client pickup zones.
lib.callback.register('AUST_oilfield:crudePipeline:getWellsForPickup', function(_src)
    local rows = MySQL.query.await(
        'SELECT id, barrels_stored, coords FROM lm_wells WHERE barrels_stored > 0 AND status IN ("producing","idle")',
        {}
    ) or {}
    local result = {}
    for _, w in ipairs(rows) do
        local c = json.decode(w.coords or '{}') or {}
        if c.x then
            result[#result + 1] = { id = w.id, barrels = w.barrels_stored, coords = c }
        end
    end
    return result
end)

--- Called after client progressBar completes loading.
--- Atomically consumes barrels, creates manifest, notifies AUST_trucker.
RegisterNetEvent('AUST_oilfield:crudePipeline:cargoLoaded', function(plate, wellId, qty, pricePerBarrel)
    local src = source
    local plr = exports.qbx_core:GetPlayer(src)
    if not plr then return end
    local citizenId = plr.PlayerData.citizenid

    -- Sanity: qty must be positive
    if not qty or qty < 1 then return end

    -- Atomically consume barrels
    local consumed = DB_ConsumeBarrels(wellId, qty)
    if not consumed then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Falha ao retirar barris — tente novamente' })
        return
    end

    -- Create manifest
    local mode       = pricePerBarrel == (DB_GetWell(wellId) or {}).transport_price_per and 'posted' or 'open'
    local manifestId = DB_CreateManifest(wellId, citizenId, qty, pricePerBarrel, mode)
    if not manifestId then
        DB_ReturnBarrels(wellId, qty)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Falha ao criar manifesto de transporte' })
        return
    end

    if Config.Debug then
        print(('[crude_pipeline] Manifest %d created: well=%d qty=%d price=%d'):format(manifestId, wellId, qty, pricePerBarrel))
    end

    -- Notify AUST_trucker server to register the job and set GPS
    local ok, err = pcall(function()
        exports['AUST_trucker']:StartCrudeJob(src, plate, manifestId, wellId, qty, pricePerBarrel)
    end)
    if not ok then
        if Config.Debug then print('[crude_pipeline] StartCrudeJob error:', err) end
        -- Cargo loaded and manifest created; GPS just won't be set automatically.
        -- Trucker can still deliver.
    end
end)

--- Called by well owner to set a custom transport price (Mode B).
RegisterNetEvent('AUST_oilfield:crudePipeline:setTransportPrice', function(wellId, pricePerBarrel)
    local src = source
    local plr = exports.qbx_core:GetPlayer(src)
    if not plr then return end
    local citizenId = plr.PlayerData.citizenid

    -- Validate ownership
    local well = DB_GetWell(wellId)
    if not well then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Poço não encontrado' })
        return
    end
    if well.owner ~= citizenId then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Você não é dono deste poço' })
        return
    end

    -- pricePerBarrel = nil clears the price (removes from job board)
    MySQL.update.await(
        'UPDATE lm_wells SET transport_price_per = ? WHERE id = ?',
        { pricePerBarrel, wellId }
    )

    local msg = pricePerBarrel
        and ('Preço de transporte definido: $%d/barril'):format(pricePerBarrel)
        or  'Preço de transporte removido'
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = msg })
end)

--- Thread: expire manifests that passed their expires_at
CreateThread(function()
    while true do
        Wait(300000) -- every 5 minutes
        MySQL.update.await(
            'UPDATE lm_transport_manifests SET status = "expired" WHERE status = "active" AND expires_at < ?',
            { os.time() }
        )
    end
end)
```

- [ ] **Step 2: Verify file was created**

Confirm file exists at `server/crude_pipeline.lua`. Restart resource — no Lua errors should appear.

- [ ] **Step 3: Commit**

```bash
git add server/crude_pipeline.lua
git commit -m "feat: add server/crude_pipeline.lua with exports and callbacks for crude oil transport"
```

---

## Task 4: Client Pickup Interaction (AUST_oilfield)

**Files:**
- Create: `client/crude_pipeline.lua`

This file creates ox_target sphere zones on all producing wells so truckers can initiate crude pickup. Also adds a "Definir Preço de Transporte" option on wells the player owns.

- [ ] **Step 1: Create client/crude_pipeline.lua**

```lua
-- client/crude_pipeline.lua
-- Crude Oil Pipeline — client-side well interaction (pickup + price setting)

local ActiveZones = {}   -- [wellId] = zoneId (ox_target sphere)
local IsLoading   = false

----------------------------------------
-- Helpers
----------------------------------------

local function GetCurrentPlate()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if not veh or veh == 0 then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
end

local function IsInTanker()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if not veh or veh == 0 then return false end
    local model = GetEntityModel(veh)
    for _, m in ipairs(Config.CrudeOilPipeline.TankerModels) do
        if model == GetHashKey(m) then return true end
    end
    return false
end

local function GetTankerCapacity()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if not veh or veh == 0 then return Config.CrudeOilPipeline.MaxBarrels.default end
    local model = GetEntityModel(veh)
    for modelName, cap in pairs(Config.CrudeOilPipeline.MaxBarrels) do
        if modelName ~= 'default' and model == GetHashKey(modelName) then
            return cap
        end
    end
    return Config.CrudeOilPipeline.MaxBarrels.default
end

----------------------------------------
-- Pickup interaction
----------------------------------------

local function StartPickup(wellId, availableBarrels)
    if IsLoading then
        lib.notify({ type = 'error', description = 'Já está carregando' })
        return
    end
    if not IsInTanker() then
        lib.notify({ type = 'error', description = 'Você precisa estar em um veículo tanker' })
        return
    end

    local plate = GetCurrentPlate()
    if not plate then
        lib.notify({ type = 'error', description = 'Nenhum veículo detectado' })
        return
    end

    local capacity = GetTankerCapacity()
    local maxQty   = math.min(availableBarrels, capacity)

    -- Let player choose quantity
    local input = lib.inputDialog('Carregar Crude Oil', {
        { type = 'number', label = ('Quantidade de barris (1–%d)'):format(maxQty), min = 1, max = maxQty, default = maxQty, required = true },
    })
    if not input or not input[1] then return end
    local qty = math.floor(input[1])

    -- Server validation
    local result = lib.callback.await('AUST_oilfield:crudePipeline:validatePickup', false, wellId, qty)
    if not result or not result.ok then
        lib.notify({ type = 'error', description = result and result.reason or 'Falha ao validar pickup' })
        return
    end

    -- Recalculate with validated qty
    qty = math.min(qty, result.maxQty)
    local pricePerBarrel = result.pricePerBarrel

    -- Progress bar — one tick per barrel
    IsLoading = true
    local totalMs = qty * Config.CrudeOilPipeline.LoadTimePerBarrel
    local success = lib.progressBar({
        duration = totalMs,
        label    = ('Carregando %d barris... ($%d/barril)'):format(qty, pricePerBarrel),
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = false, car = false, combat = true },
    })
    IsLoading = false

    if not success then
        lib.notify({ type = 'error', description = 'Carregamento cancelado' })
        return
    end

    -- Confirm server-side
    TriggerServerEvent('AUST_oilfield:crudePipeline:cargoLoaded', plate, wellId, qty, pricePerBarrel)
    lib.notify({ type = 'success', description = ('%d barris de crude oil carregados'):format(qty) })
end

----------------------------------------
-- Mode B: owner sets transport price
----------------------------------------

local function OpenPriceDialog(wellId)
    local input = lib.inputDialog('Preço de Transporte', {
        { type = 'number', label = 'Preço por barril ($) — deixe 0 para remover', min = 0, max = 10000, default = 0, required = true },
    })
    if not input then return end
    local price = math.floor(input[1])
    TriggerServerEvent('AUST_oilfield:crudePipeline:setTransportPrice', wellId, price > 0 and price or nil)
end

----------------------------------------
-- Zone management
----------------------------------------

local function ClearZones()
    for wellId, _ in pairs(ActiveZones) do
        exports.ox_target:removeZone('crude_pickup_' .. wellId)
    end
    ActiveZones = {}
end

local function RegisterWellZone(well)
    local coords = well.coords
    if not coords or not coords.x then return end

    local wellId = well.id
    local zoneName = 'crude_pickup_' .. wellId

    -- Remove old zone if exists
    exports.ox_target:removeZone(zoneName)

    local options = {
        {
            name    = 'crude_pickup_' .. wellId,
            icon    = 'fas fa-oil-can',
            label   = ('Carregar Crude Oil (%d barris)'):format(well.barrels),
            onSelect = function()
                StartPickup(wellId, well.barrels)
            end,
        },
        {
            name    = 'crude_setprice_' .. wellId,
            icon    = 'fas fa-tag',
            label   = 'Definir Preço de Transporte',
            onSelect = function()
                OpenPriceDialog(wellId)
            end,
            -- Only visible if player is well owner (checked client-side for UX, re-validated server-side)
        },
    }

    exports.ox_target:addSphereZone({
        name    = zoneName,
        coords  = vec3(coords.x, coords.y, coords.z or 0),
        radius  = Config.CrudeOilPipeline.PickupRadius,
        options = options,
        debug   = Config.Debug,
    })

    ActiveZones[wellId] = zoneName
end

----------------------------------------
-- Init: fetch wells and create zones
----------------------------------------

local function RefreshWellZones()
    local wells = lib.callback.await('AUST_oilfield:crudePipeline:getWellsForPickup', false)
    if not wells then return end

    ClearZones()
    for _, well in ipairs(wells) do
        RegisterWellZone(well)
    end

    if Config.Debug then
        print(('[crude_pipeline] %d well zones registered'):format(#wells))
    end
end

-- Wait for player data to be ready, then refresh
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end
    Wait(3000) -- let other resources init
    RefreshWellZones()
end)

-- Refresh zones periodically (wells may produce more barrels)
CreateThread(function()
    while true do
        Wait(120000) -- every 2 minutes
        RefreshWellZones()
    end
end)

-- Refresh when server broadcasts after a delivery (barrels change)
RegisterNetEvent('AUST_oilfield:client:refreshCrudeZones', RefreshWellZones)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ClearZones()
end)
```

- [ ] **Step 2: Verify file created and zones appear**

Restart AUST_oilfield. Connect as player. Check:
1. No Lua errors in console
2. `Config.Debug = true` → see `[crude_pipeline] N well zones registered` in console
3. Drive a tanker to a producing well → ox_target menu shows "Carregar Crude Oil"

- [ ] **Step 3: Test pickup flow (manual)**

1. Get ADR `flammable_liquid` cert. Via admin: run the AUST_governo console command to grant an ADR cert, or use `/setjob sala` + buy via NPC, or directly insert into DB: `INSERT INTO trucker_adr_certs (citizen_id, adr_type, expires_at) VALUES ('SEU_CID', 'flammable_liquid', UNIX_TIMESTAMP() + 86400);`
2. Drive tanker to a producing well with barrels
3. Interact → inputDialog appears → select qty → progressBar runs → "X barris carregados" notification

- [ ] **Step 4: Commit**

```bash
git add client/crude_pipeline.lua
git commit -m "feat: add client/crude_pipeline.lua with well ox_target zones and pickup progressBar"
```

---

## Task 5: AUST_trucker — Config.CrudeOil + fxmanifest

**Files:**
- Modify: `config/config.lua`
- Modify: `fxmanifest.lua`

- [ ] **Step 1: Add Config.CrudeOil to config/config.lua**

Append at the end of `config/config.lua`:

```lua
Config.CrudeOil = {
    -- Refinery locations for GPS and ox_target delivery zones.
    -- ⚠ REQUIRED: Fill in standard_1 coords BEFORE Task 8 end-to-end test.
    -- To find: go to Sandy Shores refinery NPC in-game, open F8 console, run:
    --   print(GetEntityCoords(PlayerPedId()))
    Refineries = {
        { id = 'standard_1',   name = 'Refinaria Sandy Shores',        coords = vec4(0, 0, 0, 0) },      -- ← FILL IN BEFORE TASK 8
        { id = 'premium_1',    name = 'Refinaria Premium',             coords = vec4(-1094.20, -2700.10, 14.00, 0.0) },
        { id = 'industrial_1', name = 'Terminal Industrial — Porto LS', coords = vec4(-267.00, -2780.00, 6.00, 90.0) },
    },
    UnloadTimePerBarrel = 2000, -- ms per barrel at refinery
    DeliveryRadius      = 6.0,  -- meters for ox_target at refinery
}
```

> **REQUIRED BEFORE TASK 8:** Fill in the `standard_1` coords. Connect to server, go to the Sandy Shores refinery NPC (already spawned by AUST_oilfield), open F8 console and run `print(GetEntityCoords(PlayerPedId()))`. Use those coords in the config above.

- [ ] **Step 2: Add new files to fxmanifest.lua**

In `fxmanifest.lua`, find the `server_scripts` block. Add `'server/crude_oil.lua'` just before `'server/exports.lua'`:

```lua
    'server/services/job_service.lua',
    'server/services/convoy_service.lua',
    'server/services/illegal_service.lua',
    'server/services/npc_driver_service.lua',
    'server/services/truck_simulation_service.lua',
    'server/crude_oil.lua',        -- ← ADD HERE
    'server/exports.lua',
    'server/callbacks.lua',
    'server/events.lua',
```

In the `client_scripts` block, add `'client/crude_oil.lua'` at the end:

```lua
    'client/industries.client.lua',
    'client/industries_npc.client.lua',
    'client/crude_oil.lua',        -- ← ADD HERE
```

- [ ] **Step 3: Restart resource, confirm no load errors**

Expected: resource starts cleanly, no "file not found" errors (the files don't exist yet but Lua doesn't error until execution, so it will error later — that's fine, they'll be created in Tasks 6 and 7).

Actually: fxmanifest will fail to load non-existent files. Create placeholder files first:

```bash
echo "-- placeholder" > "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker\server\crude_oil.lua"
echo "-- placeholder" > "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker\client\crude_oil.lua"
```

Then restart resource — should load cleanly.

- [ ] **Step 4: Commit**

```bash
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker"
git add config/config.lua fxmanifest.lua server/crude_oil.lua client/crude_oil.lua
git commit -m "feat: add Config.CrudeOil, fxmanifest entries, and placeholder crude files"
```

---

## Task 6: AUST_trucker — Server Crude Oil Logic

**Files:**
- Modify: `server/crude_oil.lua` (replace placeholder)

This file owns the `ActiveCrudeJobs` table, the `StartCrudeJob` and `CheckPlayerAdr` exports (called by AUST_oilfield), and the delivery net event (called by AUST_trucker client).

- [ ] **Step 1: Write server/crude_oil.lua**

```lua
-- server/crude_oil.lua
-- Crude Oil Pipeline — AUST_trucker server side
-- Exports: StartCrudeJob (called by AUST_oilfield), CheckPlayerAdr (called by AUST_oilfield)
-- Events: AUST_trucker:server:completeCrudeDelivery (called by AUST_trucker client)

-- In-memory: plate → job data
-- Not persisted to trucker_jobs (separate flow from regular jobs)
local ActiveCrudeJobs = {}

----------------------------------------
-- EXPORTS (called by AUST_oilfield server via pcall)
----------------------------------------

--- Called by AUST_oilfield after barrels are loaded and manifest is created.
--- Registers the cargo and sends GPS to client.
exports('StartCrudeJob', function(src, plate, manifestId, wellId, qty, pricePerBarrel)
    if not src or not plate then return false end
    local plr = exports.qbx_core:GetPlayer(src)
    if not plr then return false end

    plate = plate:gsub('%s+', ''):upper()
    local citizenId = plr.PlayerData.citizenid

    ActiveCrudeJobs[plate] = {
        src           = src,
        citizenId     = citizenId,
        manifestId    = manifestId,
        wellId        = wellId,
        qty           = qty,
        pricePerBarrel= pricePerBarrel,
        startedAt     = os.time(),
    }

    if Config.Debug then
        print(('[crude_oil] Job started: plate=%s manifestId=%d qty=%d'):format(plate, manifestId, qty))
    end

    -- Send refinery coords to client for GPS
    TriggerClientEvent('AUST_trucker:client:crudeJobStarted', src, Config.CrudeOil.Refineries)
    return true
end)

--- Checks if a player has a valid ADR cert of the given type.
--- Called by AUST_oilfield to verify before allowing pickup.
exports('CheckPlayerAdr', function(citizenId, adrType)
    return AdrService.HasCert(citizenId, adrType)
end)

----------------------------------------
-- NET EVENTS
----------------------------------------

--- Called by AUST_trucker client after progressBar at refinery completes.
RegisterNetEvent('AUST_trucker:server:completeCrudeDelivery', function(plate, refineryId)
    local src = source
    if not plate then return end
    plate = plate:gsub('%s+', ''):upper()

    local job = ActiveCrudeJobs[plate]
    if not job then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Nenhum job de crude ativo para este veículo' })
        return
    end

    -- Validate the request comes from the right player
    local plr = exports.qbx_core:GetPlayer(src)
    if not plr or plr.PlayerData.citizenid ~= job.citizenId then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Não autorizado' })
        return
    end

    -- Mark manifest as delivered in AUST_oilfield
    local ok, delivered = pcall(function()
        return exports['AUST_oilfield']:CompleteTransportDelivery(job.manifestId)
    end)
    if not ok or not delivered then
        if Config.Debug then print('[crude_oil] CompleteTransportDelivery failed:', delivered) end
        -- Continue with payment even if manifest update failed (manifest may have expired)
    end

    -- Calculate payment
    local totalPayment = job.qty * job.pricePerBarrel

    -- Pay player (uses qbx_core cash)
    local paid = plr.Functions.AddMoney('cash', totalPayment, 'crude_oil_delivery')
    if Config.Debug then
        print(('[crude_oil] Payment $%d to %s (manifest=%d)'):format(totalPayment, job.citizenId, job.manifestId))
    end

    -- Clear job
    ActiveCrudeJobs[plate] = nil

    -- Notify client to clear GPS and show summary
    TriggerClientEvent('AUST_trucker:client:crudeJobCompleted', src, {
        qty            = job.qty,
        pricePerBarrel = job.pricePerBarrel,
        totalPayment   = totalPayment,
    })

    -- Broadcast to AUST_oilfield clients to refresh well zones (barrels changed)
    TriggerClientEvent('AUST_oilfield:client:refreshCrudeZones', -1)

    lib.notify(src, {
        type        = 'success',
        title       = 'Entrega Concluída',
        description = ('$%d recebidos por %d barris de crude'):format(totalPayment, job.qty),
        duration    = 8000,
    })
end)

--- Called by client when job is abandoned (player exits vehicle or manually cancels).
RegisterNetEvent('AUST_trucker:server:abandonCrudeJob', function(plate)
    local src = source
    if not plate then return end
    plate = plate:gsub('%s+', ''):upper()

    local job = ActiveCrudeJobs[plate]
    if not job then return end

    local plr = exports.qbx_core:GetPlayer(src)
    if not plr or plr.PlayerData.citizenid ~= job.citizenId then return end

    -- Return barrels to well
    local ok, err = pcall(function()
        exports['AUST_oilfield']:ReturnBarrels(job.wellId, job.qty)
    end)
    if not ok and Config.Debug then
        print('[crude_oil] ReturnBarrels error:', err)
    end

    -- Expire manifest immediately (don't wait for the 5-min thread)
    local ok2, err2 = pcall(function()
        exports['AUST_oilfield']:ExpireManifest(job.manifestId)
    end)
    if not ok2 and Config.Debug then print('[crude_oil] ExpireManifest error:', err2) end

    ActiveCrudeJobs[plate] = nil

    TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'Job de crude oil cancelado — barris devolvidos ao poço' })
    if Config.Debug then
        print(('[crude_oil] Job abandoned: plate=%s, returned %d barrels to well %d'):format(plate, job.qty, job.wellId))
    end
end)

--- Expose for GetActiveJobByPlate export (defined in server/exports.lua)
function GetActiveCrudeJobByPlate(plate)
    if not plate then return nil end
    return ActiveCrudeJobs[plate:gsub('%s+', ''):upper()]
end
```

- [ ] **Step 2: Test exports load**

Restart AUST_trucker. In server console: `exports['AUST_trucker']:CheckPlayerAdr` should not throw an error (returns nil for unknown player, which is correct).

- [ ] **Step 3: Commit**

```bash
git add server/crude_oil.lua
git commit -m "feat: add server/crude_oil.lua with StartCrudeJob/CheckPlayerAdr exports and delivery handler"
```

---

## Task 7: AUST_trucker — GetActiveJobByPlate Export + Job Board

**Files:**
- Modify: `server/exports.lua` — add new export
- Modify: `server/callbacks.lua` — merge crude wells into `getInitialData`

- [ ] **Step 1: Add GetActiveJobByPlate to server/exports.lua**

Open `server/exports.lua`. At the end, add:

```lua
--- Returns active crude oil job for a given vehicle plate.
--- Used by AUST_sala (via pcall) to verify manifest during transport checks.
exports('GetActiveJobByPlate', function(plate)
    if not plate then return nil end
    local job = GetActiveCrudeJobByPlate(plate)
    if not job then return nil end
    return {
        cargoType      = 'crude_oil',
        manifestId     = job.manifestId,
        wellId         = job.wellId,
        barrelCount    = job.qty,
        pricePerBarrel = job.pricePerBarrel,
    }
end)
```

- [ ] **Step 2: Merge crude orders into getInitialData in server/callbacks.lua**

In `server/callbacks.lua`, find `lib.callback.register('AUST_trucker:getInitialData', ...)`. The callback builds and returns a table inline — there is no `local jobs =` variable. Refactor the `jobs` key to use a local variable so crude orders can be appended before the return. Change:

```lua
-- BEFORE (example — find the exact line with jobs = JobService.GetAvailable):
return {
    ...
    jobs = JobService.GetAvailable(citizenId),
    ...
}
```

to:

```lua
-- AFTER
local jobs = JobService.GetAvailable(citizenId)

-- Merge crude oil posted orders from AUST_oilfield
local ok, crudeOrders = pcall(function()
    return exports['AUST_oilfield']:GetPostedOrders()
end)
if ok and crudeOrders then
    for _, order in ipairs(crudeOrders) do
        jobs[#jobs + 1] = {
                    id             = 'crude_' .. order.wellId,
                    originName     = 'Poço de Petróleo #' .. order.wellId,
                    destName       = 'Refinaria Sandy Shores',
                    cargoItem      = 'crude_oil_barrel',
                    trailerModel   = 'tanker',
                    basePayment    = order.pricePerBarrel * order.barrels,
                    cargoQty       = order.barrels,
                    expiresAt      = nil,
                    adrRequired    = 'flammable_liquid',
                    adrLocked      = not AdrService.HasCert(citizenId, 'flammable_liquid'),
                    pricePerBarrel = order.pricePerBarrel,
                    wellCoords     = order.coords,
                    isCrudeOrder   = true,
                }
            end
        elseif Config.Debug then
            print('[crude_oil] GetPostedOrders failed:', crudeOrders)
        end
```

- [ ] **Step 3: Handle crude job "navigation" in server/events.lua**

When the NUI sends `acceptJob` with id `crude_<wellId>`, the existing handler will fail (no such job in trucker_jobs). Open `server/events.lua` (not callbacks.lua) and find the `AUST_trucker:acceptJob` RegisterNetEvent handler. Add a check at the very top of that handler:

```lua
-- Inside the acceptJob handler (find by searching for 'acceptJob'):
if tostring(jobId):sub(1, 6) == 'crude_' then
    -- Crude oil order: just set GPS to well coords (no formal accept)
    local wellId = tonumber(tostring(jobId):sub(7))
    local ok, orders = pcall(function() return exports['AUST_oilfield']:GetPostedOrders() end)
    if ok and orders then
        for _, o in ipairs(orders) do
            if o.wellId == wellId and o.coords and o.coords.x then
                TriggerClientEvent('AUST_trucker:client:setCrudeGPS', src, o.coords)
                break
            end
        end
    end
    cb(true)
    return
end
-- ... rest of existing acceptJob logic
```

- [ ] **Step 4: Test crude orders appear in job board**

1. In AUST_oilfield: as well owner, set transport price via ox_target on your well
2. Open AUST_trucker job board → crude oil order should appear with badge `crude_oil_barrel`
3. Accept → GPS waypoint is set to well

- [ ] **Step 5: Commit**

```bash
git add server/exports.lua server/callbacks.lua
git commit -m "feat: add GetActiveJobByPlate export and merge crude oil orders into job board"
```

---

## Task 8: AUST_trucker — Client Refinery Delivery

> **PRÉ-REQUISITO OBRIGATÓRIO:** Antes de começar esta tarefa, preencha as coords de `standard_1` em `Config.CrudeOil.Refineries`. Vá até o NPC da Refinaria Sandy Shores in-game, abra o console F8 e rode `print(GetEntityCoords(PlayerPedId()))`. Atualize o config e faça commit. Sem isso, o ox_target de entrega será criado no fundo do oceano.

- [ ] **Pré-req: Preencher coords standard_1 e commitar antes de prosseguir**

**Files:**
- Modify: `client/crude_oil.lua` (replace placeholder)

This file creates ox_target zones at refineries and handles the delivery progressBar + server communication.

- [ ] **Step 1: Write client/crude_oil.lua**

```lua
-- client/crude_oil.lua
-- Crude Oil Pipeline — AUST_trucker client side
-- Handles refinery ox_target, unloading progressBar, and GPS events.

local ActiveZones    = {}    -- refinery ox_target zone names
local IsUnloading    = false
local CrudeJobActive = false
local CrudeJobData   = nil   -- { qty, pricePerBarrel } set by server on job start

----------------------------------------
-- Helpers
----------------------------------------

local function GetCurrentPlate()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if not veh or veh == 0 then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
end

----------------------------------------
-- Refinery ox_target zones
----------------------------------------

local function RegisterRefineryZone(refinery)
    local c = refinery.coords
    if not c then return end

    local zoneName = 'crude_delivery_' .. refinery.id
    exports.ox_target:addSphereZone({
        name   = zoneName,
        coords = type(c) == 'vector4' and vec3(c.x, c.y, c.z) or vec3(c.x, c.y, c.z or 0),
        radius = Config.CrudeOil.DeliveryRadius,
        options = {
            {
                name     = 'crude_deliver_' .. refinery.id,
                icon     = 'fas fa-industry',
                label    = 'Entregar Crude Oil',
                onSelect = function()
                    StartDelivery(refinery.id)
                end,
                canInteract = function()
                    return CrudeJobActive and not IsUnloading
                end,
            },
        },
        debug = Config.Debug,
    })
    table.insert(ActiveZones, zoneName)
end

local function ClearZones()
    for _, z in ipairs(ActiveZones) do
        exports.ox_target:removeZone(z)
    end
    ActiveZones = {}
end

----------------------------------------
-- Delivery flow
----------------------------------------

function StartDelivery(refineryId)
    if IsUnloading then
        lib.notify({ type = 'error', description = 'Já está descarregando' })
        return
    end
    if not CrudeJobActive then
        lib.notify({ type = 'error', description = 'Nenhum cargo de crude oil ativo' })
        return
    end

    local plate = GetCurrentPlate()
    if not plate then
        lib.notify({ type = 'error', description = 'Nenhum veículo detectado' })
        return
    end

    -- Get qty from server to know how long progressBar should run
    -- We stored it in CrudeJobData on job start
    local qty = CrudeJobData and CrudeJobData.qty or 1

    IsUnloading = true
    local totalMs = qty * Config.CrudeOil.UnloadTimePerBarrel
    local success = lib.progressBar({
        duration     = totalMs,
        label        = ('Descarregando %d barris...'):format(qty),
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = true, car = false, combat = true },
    })
    IsUnloading = false

    if not success then return end

    TriggerServerEvent('AUST_trucker:server:completeCrudeDelivery', plate, refineryId)
end

----------------------------------------
-- Server event handlers
----------------------------------------

--- Fired by server/crude_oil.lua:StartCrudeJob after cargo loaded.
RegisterNetEvent('AUST_trucker:client:crudeJobStarted', function(refineries)
    CrudeJobActive = true

    -- Rebuild refinery zones if not done yet
    if #ActiveZones == 0 then
        for _, r in ipairs(refineries or Config.CrudeOil.Refineries) do
            RegisterRefineryZone(r)
        end
    end

    -- Set GPS to first refinery
    if refineries and refineries[1] then
        local c = refineries[1].coords
        SetNewWaypoint(c.x, c.y)
        lib.notify({ type = 'inform', description = 'Entregue o crude na refinaria — GPS definido', duration = 6000 })
    end
end)

--- Store job data for qty reference during unload
RegisterNetEvent('AUST_trucker:client:crudeJobData', function(data)
    CrudeJobData = data
end)

--- Fired by server after successful delivery.
RegisterNetEvent('AUST_trucker:client:crudeJobCompleted', function(summary)
    CrudeJobActive = false
    CrudeJobData   = nil
    -- Clear GPS waypoint
    RemoveWaypoint()
    lib.notify({
        type        = 'success',
        title       = 'Entrega de Crude Oil Concluída',
        description = ('$%d por %d barris'):format(summary.totalPayment, summary.qty),
        duration    = 10000,
    })
end)

--- Set GPS to well coords (from job board "accept" click)
RegisterNetEvent('AUST_trucker:client:setCrudeGPS', function(coords)
    if coords and coords.x then
        SetNewWaypoint(coords.x, coords.y)
        lib.notify({ type = 'inform', description = 'GPS definido para o poço de crude oil', duration = 5000 })
    end
end)

----------------------------------------
-- Init
----------------------------------------

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end
    Wait(2000)

    -- Fetch refinery coords from AUST_oilfield
    local ok, refineries = pcall(function()
        return lib.callback.await('AUST_trucker:getRefineries', false)
    end)

    local refineryList = (ok and refineries) or Config.CrudeOil.Refineries
    for _, r in ipairs(refineryList) do
        RegisterRefineryZone(r)
    end

    if Config.Debug then
        print(('[crude_oil client] %d refinery zones registered'):format(#ActiveZones))
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ClearZones()
end)
```

- [ ] **Step 2: Add getRefineries callback to server/callbacks.lua**

Append to `server/callbacks.lua`:

```lua
lib.callback.register('AUST_trucker:getRefineries', function(_src)
    local ok, result = pcall(function()
        return exports['AUST_oilfield']:GetRefineries()
    end)
    if ok and result then return result end
    return Config.CrudeOil.Refineries  -- fallback to config
end)
```

- [ ] **Step 3: Also pass qty to client when job starts**

In `server/crude_oil.lua`, after `TriggerClientEvent('AUST_trucker:client:crudeJobStarted', src, Config.CrudeOil.Refineries)`, add:

```lua
TriggerClientEvent('AUST_trucker:client:crudeJobData', src, { qty = qty, pricePerBarrel = pricePerBarrel })
```

- [ ] **Step 4: Full end-to-end test**

1. Start resource. Connect. Confirm no errors.
2. Get ADR flammable_liquid cert
3. Spawn a tanker (`tanker`, `tanker2`, or `flatbed`)
4. Drive to a producing well with barrels
5. Interact via ox_target → "Carregar Crude Oil" → inputDialog → select qty → progressBar
6. Notification: "X barris carregados" + GPS set to refinery
7. Drive to refinery
8. Interact via ox_target → "Entregar Crude Oil" → progressBar
9. Notification: "Entrega Concluída — $X"
10. Verify in DB:

```sql
SELECT * FROM lm_transport_manifests ORDER BY id DESC LIMIT 5;
-- Expected: one row with status='delivered'

SELECT barrels_stored FROM lm_wells WHERE id = <wellId>;
-- Expected: reduced by qty loaded
```

- [ ] **Step 5: Test abandon flow**

1. Load crude on tanker
2. Trigger `TriggerServerEvent('AUST_trucker:server:abandonCrudeJob', plate)` via client console
3. Verify: notification "Job cancelado — barris devolvidos"
4. Verify DB: `barrels_stored` back to original value

- [ ] **Step 6: Test Mode B (posted orders)**

1. As well owner: go to your well → ox_target → "Definir Preço de Transporte" → enter $200
2. Verify DB: `SELECT transport_price_per FROM lm_wells WHERE id = <id>;` → 200
3. As trucker: open job board → crude oil order appears with $200/barrel
4. Click "Accept" → GPS set to well
5. Drive to well → load → deliver → confirm $200/barrel payment

- [ ] **Step 7: Commit**

```bash
git add client/crude_oil.lua server/callbacks.lua server/crude_oil.lua
git commit -m "feat: add client/crude_oil.lua refinery delivery, getRefineries callback, crudeJobData event"
```

---

## Task 9: Final Integration Verification

- [ ] **Step 1: SQL sanity checks**

```sql
-- Manifests created properly
SELECT status, COUNT(*) FROM lm_transport_manifests GROUP BY status;

-- Wells transport price
SELECT id, barrels_stored, transport_price_per FROM lm_wells WHERE transport_price_per IS NOT NULL;

-- Expiry thread working (after 5 min with expired manifests)
SELECT * FROM lm_transport_manifests WHERE status = 'expired';
```

- [ ] **Step 2: Verify SALA can check manifest**

In AUST_sala code (pcall pattern):
```lua
local ok, job = pcall(function()
    return exports['AUST_trucker']:GetActiveJobByPlate(plate)
end)
if ok and job and job.cargoType == 'crude_oil' then
    -- job.manifestId, job.wellId, job.barrelCount available
end
```

Test by loading crude, then calling this from a test event.

- [ ] **Step 3: Version bump**

In AUST_oilfield `fxmanifest.lua`: bump version to `2.6.0`.
In AUST_trucker `fxmanifest.lua`: bump version to next minor.

- [ ] **Step 4: Final commit + push**

```bash
# AUST_oilfield
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_oilfield"
git add -A
git commit -m "feat: Phase 1 crude oil pipeline — v2.6.0"
git push

# AUST_trucker
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker"
git add -A
git commit -m "feat: Phase 1 crude oil pipeline integration with AUST_oilfield"
git push
```

---

## Checklist de Entrega

- [ ] `lm_transport_manifests` criada e migração limpa
- [ ] `transport_price_per` adicionada a `lm_wells`
- [ ] `server/crude_pipeline.lua` com todos os exports e callbacks
- [ ] `client/crude_pipeline.lua` com zones em poços e progressBar
- [ ] `Config.CrudeOilPipeline` em AUST_oilfield
- [ ] `Config.CrudeOil` em AUST_trucker
- [ ] `server/crude_oil.lua` com StartCrudeJob, CheckPlayerAdr, entrega, abandono
- [ ] `GetActiveJobByPlate` export funcionando
- [ ] Crude orders aparecem no job board do AUST_trucker
- [ ] Fluxo completo ponta-a-ponta testado (poço → tanker → refinaria → pagamento)
- [ ] Abandono devolve barris ao poço
- [ ] Mode B: dono define preço, aparece no job board
- [ ] Versões incrementadas e commits feitos
