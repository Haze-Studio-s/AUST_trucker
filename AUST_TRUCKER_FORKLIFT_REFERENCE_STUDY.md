# AUST_TRUCKER — Estudo comparativo: forklift / pallets

Status: **leitura de código COMPLETA nos 4 repositórios; SEM validação in-game** (nenhuma recomendação abaixo foi executada no FiveM). Nenhum código do AUST foi alterado.

Convenção: notas 0–10, **10 = melhor** (inclusive em "complexidade": 10 = mais simples e "exploit": 10 = menor superfície). As notas são julgamento de engenharia a partir do código lido, não medição.

## 1. Repositórios estudados

| Repo | Commit lido | Data | Papel |
|---|---|---|---|
| derPolarix/polarix_truckerjob | `d11dcd1` | 2026-10-03 | Referência principal (o AUST é derivado dele) |
| DonHulieo/don-forklift | `4adaf7a` (v1.3.1) | 2024-12-11 | Física pura, servidor cria o objeto |
| Mobius1/esx_forklift | `9edc213` | 2020-09-21 | Física pura, minijogo ESX clássico |
| xDope7137/forklift | `1718e31` | 2026-07-28 | Histórico/gameplay apenas |

Limites: o `ESX.Game.SpawnObject` do Mobius1 vive no framework, não no repo (não verificado se é networked). Os `.ydr` do Polarix existem em `stream/`, mas não abri a colisão deles.

## 2. Arquivos estudados

- Polarix: `client/modules/cargo.lua` (776 linhas, inteiro), `client/modules/forklift.lua` (357, inteiro), `server/modules/party_mission.lua` (claim/load/dropout/cargo state), `config/shared.lua`, `config/client.lua`.
  - Achado: **`forklift.lua` do Polarix NÃO tem lógica de pallet.** É só deploy/stow do forklift no trailer. Toda a mecânica de pickup/attach/load está em `cargo.lua`.
- Don: `client/main.lua` (spawn, `await_load`, entrega), `server/main.lua` (create/remove/finish), `shared/config.lua` (modelos).
- ESX: `client/main.lua` (SpawnPallet, thread de entrega, ValidDrop), `client/utils.lua`, `server/main.lua`.
- xDope: `forklift_c.lua`, `forklift_sv.lua`.
- AUST: `client/modules/forklift.lua`, `client/main.lua`, `server/main.lua` em `origin/main` (`e5ce6cc`), mais o diff do J2 de hoje.

## 3. Arquitetura de cada projeto

| Pergunta | Polarix | Don | ESX (Mobius1) | xDope | AUST (main hoje) |
|---|---|---|---|---|---|
| Como o pallet nasce | `CreateObject(..., false,false,false)` em **cada cliente** (determinístico) | Servidor: `CreateObjectNoOffset(..., true,false,false)` | `ESX.Game.SpawnObject` no cliente | `CreateObject(..., true,true,true)` no cliente | Servidor: `CreateObject(..., true,true,false)` em `z+0.15`, `Freeze(true)` |
| Networked ou local | **Local** (não networked) | Networked, dono = motorista (`SetEntityIgnoreRequestControlFilter`) | Provavelmente networked (não verificado) | Networked | Networked, dono travado no motorista |
| Frozen ou dynamic | **Frozen** | **Dynamic** (`SetEntityDynamic(true)`) | Dynamic (padrão) | Dynamic, `Freeze(false)` | Frozen no spawn, descongela no engate |
| Colisão | `SetEntityCollision(true,true)` | padrão | padrão | padrão | ligada |
| Gravidade | n/a (frozen) | padrão | padrão | padrão | desligada no `ground_engaged` (J2) |
| Placement no chão | `PlaceObjectOnGroundProperly` | `PlaceObjectOnGroundProperly` (cliente, após o objeto aparecer) | `PlaceObjectOnGroundProperly`, **adiado até o pallet estar a < 50 m** | `z - 0.95` fixo | raycast + `groundZ + minDim` (J2) |
| Detecção dos garfos | distância ao osso `forks_attach`: horizontal ≤ 0,7 m, vertical −0,08…+0,18 | nenhuma (garfo empurra por física) | `IsEntityAtEntity` (caixa 3×3×3) forklift↔pallet | nenhuma | caixa relativa ao forklift (x ≤ 1,3; y 0,1–3,5; z ≤ 0,9) |
| Detecção do pickup | **tecla** com candidato válido | nenhuma (só observa a entrega) | `IsEntityInAir(pallet)` = "lifted" | proximidade | automático por zLift ≥ 0,35 (J2) |
| Física real nos garfos | **Não** | **Sim**, totalmente | **Sim**, totalmente | **Sim** | **Sim** até 0,35 m, depois attach |
| `AttachEntityToEntity` | Sim, no osso `forks_attach`, offset `(0,0,0.05)` | Não (só em ped/cadeira) | Não | Não | Sim, a partir de 0,35 m |
| Quando faz attach | **No chão, no instante do pickup** | nunca | nunca | nunca | depois de erguer 0,35 m pela Havok |
| Remove/substitui o pallet do chão | **Sim**: `DeleteEntity(source)` + `CreateObject` novo | Deleta ao entregar | Deleta ao entregar | Deleta ao entregar | Não: mesmo objeto |
| Sincroniza outros jogadores | Operador: prop local; party: prop decorativo local reconstruído por polling de 3 s | Nativo do OneSync (networked) | Nativo | Nativo | Nativo + statebags |
| Pallet no trailer | `DetachEntity` + `AttachEntityToEntity(trailer, bone 0, offset do slot)` + `SetEntityNoCollisionEntity` | Distância ≤ 3 m ao porta-malas | Zona de entrega (sem trailer): ≤ 0,5 m + heading ±1° + fora do ar | Distância ≤ 2 m | `SnapPalletToCurrentSlot` (bone 0, offset do slot / PropEditor) |
| Evita duplicação | Servidor `slots[i]` (party) / pool de claim (solo); evento `partyGroundPalletTaken` | Statebag `owner` + `RemoveEntity` valida dono | `Player.Pallet` único | `paczuszka` global único | `usedPallets`/`slotPallets` (PR #9) |
| Streaming | Re-spawna local por proximidade (< 40 m) e por evento `Freed` | `NetworkDoesEntityExistWithNetworkId` | Adia `PlaceObjectOnGround` até < 50 m | nenhum | `WaitForNetworkEntity(8000)` |
| Colisão não carregada | Não trata (frozen + local reduz o risco) | Não trata | **Trata**, com comentário explícito: "se o pallet está longe, a colisão pode não estar carregada e ele cai pelo chão" | Não trata | `RequestCollisionAtCoord` + timeout 3,5 s (J2/meu 2A) |
| Ownership | n/a (local) | `repeat Wait until NetworkGetEntityOwner == player` | nenhum | nenhum | `LockEntityNetworkOwner` + `SetNetworkIdCanMigrate(false)` |
| Validação server-side | Party: claim/load com CAS por slot, sem checar distância. Solo: só o pool de claim | Dono do objeto/almoxarifado em create/remove, kick em mismatch. **Não valida `loads` nem tempo de forma robusta** | `getPaid(amount)` aceita **qualquer valor** do cliente | `wykonanieMisji(premia)` aceita valor do cliente | `PalletRegistry` (PR #9): netId, slot, retry, distância pallet↔trailer |

## 4. Fluxo de pickup de cada um

**Polarix:** frozen local no chão → candidato (horizontal ≤ 0,7, vertical −0,08…+0,18 do osso) → prompt → tecla → `claimGroundPallet` (party) → `MissionPallets[slot]=nil` → `DeleteEntity(ground)` → `CreateObject` local novo → `AttachEntityToEntity(prop, forklift, forks_attach, 0,0,0.05, 0,0,0, false,false,false,false,2,true)`. O parâmetro de colisão é `false`, então o prop carregado **não colide com o forklift**.

**Don / ESX / xDope:** nenhum "pickup". O jogador enfia os garfos e a Havok ergue o objeto. O sistema só observa (distância, `IsEntityInAir`, heading) e paga pela entrega.

**AUST:** `STAGED_FROZEN → GROUND_ENGAGED (unfreeze, dynamic, sem gravidade) → [Havok ergue 0,35 m] → ATTACHED_TO_FORKS → STOWED`.

## 5. Física usada

- Polarix: **nenhuma física no pallet.** Frozen no chão; depois, prop kinematic anexado. Zero janela de Havok.
- Don/ESX/xDope: física real o tempo todo. Aceitam o jitter porque o minijogo é simples (um pallet, sem trailer físico, sem multiplayer cooperativo).
- AUST: híbrido com uma **janela de Havok de 0 → 0,35 m** com gravidade desligada. É o pior dos dois mundos: tem o risco da física sem a naturalidade de gravidade ligada.

## 6. Networking

- Polarix: ground local por cliente (cada um cria o seu), carregado local no operador, decorativo para a party. O servidor guarda só estado lógico. Consequências: sem migração de dono, sem sink por colisão do servidor, sem catapulta de ownership. Custo: um jogador **fora da party não vê** o pallet nos garfos, e a consistência visual depende de polling (3 s) e de eventos.
- Don: servidor cria e o dono é forçado para o motorista; a Havok roda no cliente dono.
- AUST: igual ao Don no desenho de rede, mas com o dono travado e `CanMigrate(false)`, o que ajuda, e com `FreezeEntityPosition` só aplicado pelo cliente dono (outro cliente pode ver o pallet "solto" até o estado propagar).

## 7. Server authority

| | Estado lógico | Máquina | Proximidade | CAS |
|---|---|---|---|---|
| Polarix party | `slots[i] = {state, identifier,...}` | free→carried→loaded→delivered; dropout → free | **não** | por slot nil |
| Polarix solo | contagem de claim | — | não | pool |
| Don | statebags de dono | — | só na criação (50 m do almoxarifado) | não |
| ESX/xDope | nenhum | — | — | — |
| AUST | `usedPallets`, `slotPallets`, `usedSlots` | contagem + stage do lobby | pallet↔trailer ≤ 60 m | retry detectado |

## 8. Pontos fortes

- **Polarix:** pallet de chão nunca sofre física; swap de representação elimina a janela de risco; state machine de slots no servidor com dropout/recuperação; reconcile periódico auto-curativo.
- **Don:** servidor é dono do ciclo de vida do objeto e valida o dono em remove/create; statebags com `owner`/`warehouse`.
- **ESX:** o único que **documenta** o modo de falha que o AUST sofre (colisão não carregada → pallet cai) e o evita adiando o snap.
- **xDope:** nada de segurança; só referência de gameplay (reboque NPC, janela de bônus por tempo).

## 9. Pontos fracos

- **Polarix:** sem validação de distância no claim/load; o pickup "teleporta" para os garfos sem elevação física (menos realismo); prop local não aparece para quem não é party; `ForkliftAttachOffset` é um único offset global.
- **Don:** `finish_mission` confia em `loads` e `health` do cliente (rejeita só `health > 1`). Pagamento inflável.
- **ESX:** `getPaid(amount)` sem nenhuma validação: qualquer cliente se paga o que quiser.
- **xDope:** idem, bônus vem do cliente; `Citizen.Wait` em laços de 2–4 ms.
- **AUST:** janela Havok; thresholds mudando a cada commit (0,10 → 0,35); offset de garfo fixo `(0, 0.95, -0.05)`; fallback de osso `ForkBoneIndex or 3` (índice mágico); a mudança de `FreezeEntityPosition(false)` + `SetEntityDynamic(false)` no momento do attach pode causar tranco.

## 10. Técnicas reutilizáveis

1. Pallet de chão **frozen e sem Havok** até o pickup (Polarix).
2. **Swap de representação** ou attach único no osso real dos garfos, com `collision=false` e `SetEntityNoCollisionEntity` (Polarix).
3. Estado lógico por slot no servidor com dropout que devolve o slot ao chão (Polarix).
4. Reconcile periódico do visual a partir do estado do servidor (Polarix), para reconnect e late join.
5. Adiar `PlaceObjectOnGroundProperly` até o jogador estar perto, quando a colisão já carregou (ESX).
6. Dono do objeto em statebag + validação do dono em remoção (Don).
7. Caixa de detecção por entidade (`IsEntityAtEntity`) como filtro barato antes de checagens finas (ESX).

## 11. Técnicas que NÃO devemos copiar

- Pagamento ou contagem confiados ao cliente (Don, ESX, xDope).
- Física pura sem staging para um fluxo cooperativo com trailer (Don, ESX).
- `CreateObject` local sem registro no servidor para pallets que valem dinheiro. O Polarix só se salva por manter o estado lógico no servidor; o AUST tem payout e precisa disso.
- Polarix sem checagem de proximidade no claim.
- Prop local invisível para não-party, se o AUST quiser que outros jogadores vejam a carga.
- Thresholds em "m" da posição do pallet sob Havok (ruído).

## 12. Matriz A/B/C/D (10 = melhor)

| Critério | A Havok real | B Attach direto | C Swap de representação | D Híbrido (kinematic) |
|---|---|---|---|---|
| Realismo | 10 | 4 | 5 | 8 |
| Estabilidade | 3 | 9 | 10 | 8 |
| OneSync | 4 | 8 | 9 | 8 |
| Multiplayer | 5 | 8 | 6 (8 com reconstrução por statebag) | 8 |
| Desync | 3 | 8 | 8 | 7 |
| Performance | 5 | 9 | 8 | 8 |
| Superfície de exploit | 4 | 6 | 8 | 7 |
| Streaming | 4 | 8 | 6 | 7 |
| Reconnect | 4 | 7 | 8 | 7 |
| Simplicidade | 6 | 9 | 4 | 6 |
| **Média** | **4,8** | **7,6** | **7,2** | **7,4** |

Leitura: **B e D empatam em números, mas D preserva a sensação física que você quer e B não.** C tem a melhor estabilidade, ao custo de complexidade e de depender de reconstrução visual. A é o estado atual e a pior nota em estabilidade.

## 13. Comparação com o AUST atual

O AUST já tem a **estrutura do Polarix** (frozen no chão, attach no osso, slot no trailer) e acrescentou, por cima, uma janela de física que o Polarix evita deliberadamente. A janela `GROUND_ENGAGED → ATTACHED_TO_FORKS` é onde:

- o pallet está `Dynamic` e sem gravidade, empurrado só por contato com os garfos;
- o objeto é networked e a Havok pode mudar de dono/estado;
- um modelo sem aberturas para garfo (**hipótese**: `hei_prop_carrier_cargo_04b` é prop de carga de porta-aviões, não um pallet com vão) colide com a malha dos garfos e gera a catapulta.

Essa hipótese **não está confirmada**; ela se testa com `/palletdebug` (colisão/bounds do asset, pergunta B do roteiro).

**Resposta explícita: o Polarix usa o MESMO objeto físico do chão nos garfos? NÃO.**
O pallet do chão é um objeto local frozen; no pickup ele é deletado e um **prop novo** é criado e anexado ao osso. A vantagem de trocar a representação:

- o objeto do chão nunca sai do estado frozen, então não existe sinking nem tunneling;
- o prop anexado nasce já kinematic e com colisão desligada contra o forklift, então não existe catapulta;
- como nenhum dos dois é networked, não há migração de dono nem jitter de ownership;
- o preço é perder a elevação física (o pallet "pula" para os garfos) e a visibilidade para quem não é party.

## 14. Recomendação arquitetural

### Modelo D, na variante **kinematic** ("D-K")

A ideia central, que o pedido original não separou: **detectar a primeira elevação pelos garfos, não pelo pallet.** O pallet fica **frozen o tempo todo** até o attach. O que sobe é o osso dos garfos, e isso dá para medir sem Havok no pallet:

```
elevação = Z do osso 'forks' no referencial do forklift − Z de repouso do osso
```

Medida no referencial local do forklift (`GetOffsetFromEntityGivenWorldCoords`), ela é imune a rampa, a inclinação e ao ruído de contato do pallet.

Fluxo:

```
STAGED_FROZEN
  ↓ garfos alinhados (X, heading) e inseridos (Y)
FORKS_ALIGNED
  ↓ altura Z dentro da janela do vão, velocidade baixa
FORKS_ENGAGED          (servidor: STAGED → CLAIMED, com distância validada)
  ↓ garfos sobem ≥ limiar, N ticks seguidos
ASSISTED_ATTACH        (zero velocity; sem colisão pallet↔forklift; dynamic=false; gravity=false;
                        controle de rede; Attach no osso real, offset calibrado)
  ↓
ATTACHED_TO_FORKS      (servidor: CLAIMED → CARRIED)
  ↓
TRAILER_SLOT_VALID
  ↓
STOWED_ON_TRAILER      (servidor: CARRIED → STOWED)
```

Com isso a Havok **nunca carrega o pallet**. Preserva a sensação (o pallet sobe junto com os garfos) sem a janela de 0,35 m.

### Thresholds (comparados)

| Limiar | Veredito |
|---|---|
| 0,05 m | Só serve na medida **cinemática do osso**; sob Havok é ruído de suspensão/contato (falso positivo) |
| **0,08 m** | **Recomendado**, com 3 ticks consecutivos (~150 ms a 50 ms/tick) e velocidade do forklift < 1,5 m/s; é perceptível, mas ainda abaixo do "pop" visível |
| 0,10 m | Aceitável, é o fallback se 0,08 gerar falso positivo em rampa |
| 0,15 m | O pallet já "pendurou" visivelmente antes do attach; início de pop |
| 0,35 m (atual) | Sem motivo técnico para a Havok carregar 35 cm; é onde moram tranco e migração de dono |

Histerese: só reverter se a elevação cair < 0,03 m **antes** do attach; depois do attach não há volta, só detach explícito.

### Calibração (PropEditor 6DoF)

Separar duas tabelas, não reutilizar offset de trailer no forklift:

- `forklift ↔ pallet`: chave `{forkliftModel, palletModel, bone='forks'}` → `x,y,z,pitch,roll,yaw`
- `trailer ↔ pallet`: chave `{trailerModel, palletModel, slot}` → idem, bone 0

Hoje o `GetVehiclePropOffset` do J2 usa `Config.VehiclePropOffsets[veh][prop]` sem `kind` nem `bone`; um offset de garfo e um de slot compartilhariam o mesmo formato. Recomendo acrescentar `kind` e `bone`, e **falhar com log** (em vez de cair em `(0, 0.95, -0.05)` ou em `ForkBoneIndex or 3`) quando não houver calibração.

### Networking: recomendação

| Opção | Prós | Contras | Veredito |
|---|---|---|---|
| A: manter networked | menor mudança; todos veem | exige dono estável | **Escolha da Fase 1** |
| B: local do operador + decorativo | estável | observadores só por reconstrução | não agora |
| C: statebag lógico + visual reconstruído | melhor para reconnect/late join | mais código, polling | **Evolução da Fase 2 se a A falhar** |
| D: uma única entidade networked attached | simples | igual à A | = A |

Justificativa: com D-K a entidade networked só muda de estado **uma vez** (frozen → attached), com dono já travado no motorista. A instabilidade de OneSync que o Polarix evita vem da fase **solta** que o D-K elimina. Sem essa fase, não há razão forte para mudar a arquitetura de rede agora. Se o teste mostrar flicker para observadores no attach, aí sim migrar para C.

### Autoridade do servidor

Estados: `STAGED → CLAIMED → CARRIED → STOWED → DELIVERED`, mais `FREED` (volta a `STAGED` quando o carregador cai/desconecta ou o forklift é destruído, como o `HandleMemberDropout` do Polarix).

Registro por pallet: `palletId, slotId, jobId, state, carrier, trailer, trailerSlot, version`.

- `claim(palletId, forkliftNetId, reqId)`: exige `state == STAGED`; o forklift existe e o motorista é quem pede; distância do ped ao pallet ≤ X; **CAS** por `version`.
- `stow(palletId, trailerSlot, reqId)`: exige `state == CARRIED` e `carrier == src`; trailer é o do lobby; slot livre; distância pallet↔trailer.
- Idempotência por `reqId`: repetir a mesma requisição devolve o mesmo resultado sem recontar (o `PalletRegistry` do PR #9 já faz isso para `palletLoaded`).
- **O visual nunca define pagamento ou progresso**: o `completed` e o payout leem só `STOWED/DELIVERED` do servidor.

O Polarix **não** valida proximidade; o AUST deve (é lacuna do Polarix, não padrão a copiar).

## 15. Plano de implementação (NÃO iniciado)

Pré-requisito: o PR #9 (telemetria + registry) entra na `main` e o teste humano responde às 7 perguntas. **Sem isso, a hipótese de modelo/colisão não está confirmada.**

1. **Fase E1 (só telemetria nova):** `pallet_debug` registra elevação do osso, estado e velocidade do garfo. Sem mudar física.
2. **Fase E2 (servidor):** estados `STAGED/CLAIMED/CARRIED/STOWED/DELIVERED/FREED` no `pallet_registry.lua`, com `claim`, `stow`, `reqId` e dropout.
3. **Fase E3 (cliente):** substituir `GROUND_ENGAGED`/zLift por `FORKS_ALIGNED → FORKS_ENGAGED → ASSISTED_ATTACH`, mantendo o pallet frozen até o attach; threshold em `Config`.
4. **Fase E4 (calibração):** `kind`/`bone` no PropEditor e no `GetVehiclePropOffset`; tabela forklift↔pallet separada da de trailer.
5. **Fase E5 (rede):** só se o teste mostrar flicker; evoluir para C.

## 16. Plano de testes

Automático (lupa/mocks): transições de estado do servidor, CAS, idempotência de `reqId`, dropout, rejeição de claim fora de alcance; máquina de estados do cliente com sequência de elevação simulada (limiar, N ticks, histerese).

Humano (FiveM):

1. Pallet parado 60 s: sem queda, sem FIRST_DROP.
2. Garfos inseridos sem subir: pallet segue frozen e imóvel.
3. Subir 5 cm / 8 cm / 12 cm: attach no limiar, sem tranco.
4. Subir e descer antes do limiar: nenhum attach.
5. Dois jogadores: um pega, o outro vê o pallet subir; segundo claim é rejeitado.
6. Carregador desconecta com pallet nos garfos: pallet volta ao chão no slot.
7. Reconnect do dono no meio do transporte.
8. Stow no trailer: heading/offset no slot; progresso só conta uma vez (repetir o evento).
9. Rampa e piso inclinado: sem falso positivo de elevação.
10. Comparar `/palletdebug` antes e depois (valores de `heightAboveGround`, `FALLING`).

## Riscos e lacunas

- Hipótese do modelo sem vão para os garfos: **não confirmada**.
- Garfos podem colidir com um pallet frozen/estático (mesh sólida): pode empurrar o forklift. Testar antes de decidir entre D-K e C.
- `GetEntityBoneIndexByName(forklift,'forks')` e `'forks_attach'` precisam existir no modelo usado; o fallback por índice 3 é frágil.
- Attach de entidade networked para quem não é o dono pode atrasar: medir.
- O J2 continua mudando `forklift.lua` na `main`; este estudo foi feito sobre `e5ce6cc`.
