# Fase 6 — Repo Man Avançado (v16.0.0)

## Escopo

Quatro subitens da Fase 6 do blueprint:

- **6A** — Colateral veículo no empréstimo (`vehicle_plate` em `trucker_loans`)
- **6B** — Validação server-side de conclusão + fix stub `repoAgentUpdate`
- **6C** — Flatbed sync multi-client via StateBag
- **6D** — NUI Repo cards (garantir campos completos no payload)

---

## 6A — Colateral veículo no empréstimo

### Problema
`trucker_loans` não tem `vehicle_plate`. `RepoService.GenerateFromLoan` escolhe veículo aleatório
da frota da empresa em vez do bem especificamente penhorado.

### Schema
```sql
ALTER TABLE trucker_loans ADD COLUMN vehicle_plate VARCHAR(20) NULL AFTER company_id;
```

### Mudanças
- `import.sql`: adicionar coluna na definição de `trucker_loans`
- `sql/update_loan_collateral_v16.sql`: migration para servidores existentes
- `server/database.lua`:
  - `DB_CreateLoan(citizenId, companyId, vehiclePlate, amount, ...)` — novo param `vehiclePlate`
  - `DB_GetActiveLoan` e `DB_GetActiveCompanyLoan`: incluir `vehicle_plate` no SELECT
  - `DB_GetOverdueLoans`: incluir `vehicle_plate` no SELECT
  - `DB_GetLoanById`: incluir `vehicle_plate` no SELECT
- `server/services/loan_service.lua`:
  - `LoanService.Create(src, citizenId, companyId, amount, vehiclePlate)` — `vehiclePlate` opcional
- `server/services/repo_service.lua`:
  - `RepoService.GenerateFromLoan(loan)`: se `loan.vehicle_plate` → buscar modelo/valor direto da
    `trucker_company_vehicles`; senão → fallback para veículo aleatório (lógica atual)
- `server/callbacks.lua`:
  - callback `createLoan`: extrair `vehicle_plate` do data e passar para `LoanService.Create`

---

## 6B — Server-side + owner blip

### Problema 1: `completeRepoOrder` sem validação de proximidade
O zone check é puramente client-side. Um cliente malicioso pode disparar o evento de qualquer lugar.

### Fix
`server/events.lua`, handler `completeRepoOrder`:
```lua
local ped    = GetPlayerPed(src)
local coords = DoesEntityExist(ped) and GetEntityCoords(ped) or nil
if coords then
    local dist = #(coords - Config.RepoMan.ImpoundLocation)
    if dist > Config.RepoMan.impoundRadius * 2 then
        lib.notify(src, { title='Repo Man', description='Muito longe do impound', type='error' })
        return
    end
end
```

### Problema 2: `repoAgentUpdate` é stub
`client/repo.client.lua` handler `repoAgentUpdate` tem apenas comentário placeholder.

### Fix
```lua
local repoAgentBlip = nil
RegisterNetEvent('AUST_trucker:client:repoAgentUpdate')
AddEventHandler('AUST_trucker:client:repoAgentUpdate', function(data)
    if not data or not data.coords then return end
    if not repoAgentBlip then
        repoAgentBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(repoAgentBlip, 1)
        SetBlipColour(repoAgentBlip, 1)
        SetBlipFlashes(repoAgentBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Agente Repo')
        EndTextCommandSetBlipName(repoAgentBlip)
    else
        SetBlipCoords(repoAgentBlip, data.coords.x, data.coords.y, data.coords.z)
    end
end)
-- Limpar blip em repoOwnerMissionEnded (já existente)
```

---

## 6C — Flatbed sync multi-client

### Problema
`AttachVehicle`/`DetachVehicle` no servidor relay apenas para o entity owner.
Outros clientes próximos não veem o veículo carregado no flatbed.

### Fix
Adicionar `AddStateBagChangeHandler('attachedVehicle', nil, cb)` em `flatbed.client.lua`.
Quando statebag muda:
- `value ~= -1` e `value ~= nil` → `AttachVehicleLocal(flatbedEnt, NetToVeh(value))`
- `value == -1` → `DetachVehicleLocal(NetToVeh(prevValue))` — recuperar veículo anterior do StateBag

Condição guard: apenas processar se `GetEntityModel(flatbedEnt) == FLATBED_MODEL` e o cliente
não é o entity owner (para evitar double-attach).

---

## 6D — NUI Repo cards

### Problema
`DB_GetAvailableRepoOrders` não inclui `loan_id` no SELECT, impedindo a NUI de diferenciar
visualmente ordens de empréstimo vs. NPC.

### Fix
Adicionar `loan_id` ao SELECT de `DB_GetAvailableRepoOrders`.
Os demais campos (`expires_at_unix`, `payment`, `mission_type`, `vehicle_model`) já estão presentes.

---

## Arquivos modificados

| Arquivo | Mudança |
|---|---|
| `import.sql` | + coluna `vehicle_plate` em `trucker_loans` |
| `sql/update_loan_collateral_v16.sql` | NEW — migration ALTER TABLE |
| `server/database.lua` | DB_CreateLoan + queries de loan incluem vehicle_plate; DB_GetAvailableRepoOrders inclui loan_id |
| `server/services/loan_service.lua` | LoanService.Create aceita vehiclePlate |
| `server/services/repo_service.lua` | GenerateFromLoan usa vehicle_plate se presente |
| `server/callbacks.lua` | createLoan extrai vehicle_plate |
| `server/events.lua` | completeRepoOrder valida proximidade |
| `client/repo.client.lua` | repoAgentUpdate com blip; limpar blip em missionEnded |
| `client/flatbed.client.lua` | AddStateBagChangeHandler('attachedVehicle') |
| `CHANGELOG.md` | entrada v16.0.0 |

---

## Versão: 16.0.0
