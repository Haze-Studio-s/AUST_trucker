## AUST_trucker — Audit Report (2026-04-08)

Escopo: auditoria completa do resource `AUST_trucker` (server/client/NUI) no padrão “hardening” FiveM:
validações server-side, superfícies de exploit em eventos/callbacks, segurança de economia/SQL, e cleanup de entidades/threads.

### Resumo (status final)

- **Críticos**: 1 encontrado, **corrigido**
- **High**: 1 encontrado, **corrigido**
- **Médios/Low**: não foi necessário alterar além do acima

### Principais pontos positivos já existentes no código

- **Anti-cheat server-side**: rate limiting (`AntiCheatService.RateLimit`) e validação de entrega (`AntiCheatService.ValidateDelivery`) com:
  - tempo mínimo por distância (teleporte/velocidade impossível)
  - validação de posição no destino com fail-closed para coords (0,0,0)
- **SQL**: uso consistente de queries parametrizadas (`?`) com `oxmysql`.
- **Proteções anti-exploit em eventos**: sanitização de `amount/qty`, whitelists (ex.: `vehicleType`), updates atômicos (ex.: status de veículo).
- **NUI (React)**: comunicação via `SendNUIMessage` + `fetch` NUI; o front não injeta HTML arbitrário (menor risco de XSS comparado a `innerHTML`).
- **Cleanup**: a maioria dos scripts client já remove blips/targets/zones no `onResourceStop` e em unload.

---

### CRITICAL — Contratos: completar paradas remotamente (bypass de progresso + pagamento)

**Impacto**
- Um cliente malicioso podia disparar `TriggerServerEvent('aurp_trucker:completeContractStop', stopOrder)` de qualquer lugar.
- O server marcava a parada como concluída sem:
  - validar que `stopOrder` era a **parada atual** (sequência)
  - validar **proximidade** do jogador ao local da parada
- Resultado: concluir contrato inteiro “de longe” e receber pagamento indevido.

**Correção aplicada**
- `ContractService.CompleteStop` agora:
  - **só permite completar a próxima parada pendente** (sequencial)
  - valida **distância server-side** entre jogador e coords da parada
  - sanitiza `stopOrder` e fail-closed em dados inválidos
- `server/events.lua` foi ajustado para passar o `src` para a validação de proximidade.

Arquivos alterados:
- `server/services/contract_service.lua`
- `server/events.lua`

---

### HIGH — Bônus de empresa em contratos não aplicado (bug mascarado por pcall)

**Impacto**
- `ContractService.Complete` tentava creditar bônus na empresa via `CompanyService.AddBalance`.
- A função **não existia** em `CompanyService`, e o `pcall` escondia o erro → bônus nunca era aplicado.

**Correção aplicada**
- Implementado `CompanyService.AddBalance(companyId, amount)` com:
  - sanitização do `amount`
  - fail-closed para evitar saldo negativo por corrida/estado desatualizado
  - atualização do cache `VP_Trucker.Companies[companyId].balance` baseado no retorno do DB

Arquivo alterado:
- `server/services/company_service.lua`

---

### Recomendações opcionais (não-bloqueantes)

**Implementado (2026-04-09)**

- **Logs de segurança**: `ContractService` chama `logContractSecurity` quando `Config.General.contractAnticheat.securityLog` está ativo — falhas `out_of_sequence`, `too_far`, `invalid_position`, `require_vehicle`, `invalid_ped`, `invalid_stop_order`.
- **UX/anticheat**: `Config.General.contractAnticheat` — `requireVehicle` (default `false`), `pickupDistanceMultiplier` / `deliveryDistanceMultiplier` (raios separados; fallback `distanceMultiplier`).
- **Parcel delivery (19.1.2)**: proximidade em `parcel:nextStop` / `parcel:complete` exige ped válido + coords não `(0,0,0)`; raios `StopRadius` / `DepotRadius` em `Config.ParcelDelivery`. **Contratos**: `AntiCheatService.RateLimit(..., 'completeContractStop')` no net event de parada.

---

### Checklist rápido “ship-ready”

- **Eventos transacionais**: amount/qty sanitizados + validação de permissão/role ok
- **Contratos**: agora têm validação de sequência + proximidade server-side
- **Economia**: pagamentos calculados server-side (inclusive combustível via `lastFuel`)
- **Cleanup**: `onResourceStop` presente nas áreas críticas (targets/blips/zones/peds)

