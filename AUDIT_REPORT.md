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
- **NUI (jQuery/Bootstrap, não React)**: `html/index.html` carrega `panel.js`/`js/admin.js` (UI jQuery) e comunica via `SendNUIMessage` + `fetch` NUI. O front monta HTML por template string, portanto o escape (`Utils.escapeHtml`/`safeId`) é obrigatório (corrigido em 2026-10-03; ver seção abaixo).
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

---

## Rodada de auditoria 2026-10-03

### Corrigido nesta rodada (branch de hardening, versão 20.7.7)

- **Dinheiro**: exploits de pagamento/preço, débito atômico da empresa, prova de entrega LC validada no servidor, empréstimos (loans) endurecidos, dano de veículo lido no servidor.
- **Framework**: `AddMoney`/`RemoveMoney`/`HasMoney` rejeitam NaN, infinito, não numérico e negativos (antes `RemoveMoney` negativo creditava no ESX).
- **Admin**: `adminTeleport` server-side; `IsPlayerAdmin` exige a ACE `command.truckeradmin` (ACEs genéricas removidas; nil não é mais admin, só `src == 0`); handlers admin com whitelist/clamp/limite de tamanho, somente campos sanitizados em memória, log de toda escrita; `GetActiveContracts` sem escrita no banco; bloqueio ADR mapeado para os tipos reais de `trucker_adr_certs`; `ReloadTrailerOffsets` reconstrói `Config.TrailerSlots` (remove offsets apagados).
- **NUI**: XSS (`panel.js`, `js/admin.js`); dependências (Bootstrap 4.6.2, three.js r128, TransformControls, Font Awesome 6.2.0, fontes) agora locais em `html/vendor/` (obtidas do registro npm; o proxy bloqueou jsdelivr/cdnjs) e CSP conservadora; removido fallback `document.write` e imagem de terceiros.
- **Client**: prints de debug sob `Config.Debug`; `clearjob`/`canceljob` passam pelos eventos de cancelamento do servidor; `checkactivejob`/`checktrailer`/`cleartrailer` só com `Config.Debug`; `onResourceStop` adicionado em parcel_delivery, cargo_liquid, zones, convoy, car_carrier, offset_editor.
- **CI/CD**: `deploy.yml` com `permissions: contents: read`, `environment: production`, action fixada em tag, caminhos entre aspas, `find` global removido e EXCLUDE de ferramentas de desenvolvimento.
- **Higiene**: removidos scratch_*.js, Thumbs.db, `.server.pid`, `config/helper_functions.ccs.js` (sem referências); `.gitignore` ampliado; versão alinhada (README/CHANGELOG/fxmanifest); `client/modules/*.lua` fora de `files{}` (não expor código-fonte).

### Ainda em aberto

- Regra de consequência para **inadimplência de empréstimo** (loan default).
- Confiança no **`parkedManually` de caminhões próprios** (informado pelo cliente).
- Itens médios/baixos residuais; webhook do Parcel agora vem de convar (`aurp_trucker_parcel_webhook`), mas o ideal é migrar o envio para um arquivo server-only.
- Pin da action `easingthemes/ssh-deploy` por SHA de commit (hoje por tag `v5.1.0`; verificar).
- Validar in-game: CSP da NUI, fontes/ícones locais e comandos de cancelamento (não testado em runtime).
- `server/schema.lua` (stub sem uso) e `fxmanifest.lua.disabled` continuam no repositório (decisão do mantenedor).
