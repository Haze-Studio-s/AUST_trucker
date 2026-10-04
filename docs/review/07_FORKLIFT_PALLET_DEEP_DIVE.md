# 07 — Forklift / Pallet Deep Dive

**ANALYZED HEAD: `c9d9187`** (= `main` `e5ce6cc` + PR #9). Linhas citadas são do HEAD analisado.
Legenda de confiança: **CONFIRMED** (lido no código/commit), **LIKELY** (consistente com o código, sem prova de runtime), **UNKNOWN**, **RUNTIME PROOF REQUIRED** (só o FiveM decide).

---

## 1. Dois sistemas de forklift convivem

| | Sistema A: carga seca "Polarix" | Sistema B: Trade Point / indústria |
|---|---|---|
| Cliente | `client/main.lua` + `client/modules/forklift.lua` | `client/forklift.client.lua` |
| Servidor | `server/main.lua` (`HandlePalletLoaded`, `PolarixLobbies`) | `server/services/forklift_service.lua`, `server/events.lua:1144` (`aurp_trucker:palletLoaded`) |
| Quem cria o pallet | **servidor** (`CreateObject`, `server/main.lua:1037`) | **cliente** (`CreateObjectNoOffset(..., true,false,false)`, `forklift.client.lua:38`) |
| Dono lógico | `lobby.src` | statebag `forklift_owner` = `tostring(src)` |
| Pallet | frozen; `PalletRegistry` | `SetEntityDynamic(obj, true)` (`forklift.client.lua:156`), Havok pura |
| Conclusão | estiva no trailer: `polarixPalletLoaded` | pallet a ≤ `LoadDetectRadius` do porta-malas: `palletLoaded`, **servidor deleta o objeto** |
| Eventos de carga | `aurp_trucker:server:polarixPalletLoaded` (alias `attachPalletToTrailer`) | `aurp_trucker:palletLoaded` |
| Limpeza em queda | handlers genéricos de lobby | `ForkliftService.OnPlayerDropped` |

**CONFIRMED:** são fluxos independentes que reutilizam a palavra "pallet" e o módulo de rentals. O Sistema B é, em física, o modelo A do estudo (Havok pura, sem staging) e valida no servidor por statebag + modelo + distância + rate limit (`events.lua:1144-1201`); o Sistema A é o que vem sofrendo afundamento/catapulta.

### Resíduo morto entre os dois

`client/cargo_dry.lua` define `CargoDry.Setup` (linhas 34–110), que chama `ForkliftModule.SetupTrailerTarget` e `ForkliftModule.LoadPalletOntoTrailer`. **Nenhuma dessas funções existe** em `client/modules/forklift.lua` (funções definidas: `IsPlayerInForklift`, `GetPlayerForklift`, `GetCarriedPallet`, `SetMissionPallets`, `GetNearestGroundPallet`, `DeleteGhostProp`, `GetCurrentGhost`, `GetCurrentSlotIndex`, `GetSlotOffset`, `GetForkliftSlotOffset`, `GetGhostModelForSlot`, `SpawnGhostProp`, `SpawnForkliftGhost`, `SnapPalletToCurrentSlot`, `SnapForkliftToSlot`, `StartOperation`, `SafeDetachWithDistanceCheck`, `StopOperation`) e **`CargoDry.Setup` não tem chamador** (grep em `client/` e `server/`). `CargoDry.Cleanup` e `dryProgressSync` continuam ativos. **STATUS: PARTIALLY_REPLACED / LEGACY_CANDIDATE** (não "morto": o resto do arquivo é usado).

---

## 2. Pipeline atual do Sistema A (HEAD analisado)

### 2.1 Spawn (servidor)

`server/main.lua:1037` `CreateObject(pModel, coord.x, coord.y, coord.z + 0.15, true, true, false)`; depois `FreezeEntityPosition(pObj, true)`, `LockEntityNetworkOwner(pObj, src)` (`:1042`, definido em `:51`), `SetEntityDistanceCullingRadius(pObj, 0.0)` (`:1043`), `ignoreEntities[pObj] = true`. Fallback para `hei_prop_carrier_cargo_04b` se o modelo falhar (`:1050`, `:1089`). Os spawns passam por `ValidatedPalletSpawns` (`:952`, PR #9): 6 spawns do config, sem duplicata/colisão de espaçamento.

**CONFIRMED:** o servidor congela o objeto 15 cm acima da coordenada de config. Sem o snap do cliente o pallet **flutua**, não afunda.

### 2.2 Sync e snap (cliente do dono)

`client/main.lua:2670` `polarixSyncPallets`, idempotente por `PalletSyncGuard` (PR #9). Por pallet (thread): `WaitForNetworkEntity(8000)` → controle de rede → `RequestCollisionAtCoord` + `HasCollisionLoadedAroundEntity` (timeout 3,5 s) → `Wait(200)` → raycast `StartShapeTestRay(..., 1 | 16, ent, 7)` (`:2727`; flag 16 inclui objetos, não só o mapa) → `finalRestZ = groundZ + math.abs(minDim.z) + 0.02` (`:2743-2744`) → `SetEntityCollision(true,true)`, `SetEntityDynamic(false)`, `SetEntityHasGravity(false)`, `FreezeEntityPosition(true)`, `SetEntityVelocity(0)`.

**CONFIRMED:** estado de repouso é frozen e não dinâmico. **LIKELY:** `math.abs(minDim.z)` só equivale a "apoiar a base no chão" se o pivô estiver no centro vertical do modelo; se o pivô estiver na base, `|minDim.z| ≈ 0` e o pallet fica 2 cm acima; se `minDim.z` for positivo (pivô abaixo do modelo), `abs()` inverte o sinal e o pallet sobe. **RUNTIME PROOF REQUIRED** (`/palletdebug` imprime `minDim.z/maxDim.z`).

### 2.3 Operação (cliente, `ForkliftModule.StartOperation`, `forklift.lua:574`)

Laço com `sleep = 150` (`:633`, 0 perto do slot). Por pallet, estado local `PalletPhysState[p]` (**local da thread**, `:630`):

```
frozen
  └─ isEngagedWithForks (relP.x ≤ 1.3 ∧ 0.1 ≤ relP.y ≤ 3.5 ∧ |relP.z| ≤ 0.9)         :707
       → FreezeEntityPosition(false), SetEntityDynamic(true), SetEntityHasGravity(false), ActivatePhysics   :711-716
       → ground_engaged
  └─ zLift = pallet.z − PalletBaseZ ≥ 0.35                                               :721
       → SetEntityVelocity(0), Freeze(false), Dynamic(false), Gravity(false),
         AttachEntityToEntity(p, forklift, forkBone, 0.0, 0.95, -0.05, 0,0,0, ...)       :735-740
       → attached_to_forks
  └─ garfos longe e |z − base| ≤ 0.10 → re-freeze → frozen                               :751-759
attached_to_forks
  └─ perto do slot (dist3D ≤ 1.20 ∧ Δheading ≤ 35° ∧ |Δz| ≤ 0.45 ∧ z − slot.z ≤ 0.15)   :806-812
       → DetachEntity, Dynamic(false), Gravity(false), Freeze(true) → detached_at_ghost
detached_at_ghost
  └─ garfos ≥ 1.80 m e Wait(300) → SnapPalletToCurrentSlot → stowed, TriggerServerEvent polarixPalletLoaded
```

`SnapPalletToCurrentSlot` (`forklift.lua:360`): bone 0 do trailer, offset do slot **ou** do PropEditor (`GetVehiclePropOffset`, `:138`), `Freeze(false)`, `Dynamic(false)`, `Gravity(false)`, `SetEntityCollision(false,false)`, `SetEntityNoCollisionEntity` (valor `false`) com trailer, caminhão e forklift, `SetNetworkIdCanMigrate(false)`, statebag `loadedSlots` no trailer.

### 2.4 Servidor na estiva

`HandlePalletLoaded` (`server/main.lua:1429`): lobby do jogador, `cargoType == 'dry'`, `PalletRegistry.Evaluate` (netId do lobby, slot, retry), estágio, contagem, distância jogador↔trailer ≤ 40 m, rate limit 1 pallet/s, distância pallet↔trailer ≤ 60 m. **CONFIRMED (antes do PR #9, ainda na `main`):** o servidor fazia `FreezeEntityPosition(pObj, false)` em **todos** os pallets do lobby a cada estiva. No HEAD analisado isso só ocorre com `KinematicLift` desligado (`:1546`).

---

## 3. Reconstrução dos commits

### `909d17c` — 2026-10-04 03:49 — "Stabilize pallet physics and forklift loading"

| | |
|---|---|
| **WHAT CHANGED** | Cliente (`main.lua`, sync): remove a liberação dinâmica após o snap; pallet passa a ficar `Freeze(true)`, `Dynamic(false)`, `Gravity(false)`; repouso por `groundZ + |minDim.z| + 0.02`; remove o resgate "anti-limbo" de 6 s. `forklift.lua`: descongela quando `isEngagedWithForks`; `zLift ≥ 0.10`; re-congela parado a ≤ 0,08 m do chão com `vel < 0.15`. |
| **WHY** | Combater afundamento e tunelamento do pallet dinâmico na malha do MLO. |
| **PROBLEM ADDRESSED** | Pallet dinâmico afundando/tunelando no staging. |
| **NEW RISK** | Pallet frozen é obstáculo sólido contra os garfos; a caixa de engate é ampla (x 1,3 m, y até 3,5 m), então o descongelamento acontece cedo e longe; `PalletBaseZ` nasce do primeiro `GetEntityCoords` (vira "repouso" mesmo se a leitura for transitória). |
| **STILL USED** | A lógica de sync e de repouso sim. O re-freeze foi alterado depois. |

### `caaf127` — 04:00 — "Restrict forklift pallet lift release"

| | |
|---|---|
| **WHAT CHANGED** | Só descongela se há input de elevação (`IsControlPressed(0,60/62)`); re-freeze mais agressivo fora do vão. |
| **WHY** | Evitar ativar a física só por encostar. |
| **PROBLEM** | Ativação prematura de física. |
| **NEW RISK** | Dependência de controles de teclado específicos (60/62); sem input o pallet bloqueia os garfos; incompatível com teclas rebindadas. |
| **STILL USED** | **Não.** Revertido na `41efab6`. |

### `41efab6` — 04:12 — "Adjust forklift pallet lifting behavior"

| | |
|---|---|
| **WHAT CHANGED** | Remove o gate de input; descongela no toque "para não atuar como parede sólida contra os garfos" (comentário no código); gravidade **off** no chão; **on** quando `zLift ≥ 0.08`; limiar 0,10 → 0,08. |
| **WHY** | O gate de input fazia o pallet frozen impedir os garfos de entrar. |
| **PROBLEM** | Pallet frozen como parede. |
| **NEW RISK** | Reabre a janela dinâmica no chão; gravidade ligando em pleno contato com os dentes. |
| **STILL USED** | A ideia (descongelar ao engatar) sim; a gravidade on/off foi alterada na seguinte. |

**CONFIRMED:** este é o único ponto do histórico em que o próprio autor registra a causa da parede sólida. Ele é a justificativa técnica de tudo o que veio depois.

### `0f2c831` — 04:23 — "Stabilize forklift pallet physics transitions"

| | |
|---|---|
| **WHAT CHANGED** | Estados por pallet (`frozen`, `ground_engaged`, `lifted`); aplica natives só na transição; clamp da velocidade vertical `vel.z < -0.05`. |
| **WHY** | "Reliable network event overflow" por reaplicar natives todo tick. |
| **PROBLEM** | Excesso de eventos de rede por chamar `Freeze/Dynamic/Gravity/ActivatePhysics` a cada iteração. |
| **NEW RISK** | `PalletPhysState` é local da thread: reiniciar a operação perde o estado. O clamp de velocidade luta contra a Havok sem eliminar a causa. |
| **STILL USED** | A tabela de estados sim; `lifted` foi removido na `ecd55f0`. |

### `ecd55f0` — 05:40 — "Improve forklift loading and payouts"

| | |
|---|---|
| **WHAT CHANGED** | Attach nos garfos a `zLift ≥ 0.35` (osso real, offset literal `(0, 0.95, -0.05)`); `ground_engaged` com gravidade off; detach perto do holograma + `Freeze(true)`; estados `attached_to_forks`, `detached_at_ghost`, `stowed`; tolerância de slot 1,10 → 1,20; espera 500 → 300 ms. Também: `CalcBonus` e reembolso de saldo da empresa (outros arquivos). |
| **WHY** | Tirar a Havok do transporte e do trailer. |
| **PROBLEM** | Tranco/catapulta quando o pallet dinâmico é carregado até o trailer. |
| **NEW RISK** | Janela Havok 0 → 35 cm continua; **o servidor não conhece o estado "carregando"**; offset do garfo literal ignora `Config.Polarix.Forklift.AttachOffset = (0, 1.2, -0.42)` e o PropEditor; limiar 0,35 sem origem rastreável (`MaxLiftTolerance` existe em `shared/config.lua` mas nenhum código o lê). |
| **STILL USED** | **Sim, é o fluxo atual.** |

### `d8f530e` — 06:30 — "Add 6DoF PropEditor and hot reload"

| | |
|---|---|
| **WHAT CHANGED** | Novo `client/modules/offset_editor.lua` (+383 linhas), aba no admin NUI, tabela `aust_trucker_vehicle_prop_offsets`, cache `AdminService.VehiclePropOffsets`; `GetVehiclePropOffset` global + export; `SnapPalletToCurrentSlot` usa o offset calibrado com prioridade máxima. |
| **WHY** | Calibrar offsets visualmente em vez de editar config. |
| **PROBLEM** | Offsets de slot desalinhados do holograma. |
| **NEW RISK** | A chave `[veh][prop]` não distingue **tipo** (slot de trailer × garfo) nem **osso**; hoje só o trailer a consulta, mas qualquer reutilização para garfo misturaria bone 0 e bone `forks`. |
| **STILL USED** | **Sim**, apenas no snap do trailer. |

### Contexto anterior (sem análise linha a linha)
Entre `1b4dc34` (10-03 23:46) e `cf6529c` (10-04 03:11) há mais de 15 commits sobre grounding, anti-limbo e jobId (`a1d4375`, `bbc9256`, `3c6037a`, `14ded23`, `a751832`). Em `bbc9256` o servidor passou a `FreezeEntityPosition(pObj, true)` no spawn; em `14ded23` entrou um guard local que sombreava o `PalletSyncGuard` (corrigido no PR #9).

---

## 4. Temas pedidos

| Tema | Fato no código | Classe |
|---|---|---|
| **SINKING** | Pallet dinâmico + colisão do mapa não carregada afunda; o ESX documenta o mesmo modo de falha. No HEAD o pallet nasce frozen e só vira dinâmico ao engatar. | **LIKELY** (causa original); **RUNTIME PROOF REQUIRED** para o fluxo atual |
| **BOUNDING BOX** | Repouso por `math.abs(minDim.z)`; `GetModelDimensions` só usado ali e na telemetria. Sem uso de `maxDim` nem do centro do modelo. | **CONFIRMED** (uso); **UNKNOWN** (pivô do `hei_prop_carrier_cargo_04b`) |
| **FREEZE** | Servidor freeza no spawn (`:1039`); cliente freeza no repouso; engate descongela; detach no holograma freeza de novo; `SnapPalletToCurrentSlot` descongela antes do attach (nunca freezar anexado: comentário v20.8.0). | **CONFIRMED** |
| **DYNAMIC** | Liga ao engatar (`:713`); desliga no attach e no detach. | **CONFIRMED** |
| **GRAVITY** | Sempre `false` no HEAD. Nas versões `41efab6`/`0f2c831` ligava a 0,08 m. Como `SetEntityHasGravity` não tem leitura nativa, o estado real não é observável. | **CONFIRMED** (código); **UNKNOWN** (efeito) |
| **ACTIVATE PHYSICS** | Só na transição `frozen → ground_engaged` (`:715`). | **CONFIRMED** |
| **CATAPULT** | Hipótese: corpo dinâmico interpenetrando a malha dos garfos ou saindo do estado frozen em contato. Nenhuma telemetria de contato existe. | **LIKELY**; **RUNTIME PROOF REQUIRED** |
| **ZLIFT** | `pallet.z − PalletBaseZ` ≥ 0,35 (hardcoded). Não usa o osso dos garfos; `PalletBaseZ` é amostrado uma única vez. | **CONFIRMED** |
| **ATTACH TO FORKS** | `AttachEntityToEntity` no osso `forks`/`forks_attach`/índice 3, offset literal, `collision=false`. Servidor não é informado. | **CONFIRMED** |
| **TRAILER SNAP** | Bone 0, offset do slot/PropEditor, `collision=false` (`SetEntityCollision(false,false)`), statebag `loadedSlots`. | **CONFIRMED** |
| **ONESYNC** | Pallet networked, dono travado (`LockEntityNetworkOwner`, `SetNetworkIdCanMigrate(false)`); sync idempotente. Sem `NetworkUseHighPrecisionBlending`; orphan mode não definido. | **CONFIRMED** (código); comportamento **RUNTIME PROOF REQUIRED** |
| **OWNER** | Dono = motorista (`lobby.src`) travado no servidor; cliente ainda pede controle antes de mexer. | **CONFIRMED** |
| **OBSERVERS** | Observador vê a pose por rede. `Freeze` aplicado só no dono pode chegar atrasado ao observador. | **UNKNOWN**; **RUNTIME PROOF REQUIRED** |

---

## 5. Convenção do `SetEntityNoCollisionEntity`

O AUST usa as duas formas: `true` **a cada frame** em `client/main.lua:1287-1293` ("thisFrameOnly = true") e em `forklift.lua` (loop de 4 s, `Wait(0)`), e `false` **uma vez** em `SnapPalletToCurrentSlot`. O Polarix usa `true` **uma vez**. Sob a convenção do AUST (`true` = só neste frame), a chamada única do Polarix duraria um frame. **UNKNOWN** se o Polarix depende de outro efeito; **RUNTIME PROOF REQUIRED**.

---

## 6. Lacunas que importam para a decisão

1. `PalletPhysState` local; estado `CARRIED` só no cliente (**CONFIRMED**).
2. Recuperação de pallet perdido em trânsito (`client/main.lua:1236-1282`) reenvia `polarixPalletLoaded` com `#LoadedPallets` e **sem netId**; o servidor só decrementa `lostPallets` nesse caso (`HandlePalletLoaded`, ramo `STATUS_IN_TRANSIT`).
3. `ForkliftModule.SetMissionPallets({ palletEnt })` (`client/main.lua:2032`) **substitui** a lista de pallets da missão pelo pallet caído; qualquer estado por pallet que dependa da lista inteira precisa tolerar isso.
4. `StopOperation` referencia `CurrentForkliftPallet` (`forklift.lua:1021`), **que nunca é atribuído** (declarado em `:8`, lido em `:267` e `:1021`): o ramo é código inalcançável.
5. Osso: `forks` → `forks_attach` → `ForkBoneIndex = 3` (`:37-43`); sem log quando cai no índice.
6. `GetNearestGroundPallet` varre `GetClosestObjectOfType` por seis modelos (não só os da missão) para dica de UI (`:69-88`).
