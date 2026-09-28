# AUST_trucker — Refactor Completo: Design Spec

> **Para workers:** Use `superpowers:subagent-driven-development` ou `superpowers:executing-plans` para implementar o plano gerado a partir deste spec.

**Goal:** Refatorar o `AUST_trucker` de QBCore + JSON + lation_ui + vanilla JS para QBX + oxmysql + ox_lib + React/TypeScript, reestruturando o código em serviços modulares e preparando a arquitetura para integração com `AUST_sala`.

**Data:** 2026-03-19
**Versão alvo:** 3.0.0
**Status:** Aprovado

---

## Contexto

O `AUST_trucker` é um sistema completo de empresa de transporte (trucking) para FiveM. Atualmente usa:
- **QBCore** — incompatível com o stack do servidor (qbx_core)
- **Persistência JSON** (`companies.json`, `industries.json`, `player_stats.json`) — risco de corrupção em writes concorrentes
- **lation_ui** — dependência extra não padrão
- **Monolito** — `server.lua` (~2000 linhas), `script.js` (~3000 linhas)

O resource está em **desenvolvimento** (sem dados de produção), permitindo migração limpa sem scripts de migração legacy.

---

## Abordagem

**Layer-by-Layer em 3 fases sequenciais** dentro do mesmo repositório:

1. **Fase 1 — Backend Foundation:** JSON → oxmysql + QBCore → QBX + lation_ui → ox_lib (UI antiga mantida temporariamente)
2. **Fase 2 — Server Refactor:** `server.lua` monolítico → services modulares + exports para AUST_sala + jobs persistindo no DB
3. **Fase 3 — React UI:** html/ substituído por Vite + React + TypeScript + Tailwind

---

## Dois Sistemas de Indústria — Distinção Crítica

O resource tem **dois sistemas de indústria completamente separados** que servem propósitos diferentes:

### Sistema 1 — Roteamento de Jobs (config-only, sem DB)
`Config.PrimaryIndustries` + `Config.SecondaryIndustries`

- **25 origens** (primárias): onde o jogador carrega a carga. Cada origem tem produtos com nomes de string (ex: "Containers", "Combustível Marítimo") e `basePrice`.
- **24 destinos** (secundárias): onde o jogador entrega. Cada destino tem `acceptedProducts` (lista de nomes) e `multiplier`.
- `cargo_item` em `trucker_jobs` é o **nome string do produto** (ex: `"Containers"`), NÃO uma chave de ox_inventory.
- `JobService.GenerateBatch()` lê direto do config — **não precisa de tabela DB para este sistema**.

### Sistema 2 — Economy Trading (DB-backed)
`Config.Industries`

- **5 indústrias** com NPCs interativos onde jogadores compram/vendem itens.
- Usa **chaves de ox_inventory** (ex: `"food"`, `"meat"`, `"fuel"`, `"cement"`, `"chemicals"`).
- Preços dinâmicos (supply/demand) que persistem entre restarts.
- `trucker_industry_state` no DB rastreia apenas **este sistema**.

---

## Estrutura Final de Arquivos

```
AUST_trucker/
├── fxmanifest.lua
├── import.sql
├── config/
│   └── config.lua                         — shared_scripts (vector3/4, usado por client e server)
├── server/
│   ├── main.lua                           — init, VP_Trucker global, Ready flag
│   ├── database.lua                       — queries oxmysql centralizadas
│   ├── exports.lua                        — API pública para AUST_sala
│   ├── callbacks.lua                      — lib.callback.register (ox_lib)
│   ├── events.lua                         — RegisterNetEvent handlers
│   └── services/
│       ├── company_service.lua            — CRUD empresas, membros, veículos, balanço
│       ├── job_service.lua                — geração, aceitação, conclusão, abandono
│       ├── economy_service.lua            — preços dinâmicos, supply/demand
│       └── industry_service.lua          — estado indústrias trading, BuyFrom/SellTo
├── client/
│   ├── main.lua                           — init, keybind NUI, VP_Trucker client state
│   ├── jobs.lua                           — blips pickup/delivery, progresso, tracking
│   ├── industries.lua                     — spawn NPCs + ox_target + menus ox_lib
│   └── ui.lua                             — RegisterNUICallback handlers
└── html/
    ├── index.html
    ├── package.json
    ├── vite.config.ts
    ├── tailwind.config.ts
    └── src/
        ├── App.tsx
        ├── hooks/
        │   └── useNUI.ts
        ├── stores/
        │   ├── useAppStore.ts
        │   ├── useJobStore.ts
        │   ├── useCompanyStore.ts
        │   ├── useIndustryStore.ts
        │   └── useStatsStore.ts
        └── components/
            ├── layout/
            │   ├── TabBar.tsx
            │   └── Modal.tsx
            ├── jobs/
            │   ├── JobList.tsx
            │   ├── JobCard.tsx
            │   └── ActiveJob.tsx
            ├── company/
            │   ├── CompanySetup.tsx
            │   ├── CompanyPanel.tsx
            │   └── MemberList.tsx
            ├── garage/
            │   └── GaragePanel.tsx
            ├── industries/
            │   └── IndustryList.tsx
            └── stats/
                └── StatsPanel.tsx
```

---

## fxmanifest.lua — Load Order

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
version '3.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',    -- vector3/4 + Config usado por ambos server e client
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',                          -- VP_Trucker global (PRIMEIRO)
    'server/database.lua',                      -- helpers DB (antes dos services)
    'server/services/company_service.lua',
    'server/services/economy_service.lua',
    'server/services/industry_service.lua',
    'server/services/job_service.lua',          -- pode usar EconomyService
    'server/exports.lua',                       -- usa services
    'server/callbacks.lua',                     -- usa services
    'server/events.lua',                        -- usa services (ÚLTIMO)
}

client_scripts {
    'client/main.lua',                          -- VP_Trucker client global (PRIMEIRO)
    'client/jobs.lua',                          -- usa VP_Trucker.ActiveJob
    'client/industries.lua',                    -- spawn NPCs + targets
    'client/ui.lua',                            -- NUICallbacks (ÚLTIMO)
}

files {
    'html/index.html',
    'html/assets/*.js',
    'html/assets/*.css',
}

ui_page 'html/index.html'

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'qbx_core',
}
```

**Nota lua54:** Com `lua54 'yes'`, cada arquivo é um chunk isolado. Funções compartilhadas entre arquivos DEVEM ser globais (não `local`). Services são globais (`CompanyService = {}`, `JobService = {}`, etc.). `VP_Trucker` é global em `main.lua`, acessível por todos os outros arquivos server-side.

---

## Schema do Banco de Dados

```sql
-- Empresas de transporte
CREATE TABLE trucker_companies (
    id              VARCHAR(50)     PRIMARY KEY,
    owner_citizenid VARCHAR(50)     NOT NULL,
    name            VARCHAR(100)    NOT NULL,
    balance         INT             DEFAULT 0,
    is_recruiting   TINYINT(1)      DEFAULT 0,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- Membros das empresas (1 empresa por jogador)
CREATE TABLE trucker_company_members (
    citizenid       VARCHAR(50)     PRIMARY KEY,
    company_id      VARCHAR(50)     NOT NULL,
    role            ENUM('owner','manager','driver') DEFAULT 'driver',
    joined_at       TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (company_id) REFERENCES trucker_companies(id) ON DELETE CASCADE
);

-- Veículos registrados nas empresas
-- status: 'stored' = disponível no garage, 'out' = em uso pelo jogador
CREATE TABLE trucker_company_vehicles (
    plate           VARCHAR(20)     PRIMARY KEY,
    company_id      VARCHAR(50)     NOT NULL,
    model           VARCHAR(50)     NOT NULL,
    vehicle_type    VARCHAR(50)     NOT NULL,
    status          ENUM('stored','out') DEFAULT 'stored',
    added_at        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (company_id) REFERENCES trucker_companies(id) ON DELETE CASCADE
);

-- Jobs gerados (persistem entre restarts)
-- cargo_item = nome string do produto (ex: "Containers"), NÃO chave ox_inventory
CREATE TABLE trucker_jobs (
    id                  VARCHAR(50)     PRIMARY KEY,
    origin_id           VARCHAR(50)     NOT NULL,   -- id de Config.PrimaryIndustries
    dest_id             VARCHAR(50)     NOT NULL,   -- id de Config.SecondaryIndustries
    cargo_item          VARCHAR(100)    NOT NULL,   -- nome do produto (string label)
    trailer_model       VARCHAR(50)     NOT NULL,   -- modelo do trailer requerido
    base_payment        INT             NOT NULL,
    distance            FLOAT           NOT NULL,
    status              ENUM('available','active','completed','expired') DEFAULT 'available',
    assigned_citizenid  VARCHAR(50)     NULL,
    company_id          VARCHAR(50)     NULL,
    expires_at          TIMESTAMP       NOT NULL,
    accepted_at         TIMESTAMP       NULL,
    completed_at        TIMESTAMP       NULL,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_status    (status),
    INDEX idx_assigned  (assigned_citizenid)
);

-- Estatísticas por jogador
CREATE TABLE trucker_player_progression (
    citizenid           VARCHAR(50)     PRIMARY KEY,
    total_earnings      INT             DEFAULT 0,
    total_deliveries    INT             DEFAULT 0,
    total_distance      FLOAT           DEFAULT 0,
    joined_at           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- Estado dinâmico das indústrias de TRADING (apenas Config.Industries — 5 indústrias)
-- Não cobre Config.PrimaryIndustries/SecondaryIndustries (config-only)
CREATE TABLE trucker_industry_state (
    industry_id         VARCHAR(50)     NOT NULL,   -- id de Config.Industries
    item                VARCHAR(50)     NOT NULL,   -- chave ox_inventory (ex: "food")
    entry_type          ENUM('production','consumption') NOT NULL,
    current_price       INT             NOT NULL,
    current_stock       INT             DEFAULT 0,
    next_production_time TIMESTAMP      NULL,
    PRIMARY KEY (industry_id, item, entry_type)
);

-- Infrações registradas pelo AUST_sala
CREATE TABLE trucker_infractions (
    id              INT             AUTO_INCREMENT PRIMARY KEY,
    citizenid       VARCHAR(50)     NOT NULL,
    job_id          VARCHAR(50)     NULL,
    infraction_type VARCHAR(50)     NOT NULL,   -- 'overload'|'no_manifest'|'expired_manifest'|'dangerous_cargo'
    reason          TEXT            NOT NULL,
    -- issued_by = citizenid do inspetor SALA OU identificador de sistema (ex: 'AUST_sala:auto')
    issued_by       VARCHAR(100)    NOT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_citizenid (citizenid)
);
```

### Notas do schema

| Decisão | Motivo |
|---------|--------|
| `trucker_jobs.cargo_item` é string label | Vem de `Config.PrimaryIndustries.products[].name`, não é item ox_inventory |
| `trucker_jobs.trailer_model` adicionado | Necessário para GaragePanel mostrar compatibilidade e para manifesto |
| `trucker_company_vehicles.status` adicionado | GaragePanel precisa diferenciar veículos disponíveis de em uso |
| `trucker_industry_state` cobre apenas Config.Industries | Config.PrimaryIndustries/SecondaryIndustries são config-only (sem DB) |
| `issued_by VARCHAR(100)` | Aceita citizenid (50 chars) OU identificador de sistema como 'AUST_sala:auto' |
| `ON DELETE CASCADE` em members/vehicles | Deletar empresa limpa automaticamente |
| `airport_warehouse` — corrigir duplicata no config | PrimaryIndustries: renomear para `lsia_warehouse_cargo`; SecondaryIndustries: renomear para `lsia_warehouse_south`. Estes IDs canônicos são usados nos campos `origin_id`/`dest_id` de `trucker_jobs` — devem estar alinhados entre config e DB. |

---

## Arquitetura Server-side

### Global State (server/main.lua)

```lua
VP_Trucker = {
    Ready      = false,
    Companies  = {},   -- cache: companyId → data
    ActiveJobs = {},   -- cache: jobId → data (sincronizado com DB)
    PlayerJobs = {},   -- cache: citizenid → jobId
}
```

### Services — API Pública (todos globais por lua54)

#### CompanyService (`server/services/company_service.lua`)
```lua
CompanyService = {}

CompanyService.Create(citizenId, name)              -- cria empresa ($150k)
CompanyService.Get(companyId)                       -- retorna data do cache
CompanyService.GetByMember(citizenId)               -- empresa do jogador
CompanyService.GetRecruiting()                      -- lista de empresas recrutando
CompanyService.AddMember(companyId, citizenId)      -- join
CompanyService.RemoveMember(citizenId)              -- leave/kick
CompanyService.SetRecruiting(companyId, bool)       -- toggle recruitment
CompanyService.Deposit(companyId, citizenId, amount)
CompanyService.Withdraw(companyId, citizenId, amount)
CompanyService.RegisterVehicle(companyId, plate, model, vehicleType)
CompanyService.RemoveVehicle(plate)
CompanyService.SetVehicleStatus(plate, status)      -- 'stored'|'out'
CompanyService.Sell(companyId, src)                 -- dissolve + paga $25k ao owner
```

#### JobService (`server/services/job_service.lua`)
```lua
JobService = {}

JobService.GenerateBatch()                          -- gera até 8 jobs a partir do config, salva no DB
JobService.GetAvailable()                           -- jobs com status='available'
JobService.LoadFromDB()                             -- carrega jobs ativos no restart
JobService.Accept(jobId, citizenId, companyId)      -- status→active, assignment no DB
-- payload = { deliveryTime: number (segundos desde acceptedAt), plate: string }
JobService.Complete(citizenId, payload)             -- calcula pagamento com bônus de tempo, atualiza stats
-- Regra de expiração no abandon: verificar expires_at antes de restaurar status
-- SE expires_at < NOW() → status = 'expired' (não recolocar job expirado como disponível)
-- SE expires_at >= NOW() → status = 'available', limpa assignment
JobService.Abandon(citizenId)
JobService.GetActiveByPlayer(citizenId)             -- job ativo: { jobId, originName, destName, cargoItem, trailerModel, payment, acceptedAt }
JobService.GetManifest(citizenId)                   -- manifesto: { plate, cargo, trailerModel, origin, destination, companyName, issuedAt }
JobService.RecordInfraction(citizenId, type, reason, issuedBy)
JobService.ExpireStale()                            -- cron: marca jobs expirados, limpa assignments
```

**Nota `JobService.Complete` payload:**
```lua
-- Enviado pelo client via TriggerServerEvent após detecção de chegada na zona de entrega
-- payload = {
--   deliveryTime = 423,   -- segundos decorridos desde acceptedAt
--   plate        = "ABC1234"  -- placa do veículo usado (para manifesto)
-- }
-- Bônus de tempo calculado com Config.JobGeneration.timeBonus
```

#### EconomyService (`server/services/economy_service.lua`)
```lua
EconomyService = {}

EconomyService.Init()                               -- carrega estado do DB ou seed do config
EconomyService.UpdatePrices()                       -- ciclo 20min: ajusta preços por supply/demand
EconomyService.GetPrice(industryId, item)
EconomyService.RecordSale(industryId, item, qty)    -- jogador vendeu → diminui stock
EconomyService.RecordPurchase(industryId, item, qty) -- jogador comprou → aumenta stock
```

#### IndustryService (`server/services/industry_service.lua`)
```lua
IndustryService = {}

-- Apenas Config.Industries (sistema de trading com ox_inventory)
IndustryService.GetAll()                            -- todas as 5 indústrias com estado atual
IndustryService.Get(industryId)
IndustryService.BuyFrom(src, industryId, item, qty) -- jogador compra item de produção
IndustryService.SellTo(src, industryId, item, qty)  -- jogador vende item de consumo
-- ATENÇÃO: indústrias terciárias (ex: twentyfourseven_dist) têm production = nil
-- RunProductionCycle DEVE verificar industry.production ~= nil antes de produzir
-- Apenas processar consumo para indústrias terciárias
IndustryService.RunProductionCycle()                -- cron: produção primária (1min) e secundária (10min)
```

### Callbacks (ox_lib — `server/callbacks.lua`)

```lua
-- Substitui QBCore.Functions.CreateCallback
lib.callback.register('AUST_trucker:getInitialData', function(source)
    -- retorna { jobs, company, activeJob, stats, recruitingCompanies }
end)
lib.callback.register('AUST_trucker:getCompanyMembers', function(source, companyId) end)
lib.callback.register('AUST_trucker:getPlayerStats', function(source) end)
lib.callback.register('AUST_trucker:getIndustries', function(source) end)
```

---

## Exports para AUST_sala (`server/exports.lua`)

```lua
-- Job ativo de um jogador (inspeção SALA em tempo real)
-- @param citizenId string  citizenid do jogador
-- @return table|nil { jobId, originName, destName, cargoItem, trailerModel, payment, acceptedAt }
exports('GetPlayerActiveJob', function(citizenId)
    return JobService.GetActiveByPlayer(citizenId)
end)

-- Manifesto de transporte (documento para fiscalização física)
-- @return table|nil { plate, cargo, trailerModel, origin, destination, companyName, issuedAt }
exports('GetJobManifest', function(citizenId)
    return JobService.GetManifest(citizenId)
end)

-- Dados da empresa para auditoria SALA
-- @return table|nil { id, name, ownerCitizenId, balance, memberCount, vehicleCount }
exports('GetCompanyInfo', function(companyId)
    return CompanyService.Get(companyId)
end)

-- Empresa de um jogador (para SALA verificar vínculo empregatício)
-- @return table|nil
exports('GetPlayerCompany', function(citizenId)
    return CompanyService.GetByMember(citizenId)
end)

-- SALA registra infração no histórico do motorista
-- @param citizenId      string  citizenid do infrator
-- @param infractionType string  'overload'|'no_manifest'|'expired_manifest'|'dangerous_cargo'
-- @param reason         string  descrição da infração
-- @param issuedBy       string  citizenid do inspetor OU 'AUST_sala:auto' (sistema)
-- @return boolean
exports('RecordInfraction', function(citizenId, infractionType, reason, issuedBy)
    return JobService.RecordInfraction(citizenId, infractionType, reason, issuedBy)
end)

-- Histórico de infrações para MDT SALA
-- @return table[]  lista ordenada por created_at DESC
exports('GetInfractions', function(citizenId)
    return MySQL.query.await(
        'SELECT * FROM trucker_infractions WHERE citizenid = ? ORDER BY created_at DESC',
        { citizenId }
    )
end)
```

### Eventos disparados (AUST_sala pode escutar via AddEventHandler)

```lua
TriggerEvent('AUST_trucker:jobAccepted',         citizenId, companyId, jobData)
TriggerEvent('AUST_trucker:jobCompleted',        citizenId, companyId, jobData, payment)
TriggerEvent('AUST_trucker:infractionRecorded',  citizenId, infractionData)
```

---

## Arquitetura Client-side

### Globals client (definidos em `client/main.lua`, acessíveis pelos outros arquivos)

```lua
-- VP_Trucker é global (lua54 chunk isolation — outros arquivos acessam diretamente)
VP_Trucker = {
    IsNUIOpen = false,
    ActiveJob = nil,    -- jobs.lua pode ESCREVER aqui diretamente
    CompanyId = nil,
}
```

**Contrato de mutação:** `client/jobs.lua` escreve em `VP_Trucker.ActiveJob` diretamente (sem evento local) quando job é aceito, completado ou abandonado. `client/ui.lua` lê `VP_Trucker.ActiveJob` para contexto nos NUICallbacks. `client/industries.lua` não toca `VP_Trucker`.

### `client/main.lua`
- Define global `VP_Trucker`
- `RegisterKeyMapping('AUST_trucker_open', 'Abrir Painel Trucker', 'keyboard', 'F6')`
- `OpenNUI()`: `lib.callback.await('AUST_trucker:getInitialData')` → `SendNUIMessage({action='open', data=...})` → `SetNuiFocus(true, true)`
- `CloseNUI()`: `SetNuiFocus(false, false)` → `SendNUIMessage({action='close'})`

### `client/jobs.lua`
- Gerencia blips: pickup (azul, sprite 227) e delivery (verde, sprite 227 + rota ativada)
- Thread de distância: ativa apenas com `VP_Trucker.ActiveJob ~= nil`, atualiza NUI via `SendNUIMessage({action='updateActiveJob', ...})` a cada 5s
- Detecção de chegada na zona de entrega (`< 15m` das coords do destino) → `lib.showTextUI` → key E → `TriggerServerEvent('AUST_trucker:completeJob', { deliveryTime=..., plate=... })`
- Eventos recebidos:
  - `AUST_trucker:client:jobStarted` → escreve `VP_Trucker.ActiveJob`, cria blip pickup
  - `AUST_trucker:client:jobPickedUp` → remove blip pickup, cria blip delivery
  - `AUST_trucker:client:jobCompleted` → limpa `VP_Trucker.ActiveJob`, remove blips, `SendNUIMessage({action='updateActiveJob', data=nil})`
  - `AUST_trucker:client:jobAbandoned` → idem

### `client/industries.lua`
- Loop de spawn: para cada industria em `Config.Industries`, cria ped NPC
- Padrão de spawn:
  ```lua
  lib.requestModel(model)
  local ped = CreatePed(4, model, coords.x, coords.y, coords.z, heading, false, true)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  exports.ox_target:addLocalEntity(ped, { { name=..., label=..., onSelect=... } })
  ```
- Cleanup obrigatório em `AddEventHandler('onResourceStop', ...)`: `DeleteEntity(ped)` + `exports.ox_target:removeLocalEntity(ped)`
- Menu ao interagir: `lib.registerContext` + `lib.showContext` com opções comprar/vender por item
- Preços buscados via `lib.callback.await('AUST_trucker:getIndustries')` ao abrir menu

### `client/ui.lua`
Todos os `RegisterNUICallback`:

| Callback | Ação |
|----------|------|
| `acceptJob` | TriggerServerEvent |
| `abandonJob` | TriggerServerEvent |
| `createCompany` | TriggerServerEvent |
| `joinCompany` | TriggerServerEvent |
| `leaveCompany` | TriggerServerEvent |
| `sellCompany` | TriggerServerEvent |
| `toggleRecruiting` | TriggerServerEvent |
| `depositMoney` | TriggerServerEvent |
| `withdrawMoney` | TriggerServerEvent |
| `registerVehicle` | TriggerServerEvent (registra veículo atual por GetVehiclePedIsIn) |
| `removeVehicle` | TriggerServerEvent |
| `kickMember` | TriggerServerEvent |
| `buyFromIndustry` | TriggerServerEvent |
| `sellToIndustry` | TriggerServerEvent |
| `closeUI` | CloseNUI() local |

---

## NUI React + TypeScript

### Stack
```json
{
  "dependencies": {
    "react": "^18",
    "react-dom": "^18",
    "zustand": "^4",
    "clsx": "^2"
  },
  "devDependencies": {
    "typescript": "^5",
    "vite": "^5",
    "@vitejs/plugin-react": "^4",
    "tailwindcss": "^3",
    "autoprefixer": "^10"
  }
}
```

### Stores Zustand

```typescript
// useAppStore    — isOpen: bool, activeTab: string, hasCompany: bool
// useJobStore    — jobs: Job[], activeJob: ActiveJob|null, selectedJobId: string|null
// useCompanyStore — company: Company|null, members: Member[], vehicles: Vehicle[], recruitingList: Company[]
// useIndustryStore — industries: Industry[]
// useStatsStore  — totalEarnings: number, totalDeliveries: number, totalDistance: number
```

### Hook `useNUI` — ações completas

```typescript
// Todas as ações que o Lua pode enviar via SendNUIMessage:
type NUIAction =
    | 'open'            // dados iniciais: { jobs, company, activeJob, stats, recruitingCompanies }
    | 'close'
    | 'updateJobs'      // { jobs: Job[] }
    | 'updateActiveJob' // { activeJob: ActiveJob | null }
    | 'updateCompany'   // { company: Company | null }
    | 'updateMembers'   // { members: Member[] }
    | 'updateVehicles'  // { vehicles: Vehicle[] }
    | 'updateStats'     // { stats: Stats }
    | 'updateIndustries'// { industries: Industry[] }

// fetchNUI<T>(endpoint, data?) → Promise<T>
// wrapper de fetch para https://AUST_trucker/{endpoint}
```

### Tipos TypeScript principais

```typescript
interface Job {
    id: string
    originName: string
    destName: string
    cargoItem: string        // nome string do produto (ex: "Containers")
    trailerModel: string
    basePayment: number
    distance: number
    expiresAt: number        // timestamp ms
    companyId?: string
}

interface ActiveJob extends Job {
    acceptedAt: number       // timestamp ms
    stage: 'pickup' | 'delivering'
    distanceRemaining?: number
}

interface Company {
    id: string
    name: string
    balance: number
    isRecruiting: boolean
    memberCount: number
    vehicleCount: number
    role: 'owner' | 'manager' | 'driver'
}

interface Vehicle {
    plate: string
    model: string
    vehicleType: string
    status: 'stored' | 'out'
}
```

### Design visual (Tailwind)

```
bg-zinc-900   → fundo principal
bg-zinc-800   → cards e painéis
bg-zinc-700   → hover states
text-zinc-100 → texto primário
text-zinc-400 → texto secundário
blue-500      → ações primárias, jobs disponíveis
green-500     → entrega ativa, sucesso
red-500       → urgente (<5min), erro
amber-500     → aviso (<15min)
```

### Urgência de jobs (JobCard.tsx)

```typescript
const urgencyClass = minutesLeft < 5
    ? 'border-red-500 bg-red-500/10'
    : minutesLeft < 15
    ? 'border-amber-500 bg-amber-500/10'
    : 'border-zinc-700'
```

---

## Melhorias incluídas no refactor

| Problema original | Solução |
|------------------|---------|
| JSON corrompe em writes concorrentes | oxmysql com transações |
| Jobs somem no restart | `trucker_jobs` no DB + `JobService.LoadFromDB()` no init |
| Sem rate limiting | Guard de ação por player nos handlers de events.lua |
| Trading sem validação de permissão | Verificação de citizenid e company antes de BuyFrom/SellTo |
| `server.lua` 2000 linhas | 4 services + callbacks + events |
| `script.js` 3000 linhas | Componentes React isolados por responsabilidade |
| lation_ui | ox_lib context menus (padrão do stack) |
| QBCore incompatível com qbx_core | QBX nativo |
| Status de veículos não rastreado | `status ENUM('stored','out')` em trucker_company_vehicles |
| ID duplicado `airport_warehouse` no config | Corrigir antes de implementar: renomear um dos dois |

---

## Fora do Escopo deste Refactor

- Integração funcional com AUST_sala (apenas preparar arquitetura/exports)
- Sistema de ranking/achievement
- Mecânicas de veículo (combustível, dano)
- Novos tipos de missão
- Port do 0r-towtruck (projeto separado)
- Migração de dados de produção (resource ainda em desenvolvimento)

---

## Dependências

```
qbx_core    ox_lib    ox_inventory    ox_target    oxmysql
```

Sem dependências opcionais.
