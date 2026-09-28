# Forklift System — Design Spec (v12.0.0)

**Data:** 2026-03-20
**Status:** Aprovado
**Fase Blueprint:** 5 — Polimento

---

## Visão Geral

Sistema de empilhadeira (forklift) para o `AUST_trucker` com dois modos integrados na mesma infraestrutura:

- **Modo 1 — Trade Point Mini-Job:** Jobs standalone em 2 depósitos fixos. Player aluga forklift, carrega pallets físicos em caminhão NPC, recebe pagamento próprio.
- **Modo 2 — Integração com Delivery Jobs:** Jobs de entrega ganham `cargo_qty` (1–6 pacotes). Sem forklift: progressBars sequenciais (lento). Com forklift: mecânica física de pallets (rápido → maior time bonus).

Ambos os modos compartilham veículo (`forklift`), props de pallet, sistema de aluguel/devolução e `Config.Forklift`.

---

## Sistema de Aluguel e Devolução

- **Custo de aluguel:** $500 debitado do banco ao alugar
- **Reembolso de devolução:** 50% ($250) ao retornar o forklift ao ponto de origem (raio 15m do spawn)
- **Sem reembolso:** forklift destruído ou abandonado
- **Limite:** 1 aluguel ativo por jogador
- **Tracking:** em memória — não persiste no DB

### Estrutura do rental em memória

```lua
VP_Trucker.ForkliftRentals[citizenId] = {
    locationId  = 'walker_logistics',  -- trade point id ou industry id
    mode        = 'tradepoint',        -- 'tradepoint' | 'industry'
    cost        = 500,
    spawnCoords = vector4(...),
    rentedAt    = os.time(),
    -- Controle de pallets (populado ao iniciar missão):
    loaded      = 0,                   -- pallets já carregados
    expected    = 5,                   -- total esperado (maxPallets ou cargo_qty)
    trailerEntity = nil,               -- handle do trailer (Modo 2 apenas)
}
```

---

## Modo 1 — Trade Point Mini-Job

### 2 Localizações Fixas

```lua
Config.Forklift.TradePoints = {
    {
        id              = 'walker_logistics',
        name            = 'Walker Logistics',
        coords          = vector3(153.81, -3214.60, 4.93),
        npcCoords       = vector4(156.0, -3211.0, 4.93, 180.0),
        forkliftSpawn   = vector4(148.0, -3208.0, 4.93, 90.0),
        palletSpawns    = {
            vector4(158.0, -3220.0, 4.93, 0.0),
            vector4(161.0, -3220.0, 4.93, 0.0),
            vector4(164.0, -3220.0, 4.93, 0.0),
            vector4(158.0, -3224.0, 4.93, 0.0),
            vector4(161.0, -3224.0, 4.93, 0.0),
        },
        deliveryVehicle = 'benson',
        deliveryStart   = vector4(130.0, -3190.0, 4.93, 180.0),
        deliveryEnd     = vector4(153.0, -3215.0, 4.93, 180.0),
        maxPallets      = 5,
        basePay         = 500,
        timeLimit       = 180,
    },
    {
        id              = 'pacific_shipyard',
        name            = 'Pacific Shipyard',
        coords          = vector3(739.3, -2869.6, 0.9),
        npcCoords       = vector4(742.0, -2866.0, 0.9, 90.0),
        forkliftSpawn   = vector4(735.0, -2872.0, 0.9, 270.0),
        palletSpawns    = {
            vector4(748.0, -2875.0, 0.9, 0.0),
            vector4(751.0, -2875.0, 0.9, 0.0),
            vector4(754.0, -2875.0, 0.9, 0.0),
            vector4(748.0, -2879.0, 0.9, 0.0),
            vector4(751.0, -2879.0, 0.9, 0.0),
        },
        deliveryVehicle = 'mule2',
        deliveryStart   = vector4(720.0, -2850.0, 0.9, 90.0),
        deliveryEnd     = vector4(740.0, -2870.0, 0.9, 90.0),
        maxPallets      = 5,
        basePay         = 550,
        timeLimit       = 180,
    },
}
```

### Fluxo do Jogador (Trade Point)

1. Player chega ao trade point → ox_target no NPC → "Aceitar Ordem"
2. Verifica se não há job de delivery ativo e se trade point não está ocupado
3. `rentForklift` callback → debita $500 → `VP_Trucker.TradePointActive[locationId] = citizenId`
4. Forklift spawna no `forkliftSpawn`; pallets spawnam nas `palletSpawns` (networkados)
5. `rental.expected = maxPallets`, `rental.loaded = 0`
6. Caminhão NPC spawna em `deliveryStart`, dirige até `deliveryEnd` via `TaskVehicleDriveToCoordLongrange`
7. Caminhão estaciona, boot abre (`SetVehicleDoorOpen`)
8. Thread 500ms monitora cada pallet:
   - `GetVehicleDoorAngleRatio(npcTruck, 5) >= 0.75` **E** `#(palletCoords - bootCoords) <= 3.0`
   - Ao detectar: `TriggerServerEvent('AUST_trucker:palletLoaded', netId, locationId)`
9. Server valida ownership via StateBag, deleta entidade, incrementa `rental.loaded`
10. Quando `rental.loaded == rental.expected` → client recebe evento → `completeTradePoint` callback
11. Pagamento: `payment = basePay × maxPallets × speed_mult`
    - `speed_mult`: ≤90s → 1.3×, ≤150s → 1.0×, >150s → 0.7×
    - **Nota:** `healthRatio` removido do Modo 1 (YAGNI — mecânica de dano de pallet não implementada)
12. Player retorna forklift ao `forkliftSpawn` (raio 15m) → `returnForklift` callback → $250
13. Cleanup: `VP_Trucker.TradePointActive[locationId] = nil`, caminhão NPC parte, pallets residuais deletados

### Proteções
- `VP_Trucker.TradePointActive[locationId]` — um player por trade point por vez
- Time limit: thread server-side; após `timeLimit` segundos → cancel sem refund
- StateBag ownership check em cada `palletLoaded`
- `playerDropped`: `ForkliftService.OnPlayerDropped(citizenId)` limpa rental, TradePointActive, deleta entidades

---

## Modo 2 — Integração com Delivery Jobs

### cargo_qty nos Jobs

Coluna adicionada a `trucker_jobs`:
```sql
cargo_qty TINYINT UNSIGNED NOT NULL DEFAULT 1
```

`GenerateOne()` sorteia `cargo_qty` ponderado (1-6):
```lua
local QTY_WEIGHTS = { {qty=1, w=30}, {qty=2, w=25}, {qty=3, w=20},
                      {qty=4, w=12}, {qty=5, w=8},  {qty=6, w=5} }
-- Weighted random: soma pesos, sorteia 1..totalWeight, encontra faixa
```

**Fórmula de pagamento com cargo_qty** (modifica linha existente em `GenerateOne()`):
```lua
-- Antes:
local payment = math.floor(product.basePrice + dist * Config.JobGeneration.distanceMultiplier * dest.multiplier)
-- Depois:
local payment = math.floor((product.basePrice * cargoQty) + dist * Config.JobGeneration.distanceMultiplier * dest.multiplier)
```
O componente de distância **não** escala com qty (distância é a mesma independentemente de quantos pacotes). Apenas o `basePrice` escala.

**`cargo_qty` em convoy jobs** (`GenerateConvoyBatch`): convoy jobs recebem `cargo_qty = 1` fixo. Forklift não é escopo do sistema de convoy. A coluna DB tem `DEFAULT 1`, portanto nenhuma mudança no `GenerateConvoyBatch`.

### Modificações em `GenerateOne()` — return table

```lua
-- Retorna (adicionar cargo_qty ao table existente):
return {
    id            = jobId,
    origin_id     = origin.id,
    dest_id       = dest.id,
    cargo_item    = product.name,
    trailer_model = product.trailer,
    base_payment  = payment,
    distance      = dist,
    expires_at    = expiresAt,
    cargo_qty     = cargoQty,   -- NOVO
}
```

### Modificações em `DB_InsertJob()` — SQL

```lua
-- SQL INSERT modificado (adicionar cargo_qty):
MySQL.query.await([[
    INSERT INTO trucker_jobs
        (id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at, cargo_qty)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
]], { job.id, job.origin_id, job.dest_id, job.cargo_item, job.trailer_model,
      job.base_payment, job.distance, job.expires_at, job.cargo_qty or 1 })
```

`DB_GetAvailableJobs` usa `SELECT *` → `cargo_qty` retornado automaticamente após `ALTER TABLE`.

### Modificações em `GetAvailable()` e `GetActiveByPlayer()` — result tables

```lua
-- GetAvailable() — adicionar ao table de cada job:
cargoQty = row.cargo_qty or 1,   -- NOVO

-- GetActiveByPlayer() — adicionar ao table de retorno:
cargoQty = row.cargo_qty or 1,   -- NOVO
```

### Forklift nas Primary Industries

Cada Primary Industry tem spawn de forklift no config:
```lua
Config.Forklift.IndustrySpawns = {
    -- keyed por Config.PrimaryIndustries[i].id
    ['porto_a1']      = vector4(361.0, -2545.0, 5.74, 270.0),
    ['refinaria']     = vector4(...),
    -- ... um por industry com loading dock
}
```

ox_target em `prop_consite_bagb` (prop de obra estático, parece forklift estacionado) em cada spawn. Opção "Alugar Forklift ($500)" — só visível se `canInteract = player tem job ativo cuja origin_id == este industry id`.

### Fluxo de Loading com Forklift (Modo 2)

**`StartLoading()` em `client/client.lua` — lógica de branch:**

```lua
local function StartLoading()
    local qty = currentJob.cargoQty or 1

    -- Verificar se player tem forklift ativo nesta origin
    local hasForklift = (VP_Trucker_ForkliftActive ~= nil)
        -- VP_Trucker_ForkliftActive é local client-side, setado pelo rentForklift callback

    if hasForklift and qty > 1 then
        -- Modo forklift: spawn pallets, mecânica física
        TriggerEvent('AUST_trucker:forklift:startIndustryLoad', qty)
        -- Bloqueio: o evento forklift.client.lua completa o loading e
        -- dispara 'AUST_trucker:client:loadingComplete' quando done
        return  -- não executa progressBar
    end

    -- Modo manual: qty progressBars sequenciais
    for i = 1, qty do
        lib.showTextUI(('[%d/%d] Carregando %s...'):format(i, qty, currentJob.cargo))
        local success = lib.progressBar({
            duration   = currentJob.loadTime,
            label      = ('Carregando pacote %d/%d'):format(i, qty),
            canCancel  = false,
            disable    = { move = true, car = true, combat = true },
        })
        lib.hideTextUI()
        if not success then return end  -- cancelado (ex: player saiu da zona)
    end

    -- Loading completo — continuar fluxo normal
    TriggerEvent('AUST_trucker:client:loadingComplete')
end
```

O evento `'AUST_trucker:client:loadingComplete'` é o ponto de continuação (stage → 'delivering', blip de entrega, etc.). Este evento já existe implicitamente no código atual como o ponto após o `lib.progressBar` — deve ser refatorado para um named event para suportar o branch.

### Detecção do Trailer no Modo 2

O player está **dentro do forklift** durante o carregamento, então `GetVehiclePedIsIn` retorna o forklift, não o truck/trailer.

**Solução:** Ao iniciar o modo forklift (`rentForklift` com `mode = 'industry'`), o handle do trailer é capturado **antes** de o player entrar no forklift:

```lua
-- Em forklift.client.lua, ao iniciar industry load:
AddEventHandler('AUST_trucker:forklift:startIndustryLoad', function(qty)
    -- Capturar trailer AGORA (player ainda está no truck ou a pé)
    local playerVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    local trailer = GetVehicleTrailerVehicle(playerVeh)
    if not trailer or trailer == 0 then
        -- Fallback: scan entidades próximas pelo modelo de trailer do job
        trailer = FindNearbyTrailer()  -- helper que itera GetClosestVehicle
    end

    -- Armazenar handle para uso na thread de detecção
    -- (passado via upvalue na closure da thread)
    StartPalletLoadThread(qty, trailer)
end)
```

`rental.trailerEntity` é armazenado no ForkliftRentals server-side (opcional) ou mantido como local client-side (suficiente, pois o client faz a detecção).

---

## Mecânica de Pallet (Compartilhada)

### Spawn de Pallet

Server-side via evento `RegisterNetEvent('AUST_trucker:spawnPallet', ...)`:
```lua
local obj = CreateObjectNoOffset(GetHashKey(model), x, y, z, true, false, false)
SetEntityAsMissionEntity(obj, true, true)
SetEntityDynamic(obj, true)
Entity(obj).state:set('forklift_owner', citizenId, true)
Entity(obj).state:set('forklift_location', locationId, true)
-- Retornar netId via callback para o client monitorar
```

### Detecção de Carregamento (thread 500ms no client do owner)

```lua
-- Para cada pallet pendente (netId na lista):
local palletObj   = NetToObj(netId)
if not DoesEntityExist(palletObj) then return end  -- já deletado
local palletCoords = GetEntityCoords(palletObj)

-- Boot do caminhão NPC (Modo 1) ou trailer (Modo 2):
local bootCoords  = GetOffsetFromEntityInWorldCoords(targetVehicle, 0.0, -targetLen, 0.0)
-- targetLen: ~4.0 para benson, ~3.0 para mule2, ~6.0 para trailer

local bootAngle   = GetVehicleDoorAngleRatio(targetVehicle, 5)

if bootAngle >= 0.75 and #(palletCoords - bootCoords) <= 3.0 then
    TriggerServerEvent('AUST_trucker:palletLoaded', netId, locationId)
    -- Remover netId da lista local para evitar double-trigger
end
```

### Server: `RegisterNetEvent('AUST_trucker:palletLoaded', ...)`

```lua
RegisterNetEvent('AUST_trucker:palletLoaded', function(netId, locationId)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local citizenId = Player.PlayerData.citizenid

    -- Validar ownership via StateBag
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local obj = NetworkGetEntityFromNetworkId(netId)
    if Entity(obj).state.forklift_owner ~= citizenId then return end

    -- Deletar entidade
    DeleteEntity(obj)

    -- Incrementar contador
    local rental = VP_Trucker.ForkliftRentals[citizenId]
    if not rental then return end
    rental.loaded = rental.loaded + 1

    -- Notificar client se completo
    if rental.loaded >= rental.expected then
        TriggerClientEvent('AUST_trucker:client:allPalletsLoaded', src, locationId)
    end
end)
```

---

## ForkliftService — API

```lua
ForkliftService = {}

-- Registra aluguel: debita $500, seta ForkliftRentals[citizenId]
-- Retorna: { success, reason? }
ForkliftService.Rent(citizenId, locationId, mode, expected)

-- Devolução no ponto de origem
-- Retorna: { success, refund }  (refund=250 se válido, 0 se não)
ForkliftService.Return(citizenId)

-- Retorna rental ativo ou nil
ForkliftService.GetRental(citizenId)

-- Verifica se locationId não está ocupado
ForkliftService.IsAvailable(locationId)

-- Calcula e paga trade point concluído
-- elapsedSeconds = tempo decorrido desde aceitar a ordem
ForkliftService.CompleteTradePoint(citizenId, locationId, elapsedSeconds)

-- Cleanup no playerDropped: limpa rental, TradePointActive, não deleta entidades
-- (entidades são deletadas pelo GC do FiveM quando owner desconecta)
ForkliftService.OnPlayerDropped(citizenId)
```

### `OnPlayerDropped` — integração em `server/events.lua`

```lua
-- Adicionar no handler playerDropped existente (events.lua ~linha 390):
AddEventHandler('playerDropped', function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if Player then
        local citizenId = Player.PlayerData.citizenid
        ForkliftService.OnPlayerDropped(citizenId)  -- NOVO
        TruckSimulationService.OnPlayerDropped(src)
        PartyService.OnPlayerDisconnect(citizenId)
    end
end)
```

---

## Arquitetura de Código

### Novos Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `server/services/forklift_service.lua` | `ForkliftService` global: `Rent`, `Return`, `GetRental`, `IsAvailable`, `CompleteTradePoint`, `OnPlayerDropped` |
| `client/forklift.client.lua` | ox_target NPCs/props, spawn forklift/pallets, pallet detection thread, return zone, NUI callbacks |

### Arquivos Modificados

| Arquivo | Mudança |
|---|---|
| `config/config.lua` | Bloco `Config.Forklift` completo |
| `import.sql` | Coluna `cargo_qty TINYINT UNSIGNED NOT NULL DEFAULT 1` em `trucker_jobs` |
| `sql/update_forklift_v12.sql` | `ALTER TABLE trucker_jobs ADD COLUMN IF NOT EXISTS cargo_qty...` |
| `server/database.lua` | `DB_InsertJob` SQL inclui `cargo_qty`; `DB_GetAvailableJobs` SELECT * já retorna automaticamente |
| `server/services/job_service.lua` | `GenerateOne()`: sorteia `cargo_qty`, inclui no return e no payment; `GetAvailable()` e `GetActiveByPlayer()` expõem `cargoQty` |
| `server/main.lua` | `VP_Trucker.ForkliftRentals = {}`; `VP_Trucker.TradePointActive = {}` |
| `server/callbacks.lua` | `rentForklift`, `returnForklift`, `completeTradePoint` callbacks |
| `server/events.lua` | `palletLoaded` net event; `playerDropped` chama `ForkliftService.OnPlayerDropped` |
| `client/client.lua` | `StartLoading()` branch: forklift vs. progressBar loop; evento `'AUST_trucker:client:loadingComplete'` como ponto nomeado |
| `fxmanifest.lua` | `forklift_service.lua` após `adr_service.lua`; `forklift.client.lua` após `adr.client.lua` |
| `html/src/types/index.ts` | `Job` interface: campo `cargoQty?: number` |
| `html/src/components/jobs/JobCard.tsx` | Mostrar `cargoQty` pacotes + badge "Forklift rec." para qty ≥ 3 |
| `html/src/components/jobs/JobList.tsx` | Modal de detalhes: mostrar `cargoQty` e badge |

---

## Callbacks Server

### `AUST_trucker:rentForklift`
```lua
lib.callback.register('AUST_trucker:rentForklift', function(source, data)
    -- data = { locationId, mode, expected }
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid

    if ForkliftService.GetRental(citizenId) then
        return { success = false, reason = 'Você já tem um forklift alugado' }
    end
    if not ForkliftService.IsAvailable(data.locationId) then
        return { success = false, reason = 'Forklift em uso neste local' }
    end
    local removed = Player.Functions.RemoveMoney('bank', 500, 'forklift-rental')
    if not removed then
        return { success = false, reason = 'Saldo bancário insuficiente' }
    end
    ForkliftService.Rent(citizenId, data.locationId, data.mode, data.expected)
    return { success = true }
end)
```

### `AUST_trucker:returnForklift`
```lua
lib.callback.register('AUST_trucker:returnForklift', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid
    local result = ForkliftService.Return(citizenId)
    if result.success and result.refund > 0 then
        Player.Functions.AddMoney('bank', result.refund, 'forklift-return')
    end
    return result
end)
```

### `AUST_trucker:completeTradePoint`
```lua
lib.callback.register('AUST_trucker:completeTradePoint', function(source, data)
    -- data = { locationId, elapsedSeconds }
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local citizenId = Player.PlayerData.citizenid
    local rental = ForkliftService.GetRental(citizenId)
    if not rental or rental.locationId ~= data.locationId then
        return { success = false, reason = 'Missão inválida' }
    end
    if rental.loaded < rental.expected then
        return { success = false, reason = 'Nem todos os pallets foram carregados' }
    end
    local payment = ForkliftService.CompleteTradePoint(citizenId, data.locationId, data.elapsedSeconds)
    Player.Functions.AddMoney('bank', payment, 'forklift-tradepoint')
    ForkliftService.Return(citizenId)  -- cleanup sem refund (missão concluída)
    return { success = true, payment = payment }
end)
```

---

## DB — Alterações

### `import.sql` — coluna em `trucker_jobs`

Adicionar `cargo_qty TINYINT UNSIGNED NOT NULL DEFAULT 1` na definição do `CREATE TABLE IF NOT EXISTS trucker_jobs`.

### `sql/update_forklift_v12.sql`

```sql
-- Migração v11 → v12
ALTER TABLE `trucker_jobs`
    ADD COLUMN IF NOT EXISTS `cargo_qty` TINYINT UNSIGNED NOT NULL DEFAULT 1;
```

---

## fxmanifest — Ordem

```lua
-- server_scripts (após adr_service):
'server/services/forklift_service.lua',

-- client_scripts (após adr.client.lua):
'client/forklift.client.lua',
```

---

## Critérios de Sucesso

1. Trade point: player completa mini-job com forklift do início ao fim e recebe pagamento correto com speed_mult
2. Trade point: devolução do forklift no spawn retorna $250; abandono não retorna
3. Trade point: dois players não conseguem reservar o mesmo trade point simultaneamente
4. Trade point: auto-cancel após `timeLimit` segundos sem refund de aluguel
5. Trade point: playerDropped limpa rental e TradePointActive sem crash
6. Delivery job: `cargo_qty` gerado corretamente (1–6) com pesos corretos; `base_payment` escala com qty
7. Delivery job: convoy jobs recebem `cargo_qty = 1` (DEFAULT, sem alteração em GenerateConvoyBatch)
8. Delivery job: sem forklift = `cargo_qty` progressBars sequenciais; com forklift = mecânica de pallets
9. Delivery job: trailer handle capturado antes de player entrar no forklift; detecção funciona
10. Pallet: server valida ownership via StateBag antes de aceitar `palletLoaded`
11. NUI: `cargoQty` visível no JobCard e no Modal de detalhes; badge para qty ≥ 3

---

## Não-Escopo (YAGNI)

- Sem health_ratio / dano de pallet afetando pagamento (nenhum dos modos)
- Sem forklift para unloading na entrega — só no loading da origin
- Sem persistência de rentals no DB
- Sem multiplayer cooperativo no forklift (um player por missão/location)
- Sem animação custom além do comportamento nativo do veículo forklift
- Convoy jobs: `cargo_qty = 1` fixo (sem forklift integration)
