# AUST_trucker — atualizações do repo VP e direcionamento de gameplay (LSRP / GTA World)

> Documento de alinhamento entre as duas equipes. Data: 2026-09-28.
> Nada de UI, HTML, client ou config desta equipe foi alterado por este documento.

## 1. Origem dos dois repositórios

| | Repo VP (origem) | Este repo (Haze-Studio-s/AUST_trucker) |
|---|---|---|
| Onde | `vinicius3232/aust_trucker` → pasta `[standalone]/AUST_trucker` do servidor Qbox_753251 | Deploy por GitHub Action para a VPS `Qbox_BA141A` |
| Histórico | 254 commits desde 2026-03-19 | Nasceu de uma cópia do commit VP `1841642` (16/09): os 49 `.lua` são idênticos ao `d6d492e` daqui |
| Base comum | `1841642` = `d6d492e` | |

Os serviços do núcleo industrial continuam **idênticos** nos dois: `industry_service`,
`industry_ownership_service`, `shop_stock_service`, `economy_service`, `contract_service`.

## 2. O que foi atualizado e adicionado no repo VP depois da cópia

| Commit VP | O quê | Veio para cá? |
|---|---|---|
| `27dbea7` | **Combustível → postos (`vp_gasstations`)**: entrega de carga de combustível (trailer `tanker` ou produto Combustível/Gasolina/Diesel/Petróleo) num posto chama `AddFuelStock(coords, litros, origem)`. 4 postos entraram como destino em `Config.SecondaryIndustries` (Strawberry, Innocence, Davis, Paleto). | Sim — PR #1 (cherry-pick sem conflito) |
| `a0e68af` | **Aluguel de caminhão com caução v20.2.0**: balcão com NPC + ox_target + blip; caminhão criado **no servidor**; dano lido no servidor; placa/netId conferidos; trava + throttle; rollback se o spawn falhar; estorno pendente persistido (`trucker_rentals.refund_due`) para desconexão e restart. | Sim, **adaptado** — PR #1 blinda o `truck_rental_service.lua` daqui mantendo o contrato do client atual (o client continua criando o veículo). O balcão/NPC do VP **não** veio, porque a UI daqui já tem o fluxo de aluguel |
| base `052a5b5` | `qbx_truckerjob` desligado no servidor VP: o AUST_trucker é o único sistema de caminhoneiro. | Não se aplica (config do servidor) |

Detalhes técnicos, tabela de correções e achados: [`SYNC_VP_LOCAL_2026-09-28.md`](https://github.com/Haze-Studio-s/AUST_trucker/blob/feat/sync-vp-local-2026-09-28/docs/SYNC_VP_LOCAL_2026-09-28.md)
(no branch do [PR #1](https://github.com/Haze-Studio-s/AUST_trucker/pull/1)).

### Achados da revisão do código daqui (não alterados — recomendação)

| Gravidade | Onde | Problema |
|---|---|---|
| Crítico | `events.lua` → `aurp_trucker:server:completeLCContract` | Paga sem validar entrega, distância ou tempo; SELECT → paga → UPDATE permite pagar 2× com spam; `parkedManually` (+5%) vem do client |
| Alto | `truck_fleet_service.lua` | Usa `Framework.GetPlayerMoney/RemovePlayerMoney/AddPlayerMoney`, que não existem (o bridge tem `GetMoney/RemoveMoney/AddMoney` recebendo o Player) → comprar/vender/reparar quebra |
| Alto | `TruckFleetService.SellTruck` | DELETE sem checar linhas afetadas antes de pagar → venda concorrente paga 2× |
| Médio | `job_service.lua` | `payload.truckId` e `payload.parkedManually` vindos do client sem validação |
| Atenção | `config/logistics_config.lua`, `html/` | O cabeçalho diz "Transplante completo das configurações do lc_truck_logistics". Se for material de script comercial, há risco de licença. O padrão do projeto é **clean-room**: estudar a ideia, escrever do zero |

## 3. Direcionamento: um trucker na pegada de LSRP e GTA World

Fonte: estudos em `_kb/studies/` do repo base (`ESTUDO_LSRP.md` §10.1 e §15.10, `ESTUDO_GTAWORLD.md` §5.5 e combustível).

### 3.1 O que os dois servidores faziam

**LSRP — Trucker**
- Carga entre **indústrias, portos e negócios**; **sem rota fixa** — o jogador escolhe e descobre o que é mais lucrativo.
- **Preço dinâmico**: cada destino paga diferente por cada carga; o valor muda com o tempo.
- **Progressão por rank**: começa com veículo pequeno (Sadler, Bobcat, Yosemite) e sobe até carreta.
- Venda no porto (Ocean Docks) **ou em negócios de jogadores**.
- **TPDA** (Trucker Personal Digital Assistant): o "tablet" do caminhoneiro para ver cargas, preços e rotas.

**GTA World — Trucking & Suppliers**
- Dois modelos: **motorista independente** usando frota de empresa com comissão, e **cadeia de suprimentos**:
  fornecedores base → fábricas intermediárias que refinam → negócios.
- **Caminhões-tanque** abastecem postos e até outros veículos (empresa, facção, pessoal).

### 3.2 Onde o AUST_trucker já está (núcleo comum aos dois repos)

| Pilar LSRP/GTAW | Já existe | Arquivos |
|---|---|---|
| Cadeia primária → secundária → negócio | 25 indústrias primárias, 33+ secundárias, estoque de lojas com reposição por contrato e failsafe NPC | `industry_service`, `shop_stock_service`, `Config.PrimaryIndustries/SecondaryIndustries/ShopStock` |
| Sem rota fixa / preço dinâmico | Preço por oferta e demanda do estoque de cada indústria | `economy_service`, `Config.Economy` |
| Negócio de jogador na cadeia | Indústria com dono (jogador compra, recebe, repõe) | `industry_ownership_service`, `Config.IndustryOwnership` |
| Motorista independente em frota de empresa | Empresas, membros, veículos da empresa, garagem, NPC drivers | `company_service`, `npc_driver_service` |
| Progressão | Níveis, skills, confiança de cliente, capacidade por classe de veículo (compacto → industrial) | `progression_service`, `Config.Skills/TrustLevels/VehicleCapacity` |
| Financiamento e retomada | Empréstimo e repo man | `loan_service`, `repo_service` |
| Combustível na economia | Tanque abastece postos do `vp_gasstations` (repo VP, PR #1) | `job_service` |
| Cargas especiais / RP de risco | ADR, roubo de carga, cargas ilegais, comboio | `adr_service`, `cargo_tracking_service`, `illegal_service`, `convoy_service` |

### 3.3 Lacunas e prioridades sugeridas

1. **TPDA de verdade (prioridade 1).** A UI é onde o jogador enxerga a cadeia. A UI LC daqui não mostra
   indústrias, estoque nem preço por destino — o núcleo industrial continua rodando, mas fica invisível.
   Qualquer UI nova (da equipe daqui ou a React do repo VP) deve ter no mínimo: mapa/lista de indústrias,
   o que cada uma **compra e vende**, preço atual por destino, estoque, e a carga no caminhão.
2. **Contratos LC como camada, não como substituto.** Contrato fixo de A→B é o oposto do "sem rota fixa".
   Se ficar, que gere contratos **a partir** do estado das indústrias (falta de estoque = contrato), com
   entrega validada no servidor como no `JobService.Complete`.
3. **Progressão por veículo (LSRP).** Já existe capacidade por classe; falta amarrar o **nível** ao tipo de
   veículo/carga liberado (Sadler/Bobcat no início → carreta), sem obrigar a ter empresa.
4. **Venda em negócio de jogador.** `shop_stock_service` já tem `management_type = 'player'`; expor na UI e
   dar ao dono o controle de preço de compra fecha o loop LSRP.
5. **Tanque abastecendo veículos (GTAW).** Passo seguinte ao `vp_gasstations`: tanque com litros no
   servidor abastecendo frota de empresa/facção, debitando do estoque do caminhão.
6. **Aluguel como porta de entrada.** Quem não tem veículo nem empresa aluga (já existe), faz as primeiras
   cargas e sobe de nível — é o "primeiro emprego" dos dois servidores.

### 3.4 Regras que valem para qualquer módulo novo

- **Servidor decide tudo**: pagamento, distância, tempo mínimo de viagem, posse do veículo, dano, estoque.
  O client só pede. Nada de `payload.*` virando dinheiro ou XP sem validação.
- **Pagamento idempotente**: marcar concluído (UPDATE com linhas afetadas) **antes** de pagar.
- **Rate limit** ≥ 2 s em ação de dinheiro; trava por jogador em operações com `await`.
- **Schema automático** no boot (`CREATE TABLE IF NOT EXISTS` + `ALTER` em `MIGRATIONS`).
- **Clean-room**: estudar LSRP/GTAW/LC como ideia e fluxo; código, UI e config escritos do zero.
- Textos em **pt-BR**; ambientação do servidor nos EUA (doutrina US).

## 4. Próximos passos combinados

1. Revisar e decidir o merge do [PR #1](https://github.com/Haze-Studio-s/AUST_trucker/pull/1) (branch separado: o deploy só roda no `main`).
2. Corrigir os achados da seção 2 (crítico primeiro: `completeLCContract`).
3. Definir a UI do TPDA a partir da seção 3.3 item 1.
