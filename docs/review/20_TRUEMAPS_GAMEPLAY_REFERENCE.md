# 20 — Adendo: TrueMaps Advanced Trucker Job (referência de GAMEPLAY) — REVISÃO COM TRANSCRIÇÃO

**BASE DOCUMENTAL:** commit `3a89631` (V2 em `94f336b`; adendo TrueMaps v1 em `b66d975`). **ANALYZED HEAD (AUST): `c9d9187`** — código idêntico nas revisões seguintes. **Nenhum código foi alterado, copiado ou implementado.**

**REFERENCE M — TrueMaps / TRUE. — "[Fivem Script] Advanced Trucker Job | 12 Unique Jobs, Realistic Cargo [ESX/QBCore/QBOX]"**

| Campo | Valor |
|---|---|
| SOURCE TYPE | **VIDEO GAMEPLAY REFERENCE** (showcase de 3:54) |
| SOURCE | https://youtu.be/9hNLhOnFLL8 |
| DEVELOPER | TrueMaps / TRUE. |
| CLASSIFICATION | **GAMEPLAY REFERENCE** — **NOT** a source-code reference |
| SOURCE CODE REVIEWED | **NO** |
| EVIDENCE USED | **transcrição da narração** (legenda automática em inglês do YouTube, fornecida pelo usuário; pode ter erros de reconhecimento; **não inclui o que aparece só na imagem**) + brief da missão |

> **PROVENIÊNCIA.** A sessão **não acessa o vídeo** (`youtu.be` bloqueado pelo proxy). A v1 deste adendo usava só a brief. Esta revisão **confronta cada item com a transcrição fornecida**. A narração é **marketing do desenvolvedor**: confirma que a mecânica **é apresentada**, não como é implementada. **O que depende de imagem (sem fala) continua não verificado.**

## 0. Etiquetas de confiança (nunca misturar)

| Tag | Significado |
|---|---|
| **[VIDEO OBSERVED — NARRATED]** | dito na narração (confirmado pela transcrição fornecida) |
| **[VIDEO OBSERVED — BRIEF ONLY]** | consta na brief como visto no vídeo, **mas não aparece na transcrição**; depende de imagem; **não verificado** |
| **[SECONDARY REPORT]** | informação externa (ex.: título/compatibilidade), não observada no conteúdo |
| **[AUST DESIGN PROPOSAL]** | ideia de desenho do AUST: **não** é afirmação sobre o TrueMaps |

## 1. O que é DESCONHECIDO (não inferir)

| Aspecto | Status |
|---|---|
| IMPLEMENTATION DETAILS | **UNKNOWN** |
| SERVER AUTHORITY | **UNKNOWN** |
| SECURITY | **UNKNOWN** |
| ONESYNC | **UNKNOWN** |
| DATABASE DESIGN | **UNKNOWN** |
| PERFORMANCE | **UNKNOWN** |
| MAINTAINABILITY | **UNKNOWN** |
| Licença / código | **UNKNOWN** (tratar como proprietário; **IDEA ONLY — INDEPENDENT REIMPLEMENTATION**, sem copiar código nem UI) |

Nenhum SQL, evento, callback, função, esquema ou desenho de rede é atribuído ao TrueMaps. A transcrição **não** informa nada disso.

## 2. Confirmação item a item (brief × transcrição)

Legenda de resultado: **CONFIRMADO** (na narração) · **PARCIAL** · **NÃO CONFIRMADO** (não aparece na transcrição; pode estar só na imagem) · **NOVO** (aparece na transcrição e não estava na brief).

| # | Item | Resultado | Trecho da transcrição | Tag |
|---|---|---|---|---|
| 1 | 12 tipos de job (de courier a oversized/especial) | **CONFIRMADO** | [0:08–0:16] "as many as 12 different job types, ranging from courier deliveries to oversized and special cargo transportation" | NARRATED |
| 2 | Carregar com **pallet jack** | **CONFIRMADO** | [0:16–0:24] "load cargo using a pallet jack" | NARRATED |
| 3 | **Rampa de carga do caminhão** (abrir, subir, baixar conforme a situação) | **CONFIRMADO** (como "loading ramp") | [0:40] "operate the truck's loading ramp, deploying it, raising it, and lowering it" | NARRATED |
| 4 | Liftgate **hidráulico** | **PARCIAL** — a narração diz "loading ramp"; a palavra "hydraulic" **não** aparece | — | NARRATED (rampa) / BRIEF ONLY ("hidráulico") |
| 5 | **Abrir portas traseiras**; sair do veículo; interagir com a área traseira | **NÃO CONFIRMADO** | não mencionado | BRIEF ONLY |
| 6 | Posicionar o caminhão no ponto de carga (veículo longo, correções constantes) | **CONFIRMADO** | [0:57–1:14] "position yourself perfectly at the loading point while controlling an extremely long vehicle" | NARRATED |
| 7 | Descarga: colocar a mercadoria no **local designado** | **NOVO / CONFIRMADO** | [0:32] "carefully place the goods in the correct designated location" | NARRATED |
| 8 | **Estacionamento de precisão** em ré, ruas estreitas | **CONFIRMADO** | [0:24–0:30] "parking situations where every inch matters"; [1:14–1:38] "narrow streets…reverse into the designated parking area…near-perfect positioning" | NARRATED |
| 9 | **Courier**: entrar na carroceria, achar a encomenda certa (só uma), **escanear etiquetas**, entregar na porta, seguir para o próximo ponto | **CONFIRMADO** | [1:38–1:54] | NARRATED |
| 10 | Carregar o pacote até o destinatário | **CONFIRMADO** ("deliver it straight to the customer's door") | [1:54] | NARRATED |
| 11 | Dados de pacote (assinatura, prioridade, destinatário nomeado etc.) | **NÃO CONFIRMADO** | não mencionado | — (apenas **[AUST DESIGN PROPOSAL]**) |
| 12 | **Integridade da carga**: colisão/dano afetam o **pagamento final** | **CONFIRMADO** | [0:24–0:32] "take proper care of the condition of their cargo"; [2:40–2:47] "Every collision and every bit of damage can directly affect the final payout" | NARRATED |
| 13 | Direção agressiva, raspagem, curva brusca afetam a carga | **NÃO CONFIRMADO** (só "collision" e "damage" são ditos; os demais podem estar na imagem; a brief já dizia "possivelmente" para curva brusca) | — | BRIEF ONLY |
| 14 | **8 trailers customizados** com dimensões diferentes | **NOVO / CONFIRMADO** | [2:08] "eight custom trailers, each with different dimensions, widths, and overall sizes" | NARRATED |
| 15 | Oversized **não passa em toda ponte**; planejar rota | **CONFIRMADO** | [2:15–2:24] | NARRATED |
| 16 | Folga de **túnel**, raio de curva, obstrução de via como fatores | **PARCIAL** — narração fala de **pontes** e de **larguras/dimensões** de trailer; **túnel** e **raio de curva** não são ditos | — | NARRATED (pontes/dimensões) / BRIEF ONLY (túnel, raio) |
| 17 | **Escolta ativa**: segundo jogador garante a rota, ajuda nas manobras e **remove obstáculos** (ex.: postes de luz) | **CONFIRMADO** (a narração é explícita; a v1 dizia "aparentemente") | [2:24–2:40] "at least two players…escort, securing the route, helping the driver maneuver…removing roadside obstacles such as lamps" | NARRATED |
| 18 | Luzes de alerta, sinalização temporária, controle de cruzamento, espaçamento de comboio | **NÃO CONFIRMADO** | não mencionado | — (apenas **[AUST DESIGN PROPOSAL]**) |
| 19 | Jobs complexos duram 30+ minutos | **NOVO / CONFIRMADO** | [0:48] | NARRATED |
| 20 | **Modo empresa**: dono compra caminhões/trailers, contrata, expande a frota, gerencia | **CONFIRMADO** | [2:54–3:10] | NARRATED |
| 21 | **10%** de cada job de funcionário vai automaticamente para a conta da empresa | **CONFIRMADO como afirmação do vídeo** | [3:10–3:18] | NARRATED (percentual **não** copiado) |
| 22 | **Modo job padrão** (sem empresa; dinheiro e XP para progressão) | **NOVO / CONFIRMADO** | [3:18–3:34] | NARRATED |
| 23 | Compatibilidade ESX / QBCore / QBOX | título do produto (não é fala) | — | SECONDARY REPORT |
| 24 | "Dock/rear cargo area → sair do veículo → interagir" como fluxo completo | **NÃO CONFIRMADO** como sequência | só partes (itens 2, 3, 6) são ditas | BRIEF ONLY |

**Correções em relação à v1 (`b66d975`):** (a) a escolta **ativa** passa de "aparentemente" para **narrada**; (b) "direção agressiva/raspagem" e "portas traseiras abertas" **não** estão na transcrição; (c) "hidráulico" e "túnel/raio de curva" **não** estão na transcrição; (d) o **10%** passa de **SECONDARY REPORT** para **afirmação narrada do vídeo**; (e) itens **novos**: descarga em local designado, 8 trailers, jobs de 30+ min, modo job padrão, planejamento de rota pelo motorista.

## 3. Avaliação (somente critérios de gameplay)

Nota 1–10; confiança **MÉDIA** (narração do desenvolvedor, sem verificação visual, sem código).

| Critério | Nota | Base | Tag |
|---|---|---|---|
| GAMEPLAY | 9 | tarefas físicas distintas por tipo de frete (itens 2, 3, 7, 8, 9, 17) | NARRATED |
| JOB VARIETY | 9 | **12 tipos** de job; 8 trailers; courier, oversized, especial | NARRATED |
| HEAVY RP VALUE | 9 | carga manual, rampa, estacionamento de precisão, escolta | NARRATED |
| PHYSICAL INTERACTION | 9 | pallet jack, rampa, scanner de etiquetas, remover obstáculos | NARRATED |
| COOP VALUE | 9 (↑ de 8) | jobs de **no mínimo 2 jogadores** com escolta ativa explícita | NARRATED |
| AUST RELEVANCE | 8 | complementa onde o AUST é mais fraco (profundidade física/courier/escolta); **não** fornece arquitetura | AUST DESIGN PROPOSAL |

## 4. Loop de gameplay observado

```
JOB SELECTION → VEHICLE / CARGO PREPARATION → DOCKING → PHYSICAL LOADING → TRANSPORT
  → CARGO RISK → SPECIAL JOB MECHANICS → PRECISION DELIVERY → REWARD / XP / COMPANY ECONOMY
```

- **[VIDEO OBSERVED — NARRATED]** presentes na narração: posicionar no ponto de carga (6), carregar com pallet jack (2), rampa (3), risco de carga com pagamento (12), mecânicas especiais — courier/oversized/escolta (9, 15, 17), entrega com posicionamento quase perfeito (8), recompensa/XP/empresa (20–22).
- **[VIDEO OBSERVED — BRIEF ONLY]** a etapa "preparação do veículo" como **abrir portas/sair do veículo** não consta na transcrição.
- **[AUST DESIGN PROPOSAL]** a sequência completa como **modelo de profundidade** para o AUST.

**Diferença central:** o job genérico é `PICK TRAILER → DRIVE A TO B → PAYMENT`. **[NARRATED]** o TrueMaps abre dizendo que o script é "much more than simply driving from point A to point B". O AUST hoje é forte em economia/indústria e fraco em preparação física e interação de carga fora de forklift/reach stacker (docs 05 e 07) — **[AUST DESIGN PROPOSAL]**.

## 5. Carregamento físico em doca

**[VIDEO OBSERVED — NARRATED]:** posicionar o caminhão no ponto de carga, **usar pallet jack**, **operar a rampa do caminhão** (abrir/subir/baixar), e na descarga **colocar a mercadoria no local designado**.

**[VIDEO OBSERVED — BRIEF ONLY]:** dar ré na doca → sair do veículo → interagir com a área traseira → abrir portas traseiras → engatar o pallet → mover → carregar dentro do caminhão (a **sequência completa** não é narrada).

Elementos distintos a estudar: **PALLET JACK · LIFTGATE/RAMPA · CARGO DOOR STATE · DOCKING**.

**[AUST DESIGN PROPOSAL] — valor para Heavy RP:** o motorista **prepara fisicamente o veículo** antes de carregar.

## 6. Pallet Jack e modos de manuseio

| Modo | Uso | Estado no AUST (fato) | Tag |
|---|---|---|---|
| **Forklift** | pallets pesados | `client/modules/forklift.lua` (Polarix) e `client/forklift.client.lua` (trade point); estudo em docs 07/10 | fato do AUST |
| **Reach Stacker** | contêineres | `client/modules/reach_stacker.lua`; `container_handler` | fato do AUST |
| **Pallet Jack** | armazém / van / box truck / carga curta | **não existe** | **[NARRATED]** o TrueMaps usa pallet jack para carregar; **[AUST DESIGN PROPOSAL]** terceiro modo (uso em van/box truck é proposta; a narração não especifica o veículo) |

**[AUST DESIGN PROPOSAL]:** `FORKLIFT = heavy pallet handling` · `PALLET JACK = warehouse / van / box truck / short-distance` · `REACH STACKER = containers`. Sem implementação imediata → **GPLAY-01**.

## 7. Cargo Access System (conceito)

**[AUST DESIGN PROPOSAL]** — estados possíveis (rótulos de discussão): `DOORS_CLOSED` · `DOORS_OPEN` · `LIFTGATE_UP` · `LIFTGATE_DOWN` · `LOADING_ALLOWED` · `LOADING_COMPLETE`.

Observação: **[NARRATED]** só a **rampa** (abrir/subir/baixar) é confirmada; **portas** são **[BRIEF ONLY]**. Como o TrueMaps modela estado é **UNKNOWN**. → **GPLAY-02**.

## 8. Courier

**Fluxo [VIDEO OBSERVED — NARRATED]:** entrar na área de carga → **achar o pacote correto (só um é o certo)** → **escanear etiquetas** → identificar → entregar **na porta do cliente** → **seguir para o próximo ponto**.

**Estado do AUST (fato):** depósito NPC → missão de parcel → coleta (`CarrySystem` do **cliente**) → paradas sequenciais → depósito; o servidor valida cooldown, nível e posição (≤ 15 m) por parada (doc 05 §6). **Sem identidade de pacote nem scanner.**

**[AUST DESIGN PROPOSAL] — PARCEL IDENTIFICATION SYSTEM:** dados lógicos possíveis (a transcrição **não** informa o modelo de dados): `parcelId` · `barcode` · `routeStop` · `recipient` · `address` · `priority` · `fragile` · `signatureRequired`. **O servidor decide qual pacote pertence a qual parada**; o cliente só apresenta/interage. → **GPLAY-03**.

## 9. Integridade da carga

**[NARRATED]:** cuidar da condição da carga; **colisão e dano afetam diretamente o pagamento final**. **[BRIEF ONLY]:** direção agressiva, raspagem e curva brusca (**não** aparecem na transcrição).

**Estado do AUST (fato):** integridade **reportada pelo cliente** e **consumida pelo servidor**: `truck_simulation_service.lua:103-108` (clamp 0..100, só pode diminuir); usada em `job_service.lua:434`. Um cliente modificado pode **nunca reportar queda** (CLIENT-SOURCED / SERVER-CONSUMED; **RUNTIME PROOF REQUIRED**).

**[AUST DESIGN PROPOSAL] — conceito (a fórmula do TrueMaps é UNKNOWN):** `CARGO DAMAGE = impact severity + cargo sensitivity + secure state + vehicle dynamics`.

| Classe | Exemplos (**proposta**) |
|---|---|
| LOW | aço / industrial |
| MEDIUM | carga geral |
| HIGH | eletrônicos, vidro, frágeis |
| SPECIAL | líquido, hazmat |

→ **GPLAY-04**.

## 10. Carga oversized e planejamento de rota

**[NARRATED]:** **8 trailers customizados** de dimensões diferentes; **nem toda carga oversized passa em toda ponte**, então o motorista deve **conhecer as rotas certas e planejar a viagem**. **[BRIEF ONLY]:** túnel, raio de curva, obstrução de via como fatores.

**[AUST DESIGN PROPOSAL] — SPECIAL TRANSPORT ROUTE VALIDATION (não implementar):** dimensões do veículo, restrições de rota, **pontes (narrado)**, túneis, curvas fechadas, obstáculos. Fonte dos dados de mapa e método de validação do TrueMaps: **UNKNOWN**. → **GPLAY-07**.

## 11. Escolta ativa

| Recurso | Escolta no XS-Trucking (código lido) | Escolta no TrueMaps |
|---|---|---|
| Natureza | presença/distância/suporte de convoy + bônus (`08b` §9) | **[NARRATED]** tarefas **ativas** (jobs de ≥ 2 jogadores) |

**Fluxo [NARRATED]:** segundo jogador **garante a rota**, **ajuda o motorista a manobrar em trechos difíceis** e **remove obstáculos laterais (ex.: postes de luz)** para o caminhão passar.

**[AUST DESIGN PROPOSAL] — ACTIVE ESCORT ROLE:** tarefas futuras possíveis: controle de tráfego · fechamento de via · reconhecimento de rota · remoção de obstáculo · controle de cruzamento · sinalizador de alerta · sinalização temporária · espaçamento do comboio · verificação de folga (os itens além de "garantir a rota", "ajudar a manobrar" e "remover obstáculos" **não** são ditos no vídeo). **HIGH GAMEPLAY VALUE.** Estado do AUST: papel `escort` citado em `client/convoy.client.lua:180` (não auditado a fundo). → **GPLAY-06**.

## 12. Precisão de estacionamento → DOCKING QUALITY SYSTEM

- **XS (código lido):** `dockScore` (distância 2D + heading do trailer ao ponto, no servidor) — `08b` §9.
- **TrueMaps [NARRATED]:** "every inch matters", "near-perfect positioning", reverse em área designada.
- **[AUST DESIGN PROPOSAL]:** métricas: erro de posição · erro de heading · alinhamento de ré · alinhamento do trailer · velocidade final → **DOCK SCORE 0–100**.

| Faixa (**proposta do AUST; não do TrueMaps**) | Classe |
|---|---|
| < 50 | Poor |
| 50–69 | Acceptable |
| 70–84 | Good |
| 85–94 | Excellent |
| 95+ | Dock Master |

→ **GPLAY-05**.

## 13. Economia de empresa e modos

**[NARRATED]:** dois sistemas principais — **empresa** (dono compra caminhões/trailers, contrata, expande a frota e gerencia; **10%** de cada job de funcionário vai automaticamente à conta da empresa) e **modo job padrão** (sem empresa; dinheiro e XP para desbloquear progressão). **O percentual não é copiado.**

Conceito: `ENTREGA DO FUNCIONÁRIO → PAGAMENTO DO MOTORISTA + RECEITA DA EMPRESA (revenue share)`.

**[AUST DESIGN PROPOSAL]:** o AUST pode ter sistema mais rico (rank, corte do motorista, corte da empresa, propriedade de veículo, contrato, perks, reputação); percentual **configurável por rank**. O AUST **já tem** empresa/frota/progressão (docs 03/05) e modo padrão. **Conclusão: IDEA VALIDATED — EXACT ECONOMY NOT TO COPY.**

## 14. Comparação por especialidade (matriz completa em `09_COMPARATIVE_MATRIX.md`)

| Referência | BEST FOR |
|---|---|
| **XS-Trucking** (código lido) | arquitetura, business, carreira, estrutura co-op, bridges, admin, ferramentas estáticas |
| **Polarix** (código lido, MIT) | representação forklift/pallet, estado lógico de carga no servidor, *representation swap* |
| **TrueMaps** (**só gameplay; sem código**) | gameplay físico, interação de carga, variedade de jobs, courier, escolta ativa, docking de precisão, transporte oversized |
| **AUST** | alvo de integração, economia de indústria, ADR, petróleo, repo, manuseio de contêiner, car carrier, logística NPC, PropEditor, endurecimento de autoridade do servidor |

> **O AUST NÃO deve copiar um único recurso de trucking.** Usar referências **por domínio**. **TARGET DESIGN (proposta):** XS → arquitetura · Polarix → manuseio de pallet · TrueMaps → profundidade de gameplay · AUST → sistema integrado canônico.

## 15. Backlog de ESTUDO de gameplay (GPLAY) — nada será implementado

| ID | Título | Prioridade | Evidência no vídeo (transcrição) | Estado |
|---|---|---|---|---|
| GPLAY-01 | Pallet Jack (**+ descarga em local designado**) | ALTA | pallet jack e descarga: **NARRATED** | STUDY ONLY |
| GPLAY-02 | Hydraulic Liftgate / Cargo Doors | ALTA | rampa: **NARRATED**; portas: **BRIEF ONLY** | STUDY ONLY |
| GPLAY-03 | Courier Package Scanner | ALTA | **NARRATED** | STUDY ONLY |
| GPLAY-04 | Cargo Integrity | ALTA | colisão/dano → pagamento: **NARRATED**; direção agressiva/raspagem: **BRIEF ONLY** | STUDY ONLY |
| GPLAY-05 | Precision Docking | ALTA | **NARRATED** | STUDY ONLY |
| GPLAY-06 | Active Escort Gameplay | ALTA | **NARRATED** | STUDY ONLY |
| GPLAY-07 | Oversized Route Restrictions | MÉDIA | pontes e planejamento de rota: **NARRATED**; túnel/raio: **BRIEF ONLY** | STUDY ONLY |
| GPLAY-08 | Road Obstacle Interaction | MÉDIA | remover obstáculos (ex.: postes): **NARRATED** | STUDY ONLY |
| GPLAY-09 | Special Transport Convoy | MÉDIA | oversized + escolta ≥ 2 jogadores: **NARRATED** | STUDY ONLY |

Todos: **J2 APPROVAL REQUIRED: YES · CODE CHANGE: NO.** Decisão por item: **APPROVE / DEFER / REJECT**.

## 16. Detalhamento dos itens de estudo

### 16.1 GPLAY-01 — Pallet Jack

**STUDY:** modelo de interação · claim de pallet · colisão · movimento · animação do jogador · autoridade de rede · ownership · zonas de carregamento · baia de carga do caminhão · observador multiplayer · **descarga em local designado** (narrada). Comparar com forklift e reach stacker.

**Pergunta para J2 (sem decisão automática):** o pallet jack deveria usar **A)** pallet físico em rede · **B)** *assisted attach* · **C)** *representation swap* · **D)** híbrido? (Ver `10_PALLET_ARCHITECTURE_OPTIONS.md`.) O vídeo **não informa** como o TrueMaps representa o pallet (**UNKNOWN**).

### 16.2 GPLAY-02 — Cargo Access

**STUDY:** rampa/liftgate (narrada) · portas traseiras (**BRIEF ONLY**) · rampas · acesso à carga do veículo · permissão de carregamento. **Perguntas:** abrir a porta afeta o estado da carga? pode-se carregar com a porta fechada? quem é dono do estado do liftgate? o estado deve replicar? o que acontece na desconexão? (docs 06 e 11).

### 16.3 GPLAY-03 — Courier Scanner

**STUDY:** identidade do pacote · parada da rota · código de barras/etiqueta (narrada: "scan the labels") · prop de scanner · pacote errado/correto (narrado: "only one of them is the right one") · assinatura e destinatário (**não** narrados; proposta). **Requisito:** o **SERVIDOR** decide qual pacote pertence a qual parada; o cliente só apresenta/interage. Base do AUST: `server/services/parcel_service.lua`, `client/parcel_delivery.lua` (doc 05 §6).

### 16.4 GPLAY-04 — Cargo Integrity

**STUDY:** impacto · velocidade · velocidade angular · tipo de carga · acúmulo de dano. **Requisito:** **não confiar em número de dano arbitrário do cliente**; desenho **server-authoritative** ou telemetria validada. **RUNTIME PROOF REQUIRED.** Base: `truck_simulation_service.lua:103-108` e política **W3-10**.

### 16.5 GPLAY-05 — Precision Docking

**STUDY:** `dockScore` do XS como referência técnica; comparar com o gameplay do TrueMaps (narrado). **Preferência (proposta):** calcular **no servidor** — posição e heading do trailer × alvo. **Saída:** score · bônus · XP · rating. Relaciona-se com **W3-01**.

### 16.6 GPLAY-06 — Active Escort

**Objetivo:** transformar a escolta de "ficar no alcance" em **função ativa** (narrada: garantir a rota, ajudar a manobrar, remover obstáculos). **STUDY:** pilot car · luzes de alerta · scout de rota · interação com obstáculo · controle temporário de via · suporte ao comboio. **Heavy RP: VERY HIGH.**

### 16.7 GPLAY-07 / 08 / 09 (prioridade média)

| ID | Escopo de estudo |
|---|---|
| GPLAY-07 | restrições de rota para oversized: dimensões, **pontes (narrado)**, túneis, curvas, obstruções; **planejamento de rota pelo motorista** (narrado); fonte de dados de mapa **UNKNOWN** |
| GPLAY-08 | interação com obstáculo de via (remover/criar; quem pode; ciclo de vida; limpeza na desconexão; risco de grief) |
| GPLAY-09 | comboio de transporte especial (oversized + escolta ativa + pilot car) sobre o convoy atual (`convoy_service`); depende de GPLAY-06/07 |

## 17. Ecossistema de dispositivos (sem criar outra UI isolada)

Ver `19_AUST_DEVICE_ECOSYSTEM_INTEGRATION.md` (**PHONE ≠ TABLET ≠ NEXUSOS**; fontes dos três resources **não lidas**; **ARCHITECTURE PENDING SOURCE REVIEW**). **[AUST DESIGN PROPOSAL]**:

| Funcionalidade | Dispositivo proposto |
|---|---|
| Courier scanner | **TABLET** / interface operacional portátil |
| Manifesto de carga | **TABLET** |
| Planejamento da empresa | **NEXUSOS** |
| Atribuição de escolta | **NEXUSOS / TABLET** |
| Alerta de escolta | **PHONE** |
| **Route Builder** | **ADMIN ONLY** |

## 18. Route Builder

**ROUTE BUILDER = ADMIN ONLY. Jogador comum = SEM ACESSO.** Não confundir **planejamento de rota como gameplay** (narrado: o motorista planeja a rota por pontes; a escolta garante a rota) com **ferramenta administrativa de autoria de rotas**. São coisas diferentes: nenhum GPLAY dá a jogadores acesso ao builder.

## 19. Perguntas para J2

1. Quais GPLAY entram no roadmap? (APPROVE / DEFER / REJECT por ID.)
2. Pallet Jack: A, B, C ou D? (GPLAY-01.)
3. Conferir **na imagem** os itens **BRIEF ONLY** (portas traseiras, direção agressiva/raspagem, túnel/raio de curva, "hidráulico") antes de aprová-los.
4. GPLAY-04: tratar a integridade atual (cliente → servidor, só decresce) como transitória?

## 20. Limites desta revisão

- A transcrição é **legenda automática** (erros possíveis) e **não cobre a imagem**; nada foi checado visualmente.
- A narração é **material de divulgação**: confirma o que o produto **afirma**, não como funciona nem se é robusto.
- Nenhum dado de implementação, segurança, OneSync, banco ou desempenho foi obtido (**UNKNOWN**).

## 21. Legal

TrueMaps: sem acesso a código; **nenhum código, UI, asset ou texto foi copiado** (a transcrição foi usada só para registrar fatos de gameplay; trechos citados são curtos e atribuídos). **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.**
