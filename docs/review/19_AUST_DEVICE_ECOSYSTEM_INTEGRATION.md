# 19 — AUST × Ecossistema de dispositivos (NexusOS · vp_tablet · vp_phone)

**STATUS: ARCHITECTURE PENDING SOURCE REVIEW.** Este documento é **proposta de arquitetura para J2**, escrita **sem ler** os repositórios `Haze-Studio-s/nexus_os`, `Haze-Studio-s/vp_tablet` e `Haze-Studio-s/vp_phone` (fora do escopo desta missão documental; o escopo de acesso da sessão cobre apenas `AUST_trucker`). **Nenhum export, evento, callback, badge, deep link ou API desses resources é citado — nada foi inventado.** Onde faltar fato, está marcado **UNKNOWN**.

**ANALYZED HEAD (AUST): `c9d9187`** (código idêntico em `3a89631`). **Nada foi implementado.** Cada item abaixo é **APPROVABLE · REJECTABLE · DEFERABLE · REVIEWABLE** (ver `17_J2_REVIEW_CHECKLIST.md`).

> **GATE 6 — `PHONE ≠ TABLET ≠ NEXUSOS`.** São três dispositivos com papéis distintos. Nenhuma recomendação aqui trata um como substituto do outro.
> **GATE 7 — `ROUTE BUILDER = ADMIN ONLY`. NORMAL PLAYER = NO ACCESS.**

---

## 1. Fatos verificados do lado do AUST (sem depender dos três resources)

| Fato | Evidência |
|---|---|
| O AUST tem **UI própria standalone**: a central de cargas abre por um **despachante NPC** (`ox_target` → evento `truck_logistics:openJobBoard`) | `client/main.lua:418-440`; `client/client.lua:427-440,505-508` |
| A NUI standalone busca dados no servidor por callback (`aurp_trucker:getInitialData`) | `client/client.lua:430` |
| O servidor do AUST já tem dados de domínio: cargas, contratos, empresa/frota, convoy, indústrias, ADR, leaderboards | docs `03_MODULE_OWNERSHIP_MAP.md`, `04_EVENT_CALLBACK_GRAPH.md` |
| Existem duas pilhas de NUI no repositório (jQuery servida × React `html/src` não referenciada) | `01_RESOURCE_INVENTORY.md`, TD-07 |
| Não há integração com NexusOS/vp_tablet/vp_phone no código lido (a busca textual só encontra o áudio `Phone_SoundSet_Default` e o texto "Tablet" do alvo do NPC) | `grep` em `client/main.lua:85,418-437` |
| Os documentos do AUST citam o conceito "TPDA/tablet" como **referência de outros servidores** (LSRP), não como integração implementada | `docs/ATUALIZACOES_VP_E_DIRECIONAMENTO_LSRP_GTAW.md` |
| O AUST **já integra** com outro resource `vp_*` do servidor por **export de servidor protegido por `GetResourceState`** (`vp_gasstations:AddFuelStock`): precedente do padrão "detectar resource → chamar export → seguir sem ele" | `server/services/job_service.lua:509-531`; contexto em `docs/ATUALIZACOES_VP_E_DIRECIONAMENTO_LSRP_GTAW.md` (nada se infere sobre as APIs de NexusOS/vp_tablet/vp_phone) |

**Lacuna:** não há, no AUST, uma **fronteira explícita entre domínio e interface**; a NUI standalone e os handlers de `events.lua` misturam regra de negócio e apresentação (TD-01/TD-02/TD-07).

## 2. O que o XS ensina (e o que NÃO deve ser copiado)

| Do XS (`08b_…`) | Uso proposto no AUST | Restrição |
|---|---|---|
| NUI modular + contrato RPC (`UI RPC ALLOWLIST + SERVER AUTHORITY`) | modelo mental para **qualquer** dispositivo falar com o AUST: o dispositivo só **chama operações nomeadas**; a decisão fica no servidor | **IDEA ONLY — INDEPENDENT REIMPLEMENTATION** |
| A allowlist do cliente **não** é a fronteira de segurança | cada operação do AUST revalida permissão no servidor, **independente do dispositivo** | — |
| Todo o job vive num "laptop" físico | **NÃO replicar o laptop.** O AUST já tem NUI própria e um ecossistema de dispositivos | — |
| Bridges (autodetecção/força de provedor, fallback) | padrão para **dispositivo ausente** → fallback (§7) | W6-07 |

## 3. Responsabilidade proposta de cada dispositivo (PROPOSTA — não é fato do estado atual)

### 3.1 NexusOS — OFFICE / MANAGEMENT / ERP

Candidato para: dashboard · cargas disponíveis · gestão da empresa · frota · motoristas · contratos · convoys · indústrias · cadeia de suprimentos · histórico · ledger · leaderboards · configurações do negócio. **Ferramentas de admin somente quando autorizado** (ver §6).

### 3.2 vp_tablet — FIELD / OPERATIONAL DEVICE

Candidato para: job ativo · manifesto · próxima parada · estado da carga · checklist ADR · status do convoy · status do veículo · inspeção · checklist de entrega · execução de contrato.

### 3.3 vp_phone — COMMUNICATION / NOTIFICATIONS

Candidato para: notificação de job · convite de empresa · convite de convoy · convite de co-driver · alerta de contrato · fim de *fleet run* · notificação de pagamento · alerta de manutenção · **deep link para o tablet/NexusOS** (se o mecanismo existir — **UNKNOWN**).

### 3.4 AUST standalone (NUI atual)

Decisão **pendente de J2**: manter **apenas como fallback** quando o dispositivo não estiver disponível, ou como interface equivalente. Ver decisão 4 em `16_J2_REVIEW_PACKAGE.md`.

## 4. UI RESPONSIBILITY MATRIX (proposta)

Legenda: YES · NO · SUMMARY · FULL · LIMITED · VIEW · ALERT(S) · EXECUTE · PLAN/MANAGE · OVERSIGHT · MODERATION · "—" = não se aplica.

| Feature | PHONE | TABLET | NEXUSOS (jogador) | ADMIN |
|---|---|---|---|---|
| Notifications | YES | YES | YES | — |
| Active job | SUMMARY | FULL | VIEW | VIEW |
| Manifest | SUMMARY | FULL | FULL | VIEW |
| Next stop / entrega (execução) | ALERT | EXECUTE | VIEW | VIEW |
| Cargo / ADR checklist | NO | FULL | VIEW | VIEW |
| Company | SUMMARY | LIMITED | FULL | MODERATION |
| Fleet | ALERTS | LIMITED | FULL | MODERATION |
| Contracts | ALERT | EXECUTE | PLAN/MANAGE | OVERSIGHT |
| Convoy | INVITE/ALERT | STATUS | PLAN/MANAGE | OVERSIGHT |
| Industries / supply chain | NO | LIMITED | FULL | OVERSIGHT |
| Ledger / leaderboards | NO | NO | FULL | VIEW |
| **Route Builder** | **NO** | **NO** | **NO (jogador)** | **YES — ADMIN ONLY** |
| **Server settings** | **NO** | **NO** | **NO (jogador)** | **YES — ADMIN ONLY** |

Observações: (a) a matriz é **proposta de UX**, não requisito técnico descoberto; (b) o que cada dispositivo **consegue** fazer depende da revisão de fonte (STUDY-DEVICE-01); (c) "NEXUSOS ADMIN" refere-se à parte **administrativa** do NexusOS, se existir — **UNKNOWN**.

## 5. Backend canônico do AUST (direção, não implementação)

```
 NexusOS · vp_tablet · vp_phone · (NUI standalone opcional)
                │   (chamadas de operação nomeadas)
                ▼
          AUST TRUCKER API   ← fronteira única; autorização revalidada no servidor
                │
                ▼
        SERVER DOMAIN SERVICES (jobs, contratos, empresa, frota, progressão, pagamento…)
```

**AUST NÃO DEVE DUPLICAR REGRA DE NEGÓCIO EM CADA DEVICE.** Nenhum dispositivo decide:

payout · permissão de job · permissão de contrato · permissão de empresa · propriedade de frota · progressão · conclusão de entrega.

Essas decisões pertencem ao **servidor do AUST**. Regra de projeto proposta: o dispositivo envia **intenção** (ex.: "aceitar job X"); o AUST valida identidade (`source`/citizen), papel, estado e distância/entidades, e responde com o novo estado.

## 6. ROUTE BUILDER = ADMIN ONLY (requisito do projeto)

- **Requisito do projeto, não descoberta técnica.** O Route Builder é **ferramenta administrativa**. **Jogadores comuns não veem nem acessam** esse recurso.
- Não associar o Route Builder à experiência normal de **NexusOS (jogador)**, **vp_tablet**, **vp_phone** ou qualquer "laptop de trucker".
- Deve exigir **autorização de admin no servidor** a cada operação (não basta esconder a UI).
- Cadeia conceitual:

```
ADMIN → NEXUSOS ADMIN / PAINEL ADMIN → ROUTE BUILDER
Nunca: PLAYER → UI NORMAL DE TRUCKING → ROUTE BUILDER
```

- **No XS** (evidência de que o desenho é viável): comando de admin + callbacks `guarded()` por chamada + allowlist de UI por modo + auditoria (`08b` §8.1). **IDEA ONLY — INDEPENDENT REIMPLEMENTATION.**
- **Estado no AUST:** ferramenta de rotas/spots em jogo **não identificada** (busca textual sem resultados; **UNKNOWN**). Esta fase **não propõe construir** um novo builder (ver W5-06, apenas estudo de validação de posicionamento).

## 7. Fallback quando um dispositivo não está disponível (a definir por J2)

| Situação | Comportamento proposto (REVIEWABLE) |
|---|---|
| vp_phone ausente | notificações caem para notificação do framework/`ox_lib` |
| vp_tablet ausente | NUI standalone do AUST (fallback) para execução do job |
| NexusOS ausente | NUI standalone para gestão **sem** ferramentas de admin; admin continua só por comando/ACE |
| Dispositivo presente mas sem permissão | operação recusada **no servidor** com mensagem padrão |

Padrão inspirador (XS): detecção de recurso por estado + "fallback próprio" (`bridge/dispatch.lua`). **UNKNOWN** como NexusOS/vp_* registram apps/permissões.

## 8. Operações canônicas candidatas (somente NOMES; sem assinatura)

> **Não definir assinatura final ainda.** Primeiro: **revisão de J2** + **revisão de fonte** dos três resources (STUDY-DEVICE-01). Os nomes abaixo são rótulos de discussão, **não** contratos.

| Domínio | Operações candidatas |
|---|---|
| Painel/Jobs | GetDashboard · GetAvailableJobs · GetActiveJob · AcceptJob · CancelJob · GetManifest |
| Empresa | GetCompany · GetCompanyMembers · GetCompanyFleet · GetCompanyLedger |
| Contratos | GetContracts · AcceptContract |
| Convoy | GetConvoy · CreateConvoy · JoinConvoy |
| Perfil | GetDriverProfile · GetProgression |
| Veículo | GetVehicleStatus · GetMaintenance |
| Indústria | GetIndustryStatus · GetSupplyOrders |

Para cada operação, o AUST precisaria definir (futuro): autorização, rate limit, idempotência (ex.: `reqId`), formato de erro e política de *late join*/reconexão (ver `11_…`).

## 9. Riscos de arquitetura (para revisão)

| ID | Risco | Mitigação proposta |
|---|---|---|
| DEV-R1 | Regra de negócio duplicada em cada dispositivo | backend canônico (§5) |
| DEV-R2 | Dispositivo "decide" pagamento/permissão | decisões só no servidor do AUST |
| DEV-R3 | Route Builder exposto a jogador por engano | admin-only no servidor + auditoria; nunca no catálogo de apps de jogador |
| DEV-R4 | Dependência de resource ausente quebra o fluxo | fallback (§7) |
| DEV-R5 | Três UIs divergem em estado (job ativo) | fonte única de estado no servidor; dispositivos só leem/solicitam |
| DEV-R6 | Contrato RPC sem verificação estática | checker de contrato (W0-04C) estendido aos dispositivos |
| DEV-R7 | Cópia acidental de código do XS | política IDEA ONLY + prática *clean-room* |

## 10. STUDY-DEVICE-01 (escopo proposto — RISK: NONE, STUDY ONLY)

Ler `nexus_os`, `vp_tablet`, `vp_phone` e **mapear**: registro de apps · exports · eventos · callbacks · notificações · deep links · badges · permissões · eventos em segundo plano · comunicação NUI · ciclo de vida do resource. Entregável: documento de **fatos** (com arquivo/função) + lista do que o AUST precisaria expor. **J2 APPROVAL REQUIRED: YES** (inclui autorizar o acesso de leitura aos três repositórios).

## 11. Decisões pedidas a J2 (ver também `16_…`)

1. NexusOS como interface principal de gestão? 2. Tablet como interface operacional do motorista? 3. Phone restrito a notificação/ação rápida? 4. NUI standalone só como fallback? 5. Route Builder **ADMIN ONLY** (requisito: YES)? 6. Aprovar STUDY-DEVICE-01? 7. Aprovar o desenho conceitual W6-06 **após** o estudo?

## 12. Legal

Nenhum código do XS ou de terceiros foi copiado para este documento. XS-Trucking: **ALL RIGHTS RESERVED** → **IDEA ONLY — INDEPENDENT REIMPLEMENTATION**.
