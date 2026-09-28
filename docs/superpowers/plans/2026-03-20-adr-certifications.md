# ADR Certifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar o sistema de certificações ADR (v11.0.0) — 6 tipos de hazmat, exame com banco de questões, expiração em 30 dias, renovação por pagamento, jobs bloqueados na UI para não-certificados.

**Architecture:** Novo `AdrService` global server-side gerencia certs no DB. `JobService.GetAvailable` recebe `citizenid` para injetar `adrLocked` em cada job. A NUI recebe `adrCerts` no payload `open` e renderiza a aba ADR com 6 `AdrCertCard` components.

**Tech Stack:** FiveM Lua 5.4 (chunk isolation, globais obrigatórios), oxmysql, ox_lib callbacks, ox_target, React 18 + TypeScript + Zustand + Tailwind CSS.

**Spec:** `docs/superpowers/specs/2026-03-20-adr-certifications-design.md`

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `import.sql` | Modificar | Adicionar tabela `trucker_adr_certs` |
| `config/config.lua` | Modificar | Bloco `Config.Adr` + campo `adr` nos produtos |
| `server/main.lua` | Modificar | Adicionar `VP_Trucker.AdrExamCooldowns = {}` |
| `server/database.lua` | Modificar | 3 funções DB_Adr* |
| `server/services/adr_service.lua` | Criar | `AdrService` global |
| `server/services/job_service.lua` | Modificar | `GetAvailable(citizenid)` + ADR overlay |
| `server/callbacks.lua` | Modificar | `getInitialData` + `submitAdrExam` + `renewAdrCert` |
| `fxmanifest.lua` | Modificar | Ordem de carga dos novos arquivos |
| `client/adr.client.lua` | Criar | NPC zone + ox_target + exam flow |
| `html/src/types/index.ts` | Modificar | `TabName` + `AdrCert` interface |
| `html/src/stores/useAdrStore.ts` | Criar | Zustand store de ADR |
| `html/src/hooks/useNUI.ts` | Modificar | Caso `open` + `updateAdrCerts` |
| `html/src/components/adr/AdrCertCard.tsx` | Criar | Card de cert individual |
| `html/src/components/adr/AdrPanel.tsx` | Criar | Painel ADR com 6 cards |
| `html/src/components/layout/TabBar.tsx` | Modificar | Nova aba "ADR" |
| `html/src/App.tsx` | Modificar | Render `<AdrPanel>` na aba `adr` |
| `CHANGELOG.md` | Modificar | Entrada v11.0.0 |

---

## Task 1: SQL — Tabela `trucker_adr_certs`

**Files:**
- Modify: `import.sql`

- [ ] **Adicionar a tabela ao `import.sql`** logo após a tabela `trucker_player_stats`:

```sql
CREATE TABLE IF NOT EXISTS `trucker_adr_certs` (
    `id`          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid`   VARCHAR(50) NOT NULL,
    `adr_type`    ENUM('flammable_liquid','flammable_gas','toxic','corrosive','explosive','environmental') NOT NULL,
    `expires_at`  INT UNSIGNED NOT NULL,
    `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_citizen_type` (`citizenid`, `adr_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

- [ ] **Criar o arquivo de migração para servidores existentes** em `sql/update_adr_v11.sql`:

```sql
-- AUST_trucker — migração v10 → v11: ADR Certifications
CREATE TABLE IF NOT EXISTS `trucker_adr_certs` (
    `id`          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid`   VARCHAR(50) NOT NULL,
    `adr_type`    ENUM('flammable_liquid','flammable_gas','toxic','corrosive','explosive','environmental') NOT NULL,
    `expires_at`  INT UNSIGNED NOT NULL,
    `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_citizen_type` (`citizenid`, `adr_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

- [ ] **Verificar manualmente no MySQL:**
```sql
DESCRIBE trucker_adr_certs;
-- Esperado: 5 colunas — id, citizenid, adr_type, expires_at, created_at
```

- [ ] **Commit:**
```bash
git add import.sql sql/update_adr_v11.sql
git commit -m "feat(adr): add trucker_adr_certs table"
```

---

## Task 2: Config — Bloco `Config.Adr` e campos `adr` nos produtos

**Files:**
- Modify: `config/config.lua`

- [ ] **Adicionar `Config.Adr` ao final de `config/config.lua`** (antes do último `end` ou após `Config.FleetUpgrades`):

```lua
-- ============================================================
-- ADR CERTIFICATIONS (v11.0.0)
-- ============================================================
Config.Adr = {
    ExaminerLocation = vector3(361.62, -2541.45, 5.74),
    ExaminerPed      = 's_m_m_trucker_01',
    ExaminerHeading  = 180.0,
    ExaminerRadius   = 5.0,

    ValiditySeconds      = 30 * 86400,   -- 2592000
    RetryCooldownSeconds = 1800,

    ExamCost = {
        flammable_liquid = 5000,
        flammable_gas    = 6000,
        toxic            = 8000,
        corrosive        = 8000,
        explosive        = 15000,
        environmental    = 6000,
    },

    RenewalCost = {
        flammable_liquid = 3000,
        flammable_gas    = 3600,
        toxic            = 4800,
        corrosive        = 4800,
        explosive        = 9000,
        environmental    = 3600,
    },

    TypeLabels = {
        flammable_liquid = 'Líquidos Inflamáveis',
        flammable_gas    = 'Gases Inflamáveis',
        toxic            = 'Substâncias Tóxicas',
        corrosive        = 'Substâncias Corrosivas',
        explosive        = 'Explosivos',
        environmental    = 'Perigosas ao Meio Ambiente',
    },

    -- Banco de questões — mínimo 3 por tipo.
    -- Formato: { q = "Pergunta?", options = {"A","B","C","D"}, answer = 1 }
    -- answer = índice da opção correta (1-based)
    Questions = {
        flammable_liquid = {
            { q = 'Qual equipamento é obrigatório ao transportar líquidos inflamáveis?',
              options = {'Extintor', 'Picareta', 'Capacete', 'Luvas de Latex'},
              answer = 1 },
            { q = 'A velocidade máxima recomendada com carga inflamável em rodovias é:',
              options = {'110 km/h', '90 km/h', '70 km/h', '50 km/h'},
              answer = 2 },
            { q = 'Em caso de vazamento de líquido inflamável, a primeira ação é:',
              options = {'Acender luz de emergência', 'Isolar a área e ligar para emergências', 'Tentar tampar com pano', 'Continuar viagem'},
              answer = 2 },
            { q = 'O painel de segurança laranja em veículos ADR identifica:',
              options = {'Carga frágil', 'Carga perigosa', 'Carga refrigerada', 'Carga viva'},
              answer = 2 },
        },
        flammable_gas = {
            { q = 'Cilindros de gás devem ser transportados:',
              options = {'Deitados sem fixação', 'Em pé e fixados', 'Empilhados horizontalmente', 'Com a válvula para baixo'},
              answer = 2 },
            { q = 'Gases inflamáveis pertencem à classe ADR:',
              options = {'Classe 1', 'Classe 2', 'Classe 3', 'Classe 4'},
              answer = 2 },
            { q = 'O risco principal no transporte de gás GLP é:',
              options = {'Explosão por ignição', 'Contaminação de água', 'Dano à camada de ozônio', 'Radiação'},
              answer = 1 },
        },
        toxic = {
            { q = 'Substâncias tóxicas exigem qual EPI mínimo ao manusear?',
              options = {'Apenas luvas', 'Máscara, luvas e óculos', 'Apenas óculos', 'Nenhum'},
              answer = 2 },
            { q = 'Em caso de contato de produto tóxico com a pele, deve-se:',
              options = {'Esfregar com areia', 'Lavar com água corrente por 15 min', 'Cobrir com pano', 'Aguardar secar'},
              answer = 2 },
            { q = 'O símbolo de caveira com ossos cruzados indica:',
              options = {'Explosivo', 'Radioativo', 'Tóxico', 'Corrosivo'},
              answer = 3 },
        },
        corrosive = {
            { q = 'Substâncias corrosivas podem destruir:',
              options = {'Apenas metais', 'Apenas plástico', 'Tecidos vivos e materiais', 'Apenas madeira'},
              answer = 3 },
            { q = 'O pH de um ácido forte corrosivo é aproximadamente:',
              options = {'7', '9', '1', '14'},
              answer = 3 },
            { q = 'Contêineres de corrosivos devem ser feitos de:',
              options = {'Alumínio puro', 'Material resistente ao produto', 'Vidro sempre', 'Madeira tratada'},
              answer = 2 },
        },
        explosive = {
            { q = 'A distância mínima de segurança ao estacionar veículo com explosivos próximo a edifícios é:',
              options = {'5 metros', '10 metros', '50 metros', 'Não há restrição'},
              answer = 3 },
            { q = 'Explosivos devem ser transportados longe de:',
              options = {'Carga seca', 'Fontes de calor e ignição', 'Carga refrigerada', 'Produtos alimentícios'],
              answer = 2 },
            { q = 'O detonador e o explosivo principal devem ser transportados:',
              options = {'Juntos para facilitar', 'Em compartimentos separados', 'Na cabine do motorista', 'Não há regra'],
              answer = 2 },
        },
        environmental = {
            { q = 'Fertilizantes em excesso no ambiente causam principalmente:',
              options = {'Eutrofização de rios', 'Aumento da temperatura', 'Redução da chuva ácida', 'Melhora do solo'],
              answer = 1 },
            { q = 'O símbolo de peixe morto e árvore indica:',
              options = {'Produto venenoso', 'Perigoso ao meio ambiente', 'Produto radioativo', 'Inflamável'],
              answer = 2 },
            { q = 'Em caso de derramamento de produto perigoso ao meio ambiente, deve-se:',
              options = {'Lavar com mangueira', 'Conter e acionar equipe especializada', 'Cobrir com terra', 'Deixar evaporar'],
              answer = 2 },
        },
    },
}
```

- [ ] **Adicionar campo `adr` nos produtos de `Config.PrimaryIndustries`** que são hazmat. Localizar cada produto e adicionar `adr = 'tipo'` na tabela do produto:

```lua
-- terminal_b1 — Combustível e Diesel
{name = "Combustível", trailer = "tanker", basePrice = 820, loadTime = 10000, icon = "fas fa-gas-pump", adr = 'flammable_liquid'},
{name = "Diesel",      trailer = "tanker", basePrice = 750, loadTime = 9000,  icon = "fas fa-oil-can",  adr = 'flammable_liquid'},

-- terminal_d1 — Petróleo e Gasolina
{name = "Petróleo Refinado", trailer = "tanker", basePrice = 870, loadTime = 10500, icon = "fas fa-oil-can",  adr = 'flammable_liquid'},
{name = "Gasolina Premium",  trailer = "tanker", basePrice = 800, loadTime = 9500,  icon = "fas fa-gas-pump", adr = 'flammable_liquid'},

-- terminal_d2 — Químicos
{name = "Produtos Químicos", trailer = "trailers", basePrice = 750, loadTime = 9000, icon = "fas fa-flask",   adr = 'toxic'},
{name = "Fertilizantes",     trailer = "trailers", basePrice = 680, loadTime = 8000, icon = "fas fa-seedling", adr = 'environmental'},
{name = "Químicos Líquidos", trailer = "tanker",   basePrice = 820, loadTime = 9500, icon = "fas fa-vial",    adr = 'toxic'},

-- terminal_h1 — Óleos
{name = "Óleo Diesel",    trailer = "tanker", basePrice = 740, loadTime = 8800, icon = "fas fa-oil-can", adr = 'flammable_liquid'},
{name = "Lubrificantes",  trailer = "tanker", basePrice = 690, loadTime = 8200, icon = "fas fa-tint",    adr = 'flammable_liquid'},
{name = "Óleo de Motor",  trailer = "tanker", basePrice = 720, loadTime = 8500, icon = "fas fa-oil-can", adr = 'flammable_liquid'},
```

- [ ] **Adicionar campo `adr` em `Config.IllegalJobs` para o tipo `weapons`:**

```lua
-- No bloco Config.IllegalJobs.paymentMultipliers e em cada contact que aceita 'weapons',
-- adicionar ao config uma tabela de adr por tipo de carga ilegal:
-- (No topo de Config.IllegalJobs, após o bloco de contacts)
adrRequired = {
    weapons = 'explosive',
    -- outros tipos de carga ilegal não exigem ADR
},
```

- [ ] **Commit:**
```bash
git add config/config.lua
git commit -m "feat(adr): add Config.Adr block and adr fields to products"
```

---

## Task 3: Database — Funções DB_Adr*

**Files:**
- Modify: `server/database.lua`

- [ ] **Adicionar ao final de `server/database.lua`** (nova seção ADR):

```lua
-- ============================================================
-- ADR CERTIFICATIONS (v11.0.0)
-- ============================================================

-- Retorna todas as rows de um citizenid (válidas e expiradas)
function DB_GetAdrCerts(citizenId)
    return MySQL.query.await(
        'SELECT adr_type, expires_at FROM trucker_adr_certs WHERE citizenid = ?',
        { citizenId }
    ) or {}
end

-- Retorna uma row específica (usado para verificar se existe antes de renovar)
function DB_GetAdrCert(citizenId, adrType)
    return MySQL.single.await(
        'SELECT adr_type, expires_at FROM trucker_adr_certs WHERE citizenid = ? AND adr_type = ? LIMIT 1',
        { citizenId, adrType }
    )
end

-- Insere ou atualiza expires_at (upsert). created_at não é tocado no UPDATE.
function DB_UpsertAdrCert(citizenId, adrType, expiresAt)
    MySQL.update.await([[
        INSERT INTO trucker_adr_certs (citizenid, adr_type, expires_at)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at)
    ]], { citizenId, adrType, expiresAt })
end
```

- [ ] **Verificar no console do servidor** reiniciando o resource:
```
ensure AUST_trucker
-- Não deve aparecer nenhum erro de sintaxe Lua
```

- [ ] **Commit:**
```bash
git add server/database.lua
git commit -m "feat(adr): add DB_GetAdrCerts, DB_GetAdrCert, DB_UpsertAdrCert"
```

---

## Task 4: AdrService — Serviço server-side

**Files:**
- Create: `server/services/adr_service.lua`

- [ ] **Criar `server/services/adr_service.lua`:**

```lua
-- AUST_trucker — server/services/adr_service.lua
-- Gerencia certificações ADR: concessão, renovação, verificação de validade

AdrService = {}

local VALIDITY = Config.Adr.ValiditySeconds  -- 2592000 (30 dias)

-- Verifica se citizenid tem cert válida para o tipo dado
-- Retorna: boolean
function AdrService.HasCert(citizenId, adrType)
    local row = DB_GetAdrCert(citizenId, adrType)
    if not row then return false end
    return row.expires_at > os.time()
end

-- Concede cert por VALIDITY segundos (INSERT ON DUPLICATE KEY UPDATE)
-- Retorna: expiresAt (number)
function AdrService.GrantCert(citizenId, adrType)
    local expiresAt = os.time() + VALIDITY
    DB_UpsertAdrCert(citizenId, adrType, expiresAt)
    return expiresAt
end

-- Renova cert existente por mais VALIDITY segundos (alias semântico de GrantCert)
-- Retorna: expiresAt (number)
function AdrService.Renew(citizenId, adrType)
    return AdrService.GrantCert(citizenId, adrType)
end

-- Retorna mapa { [adr_type] = expires_at } com apenas certs VÁLIDAS (não expiradas)
function AdrService.GetValid(citizenId)
    local rows = DB_GetAdrCerts(citizenId)
    local now  = os.time()
    local valid = {}
    for _, row in ipairs(rows) do
        if row.expires_at > now then
            valid[row.adr_type] = row.expires_at
        end
    end
    return valid
end

-- Retorna lista enriquecida para UI: todas as rows do DB + label server-side
-- Formato: { { adr_type, expires_at, label } }
-- Tipos sem row no DB não aparecem — a NUI usa Config.Adr.TypeLabels para complementar
function AdrService.GetAll(citizenId)
    local rows  = DB_GetAdrCerts(citizenId)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            adr_type  = row.adr_type,
            expires_at = row.expires_at,
            label     = Config.Adr.TypeLabels[row.adr_type] or row.adr_type,
        })
    end
    return result
end
```

- [ ] **Testar via console do servidor** (após ensure):
```
-- No console FiveM:
print(json.encode(AdrService.GetValid('ABC123')))
-- Esperado: {} (sem certs ainda)
```

- [ ] **Commit:**
```bash
git add server/services/adr_service.lua
git commit -m "feat(adr): add AdrService (HasCert, GrantCert, Renew, GetValid, GetAll)"
```

---

## Task 5: main.lua — Cache de cooldowns

**Files:**
- Modify: `server/main.lua`

- [ ] **Adicionar `AdrExamCooldowns` ao `VP_Trucker` em `server/main.lua`** (linha ~22, dentro do bloco VP_Trucker):

```lua
VP_Trucker = {
    -- ... campos existentes ...
    -- ADR (v11.0.0)
    AdrExamCooldowns = {},   -- [citizenid_adrtype] = os.time() de expiração do cooldown
}
```

- [ ] **Commit:**
```bash
git add server/main.lua
git commit -m "feat(adr): add AdrExamCooldowns to VP_Trucker"
```

---

## Task 6: fxmanifest — Ordem de carga

**Files:**
- Modify: `fxmanifest.lua`

- [ ] **Adicionar `adr_service.lua` na posição correta** em `server_scripts` (após `progression_service.lua`, antes de `job_service.lua`):

```lua
'server/services/progression_service.lua',
'server/services/adr_service.lua',         -- NOVO
'server/services/job_service.lua',
```

- [ ] **Adicionar `adr.client.lua` em `client_scripts`** (após `hud.client.lua`):

```lua
'client/hud.client.lua',
'client/adr.client.lua',          -- NOVO
'client/convoy.client.lua',
```

- [ ] **Verificar** que o resource inicia sem erros:
```
ensure AUST_trucker
-- Console não deve mostrar erros de "attempt to index a nil value"
```

- [ ] **Commit:**
```bash
git add fxmanifest.lua
git commit -m "feat(adr): add adr_service and adr.client to fxmanifest"
```

---

## Task 7: JobService — ADR overlay em GetAvailable

**Files:**
- Modify: `server/services/job_service.lua` (linha ~157)

- [ ] **Modificar a assinatura de `JobService.GetAvailable`** para receber `citizenid` opcional e adicionar o overlay ADR após construir `result`:

Localizar a função (linha ~157):
```lua
function JobService.GetAvailable()
```
Substituir por:
```lua
function JobService.GetAvailable(citizenId)
```

Localizar o `return result` no final da função e adicionar o overlay ADR ANTES do return:

```lua
    -- Overlay ADR: marcar jobs que exigem cert que o player não possui
    local validCerts = citizenId and AdrService.GetValid(citizenId) or {}
    for _, job in ipairs(result) do
        -- Buscar no Config se o cargo_item do job tem exigência ADR
        local adrRequired = nil
        for _, industry in ipairs(Config.PrimaryIndustries) do
            for _, product in ipairs(industry.products or {}) do
                if product.name == job.cargoItem and product.adr then
                    adrRequired = product.adr
                    break
                end
            end
            if adrRequired then break end
        end
        -- Verificar illegal jobs também
        if not adrRequired and Config.IllegalJobs.adrRequired then
            adrRequired = Config.IllegalJobs.adrRequired[job.cargoItem]
        end

        job.adrRequired = adrRequired
        job.adrLocked   = adrRequired and not validCerts[adrRequired] or false
    end

    return result
```

- [ ] **Modificar `JobService.Accept`** (linha ~191) para retornar `boolean` e rejeitar se ADR bloqueado:

```lua
function JobService.Accept(jobId, citizenId, companyId)
    -- Buscar job no DB para checar ADR
    local jobRow = MySQL.single.await('SELECT cargo_item FROM trucker_jobs WHERE id = ? LIMIT 1', { jobId })
    if jobRow then
        local adrRequired = nil
        for _, industry in ipairs(Config.PrimaryIndustries) do
            for _, product in ipairs(industry.products or {}) do
                if product.name == jobRow.cargo_item and product.adr then
                    adrRequired = product.adr
                    break
                end
            end
            if adrRequired then break end
        end
        if not adrRequired and Config.IllegalJobs.adrRequired then
            adrRequired = Config.IllegalJobs.adrRequired[jobRow.cargo_item]
        end
        if adrRequired and not AdrService.HasCert(citizenId, adrRequired) then
            return false  -- rejeitado server-side
        end
    end
    DB_AcceptJob(jobId, citizenId, companyId)
    return true
end
```

- [ ] **Atualizar o caller em `server/events.lua`** (linha 22 — é aqui que `JobService.Accept` é chamado, NÃO em `callbacks.lua`):

Substituir:
```lua
local company = CompanyService.GetByMember(citizenId)
JobService.Accept(jobId, citizenId, company and company.id or nil)

local jobData = JobService.GetActiveByPlayer(citizenId)
```
Por:
```lua
local company  = CompanyService.GetByMember(citizenId)
local accepted = JobService.Accept(jobId, citizenId, company and company.id or nil)
if not accepted then
    TriggerClientEvent('AUST_trucker:notify', src, 'Você não possui a certificação ADR necessária para este cargo', 'error')
    return
end

local jobData = JobService.GetActiveByPlayer(citizenId)
```

- [ ] **Testar manualmente:**
  - Iniciar o resource
  - Abrir PDA → aba Jobs
  - Jobs de produtos hazmat devem carregar normalmente (sem crash)

- [ ] **Commit:**
```bash
git add server/services/job_service.lua server/events.lua
git commit -m "feat(adr): JobService.GetAvailable receives citizenId, ADR gate in Accept+events"
```

---

## Task 8: Callbacks — getInitialData + submitAdrExam + renewAdrCert

**Files:**
- Modify: `server/callbacks.lua`

- [ ] **Atualizar `getInitialData`** — linha 85, mudar `JobService.GetAvailable()` e adicionar `adrCerts`:

```lua
return {
    jobs                = JobService.GetAvailable(citizenId),   -- citizenId agora
    adrCerts            = AdrService.GetAll(citizenId),         -- NOVO
    company             = companyPayload,
    -- ... resto igual ...
}
```

- [ ] **Adicionar `submitAdrExam` ao final de `callbacks.lua`:**

```lua
-- ADR: submeter exame
lib.callback.register('AUST_trucker:submitAdrExam', function(source, adrType, answers)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid

    -- 1. Validar tipo
    if not Config.Adr.ExamCost[adrType] then
        return { success = false, reason = 'Tipo ADR inválido' }
    end

    -- 2. Verificar cooldown
    local key = citizenId .. '_' .. adrType
    local now = os.time()
    local cooldownExpiry = VP_Trucker.AdrExamCooldowns[key]
    if cooldownExpiry and now < cooldownExpiry then
        return { success = false, reason = 'cooldown', remainingSeconds = cooldownExpiry - now }
    end

    -- 3. Verificar se já possui cert válida
    if AdrService.HasCert(citizenId, adrType) then
        return { success = false, reason = 'Você já possui esta certificação válida' }
    end

    -- 4. Deduzir taxa do exame
    local cost    = Config.Adr.ExamCost[adrType]
    local removed = Player.Functions.RemoveMoney('cash', cost, 'adr-exam')
    if not removed then
        return { success = false, reason = 'Saldo insuficiente' }
    end

    -- 5. Avaliar respostas
    local questions   = Config.Adr.Questions[adrType] or {}
    local correct     = 0
    for i, answer in ipairs(answers or {}) do
        local q = questions[i]
        if q and tonumber(answer) == q.answer then
            correct = correct + 1
        end
    end

    -- 6. Aprovar ou reprovar
    if correct >= 2 then
        local expiresAt = AdrService.GrantCert(citizenId, adrType)
        return { success = true, passed = true, expiresAt = expiresAt }
    else
        VP_Trucker.AdrExamCooldowns[key] = now + Config.Adr.RetryCooldownSeconds
        return { success = true, passed = false, correct = correct }
    end
end)

-- ADR: renovar cert expirada (sem re-exame)
lib.callback.register('AUST_trucker:renewAdrCert', function(source, adrType)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return { success = false, reason = 'Jogador não encontrado' } end
    local citizenId = Player.PlayerData.citizenid

    if not Config.Adr.RenewalCost[adrType] then
        return { success = false, reason = 'Tipo ADR inválido' }
    end

    -- Deve ter cert prévia (expirada ou válida) para renovar
    local existing = DB_GetAdrCert(citizenId, adrType)
    if not existing then
        return { success = false, reason = 'Sem certificação prévia — faça o exame primeiro' }
    end

    local cost    = Config.Adr.RenewalCost[adrType]
    local removed = Player.Functions.RemoveMoney('bank', cost, 'adr-renewal')
    if not removed then
        return { success = false, reason = 'Saldo insuficiente' }
    end

    local expiresAt = AdrService.Renew(citizenId, adrType)
    return { success = true, expiresAt = expiresAt }
end)
```

- [ ] **Commit:**
```bash
git add server/callbacks.lua
git commit -m "feat(adr): add submitAdrExam and renewAdrCert callbacks, update getInitialData"
```

---

## Task 9: Client — NPC Zone + Exam Flow

**Files:**
- Create: `client/adr.client.lua`

- [ ] **Criar `client/adr.client.lua`:**

```lua
-- AUST_trucker — client/adr.client.lua
-- NPC examinador ADR: zona ox_lib, ox_target, fluxo de exame

local ExaminerPed    = nil
local ExaminerZone   = nil
local ExaminerZoneId = 'adr_examiner_zone'

-- ============================================================
-- SPAWN DO NPC EXAMINADOR
-- ============================================================

local function SpawnExaminerPed()
    local cfg     = Config.Adr
    local model   = GetHashKey(cfg.ExaminerPed)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    ExaminerPed = CreatePed(4,
        model,
        cfg.ExaminerLocation.x,
        cfg.ExaminerLocation.y,
        cfg.ExaminerLocation.z - 1.0,
        cfg.ExaminerHeading,
        false, true)

    SetEntityInvincible(ExaminerPed, true)
    SetBlockingOfNonTemporaryEvents(ExaminerPed, true)
    FreezeEntityPosition(ExaminerPed, true)
    SetModelAsNoLongerNeeded(model)

    exports.ox_target:addLocalEntity(ExaminerPed, {
        {
            name     = 'adr_examiner',
            label    = 'Centro ADR — Ver Certificações',
            icon     = 'fas fa-certificate',
            distance = 2.5,
            onSelect = function()
                TriggerEvent('AUST_trucker:client:openAdrMenu')
            end,
        },
    })
end

-- ============================================================
-- MENU DE SELEÇÃO DE TIPO
-- ============================================================

local function OpenAdrMenu()
    local options = {}
    for adrType, label in pairs(Config.Adr.TypeLabels) do
        local examCost   = Config.Adr.ExamCost[adrType]
        local renewCost  = Config.Adr.RenewalCost[adrType]
        table.insert(options, {
            title       = label,
            description = ('Exame: $%d  |  Renovação: $%d'):format(examCost, renewCost),
            icon        = 'fas fa-certificate',
            onSelect    = function()
                TriggerEvent('AUST_trucker:client:startExam', adrType)
            end,
        })
    end

    lib.registerContext({
        id      = 'adr_type_menu',
        title   = 'Centro de Certificação ADR',
        options = options,
    })
    lib.showContext('adr_type_menu')
end

-- ============================================================
-- FLUXO DO EXAME
-- ============================================================

local function StartExam(adrType)
    local questions = Config.Adr.Questions[adrType] or {}
    if #questions == 0 then
        lib.notify({ title = 'ADR', description = 'Sem questões disponíveis', type = 'error' })
        return
    end

    -- Sortear 3 questões aleatórias
    local pool = {}
    for _, q in ipairs(questions) do table.insert(pool, q) end
    local selected = {}
    for i = 1, math.min(3, #pool) do
        local idx = math.random(1, #pool)
        table.insert(selected, pool[idx])
        table.remove(pool, idx)
    end

    -- Apresentar cada questão via lib.inputDialog
    local answers = {}
    for i, q in ipairs(selected) do
        local result = lib.inputDialog(
            ('Exame ADR — Pergunta %d/%d'):format(i, #selected),
            {
                { type = 'select', label = q.q, options = (function()
                    local opts = {}
                    for j, opt in ipairs(q.options) do
                        table.insert(opts, { value = tostring(j), label = opt })
                    end
                    return opts
                end)() },
            }
        )
        if not result or not result[1] then
            lib.notify({ title = 'ADR', description = 'Exame cancelado', type = 'warning' })
            return
        end
        table.insert(answers, tonumber(result[1]))
    end

    -- Enviar ao servidor
    local ok, res = pcall(lib.callback.await, 'AUST_trucker:submitAdrExam', false, adrType, answers)
    if not ok or not res then
        lib.notify({ title = 'ADR', description = 'Erro ao processar exame', type = 'error' })
        return
    end

    if not res.success then
        if res.reason == 'cooldown' then
            local mins = math.ceil((res.remainingSeconds or 0) / 60)
            lib.notify({ title = 'ADR',
                description = ('Aguarde %d min antes de tentar novamente'):format(mins),
                type = 'error', duration = 8000 })
        else
            lib.notify({ title = 'ADR', description = res.reason or 'Erro', type = 'error' })
        end
        return
    end

    if res.passed then
        lib.notify({
            title       = 'ADR — Aprovado!',
            description = ('Certificação obtida! Válida por 30 dias.'),
            type        = 'success',
            duration    = 8000,
        })
        -- Atualizar NUI via SendNUIMessage
        SendNUIMessage({ action = 'adrCertGranted', adrType = adrType, expiresAt = res.expiresAt })
    else
        lib.notify({
            title       = 'ADR — Reprovado',
            description = ('Acertou %d/3. Tente novamente em 30 minutos.'):format(res.correct or 0),
            type        = 'error',
            duration    = 8000,
        })
    end
end

-- ============================================================
-- RENOVAÇÃO
-- ============================================================

local function RenewCert(adrType)
    local ok, res = pcall(lib.callback.await, 'AUST_trucker:renewAdrCert', false, adrType)
    if not ok or not res then
        lib.notify({ title = 'ADR', description = 'Erro ao renovar', type = 'error' })
        return
    end

    if res.success then
        lib.notify({
            title       = 'ADR — Renovada',
            description = 'Certificação renovada por mais 30 dias.',
            type        = 'success',
            duration    = 6000,
        })
        SendNUIMessage({ action = 'adrCertGranted', adrType = adrType, expiresAt = res.expiresAt })
    else
        lib.notify({ title = 'ADR', description = res.reason or 'Erro', type = 'error' })
    end
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

AddEventHandler('AUST_trucker:client:openAdrMenu', OpenAdrMenu)
AddEventHandler('AUST_trucker:client:startExam',   StartExam)
AddEventHandler('AUST_trucker:client:renewCert',   RenewCert)

-- ============================================================
-- INICIALIZAÇÃO
-- ============================================================

CreateThread(function()
    Wait(2000)  -- aguardar resource inicializar
    SpawnExaminerPed()

    -- Zona de proximidade para TextUI
    ExaminerZone = lib.zones.sphere({
        name   = ExaminerZoneId,
        coords = Config.Adr.ExaminerLocation,
        radius = Config.Adr.ExaminerRadius,
        onEnter = function()
            lib.showTextUI('[E] Centro de Certificação ADR', { position = 'left-center', icon = 'certificate' })
        end,
        onExit = function()
            lib.hideTextUI()
        end,
    })
end)

-- Cleanup ao parar o resource
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if ExaminerPed and DoesEntityExist(ExaminerPed) then
        exports.ox_target:removeLocalEntity(ExaminerPed)
        DeletePed(ExaminerPed)
    end
    if ExaminerZone then ExaminerZone:remove() end
end)
```

- [ ] **Testar no jogo:**
  - Ir até as coords do Terminal Portuário A1 (`vector3(361.62, -2541.45, 5.74)`)
  - NPC deve aparecer
  - TextUI deve mostrar ao entrar no raio
  - ox_target deve mostrar opção "Centro ADR"

- [ ] **Adicionar NUI callbacks ao final de `client/adr.client.lua`** (antes do `CreateThread` de inicialização):

```lua
-- NUI Callback: GPS ao examinador (disparado pelo botão "Fazer Exame" no PDA)
RegisterNUICallback('setAdrGps', function(data, cb)
    SetNewWaypoint(Config.Adr.ExaminerLocation.x, Config.Adr.ExaminerLocation.y)
    lib.notify({ title = 'ADR', description = 'GPS marcado no examinador ADR', type = 'inform' })
    cb({ ok = true })
end)

-- NUI Callback: renovação direta do PDA (sem precisar ir ao NPC)
RegisterNUICallback('renewAdrCert', function(data, cb)
    local ok, res = pcall(lib.callback.await, 'AUST_trucker:renewAdrCert', false, data.adrType)
    if ok and res then
        cb(res)
    else
        cb({ success = false, reason = 'Erro interno' })
    end
end)
```

- [ ] **Commit:**
```bash
git add client/adr.client.lua
git commit -m "feat(adr): add NPC examiner zone, exam flow, renewal, NUI callbacks in adr.client.lua"
```

---

## Task 10: NUI — Types e Store

**Files:**
- Modify: `html/src/types/index.ts`
- Create: `html/src/stores/useAdrStore.ts`

- [ ] **Adicionar `'adr'` ao `TabName` em `html/src/types/index.ts`** (linha 122):

```ts
export type TabName = 'jobs' | 'missions' | 'active' | 'company' | 'garage' | 'industries' | 'stats' | 'convoy' | 'drivers' | 'adr'
```

- [ ] **Adicionar interface `AdrCert` ao mesmo arquivo** (após as interfaces existentes):

```ts
export interface AdrCert {
  adr_type:   string
  expires_at: number   // Unix timestamp em segundos; 0 = nunca teve cert
  label:      string
}
```

- [ ] **Criar `html/src/stores/useAdrStore.ts`:**

```ts
import { create } from 'zustand'
import type { AdrCert } from '../types'

interface AdrStore {
  certs:    AdrCert[]
  setCerts: (certs: AdrCert[]) => void
  upsertCert: (adrType: string, expiresAt: number) => void
}

export const useAdrStore = create<AdrStore>((set) => ({
  certs: [],

  setCerts: (certs) => set({ certs }),

  upsertCert: (adrType, expiresAt) => set((state) => {
    const existing = state.certs.find((c) => c.adr_type === adrType)
    if (existing) {
      return { certs: state.certs.map((c) =>
        c.adr_type === adrType ? { ...c, expires_at: expiresAt } : c
      )}
    }
    return { certs: [...state.certs, { adr_type: adrType, expires_at: expiresAt, label: adrType }] }
  }),
}))
```

- [ ] **Commit:**
```bash
git add html/src/types/index.ts html/src/stores/useAdrStore.ts
git commit -m "feat(adr): add AdrCert type, TabName adr, useAdrStore"
```

---

## Task 11: NUI — Componentes AdrCertCard e AdrPanel

**Files:**
- Create: `html/src/components/adr/AdrCertCard.tsx`
- Create: `html/src/components/adr/AdrPanel.tsx`

- [ ] **Criar `html/src/components/adr/AdrCertCard.tsx`:**

```tsx
import type { AdrCert } from '../../types'

// Todos os 6 tipos com metadados de exibição
const ADR_META: Record<string, { icon: string; color: string }> = {
  flammable_liquid: { icon: '🔥', color: 'text-orange-400' },
  flammable_gas:    { icon: '💨', color: 'text-yellow-400' },
  toxic:            { icon: '☠️', color: 'text-green-400'  },
  corrosive:        { icon: '⚗️', color: 'text-purple-400' },
  explosive:        { icon: '💥', color: 'text-red-400'    },
  environmental:    { icon: '🌿', color: 'text-emerald-400' },
}

// Todos os 6 tipos fixos (para exibir mesmo sem row no DB)
export const ALL_ADR_TYPES = [
  { adr_type: 'flammable_liquid', label: 'Líquidos Inflamáveis'      },
  { adr_type: 'flammable_gas',    label: 'Gases Inflamáveis'         },
  { adr_type: 'toxic',            label: 'Substâncias Tóxicas'       },
  { adr_type: 'corrosive',        label: 'Substâncias Corrosivas'    },
  { adr_type: 'explosive',        label: 'Explosivos'                },
  { adr_type: 'environmental',    label: 'Perigosas ao Meio Ambiente'},
]

interface Props {
  adrType:   string
  label:     string
  cert:      AdrCert | null
  onExam:    (adrType: string) => void
  onRenew:   (adrType: string) => void
}

export function AdrCertCard({ adrType, label, cert, onExam, onRenew }: Props) {
  const meta    = ADR_META[adrType] ?? { icon: '📄', color: 'text-zinc-400' }
  const now     = Math.floor(Date.now() / 1000)
  const isValid = cert && cert.expires_at > now
  const isExpired = cert && cert.expires_at <= now

  const expiresDate = cert
    ? new Date(cert.expires_at * 1000).toLocaleDateString('pt-BR')
    : null

  return (
    <div className="bg-zinc-800/60 border border-zinc-700/50 rounded-lg p-3 flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <span className="text-xl leading-none">{meta.icon}</span>
        <div className="flex-1 min-w-0">
          <div className={`text-[11px] font-semibold truncate ${meta.color}`}>{label}</div>
          {isValid && (
            <div className="text-[9px] text-zinc-400">Válida até {expiresDate}</div>
          )}
          {isExpired && (
            <div className="text-[9px] text-red-400">Expirada em {expiresDate}</div>
          )}
          {!cert && (
            <div className="text-[9px] text-zinc-500">Não certificado</div>
          )}
        </div>
        <div className={`text-[9px] px-1.5 py-0.5 rounded-full font-semibold ${
          isValid    ? 'bg-emerald-500/20 text-emerald-400' :
          isExpired  ? 'bg-red-500/20 text-red-400'         :
                       'bg-zinc-700 text-zinc-500'
        }`}>
          {isValid ? 'Válida' : isExpired ? 'Expirada' : 'Disponível'}
        </div>
      </div>

      {!isValid && (
        <button
          onClick={() => isExpired ? onRenew(adrType) : onExam(adrType)}
          className="w-full text-[10px] py-1.5 rounded bg-blue-600 hover:bg-blue-500 text-white font-medium transition-colors"
        >
          {isExpired ? 'Renovar' : 'Fazer Exame'}
        </button>
      )}
    </div>
  )
}
```

- [ ] **Criar `html/src/components/adr/AdrPanel.tsx`:**

```tsx
import { useAdrStore } from '../../stores/useAdrStore'
import { AdrCertCard, ALL_ADR_TYPES } from './AdrCertCard'
import type { AdrCert } from '../../types'

export function AdrPanel() {
  const { certs, upsertCert } = useAdrStore()

  const certMap: Record<string, AdrCert> = {}
  certs.forEach((c) => { certMap[c.adr_type] = c })

  const handleExam = (adrType: string) => {
    // O exame acontece no cliente Lua via ox_target / lib.inputDialog.
    // Aqui apenas abrimos o PDA no NPC — informar usuário para ir ao examinador.
    // Se já estiver no NPC, o exam flow é disparado via event Lua.
    // Este botão serve como fallback: abre o GPS via SendNUIMessage.
    fetch(`https://AUST_trucker/setAdrGps`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ adrType }),
    })
  }

  const handleRenew = async (adrType: string) => {
    const res = await fetch(`https://AUST_trucker/renewAdrCert`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ adrType }),
    }).then((r) => r.json()) as { success: boolean; expiresAt?: number; reason?: string }

    if (res.success && res.expiresAt) {
      upsertCert(adrType, res.expiresAt)
    }
  }

  return (
    <div className="p-4 space-y-4">
      <div>
        <h2 className="text-sm font-semibold text-zinc-200">Licenças ADR</h2>
        <p className="text-[11px] text-zinc-500 mt-0.5">
          Certificações exigidas para transporte de carga perigosa. Válidas por 30 dias.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-2">
        {ALL_ADR_TYPES.map(({ adr_type, label }) => (
          <AdrCertCard
            key={adr_type}
            adrType={adr_type}
            label={certMap[adr_type]?.label ?? label}
            cert={certMap[adr_type] ?? null}
            onExam={handleExam}
            onRenew={handleRenew}
          />
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Commit:**
```bash
git add html/src/components/adr/
git commit -m "feat(adr): add AdrCertCard and AdrPanel components"
```

---

## Task 12: NUI — Integração em useNUI, TabBar e App

**Files:**
- Modify: `html/src/hooks/useNUI.ts`
- Modify: `html/src/components/layout/TabBar.tsx`
- Modify: `html/src/App.tsx` (ou arquivo raiz que renderiza os panels)

- [ ] **Adicionar `adrCerts` ao NUIMessage e ao caso `open` em `useNUI.ts`:**

No topo, adicionar ao import:
```ts
import { useAdrStore } from '../stores/useAdrStore'
import type { AdrCert } from '../types'
```

Na interface `NUIMessage`, adicionar:
```ts
adrCerts?: AdrCert[]
```

Dentro de `useNUI()`, adicionar:
```ts
const { setCerts, upsertCert } = useAdrStore()
```

No `case 'open':`, adicionar (após `setParty`):
```ts
setCerts(event.data.adrCerts ?? [])
```

Adicionar novo case para atualização pós-exame:
```ts
case 'adrCertGranted':
  if (event.data.adrType && event.data.expiresAt) {
    upsertCert(event.data.adrType as string, event.data.expiresAt as number)
  }
  break
```

Adicionar campos ao NUIMessage para o novo case:
```ts
adrType?:   string
expiresAt?: number
```

- [ ] **Adicionar aba ADR no `TabBar.tsx`** — localizar o array `TABS` e adicionar:

```ts
{ id: 'adr', label: 'ADR' },
```

Posicionar após `{ id: 'stats', label: 'Stats' }`.

<!-- NUI callbacks (setAdrGps, renewAdrCert) já adicionados ao client/adr.client.lua na Task 9. -->

- [ ] **Adicionar `<AdrPanel />` ao App** — localizar onde os outros panels são renderizados (provavelmente em `App.tsx` ou equivalente) e adicionar:

```tsx
import { AdrPanel } from './components/adr/AdrPanel'

// No switch/conditional de tabs:
{activeTab === 'adr' && <AdrPanel />}
```

- [ ] **Build da NUI:**
```bash
cd "E:\Users\Vinicius\Downloads\txData\Qbox_753251.base\resources\[standalone]\AUST_trucker\html"
npm run build
```

- [ ] **Testar no jogo:**
  - Abrir PDA → aba ADR deve aparecer
  - 6 cards devem aparecer com status "Disponível"
  - Botão "Fazer Exame" em qualquer card → marca GPS no examinador
  - Ir ao examinador → ox_target → questões → aprovação → card muda para "Válida"

- [ ] **Commit:**
```bash
git add html/src/ client/adr.client.lua
git commit -m "feat(adr): integrate ADR tab in NUI (useNUI, TabBar, App, NUI callbacks)"
```

---

## Task 13: CHANGELOG e version bump

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `fxmanifest.lua`

- [ ] **Atualizar `fxmanifest.lua`:** mudar `version '10.0.0'` para `version '11.0.0'`

- [ ] **Adicionar entrada ao `CHANGELOG.md`:**

```markdown
## [11.0.0] — 2026-03-20 — ADR Certifications

### Added
- **ADR Certifications System** (Fase 5 — Polimento)
  - 6 tipos de certificação: `flammable_liquid`, `flammable_gas`, `toxic`, `corrosive`, `explosive`, `environmental`
  - Exame com banco de questões (3 por tipo, 3 sorteadas), ≥2 corretas para aprovação
  - Expiração em 30 dias (`os.time() + 2592000`)
  - Renovação sem re-exame: taxa de 60% do valor original, paga do banco
  - Cooldown de 30 min após reprovação (cache em memória, não persiste em restart)
  - Jobs com carga hazmat aparecem bloqueados na UI para não-certificados
  - Validação server-side em `JobService.Accept` — não apenas client-side
- **NPC Examinador** (`client/adr.client.lua`)
  - Ped no Terminal Portuário A1, ox_target, lib.zones.sphere
  - Exame via `lib.inputDialog` multi-step
  - GPS marcado pelo PDA ao clicar "Fazer Exame"
- **React NUI** — aba "ADR" no TabBar
  - `useAdrStore` — Zustand store
  - `AdrCertCard` — card por tipo com status badge e botão contextual
  - `AdrPanel` — grid 2 colunas com 6 cards
- **Schema** (`import.sql`, `sql/update_adr_v11.sql`)
  - `trucker_adr_certs`: citizenid, adr_type ENUM, expires_at, UNIQUE KEY

### Modified
- `JobService.GetAvailable(citizenId)` — recebe citizenid para injetar `adrLocked` por job
- `JobService.Accept` — valida ADR server-side antes de aceitar
- `getInitialData` — inclui `adrCerts` e passa `citizenId` para `GetAvailable`
- `config/config.lua` — `Config.Adr` block + campo `adr` em produtos hazmat
```

- [ ] **Commit:**
```bash
git add CHANGELOG.md fxmanifest.lua
git commit -m "chore: bump version to 11.0.0, update CHANGELOG for ADR system"
```

---

## Checklist de Validação Final

- [ ] Resource inicia sem erros no console
- [ ] `DB_GetAdrCerts('test123')` retorna `{}` sem crash
- [ ] PDA abre com aba ADR mostrando 6 cards com status "Disponível"
- [ ] Job hazmat aparece na lista com ícone de cadeado para player sem cert
- [ ] Tentar aceitar job bloqueado via UI retorna mensagem de erro
- [ ] Ir ao NPC → fazer exame → aprovar → card muda para "Válida"
- [ ] Tentar novamente imediatamente → mensagem de cooldown com tempo restante
- [ ] Aguardar 30 dias (ou forçar expires_at no DB) → card muda para "Expirada"
- [ ] Clicar "Renovar" → taxa debitada → card volta para "Válida"
- [ ] Job hazmat desbloqueado após certificação
