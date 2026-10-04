# 03 — Module Ownership Map

**ANALYZED HEAD: `c9d9187`.** Para cada domínio: quem é dono do quê **no código atual**. "—" = não existe; "NOT FOUND" = busca feita; "UNKNOWN" = não verificado. Eventos/callbacks completos em `04_EVENT_CALLBACK_GRAPH.md`.

Abreviações de colunas: **CL** = client owner, **SV** = server owner, **ST** = state owner, **EN** = entity owner, **NW** = network owner, **DB** = db owner, **CLN** = cleanup, **DROP** = `playerDropped`, **RECON** = reconnect, **STOP** = `onResourceStop`.

## Tabela 1: núcleo de job e cargas

| DOMÍNIO | CL | SV | ST | EN | NW | DB | CLN / DROP / RECON / STOP | OVERLAP / CONFLITO / RISCO LEGADO |
|---|---|---|---|---|---|---|---|---|
| **CORE JOB (Polarix)** | `client/main.lua` | `server/main.lua` | `PolarixLobbies` (servidor) + `CurrentStage` (cliente, divergente) | servidor (truck, trailer, extras) | `LockEntityNetworkOwner` | `0r_trucker`, `trucker_player_progression`, `aust_trucker_stats` (3 stores) | `CleanupLobbyEntities` / lobby apagado na queda / **NOT FOUND** / `sv/main:2427` limpa lobbies | **Conflito:** 3 sistemas de job sem registro comum; estágio do cliente ≠ servidor; `inspectionCompleted` nunca enviado |
| **CORE JOB (legado)** | `client/client.lua` (`StartJob…CompleteJob`) | `JobService` | linha `trucker_jobs.status` | cliente cria trailer | — | `trucker_jobs` | grace de 3 min em `events.lua:380` / idem / `LoadFromDB` reseta `active→available` | LEGACY_CANDIDATE: início do job vai a `startDelivery`; `aurp_trucker:acceptJob` **sem consumidor** na NUI |
| **DRY CARGO** | `main.lua` + `modules/forklift.lua` (`cargo_dry.lua` legado) | `HandlePalletLoaded` (`main.lua`) | `lobby.loadedCount`, `PalletRegistry` | servidor | idem | — | `CleanupLobbyEntities` | `cargo_dry.lua`: `Setup` sem chamador |
| **LIQUID CARGO** | `client/cargo_liquid.lua` | `main.lua` (hose×5) | `lobby.hoseProp/hoseConnected` | servidor (hose) + cliente (fallback) | hose **sem lock** | — | `CleanupLobbyEntities` / idem / NOT FOUND / `CargoLiquid.Cleanup` | **Inoperante:** `CargoLiquid.Setup` sem chamador; job não sai de `STEP_5_FUEL_LOADING` |
| **PALLET** | `modules/forklift.lua`, `main.lua` (sync) | `main.lua` + `pallet_registry.lua` | cliente: `PalletPhysState` (local da thread); servidor: `PalletRegistry` (dormente) | servidor | `LockEntityNetworkOwner` + `CanMigrate(false)` | — | `CleanupLobbyEntities` / `PalletRegistry.Recover` / NOT FOUND / lobby | Fluxos legado e cinemático coexistem; estado `CARRIED` só no cliente |
| **FORKLIFT (Polarix)** | `modules/forklift.lua` | `main.lua` (spawn) | cliente (`PalletPhysState`, ghost, `ForkliftLoadedOnTrailer`) | servidor | `LockEntityNetworkOwner`; emergência **sem lock** | — | **órfão após conclusão com caminhão próprio** | ver `06_…` |
| **TRADEPOINT FORKLIFT** | `client/forklift.client.lua` | `forklift_service.lua` + `callbacks.lua:1422-1501` + `events.lua:1090-1201` | `VP_Trucker.ForkliftRentals`, `TradePointActive` | **cliente cria** forklift e pallets | nenhum | — | `ForkliftService.OnPlayerDropped` (TradePoint sim, indústria não) / NOT FOUND / `CleanupTradePoint` | **P1:** prova do pallet é statebag escrita pelo cliente (SEC-05) |
| **TRAILER** | `main.lua` (resolve), `client.lua` (legado) | `main.lua` | `lobby.trailer` | servidor (Polarix), cliente (legado) | lock (Polarix) | — | apagado na queda | `loadedSlots` escrito por **cliente e servidor** |
| **STRAPS** | `main.lua` (`:663-1204`) | `strappingCompleted` (`main.lua:1891`) | **client-only** (`isSecured`, `riskLevel`) | — | — | — | `CleanupCurrentJob` | servidor nunca verifica as cintas |
| **REACH STACKER** | `modules/reach_stacker.lua` | `heavyContainerLoaded` (`main.lua:1975`) | cliente | container servidor (Polarix) | lock (container) | — | `StopOperation` só desanexa | `heavyContainerLoaded` enviado 2× |
| **CONTAINER HANDLER** | `client/container_handler.client.lua` | `container_handler_service.lua` | `VP_Trucker.ContainerJobs` | **cliente** (handler/container locais) | — | — | `OnPlayerDropped` limpa só o job | mecânica duplicada com `reach_stacker`; container nunca apagado |
| **CAR CARRIER** | `modules/car_carrier.lua` | `main.lua` (spawn 3 carros) | cliente | servidor (carros) | lock | — | `CleanupLobbyEntities` | **Inoperante:** netId × handle; callback sem argumento |
| **FLATBED** | `client/flatbed.client.lua` | `flatbed.server.lua` | statebags `attachedVehicle/bedLowered/bedMoving/bedProp` | servidor (bed), cliente (flatbed de repo) | sem lock | — | `entityRemoved`; stop: só cliente | statebags escritas também pelo cliente |
| **REPO MAN** | `client/repo.client.lua` | `repo_service.lua` + `events.lua` | `trucker_repo_orders` | **cliente** (alvo, guardas) | — | `trucker_repo_orders` | só cliente / **NOT FOUND (ordem fica `active`)** / — / `CleanupMission` | **P1:** nada prova recuperação (SEC-06) |
| **PARCEL** | `client/parcel_delivery.lua` + `carry_system.lua` | `parcel_service.lua` | `ParcelState` (memória) | cliente (prop) | — | — | `playerDropped` próprio + varredura 30 min | cooldown só no `complete` |
| **CARRY SYSTEM** | `client/carry_system.lua` | — | `_active` (cliente) | cliente | — | — | `Stop`, `onResourceStop` | só `parcel_delivery` usa |
| **ADR** | `client/adr.client.lua` | callbacks `callbacks.lua:1256-1414` + `adr_service.lua` | `trucker_adr_certs`; `AdrExamSets` (memória) | — | — | `trucker_adr_certs`, `trucker_licenses` | — | **2 sistemas de ADR**; fee debitada antes de corrigir |
| **ADR HAZARD** | `modules/adr_hazard.lua` | `adrLeakContained` | cliente | — | — | — | `StopMonitoring` | vazamento não contido nunca é reportado |
| **CRUDE OIL** | `client/crude_oil.lua` | `server/crude_oil.lua` | `ActiveCrudeJobs` (memória) | — | — | — | `playerDropped` (devolve barris) / — / sem `onResourceStop` | `abandonCrudeJob` sem chamador no cliente |
| **CARGO THEFT** | `client/cargo_theft.client.lua` | `cargo_tracking_service.lua` | `VP_Trucker.CargoByPlate` | — | — | `trucker_jobs.truck_plate` | `events.lua:1216-1226` | `ct_vulnerable` escrita pelo cliente (SEC-07) |
| **ILLEGAL JOB** | `client/illegal.client.lua` | `illegal_service.lua` | `IllegalTargets` (memória) | — | — | `trucker_jobs` | **NOT FOUND na queda** | **Cliente não inicia o job** (sem `client:jobStarted`) |

## Tabela 2: economia e organização

| DOMÍNIO | CL | SV | ST | DB | CLN / DROP / RECON / STOP | OVERLAP / RISCO |
|---|---|---|---|---|---|---|
| **COMPANY** | `client.lua` (NUI) | `company_service.lua` + `events.lua:463-720` | `VP_Trucker.Companies/PlayerCompanies` | `trucker_companies`, `_members`, `_company_vehicles` | — / — / — / — | Venda não limpa indústrias (SEC-18); depósito/saque duplicado em 2 caminhos |
| **FLEET** | `client.lua` | `truck_fleet_service.lua` + `company_service.lua` | `trucker_trucks`, `trucker_company_vehicles` | idem | — | **2 modelos de frota**; `fleet:repairTruck` ignora o lock do serviço |
| **TRUCK RENTAL** | `client.lua:864-902` | `truck_rental_service.lua` | `Active`, `trucker_rentals` | `trucker_rentals` | `OnPlayerDropped` / `Init` / login `payPending` | **Provável perda de caução na queda** (ordem dos handlers, ver 05) |
| **LOANS** | `client.lua` | `loan_service.lua` | `trucker_loans` | `trucker_loans` | thread `CheckOverdue` (sem stop) | `Create` × `TakePlan` (duas APIs); empréstimo de empresa sacável (SEC-08) |
| **PROGRESSION** | — | `progression_service.lua` | `trucker_player_progression` | idem + `0r_trucker` + `aust_trucker_stats` | — | **3 armazenamentos**, 2 fontes de nível |
| **ECONOMY** | — | `economy_service.lua` | `priceCache` | `trucker_industry_state` | — | só `industry_service` chama |
| **INDUSTRY** | `industries*.client.lua` | `industry_service.lua` | idem | idem | — | 2 modelos de indústria; produção ignora `productionPerHour`; **sem laço de consumo** |
| **INDUSTRY OWNERSHIP** | `client.lua` | `industry_ownership_service.lua` | `VP_Trucker.IndustryOwners` | `trucker_industry_ownership` | — | Órfã após venda da empresa; custo de operação por minuto |
| **SHOP STOCK** | — | `shop_stock_service.lua` + `exports_shop.lua` | `VP_Trucker.ShopStock` | `trucker_shop_stock` | — | **Dead end:** contratos de resupply não têm aceite |
| **CONTRACTS** | `client.lua:2895-3077` | `contract_service.lua` | `trucker_contracts/_stops` | idem | — | Negociação sem rate limit; sem gerador periódico |
| **PARTY** | `convoy.client.lua` | `party_service.lua` | `VP_Trucker.Parties` (só memória) | `trucker_parties` | grace 180 s / `OnPlayerReconnect` / — | Kick não chama `MemberAbandon` |
| **CONVOY** | `convoy.client.lua` | `convoy_service.lua` | `VP_Trucker.Convoys` | `trucker_convoy_*` | `Cancel` (party disband) / `LoadFromDB` cancela / sem stop do interval | **`SetInterval` com argumentos trocados**; jobs de convoy não atribuídos |
| **NPC DRIVERS** | `npc_driver.client.lua` | `npc_driver_service.lua` | `NpcDrivers/NpcJobs/PendingEvents` | `trucker_npc_*`, `trucker_drivers` | `LoadFromDB` / — / — | 2 sistemas no mesmo arquivo; job devolvido a `available` |
| **TRUCK SIMULATION** | `hud.client.lua` | `truck_simulation_service.lua` | `SimState` | fuel/fatigue/upgrades | `OnPlayerDropped` persiste | placa/integridade/coords do cliente |
| **ADMIN** | `main.lua:3017-3126`, `offset_editor.lua` | `admin_service.lua` | `AdminService.*` | `aust_trucker_*` (7) | — | ACE `command.truckeradmin`; `LoadAll` × schema (ordem não garantida) |
| **OFFSET EDITOR / PropEditor** | `modules/offset_editor.lua` | `admin_service.lua` | `Config.VehiclePropOffsets` (cliente) | `aust_trucker_vehicle_prop_offsets` | — | **Join tardio:** nenhum carregamento inicial dos offsets no cliente; só o broadcast do admin |
| **NUI** | `html/` | — | — | — | — | 2 pilhas (jQuery carregada; React não referenciada) |
| **DATABASE** | — | `database.lua` | — | 36 tabelas + `0r_trucker`, `trucker_licenses` (em `main.lua`) | — | SQL cru em serviços; schema dividido; tabela `trucker_company` inexistente consultada |
| **ANTI-CHEAT** | — | `anti_cheat_service.lua` | `_cooldowns`, `_strikes` | — | `CleanupPlayer` (não limpa `_strikes`) | prova de entrega = ped + tempo; kick por strikes |

## Observações transversais

- **Donos de cleanup:** o servidor tem **um** `onResourceStop` (`main.lua:2427`); nenhum serviço tem. O cliente tem vários, incompletos (`06_ENTITY_LIFECYCLE_MAP.md`).
- **Donos de `playerDropped`:** oito handlers independentes, dois em conflito (`events.lua:380` × `:1207`; `main.lua:2414` × `:1207`), ver `06_…`.
- **Reconnect:** inexistente para entidades; só `PartyService.OnPlayerReconnect` e `TruckRentalService.OnPlayerLoaded` tratam algo.
