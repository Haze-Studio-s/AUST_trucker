# Truck Simulation (EuroTruck-Inspired) — Design Spec

**Data:** 2026-03-19
**Projeto:** AUST_trucker — Sub-projeto A: Simulação de Viagem
**Status:** Aprovado pelo usuário (revisão v2)

---

## Objetivo

Adicionar mecânicas de simulação inspiradas no EuroTruck Simulator ao AUST_trucker:
combustível persistente por veículo, fadiga persistente por motorista, integridade da carga
linear e Dashboard HUD configurável. Cada sistema afeta diretamente o gameplay e o pagamento
das entregas, criando decisões estratégicas reais.

---

## Arquitetura Geral

Abordagem híbrida: client gerencia estado local e display em tempo real; servidor valida e
persiste em checkpoints (job complete, guardar veículo, desconexão). Servidor faz validação
leve de anti-cheat no job complete.

```
Client (hud.client.lua)
  ├── Thread de combustível  → consome fuel por tempo/velocidade → sync ao servidor
  ├── Thread de fadiga       → aumenta dirigindo → restaura em rest stops
  ├── Detector de impacto    → queda brusca de velocidade = dano à carga
  └── Thread HUD             → SendNUIMessage('updateHUD') a cada 500ms

Server (truck_simulation_service.lua)
  ├── Carrega fuel/fatigue do banco no spawn/login
  ├── Recebe syncs periódicos (30s) e em checkpoints
  ├── Valida integridade no job complete (algoritmo definido abaixo)
  └── Persiste no banco

React NUI
  └── <TruckHUD /> — overlay persistente fora do painel principal
```

---

## Modelo de Dados

### Migração

**`sql/update_simulation.sql`** — para servidores existentes (v5.x → v7.x):
```sql
ALTER TABLE trucker_company_vehicles
    ADD COLUMN IF NOT EXISTS fuel_level FLOAT DEFAULT 100.0;

ALTER TABLE trucker_player_progression
    ADD COLUMN IF NOT EXISTS fatigue FLOAT DEFAULT 0.0;

ALTER TABLE trucker_companies
    ADD COLUMN IF NOT EXISTS fleet_upgrades JSON DEFAULT ('{}');
```

**`import.sql`** — para instalações novas: as mesmas colunas são incluídas diretamente nas
definições `CREATE TABLE` de `trucker_company_vehicles`, `trucker_player_progression` e
`trucker_companies`. O arquivo `update_simulation.sql` usa apenas `ALTER TABLE IF NOT EXISTS`
e é seguro rodar em qualquer servidor.

A integridade da carga **não é persistida** — existe apenas na memória do client durante
o job ativo. O servidor recebe o valor final apenas no `job_complete`.

---

## Configuração (`Config.TruckSimulation`)

```lua
Config.TruckSimulation = {
    TruckModels = {
        'flatbed', 'hauler', 'phantom', 'mule', 'bison',
    },

    HUD = {
        Enabled  = true,          -- false = desativa display (sistemas continuam rodando)
        Position = 'bottom-left', -- bottom-left | bottom-right | top-left | top-right
        Scale    = 1.0,
    },

    Fuel = {
        ConsumptionRate  = 0.015,  -- % por segundo em velocidade normal
        LoadedMultiplier = 1.4,    -- multiplicador com carga ativa
        LowFuelThreshold = 20.0,   -- % para alerta no HUD
        SyncInterval     = 30000,  -- ms entre syncs com servidor
        GasStations      = {
            -- ATENÇÃO: substituir vector3(0,0,0) por coordenadas reais antes de deploy
            { coords = vector3(0, 0, 0), name = "Posto Sandy" },
        },
    },

    Fatigue = {
        IncreaseRate      = 0.02,  -- % por segundo dirigindo
        RestoreRate       = 0.5,   -- % por segundo em parada de descanso
        RestDuration      = 1.2,   -- segundos de barra por % de fadiga (80% = 96s de barra)
        WarnThreshold     = 50.0,
        HeavyThreshold    = 75.0,
        CriticalThreshold = 90.0,
        MinSpeedForSleep  = 5.0,   -- m/s mínimo para disparar evento de 100% (evita griefing parado)
        RestStops         = {
            -- ATENÇÃO: substituir vector3(0,0,0) por coordenadas reais antes de deploy
            { coords = vector3(0, 0, 0), name = "Parada I-95" },
        },
    },

    Cargo = {
        ImpactThreshold  = 8.0,    -- m/s² de desaceleração para detectar colisão
        ImpactDamage     = 15.0,   -- % de integridade perdida por colisão forte
        SpeedDamageRate  = 0.005,  -- % por segundo acima do SpeedLimit
        SpeedLimit       = 30.0,   -- m/s (~108 km/h)
        MinPaymentRate   = 0.10,   -- pagamento mínimo (10%) se integridade = 0%
        -- Anti-cheat: mínimo de integridade esperada por km percorrido em condições perfeitas
        -- Um motorista perfeito em rota de 100km recebe no máximo 100% (sem penalidade mínima)
        -- O servidor só rejeita valores ACIMA de 100 (impossíveis) — não assume dano mínimo
        MaxIntegrityFloor = 100.0,
    },
}

Config.FleetUpgrades = {
    anti_sleep = {
        label       = "Sistema Anti-Sono (ADAS)",
        price       = 150000,
        description = "Freio automático ao detectar fadiga crítica. "
                   .. "Sem upgrade: caminhão acelera ao adormecer.",
    },
}
```

---

## Sistema de Combustível

### Spawn do veículo
1. Servidor carrega `fuel_level` de `trucker_company_vehicles` pelo `plate`
2. Envia `AUST_trucker:client:setVehicleFuel` ao client com `{ plate, fuel }`
3. Client aplica `SetVehicleFuelLevel(vehicle, fuel)` e inicia thread de consumo

### Thread client (a cada 1s, só enquanto veículo com `plate` vinculado está ativo)
- Lê `GetEntitySpeed(vehicle)` — se veículo mudou (player entrou em outro), thread redetecta plate
- Calcula consumo: `ConsumptionRate × (LoadedMultiplier se activeJob ~= nil)`
- Skill Distance: cada nível (1–6) reduz `ConsumptionRate` em 4% (máx. 24% no nível 6)
- Reduz fuel local; atualiza HUD
- A cada `SyncInterval`: `TriggerServerEvent('AUST_trucker:syncSimulation', { fuel = fuel, fatigue = fatigue })`

### Validação server-side do sync de combustível
O servidor valida o valor recebido contra o tempo decorrido desde o último sync:
```
-- Teto: consumo máximo possível (previne over-consumption impossível)
maxConsumption = ConsumptionRate × LoadedMultiplier × elapsedSeconds × 1.2  -- margem 20%
-- Piso: consumo mínimo esperado se veículo estava em movimento
minConsumption = ConsumptionRate × elapsedSeconds × 0.5  -- 50% margem para idle/baixa velocidade

actualDrop = lastFuel - reportedFuel

if actualDrop > maxConsumption then
    savedFuel = lastFuel - maxConsumption       -- consumo impossível → usar teto do servidor
elseif actualDrop < minConsumption and vehicleWasMoving then
    savedFuel = lastFuel - (ConsumptionRate × elapsedSeconds)  -- under-reporting → usar base
else
    savedFuel = reportedFuel
end
```
O servidor mantém `lastSyncTime`, `lastFuel` e `vehicleWasMoving` por jogador em memória
(`VP_Trucker.SimState[source]`). O client envia `vehicleWasMoving` (bool) junto no sync payload.

### Combustível em 0
- `SetVehicleEnginePowerMultiplier(vehicle, 0.1)` — veículo arrasta progressivamente
- HUD pisca vermelho

### Troca de veículo / multi-veículo
- Thread detecta mudança de vehicle entity a cada 1s via `GetVehiclePedIsIn`
- Se player entra em outro caminhão da frota: sync do veículo anterior → carrega fuel do novo
- Integridade da carga está vinculada ao `activeJob.id`, não ao veículo — não é possível completar job de outro veículo (o server valida `plate` no `completeJob`)

### Checkpoints obrigatórios (sync imediato)
- Job complete
- Guardar veículo na garagem
- Desconexão (`playerDropped` server-side)
- **Veículo destruído**: server event `AUST_trucker:vehicleDestroyed` — fuel é sincronizado no estado atual, job é marcado como `failed` com integridade 0% e pagamento mínimo (10%)

### Reabastecimento (ox_target nos postos)
- Menu ox_lib: quantidade de litros × preço por litro (config)
- Preço deduzido do bolso do motorista
- Client aplica `SetVehicleFuelLevel` + sync imediato ao servidor

---

## Sistema de Fadiga

### Login do jogador
1. Servidor carrega `fatigue` de `trucker_player_progression`
2. Se linha não existe ou query retorna nil: `fatigue = 0.0` (padrão seguro)
3. Envia `AUST_trucker:client:setFatigue` ao client com `{ fatigue }`
4. Client inicializa estado local

### Thread client (a cada 1s, só enquanto em caminhão em movimento > 2 m/s)
- `fatigue += IncreaseRate` (0.02% por segundo)
- Skill Speed: cada nível (1–6) reduz `IncreaseRate` em 5% (máx. 30% no nível 6)
- Aplica efeitos visuais por faixa:

| Faixa     | Efeito                                                    |
|-----------|-----------------------------------------------------------|
| 0–49%     | Nenhum                                                    |
| 50–74%    | Vinheta leve (`SetTimecycleModifier('HighContrast', 0.3)`) |
| 75–89%    | Blur suave + notificação de aviso                         |
| 90–99%    | Blur pesado + aviso crítico a cada 30s                    |
| 100%      | Ver abaixo                                                |

### Fadiga 100% — condição de disparo
- Só dispara se `GetEntitySpeed(vehicle) > MinSpeedForSleep` (5 m/s)
- Se parado ou quase parado: apenas efeito visual de blur, sem perda de controle

### Fadiga 100% — sem upgrade Anti-Sono
- Tela fecha por 3s (`DoScreenFadeOut / DoScreenFadeIn`)
- `SetVehicleEnginePowerMultiplier(vehicle, 2.0)` + `SetVehicleHandbrake(vehicle, false)` — caminhão acelera
- Após 3s: controle devolvido ao jogador
- Integridade da carga sofre `ImpactDamage × 2` (impacto presumido)

### Fadiga 100% — com upgrade Anti-Sono (empresa comprou)
- Alerta sonoro a 90% de fadiga
- Aos 100%:
  1. `SetVehicleEnginePowerMultiplier(vehicle, 0.0)` — corta acelerador
  2. `SetVehicleBrakeLights(vehicle, true)` + aplica freio via `TaskVehicleTempAction(ped, vehicle, 1, 3000)` — desacelera suavemente
  3. Tela fecha por 2s — veículo para com segurança
- Controle devolvido após parada completa

### Como o client sabe se a empresa tem o upgrade
- Ao abrir o caminhão / spawn: servidor envia `AUST_trucker:client:setSimConfig` com `{ hasAntiSleep = true/false }`
- Carregado de `trucker_companies.fleet_upgrades` (JSON: `{ "anti_sleep": true }`)
- Client armazena localmente — não consulta servidor em tempo real (sem round-trip no momento crítico)

### Parada de descanso (ox_target nas coords do Config)
- Opção "Descansar" → progress bar ox_lib
- Duração: `fatigue × RestDuration` segundos (ex: 80% fadiga × 1.2s = 96s de barra)
- Cancelamento da barra: restauração parcial proporcional ao tempo completado é aplicada
- `fatigue = math.max(0.0, fatigue - RestoreRate × tempo_completado)` ao cancelar ou completar
- Ao completar 100% da barra: notificação + sync imediato ao servidor

### Sync com servidor
- A cada 30s (mesma chamada que o sync de combustível: `AUST_trucker:syncSimulation`)
- Job complete, desconexão

---

## Sistema de Integridade da Carga

### Job aceito
- Integridade inicia em 100% (memória local do client, vinculada a `activeJob.id`)
- HUD exibe barra verde

### Thread client (a cada 500ms, só com job ativo)

**Detector de impacto:**
- `prevSpeed` registrado a cada frame
- Se `(prevSpeed - currentSpeed) > ImpactThreshold` → colisão detectada
- `integrity -= ImpactDamage` (15% por colisão)
- Flash vermelho no HUD

**Excesso de velocidade:**
- Se `GetEntitySpeed(vehicle) > SpeedLimit` → `integrity -= SpeedDamageRate` por segundo (a cada 0.5s: `SpeedDamageRate × 0.5`)
- Skill Fragile: cada nível (1–6) reduz `ImpactDamage` em 10% e `SpeedDamageRate` em 8%

**Cores HUD:**

| Faixa    | Cor                       |
|----------|---------------------------|
| 80–100%  | Verde                     |
| 50–79%   | Amarelo                   |
| 0–49%    | Vermelho + ícone de aviso |

### Payload do job complete — contrato de dados
O client envia via `TriggerServerEvent('AUST_trucker:completeJob', payload)` com:
```lua
payload = {
    jobId        = activeJob.id,
    deliveryTime = deliveryTime,      -- segundos desde aceite
    plate        = activeJob.plate,   -- validação de veículo
    cargoIntegrity = math.floor(integrity),  -- 0–100, inteiro
}
```

### Validação server-side (anti-cheat leve)
O servidor **não pode** recalcular a integridade (eventos de impacto são físicos, client-only).
A validação é simples: rejeitar apenas valores impossíveis.

```lua
-- Só rejeitar integridade acima de 100 (impossível) ou negativa
local integrity = math.max(0, math.min(100, payload.cargoIntegrity))
```

Nota: a abordagem intencional é confiar no client para integridade, pois os eventos de
impacto são físicos e não replicáveis no servidor. O anti-cheat de integridade é
responsabilidade do sistema de infrações (penaliza patterns suspeitos no histórico).

### Fórmula de pagamento final
```lua
local integrityMult  = math.max(Config.TruckSimulation.Cargo.MinPaymentRate, integrity / 100)
local payment = math.floor(activeJob.base_payment * timeMult * skillMult * companyMult * integrityMult)
```
Ordem dos multiplicadores: `base × tempo × skill × empresa × integridade`

### Consequências
- Integridade < 30%: infração registrada em `trucker_infractions` (tipo: `'cargo_damage'`)
- Integridade 0%: pagamento = `base_payment × MinPaymentRate` (10%)
- Veículo destruído mid-job: integridade forçada a 0%, job marcado `failed`, pagamento mínimo aplicado

---

## Dashboard HUD

### Visibilidade
- Veículo em `TruckModels`: exibe velocidade + combustível + fadiga
- Com job ativo: barra de integridade da carga aparece
- Fora de caminhão: HUD some

### Layout (canto configurável via `HUD.Position`)
```
┌─────────────────────────────────┐
│  🚛 128 km/h                    │
│  ⛽ ████████░░  78%             │
│  😴 ███░░░░░░░  32%             │
│  ─────────────────────────────  │  ← só com job ativo
│  📦 ██████░░░░  61%             │
└─────────────────────────────────┘
```

### Arquitetura React
- `<TruckHUD />` montado na raiz do `App.tsx`, fora do `<MainPanel />`
- Recebe `updateHUD` via `useNUI` mesmo com NUI fechada
- Se `HUD.Enabled = false`: componente não é montado; threads continuam normalmente

### Mensagem `updateHUD`
```typescript
interface HUDData {
  visible:   boolean
  speed:     number        // km/h
  fuel:      number        // 0–100
  fatigue:   number        // 0–100
  integrity: number | null // 0–100 com job ativo, null sem job
}
```

### Exports para HUDs externas (quando `HUD.Enabled = false`)
```lua
-- server/exports.lua (server-side — retornam último valor sincronizado)
exports.AUST_trucker:GetPlayerFuel(source)     -- 0–100 (último sync do servidor)
exports.AUST_trucker:GetPlayerFatigue(source)  -- 0–100 (último sync do servidor)

-- client-side (retorna valor em tempo real da memória local)
exports.AUST_trucker:GetCargoIntegrity()       -- 0–100 ou nil (sem job) — export CLIENT
```

`GetCargoIntegrity` é export **client-side** pois a integridade só existe em memória local
do client durante o job. O server não mantém esse valor entre syncs.

---

## Upgrades de Frota

### Compra (NUI da empresa)
- Seção "Upgrades de Frota" na aba de empresa (apenas dono/manager)
- NUI callback: `purchaseFleetUpgrade` com `{ upgradeKey = 'anti_sleep' }`
- Server handler:
  1. Valida role (owner/manager)
  2. Verifica se upgrade já foi comprado (`fleet_upgrades.anti_sleep == true`)
  3. Verifica saldo da empresa (`company.balance >= price`)
  4. Deduz do saldo via `CompanyService` (que já existe)
  5. Salva `fleet_upgrades` JSON no banco
  6. Notifica todos os membros online: `AUST_trucker:client:setSimConfig` com upgrade atualizado

### JSON structure (`fleet_upgrades`)
```json
{ "anti_sleep": true }
```

### Distribuição do status do upgrade ao client
- No spawn do veículo: servidor envia `AUST_trucker:client:setSimConfig` com `{ hasAntiSleep }`
- Client armazena em variável local — sem round-trip no momento de fadiga crítica

---

## Novos Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `client/hud.client.lua` | Threads fuel/fatigue/integrity, detector de impacto, HUD messages, rest stops e gas stations via ox_target |
| `server/services/truck_simulation_service.lua` | Carrega/salva fuel+fatigue, valida sync, processa job complete com integridade, fleet upgrades |
| `html/src/components/hud/TruckHUD.tsx` | Componente HUD persistente |
| `sql/update_simulation.sql` | Migração das 3 colunas (`fuel_level`, `fatigue`, `fleet_upgrades`) |

## Arquivos Modificados

| Arquivo | Mudança |
|---|---|
| `server/database.lua` | `DB_GetVehicleFuel`, `DB_SetVehicleFuel`, `DB_GetFatigue`, `DB_SetFatigue`, `DB_GetFleetUpgrades`, `DB_SetFleetUpgrades` |
| `server/services/job_service.lua` | Recebe `cargoIntegrity` no payload do `completeJob`; aplica `integrityMult` na fórmula de pagamento |
| `server/exports.lua` | `GetPlayerFuel(source)`, `GetPlayerFatigue(source)` (server); `GetCargoIntegrity()` (client export em `hud.client.lua`) |
| `config/config.lua` | Bloco `Config.TruckSimulation` + `Config.FleetUpgrades` |
| `html/src/App.tsx` | Renderiza `<TruckHUD />` na raiz |
| `html/src/hooks/useNUI.ts` | Case `updateHUD` |
| `html/src/types/index.ts` | Interface `HUDData` |
| `fxmanifest.lua` | Novos arquivos client/server |
| `import.sql` | Colunas nas definições CREATE TABLE (não ALTER TABLE) |
