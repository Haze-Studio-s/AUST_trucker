# ADR Certifications — Design Spec (v11.0.0)

**Data:** 2026-03-20
**Status:** Aprovado
**Fase Blueprint:** 5 — Polimento

---

## Visão Geral

Sistema de certificações ADR (Acordo Europeu relativo ao Transporte Internacional de Mercadorias Perigosas por Estrada) para o `AUST_trucker`. Jogadores precisam obter certificações específicas para aceitar jobs com carga perigosa (hazmat). Certificações expiram em 30 dias e são renovadas com pagamento simples (sem re-exame).

---

## 6 Tipos de Certificação

| Código | Nome | Produtos Cobertos |
|---|---|---|
| `flammable_liquid` | Líquidos Inflamáveis | Combustível, Diesel, Gasolina Premium, Óleo de Motor, Lubrificantes, Combustível Marítimo |
| `flammable_gas` | Gases Inflamáveis | Gás Liquefeito, Gás Natural |
| `toxic` | Substâncias Tóxicas | Produtos Químicos, Químicos Líquidos |
| `corrosive` | Substâncias Corrosivas | Ácido Industrial, Solventes |
| `explosive` | Explosivos | `weapons` (illegal jobs) |
| `environmental` | Perigosas ao Meio Ambiente | Fertilizantes, Minerais Ilegais |

Cada produto em `Config.PrimaryIndustries` e `Config.IllegalJobs` que exige ADR recebe um campo `adr = '<tipo>'`. Jobs sem campo `adr` são livres para todos os jogadores.

---

## Fluxo do Jogador

### Obter Certificação (primeira vez)

1. Jogador abre PDA → aba **"Licenças ADR"**
   - Exibe 6 cards: estado de cada cert (`active` / `expired` / `available`)
2. Clica em cert disponível → GPS marcado no Centro de Certificação (NPC examinador)
3. Chega ao NPC → `ox_target` → opção "Fazer Exame"
4. Paga taxa (`Config.Adr.ExamCost[type]`)
5. `lib.inputDialog` com 3 perguntas aleatórias do banco daquele tipo
6. **≥ 2 corretas** → certificação concedida por 30 dias (`expires_at = os.time() + 2592000`)
7. **< 2 corretas** → falha + cooldown 30 min (cache em memória, não persiste no DB)

### Renovação (cert expirada)

1. Jogador abre NUI ou vai ao NPC → opção "Renovar"
2. Paga taxa de renovação (`Config.Adr.RenewalCost[type]` = 60% do ExamCost)
3. Cert renovada imediatamente por mais 30 dias (sem exame)

### Job List — Jobs Bloqueados

- Jobs com `adr_required ~= nil` e player sem cert aparecem na lista com:
  - Ícone de cadeado
  - Label `"Exige ADR: <Nome do Tipo>"`
  - Aceitar bloqueado — notificação explicativa ao tentar
- Jobs com cert válida aparecem normalmente

---

## Config

```lua
Config.Adr = {
    -- Localização do NPC examinador
    ExaminerLocation = vector3(361.62, -2541.45, 5.74),  -- Terminal Portuário A1
    ExaminerPed      = 's_m_m_trucker_01',
    ExaminerHeading  = 180.0,
    ExaminerRadius   = 5.0,

    -- Dias de validade
    ValidityDays = 30,  -- 30 * 86400 = 2592000 segundos

    -- Cooldown de retry em caso de reprovação (segundos)
    RetryCooldownSeconds = 1800,  -- 30 minutos

    -- Taxa do exame por tipo
    ExamCost = {
        flammable_liquid = 5000,
        flammable_gas    = 6000,
        toxic            = 8000,
        corrosive        = 8000,
        explosive        = 15000,
        environmental    = 6000,
    },

    -- Taxa de renovação (sem exame) — 60% do ExamCost
    RenewalCost = {
        flammable_liquid = 3000,
        flammable_gas    = 3600,
        toxic            = 4800,
        corrosive        = 4800,
        explosive        = 9000,
        environmental    = 3600,
    },

    -- Banco de questões: mínimo 3 por tipo (serão escolhidas 3 aleatoriamente)
    -- Formato: { q = "Pergunta?", options = {"A","B","C","D"}, answer = 1 }
    Questions = {
        flammable_liquid = { ... },
        flammable_gas    = { ... },
        toxic            = { ... },
        corrosive        = { ... },
        explosive        = { ... },
        environmental    = { ... },
    },

    -- Nomes de exibição por tipo
    TypeLabels = {
        flammable_liquid = 'Líquidos Inflamáveis',
        flammable_gas    = 'Gases Inflamáveis',
        toxic            = 'Substâncias Tóxicas',
        corrosive        = 'Substâncias Corrosivas',
        explosive        = 'Explosivos',
        environmental    = 'Perigosas ao Meio Ambiente',
    },
}
```

---

## Banco de Dados

### Nova tabela: `trucker_adr_certs`

```sql
CREATE TABLE IF NOT EXISTS trucker_adr_certs (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    citizenid   VARCHAR(50) NOT NULL,
    adr_type    ENUM('flammable_liquid','flammable_gas','toxic','corrosive','explosive','environmental') NOT NULL,
    expires_at  INT UNSIGNED NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_citizen_type (citizenid, adr_type)
);
```

`UNIQUE KEY` em `(citizenid, adr_type)` permite `INSERT ... ON DUPLICATE KEY UPDATE` para renovação sem lógica extra.

### DB_UpsertAdrCert — SQL completo

```lua
function DB_UpsertAdrCert(citizenId, adrType, expiresAt)
    MySQL.update.await([[
        INSERT INTO trucker_adr_certs (citizenid, adr_type, expires_at)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at)
    ]], { citizenId, adrType, expiresAt })
end
```

`created_at` **não** aparece no `ON DUPLICATE KEY UPDATE` — preserva a data original de certificação para auditoria.

---

## Arquitetura de Código

### Novos arquivos

| Arquivo | Responsabilidade |
|---|---|
| `server/services/adr_service.lua` | `AdrService` global: `HasCert`, `GrantCert`, `Renew`, `GetAll`, `CheckExpiry` |
| `client/adr.client.lua` | Zona NPC, ox_target, exam flow via callbacks |

### Arquivos modificados

| Arquivo | Mudança |
|---|---|
| `config/config.lua` | Bloco `Config.Adr` + campo `adr` nos produtos de `Config.PrimaryIndustries` e `Config.IllegalJobs` |
| `server/database.lua` | `DB_GetAdrCerts(citizenid)`, `DB_UpsertAdrCert(citizenid, type, expiresAt)`, `DB_GetAdrCert(citizenid, type)` |
| `server/callbacks.lua` | `getInitialData` (adiciona `adrCerts` ao payload), `submitAdrExam`, `renewAdrCert` |
| `server/services/job_service.lua` | Ao montar job list para player: adiciona `adr_required` e `adr_locked` em cada job |
| `server/main.lua` | `VP_Trucker.AdrExamCooldowns = {}` no init |
| `fxmanifest.lua` | `adr_service.lua` após `progression_service.lua`; `adr.client.lua` na lista client |
| React NUI | `useAdrStore.ts`, `AdrPanel.tsx`, `AdrCertCard.tsx`, nova aba no `TabBar` |

---

## getInitialData — Integração ADR

`AdrService.GetAll(citizenId)` é adicionado diretamente ao payload de retorno de `getInitialData` em `callbacks.lua`. Não existe callback separado `getAdrStatus` — os dados chegam na abertura do PDA junto com tudo mais:

```lua
-- callbacks.lua — getInitialData return table (adicionar):
return {
    jobs                = JobService.GetAvailable(citizenId),  -- recebe citizenId agora
    adrCerts            = AdrService.GetAll(citizenId),        -- NOVO
    -- ... resto igual ...
}
```

A NUI lê `adrCerts` do payload inicial e popula `useAdrStore`. Não é necessário chamada extra de callback ao trocar de aba.

---

## AdrService — API

```lua
AdrService = {}

-- Verifica se citizenid tem cert válida (não expirada)
-- Retorna: boolean
AdrService.HasCert(citizenid, adrType)

-- Concede cert por 30 dias (usado no submitAdrExam após aprovação)
-- INSERT ON DUPLICATE KEY UPDATE expires_at
-- Retorna: expiresAt (number)
AdrService.GrantCert(citizenid, adrType)

-- Renova cert existente por mais 30 dias (usado no renewAdrCert, sem re-exame)
-- Internamente chama GrantCert — documentado separadamente para clareza de intenção
-- Retorna: expiresAt (number)
AdrService.Renew(citizenid, adrType)

-- Retorna mapa { [adr_type] = expires_at } com apenas certs válidas (não expiradas)
AdrService.GetValid(citizenid)

-- Retorna lista de objetos enriquecidos para UI — inclui todas as rows do DB (válidas e expiradas)
-- Cada objeto: { adr_type, expires_at, label }
-- label = Config.Adr.TypeLabels[row.adr_type] — enriquecido server-side antes de retornar
-- Tipos sem row no DB não aparecem na lista; a NUI complementa com os 6 tipos fixos do Config
AdrService.GetAll(citizenid)
```

### renewAdrCert — callback body

```lua
lib.callback.register('AUST_trucker:renewAdrCert', function(source, adrType)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid

    -- Validar tipo
    if not Config.Adr.RenewalCost[adrType] then
        return { success = false, reason = 'Tipo ADR inválido' }
    end

    -- Deve ter cert (expirada ou válida) para poder renovar
    local existing = DB_GetAdrCert(citizenId, adrType)
    if not existing then
        return { success = false, reason = 'Sem certificação prévia — faça o exame' }
    end

    local cost = Config.Adr.RenewalCost[adrType]
    local removed = Player.Functions.RemoveMoney('bank', cost, 'adr-renewal')
    if not removed then
        return { success = false, reason = 'Saldo insuficiente' }
    end

    local expiresAt = AdrService.Renew(citizenId, adrType)
    return { success = true, expiresAt = expiresAt }
end)
```

---

## Job Service — Integração

`JobService.GetAvailable()` em `server/services/job_service.lua` (linha 157) não recebe citizenid. Para injetar o ADR lock, a função precisa receber citizenid opcional:

```lua
-- Assinatura nova:
function JobService.GetAvailable(citizenid)
    -- ...build result como hoje...

    -- Overlay ADR (apenas se citizenid fornecido)
    local validCerts = citizenid and AdrService.GetValid(citizenid) or {}
    for _, job in ipairs(result) do
        local adrRequired = job.adrRequired  -- campo adicionado pelo produto no Config
        if adrRequired then
            job.adrLocked = not validCerts[adrRequired]
        else
            job.adrLocked = false
        end
    end

    return result
end
```

**Call site em `callbacks.lua` linha 85** muda de:
```lua
jobs = JobService.GetAvailable(),
```
para:
```lua
jobs = JobService.GetAvailable(citizenId),
```

Jobs `adrLocked = true` são incluídos na lista mas bloqueados na UI e rejeitados server-side em `JobService.Accept` se player tentar aceitar sem cert válida.

---

## Cache de Cooldown

```lua
-- server/main.lua
VP_Trucker.AdrExamCooldowns = {}

-- Uso em callbacks.lua ao receber submitAdrExam:
local key = citizenid .. '_' .. adrType
local now = os.time()
local cooldown = VP_Trucker.AdrExamCooldowns[key]
if cooldown and now < cooldown then
    return { success = false, reason = 'retry_cooldown', remainingSeconds = cooldown - now }
end
-- Se reprovar:
VP_Trucker.AdrExamCooldowns[key] = now + Config.Adr.RetryCooldownSeconds
```

Cooldown não persiste no DB nem em restart — aceitável, pois é uma penalidade leve de gameplay.

## Ordem de Operações — submitAdrExam (segurança TOCTOU)

Seguindo o padrão de `ProgressionService.PurchaseSkill` (que debita skill point antes de conceder — comentário na linha 112 de `progression_service.lua`):

```
1. Verificar cooldown → retornar erro se ativo
2. Verificar se já possui cert válida → retornar erro se sim
3. Deduzir ExamCost do player (Player.Functions.RemoveMoney)
   → Se saldo insuficiente → retornar erro (sem dedução)
4. Sortear e avaliar 3 perguntas
5. Se ≥ 2 corretas → AdrService.GrantCert → retornar { success=true, passed=true }
6. Se < 2 corretas → registrar cooldown → retornar { success=true, passed=false }
   (dinheiro NÃO é devolvido em caso de reprovação — custo de tentativa)
```

O dinheiro é deduzido **antes** da avaliação — se o servidor crashar após o passo 3, o player perde o dinheiro mas não recebe a cert. Isso é aceitável (mesma tradeoff do skill system) e evita race conditions.

---

## React NUI

### Componentes

- **`AdrPanel`** — container principal, lista os 6 cards
- **`AdrCertCard`** — card por tipo: nome, ícone hazmat, status badge (`Válida / Expirada / Disponível`), data de expiração, botão "Obter" ou "Renovar"

### Store (`useAdrStore.ts`)

```ts
interface AdrCert {
  adr_type: string
  expires_at: number   // Unix timestamp, 0 = não possui
  label: string
}

interface AdrStore {
  certs: AdrCert[]
  setCerts: (certs: AdrCert[]) => void
}
```

### Aba no TabBar

Nova aba **"ADR"** com ícone `fas fa-certificate`, posicionada após a aba de Progressão.

---

## fxmanifest — Ordem

```lua
-- server_scripts (inserir após progression_service):
'server/services/adr_service.lua',

-- client_scripts (inserir após hud.client.lua):
'client/adr.client.lua',
```

---

## Critérios de Sucesso

1. Jogador sem ADR vê job bloqueado com label explicativo
2. Exame com ≥2/3 acertos concede cert; <2/3 aplica cooldown de 30 min
3. Cert expira exatamente após 30 dias (verificado por `os.time()`)
4. Renovação funciona sem re-exame, apenas pagamento
5. UI mostra estado correto (válida/expirada/disponível) com data de expiração
6. `AdrService.HasCert` é chamado corretamente no job acceptance server-side (não apenas client-side)
7. `INSERT ON DUPLICATE KEY UPDATE` garante sem duplicatas na tabela

---

## Não-Escopo (YAGNI)

- Sem integração com `ProgressionService` (rank mínimo para ADR) — pode ser adicionado futuramente
- Sem notificação automática de expiração — jogador descobre ao abrir o PDA
- Sem logs de infração por dirigir sem ADR — cargo ilegal já tem `IllegalService`
