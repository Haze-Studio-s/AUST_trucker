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

## 0. Classificação de evidência (4 níveis — nunca misturar)

| # | Tag | Significado | Uso neste estudo |
|---|---|---|---|
| 1 | **VIDEO NARRATION CONFIRMED** | declarado diretamente pela narração/transcrição | todas as mecânicas dos tempos [0:00]–[3:34+] listadas na §2 |
| 2 | **VIDEO VISUAL OBSERVED** | visível no gameplay, não necessariamente narrado | **nenhum item confirmado**: esta sessão não vê a imagem e ninguém forneceu confirmação visual; **candidatos** estão na §2 (itens marcados SECONDARY REPORT que podem aparecer só na imagem) |
| 3 | **SECONDARY REPORT** | informado por análise externa, sem confirmação direta | itens da brief que **não** aparecem na transcrição (portas traseiras, direção agressiva/raspagem/curva brusca, túnel/raio de curva, "hidráulico", sequência completa de doca) e a compatibilidade ESX/QBCore/QBOX (título) |
| 4 | **AUST DESIGN PROPOSAL** | ideia nossa derivada da referência | estados de acesso à carga, modelo de dados de pacote, fórmula de dano, faixas de docking, tarefas de escolta além das narradas |

**TECHNICAL IMPLEMENTATION UNKNOWN** para tudo que não é gameplay (ver §1). Fonte da evidência 1: **transcrição temporal** (legenda automática em inglês do YouTube, 3:54, fornecida pelo usuário; **pode conter erros de reconhecimento**; não inclui o que aparece só na imagem).

## 1. TECHNICAL IMPLEMENTATION UNKNOWN (não inferir)

| Aspecto | Status |
|---|---|
| Arquitetura do código-fonte | **UNKNOWN** |
| Esquema de banco de dados | **UNKNOWN** |
| Divisão servidor/cliente | **UNKNOWN** |
| Autoridade do servidor (SERVER AUTHORITY) | **UNKNOWN** |
| Ownership OneSync | **UNKNOWN** |
| Ciclo de vida de entidades | **UNKNOWN** |
| Design de eventos/callbacks | **UNKNOWN** |
| Estratégia anti-exploit / segurança | **UNKNOWN** |
| Persistência | **UNKNOWN** |
| Desempenho / manutenção | **UNKNOWN** |
| Fórmulas exatas (pontuação de estacionamento, dano) | **UNKNOWN** |
| Implementação exata do scanner | **UNKNOWN** |
| Algoritmo exato de folga de ponte | **UNKNOWN** |
| Implementação exata da remoção de obstáculos | **UNKNOWN** |
| Licença / código | **UNKNOWN** (tratar como proprietário; **IDEA ONLY — INDEPENDENT REIMPLEMENTATION**) |

Nenhum SQL, evento, callback, função, esquema ou desenho de rede é atribuído ao TrueMaps.

## 2. Confirmação item a item (brief × transcrição)

Legenda de resultado: **CONFIRMADO** (na narração) · **PARCIAL** · **NÃO CONFIRMADO** (não aparece na transcrição; pode estar só na imagem) · **NOVO** (aparece na transcrição e não estava na brief).

| # | Item | Resultado | Trecho da transcrição | Tag |
|---|---|---|---|---|
| 1 | 12 tipos de job (de courier a oversized/especial) | **CONFIRMADO** | [0:08–0:16] "as many as 12 different job types, ranging from courier deliveries to oversized and special cargo transportation" | VIDEO NARRATION CONFIRMED |
| 2 | Carregar com **pallet jack** | **CONFIRMADO** | [0:16–0:24] "load cargo using a pallet jack" | VIDEO NARRATION CONFIRMED |
| 3 | **Rampa de carga do caminhão** (abrir, subir, baixar conforme a situação) | **CONFIRMADO** (como "loading ramp") | [0:40] "operate the truck's loading ramp, deploying it, raising it, and lowering it" | VIDEO NARRATION CONFIRMED |
| 4 | Liftgate **hidráulico** | **PARCIAL** — a narração diz "loading ramp"; a palavra "hydraulic" **não** aparece | — | VIDEO NARRATION CONFIRMED (rampa) / SECONDARY REPORT ("hidráulico") |
| 5 | **Abrir portas traseiras**; sair do veículo; interagir com a área traseira | **NÃO CONFIRMADO** | não mencionado | SECONDARY REPORT |
| 6 | Posicionar o caminhão no ponto de carga (veículo longo, correções constantes) | **CONFIRMADO** | [0:57–1:14] "position yourself perfectly at the loading point while controlling an extremely long vehicle" | VIDEO NARRATION CONFIRMED |
| 7 | Descarga: colocar a mercadoria no **local designado** | **NOVO / CONFIRMADO** | [0:32] "carefully place the goods in the correct designated location" | VIDEO NARRATION CONFIRMED |
| 8 | **Estacionamento de precisão** em ré, ruas estreitas | **CONFIRMADO** | [0:24–0:30] "parking situations where every inch matters"; [1:14–1:38] "narrow streets…reverse into the designated parking area…near-perfect positioning" | VIDEO NARRATION CONFIRMED |
| 9 | **Courier**: entrar na carroceria, achar a encomenda certa (só uma), **escanear etiquetas**, entregar na porta, seguir para o próximo ponto | **CONFIRMADO** | [1:38–1:54] | VIDEO NARRATION CONFIRMED |
| 10 | Carregar o pacote até o destinatário | **CONFIRMADO** ("deliver it straight to the customer's door") | [1:54] | VIDEO NARRATION CONFIRMED |
| 11 | Dados de pacote (assinatura, prioridade, destinatário nomeado etc.) | **NÃO CONFIRMADO** | não mencionado | — (apenas **[AUST DESIGN PROPOSAL]**) |
| 12 | **Integridade da carga**: colisão/dano afetam o **pagamento final** | **CONFIRMADO** | [0:24–0:32] "take proper care of the condition of their cargo"; [2:40–2:47] "Every collision and every bit of damage can directly affect the final payout" | VIDEO NARRATION CONFIRMED |
| 13 | Direção agressiva, raspagem, curva brusca afetam a carga | **NÃO CONFIRMADO** (só "collision" e "damage" são ditos; os demais podem estar na imagem; a brief já dizia "possivelmente" para curva brusca) | — | SECONDARY REPORT |
| 14 | **8 trailers customizados** com dimensões diferentes | **NOVO / CONFIRMADO** | [2:08] "eight custom trailers, each with different dimensions, widths, and overall sizes" | VIDEO NARRATION CONFIRMED |
| 15 | Oversized **não passa em toda ponte**; planejar rota | **CONFIRMADO** | [2:15–2:24] | VIDEO NARRATION CONFIRMED |
| 16 | Folga de **túnel**, raio de curva, obstrução de via como fatores | **PARCIAL** — narração fala de **pontes** e de **larguras/dimensões** de trailer; **túnel** e **raio de curva** não são ditos | — | VIDEO NARRATION CONFIRMED (pontes/dimensões) / SECONDARY REPORT (túnel, raio) |
| 17 | **Escolta ativa**: segundo jogador garante a rota, ajuda nas manobras e **remove obstáculos** (ex.: postes de luz) | **CONFIRMADO** (a narração é explícita; a v1 dizia "aparentemente") | [2:24–2:40] "at least two players…escort, securing the route, helping the driver maneuver…removing roadside obstacles such as lamps" | VIDEO NARRATION CONFIRMED |
| 18 | Luzes de alerta, sinalização temporária, controle de cruzamento, espaçamento de comboio | **NÃO CONFIRMADO** | não mencionado | — (apenas **[AUST DESIGN PROPOSAL]**) |
| 19 | Jobs complexos duram 30+ minutos | **NOVO / CONFIRMADO** | [0:48] | VIDEO NARRATION CONFIRMED |
| 20 | **Modo empresa**: dono compra caminhões/trailers, contrata, expande a frota, gerencia | **CONFIRMADO** | [2:54–3:10] | VIDEO NARRATION CONFIRMED |
| 21 | **10%** de cada job de funcionário vai automaticamente para a conta da empresa | **CONFIRMADO como afirmação do vídeo** | [3:10–3:18] | VIDEO NARRATION CONFIRMED (percentual **não** copiado) |
| 22 | **Modo job padrão** (sem empresa; dinheiro e XP para progressão) | **NOVO / CONFIRMADO** | [3:18–3:34] | VIDEO NARRATION CONFIRMED |
| 23 | Compatibilidade ESX / QBCore / QBOX | título do produto (não é fala) | — | SECONDARY REPORT |
| 24 | "Dock/rear cargo area → sair do veículo → interagir" como fluxo completo | **NÃO CONFIRMADO** como sequência | só partes (itens 2, 3, 6) são ditas | SECONDARY REPORT |

**Correções em relação à v1 (`b66d975`):** (a) a escolta **ativa** passa de "aparentemente" para **narrada**; (b) "direção agressiva/raspagem" e "portas traseiras abertas" **não** estão na transcrição; (c) "hidráulico" e "túnel/raio de curva" **não** estão na transcrição; (d) o **10%** passa de **SECONDARY REPORT** para **afirmação narrada do vídeo**; (e) itens **novos**: descarga em local designado, 8 trailers, jobs de 30+ min, modo job padrão, planejamento de rota pelo motorista.

## 3. Avaliação (somente critérios de gameplay)

Nota 1–10; confiança **MÉDIA** (narração do desenvolvedor, sem verificação visual, sem código).

| Critério | Nota | Base | Tag |
|---|---|---|---|
| GAMEPLAY | 9 | tarefas físicas distintas por tipo de frete (itens 2, 3, 7, 8, 9, 17) | VIDEO NARRATION CONFIRMED |
| JOB VARIETY | 9 | **12 tipos** de job; 8 trailers; courier, oversized, especial | VIDEO NARRATION CONFIRMED |
| HEAVY RP VALUE | 9 | carga manual, rampa, estacionamento de precisão, escolta | VIDEO NARRATION CONFIRMED |
| PHYSICAL INTERACTION | 9 | pallet jack, rampa, scanner de etiquetas, remover obstáculos | VIDEO NARRATION CONFIRMED |
| COOP VALUE | 9 (↑ de 8) | jobs de **no mínimo 2 jogadores** com escolta ativa explícita | VIDEO NARRATION CONFIRMED |
| AUST RELEVANCE | 8 | complementa onde o AUST é mais fraco (profundidade física/courier/escolta); **não** fornece arquitetura | AUST DESIGN PROPOSAL |

## 4. Loop de gameplay observado

```
JOB SELECTION → VEHICLE / CARGO PREPARATION → DOCKING → PHYSICAL LOADING → TRANSPORT
  → CARGO RISK → SPECIAL JOB MECHANICS → PRECISION DELIVERY → REWARD / XP / COMPANY ECONOMY
```

- **[VIDEO NARRATION CONFIRMED]** presentes na narração: posicionar no ponto de carga (6), carregar com pallet jack (2), rampa (3), risco de carga com pagamento (12), mecânicas especiais — courier/oversized/escolta (9, 15, 17), entrega com posicionamento quase perfeito (8), recompensa/XP/empresa (20–22).
- **[SECONDARY REPORT]** a etapa "preparação do veículo" como **abrir portas/sair do veículo** não consta na transcrição.
- **[AUST DESIGN PROPOSAL]** a sequência completa como **modelo de profundidade** para o AUST.

**Diferença central:** o job genérico é `PICK TRAILER → DRIVE A TO B → PAYMENT`. **[VIDEO NARRATION CONFIRMED]** o TrueMaps abre dizendo que o script é "much more than simply driving from point A to point B". O AUST hoje é forte em economia/indústria e fraco em preparação física e interação de carga fora de forklift/reach stacker (docs 05 e 07) — **[AUST DESIGN PROPOSAL]**.

## 5. Carregamento físico em doca

**[VIDEO NARRATION CONFIRMED]:** posicionar o caminhão no ponto de carga, **usar pallet jack**, **operar a rampa do caminhão** (abrir/subir/baixar), e na descarga **colocar a mercadoria no local designado**.

**[SECONDARY REPORT]:** dar ré na doca → sair do veículo → interagir com a área traseira → abrir portas traseiras → engatar o pallet → mover → carregar dentro do caminhão (a **sequência completa** não é narrada).

Elementos distintos a estudar: **PALLET JACK · LIFTGATE/RAMPA · CARGO DOOR STATE · DOCKING**.

**[AUST DESIGN PROPOSAL] — valor para Heavy RP:** o motorista **prepara fisicamente o veículo** antes de carregar.

## 6. Pallet Jack e modos de manuseio

| Modo | Uso | Estado no AUST (fato) | Tag |
|---|---|---|---|
| **Forklift** | pallets pesados | `client/modules/forklift.lua` (Polarix) e `client/forklift.client.lua` (trade point); estudo em docs 07/10 | fato do AUST |
| **Reach Stacker** | contêineres | `client/modules/reach_stacker.lua`; `container_handler` | fato do AUST |
| **Pallet Jack** | armazém / van / box truck / carga curta | **não existe** | **[VIDEO NARRATION CONFIRMED]** o TrueMaps usa pallet jack para carregar; **[AUST DESIGN PROPOSAL]** terceiro modo (uso em van/box truck é proposta; a narração não especifica o veículo) |

**[AUST DESIGN PROPOSAL]:** `FORKLIFT = heavy pallet handling` · `PALLET JACK = warehouse / van / box truck / short-distance` · `REACH STACKER = containers`. Sem implementação imediata → **GPLAY-01**.

## 7. Cargo Access System (conceito)

**[AUST DESIGN PROPOSAL]** — estados possíveis (rótulos de discussão): `DOORS_CLOSED` · `DOORS_OPEN` · `LIFTGATE_UP` · `LIFTGATE_DOWN` · `LOADING_ALLOWED` · `LOADING_COMPLETE`.

Observação: **[VIDEO NARRATION CONFIRMED]** só a **rampa** (abrir/subir/baixar) é confirmada; **portas** são **[SECONDARY REPORT]**. Como o TrueMaps modela estado é **UNKNOWN**. → **GPLAY-02**.

## 8. Courier

**Fluxo [VIDEO NARRATION CONFIRMED]:** entrar na área de carga → **achar o pacote correto (só um é o certo)** → **escanear etiquetas** → identificar → entregar **na porta do cliente** → **seguir para o próximo ponto**.

**Estado do AUST (fato):** depósito NPC → missão de parcel → coleta (`CarrySystem` do **cliente**) → paradas sequenciais → depósito; o servidor valida cooldown, nível e posição (≤ 15 m) por parada (doc 05 §6). **Sem identidade de pacote nem scanner.**

**[AUST DESIGN PROPOSAL] — PARCEL IDENTIFICATION SYSTEM:** dados lógicos possíveis (a transcrição **não** informa o modelo de dados): `parcelId` · `barcode` · `routeStop` · `recipient` · `address` · `priority` · `fragile` · `signatureRequired`. **O servidor decide qual pacote pertence a qual parada**; o cliente só apresenta/interage. → **GPLAY-03**.

## 9. Integridade da carga

**[VIDEO NARRATION CONFIRMED]:** cuidar da condição da carga; **colisão e dano afetam diretamente o pagamento final**. **[SECONDARY REPORT]:** direção agressiva, raspagem e curva brusca (**não** aparecem na transcrição).

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

**[VIDEO NARRATION CONFIRMED]:** **8 trailers customizados** de dimensões diferentes; **nem toda carga oversized passa em toda ponte**, então o motorista deve **conhecer as rotas certas e planejar a viagem**. **[SECONDARY REPORT]:** túnel, raio de curva, obstrução de via como fatores.

**[AUST DESIGN PROPOSAL] — SPECIAL TRANSPORT ROUTE VALIDATION (não implementar):** dimensões do veículo, restrições de rota, **pontes (narrado)**, túneis, curvas fechadas, obstáculos. Fonte dos dados de mapa e método de validação do TrueMaps: **UNKNOWN**. → **GPLAY-07**.

## 11. Escolta ativa

| Recurso | Escolta no XS-Trucking (código lido) | Escolta no TrueMaps |
|---|---|---|
| Natureza | presença/distância/suporte de convoy + bônus (`08b` §9) | **[VIDEO NARRATION CONFIRMED]** tarefas **ativas** (jobs de ≥ 2 jogadores) |

**Fluxo [VIDEO NARRATION CONFIRMED]:** segundo jogador **garante a rota**, **ajuda o motorista a manobrar em trechos difíceis** e **remove obstáculos laterais (ex.: postes de luz)** para o caminhão passar.

**[AUST DESIGN PROPOSAL] — ACTIVE ESCORT ROLE:** tarefas futuras possíveis: controle de tráfego · fechamento de via · reconhecimento de rota · remoção de obstáculo · controle de cruzamento · sinalizador de alerta · sinalização temporária · espaçamento do comboio · verificação de folga (os itens além de "garantir a rota", "ajudar a manobrar" e "remover obstáculos" **não** são ditos no vídeo). **HIGH GAMEPLAY VALUE.** Estado do AUST: papel `escort` citado em `client/convoy.client.lua:180` (não auditado a fundo). → **GPLAY-06**.

## 12. Precisão de estacionamento → DOCKING QUALITY SYSTEM

- **XS (código lido):** `dockScore` (distância 2D + heading do trailer ao ponto, no servidor) — `08b` §9.
- **TrueMaps [VIDEO NARRATION CONFIRMED]:** "every inch matters", "near-perfect positioning", reverse em área designada.
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

**[VIDEO NARRATION CONFIRMED]:** dois sistemas principais — **empresa** (dono compra caminhões/trailers, contrata, expande a frota e gerencia; **10%** de cada job de funcionário vai automaticamente à conta da empresa) e **modo job padrão** (sem empresa; dinheiro e XP para desbloquear progressão). **O percentual não é copiado.**

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

## 15. Backlog de ESTUDO de gameplay (GPLAY-01…11) — nada será implementado

| ID | Título | Prioridade | Evidência no vídeo (transcrição) | Estado |
|---|---|---|---|---|
| GPLAY-01 | Pallet Jack (**+ descarga em local designado**) | ALTA | pallet jack e descarga: **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| GPLAY-02 | Cargo Ramp / Liftgate (+ portas) | ALTA | rampa: **VIDEO NARRATION CONFIRMED**; portas: **SECONDARY REPORT** | STUDY ONLY |
| GPLAY-03 | Courier Package Scanner | ALTA | **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| GPLAY-04 | Cargo Integrity | ALTA | colisão/dano → pagamento: **VIDEO NARRATION CONFIRMED**; direção agressiva/raspagem: **SECONDARY REPORT** | STUDY ONLY |
| GPLAY-05 | Precision Docking | ALTA | **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| GPLAY-06 | Active Escort Gameplay | ALTA | **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| GPLAY-07 | Oversized Route Clearance | **ALTA** | pontes e planejamento de rota: **VIDEO NARRATION CONFIRMED**; túnel/raio: **SECONDARY REPORT** | STUDY ONLY |
| GPLAY-08 | Road Obstacle Interaction | MÉDIA (sobe para ALTA se GPLAY-06 for aprovado) | remover obstáculos (ex.: postes): **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| GPLAY-09 | Special Transport Convoy | MÉDIA (sobe para ALTA se GPLAY-06/07 forem aprovados) | oversized + escolta ≥ 2 jogadores: **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| **GPLAY-10** | Long-form logistics jobs | **ALTA** | jobs complexos de **30+ minutos**: **VIDEO NARRATION CONFIRMED** | STUDY ONLY |
| **GPLAY-11** | Trailer dimensional route constraints | **ALTA** | 8 trailers de dimensões diferentes e restrição de ponte: **VIDEO NARRATION CONFIRMED** | STUDY ONLY |

**Prioridades:** HIGH PRIORITY STUDY = GPLAY-01…07, 10 e 11; GPLAY-08/09 mantidos MÉDIA (HIGH/MEDIUM conforme a arquitetura de escolta/oversized). Todos: **J2 APPROVAL REQUIRED: YES · CODE CHANGE: NO.** Decisão por item: **APPROVE / DEFER / REJECT**.

## 16. Detalhamento dos itens de estudo

### 16.1 GPLAY-01 — Pallet Jack

**STUDY:** modelo de interação · claim de pallet · colisão · movimento · animação do jogador · autoridade de rede · ownership · zonas de carregamento · baia de carga do caminhão · observador multiplayer · **descarga em local designado** (narrada). Comparar com forklift e reach stacker.

**Pergunta para J2 (sem decisão automática):** o pallet jack deveria usar **A)** pallet físico em rede · **B)** *assisted attach* · **C)** *representation swap* · **D)** híbrido? (Ver `10_PALLET_ARCHITECTURE_OPTIONS.md`.) O vídeo **não informa** como o TrueMaps representa o pallet (**UNKNOWN**).

### 16.2 GPLAY-02 — Cargo Access

**STUDY:** rampa/liftgate (narrada) · portas traseiras (**SECONDARY REPORT**) · rampas · acesso à carga do veículo · permissão de carregamento. **Perguntas:** abrir a porta afeta o estado da carga? pode-se carregar com a porta fechada? quem é dono do estado do liftgate? o estado deve replicar? o que acontece na desconexão? (docs 06 e 11).

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

### 16.8 GPLAY-10 — Long-form logistics jobs

**EVIDENCE [VIDEO NARRATION CONFIRMED, 0:48–0:57]:** jobs complexos podem levar **30 minutos ou mais**.

**STUDY [AUST DESIGN PROPOSAL]:** como sustentar engajamento em jobs longos · checkpoints intermediários · tarefas físicas · risco · multi-parada · recuperação · progresso parcial · tratamento de desconexão · escala de recompensa · risco de fadiga/repetição.

**AUST GOAL:** jobs longos devem ser **mais profundos, não apenas mais longos de direção**. Relaciona-se com o registro único de job e a recuperação de restart/queda (TD-02, TD-27, W4-02) — jobs longos amplificam a perda por reinício (o AUST e o XS mantêm estado só em memória em partes do fluxo; ver `08b` §4.5 e doc 11).

### 16.9 GPLAY-11 — Trailer dimensional route constraints

**EVIDENCE [VIDEO NARRATION CONFIRMED, 2:08–2:24]:** 8 trailers customizados com dimensões/larguras/tamanhos diferentes; nem toda carga oversized passa em toda ponte; exige planejamento de rota.

**STUDY [AUST DESIGN PROPOSAL]:** largura do trailer · altura do trailer · altura da carga · folga de rota · restrições de ponte/túnel · rotas especiais permitidas · **metadados de folga criados por admin**. Algoritmo e fonte de dados do TrueMaps: **UNKNOWN**.

**IMPORTANTE:** **Route Builder = ADMIN ONLY.** Jogadores podem **PLANEJAR** rotas (consulta/planejamento como gameplay), mas **nunca** ganham acesso a ferramentas de **autoria** de rotas ou de metadados de folga. Relaciona-se com GPLAY-07 (validação) e com as dimensões por modelo que o PropEditor já calibra (docs 07/10).

## 17. Ecossistema de dispositivos (sem criar outra UI isolada)

Ver `19_AUST_DEVICE_ECOSYSTEM_INTEGRATION.md` (**PHONE ≠ TABLET ≠ NEXUSOS**; fontes dos três resources **não lidas**; **ARCHITECTURE PENDING SOURCE REVIEW**). **[AUST DESIGN PROPOSAL]** de distribuição:

| Dispositivo | Papel | Funcionalidades candidatas |
|---|---|---|
| **NEXUSOS** | gestão | planejamento de jobs · gestão da empresa · **planejamento de rota oversized** · frota · contratos · atribuição de escolta |
| **VP_TABLET** | operação | manifesto · **checklist de carregamento** · tarefas de pallet/carga · **courier scanner** · condição da carga · rota ativa · tarefas de escolta |
| **VP_PHONE** | comunicação | atribuição de job · convites de empresa/convoy · alertas (incl. alerta de escolta) · manutenção · notificações de frota |
| **ROUTE BUILDER** | autoria | **ADMIN ONLY** |

## 18. Route Builder

**ROUTE BUILDER = ADMIN ONLY. Jogador comum = SEM ACESSO.** Não confundir **planejamento de rota como gameplay** (narrado: o motorista planeja a rota por pontes; a escolta garante a rota) com **ferramenta administrativa de autoria de rotas**. São coisas diferentes: nenhum GPLAY dá a jogadores acesso ao builder.

## 19. Perguntas para J2

1. Quais GPLAY (01–11) entram no roadmap? (APPROVE / DEFER / REJECT por ID.)
2. Pallet Jack: A, B, C ou D? (GPLAY-01.)
3. Conferir **na imagem** (VIDEO VISUAL OBSERVED) os itens **SECONDARY REPORT** (portas traseiras, direção agressiva/raspagem, túnel/raio de curva, "hidráulico") antes de aprová-los.
4. GPLAY-04: tratar a integridade atual (cliente → servidor, só decresce) como transitória?

## 20. Limites desta revisão

- A transcrição é **legenda automática** (erros possíveis) e **não cobre a imagem**; nada foi checado visualmente.
- A narração é **material de divulgação**: confirma o que o produto **afirma**, não como funciona nem se é robusto.
- Nenhum dado de implementação, segurança, OneSync, banco ou desempenho foi obtido (**UNKNOWN**).

## 21. Legal

TrueMaps: sem acesso a código; **nenhum código, UI, asset ou texto foi copiado** (a transcrição foi usada só para registrar fatos de gameplay; trechos citados são curtos e atribuídos). **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.**
