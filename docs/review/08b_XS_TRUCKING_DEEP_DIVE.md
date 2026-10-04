# 08b — XS-Trucking: aprofundamento (REVISÃO V2)

**BASE DOCUMENTAL:** commit `3a89631` (v1 deste documento). **ANALYZED HEAD (código do AUST): `c9d9187`** — o código do AUST em `3a89631` é idêntico ao de `c9d9187` (só `docs/review/` mudou; verificado por `git diff`). **REFERÊNCIA:** `XyraL/XS-Trucking` v3.0.0, commit `50af0ac` (3.0.0). **Nenhum código foi alterado nem copiado.**

> **LICENÇA — IDEA ONLY / INDEPENDENT REIMPLEMENTATION.** `LICENSE` do XS: "All rights reserved". Permite usar e **modificar para o próprio servidor**; **proíbe** redistribuir (original ou modificado), vender/sublicenciar qualquer derivado e remover avisos de autoria. O AUST contém `DESCRICAO_VENDA.md`, o que sugere distribuição comercial; por isso **nenhum código, trecho, estrutura de tabela ou texto do XS pode entrar no AUST**. Este documento descreve **comportamento, arquitetura e ideias** com identificadores citados apenas para rastreabilidade.

**Legenda de evidência (não há severidade inventada neste documento):**

| Classe | Significado |
|---|---|
| **CONFIRMED_BY_CODE** | o caminho aparece no código lido; não depende de runtime para existir |
| **RUNTIME_UNVERIFIED** | decorre do código, mas só um teste concorrente/em jogo confirma o efeito |
| **UNKNOWN** | não foi possível determinar sem executar ou sem ler outra fonte |
| **DESIGN PATTERN** | padrão arquitetural observado, transferível como ideia |

---

## 1. Escopo de leitura (FULL / PARTIAL / NOT READ)

Critério: **FULL READ** = todas as linhas do arquivo foram lidas; linhas longas exibidas truncadas foram relidas por completo antes de classificar. Nada foi executado (os `tools/*.mjs` foram **lidos**, não rodados).

### 1.1 Server (11 de 11 — FULL)

| Arquivo | Linhas | Status |
|---|---|---|
| `server/main.lua` | 43 | FULL READ |
| `server/db.lua` | 409 | FULL READ |
| `server/jobs.lua` | 1326 | FULL READ |
| `server/callbacks.lua` | 287 | FULL READ |
| `server/progress.lua` | 252 | FULL READ |
| `server/business.lua` | 591 | FULL READ |
| `server/garage.lua` | 486 | FULL READ |
| `server/coop.lua` | 252 | FULL READ |
| `server/spots.lua` | 343 | FULL READ |
| `server/settings.lua` | 122 | FULL READ |
| `server/admin.lua` | 354 | FULL READ |

### 1.2 Client (6 de 6 — FULL)

| Arquivo | Linhas | Status |
|---|---|---|
| `client/job.lua` | 543 | FULL READ |
| `client/main.lua` | 104 | FULL READ |
| `client/placement.lua` | 377 | FULL READ |
| `client/ui.lua` | 130 | FULL READ |
| `client/builder.lua` | 66 | FULL READ |
| `client/guards.lua` | 72 | FULL READ |

### 1.3 Config, shared e bridge (FULL)

| Arquivo | Linhas | Status |
|---|---|---|
| `config.lua` | 627 | FULL READ |
| `shared/util.lua` (extra) | 150 | FULL READ |
| `bridge/framework.lua` | 207 | FULL READ |
| `bridge/fuel.lua` | 49 | FULL READ |
| `bridge/inventory.lua` | 39 | FULL READ |
| `bridge/keys.lua` | 89 | FULL READ |
| `bridge/target.lua` | 121 | FULL READ |
| `bridge/dispatch.lua` | 164 | FULL READ |

### 1.4 NUI (FULL)

`html/index.html` (39) · `html/js/core.js` (235) · `app.js` (36) · `admin.js` (282) · `builder.js` (470) · `hud.js` (163) · `laptop.js` (116) · `page-boards.js` (84) · `page-business.js` (292) · `page-certs.js` (44) · `page-loads.js` (502) · `page-run.js` (297) · `page-skills.js` (152) · `page-truck.js` (262) · `rig.js` (68) · `satmap.js` (91) · `tilt.js` (228) · `html/css/cabos.css` (438): **todos FULL READ**.

Observação de método: nos arquivos JS/CSS com linhas muito longas, a primeira passada exibiu as linhas cortadas em 150–185 colunas; as **caudas cortadas foram impressas e lidas** (eram marcação HTML, declarações CSS ou decoração de comentários; nenhuma lógica ficou sem leitura).

### 1.5 Tools (FULL, exceto o cache de dados)

`tools/check-all.mjs` (26) · `check-events.mjs` (85) · `check-js.mjs` (46) · `check-lua.mjs` (114) · `check-manifest.mjs` (118) · `check-natives.mjs` (202) · `check-netids.mjs` (55) · `check-nui.mjs` (130) · `check-returns.mjs` (116) · `check-runtime.mjs` (72): **FULL READ**.

`tools/.natives-cache.json` (225 KB, uma linha): **PARTIAL READ** — apenas o início (lista ordenada de nomes de natives, gerada pelo próprio `check-natives`); não é código.

### 1.6 Outros arquivos lidos

`README.md` (145) FULL · `CHANGELOG.md` (179) FULL (v3.0.0 … v2.0.0) · `LICENSE` (38) FULL · `fxmanifest.lua` (64) FULL · `.github/workflows/announce.yml` (56) e `release-asset.yml` (59) FULL.

### 1.7 NOT READ

Nada na lista da missão ficou sem leitura. **Não foi lido:** `html/vendor/leaflet/*` (biblioteca de terceiros), `html/assets/maps/tiles/*.webp` (129 imagens). **Não foi feita** execução alguma (nem dos checkers do XS, nem do recurso em jogo): toda afirmação de runtime é **RUNTIME_UNVERIFIED**.

---

## 2. Errata da v1 (conclusões corrigidas)

| # | v1 dizia | Correção (evidência) |
|---|---|---|
| E1 | "CI estático (`tools/*.mjs`)": os verificadores rodam em CI | **Falso.** Os 9 verificadores + `check-all` são **ferramentas locais**; os workflows do XS são só `announce.yml` e `release-asset.yml`, o zip de release **exclui `tools`**, e não há `package.json`. Eles *poderiam* ser ligados a CI. |
| E2 | "10 scripts" | São **9 verificadores** (`check-manifest/events/nui/returns/netids/runtime/natives/lua/js`) + 1 runner (`check-all.mjs:8`). |
| E3 | "chaves (11)" | `bridge/keys.lua` lista **10** recursos + saída `custom` (11 só se contar o `custom`). Combustível 5, dispatch 7, inventário 4, target 2, framework 2. |
| E4 | "único evento cliente→servidor validado" | O servidor registra **um único `RegisterNetEvent`** (`guardsAlarm`, `jobs.lua:1314`); todo o resto é **callback** (`lib.callback`) com validação no serviço. Não é "evento validado" por si só: a validação é `guardedJobFor`. |
| E5 | Scorecard H com notas de leitura parcial | Reavaliado na §3 com leitura completa. |
| E6 | "NOT READ: settings, ui, main, html, tools" | Todos lidos nesta revisão (§1). |
| E7 | "Builder administra o laptop do jogador" (implícito) | O Builder é **tela separada** (`#builder`), fora da `DOCK` do laptop; abre por comando de admin ou botão do painel admin (§8). |
| E8 | XS como "100% server authoritative" (implícito em "autoridade total") | É **autoridade majoritária com exceções** (hitch, combustível, hora do relógio); ver §4. |

---

## 3. Scorecard V2 (com justificativa por evidência)

Escala 1–10. As notas sugeridas na missão foram **conferidas**, não aplicadas automaticamente.

| Critério | v1 | **v2** | Justificativa (evidência) |
|---|---|---|---|
| CODE QUALITY | 7 | **8** | Módulos coesos por domínio; normalização/clamp uniformes (`spots.lua:14-130`, `shared/util.lua`); callbacks e NUI com wrapper central (`db.lua:1-16`, `bridge/framework.lua:1-14`); 9 checkers próprios. Descontos: **nenhuma suíte de testes** (não há `tests/`); bug cosmético `page-business.js:24` (`/s+/`); estado global por tabela (`Jobs`, `Business`, `Garage`). |
| SECURITY | 7 | **7** | Mantida (sugestão 7,5–8 **não** adotada): admin com `guarded()` + auditoria (`admin.lua:1-12`), logos por allowlist (`business.lua:207`), prova de entrega por entidade. Mas há **janelas check-then-act** em dinheiro/estado (`Garage.Collect/Sell`, `BuySkill`, `BuySlots`, `Jobs.Take`, `Coop.Start`: §4.4), **entradas do cliente consumidas** (combustível, hora), **sem rate limit** nos callbacks e liquidação **não transacional**. |
| SERVER AUTHORITY | 9 | **8,5** | Veículos/guardas criados no servidor, estado do job, pagamento, progressão, empresa e banco no servidor; entrega validada com coordenadas de entidades do servidor (`jobs.lua:804`). Descontos: hitch detectado no cliente (`job.lua:201-224`), combustível e hora vêm do cliente. |
| ONESYNC | 9 | **8,5** | `CreateVehicleServerSetter` + `SetEntityOrphanMode(…,2)` (`jobs.lua:37-47`), guardas via `CreatePed` no servidor com orphan mode (`:649`), statebags escritas **no servidor** (`:476-477`, `:652`), `NetworkDoesNetworkIdExist` antes de resolver netId (`job.lua:7-25`), `takeControl` limitado (`:28`), retomada do job após restart do cliente (`job.lua:530`). Descontos: sem `SetNetworkIdCanMigrate(false)`; IA dos guardas depende do dono de rede (`guards.lua:49`); `lib.callback.await` servidor→cliente sem tratamento de timeout (`jobs.lua:675,704`, comportamento padrão **UNKNOWN**). |
| PERFORMANCE | 6 | **7** | Servidor barato: laços de 1 s/5 s/15 s, sem DB por tick, leaderboard com cache de 30 s (`callbacks.lua:224`). Descontos: laço de cliente `Wait(0)` durante todo o job (`job.lua:276`), HUD por NUI a cada 250 ms (`job.lua:386`), `GetAllVehicles()` por baia (`jobs.lua:17-35`), consultas por abertura do snapshot de empresa (`callbacks.lua:107`), mapa 3D com cálculo de DOM (`tilt.js`). |
| GAMEPLAY | 8 | **9** | Amplitude: 50 níveis, 5 ramos de skills, 5 certificados, empresas com ranks/banco/perks, convoy, escolta, co-piloto, hot loads, ilegal com heat e tip-off, guardas armados, multi-parada, timer, frágil, dock score, frota passiva. Desconto: **não há carga física** (nenhum forklift/pallet). |
| MAINTAINABILITY | 7 | **8** | Maior arquivo: `jobs.lua` (1326); camadas bridge/server/client/NUI separadas; migrações auto-provisionadas (`db.lua:349`); checkers. Descontos: sem testes e sem CI ligando os checkers; espaço de nomes global; licença fechada. |
| AUST RELEVANCE | 8 | **8,5** | Alta como **fonte de ideias** (arquitetura de job, bridges, ferramentas, admin, NUI modular). Não é 9: não resolve forklift/pallet, a licença impede reuso de código e o AUST **já tem um ecossistema de dispositivos** (§ doc 19), o que reduz o valor de copiar o "laptop". |

**Melhor por tema (inalterado em essência):** core trucking e OneSync de entidades de job → XS (ideias); forklift → Polarix (MIT); blending de rede → Don (GPL, ideias).

---

## 4. Server authority: leitura corrigida

### 4.1 Forças mantidas (CONFIRMED_BY_CODE)

| # | Força | Evidência |
|---|---|---|
| S1 | Veículos principais criados no servidor, com espera limitada e orphan mode | `jobs.lua:37-47` |
| S2 | Estado do job em `Jobs.active[src]`; cliente é renderizador fino | `jobs.lua:1`, `stateFor` `:255` |
| S3 | Entrega validada com **coordenadas de entidades do servidor**: trailer na zona, caminhão ≤ 20 m do trailer, jogador perto | `jobs.lua:804-840` |
| S4 | `finish()` e `drop()` zeram `Jobs.active[src]` **antes** de pagar/limpar (chamada dupla cai em "nada a entregar") | `jobs.lua:972-973`, `:1130-1131` |
| S5 | Pagamento e XP calculados no servidor; dano = vida do veículo lida no servidor contra baseline | `jobs.lua:859-908`, `health()` `:59` |
| S6 | Banco da empresa com débito **atômico** condicionado ao saldo | `business.lua:154-161` |
| S7 | Progressão (skills, certificados, heat) e permissões de empresa no servidor | `progress.lua`, `business.lua:92-101` |
| S8 | Rota/spot normalizados com clamps antes de gravar | `spots.lua:14-130` |
| S9 | Admin: toda callback passa por `guarded()` (`Framework.IsAdmin` a cada chamada) + auditoria | `admin.lua:1-12` |
| S10 | StateBags relevantes (`xsTrucking`, `xsGuard`) escritas **no servidor** | `jobs.lua:476-477`, `:652` |
| S11 | Hierarquia de ranks respeitada (não promove/remove acima do próprio grau) | `business.lua:312-355` |

### 4.2 HYBRID AUTHORITY — hook/hitch (CONFIRMED_BY_CODE)

Fluxo: o **cliente** observa o engate com `attached(Run.truck)` (native de "trailer acoplado", `job.lua:201-204`), roda um *watcher* a cada 500 ms (`:206-224`) e chama o callback `hooked` (no máx. 1 vez a cada 4 s). O **servidor** (`Jobs.Hooked`, `jobs.lua:722`) confere estágio e que caminhão e trailer (coordenadas do servidor) estão a ≤ 20 m; **não há prova física de acoplamento no servidor**.

| Papel | Quem |
|---|---|
| Observação física | **CLIENT** |
| Autorização da transição `hookup → enroute` | **SERVER** |

**Classificação: HYBRID AUTHORITY** — não é 100% autoritativo no servidor. Efeito prático: um cliente modificado pode chamar `hooked` com o trailer a ≤ 20 m sem acoplar (**RUNTIME_UNVERIFIED**).

### 4.3 Combustível e hora: CLIENT-SOURCED / SERVER-CONSUMED

| Dado | Origem | Consumo | Clamp/limite | Impacto observado |
|---|---|---|---|---|
| **Combustível** na devolução | `Fuel.Get(Run.truck)` no cliente (`job.lua:260-263`) | callback `return` (`callbacks.lua:12`) → `Jobs.Return` (`jobs.lua:1110`) → `Garage.ApplyTrip` (`garage.lua:407`) | **0..100** (`Util.Clamp`, `garage.lua:412`); NaN não tratado (**UNKNOWN**) | define o combustível salvo do caminhão **próprio**; contorna o preço de abastecimento do depósito. Não toca pagamento. A documentação do `config.lua` (Bridges.fuel) declara isso como **intenção de design** ("lido de volta ao estacionar"). |
| **Hora do jogo** (`GetClockHours`) | cliente substitui os argumentos (`ui.lua:77-78`) | `Jobs.Take(..., hour)` (`callbacks.lua:9`) → `job.night` (`jobs.lua:455`) → contexto de `payout` (`:859`, contexto em `:868`) | nenhum além de `tonumber` | o bônus de skill "noturno" (+8% por rank) pode ser forjado por cliente modificado (CONFIRMED_BY_CODE; efeito RUNTIME_UNVERIFIED). |

> **FUEL = CLIENT-SOURCED / SERVER-CONSUMED.** Não tratar combustível como prova autoritativa do servidor.

### 4.4 Janelas check-then-act (RUNTIME_UNVERIFIED — precisam de teste concorrente)

| # | Onde | Mecanismo observado |
|---|---|---|
| R-A | `Jobs.Take` (`jobs.lua:540`) | `Validate` checa `Jobs.Busy` (`:371`), mas `spawnDriver` **cede** (`Wait` em `spawn`, `:37-47`) antes de gravar `Jobs.active[src]` (`:479`); duas chamadas simultâneas poderiam passar a checagem |
| R-B | `Coop.Start` (`coop.lua:172`) | `Jobs.StartCrew` cede; o lobby só é removido **depois** (`coop.lua:191`) |
| R-C | `Garage.Collect` (`garage.lua:465`) | zera `dispatch_*` sem condição `IS NOT NULL` e sem checar linhas afetadas, depois credita |
| R-D | `Garage.Sell` (`garage.lua:218`) | `DELETE` sem checar linhas afetadas, depois credita |
| R-E | `Progress.BuySkill` (`progress.lua:96`) | pontos/rank lidos do cache, `INSERT … ON DUPLICATE` cede, cache atualizado depois |
| R-F | `Business.BuySlots` (`business.lua:495`) | `tier` calculado antes do `await` do débito atômico: duas chamadas poderiam cobrar duas vezes o mesmo degrau |

Contraexemplos **seguros** (sem cessão entre checagem e escrita): `Jobs.Hooked/Deliver/finish/drop`, `Business.BuyPerk` (decrementa o cache antes de qualquer `await`).

### 4.5 Liquidação e persistência (CONFIRMED_BY_CODE)

- **Liquidação não totalmente transacional:** `finish()` (`jobs.lua:972-1070`) credita dinheiro, banco da empresa, reputação, XP/estatísticas, desgaste e log em passos separados; `paySide` credita **antes** de gravar estatísticas (`:920-931`).
- **Débito antes da escrita:** `Business.Found` (`:223`), `Progress.EarnCert` (`:162`), `Respec` (`:123`), `Garage.Buy/Repair/Service/Refuel/Upgrade/Style`, `Business.Deposit` (`:439`): o dinheiro sai antes do `INSERT/UPDATE`.
- **Multi-query sem transação:** `Business.Found` (3 inserts), `SaveRanks` (DELETE + INSERTs, `:358`), `TransferOwner` (3 updates, `:516`), `Disband` (2 statements).
- **Cache + DB:** `Business.Credit/AddRep/CountDelivery` atualizam o cache e o banco **sem aguardar** (`:146-190`); falha de DB deixa o cache divergente até o restart.
- **Restart:** `Jobs.active`, convoys, lobbies e `bayUse` são só memória; `onResourceStop` apaga entidades (`jobs.lua:1319-1326`). **Recuperação de restart incompleta** (job perdido, sem reembolso).
- **Sem rate limit:** o wrapper `register` só protege contra erro (`callbacks.lua:1-6`, `db.lua:1-16`), não contra repetição.

---

## 5. Entity ownership / network — padrão real

```
SERVER: CreateVehicleServerSetter  →  espera ≤ 5 s  →  SetEntityOrphanMode(…, 2)
        └─ StateBag xsTrucking {run, driver}  +  netId no estado enviado ao cliente
CLIENT: entityFromNet(netId, 8 s)
          └─ NetworkDoesNetworkIdExist → NetworkGetEntityFromNetworkId → DoesEntityExist (poll 50 ms)
        takeControl(entity)
          └─ NetworkRequestControlOfEntity, no máx. 60 × 50 ms, confirma NetworkHasControlOfEntity
        só então aplica props/livery/combustível (job.lua:430-440)
```

| Elemento | Evidência |
|---|---|
| Criação no servidor + espera | `jobs.lua:37-47` |
| Resolução de netId no cliente com guarda | `job.lua:7-25` |
| Controle limitado e confirmado | `job.lua:28-35`; mutação só se `takeControl` retorna verdadeiro (`:436-437`) |
| Retomada do job | `job.lua:530` (cliente pergunta `run` ao servidor ao carregar) |

**TRANSFERABLE DESIGN PATTERN — `REQUEST → RETRY BOUNDED → CONFIRM → MUTATE`** (helper `takeControl`). IDEA ONLY — INDEPENDENT REIMPLEMENTATION. Relevante para o AUST, cujo cliente espera controle com laços informais (doc 11, §1) → **W4-05**.

Guardas (DESIGN PATTERN `SERVER STATE → NETWORK OWNER → CLIENT AI EXECUTION`): o servidor cria o ped e grava `xsGuard` (`jobs.lua:630-655`); **somente o cliente que tem controle de rede** aplica relacionamento, precisão e tarefa de guarda (`guards.lua:24-52`); o alarme volta por **um único evento** validado por `guardedJobFor` (`guards.lua:61-72`, `jobs.lua:679,1314`). Evidência para NPCs de ilegal/escolta; **não implementar** (W6-08, estudo).

---

## 6. Bridge Architecture

```
CONFIG (Config.Bridges.*: 'auto' | nome | 'none' | 'custom')
   ↓
AUTODETECT (GetResourceState == 'started') / FORCE PROVIDER
   ↓
CANONICAL BRIDGE API  (Framework.* · Fuel.* · Inventory.* · Keys.* · Target.* · Dispatch.*)
   ↓
RESOURCE DOMAIN  (jobs, garage, business… só chamam a API canônica)
```

O restante do recurso **não conhece** Qbox/QBCore, ox_target/qb-target, o provedor de combustível, chaves, inventário ou dispatch.

| Bridge | Lado | Provedores | Observações (evidência) |
|---|---|---|---|
| **Framework** | cliente + servidor | `qbox`, `qbcore` (**sem ESX**) | PLAYER/CITIZEN ID/NAME/MONEY/POLICE/ADMIN/NOTIFY (`framework.lua:18-205`); `RemoveMoney` confere saldo e depois remove (não atômico); **Admin aceita ACE, grupos do framework e allowlist de licenças** (`:126-149`); polícia exige `onduty` |
| **Fuel** | **cliente** | `ox_fuel`, `LegacyFuel`, `cdn-fuel`, `ps-fuel`, `lj-fuel` | `Set/Get` com **clamp 0..100** e `pcall`; fallback `GetVehicleFuelLevel`; `ox_fuel` via statebag (escrita no cliente) |
| **Inventory** | **servidor** | `ox_inventory`, `qs-inventory`, `ps-inventory`, `qb-inventory` | só `Inventory.Add`, em `pcall`; usado só se o pagamento ilegal for item |
| **Keys** | **servidor + cliente** | 10 + `custom` | `SERVER_SIDE` = `qbx_vehiclekeys`, `Renewed-Vehiclekeys`, `wasabi_carlock`, `custom`; **providers de cliente** recebem `netId` + `plate` por evento e **esperam a entidade existir** (≤ 100 × 50 ms) antes de agir (`keys.lua:53-86`); evento `custom` configurável |
| **Target** | cliente | `ox_target`, `qb-target` | API própria `AddSphere/AddEntity/AddPlayers/Remove/Clear(prefix)` com **registry local** para remoção, limpeza no resource stop e limpeza por prefixo (`target.lua`) |
| **Dispatch** | servidor (+ blip no cliente) | `XS-Dispatch`, `ps-dispatch`, `qs-dispatch`, `cd_dispatch`, `core_dispatch`, `rcore_dispatch`, `linden_outlawalert` | falha do provedor → **fallback próprio** para policiais em serviço com blip (`dispatch.lua:139-164`); `core_dispatch` tem cadeia export→evento |

**Lacuna do AUST (CONFIRMED_BY_CODE):** `server/framework.lua` abstrai QBX/QBCore/ESX (por `Config.Framework`, sem autodetecção), mas **chaves, combustível, polícia e target estão espalhados**: `qbx_vehiclekeys`/`qb-vehiclekeys` em `server/events.lua:341,351,431,1825-1828,2166,2201,2487` e `server/main.lua:361-365`; combustível `ox_fuel`/`cdn-fuel` em `client/client.lua:169-180` e `client/main.lua:2574`; polícia fixa no job `police` (`server/services/illegal_service.lua:98-115`); `Config.Target='ox_target'` (`shared/config.lua:13`) coexiste com chamadas diretas a `exports.ox_target` (`client/zones.lua:217,301`). → **W6-07 (proposta)**.

---

## 7. NUI architecture, Core RPC e o "laptop" do XS

### 7.1 Arquitetura (não é NUI monolítica)

```
index.html (scripts clássicos, sem bundler, ordem fixa)
   ↓
core.js  → namespace XS (post/rpc/esc/format/ícones SVG/gráficos inline)
   ↓
módulos de feature: tilt · satmap · rig · laptop · page-loads · page-run · page-truck ·
                    page-skills · page-certs · page-business · page-boards · hud · builder · admin
   ↓
app.js  → dispatcher de mensagens do jogo (switch por `action`) + atalho Esc
```

Cada página é um objeto registrado em `XS.Pages.<nome>` com `render/leave/live`; `laptop.js` navega pela `DOCK` de **7 páginas**; `builder.js` e `admin.js` são **cabines separadas** (`#builder`, `#admin`). Sem bibliotecas de gráficos (SVG inline), mapa por Leaflet local com **129 tiles `.webp` vendorizados** (~5 MB).

### 7.2 Core RPC

```
JS XS.rpc(fn, ...args) → POST https://<GetParentResourceName()>/rpc
   ↓
client/ui.lua  RegisterNUICallback('rpc')
   ├─ fn ∈ PLAYER (≈50 nomes)  → ok
   └─ fn ∈ ADMIN               → só se UI.mode ∈ {builder, admin}
   ↓ (máx. 6 args; hora do relógio injetada em take/crewStart)
lib.callback.await('XS-Trucking:server:<fn>')  →  serviço no servidor
```

- Host **não é hardcoded**: `GetParentResourceName()` (`core.js:2`), e `tools/check-nui.mjs` ainda varre o host fixo.
- Nil do servidor vira `false` (nunca "sem resposta"): wrapper em `framework.lua:1-14`; cada handler NUI roda na própria thread.
- **A allowlist da NUI NÃO é a fronteira de segurança.** Ela é conveniência/higiene do lado do cliente (um cliente modificado pode chamar qualquer callback). A autorização real está no servidor (`guarded()` para admin; `Business.Can`, `Garage.Usable`, etc.).
- Boa ideia: **UI RPC ALLOWLIST + SERVER AUTHORITY**.

### 7.3 Funcionalidade do "laptop" do XS

Páginas: **Loads · My run · Truck · Skills · Certificates · Business · Leaderboards**. No XS tudo vive no "laptop" físico (alvo `ox_target` em cada spot, `client/main.lua:49`; prop local opcional não networked).

> **NÃO recomendar criar um laptop no AUST.** O AUST já tem a central de cargas em NUI própria (despachante NPC com `ox_target` → `truck_logistics:openJobBoard`, `client/main.lua:418-440`) e, no servidor, um ecossistema de dispositivos (NexusOS, vp_tablet, vp_phone — ver `19_AUST_DEVICE_ECOSYSTEM_INTEGRATION.md`). O valor do XS aqui é **organização modular da NUI** e **contrato RPC**, não o laptop.

### 7.4 Achados de NUI (CONFIRMED_BY_CODE)

- Dependências externas: **Google Fonts** em `index.html` e imagens de veículos de `docs.fivem.net` (`page-truck.js:7`).
- `esc()` aplicado de forma consistente em textos dinâmicos; `style` com URL de logo escapada.
- Bug cosmético: `page-business.js:24` divide o nome por `/s+/` (letra "s") em vez de `/\s+/` (`laptop.js:24` está correto).
- Constante duplicada na UI: bônus multi-parada = 25 fixo em `page-loads.js` (o servidor usa `Config.Pay.multiStopBonus`/`SGet`): só estimativa de exibição.
- Polling: `crews` a cada 3 s (`page-loads.js`) e `run` a cada 4 s (`page-run.js`) enquanto a página está aberta; o servidor também empurra eventos.
- Sem `@media`/`prefers-reduced-motion`; palco fixo 1600×900 escalado (`laptop.js:scale`).

---

## 8. Admin tooling e Route Builder

### 8.1 ROUTE BUILDER = ADMIN ONLY (requisito do projeto + confirmação no XS)

> **Requisito do projeto AUST:** o Route Builder é **ferramenta administrativa**. **Jogador comum = SEM ACESSO.** Não associar o Builder a NexusOS (jogador), vp_tablet, vp_phone nem ao laptop do trucker.

No XS (descoberta técnica, CONFIRMED_BY_CODE) o Builder **já é admin-only em três camadas**:

1. **Comando** `/truckingbuilder` só dispara a UI se `Framework.IsAdmin(src)` (`server/main.lua:27-42`).
2. **Callbacks** `builder`, `saveSpot`, `deleteSpot`, `saveRoute`, `deleteRoute`, `suggestPay` são registrados com `guarded()` → `IsAdmin` a **cada** chamada (`admin.lua:7-12,42+`).
3. **NUI**: nomes de admin só passam no relay se `UI.mode ∈ {builder, admin}` (`client/ui.lua:14-22,69-90`) — camada de conveniência, não de segurança.

Cadeia conceitual (já existe no XS e é a desejada para o AUST):

```
ADMIN → /truckingadmin (painel) → botão "Open the builder" (admin.js:171) → openBuilder → ExecuteCommand(builder)
        → servidor reconfere IsAdmin → UI do Builder
Nunca: PLAYER → UI normal de trucking → Route Builder
```

### 8.2 O que o Builder administra (para estudo)

spots · baias de caminhão/trailer/retorno · rotas · pickup · paradas (≤ 8) · carga · tipo de trailer/modelo · peso · pay/XP/nível · certificado · timer · convoy · escolta · ilegal · frágil · guardas (só ilegal + pickup) · sugestão de pagamento por distância · duplicar rota · "Quick route".

### 8.3 Placement (`client/placement.lua`) vs PropEditor 6DoF do AUST

| Capacidade do Placement (XS) | Evidência |
|---|---|
| câmera livre + raycast | `placement.lua:29-48`, loop `:205+` |
| ghost local (veículo/objeto), colisão off, congelado, invencível, alpha | `makeGhost` |
| limites do modelo → **footprint OBB** com margem e teste de sobreposição (SAT) | `footprint`, `overlaps` (`:109`) |
| detecção de **piso** e de **água** | `floorUnder`, `GetWaterHeightNoWaves` |
| confirmação dupla para sobrepor | `armed` |
| limpeza por token de sessão e no resource stop | `session` |

**Conclusão:** o **PropEditor do AUST é mais especializado em offset/calibração 6DoF**; o Placement do XS é interessante para **validação de posicionamento no mundo** (footprint/piso/água). **Não propor substituição direta.** O servidor do XS **não valida a geometria**: só normaliza/clampa (`spots.lua`).

---

## 9. Gameplay, business, fleet e co-op (checklist)

| Recurso | Evidência | Observação |
|---|---|---|
| Business ACL/ranks, **corte do motorista**, **banco compartilhado**, **ledger**, perks, reputação, slots de membros/frota | `business.lua`, `config.lua` Business | ranks hierárquicos; 8 permissões |
| Reserva de frota (`reserved_for`) e `Usable` | `garage.lua:50` | |
| Frota passiva (envio/coleta) | `garage.lua:431,465` | janelas R-C |
| Co-driver, escort, convoy (bônus por janela, top-up posterior) | `coop.lua`, `jobs.lua:787` | presença medida por amostragem a cada 5 s |
| Hot loads rotativas | `jobs.lua:64` | |
| Ilegal: tip-off, heat, bloqueio por heat | `jobs.lua:697-720`, `progress.lua` | |
| Guardas armados | `jobs.lua:630`, `guards.lua` | |
| Multi-stop, timer/atraso, frágil | `jobs.lua:804,859` | |
| Retorno antes da liquidação (`return`) | `jobs.lua:1110` | |
| Dock score (distância 2D + heading do trailer) | `jobs.lua:739` | só com skill/bônus |
| Certificações e skill tree | `progress.lua`, `config.lua` | |
| Histórico de entregas e leaderboards | `callbacks.lua:224`, tabela `deliveries` | |
| Monitoramento admin ao vivo | `admin.lua`, `Jobs.List` | |

---

## 10. Tooling (separação em sub-checkers)

> Todos são **REIMPLEMENTAÇÕES INDEPENDENTES (IDEA ONLY)**. Os `tools/*.mjs` do XS são **locais** (não rodam em CI do XS — Errata E1) e **heurísticos** (regex, não parsers).

| Sub-checker proposto | O que o XS observado faz | Limites observados | Aplicabilidade ao AUST |
|---|---|---|---|
| **W0-04A Manifest** | manifest→disco e disco→manifest; arquivo existe; arquivo está em bloco de script (não só `files{}`); `html` listado; referências de `index.html` enviadas; glob com pasta existente e com correspondência; glob aninhado `**` reprovado (`check-manifest.mjs`) | extração por regex dos blocos; glob de 1 nível | **alta** (`shared/fork_lift.lua` fora do manifest; órfãos; deriva de versão) |
| **W0-04B Eventos/callbacks** | handler duplicado; evento disparado sem handler; callback aguardado sem registro (`check-events.mjs`) | só nomes com prefixo do recurso; nomes dinâmicos escapam | **alta** (handlers duplicados `playerDropped`, eventos NO CONSUMER, sistemas paralelos) |
| **W0-04C Contrato NUI** | POST da página ↔ `RegisterNUICallback`; RPC ↔ allowlist do cliente ↔ callback no servidor; sem host fixo (`check-nui.mjs`) | depende de convenção `XS.post/rpc` | **alta** (NUI própria + futuros dispositivos) |
| **W0-04D Natives** | compara chamadas capitalizadas com a lista oficial de natives (cache + fetch) (`check-natives.mjs`) | heurística de nomes; lista da `NOT_NATIVES` carrega nomes de outros recursos (**cópia entre projetos**) | média-alta |
| **W0-04E NetId** | `NetToVeh/NetToEnt/NetworkGetEntityFromNetworkId` no cliente precisam de `NetworkDoesNetworkIdExist` nas ~6 linhas anteriores (`check-netids.mjs`) | janela fixa de linhas | média (streaming/late join/spam de console) |
| **W0-04F Runtime lado** | `os`/`io` em arquivos de cliente ou compartilhados sem `IsDuplicityVersion`; natives de cliente em arquivos compartilhados (`check-runtime.mjs`) | janela de 8 linhas | média (arquivos `shared/*`) |
| **W0-04G Multi-retorno Lua** | `return x:gsub(...)`/`find`/`pcall`/`unpack`/natives multi-retorno sem parênteses (`check-returns.mjs`) | lista fixa de funções; allowlist manual | média (classe de bug de parâmetros no oxmysql) |
| **W0-04H Sintaxe JS** | compila cada script como script clássico, sem executar (`new Function`) (`check-js.mjs`) | só sintaxe | média |
| (apoio) Lua estrutural | balanceamento de blocos/chaves/aspas e marcadores de merge (`check-lua.mjs`) | **não é parser** | baixa-média |

Limite geral: **nenhum checker pegaria** o bug `/s+/` do XS nem o `SetInterval` com argumentos trocados do AUST (TD-13) — exigem checagem de semântica/assinatura.

**Fato do AUST:** `deploy.yml` faz **deploy por rsync com `--delete` a cada push em `main`/`master`** (ambiente `production`) **sem etapa de validação**; os checkers propostos poderiam ser **pré-condição** do deploy (proposta; não implementada).

---

## 11. Riscos e achados do XS (por evidência; sem severidade inventada)

| ID | Achado | Evidência | Classe |
|---|---|---|---|
| XR-01 | Hitch detectado no cliente; servidor só confere distância ≤ 20 m | `job.lua:201-224`, `jobs.lua:722` | CONFIRMED_BY_CODE (HYBRID) |
| XR-02 | Combustível vem do cliente na devolução | `job.lua:260`, `garage.lua:407` | CONFIRMED_BY_CODE |
| XR-03 | Hora do relógio vem do cliente (bônus noturno) | `ui.lua:77-78`, `jobs.lua:455` | CONFIRMED_BY_CODE |
| XR-04 | `Jobs.Take` cede antes de gravar o job | `jobs.lua:371,479` | RUNTIME_UNVERIFIED |
| XR-05 | `Coop.Start` remove o lobby depois de `StartCrew` | `coop.lua:172` | RUNTIME_UNVERIFIED |
| XR-06 | `Garage.Collect` sem condição/linhas afetadas | `garage.lua:465` | CONFIRMED_BY_CODE / efeito RUNTIME_UNVERIFIED |
| XR-07 | `Garage.Sell` sem checar linhas afetadas | `garage.lua:218` | idem |
| XR-08 | `Progress.BuySkill` com leitura/escrita separadas por `await` | `progress.lua:96` | RUNTIME_UNVERIFIED |
| XR-09 | `Business.BuySlots` pode cobrar duas vezes o mesmo degrau | `business.lua:495` | RUNTIME_UNVERIFIED |
| XR-10 | Liquidação não transacional (vários writes) | `jobs.lua:972-1070` | CONFIRMED_BY_CODE |
| XR-11 | Débito antes da escrita em várias operações | `business.lua:223,439`, `progress.lua:123,162`, `garage.lua` | CONFIRMED_BY_CODE |
| XR-12 | Operações multi-query de empresa sem transação | `business.lua:223,358,516` | CONFIRMED_BY_CODE |
| XR-13 | Cache e DB atualizados em momentos distintos (sem `await` em `Credit/AddRep/CountDelivery`) | `business.lua:146-190` | CONFIRMED_BY_CODE |
| XR-14 | Jobs ativos só em memória; restart apaga entidades | `jobs.lua:1,1319` | CONFIRMED_BY_CODE |
| XR-15 | `lib.callback.await` servidor→cliente sem tratamento de timeout | `jobs.lua:675,704` | UNKNOWN (depende da versão do ox_lib) |
| XR-16 | Sem rate limit nos callbacks | `callbacks.lua:1-6` | CONFIRMED_BY_CODE (ausência) |
| XR-17 | IA dos guardas depende do dono de rede | `guards.lua:49-52` | RUNTIME_UNVERIFIED |
| XR-18 | `GetAllVehicles()` por checagem de baia | `jobs.lua:17-35` | CONFIRMED_BY_CODE (custo só no spawn) |
| XR-19 | Laço de cliente por frame durante todo o job | `job.lua:276` | CONFIRMED_BY_CODE |
| XR-20 | Dependências externas na NUI (fontes e imagens) | `index.html`, `page-truck.js:7` | CONFIRMED_BY_CODE |
| XR-21 | Bug cosmético `/s+/` | `page-business.js:24` | CONFIRMED_BY_CODE |
| XR-22 | Sem testes automatizados; checkers não ligados a CI | ausência de `tests/`; workflows | CONFIRMED_BY_CODE |
| XR-23 | Suporte só Qbox/QBCore (sem ESX) | `bridge/framework.lua:18-24` | CONFIRMED_BY_CODE |
| XR-24 | Providers de chaves do lado do cliente delegam confiança a eventos de terceiros | `keys.lua:53-86` | DESIGN LIMIT (fora do XS) |

---

## 12. Rastreabilidade: finding → evidência → referência → proposta

| Finding (AUST) | Evidência no AUST | Referência XS (ideia) | Proposta (PLAN ID) |
|---|---|---|---|
| Sem validadores estáticos; deploy sem validação | `deploy.yml`; `14_…` TD-12/13/27 | `tools/check-*.mjs` | **W0-04A–H** |
| Integrações espalhadas (chaves/combustível/polícia/target) | `server/events.lua:341…`, `client/client.lua:169`, `illegal_service.lua:98` | `bridge/*.lua` | **W6-07** |
| Prova de entrega fraca (ped + tempo) | `12_…` SEC-02 | `Jobs.Deliver`, `dockScore` | **W3-01** (já existente) |
| Sem orphan mode; statebags de cliente | `11_…`; TD-22/26 | `jobs.lua:37-47,476` | **W4-01, W4-03** |
| Espera de controle de rede sem limite/confirmação | `11_…` §1 | `takeControl` | **W4-05** |
| Entrada do cliente aceita sem política | combustível/hora no XS como contraexemplo | `XR-02/03` | **W3-10** |
| Settings só por `config.lua` | — | `settings.lua` | **W5-05** |
| Dispositivos e NUI duplicada | `html/`, `client/client.lua:427` | NUI modular + RPC | **STUDY-DEVICE-01, W6-06** |
| Route Builder (requisito admin-only) | — | `admin.lua`, builder/placement | **W5-06** (estudo de validação), requisito em `19_…` |
| NPCs de segurança (ilegal/escolta) | — | `guards.lua`, `jobs.lua:630` | **W6-08** (estudo) |
| Resume do job após restart do cliente | `11_…` (ActiveJob se perde) | `job.lua:530` | **W4-02** (nota) |

---

## 13. Legal / licença

- XS: **ALL RIGHTS RESERVED** → **DO NOT COPY SOURCE CODE**.
- Permitido nesta análise: estudar comportamento, arquitetura e conceitos; **reimplementação independente**.
- Todo item derivado deve trazer **IDEA ONLY — INDEPENDENT REIMPLEMENTATION** (feito no plano e no checklist).
- Cuidado adicional: documentos de reimplementação devem partir do **comportamento descrito aqui**, não dos arquivos do XS abertos ao lado (prática *clean-room* recomendada a J2).

## 14. Lacunas abertas

- Nenhum teste em jogo; nenhum checker do XS foi executado.
- `tools/.natives-cache.json` lido só no início.
- Versões de ox_lib/oxmysql do servidor do AUST não foram consultadas (afeta XR-15 e semântica de `await`).
- Fontes de `nexus_os`, `vp_tablet`, `vp_phone` **não** foram lidas (ver doc 19).
