# AURP Trucker — Guia de Staff

## Instalação

### 1. Dependências obrigatórias
```
oxmysql
ox_lib
ox_inventory
ox_target
```
**Framework** (apenas uma das opções):
```
qbx_core   ← se Config.Framework = 'qbx'
qb-core    ← se Config.Framework = 'qbcore'
es_extended ← se Config.Framework = 'esx'
```

### 2. Configuração de framework (v17)
Edite `config/config.lua` **antes** de iniciar o resource:
```lua
Config.Framework = 'qbx'   -- 'qbx' | 'qbcore' | 'esx'
```

### 3. Banco de dados
**Fresh install (v17+):** **nenhuma ação necessária** — as tabelas são criadas automaticamente no primeiro `start AUST_trucker` via `SchemaService.EnsureTables()`. Não é necessário executar `import.sql`.

**Atualização de v15 ou anterior:**

| De → Para | Ação |
|---|---|
| v15.x → v16.x | Executar `sql/update_loan_collateral_v16.sql` |
| v16.x → v17.x | Nenhuma — `SchemaService` aplica migrações automaticamente |

**Atualizações anteriores** (informação histórica):

| De → Para | Arquivo |
|---|---|
| v5.x → v6.x | `sql/update_company_levels.sql` — adiciona `company_level`, `company_xp` |
| v6.x → v7.x | `sql/update_simulation.sql` — adiciona `fuel_level`, `fatigue`, `fleet_upgrades` |
| v7.x → v8.x | `sql/update_economy_v8.sql` — adiciona `last_npc_fill_at`, `npc_completed`, `total_earned` |
| v10.x → v11.x | `sql/update_adr_v11.sql` — cria `trucker_adr_certs` |
| v11.x → v12.x | `sql/update_forklift_v12.sql` — adiciona `cargo_qty` em `trucker_jobs` |
| v13.x → v14.x | `sql/update_cargo_theft_v14.sql` — adiciona `truck_plate` + `has_gps_tracker` |
| v15.x → v16.x | `sql/update_loan_collateral_v16.sql` — adiciona `vehicle_plate` em `trucker_loans` |

| Tabela | Uso |
|---|---|
| `trucker_companies` | Empresas |
| `trucker_company_members` | Membros e cargos |
| `trucker_company_vehicles` | Veículos registrados + `has_gps_tracker` (v14) |
| `trucker_jobs` | Jobs gerados e histórico + `cargo_qty` (v12) + `truck_plate` (v14) + `weight` (v18) |
| `trucker_industry_state` | Estoques das indústrias |
| `trucker_industry_ownership` | Propriedade de indústrias |
| `trucker_player_progression` | XP, nível, rank, skill points |
| `trucker_player_skills` | Níveis de cada skill por jogador |
| `trucker_adr_certs` | Certificações ADR por jogador (v11) |
| `trucker_loans` | Empréstimos ativos e histórico |
| `trucker_npc_drivers` | Motoristas NPC contratados (v10) |
| `trucker_npc_jobs` | Histórico de jobs de motoristas NPC (v10) |
| `trucker_repo_orders` | Ordens de repossessão |
| `trucker_infractions` | Infrações de motoristas |
| `trucker_parties` | Grupos e parties de caminhoneiros para comboios |
| `trucker_convoy_jobs` | Jobs de comboio com multiplicador de bônus |
| `trucker_convoy_members` | Membros vinculados a um comboio ativo |
| `trucker_convoy_payments` | Registro e conciliação de pagamentos de comboio (v20.1) |
| `trucker_contracts` | Contratos de frete empresa↔cliente (v18) |
| `trucker_contract_stops` | Paradas dos contratos (v18) |
| `trucker_client_relationships` | Relacionamento empresa↔cliente com trust level (v18.1) |
| `trucker_shop_stock` | Ecossistema de reabastecimento de lojas e consumo dinâmico (v16) |

### 4. fxmanifest / server.cfg
O resource já vem configurado. Verifique se as dependências estão na ordem correta no seu `server.cfg`:
```
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core      # ou qb-core ou es_extended, conforme Config.Framework
ensure AUST_trucker
```

**Permissões e webhook (obrigatório revisar ao atualizar para 20.7.7+):**
```
# Painel /truckeradmin e todas as ações admin: só a ACE dedicada (ACEs genéricas 'command'/'admin' NÃO valem mais)
add_ace group.admin command.truckeradmin allow

# Webhook do Discord das encomendas (opcional). Use `set` (NÃO `setr`): o valor não pode ir ao client
set aurp_trucker_parcel_webhook "https://discord.com/api/webhooks/..."
```
Os admins de framework (QBX/QBCore `admin`/`god`, ESX `admin`/`superadmin`/`owner`) continuam reconhecidos.

---

## Configuração — config/config.lua

### Jobs (`Config.JobGeneration`)
```lua
Config.JobGeneration = {
    maxActiveJobs = 8,          -- jobs disponíveis simultâneos
    refreshInterval = 1800000,  -- ms entre gerações (30 min)
    jobExpiration = {
        minTime = 600,   -- 10 min (jobs caros expiram mais rápido)
        maxTime = 2400,  -- 40 min (jobs baratos duram mais)
        basePayment = 1000,
    },
    distanceMultiplier = 0.05,  -- $$ por km de distância
    timeBonus = {
        fast   = { time = 300, multiplier = 1.2 },  -- <5 min: +20%
        normal = { time = 600, multiplier = 1.0 },  -- <10 min: base
        slow   = { time = 900, multiplier = 0.8 },  -- >10 min: -20%
    }
}
```

### Economia dinâmica (`Config.Economy`)
```lua
Config.Economy = {
    priceUpdateInterval          = 1200000, -- ms entre atualizações (20 min)
    primaryProductionInterval    = 60000,   -- ms por unidade produzida (primária)
    secondaryProductionInterval  = 600000,  -- ms por unidade produzida (secundária)
    priceFloor   = 0.5,   -- preço mínimo = 50% do base
    priceCeiling = 2.0,   -- preço máximo = 200% do base
    priceAdjustmentSpeed = 0.15,  -- variação por ciclo (15%)
}
```

### Empréstimos (`Config.Loans`)
```lua
Config.Loans = {
    MinAmount       = 10000,   -- valor mínimo
    MaxAmount       = 500000,  -- valor máximo
    InterestRate    = 0.05,    -- juros 5%
    NumInstallments = 4,       -- parcelas
    InstallmentDays = 7,       -- dias entre parcelas
    PenaltyRate     = 0.15,    -- multa por atraso 15%
    CheckInterval   = 300,     -- segundos entre verificações de atraso
    AutoDebit         = true,  -- tenta debitar a parcela vencida (banco do jogador online / cofre da empresa)
    MaxMissedPayments = 3,     -- parcelas perdidas seguidas até virar 'defaulted' (inadimplente)
    BankerLocation  = vector3(-2962.6, 485.6, 15.7),  -- Paleto Bay
    BankerPed       = 'ig_bankman',
    BankerHeading   = 90.0,
}
```

**Calote:** a cada parcela vencida o sistema tenta o débito automático. Sem saldo (ou jogador offline), aplica a
multa (`PenaltyRate`) e conta uma parcela perdida. Ao atingir `MaxMissedPayments` o empréstimo vira `defaulted`:
para de acumular multa, bloqueia novos empréstimos e a venda da empresa, e só sai quitando o saldo total.

### Progressão de Empresa (`Config.CompanyLevels` e `Config.CompanyXpPerDelivery`)

As empresas acumulam XP a cada entrega concluída por qualquer membro e sobem de nível automaticamente (30 níveis). Cada nível desbloqueia mais vagas de veículo, mais membros permitidos e um bônus percentual no pagamento das entregas.

```lua
Config.CompanyXpPerDelivery = 50  -- XP por entrega (padrão)

-- Exemplo das primeiras e últimas entradas de Config.CompanyLevels:
Config.CompanyLevels = {
    { level = 1,  xpRequired = 0,     vehicles = 2, members = 5,  bonus = 1.00 },
    { level = 2,  xpRequired = 500,   vehicles = 2, members = 5,  bonus = 1.002 },
    -- ... (30 entradas, definidas em config/config.lua)
    { level = 30, xpRequired = 14500, vehicles = 5, members = 20, bonus = 1.06 },
}
```

| Campo | Significado |
|---|---|
| `xpRequired` | XP acumulado total da empresa para atingir este nível |
| `vehicles` | Slots de veículo liberados neste nível (máx. 5) |
| `members` | Máximo de membros neste nível (máx. 20) |
| `bonus` | Multiplicador de pagamento (1.06 = +6% sobre o valor base) |

Para resetar o nível de uma empresa:
```sql
UPDATE trucker_companies SET company_level = 1, company_xp = 0 WHERE id = 'COMPANY_ID';
```

### Repo Man (`Config.RepoMan`)
```lua
Config.RepoMan = {
    PoolInterval      = 1800,  -- segundos entre verificações do pool (30 min)
    MaxNpcOrders      = 5,     -- máximo de ordens NPC simultâneas
    NpcOrderExpiry    = 7200,  -- segundos para expirar ordem NPC (2h)
    LoanOrderExpiry   = 86400, -- segundos para expirar ordem de loan (24h)
    NpcMissionWeights = { simple = 70, npc_hostile = 30 }, -- % de chance

    PaymentRate    = 0.15,  -- motorista recebe 15% do valor do veículo
    CompanyFeeRate = 0.20,  -- empresa recebe 20% do pagamento do motorista
    TypeMultipliers = {
        simple      = 1.0,
        npc_hostile = 1.5,
        pvp         = 2.0,
        stealth     = 2.5,
    },

    DefaultVehicleValue = 50000,  -- valor padrão se modelo não estiver mapeado
    VehicleValues = {
        flatbed = 80000,
        hauler  = 120000,
        phantom = 150000,
        mule    = 60000,
        bison   = 45000,
    },

    ImpoundLocation = vector3(400.0, -1640.0, 29.0),  -- destino de entrega
    ImpoundHeading  = 90.0,
}
```

### Motoristas NPC (`Config.NpcDrivers`) — v10

```lua
Config.NpcDrivers = {
    maxDriversPerCompany = 5,
    agencyLocation       = vector3(-179.0, -1320.0, 31.3),
    agencyRadius         = 15.0,
    agencyRefreshSeconds = 86400,   -- rotação de perfis da agência (24h)
    cronIntervalMinutes  = 5,       -- frequência do tick de simulação

    hireCost = {
        junior = 2000,
        pleno  = 6000,
        senior = 15000,
    },
    trainingCost = {
        junior_to_pleno = 5000,
        pleno_to_senior = 12000,
    },
    trainingJobsRequired = {
        junior_to_pleno = 20,   -- jobs concluídos para promover junior → pleno
        pleno_to_senior = 50,   -- jobs concluídos para promover pleno → sênior
    },
    skillEfficiency = {
        junior = 0.80,  -- 80% do pagamento médio
        pleno  = 0.95,
        senior = 1.10,
    },
    -- satisfação: 0–100; abaixo de 20 há risco de demissão
    -- decai diariamente; sobe com bônus e resolução de eventos
}
```

### ADR (`Config.Adr`) — v11

> O banco de perguntas **com gabarito** fica em `server/adr_questions.lua` (`AdrExamBank`, só servidor).
> O client recebe apenas texto e opções, sorteados pelo servidor a cada tentativa.

```lua
Config.Adr = {
    ExaminerLocation     = vector3(361.62, -2541.45, 5.74),
    ExaminerPed          = 's_m_m_trucker_01',
    ExaminerHeading      = 180.0,
    ExaminerRadius       = 5.0,

    ValiditySeconds      = 30 * 86400,  -- validade: 30 dias
    RetryCooldownSeconds = 1800,        -- cooldown após reprovação: 30 min

    -- Taxa de exame por tipo (não reembolsável)
    ExamCost = {
        flammable_liquid = 5000,
        flammable_gas    = 6000,
        toxic            = 8000,
        corrosive        = 8000,
        explosive        = 15000,
        environmental    = 6000,
    },

    -- Taxa de renovação (sem re-exame, ~60% do custo)
    RenewalCost = {
        flammable_liquid = 3000,
        flammable_gas    = 3600,
        toxic            = 4800,
        corrosive        = 4800,
        explosive        = 9000,
        environmental    = 3600,
    },
}
```

Para adicionar ADR a um produto de origem, acrescente o campo `adr` na entrada do produto em `Config.PrimaryIndustries`:
```lua
{ name = "Combustível", trailer = "tanker", basePrice = 950, loadTime = 11000,
  icon = "fas fa-fire", adr = 'flammable_liquid' }
```
Tipos válidos: `flammable_liquid`, `flammable_gas`, `toxic`, `corrosive`, `explosive`, `environmental`.

### Forklift (`Config.Forklift`) — v12

```lua
Config.Forklift = {
    RentalCost    = 500,   -- $ debitado do banco ao alugar
    RefundAmount  = 250,   -- $ devolvidos ao retornar no spawn (raio 15m)

    ForkliftModel = 'forklift',
    PalletModel   = 'prop_pallet_05a',

    LoadDetectRadius = 3.0,   -- metros: distância máxima pallet → boot
    BootDoorRatio    = 0.75,  -- ângulo mínimo da porta traseira para detectar carregamento

    TradePoints = {
        -- Cada entrada é um mini-job standalone de empilhadeira:
        {
            id = 'walker_logistics', name = 'Walker Logistics',
            coords = vector3(153.81, -3214.60, 4.93),
            maxPallets = 5, basePay = 500, timeLimit = 180,  -- segundos
        },
        -- adicione mais entradas aqui
    },

    IndustrySpawns = {
        -- mapeie industryId → posição de spawn da empilhadeira
        ['terminal_a1'] = vector4(361.0, -2545.0, 5.74, 270.0),
    },
}
```

**Multiplicadores de pagamento no Trade Point** (não configurável — hardcoded no serviço):
| Tempo | Mult |
|---|---|
| ≤ 90s | ×1.3 |
| ≤ 150s | ×1.0 |
| > 150s | ×0.7 |

### Skills (`Config.Skills`) — v13

```lua
Config.Skills = {
    BonusPerLevel     = 0.02,   -- +2% por nível de skill ativo
    DistanceThreshold = 10.0,   -- km mínimos para ativar bônus Distance
    ValuableThreshold = 5000,   -- $ mínimos no base_payment para ativar Valuable
    FragileThreshold  = 85,     -- % mínimos de integridade entregue para ativar Fragile
}
```

Todos os thresholds são ajustáveis. `BonusPerLevel = 0.02` + 6 níveis = +12% máx por skill.

### Roubo de Carga (`Config.CargoTheft`) — v14

```lua
Config.CargoTheft = {
    VulnerableDelay = 30,       -- segundos parado sem motorista para ativar vulnerabilidade
    TheftDuration   = 20,       -- segundos do progress bar do roubo
    TheftRange      = 15.0,     -- distância máxima entre veículos para a transferência (metros)
    TheftBonus      = 0.25,     -- bônus de pagamento para carga roubada (+25% sobre base)
    GpsTrackerPrice = 5000,     -- $ cobrados do caixa da empresa para instalar GPS tracker
    VulnerableBlip  = true,     -- mostrar blip para todos ao tornar cargo vulnerável
    PoliceJob       = 'police', -- job que recebe alertas de roubo

    PoliceZones = {
        -- Zonas usadas para dar referência vaga aos policiais
        { name = 'Porto',           coords = vec3(361.0,   -2545.0,  5.7),   radius = 300.0 },
        { name = 'Zona Industrial', coords = vec3(100.0,   -1700.0, 29.0),   radius = 400.0 },
        -- adicione mais zonas conforme o mapa do servidor
    },
}
```

---

### Entrega de Encomendas / Parcel Delivery (`Config.ParcelDelivery`) — v19

O módulo de encomendas leves permite entregas porta a porta com veículos utilitários (vans, picapes como Rumpo, Speedo, Burrito, Bison).

```lua
Config.ParcelDelivery = {
    Enabled = true,
    Depots = {
        { id = 'depot_postop', name = 'Post OP Terminal', coords = vector3(-424.0, -2789.0, 6.0) },
        { id = 'depot_godrive', name = 'GoPostal Hub', coords = vector3(68.0, 120.0, 79.0) },
    },
    BoxProp = 'hei_prop_heist_box',
    CarryAnim = { dict = 'anim@heists@box_carry@', name = 'idle' },
    MaxStopsPerRoute = 6,
    RewardPerPackage = 350,
}
```

---

### Container Handler & Operações Portuárias (`Config.ContainerHandler`) — v20

O módulo portuário adiciona operações pesadas de logística intermodal com guindastes e empilhadeiras de contêiner (Reach Stacker / Handler).

```lua
Config.ContainerHandler = {
    Enabled = true,
    TerminalCoords = vector3(1194.0, -3252.0, 7.0),
    AllowedVehicles = { 'handler' },
    StackingGrid = {
        BayCount = 4,
        MaxHeight = 3,
        BaySpacing = 4.5,
    },
    BasePayPerMove = 850,
}
```

---

### Hardening de Segurança e Anti-Exploit — v20.1

A v20.1 introduz portões rígidos de validação e fail-closed no servidor:
1. **Transações de Indústria (`IndustryService.BuyFrom` / `SellTo`):**
   - O servidor verifica a distância do jogador até o ponto de entrega/coleta (`dist <= 15m`). Tentativas de acionamento remoto ou teletransporte falham imediatamente.
2. **Descarga de Petróleo Cru (`crude_oil.lua`):**
   - Validação de raio máximo de proximidade do tanque (`<= 25m`).
   - Verificação de tempo mínimo de descarga baseado na quantidade (`elapsed >= minUnloadTime + 5s`).
3. **Roubo de Carga (`CargoTheft`):**
   - Apenas o motorista (`seat -1`) pode iniciar o roubo.
   - A conclusão do roubo requer que a placa alvo bata com a registrada e que os veículos estejam dentro do raio de proximidade seguro.
4. **Guincho Flatbed (`flatbed.server.lua`):**
   - Operador deve estar a $\le 20\text{m}$ do guincho.
   - Veículo rebocado deve estar a $\le 18\text{m}$ do guincho.
   - Anti-self-attach: bloqueia tentativa de prender o próprio guincho em si mesmo.
   - Double-attach guard: bloqueia prender veículos já rebocados.
5. **Parties e Comboios (`PartyService` / `ConvoyService`):**
   - Convites possuem TTL de 60 segundos com expiração automática.
   - Tokens de convite são de uso único (one-time use).
   - Pagamentos de comboio offline são liquidados diretamente via banco de dados na conta bancária do jogador (`trucker_convoy_payments`), prevenindo perdas por disconnects.
6. **Timeouts em Callbacks:**
   - Proteção de barreira assíncrona com timeout estrito de 500 ticks em queries históricas para evitar congelamento de threads.

---

## Exports disponíveis

O resource expõe exports para integração com outros scripts (ex: AUST_sala):

```lua
-- Retorna o job ativo de um jogador (ou nil)
exports.AUST_trucker:GetPlayerActiveJob(source)

-- Retorna o manifesto completo de um job por ID
exports.AUST_trucker:GetJobManifest(jobId)

-- Retorna dados da empresa (id, nome, tipo, saldo)
exports.AUST_trucker:GetCompanyInfo(companyId)

-- Retorna o ID da empresa de um jogador (ou nil)
exports.AUST_trucker:GetPlayerCompany(citizenId)

-- Registra uma infração para um jogador
exports.AUST_trucker:RecordInfraction(citizenId, type, description)

-- Retorna lista de infrações de um jogador
exports.AUST_trucker:GetInfractions(citizenId)
```

---

## Adicionando Origens e Destinos

### Nova origem (indústria primária de jobs)
Em `config/config.lua`, dentro de `Config.PrimaryIndustries`, adicione:
```lua
{
    id = "id_unico",           -- sem espaços, sem acentos
    name = "Nome no Mapa",
    coords = vector3(x, y, z),
    type = "mixed",            -- mixed | construction | food | petrol | chemical
    products = {
        { name = "Nome da Carga", trailer = "trailers", basePrice = 700, loadTime = 8000, icon = "fas fa-box" }
    }
},
```

### Novo destino
Em `Config.SecondaryIndustries`:
```lua
{
    id = "id_unico",
    name = "Nome no Mapa",
    coords = vector3(x, y, z),
    type = "mixed",
    acceptedProducts = { "Nome da Carga", "Outra Carga" },  -- deve bater com o campo `name` da origem
    multiplier = 1.2,    -- multiplicador de preço (1.0 = base, 1.5 = +50%)
    unloadTime = 7000,   -- ms para descarregar
},
```

---

## Adicionando Indústrias (Compra/Venda de Itens)

Em `Config.Industries`, adicione uma entrada:
```lua
minha_industria = {
    id   = "minha_industria",
    name = "Nome da Indústria",
    welcomeMessage = "Bem-vindo!",
    coords = vector3(x, y, z),
    type = "secondary",  -- primary (só vende) | secondary (compra e vende) | tertiary (só compra)
    production = {
        item = "item_name",    -- nome do item no ox_inventory
        label = "Nome UI",
        productionPerHour = 20,
        maxStock = 500,
        unit = "caixas",
        basePrice = 200,
    },
    consumption = {
        { item = "raw_item", label = "Matéria-prima", consumptionPerHour = 10, maxStock = 200, unit = "unidades", basePrice = 80 }
    }
},
```

---

## Adicionando Veículos ao Repo Man

Em `Config.RepoMan.VehicleValues`, mapeie o modelo do veículo:
```lua
VehicleValues = {
    flatbed = 80000,
    hauler  = 120000,
    meu_veiculo = 95000,  -- adicione aqui
},
```

Em `Config.RepoMan.NpcVehicles`, adicione ao pool NPC:
```lua
NpcVehicles = {
    { model = 'mule',        label = 'Mule',        value = 60000 },
    { model = 'meu_veiculo', label = 'Meu Veículo', value = 95000 },  -- adicione aqui
},
```

---

## Limpeza do banco de dados

Queries úteis para manutenção:

```sql
-- Ver empresas ativas e seus donos
SELECT id, name, company_type, owner_citizenid, balance FROM trucker_companies;

-- Ver empréstimos ativos com inadimplência
SELECT * FROM trucker_loans WHERE status = 'active' AND next_payment_at < NOW();

-- Ver ordens de repo em aberto
SELECT id, vehicle_model, mission_type, status, expires_at FROM trucker_repo_orders WHERE status IN ('available', 'active');

-- Remover ordens expiradas manualmente
DELETE FROM trucker_repo_orders WHERE status = 'expired' AND created_at < DATE_SUB(NOW(), INTERVAL 7 DAY);

-- Ver top 10 jogadores por ganhos
SELECT citizenid, total_earnings, total_deliveries, level, rank FROM trucker_player_progression ORDER BY total_earnings DESC LIMIT 10;

-- Resetar progression de um jogador
UPDATE trucker_player_progression SET xp=0, level=1, rank=1, skill_points=0 WHERE citizenid = 'CIDID';
DELETE FROM trucker_player_skills WHERE citizenid = 'CIDID';

-- Deletar empresa e membros (ex: empresa problemática)
DELETE FROM trucker_company_members WHERE company_id = 'company_ID';
DELETE FROM trucker_companies WHERE id = 'company_ID';

-- Ver ranking de empresas por nível
SELECT id, name, company_type, company_level, company_xp FROM trucker_companies ORDER BY company_level DESC, company_xp DESC;

-- Resetar progressão de uma empresa
UPDATE trucker_companies SET company_level = 1, company_xp = 0 WHERE id = 'COMPANY_ID';

-- Forçar nível de empresa (ex: recompensa de staff)
UPDATE trucker_companies SET company_level = 10, company_xp = 3500 WHERE id = 'COMPANY_ID';

-- === ADR (v11) ===

-- Ver certificações de um jogador
SELECT citizenid, adr_type, expires_at FROM trucker_adr_certs WHERE citizenid = 'CIDID';

-- Conceder certificação manualmente (sem exame)
INSERT INTO trucker_adr_certs (citizenid, adr_type, expires_at)
VALUES ('CIDID', 'flammable_liquid', DATE_ADD(NOW(), INTERVAL 30 DAY))
ON DUPLICATE KEY UPDATE expires_at = DATE_ADD(NOW(), INTERVAL 30 DAY);

-- Revogar uma certificação
DELETE FROM trucker_adr_certs WHERE citizenid = 'CIDID' AND adr_type = 'explosive';

-- Limpar certidões expiradas
DELETE FROM trucker_adr_certs WHERE expires_at < NOW();

-- === Forklift (v12) ===

-- Ver jobs com múltiplos pallets ativos
SELECT id, assigned_citizenid, cargo_qty, status, created_at FROM trucker_jobs WHERE cargo_qty > 1 AND status = 'active';

-- === Cargo Theft (v14) ===

-- Ver jobs com caminhão vinculado (cargo monitorado)
SELECT id, assigned_citizenid, truck_plate, status FROM trucker_jobs WHERE truck_plate IS NOT NULL AND status = 'active';

-- Ver veículos com GPS tracker instalado
SELECT plate, company_id FROM trucker_company_vehicles WHERE has_gps_tracker = 1;

-- Remover GPS tracker de um veículo (ex: venda do veículo)
UPDATE trucker_company_vehicles SET has_gps_tracker = 0 WHERE plate = 'PLACA';

-- === NPC Drivers (v10) ===

-- Ver motoristas NPC por empresa
SELECT id, company_id, name, skill_level, satisfaction, status FROM trucker_npc_drivers WHERE company_id = 'company_ID';

-- Demitir motorista NPC manualmente
UPDATE trucker_npc_drivers SET status = 'fired' WHERE id = 'DRIVER_ID';

-- Ver jobs completados por NPC
SELECT driver_id, earnings, distance, completed_at FROM trucker_npc_jobs ORDER BY completed_at DESC LIMIT 20;
```

---

## Solução de Problemas

### Resource não inicia / erro no MySQL.ready
- Confirme que o `import.sql` foi executado e todas as 13 tabelas existem
- Confirme que `oxmysql` está listado antes de `AUST_trucker` no `server.cfg`

### Jobs não aparecem no menu
- Verifique se `VP_Trucker.Ready` é `true` no console: `print(VP_Trucker.Ready)` via txAdmin
- O primeiro batch de jobs é gerado assim que `Ready = true`. Se a tabela `trucker_jobs` estiver vazia, reinicie o resource

### NPC banqueiro não aparece
- Confirme as coordenadas em `Config.Loans.BankerLocation`
- O NPC usa `ig_bankman` — se o modelo não existir no servidor, troque por outro ped válido em `Config.Loans.BankerPed`

### Ordens Repo Man não aparecem
- Confirme que a empresa é do tipo `repo` (`SELECT company_type FROM trucker_companies WHERE id = '...'`)
- O pool NPC só gera se houver menos de `MaxNpcOrders` ordens `available` na tabela
- Verifique logs de erro no console para falhas em `RepoService.GenerateNPC`

### Empréstimo gera erro ao criar
- O bug de `total_amount` já foi corrigido na v5.1.0. Confirme que `server/database.lua` está na versão atual (sem `total_amount` no INSERT de `trucker_loans`)

### Skill points não funcionam
- Verifique se `trucker_player_skills` e `trucker_player_progression` têm a linha do jogador
- O upsert de stats acontece no evento `QBCore:Server:OnPlayerLoaded` — confirme que o evento está disparando

### Nível/XP de empresa não aparece na NUI
- Confirme que `sql/update_company_levels.sql` foi executado (ou que o `import.sql` atual foi usado)
- Verifique: `SELECT company_level, company_xp FROM trucker_companies WHERE id = '...';`
- O nível é calculado no servidor e enviado junto com os dados iniciais (`AUST_trucker:getInitialData`) — se a NUI abrir sem dados de nível, reinicie o resource

### Empresa não sobe de nível após entregas
- Confirme que `Config.CompanyXpPerDelivery` está definido (padrão: 50)
- Verifique se a empresa tem membros ativos completando entregas (`JobService.Complete` em `server/services/job_service.lua`)
- Os logs de `CompanyService.AddXP` no console mostrarão se o XP está sendo adicionado

### Cache desatualizado após reinício
- `VP_Trucker.Companies` e `VP_Trucker.PlayerCompanies` são recarregados a cada init via `LoadCompanies()` em `server/main.lua`
- Jobs ativos com status `active` voltam para `available` automaticamente no restart

### NPC Examinador ADR não aparece
- Confirme as coordenadas em `Config.Adr.ExaminerLocation`
- Verifique se `adr_service.lua` está carregando sem erros no console
- Confirme que `trucker_adr_certs` existe no banco: `SHOW TABLES LIKE 'trucker_adr_certs'`

### Job ADR aparece bloqueado mesmo com certificação válida
- Verifique a data de expiração: `SELECT expires_at FROM trucker_adr_certs WHERE citizenid = 'CIDID' AND adr_type = 'tipo'`
- O campo `adr` no produto da `Config.PrimaryIndustries` deve usar o nome exato do tipo (ex: `'flammable_liquid'`, não `'Líquido Inflamável'`)
- Reinicie o resource para forçar recarga do cache de certs

### Empilhadeira não detecta pallet carregado
- Confirme que `Config.Forklift.PalletModel` bate com o modelo spawned no servidor
- Aumente `LoadDetectRadius` se a detecção estiver muito restrita (padrão: 3.0m)
- `BootDoorRatio` controla o ângulo mínimo da porta — se o veículo não abrir completamente, reduza para 0.5

### Cargo Theft — carga não fica vulnerável
- Confirme que `acceptJob` está disparando `startCargoMonitoring` no client (veja `server/events.lua`)
- A thread de monitoramento inicia no client: verifique o console client por erros em `cargo_theft.client.lua`
- O `truck_plate` deve ser registrado via evento `registerTruckPlate` — confirme que o jogador entra no veículo após aceitar o job

### GPS Tracker não notifica o dono
- Confirme que `trucker_company_vehicles.has_gps_tracker = 1` para a placa do veículo
- O dono deve estar online para receber a notificação — o sistema não persiste alertas para players offline
- Verifique `Config.CargoTheft.GpsTrackerPrice` e se o saldo da empresa era suficiente no momento da compra

### Motoristas NPC não completam jobs
- Verifique se `trucker_npc_drivers` tem registros com `status = 'idle'` para a empresa
- O tick de simulação roda a cada `Config.NpcDrivers.cronIntervalMinutes` minutos — aguarde pelo menos um ciclo
- Confira logs do servidor por erros em `NpcDriverService` após cada tick

### Transação na Indústria rejeitada / "Fora de alcance"
- Verifique se a distância física do jogador até as coordenadas da indústria é $\le 15\text{m}$.
- Tentativas de acionamento via NUI ou trigger remoto a longas distâncias são bloqueadas por fail-closed no servidor.

### Descarga de Petróleo Cru falha ou cancela
- O caminhão tanque precisa estar a $\le 25\text{m}$ do ponto de descarregamento configurado.
- A descarga requer tempo mínimo (`elapsed >= minUnloadTime + 5s`). Tentativas de bypass do timer de progresso no client são rejeitadas pelo servidor.

### Guincho Flatbed não engata veículo
- O operador deve estar a no máximo $20\text{m}$ do guincho.
- O veículo a ser rebocado deve estar a no máximo $18\text{m}$ do guincho.
- O script bloqueia tentativas de anexar o guincho a si próprio ou anexar veículos que já estão rebocados.

### Convites de Comboio expirando rapidamente
- A partir da v20.1, todos os convites de comboio e party possuem TTL de 60 segundos por segurança.
- Se o jogador demorar mais de 60s para aceitar, um novo convite deve ser emitido pelo líder.

### Membro de Comboio caiu da cidade e não recebeu pagamento
- O sistema da v20.1 credita o valor diretamente na conta bancária persistida no banco (`users` / `trucker_convoy_payments`) mesmo que o jogador esteja offline no momento da entrega do líder.
- Verifique a tabela `trucker_convoy_payments`:
  ```sql
  SELECT * FROM trucker_convoy_payments WHERE citizenid = 'CID_DO_JOGADOR' ORDER BY created_at DESC LIMIT 5;
  ```

---

## Painel Administrativo (`/truckeradmin`) & Ferramentas 3D Gizmo

Acesso exclusivo para administradores com permissão ACE `command.truckeradmin`. O painel centraliza a configuração em tempo real sem necessidade de reiniciar o resource.

### 1. Spawns Dinâmicos e Pastas
- **Organização por Pastas:** Agrupe pontos de spawn por locais ou clientes (ex: `Porto de Los Santos`, `Depósito Paleto`).
- **Posicionamento Sequencial em Lote:** Configure o campo de quantidade (ex: `5`). O Gizmo 3D abrirá para o primeiro item, e ao confirmar com `ENTER`, o próximo item será instanciado imediatamente à frente com badge `Item X de Y` sem reabrir a UI. Todos os itens são salvos atomicamente no banco ao final.
- **Duplicação Rápida:** O botão de clonagem lê o ponto original e cria cópias com sufixos incrementais automáticos (`Nome (2)`, `Nome (3)`), abrindo o Gizmo diretamente no ponto copiado.

### 2. Offsets Trailer 3D & Cintas de Amarração (6DoF)
- **Calibração de Cargas e Cintas:** Na aba **Offsets Trailer 3D**, use o alternador flutuante `[ Carga ]` e `[ Cinta Catraca ]`.
- **Cintas Catraca (`prop_ratchet_strap`):** Posicione e rotacione cintas individualmente com precisão 6DoF sobre cada carga do reboque. Os dados são salvos na coluna `straps` e aplicados fisicamente no gameplay quando o jogador conclui o minigame de amarração.

### 3. Controles do Gizmo 3D
| Comando / Tecla | Ação |
|---|---|
| `W`, `A`, `S`, `D` | Voo livre e navegação da câmera |
| `L-SHIFT` | Aceleração da câmera (Turbo) |
| `Mouse Look` | Rotação orbital da câmera |
| `[ALT]` (Segurar) | Libera o cursor do mouse para arrastar as alças do Gizmo |
| `T` | Alterna para o modo de Translação (Setas de eixos X, Y, Z) |
| `R` | Alterna para o modo de Rotação (Anéis de rotação 3D) |
| `ENTER` | Confirma o item atual e avança para o próximo / salva |
| `ESC` ou `Backspace` | Cancela ou encerra a calibração com salvamento parcial dos confirmados |

---

## Infrações (integração com AUST_sala)

O sistema registra e expõe infrações de motoristas para uso externo:

```lua
-- Registrar infração de speeding de outro script
exports.AUST_trucker:RecordInfraction(citizenId, 'speeding', 'Excesso de velocidade na zona industrial')

-- Consultar infrações antes de contratar
local infractions = exports.AUST_trucker:GetInfractions(citizenId)
for _, inf in ipairs(infractions) do
    print(inf.type, inf.description, inf.created_at)
end
```

Infrações ficam na tabela `trucker_infractions` e não têm penalidade automática — o uso é deixado para o servidor definir (ex: bloqueio de jobs, aumento de juros).
