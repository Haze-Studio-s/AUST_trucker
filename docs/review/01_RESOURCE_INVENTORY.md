# 01 — Resource Inventory

**ANALYZED HEAD: `c9d9187`.** A lista de "o que é realmente carregado" parte de `fxmanifest.lua` (versão `20.8.5`). Contagem de linhas: `wc -l` no HEAD. **STATUS** usa apenas `CANONICAL`, `ACTIVE`, `LEGACY_CANDIDATE`, `PARTIALLY_REPLACED`, `DUPLICATED_RESPONSIBILITY`, `UNKNOWN`; **nenhum arquivo é marcado "morto/órfão" sem prova**. Colunas curtas por arquivo; os eventos/callbacks completos estão em `04_EVENT_CALLBACK_GRAPH.md`.

Fontes: leitura direta (manifest, contagem, greps de verificação) e relatórios de leitura de código por faixa (arquivos e faixas listados em cada documento temático). Onde um arquivo foi lido só por grep, a coluna "Cobertura" diz.

## 0. Resumo numérico

| Grupo | Arquivos | Linhas |
|---|---|---|
| Lua carregado pelo manifest | 70 (72 `.lua` versionados menos o próprio `fxmanifest.lua` e `shared/fork_lift.lua`) | ≈ 39 000 |
| `shared/fork_lift.lua` (PR #9) | 1 — **não carregado** (pendente de linha no manifest) | 135 |
| NUI (jQuery) | `html/index.html`, `panel.js`, `js/*`, `css/*`, `lang/*` | ver §4 |
| NUI (React/Vite, `html/src`) | 44 `.tsx/.ts` + `assets/index-*.js/css` | **UNKNOWN se carregado** (ver §4) |
| Data (`*.meta`) | 15 | — |
| Stream | 24 (`ydr`/`yft`/`ytd`/`ytyp`) | binário |
| Docs / planos | 39 em `docs/` + 5 `.md` raiz | — |
| Testes | 2 (`tests/*.py`, PR #9) | 440 |

`fxmanifest.lua` carrega **todos** os Lua do repo; nenhum arquivo referenciado está ausente; **nenhum Lua do repositório deixa de ser carregado, salvo `shared/fork_lift.lua`**.

## 1. SHARED

| PATH | LOADED | LINES | DOMAIN | RESPONSABILIDADE PRIMÁRIA / SECUNDÁRIA | DEPENDÊNCIAS | EVENTS/CB/EXPORTS/STATEBAGS/ENTITY/DB | STATUS |
|---|---|---|---|---|---|---|---|
| `config/config.lua` | shared | 1 890 | Core/config | Config global do recurso (jobs, economia, loans, repo, party, ADR, forklift…) / validações implícitas | `ox_lib` | nenhum / só dados | CANONICAL (monólito de config; mutado em runtime: `Config.TrailerSlots`, `Config.VehiclePropOffsets`) |
| `config/logistics_config.lua` | shared | 449 | LC / logística | Dealership, contratos LC | `config.lua` | dados | ACTIVE |
| `shared/config.lua` | shared | 575 | Polarix/pallet | `Config.Polarix` (spawns, forklift, handler, `KinematicLift`, `ForkliftAttachProfiles`, `PalletSpawnRules`) / `Config.CargoTypes`, `TrailerSlots` | — | dados | CANONICAL |
| `shared/pallet_spawn_validation.lua` | shared | 72 | Pallet | Validação pura de spawns (PR #9) | — | nenhum | ACTIVE (PR #9) |
| `shared/pallet_sync_guard.lua` | shared | 40 | Pallet | Guarda de idempotência do sync (PR #9) | — | nenhum | ACTIVE (PR #9) |
| `shared/fork_lift.lua` | **NÃO** | 135 | Forklift | Regras puras do levantamento cinemático (PR #9) | — | nenhum | **ACTIVE no repositório, mas não carregado pelo manifest** |
| `lang/br.lua`, `lang/en.lua`, `lang/locale.lua` | shared | — | i18n | Locale do Lua | — | — | ACTIVE |

## 2. SERVER

| PATH | LINES | DOMAIN | PRIMÁRIA / SECUNDÁRIA | EVENTS / CALLBACKS / EXPORTS (resumo) | ENTIDADES / DB | STATUS | Cobertura |
|---|---|---|---|---|---|---|---|
| `server/framework.lua` | 283 | Framework | Abstração QBX/QBCore/ESX (`Framework.*`) / cache src→citizenid | handler `playerDropped` | DB: não | CANONICAL | lido completo |
| `server/database.lua` | 1 916 | DB | `SchemaService` (36 tabelas) + ~150 `DB_*` globais | — | todas as tabelas `trucker_*`/`aust_trucker_*` | CANONICAL (esquema dividido: `0r_trucker` e `trucker_licenses` são criados em `main.lua:420-442`) | helpers completos; esquema 79–575 por grep |
| `server/pallet_registry.lua` | 243 | Pallet | Regras de registro + estados lógicos (PR #9) | — (usado por `main.lua`) | — | ACTIVE (metade legado) / dormente (estados, atrás da flag) | lido completo |
| `server/main.lua` | 2 453 | Core job / Polarix | Lobby Polarix inteiro (spawn, carga, trânsito, pagamento, cleanup) / estado global `VP_Trucker`, boot, `IsSpawnPointClear` | `startDelivery`, `inspectionCompleted`, `polarixPalletLoaded`, `attachPalletToTrailer`, `palletClaim`/`palletConfirmCarry`/`palletRelease`/`palletKinematicOff`, hose×5, `strappingCompleted`, `palletLost`, `heavyContainerLoaded`, `adrLeakContained`, `completePolarixDelivery`, `returnQuickJobTruck`, `cancelDelivery`, `emergencyRespawnEquipment` | cria truck/trailer/forklift/handler/container/pallets/cars/hose; `0r_trucker` | CANONICAL p/ Polarix; DUPLICATED_RESPONSIBILITY com `events.lua` (LC) e `JobService` | lido completo |
| `server/events.lua` | 3 005 | Roteador de eventos | Eventos de empresa, empréstimo, repo, forklift trade point, theft, LC, frota, party, banco / motor de contratos LC (`:1618-2685`), registro de entidades (`registerJobEntities`), `playerDropped` principal | ~110 `RegisterNetEvent` | `ActiveLCContracts`, `ActiveLCContractData`, `StartingJobLock` (locais) | ACTIVE; PARTIALLY_REPLACED (caminho LC) ; DUPLICATED_RESPONSIBILITY com `callbacks.lua` | lido completo (auditoria de gameplay) |
| `server/callbacks.lua` | 1 737 | Roteador `lib.callback` | Callbacks de NUI/dados, licenças/ADR, rental forklift / `BuildInitialDataForPlayer` (`:85-546`) | ~70 `lib.callback.register` | DB leituras em paralelo | ACTIVE; DUPLICATED_RESPONSIBILITY com `events.lua` | ≈ 60 % lido |
| `server/exports.lua` | 105 | API pública | Exports somente leitura (SALA/MDT/HUD) + `RecordInfraction` | exports | — | ACTIVE | lido completo |
| `server/exports_shop.lua` | 42 | Shop stock API | `ConsumeShopStock/RestockShop/GetShopStock/GetAllShopStocks` | exports | — | ACTIVE | lido completo |
| `server/adr_questions.lua` | 75 | ADR | Banco de perguntas (gabarito só no servidor) | — | — | CANONICAL | cabeçalho lido |
| `server/flatbed.server.lua` | 275 | Flatbed | Ciclo de vida do bed prop + relay attach/lower | `flatbed:*` | cria bed (`CreateObjectNoOffset`) | ACTIVE | lido completo |
| `server/crude_oil.lua` | 256 | Crude oil | `ActiveCrudeJobs` por placa, integração `AUST_oilfield` | `completeCrudeDelivery`, `abandonCrudeJob`, export `StartCrudeJob` | memória; sem DB | ACTIVE | lido completo |

### `server/services/*`

| PATH | LINES | DOMAIN | RESPONSABILIDADE | DB / ESTADO | Money/XP | STATUS | Cobertura |
|---|---|---|---|---|---|---|---|
| `company_service.lua` | 361 | Company | Criar/vender/depositar/sacar, frota registrada, perks | `trucker_companies`, `trucker_company_vehicles`, `VP_Trucker.Companies` | move dinheiro (constantes do servidor) | CANONICAL | completo |
| `party_service.lua` | 444 | Party | Party, convites, grace de queda | `trucker_parties`; `VP_Trucker.Parties` (só memória) | — | CANONICAL | 131–299 em diagonal |
| `loan_service.lua` | 423 | Loans | `Create` (manual) e `TakePlan` (planos) + `CheckOverdue` | `trucker_loans` | credita/debita | ACTIVE (duas APIs de criação vivas) | completo |
| `truck_fleet_service.lua` | 223 | Fleet (LC dealership) | Comprar/vender/reparar caminhão pessoal | `trucker_trucks` | débito/crédito | ACTIVE (2º modelo de frota) | completo |
| `repo_service.lua` | 310 | Repo | Ordens de repossessão + abatimento de dívida | `trucker_repo_orders` | mint de pagamento | ACTIVE | completo |
| `economy_service.lua` | 128 | Economia | Preços de `Config.Industries` | `trucker_industry_state` | — | ACTIVE (só `industry_service` o chama) | completo |
| `industry_ownership_service.lua` | 213 | Indústria | Posse por empresa | `trucker_industry_ownership` | débito/lucro | ACTIVE (sem limpeza na venda da empresa) | completo |
| `industry_service.lua` | 259 | Indústria | Trade comprar/vender + produção em cron | `trucker_industry_state` | cash mint | ACTIVE | completo |
| `progression_service.lua` | 384 | Progressão | XP, níveis, skills, `CalcBonus` | `trucker_player_progression` | XP | CANONICAL | 160–280 em diagonal |
| `adr_service.lua` | 55 | ADR | Certificados | `trucker_adr_certs` | — | ACTIVE | completo |
| `forklift_service.lua` | 153 | Forklift (trade point) | Aluguel/retorno/conclusão do mini-job | `VP_Trucker.ForkliftRentals` | via `callbacks.lua` | ACTIVE (independe do fluxo Polarix) | completo |
| `cargo_tracking_service.lua` | 261 | Theft | Carga por placa, roubo | `VP_Trucker.CargoByPlate` | — | ACTIVE | completo |
| `anti_cheat_service.lua` | 148 | Anti-cheat | Rate limit, strikes, `ValidateDelivery` | memória | — | ACTIVE | completo |
| `container_handler_service.lua` | 183 | Container | Mission do handler portuário | `VP_Trucker.ContainerJobs` | paga | ACTIVE | completo |
| `job_service.lua` | 769 | Core job (legado `trucker_jobs`) | Gerar/aceitar/completar/abandonar, completar roubo | `trucker_jobs` | paga | DUPLICATED_RESPONSIBILITY (pagamento/XP repetido em outros caminhos) | quase completo |
| `convoy_service.lua` | 370 | Convoy | Convoy de party, pagamento coletivo | `trucker_convoy_*`, `trucker_pending_payouts` | paga | ACTIVE (com defeito de `SetInterval`) | completo |
| `illegal_service.lua` | 294 | Illegal | Jobs ilegais e apreensão | `trucker_jobs` | paga em cash | ACTIVE | completo |
| `contract_service.lua` | 700 | Contratos | Negociar/parar/completar, resupply | `trucker_contracts`, `_stops`, `trucker_client_relationships` | paga | ACTIVE | completo |
| `shop_stock_service.lua` | 250 | Shop stock | Estoque de lojas + hook `buyItem` | `trucker_shop_stock` | — | ACTIVE (resupply sem consumidor, ver 05) | completo |
| `npc_driver_service.lua` | 909 | NPC drivers | (A) motoristas da empresa; (B) motoristas pessoais LC | `trucker_npc_*`, `trucker_drivers` | credita empresa | DUPLICATED_RESPONSIBILITY (dois sistemas no mesmo arquivo) | completo |
| `truck_simulation_service.lua` | 298 | Simulação | Combustível/fadiga/integridade; upgrades de frota | `SimState`; DB combustível/fadiga | — | ACTIVE | completo |
| `parcel_service.lua` | 392 | Parcel | Entrega de encomenda | memória (sem DB) | paga | ACTIVE | completo |
| `truck_rental_service.lua` | 373 | Aluguel de caminhão | Aluguel com caução e reembolso | `trucker_rentals` | caução/reembolso | CANONICAL | completo |
| `admin_service.lua` | 1 102 | Admin | Painel, rotas dinâmicas, spawns, offsets, PropEditor | `aust_trucker_*` (7 tabelas) | — | ACTIVE | completo |

## 3. CLIENT

| PATH | LINES | DOMAIN | PRIMÁRIA / SECUNDÁRIA | EVENTS / NUI (resumo) | ENTIDADES | STATUS |
|---|---|---|---|---|---|---|
| `client/main.lua` | 3 302 | Polarix job (cliente) | Máquina de estados `STEP_1..9`, sync de pallets, strapping, trânsito, entrega / gerenciador de objetivo, ponte admin NUI, re-attach por statebag | `polarixJobStarted`, `polarixSyncPallets`, `polarixReadyForTransit`, `polarixJobFinished`…; NUI `startDelivery/acceptJob/startJob/startContract/confirmJob`, `closeMenu…`, 19 `admin*` | resolve netIds do servidor; não cria veículos | CANONICAL p/ Polarix; **DUPLICATED_RESPONSIBILITY** com `client.lua` (NUI e `StartDeliveryRoute`) |
| `client/client.lua` | 3 606 | Hub NUI + legado + LC | Quadro de jobs/empresa/frota/empréstimos; job legado `StartJob…CompleteJob`; fluxo LC | ~35 `lib.callback.await`, ~45 NUI | cria trailer/aluguel/garagem | **DUPLICATED_RESPONSIBILITY**; PARTIALLY_REPLACED (início legado → `startDelivery`) |
| `client/hud.client.lua` | 538 | Simulação/HUD | Combustível, fadiga, integridade, HUD; **ponte para `aurp_trucker:completeJob`** (`:405-410`) | — | — | ACTIVE |
| `client/zones.lua` | 392 | Objetivo | Blip/seta de objetivo | `SetObjective`, `ClearObjective` | — | **PARTIALLY_REPLACED:** `Zones.Setup*` sem chamador; só `ClearObjective` usado |
| `client/carry_system.lua` | 183 | Carry | Prop de carry + animação | — | cria prop | ACTIVE (só `parcel_delivery`) |
| `client/cargo_dry.lua` | 145 | Dry cargo (legado) | Zona de carga traseira | `dryProgressSync`, `cleanupCargoDry` | — | **LEGACY_CANDIDATE:** `CargoDry.Setup` sem chamador e chama funções inexistentes de `ForkliftModule` |
| `client/cargo_liquid.lua` | 393 | Liquid | Fluxo de hose | `hosePickedUp`, `hoseConnected`… | cria hose (fallback) | **LEGACY_CANDIDATE:** `CargoLiquid.Setup` sem chamador |
| `client/forklift.client.lua` | 538 | Forklift trade point | Mini-jobs trade point / indústria | `tradePointTimeout`, `allPalletsLoaded` | cria forklift/pallets (cliente) | ACTIVE (independente do Polarix) |
| `client/adr.client.lua` | 177 | ADR | NPC examinador | callbacks do exame | cria ped | ACTIVE |
| `client/cargo_theft.client.lua` | 374 | Theft | Monitoramento e roubo | 12 eventos | — | ACTIVE |
| `client/convoy.client.lua` | 297 | Convoy | UI de party, blips, rádio CB | 8 eventos | — | ACTIVE |
| `client/illegal.client.lua` | 251 | Illegal | Contatos, zonas de entrega, apreensão | 4 eventos | — | ACTIVE (**sem caminho que inicie o job no cliente**, ver 05) |
| `client/flatbed.client.lua` | 429 | Flatbed | Bed/attach (port gs_flatbed) | `flatbed:*` | cria flatbed/bed | ACTIVE |
| `client/repo.client.lua` | 657 | Repo | Missões repo | 5 eventos | cria alvo/guardas/flatbed | ACTIVE |
| `client/npc_driver.client.lua` | 183 | NPC drivers | Blips/peds/eventos | 6 eventos | cria peds | ACTIVE |
| `client/industries.client.lua` | 34 | Indústria | GPS/lista | NUI `getIndustries` (**duplicado em `client.lua`**) | — | DUPLICATED_RESPONSIBILITY |
| `client/industries_npc.client.lua` | 209 | Indústria | NPCs/menus compra-venda | — | cria peds | ACTIVE |
| `client/crude_oil.lua` | 186 | Crude oil | Entrega no refinaria | 5 eventos | — | ACTIVE |
| `client/parcel_delivery.lua` | 391 | Parcel | Fluxo multi-parada | callbacks | cria ped | ACTIVE |
| `client/container_handler.client.lua` | 433 | Container | Missão do handler (oConteneur) | — | cria handler/container/ped | ACTIVE (mecânica parecida com `reach_stacker`) |
| `client/modules/forklift.lua` | 1 036 | Forklift/pallet | Motor de levantar/estivar, offsets de slot, holograma | `polarixPalletLoaded` (1 caminho) | attach/freeze | CANONICAL (Polarix) |
| `client/modules/reach_stacker.lua` | 235 | Reach stacker | Spreader [G] | `heavyContainerLoaded` (**duplicado em `main.lua:2441`**) | attach container | ACTIVE |
| `client/modules/car_carrier.lua` | 235 | Car carrier | Rampa e slots | — | cria rampa | ACTIVE **mas inoperante** (netId × handle) |
| `client/modules/adr_hazard.lua` | 175 | ADR hazard | Simulação de vazamento | `adrLeakContained` | ptfx | ACTIVE (só no Polarix `adr`) |
| `client/modules/dataview.lua` | 114 | util | Polyfill `DataView` | — | — | **LEGACY_CANDIDATE:** sem referência no repo (pode ser usado pela NUI/outro recurso: UNKNOWN) |
| `client/modules/offset_editor.lua` | 1 740 | Admin/PropEditor | Gizmo 3D, spawn preview, prop editor | `adminSync*`; 11 NUI | cria veículos/props de preview | ACTIVE (verificação de admin no servidor: ver `12_…`) |
| `client/modules/pallet_debug.lua` | 210 | Debug | Telemetria de pallets (`Config.Debug`) | — | — | ACTIVE (debug) |

## 4. NUI

| Item | Observação | STATUS |
|---|---|---|
| `html/index.html` (1 643 linhas) | Carrega `jquery.min.js`, `bootstrap`, `three.min.js`, `utils.js`, `panel.js`, `admin.js`, `gizmo_overlay.js` | **CANONICAL** (é o que o manifest serve) |
| `html/panel.js` (1 973), `js/admin.js` (1 588), `js/gizmo_overlay.js` (322) | UI principal, painel admin, gizmo | ACTIVE |
| `html/src/**` (44 arquivos React/TS) + `html/assets/index-*.js/css` | `vite.config.ts` usa `outDir = html/` e `index.html` **não referencia** `assets/index-*.js` (grep) | **UNKNOWN** quanto a estar em uso; **PARTIALLY_REPLACED / DUPLICATED_RESPONSIBILITY** candidato (duas pilhas de NUI) |
| `html/lang/*.js` (8 idiomas) | i18n da NUI | ACTIVE |
| `html/vendor/**`, `html/css/**` | libs (bootstrap, three, fontawesome) | ACTIVE (vendor) |

## 5. DATA, STREAM, CONFIG, DOCS, TESTS

| Grupo | Conteúdo | Observação |
|---|---|---|
| DATA | 15 `.meta` (aerocab, brickades, linerunner, vetirs: handling, vehicles, carvariations, dlctext) | todos referenciados por `data_file` no manifest; conteúdo **NOT READ** |
| STREAM | `sm3d_prop_logi_shelf_def.ytyp`, `sm3d_prop_pallets_def.ytyp` + `ydr/yft/ytd` | os dois `.ytyp` são registrados (`DLC_ITYP_REQUEST`); geometria/colisão **NOT READ** |
| CONFIG | `config/config.lua`, `config/logistics_config.lua`, `shared/config.lua` | ver §1 |
| DOCS | `README.md`, `CHANGELOG.md`, `AUDIT_REPORT.md`, `GUIA_*.md`, `DESCRICAO_VENDA.md`, `docs/*`, `docs/superpowers/{plans,specs}` (≈ 35 arquivos de março/2026) | `docs/superpowers` não verificado contra o código (**UNKNOWN**) |
| TESTS | `tests/pallet_hardening_test.py`, `tests/kinematic_lift_test.py` | só lógica pura via `lupa` (PR #9) |
| OUTROS | `.github/workflows/deploy.yml`; `.superpowers/brainstorm/**` (3 `.html` de brainstorm); `import.sql` | `.superpowers` parece artefato de ferramenta (**UNKNOWN**) |

## 6. Dependências externas declaradas e observadas

- Manifest: `oxmysql`, `ox_lib`, `ox_inventory`, `ox_target`.
- Observadas no código **sem estarem no manifest**: `qbx_vehiclekeys`, `qbx_core`/`qb-core`/ESX (via `Framework`), `AUST_oilfield`, `AUST_governo`, `vp_gasstations`, `vp-governo`, `lsn-oilfield` (eventos), `baseevents`. Referência global a `QBCore` em `framework.lua:24` não definida no repositório.
- `server/main.lua:88-109` abre `fxmanifest.lua` em modo de escrita no boot e remove linhas com `webpack_bundle` (**higiene/NOT INVESTIGADO além disso**).
