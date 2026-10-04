# 13 — Performance Review

**ANALYZED HEAD: `c9d9187`.** Estimativas **estáticas** (leitura de código); **nada foi perfilado**. Classes: **A** = ALWAYS ACTIVE, **J** = JOB ONLY, **P** = PROXIMITY, **AD** = ADMIN ONLY, **D** = DEBUG ONLY. Propostas descrevem direção, **não alteram código**.

## 1. Resumo

- 3 laços do cliente respondem pela maior parte do custo previsível: o escudo de colisão (`client/main.lua:1293`), o desenho das cintas (`:1030`) e o `updateHUD` via NUI (`hud.client.lua:391`).
- No servidor **não há DB por tick**: todo laço é ≥ 3 s; SQL em laço só existe em crons de 5–30 min.
- Não há uso de `GlobalState`. Não há `TriggerClientEvent(…, -1)` em laço; broadcasts são orientados a evento (exceção: `jobsUpdated` a cada 30 min).
- `SendNUIMessage` aparece 104 vezes no cliente; os que fazem polling são `hud.client.lua:391` (500 ms, sempre), `client.lua:2138` (5 s/15 s) e o par por frame do editor de offsets (admin).

## 2. Cliente

| arquivo:linha | O que faz | Período | Gate | Classe | Risco | Alternativa (descrição) |
|---|---|---|---|---|---|---|
| `client/main.lua:1293-1361` | "Havok shield": a cada iteração `GetGamePool('CVehicle')`, por veículo `GetVehicleClass`, `GetEntityCoords` e leitura de statebag; aplica NoCollision a pallets/trailer/caminhão | 250 ms em repouso; **0** quando há carga (inclui trailers de observadores a ≤ 35 m) | nenhum: roda para **todo jogador** | A (por frame com carga) | **ALTO**: varredura do pool ~4×/s para todos; por frame com carga | Registro por evento dos trailers carregados (os handlers de `loadedSlots`/`loadedForklift` em `:3214`/`:3224` já veem todo trailer carregado) e laço só sobre esse conjunto; dormir ≥ 500 ms quando vazio; `Wait(0)` só a ≤ 35 m |
| `client/main.lua:1030-1056` (com `:975-1026`) | Desenha as cintas: ~12 `DrawPoly` por cinta | 500 ms; **0** com trailer a ≤ 100 m | trailer existe e há pallets | J | MÉD-ALTO | Reduzir raio para 40–50 m; desenhar só no campo de visão; ou prop estático |
| `client/hud.client.lua:391-396` | `SendNUIMessage updateHUD` com tabela | 500 ms | só `Config.TruckSimulation.HUD.Enabled`; **envia mesmo fora do caminhão** | A | MÉD-BAIXO | Enviar só na mudança; um `visible=false` na transição |
| `client/modules/offset_editor.lua:470, 929, 1387` | Gizmo: `DisableAllControlActions` e `SendNUIMessage setCameraPosition` **por frame** | 0 | `IsCalibrating` (callbacks admin) | AD | MÉD enquanto ativo | Enviar câmera só quando mudar |
| `client/modules/forklift.lua:632-973` (`:942` via `:79-86`) | Laço da operação; `GetNearestGroundPallet` faz 6× `GetClosestObjectOfType` quando nenhum pallet da missão está mais perto | 150 ms; 0 perto de pallet/slot | `OperationActive` | J | MÉD (~6,7 Hz × 6 varreduras) | Usar o fallback por modelo só com a lista da missão vazia |
| `client/main.lua:1653-1800` | G-force/física de carga/freeze + sync anchor | 500 ms parado; cadência dirigindo não totalmente lida | `STEP_8_IN_TRANSIT` | J | MÉD | Alternar por evento (dirigindo/parado) |
| `client/client.lua:2020-2065` | Marcador do HQ (laço sobre `hqLocations`, `DrawMarker` + `DrawText3D`) | 1500 ms; 0 a ≤ 35 m | nenhum | A, P | BAIXO-MÉD | `lib.points`, como o resto do arquivo |
| `client/illegal.client.lua:134-157` | Reavalia toda placa ilegal; `ox_target:addLocalEntity` repetido a cada 5 s | 5000 ms | `knownIllegalPlates` não vazio (o laço roda sempre) | A, J | MÉD | Rastrear `targeted[vehicle]` e adicionar uma vez |
| `client/cargo_theft.client.lua:42` | `GetGamePool('CVehicle')` em `GetVehicleByPlate` | sob demanda | eventos | J | BAIXO-MÉD | `GetVehicleWithNumberPlate` (já usado em `illegal.client.lua:140`) |
| `client/flatbed.client.lua:390-428` | Handler `attachedVehicle`; descarga varre o pool | evento | todos os flatbeds | A (evento) | BAIXO-MÉD | Guardar o netId do veículo anexado |
| `client/main.lua:3214-3235` + `server/main.lua:1562-1580` | `loadedSlots` regravado **inteiro** a cada pallet; cada escrita roda o handler de todos os slots (uma thread por slot, até 5 s de polling de 100 ms) | evento | todos | J | MÉD (O(N²) com pallets) | Delta por slot |
| `client/hud.client.lua:148, 204, 236` | Detecção de veículo, combustível, fadiga | 1000 ms | pulam fora do caminhão | A (leve) | BAIXO | `cache.vehicle` por evento; dormir mais fora do caminhão |
| `client/convoy.client.lua:199, 272` | Texto de overlay (CB, GPS) desenhado a cada 500/1000 ms | 500–1000 ms | log não vazio | A (ocioso barato) | BAIXO; **o texto pisca** (draw natives pedem chamada por frame) | `Wait(0)` só enquanto houver mensagem |
| `client/main.lua:2864-2945`, `client.lua:3084-3425`, `main.lua:555-640, 2125-2200`, `zones.lua:99-130` | Marcadores/zonas por proximidade | 2 ms só dentro do raio, 1000–2000 ms fora, ou `lib.points` | job/proximidade | J, P | BAIXO | OK; calcular alinhamento a ~10 Hz e desenhar por frame |
| `client/main.lua:268` | `DrawMarker 20` do objetivo em `lib.points nearby` | por frame a ≤ 150 m | objetivo ativo | J, P | BAIXO-MÉD | Reduzir raio para 60–80 m |
| `client/modules/pallet_debug.lua:147-155` | Amostrador de telemetria | 1000 ms | retorna se `Config.Debug` falso | D | BAIXO | OK |

Bem otimizados (citados pela auditoria): `lib.points` para marcadores (`zones.lua:4`, `client.lua:1222/1296/3014`, `main.lua:268/551/2125`); `convoy.client.lua:243-251` (500 ms fora, 0 só dentro); `container_handler.client.lua:220-364`, `reach_stacker.lua:93-206`, `car_carrier.lua:149-215` (250–500 ms, 0 perto); `npc_driver.client.lua:105-121` (zona esfera).

## 3. Servidor

| arquivo:linha | O que faz | Período | Classe | Risco | Alternativa |
|---|---|---|---|---|---|
| `truck_rental_service.lua:357-372` (+ `:91-107`) | Amostrador de saúde dos aluguéis; sem `netId`, `GetAllVehicles()` e varredura por modelo/placa **por aluguel** | 3000 ms | A (barato ocioso), J | MÉD | Guardar o netId no aluguel; amostrar a cada 10–15 s |
| `server/main.lua:456-497` (`IsSpawnPointClear`) | `GetAllVehicles()` + `IsVehicleOccupiedByPlayer` (que percorre `GetPlayers()`) | por spawn | J | MÉD | Filtrar por distância antes (já filtra) e reduzir a lista |
| `events.lua:903-914` | Geração de jobs + `TriggerClientEvent jobsUpdated -1` | 30 min (`Config.JobGeneration.refreshInterval = 1800000`, `config.lua:693`; o `config.lua:55` é `Config.Contracts.refreshInterval`, não usado por este laço) | A | BAIXO | Notificar só quem tem a NUI aberta; INSERT em lote (`job_service.lua:195-201`) |
| `industry_service.lua:217-248` | Produção primária: um UPDATE por indústria + `RunOperationalCosts` por dono | 60 s / 10 min | A | BAIXO-MÉD | Transação em lote |
| `economy_service.lua:60-98` | Preço: um UPDATE por linha, a cada 20 min e depois de cada compra/venda (debounce 5 s) | 20 min + rajadas | A | MÉD | Escrever só linhas que mudaram; aumentar o debounce |
| `convoy_service.lua:22` | `SetInterval` por convoy: lista de posições para cada membro | 3 s | J | MÉD | Transmitir só com mudança; as posições só atualizam a cada 30 s no cliente. **Argumentos de `SetInterval` em ordem diferente da do ox_lib local** (ver `12_SECURITY_AUTHORITY_REVIEW.md`, SEC-25) |
| `npc_driver_service.lua:132-195` | `ProcessTick`: por motorista ocioso, 1–2 SELECTs + `MySQL.update.await` | 5 min | A | MÉD (escala com nº de motoristas) | Pré-buscar jobs e atribuir em memória |
| `callbacks.lua:105, 720` | Barreira de queries paralelas (`getInitialData`), polling `Wait(0)` até 500 ticks | por abertura de NUI | J | BAIXO-MÉD (15+ queries por abertura) | Cache das partes estáticas |
| `callbacks.lua:392, 402` (leaderboard) | Duas queries sobre a tabela inexistente `trucker_company`, falham em `pcall` a cada `getInitialData` | por abertura | A | BAIXO (desperdício) | Corrigir o nome ou remover |
| `callbacks.lua:1731`; `main.lua:1328` | `getTrailerOffsetsForModel` recarrega do banco a cada chamada (inclusive por spawn) | por chamada | J | BAIXO-MÉD | Usar o cache (`AdminService.TrailerOffsets`) |
| `server/main.lua:1562-1580` | `Entity().state:set('loadedSlots', tabelaInteira, true)` a cada pallet | evento | J | BAIXO-MÉD | Delta por slot |
| `repo_service.lua:15-30` | `BroadcastAvailableOrders` percorre `GetPlayers()` + `GetByMember` por jogador | evento | A (evento) | BAIXO-MÉD | Conjunto de agentes online |
| demais crons | loans, shop stock, repo, parcel, simulação (`pcall` em volta) | 1–30 min | A | BAIXO | OK |

## 4. Top 15 hotspots (ordem de prioridade)

1. `client/main.lua:1293-1361`: varredura do pool de veículos para todo jogador.
2. `client/main.lua:1030-1056`: `DrawPoly` por cinta/pallet a ≤ 100 m.
3. `client/hud.client.lua:391-396`: NUI a cada 500 ms para todos.
4. `client/modules/offset_editor.lua:470/929/1387`: NUI por frame (admin).
5. `client/modules/forklift.lua:942` via `:79-86`: 6 varreduras por modelo a 150 ms.
6. `loadedSlots` regravado inteiro (O(N²)).
7. `client/illegal.client.lua:134-157`: re-adiciona `ox_target` a cada 5 s.
8. `truck_rental_service.lua:357` + `:91-107`.
9. `convoy_service.lua:22` (e ordem dos argumentos).
10. `npc_driver_service.lua:132-195`.
11. `economy_service.lua:60-98`.
12. `client/client.lua:2020-2065`: HQ sempre ativo.
13. `events.lua:903-914`: broadcast de 30 min a todos (baixa prioridade).
14. `cargo_theft.client.lua:42` e `flatbed.client.lua:415`: varreduras de pool.
15. `industry_service.lua:217-230` e `industry_ownership_service.lua:202-206`: escritas por indústria/dono.

## 5. Observações de método e limites

- **NOT READ em corpo:** `client/parcel_delivery.lua` (sem `CreateThread`/`Wait` no grep), `industries.client.lua`, `server/database.lua`, `flatbed.server.lua` (corpos de laço) e a maior parte de `admin_service.lua`, `contract_service.lua`, `party_service.lua`, `company_service.lua` (só greps por padrão de laço).
- Custos reais dependem do número de jogadores e veículos; **RUNTIME PROOF REQUIRED** para qualquer priorização fina (`resmon`/profiler).
- O novo laço cinemático do PR #9 (desligado) reduziria o `sleep` para 0 só com pallets a ≤ 6 m dos garfos; o custo adicional é limitado ao jogador no forklift.
