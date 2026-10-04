# 02 — Architecture Overview

**ANALYZED HEAD: `c9d9187`.** Arquitetura **real** (como o código é), não a desenhada nos planos de março (`docs/superpowers/*`, não verificados contra o código).

## 1. Camadas lógicas

```
                          ┌──────────────────────────────┐
  NUI (jQuery)            │ html/index.html + panel.js   │   (html/src React + assets: UNKNOWN se usado)
  html/js/admin.js        │ admin.js, gizmo_overlay.js   │
                          └──────────────┬───────────────┘
                                         │ RegisterNUICallback  (client.lua ~45, main.lua 29, offset_editor 11)
                          ┌──────────────▼───────────────┐
  CLIENT ORCHESTRATORS    │ client/main.lua   (Polarix)  │  ← duas máquinas de estado, dois "StartDeliveryRoute",
                          │ client/client.lua (hub+legado│     NUI duplicada
                          │   +LC)                       │
                          └──────────────┬───────────────┘
                                         │ funções globais / _G / eventos locais
                          ┌──────────────▼───────────────┐
  CLIENT MODULES          │ modules/{forklift,reach_stacker,car_carrier,adr_hazard,offset_editor,
                          │          pallet_debug,dataview}  ·  cargo_{dry,liquid}  ·  carry_system
                          │ *.client.lua por domínio (repo, flatbed, convoy, illegal, theft, parcel…)
                          └──────────────┬───────────────┘
                                         │ TriggerServerEvent (~110 eventos) · lib.callback.await (~70)
                          ┌──────────────▼───────────────┐
  SERVER ROUTERS          │ server/main.lua   (lobby Polarix: eventos + lógica)
                          │ server/events.lua (eventos: empresa, empréstimo, repo, LC…)
                          │ server/callbacks.lua (callbacks + dados da NUI)
                          │ flatbed.server.lua · crude_oil.lua · exports*.lua
                          └──────────────┬───────────────┘
                                         │ chamadas diretas a tabelas globais (XService.*)
                          ┌──────────────▼───────────────┐
  SERVER SERVICES         │ server/services/*.lua (24)  — estado em memória + DB_* globais
                          └──────────────┬───────────────┘
                          ┌──────────────▼───────────────┐
  DATABASE / FRAMEWORK    │ server/database.lua (SchemaService + ~150 DB_*)  ·  server/framework.lua
                          │ oxmysql · ox_inventory · QBX/QBCore/ESX · AUST_* (externos)
                          └──────────────────────────────┘
```

## 2. Cada arquivo-chave

### `client/main.lua` (3 302 linhas): orquestrador **Polarix**
Máquina de estados do cliente `STEP_1_START … STEP_9_DELIVERY, STEP_RETURN_TRUCK`: resolve os netIds enviados pelo servidor (`WaitForNetworkEntity`), acopla o trailer, estaciona na doca, delega ao módulo de carga (forklift, reach stacker, car carrier, hose), faz o strapping, roda a física de trânsito (G-force, queda de pallet) e a entrega. Também contém: gerenciador de objetivo/seta (`:126-293`, duplica `zones.lua`), callbacks NUI de início/fechamento (`:500-521`, duplicam `client.lua:834-859`), ponte NUI→servidor do painel admin (`:3017-3126`) e re-attach por statebag para observadores (`:3150-3270`).

### `client/client.lua` (3 606 linhas): hub NUI + legado + LC
Quadro de jobs/empresa/frota/empréstimos/party (≈ 80 callbacks entre NUI e `lib.callback`); **job legado** (`StartJob → StartLoading → StartUnloading → CompleteJob`); **fluxo LC** (quick job/caminhão próprio, `:3083-3575`) com seu próprio `StartDeliveryRoute` local e laço de retorno; marcadores do HQ; banqueiro.

### `server/main.lua` (2 453 linhas): lobby Polarix
`PolarixLobbies[jobId]` (local do arquivo): spawn de truck/trailer/forklift/handler/container/pallets/carros, transições de estágio, pagamento (`completePolarixDelivery`), cleanup. Também guarda o estado global `VP_Trucker`, o boot (`MySQL.ready`), criação de tabelas fora do `SchemaService` e `IsSpawnPointClear`.

### `server/events.lua` (3 005 linhas): roteador de eventos
Eventos de empresa, empréstimo, repo, trade point de forklift, roubo de carga, contratos LC (motor próprio `:1618-2685`), frota, party, banco; registro de entidades (`registerJobEntities`); o principal `playerDropped` (`:1207`).

### `server/callbacks.lua` (1 737 linhas)
`lib.callback.register` de NUI + `BuildInitialDataForPlayer` (`:85-546`); licenças, exame ADR, aluguel de forklift, container handler.

### Services (`server/services/*`), database, framework
Serviços são tabelas globais (`CompanyService`, `JobService`…) que mantêm estado em memória e chamam `DB_*` globais; ver `01_RESOURCE_INVENTORY.md`. `server/database.lua` = `SchemaService` (36 tabelas) + ~150 helpers globais. `server/framework.lua` abstrai QBX/QBCore/ESX.

## 3. Fontes de autoridade (quem decide o quê)

| Assunto | Autoridade | Observação |
|---|---|---|
| Job Polarix (estágio, pagamento) | `PolarixLobbies` (local de `main.lua:157`) | O cliente tem sua própria `CurrentStage`; várias transições são **client-only** |
| Job legado (`trucker_jobs`) | linha do banco (`status`) | sem campo de estágio |
| Contrato LC | `ActiveLCContracts`/`ActiveLCContractData` (locais de `events.lua`) + linhas `lc_*` | cancel não atualiza o banco (SEC-04) |
| Crude, forklift trade point, container, theft, parcel | tabelas globais em memória (`VP_Trucker.*`, locais de serviço) | perdidas em restart |
| Dinheiro | `Framework.AddMoney` chamado a partir de ≥ 8 caminhos diferentes | ver `12_…` |
| Progressão | **3 armazenamentos**: `trucker_player_progression`, `0r_trucker`, `aust_trucker_stats` | todos escritos na conclusão Polarix |
| Entidades | servidor cria (Polarix, LC quick); cliente cria (rental, repo, trade point, container handler, parcel, flatbed de repo) | registro por `registerJobEntities` é "lado do cliente" |
| Estado de pallet nos garfos | **só o cliente** (`PalletPhysState`) | PR #9 adiciona estado lógico no servidor, dormente |

Três sistemas de job paralelos **sem registro comum**: `PolarixLobbies`, `ActiveLCContracts` e `JobService`/`VP_Trucker.ActiveJobs`. `StartTruckDelivery` não consulta `JobService`/`ActiveLCContracts` e `StartLCContractForPlayer` não consulta Polarix.

## 4. Monólitos

| Arquivo | Linhas | Sintoma |
|---|---|---|
| `client/client.lua` | 3 606 | 3 famílias de missão + hub NUI + HQ + banqueiro |
| `client/main.lua` | 3 302 | Polarix + objetivo + admin bridge + statebags; contorno do limite de 200 locals (comentário em `:29`) |
| `server/events.lua` | 3 005 | 110 eventos + motor LC + registro de entidades |
| `server/main.lua` | 2 453 | lobby + boot + schema parcial |
| `server/database.lua` | 1 916 | esquema + 150 helpers globais |
| `config/config.lua` | 1 890 | config de todos os domínios; mutada em runtime |
| `client/modules/offset_editor.lua` | 1 740 | gizmo, preview, editor de props, sync |

## 5. Sobreposições (overlaps)

1. **`client/main.lua` × `client/client.lua`**: NUI (`closeMenu/closeModal/focusMenu/cancelJob`), dois `StartDeliveryRoute`, duas UIs de estacionamento de entrega, dois laços de retorno de caminhão. `levelUp` e `startRepoMission` tratados duas vezes.
2. **`server/events.lua` × `server/callbacks.lua`**: depósito/saque (`depositMoney` × `bank:deposit`), compra/venda de caminhão (eventos × `buyTruck`/`sellTruck`), plano de empréstimo (`loan:takePlan` com offset +1 × `takeLoanPlan` sem), party (`party:*` × `party*`), motoristas (`driver:*` × callbacks).
3. **Dois sistemas de forklift** (Polarix × trade point) com eventos de nome quase igual (`polarixPalletLoaded` × `palletLoaded`).
4. **Dois modelos de frota** (`trucker_trucks` e `trucker_company_vehicles`) mais aluguel (`trucker_rentals`).
5. **Dois modelos de indústria** (`Config.Industries` × `Config.PrimaryIndustries/SecondaryIndustries`).
6. **Duas pilhas de NUI** (jQuery carregada × React em `html/src`).
7. **Dois sistemas de ADR** (`trucker_adr_certs` × `trucker_licenses.adr_certified`).
8. **Dois sistemas de motorista NPC** no mesmo arquivo.

## 6. Acoplamento e estado global

- **Servidor:** serviços são **globais** carregados em ordem do manifest; chamadas cruzadas resolvem em runtime com guardas `if X then`. O boot usa *spin-wait* (`while not X do Wait(100)`) em vez de ordenar (`main.lua:118-136`). Duas `MySQL.ready` independentes (`main.lua:~113` e `:420`) e `AdminService.LoadAll` numa terceira, com ordem **não garantida**.
- **Cliente:** espelhos `_G.JobEntities`, `_G.ActiveJob`, `_G.LoadedPallets` ficam **obsoletos** (`CleanupCurrentJob` religa só os locais), mas `modules/forklift.lua` os lê (`:366-548`). Globais de função cruzam arquivos (`SendMissionNotify`, `UpdateMissionObjective`, `StartJob`…). `lcActiveJob` existe como global em `main.lua:2275` e como local em `client.lua:67`: duas variáveis sem relação.
- **Config mutável:** `Config.TrailerSlots`/`Config.VehiclePropOffsets` são alterados em runtime a partir de quatro lugares (`main.lua:2477/3285`, `forklift.lua:598`, `offset_editor.lua:724/752`, `admin_service.lua:359-404`).
- **Bug de escopo no cliente:** `StartDeliveryRoute` é chamada em `main.lua:619` antes de `local StartDeliveryRoute = nil` (`:661`); a função só é definida em `:1500`.

## 7. Boundaries (fronteiras) que existem de fato

- Servidor ↔ cliente por `lib.callback` e `RegisterNetEvent`; `source` sempre do motor.
- Serviços ↔ roteadores: chamadas diretas a globais (sem interface).
- DB: tudo por helpers `DB_*` globais, mas com SQL cru em serviços (`truck_fleet`, `industry`, `contract`, `convoy`, `job`, `npc_driver`) e `main.lua`.
- Framework: só por `Framework.*` (exceto `qbx_vehiclekeys`, chamado direto).
- Recursos externos: `AUST_oilfield`, `AUST_governo`, `vp_gasstations`… por exports/eventos, sem declaração no manifest.

## 8. Pontos fortes e fracos da arquitetura (observados)

**Fortes:** claim-before-pay consistente; locks por domínio; aluguel de caminhão exemplar; validação de entrada compartilhada (`posInt`); `PolarixReject` para diagnóstico; boot com `Ready`.
**Fracos:** estado de job fragmentado em 3 sistemas; clients monolíticos; duplicações com comportamento divergente; estado global mutável; cleanup incompleto (ver `06_…`); caminhos de gameplay inoperantes (liquid, ADR no Polarix, car carrier, illegal, shop resupply).
