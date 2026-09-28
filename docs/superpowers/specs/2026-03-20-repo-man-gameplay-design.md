# Repo Man — Gameplay Client-Side — Design Spec

**Fase:** 6 — Repo Man (Sub-spec 2: Gameplay Client-Side)
**Versão alvo:** 6.1.0
**Data:** 2026-03-20
**Depende de:** Sub-spec 1 (backend + NUI) — já implementado em v5.1.0

---

## Objetivo

Implementar a gameplay in-world do sistema Repo Man: spawning do veículo alvo e do flatbed,
mecânicas por tipo de missão (simple/stealth/npc_hostile/pvp), sistema de flatbed integrado
internamente (sem dependência externa de gs_flatbed), e entrega no impound.

---

## Decisão de Integração: Flatbed Interno

A lógica de flatbed (rope attach, statebags, bed lowering) é copiada do `gs_flatbed` e adaptada
em `client/flatbed.client.lua` dentro do próprio AUST_trucker. Isso elimina toda dependência
externa. O código de flatbed ativa **apenas durante missão repo ativa** — não é always-on.

O modelo `flatbed5` (do pack 0r-towtruck) é copiado para `stream/flatbed5/` no AUST_trucker.

---

## Arquitetura

### Fluxo por Tipo de Missão

```
Agent aceita ordem (NUI)
  → server: RepoService.Accept → TriggerClientEvent('AUST_trucker:client:startRepoMission', src, orderData)

client/repo.client.lua recebe startRepoMission:
  → SpawnTargetVehicle(orderData)  ← networked, model por vehicle_type
  → GPS ao target vehicle

  ┌─ simple ──────────────────────────────────────────────────────────────
  │  ox_target "Assumir Veículo" no target
  │  Agent entra → GPS troca para impound → EntrarFaseEntrega()
  └────────────────────────────────────────────────────────────────────────

  ┌─ stealth ─────────────────────────────────────────────────────────────
  │  ox_target "Assumir Veículo" no target
  │  Polling 1s: player <15m antes de entrar → FailMission('detected')
  │  Agent entra → GPS troca para impound → EntrarFaseEntrega()
  │  Dono online notificado APÓS agent sair da zona (≥80m do target spawn)
  └────────────────────────────────────────────────────────────────────────

  ┌─ npc_hostile ─────────────────────────────────────────────────────────
  │  SpawnFlatbed(~55m da zona)  → GPS secundário "Buscar reboque"
  │  SpawnNpcGuards(2-4 ao redor do target, hostis)
  │  Flatbed.client.lua: lowerBed, ox_target "Carregar Veículo" no flatbed
  │  Attach concluído (statebag attachedVehicle != -1):
  │    → DespawnGuards()
  │    → GPS troca para impound → EntrarFaseEntrega()
  └────────────────────────────────────────────────────────────────────────

  ┌─ pvp ─────────────────────────────────────────────────────────────────
  │  SpawnFlatbed(~55m da zona)  → GPS secundário "Buscar reboque"
  │  Dono recebe TriggerClientEvent 'repoTargetNotify': blip piscante + notif
  │  Agente envia coords ao servidor a cada 10s (thread) → servidor relaya ao dono
  │  Attach concluído: GPS troca para impound → EntrarFaseEntrega() + blip some
  └────────────────────────────────────────────────────────────────────────

EntrarFaseEntrega():
  → Zona ox_lib (radius 15m) no Config.RepoMan.ImpoundLocation
  → Callback da zona verifica que o veículo correto está presente ANTES de completar:
      simple/stealth : GetVehiclePedIsIn(PlayerPedId(), false) == NetToVeh(targetVehicle)
      pvp/npc_hostile: jogador está no flatbed E statebag attachedVehicle ~= -1
  → Se validação falhar: notif "Você precisa estar no veículo correto" e NÃO completa
  → Se validação passar: TriggerServerEvent('AUST_trucker:completeRepoOrder', orderId)
  → Servidor processa e emite 'AUST_trucker:client:repoMissionEnded' ao agent → CleanupMission()
```

### Estado Client-Side

```lua
-- client/repo.client.lua
local ActiveRepoMission = nil
-- {
--   orderId           : string,
--   missionType       : 'simple' | 'stealth' | 'npc_hostile' | 'pvp',
--   targetVehicle     : number (netId),   → entidade local via NetToVeh()
--   flatbedVehicle    : number | nil,     → netId
--   npcs              : { number, ... },  → handles locais
--   targetSpawnCoords : vector3,          → para detecção stealth + blip dono
--   phase             : 'driving_to_zone' | 'attaching' | 'driving_to_impound',
--   blipHandle        : number | nil,     → blip do target vehicle
--   impoundZoneId     : string | nil,     → id da zona ox_lib (para remover no cleanup)
--   ownerNotified     : boolean,          → stealth: dono já foi notificado?
--   pvpStartTime      : number | nil,     → GetGameTimer() no início da missão pvp
-- }
```

---

## Mecânicas por Tipo

### `simple`
- Target spawna locked (lock level 4), engine off
- ox_target "Assumir Veículo" (`distance 2.5`): unlock + SetPedIntoVehicle
- Sem NPCs, sem notificação ao dono
- Phase muda para `'driving_to_impound'` ao entrar no veículo

### `stealth`
- Igual ao `simple` com adições:
- Thread polling (Wait 1000): usa `lib.getNearbyPlayers(targetCoords, stealthDetectionRadius, false)`
  (ox_lib, `false` = excluir o próprio player local). Se qualquer player estiver no raio enquanto
  `phase == 'driving_to_zone'` → `FailMission('detected')`
- Notificação ao dono: somente quando agent está a ≥80m do `targetSpawnCoords` E phase muda para
  `'driving_to_impound'` (evita vazar localização antes de sair da zona)

### `npc_hostile`
- 2-4 NPCs criados via `CreatePed` + `TaskGuardCurrentPosition` + Relationship Group hostil ao player
  (count = `math.random(Config.RepoMan.npcGuardCount.min, Config.RepoMan.npcGuardCount.max)`)
- NPCs não perseguem além de `npcLeashRadius` (80m do spawn): thread verifica distância, chama
  `TaskGoStraightToCoord` de volta se ultrapassarem
- Ao attach concluído: `DeletePed` em todos, `ActiveRepoMission.npcs = {}`

### `pvp`
- Ao agent aceitar: servidor emite `repoTargetNotify` ao citizenid do dono (se online)
  → client do dono recebe: `AddBlipForRadius` piscante + notif "Seu veículo está sendo repossessado"
- Client do agent: thread a cada 10s verifica `GetGameTimer() - pvpStartTime < pvpBlipDuration * 1000`.
  Enquanto dentro da janela, envia `repoAgentPositionUpdate` com coords atuais. Após a janela, para.
  Servidor recebe e relaya coords ao dono via `repoAgentUpdate` (sem timer server-side — a janela é
  controlada unilateralmente pelo client do agent)
- Ao mission end (complete ou fail): servidor emite `repoOwnerMissionEnded` ao dono → dono limpa blips

### Detecção de Morte do Agent
- Thread client (Wait 2000): `GetEntityHealth(PlayerPedId()) <= 0` enquanto missão ativa
  → `TriggerServerEvent('AUST_trucker:failRepoOrder', orderId, 'agent_died')`

---

## Sistema de Flatbed (Integrado)

### `client/flatbed.client.lua`

Copiado e adaptado do gs_flatbed. Expõe funções globais usadas por `repo.client.lua`:

```lua
Flatbed = {}

-- Spawna flatbed model na posição dada, retorna netId
function Flatbed.Spawn(coords, heading)

-- Abaixa a cama do flatbed (animação de prop)
function Flatbed.LowerBed(flatbedEntity)

-- Registra ox_target "Carregar Veículo" no flatbed
-- Quando acionado: AttachEntityToEntity + statebag attachedVehicle = netId do target
-- Chama callback onAttached() ao concluir
function Flatbed.RegisterAttachTarget(flatbedEntity, targetEntity, onAttached)

-- Remove ox_target e detach (cleanup)
function Flatbed.Detach(flatbedEntity)

-- Despawna flatbed e limpa statebags
function Flatbed.Despawn(flatbedEntity)
```

Statebag: `Entity(flatbedEntity).state:set('attachedVehicle', netId, true)` (synced)

O modelo `flatbed5` precisa ser adicionado ao config interno de `flatbed.client.lua`
com os offsets corretos de attach (medidos do modelo 0r-towtruck durante implementação).

---

## Cleanup e Encerramento

Toda saída da missão (complete, fail, timeout) passa por `CleanupMission()`:

```lua
local function CleanupMission()
    if not ActiveRepoMission then return end
    local m = ActiveRepoMission
    ActiveRepoMission = nil  -- nil primeiro para evitar re-entrância

    -- Remover GPS/blips do agent
    -- Remover zona ox_lib do impound (m.impoundZoneId)
    -- Deletar NPCs restantes
    -- Limpar ox_target do target vehicle

    -- Flatbed missions (pvp/npc_hostile): SEMPRE desatachar e deletar target + flatbed
    if m.flatbedVehicle then
        local flatbedEnt = NetToVeh(m.flatbedVehicle)
        if DoesEntityExist(flatbedEnt) then
            Flatbed.Detach(flatbedEnt)
        end
        if m.targetVehicle then
            local targetEnt = NetToVeh(m.targetVehicle)
            if DoesEntityExist(targetEnt) then
                DeleteVehicle(targetEnt)
            end
        end
        Flatbed.Despawn(flatbedEnt)
    else
        -- simple/stealth: deletar target apenas se não foi entregue (não está no impound)
        -- Na fase 'driving_to_impound' após completeRepoOrder, o servidor confirmou a entrega;
        -- o veículo pode ser limpo pelo servidor ou deixado despawnar naturalmente.
        -- Se phase != 'driving_to_impound' (fail antes de entregar): deletar target
        if m.phase ~= 'driving_to_impound' and m.targetVehicle then
            local targetEnt = NetToVeh(m.targetVehicle)
            if DoesEntityExist(targetEnt) then DeleteVehicle(targetEnt) end
        end
    end
end
```

`CleanupMission` é acionado por:
- `AUST_trucker:client:repoMissionEnded` recebido do servidor (sucesso ou falha)
- Timeout client local (fallback: `missionTimeout + 30` segundos = 930s)

---

## Eventos de Rede

### Server → Client (agent)
| Evento | Payload | Quando |
|--------|---------|--------|
| `AUST_trucker:client:startRepoMission` | `orderData` | Após Accept — já implementado em RepoService.Accept |
| `AUST_trucker:client:repoMissionEnded` | `{ success, payment }` | Complete OU Fail — **ADICIONAR** em RepoService.Complete e RepoService.Fail |

### Client → Server (agent)
| Evento | Payload | Quando |
|--------|---------|--------|
| `AUST_trucker:completeRepoOrder` | `orderId` | Agent chega ao impound com veículo correto |
| `AUST_trucker:failRepoOrder` | `orderId, reason` | Fail (morte, detecção, etc.) |
| `AUST_trucker:repoAgentPositionUpdate` | `{ orderId, coords }` | A cada 10s durante janela pvp (client controla expiração) |

### Server → Client (dono do veículo — pvp/stealth)
| Evento | Payload | Quando |
|--------|---------|--------|
| `AUST_trucker:client:repoTargetNotify` | `{ zone_coords, agentName }` | Missão iniciada |
| `AUST_trucker:client:repoAgentUpdate` | `{ coords }` | Relay de repoAgentPositionUpdate (pvp) |
| `AUST_trucker:client:repoOwnerMissionEnded` | `{ recovered }` | Missão encerrada |

> **Nota:** Os eventos `repoTargetNotify`, `repoAgentUpdate` e `repoOwnerMissionEnded` são registrados
> em `client/repo.client.lua` como handlers passivos disponíveis para qualquer jogador
> (não apenas agents ativos). Qualquer jogador que seja dono de um veículo alvo recebe esses
> eventos sem precisar ter missão ativa.
> O evento `repoMissionEnded` (agent) e `repoOwnerMissionEnded` (dono) têm nomes distintos
> para evitar colisão de handlers no mesmo arquivo.

---

## Arquivos a Criar / Modificar

| Ação | Arquivo |
|------|---------|
| **CRIAR** | `client/repo.client.lua` — gameplay completa de missão repo |
| **CRIAR** | `client/flatbed.client.lua` — sistema de flatbed integrado (adaptado de gs_flatbed) |
| **CRIAR** | `stream/flatbed5/` — arquivos do modelo (copiados do 0r-towtruck) |
| **MODIFICAR** | `server/services/repo_service.lua` — ADD `TriggerClientEvent('AUST_trucker:client:repoMissionEnded', src, ...)` em `Complete` e `Fail` |
| **MODIFICAR** | `server/events.lua` — ADD handlers: `completeRepoOrder`, `failRepoOrder`, `repoAgentPositionUpdate` (relaya coords ao dono) |
| **MODIFICAR** | `config/config.lua` — ADD seção gameplay ao `Config.RepoMan` existente (vehicleModels, flatbedModel, timeouts, NPC, stealth, pvp) |
| **MODIFICAR** | `fxmanifest.lua` — ADD v6.1.0, `flatbed.client.lua` antes de `repo.client.lua` |

---

## Config a Adicionar em `Config.RepoMan` (seção gameplay)

Adicionar ao bloco `Config.RepoMan` já existente em `config/config.lua`:

```lua
-- Gameplay (Sub-spec 2)
vehicleModels = {
    sedan  = { 'sultan', 'premier', 'asea', 'stratum' },
    suv    = { 'granger', 'cavalcade', 'patriot' },
    truck  = { 'bison', 'bobcatxl', 'sandking2' },
    sport  = { 'feltzer2', 'sentinel', 'schafter2' },
},
flatbedModel           = 'flatbed5',
flatbedSpawnDistance   = 55.0,
-- ImpoundLocation e ImpoundHeading já existem no bloco Config.RepoMan (Sub-spec 1)
impoundRadius          = 15.0,
missionTimeout         = 900,
stealthDetectionRadius = 15.0,
pvpBlipDuration        = 300,
npcGuardModel          = 's_m_m_security_01',
npcGuardCount          = { min = 2, max = 4 },
npcGuardRadius         = 8.0,
npcLeashRadius         = 80.0,
```

---

## Fora de Escopo

- Sistema de flatbed para outros veículos além do repo (future Fase 5)
- UI in-world de progresso da missão (future polish)
- Anti-cheat de teleporte/invulnerabilidade durante repo (future Fase 5)
- Múltiplas zonas de impound configuráveis (future)
