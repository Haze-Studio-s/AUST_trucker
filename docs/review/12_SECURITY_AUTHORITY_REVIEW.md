# 12 — Security / Server Authority Review

**ANALYZED HEAD: `c9d9187`.** Auditoria estática de código (nada foi executado). **Nenhuma correção foi feita.** Duas auditorias independentes (economia/empresa e jogabilidade) foram consolidadas; onde discordam, a divergência e a decisão estão registradas. Itens marcados **[VERIFICADO]** foram conferidos por mim no código depois do relatório.

Severidade: **P0** = dinheiro/itens arbitrários por qualquer cliente; **P1** = pagamento completo repetível ou dano a terceiros com cliente trivial; **P2** = abuso limitado/griefing/validação fraca; **P3** = higiene/defesa em profundidade.

## Resumo

| | Qtde |
|---|---|
| **P0** | **0** |
| **P1** | **8** |
| **P2** | **14** |
| **P3** | **12** |

**Conclusão geral:** não há caminho para valores arbitrários: os montantes pagos são quase sempre derivados no servidor, e há boa disciplina de "claim antes de pagar". A fraqueza sistêmica é **prova de trabalho**: a maioria das conclusões só exige *ped perto do destino + um tempo mínimo*; caminhão, trailer, carga e veículo de manuseio quase nunca são exigidos. Um cliente que consiga teleportar o ped (ou forjar os passos de carregamento, que são autodeclarados) recebe o pagamento fixo em segundos, de forma repetível.

## 1. Metodologia e cobertura

- Leitura integral de `server/events.lua` (3 005 linhas) e `server/main.lua` (trechos de job, cleanup e pagamento); quase todos os serviços, completos; `callbacks.lua` em faixas (≈ 60 %).
- **NOT READ** (de modo relevante): `callbacks.lua` 1–574, 705–804, 965–1035; `server/main.lua` 1–254, 285–501, 762–1179 (auditoria de economia); a maior parte de `client/*` (só consultado por grep nas duas auditorias de segurança); todo `html/js`; `server/database.lua` fora das faixas citadas (o comportamento atômico de `DB_UpdateLoanBalance`/`DB_GetActiveLoan` foi **assumido** a partir dos chamadores).
- Os valores de configuração (cooldowns, raios, pagamentos) não foram lidos integralmente; impactos dependem deles quando indicado.

## 2. Findings consolidados

### P1

| ID | Domínio | Handler (arquivo:linha) | Cenário concreto | Fonte |
|---|---|---|---|---|
| **SEC-01** | ENTIDADES | `aurp_trucker:server:registerJobEntities` `events.lua:297`; `validateJobEntity` `:88-120`; `safeDeleteJobEntity` `:136-147` | Sem lobby Polarix, a validação aceita qualquer entidade do tipo certo, a ≤ 250 m do ped, **da qual o chamador seja dono de rede** (`:114-118`). `accept()` marca todo aceito como `verified[netId] = model` (`:325-326`), logo concede `GiveKeys`, `LockEntityNetworkOwner` e **permite a exclusão** em `abandonJob`/`onPlayerDeath`. Um cliente dono de um carro estacionado (OneSync costuma entregar donos de veículos vazios ao jogador mais próximo) o registra, ganha chaves e o apaga. **[VERIFICADO no código; exploração RUNTIME PROOF REQUIRED]** | Auditoria B (P1); A tratou `validateJobEntity` como OK. **Divergência:** a decisão é P1 condicional, pois o ramo 3 de `validateJobEntity` e a cópia de `verified` em `accept()` foram lidos diretamente. |
| **SEC-02** | JOB / PAGAMENTO | `completePolarixDelivery` `main.lua:2011`; `JobService.Complete` `job_service.lua:368` (via `completeJob` `events.lua:244`); `FinishQuickJobContract` `events.lua:2671` | Só o **ped** precisa estar perto do destino, mais 10 s (Polarix) ou `max(25 s, dist/120 km/h)` (legado). Caminhão/trailer/carga não são exigidos. Para `adr`/`vehicle_carrier`, `strappingCompleted` (`main.lua:1891`) exige só `EnterLoadingStage`; `heavyContainerLoaded` (`:1975`) e `disconnectHose` (`:1858`, sem tempo de enchimento) idem. Sequência: iniciar, evento de "carregado", 10 s, teleportar o ped, `completePolarixDelivery(jobId)`: ≈ US$ 5 000 por ~30 s, repetível. | A (F2a, F5a) e B (itens 6, 7, 13) concordam |
| **SEC-03** | CONTAINER | `containerHandler:start/complete` `callbacks.lua:1568/1576` → `container_handler_service.lua:76` | Sem validação de veículo, container ou carga: `start`, 20 s, ir ao slot (coordenadas devolvidas ao cliente), `complete`. US$ 1 200–3 500 a cada ~30 s. | B (P1); A (P2). **Decisão:** P1, repetível sem prova. |
| **SEC-04** | LC CONTRACT | `cancelActiveLCContract` `events.lua:2148-2181` + `finishQuickJobContract` `:2671` | O cancel apaga o caminhão e limpa `ActiveLCContractData`, mas **não altera a linha do banco** (continua `active`) **[VERIFICADO: sem chamada de DB no handler]**. O finish seguinte lê a linha do banco, encontra `info == nil`, pula a checagem do caminhão (`:2333-2342`) e assume "sem dano": pagamento cheio sem caminhão/trailer. | A (P1) |
| **SEC-05** | FORKLIFT TRADE POINT | `palletLoaded` `events.lua:1144`; `completeTradePoint` `callbacks.lua:1480` | A única prova de dono do pallet é `Entity(obj).state.forklift_owner == tostring(src)`, **statebag que o próprio cliente escreve** (`forklift.client.lua:158`, `:330`). O cliente cria 5 objetos com o modelo permitido, marca a statebag e envia `palletLoaded`; `completeTradePoint` paga 500×5×1,3 = US$ 3 250 por um aluguel de US$ 500. | A e B concordam |
| **SEC-06** | REPO | `completeRepoOrder` `events.lua:1000` → `repo_service.lua:148` | Nada prova que um veículo foi recuperado: aceitar, 30 s, ir ao impound, completar. Um devedor que seja membro de uma empresa de repo pode aceitar a **própria** ordem (`Accept` não compara agente × dono) e **abater a própria dívida** (`repo_service.lua:189-204`). | A e B concordam |
| **SEC-07** | CARGO THEFT | `completeCargoTheft` `events.lua:1526`; `JobService.CompleteTheft` `job_service.lua:710` | `CompleteTheft` paga com bônus **sem `ClaimJob`** e com `distance = 0` em `ValidateDelivery` (mínimo de 25 s). `cargoPlayerLeft` é autodeclarado. Colusão: A aceita e registra a placa, B "rouba" e entrega e é pago, sem carregar nada. | A (P1) |
| **SEC-08** | EMPRÉSTIMO | `requestLoan` `events.lua:921` → `LoanService.Create` `loan_service.lua:125`; `takeLoanPlan` | Empréstimo de empresa vai para o cofre da empresa e é sacável como dinheiro (`withdrawMoney`); nada responsabiliza o jogador (a inadimplência só bloqueia novos empréstimos); o colateral é qualquer placa registrada por proximidade. É problema de **desenho econômico** explorável por quem não se importa com a empresa. | A (P1) |

### P2

| ID | Domínio | Onde | Descrição | Fonte |
|---|---|---|---|---|
| SEC-09 | CONVOY | `JobService.GenerateConvoyBatch` `job_service.lua:586-691`; `ConvoyService.MemberComplete` `convoy_service.lua:139-159` | Jobs de membros de convoy são inseridos `available` e listados a todos (`GetAvailable` sem filtro). Um terceiro aceita e completa: `activeCount` cai e o `_PayAll` pode disparar cedo, reduzindo o bônus dos membros. Só XP/estatística para o intruso. A: P1; B: P2. **Decisão:** P2 (grief/XP, sem dinheiro). | A+B |
| SEC-10 | PALLET (legado) | `HandlePalletLoaded` `main.lua:1429`; `palletKinematicOff` `:1706` | No fluxo legado basta o pallet estar a ≤ 60 m do trailer e o jogador a ≤ 40 m; um bot envia `polarixPalletLoaded` por pallet a cada 1 s sem tocar a empilhadeira (só pula o trabalho, não o pagamento). Com a flag ligada, `palletKinematicOff` rebaixa a validação do próprio lobby. Se `palletNetIds` for menor que `requiredCount`, `netId = nil` é aceito sem checar posição. | B |
| SEC-11 | JOB START | `startDelivery` `main.lua:1351` → `StartTruckDelivery` `:502` | Sem rate limit nesse evento (o `startLCContract` tem 2 s). Loop `startDelivery`/`cancelDelivery` gera ≈ 10 entidades e chaves por ciclo; em lobby com caminhão próprio, o cancel não apaga o caminhão (`:231`). `truckPlate` entra em `LIKE '%…%'` (`:616`), logo `%`/`_` casam qualquer caminhão do jogador; a placa vem da string do cliente (`:619`). | B |
| SEC-12 | ENTIDADES | `IsSpawnPointClear` `main.lua:468-497` | **[VERIFICADO]** Apaga **qualquer veículo vazio** dentro do raio das vagas, de qualquer dono; acionável por qualquer cliente via `startDelivery`. Alto impacto se veículos de jogadores ficam no pátio. | A(entidades)+B |
| SEC-13 | FLATBED | `flatbed.server.lua:166-275` | Qualquer jogador perto de qualquer flatbed anexa qualquer veículo desocupado a ≤ 18 m (sem dono/job/papel policial); `DeleteBedEntity` apaga o bed de outro jogador a 30 m. | B |
| SEC-14 | EMPRESA | `Sell` `company_service.lua:349`; `Withdraw` `:222` | Pagamento de venda usa saldo **do cache lido após awaits**; um `withdrawMoney` concorrente (sem lock) debita o banco antes do DELETE e o cache depois: janela estreita de duplo pagamento. `Deposit` concorrente com `Sell` perde o depósito. | A |
| SEC-15 | EMPRESA/NPC | `NpcDriverService.Hire` `npc_driver_service.lua:604`; `purchaseGpsTracker` `callbacks.lua:1511` | Hire sem lock: o limite `maxDriversPerCompany` e o INSERT têm awaits no meio (excede o teto). `purchaseGpsTracker` não checa papel: **qualquer membro gasta fundos da empresa**. | A |
| SEC-16 | SIMULAÇÃO | `TruckSimulationService.OnVehicleSpawn/OnSync` `truck_simulation_service.lua:41-117`; `events.lua:1246-1256` | Placa, integridade e coordenadas vêm do cliente. A placa escolhida define em qual veículo de empresa se grava o combustível (`DB_SetVehicleFuel`); a integridade só diminui (cliente que nunca reporta dano paga 100 %); `vehicleDestroyed` usa `force=true` e ignora o limitador. | A+B |
| SEC-17 | CONTRATOS | `Negotiate` `contract_service.lua:230` | Sem rate limit; o teto de contratos ativos e o INSERT não são atômicos; loop `negotiate`→`abandon` gera linhas. | A |
| SEC-18 | INDÚSTRIA | `Buy` `industry_ownership_service.lua:142`; `Sell` `company_service.lua:349` | Vender a empresa não limpa `IndustryOwners` nem as linhas de posse: indústria órfã para sempre. | A |
| SEC-19 | SHOP STOCK | hook `buyItem` `shop_stock_service.lua:209-224` | O estoque é consumido **no hook, antes** de o ox_inventory concluir o pagamento: compras que falham drenam estoque; `payload.shopType` nil quebra a concatenação (`:213`). | A |
| SEC-20 | JOB (valores do cliente) | `returnQuickJobTruck` `main.lua:2234`; `palletLost` `:1959`; `hoseLeak` `:1834` | `inspection{engineHealth, bodyHealth, burstTires}` vem do cliente (zero dano é aceito); a perda de pallet só existe se o cliente reportar (e o resgate em trânsito desfaz perdas à vontade: `HandlePalletLoaded` ramo `IN_TRANSIT`); o vazamento do hose é decidido no cliente. | A+B |
| SEC-21 | CLASSE "TELEPORT + TIMER" (valor menor) | `completeCrudeDelivery` `crude_oil.lua:71`; parcel `parcel_service.lua:165-306`; `completeContractStop` `contract_service.lua:427`; cargo theft | Só posição do ped + tempo; caminhão/veículo não verificados. Limite real: cooldowns de config (não lidos). | B |
| SEC-22 | LC (caminhão próprio) | `StartLCContractForPlayer` `events.lua:1634`; `ValidateLCDelivery` `:2319` | Contrato tipo 1 (caminhão próprio) não rastreia caminhão nem trailer (`truckEntity = nil`, `:1833-1839`); a prova é só ped ≤ 35 m + tempo mínimo (50 m/s). | A |

### P3

| ID | Descrição |
|---|---|
| SEC-23 | `FinalizeLCContract` (`events.lua:2612`) chama `DropPlayer` em "sem job ativo" (`:2634`) e em ">35 m" (`:2659`): kick por repetição de evento ou lag. |
| SEC-24 | `party:invite`/`partyInvite` sem rate limit (spam de notificação). |
| SEC-25 | `ConvoyService.Start` não verifica `party.convoyActive`; **defeito funcional:** `SetInterval(Config.Party.positionBroadcastInterval, function…)` com o número primeiro (`convoy_service.lua:22`) **[VERIFICADO]**; o `SetInterval` do `ox_lib` local é `(callback, interval)` e dá erro se `interval` não for número (`ox_lib/init.lua:113-120`). A versão realmente implantada **não foi verificada**; `npc_driver_service.lua:906` usa a ordem correta. Se o erro ocorrer, `ConvoyService.Start` falha depois de criar as linhas no banco. |
| SEC-26 | NPC drivers: `_CompleteJob` devolve o job a `available` (ganho infinito do mesmo job); `RespondToEvent` com resposta desconhecida deixa o job preso em `event` e o motorista `working`. |
| SEC-27 | `repoAgentPositionUpdate` (`events.lua:1036`) repassa `coords` sem limite de tamanho/forma ao dono. |
| SEC-28 | `GetSkills` trata `fast` e `speed` como alias (`progression_service.lua:174-175`) enquanto ambas são compráveis: um ponto paga dois bônus. |
| SEC-29 | Duas fontes de nível (`0r_trucker.level` para Polarix/licenças × `trucker_player_progression` para empréstimos/caminhões): gates inconsistentes. |
| SEC-30 | `DB_UpdateAustTruckerStats` faz leitura-modificação-escrita em Lua (não atômico), pós-pagamento. |
| SEC-31 | `returnForklift` reembolsa US$ 250 sem checar proximidade nem existência do forklift; `fleet:repairTruck` debita antes do UPDATE (queda no meio perde dinheiro). |
| SEC-32 | `takeLicenseExam`: a prova é corrigida no cliente (`client.lua:1876-1926`) e o servidor só cobra a taxa e emite a licença (pay-to-grant). |
| SEC-33 | `ConsumeShopStock` devolve `true` quando o serviço não existe (`exports_shop.lua:17`); `RecordInfraction` aceita `issuedBy`/`reason` arbitrários de outros recursos. |
| SEC-34 | Eventos de servidor do `ox_target` (`setEntityHasOptions`, `toggleEntityDoor`) aceitam qualquer netId de qualquer cliente (dependência externa, ver `08_EXTERNAL_REFERENCE_STUDY.md`). |

## 3. Divergências entre auditores (e decisão)

| Tema | Auditoria A | Auditoria B | Decisão |
|---|---|---|---|
| `validateJobEntity` | OK ("bom") | P1 (ramo de dono de rede) | **P1 condicional (SEC-01)**: li o código e a cópia `verified[netId] = model` em `accept()` torna deletável qualquer entidade aceita. Falta provar o cenário de posse em runtime. |
| Container handler | P2 | P1 | **P1 (SEC-03)**: repetível a cada ~30 s sem nenhuma prova. |
| Convoy: job hijack | P1 | P2 | **P2 (SEC-09)**: sem ganho monetário. |
| Cancel LC + finish | P1 | não achou | **P1 (SEC-04)**: verifiquei que o cancel não toca o banco. |
| Contagem de severidade | P1 = 8 | P1 = 6 | Contagem consolidada acima. |

## 4. O que está bem feito

- **Claim antes de pagar** (CAS atômico): `ClaimJob` (`job_service.lua:396-402`), aceite de job (`:297`), LC finish (`events.lua:2413`, `:2555`), Polarix `STATUS_COMPLETING` setado antes de qualquer yield (`main.lua:2064`), repo (`database.lua:1187`), container (`:105`), convoy (`INSERT IGNORE`, `convoy_service.lua:265`), forklift (`Cleanup` antes de pagar, `callbacks.lua:1501`), parcel (`:246`), `PayPending` (DELETE antes de pagar).
- **Valores derivados no servidor:** pagamento LC (`events.lua:1756`), dano LC lido da entidade do servidor (`:2364`), bônus de estacionamento (`:2298`), reembolso do aluguel por saúde do veículo + amostrador (`truck_rental_service.lua:80`, `:357`), preço de combustível (`callbacks.lua:935`).
- **Débitos atômicos e locks** em empresa, empréstimos, frota, upgrades, indústria, progressão, ADR e licenças.
- **`posInt`** (`events.lua:17-24`) rejeita NaN/inf/≤ 0 em depósito, saque, empréstimo, comércio e reparo.
- **Aluguel de caminhão** é a mutação mais bem escrita do repositório.
- **Exame ADR:** conjunto de perguntas emitido e corrigido no servidor, com TTL.
- **`PolarixReject`** registra cada recusa com limitação de log por chave.
- **Estado lógico de pallet** (`PalletRegistry`, PR #9): CAS por `version`, idempotência por `reqId`, lease, um pallet por forklift (hoje desligado por flag).

## 5. Observação sobre o PR #9

O servidor do levantamento cinemático (`palletClaim`, `palletConfirmCarry`, `palletRelease`, `palletKinematicOff`) está pronto e inativo (`KinematicLift.Enabled = false`); **ligar a flag sem o cliente correspondente rejeita todas as estivas** (`RequireClaim`). Ver `15_IMPLEMENTATION_PLAN_FOR_J2.md`, PLAN W1-03.

## 6. Referências

- Padrões de mutação segura: **XS-Trucking** (`finish()` apaga o estado antes de pagar; servidor lê saúde/posição reais), **fiji-oil** (`TryLock`+`pcall`, claim atômico por status), **qbx_core** (mutação só no servidor, validação numérica, log de origem). Ver `08_EXTERNAL_REFERENCE_STUDY.md`.
