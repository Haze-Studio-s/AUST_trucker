# Phase 1: Crude Oil Pipeline — Design Spec

**Data:** 2026-03-21
**Resources envolvidos:** AUST_oilfield, AUST_trucker
**Fase:** 1 de 4 do Ecosystem RP Integration

---

## Objetivo

Conectar AUST_oilfield e AUST_trucker criando um pipeline físico de crude oil: truckers com veículo tanker coletam barris nos poços e entregam na refinaria, gerando RP para truckers, donos de poço e inspetores SALA.

---

## Arquitetura

Dois resources se comunicam via **exports bidirecionais server-side**. Nenhum dado cruza via eventos de rede diretos — apenas exports síncronos entre os dois resources, mantendo cada um independente e testável separadamente.

### Exports AUST_oilfield → AUST_trucker

| Export | Descrição |
|---|---|
| `GetWellBarrels(wellId)` | Retorna `lm_wells.barrels_stored` do poço |
| `ConsumeBarrels(wellId, qty)` | Decrementa `barrels_stored` atomicamente — retorna true/false |
| `GetCrudeManifest(manifestId)` | Retorna dados da tabela `lm_transport_manifests` |
| `ValidateCrudeManifest(manifestId, truckerId)` | Valida se manifesto pertence ao trucker e está `active` |

> **Nota:** `server/transport.lua` já existe no AUST_oilfield com `_G.GenerateManifest` e `_G.ValidateManifest` baseados em itens de inventário (ox_inventory). Os 4 exports acima são **adicionados** a esse arquivo sem remover a lógica existente de item-manifesto. A nova tabela `lm_transport_manifests` é específica para crude oil — os manifestos de item existentes continuam funcionando para outros cargos.

### Exports AUST_trucker → AUST_oilfield

| Export | Descrição |
|---|---|
| `DeliverCrudeOil(wellId, refineryId, qty, manifestId)` | Chamado ao completar entrega — aciona pagamento e bonus de manifesto |

### CargoTrackingService — novo tipo

O `CargoTrackingService` do AUST_trucker ganha tipo `crude_oil`. A assinatura atual de `RegisterCargo(plate, jobId, citizenId, basePayment, gpsEnabled)` **deve ser estendida** para aceitar um parâmetro `metadata` opcional — o implementador precisa atualizar a assinatura, a persistência via `DB_` helpers e o `LoadFromDB`. O novo tipo passa:
```lua
{
    wellId        = number,
    manifestId    = number,
    barrelCount   = number,
    loadTimestamp = number,  -- unix timestamp
}
```

O export `GetActiveJobByPlate(plate)` em `server/exports.lua` deve ser implementado como wrapper sobre `VP_Trucker.CargoByPlate[plate]` (in-memory, já indexado por placa) — **não** como query DB — para evitar conflito com `DB_GetActiveJobByPlate` existente em `server/database.lua`.

---

## Modos de Iniciação de Job

### Modo A — Open Pickup (Pickup Livre)

Trucker com ADR `flammable_liquid` e veículo tanker vai diretamente ao poço. AUST_oilfield gera manifesto automático com preço base (`Config.CrudeOil.BasePrice × qty`).

### Modo B — Posted Order (Ordem Postada)

Dono do poço no Landman OS posta uma ordem de transporte definindo quantidade, preço/barril e prazo (até 60min). A ordem aparece no job board do AUST_trucker com badge `🛢️ CRUDE OIL`. Trucker aceita → manifesto real gerado no AUST_oilfield vinculado ao trucker.

Ambos os modos usam o mesmo fluxo de carregamento e entrega após iniciação.

---

## Fluxo de Estados

```
[IDLE] → [MANIFESTO_OBTIDO] → [CARREGANDO] → [EM_ROTA] → [DESCARREGANDO] → [CONCLUÍDO]
                                                    ↓
                                          [ROUBADO / ABANDONADO]
```

### Etapas detalhadas

1. **Verificação de pré-requisitos** (server-side ao iniciar):
   - Trucker tem ADR `flammable_liquid` ativo
   - Veículo está na lista `Config.CrudeOil.TankerModels`
   - Poço tem barris disponíveis (`lm_wells.barrels_stored >= 1`)

2. **Carregamento no poço:**
   - ox_target no poço → trucker escolhe quantidade (até capacidade do tanker)
   - `lib.progressBar` por barril (`Config.CrudeOil.LoadTimePerBarrel` ms cada) — pode ser interrompido
   - `ConsumeBarrels(wellId, qty)` atômico no server — segundo trucker recebe quantidade reduzida
   - `CargoTrackingService` registra job com metadata do manifesto
   - GPS para refinaria aparece no HUD

3. **Entrega na refinaria:**
   - ox_target na refinaria → `lib.progressBar` por barril (descarregamento espelhado)
   - `DeliverCrudeOil()` chamado no server → pagamento imediato
   - Bônus de preço aplicado se manifesto válido (sistema já existente no AUST_oilfield)
   - Imposto 15% coletado automaticamente (já existente)

4. **SALA em rota:**
   - **Novo export** `GetActiveJobByPlate(plate)` criado em `server/exports.lua` do AUST_trucker — retorna `{ cargoType, manifestId, wellId, barrelCount }` para a placa passada. SALA usa via pcall para verificar se o caminhão carrega crude e se tem manifesto válido.
   - ADR verificável via export existente do AUST_trucker
   - Cargo theft deliberado → item `crude_oil_barrel` no inventário do ladrão (venda no mercado negro — Phase D)

---

## Schema de Dados

### AUST_trucker — novas colunas em `aurp_jobs`

```sql
ALTER TABLE aurp_jobs ADD COLUMN cargo_type     VARCHAR(32)      DEFAULT NULL;
ALTER TABLE aurp_jobs ADD COLUMN manifest_id    INT              DEFAULT NULL;
ALTER TABLE aurp_jobs ADD COLUMN well_id        INT              DEFAULT NULL;
ALTER TABLE aurp_jobs ADD COLUMN barrels_total  TINYINT UNSIGNED DEFAULT 0;
ALTER TABLE aurp_jobs ADD COLUMN barrels_loaded TINYINT UNSIGNED DEFAULT 0;
```

### AUST_oilfield — nova tabela `lm_transport_manifests`

```sql
CREATE TABLE IF NOT EXISTS lm_transport_manifests (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    well_id     INT NOT NULL,
    trucker_id  VARCHAR(64),
    quantity    TINYINT UNSIGNED NOT NULL,
    price_per   INT NOT NULL,
    mode        ENUM('open','posted') DEFAULT 'open',
    status      ENUM('pending','active','delivered','expired','stolen') DEFAULT 'pending',
    expires_at  BIGINT,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_well_id (well_id),
    INDEX idx_trucker_id (trucker_id),
    INDEX idx_status (status)
);
```

### Config — AUST_trucker `config/config.lua`

```lua
Config.CrudeOil = {
    CargoType         = 'crude_oil',
    TankerModels      = { 'tanker', 'tanker2', 'packer' },
    LoadTimePerBarrel = 3000,    -- ms por barril
    BasePrice         = 150,     -- $/barril no modo A (open pickup)
    ManifestExpiry    = 3600,    -- segundos para manifesto expirar
    MaxBarrels        = {
        tanker  = 20,
        tanker2 = 16,
        packer  = 10,
    },
}
```

---

## Tratamento de Erros & Edge Cases

| Situação | Comportamento |
|---|---|
| Poço sem barris | Notifica "Sem produção disponível" — não abre menu de carregamento |
| Manifesto expirado em rota | Thread verifica a cada 5min; marca `expired`; entrega aceita mas sem bônus de preço |
| Trucker desconecta com carga | Job fica `active` no DB; restaurado ao reconectar; barris não retornam ao poço |
| Veículo destruído com carga | `cargo_lost` event → barris somem (sem item no inventário) |
| AUST_oilfield offline | Todos os exports em `pcall`; notifica trucker; não consome barris |
| Dois truckers no mesmo poço | `ConsumeBarrels` atômico — segundo recebe quantidade reduzida ou zero |
| Trucker abandona job | `JobService.Abandon()` em `job_service.lua` chama hook em `server/crude_oil.lua` que invoca `ConsumeBarrels` com qty negativa (reversal) — barris retornam ao poço sem perda para o dono |

---

## Arquivos a Criar/Modificar

### AUST_oilfield

| Arquivo | Ação |
|---|---|
| `server/transport.lua` | MODIFICAR — adicionar exports `GetWellBarrels`, `ConsumeBarrels`, `GetCrudeManifest`, `ValidateCrudeManifest` + gestão de `lm_transport_manifests`. **Não remover** lógica de item-manifesto existente. |
| `server/main.lua` | MODIFICAR — `CREATE TABLE IF NOT EXISTS lm_transport_manifests` no startup + thread de expiração a cada 5min |
| `client/transport.lua` | MODIFICAR — adicionar ox_target no poço para crude pickup + progressBar de carregamento. **Não remover** lógica existente (CheckTankerVehicle, NPC refinery spawn). |
| `fxmanifest.lua` | MODIFICAR — versão bump (sem novos arquivos neste resource) |

### AUST_trucker

| Arquivo | Ação |
|---|---|
| `server/crude_oil.lua` | CRIAR — handlers de job crude, export `DeliverCrudeOil`, chamadas pcall para AUST_oilfield |
| `client/crude_oil.lua` | CRIAR — ox_target na refinaria, progressBar de descarregamento |
| `server/exports.lua` | MODIFICAR — adicionar export `GetActiveJobByPlate(plate)` |
| `server/services/job_service.lua` | MODIFICAR — `JobService.GetAvailable()` inclui ordens crude postadas; `JobService.Accept()` suporta tipo `crude_oil` |
| `client/client.lua` | MODIFICAR — `OpenJobBoard` exibe badge `🛢️ CRUDE OIL` para ordens crude |
| `config/config.lua` | MODIFICAR — adicionar bloco `Config.CrudeOil` |
| `fxmanifest.lua` | MODIFICAR — adicionar novos arquivos server/client |

---

## Dependências

- ADR `flammable_liquid` no AUST_trucker (já implementado)
- Sistema de manifesto de transporte no AUST_oilfield (existente — estender)
- Bônus de preço na refinaria com manifesto válido (existente no AUST_oilfield)
- `CargoTrackingService` no AUST_trucker (existente — estender com tipo `crude_oil`)
- ox_target em ambos os resources (já configurado)
- Imposto 15% na venda (já existente no AUST_oilfield)

---

## O que NÃO está no escopo desta fase

- Licença de extração de petróleo via AUST_governo (Phase C)
- Licença hazmat via AUST_governo (Phase C)
- Embargo de zona pelo SALA bloqueando jobs (Phase B)
- Loop criminal / mercado negro de crude (Phase D)
- Contratos públicos do tesouro (Phase D)
