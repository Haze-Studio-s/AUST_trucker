# Fase Final — Comercial (v17.0.0)

## Escopo

Quatro itens para viabilidade comercial do script:

- **A** — ESX bridge (Framework abstraction layer)
- **B** — Auto-create tables no boot (`server/schema.lua`)
- **C** — Performance audit (0.00ms idle)
- **D** — Docs update (README, GUIA_JOGADOR, GUIA_STAFF)

---

## A — ESX Bridge (`server/framework.lua`)

### Problema
~100 chamadas diretas `exports.qbx_core:GetPlayer` em 15 arquivos + `Player.Functions.*` e
`Player.PlayerData.*` travam o script em QBX. ESX e QBCore são incompatíveis com esse código.

### API normalizada

```lua
Framework = {}

-- Resolução de player
Framework.GetPlayer(src)                       -- → player_table | nil
Framework.FindPlayerByCitizenId(citizenId)     -- → src | nil (substitui loops GetPlayers+GetPlayer)

-- Getters do player (recebem o player_table retornado por GetPlayer)
Framework.GetCitizenId(player)                 -- → string
Framework.GetCharInfo(player)                  -- → { firstname, lastname }
Framework.GetJob(player)                       -- → { name, label }

-- Money (account = 'cash' | 'bank')
Framework.AddMoney(player, account, amount, reason)      -- void
Framework.RemoveMoney(player, account, amount, reason)   -- → bool
Framework.GetMoney(player, account)                      -- → number
Framework.HasMoney(player, account, amount)              -- → bool
```

### Implementação por framework

**QBX / QBCore:**
```lua
Framework.GetPlayer = function(src) return exports.qbx_core:GetPlayer(src) end
Framework.GetCitizenId = function(p) return p.PlayerData.citizenid end
Framework.AddMoney = function(p, acc, amt, r) p.Functions.AddMoney(acc, amt, r) end
Framework.RemoveMoney = function(p, acc, amt, r) return p.Functions.RemoveMoney(acc, amt, r) end
Framework.GetMoney = function(p, acc) return p.Functions.GetMoney(acc) end
```

**ESX:**
```lua
Framework.GetPlayer = function(src) return ESX.GetPlayerFromId(src) end
Framework.GetCitizenId = function(p) return p.getIdentifier() end
Framework.AddMoney = function(p, acc, amt, r)
    if acc == 'cash' then p.addMoney(amt) else p.addAccountMoney('bank', amt) end
end
Framework.RemoveMoney = function(p, acc, amt, r)
    local have = (acc == 'cash') and p.getMoney() or p.getAccount('bank').money
    if have < amt then return false end
    if acc == 'cash' then p.removeMoney(amt) else p.removeAccountMoney('bank', amt) end
    return true
end
Framework.GetMoney = function(p, acc)
    if acc == 'cash' then return p.getMoney() end
    return p.getAccount('bank').money
end
```

### FindPlayerByCitizenId

Substitui o padrão repetido 15+ vezes:
```lua
-- Antes:
local players = GetPlayers()
for _, pid in ipairs(players) do
    local P = exports.qbx_core:GetPlayer(tonumber(pid))
    if P and P.PlayerData.citizenid == targetCid then ... break end
end

-- Depois:
local targetSrc = Framework.FindPlayerByCitizenId(targetCid)
if targetSrc then ... end
```

### Config
`Config.Framework = 'qbx'` (padrão) em `config.lua`.

### fxmanifest
`qbx_core` removido de `dependencies` (torna-se opcional, detectado em runtime via `Config.Framework`).

### Substituições mecânicas (replace_all)
| Padrão antigo | Novo |
|---|---|
| `exports.qbx_core:GetPlayer(src)` | `Framework.GetPlayer(src)` |
| `exports.qbx_core:GetPlayer(tonumber(pid))` | `Framework.GetPlayer(tonumber(pid))` |
| `Player.PlayerData.citizenid` | `Framework.GetCitizenId(Player)` |
| `Player.Functions.AddMoney(` | `Framework.AddMoney(Player, ` |
| `Player.Functions.RemoveMoney(` | `Framework.RemoveMoney(Player, ` |
| `Player.Functions.GetMoney(` | `Framework.GetMoney(Player, ` |

Loops de broadcast com padrão `GetPlayers()+GetPlayer(pid)+citizenid == X` → `Framework.FindPlayerByCitizenId`.

---

## B — Auto-Create Tables (`server/schema.lua`)

### Problema
Servidor precisa executar `import.sql` manualmente. Erro humano frequente em atualizações.

### Solução
`server/schema.lua` — global `SchemaService = {}` com `SchemaService.EnsureTables()`.
Contém todos os `CREATE TABLE IF NOT EXISTS` e `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
Chamado de `main.lua` dentro de `MySQL.ready`, **antes** de `LoadCompanies()`.

Load order: `server/schema.lua` inserido após `server/main.lua` no fxmanifest.

---

## C — Performance Audit

Verificar todos os `CreateThread` loops. Target: 0.00ms resmon com 0 players ativos.

Principais suspeitos:
- Loops `while true do ... Wait(X)` em services com X pequeno
- Threads que não testam `VP_Trucker.Ready` antes de iniciar
- Threads por-player que ficam rodando após disconnect

Cada loop deve ter `Wait` mínimo de 1000ms (idealmente 5000ms+) em paths idle.

---

## D — Docs

- `README.md`: reescrever com instalação (auto-tables), `Config.Framework`, dependências opcionais, txAdmin setup
- `GUIA_JOGADOR.md`: adicionar Repo Man (v16), colateral de veículo, blip do agente
- `GUIA_STAFF.md`: adicionar comandos admin, migration notes para v16/v17

---

## Arquivos modificados

| Arquivo | Mudança |
|---|---|
| `server/framework.lua` | NEW — Framework global (QBX/QBCore/ESX) |
| `server/schema.lua` | NEW — SchemaService.EnsureTables() |
| `server/main.lua` | Chamar SchemaService.EnsureTables() no boot |
| `config/config.lua` | + Config.Framework = 'qbx' |
| `fxmanifest.lua` | Remove qbx_core de dependencies; add schema.lua e framework.lua |
| `server/events.lua` | Replace todas as chamadas de framework |
| `server/callbacks.lua` | Replace todas as chamadas de framework |
| `server/services/*.lua` | Replace todas as chamadas de framework (15 arquivos) |
| `README.md` | Reescrever com install guide multi-framework |
| `GUIA_JOGADOR.md` | Atualizar com features v16+ |
| `GUIA_STAFF.md` | Atualizar com admin guide v16+ |
| `CHANGELOG.md` | entrada v17.0.0 |

## Versão: 17.0.0
