# 08 — External Reference Study

**ANALYZED HEAD (AUST): `c9d9187`.** Referências lidas em clones rasos locais (commit indicado). **Gate 2 (REFERENCE READ):** só conta como lido o que está listado em "FILES READ". Onde uma referência foi lida só em parte, a lacuna está declarada. Pontuações 0–10 (10 = melhor) são **julgamento de engenharia**, não medição.

> Licenças foram verificadas lendo o arquivo `LICENSE` de cada clone. Isto **não é parecer jurídico**; o AUST não tem arquivo `LICENSE` na raiz e é derivado do Polarix (MIT). Ver `14_TECH_DEBT_REGISTER.md` (LEGAL-01).

## Índice de referências

| ID | Projeto | Commit lido | Última atividade | Licença (arquivo) | Framework |
|---|---|---|---|---|---|
| A | derPolarix/polarix_truckerjob | `d11dcd1` | 2026-10-03 | **MIT** | ox_lib; framework por bridge |
| B | DonHulieo/don-forklift | `4adaf7a` (v1.3.1) | 2024-12-11 | GPL-3.0 (`LICENSE.md`) | multi (bridge `duff`) |
| C | Mobius1/esx_forklift | `9edc213` | 2020-09-21 | GPL-3.0 | ESX |
| D | xDope7137/forklift | `1718e31` | 2026-07-28 | **sem arquivo de licença** | QB/ESX-style |
| E | qbcore-framework/qb-truckerjob | `f994467` | 2026-08-26 | GPL-3.0 | QBCore |
| F | Qbox-project/qbx_core | `1825a3c` | 2026-09-29 | GPL-3.0 (cabeçalho "es_extended") | Qbox |
| G | DrSnyder86/ls_trucking | `7940d00` (v1.4.1) | 2026-09-18 | GPL-3.0 | qb/qbox/esx/nd/standalone |
| H | XyraL/XS-Trucking | `50af0ac` (v3.0.0) | 2026-09-30 | **"All rights reserved"** (uso no próprio servidor; sem redistribuição) | Qbox/QBCore |
| I | Zotters/fiji-oil | `c6189a1` | 2026-08-01 | GPL-3.0 | qb/qbx/esx (bridge próprio) |
| J | Distortionzz/Distortionz_Towjob | `e518902` (v1.2.3) | 2026-05-13 | **sem arquivo de licença** | Qbox |
| K | apoiat/ESX_Deliveries | `3f4a28f` | 2019-07-21 | **sem arquivo de licença** (README cita GPL-3) | ESX (cliente em C#) |
| L1 | overextended/ox_lib | `66906c5` (v3.40.0) | 2026-10-03 | LGPL-3.0 | — |
| L2 | overextended/ox_inventory | `488aa6d` (v2.48.0) | 2026-10-03 | GPL-3.0 | — |
| L3 | overextended/ox_target | `bf03d52` | 2026-06-09 (só README; atividade de código **UNKNOWN**) | MIT | — |
| **M** | TrueMaps / TRUE. — Advanced Trucker Job (**vídeo**) | **sem commit (sem código)** | **UNKNOWN** | **UNKNOWN** (sem acesso ao código; tratar como proprietário) | ESX/QBCore/QBOX (**SECONDARY REPORT**: título do produto) |

---

## REFERENCE A — Polarix Trucker Job

**FILES READ:** `client/modules/cargo.lua` (776/776), `client/modules/forklift.lua` (357/357), `server/modules/party_mission.lua` (spawn do estado, `GetGroundState`, `ClaimGroundPallet`, `GetCargoState`, `LoadPalletOnTrailer`, `CompleteTrip`, `HandleMemberDropout`, `BroadcastProgress` início), `server/modules/party.lua` (`OnPlayerUnload`), `shared/cargo.lua`, `config/shared.lua`, `config/client.lua`, stream `*.ydr` listados. **NOT READ:** `server/modules/orders.lua`, `delivery.lua` e demais módulos de economia/NUI.

Detalhe completo (call-flow por etapa) em `AUST_TRUCKER_FORKLIFT_REFERENCE_STUDY.md` §4. Resumo técnico:

- **Pallet de chão:** `CreateObject(model, x, y, z, false, false, false)` em **cada cliente** (local), `PlaceObjectOnGroundProperly`, `FreezeEntityPosition(true)`, colisão ligada, invencível (`cargo.lua:66-79`).
- **Pickup:** thread de 300 ms; candidato = horizontal ≤ 0,7 m e vertical −0,08…+0,18 m **do osso `forks_attach`** (`:104-124`); **tecla** (`:272`); party: `claimGroundPallet` (CAS por slot, `party_mission.lua:87-112`).
- **Representação:** `DeleteEntity(sourcePallet)` + `CreateObject` novo local + `AttachEntityToEntity(prop, forklift, forks_attach, 0,0,0.05, 0,0,0, false,false,false,false,2,true)` (`:126-156`, `:222-227`). **NÃO é o mesmo entity.**
- **Trailer:** `DetachEntity` + `AttachEntityToEntity(trailer, bone 0, attachOffsets[slot])`; por padrão `renderLoadedPallets = false` (config entregue) e o prop é deletado.
- **Observadores:** prop decorativo local por `ReconcileForkliftProps`/`ReconcileTrailerProps` a cada 3 s via `getPartyCargoState` (`:711-740`). Jogador fora da party não vê.
- **Servidor:** `slots[i] = {state, identifier|ownerIdentifier, trailerSlot}`; `loadPalletOnTrailer` valida `state == "carried"` e `identifier == caller` (`:154-207`); `HandleMemberDropout` devolve slots (`:262-293`) e dispara `partyGroundPalletFreed`.

| LAST ACTIVITY | 2026-10-03 |
|---|---|
| CODE QUALITY | 7 |
| SECURITY | 5 (claim/load sem validar proximidade; solo com contagem no cliente) |
| SERVER AUTHORITY | 5 |
| ONESYNC | 6 (evita rede por ser local; observador só da party) |
| PERFORMANCE | 7 |
| GAMEPLAY | 6 |
| MAINTAINABILITY | 7 |
| **AUST RELEVANCE** | **10** (origem do AUST) |

**GOOD IDEAS:** chão frozen sem Havok; swap de representação; máquina de slot no servidor; reconcile auto-curativo; dropout devolve slots.
**BAD IDEAS:** sem proximidade no claim/load; sem lease em `carried`; offset de garfo único e global; constantes mortas (`ForkliftDropMaxHeight`).
**TRANSFERABLE:** estados por slot com recuperação; reconcile periódico; `collision=false` no attach; chão determinístico a partir do servidor.
**DO NOT COPY:** a ausência de validação de distância; o modo solo com contagem no cliente.

---

## REFERENCE B — Don Forklift

**FILES READ:** `client/main.lua` (1–450, 450–562 e 780–863 por grep; funções `setup_mission_obj`, `await_load`, `create_object`, `init_mission_obj`, `get_damage_ratio`), `server/main.lua` (333/333), `shared/config.lua` (modelos), `fxmanifest.lua`. **NOT READ:** `server/config.lua` além do uso; partes de `client/main.lua` 563–780 (IA do motorista NPC).

- **Entidade:** servidor cria (`CreateObjectNoOffset(hash, x,y,z, true,false,false)`, `server/main.lua:179`), define statebags `init/owner/warehouse` e `SetEntityIgnoreRequestControlFilter(obj, true)`; **espera `NetworkGetEntityOwner(obj) == player` sem timeout** (`:190`).
- **Cliente:** `NetworkUseHighPrecisionBlending(netId, true)`, `NetworkSetObjectForceStaticBlend(obj, true)`, `PlaceObjectOnGroundProperly`, `SetEntityDynamic(obj, true)` (`client/main.lua:264-269`).
- **Validação:** reserva de warehouse por identifier em `GlobalState`; `exploit_ban` (kick) em mismatch de dono na remoção (`:256-273`) e na criação (`:178`). **`finish_mission` confia em `loads` do cliente**; só rejeita `health > 1` (`:288-306`).
- **Sem** `playerDropped` nem `SetEntityOrphanMode` (grep).

| LAST ACTIVITY | 2024-12-11 |
|---|---|
| CODE QUALITY | 6 |
| SECURITY | 5 |
| SERVER AUTHORITY | 6 (ciclo de vida do objeto no servidor; pagamento por loads do cliente) |
| ONESYNC | 6 |
| PERFORMANCE | 6 |
| GAMEPLAY | 5 |
| MAINTAINABILITY | 6 |
| **AUST RELEVANCE** | **6** (ownership + statebags) |

**GOOD:** entidade criada no servidor com dono em statebag; remoção validada por dono; blending de precisão.
**BAD:** espera de dono sem timeout; kick imediato em qualquer mismatch; `loads` do cliente; sem tratamento de queda.
**TRANSFERABLE:** statebag `owner` + validação em remoção/criação; `NetworkUseHighPrecisionBlending` para o observador (**efeito não verificado in-game**).
**DO NOT COPY:** `repeat Wait(100) until owner == player` sem limite; pagamento por contagem do cliente.

---

## REFERENCE C — Mobius ESX Forklift

**FILES READ:** `client/main.lua` (120–260, 256–380, 540–690, 690–890), `client/utils.lua` (226/226), `server/main.lua` (16/16), `config.lua` (modelo). 

- **Colisão não carregada:** em `StartDeliveryThread`, `if pdist < 50 then Player.Pallet.Ready = true; PlaceObjectOnGroundProperly(...) end`, com o comentário "If pallet is far from player, collisions might not be loaded so it'll fall through floor" (`:739-740`).
- **Lifted:** `IsEntityInAir(pallet)`; engate: `IsEntityAtEntity(forklift, pallet, 3,3,3, ...)`.
- **Bug no `ValidDrop`:** `angle < 1 or angle - 180 < 1` aceita qualquer `angle < 181` (`:364-369`).
- **Servidor:** `esx_flt:getPaid(amount)` aceita **qualquer valor** do cliente.

| LAST ACTIVITY | 2020-09-21 |
|---|---|
| CODE QUALITY | 4 |
| SECURITY | 1 |
| SERVER AUTHORITY | 0 |
| ONESYNC | 3 |
| PERFORMANCE | 5 |
| GAMEPLAY | 5 |
| MAINTAINABILITY | 4 |
| **AUST RELEVANCE** | **4** (só o comentário/remédio de colisão) |

**GOOD:** documenta e mitiga o modo de falha "pallet longe cai pelo chão" (reposicionar ao chegar perto); bounds por `GetModelDimensions`.
**TRANSFERABLE:** adiar o ground placement até a colisão estar carregada perto do jogador; caixa de entrega derivada das dimensões do modelo.
**DO NOT COPY:** pagamento do cliente; validação de heading frouxa.

---

## REFERENCE D — xDope Forklift

**FILES READ:** `forklift_c.lua` (531/531), `forklift_sv.lua` (66/66), `config.lua`, `fxmanifest.lua`.

- `CreateObject(prop_boxpile_*, x, y, z-0.95, true,true,true)` + `SetEntityDynamic(true)` + `FreezeEntityPosition(false)` (`:62-91`): Havok pura, objeto networked criado pelo cliente.
- Entrega por `Vdist ≤ 2.0` a um marker, laço `Citizen.Wait(2)`; `DeleteEntity(paczuszka)`.
- Servidor: posse do hangar por `source`, limpa em `playerDropped`; **pagamento com valor do cliente** (`tostdostawa:wykonanieMisji`).

| LAST ACTIVITY | 2026-07-28 |
|---|---|
| CODE QUALITY | 2 |
| SECURITY | 0 |
| SERVER AUTHORITY | 1 |
| ONESYNC | 2 |
| PERFORMANCE | 3 |
| GAMEPLAY | 4 |
| MAINTAINABILITY | 2 |
| **AUST RELEVANCE** | **2** (histórico) |

**GOOD IDEAS:** bônus por tempo.
**BAD:** `z-0.95` fixo; objeto órfão se o jogador cai; valor pago pelo cliente; laços de 2 ms.
**DO NOT COPY:** tudo.

---

## REFERENCE E — qb-truckerjob

**FILES READ:** `fxmanifest.lua` (1–23), `server/main.lua` (1–60), `config.lua` (1–66), `client/main.lua` (1–563), `LICENSE`. 

- 563 linhas de cliente e 60 de servidor; **toda a lógica no cliente**. Servidor: `DoBail` (depósito em memória `Bail[citizenid]`, `server/main.lua:4-28`), `qb-trucker:server:01101110` (pagamento).
- **Pagamento:** `payment = DropPrice*drops + bonus` com `drops` **do cliente** (clamp a `MaxDrops` = 20), sem sessão, sem cooldown (`:30-52`).
- `qb-trucker:server:nano` sem checagens. Sem `playerDropped`.

| LAST ACTIVITY | 2026-08-26 |
|---|---|
| CODE QUALITY | 4 |
| SECURITY | 2 |
| SERVER AUTHORITY | 1 |
| ONESYNC | 2 |
| PERFORMANCE | 5 |
| GAMEPLAY | 4 |
| MAINTAINABILITY | 4 |
| **AUST RELEVANCE** | **5** |

**GOOD:** depósito simples com reembolso na devolução; fórmula base × quantidade + bônus − imposto calculada no servidor.
**BAD:** quantidade enviada pelo cliente; zero estado de sessão no servidor.
**DO NOT COPY:** GPL-3.0; evento `01101110` (nome ofuscado não é segurança).

---

## REFERENCE F — Qbox (`qbx_core`)

**FILES READ:** `fxmanifest.lua`, `server/events.lua` (279/279), `server/vehicle-persistence.lua` (295/295), `client/vehicle-persistence.lua` (116/116), `server/player.lua` (28–130, 1155–1500), `server/functions.lua` (1–55, 475–588), `server/main.lua` (1–74), `server/character.lua` (20–138), `server/loops.lua` (40–85), `modules/hooks.lua` (1–74), `modules/lib.lua` (262–400), `config/server.lua` (1–50), `bridge/qb/server/main.lua` (1–50). **NOT READ:** `server/groups.lua`, `commands.lua`, `queue.lua`, `server/storage/*`, `modules/playerdata.lua`, a maioria de `client/*`.

- **Mutação só no servidor:** `AddMoney/RemoveMoney/SetMoney` são funções + exports, **não eventos** (`server/player.lua:1320-1477`); `validateMoneyAmount` rejeita NaN/Inf/negativo (`:1306-1313`); hooks com `pcall` e remoção ao parar o recurso; log com `GetInvokingResource()`.
- **Veículos:** `qbx.spawnVehicle` (`CreateVehicleServerSetter`, espera dono, `SetEntityOrphanMode(veh, 2)`, persistência) (`modules/lib.lua:286-393`); `DeleteVehicle` desliga persistência antes de apagar (`functions.lua:581-588`).
- **Fraqueza:** `vehiclePropsChanged` aceita `netId` e `diff` do cliente sem checar proximidade (`vehicle-persistence.lua:29-77`).
- **Sem rate limit por evento** nos arquivos lidos.

| LAST ACTIVITY | 2026-09-29 |
|---|---|
| CODE QUALITY | 7 |
| SECURITY | 7 |
| SERVER AUTHORITY | 8 |
| ONESYNC | 8 |
| PERFORMANCE | 7 |
| GAMEPLAY | n/a (core) |
| MAINTAINABILITY | 6 |
| **AUST RELEVANCE** | **6** |

**TRANSFERABLE:** API de mutação só no servidor com validação numérica e log de origem; spawn no servidor com `SetEntityOrphanMode`; remoção que desliga persistência; loops escalonados (`forEachPlayerStaggered`); guarda idempotente (`Player(src).state.isLoggedIn`).
**DO NOT COPY:** o evento de props com diff do cliente; funções globais + export como estilo único.

---

## REFERENCE G — LS Trucking

**FILES READ:** `fxmanifest.lua`, `sql/ls_trucking.sql`, `server/main.lua` (1–520, 556–895, 1709–1958, 2183–2680), `server/routes.lua` (1–235), `server/cargo.lua` (1–704), `server/contractors.lua` (1–330, 780–1087), `server/depot_vehicles.lua` (110–331), `server/service_bay.lua` (190–279), `server/company_garage.lua` (1–80), `server/admin.lua` (40–100), `server/ids.lua`, `server/framework.lua` (parcial), `client/main.lua` (2385–2430), `config/config.lua` (1–150). **NOT READ:** `server/main.lua` 895–1709 e 1958–2183, `contractors.lua` 330–780, `dispatch_data.lua`, demais `client/*`, `html/*`, `config/contracts.lua` (4031 linhas).

- Empresa = **NPC empregador** (sem empresa de jogador, banco, empréstimo ou convoy nos arquivos lidos). Estado em `ActiveContracts[src]` na memória.
- Servidor **autoritativo** para o contrato (manifesto, assinaturas, flag `paid`, distância por ação via `RequireServerNear`, rate limit por ação); **não autoritativo** para veículos (cliente cria; `registerAssignedTrailer` aceita o netId do cliente se o servidor não rastreia nenhum; dano e mileage vindos do cliente).
- `markTrailerHooked` não verifica trailer anexado (só o jogador perto do depósito).
- Reserva atômica `UPDATE ... SET stored=2 WHERE stored=1` na venda de veículo (`contractors.lua:947-955`).

| LAST ACTIVITY | 2026-09-18 |
|---|---|
| CODE QUALITY | 6 |
| SECURITY | 6 |
| SERVER AUTHORITY | 5 |
| ONESYNC | 6 |
| PERFORMANCE | 6 |
| GAMEPLAY | 7 |
| MAINTAINABILITY | 4 (`server/main.lua` 2 680 linhas, closures `ctx`) |
| **AUST RELEVANCE** | **4** |

**TRANSFERABLE:** manifesto + máquina de estágios com flag `paid`; `RequireServerNear` configurável; reserva atômica; fatura de oficina calculada no servidor; checagem de posição do trailer com tolerância e velocidade ≈ 0.
**DO NOT COPY:** GPL-3.0; netId/dano/mileage do cliente; `markTrailerHooked`.

---

## REFERENCE H — XS-Trucking  *(REVISÃO V2 — detalhes em `08b_XS_TRUCKING_DEEP_DIVE.md`)*

**FILES READ (FULL):** server 11/11 (`main, db, jobs, callbacks, progress, business, garage, coop, spots, settings, admin`), client 6/6 (`job, main, placement, ui, builder, guards`), `config.lua`, bridge 6/6 (`framework, fuel, inventory, keys, target, dispatch`), `shared/util.lua`, NUI 18/18 (`index.html`, `js/*` ×16, `css/cabos.css`), tools 10/10 (`check-*.mjs` + `check-all.mjs`), `README`, `CHANGELOG`, `LICENSE`, `fxmanifest.lua`, 2 workflows. **PARTIAL:** `tools/.natives-cache.json` (início; arquivo de dados). **NOT READ:** `html/vendor/leaflet/*`, `html/assets/maps/tiles/*.webp`. Nada foi executado.

- **Servidor cria os veículos** (`CreateVehicleServerSetter` + `SetEntityOrphanMode(…,2)`, `jobs.lua:37-47`) e os guardas (`CreatePed` + orphan mode, `:649`); marca statebags `xsTrucking`/`xsGuard` **no servidor**; o cliente é renderizador fino via callbacks (o servidor registra **um único** `RegisterNetEvent`, `guardsAlarm`).
- `Jobs.Deliver` valida estágio, **trailer do servidor** na zona, caminhão ≤ 20 m do trailer, jogador perto; `finish()`/`drop()` limpam `Jobs.active[src]` **antes** de pagar (sem pagamento duplo); dano = saúde lida no servidor; watchdog de 5 s.
- **Autoridade HÍBRIDA, não 100%:** o **hitch** é detectado no cliente e o servidor só confere distância; **combustível** (devolução) e **hora do relógio** vêm do cliente (clamp 0..100 só no combustível).
- Empresa de jogador com banco, ranks hierárquicos, corte do motorista, ledger e `Charge` atômico (`bank >= ?`); frota com reserva; co-op (convoy/escort/co-driver); auditoria em `xs_trucking_deliveries` e `xs_trucking_admin_log`; admin sempre por `guarded()`.
- Falhas: janelas **check-then-act** (`Garage.Collect/Sell`, `BuySkill`, `BuySlots`, `Jobs.Take`, `Coop.Start` — RUNTIME_UNVERIFIED), liquidação **não transacional**, débito antes da escrita, jobs só em memória, sem rate limit, sem testes. Detalhes e evidência em `08b` §4 e §11.
- **Diferenciais para o AUST (ideias):** camada de **bridges** (framework/fuel/inventory/keys/target/dispatch), **ferramentas estáticas** (9 verificadores locais), **NUI modular** com contrato RPC, **painel admin** com auditoria e **settings ao vivo**, **Placement** (footprint/piso/água), padrão `takeControl` limitado.
- **Possível derivação de "Cipher-Trucking"** (importador `cipher_trucking_*`, `db.lua:321`); licença do upstream **UNKNOWN**.

| LAST ACTIVITY | 2026-09-30 |
|---|---|
| CODE QUALITY | 8 |
| SECURITY | 7 |
| SERVER AUTHORITY | 8,5 |
| ONESYNC | 8,5 |
| PERFORMANCE | 7 |
| GAMEPLAY | 9 |
| MAINTAINABILITY | 8 |
| **AUST RELEVANCE** | **8,5** |

**TRANSFERABLE (ideias, não código):** veículos criados no servidor com statebag e registro por job; watchdog; `finish()` que apaga o estado antes de pagar; `lockReason()`; ledger e auditoria por entrega; settings ajustáveis; normalização/clamp de rotas; bridges; verificadores estáticos; `takeControl` limitado; contrato `UI RPC allowlist + server authority`.
**DO NOT COPY:** licença **ALL RIGHTS RESERVED** (sem redistribuição de original ou derivado, sem venda); `Collect`/`Sell`/`BuySkill` não atômicos; combustível/hora do cliente. **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.**

---

## REFERENCE I — Fiji Oil

**FILES READ:** `fxmanifest.lua`, `server/main.lua` (1–51), `server/drilling.lua` (1–120), `server/refinery.lua` (1–208), `server/packaging.lua` (1–91), `server/companies.lua` (1–322), `server/supplyorders.lua` (1–156), `server/boats.lua` (1–59), `server/terminal.lua` (1–36), `shared/config.lua` (1–120), `shared/callback.lua`, `shared/loader.lua`, `shared/bridge.lua` (grep). **NOT READ:** todo `client/*`, `ui/*`, `sql/fiji_oil.sql`, README.

- Cadeia de suprimento **por jogador** (sem estoque de mundo): pedido com `ready_at`, coleta com claim atômico `UPDATE ... WHERE id=? AND status != 'collected'` e rollback se `AddItem` falhar.
- `TryLock` + `pcall` por origem em toda mutação; distância revalidada no servidor em quase toda ação; recompensa/preço sempre da config; reputação por upsert SQL com clamp.
- Refino em 3 fases com o tipo de saída vindo do **estado do servidor**.
- Falhas: progresso do refino em memória; `distillComplete` sem validação; aluguel de barco sem vínculo a entidade; camada de callback própria sem timeout.

| LAST ACTIVITY | 2026-08-01 |
|---|---|
| CODE QUALITY | 7 |
| SECURITY | 7 |
| SERVER AUTHORITY | 7 |
| ONESYNC | 6 |
| PERFORMANCE | 7 |
| GAMEPLAY | 6 |
| MAINTAINABILITY | 6 |
| **AUST RELEVANCE** | **5** |

**TRANSFERABLE:** `TryLock` + `pcall`; claim atômico por status; rep por upsert clampado; peso do rendimento + qualidade; reembolso pro-rata calculado no servidor.
**DO NOT COPY:** GPL-3.0; estado do refino só em memória; camada de callback própria.

---

## REFERENCE J — Distortionz TowJob

**FILES READ:** `fxmanifest.lua`, `server.lua` (1–304 de 367), `client.lua` (186–462 de 975 + outline), `config.lua` (140–180, 295–312). **NOT READ:** `client.lua` 1–185 e 463–975, `html/*`, README.

- **Attach:** `AttachEntityToEntity(target, flatbed, 0, off.x,off.y,off.z, 0,0,0, false,false,false,false, 20, true)`: osso 0, rotação 0, colisão `false`, offset por modelo com default `(0, -2.6, 1.0)`; sem freeze; distância ≤ 10 m (`client.lua:291-335`).
- **Pickup/Drop:** `confirmPickup` sem argumentos e sem validação; drop paga com `driveDistanceKm` e saúde do cliente **sem limite superior**; posição do destino só no cliente.
- `playerDropped` só zera `jobs[src]`; veículos não são tocados.

| LAST ACTIVITY | 2026-05-13 |
|---|---|
| CODE QUALITY | 6 |
| SECURITY | 2 |
| SERVER AUTHORITY | 3 |
| ONESYNC | 4 |
| PERFORMANCE | 6 |
| GAMEPLAY | 5 |
| MAINTAINABILITY | 6 |
| **AUST RELEVANCE** | **5** (forma da fórmula e offsets por modelo) |

**GOOD:** tabela de offsets por modelo (confirma a abordagem do PropEditor do AUST); fórmula `base + km − dano` com piso.
**DO NOT COPY:** payout com entradas do cliente; sem licença.

---

## REFERENCE K — ESX Deliveries

**FILES READ:** `__resource.lua`, `Esx_Deliveries_Server/main.lua` (42/42), `Esx_Deliveries_Client/Client.cs` (1–783), `DeliveryData.cs` (1–60), README (1–30). **NOT READ:** `DeliveryData.cs` 61–276, `.csproj`, `.sln`.

- Cliente em **C#**; máquina de estados nomeada (`DELIVERY_INACTIVE … PLAYER_RETURNING_TO_BASE`); carry com animação/prop por classe de veículo; depósito/retorno com **valor escolhido pelo cliente** (`RemoveBankMoney(amount)`, `AddBankMoney(deposit)`); servidor sem nenhuma validação (`AddCashMoney(amount)` livre).
- Bug: compara handle de veículo com hash de modelo (`GetVehiclePedIsIn(...) != Model.Hash`).

| LAST ACTIVITY | 2019-07-21 |
|---|---|
| CODE QUALITY | 4 |
| SECURITY | 0 |
| SERVER AUTHORITY | 0 |
| ONESYNC | 2 |
| PERFORMANCE | 3 |
| GAMEPLAY | 6 |
| MAINTAINABILITY | 4 |
| **AUST RELEVANCE** | **6** (UX de depósito e carry de encomenda) |

**TRANSFERABLE (conceito):** depósito/retido/reembolso como **estado do servidor**; carry com bloqueio de sprint e reaplicação da animação; espaçamento mínimo de 50 m entre paradas.
**DO NOT COPY:** todos os eventos de servidor; cliente C#.

---

## REFERENCE L — ox_lib / ox_inventory / ox_target

**FILES READ:** ver relatório de leitura: `ox_lib` (`imports/callback/{client,server}.lua`, `resource/callbacks/shared.lua`, `imports/{requestModel,requestAnimDict,streamingRequest,waitFor,points}`, `resource/cache/client.lua`, `resource/interface/client/progress.lua`, `imports/zones/shared.lua` parcial); `ox_inventory` (`modules/inventory/server.lua` por faixas, `modules/hooks/server.lua`, `modules/shops/server.lua`, `modules/locks.lua`, `server.lua` 106–340); `ox_target` (`client/api.lua`, `client/main.lua`, `server/main.lua` completos). **NOT READ:** `lib.onCache`, internals de `lib.grid`, caminhos de crafting/`usingItem`, `loadInventoryData` completo.

- **Callbacks:** `source` vem do motor; sem tratamento de queda durante `await` (timeout padrão 5 min; erro de handler volta como `false`, ambíguo). Sem serialização por jogador: handler que cede pode reentrar.
- **ox_inventory:** `AddItem` **não checa peso**, só `CanCarryItem` (`modules/inventory/server.lua:1147-1255`, `:1472`); `RemoveItem` antes de `AddItem`; hooks falham abertos se o hook der erro.
- **ox_target:** `ox_target:setEntityHasOptions` e `toggleEntityDoor` aceitam netId de qualquer cliente sem validação (`server/main.lua:9-23`); `serverEvent` options têm checagens só cosméticas no cliente.
- **Zones/points:** loop compartilhado de 300 ms; zonas funcionam no servidor como geometria (`zone:contains`).

| | ox_lib | ox_inventory | ox_target |
|---|---|---|---|
| CODE QUALITY | 8 | 7 | 8 |
| SECURITY | 7 | 8 | 5 |
| SERVER AUTHORITY | 6 | 9 | 2 (UI) |
| PERFORMANCE | 8 | 7 | 9 |
| MAINTAINABILITY | 8 | 6 | 8 |
| **AUST RELEVANCE** | 9 | 8 | 6 |

**TRANSFERABLE:** validar na ordem estado → distância (ped do servidor) → entidade → mutar; devolver `true|false, motivo` em vez de depender de erro; lock por chave para handlers que cedem; progress "completo" nunca é prova de trabalho (registrar `startedAt` no servidor); chamar `CanCarryItem` antes de `AddItem`.
**DO NOT COPY:** código do `ox_inventory` (GPL-3.0); confiar em eventos de servidor do `ox_target`.

---

## REFERENCE M — TrueMaps Advanced Trucker Job  *(adendo de GAMEPLAY — detalhes em `20_TRUEMAPS_GAMEPLAY_REFERENCE.md`)*

**SOURCE TYPE:** VIDEO GAMEPLAY REFERENCE · **SOURCE:** https://youtu.be/9hNLhOnFLL8 · **DEVELOPER:** TrueMaps / TRUE. · **CLASSIFICATION:** **GAMEPLAY REFERENCE — NOT a SOURCE CODE REFERENCE.**

**FILES READ:** **nenhum** (sem código). A sessão **não acessa o vídeo** (`youtu.be` bloqueado pelo proxy). Evidência usada: **transcrição da narração** (legenda automática em inglês do YouTube, 3:54, fornecida pelo usuário; pode ter erros; **não inclui o que aparece só na imagem**) **+ brief da missão**. Evidência em **4 níveis** (nunca misturados): **VIDEO NARRATION CONFIRMED** (declarado pela narração/transcrição), **VIDEO VISUAL OBSERVED** (visível no gameplay; **nenhum item confirmado**, a sessão não vê a imagem), **SECONDARY REPORT** (análise externa sem confirmação direta) e **AUST DESIGN PROPOSAL** (ideia nossa). A narração é material de divulgação: confirma o que o produto **afirma**, não como funciona. **TECHNICAL IMPLEMENTATION UNKNOWN** (arquitetura, banco, divisão servidor/cliente, autoridade, OneSync, ciclo de vida de entidades, eventos/callbacks, anti-exploit, persistência, fórmulas, scanner, algoritmo de ponte, remoção de obstáculos).

| Aspecto | Status |
|---|---|
| IMPLEMENTATION DETAILS | **UNKNOWN** |
| SERVER AUTHORITY | **UNKNOWN** |
| SECURITY | **UNKNOWN** |
| ONESYNC | **UNKNOWN** |
| DATABASE DESIGN | **UNKNOWN** |
| PERFORMANCE | **UNKNOWN** |
| MAINTAINABILITY | **UNKNOWN** |

**Só avaliado (gameplay, confiança MÉDIA — narração do desenvolvedor):** GAMEPLAY 9 · JOB VARIETY 9 · HEAVY RP VALUE 9 · PHYSICAL INTERACTION 9 · COOP VALUE 9 · **AUST RELEVANCE 8**.

**Gameplay confirmado pela narração (ver doc 20 §2):** 12 tipos de job · carregamento com **pallet jack** · **rampa de carga** (abrir/subir/baixar) · descarga em local designado · estacionamento de precisão · **courier** (achar o pacote certo, escanear etiquetas, entregar na porta) · 8 trailers customizados · oversized com **restrição de pontes** e planejamento de rota · **escolta ativa** (≥ 2 jogadores; garante rota, ajuda a manobrar, remove obstáculos como postes) · colisão/dano afetam o **pagamento** · jobs de 30+ min · **modo empresa** (afirma **10%** automático à conta da empresa; **não copiado**) e **modo job padrão**. **Só na brief (não narrado):** portas traseiras, direção agressiva/raspagem/curva brusca, túnel/raio de curva, "hidráulico".

**Ideias para o AUST (todas [AUST DESIGN PROPOSAL], itens de estudo GPLAY-01…11):** pallet jack · cargo access (portas/liftgate) · scanner de courier · cargo integrity · docking quality · escolta ativa · restrições de rota oversized · obstáculos de via · comboio de transporte especial · **jobs longos (30+ min)** · **restrições dimensionais de rota por trailer**.

**NÃO inferir nem atribuir ao TrueMaps:** arquitetura interna, SQL, eventos/callbacks, autoridade de servidor, OneSync, desempenho. **DO NOT COPY:** nenhum código/UI/asset (licença **UNKNOWN**). **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.**

| LAST ACTIVITY | UNKNOWN |
|---|---|
| CODE QUALITY | UNKNOWN |
| SECURITY | UNKNOWN |
| SERVER AUTHORITY | UNKNOWN |
| ONESYNC | UNKNOWN |
| PERFORMANCE | UNKNOWN |
| GAMEPLAY | 9 (narrado) |
| MAINTAINABILITY | UNKNOWN |
| **AUST RELEVANCE** | **8 (gameplay)** |

---

## SCORECARD — resumo

| Ref | Qualidade | Segurança | Autoridade servidor | OneSync | Performance | Gameplay | Manutenção | Relevância AUST |
|---|---|---|---|---|---|---|---|---|
| A Polarix | 7 | 5 | 5 | 6 | 7 | 6 | 7 | **10** |
| B Don | 6 | 5 | 6 | 6 | 6 | 5 | 6 | 6 |
| C Mobius | 4 | 1 | 0 | 3 | 5 | 5 | 4 | 4 |
| D xDope | 2 | 0 | 1 | 2 | 3 | 4 | 2 | 2 |
| E qb-truckerjob | 4 | 2 | 1 | 2 | 5 | 4 | 4 | 5 |
| F qbx_core | 7 | 7 | 8 | 8 | 7 | n/a | 6 | 6 |
| G ls_trucking | 6 | 6 | 5 | 6 | 6 | 7 | 4 | 4 |
| H XS-Trucking (v2) | 8 | 7 | **8,5** | **8,5** | 7 | **9** | 8 | **8,5** |
| I fiji-oil | 7 | 7 | 7 | 6 | 7 | 6 | 6 | 5 |
| J Tow | 6 | 2 | 3 | 4 | 6 | 5 | 6 | 5 |
| K ESX Deliveries | 4 | 0 | 0 | 2 | 3 | 6 | 4 | 6 |
| L1 ox_lib | 8 | 7 | 6 | n/a | 8 | n/a | 8 | 9 |
| L2 ox_inventory | 7 | 8 | 9 | n/a | 7 | n/a | 6 | 8 |
| L3 ox_target | 8 | 5 | 2 | n/a | 9 | n/a | 8 | 6 |
| **M TrueMaps (só gameplay)** | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | **9** (narrado) | UNKNOWN | **8** (gameplay) |

**M (TrueMaps)** só tem critérios de gameplay (fonte: narração do vídeo via transcrição fornecida + brief; imagem não verificada); os demais são **UNKNOWN**, **não** zero.

Pontuações de B, C, D e A são **minhas** (leitura direta); E–L foram produzidas a partir de relatórios de leitura de subagentes (arquivos e faixas listados acima) e conferidas por amostragem de licença e commit.

## Melhor referência por tema

| Tema | Referência | Por quê |
|---|---|---|
| Forklift / pickup | **Polarix (A)** | swap de representação; chão frozen |
| Colisão a distância | **Mobius (C)** | único que nomeia e mitiga o modo de falha |
| OneSync / ownership / statebag | **Don (B)** + **XS-Trucking (H)** | dono em statebag e remoção validada; veículos/guardas criados no servidor com orphan mode, statebags do servidor e `takeControl` limitado |
| Core trucking | **XS-Trucking (H)** | autoridade **majoritária** (hitch, combustível e hora ainda vêm do cliente), empresa, frota, convoy, auditoria |
| Integration bridges | **XS-Trucking (H)** | autodetecção/força de provedor + API canônica (framework, fuel, inventory, keys, target, dispatch) |
| Ferramentas estáticas FiveM | **XS-Trucking (H)** | 9 verificadores locais (manifest, eventos, NUI, natives, netIds, runtime, multi-retorno, sintaxe) |
| Arquitetura de NUI de trucking | **XS-Trucking (H)** | NUI modular + contrato RPC; **não** replicar o laptop (ver doc 19) |
| Admin / Route Builder | **XS Builder + PropEditor do AUST** | builder admin-only com auditoria; PropEditor para offsets; **ADMIN ONLY** |
| Segurança de mutação | **fiji-oil (I)** + **qbx_core (F)** | locks, claim atômico, API de mutação só no servidor |
| Petróleo | **fiji-oil (I)** | cadeia de suprimento e refino com estado no servidor |
| Flatbed / reboque | **Tow (J)** só para offsets por modelo; o AUST já supera o resto | |
| Parcel / depósito | **ESX Deliveries (K)** (conceito) | UX de depósito/carry; sem enforcement |
| Cleanup / validação | **ox_lib / ox_inventory (L)** | padrões de callback, locks e hooks |
| **Profundidade de gameplay físico** (portas/liftgate, pallet jack, courier com scanner, escolta ativa, oversized, docking de precisão) | **TrueMaps (M)** — **só gameplay (vídeo/brief)** | nenhuma inferência de implementação; ver doc 20 |


> Adendo: aprofundamento do XS-Trucking em `08b_XS_TRUCKING_DEEP_DIVE.md`.

> Adendo: referência de gameplay TrueMaps em `20_TRUEMAPS_GAMEPLAY_REFERENCE.md`.
