# 16 — J2 Review Package (índice e resumo executivo)

**ANALYZED HEAD: `c9d9187`** (main `e5ce6cc` + PR #9; **revisão V2** sobre a base documental `3a89631`, código idêntico). **CODE CHANGED: NO. IMPLEMENTATION PERFORMED: NO** neste pacote (somente `docs/review/`). O PR #9 anterior contém código **atrás de flag desligada** (`KinematicLift.Enabled=false`); ele não faz parte desta missão e não deve ser mesclado sem decisão de J2.

## 1. Índice

| Doc | Conteúdo |
|---|---|
| 00 | Estado atual, git, PRs, deriva de versão |
| 01 | Inventário de recursos (arquivo a arquivo) |
| 02 | Arquitetura em camadas, autoridade, monólitos |
| 03 | Mapa de donos por módulo (37 domínios) |
| 04 | Grafo de eventos/callbacks |
| 05 | 19 fluxos de gameplay e defeitos verificados |
| 06 | Ciclo de vida das entidades |
| 07 | Forklift/pallet: reconstrução dos commits e física |
| 08 | 13 referências (12 de código + **M TrueMaps: só gameplay/vídeo**), licenças, scorecard |
| 08b | **XS-Trucking V2**: leitura completa (server/client/bridge/NUI/tools), autoridade híbrida, bridges, NUI/RPC, builder admin-only, tooling A–H, errata da v1 |
| 09 | Matriz comparativa por domínio |
| 10 | Opções de arquitetura de pallet (A, B, C, D-H, D-K) |
| 11 | Revisão OneSync/rede |
| 12 | Segurança/autoridade (P0 0, P1 8, P2 14, P3 12) |
| 13 | Desempenho (top 15 hotspots) |
| 14 | Registro de dívida técnica (P1 9, P2 31, P3 11; V2 adicionou TD-42…TD-45) |
| 15 | Plano de implementação (**49 PLAN IDs** + **9 GPLAY (estudo)**, ondas 0–8 + *Gameplay Study Wave*; W0-04 com sub-tarefas A–H) |
| 17 | Checklist de revisão por PLAN ID |
| 18 | Resumo executivo |
| **20** | **Adendo TrueMaps Advanced Trucker Job** — referência de **GAMEPLAY** (vídeo/brief, **sem código**); loop físico, courier, integridade, oversized, escolta ativa, docking; backlog **GPLAY-01…09** |
| **19** | **AUST × ecossistema de dispositivos** (NexusOS · vp_tablet · vp_phone) — **ARCHITECTURE PENDING SOURCE REVIEW**; Route Builder = ADMIN ONLY |

## 2. Resumo

O AUST tem controles de servidor sólidos em dinheiro (claim-before-pay, locks, rollback) e recursos que as referências não têm (PropEditor, ADR com exame no servidor, party com segurança de senha). Fraquezas: três sistemas de job paralelos sem registro comum, prova de entrega fraca (ped + tempo), muita confiança em estado escrito pelo cliente, e física de forklift dependente da janela Havok 0 → 0,35 m. Nenhuma falha P0 foi achada.

## 3. Top 10 achados

1. Prova de entrega = ped perto + tempo (SEC-02, TD-21).
2. Três sistemas de job sem registro comum (TD-02).
3. `validateJobEntity` aceita e marca como verificada qualquer entidade (TD-20).
4. Statebags replicadas escritas pelo cliente (TD-22).
5. `IsSpawnPointClear` apaga veículos vazios (TD-19).
6. `SetInterval` do convoy com argumentos na ordem errada (TD-13).
7. `StartDeliveryRoute` com escopo quebrado e espera por `VP_Trucker` indefinido (TD-10/12).
8. Janela física Havok no forklift; o 0,35 m não tem origem rastreada (07, TD-06).
9. Handlers `playerDropped` conflitantes e entidades de cliente sem limpeza (TD-27/28).
10. Licença: AUST deriva do Polarix (MIT) sem LICENSE/NOTICE (LEGAL-01).

## 4. Top propostas

W1-01 (telemetria) → W1-03 (Modelo D-K, rede opção A) → W3-01/W3-09 (prova de entrega e registro) → W2-01…W2-03 (correções baratas) → W4-01/W4-02 (rede) → W0-01 (legal).

## 5. Melhores referências

| Tema | Melhor | Observação |
|---|---|---|
| Geral | XS-Trucking (estrutura) | **ALL RIGHTS RESERVED → IDEA ONLY — INDEPENDENT REIMPLEMENTATION**; autoridade majoritária, **não** 100% |
| Integration bridges | XS-Trucking | autodetecção + API canônica + fallback |
| Ferramentas estáticas FiveM | XS-Trucking | 9 verificadores **locais** (não rodam em CI do XS) |
| Arquitetura de UI | XS-Trucking (modularidade/RPC) | **não** replicar o laptop; alvo = NexusOS/vp_tablet/vp_phone |
| Admin / Route Builder | XS Builder + PropEditor do AUST | **ADMIN ONLY** |
| Forklift | Polarix | MIT; frozen + prop novo anexado |
| OneSync | XS-Trucking + Don (blending) | Don é GPL-3.0: só ideias |
| Core trucking | XS-Trucking/ls_trucking | idem |

## 6. Primeira onda e perguntas abertas

**Primeira onda:** Onda 0 (começando por W0-04A–C, verificadores estáticos) + W2-01…W2-03 + W1-01; **STUDY-DEVICE-01** em paralelo (somente leitura, após autorização) (ver `15_…`).

**Perguntas para J2:**
1. Autoriza editar `fxmanifest.lua` (1 linha) e `client/modules/forklift.lua`, ou prefere receber o diff? (W1-02/W1-03)
2. Qual licença para o AUST? (W0-01)
3. Qual pilha de NUI é a oficial? (W6-01)
4. O "0,35 m" tem origem conhecida por J2? (W1-04)
5. Rede opção A (entidade única) ou B (props locais, como o Polarix)? (10)
6. Orphan mode: aceita decidir após teste? (W4-01)

## 7. Testes de runtime necessários

Ver `11_…` §5, `15_…` ("Itens de prova de runtime") e `13_…` §5. **Nada foi testado em jogo**; apenas sintaxe e testes de lógica pura (lupa/Lua 5.4: 77 + 59 casos no PR #9).

## 8. Decisões necessárias

Aprovar/rejeitar cada PLAN ID em `17_J2_REVIEW_CHECKLIST.md` (opções: APPROVE · APPROVE WITH CHANGES · REJECT · DEFER · NEEDS RUNTIME PROOF · NEEDS MORE ANALYSIS) e responder às decisões de arquitetura abaixo.

**Decisões da revisão V2 (dispositivos e Route Builder):**

| # | Decisão | Observação |
|---|---|---|
| 1 | O AUST deve usar o **NexusOS** como interface principal de **gestão**? | proposta de UX (doc 19 §3.1); depende de STUDY-DEVICE-01 |
| 2 | O **tablet** (vp_tablet) deve ser a interface **operacional** do motorista? | proposta (doc 19 §3.2) |
| 3 | O **phone** (vp_phone) fica restrito a **notificação/ação rápida**? | proposta (doc 19 §3.3) |
| 4 | A NUI **standalone** do AUST continua **apenas como fallback**? | hoje é a interface (`client/main.lua:418-440`) |
| 5 | **Route Builder = ADMIN ONLY**? | **Resposta esperada: YES — ADMIN ONLY.** É **requisito do projeto**, não descoberta técnica (no XS o builder já é admin-only em 3 camadas) |
| 6 | Aprovar **STUDY-DEVICE-01**? | estudo, sem código; inclui acesso de leitura a `nexus_os`, `vp_tablet`, `vp_phone` |
| 7 | Aprovar o desenho conceitual **W6-06** após o estudo dos três resources? | não implementar antes |

**Lembrete de gate:** `PHONE ≠ TABLET ≠ NEXUSOS`; nenhum dispositivo decide payout, permissão ou conclusão de entrega (decisões só no servidor do AUST).

## 9. Limites do pacote

Arquivos de corpo não lidos estão listados em `01_…`/`13_…` §5. Subagentes Explore foram usados no lugar do OmniRoute (indisponível). Comparação com `vinicius3232/aust_trucker` **não** foi feita (bloqueada).

## 10. Revisão V2 — o que mudou no estudo do XS-Trucking

- **Leitura completa** de server (11/11), client (6/6), bridge (6/6), NUI (18/18) e tools (10/10); só o cache de natives e as bibliotecas/imagens vendorizadas ficaram parciais/não lidos (`08b` §1).
- **Correções da v1:** os verificadores do XS são **locais** (não CI); são **9**, não 10; XS é **autoridade híbrida** (hitch, combustível e hora vêm do cliente); o Builder é **admin-only** e separado do laptop (`08b` §2).
- **Contribuições mais transferíveis (ideias):** 1) arquitetura de job no servidor; 2) abstração de bridges; 3) gameplay de empresa/frota/co-op; 4) ferramentas de admin; 5) verificadores estáticos FiveM; 6) NUI modular com contrato RPC.
- **O XS não resolve forklift/pallet.**
- **Não reproduzir o laptop:** o AUST já tem um ecossistema de dispositivos (doc 19).
- **Novos PLAN IDs:** STUDY-DEVICE-01, W3-10, W4-05, W5-06, W6-06, W6-07, W6-08 + sub-tarefas W0-04A–H.

## 11. OPEN SOURCE GAPS

| Lacuna | Efeito |
|---|---|
| Fontes de `nexus_os`, `vp_tablet`, `vp_phone` **não lidas** | doc 19 é **ARCHITECTURE PENDING SOURCE REVIEW**; nenhuma API foi citada |
| Nenhum teste em jogo; nenhum checker do XS executado | toda afirmação de runtime é RUNTIME_UNVERIFIED |
| Versões de ox_lib/oxmysql do servidor não consultadas | afeta XR-15 e semântica de `await` |
| Comparação com `vinicius3232/aust_trucker` bloqueada | fora desta missão |

## 12. NOVA REFERÊNCIA DE GAMEPLAY — TrueMaps Advanced Trucker Job (vídeo)

**NEW GAMEPLAY REFERENCE: TrueMaps Advanced Trucker Job video** (https://youtu.be/9hNLhOnFLL8). **Não há código** nesta referência: é **GAMEPLAY DESIGN REFERENCE ONLY**; implementação, autoridade de servidor, segurança, OneSync, banco e desempenho são **UNKNOWN**. A sessão **não conseguiu acessar o vídeo**; o conteúdo "observado" vem da brief e **precisa ser conferido por J2**. Detalhes: `20_TRUEMAPS_GAMEPLAY_REFERENCE.md`.

**Ideias mais fortes (todas [AUST DESIGN PROPOSAL] sobre gameplay reportado):**

1. carregamento físico em doca;
2. pallet jack (GPLAY-01);
3. liftgate / portas de carga (GPLAY-02);
4. scanner de courier (GPLAY-03);
5. integridade de carga (GPLAY-04);
6. escolta ativa (GPLAY-06);
7. rotas de carga oversized (GPLAY-07);
8. docking de precisão (GPLAY-05).

**Pergunta para J2: quais destes devem entrar no roadmap do AUST?** — **APPROVE / DEFER / REJECT por GPLAY ID** (`17_J2_REVIEW_CHECKLIST.md`). Perguntas adicionais: Pallet Jack deve usar **A** pallet físico em rede, **B** assisted attach, **C** representation swap ou **D** híbrido? (sem decisão automática). **Route Builder permanece ADMIN ONLY.**
