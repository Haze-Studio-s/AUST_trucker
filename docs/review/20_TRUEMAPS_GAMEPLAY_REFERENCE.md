# 20 — Adendo: TrueMaps Advanced Trucker Job (referência de GAMEPLAY)

**BASE DOCUMENTAL:** commit `3a89631` (revisão V2 em `94f336b`). **ANALYZED HEAD (AUST): `c9d9187`** — código idêntico em `94f336b`. **Nenhum código foi alterado, copiado ou implementado.**

**REFERENCE M — TrueMaps / TRUE. — "[Fivem Script] Advanced Trucker Job | 12 Unique Jobs, Realistic Cargo [ESX/QBCore/QBOX]"**

| Campo | Valor |
|---|---|
| SOURCE TYPE | **VIDEO GAMEPLAY REFERENCE** |
| SOURCE | https://youtu.be/9hNLhOnFLL8 |
| DEVELOPER | TrueMaps / TRUE. |
| CLASSIFICATION | **GAMEPLAY REFERENCE** — **NOT** a source-code reference |
| SOURCE CODE REVIEWED | **NO** |

> **AVISO DE PROVENIÊNCIA (honestidade de fonte).** O vídeo **não pôde ser acessado por esta sessão** (`youtu.be` bloqueado pelo proxy de saída; tentativa registrada). Tudo marcado como **VIDEO OBSERVED** abaixo vem da **descrição fornecida na brief da missão** como "observado no vídeo"; **não foi verificado de forma independente por mim**. J2 deve conferir cada item no vídeo antes de aprová-lo para o roadmap.

## 0. Etiquetas de confiança (nunca misturar as três)

| Tag | Significado |
|---|---|
| **[VIDEO OBSERVED]** | gameplay descrito como observável no vídeo (conforme a brief; não verificado por mim) |
| **[SECONDARY REPORT]** | informação relatada externamente (título do produto, comentários), não observada |
| **[AUST DESIGN PROPOSAL]** | ideia de desenho do AUST: **não** é afirmação sobre o TrueMaps |

## 1. O que é DESCONHECIDO sobre o TrueMaps (não inferir)

| Aspecto | Status |
|---|---|
| IMPLEMENTATION DETAILS | **UNKNOWN** |
| SERVER AUTHORITY | **UNKNOWN** |
| SECURITY | **UNKNOWN** |
| ONESYNC | **UNKNOWN** |
| DATABASE DESIGN | **UNKNOWN** |
| PERFORMANCE | **UNKNOWN** |
| MAINTAINABILITY | **UNKNOWN** |
| Licença / código | **UNKNOWN** (não houve acesso ao código; tratar como proprietário; **IDEA ONLY — INDEPENDENT REIMPLEMENTATION**, sem copiar código nem UI) |

Não há neste documento nenhum SQL, evento, callback, função, esquema ou desenho de rede atribuído ao TrueMaps.

## 2. Avaliação (somente critérios de gameplay)

Nota 1–10 **por observação reportada**; confiança **BAIXA/MÉDIA** (fonte secundária, sem verificação).

| Critério | Nota | Base | Tag |
|---|---|---|---|
| GAMEPLAY | 9 | tarefas físicas distintas por tipo de frete | VIDEO OBSERVED |
| JOB VARIETY | 9 | "12 Unique Jobs" no título; courier, carga especial, escolta | SECONDARY REPORT (título) + VIDEO OBSERVED (tipos citados) |
| HEAVY RP VALUE | 9 | preparar o veículo, docar, carregar à mão, escoltar | VIDEO OBSERVED |
| PHYSICAL INTERACTION | 9 | portas, plataforma hidráulica, pallet jack, scanner | VIDEO OBSERVED |
| COOP VALUE | 8 | escolta aparentemente ativa (conforme a brief) | VIDEO OBSERVED ("aparentemente") |
| AUST RELEVANCE | 8 | complementa o AUST onde ele é mais fraco (profundidade física/courier/escolta); não fornece arquitetura | AUST DESIGN PROPOSAL (julgamento) |

## 3. Loop de gameplay observado

```
JOB SELECTION
  ↓
VEHICLE / CARGO PREPARATION
  ↓
DOCKING
  ↓
PHYSICAL LOADING
  ↓
TRANSPORT
  ↓
CARGO RISK
  ↓
SPECIAL JOB MECHANICS
  ↓
PRECISION DELIVERY
  ↓
REWARD / XP / COMPANY ECONOMY
```
**[VIDEO OBSERVED]** (sequência conforme a brief).

**Diferença central:** o job genérico é `PICK TRAILER → DRIVE A TO B → PAYMENT`. **[VIDEO OBSERVED]** no TrueMaps o gameplay cria **tarefas físicas diferentes conforme o tipo de frete**. **[AUST DESIGN PROPOSAL]** usar isso como régua de profundidade: o AUST hoje é forte em economia/indústria e fraco nas etapas "preparação física" e "interação de carga" fora de forklift/reach stacker (docs 05 e 07).

## 4. Carregamento físico em doca

**Fluxo [VIDEO OBSERVED]:**

```
dar ré até a doca de carregamento → sair do veículo → interagir com a área traseira de carga
→ abrir as portas traseiras → operar a plataforma/rampa hidráulica (liftgate)
→ usar o pallet jack → engatar o pallet → mover a carga → carregar dentro do caminhão
```

Elementos distintos: **PALLET JACK · HYDRAULIC LIFTGATE · CARGO DOOR STATE · DOCKING.**

**[AUST DESIGN PROPOSAL] — valor para Heavy RP:** o motorista precisa **preparar fisicamente o veículo antes de carregar** (portas, plataforma, posição de doca), em vez de a carga "aparecer" no trailer.

## 5. Pallet Jack e modos de manuseio

| Modo | Uso | Estado no AUST (fato) | Tag |
|---|---|---|---|
| **Forklift** | pallets pesados | existe: `client/modules/forklift.lua` (Polarix) e `client/forklift.client.lua` (trade point); estudo de física nos docs 07/10 | fato do AUST |
| **Reach Stacker** | contêineres | existe: `client/modules/reach_stacker.lua`; `container_handler` | fato do AUST |
| **Pallet Jack** | armazém / van / box truck / carga curta | **não existe** | **[VIDEO OBSERVED]** que o TrueMaps usa pallet jack; **[AUST DESIGN PROPOSAL]** posicioná-lo como terceiro modo |

**[AUST DESIGN PROPOSAL]:** `FORKLIFT = heavy pallet handling` · `PALLET JACK = warehouse / van / box truck / short-distance cargo handling` · `REACH STACKER = containers`. **Sem proposta de implementação imediata** → item de estudo **GPLAY-01**.

## 6. Cargo Access System (conceito)

**[AUST DESIGN PROPOSAL]** — estados possíveis (rótulos de discussão, **sem implementação definida**):

`DOORS_CLOSED` · `DOORS_OPEN` · `LIFTGATE_UP` · `LIFTGATE_DOWN` · `LOADING_ALLOWED` · `LOADING_COMPLETE`

Perguntas em aberto estão em **GPLAY-02** (§15.2). Nada aqui descreve como o TrueMaps modela estado de porta (**UNKNOWN**).

## 7. Gameplay de courier

**Fluxo [VIDEO OBSERVED] (um dos pontos mais fortes da brief):**

```
VAN / DELIVERY VEHICLE → VÁRIOS PACOTES → ENDEREÇO DE ENTREGA ATUAL → PROCURAR NA CARGA
→ ESCANEAR A ETIQUETA DO PACOTE → IDENTIFICAR O PACOTE CORRETO → CARREGAR → ENTREGAR AO DESTINATÁRIO
```

**Estado do AUST (fato):** o fluxo de parcel atual é depósito NPC → missão de parcel → coleta (barra de progresso, `CarrySystem` do **cliente**) → paradas sequenciais → depósito; o servidor valida cooldown, nível e posição (≤ 15 m) por parada (doc 05 §6). **Não há identidade de pacote nem scanner.**

**[AUST DESIGN PROPOSAL] — PARCEL IDENTIFICATION SYSTEM:** possíveis dados lógicos (**proposta de modelagem, não prova de como o TrueMaps implementa**): `parcelId` · `barcode` · `routeStop` · `recipient` · `address` · `priority` · `fragile` · `signatureRequired`. Requisito: o **servidor** decide qual pacote pertence a qual parada; o cliente só apresenta/interage → **GPLAY-03**.

## 8. Integridade da carga

**[VIDEO OBSERVED]:** colisões, direção agressiva e raspagem podem afetar a condição da carga. **Curvas bruscas:** a brief diz "possivelmente" → **não confirmado** (tratar como hipótese).

**Estado do AUST (fato):** a integridade é **reportada pelo cliente** na telemetria da simulação e **consumida pelo servidor**: `server/services/truck_simulation_service.lua:103-108` aceita `payload.integrity`, faz clamp 0..100 e só deixa **diminuir**; `job_service.lua:434` usa `GetLastIntegrity`. Ou seja, um cliente modificado pode simplesmente **nunca reportar queda** (CLIENT-SOURCED / SERVER-CONSUMED; efeito **RUNTIME PROOF REQUIRED**).

**[AUST DESIGN PROPOSAL] — conceito (não é a fórmula do TrueMaps, que é UNKNOWN):**

`CARGO DAMAGE = impact severity + cargo sensitivity + secure state + vehicle dynamics`

Sensibilidade por classe:

| Classe | Exemplos |
|---|---|
| LOW | aço / industrial |
| MEDIUM | carga geral |
| HIGH | eletrônicos, vidro, frágeis |
| SPECIAL | líquido, hazmat |

→ **GPLAY-04** (não confiar em número de dano arbitrário do cliente).

## 9. Carga sobredimensionada (oversized)

**[VIDEO OBSERVED]:** carga oversized **muda a condução fisicamente**. Fatores citados na brief como observáveis: largura, altura, raio de curva, folga de túnel, folga de ponte, obstrução de via.

**[AUST DESIGN PROPOSAL] — SPECIAL TRANSPORT ROUTE VALIDATION (não implementar):** checagens possíveis: dimensões do veículo, restrições de rota, túneis, pontes, curvas fechadas, obstáculos na via. **Como** o TrueMaps valida isso é **UNKNOWN**. → **GPLAY-07**.

## 10. Escolta ativa

Contraste (apenas descritivo):

| Recurso | Escolta no XS-Trucking (código lido) | Escolta no TrueMaps |
|---|---|---|
| Natureza | presença/distância/suporte de convoy + bônus (`08b` §9) | **[VIDEO OBSERVED]** (brief: "aparentemente") tarefas **ativas** |

**Fluxo [VIDEO OBSERVED]:** `PILOT VEHICLE → SCOUT ROUTE → IDENTIFY OBSTRUCTION → INTERACT WITH ROAD OBSTACLE → CLEAR PATH → HEAVY TRANSPORT PASSES`.

**[AUST DESIGN PROPOSAL] — ACTIVE ESCORT ROLE:** tarefas futuras possíveis: controle de tráfego · fechamento de via · reconhecimento de rota · remoção de obstáculo · controle de cruzamento · sinalizador de alerta · sinalização temporária · espaçamento do comboio · verificação de folga. **HIGH GAMEPLAY VALUE.** Estado do AUST: há papel `escort` mencionado em `client/convoy.client.lua:180` (escopo não auditado em profundidade). → **GPLAY-06**.

## 11. Estacionamento de precisão → DOCKING QUALITY SYSTEM

- **XS (código lido):** `dockScore` (distância 2D + diferença de heading do trailer ao ponto, no servidor) — `08b` §9.
- **TrueMaps [VIDEO OBSERVED]:** gameplay de precisão de estacionamento/alinhamento (como mecânica de entrega).
- **[AUST DESIGN PROPOSAL] — unificação conceitual:** métricas possíveis: erro de posição · erro de heading · alinhamento de ré · alinhamento do trailer · velocidade final. Saída: **DOCK SCORE 0–100**.

| Faixa (**proposta do AUST; não do TrueMaps**) | Classe |
|---|---|
| < 50 | Poor |
| 50–69 | Acceptable |
| 70–84 | Good |
| 85–94 | Excellent |
| 95+ | Dock Master |

→ **GPLAY-05**.

## 12. Economia de empresa

**[SECONDARY REPORT]:** a empresa recebe uma parcela das entregas dos funcionários (a brief cita 10%; **o percentual não é copiado**).

Conceito: `ENTREGA DO FUNCIONÁRIO → PAGAMENTO DO MOTORISTA + RECEITA DA EMPRESA (revenue share)`.

**[AUST DESIGN PROPOSAL]:** o AUST pode ter um sistema mais rico (rank, corte do motorista, corte da empresa, propriedade de veículo, contrato, perks, reputação da empresa); percentual **configurável por rank**. **Conclusão: IDEA VALIDATED — EXACT ECONOMY NOT TO COPY.**

## 13. Comparação por especialidade (resumo; matriz completa em `09_COMPARATIVE_MATRIX.md`)

| Referência | BEST FOR |
|---|---|
| **XS-Trucking** (código lido) | arquitetura, business, carreira, estrutura co-op, bridges, admin, ferramentas estáticas |
| **Polarix** (código lido, MIT) | representação forklift/pallet, estado lógico de carga no servidor, *representation swap* |
| **TrueMaps** (**só gameplay**) | gameplay físico, interação de carga, variedade de jobs, courier, escolta ativa, docking de precisão, transporte oversized |
| **AUST** | alvo de integração, economia de indústria, ADR, petróleo, repo, manuseio de contêiner, car carrier, logística NPC, PropEditor, endurecimento de autoridade do servidor |

> **O AUST NÃO deve copiar um único recurso de trucking.** Usar referências **por domínio**. **TARGET DESIGN (proposta):** XS → arquitetura · Polarix → arquitetura de manuseio de pallet · TrueMaps → profundidade de gameplay · AUST → sistema integrado canônico.

## 14. Backlog de ESTUDO de gameplay (GPLAY) — nada será implementado

| ID | Título | Prioridade | Estado |
|---|---|---|---|
| GPLAY-01 | Pallet Jack | ALTA | STUDY ONLY |
| GPLAY-02 | Hydraulic Liftgate / Cargo Doors | ALTA | STUDY ONLY |
| GPLAY-03 | Courier Package Scanner | ALTA | STUDY ONLY |
| GPLAY-04 | Cargo Integrity | ALTA | STUDY ONLY |
| GPLAY-05 | Precision Docking | ALTA | STUDY ONLY |
| GPLAY-06 | Active Escort Gameplay | ALTA | STUDY ONLY |
| GPLAY-07 | Oversized Route Restrictions | MÉDIA | STUDY ONLY |
| GPLAY-08 | Road Obstacle Interaction | MÉDIA | STUDY ONLY |
| GPLAY-09 | Special Transport Convoy | MÉDIA | STUDY ONLY |

Todos: **J2 APPROVAL REQUIRED: YES · CODE CHANGE: NO.** Decisão por item: **APPROVE / DEFER / REJECT**.

## 15. Detalhamento dos itens de estudo

### 15.1 GPLAY-01 — Pallet Jack

**STUDY:** modelo de interação · claim de pallet · colisão · movimento · animação do jogador · autoridade de rede · propriedade (ownership) · zonas de carregamento · baia de carga do caminhão · observador multiplayer. **Comparar com** forklift e reach stacker.

**Pergunta para J2 (sem decisão automática):** o pallet jack deveria usar **A)** pallet físico em rede · **B)** *assisted attach* · **C)** *representation swap* · **D)** híbrido? (Ver as famílias de modelo em `10_PALLET_ARCHITECTURE_OPTIONS.md`.)

### 15.2 GPLAY-02 — Cargo Access

**STUDY:** portas traseiras · liftgate · rampas · acesso à carga do veículo · permissão de carregamento. **Perguntas:** abrir a porta afeta o estado da carga? pode-se carregar com a porta fechada? quem é dono do estado do liftgate? o estado deve replicar? o que acontece na desconexão? (relacionar com `06_ENTITY_LIFECYCLE_MAP.md` e `11_ONESYNC_NETWORK_REVIEW.md`).

### 15.3 GPLAY-03 — Courier Scanner

**STUDY:** identidade do pacote · parada da rota · código de barras · prop de scanner · pacote errado/correto · assinatura · destinatário. **Requisito:** o **SERVIDOR** decide qual pacote pertence a qual parada; o cliente só apresenta/interage. Ponto de partida do AUST: `server/services/parcel_service.lua` e `client/parcel_delivery.lua` (doc 05 §6).

### 15.4 GPLAY-04 — Cargo Integrity

**STUDY:** impacto · velocidade · velocidade angular · tipo de carga · acúmulo de dano. **Requisito:** **não confiar em número de dano arbitrário do cliente**; precisa de desenho **server-authoritative** ou telemetria validada. **RUNTIME PROOF REQUIRED.** Ponto de partida do AUST: `truck_simulation_service.lua:103-108` (integridade reportada pelo cliente, só decresce) e a política **W3-10**.

### 15.5 GPLAY-05 — Precision Docking

**STUDY:** o `dockScore` do XS como referência técnica; comparar com o gameplay do TrueMaps. **Preferência (proposta):** calcular **no servidor** quando possível — posição e heading do trailer × posição e heading do alvo. **Saída:** score · bônus · XP · rating. Relaciona-se com **W3-01** (prova de entrega por entidade).

### 15.6 GPLAY-06 — Active Escort

**Objetivo:** transformar a escolta de "ficar no alcance" em **função ativa**. **STUDY:** pilot car · luzes de alerta · scout de rota · interação com obstáculo · controle temporário de via · suporte ao comboio. **Potencial de Heavy RP: VERY HIGH.**

### 15.7 GPLAY-07 / 08 / 09 (prioridade média)

| ID | Escopo de estudo |
|---|---|
| GPLAY-07 | restrições de rota para oversized: dimensões do veículo, túneis, pontes, curvas, obstruções (validação por dados de mapa — fonte **UNKNOWN**) |
| GPLAY-08 | interação com obstáculo de via (criar/remover obstáculo; quem pode; ciclo de vida; limpeza na desconexão) |
| GPLAY-09 | comboio de transporte especial (carga oversized + escolta ativa + pilot car); depende de GPLAY-06/07 e do convoy atual (`convoy_service`) |

## 16. Ecossistema de dispositivos (sem criar outra UI isolada)

Relacionar com `19_AUST_DEVICE_ECOSYSTEM_INTEGRATION.md` (**PHONE ≠ TABLET ≠ NEXUSOS**; fontes dos três resources **não lidas**; **ARCHITECTURE PENDING SOURCE REVIEW**). **[AUST DESIGN PROPOSAL]**:

| Funcionalidade | Dispositivo proposto |
|---|---|
| Courier scanner | **TABLET** / interface operacional portátil |
| Manifesto de carga | **TABLET** |
| Planejamento da empresa | **NEXUSOS** |
| Atribuição de escolta | **NEXUSOS / TABLET** |
| Alerta de escolta | **PHONE** |
| **Route Builder** | **ADMIN ONLY** |

## 17. Route Builder

**ROUTE BUILDER = ADMIN ONLY. Jogador comum = SEM ACESSO.** Não confundir **planejamento de rota como gameplay** (ex.: escolta que faz o reconhecimento de rota, ou o motorista que consulta o manifesto) com **ferramenta administrativa de autoria de rotas** (builder). São coisas diferentes: nenhuma feature GPLAY dá a jogadores acesso ao builder.

## 18. Perguntas para J2

1. Quais GPLAY entram no roadmap do AUST? (APPROVE / DEFER / REJECT por ID.)
2. Pallet Jack: A, B, C ou D? (GPLAY-01.)
3. Verificar no vídeo os itens **VIDEO OBSERVED** deste documento (a sessão não teve acesso ao vídeo).
4. GPLAY-04: aceitar que a integridade atual (cliente → servidor, só decresce) é transitória?

## 19. Legal

TrueMaps: sem acesso a código; **nenhum código, UI, asset ou texto foi copiado**. **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.** Itens de estudo não implicam implementação.
