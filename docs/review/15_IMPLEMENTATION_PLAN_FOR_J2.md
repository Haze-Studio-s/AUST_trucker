# 15 — Implementation Plan for J2 (PROPOSTA — nada implementado)

**ANALYZED HEAD: `c9d9187`** (revisão V2 sobre a base documental `3a89631`; código idêntico). Este plano é **proposta para revisão**. **Nenhum item foi implementado por este pacote.** Todo item exige **J2 APPROVAL REQUIRED: YES** antes de qualquer alteração de código (ver `17_J2_REVIEW_CHECKLIST.md`). Ordem das ondas = ordem de risco crescente; cada onda só começa depois do aceite da anterior.

**Opções de decisão por item (J2):** `APPROVE` · `APPROVE WITH CHANGES` · `REJECT` · `DEFER` · `NEEDS RUNTIME PROOF` · `NEEDS MORE ANALYSIS`. Itens derivados do XS-Trucking trazem **IDEA ONLY — INDEPENDENT REIMPLEMENTATION** (licença *all rights reserved*).

Campos por item: **ID · Título · Origem (TD/SEC/doc) · Arquivos prováveis · Proposta · Referência · Depende de · Risco · Aceite / prova de runtime · Rollback**. Todos: *J2 approval required = YES; flag/feature-toggle quando houver mudança de comportamento.*

## Onda 0 — Base legal, documental e de medição (sem código de jogo)

| ID | Título | Origem | Arquivos prováveis | Proposta | Ref. | Dep. | Risco | Aceite / prova | Rollback |
|---|---|---|---|---|---|---|---|---|---|
| W0-01 | LICENSE/NOTICE e política de referências | LEGAL-01/02 | `LICENSE`, `NOTICE` (novos) | aviso MIT do Polarix; decisão da licença do AUST; regra "só ideias" para refs sem licença compatível | `08_…` §licenças | — | nenhum | revisão jurídica do dono | remover arquivos |
| W0-02 | Alinhar versão | DOC-01 | `fxmanifest.lua`, README, CHANGELOG | uma versão única | — | — | baixo | grep de versão | reverter |
| W0-04 | Verificadores estáticos FiveM (ideia do XS-Trucking, **reimplementação independente**; sub-tarefas A–H abaixo) | `08b_…` §10, TD-43 | `tools/` (novo, Node; fora do runtime do jogo) + opcional passo de validação antes do deploy | verificadores heurísticos que **só relatam**; cada sub-tarefa é aprovável isoladamente | XS (**IDEA ONLY**) | — | baixo | rodar localmente e listar achados (sem corrigir); decisão separada para plugar no `deploy.yml` | remover `tools/` |
| W0-03 | Plano de testes de runtime | `11_…` §5 | `docs/` | executar a matriz de testes multi-jogador como linha de base **antes** das mudanças | — | — | nenhum | planilha de resultados | — |


### W0-04 — sub-tarefas (documentadas sem criar 8 PLAN IDs; J2 pode aprovar todas, algumas ou só as de prioridade)

> **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.** Não copiar o source do XS (licença *all rights reserved*). Cada sub-tarefa parte do **comportamento descrito em `08b` §10**, não dos arquivos do XS. Todos só **reportam**; nenhum corrige código.

| Sub-ID | Verificador | Defeitos reais do AUST que ajuda a revelar | Prioridade sugerida |
|---|---|---|---|
| W0-04A | Manifest ↔ disco (+ HTML/`files{}`/glob) | `shared/fork_lift.lua` fora do manifest (W1-02), órfãos (TD-07), deriva de versão (DOC-01) | **alta** |
| W0-04B | Eventos/callbacks (duplicado, sem handler, `await` sem registro) | `playerDropped` conflitante (TD-27), eventos NO CONSUMER (doc 04), `VP_Trucker` indefinido (TD-12) | **alta** |
| W0-04C | Contrato NUI (POST ↔ `RegisterNUICallback`; RPC ↔ allowlist ↔ callback; sem host fixo) | acoplamento NUI (TD-07); base para futuros dispositivos (doc 19) | **alta** |
| W0-04D | Validade de natives (lista oficial) | chamadas só quebram em runtime | média |
| W0-04E | Guarda de netId no cliente (`NetworkDoesNetworkIdExist`) | `WaitForNetworkEntity` sem retry/entidade `nil` (TD-31), spam de console em late join | média |
| W0-04F | Compatibilidade de lado (`os`/`io` no cliente; natives de cliente em `shared`) | arquivos `shared/*` | média |
| W0-04G | Multi-retorno Lua (`return s:gsub(...)`) | classe de erro de parâmetros no oxmysql | média |
| W0-04H | Sintaxe JS (sem executar) | páginas NUI que não carregam | média |

Observação: nenhum desses verificadores detectaria o `SetInterval` com argumentos trocados (TD-13); isso exige checagem de assinatura própria.

## Estudos (sem código)

| ID | Título | Origem | Escopo | Risco | Decisão |
|---|---|---|---|---|---|
| **STUDY-DEVICE-01** | Auditar a capacidade de integração de **NexusOS / vp_tablet / vp_phone** | doc 19 | ler `Haze-Studio-s/nexus_os`, `vp_tablet`, `vp_phone` e mapear: registro de apps, exports, eventos, callbacks, notificações, deep links, badges, permissões, eventos em segundo plano, comunicação NUI, ciclo de vida do resource. Entregável: documento de **fatos** (arquivo/função). | **NONE — STUDY ONLY** | **J2 APPROVAL REQUIRED: YES** (inclui autorizar acesso de leitura aos três repositórios) · APPROVE / REJECT / DEFER |

## Onda 1 — Forklift / pallet (Fase 2A já tem base atrás de flag; **2B não inicia sem aprovação**)

| ID | Título | Origem | Arquivos prováveis | Proposta | Ref. | Dep. | Risco | Aceite / prova | Rollback |
|---|---|---|---|---|---|---|---|---|---|
| W1-01 | Capturar telemetria real do pallet | `07_…`, `10_…` | `client/modules/pallet_debug.lua` (já existe) | sessões com `Config.Debug` em forklift real: altura da pista, `zLift`, momento do salto Havok, 2 clientes | A, C | W0-03 | baixo | CSV de telemetria; define o 0,35 m medido | desligar debug |
| W1-02 | Carregar `shared/fork_lift.lua` | TD (LOAD_ORDER) | `fxmanifest.lua` (1 linha em `shared_scripts` após `pallet_sync_guard.lua`) | módulo puro, já existente e testado (77 casos) | — | — | baixo | `fxmanifest` carrega sem erro | remover linha |
| W1-03 | Patch cinemático no cliente | `07_…`, `10_…` Modelo D-K | `client/modules/forklift.lua` (`KinematicPalletStep`, `StartAssistedAttach`, `KLReleaseAllCarried`, estado em escopo de módulo, guarda no laço legado) + **timeout customizado do claim** (o padrão de `lib.callback.await` é 5 min) | pallet frozen até attach; lift lido no osso do garfo; attach preserva a pose do mundo | A | W1-01, W1-02 | MÉD | **runtime:** 3 pallets × 3 alturas, 2 observadores | `KinematicLift.Enabled=false` |
| W1-04 | Limiar medido | TD-06 | `shared/config.lua`, `forklift.lua:721` | usar a config (ou remover `MaxLiftTolerance`) com o valor de W1-01 | — | W1-01 | BAIXO | valor medido documentado | reverter |
| W1-05 | Ligar a flag em staging | TD-25 | `shared/config.lua` | `KinematicLift.Enabled=true` só em staging; reqId/lease/CAS do `PalletRegistry` passam a valer | C (idempotência) | W1-03 | MÉD | stow/deliver/drop; queda do operador (`Recover`) | `Enabled=false` |

> **Estado atual (fato):** sem W1-02/W1-03, `Enabled` **deve permanecer `false`** (a regra estrita rejeitaria todo stow). Pendente: autorização para editar `fxmanifest.lua` e `client/modules/forklift.lua` ou receber o diff.

## Onda 2 — Defeitos funcionais verificados (baixo risco)

| ID | Título | Origem | Arquivos prováveis | Proposta | Dep. | Risco | Aceite / prova | Rollback |
|---|---|---|---|---|---|---|---|---|
| W2-01 | Car carrier: netId × handle | TD-11 | `client/modules/car_carrier.lua:158-160` | converter com `NetToVeh`/`NetworkGetNetworkIdFromEntity` conforme o uso | — | BAIXO | carregar/descarregar um carro | reverter |
| W2-02 | Escopo de `StartDeliveryRoute` e espera `VP_Trucker` | TD-10, TD-12 | `client/main.lua:619,661`; `client/client.lua:2760` | mover a função para escopo correto; remover a espera por global inexistente | — | BAIXO | rota de entrega abre; HQ não trava | reverter |
| W2-03 | Ordem de `SetInterval` no convoy | TD-13 | `server/services/convoy_service.lua:22` | conferir a assinatura do `SetInterval` usado e corrigir a ordem | — | BAIXO | posições de convoy chegam a cada 3 s | reverter |
| W2-04 | Caminho de carregamento liquid/ADR | TD-05 | cliente de cargo Polarix | ligar o driver de cliente ou documentar como desligado | W2-02 | MÉD | iniciar missão liquid/ADR | reverter |
| W2-05 | Job ilegal iniciável | TD-14 | `client/illegal.client.lua`, `events.lua:239` (único emissor de `client:jobStarted`) | emitir o evento no caminho ilegal | — | BAIXO | iniciar job ilegal | reverter |
| W2-06 | Forklift de emergência | TD-29 | `server/main.lua` (spawn de emergência) | lock de dono, plate, chaves e devolver o netId ao cliente | — | BAIXO | spawn e uso | reverter |

## Onda 3 — Autoridade do servidor / segurança (cada item atrás de flag)

| ID | Título | Origem | Proposta | Ref. | Dep. | Risco | Aceite / prova |
|---|---|---|---|---|---|---|---|
| W3-01 | Prova de entrega por entidade (+ ideia de **docking score** do XS: distância 2D e heading do trailer medidos no servidor; **IDEA ONLY**) | TD-02, TD-21 (SEC-02) | no `complete`, verificar no servidor posição do caminhão/trailer e carga (`GetEntityCoords` das entidades registradas), não só ped+tempo | H (`Jobs.Deliver`), G | W3-09 | ALTO | **runtime:** teleport+timer deve falhar; entrega legítima passa |
| W3-02 | Flatbed/repo/aluguel: papel e limpeza | TD-17, TD-18, TD-23 | restringir attach a missão/papel; liberar ordem de repo em queda; apagar forklift/handler na conclusão; corrigir reembolso do aluguel | G, J | — | MÉD | cenários de queda e de abuso |
| W3-03 | Spawn point e trailer | TD-19 | `IsSpawnPointClear` não apaga veículos de terceiros (só os do próprio job); validar posição do trailer no servidor | H | — | MÉD | spawn com carro de terceiro no ponto |
| W3-04 | Contratos | TD-15, TD-24 | UPDATE no cancelamento LC; rate limit em `Negotiate`; prova de carga | G | — | MÉD | cancelar contrato → banco consistente |
| W3-05 | Party/convoy | TD-13 (jobs públicos) | `Kick` libera convoy; atribuir jobs corretamente | H | W2-03 | MÉD | kick durante convoy |
| W3-06 | Indústria e reabastecimento | TD-16 | definir produção/consumo; caminho de aceite do resupply | I | — | MÉD | resupply completo |
| W3-07 | Parcel | `05_…` | cancelar no servidor em recusa; cooldown no start | G | — | BAIXO | recusa libera estado |
| W3-08 | Export de petróleo | TD-24 | validar `qty/price` no servidor; retorno de barris no stop | I | — | MÉD | valores forjados rejeitados |
| W3-09 | Registro de entidades | TD-20 (SEC-01) | `validateJobEntity`: provar que a entidade foi criada pelo servidor para este job; dois clientes não registram o mesmo carro | F | — | MÉD | **runtime:** 2 clientes, mesmo carro |
| W3-10 | Política para **entradas do cliente consumidas pelo servidor** | `08b` XR-02/XR-03 (contraexemplos), TD-21/TD-22 | todo dado vindo do cliente que o servidor consome (ex.: combustível, hora, estado de hitch) deve ser **clampado, limitado em impacto e documentado**; preferir derivar no servidor quando possível; checklist de revisão para fluxos novos | XS (**IDEA ONLY**, como contraexemplo) | W3-01 | BAIXO | documento de política aprovado; aplicado primeiro ao PR #9 e aos novos fluxos |

## Onda 4 — OneSync / rede (exige prova de runtime antes de decidir)

| ID | Título | Origem | Proposta | Risco | Aceite / prova |
|---|---|---|---|---|---|
| W4-01 | Orphan mode (referência: XS usa `SetEntityOrphanMode` em veículos/guardas criados no servidor; **IDEA ONLY**) | TD-26 | testar o comportamento padrão; se necessário aplicar `SetEntityOrphanMode` por tipo de entidade | MÉD | queda do dono com pallet/trailer |
| W4-02 | Queda/reconexão | TD-27, TD-28, TD-31 | unificar os handlers de `playerDropped`; limpeza de entidades de cliente; retry de `WaitForNetworkEntity` | MÉD | queda, reconexão, streaming lento |
| W4-03 | Statebags escritas pelo cliente (referência: XS escreve `xsTrucking`/`xsGuard` só no servidor; **IDEA ONLY**) | TD-22 | mover a escrita para o servidor (`loadedSlots`, `forklift_owner`, flatbed) | MÉD | cliente adulterado não altera |
| W4-04 | Resource stop | TD-30 | limitar a varredura a entidades marcadas pelo recurso | MÉD | restart com 2 jogadores |
| W4-05 | Helper de **controle de rede limitado e confirmado** no cliente | TD-45, `08b` §5 | padrão `REQUEST → RETRY BOUNDED → CONFIRM → MUTATE` para `NetworkRequestControlOfEntity` (tentativas e tempo limitados; só muta se o controle foi confirmado); **IDEA ONLY — INDEPENDENT REIMPLEMENTATION** | BAIXO | **runtime:** 2 clientes disputando o mesmo pallet/trailer |

## Onda 5 — Admin e desempenho

| ID | Título | Origem | Proposta |
|---|---|---|---|
| W5-01 | Log de auditoria admin | TD-41 | registrar eventos de admin (ref. H `guarded()`) |
| W5-02 | Join tardio de offsets | TD-41 | enviar offsets no join |
| W5-03 | Hotspots top 15 (`13_…` §4) | TD-32..36 | começar pelos 3 maiores (escudo Havok, cintas, HUD); medir com `resmon` antes/depois |
| W5-04 | Leaderboard e cache de offsets | TD-08, TD-09 | corrigir tabela; usar cache |
| W5-05 | Settings ao vivo no painel admin (opcional) | `08b_…` | schema declarativo com min/max, fallback no `Config`; persistência em tabela nova (**migração revisada**) |
| W5-06 | **Validação de posicionamento** em ferramentas admin (footprint do modelo, piso, água, sobreposição) | `08b` §8.3 | **estudo apenas** (**IDEA ONLY — INDEPENDENT REIMPLEMENTATION**): avaliar se uma checagem de footprint/piso/água agregaria ao PropEditor 6DoF; **não substitui** o PropEditor e **não cria Route Builder**; qualquer ferramenta resultante é **ADMIN ONLY** |

## Onda 6 — Consolidações (maior risco de dados; sempre com migração revisada)

| ID | Título | Origem | Proposta / notas |
|---|---|---|---|
| W6-01 | Decidir pilha de NUI (jQuery × React) | TD-07 | — |
| W6-02 | Ledger de empresa e limpeza na venda | TD-40 | — |
| W6-03 | Modelo único de frota | TD-37 | — |
| W6-04 | Fonte única de nível/progressão | TD-38 | — |
| W6-05 | Separar sistemas de NPC driver; atomizar reserva | TD-39 | — |
| W6-06 | **Integração unificada de dispositivos do AUST** (NexusOS = gestão · vp_tablet = operação · vp_phone = notificações · AUST = backend canônico · Route Builder = **ADMIN ONLY**) | doc 19, TD-44 | **depende de STUDY-DEVICE-01**; UX por dispositivo **sem duplicar regra de negócio** (decisões só no servidor do AUST); **não implementar até revisão** de J2 e do código dos três resources |
| W6-07 | **Camada de integration bridges** (framework/fuel/inventory/keys/target/dispatch) | TD-42, `08b` §6 | CONFIG → autodetecção/força de provedor → API canônica → domínio; fallback próprio quando o provedor falha; registry de target com limpeza; **IDEA ONLY — INDEPENDENT REIMPLEMENTATION** |
| W6-08 | **Padrão de NPCs de segurança criados no servidor** (ilegal/escolta) | `08b` §5, XR-17 | **estudo apenas** (**IDEA ONLY — INDEPENDENT REIMPLEMENTATION**): `SERVER STATE → NETWORK OWNER → CLIENT AI EXECUTION`; **não implementar** |

## Gameplay Study Wave (STUDY ONLY — referência TrueMaps, sem código)

> Inserida **antes da Onda 7** (refatoração estrutural), **depois da Onda 6**; **a ordem existente não foi alterada**. Justificativa: são itens de **estudo** sem código, podem rodar em paralelo às ondas 3–6, mas qualquer implementação decorrente só faz sentido **depois** de W1 (pallet), W3 (autoridade), W4 (rede) e do estudo de dispositivos. TrueMaps é **referência de gameplay (transcrição da narração fornecida + brief; sem código); **TECHNICAL IMPLEMENTATION UNKNOWN****; nada de arquitetura é inferido dele. Detalhes em `20_TRUEMAPS_GAMEPLAY_REFERENCE.md`.

Todos os itens: **STUDY ONLY · J2 APPROVAL REQUIRED: YES · CODE CHANGE: NO** · opções de decisão **APPROVE / DEFER / REJECT**. Todos: **IDEA ONLY — INDEPENDENT REIMPLEMENTATION**.

| ID | Título | Prioridade | Estudo (resumo) | Depende de (para um futuro) |
|---|---|---|---|---|
| GPLAY-01 | Pallet Jack (+ descarga em local designado) | ALTA | modelo de interação, claim, colisão, movimento, animação, autoridade de rede, ownership, zonas de carga, baia do caminhão, observador; comparar com forklift/reach stacker; **J2 escolhe A) pallet em rede · B) assisted attach · C) representation swap · D) híbrido** | W1-03/W1-05, W4-05 |
| GPLAY-02 | Cargo Ramp / Liftgate (+ portas) | ALTA | rampa/liftgate (**narrado**), portas (**só brief**), permissão de carga; estado, dono, replicação, desconexão | W4-02 |
| GPLAY-03 | Courier Package Scanner | ALTA | identidade de pacote, parada, barcode, scanner, pacote errado/correto, assinatura; **servidor decide pacote × parada** | W3-07 |
| GPLAY-04 | Cargo Integrity | ALTA | impacto, velocidade, velocidade angular, tipo de carga, acúmulo; **sem confiar em dano arbitrário do cliente** (vídeo narra colisão/dano → pagamento); RUNTIME PROOF REQUIRED | W3-10 |
| GPLAY-05 | Precision Docking | ALTA | `dockScore` do XS como referência técnica; cálculo no servidor; saída score/bônus/XP/rating | W3-01 |
| GPLAY-06 | Active Escort Gameplay | ALTA | (**narrado**: garantir rota, ajudar a manobrar, remover obstáculos) pilot car, luzes, scout, obstáculo, controle temporário de via, suporte ao comboio (Heavy RP: VERY HIGH) | W3-05, W4-02 |
| GPLAY-07 | Oversized Route Clearance | **ALTA** | dimensões, **pontes (narrado)**, túneis (só brief), curvas, obstruções; planejamento de rota pelo motorista (narrado); fonte de dados de mapa **UNKNOWN** | GPLAY-06 |
| GPLAY-08 | Road Obstacle Interaction | MÉDIA (ALTA se GPLAY-06 aprovado) | criar/remover obstáculo de via; ciclo de vida e limpeza | GPLAY-06, W4-02 |
| GPLAY-09 | Special Transport Convoy | MÉDIA (ALTA se GPLAY-06/07 aprovados) | oversized + escolta ativa + pilot car sobre o convoy atual | GPLAY-06/07 |
| **GPLAY-10** | Long-form logistics jobs | **ALTA** | evidência **VIDEO NARRATION CONFIRMED**: jobs complexos de 30+ min; estudar engajamento, checkpoints, tarefas físicas, risco, multi-parada, recuperação, progresso parcial, desconexão, escala de recompensa, fadiga; **jobs mais profundos, não apenas mais longos** | TD-02, W4-02, W3-10 |
| **GPLAY-11** | Trailer dimensional route constraints | **ALTA** | evidência **VIDEO NARRATION CONFIRMED**: 8 trailers de dimensões diferentes; oversized não passa em toda ponte; estudar largura/altura do trailer e da carga, folga de rota, restrições de ponte/túnel, rotas permitidas, **metadados de folga criados por admin**; **Route Builder ADMIN ONLY** (jogadores só planejam) | GPLAY-07, W0-04 |

**Dispositivos (proposta):** nenhuma UI isolada nova; **NEXUSOS** = planejamento de job, gestão da empresa, planejamento de rota oversized, frota, contratos; **VP_TABLET** = manifesto, checklist de carregamento, tarefas de pallet/carga, courier scanner, condição da carga, rota ativa, tarefas de escolta; **VP_PHONE** = atribuição de job, convites de empresa/convoy, alertas, manutenção, notificações de frota; **Route Builder = ADMIN ONLY** (ver doc 19/20). Dependência dos itens de UI: **STUDY-DEVICE-01**.

## Onda 7 — Refatoração estrutural (só após ondas 1–5 estáveis)

| ID | Título | Origem |
|---|---|---|
| W7-01 | Dividir monólitos por domínio | TD-01 |
| W7-02 | Registro único de job e encapsulamento de estado | TD-02, TD-04 |
| W7-03 | Avaliar fusão dos dois forklifts | TD-03 |

## Onda 8 — Remoções

| ID | Título | Origem |
|---|---|---|
| W8-01 | Remover candidatos a órfão **provados** | §7 de `14_…`; item a item, com grep de consumidores e runtime |

## Primeira onda recomendada

**Onda 0 (começando por W0-04A–C) + Onda 2 (W2-01…W2-03) + medição W1-01; STUDY-DEVICE-01 em paralelo (somente leitura, após autorização).** Razão: risco baixo, defeitos verificados por leitura, nenhuma mudança de física/rede/economia, e a telemetria (W1-01) é o dado que falta para decidir a Onda 1 com evidência. W1-02/W1-03 só quando houver autorização explícita.

## Itens de prova de runtime exigidos

W1-01, W1-03, W1-05, W2-01…W2-06, W3-01, W3-02, W3-03, W3-09, W4-01…W4-05, W5-03 (profiler), W6-07 (provedores reais).

## Dependências críticas

W1-03 → W1-02 e W1-01; W1-05 → W1-03; W3-01 → W3-09; W3-05 → W2-03; W3-10 → W3-01; **W6-06 → STUDY-DEVICE-01**; W6-06 usa W0-04C; GPLAY-* só viram implementação após W1/W3/W4 e STUDY-DEVICE-01; W7-* → ondas 1–5.

## Índice de PLAN IDs (revisão V2)

**60 IDs (49 PLAN IDs + 11 GPLAY de estudo):** W0-01…W0-04 (4; W0-04 com sub-tarefas A–H) · STUDY-DEVICE-01 (1) · W1-01…W1-05 (5) · W2-01…W2-06 (6) · W3-01…W3-10 (10) · W4-01…W4-05 (5) · W5-01…W5-06 (6) · W6-01…W6-08 (8) · W7-01…W7-03 (3) · W8-01 (1). **Novos na V2:** STUDY-DEVICE-01, W3-10, W4-05, W5-06, W6-06, W6-07, W6-08 (e o detalhamento A–H de W0-04). Nenhum foi executado.
**Adicionados na revisão TrueMaps (STUDY ONLY):** GPLAY-01…GPLAY-11 (10 e 11 após a transcrição). Nenhum foi executado; dependências em `Gameplay Study Wave`.
