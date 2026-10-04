# 16 — J2 Review Package (índice e resumo executivo)

**ANALYZED HEAD: `c9d9187`** (main `e5ce6cc` + PR #9). **CODE CHANGED: NO. IMPLEMENTATION PERFORMED: NO** neste pacote (somente `docs/review/`). O PR #9 anterior contém código **atrás de flag desligada** (`KinematicLift.Enabled=false`); ele não faz parte desta missão e não deve ser mesclado sem decisão de J2.

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
| 08 | 12 referências externas, licenças, scorecard |
| 08b | XS-Trucking: aprofundamento (CI estático, docking, orphan mode, settings) |
| 09 | Matriz comparativa por domínio |
| 10 | Opções de arquitetura de pallet (A, B, C, D-H, D-K) |
| 11 | Revisão OneSync/rede |
| 12 | Segurança/autoridade (P0 0, P1 8, P2 14, P3 12) |
| 13 | Desempenho (top 15 hotspots) |
| 14 | Registro de dívida técnica (P1 9, P2 28, P3 10) |
| 15 | Plano de implementação (42 itens, ondas 0–8) |
| 17 | Checklist de revisão por PLAN ID |
| 18 | Resumo executivo |

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
| Geral | XS-Trucking (estrutura) | **all rights reserved: só ideias** |
| Forklift | Polarix | MIT; frozen + prop novo anexado |
| OneSync | XS-Trucking + Don (blending) | Don é GPL-3.0: só ideias |
| Core trucking | XS-Trucking/ls_trucking | idem |

## 6. Primeira onda e perguntas abertas

**Primeira onda:** Onda 0 (inclui W0-04, verificadores de CI) + W2-01…W2-03 + W1-01 (ver `15_…`).

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

Aprovar/rejeitar cada PLAN ID em `17_J2_REVIEW_CHECKLIST.md`.

## 9. Limites do pacote

Arquivos de corpo não lidos estão listados em `01_…`/`13_…` §5. Subagentes Explore foram usados no lugar do OmniRoute (indisponível). Comparação com `vinicius3232/aust_trucker` **não** foi feita (bloqueada).
