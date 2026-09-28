# Fase 3B — Illegal Deliveries Design

**Data:** 2026-03-19
**Versão alvo:** 9.1.0
**Contexto:** AUST_trucker FiveM resource — QBX + ox_lib + oxmysql, lua54='yes'

---

## Objetivo

Adicionar um segundo tipo de job paralelo ao sistema existente: entregas de carga contrabandeada com pagamento maior, alertas para LSPD e SALA (órgão ambiental), e mecânica de apreensão por jogadores cops/agentes.

---

## Abordagem: Híbrido Leve (Opção C)

Uma coluna `illegal_type VARCHAR(20) NULL` em `trucker_jobs` (NULL = job legal). Um serviço dedicado `IllegalService` encapsula toda a lógica nova. O `JobService.Complete` recebe um hook cirúrgico. Nenhuma tabela nova necessária.

---

## Arquivos Criados / Modificados

| Arquivo | Ação |
|---|---|
| `sql/update_illegal_v9_1.sql` | CRIAR — migração v9→v9.1 |
| `import.sql` | MODIFICAR — + `illegal_type` em trucker_jobs |
| `config/config.lua` | MODIFICAR — + `Config.IllegalJobs` |
| `server/database.lua` | MODIFICAR — + `DB_GetActiveJobByPlayer` retorna `illegal_type`; + `DB_InsertIllegalJob` |
| `server/main.lua` | MODIFICAR — + `VP_Trucker.IllegalTargets` |
| `server/services/illegal_service.lua` | CRIAR — `IllegalService` global |
| `server/services/job_service.lua` | MODIFICAR — hook em `Complete` para jobs ilegais |
| `server/callbacks.lua` | MODIFICAR — + `getIllegalJobs` + `acceptIllegalJob` |
| `server/events.lua` | MODIFICAR — + `seizeIllegalCargo` event handler |
| `client/illegal.client.lua` | CRIAR — contatos, ox_target, apreensão client-side |
| `fxmanifest.lua` | MODIFICAR — v9.1.0, + illegal_service + illegal.client.lua |
| `CHANGELOG.md` | MODIFICAR — entrada v9.1.0 |

---

## Section 1 — Schema

### `trucker_jobs` — nova coluna

```sql
ALTER TABLE trucker_jobs
    ADD COLUMN IF NOT EXISTS illegal_type VARCHAR(20) NULL DEFAULT NULL;
```

`illegal_type` é NULL para todos os jobs legais existentes. Valores válidos: `'contraband'`, `'animals'`, `'minerals'`, `'weapons'`, `'drugs'`.

### Arquivo de migração: `sql/update_illegal_v9_1.sql`

```sql
-- AUST_trucker — migração v9→v9.1 (Fase 3B — Illegal Deliveries)
ALTER TABLE trucker_jobs
    ADD COLUMN IF NOT EXISTS illegal_type VARCHAR(20) NULL DEFAULT NULL;

-- Adicionar 'illegal_seizure' ao ENUM de infraction_type
ALTER TABLE trucker_infractions
    MODIFY infraction_type ENUM('overload','no_manifest','expired_manifest','dangerous_cargo','illegal_seizure') NOT NULL;
```

### `import.sql` — atualizar ENUM de `trucker_infractions`

Na definição de `trucker_infractions`, alterar:
```sql
-- DE:
infraction_type ENUM('overload','no_manifest','expired_manifest','dangerous_cargo') NOT NULL,
-- PARA:
infraction_type ENUM('overload','no_manifest','expired_manifest','dangerous_cargo','illegal_seizure') NOT NULL,
```

### `import.sql`

No `CREATE TABLE trucker_jobs`, adicionar após `convoy_id`:
```sql
    illegal_type        VARCHAR(20)     NULL DEFAULT NULL,
```

---

## Section 2 — Config

### `Config.IllegalJobs`

```lua
Config.IllegalJobs = {
    -- Job names dos agentes que recebem alertas
    policeJob = 'police',
    salaJob   = 'sala',

    -- Multiplicadores de pagamento por tipo.
    -- Fórmula: base_payment = floor(dist_km × Config.JobGeneration.distanceMultiplier × paymentMultipliers[type])
    -- 'dist_km' = distância em km entre contact.coords e delivery.coords (CalcDistance já retorna km)
    paymentMultipliers = {
        contraband = 2.0,
        animals    = 2.5,
        minerals   = 2.3,
        weapons    = 3.0,
        drugs      = 2.8,
    },

    -- Multas de apreensão por tipo (deduzidas do cash do motorista)
    seizureFines = {
        contraband = 5000,
        animals    = 12000,
        minerals   = 8000,
        weapons    = 20000,
        drugs      = 15000,
    },

    -- Textos de alerta por tipo (para notificação de texto)
    alertLabels = {
        contraband = 'contrabando',
        animals    = 'tráfico de animais silvestres',
        minerals   = 'extração/desvio mineral ou petróleo',
        weapons    = 'armas e munições',
        drugs      = 'entorpecentes',
    },

    -- Tipos que acionam SALA além da LSPD
    salaTypes = { 'animals', 'minerals' },

    -- Tipos com alerta de alta prioridade para LSPD
    highPriorityTypes = { 'weapons', 'drugs' },

    -- Pontos de contato (onde jogador vai pessoalmente para pegar missão)
    contacts = {
        {
            id     = 'porto_sul',
            label  = 'Contato do Porto',
            area   = 'Porto de LS',
            coords = vector3(1167.0, -3043.0, 5.9),
            radius = 3.0,
            cargo  = { 'contraband', 'minerals' },
        },
        {
            id     = 'paleto_floresta',
            label  = 'Contato Rural',
            area   = 'Zona Rural — Paleto',
            coords = vector3(-357.0, 6145.0, 31.5),
            radius = 3.0,
            cargo  = { 'animals', 'minerals' },
        },
        {
            id     = 'strawberry_galpao',
            label  = 'Contato do Galpão',
            area   = 'Strawberry — LS',
            coords = vector3(-1183.0, -1573.0, 4.0),
            radius = 3.0,
            cargo  = { 'drugs', 'weapons' },
        },
        {
            id     = 'sandy_deserto',
            label  = 'Contato do Deserto',
            area   = 'Sandy Shores',
            coords = vector3(1956.0, 3740.0, 32.6),
            radius = 3.0,
            cargo  = { 'drugs', 'animals', 'weapons' },
        },
        {
            id     = 'palomino_bay',
            label  = 'Contato da Baía',
            area   = 'Palomino Bay',
            coords = vector3(1389.0, -2067.0, 52.0),
            radius = 3.0,
            cargo  = { 'contraband', 'weapons' },
        },
    },

    -- Pontos de entrega clandestinos (destinos ilegais — sem nome no mapa para o cop)
    deliveries = {
        {
            id     = 'del_north_ls',
            area   = 'Norte de LS',
            coords = vector3(138.0, -1744.0, 29.3),
            radius = 8.0,
            accepts = { 'contraband', 'drugs', 'weapons' },
        },
        {
            id     = 'del_sandy_caves',
            area   = 'Cavernas — Sandy',
            coords = vector3(2580.0, 3517.0, 53.7),
            radius = 8.0,
            accepts = { 'animals', 'minerals' },
        },
        {
            id     = 'del_grapeseed',
            area   = 'Grapeseed',
            coords = vector3(1710.0, 4922.0, 42.1),
            radius = 8.0,
            accepts = { 'animals', 'minerals', 'contraband' },
        },
        {
            id     = 'del_vespucci',
            area   = 'Vespucci Canals',
            coords = vector3(-789.0, -1607.0, 0.3),
            radius = 8.0,
            accepts = { 'drugs', 'weapons', 'contraband' },
        },
    },
}
```

---

## Section 3 — DB Functions

### `DB_InsertIllegalJob(job, illegalType)`

```lua
-- Insere job ilegal (com illegal_type preenchido)
function DB_InsertIllegalJob(job, illegalType)
    return MySQL.insert.await(
        [[INSERT INTO trucker_jobs
          (id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at, illegal_type)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)]],
        { job.id, job.origin_id, job.dest_id, job.cargo_item, job.trailer_model,
          job.base_payment, job.distance, job.expires_at, illegalType }
    )
end
```

### `DB_GetActiveJobByPlayer` — sem alteração necessária

A query existente usa `SELECT *`, que retornará `illegal_type` automaticamente assim que a coluna for adicionada pela migração. **Não alterar a query** — uma lista explícita de colunas poderia omitir campos como `UNIX_TIMESTAMP(expires_at) as expires_at_unix`, que são necessários para a lógica de expiração.

---

## Section 4 — VP_Trucker Cache

### `server/main.lua`

Adicionar ao bloco `VP_Trucker = { ... }`:
```lua
IllegalTargets = {},  -- [plate] = { src, jobId, citizenid, illegalType }
```

---

## Section 5 — IllegalService

### `server/services/illegal_service.lua`

```lua
IllegalService = {}  -- global (lua54: sem local)
```

#### Métodos

**`IllegalService.Generate(contactId, illegalType, requesterSrc)`**
- Valida: jogador sem job ativo, contactId existe em Config, illegalType é válido para esse contato (`contact.cargo`)
- Seleciona destino compatível aleatório de `Config.IllegalJobs.deliveries` onde `delivery.accepts` contém `illegalType`
- Calcula distância com a mesma `CalcDistance` do `job_service.lua` (retorna km)
- `base_payment` = `math.floor(dist * Config.JobGeneration.distanceMultiplier * Config.IllegalJobs.paymentMultipliers[illegalType])`
  — reutiliza o mesmo multiplicador de distância dos jobs legais; `paymentMultipliers` serve como o fator combinado de preço
- `DB_InsertIllegalJob(job, illegalType)` — usar `contact.id` como `origin_id` e `delivery.id` como `dest_id` (estes IDs NÃO existem em `Config.PrimaryIndustries`/`Config.SecondaryIndustries`, mas o DB apenas os armazena como VARCHAR sem FK); NÃO definir `convoy_id` (deve ser NULL)
- `DB_AcceptJob(jobId, citizenId, companyId=nil)`
- Retorna `{ jobId, destCoords = delivery.coords, destArea = delivery.area, cargoLabel = Config.IllegalJobs.alertLabels[illegalType], payment = base_payment }`

**`IllegalService.BroadcastAlert(src, illegalType, area)`**
- Itera `GetPlayers()`, checa `PlayerData.job.name`
- LSPD: notificação de texto colorida (vermelho/laranja)
- SALA (se `illegalType` em `salaTypes`): notificação adicional para agentes SALA
- Alta prioridade (`highPriorityTypes`): prefixo `[LSPD ⚠]`

**`IllegalService.RegisterSeizureTarget(src, jobId, plate, illegalType)`**
- `VP_Trucker.IllegalTargets[plate] = { src = src, jobId = jobId, citizenid = cid, illegalType = illegalType }`
- Broadcast `AUST_trucker:client:illegalJobStarted` para TODOS os clientes conectados (não só o motorista):
  ```lua
  TriggerClientEvent('AUST_trucker:client:illegalJobStarted', -1, { plate = plate, driverSrc = src })
  ```
  Usar `-1` como target para broadcast global. O client-side handler verifica o job do jogador para decidir se registra o ox_target (cop/sala registra para poder lacrar; motorista registra para atualizar estado local)

**`IllegalService.ClearSeizureTarget(plate)`**
- Lê `VP_Trucker.IllegalTargets[plate]` para capturar `target.src` ANTES de remover
- Remove `VP_Trucker.IllegalTargets[plate] = nil` imediatamente após a leitura, para prevenir re-entrada caso `ClearSeizureTarget` seja chamado novamente antes da função retornar
- Broadcast `AUST_trucker:client:illegalJobEnded` para TODOS os clientes com a placa:
  ```lua
  TriggerClientEvent('AUST_trucker:client:illegalJobEnded', -1, { plate = plate, driverSrc = target and target.src or nil })
  ```
  Todos os clientes que registraram o ox_target devem removê-lo; o motorista também limpa seu estado local

**`IllegalService.Seize(copSrc, plate)`**
- Valida: cop tem job `policeJob` ou `salaJob`; plate existe em `VP_Trucker.IllegalTargets`
- Se validação falha: retorna silenciosamente (o servidor rejeita — é a única proteção; nenhum check client-side necessário)
- `target = VP_Trucker.IllegalTargets[plate]` — captura antes de limpar
- `DB_AbandonJob(target.jobId, target.citizenid)` — DEVE passar citizenid, pois a query inclui `AND assigned_citizenid = ?`
- Deduz multa no jogador motorista: `Player.Functions.RemoveMoney('cash', fine, 'seizure')` — sem banco
- Log: `DB_RecordInfraction(target.citizenid, target.jobId, 'illegal_seizure', descricao, copIdentifier)` — `'illegal_seizure'` é válido após a migração do ENUM
- `TriggerClientEvent('AUST_trucker:client:cargoSeized', target.src, { fine = fine, illegalType = target.illegalType })`
- `TriggerClientEvent('AUST_trucker:client:seizureSuccess', copSrc, { illegalType = target.illegalType })`
- `IllegalService.ClearSeizureTarget(plate)`

**`IllegalService.OnComplete(src, Player, citizenId, activeJob, payload)`**
- Chamado por `JobService.Complete` quando `activeJob.illegal_type ~= nil`
- Calcula pagamento: `math.floor(activeJob.base_payment * timeMult * integrityMult)` — SEM skillMult de empresa, SEM companyMult
- `Player.Functions.AddMoney('cash', payment, 'aurp-trucker-illegal')` — pago em cash (não banco)
- `DB_CompleteJob(activeJob.id)`
- `DB_AddPlayerStats(citizenId, payment, activeJob.distance)` — contabiliza dinheiro e distância
- `ProgressionService.GrantXP(src, citizenId, activeJob.base_payment, 1.0)` — XP pessoal concedido normalmente
- **NÃO** concede XP de empresa
- `if payload.plate then IllegalService.ClearSeizureTarget(payload.plate) end` — nil-guard obrigatório; `payload.plate` pode ser nil se o motorista completou o job a pé (fora do caminhão)
- Retorna `true, payment`

---

## Section 6 — JobService Hook

### `server/services/job_service.lua` — `JobService.Complete`

Adicionar bloco APÓS o hook de convoy e ANTES do cálculo de `timeMult`:

```lua
-- Detectar job ilegal — delegar ao IllegalService
if activeJob.illegal_type and IllegalService then
    return IllegalService.OnComplete(src, Player, citizenId, activeJob, payload)
end
```

**Ordem dos hooks em `JobService.Complete`:**
1. Convoy hook (`activeJob.convoy_id`) → `return`
2. **Illegal hook** (`activeJob.illegal_type`) → `return`
3. Cálculo normal de timeMult, skillMult, etc.

---

## Section 7 — Callbacks

### Adicionar em `server/callbacks.lua`

```lua
-- Retorna lista de jobs ilegais disponíveis no contato
lib.callback.register('AUST_trucker:getIllegalJobs', function(source, contactId)
    -- Validar contactId
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if not contact then return nil end  -- nil = client não exibe menu

    -- Construir opções: uma por tipo de cargo que esse contato oferece
    local options = {}
    for _, illegalType in ipairs(contact.cargo) do
        -- Selecionar um destino compatível aleatório para mostrar a área (sem revelar coords)
        local destArea = nil
        local compatible = {}
        for _, d in ipairs(Config.IllegalJobs.deliveries) do
            for _, a in ipairs(d.accepts) do
                if a == illegalType then table.insert(compatible, d); break end
            end
        end
        if #compatible > 0 then
            destArea = compatible[math.random(#compatible)].area
        end

        -- Estimar pagamento: cálculo aproximado usando distância média, ±20% de variação exibida
        -- Não revelar valor exato — manter mistério
        local mult = Config.IllegalJobs.paymentMultipliers[illegalType] or 1.0
        local estBase = math.floor(Config.JobGeneration.distanceMultiplier * 30 * mult)  -- 30 km estimado
        local low  = math.floor(estBase * 0.8 / 1000) * 1000
        local high = math.floor(estBase * 1.2 / 1000) * 1000
        local paymentEstimate = ('$%d – $%d'):format(low, high)

        table.insert(options, {
            illegalType     = illegalType,
            cargoLabel      = Config.IllegalJobs.alertLabels[illegalType] or illegalType,
            paymentEstimate = paymentEstimate,
            destArea        = destArea or '???',
        })
    end

    return options  -- lista de { illegalType, cargoLabel, paymentEstimate, destArea }
end)

-- Aceita um job ilegal
lib.callback.register('AUST_trucker:acceptIllegalJob', function(source, contactId, illegalType)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false } end
    local cid = Player.PlayerData.citizenid

    -- Validar: sem job ativo
    if DB_GetActiveJobByPlayer(cid) then
        return { success = false, reason = 'Você já tem um trabalho ativo' }
    end

    local result = IllegalService.Generate(contactId, illegalType, source)
    if not result then return { success = false, reason = 'Trabalho indisponível' } end

    -- Alerta após aceite
    local contact = nil
    for _, c in ipairs(Config.IllegalJobs.contacts) do
        if c.id == contactId then contact = c; break end
    end
    if contact then
        IllegalService.BroadcastAlert(source, illegalType, contact.area)
    end

    return { success = true, jobData = result }
end)
```

---

## Section 8 — Events

### `server/events.lua` — dois novos handlers

```lua
-- Apreensão: cop usa ox_target "Lacrar Carga"
RegisterNetEvent('AUST_trucker:seizeIllegalCargo', function(plate)
    local src = source
    if not plate then return end
    IllegalService.Seize(src, plate)
end)

-- Registro de placa: motorista entra no caminhão com job ilegal ativo
-- Chamado pelo client quando truckStateChanged isInTruck=true e illegalJobActive=true
RegisterNetEvent('AUST_trucker:illegalRegisterPlate', function(plate)
    local src = source
    if not plate then return end
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    local activeJob = DB_GetActiveJobByPlayer(cid)
    if not activeJob or not activeJob.illegal_type then return end
    IllegalService.RegisterSeizureTarget(src, activeJob.id, plate, activeJob.illegal_type)
end)
```

**Nota:** `RegisterSeizureTarget` é chamado SOMENTE pelo handler de `illegalRegisterPlate`, não no momento do aceite do job (o plate não é conhecido no momento do aceite).

---

## Section 9 — Client (`illegal.client.lua`)

### Zonas de contato

- `CreateThread` que registra `exports.ox_target:addSphereZone` para cada contato em `Config.IllegalJobs.contacts`
- Opção: "Falar com Contato" (ícone `fas fa-handshake`, sem job check — qualquer jogador pode tentar)
- Ao interagir: `lib.callback.await('AUST_trucker:getIllegalJobs', false, contact.id)`
- `lib.registerContext` exibe menu com opções de cargo — nome vago, faixa de pagamento, área de entrega
- Ao escolher: `lib.callback.await('AUST_trucker:acceptIllegalJob', false, contact.id, illegalType)`
- Se `result.success`: `lib.notify` + aceita job normalmente (mesmo fluxo de `StartLoading`)

### Zonas de entrega

- `CreateThread` que registra `exports.ox_target:addSphereZone` para cada delivery em `Config.IllegalJobs.deliveries`
- Opção: "Descarregar Carga Ilegal" — visível apenas se `illegalJobActive == true` (estado local)
- Ao interagir: dispara `TriggerEvent('AUST_trucker:client:triggerComplete')` para acionar o fluxo de conclusão em `client.lua`

### Modificação em `client.lua`

Adicionar após a declaração da função `CompleteJob` em `client.lua` (necessário porque lua54='yes' torna `CompleteJob` local e invisível para `illegal.client.lua`):
```lua
AddEventHandler('AUST_trucker:client:triggerComplete', CompleteJob)
```
Isso permite que `illegal.client.lua` dispare a conclusão do job através do barramento de eventos local, cruzando o isolamento de chunk.

### Registrar placa quando motorista entra no caminhão

Em `illegal.client.lua`, adicionar handler para o evento já existente `AUST_trucker:client:truckStateChanged` (ou equivalente emitido por `client.lua`/`hud.client.lua` quando `isInTruck` muda para `true`):
```lua
AddEventHandler('AUST_trucker:client:truckStateChanged', function(isInTruck, plate)
    if isInTruck and illegalJobActive and plate then
        TriggerServerEvent('AUST_trucker:illegalRegisterPlate', plate)
    end
end)
```
Se o evento `truckStateChanged` não existir (verificar no `client.lua` atual), adicionar um `TriggerEvent` com essa assinatura onde `isInTruck` muda.

### Estado local

```lua
local illegalJobActive = false
local illegalPlate     = nil

-- Conjunto de placas com jobs ilegais ativos conhecidos por este client (para re-registro em streaming)
-- { [plate] = true } — populado por illegalJobStarted, removido por illegalJobEnded
local knownIllegalPlates = {}
```

### Thread de re-registro por proximidade (late-arriving cops)

Como `illegalJobStarted` é um broadcast único, um cop que não estava em range de streaming quando o evento disparou nunca registrará o ox_target. Para resolver isso, adicionar em `illegal.client.lua` uma thread de polling:

```lua
-- Verifica a cada 5s se alguma placa conhecida entrou em range de streaming
CreateThread(function()
    while true do
        Wait(5000)
        for plate, _ in pairs(knownIllegalPlates) do
            local vehicle = GetVehicleWithNumberPlate(plate)
            if vehicle and vehicle ~= 0 then
                -- Tenta registrar — ox_target ignora silenciosamente se já registrado
                exports.ox_target:addLocalEntity(vehicle, {
                    {
                        name     = 'seize_illegal_cargo_' .. plate,
                        label    = 'Lacrar Carga',
                        icon     = 'fas fa-lock',
                        distance = 3.0,
                        onSelect = function()
                            TriggerServerEvent('AUST_trucker:seizeIllegalCargo', plate)
                        end,
                    }
                })
            end
        end
    end
end)
```

Atualizar os handlers `illegalJobStarted` e `illegalJobEnded` para manter `knownIllegalPlates`:
- Em `illegalJobStarted`: `knownIllegalPlates[data.plate] = true`
- Em `illegalJobEnded`: `knownIllegalPlates[data.plate] = nil`

### Eventos recebidos

```lua
-- Servidor broadcast para TODOS os clientes quando job ilegal é iniciado.
-- Cada cliente decide localmente o que fazer com a informação.
RegisterNetEvent('AUST_trucker:client:illegalJobStarted', function(data)
    -- Atualizar estado do motorista (identificado por driverSrc)
    local myServerId = GetPlayerServerId(PlayerId())  -- sempre = source local
    if data.driverSrc == myServerId then
        illegalJobActive = true
        illegalPlate     = data.plate
    end

    -- Todos os jogadores (inclusive cops) registram o ox_target no caminhão
    -- Se o veículo não está streamado, GetVehicleWithNumberPlate retorna 0 — cop deve se aproximar
    -- Nota: função nativa correta é GetVehicleWithNumberPlate (não GetVehicleWithPlate)
    local vehicle = GetVehicleWithNumberPlate(data.plate)
    if vehicle and vehicle ~= 0 then
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name     = 'seize_illegal_cargo_' .. data.plate,
                label    = 'Lacrar Carga',
                icon     = 'fas fa-lock',
                distance = 3.0,
                onSelect = function()
                    TriggerServerEvent('AUST_trucker:seizeIllegalCargo', data.plate)
                end,
            }
        })
    end
end)

-- Carga apreendida (motorista recebe)
RegisterNetEvent('AUST_trucker:client:cargoSeized', function(data)
    illegalJobActive = false
    illegalPlate     = nil
    lib.notify({
        title       = 'Carga Apreendida',
        description = ('Sua carga foi apreendida. Multa: $%d'):format(data.fine),
        type        = 'error',
        duration    = 8000,
    })
end)

-- Apreensão bem-sucedida (cop recebe)
RegisterNetEvent('AUST_trucker:client:seizureSuccess', function(data)
    lib.notify({
        title       = 'Apreensão Confirmada',
        description = ('Carga de %s lacrada com sucesso.'):format(
            Config.IllegalJobs.alertLabels[data.illegalType] or data.illegalType),
        type        = 'success',
    })
end)

-- Job concluído ou cancelado — broadcast para todos os clientes.
-- Cada cliente remove o ox_target local; o motorista também limpa estado.
RegisterNetEvent('AUST_trucker:client:illegalJobEnded', function(data)
    -- Remover ox_target do caminhão em todos os clientes que o registraram
    if data and data.plate then
        local vehicle = GetVehicleWithNumberPlate(data.plate)
        if vehicle and vehicle ~= 0 then
            exports.ox_target:removeLocalEntity(vehicle)
        end
    end

    -- Limpar estado local apenas no motorista
    local myServerId = GetPlayerServerId(PlayerId())
    if data and data.driverSrc == myServerId then
        illegalJobActive = false
        illegalPlate     = nil
    end
end)
```

---

## Section 10 — fxmanifest

### Versão e novos arquivos

- `version '9.1.0'`
- Em `server_scripts`: adicionar `'server/services/illegal_service.lua'` APÓS `convoy_service.lua`
- Em `client_scripts`: adicionar `'client/illegal.client.lua'` após `convoy.client.lua`

---

## Section 11 — Notas de Implementação

### Armadilhas conhecidas

1. **`DB_GetActiveJobByPlayer` deve retornar `illegal_type`** — verificar o SELECT atual e garantir que a coluna está incluída. Se não estiver, modificar a query.

2. **ox_target no veículo** — `addLocalEntity` é client-side e requer que o veículo exista no mundo do jogador. O target de apreensão é registrado ao receber `illegalJobStarted`. Se o motorista sair do veículo antes de ser apreendido, o target persiste no veículo enquanto o evento `illegalJobEnded` não chegar.

3. **`GetVehicleWithPlate(plate)` em FiveM** — a função nativa é `GetVehicleWithNumberPlate(plate)` que pode retornar 0 se o veículo não estiver streamado para o cliente. O cop pode precisar estar próximo do caminhão para que ele apareça.

4. **`IllegalService.OnComplete` recebe `payload.plate`** — o plate vem do payload de `CompleteJob`. Garantir que `hud.client.lua` envia `SimState.lastKnownPlate` no payload (padrão já estabelecido em v7+).

5. **Jobs ilegais não contam para XP de empresa** — apenas `ProgressionService.GrantXP` pessoal. Não chamar `CompanyService.AddXP`.

6. **Pagamento em cash** — `AddMoney('cash', ...)`, não `Config.General.payment.currency`. Entregas ilegais são sempre cash.

7. **`illegal_service.lua` APÓS `convoy_service.lua` no fxmanifest** — como o hook em `JobService.Complete` usa nil-guard (`if activeJob.illegal_type and IllegalService`), a referência a `IllegalService` é resolvida em runtime (não em load time). Mesmo que `job_service.lua` carregue antes de `illegal_service.lua`, o nil-guard garante que não há erro de referência. Ainda assim, por convenção coloca-se após `convoy_service.lua`.

8. **Jobs ilegais NUNCA devem ter `convoy_id`** — `DB_InsertIllegalJob` não deve incluir `convoy_id` na INSERT (o default NULL é correto). Se um job tivesse tanto `convoy_id` quanto `illegal_type`, o hook de convoy em `JobService.Complete` seria acionado primeiro, ignorando o hook ilegal. Essa combinação é arquiteturalmente inválida.

9. **`seizeIllegalCargo` — proteção server-side é suficiente** — o ox_target "Lacrar Carga" é registrado client-side no caminhão do motorista e é visível para todos. Qualquer jogador pode acionar o evento. A validação de job police/sala no servidor é a única proteção necessária: se um não-cop disparar o evento, o servidor rejeita silenciosamente. Não adicionar checagem client-side adicional — seria bypassável.

10. **`RegisterSeizureTarget` é chamado pelo handler de `illegalRegisterPlate`** — o aceite do job (`acceptIllegalJob`) não conhece a placa do veículo. A placa só é registrada quando o motorista entra no caminhão e o client dispara `illegalRegisterPlate`. Isso significa que há uma janela de tempo entre o aceite e o registro do target de apreensão (enquanto o motorista ainda não entrou no caminhão).

11. **`removeLocalEntity` remove TODAS as opções do entity handle** — `exports.ox_target:removeLocalEntity(vehicle)` não é scoped ao nome da opção; remove o veículo inteiramente do sistema ox_target. Isso é aceitável porque nenhum outro sistema neste resource registra ox_target em caminhões dirigidos por jogadores. Não introduzir targets genéricos em veículos de jogadores em outros arquivos.

12. **`removeLocalEntity` em entity não registrada é no-op** — um cop que estava fora de range durante `illegalJobStarted` (nunca chamou `addLocalEntity`) pode chamar `removeLocalEntity` em `illegalJobEnded` sem causar erro; ox_target simplesmente não encontrará nada para remover.

13. **`math.random` é inicializado em `main.lua`** — verificar se `math.randomseed(os.time())` já existe no startup. Se não existir, adicionar em `main.lua` antes do primeiro uso.

### Fluxo completo do jogador

```
1. Vai ao ponto de contato (ox_target)
2. Escolhe tipo de cargo no menu ox_lib
3. Server gera job ilegal + aceita automaticamente
4. Server dispara alerta para LSPD/SALA (texto, área geral)
5. Client recebe illegalJobStarted → registra ox_target no caminhão
6. Jogador carrega trailer (fluxo normal de StartLoading)
7. Jogador dirige até destino de entrega
8. Usa ox_target "Descarregar" → CompleteJob() → IllegalService.OnComplete
9. Pagamento em cash × multiplicador
10. ClearSeizureTarget → illegalJobEnded → limpa estado client
```

### Fluxo de apreensão

```
1. Cop está próximo do caminhão ilegal
2. Vê ox_target "Lacrar Carga" (sempre visível — validação no servidor)
3. TriggerServerEvent('AUST_trucker:seizeIllegalCargo', plate)
4. Server valida job police/sala → IllegalService.Seize
5. Job cancelado, multa deduzida do motorista
6. Notificação ao motorista + ao cop
7. Cop prossegue com prisão pelo sistema policial do servidor (fora do escopo)
```
