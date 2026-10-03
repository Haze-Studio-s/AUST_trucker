# Sync do repo VP local → Haze-Studio-s/AUST_trucker (2026-09-28)

Este branch traz para cá o que foi feito no repositório de origem (`vinicius3232/aust_trucker`,
pasta `[standalone]/AUST_trucker` do servidor Qbox_753251) **depois** do commit do qual este repo
nasceu (`1841642`, idêntico ao `d6d492e` daqui).

**Regra seguida: nada de UI, HTML, client ou config do trabalho em andamento aqui foi alterado.**
Só servidor, esquema de banco e documentação.

## O que entrou

### 1. Combustível dos caminhões-tanque abastece os postos (`vp_gasstations`)
- Commit de origem `27dbea7` (cherry-pick sem conflito).
- `config/config.lua`: 4 postos como destino em `Config.SecondaryIndustries` (Strawberry, Innocence, Davis, Paleto).
- `server/services/job_service.lua`: ao concluir uma entrega de combustível (trailer `tanker` ou carga
  Combustível/Gasolina/Diesel/Petróleo) num posto, chama `exports.vp_gasstations:AddFuelStock(coords, litros, origem)`.
  Só roda se o `vp_gasstations` estiver iniciado; sem ele, nada muda.

### 2. Aluguel de caminhão blindado (`server/services/truck_rental_service.lua`)
Mesma ideia e **mesmo contrato** do aluguel que já existia aqui — o client/UI continuam iguais:

| Contrato | Mantido |
|---|---|
| `aurp_trucker:rental:rentTruck(model)` | devolve `{ success, plate, model, deposit, fee, spawnCoords }`; o client cria o veículo |
| `aurp_trucker:rental:registerNetId` → `TruckRentalService.RegisterNetId` | sim |
| `aurp_trucker:rental:returnTruck(payload)` | devolve `refund`/`damagePenalty` **e** `refundAmount`/`damageCost` |
| `TruckRentalService.GetRental` / `OnPlayerDropped` | sim |

Correções:

| Gravidade | Antes | Agora |
|---|---|---|
| Crítico | Dano da devolução vinha do client (`payload.bodyHealth`): mandar 1000 = caução inteira | Dano lido no servidor (`GetVehicleBodyHealth`/`GetVehicleEngineHealth`); payload ignorado |
| Crítico | `RegisterNetId` aceitava qualquer netId; a devolução apagava esse veículo (dava pra apagar o caminhão de outro) | Só aceita veículo com a placa e o modelo do aluguel, perto do spawn, uma vez |
| Alto | A UI lê `res.refundAmount`/`res.damageCost`, o servidor devolvia `refund`/`damagePenalty` → `%d` com `nil` dava erro no aviso | Devolve os dois pares de nomes |
| Alto | Sem trava/throttle; aluguel limpo depois do pagamento | Trava por jogador + throttle 2 s; aluguel limpo antes de pagar |
| Médio | Desconexão/restart perdiam a caução | Coluna `refund_due`: desconexão guarda o estorno pelo dano; restart = caução integral; spawn que nunca aconteceu = caução integral; pago no próximo login (DELETE com linhas afetadas, sem estorno duplo) |
| Médio | Sem netId registrado não havia como devolver | Servidor acha o caminhão pela placa + modelo (`GetAllVehicles`) |

Integração (mínima):
- `server/database.lua`: coluna `refund_due` no `CREATE` + `ALTER` em `MIGRATIONS` (servidores existentes).
- `server/main.lua`: `TruckRentalService.Init()` após o schema.
- `server/events.lua`: `TruckRentalService.OnPlayerLoaded` no `QBCore:Server:OnPlayerLoaded`.
- `import.sql`: referência atualizada.

Chaves **opcionais** novas em `Config.TruckRental` (têm padrão no código, não precisa adicionar):
`throttleMs` (2000), `damageThreshold` (950.0), `spawnCheckRadius` (60.0).

Verificação: harness MOCK 13/13 com o contrato deste repo + sintaxe de todos os arquivos. **Não testado in-game.**

## Achados da revisão que NÃO foram mexidos (código da equipe daqui)

Ficam como recomendação — não alteramos para não atropelar o trabalho em andamento:

| Gravidade | Onde | Problema |
|---|---|---|
| Crítico | `server/events.lua` `aurp_trucker:server:completeLCContract` | Paga o contrato sem checar entrega/distância/tempo — dá pra disparar logo após aceitar. Faz SELECT → paga → UPDATE: com spam paga 2×. `parkedManually` (+5%) vem do client |
| Alto | `server/services/truck_fleet_service.lua` | Chama `Framework.GetPlayerMoney` / `RemovePlayerMoney` / `AddPlayerMoney`, que **não existem** em `server/framework.lua` (lá são `GetMoney`/`RemoveMoney`/`AddMoney` recebendo o Player) → comprar/vender/reparar dá erro |
| Alto | `TruckFleetService.SellTruck` | DELETE sem checar linhas afetadas antes de pagar → venda concorrente paga 2× |
| Médio | `job_service.lua` | `payload.truckId` (client) usado no desgaste da frota; `payload.parkedManually` dá +5% e XP sem validação |
| Atenção | `config/logistics_config.lua`, `html/` | O cabeçalho diz "Transplante completo das configurações do lc_truck_logistics" e a UI segue o mesmo painel. Se for material de script comercial, há risco de licença — o padrão do projeto é clean-room (ideia sim, cópia não) |
