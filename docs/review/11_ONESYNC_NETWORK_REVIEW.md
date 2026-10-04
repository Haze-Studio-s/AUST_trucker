# 11 — OneSync / Network Review

**ANALYZED HEAD: `c9d9187`.** Revisão **conceitual** a partir do código; **nada foi testado em runtime**. Classificação: **SAFE** (o código trata explicitamente), **RISK** (lacuna evidente no código), **UNKNOWN** (depende de comportamento do FiveM/OneSync que não foi verificado), **RUNTIME PROOF REQUIRED** (só um teste multi-jogador decide).

## 1. Primitivas de rede usadas pelo AUST

| Primitiva | Onde | Observação |
|---|---|---|
| `NetworkSetEntityOwner` + `SetNetworkIdCanMigrate(netId, false)` | `LockEntityNetworkOwner` (`server/main.lua:51-67`), em `pcall` | única "âncora" de dono; chamada no servidor para truck, trailer, forklift, handler, container, carros, pallets; **não** no hose, no forklift de emergência, nem no caminhão LC quick job |
| `NetworkRequestControlOfEntity` / `NetworkHasControlOfEntity` | cliente (`polarixSyncPallets`, `SnapPalletToCurrentSlot`, `StartAssistedAttach` no PR #9) | espera ativa de 1,5–2 s; sem tratamento do caso "não obteve" além de seguir |
| `SetEntityOrphanMode` | **nenhuma ocorrência no repositório** | comportamento de entidades órfãs fica no padrão do motor |
| `SetEntityDistanceCullingRadius(pObj, 0.0)` | spawn de pallets (`sv/main:1043`) | **semântica não verificada** |
| `NetworkUseHighPrecisionBlending` / `NetworkSetObjectForceStaticBlend` | **não usadas** (Don usa) | candidatos para suavizar observadores; efeito **não verificado** |
| StateBags | trailer: `loadedSlots`, `loadedForklift`; veículo: `activeJobData`; player: `activeJobId`; flatbed: `bedProp/attachedVehicle/bedLowered/bedMoving`; cargo: `ct_vulnerable`; pallets legados: `forklift_owner/forklift_location` | **vários são escritos pelo cliente** (`loadedSlots`, `loadedForklift`, flatbed, `ct_vulnerable`, `forklift_owner`) |
| `AddStateBagChangeHandler` | `loadedSlots`/`loadedForklift` (`cl/main:3214/3224`), `attachedVehicle` (`flatbed.client:390`), `ct_vulnerable` | único mecanismo de reconstrução para observadores |

## 2. Cenários

**PLAYER A** = dono/operador; **PLAYER B** = observador; **PLAYER C** = entra depois (late join).

### 2.1 Pallet carregado nos garfos (fluxo atual: Havok até 0,35 m, depois attach)

| Evento | Resultado | Classe |
|---|---|---|
| A levanta o pallet | O pallet é networked, dono travado em A; a pose vem por rede. Durante a janela dinâmica o `Freeze/Dynamic/ActivatePhysics` é aplicado **só no cliente de A**; B pode ver o pallet "solto" até o estado propagar | **RISK**; **RUNTIME PROOF REQUIRED** |
| Attach do pallet ao forklift (osso dos garfos) | Replicação do attach de entidade networked a veículo networked é padrão do OneSync; comportamento com B fora do alcance de streaming não verificado | **UNKNOWN** |
| B se aproxima / stream in | B vê o pallet pela rede; nenhum handler reconstrói o estado "nos garfos" | **UNKNOWN** |
| A desconecta com o pallet nos garfos | Polarix: lobby apagado na hora (`sv/main:2414`) → pallets apagados; PR #9: `PalletRegistry.Recover` só atualiza o registro | **SAFE** para entidades Polarix (apagadas); **RISK** de recuperação (não há respawn no `sourceSlot`) |
| A reconecta | Nenhum handler religa entidades; `ActiveJob` do cliente se perde; lobby já apagado | **RISK** |
| Troca de dono com o pallet anexado | `CanMigrate(false)` evita migração normal; troca forçada (queda do dono) não está coberta; cenário menos testado do OneSync | **UNKNOWN** |
| Resource restart | Servidor apaga lobbies e `PlayerJobEntities` (sem filtro `verified`); cliente varre o pool de objetos e apaga os de modelo rastreado (inclusive de outros scripts) | **RISK** (varredura ampla no cliente) |

### 2.2 Pallet estivado no trailer

| Evento | Resultado | Classe |
|---|---|---|
| Estiva | `SnapPalletToCurrentSlot`: bone 0 do trailer, `SetEntityCollision(false,false)`, `SetNetworkIdCanMigrate(false)`; statebag `loadedSlots` no trailer (servidor **e** cliente escrevem) | **SAFE** para o fluxo feliz |
| Trailer em movimento, B observa | O attach vem do estado da entidade; sem verificação de jitter | **UNKNOWN** |
| B stream out/in | O handler `loadedSlots` re-anexa para observadores (`cl/main:3150-3222`), mas cada escrita da tabela **inteira** dispara uma thread por slot (O(N²)) | **RISK** (desempenho) / **UNKNOWN** (corretude) |
| C late join | C processa o valor atual da statebag ao carregar o trailer; pallets são entidades normais | **UNKNOWN** |
| Pallet caído | `loadedSlots` nunca é limpo para pallets caídos; qualquer escrita posterior re-anexa todos os slots para todos os clientes | **RISK** |
| Trailer deletado no fim | Pallets apagados pelo servidor | **SAFE** |

### 2.3 Caminhão, trailer, forklift

| Cenário | Resultado | Classe |
|---|---|---|
| Dono A sai (queda) | Polarix: apaga trailer e caminhão não-próprio; caminhão próprio **permanece** com `activeJobData` obsoleto; LC quick job **vaza** (sem handler); aluguel: reembolso com defeito provável de ordem (ver 05) | **RISK** |
| Grace de 3 min × limpeza imediata | `events.lua:380` quer 3 min; `events.lua:1207` apaga na hora; efeito: o grace não recupera nada | **RISK** (conflito de handlers) |
| Forklift de emergência | criado sem lock, sem plate, sem chaves, e o cliente não recebe o novo netId | **RISK** |
| Owner migration em trailer/forklift em trânsito | `CanMigrate(false)`; o cliente reaplica attach do forklift a cada 1,5 s dirigindo | **UNKNOWN** |
| Streaming do trailer/truck no cliente | `WaitForNetworkEntity(netId, 4000)` sem retry (`cl/main:2523`) | **RISK** (jogador com streaming lento fica com entidade `nil`) |

### 2.4 Entidades criadas pelo cliente

Aluguel de caminhão, alvo/guardas do repo, flatbed do repo, handler/NPC do container handler, forklift/pallets do trade point e prop de parcel são **client-created networked** (`CreateVehicle(…,true,false)`, `CreateObject(…,true,true,true)`): sem dono travado, sem orphan mode, sem cleanup do servidor na queda (exceto aluguel e forklift do trade point). **RISK**; **RUNTIME PROOF REQUIRED** sobre o que acontece quando o criador sai.

### 2.5 Statebags escritas pelo cliente

`loadedSlots`, `loadedForklift`, `attachedVehicle`, `bedLowered`, `bedMoving`, `ct_vulnerable`, `forklift_owner`: qualquer cliente pode escrever statebags **replicadas** de entidades que ele controla; o servidor só verifica algumas (`forklift_owner` é checado e é forjável; flatbed tem validação cruzada no servidor para attach/detach). **RISK** (SEC-05, SEC-07, SEC-13).

## 3. Observadores específicos do pallet no PR #9 (desligado)

| Aspecto | Estado |
|---|---|
| Pallet permanece **frozen** até o attach | reduz a janela em que B vê física; **dono único e fixo** |
| Attach "preserva a pose do mundo" | evita salto; para observadores, o salto de representação depende do attach ser replicado |
| `palletConfirmCarry`/`Release`/`Recover` | estado lógico no servidor; **não há respawn físico** no `sourceSlot` ainda (só registro) |
| `NetworkUseHighPrecisionBlending` | **não aplicado** (exigiria handler de statebag em todos os clientes; não implementado) |
| Orphan mode | não definido |

## 4. Lacunas de rede do código atual (resumo)

1. **Nenhum `SetEntityOrphanMode`** em entidade servidor-criada: comportamento de órfãos depende do padrão do motor. **RUNTIME PROOF REQUIRED**
2. **Nenhum reconnect** de entidade ou de job.
3. **Statebags** replicadas escritas pelo cliente, sem validação.
4. **`CleanupCurrentJob` não restaura** `SetNetworkIdCanMigrate`, freeze de truck, nem statebags.
5. **Handlers de `playerDropped`** conflitantes.
6. **Varredura de pool** a cada resource stop apaga objetos locais do mesmo modelo de outros scripts.
7. **`SetEntityDistanceCullingRadius(…, 0.0)`**: semântica não verificada.

## 5. Plano de prova em runtime (mínimo)

| Teste | O que prova |
|---|---|
| A levanta pallet, B observa a 10 m e a 200 m | replicação do attach e do estado frozen/dynamic |
| A desconecta com pallet nos garfos; B e C observam | limpeza vs órfão |
| A reconecta durante transporte | perda de estado |
| Dois clientes tentam registrar o mesmo carro estacionado (`registerJobEntities`) | SEC-01 |
| Resource restart com 2 jogadores em jobs | varredura de objetos e entidades órfãs |
| Trailer em movimento com 5 pallets, B segue a 30 m | jitter e re-attach por statebag |
