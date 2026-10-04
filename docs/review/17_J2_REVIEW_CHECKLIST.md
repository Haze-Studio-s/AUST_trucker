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
| W0-04 | Verificadores estáticos FiveM (pai; sub-tarefas A–H abaixo) — **IDEA ONLY** | não | — | ☐ | |
| ↳ W0-04A | Manifest ↔ disco (+ HTML/`files{}`/glob) — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04B | Eventos/callbacks — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04C | Contrato NUI/RPC — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04D | Validade de natives — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04E | Guarda de netId no cliente — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04F | Compatibilidade de lado (`os`/`io`) — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04G | Multi-retorno Lua — **IDEA ONLY** | não | W0-04 | ☐ | |
| ↳ W0-04H | Sintaxe JS — **IDEA ONLY** | não | W0-04 | ☐ | |
| **STUDY-DEVICE-01** | Auditar NexusOS / vp_tablet / vp_phone (somente leitura) | — (estudo) | autorização de acesso | ☐ | |
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
| W3-10 | Política de entradas do cliente consumidas pelo servidor — **IDEA ONLY** | não | W3-01 | ☐ | |
| W4-01 | Orphan mode | sim | — | ☐ | |
| W4-02 | Queda/reconexão | sim | — | ☐ | |
| W4-03 | Statebags de cliente | sim | — | ☐ | |
| W4-04 | Resource stop | sim | — | ☐ | |
| W4-05 | Helper de controle de rede limitado e confirmado — **IDEA ONLY** | sim | — | ☐ | |
| W5-01 | Auditoria admin | não | — | ☐ | |
| W5-02 | Join tardio de offsets | não | — | ☐ | |
| W5-03 | Hotspots | sim (profiler) | — | ☐ | |
| W5-04 | Leaderboard/cache | não | — | ☐ | |
| W5-05 | Settings ao vivo (opcional) | não | — | ☐ | |
| W5-06 | Validação de posicionamento admin (estudo) — **IDEA ONLY**; **ADMIN ONLY** | não | — | ☐ | |
| W6-01 | Pilha de NUI | não | — | ☐ | |
| W6-02 | Ledger de empresa | não | — | ☐ | |
| W6-03 | Modelo único de frota | sim | — | ☐ | |
| W6-04 | Progressão única | não | — | ☐ | |
| W6-05 | NPC driver | sim | — | ☐ | |
| W6-06 | Integração unificada de dispositivos (NexusOS/tablet/phone; **Route Builder ADMIN ONLY**) | sim | **STUDY-DEVICE-01** | ☐ | |
| W6-07 | Camada de integration bridges — **IDEA ONLY** | sim | — | ☐ | |
| W6-08 | Padrão de NPCs de segurança no servidor (estudo) — **IDEA ONLY** | sim | — | ☐ | |
| W7-01 | Dividir monólitos | sim | ondas 1–5 | ☐ | |
| W7-02 | Registro único de job | sim | ondas 1–5 | ☐ | |
| W7-03 | Fusão dos forklifts | sim | W1-* | ☐ | |
| W8-01 | Remover órfãos provados | sim | — | ☐ | |
| GPLAY-01 | Pallet Jack — **STUDY ONLY** | sim (rede) | W1, W4-05 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-02 | Hydraulic Liftgate / Cargo Doors — **STUDY ONLY** | sim (rede) | W4-02 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-03 | Courier Package Scanner — **STUDY ONLY** | sim | W3-07 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-04 | Cargo Integrity — **STUDY ONLY** | **sim (RUNTIME PROOF REQUIRED)** | W3-10 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-05 | Precision Docking — **STUDY ONLY** | sim | W3-01 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-06 | Active Escort Gameplay — **STUDY ONLY** | sim | W3-05, W4-02 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-07 | Oversized Route Restrictions — **STUDY ONLY** | sim | GPLAY-06 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-08 | Road Obstacle Interaction — **STUDY ONLY** | sim | GPLAY-06 | ☐ APPROVE ☐ DEFER ☐ REJECT | |
| GPLAY-09 | Special Transport Convoy — **STUDY ONLY** | sim | GPLAY-06/07 | ☐ APPROVE ☐ DEFER ☐ REJECT | |

**Total: 49 PLAN IDs + 9 GPLAY (estudo)** (W0-04 tem 8 sub-tarefas decididas separadamente, linhas `↳`). Perguntas gerais de J2 estão em `16_J2_REVIEW_PACKAGE.md` §6 e as decisões da V2 (dispositivos/Route Builder) em §8.

## Checklists específicos (revisão V2)

### STUDY-DEVICE-01

- [ ] NexusOS source reviewed
- [ ] vp_tablet source reviewed
- [ ] vp_phone source reviewed
- [ ] acesso de leitura aos três repositórios autorizado por J2
- [ ] resultado entregue como **fatos** (arquivo/função), sem APIs inventadas
- [ ] nenhuma mudança de código

### W6-06 — Integração unificada de dispositivos

- [ ] NexusOS source reviewed
- [ ] vp_tablet source reviewed
- [ ] vp_phone source reviewed
- [ ] no business logic duplicated (regra só no servidor do AUST)
- [ ] server authority preserved (payout, permissão de job/contrato/empresa, frota, progressão e conclusão de entrega decididos no servidor)
- [ ] app permissions defined
- [ ] deep-link behavior defined
- [ ] resource unavailable fallback defined
- [ ] **Route Builder remains admin-only** (jogador comum = sem acesso; autorização de admin no servidor a cada operação)
- [ ] standalone fallback decision made
- [ ] no XS proprietary code copied (**IDEA ONLY — INDEPENDENT REIMPLEMENTATION**)
- [ ] **PHONE ≠ TABLET ≠ NEXUSOS** respeitado na matriz de responsabilidades (doc 19 §4)

### Itens derivados do XS (W0-04A–H, W3-10, W4-05, W5-06, W6-07, W6-08)

- [ ] a proposta parte do **comportamento descrito em `08b`**, não de arquivos do XS abertos ao lado (prática *clean-room*)
- [ ] nenhum trecho, estrutura de tabela ou texto do XS entra no AUST
- [ ] o AUST tem `DESCRICAO_VENDA.md`: confirmar a política de licenciamento (W0-01) antes de qualquer reimplementação

## Checklists dos itens GPLAY (STUDY ONLY; **CODE CHANGE: NO**; J2 APPROVAL REQUIRED: YES)

Cada item: marcar `[x]` ou anotar ao avaliar. Opções de decisão por item: **APPROVE / DEFER / REJECT**. Origem: referência de **gameplay** (narração do vídeo via transcrição + brief), **sem código**; itens **[BRIEF ONLY]** exigem conferência na imagem; **IDEA ONLY — INDEPENDENT REIMPLEMENTATION**. **Route Builder permanece ADMIN ONLY** (nenhum GPLAY o expõe a jogadores).

### GPLAY-01 — Pallet Jack

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Sobreposição conhecida: forklift (`client/modules/forklift.lua`, `forklift.client.lua`) e reach stacker. Decisão de modelo A/B/C/D pendente de J2. Licença: TrueMaps **sem código** (IDEA ONLY).

### GPLAY-02 — Hydraulic Liftgate / Cargo Doors

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Rampa narrada; **portas traseiras só na brief** (conferir na imagem). Estado de porta/liftgate novo; lifecycle e desconexão em aberto (docs 06/11). Dependência de rede.

### GPLAY-03 — Courier Package Scanner

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Sobreposição: parcel atual (`parcel_service`, `parcel_delivery`). **Servidor decide pacote × parada.** Dispositivo: TABLET.

### GPLAY-04 — Cargo Integrity

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Sobreposição: integridade reportada pelo cliente (`truck_simulation_service.lua:103-108`). **Não confiar em dano do cliente.** Vídeo narra colisão/dano → pagamento; direção agressiva/raspagem só na brief. RUNTIME PROOF REQUIRED.

### GPLAY-05 — Precision Docking

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Sobreposição: prova de entrega (W3-01). Cálculo no servidor sempre que possível. Referência técnica: dockScore do XS (**IDEA ONLY**).

### GPLAY-06 — Active Escort Gameplay

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Sobreposição: convoy/`escort` citado em `convoy.client.lua:180`. Escolta ativa **narrada** (garantir rota, ajudar a manobrar, remover obstáculos); Heavy RP VERY HIGH; ciclo de vida de entidades de escolta novo.

### GPLAY-07 — Oversized Route Restrictions

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Pontes e planejamento de rota narrados; túnel/raio só na brief; fonte de dados de mapa **UNKNOWN**.

### GPLAY-08 — Road Obstacle Interaction

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Obstáculos de via: ciclo de vida/limpeza na desconexão; risco de grief.

### GPLAY-09 — Special Transport Convoy

- [ ] gameplay value · [ ] Heavy RP value · [ ] overlaps existing AUST system? · [ ] needs new entity lifecycle? · [ ] needs DB? · [ ] needs server authority? · [ ] OneSync risk? · [ ] performance risk? · [ ] player count requirement? · [ ] device UI? · [ ] runtime proof? · [ ] source/license concern? · [ ] implementation approved?
- *Fatos para a revisão:* Depende de GPLAY-06/07 e do convoy atual.
