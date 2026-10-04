# AUST_TRUCKER — Estudo de engenharia comparativa: pallets / forklift

**REFERENCE STUDY STATUS: COMPLETE para leitura de código; SEM validação in-game.**
Nada abaixo foi executado no FiveM. Onde algo é inferência e não leitura direta, está marcado como **[inferência]** ou **[não verificado]**.

Base de leitura: AUST em `origin/main` `e5ce6cc` + PR #9 (`5cb5ba7`, onde vivem `pallet_debug`, `pallet_registry`, `pallet_sync_guard`, `pallet_spawn_validation`). Notas 0–10, **10 = melhor** (em "complexidade", 10 = mais simples; em "exploit", 10 = menor superfície).

---

## 1. Executive Summary

1. **O Polarix NÃO usa o mesmo entity do chão nos garfos.** O pallet de chão é um `CreateObject` local, não networked, frozen. No pickup ele é deletado (`DeleteEntity(sourcePallet)`) e um prop novo, também local, é criado e anexado ao osso `forks_attach`. Nenhum dos dois entra na Havok dinâmica.
2. **Os outros três repositórios não resolvem o problema do AUST; eles o evitam.** Don, ESX e xDope deixam a Havok carregar o pallet o tempo todo, com props `prop_boxpile_*` (pallet de caixas de jogo, feito para empilhadeira) e minijogo de um pallet por vez, sem trailer físico e sem multiplayer cooperativo.
3. **O AUST é um híbrido que combina o pior dos dois:** estrutura do Polarix (frozen, attach no osso, slot no trailer) com uma **janela de física de 0 → 0,35 m** que o Polarix evita de propósito. Nessa janela o pallet é `Dynamic`, sem gravidade, networked, empurrado só por contato com os garfos.
4. **Achado novo e decisivo no histórico do J2:** em `41efab6` ele escreveu que descongela o pallet "no toque para não atuar como parede sólida contra os garfos". Ou seja, **o próprio J2 observou que o pallet frozen bloqueia os garfos.** Isso explica por que ele precisou da janela Havok, e muda o desenho da solução: o pallet frozen precisa deixar de colidir com o forklift durante a aproximação (ou o modelo precisa ter vão para os garfos).
5. **O 0,35 m não tem origem técnica rastreável.** `Config.Polarix.Forklift.MaxLiftTolerance = 0.35` existe em `shared/config.lua`, mas **nenhum código o usa** (grep). O commit `ecd55f0` hardcoda 0,35 com o comentário "Decisão A1". O Polarix tem constante análoga, `ForkliftDropMaxHeight = 0.12`, também sem uso.
6. **Recomendação:** Modelo **D-K** (híbrido cinemático): o pallet fica frozen até o attach; a "primeira elevação" é medida **no osso dos garfos, no referencial do forklift**, não no pallet. Entidade única networked (Opção A). Servidor com máquina `STAGED → CLAIMED → CARRIED → STOWED → DELIVERED (+ RECOVERY)`.
7. **Honestidade sobre a matriz:** na média simples de 11 critérios, **B (attach direto) fica um pouco acima de D-K (7,6 contra 7,4).** D-K foi escolhido porque preserva a sensação de "garfo levanta a carga" que você pediu, que B não preserva. Esse é um critério de produto, não de engenharia, e está declarado como tal.
8. **Limite do estudo:** OmniRoute/Antigravity e agentes paralelos **não estão disponíveis neste container**. As sete frentes foram cobertas por uma única leitura sequencial minha. Não há divergência entre agentes para registrar; as tensões internas estão na seção 14.

---

## 2. Repositórios estudados

| Repo | Commit lido | Data | Papel |
|---|---|---|---|
| derPolarix/polarix_truckerjob | `d11dcd1` | 2026-10-03 | Referência principal; o AUST é derivado dele |
| DonHulieo/don-forklift | `4adaf7a` (v1.3.1) | 2024-12-11 | Servidor cria o objeto; física pura |
| Mobius1/esx_forklift | `9edc213` | 2020-09-21 | Física pura; cliente cria o objeto |
| xDope7137/forklift | `1718e31` | 2026-07-28 | Histórico/gameplay apenas |
| Haze-Studio-s/AUST_trucker | `e5ce6cc` (main) + `5cb5ba7` (PR #9) | 2026-10-04 | Alvo |

## 3. Arquivos lidos

- **Polarix:** `client/modules/cargo.lua` (776/776 linhas), `client/modules/forklift.lua` (357/357), `server/modules/party_mission.lua` (claim, load, dropout, cargo state, completeTrip), `server/modules/party.lua` (`OnPlayerUnload`), `shared/cargo.lua`, `config/shared.lua`, `config/client.lua`.
  - **`forklift.lua` do Polarix não contém lógica de pallet.** É só deploy/stow do forklift no trailer. Toda a mecânica de pallet está em `cargo.lua`.
- **Don:** `client/main.lua` (spawn, `setup_mission_obj`, `await_load`, `create_object`), `server/main.lua` (inteiro), `shared/config.lua` (modelos), `server/config.lua`.
- **Mobius:** `client/main.lua` (SpawnPallet, PickupPallet, DeliverPallet, ValidDrop, threads de pallet/entrega/debug), `client/utils.lua` (inteiro), `server/main.lua`, `config.lua` (modelo).
- **xDope:** `forklift_c.lua` (inteiro), `forklift_sv.lua` (inteiro).
- **AUST:** `client/modules/forklift.lua` (lido por regiões: bones, snap no trailer, snap do forklift, `StartOperation` inteiro, `StopOperation`), `client/main.lua` (handler `polarixSyncPallets`), `server/main.lua` (spawn de pallets, ~975–1075), `shared/config.lua` (seção `Polarix`), mais os módulos do PR #9 que eu mesmo escrevi. Diffs completos de `909d17c`, `caaf127`, `41efab6`, `0f2c831`, `ecd55f0`; `d8f530e` pelo diff de `forklift.lua`.

---

## 4. Polarix deep dive

### 4.1 Call-flow real

```
SPAWN → GROUND → PICKUP DETECTION → CLAIM → CARRY → TRAILER → DELIVERY → CLEANUP
```

| Etapa | Entity | Physics | Authority | Network | Validation | Failure handling |
|---|---|---|---|---|---|---|
| **SPAWN** (`SpawnMissionPallets`, thread de 1 s, dist < 40 m) | client-created, **local** (`CreateObject(...,false,false,false)`), em **cada** cliente | `SetEntityHeading`, `PlaceObjectOnGroundProperly`, `FreezeEntityPosition(true)`, `SetEntityCollision(true,true)`, invencível | Cliente cria; servidor decide **quantos/quais slots** (solo: `RequestTripClaim`; party: `getPartyGroundState`) | nenhuma entidade na rede; layout determinístico (`GenerateGridCoords` ou `pickup_pallet_coords`) | slots já tomados pulam | `pickupSpawned` evita duplo spawn; `HasModelLoaded` com timeout de 10 s; **sem espera de colisão** |
| **GROUND** | local | frozen; sem gravidade relevante | cliente | — | — | despawn se status sai de `awaiting_pickup`; `partyGroundPalletFreed` re-spawna local |
| **PICKUP DETECTION** (`GetPickupCandidatePallet`, thread de 300 ms) | local | — | cliente | — | `horizontal ≤ 0,7` e `−0,08 ≤ vertical ≤ +0,18`, medidos do **osso `forks_attach`** ao pallet; prompt `HeldAction`; **tecla** | — |
| **CLAIM** (`PickupPalletWithForklift`) | local | — | **servidor (party)**; cliente (solo) | `lib.callback` | party: `mission.slots[slot]` nil, slot em `1..totalPallets`; **sem checar distância nem forklift no servidor** | claim falho → deleta o pallet local; `partyGroundPalletTaken` avisa os outros |
| **CARRY** (`AttachPalletToForklift`) | **novo** prop local | `AttachEntityToEntity(prop, forklift, forks_attach, 0,0,0.05, 0,0,0, false,false,false,false,2,true)`: `collision=false` | cliente | só o operador vê o prop; party recebe prop **decorativo** local via `ReconcileForkliftProps` (poll de 3 s) | — | `DetachPalletFromForklift` deleta; dropout limpa |
| **TRAILER** (`TryLoadPalletOnTrailer`) | o mesmo prop do carry | `DetachEntity` + `AttachEntityToEntity(trailer, bone 0, attachOffsets[slot])`, `SetEntityCollision(true)`, `SetEntityNoCollisionEntity(prop, trailer, true)` e entre props | **servidor (party)**: `loadPalletOnTrailer` | `partyPalletLoaded` + reconcile de 3 s | `state == "carried"` e `identifier == caller`; alvo online; capacidade `GetActiveMaxPallets`; `trailerSlot = loaded + 1`; "trailer cheio" | solo: contagem **no cliente** |
| **DELIVERY** (`CompleteTrip`) | — | — | servidor | broadcast de progresso | entrega só conta `state == "loaded"` e `ownerIdentifier == caller`; `clientReportedCount` **só é logado** | — |
| **CLEANUP** | — | — | — | — | — | `ResetMissionCargo`, `onResourceStop`; `OnPlayerUnload → HandleMemberDropout` devolve slots `carried`/`loaded` ao chão |

**Fato de configuração:** no `config/shared.lua` entregue, os trailers vêm com `renderLoadedPallets = false` e `attachOffsets` comentados. **Por padrão o Polarix nem renderiza o pallet no trailer**; o pallet carregado é deletado ao "carregar". O attach no trailer é opcional e depende de calibração do operador do servidor.

### 4.2 Perguntas pedidas

- **Pallet de chão é local ou networked?** Local, criado em cada cliente.
- **Frozen? Collision?** Frozen, colisão ligada.
- **Posicionamento:** `PlaceObjectOnGroundProperly`; nenhuma espera por colisão carregada.
- **Detecção pelos garfos:** distância ao osso, não por física: horizontal ≤ 0,7 m, vertical −0,08 … +0,18 m.
- **O mesmo entity vai para os garfos? NÃO.** Há *representation swap* completo.
- **O servidor controla slot lógico?** Sim, só em party (`slots[i] = {state, identifier|ownerIdentifier, trailerSlot}`). No solo, a verdade é do cliente.
- **Como evita duas pessoas pegarem o mesmo pallet:** claim server-side por slot nil; quem perde o claim deleta o próprio prop local. O servidor é single-threaded por script, então `if mission.slots[i]` seguido de atribuição funciona como CAS.
- **Como observadores veem pallets carregados:** reconstrução decorativa local por polling de 3 s (`getPartyCargoState`), tanto no garfo quanto no trailer. **Jogadores fora da party não veem nada.**
- **Reconnect/dropout:** `HandleMemberDropout` libera slots; `partyGroundPalletFreed` re-spawna. **Não há TTL/lease:** se o cliente do carregador reinicia o script ou ele sai do forklift sem desconectar, o slot fica `carried` até o `OnPlayerUnload` **[inferência: não vi timeout no código lido]**.

### 4.3 Por que o swap resolve o problema de Havok (explicação técnica)

1. **O objeto de chão nunca sai do estado frozen.** Um objeto frozen não integra física; não há como afundar, tunelar ou ser empurrado. O sinking do AUST aparece quando o objeto está `Dynamic` e a malha de colisão sob ele não está carregada ou não é a esperada.
2. **O objeto carregado nunca é "solto".** `AttachEntityToEntity` com `collision=false` transforma o prop em filho cinemático do forklift: sua pose é derivada da pose do osso a cada frame, sem resolver contatos. Não há restrição contra o chão ou contra os garfos para a Havok "estourar" em impulso. O catapult do AUST vem da combinação *corpo dinâmico em contato interpenetrando com a malha dos garfos*, que o Polarix nunca cria.
3. **Nenhum dos dois é networked.** Sem netId, não existe migração de dono, nem `NetworkRequestControlOfEntity`, nem blending de rede (jitter para observadores), nem entidade órfã quando o dono cai. A "verdade" que cruza a rede é um inteiro de slot e um estado no servidor, não uma pose.
4. **O servidor guarda a verdade lógica, não a física.** O que paga é `slots[i].state`. O visual é derivado e reconstruível (`getPartyCargoState` a cada 3 s), por isso reconnect e late join funcionam sem protocolo especial.

**Custo real do swap:** o pallet "salta" para os garfos sem elevação física; quem não é da party não vê a carga; e a consistência visual é eventual (até 3 s).

### 4.4 Fraquezas do Polarix (não herdar)

- Claim e load **sem validação de proximidade**: qualquer membro da party pode pedir qualquer slot de qualquer lugar.
- Modo solo: contagem de carga no cliente.
- `forklift_attach_offset` único e global; `ForkliftDropMaxHeight` morto.
- Sem espera de colisão antes de `PlaceObjectOnGroundProperly` (mitigado por ser frozen e local).
- Sem lease/TTL em `carried`.

---

## 5. Don Forklift deep dive

### 5.1 Call-flow real

| Etapa | Entity | Physics | Authority | Network | Validation | Failure |
|---|---|---|---|---|---|---|
| **SPAWN** (`init_mission_obj` → callback `forklift:server:CreateObject`) | **server-created**, networked (`CreateObjectNoOffset(hash, x,y,z, true,false,false)`) | — | servidor cria; **espera o dono virar o player** (`repeat Wait(100) until NetworkGetEntityOwner(obj)==player`, **sem timeout**) | statebags `forklift:object:init/owner/warehouse`; `SetEntityIgnoreRequestControlFilter(obj,true)` | player precisa ser o usuário do warehouse mais próximo (`GlobalState['forklift:warehouse:N'] == identifier`); **falha = `DropPlayer`** | — |
| **GROUND** (`setup_mission_obj`) | networked | `NetworkUseHighPrecisionBlending(netId,true)`, `NetworkSetObjectForceStaticBlend(obj,true)`, `PlaceObjectOnGroundProperly`, `SetEntityAsMissionEntity`, `SetEntityCanBeDamaged(true)`, **`SetEntityDynamic(true)`** | cliente dono | blip + marker | `NetworkDoesEntityExistWithNetworkId` | **sem espera de colisão** |
| **PICKUP / CLAIM** | — | — | — | — | reserva do warehouse por identifier em `GlobalState`; `reserve_warehouse` valida `identifier == bridge.getidentifier(src)` e `dist < 50` | — |
| **CARRY** | o mesmo objeto | **Havok pura**, sem attach | física | `HighPrecisionBlending`/`ForceStaticBlend` para suavizar o observador | — | — |
| **TRAILER/DELIVERY** (`await_load`) | o mesmo | — | cliente decide a entrega | — | poll de 500 ms: pallet a ≤ 3,0 m do porta-malas com a porta ≥ 75% aberta; dano = `GetEntityHealth/GetEntityMaxHealth` | — |
| **REMOÇÃO** (`forklift:server:RemoveEntity`) | — | — | servidor | broadcast `RemoveEntity` | **dono do statebag deve ser o chamador, senão `DropPlayer`** | — |
| **PAGAMENTO** (`FinishMission`) | — | — | servidor | — | `identifier` bate, warehouse bate, `health ≤ 1`, timer existe. **`loads` vem do cliente e não é validado.** | — |
| **CLEANUP** | — | — | — | — | — | `onResourceStop` apaga peds/objs/vehs e zera `GlobalState`. **Não há `playerDropped` nem `SetEntityOrphanMode` [grep]** |

### 5.2 O que aprender

- **Servidor cria a entidade, define statebags de dono e valida o dono em toda remoção.** Esse é o padrão certo para o AUST (o `LockEntityNetworkOwner` do AUST faz o equivalente de rede).
- `NetworkUseHighPrecisionBlending` + `NetworkSetObjectForceStaticBlend`: pelo nome e pelo uso, suavizam a pose que o **observador** interpola (interpolação mais precisa, sem extrapolação por velocidade). **[não verificado in-game]**. O AUST não usa nenhum dos dois; são candidatos baratos para o pallet networked do AUST em D-K (Fase E5).
- Não copiar: `repeat Wait(100) until owner == player` sem timeout (trava a callback se o dono nunca migrar), pagamento por `loads` do cliente, e o fato de uma desconexão deixar o warehouse reservado **[inferência: não há handler de `playerDropped`]**.

---

## 6. Mobius (esx_forklift) deep dive

### 6.1 Call-flow real

| Etapa | Entity | Physics | Authority | Validation | Failure |
|---|---|---|---|---|---|
| **SPAWN** (`SpawnPallet`) | `ESX.Game.SpawnObject('prop_boxpile_07d')` no cliente **[o framework não está no repo; rede não verificada]** | `SetEntityAsMissionEntity`, **`PlaceObjectOnGroundProperly` imediato**, `Wait(1000)` | cliente | — | — |
| **GROUND** (thread de entrega) | idem | Havok pura | cliente | **quando `pdist < 50`: `PlaceObjectOnGroundProperly` de novo** | ver abaixo |
| **PICKUP** | — | — | cliente | `AtPallet = IsEntityAtEntity(forklift, pallet, 3,3,3, 0,1,0)`, `Lifted = IsEntityInAir(pallet)`; `PickupPallet()` é só flag | — |
| **DELIVERY** (`ValidDrop`) | — | — | cliente | `pdist ≤ 0,5`, `PickedUp`, não lifted, garfo longe, e heading (ver 6.3) | `WreckPallet` se `health/10 ≤ DamageLimit` |
| **PAGAMENTO** | — | — | **servidor aceita qualquer `amount`** | `xPlayer.addMoney(math.floor(amount))` | — |

### 6.2 O comentário sobre colisão não carregada

Em `StartDeliveryThread`:

```lua
-- If pallet is far from player, collisions might not be loaded so it'll fall through floor
PlaceObjectOnGroundProperly(Player.Pallet.Entity)   -- executado quando pdist < 50
```

É a única referência que **diz em palavras** o modo de falha que o AUST sofreu: objeto spawnado longe do jogador, colisão do mapa ainda não carregada, objeto dinâmico cai pelo chão. O remédio do ESX é **temporal**: repetir o ground placement quando o jogador chega perto.

**Comparação direta com o AUST:**

| | ESX | AUST |
|---|---|---|
| Quem spawna | cliente, perto de onde pretende usar | **servidor** (`CreateObject` em `z + 0.15`), longe de qualquer colisão carregada |
| Quando reposiciona | de novo a < 50 m | `RequestCollisionAtCoord` + `HasCollisionLoadedAroundEntity` (timeout 3,5 s) + `Wait(200)` + raycast, no sync do cliente **do dono** |
| Remédio extra | nenhum | `FreezeEntityPosition(true)` no servidor e no cliente (J2) |

O servidor freezar o objeto em `z + 0.15` faz o pallet **flutuar 15 cm** se o cliente nunca rodar o snap, mas **não afunda**. O afundamento do AUST só pôde ocorrer enquanto o pallet esteve `Dynamic` (versão anterior a `909d17c`) ou na janela de engage. Isso é coerente com o diagnóstico da Fase 1, mas **a causa raiz continua sem confirmação in-game**.

### 6.3 Bug no `ValidDrop` do Mobius (leitura do código)

```lua
local angle = math.abs(Zones.Drop.Heading - Player.Pallet.Heading)
if angle < offset or angle - 180 < offset then correctAngle = true end   -- offset = 1.0
```

`angle - 180 < 1` é verdadeiro para qualquer `angle < 181`; a validação de heading efetivamente **só rejeita ângulos > 181**. Lição para o AUST: use diferença angular modular (`((a-b+540)%360)-180`).

### 6.4 `GetEntityBounds`

Usa `GetModelDimensions` para desenhar a caixa de entrega. No AUST isso corresponde à telemetria `minDim/maxDim` do `/palletdebug` e à futura derivação de limiares a partir do modelo (seção 15).

---

## 7. xDope deep dive

- **`Dynamic true` / `Freeze false`:** em `ZrespPaczuszke`, para cada tipo de carga:
  `CreateObject(prop_boxpile_*, x, y, z-0.95, true,true,true)` → `SetEntityAsMissionEntity` → `SetEntityDynamic(true)` → `FreezeEntityPosition(false)`.
- **Props soltos:** `paczuszka` é uma única variável global; a entrega é `Vdist ≤ 2,0` a um marker fixo 6 m atrás do caminhão NPC, num laço de `Citizen.Wait(2)`; `DeleteEntity(paczuszka)`.
- **Riscos dessa abordagem:**
  1. `z - 0.95` hardcoded: depende de o spawn ser no solo exato; qualquer mudança de mapa quebra.
  2. Objeto networked criado por cliente, sem dono travado, sem orphan mode: se o jogador cai, o objeto fica órfão **[inferência]**.
  3. Pagamento: `TriggerServerEvent("tostdostawa:wykonanieMisji", premia)` com **valor decidido pelo cliente**.
  4. Laços de 2–4 ms permanentes.
- **Server:** só ownership de hangar por `source` (limpo no `playerDropped`). Nenhuma validação de carga.
- **Não copiar:** tudo, exceto talvez a ideia do bônus por tempo (calculado **no servidor**).

---

## 8. AUST current architecture

### 8.1 Fluxo atual (leitura do código em `e5ce6cc`)

```
SERVER spawn (CreateObject networked, z+0.15, Freeze, LockEntityNetworkOwner, CanMigrate)
 → polarixSyncPallets (client dono, idempotente via PalletSyncGuard)
     WaitForNetworkEntity → RequestCollisionAtCoord → raycast → finalRestZ = groundZ+|minDim.z|+0.02
     → frozen / non-dynamic / no-gravity  (J2 909d17c)
 → StartOperation loop (150 ms; 0 ms perto do slot)
     STAGED_FROZEN
       ↓ isEngaged (relP.x ≤ 1.3, 0.1 ≤ relP.y ≤ 3.5, |relP.z| ≤ 0.9)   [mesma caixa que o Polarix NÃO usa]
     GROUND_ENGAGED  (FreezeEntityPosition(false), Dynamic(true), Gravity(false), ActivatePhysics)
       ↓ zLift = pallet.z − PalletBaseZ ≥ 0.35 (hardcoded)
     ATTACHED_TO_FORKS  (velocity 0, Dynamic(false), Attach no forkBone, offset (0, 0.95, −0.05) hardcoded)
       ↓ perto do slot (dist3D ≤ 1.20, heading ≤ 35°, |Δz| ≤ 0.45, z−slot.z ≤ 0.15)
     detached_at_ghost (Detach + Freeze(true))
       ↓ garfos ≥ 1.80 m do pallet + Wait(300)
     STOWED  (SnapPalletToCurrentSlot: bone 0, offset do slot ou PropEditor, collision false)
       → TriggerServerEvent polarixPalletLoaded(jobId, slot, pNetId, off, head)
```

### 8.2 Problemas verificáveis no código

1. **`PalletPhysState` é uma tabela local da thread.** Reiniciar `StartOperation` (ou `CleanupCurrentJob` seguido de novo job) zera o estado; um pallet que estava `attached_to_forks` volta a ser tratado como `frozen`.
2. **O servidor não conhece `CARRIED`.** Pickup, attach e detach nos garfos são 100% locais. O servidor só vê `polarixPalletLoaded` no stow. Se o operador cai com o pallet nos garfos, **nenhum estado é recuperado**.
3. **Fallback de osso frágil:** `'forks'` → `'forks_attach'` → `ForkBoneIndex or 3` (índice mágico). Se os nomes falharem, o attach usa o osso 3 sem log.
4. **Offsets de garfo ignoram a config e o PropEditor:** `Config.Polarix.Forklift.AttachOffset = {0, 1.2, −0.42}` existe, mas o attach usa `(0.0, 0.95, −0.05)` literal. O PropEditor (`d8f530e`) só é consultado no snap do **trailer** (`SnapPalletToCurrentSlot`).
5. **`GetNearestGroundPallet` varre `GetClosestObjectOfType` por 6 modelos**, incluindo objetos que não são da missão: só dá dica de UI, mas é superfície de confusão.
6. **Amostragem de 150 ms** durante o engage. Qualquer limiar de elevação decidido dentro do loop herda esse período; para D-K a amostragem precisa cair para ≤ 50 ms só enquanto os garfos estiverem alinhados.
7. **`SetEntityNoCollisionEntity` com semânticas misturadas:** `false` uma vez (trailer, truck), `true` por frame durante 4 s (forklift). O Polarix usa `true` uma vez. Os três usos não são consistentes entre si **[semântica do 3º parâmetro: não verificado in-game]**.
8. Telemetria e registry do PR #9 já cobrem: `usedPallets`, `slotPallets`, idempotência de `palletLoaded`, validação de spawns, distância pallet↔trailer.

---

## 9. Commit evolution (J2KGOD, 2026-10-04)

| Hora | Commit | Mudança no fluxo | Observação |
|---|---|---|---|
| 02:35 | `91c8806` | pallet dinâmico para forklift | ponto de partida (A) |
| 03:11–03:40 | `cf6529c`…`a751832` | anti-limbo, jobId, guard, thread por pallet | saneamento de spawn |
| **03:49** | **`909d17c`** | **staging congelado**; rest Z = `groundZ + |minDim.z| + 0.02`; **descongela ao engatar** (`isEngagedWithForks`); detecção `zLift ≥ 0.10`; recongela parado perto do chão (`<0.08`, `vel<0.15`) | remove o anti-limbo de 6 s; a `PalletBaseZ` nasce do 1º `GetEntityCoords` |
| 04:00 | `caaf127` | descongela **só se há input de elevação** (controles 60/62) | exige o jogador levantar o mastro |
| **04:12** | **`41efab6`** | **remove o gate de input**; descongela no toque, "para não atuar como parede sólida contra os garfos"; gravidade **off** no chão, **on** a `zLift ≥ 0.08` | **prova que o frozen bloqueia os garfos** |
| 04:23 | `0f2c831` | estados por pallet (`frozen`/`ground_engaged`/`lifted`); clamp de velocidade vertical negativa | evita reaplicar natives a cada tick ("Reliable network event overflow") |
| **05:40** | **`ecd55f0`** | **attach nos garfos a `zLift ≥ 0.35`** (osso real, offset literal); detach perto do holograma + Freeze; `GATILHO ATÔMICO`; tolerância de slot 1,10 → 1,20; espera 500 → 300 ms | cria `attached_to_forks`/`detached_at_ghost`/`stowed` |
| 06:30 | `d8f530e` | PropEditor 6DoF + `GetVehiclePropOffset` | só usado no trailer |

**Leitura da trajetória:** cada commit trata a consequência do anterior (frozen bloqueia garfos → descongela; descongelado afunda → gravidade off; gravidade off não sustenta → gravidade on a 0,08; on a 0,08 tranca → attach a 0,35). **O desenho está andando em círculo dentro da janela Havok.** Três commits em 23 minutos (04:00–04:23) e um quarto às 05:40 alteraram o mesmo bloco `if isEngagedWithForks`.

---

## 10. Physics comparison

| | AUST | POLARIX | DON | MOBIUS | XDOPE |
|---|---|---|---|---|---|
| freeze ground | **sim** (server + client) | **sim** (local) | não | não | não (`Freeze(false)`) |
| dynamic ground | não → **sim ao engatar** | não | sim | sim (padrão) | sim |
| gravity | **off** no chão/engage; (on a 0,08 em `41efab6`, retirado depois) | n/a (frozen) | padrão | padrão | padrão |
| attach carry | sim, a ≥ 0,35 m | sim, no instante do pickup | não | não | não |
| same entity | **sim** | **não** | sim | sim | sim |
| representation swap | não | **sim** | não | não | não |
| server claim | só no stow (`polarixPalletLoaded`) | **sim no pickup (party)** | não por pallet (reserva de warehouse) | não | não (posse do hangar) |
| statebag | sim (trailer: `loadedSlots`, `loadedForklift`) | não (eventos + callback poll) | **sim** (dono/warehouse) | não | não |
| owner control | `LockEntityNetworkOwner`, `CanMigrate(false)`, `NetworkRequestControl` | n/a (local) | espera `owner == player`; `IgnoreRequestControlFilter` | nenhum | nenhum |
| bounds | `GetModelDimensions` (rest Z), debug `minDim/maxDim` | não | só `ClearAreaOfObjects` por raio de dims | **sim** (caixa de entrega) | não |
| collision readiness | `RequestCollisionAtCoord` + `HasCollisionLoadedAroundEntity` (3,5 s) | não | não | **re-place a < 50 m** | não |

**Natives pedidas, e como cada repositório as usa**

- `FreezeEntityPosition`: AUST e Polarix para estabilidade; Don/ESX/xDope só em peds/xDope `false`.
- `SetEntityDynamic`: AUST alterna; Don/xDope `true`; Polarix nunca no pallet.
- `SetEntityHasGravity`: só AUST mexe, por tentativa (on/off em 4 commits).
- `ActivatePhysics`: só AUST, ao descongelar.
- `AttachEntityToEntity`: Polarix e AUST; `collision=false` nos dois.
- `SetEntityNoCollisionEntity`: Polarix (forklift↔trailer, prop↔trailer, prop↔prop); AUST (pallet↔trailer/truck/forklift).
- `PlaceObjectOnGroundProperly`: todos, menos o AUST principal (que usa raycast + bounds, com fallback).
- `GetModelDimensions`: AUST (rest Z) e Mobius (caixa).
- `IsEntityInAir`: só Mobius, como "lifted".
- `GetEntityVelocity`: AUST (clamp vertical e re-freeze), nenhum dos outros.

---

## 11. Networking comparison

| Aspecto | AUST | Polarix | Don | Mobius | xDope |
|---|---|---|---|---|---|
| Quem cria | servidor | cada cliente | servidor | cliente | cliente |
| Rede do pallet de chão | networked, dono travado | **local** | networked, dono = motorista | networked? | networked |
| Pallet carregado | **o mesmo networked** | **prop local novo** | o mesmo | o mesmo | o mesmo |
| Observadores | nativo (OneSync) | **decorativo por polling** (só party) | nativo + blending de precisão | nativo | nativo |
| Dono órfão | não tratado explicitamente | n/a | não tratado | não tratado | não tratado |
| Estado lógico que cruza a rede | statebag do trailer + `polarixPalletLoaded` | `slots[i].state` no servidor | statebags de dono/warehouse | nenhum | hangar por `source` |

### Cenários (A = operador, B = observador, C = late join)

| Cenário | Mesma entidade networked (AUST/D-K) | Swap local (Polarix) |
|---|---|---|
| **Stream out/in de B** | a pose vem da rede; attach replicado pelo OneSync **[não verificado]** | B recria o prop decorativo no próximo reconcile (até 3 s) |
| **Owner migration** | `CanMigrate(false)` + dono travado; risco só se o dono cair | n/a |
| **Disconnect de A** | pallet attached ao forklift pode ficar órfão ou ser limpo conforme o *orphan mode*, que **o AUST não define [não verificado]**; sem estado `CARRIED` no servidor, **não há recuperação** | `HandleMemberDropout` devolve o slot ao chão |
| **Reconnect de A** | sem estado `CARRIED` persistido, A volta sem carga e o pallet no mundo pode estar duplicado ou perdido | servidor devolveu o slot; novo spawn local |
| **Late join de C** | vê o pallet pela rede (se streamed) e o `loadedSlots` do trailer | reconcile reconstrói; só party |
| **Resource restart** | `onResourceStop` do forklift limpa o ghost; pallets servidor-criados dependem do cleanup do servidor | tudo local some; slots no servidor persistem até dropout |
| **Pallet no garfo quando o dono muda** | attach já existe; mudar dono de entidade attached é o cenário menos testado em OneSync **[não verificado]** | n/a |

---

## 12. Server authority comparison

| | AUST (PR #9) | Polarix (party) | Don | Mobius | xDope |
|---|---|---|---|---|---|
| ID lógico do pallet | `netId` + slot | índice de slot | netId + statebag | nenhum | nenhum |
| Estado | contagem + stage do lobby; `usedPallets`, `slotPallets` | `free/carried/loaded/delivered` | dono e warehouse | nenhum | hangar por `source` |
| Claim no pickup | **não** | **sim** | não | não | não |
| CAS | retry detectado em `Evaluate/Commit` | slot nil | `GlobalState` por identifier | — | — |
| Proximidade | pallet↔trailer ≤ 60 m | **não** | player↔warehouse ≤ 50 m | — | — |
| Recuperação em queda | nenhuma | **dropout devolve slots** | nenhuma | — | limpa hangar |
| Pagamento | server por contagem validada | server por slots `loaded` | cliente informa `loads` | cliente informa valor | cliente informa valor |

**Estados propostos:** `STAGED → CLAIMED → CARRIED → STOWED → DELIVERED`, mais `RECOVERY`.
Registro: `palletId, jobId, sourceSlot, state, carrier, trailerNetId, trailerSlot, version`.

| Operação | Pré-condição (CAS) | Efeito | Idempotência |
|---|---|---|---|
| `claim` | `STAGED`, forklift é do motorista, ped ≤ X do pallet | `CLAIMED`, `carrier = src`, `version+1` | `reqId`; repetir devolve `CLAIMED` do mesmo carrier |
| `confirmCarry` | `CLAIMED` e `carrier == src` | `CARRIED` | idem |
| `release` (voluntário) | `CLAIMED/CARRIED` e `carrier == src` | `STAGED` no slot de origem | idem |
| `stow` | `CARRIED`, `carrier == src`, trailer do lobby, slot livre, pallet↔trailer ≤ X | `STOWED`, `trailerSlot` | `reqId`; retry reconhecido (já existe no `Evaluate`) |
| `deliver` | todos `STOWED` do job | `DELIVERED` | só uma vez |
| `playerDropped`/forklift destruído | `CLAIMED/CARRIED` de `src` | `RECOVERY` → respawn em `sourceSlot` → `STAGED` | idempotente por `version` |
| **lease** | `CLAIMED` sem `confirmCarry` em N s | volta a `STAGED` | evita o slot preso que o Polarix tem |

---

## 13. Representation strategy

**OPTION A: mesma entidade networked** (`STAGED_FROZEN → CLAIMED → ATTACHED_TO_FORKS`).
**OPTION B: representation swap** (`GROUND → CLAIM → DELETE/HIDE → CARRIED PROP → ATTACH`).

| | A (mesma entidade) | B (swap) |
|---|---|---|
| Churn de netId | nenhum | cada pickup deleta e cria uma entidade networked: re-liga `usedPallets`, statebags, registry |
| Dependências atuais do AUST | `usedPallets[netId]`, `slotPallets`, `palletLoaded(netId)`, `loadedSlots` | todas precisam migrar de netId para `palletId` lógico |
| Observador | nativo | exige reconstrução (statebag/evento) |
| Anti-sink | depende de o pallet ficar frozen no chão | idem; o swap **não** protege o objeto de chão do problema de colisão |
| Complexidade | baixa | alta |

**A vantagem do swap do Polarix vem de ela ser local nos dois lados.** Se o chão fosse networked (como no AUST), o swap só adicionaria churn. Para reproduzir o benefício do Polarix de verdade seria preciso **localizar também os pallets de chão** (cada cliente cria o seu perto de si, com colisão carregada), o que é uma mudança de arquitetura maior (seção 16, fase E6, condicional).

**Decisão:** **Opção A** agora. Swap só se, depois do D-K, a telemetria mostrar flicker para observadores ou sink persistente no chão.

---

## 14. Model A/B/C/D comparison

D foi dividido em dois, porque o D que o AUST vive hoje e o que eu proponho são coisas diferentes:

- **D (Havok-assistido):** sobe fisicamente e faz attach cedo (o AUST de hoje com limiar menor).
- **D-K (cinemático):** o pallet fica frozen; a elevação é lida no osso dos garfos.

| Critério | A Havok puro | B Attach direto | C Swap | D Havok-assistido | **D-K** |
|---|---|---|---|---|---|
| Realismo | 10 | 4 | 5 | 8 | 8 |
| Estabilidade | 3 | 9 | 10 | 6 | 8 |
| OneSync | 4 | 8 | 9 | 5 | 8 |
| Multiplayer | 5 | 8 | 6 (8 com reconstrução) | 6 | 8 |
| Performance | 5 | 9 | 8 | 7 | 8 |
| Anti-desync | 3 | 8 | 8 | 5 | 7 |
| Anti-exploit | 4 | 6 | 8 | 6 | 7 |
| Streaming | 4 | 8 | 6 | 5 | 7 |
| Reconnect | 4 | 7 | 8 | 5 | 7 |
| Complexidade (10 = simples) | 6 | 9 | 4 | 6 | 6 |
| Manutenção | 4 | 8 | 5 | 5 | 7 |
| **Média** | **4,7** | **7,6** | **7,0** | **5,8** | **7,4** |

Notas = julgamento a partir do código lido, **sem pesos** e sem medição.

### Tensões internas e decisão final

1. **B vence D-K na média (7,6 contra 7,4).** O que separa os dois é só *realismo* (4 contra 8) e *multiplayer*. Se o produto não precisar da sensação de elevação, B é a escolha de engenharia mais simples. Você pediu explicitamente preservar a sensação física, então a decisão é D-K. **Isso é decisão de produto, não conclusão técnica.**
2. **Frozen bloqueia os garfos (`41efab6`) versus D-K, que exige frozen.** Resolução: durante a aproximação, `SetEntityNoCollisionEntity(pallet, forklift)` entre os dois, mantendo a colisão do pallet com o mundo. Custo: os garfos atravessam visualmente o pallet. **Risco não testado**, pois a semântica do 3º parâmetro da native é inconsistente entre as bases de código.
3. **Polarix mostra que o swap funciona, mas só porque o chão é local.** Aplicar o swap ao AUST sem localizar o chão seria churn sem ganho (seção 13).

---

## 15. Recommended architecture

### 15.1 Fluxo

```
STAGED_FROZEN            (pallet frozen; sem colisão pallet↔forklift)
  ↓ FORKS_ALIGNED        (X, heading, inserção Y, janela de Z)
  ↓ FORKS_ENGAGED        (velocidade do forklift baixa; servidor: CLAIM com distância e dono do forklift)
  ↓ LIFT_INTENT          (osso dos garfos subiu ≥ limiar, N ticks)
  ↓ ASSISTED_ATTACH      (zero velocity; Dynamic=false; Gravity=false; controle de rede; attach no osso real;
                          pose relativa PRESERVADA e interpolada até o perfil calibrado)
  ↓ CARRIED              (servidor: CARRIED)
  ↓ TRAILER_SLOT_VALID   (distância, heading, slot livre; servidor valida)
  ↓ STOWED               (servidor: STOWED)
```

### 15.2 A medida: elevação do osso, não do pallet

```
liftDelta = boneLocalZ(now) − boneLocalZ(rest)       -- no referencial do forklift
```

`boneLocalZ` = `GetOffsetFromEntityGivenWorldCoords(forklift, GetWorldPositionOfEntityBone(forklift, bone))`.
Vantagens sobre `pallet.z − PalletBaseZ` (o que existe hoje): é **imune a rampa, inclinação e suspensão** (referencial do veículo) e **não depende de o pallet estar dinâmico**. O `rest` é amostrado com o mastro baixo (e recalibrável pelo PropEditor).

### 15.3 Limiares: justificativa

Critérios que um limiar precisa cumprir:

1. **Acima do ruído de leitura.** Fontes: amostragem de 150 ms do loop atual; oscilação de suspensão ao frear; imprecisão de bone world-position. Medido em referencial local, o ruído cai, mas não sei o valor do ruído do modelo `forklift` sem telemetria. **A Fase E1 mede esse σ**.
2. **Garantir que os garfos realmente passaram a carregar o pallet**, ou seja, que há folga entre pallet e chão. Depende de `minDim.z` do pallet e da espessura dos dentes (**não medidos aqui**).
3. **Snap visível**: é função da *pose relativa* no instante do attach. Se o attach **preserva a transformada relativa** (`GetOffsetFromEntityGivenWorldCoords(boneOwner, palletCoords)` no instante) e depois interpola para o perfil calibrado em ~200 ms, **o snap visual é zero para qualquer limiar**. Isso desacopla "quando anexar" de "quanto vai pular".
4. **Risco de catapult**: em D-K a Havok **nunca** carrega o pallet, então o limiar não afeta catapult. No modelo Havok atual, o risco cresce com o tempo em que o pallet fica dinâmico, que é `limiar / velocidade de elevação`.

| Limiar | Veredito, pelos critérios acima |
|---|---|
| **0,05 m** | Válido **só** se a medida for no osso, em referencial local, e a telemetria E1 mostrar σ < ~1 cm; sob leitura de Z do pallet é indistinguível de ruído |
| **0,08 m** | **Recomendado como padrão**: 8 cm de folga ≥ qualquer espessura plausível de dente + `0.02` de margem de repouso já usado no `finalRestZ`; com histerese e *dwell* é robusto a ruído |
| **0,10 m** | Fallback se o 0,08 gerar falso positivo em rampa; sem diferença de segurança relevante em D-K |
| **0,15 m** | Sem ganho técnico; com Havok, 15 cm de pallet solto sobre dentes é tempo demais de física sem ganho de detecção |
| **0,35 m (atual)** | **Sem justificativa técnica rastreável:** a constante `MaxLiftTolerance` não é usada, o commit só cita "Decisão A1". Em D-K, 35 cm de elevação com o pallet frozen no chão faria os garfos subirem **sem** carga por 35 cm: ruim para o gameplay |

**Parâmetros recomendados (todos em `Config`, nenhum hardcoded):**
`LiftThreshold = 0.08`, `LiftHysteresis = 0.03`, `LiftDwellMs = 150` (3 ticks a 50 ms), `MaxForkliftSpeed = 1.5`, `MinInsertDepthRatio = 0.6` (calcular de `GetModelDimensions`, **a calibrar**), `BlendMs = 200`.

### 15.4 ForkliftAttachProfile (PropEditor, separado do trailer)

```lua
-- chave: {forkliftModel, palletModel}. NUNCA reutilizar as tabelas de trailer.
ForkliftAttachProfile[forkliftModel][palletModel] = {
    bone  = 'forks',          -- nome; falhar com log se não existir (sem índice mágico)
    x = 0.0, y = 0.0, z = 0.0,
    pitch = 0.0, roll = 0.0, yaw = 0.0,
    liftThreshold = 0.08,     -- opcional, por combinação
    insertDepthRatio = 0.6,   -- opcional
}
-- separado de:
TrailerSlotProfile[trailerModel][palletModel][slot] = { x,y,z, pitch,roll,yaw }   -- bone 0
```

Hoje `Config.VehiclePropOffsets[veh][prop]` (do `GetVehiclePropOffset`) não distingue *tipo* nem *osso*: um offset de garfo e um de slot de trailer compartilhariam o mesmo formato. Recomendo acrescentar `kind = 'fork' | 'trailer_slot'` e `bone`, e **recusar** (log + notificação de debug) quando não houver perfil em vez de cair em `(0, 0.95, −0.05)`.

### 15.5 Rede

- **Opção A (uma entidade networked)** com dono já travado no motorista.
- Aplicar **uma vez** `NetworkUseHighPrecisionBlending` e `NetworkSetObjectForceStaticBlend` (padrão do Don) no pallet; **medir** se melhora o observador.
- Definir **orphan mode** explicitamente para a recuperação de dropout **[a testar]**.
- Reconcile do **estado lógico**: no `playerDropped`/forklift destruído, o servidor muda para `RECOVERY`, deleta o pallet órfão e re-spawna no `sourceSlot`.

---

## 16. Migration plan (NÃO iniciado)

Pré-requisitos: PR #9 mergeado; teste humano com as 7 respostas do roteiro `docs/PALLET_DEBUG_TESTE_HUMANO.md`.

| Fase | Conteúdo | Muda física? | Risco |
|---|---|---|---|
| **E0** | Congelar `forklift.lua` entre J2 e este plano (um dono só); mergear PR #9 | não | baixo |
| **E1** | Telemetria nova: `liftDelta`, σ do osso, `relP` do pallet, estado, nº de ticks | não | baixo |
| **E2** | Servidor: estados `CLAIMED/CARRIED/RECOVERY`, `claim`, `confirmCarry`, `release`, `reqId`, lease, dropout | não | médio |
| **E3** | Cliente: máquina `FORKS_ALIGNED → FORKS_ENGAGED → LIFT_INTENT → ASSISTED_ATTACH`, pallet frozen, `NoCollision` pallet↔forklift, limiares em `Config` | **sim** | **alto** |
| **E4** | `ForkliftAttachProfile` no PropEditor e em `GetVehiclePropOffset` (`kind`, `bone`) | não | médio |
| **E5** | Blending de precisão e orphan mode | rede | baixo |
| **E6 (condicional)** | Localizar o pallet de chão (cada cliente cria o seu) **se** o sink persistir | sim | alto |

**MIGRATION COMPLEXITY: MEDIUM** (E3 sozinho é HIGH; as outras são LOW/MEDIUM).

---

## 17. Risks

1. **Hipótese do modelo:** os três repositórios legados usam `prop_boxpile_*`; o Polarix traz o próprio `sm3d_prop_pallet_1` (`stream/`). O AUST usa `hei_prop_carrier_cargo_04b`. **Não sei** se esse modelo tem vão para os garfos; `/palletdebug` imprime `minDim/maxDim` mas **não** a geometria interna. Proibido trocar o modelo agora, mas é a hipótese mais forte para o "parede sólida" do J2. **[não confirmada]**
2. **`SetEntityNoCollisionEntity` entre pallet e forklift pode não ser suficiente**, ou depender da semântica do 3º parâmetro.
3. **Attach de entidade networked** a veículo em outro cliente (observador) pode atrasar ou piscar **[não verificado]**.
4. **Ossos:** `'forks'`/`'forks_attach'` precisam existir no modelo usado; o fallback por índice é frágil.
5. **A matriz é julgamento**, não medição.
6. **Concorrência com o J2:** ele continua editando `forklift.lua`; este estudo assume `e5ce6cc`.
7. **Causa raiz do afundamento original ainda não confirmada in-game** (telemetria do PR #9 pendente).

---

## 18. Test plan

**Automático (lupa/mocks):** transições do servidor (`claim/confirmCarry/release/stow/deliver/RECOVERY`), CAS por `version`, idempotência de `reqId`, lease, dropout; máquina do cliente com sequência de `liftDelta` simulada (limiar, histerese, *dwell*, rampa); regressão do registry atual (59 casos).

**Humano (FiveM), uma sessão com `Config.Debug = true`:**

1. Pallet parado 60 s: sem queda (`FALLING`/`FIRST_DROP_AT_t` ausentes).
2. Garfos inseridos sem subir: pallet segue imóvel; **os garfos entram sem bater** (valida o `NoCollision`).
3. Subir 5/8/12 cm: attach no limiar, sem tranco (comparar `/palletdebug`).
4. Subir e descer antes do limiar: nenhum attach.
5. Rampa e piso inclinado: sem falso positivo.
6. **Medir σ de `liftDelta`** com o forklift parado e andando.
7. Trailer: stow no slot; heading/offset; progresso conta **uma** vez (repetir o evento).
8. `claim` duplicado de outro jogador: rejeitado.

## 19. Multiplayer QA

| # | Teste | Esperado |
|---|---|---|
| 1 | B observa A erguendo | pallet sobe com os garfos, sem flicker |
| 2 | C entra depois, com A carregando | C vê o pallet no garfo |
| 3 | A desconecta com pallet nos garfos | servidor → `RECOVERY`; pallet volta ao `sourceSlot`, sem duplicata |
| 4 | A reconecta no meio | A recomeça sem carga; pallet no chão |
| 5 | Stream out/in de B a 300 m | pallet reaparece anexado |
| 6 | Dois jogadores tentam o mesmo pallet | um `claim` aceito, o outro rejeitado |
| 7 | Forklift destruído com carga | `RECOVERY`, sem pallet órfão no mundo |
| 8 | Resource restart (cliente e servidor) | sem entidades duplicadas; estado coerente |
| 9 | Owner migration forçada | pallet permanece anexado |
| 10 | Replay do evento `stow` | progresso não duplica |

---

## 20. Final recommendation

- **Adotar D-K com Opção A**, em fases, com E1 e E2 antes de qualquer mudança de física.
- **Não escolher valor de limiar sem telemetria:** o padrão proposto (0,08 m, osso local, histerese 0,03, dwell 150 ms) é ponto de partida a validar com o σ medido em E1.
- **Parar de mexer no mesmo `if` de `forklift.lua`.** Os quatro commits de 04:00–05:40 foram tentativas dentro da janela Havok; o estudo mostra que o caminho é eliminar a janela.
- **Não trocar modelo, não mexer em economia/inventário, não remover módulos legados** nesta fase.
- Se o teste humano mostrar que **o pallet já afunda parado e frozen**, a hipótese de colisão/modelo passa a ser a prioridade e E6 (pallet de chão local, como Polarix) entra no plano.

---

### Checkpoint

**REFERENCE STUDY STATUS:** COMPLETE (leitura de código); sem validação in-game.
**BEST REFERENCE:** Polarix (arquitetura); Don (ownership/statebag); Mobius (colisão a distância).
**BEST GROUND STRATEGY:** pallet frozen, posicionado com colisão carregada (Polarix + ESX).
**BEST PICKUP STRATEGY:** alinhamento geométrico no osso dos garfos + claim no servidor (Polarix), com validação de distância que o Polarix não faz.
**BEST CARRY STRATEGY:** attach no osso real, `collision=false`, pose relativa preservada.
**BEST TRAILER STRATEGY:** attach no bone 0 com perfil calibrado por slot; `NoCollision` com trailer e entre pallets.
**BEST NETWORK STRATEGY:** uma entidade networked (Opção A) com dono travado, blending de precisão; localização do chão só como plano E6.
**BEST SERVER AUTHORITY STRATEGY:** máquina `STAGED/CLAIMED/CARRIED/STOWED/DELIVERED/RECOVERY` com CAS por `version`, `reqId`, lease e recuperação em dropout.
**AUST CURRENT MAIN WEAKNESS:** janela Havok de 0 → 0,35 m e ausência de estado `CARRIED` no servidor.
**RECOMMENDED MODEL:** D (variante D-K).
