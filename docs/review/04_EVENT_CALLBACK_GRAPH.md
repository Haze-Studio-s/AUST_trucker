# 04 — Event / Callback Graph

**ANALYZED HEAD: `c9d9187`.** Mapa de `RegisterNetEvent`, `TriggerServerEvent`, `TriggerClientEvent`, `lib.callback`, NUI e exports. Fonte: leitura integral de `server/main.lua` e `server/events.lua`, ≈ 90 % de `server/callbacks.lua`, e inventário do cliente; **consumidores** foram achados por grep (`client/`, `server/`, `shared/`, `html/js`). Prefixos: `s:` = `aurp_trucker:server:`, `c:` = `aurp_trucker:client:`, `a:` = `aurp_trucker:`.

Marcas: **DUPLICATE**, **ALIAS**, **NO CONSUMER**, **MULTIPLE CONSUMERS**, **AUTHORITY RISK**, **UNKNOWN**. Colunas: V = validação no servidor; RL = rate limit; RS = retry-safe; $ = paga dinheiro; P = muda progresso.

> **Cobertura:** `server/callbacks.lua` 1–574 só por registro de nomes; handlers de serviço (`XService.*`) foram auditados nos relatórios de serviços. "NOT READ" aparece onde aplicável.

## 1. Polarix (lobby), `server/main.lua`

| Evento | Produtor → Consumidor | V (resumo) | Estado/Entidade | $ P | RS | RL | Marcas |
|---|---|---|---|---|---|---|---|
| `s:startDelivery` | `client/main.lua:495`, `client.lua:608/806` → `main.lua:1351` | whitelist de campos; lock de spawn 15 s; 1 lobby; nível/licença; modelos; trailer | cria lobby, entidades, statebags `activeJobData`/`activeJobId` | – / – | parcial | **não** | AUTHORITY RISK (baixo): `palletCount`, `truckPlate` (`LIKE`) |
| `s:inspectionCompleted` | **nenhum** → `main.lua:1356` | owner, estágio, ≤ 6 m | estágio→`STATUS_LOADING` | – | sim | – | **NO CONSUMER** |
| `s:polarixPalletLoaded` | `modules/forklift.lua:884`, `main.lua:1278` → `HandlePalletLoaded` | owner, dry, `PalletRegistry`, estágio, ≤ 40 m, 1/s, pallet ≤ 60 m do trailer, offsets clampados | `loadedCount`, `loadedSlots` | – / sim | **sim** (`retry`) | 1/s por lobby | **duas formas de argumento** (`main.lua:1278` manda `#LoadedPallets` como slot e sem netId) |
| `s:attachPalletToTrailer` | nenhum → mesmo handler | idem | idem | – / sim | sim | – | **ALIAS, NO CONSUMER** |
| cb `s:palletClaim` | **nenhum** | owner, dry, `reqId`≤64, estágio, ≤ 12 m, ped no forklift do lobby, CAS | `lobby.palletStates` | – | sim | – | **NO CONSUMER** (flag desligada) |
| `s:palletConfirmCarry`, `s:palletRelease` | nenhum | CAS por registro | idem | – | sim | – | **NO CONSUMER** |
| `s:palletKinematicOff` | nenhum | owner | `lobby.kinematicOff` | – | sim | – | **NO CONSUMER**; AUTHORITY RISK se ligado |
| `s:pickupHose`, `connectHose`, `cancelHose`, `hoseLeak`, `disconnectHose` | `client/cargo_liquid.lua:85-290` → `main.lua:1738-1888` | owner, liquid, terminal ≤ 15 m, trailer ≤ 12/10 m, re-entrância | cria/apaga hose; `loadedCount=100` | `hoseLeak` debita R$ 1 500 / sim | sim (estágio) | – | **fluxo inalcançável** (`CargoLiquid.Setup` sem chamador); AUTHORITY RISK: leak decidido no cliente |
| `s:strappingCompleted` | `main.lua:693/853/954/1071` → `:1891` | owner; dry exige `STEP_STRAPPING` + todos carregados; liquid/heavy recusados; resto só `EnterLoadingStage`; ≤ 60 m | estágio→`IN_TRANSIT`; descongela pallets; apaga forklift se `withForklift=false` | – / sim | sim | – | SEC-02 (adr/vehicle_carrier) |
| `s:palletLost` | `main.lua:2017` → `:1959` | owner, `IN_TRANSIT`, teto | `lostPallets++` | reduz pagamento | – | – | AUTHORITY RISK: só existe se o cliente reportar |
| `s:heavyContainerLoaded` | `reach_stacker.lua:179`, `main.lua:2441` → `:1975` | owner, heavy, `EnterLoadingStage`, ≤ 60 m | `IN_TRANSIT`, `loadedCount=1` | – / sim | sim | – | **MULTIPLE PRODUCERS** (envio duplo) |
| `s:adrLeakContained` | `adr_hazard.lua:96` → `:1993` | owner, adr, clamp, só diminui | `cargoIntegrity` | afeta pagamento | sim | – | vazamento não contido nunca reportado |
| `s:completePolarixDelivery` | `main.lua:2188` → `:2011` | owner; `IN_TRANSIT`; ped ≤ 35 m; saúde do caminhão; ≥ 10 s; claim `COMPLETING` | apaga entidades; statebags | **sim** (bank, XP, 3 stores) | sim (reverte estágio se falhar) | – | SEC-02 |
| `s:returnQuickJobTruck` | `main.lua:2913` → `:2234` | owner, estágio, ≤ 45 m, claim | cleanup | **sim** | sim | – | AUTHORITY RISK: inspeção do cliente (SEC-20) |
| `s:cancelDelivery` | `main.lua:1669` (**único** gatilho) → `:2352` | owner, não em `COMPLETING` | cleanup | – | sim | – | `/canceljob`/`/clearjob` **não** chamam este evento |
| `s:emergencyRespawnEquipment` | `main.lua:453` → `:2381` | owner, dry, estágios, 10 s | cria forklift | – | rl | 10 s | forklift sem plate/chaves/lock |

## 2. Entidades e jobs legados, `server/events.lua`

| Evento | Produtor → Consumidor | V | Efeito | $ P | RS | Marcas |
|---|---|---|---|---|---|---|
| `a:acceptJob` | **nenhum (NUI chama `startDelivery`)** → `events.lua:165` | RL 3 s; sem job ativo; ADR; CAS no banco | `JobService.Accept` | – | – | **NO CONSUMER**; LEGACY_CANDIDATE; SEC-09 (convoy) |
| `a:completeJob` | `hud.client.lua:410` → `events.lua:244` | RL; `ClaimDelivery`; `ValidateDelivery`; CAS | `JobService.Complete`/`CompleteTheft` | **sim** | sim | payload ignorado (integridade vem de `SimState`) |
| `a:abandonJob` | `client.lua:366/2254/2887` → `:279` | player | `JobService.Abandon`; apaga entidades verificadas | – | sim | alimenta SEC-01 |
| `s:registerJobEntities` | `client.lua:237/1788/2467`, `main.lua:1649` → `:297` | `validateJobEntity` (tipo, ≤ 250 m, lobby, **ou dono de rede**) | `PlayerJobEntities`, lock, `GiveKeys` | – | sim | **AUTHORITY RISK** (SEC-01) |
| `a:rental:registerNetId` | `client.lua:877` → `:416` | RL 1 s; `RegisterNetId` | chaves | – | sim | – |
| `s:onPlayerDeath` | `client.lua:1706` → `:439` | – | apaga truck/trailer verificados; `Abandon` | – | sim | não toca o lobby Polarix |
| `a:updateForkliftExpected`, `a:forklift:setNetId`, `a:palletLoaded` | `forklift.client.lua:341/136/90` → `events.lua:1094/1110/1144` | RL 400 ms; tipo 3; modelo; **statebag `forklift_owner` (escrita pelo cliente)**; ≤ 40/150 m | `rental.loaded++`, apaga pallet | – / sim | sim (objeto some) | **AUTHORITY RISK** (SEC-05); **nome parecido com `polarixPalletLoaded`** |
| `a:syncSimulation`, `a:vehicleDestroyed`, `a:spawnVehicle`, `a:purchaseFleetUpgrade` | `hud.client.lua:61/130/169` → `:1246-1258` | RL 1 s (`force=true` em destroyed) | `SimState` | upgrade debita | – | `purchaseFleetUpgrade`: **NO CONSUMER**; AUTHORITY RISK (SEC-16) |
| `a:seizeIllegalCargo`, `a:illegalRegisterPlate` | `illegal.client.lua:147/185/124` → `:1286/:1355` | polícia/sasp; lock; placa do servidor | `IllegalService.Seize` | multa | lock | – |
| `a:registerTruckPlate`, `cargoPlayerLeft`, `cargoPlayerReturned`, `startCargoTheft`, `completeCargoTheft`, `cancelCargoTheft` | `cargo_theft.client.lua` → `events.lua:1398-1587` | placa lida da entidade; driver; distâncias | `CargoByPlate` | roubo paga depois | – | `cargoPlayerLeft` autodeclarado |
| `a:containerHandler:cancel` | `container_handler.client.lua:138/177` → `:1602` | – | cancela | – | sim | – |

## 3. Contratos LC, `server/events.lua`

| Evento | Produtor | Consumidor | V | $ | Marcas |
|---|---|---|---|---|---|
| `s:startLCContract` | **nenhum** | `:2126` | RL 2 s | via Polarix | **NO CONSUMER**; redireciona a `GlobalStartTruckDelivery` (sempre definido): ramos party/LC mortos |
| `truck_logistics:startContract` / `makeContract` | **nenhum** | `:2217` / `:2239` | RL 3 s | pagamento depois | **DUPLICATE** (corpos idênticos); NO CONSUMER |
| `s:cancelActiveLCContract` / `truck_logistics:cancelContract` | `client.lua:857/2252` / nenhum | `:2148` / `:2183` | RL | – | **DUPLICATE**; **não atualiza o banco** (SEC-04) |
| `s:finishQuickJobContract` / `finishOwnedTruckContract` | `client.lua:3365/3281` | `:2671` / `:2675` | lock; `ValidateLCDelivery`; CAS | **sim** | usa linha do banco; ignora args extras |
| `s:completeLCContract` / `truck_logistics:finishContract` | nenhum | `:2679` / `:2683` | idem | sim | **NO CONSUMER**; `FinalizeLCContract` faz `DropPlayer` em repetição |
| `truck_logistics:buyTruck` / `sellTruck` | nenhum | `:2687/2702` | – | sim | **NO CONSUMER**; triplicado com `fleet:*` e callbacks |

## 4. Empresa, frota, empréstimos, progressão

| Evento/callback | Produtor | Consumidor | V | $ | Marcas |
|---|---|---|---|---|---|
| `a:createCompany/joinCompany/leaveCompany/kickMember/toggleRecruiting/sellCompany` | `client.lua:2343-2356, 973-996` | `events.lua:463-703` | papel/dono; locks | create/sell movem | SEC-14/18 |
| `a:depositMoney` / `a:withdrawMoney` | `client.lua` | `:561` / `:586` | `posInt`; papel (saque) | sim | **DUPLICATE** de `a:bank:deposit/withdraw` (`:2892/:2918`, RL diferente) |
| `a:registerVehicle` / `removeVehicle` | `client.lua` | `:617` / `:682` | papel; placa; ≤ 20 m; ≤ 100 | – | `DB_RegisterVehicle` com parâmetros trocados (`database.lua:741-745`) |
| `a:requestLoan` | `client.lua:2734` | `:921` | `posInt`; papel; placa | credita | **DUPLICATE** de `loan:takePlan` e cb `takeLoanPlan` (índice com offset +1 × sem offset) |
| `a:loan:payOff` / cb `payLoan` | `client.lua:2779` | `:2821` / `callbacks.lua:890` | dono do empréstimo; clamp | debita | cb sem rate limit |
| `a:fleet:buyTruck/sellTruck/repairTruck` | `client.lua:631-647` | `:2722-2750` | catálogo; lock (exceto `repairTruck`) | sim | **TRIPLICADO** com `truck_logistics:*` e cbs; `repairTruck` **ignora o serviço** |
| `s:upgradeSkill` / cb `upgradeSkill` / cb `purchaseSkill` | `client.lua:655` | `:2782` / `:1645` / `:861` | whitelist | gasta ponto | **DUPLICATE** (funções diferentes do serviço) |
| `a:driver:hireAgency/fireHired/setTruck` / cbs equivalentes | `client.lua` | `:2843-2875` / `callbacks.lua:1621-1637` | papel | sim | **DUPLICATE** |
| `a:party:create/join/invite/kick/leave` | **nenhum** | `:2950-3001` | – | – | **NO CONSUMER**; **DUPLICATE** dos cbs `party*` (usados) |
| `a:negotiateContract` (evento) e cb | `client.lua:2907` | `:793` / `callbacks.lua:657` | membro; clamps | contrato | **DUPLICATE**; sem rate limit |
| `a:completeContractStop` / `abandonContract` | `client.lua:3035/2958` | `:804` / `:831` | RL; sequência; proximidade | paga no fim | – |
| `QBCore:Server:OnPlayerLoaded` / `esx:playerLoaded` | framework | `:861` / `:882` | – | paga pendências | idempotente por DELETE |

## 5. Repo, flatbed, crude, forklift (callbacks)

| Evento/callback | Produtor | Consumidor | V | $ | Marcas |
|---|---|---|---|---|---|
| cb `a:acceptRepoOrder` | `client.lua:2796` | `callbacks.lua:929` | CAS `available→active` | – | – |
| `a:completeRepoOrder` / `failRepoOrder` | `repo.client.lua:217/285…` | `events.lua:1000/1026` | dono; ≥ 30 s; ≤ 2× raio | **sim** | SEC-06; `reason` ignorado |
| `a:repoAgentPositionUpdate` / `repoNotifyOwner` | `repo.client.lua:422/260` | `:1036` / `:1055` | ordem do agente | – | coords sem limite (SEC-27) |
| `a:flatbed:{Lower,Raise,Attach,Detach}Flatbed/Vehicle`, `DeleteBedEntity` | `flatbed.client.lua` | `flatbed.server.lua:166-275` | RL 1 s; modelo; distâncias | – | SEC-13 |
| `s:completeCrudeDelivery` | `client/crude_oil.lua:59` | `crude_oil.lua:71` | dono; ped ≤ raio×3,5; tempo | **sim** | só ped |
| `s:abandonCrudeJob` | **nenhum** | `crude_oil.lua:179` | dono | devolve barris | **NO CONSUMER** no repo |
| export `StartCrudeJob` | recurso externo `AUST_oilfield` (NOT READ) | `crude_oil.lua:24` | **nenhuma** (qty/preço do chamador) | – | confiança no recurso externo |
| cbs `a:rentForklift/returnForklift/completeTradePoint` | `forklift.client.lua:411/495/183/264` | `callbacks.lua:1422/1466/1480` | locais; `Cleanup` antes de pagar | **sim** | `returnForklift` reembolsa sem checar |
| cbs `a:containerHandler:start/complete` | `container_handler.client.lua:161/296` | `callbacks.lua:1568/1576` | 20 s; ped ≤ raio do slot do servidor | **sim** | SEC-03; envia `coords` ignoradas |
| cbs `a:parcel:accept/nextStop/complete/cancel` | `parcel_delivery.lua` | `parcel_service.lua:71-306` | posição fail-closed; RL 3 s | **sim** | cliente chama `CleanupParcel` sem `cancel` em recusa |
| cbs `a:getAdrExamQuestions/submitAdrExam/renewAdrCert` | `adr.client.lua` | `callbacks.lua:1256-1414` | conjunto emitido pelo servidor; TTL; lock | cobra | taxa antes de corrigir |
| cb `a:takeLicenseExam` | `client.lua:1926` | `callbacks.lua:1671` | tipo; nível | cobra e emite | prova corrigida no cliente |
| cb `a:payForFuel` | `hud.client.lua:448` | `callbacks.lua:935` | preço do servidor | debita | combustível vem do cliente |
| cbs `a:getIllegalJobs/acceptIllegalJob` | `illegal.client.lua:35/49` | `callbacks.lua:1039/1078` | proximidade; lock | gera job | **não dispara `client:jobStarted`** |

## 6. Callbacks de leitura (`callbacks.lua`)

`getInitialData` (`:549`), `getCompanyMembers/Vehicles/History`, `getClients`, `getPlayerStats/Skills`, `getSkills`, `getLoanData`, `getConvoyHistory`, `getIndustries`, `getIndustryData`, `getIndustryOwnership`, `getRepoOrders`, `getRefineries`, `getNpcDriverData`, `getLicenses`, `getTrailerOffsetsForModel`. Marcas: `getSkills` **DUPLICATE** de `getPlayerSkills`; `getSkills`, `getLoanData`, `getRepoOrders`, `getIndustryOwnership` e `buyIndustry` **NO CONSUMER** no cliente do repo (grep); `getTrailerOffsetsForModel` recarrega do banco a cada chamada; `getCompanyHistory` com cache de 60 s sem invalidação.

## 7. Servidor → cliente (catálogo)

| Grupo | Eventos | Observações |
|---|---|---|
| Polarix | `c:polarixJobStarted`, `polarixSyncPallets`, `polarixReadyForTransit`, `polarixJobFinished`, `polarixCargoDeliveredReturnRequired`, `polarixProgressSync`, `dryProgressSync`, `hosePickedUp`, `hoseConnected`, `hoseCancelled`, `playLeakPtfx`, `liquidLoadingCompleted`, `inspectionUnlocked` | `inspectionUnlocked` **sem handler**; `dryProgressSync` handler sai cedo (`CurrentJobData` nil) |
| Jobs | `c:jobStarted`, `jobCompleted`, `jobAbandoned`, `jobsUpdated` (broadcast 5 min), `levelUp` (**handler duplicado** `client.lua:2309/3599`), `a:notify` | `jobStarted` só é emitido por `acceptJob` |
| Empresa/Empréstimo/Repo | `companyUpdated`, `loanUpdate`, `updateRepoOrders`, `startRepoMission` (**2 handlers**), `repoMissionEnded`, `repoOwnerMissionEnded`, `repoTargetNotify`, `repoAgentUpdate` | – |
| Party/Convoy | `partyUpdate`, `partyDisbanded`, `partyInvite`, `convoyStarted`, `convoyEnded`, `positionsUpdate`, `cbMessage` | `convoyStarted` não é emitido se `ConvoyService.Start` falhar em `SetInterval` |
| Theft/Illegal | `startCargoMonitoring`, `cargoVulnerable(Other)`, `cargoStolen`, `cargoTheftAlert`, `cargoClear` (broadcast), `policeCargoAlert`, `theftApproved/Cancelled`, `stolenJobStarted`, `illegalJobStarted/Ended` (broadcast), `cargoSeized`, `seizureSuccess`, `policeAlert` | `illegalJobStarted` vai a **todos** |
| Admin/PropEditor | `adminSyncOffsets`, `adminSyncVehiclePropOffsets`, `adminSyncProps`, `adminSyncNPCs`, `adminSyncEconomy` (**sem listener no cliente**, grep) | broadcast `-1` com tabelas completas |
| Outros | `SetObjective`/`ClearObjective`, `crude*`, `tradePointTimeout`, `allPalletsLoaded`, `npc*`, `setFatigue/VehicleFuel/SimConfig` | – |

## 8. NUI callbacks

`client/client.lua` ≈ 45 (roteador `post` + `close/closeUI/closeMenu/closeModal/focusMenu/cancelJob`, rental, spawnTrailer, empresa/frota/empréstimo/party/NPC/contrato/repo); `client/main.lua` 29 (`startDelivery/acceptJob/startJob/startContract/confirmJob`, `closeMenu/closeModal/cancelJob/focusMenu`, 19 `admin*`, `escapeNui`); `modules/offset_editor.lua` 11; `adr.client.lua` 2; `industries.client.lua` 2. **MULTIPLE CONSUMERS:** `closeMenu/closeModal/focusMenu/cancelJob` em `main.lua:514-517` e `client.lua:834-859` (o `cancelJob` do `client.lua` executa `canceljob`, o do `main.lua` só fecha o menu; **o comportamento com dois registros é do runtime: UNKNOWN**); `getIndustries` em `client.lua` e `industries.client.lua`.

## 9. Exports

| Export | Arquivo | Observação |
|---|---|---|
| `GetParcelWorkers`, `IsDoingParcel`, `GetPlayerActiveJob`, `GetJobManifest`, `GetCompanyInfo`, `GetPlayerCompany`, `GetInfractions`, `GetPlayerFuel`, `GetPlayerFatigue`, `GetActiveJobByPlate`, `RecordInfraction`, `CheckPlayerAdr`, `GetActiveCrudeJobsSummary`, `StartCrudeJob` | `server/exports.lua`, `crude_oil.lua` | `GetCompanyInfo` devolve a tabela viva do cache |
| `ConsumeShopStock`, `RestockShop`, `GetShopStock`, `GetAllShopStocks` | `exports_shop.lua` | `ConsumeShopStock` devolve `true` se o serviço não existe |
| `GetVehiclePropOffset`, `OpenLicensesMenu`, `GetCargoIntegrity`, `getDataFor` | cliente / `callbacks.lua:572` | – |

## 10. Globais importantes cruzando arquivos

Servidor: `VP_Trucker`, `PolarixLobbies` (**local**), `GlobalStartTruckDelivery`, `PolarixOwnsEntity`, `LockEntityNetworkOwner`, `IsSpawnPointClear`, todos os `*Service`, `SchemaService`, todos os `DB_*`, `PalletRegistry`, `PalletSpawnValidation`, `PalletSyncGuard`. Cliente: `_G.JobEntities`/`ActiveJob`/`LoadedPallets` (**obsoletos**), `ForkliftModule`, `Zones`, `CargoDry`, `CargoLiquid`, `Flatbed`, `PalletDebug`, `PalletSyncState`, `SendMissionNotify`, `UpdateMissionObjective`. **`VP_Trucker` não é definido no cliente**, mas `client.lua:2760` espera `VP_Trucker.Ready`: o NPC do banqueiro nunca é criado.

## 11. Resumo de marcas

| Marca | Itens |
|---|---|
| **DUPLICATE** | `depositMoney`/`bank:deposit`; `withdrawMoney`/`bank:withdraw`; `requestLoan`/`loan:takePlan`/cb `takeLoanPlan`; `fleet:*`/`truck_logistics:*`/cbs de frota; `upgradeSkill` ×3; `driver:*`/cbs; `party:*`/cbs; `negotiateContract` evento+cb; `startContract`/`makeContract`; `cancelActiveLCContract`/`truck_logistics:cancelContract`; `getSkills`/`getPlayerSkills` |
| **ALIAS** | `attachPalletToTrailer` → `HandlePalletLoaded`; `finishOwnedTruckContract`/`finishQuickJobContract`/`completeLCContract` |
| **NO CONSUMER** | `inspectionCompleted`, `acceptJob`, `startLCContract`, `truck_logistics:*`, `party:*` (eventos), `purchaseFleetUpgrade`, `abandonCrudeJob`, `palletClaim`/`ConfirmCarry`/`Release`/`KinematicOff`, `attachPalletToTrailer`, `adminSyncEconomy` (sem listener) |
| **MULTIPLE CONSUMERS/PRODUCERS** | `heavyContainerLoaded` (2 produtores); NUI `closeMenu…`; `startRepoMission`/`levelUp`/`getIndustries` |
| **AUTHORITY RISK** | `registerJobEntities`, `palletLoaded` (trade point), `returnQuickJobTruck`, `palletLost`, `hoseLeak`, `syncSimulation`/`spawnVehicle`, `containerHandler:complete(coords)` (ignorado), `StartCrudeJob` (externo), `negotiateContract(terms)`, `payLoan(amount)` |
