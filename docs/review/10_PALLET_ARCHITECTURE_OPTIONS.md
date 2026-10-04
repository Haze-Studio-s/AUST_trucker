# 10 — Pallet Architecture Options

**ANALYZED HEAD: `c9d9187`.** Este documento **recomenda**, não implementa. Notas 0–10, **10 = melhor** (em "implementation risk", 10 = menor risco). Notas são julgamento de engenharia a partir do código lido; **não foram medidas**.

## 1. Problema que a arquitetura precisa resolver

Evidências (ver `07_FORKLIFT_PALLET_DEEP_DIVE.md`):

1. O pallet frozen bloqueia os garfos como parede sólida (comentário do próprio J2 em `41efab6`).
2. Para contornar, o fluxo atual descongela ao engatar e deixa a Havok carregar o pallet por 0 → 0,35 m (`forklift.lua:707-740`).
3. O servidor não conhece o estado "reivindicado/carregando" (só vê a estiva).
4. O limiar 0,35 m e o offset `(0, 0.95, -0.05)` são literais sem origem verificável.
5. O Polarix (referência da qual o AUST deriva) evita a janela Havok: chão frozen **local**, troca de representação no pickup, prop anexado com `collision=false`.

## 2. Modelos

### MODEL A — HAVOK PURE
`STAGED → DYNAMIC → PHYSICAL LIFT → LATE ATTACH`
É o que o AUST faz hoje com attach a 0,35 m e o que Don, Mobius e xDope fazem sem attach nenhum.

### MODEL B — DIRECT ATTACH
`STAGED_FROZEN → VALIDATE → ATTACH SAME ENTITY`
O pallet "salta" para os garfos assim que o alinhamento é válido, sem elevação.

### MODEL C — REPRESENTATION SWAP
`GROUND PROP → SERVER CLAIM → REMOVE → CARRIED PROP → ATTACH`
É a arquitetura do Polarix. Funciona porque o chão é **local por cliente** e o carregado também.

### MODEL D — ASSISTED HYBRID
`STAGED_FROZEN → FORKS VALID → LIFT INTENT → MINIMAL PHYSICAL CONFIRMATION → ATTACH`
Duas variantes, porque "confirmação física mínima" pode significar duas coisas:

- **D-H (Havok):** descongela e deixa a Havok subir 5–10 cm antes de anexar.
- **D-K (cinemática):** o pallet **nunca** sai do frozen; a confirmação é a subida do **osso dos garfos** no referencial do forklift, e o attach preserva a pose do mundo (snap visual zero). É o que o PR #9 contém (desligado por flag; `shared/fork_lift.lua`, `server/pallet_registry.lua`).

## 3. Pontuação

| Critério | A Havok pura | B Attach direto | C Swap | D-H | **D-K** |
|---|---|---|---|---|---|
| REALISM | 10 | 4 | 5 | 8 | 8 |
| STABILITY | 3 | 9 | 10 | 6 | 8 |
| ONESYNC | 4 | 8 | 9 | 5 | 8 |
| MULTIPLAYER | 5 | 8 | 6 (8 com reconstrução) | 6 | 8 |
| SECURITY | 4 | 6 | 8 | 6 | 8 (claim no servidor) |
| PERFORMANCE | 5 | 9 | 8 | 7 | 8 |
| MAINTAINABILITY | 4 | 8 | 5 | 5 | 7 |
| IMPLEMENTATION RISK (10 = baixo risco) | 6 (já existe) | 9 | 4 | 6 | 6 |
| HEAVY RP QUALITY | 8 | 4 | 5 | 8 | 8 |
| **Média** | **5,9** | **7,2** | **6,7** | **6,3** | **7,7** |

Observações sobre a matriz:

- **D-K lidera na média (7,7) por margem pequena sobre B (7,2).** Com os critérios "SECURITY" e "HEAVY RP QUALITY" incluídos, D-K passa a B (na versão com 11 critérios do estudo anterior, B ficava 0,2 acima). **A ordem depende de quais critérios entram e de quanto peso cada um tem; sem pesos, tratar B e D-K como equivalentes numéricos.**
- O que separa B de D-K é **realismo** e **Heavy RP quality** (4 contra 8): em B o pallet não sobe com os garfos.
- **C** tem a melhor estabilidade, mas só entrega o ganho do Polarix se o **pallet de chão também for local por cliente** (ver 4.3). Aplicar C ao AUST sem isso é só churn de netId.
- **A** é o pior em estabilidade e é o estado atual.

## 4. Análise por modelo

### 4.1 A — o que já se sabe
Mesmo com gravidade desligada no chão, o pallet depende de contato com os dentes para subir. Pontos de falha reais no código: `PalletBaseZ` amostrado uma vez; clamp de `vel.z`; `ActivatePhysics` na transição; sem noção de dono/estado no servidor.

### 4.2 B — vantagens e custo
Mais simples e mais seguro que A. Custo: o pallet "teletransporta" para o offset dos garfos; o alinhamento precisa de validação rígida para não permitir pegar à distância.

### 4.3 C — quando faria sentido
Precondições para C ser melhor que D-K no AUST:
1. Pallets de chão criados **localmente** em cada cliente (determinístico a partir do servidor), com colisão carregada perto do jogador;
2. estado lógico por slot no servidor (já previsto);
3. reconstrução visual periódica para observadores.

Isso mexe em `server/main.lua` (spawn), `client/main.lua` (sync), `PalletRegistry` (chave por slot em vez de netId) e no modelo de pagamento por netId. É a maior mudança das quatro.

### 4.4 D-K — pontos de atenção
1. Depende de o pallet **não colidir com o forklift** durante a aproximação (`SetEntityNoCollisionEntity` por frame). Sem isso, o problema da "parede sólida" (`41efab6`) volta. **RUNTIME PROOF REQUIRED.**
2. O osso `forks`/`forks_attach` precisa existir e ter a mesma orientação da raiz do veículo (premissa do cálculo de offset relativo; o código valida o erro pós-attach e desiste após duas falhas).
3. O limiar 0,08 m, a histerese 0,03 m e o dwell de 150 ms são pontos de partida; a telemetria `OnLift` (`pallet_debug.lua`) existe para medi-los.
4. Estado **pendente de entrega**: o cliente (`client/modules/forklift.lua`) e a linha do manifest para `shared/fork_lift.lua` ainda não foram aplicados (ver `00_CURRENT_STATE_SNAPSHOT.md`).

## 5. Opção de rede (rep. do pallet carregado)

| Opção | Descrição | Veredito |
|---|---|---|
| **A** | Mesma entidade networked, dono travado | **Recomendada agora** |
| B | Swap com prop local do operador + decorativo para observadores | só se o teste mostrar flicker no attach |
| C | Chão local por cliente + estado lógico no servidor (Polarix) | caminho de longo prazo se o afundamento persistir |
| D | Entidade networked só no trailer | descartada (não resolve a fase de garfo) |

## 6. Recomendação

**Adotar D-K com a Opção A de rede**, em fases (ver `15_IMPLEMENTATION_PLAN_FOR_J2.md`, WAVE 1):

1. Primeiro apenas **telemetria** (`/palletdebug`, `OnLift`) para medir o ruído real do osso dos garfos.
2. Estado lógico no servidor (`CLAIMED/CARRIED/STOWED/RECOVERY`) com a flag desligada.
3. Cliente cinemático atrás da flag, com fallback automático para o fluxo atual após duas falhas de attach.
4. Só então decidir limiares e perfil de attach por combinação forklift × pallet.

**Alternativas aceitáveis:** B se o produto não precisar da sensação de elevação; C-local se o teste humano provar que o pallet **já afunda parado e frozen** (nesse caso o problema é a colisão/modelo, e nenhum modelo de carry resolve).

## 7. O que NÃO é decidido aqui

- Troca do modelo `hei_prop_carrier_cargo_04b` (hipótese não confirmada de ausência de vão para garfos).
- Mudança de economia ou inventário.
- Remoção de módulos legados.

**J2 APPROVAL REQUIRED: YES** para qualquer implementação.
