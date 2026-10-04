# 17 — J2 Review Checklist (por PLAN ID)

**ANALYZED HEAD: `c9d9187`.** Nada aqui foi implementado. Para **cada** PLAN ID de `15_IMPLEMENTATION_PLAN_FOR_J2.md`, J2 (ou a IA de J2) responde os 13 pontos abaixo e marca uma **DECISÃO**.

## Os 13 pontos

1. O problema existe no código atual? (cheque o arquivo:linha em `14_…`)
2. A evidência foi lida corretamente? (reproduza com grep)
3. A severidade está correta?
4. A referência citada realmente faz isso? (`08_…`)
5. A licença da referência permite? (só ideias, ou código com atribuição)
6. A proposta cabe em uma flag/rollback simples?
7. Há dependência de outro PLAN ID não aprovado?
8. O risco de física/rede/economia/DB está aceito?
9. O teste de aceite está claro?
10. A prova de runtime é viável? Quem executa?
11. Impacto em jogadores/servidor em produção?
12. Migração/DB envolvida? (requer revisão separada)
13. Escopo mínimo definido? (sem refactor oportunista)

**DECISÃO:** `APPROVE` · `APPROVE WITH CHANGES` · `REJECT` · `DEFER` · `NEEDS RUNTIME PROOF` · `NEEDS MORE ANALYSIS`

## Tabela

| PLAN ID | Título | Prova de runtime | Dep. | DECISÃO | Notas de J2 |
|---|---|---|---|---|---|
| W0-01 | LICENSE/NOTICE | não | — | ☐ | |
| W0-02 | Alinhar versão | não | — | ☐ | |
| W0-03 | Plano de testes runtime | — | — | ☐ | |
| W0-04 | Verificadores estáticos de CI | não | — | ☐ | |
| W1-01 | Telemetria do pallet | sim | W0-03 | ☐ | |
| W1-02 | Carregar `fork_lift.lua` | não | — | ☐ | |
| W1-03 | Patch cinemático cliente | sim | W1-01/02 | ☐ | |
| W1-04 | Limiar medido | sim | W1-01 | ☐ | |
| W1-05 | Flag em staging | sim | W1-03 | ☐ | |
| W2-01 | Car carrier netId | sim | — | ☐ | |
| W2-02 | `StartDeliveryRoute`/`VP_Trucker` | sim | — | ☐ | |
| W2-03 | `SetInterval` convoy | sim | — | ☐ | |
| W2-04 | Liquid/ADR | sim | W2-02 | ☐ | |
| W2-05 | Job ilegal | sim | — | ☐ | |
| W2-06 | Forklift de emergência | sim | — | ☐ | |
| W3-01 | Prova de entrega | sim | W3-09 | ☐ | |
| W3-02 | Flatbed/repo/aluguel | sim | — | ☐ | |
| W3-03 | Spawn point/trailer | sim | — | ☐ | |
| W3-04 | Contratos | sim | — | ☐ | |
| W3-05 | Party/convoy | sim | W2-03 | ☐ | |
| W3-06 | Indústria/resupply | sim | — | ☐ | |
| W3-07 | Parcel | não | — | ☐ | |
| W3-08 | Export de petróleo | não | — | ☐ | |
| W3-09 | Registro de entidades | sim | — | ☐ | |
| W4-01 | Orphan mode | sim | — | ☐ | |
| W4-02 | Queda/reconexão | sim | — | ☐ | |
| W4-03 | Statebags de cliente | sim | — | ☐ | |
| W4-04 | Resource stop | sim | — | ☐ | |
| W5-01 | Auditoria admin | não | — | ☐ | |
| W5-02 | Join tardio de offsets | não | — | ☐ | |
| W5-03 | Hotspots | sim (profiler) | — | ☐ | |
| W5-04 | Leaderboard/cache | não | — | ☐ | |
| W5-05 | Settings ao vivo (opcional) | não | — | ☐ | |
| W6-01 | Pilha de NUI | não | — | ☐ | |
| W6-02 | Ledger de empresa | não | — | ☐ | |
| W6-03 | Modelo único de frota | sim | — | ☐ | |
| W6-04 | Progressão única | não | — | ☐ | |
| W6-05 | NPC driver | sim | — | ☐ | |
| W7-01 | Dividir monólitos | sim | ondas 1–5 | ☐ | |
| W7-02 | Registro único de job | sim | ondas 1–5 | ☐ | |
| W7-03 | Fusão dos forklifts | sim | W1-* | ☐ | |
| W8-01 | Remover órfãos provados | sim | — | ☐ | |

**Total: 42 PLAN IDs.** Perguntas gerais de J2 estão em `16_J2_REVIEW_PACKAGE.md` §6.
