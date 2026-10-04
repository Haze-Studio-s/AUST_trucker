# 05 — Gameplay Flow Map

**ANALYZED HEAD: `c9d9187`.** Fluxos **como implementados**, não como documentados. `S` = servidor, `C` = cliente. `[CLIENT-ONLY]` = estado que existe só numa variável/thread do cliente. Citações `arquivo:linha`. Fonte: duas auditorias de leitura de fluxo (cobertura e lacunas ao final) + conferência por amostragem de seis achados (marcados **[VERIFICADO]**).

## 0. Visão geral

Há **três sistemas de job**: (1) **Polarix** (`PolarixLobbies`, estágios `STEP_*`/`STATUS_*`): todo início real do cliente termina em `s:startDelivery` (`main.lua:1351`); (2) **legado** `trucker_jobs` (aceitar → carregar → `completeJob`); (3) **contratos LC** (`ActiveLCContracts`), alcançados só por `truck_logistics:startContract/makeContract` (sem remetente no repositório).

**Estágios do servidor (Polarix):** `STEP_GET_TRUCK` → `STATUS_LOADING` → `STEP_STRAPPING` (só dry) → `STATUS_IN_TRANSIT` → `STATUS_COMPLETING` → (quick job) `STATUS_RETURNING_TO_BASE` → `STATUS_RETURN_COMPLETING`; `STATUS_CANCELLED`. `'STEP_8_IN_TRANSIT'` é checado no servidor (`main.lua:393`) mas **nunca definido no servidor** (nome do cliente). **Estágios do cliente:** `STEP_1_START … STEP_9_DELIVERY, STEP_RETURN_TRUCK` (`client/main.lua`).

## 1. NORMAL DELIVERY (Polarix)

```
ENTRY (NUI "startDelivery")  →  C: HandleStartDeliveryNUI (main.lua:466)  →  TSE s:startDelivery
 → S: StartTruckDelivery (:502-1345): valida, cria entidades, lobby STEP_GET_TRUCK, statebags, timer de pátio
 → C: polarixJobStarted (:2452)  STEP_1_START → STEP_2_ENTER_TRUCK → STEP_3_COUPLE_TRAILER → STEP_4_PARK_DOCK [CLIENT-ONLY]
 → STEP_5_* (por cargo) → STEP_6_* → (strapping) → StartDeliveryRoute → STEP_8_IN_TRANSIT → STEP_9_DELIVERY
 → TSE s:completePolarixDelivery → S: pagamento → polarixJobFinished → COMPLETE
```

| State | Arquivo cliente | Arquivo servidor | Evento | Entidade/netId | Statebag | DB | Validação | Falha | Cleanup |
|---|---|---|---|---|---|---|---|---|---|
| Start | `main.lua:466-495` | `main.lua:502-1345` | `s:startDelivery` | cria truck/trailer/etc.; `LockEntityNetworkOwner` | `activeJobData` (truck), `activeJobId` (player) | nenhuma | whitelist; lock 15 s; 1 lobby; nível/licença; trailer allowlist | spam sem rate limit; sem DB no início | timer de pátio 360 s |
| Entities resolve | `main.lua:2522-2665` (`WaitForNetworkEntity` 4 s) | — | `c:polarixJobStarted` | netIds do payload | — | — | — | timeout deixa a entidade `nil` sem retry | `CleanupCurrentJob` |
| Couple | `main.lua:527` (poll 250 ms) | — | — | `GetVehicleTrailerVehicle` | — | — | só cliente | `inspectionCompleted` nunca enviado | — |
| Dock | `main.lua:555-631` | — | — | — | — | — | doca 4,5 m, ≤ 20° | — | — |
| Load | por cargo (ver §2-§9) | `EnterLoadingStage` | vários | — | `loadedSlots` | — | por evento | — | — |
| Transit | `main.lua:1500-2117` | — | `s:registerJobEntities` (`:1649`) | — | — | — | física do cliente | `STEP_8` só no cliente | `cancelDelivery` (único gatilho: caminhão destruído/na água) |
| Deliver | `main.lua:2128-2200` | `main.lua:2011` | `s:completePolarixDelivery` | apaga entidades | limpa | `0r_trucker`, XP, stats | owner; `IN_TRANSIT`; ped ≤ 35 m; ≥ 10 s; claim `COMPLETING` | cancelar o progress deixa `STEP_9_DELIVERY` sem laço que o trate; recusa do servidor não volta ao cliente | forklift/handler **não** apagados (caminhão próprio) **[VERIFICADO]** |
| Quick-job return | `main.lua:2858-2913` | `main.lua:2234` | `s:returnQuickJobTruck` | — | — | stats | ≤ 45 m; claim | pagamento retido só em memória do lobby (perdido em queda) | `CleanupLobbyEntities` |

**Defeitos de fluxo (estáticos):** o timer de pátio (`main.lua:371-417`) cancela no servidor mas `ClearObjective` não zera `ActiveJob` do cliente, então um novo `startDelivery` é recusado (`main.lua:486`); `/canceljob` e `/clearjob` **não** cancelam o lobby Polarix; `main.lua:1327` usa `selectedTrailerModel` não declarado; `requiredCount` é fixado antes de contar pallets realmente criados (`main.lua:1234`), logo menos pallets que o exigido impedem a conclusão.

## 2. DRY CARGO + PALLET/FORKLIFT

```
STEP_5_ENTER_FORKLIFT → STEP_6_LOAD_PALLETS → ForkliftModule.StartOperation
  frozen → ground_engaged → attached_to_forks (zLift ≥ 0,35) → detached_at_ghost → stowed → TSE polarixPalletLoaded
  → (último) forklift dock [E] → SetupRopesStage → STEP_6_GET_ROPES → STEP_7_STRAP_PALLETS → strappingCompleted
```

| State | Cliente | Servidor | Evento | Entidade | DB | Validação | Falha |
|---|---|---|---|---|---|---|---|
| Spawn | `main.lua:2670-2791` | `main.lua:901-1106` | `c:polarixSyncPallets` | pallets (server, frozen) | — | `PalletSpawnValidation` | `requiredCount` não reduzido |
| Pick/lift | `forklift.lua:690-765` | — | — | pallet | — | — | **client-only**; servidor não conhece CARRIED |
| Stow | `forklift.lua:848-884` | `HandlePalletLoaded` (`main.lua:1429`) | `s:polarixPalletLoaded` | pallet → trailer | — | registry, distâncias, 1/s | recusa **sem reenvio**: o cliente conta localmente e segue, depois `strappingCompleted` e `complete` são recusados: job trava |
| Strap | `main.lua:663-1204` | `main.lua:1891` | `s:strappingCompleted` | — | — | **servidor não verifica as cintas** | — |
| Forklift dock | `forklift.lua:638-681`, `SnapForkliftToSlot` | **servidor nunca informado** | — | forklift anexado ao trailer | — | — | — |

**Código morto relacionado:** `CargoDry.Setup`, `client:startStrappingStage` (sem handler). **Fluxo paralelo:** `forklift.client.lua` (trade point) não faz parte deste.

## 3. LIQUID CARGO (hose)

Servidor completo (`main.lua:1737-1888`): `pickupHose` → `connectHose` → `disconnectHose` (sem tempo de enchimento) → `IN_TRANSIT`. Cliente completo em `cargo_liquid.lua`. **O fluxo é inalcançável:** `CargoLiquid.Setup` não tem chamador **[VERIFICADO]**; o cliente fica em `STEP_5_FUEL_LOADING` (`main.lua:608`) e nada o consome; o `strappingCompleted` recusa `liquid`. Hose do servidor sem lock; hose-fallback do cliente é segunda entidade networked não rastreada.

## 4. STRAPPING

Cliente: `SetupRopesStage` (`main.lua:1441`) → `StartStrappingPalletsStage` (`:1425`) → `ExecutePalletTie` (`:699`, skillCheck + progress) → `CheckAllTiedAndStartRoute` (`:663`) → `StartDeliveryRoute` **e** `s:strappingCompleted`. `isSecured`/`riskLevel` são **client-only**. Falha de tie no forklift chama `SetupForkliftTieTarget`, que é **local declarada depois**, e a chamada global é nil: o retry não acontece (`main.lua:963`/`:1059`).

## 5. TRAILER TRANSIT (perda de pallet, dano)

Tudo é decidido no cliente (`main.lua:1653-2117`): G-meter, queda de pallet (roll > 32° ou zona crítica > 55 km/h), impulso, 60 % de chance de sobreviver abaixo de 60 km/h, `cargoHealth -= 20` (local, nunca enviado). Servidor recebe `s:palletLost` (`main.lua:1959`) e só soma `lostPallets` (teto `requiredCount`). O **resgate** reenvia `polarixPalletLoaded`; em trânsito o servidor só decrementa `lostPallets` (`main.lua:1443-1448`): o cliente desfaz perdas à vontade. `loadedSlots` nunca é limpo para pallets caídos.

## 6. PARCEL

```
Depot NPC → AcceptParcelMission → cb parcel:accept → ParcelState{active, currentStop=1}
 → pickup (progress 3 s, CarrySystem) [CLIENT-ONLY] → por parada: cb parcel:nextStop → … → depot: cb parcel:complete → pagamento
```
Servidor: cooldown, nível, rota; `nextStop`: RL 3 s e posição fail-closed (≤ 15 m); `complete`: `currentStop > totalStops`, depósito ≤ 20 m, estado limpo antes do pagamento. **Lacunas:** recusa de `nextStop`/`complete` faz o cliente chamar `CleanupParcel` sem `cancel`: o servidor mantém a missão ativa até a varredura de 30 min; o servidor não verifica que o jogador carrega encomenda; cooldown só no `complete`.

## 7. CONTAINER / REACH STACKER

- **7a. Heavy dentro do Polarix:** `STEP_5_ENTER_HANDLER` → `STEP_6_LOAD_CONTAINER` → `ReachStackerModule.StartOperation` ([G] pega/solta) → `s:heavyContainerLoaded` (enviado 2×) → `IN_TRANSIT`. O servidor **não** verifica container/attach/handler.
- **7b. Container Handler (missão separada):** `containerHandler:start` → `CH_STATE idle→pickup→deliver→done` [CLIENT-ONLY] (handler networked criado pelo cliente; container **local, invisível a outros**) → `complete` (20 s, ped ≤ raio do slot do servidor; **sem licença**). Recusa do `complete` (cedo/longe): o cliente já voltou a `idle`, não envia `cancel`, e o próximo `start` é recusado ("já tem uma missão ativa") até a queda do jogador.

## 8. CAR CARRIER

Servidor cria 3 carros (`main.lua:1164-1191`). Cliente chama `CarCarrierModule.StartLoadingOperation(jobId, trailer, ActiveJob.vehicleNetIds, cb)` (`main.lua:614`) e compara **netIds com handles** (`car_carrier.lua:158-160`) **[VERIFICADO]**; `onCompleted()` é chamado sem argumentos mas o callback testa `action == 'completed'`; `StartDeliveryRoute` é chamada em `main.lua:619` antes do `local` (`:661`) **[VERIFICADO]**. O único caminho do servidor para trânsito é o `strappingCompleted` genérico, **que o cliente nunca envia** para esse cargo. **O job não completa no jogo normal**; um cliente que envie `strappingCompleted` pula o carregamento.

## 9. REPO / FLATBED

```
loan overdue (por parcela!) ou pool NPC (5 / 30 min) → trucker_repo_orders 'available'
 → NUI → cb acceptRepoOrder (CAS) → c:startRepoMission → [CLIENT-ONLY] alvo criado pelo cliente
 → simple/stealth: "Assumir Veículo" → driving_to_impound ;  npc_hostile/pvp: flatbed + guardas + attach
 → zona do impound → s:completeRepoOrder → proximidade (2× raio) + ≥ 30 s → pagamento (mint) + abatimento de dívida
```
O servidor nunca verifica veículo, attach ou fase. **Falha:** `s:failRepoOrder` devolve a ordem a `available`; queda/timeout do cliente **não avisam** o servidor (ordem fica `active`, bloqueando novas, até `expires_at`); `GenerateFromLoan` roda a **cada parcela perdida**; empréstimo `defaulted` não recebe abatimento (`loan.status=='active'`, `repo_service.lua:191`). O alvo de missão simples/stealth entregue **permanece** no mundo.

## 10. CRUDE OIL

Aceite no quadro só dá GPS (permit/DEFCON fail-closed); a carga é registrada por **export de recurso externo** (`StartCrudeJob`), sem validar `qty`/`price`; entrega: progress client-only (`qty × 2000 ms`) → `completeCrudeDelivery(plate, refineryId)`: dono do job, ped ≤ raio×3,5 (caminhão não verificado), tempo mínimo → paga em **cash**. `abandonCrudeJob` sem chamador no repositório; sem `onResourceStop` que devolva barris.

## 11. ADR

Exame: perguntas emitidas e corrigidas no servidor (3, TTL 900 s, lock, taxa antes da correção, cooldown 1 800 s). Dois sistemas de certificação (`trucker_adr_certs` × `trucker_licenses.adr_certified`). Gate no quadro: `JobService.Accept` retorna `false` sem certificado, e o chamador mostra a mensagem de ADR para **qualquer** falha de aceite. **Módulo de hazard** só roda no Polarix `adr`; vazamento não contido nunca é reportado (integridade fica 100). **O job Polarix `adr` não tem driver de cliente para sair de `STEP_5_FUEL_LOADING`** (mesma causa do liquid).

## 12. ILLEGAL JOB

`getIllegalJobs` → `acceptIllegalJob` (proximidade, lock, sem job ativo) → `IllegalService.Generate` (job inserido como `active`). **O cliente não inicia o fluxo**: `c:jobStarted` só é emitido por `acceptJob` (`events.lua:239`) **[VERIFICADO]**; o callback não o dispara; então `currentJob` fica `nil` e a entrega ilegal (`triggerComplete` → `CompleteJob`) retorna na primeira linha. Apreensão: `truckStateChanged` → `illegalRegisterPlate` → `IllegalTargets[plate]`; polícia/sasp com lock e `SeizeRange`; `illegalJobStarted` é transmitido a **todos**. `IllegalTargets` não é limpo na queda.

## 13. CARGO THEFT

Armar (dono): `registerTruckPlate` com placa lida da entidade → `RegisterCargo`. Vulnerável: `cargoPlayerLeft` (autodeclarado) → 30 s → `ct_vulnerable` (**statebag escrita pelo cliente**). Roubo: `startCargoTheft` (driver, ≤ `TheftRange`) → progress 20 s [CLIENT-ONLY] → `completeCargoTheft` (`elapsed ≥ TheftDuration − 2`, proximidade) → entrada nova com `isStolen`; entrega: `completeJob` → `CompleteTheft` **sem `ClaimJob`** (SEC-07). Queda do dono remove a carga; queda do ladrão cancela o roubo.

## 14. PARTY

`partyCreate/Join/Invite/Accept/Kick/Leave/Disband` (cbs; os eventos `party:*` não têm consumidor). Estado só em `VP_Trucker.Parties` (sem `LoadFromDB`). Queda: grace 180 s → `LeaveByIdentifier`; reconexão cancela. `Join` não checa convoy ativo. `Kick` não chama `MemberAbandon`: convoy do kickado não paga até `Disband`.

## 15. CONVOY

`convoyStart` (líder) → `ConvoyService.Start`: ≥ 2 membros → `DB_CreateConvoy` → `GenerateConvoyBatch` → cache → `StartPositionBroadcast` → `convoyStarted`. **Defeito 1:** `SetInterval(Config.Party.positionBroadcastInterval, function…)` com o número primeiro (`convoy_service.lua:22`) **[VERIFICADO]**, enquanto `ox_lib` local define `SetInterval(callback, interval)`; se o `ox_lib` implantado tiver essa assinatura, `Start` falha **depois** de criar as linhas e **antes** de notificar os membros (versão implantada **não verificada**). **Defeito 2:** os jobs de membros são inseridos `available` sem atribuição; qualquer jogador pode aceitá-los pelo quadro público (SEC-09). Pagamento: `_PayAll` quando `activeCount == 0`, idempotente (`DB_ClaimConvoyPayment`); offline vira `trucker_pending_payouts`. `Config.Party.bonusMultiplier` não é usado.

## 16. NPC DRIVER

Contratar (callback, dono/gerente, distância no servidor, taxa) → `ProcessTick` a cada 5 min (descansa → idle; trabalhando → rola evento; idle → `_TryAssignJob`) → `_CompleteJob` credita a empresa (mint) e **devolve o job a `available`**. `_TryAssignJob` reserva com `UPDATE … WHERE status='available'` **sem checar linhas afetadas**: dois motoristas no mesmo tick podem pegar o mesmo job (não confirmado). Eventos graves: auto-resolvem em `ignore` após o timer; contrabando "pagar sem fundos" deixa motorista/job presos (`npc_driver_service.lua:443-449`). O segundo sistema (`trucker_drivers`) só grava tabelas; nenhum laço os faz trabalhar.

## 17. EMPRESA / FROTA / ALUGUEL / EMPRÉSTIMOS / CONTRATOS (efeito no fluxo)

- **Empresa:** criação cobra US$ 150 000 (cash) com lock e reembolso; **venda** (`US$ 25 000 + saldo do cache`) não libera indústrias nem `IndustryOwners`. Vender com veículo `out` é bloqueado, e nada reseta `out` após queda.
- **Frota:** dois modelos; `fleet:repairTruck` (evento) ignora o lock do serviço.
- **Aluguel:** `rentTruck` (taxa+caução, placa única) → cliente cria o veículo → `registerNetId` → `returnTruck` (reembolso por pior saúde amostrada). **Defeito provável:** na queda, `events.lua:1233-1239` apaga o caminhão registrado **antes** de `TruckRentalService.OnPlayerDropped` (`:1240`); se `DoesEntityExist` já for falso, `computeRefund` devolve 0 e a caução fica `refund_due = 0` (**ordem lida; efeito em runtime não confirmado**).
- **Empréstimos:** juros fixos de 5 % na criação; `TakePlan` usa pagamento diário (`+1 dia`) mas `CheckOverdue` reagenda por 7 dias; ordem de repo por parcela perdida.
- **Contratos:** `Negotiate` já "aceita" na criação; não há gerador periódico (`Config.Contracts.refreshInterval` não usado).

## 18. TRUCK SIMULATION

Init no login; `OnVehicleSpawn(plate)` (**placa do cliente**); `OnSync` (RL 1 s, queda de combustível limitada, integridade só diminui, coords do cliente); `payForFuel` calcula preço no servidor; `GetLastIntegrity` lido uma vez pelo `JobService.Complete` (padrão 100). `vehicleDestroyed` só força sync (o comentário sugere que `JobService` marca falha: não encontrado).

## 19. INDUSTRY / OWNERSHIP / SHOP STOCK

- **Trade:** `buyFromIndustry`/`sellToIndustry` (RL 750 ms, `posInt ≤ 500`, ≤ raio+5): compra cobra cash, reserva estoque atômico, `AddItem`, reembolso se falhar; venda `RemoveItem` antes de pagar (mint). 
- **Produção:** primária **+1** a cada 60 s (ignora `productionPerHour`); secundária +1 a cada 10 min **sem consumir entrada**; **não há laço que aplique `consumptionPerHour`**; failsafe NPC a cada 5 min. A tela "Status de Produção" da NUI espera chaves que `GetAll` nunca devolve.
- **Posse:** `Buy` com lock e `INSERT IGNORE`; `RunOperationalCosts` debita US$ 500 por indústria **a cada ciclo primário (60 s)** (impacto econômico não avaliado).
- **Shop stock:** hook `buyItem` consome estoque (atômico). Contratos de **resupply** são criados `available`, mas **nenhum caminho os aceita** (`DB_AcceptContract` só é chamado em `Negotiate`) e `pending_contract_id` só é zerado por `DB_RestockShop`: loja baixa fica sem reposição (**dead end**).

## Tarefas periódicas do servidor

| Tarefa | Arquivo | Período | Muta |
|---|---|---|---|
| Geração de jobs + `jobsUpdated` (broadcast) | `events.lua:903-915` | `Config.JobGeneration.refreshInterval` = 1 800 000 ms (30 min, `config.lua:693`; verificado) | `trucker_jobs` |
| Pool NPC de repo / expiração | `repo_service.lua:287-310` | 1 800 s / 300 s | ordens |
| Empréstimos vencidos | `loan_service.lua:414-423` | 300 s | empréstimos, saldos, repo |
| Tick de NPC drivers | `npc_driver_service.lua:906` | 5 min | motoristas/jobs/saldo |
| Produção primária (+ custos de dono) / secundária / failsafe | `industry_service.lua:233-259` | 60 s / 10 min / 5 min | estoque, saldos |
| Preços | `economy_service.lua:114-126` | 20 min (+ debounce 5 s) | preços |
| Shop stock: checagem / failsafe NPC | `shop_stock_service.lua:233-250` | 5 min / 15 min | contratos, estoque |
| Amostrador de aluguel | `truck_rental_service.lua:357` | 3 s | memória |
| Grace de queda (job GC) / party / theft | `events.lua:399`, `party_service.lua:423`, `cargo_tracking_service.lua:369` | 180 s / 180 s / 30 s | entidades, membership, carga |

## Cobertura e limites

Relatórios de fluxo leram `server/main.lua`, `server/events.lua` (≈ 70 %), `job_service`, serviços de repo/crude/ADR/illegal/theft/party/convoy/NPC/company/loan/rental/fleet/contract/simulação/indústria/shop, e quase todos os arquivos de cliente por domínio. **NOT READ:** corpos de `StartLCContractForPlayer`/`FinalizeLCContract` (lidos pela auditoria de segurança, não pela de fluxo), `server/adr_questions.lua`, `AUST_oilfield`/`AUST_governo` (externos), valores de `Config.ParcelDelivery`/`Config.ContainerHandler`.
