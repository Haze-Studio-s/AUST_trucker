# AURP Trucker

![Version](https://img.shields.io/badge/version-20.7.7-blue)
![FiveM](https://img.shields.io/badge/FiveM-QBox%20%7C%20QBCore%20%7C%20ESX-green)
![Lua](https://img.shields.io/badge/lua-5.4-purple)

Sistema completo de transportadora e caminhoneiro para FiveM. Jobs de entrega com qualquer veiculo (capacidade por peso), contratos empresa-cliente com niveis de confianca, economia dinamica tri-setor, convoy multiplayer, entregas de encomendas multi-parada, operacao de conteineres portuarios, calibracao visual 3D com Gizmo vetorial, ancoragem padronizada no Bone 0 (Root), embarque continuo de empilhadeira via tecla [G], sistema visual de cintas de amarração 3D em malha poligonal planar realista (DrawPoly bilateral de 6cm) condicionadas à vitória no minigame de perícia, colisao inteligente adaptativa, OneSync Observer Shield & Network Ownership Lock (imunidade contra desync de proximidade), cinemática rígida anti-inércia (zero-desync na arrancada), OneSync StateBags, blindagem anti-exploit e interface React.

---

## Funcionalidades

### Jobs de Entrega
- Entregas freelancer com **qualquer veiculo** — capacidade calculada por classe/peso
- Geracao automatica com origem, destino, carga e trailer especificos
- Ponderacao por demanda: destinos com menos jobs tem maior chance de aparecer
- Bonus de tempo (+20% entregas rapidas) e integridade da carga (dano reduz pagamento)

### Entrega de Encomendas (Parcel Delivery — v19)
- Rotas multi-paradas sequenciais com vans ou pequenos veiculos de carga
- Multiplicador de pagamento escalonado por quantidade de paradas concluidas
- Sistema de carregamento de caixas animado com sistema de carregamento no braco (`CarrySystem`) e auto-cleanup
- Integracao com bônus de habilidades e decreto governamental de frete

### Operacao de Conteineres Portuarios (Container Handler — v20)
- Integracao portuaria com guindastes e empilhadeiras pesadas de conteineres (oConteneur)
- Movimentacao e organizacao de conteineres em terminais com slots autoritativos
- Bonificacao combinada por nivel de empresa e skills de conducao

### Contratos
- Sistema de relacionamento **empresa-cliente** com 5 niveis de confianca (Novo a Exclusivo)
- 5 setores de clientes: Alimentos, Construcao, Combustiveis, Quimicos e Geral
- Negociacao de volume, prazo e frequencia conforme nivel de trust
- Contratos simples (1 parada) e multi-stop (3-5 paradas)

### Empresas
- Criar empresa (custo: $150.000) — tipos: Transportadora e Repo Man
- Niveis de empresa (1-5) com bonus de pagamento crescente
- Cofre empresarial com deposito/saque (gerentes e owners)
- Frota registrada com limite por nivel; recrutamento ativo/inativo
- Reputacao (0-100) — afetada por contrabando, recuperada por entregas legitimas

### Garagem
- Veiculos registrados na frota da empresa
- Retirar e guardar veiculos via NUI com reset automatico de veiculos presos no boot
- Controle de status: armazenado, em uso, destruido

### Industrias e Economia Dinamica
- Tri-setor: **Primarias** (produzem sem insumos) -> **Secundarias** (fabricas) -> **Terciarias** (varejistas)
- Precos dinamicos: sobem com estoque baixo, caem quando cheio
- Validacao estrita de proximidade fisica fail-closed no trading (compras e vendas)
- Propriedade de industria: empresa pode comprar e lucrar sobre a producao
- NPC failsafe injeta producao se nenhum jogador abastecer a cadeia

### Convoy e Multiplayer
- **Party system**: criar grupo, convites seguros com TTL e One-Time Token (anti-invasao), lideranca transferivel
- **Convoy**: todos recebem jobs simultaneos na mesma rota; bonus proporcional aos que completam
- **Pagamento Offline**: garantia de pagamento direto em conta mesmo se o jogador desconectar antes da conclusao final
- **Notificacao de abandono**: quando um membro abandona o convoy em andamento, todos os restantes recebem notificacao com nome e novo multiplicador de bonus
- **Historico de pagamentos**: aba "Historico" na NUI exibe todos os convoys concluidos (data, membros que completaram, multiplicador, valor recebido)
- **Radio CB**: chat in-game por alcance (500m), tecla Z, HUD com ultimas 5 mensagens
- **Blind Driver**: motorista em convoy nao ve GPS — depende dos escoltas pelo radio CB
- Blips de posicao atualizados a cada 3s

### Motoristas NPC
- Fase 4: motoristas IA contratados para entregas automaticas
- Failsafe: injecao de producao quando a cadeia de suprimentos esta parada
- Rastreamento via `trucker_npc_drivers` e `trucker_npc_jobs`

### Certificacoes ADR
- 6 tipos: Liquido Inflamavel, Gas, Toxico, Corrosivo, Explosivo, Ambiental
- Exame com NPC no Terminal Portuario: 2 de 3 perguntas corretas
- Validade de 30 dias; renovacao sem re-exame por 60% da taxa
- Jobs com carga perigosa aparecem bloqueados sem a certificacao

### Progressao e Skill Tree
- XP por entrega; 30 niveis com rank automatico (Aprendiz -> Lenda)
- 4 tipos de skill (Distancia, Valioso, Fragil, Velocidade) x 6 niveis, +2% por nivel (+48% max)
- Bonus **contextuais**: Distance ativa para >= 10km, Valuable para pagamentos >= $5.000, Fragile para integridade >= 85%
- API `ProgressionService.GetBonuses` alimentando uniformemente todos os subsistemas de entrega

### Emprestimos
- Emprestimos pessoais e empresariais com juros, inadimplencia e bloqueio contra quitacao sem saldo
- Bloqueio de venda de empresas com debitos ativos
- Veiculos de devedores geram ordens de repossessao automaticamente (integracao Repo Man)

### Roubo de Carga (Cargo Theft)
- Caminhao parado sem motorista por 30s -> vulneravel via StateBag `ct_vulnerable` (OneSync)
- Ladrao inicia roubo via ox_target no banco do motorista; validacao de proximidade na partida e no dropoff
- Placa do ladrao obtida autoritativamente pelo servidor
- GPS Tracker ($5.000): alerta exato ao dono + alerta de zona aos policiais
- Carga roubada entregue no destino original com +25% de bonus

### Entregas Ilegais
- Contatos no mapa oferecem cargas ilegais com pagamento maior
- Cops (SALA) recebem alerta com regiao e tipo de carga
- Apreensao in-world: cop usa ox_target no caminhao para lacrar a carga

### Repo Man & Flatbed
- Empresa do tipo Repo Man recebe ordens de repossessao
- 4 tipos de missao: **Simple**, **Stealth**, **NPC Hostile**, **PvP**
- Flatbed integrado blindado: validacao de proximidade dupla, anti-autoacoplamento, limite por StateBag e protecao contra delecao de entidades

### Shop Stock Ecosystem
- Integracao com ox_inventory para estoque real nas lojas
- Entregas de contratos abastecem o inventario dos comercios
- Exports dedicados em `exports_shop.lua`

### Crude Oil Pipeline
- Sistema de petroleo e refinaria com validacao anti-teleporte
- Validacao fisica de proximidade da refinaria e tempo minimo de descarga
- Transporte de combustivel com certificacao ADR obrigatoria

### Empilhadeira (Forklift) e Estiva Física de Paletes
- Jobs multi-pallet: estiva com a empilhadeira utilizando a tecla [G] ou manual
- Mini-jobs de Trade Point: pallets em tempo limite com bônus de velocidade
- Validação server-side via StateBag (`forklift_owner` e `loadedSlots`)
- **Cinemática Rígida Anti-Inércia & Zero-Desync (v20.3.0):** Cargas atreladas operam 100% como corpos cinemáticos (`SetEntityDynamic = false`, `SetEntityHasGravity = false`, `SetEntityVelocity = 0.0`), eliminando o arrasto inercial do Havok ao arrancar.
- **Blindagem Havok & Colisão Adaptativa:** Isolamento contínuo de colisão entre qualquer prop de carga e o reboque (`SetEntityNoCollisionEntity`) eliminando catapultas de física, com colisão 100% sólida e ativa para o jogador (`SetEntityCollision(true, true)` + `SetCanClimbOnEntity(true)`) fora da cabine.

### Simulacao de Caminhao
- Peso afeta velocidade e frenagem
- Consumo de combustivel proporcional a carga
- Dano de carga por colisoes — reduz pagamento final
- HUD de telemetria em tempo real

### Anti-Cheat Server-Side
- Rate limiting por evento (acceptJob 3s, completeJob 5s, startCargoTheft 10s, etc.)
- `ValidateDelivery`: rejeita entregas impossiveis (velocidade > 120 km/h, fora do raio 80m)
- Elapsed calculado server-side (`os.time()`) — nunca confia no cliente
- Todas as rotas de pagamento sao fail-closed e operam com autoridade total do servidor
- Configuravel via `Config.AntiCheat` (pode desativar com `Enabled = false`)

### Interface React
- NUI em React 18 + TypeScript + Tailwind CSS + Zustand
- 9 abas: Jobs, Missoes (Repo), Entrega Ativa, Empresa, Convoy, Garagem, Industrias, Estatisticas, Motoristas NPC, ADR
- ConvoyPanel com duas views: **Party** (gerenciar grupo) e **Historico** (pagamentos passados)
- Comunicacao bidirecional Lua <-> React via `SendNUIMessage` / `fetch NUI`

### Estatisticas
- Historico completo do jogador: entregas, XP, nivel, rank
- Historico da empresa: receita, membros, reputacao

---

## Dependencias

| Recurso | Obrigatorio |
|---|---|
| [oxmysql](https://github.com/overextended/oxmysql) | Sim |
| [ox_lib](https://github.com/overextended/ox_lib) | Sim |
| [ox_inventory](https://github.com/overextended/ox_inventory) | Sim |
| [ox_target](https://github.com/overextended/ox_target) | Sim |
| [qbx_core](https://github.com/Qbox-project/qbx_core) | Se `Config.Framework = 'qbx'` |
| [qb-core](https://github.com/qbcore-framework/qb-core) | Se `Config.Framework = 'qbcore'` |
| [es_extended](https://github.com/esx-framework/esx_core) | Se `Config.Framework = 'esx'` |

---

## Instalacao

1. Coloque a pasta `AUST_trucker` em `resources/[standalone]/`
2. Edite `config/config.lua` e defina seu framework:
   ```lua
   Config.Framework = 'qbx'   -- 'qbx' | 'qbcore' | 'esx'
   ```
3. Adicione no `server.cfg` **apos** todas as dependencias:
   ```
   ensure AUST_trucker
   ```
4. Inicie o servidor — **as tabelas sao criadas automaticamente** no primeiro boot via `SchemaService`. Nenhum SQL precisa ser executado manualmente.

> **`import.sql`** existe apenas como referencia do schema completo. Nao e necessario executa-lo em instalacoes novas.

---

## Banco de Dados

Todas as tabelas usam o prefixo `trucker_` e sao criadas automaticamente pelo `SchemaService` no primeiro boot.

| Tabela | Descricao |
|---|---|
| `trucker_companies` | Empresas (incluindo reputacao) |
| `trucker_company_members` | Membros e cargos |
| `trucker_company_vehicles` | Frota registrada |
| `trucker_jobs` | Jobs disponiveis e historico |
| `trucker_industry_state` | Estoques das industrias |
| `trucker_industry_ownership` | Propriedade de industrias |
| `trucker_player_progression` | XP, level e rank |
| `trucker_player_skills` | Arvore de habilidades (4 x 6 niveis) |
| `trucker_adr_certs` | Certificacoes ADR dos jogadores |
| `trucker_loans` | Emprestimos pessoais e empresariais |
| `trucker_repo_orders` | Ordens de repossessao |
| `trucker_infractions` | Registro de infracoes |
| `trucker_parties` | Parties de convoy |
| `trucker_convoy_jobs` | Jobs de convoy |
| `trucker_convoy_members` | Membros de convoy |
| `trucker_convoy_payments` | Historico de pagamentos por convoy (por membro) |
| `trucker_npc_jobs` | Jobs executados pelos NPCs failsafe |
| `trucker_npc_drivers` | Estado dos motoristas NPC |

---

## Configuracao

Toda a configuracao fica em `config/config.lua`:

```lua
Config.Framework = 'qbx'           -- Framework: 'qbx' | 'qbcore' | 'esx'
Config.Debug = false               -- Logs no console (desativar em producao)

-- Geracao de jobs
Config.JobGeneration.maxActiveJobs  = 8
Config.JobGeneration.DemandWeighting = true

-- Party & Convoy
Config.Party.maxSize               = 6
Config.Party.cbRadioRange          = 500.0
Config.Party.bonusMultiplier       = 1.5

-- Simulacao de Caminhao
Config.TruckSimulation.Fuel.TankCapacityGTA      = 65.0   -- capacidade padrao GTA em litros
Config.TruckSimulation.Fatigue.TimecycleWarnStrength  = 0.3   -- forca do timecycle em alerta de fadiga
Config.TruckSimulation.Fatigue.TimecycleHeavyStrength = 0.6   -- forca do timecycle em fadiga critica

-- Entregas Ilegais
Config.IllegalJobs.SeizeRange      = 50.0   -- distancia (m) para apreensao policial

-- Contratos
Config.Contracts.refreshInterval   = 300000  -- 5 min
Config.Contracts.maxAvailable      = 5
Config.TrustLevels                 = { ... } -- 5 niveis de confianca

-- Repo Man
Config.RepoMan.ImpoundLocation     = vector3(...)

-- Anti-Cheat
Config.AntiCheat.Enabled           = true
```

Industrias, destinos, modelos de trailer, precos base, capacidade por classe de veiculo e todos os sistemas sao configuraveis no mesmo arquivo.

---

## Estrutura de Arquivos

```
AUST_trucker/
├── config/
│   └── config.lua                — Configuracao principal
├── server/
│   ├── framework.lua             — Abstracao de framework (QBX/QBCore/ESX)
│   ├── database.lua              — SchemaService (auto-criacao de tabelas) + todas as funcoes DB_
│   ├── main.lua                  — Init, cache global VP_Trucker
│   ├── callbacks.lua             — lib.callback.register handlers
│   ├── events.lua                — RegisterNetEvent handlers
│   ├── exports.lua               — Exports para integracao
│   ├── exports_shop.lua          — Exports estoque lojas
│   ├── flatbed.server.lua        — Sistema de flatbed (Repo Man)
│   ├── crude_oil.lua             — Pipeline de petroleo
│   └── services/
│       ├── company_service.lua
│       ├── job_service.lua
│       ├── economy_service.lua
│       ├── industry_service.lua
│       ├── industry_ownership_service.lua
│       ├── progression_service.lua
│       ├── party_service.lua
│       ├── convoy_service.lua
│       ├── illegal_service.lua
│       ├── loan_service.lua
│       ├── repo_service.lua
│       ├── contract_service.lua
│       ├── shop_stock_service.lua
│       ├── parcel_service.lua
│       ├── npc_driver_service.lua
│       ├── truck_simulation_service.lua
│       ├── adr_service.lua
│       ├── forklift_service.lua
│       ├── cargo_tracking_service.lua
│       └── anti_cheat_service.lua
├── client/
│   ├── client.lua                — NUI callbacks, blips, eventos de job
│   ├── hud.client.lua            — HUD de telemetria
│   ├── convoy.client.lua         — Party UI, blips, CB radio, blind driver
│   ├── illegal.client.lua        — Zonas de contato e entrega ilegal
│   ├── flatbed.client.lua        — Flatbed (Repo Man)
│   ├── repo.client.lua           — Gameplay Repo Man
│   ├── industries.client.lua     — Zonas e interacoes de industrias
│   ├── industries_npc.client.lua — NPCs de interacao
│   ├── adr.client.lua            — NPC examinador ADR
│   ├── forklift.client.lua       — Mecanicas de empilhadeira
│   ├── npc_driver.client.lua     — Motoristas NPC
│   ├── cargo_theft.client.lua    — Roubo de carga
│   ├── carry_system.lua          — Sistema de carga fisica (props no ped)
│   ├── parcel_delivery.lua       — Entregas a pe (parcel sub-sistema)
│   ├── container_handler.client.lua — Manipulacao de containers
│   └── crude_oil.lua             — Pipeline de petroleo (client)
├── html/
│   ├── index.html                — Entry point NUI
│   ├── assets/                   — Build Vite (JS + CSS)
│   └── src/                      — Codigo-fonte React (TypeScript)
├── stream/
│   └── flatbed3/                 — Modelo de reboque customizado
└── import.sql                    — Schema de referencia
```

---

## Exports

```lua
-- Obter job ativo de um jogador
local job = exports.AUST_trucker:GetPlayerActiveJob(citizenid)

-- Obter manifest de um job
local manifest = exports.AUST_trucker:GetJobManifest(citizenid)

-- Obter dados da empresa
local company = exports.AUST_trucker:GetCompanyInfo(companyId)

-- Obter empresa do jogador
local company = exports.AUST_trucker:GetPlayerCompany(citizenid)

-- Registrar infracao
exports.AUST_trucker:RecordInfraction(citizenid, infractionType, reason, issuedBy)

-- Obter infracoes
local infractions = exports.AUST_trucker:GetInfractions(citizenid)
```

---

## Desenvolvimento da NUI

```bash
cd html
npm install         # instalar dependencias (Node.js necessario)
npm run dev         # servidor de desenvolvimento (localhost:5173)
npm run build       # build de producao -> html/assets/
```

---

## Screenshots

*Em breve.*

---

## Changelog

Consulte o arquivo `CHANGELOG.md` para o historico completo de versoes.

| Versao | Descricao |
|--------|-----------|
| v20.6.0 | Sistema Visual de Cintas de Amarração 3D (DrawLine) & Texto Interativo [E] (DrawText3D) |
| v20.5.0 | OneSync Observer Shield & Network Ownership Lock (Anti-Desync Proximidade) |
| v20.4.0 | Forklift Offset Truckeradmin Fix, Dynamic Hologram Trigger & Gizmo Align |
| v20.3.0 | Cinemática Rígida Anti-Inércia, Zero-Desync na Arrancada & OneSync Handoff |
| v20.2.0 | Gizmo 3D, Colisão Inteligente & Roadmap de 6 Pilares de Engenharia |
| v20.1.0 | Auditoria Completa de Segurança & Hardening Transacional (OmniRoute) |
| v19.1.0 | Auditoria Fase 2/3 + Historico Convoy + DB unificado + Config hardcoded |
| v19.0.0 | CarrySystem + Parcel Delivery + Container Handler |
| v18.4.0 | Auditoria de Seguranca Completa (15 issues criticos) |
| v18.3.0 | Integracao Decretos Governamentais |
| v18.2.0 | Design System + Fixes GPS/Contratos |
| v17.1.0 | Correcoes criticas: exploit timing, migracao aurp-trucker -> AUST_trucker |
| v17.0.0 | Multi-framework (ESX/QBCore/QBX), auto-create tables, 0.00ms idle |
| v16.0.0 | Repo Man avancado + Shop Stock Ecosystem |
| v15.0.0 | Anti-Cheat: rate limiting, elapsed server-side, ValidateDelivery |
| v14.0.0 | Cargo Theft: StateBag OneSync, GPS Tracker |
| v13.0.0 | Skill tree contextual: bonus condicionais |
| v12.0.0 | Forklift: aluguel, pallet loading, mini-jobs Trade Point |
| v11.0.0 | Certificacoes ADR: exame NPC, 6 tipos, renovacao |
| v10.0.0 | NPC Drivers failsafe |
| v9.0.0 | Party system + Convoy + CB Radio + Blind Driver |

---

## Security & Compatibility

### Audit — 2026-04-08
- Auditado por fivem-audit skill (Claude Code)
- 0 críticos, 1 HIGH resolvido, 1 MEDIUM + 1 LOW pendentes
- Framework: QBX/QBCore/ESX compatível
- lua54: yes — todas funções cross-file verificadas como globais
- AntiCheatService: rate limiting em todos os eventos transacionais
- SQL: 100% parameterizado com `?` (zero SQL injection)
- payForFuel: preço calculado server-side via SimState[src].lastFuel (v19.1.1)

---

## Creditos

**Authentic Studios** — Criado por **Vini32**
