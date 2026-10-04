# 14 — Tech Debt Register

**ANALYZED HEAD: `c9d9187`.** Registro **somente de leitura**: nada foi corrigido. Cada item aponta a evidência (arquivo/função já lidos nos relatórios 01–13) e o PLAN ID que o endereça (ver `15_IMPLEMENTATION_PLAN_FOR_J2.md`). Severidade: **P0** quebra/exploração imediata, **P1** alto, **P2** médio, **P3** baixo. Nenhum item P0 foi encontrado. "Prova de runtime" = precisa de teste em jogo.

Categorias: LEGACY, ORPHAN_CANDIDATE, DUPLICATION, PARTIAL_REPLACEMENT, MONOLITH, GLOBAL_STATE, CONFIG_DRIFT, DOC_DRIFT, LOAD_ORDER, MISSING_CLEANUP, MISSING_IDEMPOTENCY, CLIENT_TRUST, NETWORK_RISK, DB_COUPLING, NUI_COUPLING, LEGAL.

## 1. Legal e documentação

| ID | Sev | Categoria | Domínio | Evidência | Impacto | Recomendação | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|
| LEGAL-01 | P1 | LEGAL | repo | AUST deriva do Polarix (MIT) e **não tem LICENSE na raiz**; a licença MIT exige manter o aviso de copyright em cópias substanciais | risco de redistribuição sem atribuição | adicionar LICENSE/NOTICE com o aviso do Polarix e decidir a licença do AUST (**decisão de J2/dono**) — PLAN W0-01 | nenhum (só texto) | não |
| LEGAL-02 | P2 | LEGAL | referências | XS-Trucking é "all rights reserved"; Distortionz_Towjob, ESX_Deliveries, xDope sem licença; Don/Mobius/qb-truckerjob/ls_trucking/fiji-oil/ox_inventory são GPL-3.0 | copiar código violaria licença | política: **só ideias** dessas referências; código só do Polarix (MIT) e ox_target (MIT) com atribuição — PLAN W0-01 | nenhum | não |
| DOC-01 | P3 | DOC_DRIFT | repo | `fxmanifest.lua` 20.8.5 × README/CHANGELOG 20.9.0 | confusão de versão | alinhar versão — PLAN W0-02 | baixo | não |

## 2. Estrutura (monólitos, duplicação, estado global)

| ID | Sev | Categoria | Domínio | Evidência | Impacto | Recomendação | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|
| TD-01 | P2 | MONOLITH | todos | `client/main.lua` (≥3200 linhas), `client/client.lua` (≥3400), `server/main.lua` (≥2400), `events.lua` (≥2180): lógica de job, UI, rede e física misturadas | mudanças tocam muitos fluxos; revisão difícil | dividir por domínio **depois** de estabilizar (PLAN W7-01) | ALTO | sim (regressão) |
| TD-02 | P1 | DUPLICATION | core job | 3 sistemas sem registro comum: `PolarixLobbies` (`server/main.lua:157`), `trucker_jobs`/`JobService`, `ActiveLCContracts` (`events.lua:81`) | estados divergentes; limpeza e pagamento em 3 lugares | registro único de job (PLAN W3-01, W7-02) | ALTO | sim |
| TD-03 | P2 | DUPLICATION | forklift | `modules/forklift.lua`+`server/main.lua` (Polarix) × `client/forklift.client.lua`+`forklift_service.lua` (trade point, evento `a:palletLoaded`) | duas físicas/pipelines | manter separados até W1 concluir; avaliar fusão (PLAN W7-03) | MÉD | sim |
| TD-04 | P2 | GLOBAL_STATE | todos | tabelas globais (`PolarixLobbies`, `ActiveLCContracts`, `PlayerJobEntities`, `ActiveMissionPallets`…) sem dono único | corrida entre handlers | encapsular por serviço (PLAN W7-02) | MÉD | não |
| TD-05 | P3 | PARTIAL_REPLACEMENT | cargo/ADR | cargo líquido e ADR do Polarix sem driver de carregamento no cliente (fluxos 05) | caminho inalcançável | PLAN W2-04 | MÉD | sim |
| TD-06 | P3 | CONFIG_DRIFT | pallet | `MaxLiftTolerance=0.35` em `shared/config.lua` **não é usado**; o 0,35 está fixo em `client/modules/forklift.lua:721` | configuração enganosa | ligar a config ao código ou remover — PLAN W1-04 | BAIXO | sim (valor) |
| TD-07 | P2 | ORPHAN_CANDIDATE / NUI_COUPLING | NUI | `html/index.html`+`panel.js` (jQuery) são servidos; `html/src` (React) e `assets/index-*` não são referenciados (**UNKNOWN**: pode ser build parado) | duas bases de UI | decidir uma pilha — PLAN W6-01 | MÉD | não |
| TD-08 | P3 | DB_COUPLING | leaderboard | `callbacks.lua:392,402` consultam tabela inexistente `trucker_company`; falham em `pcall` a cada `getInitialData` | desperdício + dado ausente | corrigir nome ou remover — PLAN W5-04 | BAIXO | não |
| TD-09 | P3 | DB_COUPLING | offsets | `getTrailerOffsetsForModel` (`callbacks.lua:1731`, `server/main.lua:1328`) recarrega do banco por chamada | carga desnecessária | usar cache `AdminService.TrailerOffsets` — PLAN W5-04 | BAIXO | não |

## 3. Defeitos funcionais verificados no código

| ID | Sev | Categoria | Domínio | Evidência | Impacto | Recomendação | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|
| TD-10 | P1 | PARTIAL_REPLACEMENT | core job (cliente) | `StartDeliveryRoute` com escopo diferente em `client/main.lua:619` e `:661` | rota de entrega pode ser nil | PLAN W2-02 | BAIXO | sim |
| TD-11 | P2 | PARTIAL_REPLACEMENT | car carrier | `client/modules/car_carrier.lua:158-160` mistura netId e handle | car carrier quebrado | PLAN W2-01 | BAIXO | sim |
| TD-12 | P2 | PARTIAL_REPLACEMENT | HQ/cliente | `client/client.lua:2760` espera `VP_Trucker` indefinido no cliente | espera sem fim | PLAN W2-02 | BAIXO | sim |
| TD-13 | P1 | PARTIAL_REPLACEMENT | convoy | `server/services/convoy_service.lua:22` chama `SetInterval(number, function)` (ordem contrária à do ox_lib local; ver SEC-25) | atualização de convoy não roda como pretendido | PLAN W2-03 | BAIXO | sim |
| TD-14 | P2 | PARTIAL_REPLACEMENT | job ilegal | job ilegal não pode ser iniciado no cliente (05) | feature morta | PLAN W2-05 | BAIXO | sim |
| TD-15 | P2 | DB_COUPLING | contrato LC | `events.lua:2148-2181` cancelamento LC sem UPDATE no banco | contrato fica ativo | PLAN W3-04 | BAIXO | sim |
| TD-16 | P2 | MISSING_CLEANUP | shop stock | reabastecimento sem caminho de aceite (dead end) | estoque nunca repõe | PLAN W3-06 | MÉD | sim |
| TD-17 | P2 | MISSING_CLEANUP | aluguel | caução possivelmente perdida na queda (ordem de reembolso, 05) | perda de dinheiro do jogador | PLAN W3-02 | MÉD | sim |
| TD-18 | P2 | MISSING_CLEANUP | frota | `server/main.lua:2143-2166`: conclusão com caminhão próprio não apaga forklift/handler | entidades vazadas | PLAN W3-02 | BAIXO | sim |
| TD-19 | P1 | MISSING_CLEANUP | spawn | `server/main.lua:468-497` `IsSpawnPointClear` **apaga veículos vazios** no ponto de spawn | pode apagar veículo de terceiro | PLAN W3-03 | MÉD | sim |

## 4. Confiança no cliente e segurança

| ID | Sev | Categoria | Domínio | Evidência | Impacto | Recomendação | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|
| TD-20 | P1 | CLIENT_TRUST | registro de entidades | `events.lua:88-150`: `validateJobEntity`/`accept()` marca toda entidade aceita como verificada (SEC-01, condicional) | cliente pode registrar carro parado | PLAN W3-09 | MÉD | sim |
| TD-21 | P1 | CLIENT_TRUST | entrega | prova de entrega = ped perto + tempo mínimo, sem caminhão/trailer/carga (SEC-02) | "teleport + timer" | PLAN W3-01 | ALTO | sim |
| TD-22 | P1 | CLIENT_TRUST | statebags | cliente escreve `forklift_owner` (`forklift.client.lua:158,330`), `loadedSlots`, `loadedForklift`, flatbed, `ct_vulnerable` (SEC-05/07/13) | forjável | PLAN W4-03 | MÉD | sim |
| TD-23 | P1 | CLIENT_TRUST | flatbed/repo | qualquer jogador anexa qualquer carro (11/12) | grief/roubo | PLAN W3-02 | MÉD | sim |
| TD-24 | P2 | CLIENT_TRUST | contrato/óleo | `Negotiate` sem rate limit; `qty/price` do export de petróleo vêm do chamador | abuso econômico | PLAN W3-04, W3-08 | MÉD | não |
| TD-25 | P2 | MISSING_IDEMPOTENCY | pallet legado | `a:palletLoaded` sem `reqId`; `PalletRegistry` (CAS/idempotente) está dormente no PR #9 | repetição de evento | PLAN W1-05 | MÉD | sim |

## 5. Rede / OneSync / desempenho

| ID | Sev | Categoria | Domínio | Evidência | Impacto | Recomendação | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|
| TD-26 | P2 | NETWORK_RISK | órfãos | nenhum `SetEntityOrphanMode` no repo | entidades podem ficar órfãs | decisão após teste — PLAN W4-01 | MÉD | **sim** |
| TD-27 | P2 | NETWORK_RISK | queda de jogador | handlers `playerDropped` conflitantes: `events.lua:380` (grace 3 min) × `events.lua:1207` (apaga na hora) | grace inútil; LC quick job vaza | PLAN W4-02 | MÉD | sim |
| TD-28 | P2 | NETWORK_RISK | entidades de cliente | aluguel, repo, container handler, trade point, parcel criam entidades networked no cliente sem dono travado nem limpeza no servidor | vazamento na queda | PLAN W4-02 | MÉD | sim |
| TD-29 | P2 | NETWORK_RISK | forklift de emergência | criado sem lock, plate, chaves; cliente não recebe o netId | inutilizável/vazado | PLAN W2-06 | BAIXO | sim |
| TD-30 | P2 | NETWORK_RISK | resource stop | cliente varre o pool e apaga objetos de modelo rastreado, **inclusive de outros scripts**; servidor apaga `PlayerJobEntities` sem filtro `verified` | efeito colateral em outros recursos | PLAN W4-04 | MÉD | sim |
| TD-31 | P2 | NETWORK_RISK | streaming | `WaitForNetworkEntity(netId, 4000)` sem retry (`client/main.lua:2523`) | entidade `nil` com streaming lento | PLAN W4-02 | BAIXO | sim |
| TD-32 | P2 | PERF | cliente | escudo Havok `client/main.lua:1293-1361` varre o pool de veículos ~4×/s para todos | CPU cliente | PLAN W5-03 | MÉD | sim (resmon) |
| TD-33 | P2 | PERF | cliente | cintas `client/main.lua:1030-1056` (~12 `DrawPoly` por cinta) | CPU cliente | PLAN W5-03 | BAIXO | sim |
| TD-34 | P3 | PERF | HUD | `hud.client.lua:391-396` NUI a 500 ms mesmo fora do caminhão | CPU/NUI | PLAN W5-03 | BAIXO | não |
| TD-35 | P2 | PERF | statebag | `loadedSlots` regravado inteiro (`server/main.lua:1562-1580`; handler `client/main.lua:3214-3235`) → O(N²) | picos com muitos pallets | delta por slot — PLAN W5-03 | MÉD | sim |
| TD-36 | P3 | PERF | servidor | aluguel: `GetAllVehicles()` a 3 s por aluguel sem netId (`truck_rental_service.lua:357`) | CPU servidor | PLAN W5-03 | BAIXO | não |

## 6. Consolidações de domínio

| ID | Sev | Categoria | Domínio | Evidência | Impacto | Recomendação | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|
| TD-37 | P2 | DUPLICATION | frota | 2 modelos (`trucker_trucks`, `trucker_company_vehicles`) + aluguel; `fleet:repairTruck` ignora o lock | inconsistência | PLAN W6-03 | ALTO | sim |
| TD-38 | P3 | DUPLICATION | progressão | 3 stores e 2 fontes de nível | níveis divergentes | PLAN W6-04 | MÉD | não |
| TD-39 | P2 | DUPLICATION | NPC driver | 2 sistemas; job devolvido a `available`; evento preso | estado preso | PLAN W6-05 | MÉD | sim |
| TD-40 | P3 | MISSING_CLEANUP | empresa | venda deixa indústria órfã; sem ledger | dados órfãos | PLAN W6-02 | MÉD | não |
| TD-41 | P3 | LEGACY | admin | eventos de admin sem log de auditoria; join tardio sem offsets | rastreabilidade | PLAN W5-01, W5-02 | BAIXO | não |

## 7. Candidatos a remoção (ORPHAN_CANDIDATE) — **nenhuma remoção é proposta sem prova**

Antes de qualquer remoção: grep de consumidores + runtime. Candidatos listados no inventário (`01_RESOURCE_INVENTORY.md`, status ORPHAN_CANDIDATE / LEGACY_ACTIVE / NO CONSUMER em `04_…`): `html/src` + `assets/index-*` (TD-07), eventos marcados **NO CONSUMER** em `04_EVENT_CALLBACK_GRAPH.md`, e os caminhos mortos de TD-05/TD-14. Ação proposta: PLAN W8-01 (inventário final de remoção, aprovado item a item por J2).

## 8. Itens adicionados pela revisão V2 (estudo do XS-Trucking)

| ID | Sev | Categoria | Domínio | Evidência (AUST) | Impacto | Referência (ideia) | Recomendação (PLAN) | Risco de impl. | Prova runtime |
|---|---|---|---|---|---|---|---|---|---|
| TD-42 | P2 | DUPLICATION | integrações | chaves `qbx_vehiclekeys`/`qb-vehiclekeys` espalhadas (`server/events.lua:341,351,431,1825-1828,2166,2201,2487`; `server/main.lua:361-365`); combustível `ox_fuel`/`cdn-fuel` (`client/client.lua:169-180`; `client/main.lua:2574`); polícia fixa no job `police`, sem dispatch configurável (`server/services/illegal_service.lua:98-115`); `Config.Target` vs `exports.ox_target` direto (`shared/config.lua:13`; `client/zones.lua:217,301`); framework **sem autodetecção** (`Config.Framework`) | trocar de provedor exige editar o domínio; sem fallback | XS `bridge/*.lua` (**IDEA ONLY**) | camada de bridges — **W6-07** | MÉD | sim |
| TD-43 | P2 | LOAD_ORDER (lacuna de ferramenta) | validação | não há verificadores FiveM-específicos; `.github/workflows/deploy.yml` faz rsync `--delete` a cada push em `main`/`master` **sem etapa de validação**; `tests/` só cobre o PR #9 | erros de manifest/evento/NUI/native só aparecem em runtime; o deploy de produção não tem etapa de validação (o ambiente `production` pode exigir aprovação manual: configuração do GitHub **não verificada**) | XS `tools/check-*.mjs` (**IDEA ONLY**) | **W0-04A–H** (reimplementação independente) | BAIXO | não |
| TD-44 | P3 | NUI_COUPLING | UI × dispositivos | UI standalone própria (`client/main.lua:418-440`; TD-07); nenhuma integração com NexusOS/vp_tablet/vp_phone no código lido; sem fronteira explícita domínio × interface | risco de **duplicar regra de negócio por dispositivo** se a integração for feita sem backend canônico | contrato RPC do XS (**IDEA ONLY**) | **STUDY-DEVICE-01**, **W6-06** (doc 19) | MÉD | não |
| TD-45 | P2 | NETWORK_RISK | controle de rede (cliente) | espera ativa por controle de entidade sem helper limitado/confirmado (doc 11 §1: `NetworkRequestControlOfEntity`/`NetworkHasControlOfEntity` com 1,5–2 s e sem tratamento do "não obteve") | mutação (attach/freeze/props) pode rodar **sem** controle | XS `takeControl` (**DESIGN PATTERN**) | **W4-05** | BAIXO | sim |

## 9. Contagem (atualizada na revisão V2)

P1: LEGAL-01, TD-02, TD-10, TD-13, TD-19, TD-20, TD-21, TD-22, TD-23 (**9**). P2: LEGAL-02, TD-01, TD-03, TD-04, TD-07, TD-11, TD-12, TD-14, TD-15, TD-16, TD-17, TD-18, TD-24, TD-25, TD-26–TD-33, TD-35, TD-37, TD-39, **TD-42, TD-43, TD-45** (**31**). P3: DOC-01, TD-05, TD-06, TD-08, TD-09, TD-34, TD-36, TD-38, TD-40, TD-41, **TD-44** (**11**). P0: **0**. (A contagem de **segurança** P0–P3 do relatório 12 é separada: P0 0, P1 8, P2 14, P3 12.) As severidades dos itens novos seguem o mesmo critério da v1 (impacto × evidência); nenhuma severidade foi atribuída ao próprio XS (ver `08b` §11, evidência por classe).
