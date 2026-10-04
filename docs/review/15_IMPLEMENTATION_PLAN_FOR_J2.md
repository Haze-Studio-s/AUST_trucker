# 15 — Implementation Plan for J2 (PROPOSTA — nada implementado)

**ANALYZED HEAD: `c9d9187`.** Este plano é **proposta para revisão**. **Nenhum item foi implementado por este pacote.** Todo item exige **J2 APPROVAL REQUIRED: YES** antes de qualquer alteração de código (ver `17_J2_REVIEW_CHECKLIST.md`). Ordem das ondas = ordem de risco crescente; cada onda só começa depois do aceite da anterior.

Campos por item: **ID · Título · Origem (TD/SEC/doc) · Arquivos prováveis · Proposta · Referência · Depende de · Risco · Aceite / prova de runtime · Rollback**. Todos: *J2 approval required = YES; flag/feature-toggle quando houver mudança de comportamento.*

## Onda 0 — Base legal, documental e de medição (sem código de jogo)

| ID | Título | Origem | Arquivos prováveis | Proposta | Ref. | Dep. | Risco | Aceite / prova | Rollback |
|---|---|---|---|---|---|---|---|---|---|
| W0-01 | LICENSE/NOTICE e política de referências | LEGAL-01/02 | `LICENSE`, `NOTICE` (novos) | aviso MIT do Polarix; decisão da licença do AUST; regra "só ideias" para refs sem licença compatível | `08_…` §licenças | — | nenhum | revisão jurídica do dono | remover arquivos |
| W0-02 | Alinhar versão | DOC-01 | `fxmanifest.lua`, README, CHANGELOG | uma versão única | — | — | baixo | grep de versão | reverter |
| W0-03 | Plano de testes de runtime | `11_…` §5 | `docs/` | executar a matriz de testes multi-jogador como linha de base **antes** das mudanças | — | — | nenhum | planilha de resultados | — |

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
| W3-01 | Prova de entrega por entidade | TD-02, TD-21 (SEC-02) | no `complete`, verificar no servidor posição do caminhão/trailer e carga (`GetEntityCoords` das entidades registradas), não só ped+tempo | H (`Jobs.Deliver`), G | W3-09 | ALTO | **runtime:** teleport+timer deve falhar; entrega legítima passa |
| W3-02 | Flatbed/repo/aluguel: papel e limpeza | TD-17, TD-18, TD-23 | restringir attach a missão/papel; liberar ordem de repo em queda; apagar forklift/handler na conclusão; corrigir reembolso do aluguel | G, J | — | MÉD | cenários de queda e de abuso |
| W3-03 | Spawn point e trailer | TD-19 | `IsSpawnPointClear` não apaga veículos de terceiros (só os do próprio job); validar posição do trailer no servidor | H | — | MÉD | spawn com carro de terceiro no ponto |
| W3-04 | Contratos | TD-15, TD-24 | UPDATE no cancelamento LC; rate limit em `Negotiate`; prova de carga | G | — | MÉD | cancelar contrato → banco consistente |
| W3-05 | Party/convoy | TD-13 (jobs públicos) | `Kick` libera convoy; atribuir jobs corretamente | H | W2-03 | MÉD | kick durante convoy |
| W3-06 | Indústria e reabastecimento | TD-16 | definir produção/consumo; caminho de aceite do resupply | I | — | MÉD | resupply completo |
| W3-07 | Parcel | `05_…` | cancelar no servidor em recusa; cooldown no start | G | — | BAIXO | recusa libera estado |
| W3-08 | Export de petróleo | TD-24 | validar `qty/price` no servidor; retorno de barris no stop | I | — | MÉD | valores forjados rejeitados |
| W3-09 | Registro de entidades | TD-20 (SEC-01) | `validateJobEntity`: provar que a entidade foi criada pelo servidor para este job; dois clientes não registram o mesmo carro | F | — | MÉD | **runtime:** 2 clientes, mesmo carro |

## Onda 4 — OneSync / rede (exige prova de runtime antes de decidir)

| ID | Título | Origem | Proposta | Risco | Aceite / prova |
|---|---|---|---|---|---|
| W4-01 | Orphan mode | TD-26 | testar o comportamento padrão; se necessário aplicar `SetEntityOrphanMode` por tipo de entidade | MÉD | queda do dono com pallet/trailer |
| W4-02 | Queda/reconexão | TD-27, TD-28, TD-31 | unificar os handlers de `playerDropped`; limpeza de entidades de cliente; retry de `WaitForNetworkEntity` | MÉD | queda, reconexão, streaming lento |
| W4-03 | Statebags escritas pelo cliente | TD-22 | mover a escrita para o servidor (`loadedSlots`, `forklift_owner`, flatbed) | MÉD | cliente adulterado não altera |
| W4-04 | Resource stop | TD-30 | limitar a varredura a entidades marcadas pelo recurso | MÉD | restart com 2 jogadores |

## Onda 5 — Admin e desempenho

| ID | Título | Origem | Proposta |
|---|---|---|---|
| W5-01 | Log de auditoria admin | TD-41 | registrar eventos de admin (ref. H `guarded()`) |
| W5-02 | Join tardio de offsets | TD-41 | enviar offsets no join |
| W5-03 | Hotspots top 15 (`13_…` §4) | TD-32..36 | começar pelos 3 maiores (escudo Havok, cintas, HUD); medir com `resmon` antes/depois |
| W5-04 | Leaderboard e cache de offsets | TD-08, TD-09 | corrigir tabela; usar cache |

## Onda 6 — Consolidações (maior risco de dados; sempre com migração revisada)

| ID | Título | Origem |
|---|---|---|
| W6-01 | Decidir pilha de NUI (jQuery × React) | TD-07 |
| W6-02 | Ledger de empresa e limpeza na venda | TD-40 |
| W6-03 | Modelo único de frota | TD-37 |
| W6-04 | Fonte única de nível/progressão | TD-38 |
| W6-05 | Separar sistemas de NPC driver; atomizar reserva | TD-39 |

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

**Onda 0 + Onda 2 (W2-01…W2-03) + medição W1-01.** Razão: risco baixo, defeitos verificados por leitura, nenhuma mudança de física/rede/economia, e a telemetria (W1-01) é o dado que falta para decidir a Onda 1 com evidência. W1-02/W1-03 só quando houver autorização explícita.

## Itens de prova de runtime exigidos

W1-01, W1-03, W1-05, W2-01…W2-06, W3-01, W3-02, W3-03, W3-09, W4-01…W4-04, W5-03 (profiler).

## Dependências críticas

W1-03 → W1-02 e W1-01; W1-05 → W1-03; W3-01 → W3-09; W3-05 → W2-03; W7-* → ondas 1–5.
