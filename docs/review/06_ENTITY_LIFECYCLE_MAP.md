# 06 — Entity Lifecycle Map

**ANALYZED HEAD: `c9d9187`.** Fonte: leitura do código por uma auditoria dedicada (arquivos e faixas ao final), com conferência por amostragem de quatro achados (marcados **[VERIFICADO]**). Convenções: `sv/main` = `server/main.lua`; `cl/main` = `client/main.lua`. "NOT FOUND" = busca feita, nada encontrado. "NOT READ" = não lido.

## 0. Fatos globais

- **`LockEntityNetworkOwner`** (`sv/main:51-67`): `NetworkSetEntityOwner` (se existir) + `SetNetworkIdCanMigrate(netId, false)`, ambos em `pcall`. **Nenhum orphan mode**: `SetEntityOrphanMode` não aparece em nenhum arquivo do repositório (grep).
- **`playerDropped` que tocam entidades:** `sv/main:2414-2424` (apaga o lobby Polarix na hora), `sv/main:1716-1727` (só `PalletRegistry.Recover`), `events.lua:380-414` (grace de 3 min sobre `PlayerJobEntities`), `events.lua:1207-1244` (`ForkliftService.OnPlayerDropped`, `TruckRentalService.OnPlayerDropped`, apaga truck/trailer verificados).
- **`onResourceStop` no servidor:** só `sv/main:2427-2451`. NOT FOUND em `events.lua`, `flatbed.server.lua`, `crude_oil.lua` e nos serviços.
- **Reconnect:** NOT FOUND para qualquer entidade. Não há `playerSpawned`/`onClientResourceStart` que reconecte entidades; `ActiveJob` do cliente simplesmente se perde.
- **Stream in/out:** só os handlers de statebag `loadedSlots`/`loadedForklift` (`cl/main:3214-3270`) e `attachedVehicle` do flatbed (`flatbed.client:390-423`). O resto: NOT FOUND.

## 1. TRUCK

| Campo | Achado |
|---|---|
| CREATED BY / WHERE | **Polarix:** servidor, `CreateVehicle(model,…,true,true)` (`sv/main:772`; fallback `:791`); caminhão próprio/frota é **re-criado** pelo servidor (`:601-685`). **LC quick job:** servidor (`events.lua:1797`). **Aluguel:** cliente `CreateVehicle(…,true,false)` (`client.lua:869`, `:1780`). |
| NETWORKED / NETID | Sim. `payload.truckNetId` (`sv/main:1304`); `lobby.truck` guarda o handle. Aluguel: `Active[citizen].netId` via `RegisterNetId`. |
| MISSION ENTITY | Servidor: `netMissionEntity=true`. Cliente: só no caminhão de aluguel (`client.lua:871`, `:1782`). |
| OWNER | Polarix: `LockEntityNetworkOwner` (`sv/main:1260`). LC quick: **NOT FOUND**. Registrados: `events.lua:323`, `:349`. |
| OWNER MIGRATION | Apenas "nunca migrar". |
| STATEBAGS | `activeJobData` (`sv/main:1284`), limpo em `:2167`, `:2328`, `:2367`. **Ninguém lê** (grep). |
| FREEZE / COLLISION | `FreezeEntityPosition(truck,true)` quando parado > 5 s fora do veículo (`cl/main:1683-1688`), desfeito só no mesmo laço (`:1693`). `SetEntityNoCollisionEntity(truck,trailer,true)` (`:2608`, `:2224`). |
| DELETE | `CleanupLobbyEntities` só se `not lobby.isOwned` (`sv/main:231-233`). Caminhão próprio **nunca** é apagado pelo servidor (por desenho). LC: `events.lua:2172/2206/2493`. Aluguel: `truck_rental_service:293`, `:335`. |
| PLAYER DROP | Polarix: apagado se não-próprio. **Próprio** permanece com `activeJobData` obsoleto. |
| RECONNECT | NOT FOUND. O cancel do grace (`events.lua:305-309`) só roda se o cliente chamar `registerJobEntities` de novo. |
| RESOURCE STOP | Servidor: lobbies e `PlayerJobEntities` (sem filtro `verified`). Cliente: só `currentTrailer` (`client.lua:2681`). |
| GAPS | `CleanupCurrentJob` não desfaz o freeze do caminhão; statebag obsoleto após queda/timeout/stop; `onPlayerDeath` (`events.lua:445-451`) apaga até caminhão próprio registrado. |

## 2. TRAILER

| Campo | Achado |
|---|---|
| CREATED BY | Polarix: servidor (`sv/main:841`, fallback `:867`). Legado: cliente (`client.lua:223`) + `registerJobEntities`. |
| NETID / OWNER | `payload.trailerNetId`; `lobby.trailer`. `LockEntityNetworkOwner` (`sv/main:1261`). Cliente resolve por `WaitForNetworkEntity(netId,4000)` (`cl/main:2523`) **sem retry** após timeout. |
| STATEBAGS | `loadedSlots`: escrito pelo servidor (`sv/main:1562-1572`) **e pelo cliente** (`cl/main:790-797`, `forklift.lua:480-486`). `loadedForklift`: cliente (`cl/main:928`, `forklift.lua:560`). O servidor nunca limpa `loadedSlots`. |
| ATTACH | Pai de pallets, forklift e container. |
| DELETE | `CleanupLobbyEntities`; conclusão (`sv/main:2143`, `:2196`); cliente legado (`client.lua:2647`, `:2681`). |
| PLAYER DROP | Apagado imediatamente (`sv/main:2414-2424`). |
| GAPS | Sem retry de streaming; `safeDelete` legado só funciona se o modelo bater com o registrado. |

## 3. FORKLIFT

| Campo | Achado |
|---|---|
| CREATED BY | Polarix: servidor (`sv/main:907`, fallback `:924`). Respawn de emergência: servidor (`:2406`). Trade point/indústria: cliente (`forklift.client.lua:27`). |
| NETID | `payload.forkliftNetId`; `lobby.forklift`; `JobEntities.forklift`. Legado: `rental.forkliftNetId` via `forklift:setNetId`, enviado **só no modo TradePoint** (`forklift.client.lua:136`). |
| OWNER | Polarix: placa/chaves (`sv/main:931-946`) + `LockEntityNetworkOwner` (`:1262`). **Respawn de emergência: sem plate, chaves, lock nem `ignoreEntities`.** |
| MIGRATION | Reativada só ao tombar (`cl/main:2056`); nada reativa ao fim. |
| ATTACH | Ao trailer, bone 0, offset de `GetForkliftSlotOffset`, fallback `(0,-6.6,0.35)`; reaplicado a cada 1,5 s dirigindo (`cl/main:1818-1850`). |
| FREEZE/PHYSICS | Em trânsito: `Freeze(false)`, `Dynamic(false)`, `Gravity(false)`, `SetEntityCollision(false,false)`. Ao descarregar: `Dynamic(true)`, `Gravity(true)`, `ActivatePhysics`. |
| DELETE | `CleanupLobbyEntities`; `strappingCompleted` apaga se `withForklift == false`. **A conclusão com caminhão próprio NÃO apaga o forklift** **[VERIFICADO]** (`sv/main:2143-2166` apaga trailer, container, hose, pallets, carros e depois anula o lobby). |
| PLAYER DROP | Polarix apagado; legado TradePoint sim; **modo indústria não** (nunca registrado). |
| GAPS | Forklift e handler órfãos após conclusão com caminhão próprio; respawn não informa o novo netId ao cliente. |

## 4. PALLET

| Campo | Achado |
|---|---|
| CREATED BY | Polarix: servidor, `CreateObject(pModel,…,true,true,false)` (`sv/main:1037`, `:1050`, `:1077`, `:1089`). Legado: cliente `CreateObjectNoOffset(…,true,false,false)` (`forklift.client.lua:38`). |
| SPAWN | `FreezeEntityPosition(true)`, `LockEntityNetworkOwner`, `SetEntityDistanceCullingRadius(pObj, 0.0)`, `ignoreEntities`. |
| CLIENT APPLY | `polarixSyncPallets` (`cl/main:2670-2791`): `PalletSyncGuard`, `WaitForNetworkEntity(8000)`, controle de rede (até 2 s), `SetNetworkIdCanMigrate(false)`, snap ao chão. |
| LOGICAL STATE | `PalletRegistry` STAGED→…→RECOVERY: handlers existem (`sv/main:1620-1701`), **nenhum cliente os chama** e `KinematicLift.Enabled=false`. `MarkDelivered`/`MarkRecovered` sem chamadores. |
| STATEBAGS | `loadedSlots`; `forklift_owner`/`forklift_location` nos pallets legados (escritos pelo cliente). |
| ATTACH | Garfos: `(0.0, 0.95, -0.05)` no osso (`forklift.lua:735`). Trailer: bone 0, offset do slot/PropEditor. |
| FREEZE/PHYSICS | Frozen no staging; engate descongela; em trânsito `Dynamic(false)`, `Gravity(false)`, `SetEntityCollision(false,false)` dirigindo; em queda: detach, `Dynamic(true)`, `Gravity(true)`, impulso, `SetNetworkIdCanMigrate(true)`. Servidor descongela **todos** em `strappingCompleted` (`sv/main:1932-1938`) e no stow legado. |
| DELETE | `CleanupLobbyEntities`; conclusão; legado: servidor apaga ao contar (`events.lua:1193`). |
| PLAYER DROP | Polarix apagado; **legado não**. |
| RESOURCE STOP | Cliente varre `GetGamePool('CObject')` e apaga todo objeto com modelo rastreado (`cl/main:2979-3010`), **inclusive objetos locais de outros scripts com o mesmo modelo**. |
| STREAM IN/OUT | Statebag `loadedSlots` re-anexa para observadores; observadores não pedem controle. |
| GAPS | Registro dormente; fluxos cinemático e legado coexistem. |

## 5. CONTAINER

| Campo | Achado |
|---|---|
| CREATED BY | Polarix heavy: servidor (`sv/main:1156`). Container handler: cliente, **local não-networked** (`container_handler.client.lua:65`). |
| OWNER | Polarix: `LockEntityNetworkOwner` (`sv/main:1268`). |
| ATTACH | Ao bone do handler (`reach_stacker:34-86`); ao trailer em `(0,0,0.35)` fixo (`:158-165`), depois `FreezeEntityPosition(container,true)` **em entidade anexada** (`:169`), prática que o próprio `forklift.lua:416-418` condena para pallets. |
| DELETE | Polarix: cleanup/conclusão. Handler mission: **nunca apagado**; só `SetEntityAsNoLongerNeeded` (`container_handler:123-126`). |
| PLAYER DROP | Polarix apagado; handler mission só limpa `ContainerJobs[cid]`. |
| GAPS | Sem re-attach após stream; `heavyContainerLoaded` enviado duas vezes (`reach_stacker:179` e `cl/main:2441`). |

## 6. CAR CARRIER VEHICLES

| Campo | Achado |
|---|---|
| CREATED BY | Servidor, 3 veículos (`sv/main:1178`), chaves via `qbx_vehiclekeys` (`:1185`). |
| NETID | `lobby.carrierCars`; `vehicleNetIds` no payload. |
| CLIENT | **Nunca resolvidos de netId para entidade.** `StartLoadingOperation` compara `v == currentVeh` com netIds (`car_carrier.lua:158-160`) **[VERIFICADO]**; `main.lua:614` passa `ActiveJob.vehicleNetIds`. |
| ATTACH | Slots fixos no módulo, bone 0, `collision=false`. Rampa local `CreateObject(…,false,false,false)` (`:50`). |
| GAPS | Fluxo cliente inoperante (ver `05_GAMEPLAY_FLOW_MAP.md`); rampa local não é removida ao cancelar (nenhum `StopLoadingOperation` no cleanup). |

## 7. FLATBED BED / RAMP PROP

| Campo | Achado |
|---|---|
| CREATED BY | Servidor, `CreateObjectNoOffset(BED_MODEL,x,y,z-3,true,0,1)` (`flatbed.server.lua:89`) a partir de `entityCreated` de **qualquer** `flatbed3` do mundo (`:51-62`). O flatbed de repo é criado pelo cliente (`flatbed.client:299`). |
| STATEBAGS | `bedProp`, `attachedVehicle`, `bedLowered`, `bedMoving` — escritos também pelo **cliente** (`flatbed.client:54-101`, `:172`, `:188`). |
| OWNER | Sem lock; servidor espera ≤ 500 ms por dono comum, senão apaga o bed (`flatbed.server:101-113`). |
| DELETE | `entityRemoved`, `DeleteBedEntity`, `Flatbed.Despawn`. |
| GAPS | Prop de animação do operador sem cleanup em stop/drop (`flatbed.client:210`); lerp não retoma se o dono migrar; `entityCreated` dispara para flatbeds que não são deste recurso. |

## 8. REPO TARGET VEHICLE (+ guardas)

| Campo | Achado |
|---|---|
| CREATED BY | Cliente, `CreateVehicle(…,true,false)` (`repo.client.lua:68`); guardas `CreatePed(4,…,true,true)` (`:320`). |
| SERVER | Não guarda entidade (`repo_service.lua` sem código de entidade). |
| DELETE | `CleanupMission` (`repo.client:105-153`); alvos de missão simples/stealth **só são apagados se não entregues** (`:145-150`), ou seja, o veículo entregue permanece no mundo. |
| PLAYER DROP | NOT FOUND no servidor. |
| GAPS | `while not HasModelLoaded` e `while not DoesEntityExist` sem limite (`:66`, `:70`). |

## 9. PARCEL PROP

| Campo | Achado |
|---|---|
| CREATED BY | Cliente, `CreateObject(model,…,true,true,true)` (`carry_system.lua:46`), anexado à mão do ped. |
| SERVER | `parcel_service` só estado (`ParcelState`). |
| DELETE | `CarrySystem.Stop`, `DropAt` com `SetTimeout` de 30 s; `onResourceStop` apaga props ativos e soltos. |
| PLAYER DROP | Servidor limpa `ParcelState`; prop client-created networked sem cleanup do servidor. |

## 10. HOSE (liquid)

| Campo | Achado |
|---|---|
| CREATED BY | Servidor `CreateObject(prop_cs_fuel_nozle,…,true,true,false)` (`sv/main:1772`) após `pickupHose`. **Fallback do cliente** cria outro hose networked (`cargo_liquid.lua:230`) não rastreado pelo servidor. |
| OWNER | **Sem `LockEntityNetworkOwner`.** |
| DELETE | Servidor: `cancelHose`, `hoseLeak`, `disconnectHose`, `CleanupLobbyEntities`, conclusão. Cliente: `CargoLiquid.Cleanup`, watcher de entrada em veículo, handlers de leak/cancel. |
| GAPS | **`CargoLiquid.Setup` não tem chamador** **[VERIFICADO]**: o fluxo do hose é inalcançável (ver 05). |

## Top 10 lacunas de ciclo de vida

1. **Liquid (e ADR) não conclui:** `CargoLiquid.Setup` nunca é chamado; `cl/main:608` define `STEP_5_FUEL_LOADING` e nada mais acontece. **[VERIFICADO]**
2. **Car carrier inoperante:** comparação de netId com handle **[VERIFICADO]**, callback sem argumento, `StartDeliveryRoute` chamada antes da declaração `local` (`cl/main:619` × `:661`) **[VERIFICADO]**.
3. **Forklift e Reach Stacker órfãos** após conclusão com caminhão próprio **[VERIFICADO]**; `activeJobData` obsoleto no caminhão próprio.
4. **`IsSpawnPointClear` apaga veículos vazios de qualquer jogador** nas vagas (`sv/main:476-490`) **[VERIFICADO]**.
5. **Forklift de emergência sem gestão:** sem plate/chaves/lock/`ignoreEntities`, sem informar o cliente.
6. **Queda × reconexão:** o lobby Polarix é apagado na hora; o grace de 3 min só cobre `PlayerJobEntities` (registrado uma vez, após o strapping).
7. **Caminhão do LC quick job vaza** em queda e em resource stop (sem lock; nenhum `playerDropped` toca `ActiveLCContractData`).
8. **Vazamentos de forklift/pallet legados** (pallets não contados ficam; forklift de indústria nunca registrado).
9. **`CleanupCurrentJob` não restaura nada** (freeze do caminhão, migração de rede, statebags) e o stop varre o pool de objetos.
10. **Props periféricos:** container/handler do handler-mission, alvo do repo entregue, prop de animação do flatbed, rampa local.

## FILES ACTUALLY READ (auditoria de ciclo de vida)

`server/main.lua` 30–2453; `server/events.lua` 1–470, 1100–1250, 1760–1860, 2150–2220, 2470–2510, 2570–2610; `server/flatbed.server.lua`, `server/pallet_registry.lua` completos; `truck_rental_service` 90–374; `forklift_service` 100–153; `container_handler_service` 165–183; `parcel_service` 355–392; `client/main.lua` por faixas (≈2/3 do arquivo); `client/client.lua` por faixas; `cargo_dry`, `cargo_liquid`, `car_carrier`, `reach_stacker`, `flatbed.client`, `carry_system`, `forklift.client` completos; `forklift.lua` 360–495, 574–870, 975–1036; `container_handler.client` 30–433; `repo.client` 40–657 (com lacunas). **NOT READ:** a maior parte de `events.lua`, `callbacks.lua`, serviços (grep apenas).
