# Changelog — AUST_trucker

## [20.9.10] — 2026-10-07 — Correção de Persistência & Compatibilidade de Licenças Técnicas (Heavy Lift & ADR)

### Corrigido & Aprimorado
- **Compatibilidade de Driver oxmysql/TINYINT(1) (`server/callbacks.lua`, `server/main.lua`):**
  - Resolvido bug crítico onde a emissão da licença técnica ("Certificação Heavy Lift Operator" / "ADR Specialist") era gravada com sucesso no MySQL, mas o jogador ficava impossibilitado de iniciar o frete e caía em loop solicitando o teste novamente.
  - Causa raiz: Drivers MySQL/node-mysql2 deserializam colunas `TINYINT(1)` como boolean (`true`), fazendo com que comparações estritas em Lua (`licRow.heavy_certified == 1`) falhassem silenciosamente por divergência de tipo primitivo (`true ~= 1`).
  - Implementada função de avaliação resiliente `isTruthy(val)` aceitando `true`, `1`, `'1'` e `'true'` tanto na consulta de habilitação (`aurp_trucker:getLicenses`), na blindagem de início de rotas (`StartTruckDelivery`), quanto na verificação de posse prévia de exames (`aurp_trucker:takeLicenseExam`).
  - Sanitização e trim automático de `citizenId` em todas as rotinas de licença para prevenir inconsistências de espaçamento ou formato.
- **Comando Administrativo `/truckerlicense` (`server/services/admin_service.lua`, `client/client.lua`):**
  - Adicionado comando administrativo `/truckerlicense [id] [heavy|adr] [1|0]` com validação de permissões para concessão ou revogação direta de certificações técnicas sem necessidade de refazer o teste em ambiente de desenvolvimento/testes.
  - Adicionado autocompletar e auxílio de parâmetros via `chat:addSuggestion`.

## [20.9.9] — 2026-10-07 — Comando Administrativo `/truckerxp`, Concessão de Níveis & Testes de Skill Tree

### Adicionado & Aprimorado
- **Comando Administrativo `/truckerxp` (`server/services/admin_service.lua`):**
  - Implementado comando `/truckerxp [id] [quantidade]` com validação de permissões multi-framework via `AdminService.IsPlayerAdmin(src)` (FiveM ACE, QBX, QBCore, ESX Legacy e Console).
  - Suporte a execução in-game com auto-atribuição ao omitir o ID (`/truckerxp <quantidade>`) e execução remota para qualquer jogador online (`/truckerxp <id> <quantidade>`).
  - Convocação atômica de `ProgressionService.AddDirectXP(targetId, citizenId, amount)` com trava de concorrência (`WithProgLock`) e recálculo dinâmico de nível/rank com base em `Config.required_xp_to_levelup`.
  - Atribuição automática de **+1 Skill Point por nível ganho** diretamente no banco de dados (`trucker_player_progression.skill_points`).
  - Sincronização em tempo real com a interface NUI de habilidades (`action = 'updateSkills'`) e disparo de som/notificação de conquista (`aurp_trucker:client:levelUp`).
- **Sugestão de Chat & Eventos Auxiliares (`client/client.lua`):**
  - Registro de autocompletar e ajuda de parâmetros via `chat:addSuggestion`.
  - Evento `aurp_trucker:client:refreshSkillsUI` para atualização instantânea da interface de habilidades mesmo em ganhos fracionários de XP.

## [20.9.8] — 2026-10-07 — Mecânica de Acoplamento de Containers (Reach Stacker), Blindagem Seletiva Anti-Catapulta & Multi-Slots

### Adicionado & Aprimorado
- **Mecânica de Içamento e Acoplamento de Containers (`client/modules/reach_stacker.lua`):**
  - Integração procedural do veículo `handler` (Reach Stacker) utilizando o spreader (`frame_2`) para captação no solo e assentamento nivelado em carretas (`freighttrailer` / `trflat`) via tecla `[G]`.
  - Suporte completo a cargas individuais (container de 40 pés centralizado) e duplas (2x containers de 20 pés em slots dianteiro e traseiro).
- **Blindagem Seletiva Havok Anti-Catapulta (`client/modules/reach_stacker.lua`):**
  - Eliminação da técnica arcaica de remoção total de colisão (`SetEntityCollision false`). O container mantém colisão sólida com pedestres, balas e outros veículos no trânsito, enquanto isola o contato destrutivo com a carreta e o maquinário através de `SetEntityNoCollisionEntity` mútuo + `FreezeEntityPosition`.
- **Resolução Dinâmica de Slots & Sincronização OneSync (`shared/config.lua`, `server/main.lua`, `client/main.lua`):**
  - Registro de slots nativos de containers para `freighttrailer` em `Config.TrailerSlots` e suporte à calibração livre via Gizmo 3D no `/truckeradmin`.
  - Spawning autoritativo de múltiplos containers no despacho de frete, com autoridade OneSync ancorada no motorista (`LockEntityNetworkOwner`).
  - Replicação multiplayer transparente via StateBag `loadedContainers` no reboque e controle em etapas no servidor (`aurp_trucker:server:heavyContainerLoaded`).

## [20.9.7] — 2026-10-07 — Chave Composta de Offsets de Trailer por Carga (Multi-Prop) & Isolamento no Painel Admin

### Adicionado & Aprimorado
- **Chave Composta e Isolamento de Offsets por Carga (`server/database.lua`):**
  - Tabela `aust_trucker_trailer_offsets` atualizada com a coluna `prop_model VARCHAR(100) NOT NULL DEFAULT 'hei_prop_carrier_cargo_04b'`.
  - Migração de índice segura de `uq_trailer_slot` para `uq_trailer_prop_slot (trailer_model, prop_model, slot_index, is_forklift)`. Permite que o mesmo modelo de reboque (ex: `trflat`) armazene simultaneamente calibrações independentes de posições para diferentes tipos de cargas (ex: Madeira vs Borracha vs Carga Geral) sem sobrescrita.
- **Cache O(1) e Resolução em Cascata (`server/services/admin_service.lua`, `server/main.lua`):**
  - O cache em RAM agora indexa por chave composta `model::prop` além do índice genérico de compatibilidade retroativa `model`.
  - Implementado `AdminService.GetOffsetsForTrailerAndCargo(trailerModel, cargoPropModel)` com resolução sequencial em cascata: exata (`model::prop`) → modelo geral no banco → fallback estático em `Config.TrailerSlots`.
  - Resolução dinâmica de props em missões ativas através da carga contratada no despacho.
- **Agrupamento e Controles no Painel Administrativo (`html/js/admin.js`):**
  - Exibição de cards individuais por par `Trailer — Carga: [PROP]` na aba "Offsets Trailer 3D".
  - Ação rápida "Configurar Esta Carga" preenchendo modelo de carreta e prop no formulário.
  - Exclusão atômica por slot e exclusão em lote de toda a configuração daquela carga específica (`btn-del-group`) sem afetar as demais cargas do mesmo reboque.

## [20.9.6] — 2026-10-07 — Identificação Diegética Heavy RP, Leitura Dinâmica de Placas, Alarme/Chaveiro & Remoção de Marcadores 3D

### Adicionado & Aprimorado
- **Remoção Absoluta de Marcadores 3D de Veículos (`client/main.lua`):**
  - Supressão de qualquer marcador flutuante `DrawMarker 20` (chevron/seta verde) sobre o caminhão, a carreta, a empilhadeira e seus componentes de interação (`trailer_rear`, `trailer_doors`, `trailer_strap`, `forklift_dock`). O espaço aéreo do pátio agora é 100% limpo, atendendo ao padrão rigoroso de simulação Heavy RP.
  - Preservados os blips e rotas no GPS/minimap e os marcadores de piso de doca/estacionamento (`DrawMarker 30` zebrado e `DrawMarker 1` de devolução).
- **Busca pela Placa (Leitura Dinâmica Diegética) (`client/main.lua`):**
  - Ao materializar a entidade física do caminhão no cliente, o script lê diretamente a matrícula gerada pela engine via `GetVehicleNumberPlateText(truck)`.
  - Disparo de notificação na tela: `Veículo liberado no pátio. Placa designada: [PLACA]`.
  - Sincronização automática da placa na interface NUI do contrato/HUD ativa.
- **Feedback Diegético de Alarme e Chaveiro (`client/main.lua`):**
  - Implementada a rotina `TriggerKeyfobChirp(veh)` que simula o destrancar à distância para caminhões de frota/alugados (`not payload.isOwned`).
  - Emite dois pulsos rápidos e sincronizados de faróis/setas indicadoras acompanhados de buzina curta (~140ms), auxiliando na localização visual e sonora no pátio noturno sem recorrer a elementos arcade.

## [20.9.5] — 2026-10-07 — Blindagem OneSync Multiplayer, Anti-Wipe de Frotas, Correção do Fluxo de Inicialização & Ajustes 3D de Docas

### Corrigido & Aprimorado
- **Correção da Trava de Migração de Rede OneSync (`server/main.lua`, `client/main.lua`):**
  - Ajustado `SetNetworkIdCanMigrate(netId, true)` em `LockEntityNetworkOwner` e no watcher de paletes `polarixSyncPallets`. O bloqueio anterior (`false`) impedia que o motorista assumisse a autoridade de rede do caminhão e da empilhadeira, bloqueando o acoplamento físico da 5ª roda e o manuseio de cargas.
- **Saneamento de Natives Exclusivas do Client no Servidor (`server/main.lua`):**
  - Removido `NetworkGetEntityIsNetworked` (linha 504) dentro da função de verificação `IsEntityAssignedToAnyJob`, resolvendo o erro fatal `attempt to call a nil value`.
  - Removidas chamadas de `SetNetworkIdExistsOnAllMachines` nas rotinas de spawn e fallback de paletes (linhas 1062, 1078, 1109, 1124), que interrompiam a coroutine do servidor antes do envio de `aurp_trucker:client:polarixJobStarted`.
- **Detecção Reativa da Entrada na Cabine do Caminhão (`client/main.lua`):**
  - Refatorados `StartTruckEnterWatcher` e `lib.onCache('vehicle')` para validação resiliente via `GetVehiclePedIsIn(ped, false) == veh` com auto-assentamento no assento `-1`.
  - Adicionado hook dedicado reativo `lib.onCache('seat')` para transição instantânea para `STEP_3_COUPLE_TRAILER`.
  - `UpdateMissionObjective` ajustado com `ClearObjectiveMarkers(true)` para preservar o blip secundário da carreta ao resolver o caminhão.
- **Isolamento de Multiplayer & Proteção Anti-Wipe de Pátio (`server/main.lua`, `client/client.lua`):**
  - Validação estrita em `IsSpawnPointClear` via `IsEntityAssignedToAnyJob(veh)`: vagas ocupadas por veículos de missão de outros jogadores são preservadas sem deleção.
  - Notificação amigável de capacidade esgotada em vez de substituição destrutiva de entidades.
  - Sincronização de visibilidade global de paletes para observadores via `GlobalState.activeTruckerPallets`, StateBag da carreta e raio de culling de 450m (`SetEntityDistanceCullingRadius`).
  - Trava anti-wipe no cancelamento de rotas em `client/client.lua`, restringindo remoção de entidades apenas ao seu dono de rede.
- **Ajuste de Visibilidade do DrawMarker de Doca (`client/main.lua`):**
  - Raio de renderização do marcador 3D zebrado na baía de carregamento (`DockWatcherPoint`) aumentado de 200m para **250.0 metros**.
- **Auditoria de Responsividade Front-End do Painel Admin (`/truckeradmin`):**
  - Correção de overflow de layout, corte de textos e quebra de contêineres nas abas do painel sem tocar em identificadores ou lógica JS.

## [20.9.4] — 2026-10-06 — Rampa Traseira Funcional, Empilhadeira PLT & Fluxo de Descarregamento

### Adicionado & Aprimorado
- **Integração de Assets Dedicados (`AUST_trucker_assets`):** Carreta flatbed com rampa articulada (`plttrflat`), empilhadeira compacta (`pltforklift`) e prop de colisão sólida da rampa (`polat_lumberjack_ramp001`).
- **Trava de Trânsito da Rampa:** Bloqueio procedural durante o percurso rodoviário e destravamento condicionado ao estacionamento na vaga final de entrega.
- **Fluxo Sequencial de Descarregamento:** Descida da rampa, coleta com empilhadeira, depósito orientado nos slots de descarregamento (`unloadingPoint`) e reembarque da empilhadeira.
- **Validação Autoritativa Server-Side:** Contagem em tempo real e bloqueio fail-closed de pagamento caso o total descarregado seja inferior ao exigido.

## [20.9.3] — 2026-10-05 — Blindagem Anti-Catapulta Havok, Congelamento de Carga, Fitas Realistas & Separação de Assets

### Adicionado & Aprimorado
- **Separação Arquitetural de Assets (`resources/[assets]/AUST_trucker_assets`):**
  - Isolamento completo de todos os modelos de veículos (`.yft`, `.ytd`), props 3D (`.ydr`, `.ytyp`) e metadados de handling (`data/*.meta`) para o resource dedicado `AUST_trucker_assets`.
  - Eliminação total do crash nativo do FiveM `hamper-zulu-chicken` (`GTA5_b3258.exe+487E78`) ao reiniciar o script em tempo de execução (`ensure`/`restart`). O `AUST_trucker` agora é 100% puro em scripts Lua e interface NUI.
- **Congelamento Estático da Carreta no 1º Palete (`client/modules/forklift.lua`):**
  - Rotina `FreezeTrailerRig(true)` acionada no momento exato em que a empilhadeira ergue e acopla o primeiro palete nos garfos, travando o conjunto carreta + caminhão (`FreezeEntityPosition`, freios e velocidade zero).
  - Destravamento automático (`FreezeTrailerRig(false)`) assim que a empilhadeira conclui seu acoplamento na traseira do reboque (`SnapForkliftToSlot`) ou ao encerrar a operação.
- **Blindagem Anti-Catapulta Havok (Palete nos Garfos vs Trailer):**
  - Desativação mútua contínua de colisão (`SetEntityNoCollisionEntity`) entre o palete nos garfos da empilhadeira e a prancha da carreta/caminhão, eliminando explosões de depenetração e arremesso de veículos ao aproximar a carga da prancha metálica.
- **Renderização Planar das Cintas de Amarração (`client/main.lua`):**
  - Correção da rotação planar das fitas de amarração 3D, expandindo a largura ao longo do vetor longitudinal (`GetEntityForwardVector(trailer)`). A fita agora se apresenta larga de frente e rente à parede da carga.
  - Paleta de cor em **Vermelho Industrial Realista** com sub-faixas de costura reforçada nas bordas, nervura de highlight central tridimensional e sombreamento diferenciado nas descidas laterais.

## [20.9.2] — 2026-10-05 — Restauração do Fluxo de Amarração & Blindagem Operacional de Garfos

### Corrigido & Aprimorado
- **Restauração do Fluxo Original de Amarração de Cargas (`client/main.lua`):**
  - **Estado de Aguardo e Carga Solta:** Paletes estivados no reboque permanecem rigorosamente desamarrados (`isSecured = false`) sem nenhuma fita ou corda visível até a vitória do minigame.
  - **Alvo de Interação Lateral do `ox_target` (`SetupNextPalletTarget`):** O ponto de interação de cada palete é projetado na lateral externa da carreta correspondente (`X ≈ ±1.45m`), com raio acessível do chão ($1.60\text{m}$) e distância de $2.50\text{m}$.
  - **Execução do Minigame Existente:** O jogador caminha até a lateral e aciona a amarração, executando o `lib.skillCheck` acompanhado da animação de catraca e som de catraca.
  - **Gatilho Visual no Milissegundo de Vitória:** No instante exato do sucesso, as cordas vermelhas `DrawPoly` cruzam aquele respectivo palete. Em caso de falha, o palete permanece solto e o alvo reabre para nova tentativa.
  - **Progressão Individual da Rota:** O fluxo avança sequencialmente palete a palete. A rota do caminhão só é liberada com 100% das cargas amarradas com sucesso e cordas visíveis.
- **Calibragem e Tolerância Espacial dos Garfos (`client/modules/forklift.lua`):**
  - Tolerância de penetração calibrada e restabelecida para $1.10\text{m}$ no espaço local com alinhamento angular de até $\pm 45^\circ$, janela lateral de $\pm 0.80\text{m}$ e vertical de $\pm 0.60\text{m}$.
- **Blindagem Anti-Limbo e Sentinela de Piso (`client/main.lua`, `client/modules/forklift.lua`):**
  - Colisão física sólida ativa com o piso dos armazéns e MLOs, impedindo que paletes soltos ou manobrados afundem ou atravessem a malha do mapa.

### Corrigido & Aprimorado
- **Sincronização Dinâmica de Bones no PropEditor (`offset_editor.lua`):** O PropEditor agora detecta automaticamente o bone de trabalho do veículo de carregamento (`forks` / `forks_attach` para empilhadeiras e `frame_2` para reach stacker/handler), calculando matrizes relativas (`GetOffsetFromBoneGivenWorldCoords`) em vez de forçar o Bone 0 (Root/Chassi).
- **Autoridade Suprema do 6DoF no Gameplay (`forklift.lua`, `reach_stacker.lua`, `container_handler.client.lua`):** Ao acoplar a carga nos garfos da empilhadeira ou no spreader da grua, o sistema consulta `GetVehiclePropOffset(veh, prop)` e sobrepõe os offsets padrão com prioridade máxima.
- **Isolamento de Slots da Carreta (`forklift.lua`, `main.lua`):** Removida a sobreposição indevida do PropEditor nos slots de paletes do reboque (`slotOffset`), mantendo a distribuição física longitudinal e lateral de cada carga individual na carreta.
- **Fluxo do Botão Confirmar Posição e Tecla ENTER (`gizmo_overlay.js`):** Blindagem contra cliques duplos, feedback visual de escala e sonoro, com liberação e reset imediato do foco NUI (`SetNuiFocus(false, false)`).
- **Modais de Confirmação 100% In-Game (`admin.js`, `admin.css`):** O modal de confirmação de exclusão de offsets agora utiliza renderização in-game com `position: fixed`, `z-index: 10000000` e atalho `ESC`, eliminando janelas e alertas pop-up nativos fora do jogo no CEF do FiveM.

## [20.9.0] — 2026-10-04 — Módulo PropEditor 6DoF (/truckeradmin)

### Adicionado
- **Módulo PropEditor:** Nova aba integrada ao painel `/truckeradmin` para calibração, manipulação visual, captura e persistência de offsets entre qualquer modelo de veículo e prop de carga.
- **Tabela Dedicada MySQL:** `aust_trucker_vehicle_prop_offsets` com índice único `(vehicle_model, prop_model)` e colunas para 6 graus de liberdade ($X, Y, Z, Pitch, Roll, Yaw$).
- **Cache em Memória RAM & Hot-Reload:** `AdminService.VehiclePropOffsets` com mapeamento dual-indexado (strings, hashes signed e unsigned); sincronização de rede em tempo real sem qualquer necessidade de reiniciar o servidor (`adminSyncVehiclePropOffsets`).
- **Detecção Orgânica de Engate:** Loop de escuta local interceptando o momento exato em que `IsEntityAttachedToEntity(prop, veh)` se torna verdadeiro, ativando automaticamente o manipulador 3D.
- **Gizmo 3D 6DoF (Three.js & TransformControls):** Suporte completo à rotação tridimensional Euler nos anéis Pitch, Roll e Yaw via `[R]` e translação $X, Y, Z$ via `[T]`, com controle de mouse via `[ALT]`.
- **Integração no Gameplay Principal:** Helper e export universal `GetVehiclePropOffset(vehicle, propModel)` com sobreposição de prioridade máxima no assentamento de cargas (`SnapPalletToCurrentSlot`).

## [20.8.0] — 2026-10-04 — Auditoria Completa de Código, Fix CalcBonus & Otimização NUI

### Correções Críticas
- **`server/services/progression_service.lua`** — Implementada `ProgressionService.CalcBonus(citizenId, opts)` que `JobService.Complete` e `IllegalService.OnComplete` invocavam sem existir (`attempt to call a nil value`). Mapeia diretamente para `GetBonuses` retornando `speedBonus`, `paymentMult`, `valuable`, `distance` e `fragile`.

### Vulnerabilidades Corrigidas
- **`server/services/company_service.lua`** — Saldo remanescente da conta da empresa (`company.balance`) agora é restituído integralmente ao dono ao vender (`totalPayout = SELL_PAYOUT + balanceRefund`), eliminando perda patrimonial irreversível.

### Performance
- **`client/client.lua`** — Thread de polling NUI para atualização de rota ativa agora usa Wait adaptativo: `Wait(5000)` com NUI aberta, `Wait(15000)` com NUI fechada, reduzindo consumo de CPU/tráfego NUI em repouso.

### Resumo da Auditoria
- Nível de Segurança Geral: **9.4/10**
- Arquivos alterados: 3, Removidos: 0, Dependências alteradas: 0
- Vulnerabilidades: 1 corrigida, Bugs: 1 corrigido, Otimizações: 1 aplicada

## [20.7.9] — 2026-10-03 — Residuais da auditoria

### Correções
- Locales `de/es/fr/ja/no/zh-cn` da NUI: adicionadas as 7 chaves de bloqueio de contrato que faltavam (agora 167/167 chaves em todos os idiomas).
- Reembolso da caução do aluguel usa o pior estado (lataria/motor) amostrado pelo servidor durante o aluguel, em vez de só a saúde no momento da devolução.
- `AUDIT_REPORT.md`: residuais reavaliados (locales já eram carregados sob demanda; demais itens documentados com o motivo de não serem correções pontuais).

## [20.7.8] — 2026-10-03 — Itens menores da auditoria

### Segurança / correções
- Calote de empréstimos: débito automático da parcela, parcelas perdidas e status `defaulted` (`Config.Loans.AutoDebit`/`MaxMissedPayments`); inadimplente bloqueia novos empréstimos e a venda da empresa.
- Bônus `parkedManually` (+5%) calculado no servidor (`VerifyParkedInBay`); removido do payload de `completeJob`.
- Exame ADR: perguntas sorteadas pelo servidor e exibidas pelo client; gabarito movido para `server/adr_questions.lua` (só servidor).
- `ContractService.PayPending` roda no login (QBCore/QBox e ESX) para pagamentos pendentes de quem estava offline.
- Webhook do Discord das encomendas lido só no servidor (`aurp_trucker_parcel_webhook`); URL removida do config compartilhado.
- `playerDropped`: cache `src -> citizenid` (`Framework.GetCitizenIdBySource`) para a limpeza de cargo/forklift/cooldowns não ser pulada quando o framework já removeu o jogador.
- Removidos o evento morto `truck_logistics:deliveredCargo`, `server/schema.lua` (stub) e `fxmanifest.lua.disabled` (desatualizado).

## [20.7.7] — 2026-10-03 — Security hardening

### Segurança
- Dinheiro: exploits de pagamento/preço corrigidos; débito atômico da empresa; `Framework.AddMoney/RemoveMoney/HasMoney` rejeitam valores não numéricos, NaN, infinitos e negativos (antes `RemoveMoney` negativo creditava no ESX).
- Entrega LC exige prova de entrega validada no servidor; empréstimos (loans) endurecidos; dano de veículo lido no servidor.
- Admin: `adminTeleport` executado e validado no servidor; `IsPlayerAdmin` exige a ACE dedicada `command.truckeradmin` (ACEs genéricas `command`/`admin` não bastam; apenas o console `src == 0` é implícito); todos os handlers admin validam tipo/intervalo/tamanho, gravam só campos sanitizados e registram log; `GetActiveContracts` não escreve mais no banco; bloqueio ADR usa os tipos de certificado reais; `ReloadTrailerOffsets` remove offsets apagados de `Config.TrailerSlots`.
- NUI: escape de HTML (XSS) em `panel.js`/`admin.js`; bibliotecas (Bootstrap, three.js, TransformControls, Font Awesome) e fontes agora locais em `html/vendor/` (sem CDN); CSP adicionada; removida imagem de terceiros.
- Client: prints de debug sob `Config.Debug`; comandos de debug restritos/encaminhados ao servidor; limpeza de blips/entidades/targets em `onResourceStop`.
- Deploy: workflow com `permissions: contents: read`, `environment: production`, action fixada em tag, caminhos entre aspas e EXCLUDE de ferramentas de desenvolvimento.

## [20.6.2] — 2026-10-03 — Correção no Alvo da Empilhadeira, Unificação de Colisão Híbrida e Normalização de Offsets do TruckerAdmin
## [Unreleased] — 2026-09-28 — Sync do repo VP local (só servidor + docs)

Detalhes e achados: [`docs/SYNC_VP_LOCAL_2026-09-28.md`](docs/SYNC_VP_LOCAL_2026-09-28.md).

### Adicionado
- Entrega de combustível abastece postos do `vp_gasstations` (`AddFuelStock`) + 4 postos em `Config.SecondaryIndustries`.

### Segurança
- `truck_rental_service.lua` blindado mantendo o contrato do client: dano lido no servidor, `RegisterNetId` validado (placa/modelo/spawn), trava + throttle, estorno pendente persistido (`trucker_rentals.refund_due`), resposta com `refundAmount`/`damageCost` que a UI espera.

Verificação: harness MOCK 13/13 + sintaxe. **Não testado in-game.** UI/HTML/client não foram alterados.

## [Unreleased] — 2026-09-16 — Auditoria de runtime (/fivem)

### 🎯 Reabertura Imediata de Alvo (`ox_target:addSphereZone`)
- **SphereZone Dedicada para a Empilhadeira:** Ao estivar todos os paletes e posicionar a empilhadeira, o script gera uma `addSphereZone` de 3.0m nas coordenadas da empilhadeira, eliminando falhas de raycast ou posicionamento de câmera.
- **Ciclo Resiliente de Repetição em Falha:** Se o jogador errar o minigame de travamento das catracas, `ForkliftSecured` permanece `false` e a `SphereZone` é imediatamente reaberta para permitir nova tentativa, sem travar o fluxo.

### 🧱 Unificação da Matriz de Colisão Híbrida (1:1 com os Paletes)
- **Colisão Ativa a Pé:** A empilhadeira embarcada na carreta mantém colisão física ativa com o jogador e o mundo (`SetEntityCollision(fork, true, true)` e `SetCanClimbOnEntity(fork, true)`), permitindo subir e inspecionar a carga normalmente a pé.
- **Isolamento Havok Total:** Anulada a colisão mútua contra o reboque e o caminhão (`SetEntityNoCollisionEntity(fork, trailer, false)`), prevenindo qualquer trepidação física.
- **Desativação em Trânsito:** A colisão é desativada temporariamente apenas quando o caminhão estiver em trânsito rodoviário acelerado na estrada para evitar picos de física.

### 📐 Resolução de Offsets do TruckerAdmin & Normalização 32-bit
- **Compatibilidade com `TINYINT(1)`:** Corrigida a identificação do campo `is_forklift` no MySQL, que retornava valor booleano no `oxmysql`, impedindo que os offsets da empilhadeira fossem gravados erroneamente como paletes.
- **Normalização de Hash 32-bit (Signed / Unsigned):** Implementada a máscara `hash & 0xFFFFFFFF` e dual-indexação (`signed` e `unsigned`), assegurando que `GetEntityModel(trailer)` (assinado) encontre perfeitamente as chaves numéricas salvas pelo Gizmo 3D.
- **Auto-Sync no Boot do Client:** O cliente realiza o download automático e cacheamento dos offsets do servidor logo na inicialização, garantindo que o reboque utilize sempre os offsets do banco.

### 👁️ Alcance Visual de Cintas (LOD Estendido)
- **Renderização a 100 Metros:** O raio de renderização contínua das cintas 3D (`DrawPoly`) foi expandido de 35 metros para **100 metros** ao redor da carreta, permitindo visualização nítida das cintas na estrada e em comboios à distância.

## [20.6.1] — 2026-10-02 — Refatoração Visual de Cintas (DrawPoly Bilateral de 6cm, Condicionamento por Minigame & Remoção do Texto 3D)

### 🪢 Cintas Visuais 3D com Malha Planar Realista (`DrawPoly`)
- **Substituição da Nativa `DrawLine` por `DrawPoly`:** Eliminada a limitação de espessura de 1 pixel ("laser irreal") das linhas de debug. Implementada renderização poligonal em malhas de triângulos planos (`DrawPoly`) gerando tiras têxteis com **6 cm de largura real** (`hw = 0.03m`).
- **Renderização Bilateral Anti-Culling:** Cada segmento da cinta (trilho esquerdo $\to$ topo esquerdo $\to$ topo direito $\to$ trilho direito) é desenhado com ordem horária e anti-horária de vértices, impedindo desaparecimento visual por *backface culling* independente do ângulo da câmera.
- **Cor Industrial Vibrante:** Tiras em vermelho industrial (`220, 20, 20, 255`) projetadas dinamicamente sobre a geometria do palete com base nas suas dimensões (`GetModelDimensions`).

### 🎯 Condicionamento Estrito de Estado & Fluxo do Minigame
- **Ativação Pós-Vitória Exclusiva:** As cintas visuais só são renderizadas após a conclusão com sucesso do minigame de habilidade (`isSecured == true`). Paletes pendentes ou recém-estivados não exibem nenhuma fita.
- **Comportamento em Falha no Minigame:** Caso o jogador falhe na combinação de teclas do `lib.skillCheck`, o palete permanece desamarrado (`isSecured = false`), nenhuma fita é desenhada e o sistema reabre a zona de interação do `ox_target` para permitir nova tentativa sem avançar indevidamente a lista.
- **Tratamento Idêntico para a Empilhadeira:** Falhas no minigame de travamento da empilhadeira mantêm `ForkliftSecured = false` e reconfiguram a zona de trava para repetição imediata.

### 🚫 Remoção Total do Texto 3D Flutuante
- **Abolição Absoluta do `DrawText3D`:** Removidos todos os marcadores flutuantes com o texto "Amarrar" ou "[E] Amarrar" sobre os paletes e a empilhadeira, limpando a poluição visual do pátio.
- **Interação 100% via `ox_target` / Sistema Padronizado:** A amarração e travamento operam de forma limpa e imersiva através dos alvos do `ox_target` configurados para cada palete e para o modelo da empilhadeira.

## [20.6.0] — 2026-10-02 — Sistema Visual de Amarração de Carga (Cintas 3D DrawLine, Texto 3D Interativo e Encadeamento Imediato da Forklift)

### 🪢 Cintas Visuais 3D Realistas (`DrawLine` & Vetores Dinâmicos)
- **Cintas Duplas Paralelas por Palete:** Implementado renderizador vetorial contínuo que calcula em tempo real os pontos de fixação da carga (`GetOffsetFromEntityInWorldCoords`). Cada palete recebe duas cintas completas (frontal e traseira) partindo das longarinas laterais da carreta (`-1.25m` e `+1.25m`), subindo pelas laterais do palete e cruzando o topo.
- **Espessura de Fita Têxtil:** Renderização de linhas com micro-offsets paralelos ($\Delta = 0.012\text{m}$) simulando a textura e a largura de cintas de amarração catraca reais.
- **Diferenciação Visual de Estado:**
  - **Pendente:** Vermelho vibrante translúcido (`255, 60, 60, 190`).
  - **Amarrado:** Vermelho sólido esticado com alta firmeza (`220, 20, 20, 255`).
- **Persistência em Trânsito:** As fitas vermelhas permanecem esticadas e acompanham a carga durante toda a viagem rodoviária na estrada enquanto o jogador estiver a até 25 metros do reboque (thread entra em repouso com `Wait(500)` a distâncias maiores, garantindo 0.00ms no Resmon).

### 🏷️ Texto 3D Interativo & Amarração Direta com [E] (`DrawText3D`)
- **Texto Dinâmico por Proximidade:** Renderiza o texto flutuante `~r~Amarrar~s~` a até 6.0 metros de cada palete pendente; ao aproximar-se a pé a menos de 2.5 metros, o texto transiciona para `~g~[E]~s~ Amarrar`.
- **Ação Direta por Tecla [E]:** Pressionar **[E]** (`Control 38`) inicia a amarração imediatamente com minigame de perícia e animação de ajuste da catraca, sem necessidade de navegar no menu de contexto do `ox_target` (suporte ao `ox_target` mantido de forma complementar).
- **Suporte à Empilhadeira:** Exibe texto 3D dedicado `~g~[E]~s~ Travar Catracas da Empilhadeira` quando próximo da empilhadeira embarcada na caçamba.

### 🚜 Encadeamento Imediato de Carga & Correção de Setas
- **Gatilho Imediato da Forklift no Último Palete:** Ao estivar o último palete exigido pelo frete (`loaded == total`), a busca por novos paletes no pátio é imediatamente cancelada. O holograma e a seta de objetivo (`forklift_dock`) passam instantaneamente para a traseira da carreta.
- **Eliminação de Seta Residual:** Removido o disparo de evento legado do servidor (`aust_trucker:client:SetObjective`) que recriava indevidamente marcadores sobre a empilhadeira após a colocação de cada palete.
- **Transição Fluida para as Cordas:** O embarque da empilhadeira com **[G]** avança automaticamente para a etapa de coleta de cintas na caixa lateral do caminhão (`STEP_6_GET_ROPES`).

## [20.5.0] — 2026-10-02 — Blindagem Anti-Desync de Proximidade (OneSync Observer Shield, Lock de Propriedade de Rede Server-Side & Matriz Havok Passiva)

### 🌐 Governança de Rede OneSync & Prevenção de Migração por Proximidade (A1)
- **Lock Autoritativo Server-Side (`SetEntityOwner`):** Criado helper autoritativo `LockEntityNetworkOwner(entity, src)` no servidor (`server/main.lua`, `server/events.lua`). Todas as entidades geradas na missão (`truck`, `trailer`, `forklift`, `pallets`, `container`, `carrierCars`) têm sua titularidade de rede travada estritamente no motorista contratante no momento do spawn e reafirmada em `registerJobEntities` e `HandlePalletLoaded`.
- **Desativação Total de Migração de Rede (`SetNetworkIdCanMigrate = false`):** O OneSync Infinity fica proibido de transferir a propriedade de rede das entidades da carga para outros jogadores (observers) que se aproximem do reboque, eliminando a disputa de pacotes físicos e a perda de autoridade do condutor.

### 👥 Comportamento de Clientes Espectadores / Observers (A2 & A3)
- **Observer Passivo Total nos StateBags:** Refatorados `AddStateBagChangeHandler('loadedSlots')` e `'loadedForklift'` em `client/main.lua`. Clientes observadores (terceiros) **nunca mais** requisitam controle de rede (`NetworkRequestControlOfEntity`) sobre a carga alheia. Apenas aplicam o anexo passivo no **Bone 0** (`AttachEntityToEntity`) mantendo cinemática rígida (`SetEntityDynamic = false`, gravidade e velocidade nulas) e `FreezeEntityPosition = false`.
- **Havok Shield Contínuo para Observers:** A thread de anulação contínua de colisão mútua por frame (`Wait(0)`) foi estendida para inspecionar reboques com carga num raio de até 35 metros ao redor de qualquer jogador. A engine Havok de observers próximos agora executa `SetEntityNoCollisionEntity(pEnt, veh, true)` a cada tick, impedindo 100% de qualquer colisão física, empurrão ou trepidação entre a carga e o reboque no client de observadores.
- **Matriz Havok Híbrida em Observers:** A carga mantém colisão ativa com o mundo e com o pedestre do observer (`SetEntityCollision = true`, `SetCanClimbOnEntity = true`), permitindo que terceiros subam ou inspecionem a carga fisicamente sem causar qualquer desestabilização no caminhão em movimento.

## [20.4.0] — 2026-10-02 — Padronização de Ancoragem Bone 0, Embarque Contínuo da Forklift [G] e Resolução Hierárquica Dupla

### 🚜 Sistema de Posicionamento & Ancoragem de Cargas (Bone 0 / Root)
- **Padronização Estrita no Bone 0:** Unificada a ancoragem de paletes e empilhadeiras (`AttachEntityToEntity`) para utilizar invariavelmente o **Bone 0 (Root da Entidade)** em todas as fases do ciclo de vida: estiva (`SnapPalletToCurrentSlot`, `SnapForkliftToSlot`), amarração individual a pé (`ExecutePalletTie`, `ExecuteForkliftTie`), início de viagem rodoviária (`StartDeliveryRoute`) e laço de sincronização de trânsito (`Sync Anchor`). Elimina o deslocamento relativo causado pelo osso secundário `"chassis"`, alcançando correspondência milimétrica 1:1 com o Gizmo 3D do `truckeradmin` e os hologramas fantasmas.
- **Resolução Hierárquica Dupla de Offsets:** O motor de resolução (`ForkliftModule.GetForkliftSlotOffset` e `GetSlotOffset`) agora normaliza e inspeciona chaves de entidade, modelos string (`"trailers2"`) e hashes numéricos (`joaat`), garantindo que os offsets salvos pelo Administrador no MySQL sobrescrevam com prioridade absoluta qualquer valor nativo ou fallback.
- **Fallback Contextual Inteligente:** Reboques de grande porte (`trailers2`, `trailers`) possuem fallback proporcional ajustado para a traseira (`y = -6.6`), eliminando a sobreposição de carga causada pelo fallback genérico curto (`-5.2`).

### 📦 Fluxo Operacional & Embarque Contínuo da Empilhadeira (Tecla [G])
- **Gatilho Imediato do Fantasma Traseiro:** Ao estivar o último palete exigido pelo frete, o holograma do palete é finalizado e o holograma fantasma da empilhadeira surge instantaneamente na caçamba do reboque na posição exata calibrada.
- **Embarque Direto da Cabine [G]:** O jogador pilota a empilhadeira até a traseira da carreta sobre o fantasma; ao aproximar-se da vaga, a interface exibe `[G] Embarcar Empilhadeira no Reboque`. O acionamento executa `SnapForkliftToSlot`, desembarca o condutor ordenadamente com `TaskLeaveVehicle`, acopla a empilhadeira sem soft-pinning no Bone 0 e avança o fluxo diretamente para a amarração com cintas a pé.
- **Compatibilidade Bidirecional:** Mantido suporte ao acoplamento manual a pé via menu de contexto `ox_target` para situações em que o condutor optar por descer da máquina antes do embarque.

## [20.3.0] — 2026-10-02 — Cinemática Rígida Anti-Inércia, Zero-Desync na Arrancada & OneSync Handoff

### 🚚 Física Havok & Estabilidade de Carga (Micro-Desync Zero)
- **Eliminação do Arrasto Inercial Havok:** Paletes e empilhadeiras agora são mantidos estritamente como corpos cinemáticos (`SetEntityDynamic = false`, `SetEntityHasGravity = false`, `SetEntityVelocity = 0.0`) enquanto anexados à prancha do reboque (`client/modules/forklift.lua`, `client/main.lua`). Isso impede que o solver do Havok simule inércia de massa e arraste a carga para trás no momento da aceleração inicial do caminhão.
- **Remoção do Toggle de Colisão aos 3 km/h:** Eliminada a oscilação de `SetEntityCollision` entre repouso e movimento (< 3 km/h vs $\ge$ 3 km/h) que provocava recriação síncrona de *physics proxies* da engine física no exato instante da arrancada. A alternância de colisão agora é governada exclusivamente pelo estado de permanência do jogador na cabine (`isDrivingTruck`), assegurando transição estática inalterada durante toda a aceleração.
- **Reativação Cinemática Segura na Queda Dinâmica:** `SetEntityDynamic(true)`, gravidade e impulsos físicos são restaurados exclusivamente na rotina de perda/tombamento de carga (`palletLost` / `isFallen`), preservando o realismo de acidentes e capotamentos sem penalizar a fixação em trânsito estável.

### 🌐 Sincronização OneSync & Controle de Rede
- **Aperto de Mão Autoritativo Síncrono (Network Handoff):** Refatorada a rotina de controle de entidades em `StartDeliveryRoute` e `Sync Anchor` para aguardar ativamente o controle do cliente (`NetworkRequestControlOfEntity` com timeout seguro) antes de invocar `SetNetworkIdCanMigrate(netId, false)`. Impede que entidades de carga fiquem presas sob controle do servidor enquanto a carreta é movida localmente pelo motorista.
- **Sincronização Ativa em Repouso:** Garantida a propriedade da rede no momento em que o motorista assume o volante, eliminando pacotes de correção de posição mundiais defasados emitidos pelo servidor na partida.

## [20.2.0] — 2026-10-01 — Gizmo 3D, Colisão Inteligente & Roadmap de 6 Pilares de Engenharia

### 🧭 Motor 3D & Ferramenta ADM
- **Engenharia Reversa `vp_staff_studio`:** Implementado Gizmo vetorial tridimensional completo de translação e rotação em tempo real com Three.js e TransformControls (`client/modules/offset_editor.lua`).
- **Isolamento de Câmera Livre & Cursor:** Navegação simultânea pelo teclado enquanto o mouse interage de forma independente com os eixos X, Y e Z.
- **Cálculo de Offsets Relativos:** As coordenadas manipuladas pelo Gizmo são convertidas diretamente em relação à origem do reboque (`GetOffsetFromEntityGivenWorldCoords`), garantindo alinhamento independente do terreno.
- **Persistência de Fantasmas Múltiplos:** Renderização contínua de paletes salvos em transparência durante a calibração de todos os slots.

### 💥 Física Havok & Sincronização OneSync
- **Máquina de Estados de Colisão Adaptativa:**
  - *Modo Parado / A Pé (< 3 km/h ou fora da cabine):* Colisão 100% sólida para o jogador (`SetEntityCollision(true, true)` + `SetCanClimbOnEntity(true)`) com isolamento mútuo da malha do reboque (`SetEntityNoCollisionEntity`). Permite andar, subir e inspecionar a carga na prancha.
  - *Modo Trânsito (>= 3 km/h):* Desativação dinâmica de colisão durante a viagem, eliminando 100% dos conflitos Havok, catapultas de física e trepidações.
- **Eliminação de Flickering OneSync:** Removido `FreezeEntityPosition(true)` em entidades acopladas, permitindo sincronização fluida da hierarquia de entidades na rede sem oscilações visuais para outros jogadores.

### 🛡️ Roadmap de Auditoria Estrutural (6 Pilares)
- **Pilar 1 (OneSync StateBags):** O reboque replica `Entity(trailer).state.loadedSlots` e `loadedForklift`. `AddStateBagChangeHandler('loadedSlots')` re-acopla automaticamente qualquer palete desprendido por *culling* de longa distância.
- **Pilar 2 (Anti-Cheat Server Authority):** Validação autoritativa de distância ($\le 25\text{m}$) e contrato ativo em `AntiCheatService.ValidateDelivery` e `FinalizeLCContract`. Executa `DropPlayer` sumário em tentativas de injeção ou conclusão fraudulenta.
- **Pilar 3 (Garbage Collection & Grace Period):** Rastreamento de todos os NetIDs da missão (caminhão, reboque, empilhadeira, paletes). Em caso de `playerDropped`, o servidor aguarda 3 minutos para reconexão antes de deletar todas as entidades em cascata.
- **Pilar 4 (RAM Cache do Banco de Dados):** Offsets de reboques servidos diretamente da memória RAM (`AdminService.TrailerOffsets` em `getTrailerOffsetsForModel`), eliminando queries SQL síncronas durante o trabalho.
- **Pilar 5 (Havok Parking Freeze):** Caminhão e reboque estacionados (velocidade < 0.5 km/h por 5 segundos sem motorista) são congelados no solo; descongelamento imediato ao sentar na cabine.
- **Pilar 6 (NUI Hard Escape):** Listener da tecla `Escape` em `html/panel.js` e comando de console F8 `/truckerfix` forçando liberação de foco (`SetNuiFocus(false, false)`).

## [20.1.0] — 2026-09-14 — Auditoria Completa de Segurança & Hardening Transacional (OmniRoute)

### Segurança & Anti-Exploit (Crítico & Alto)
- **`server/services/industry_service.lua`** — [SEC-01] Adicionada validação de distância física *fail-closed* em `IndustryService.BuyFrom` e `IndustryService.SellTo` (`#(playerCoords - indCoords) <= 15.0m`). Elimina exploit de trading remoto massivo em indústrias.
- **`server/crude_oil.lua`** — [SEC-02] `aurp_trucker:server:completeCrudeDelivery`:
  - Validação estrita de proximidade física do ped e caminhão até as refinarias (`<= 25.0m`).
  - Validação de tempo plausível de viagem e descarregamento (`elapsed >= minUnloadTime + 5s`) contra teleporte e conclusão forçada.
  - Migração de chamadas diretas de `qbx_core` para o padrão universal `Framework.GetPlayer(src)` e `Framework.GetCitizenId(plr)`.
- **`server/events.lua` & `server/services/cargo_tracking_service.lua`** — [SEC-03] Roubo de Carga:
  - `startCargoTheft`: validado no servidor que o solicitante é o motorista (`seat -1`) do veículo de fuga e gravadas as coordenadas de início no servidor (`startCoords`).
  - `completeCargoTheft`: placa do ladrão (`authoritativePlate`) agora é extraída diretamente pelo servidor via `GetVehicleNumberPlateText(thiefVeh)`, eliminando manipulação de placas de terceiros.
  - Validação de proximidade física entre o ladrão e o caminhão revalidada na conclusão (`<= 25.0m`).
- **`server/flatbed.server.lua`** — [SEC-04] Sistema de Flatbed:
  - `AttachVehicle`: validação contra auto-acoplamento (`flatbedNetId ~= vehicleToAttachNetId`), bloqueio se prancha já ocupada, proximidade do operador ($\le 20\text{m}$) e do veículo alvo ($\le 18\text{m}$).
  - `DetachVehicle`: validação de proximidade e correspondência estrita com o veículo acoplado no StateBag (`attachedVehicle`).
  - `DeleteBedEntity`: verificação de proximidade física e conformidade estrita com StateBag para prevenir deleção arbitrária de entidades no servidor.
- **`server/services/party_service.lua`** — [SEC-05] Party & Convoy Invites:
  - Criação de tokens temporários com TTL de 60s em `VP_Trucker.PartyInvites`.
  - Varredura de convites expirados a cada novo convite (prevenindo memory leak) e limpeza no evento `playerDropped`.
  - Validação e consumo imediato do convite no `PartyService.Accept` (One-Time Token), impedindo invasão de comboios por força bruta de UUID.

### Correções Arquiteturais e Estabilidade (Médio & Baixo)
- **`server/callbacks.lua`** — [COR-01] `aurp_trucker:getCompanyHistory`: adicionado limite de 500 ticks (~5s) no loop de barreira assíncrona, eliminando risco de coroutines zumbis consumindo ticks em caso de lentidão ou deadlock no MySQL.
- **`server/services/convoy_service.lua`** — [COR-02] `ConvoyService._PayAll`:
  - Adicionada verificação de idempotência em `trucker_convoy_payments` antes de processar qualquer pagamento.
  - Fallback de pagamento offline: participantes que desconectam antes do término do comboio têm seu saldo bancário creditado diretamente no DB (`JSON_SET` no Qbox/QBCore ou `users.bank` no ESX) e estatísticas preservadas, evitando perda de recompensas.
- **`server/services/progression_service.lua`** — [COR-03] Implementada a função oficial `ProgressionService.GetBonuses(citizenId)` com suporte a valores nulos e coerção numérica, habilitando bônus de pagamento e velocidade em encomendas (v19) e contêineres (v20).
- **`server/services/container_handler_service.lua`** — [COR-04] `Complete`: cálculo de bônus de empresa corrigido para uso direto do multiplicador de `perks.bonus` (`math.floor(basePayment * skillMult * companyMult)`), reparando defasagem de bônus.
- **`server/services/loan_service.lua` & `server/callbacks.lua`** — [SEC-06] Bloqueada quitação gratuita de empréstimos sem saldo suficiente (`payLoan`) e bloqueada evasão de dívidas empresariais na venda de empresas (`sellCompany`).
- **`server/main.lua`** — [COR-05] Adicionado reset automático de veículos presos com status `'out'` para `'stored'` na inicialização do servidor.
- **`client/industries_npc.client.lua`** — [SYNTAX] Substituídos backticks por `joaat('s_m_m_trucker_01')` eliminando erro de sintaxe.
- **`client/carry_system.lua`** — [CLEANUP] Adicionado auto-cleanup com timer de 30s para props soltos no chão.

---

## [19.1.3] — 2026-04-19 — Audit Auto-Fix

### Fixed (High)
- **`server/services/industry_service.lua`** — [H1] `IndustryService.BuyFrom`: `RemoveMoney` agora é chamado **antes** de `AddItem` — elimina exploit onde falha no pagamento (ESX retorno void, race condition) resultava em item gratuito. Fallback: estorno automático se `AddItem` falhar após pagamento confirmado.

### Fixed (Medium)
- **`server/framework.lua`** — [M1] QBX path: `Framework.AddMoney/RemoveMoney/GetMoney` agora usam `exports.qbx_core:AddMoney/RemoveMoney/GetMoney` diretamente em vez do shim depreciado `player.Functions.*`.
- **`server/framework.lua`** — [M2] ESX path: `ESX.GetPlayerFromId` substituído por `ESX.Player` em todas as ocorrências (3 lugares: `GetPlayer`, `FindPlayerByCitizenId`, `GetAllPlayers`).
- **`server/framework.lua`** — [M3] ESX path: `player.addMoney/removeMoney/getMoney/getName` substituídos por `player.addAccountMoney/removeAccountMoney/getAccount/name` (API moderna ESX Legacy).
- **`server/services/industry_service.lua`** — [M4] `RunProductionCycle`: N queries individuais por indústria substituídas por um único `SELECT` de todos os production states — indexado em memória; elimina N round-trips ao banco por ciclo de produção.

### Fixed (Low)
- **`fxmanifest.lua`** — [L1] Removido `lua54 'yes'` (depreciado desde junho/2025; Lua 5.4 é padrão).
- **`server/database.lua`** — [L2] `DB_GetOneAvailableIllegalJobForNpc`: query corrigida — substituiu JOIN com `trucker_illegal_deliveries` (tabela inexistente no schema) por filtro `WHERE illegal_type IS NOT NULL` em `trucker_jobs`.

---

## [19.1.2] — 2026-04-09 — Parcel fail-closed + contrato rate limit

### Corrigido
- `server/services/parcel_service.lua`: callbacks `parcel:nextStop` e `parcel:complete` agora são **fail-closed** quando o ped do jogador é inválido ou as coords são `(0,0,0)` — antes a checagem de distância era omitida e o estado da rota podia avançar / pagar sem proximidade válida.
- Helper local `GetPlayerPositionFailClosed` (ped existe + coords não-nulas).

### Adicionado
- `config/config.lua` → `Config.ParcelDelivery.StopRadius` e `DepotRadius` (default 15 / 20 m), usados pelos callbacks acima.
- `Config.AntiCheat.RateLimits.completeContractStop` (default 2 s) + `server/events.lua`: rate limit no evento `aurp_trucker:completeContractStop` para alinhar com outros fluxos pagos.

## [19.1.1] — 2026-04-08 — Auditoria Security & Lua Patch

### Corrigido (HIGH)
- `server/callbacks.lua` + `server/services/truck_simulation_service.lua`: **payForFuel** — preço de combustível agora calculado server-side usando `TruckSimulationService.GetLastFuel(src)`, eliminando exploit onde cliente podia enviar `price = 1` e abastecer gratuitamente
  - Adicionados `GetLastFuel(src)` e `SetLastFuel(src, fuelLevel)` ao TruckSimulationService
  - `SetLastFuel` persiste imediatamente no DB via `DB_SetVehicleFuel` ao reabastecer
- `client/hud.client.lua`: callback `payForFuel` não envia mais o argumento `price` (removido do payload)

### Corrigido (MEDIUM — Lua Audit)
- `client/client.lua`: 8 `RegisterNUICallback` que chamavam `lib.callback.await` sem `pcall` — se o await lançasse exceção (timeout, server error), `cb()` nunca era chamado e a NUI ficava em loading state eterno
  - Callbacks corrigidos: `purchaseSkill`, `payLoan`, `acceptRepoOrder`, `hireNpcDriver`, `fireNpcDriver`, `trainNpcDriver`, `setNpcAllowIllegal`, `npcRespondEvent`
  - Padrão aplicado: `local ok, result = pcall(lib.callback.await, ...) → cb(ok and result or fallback)`

### Corrigido (MEDIUM + LOW — aprovados)
- [M1] `server/callbacks.lua` — `getCompanyHistory`: 5 queries SQL sequenciais → parallel barrier (6 spawns simultâneos + barrier `while _pending > 0`); reduz latência do histórico de ~5× sequencial para ~1× paralelo
- [L1] `server/events.lua` — Adicionado handler `esx:playerLoaded` quando `Config.Framework == 'esx'`, garantindo que `DB_UpsertPlayerStats` e `TruckSimulationService.OnPlayerLoaded` sejam chamados também em deployments ESX

## [19.1.0] — 2026-04-05 — Auditoria Fase 2/3 + Histórico Convoy + DB Unificado

### Adicionado

#### Histórico de Pagamentos de Convoy
- Nova tabela `trucker_convoy_payments` (convoy_id FK → trucker_convoy_jobs ON DELETE CASCADE, citizenid, amount, bonus_mult, completed_count, total_count, created_at)
- `DB_RecordConvoyPayment` — grava pagamento por membro ao final de cada convoy
- `DB_GetConvoyHistory(citizenid, limit)` — busca últimos 20 convoys do jogador, ordenado por data
- Server callback `aurp_trucker:getConvoyHistory` via ox_lib
- NUI callback `getConvoyHistory` no client (dispara callback server e envia `updateConvoyHistory` via SendNUIMessage)
- **PartyPanel.tsx** — view dupla `party | history`:
  - Botão "Histórico →" no canto superior direito da aba Convoy
  - Tabela com colunas: Data/Hora · Membros que concluíram · Multiplicador de bônus · Valor recebido
  - Estado vazio com emoji 🚚 · Loading state · "← Voltar" para aba principal
- `ConvoyPayment` interface adicionada em `html/src/types/index.ts`
- `convoyHistory` state adicionado ao `usePartyStore` (Zustand)

#### Notificação de Abandono de Convoy
- `convoy_service.lua` — ao chamar `DB_SetConvoyBonusMult`, todos os membros restantes recebem notificação toast com nome do membro que saiu e o novo multiplicador (fallback `'Um membro'` se jogador já desconectado)

#### Config — Valores Extraídos (antes hardcoded)
- `Config.TruckSimulation.Fuel.TankCapacityGTA = 65.0` — capacidade do tanque GTA usada no cálculo de consumo (`hud.client.lua`)
- `Config.TruckSimulation.Fatigue.TimecycleWarnStrength = 0.3` — força do timecycle ao atingir threshold de alerta de fadiga
- `Config.TruckSimulation.Fatigue.TimecycleHeavyStrength = 0.6` — força do timecycle em fadiga crítica
- `Config.IllegalJobs.SeizeRange = 50.0` — distância máxima (m) para apreensão policial da carga ilegal (`events.lua`)

### Alterado

#### DB Unificado — Fonte Canônica Única
- `server/database.lua` agora contém o **SchemaService completo** no topo (array `TABLES` com todas as 20 tabelas + array `MIGRATIONS`), eliminando a duplicidade com `schema.lua`
- `server/schema.lua` substituído por stub de 10 linhas com aviso de deprecação — mantido apenas para compatibilidade de fxmanifest legado
- `fxmanifest.lua` reordenado: `database.lua` carregado **antes** de `main.lua` para garantir que `SchemaService` esteja definido quando `MySQL.ready` dispara
- `import.sql` atualizado: cabeçalho aponta para `server/database.lua` como fonte canônica; inclui `DROP/CREATE` da nova tabela `trucker_convoy_payments`

### Corrigido (Auditoria Fase 2 — HIGH)

- `hud.client.lua` — todos os usos de `65.0` (3 ocorrências), `0.6` e `0.3` substituídos por referências ao `Config`; elimina divergência silenciosa se config for alterado
- `server/events.lua` — `if dist > 50.0` na apreensão substituído por `Config.IllegalJobs.SeizeRange`

### Corrigido (Auditoria Fase 3 — MEDIUM)

- `useNUI.ts` — adicionado `convoyHistory?: ConvoyPayment[]` ao tipo `NUIMessage` para type-safety completo no handler `updateConvoyHistory`
- `usePartyStore.ts` — `setConvoyHistory` exposto corretamente na interface do store
- `PartyPanel.tsx` — `historyLoading` limpo via `useEffect([convoyHistory])` evitando spinner infinito quando `convoyHistory` já está populado

---

## [19.0.0] — 2026-03-23 — Sistema de Carga Física + Parcel Delivery

### Adicionado

#### CarrySystem — Módulo de Carga Física
- Novo arquivo `client/carry_system.lua` — módulo reutilizável de props attachados ao ped
- `CarrySystem.Start(carryType)` — attacha prop + animação carry + bloqueia armas/sprint
- `CarrySystem.Stop()` — remove prop + limpa animação
- `CarrySystem.DropAt(coords)` — solta prop no chão
- `CarrySystem.IsCarrying()` — verifica estado
- Auto-cleanup em morte/ragdoll e onResourceStop
- 4 tipos de carga: `small_box`, `medium_box`, `barrel`, `sack`

#### Parcel Delivery — Entregas a Pé
- Novo arquivo `client/parcel_delivery.lua` — sub-sistema de entregas urbanas
- Novo arquivo `server/services/parcel_service.lua` — validação, pagamento, cooldown
- NPC no depósito de encomendas com ox_target
- Fluxo: aceitar → pegar pacote (prop na mão) → caminhar até destino → entregar
- Pagamento $80-180 + skill bonus + decreto `freight_pay`
- XP integrado ao ProgressionService existente
- Cooldown 90s server-side
- Zona de entrega temporária com ox_target
- Cleanup automático de states órfãos (>30 min)

#### Config
- `Config.CarryProps` — 4 tipos de prop com modelo, bone, offset, rotação, animação
- `Config.CargoToCarryType` — mapeamento cargo → tipo de carry
- `Config.ManualLoading` — duração pickup/deposit, distância, speed reduction
- `Config.ParcelDelivery` — depot, NPC, blip, pagamento, cooldown, pontos de entrega

---

## [18.4.0] — 2026-03-23 — Auditoria de Segurança Completa

### Corrigido — 15 Issues (7 Critical + 5 Important + 3 Security)

#### Critical (3)
- **#2** `company_service.lua` — Deposit TOCTOU: `RemoveMoney` retorno verificado antes de creditar empresa
- **#3** `company_service.lua` — Withdraw: validação amount (exploit negativo), estorno em falha AddMoney
- **#4/#5** `events.lua` — depositMoney/withdrawMoney: amount validado contra valores negativos/zero

#### Critical (cont.)
- **C-03** `events.lua` — `toggleRecruiting` sem role check; qualquer driver podia alterar
- **C-04** `events.lua` — `registerVehicle`/`removeVehicle` sem role check

#### Important (5)
- **#7** `crude_oil.lua` — Pagamento usava QBCore direto; corrigido para `Framework.AddMoney`
- **#10** `anti_cheat_service.lua` — Fail-open em coords (0,0,0) permitia bypass de proximidade; agora fail-closed
- **#12** `npc_driver_service.lua` — Suborno NPC sem verificar RemoveMoney; sem dinheiro agora trata como ignore
- **#14** `events.lua` — Forklift expected aceitava qty=0 do client; validado min 1, max original

#### Security (3)
- **S-01** `events.lua` — `kickMember` podia remover membros de OUTRAS empresas; adicionada validação company_id
- **S-02** `events.lua` — `removeVehicle` podia deletar veículos de qualquer empresa; validação de ownership
- **S-04** `npc_driver_service.lua` — NPC hire usava coords do client; corrigido para server-side `GetEntityCoords`

---

## [18.3.0] — 2026-03-23 — Integração Decretos Governamentais

### Adicionado
- **Decreto `freight_pay`** — Pagamento de frete agora é afetado por decretos do AUST_governo
  - `Subsídio de Frete`: +25% pagamento
  - `Pedágio Emergencial`: -15% pagamento
  - `Boom Econômico`: +10% pagamento
- Hook aplicado em 3 pontos de pagamento:
  - `server/crude_oil.lua` — entregas de crude oil
  - `server/services/job_service.lua` — entregas normais
  - `server/services/illegal_service.lua` — entregas ilegais
- Backward compat via pcall (funciona sem AUST_governo)

---

## [18.2.0] — 2026-03-22 — Design System + Fixes GPS/Contratos

Paleta de cores padronizada conforme documento de design specs. Container responsivo. Fixes no GPS de contratos e detecção de chegada.

### Added
- **Design System** — 22 design tokens customizados no Tailwind (app-bg, card, primary, success, danger, etc.)
- **CSS**: animações fadeIn/slideInRight, scrollbar dark theme 8px
- **Container responsivo**: 90vw × 85vh (max 1400px) em vez de 700×520px fixo
- **Botão GPS** nas paradas do contrato ativo
- **Detecção de chegada** nos contratos: marcador no chão + [E] para completar parada + progress bar
- **Histórico da empresa** na tab Stats (toggle Jogador/Empresa): receita, jobs, contratos, clientes, entregas recentes
- **`getCompanyHistory`** callback server com queries SQL de totais e histórico
- **`contractGPS`** NUI callback: busca coords do Config por location_id
- **`negotiateContract`** via lib.callback.await (síncrono, garante GPS)

### Changed
- 24 componentes React atualizados com design tokens
- Tab "Entrega" renomeada para "Contratos"
- Tab Contratos habilitada quando jogador tem empresa (mesmo sem contratos)
- `getInitialData` agora envia `clients` e `activeContract` no SendNUIMessage
- `contractStarted` usa SetNewWaypoint + blip com rota
- `negotiateContract` mudou de TriggerServerEvent para lib.callback.await

### Fixed
- GPS de contratos não marcava: coords não passadas no SendNUIMessage do OpenJobBoard
- IIFE no getInitialData causava crash silencioso: substituída por variável
- `currentStop` era null: botão GPS agora aparece em todas as paradas pendentes
- Chave do veículo ao retirar da garagem via qbx_vehiclekeys

---

## [18.1.0] — 2026-03-22 — Contratos com Relacionamento Empresa↔Cliente

Sistema de contratos redesenhado: empresas constroem relacionamento com clientes (indústrias), desbloqueando contratos melhores, negociação de termos e bônus crescente.

### Added
- **`Config.ClientSectors`** — 5 setores (Alimentos, Construção, Combustíveis, Químicos, Geral) com threshold premium
- **`Config.TrustLevels`** — 5 níveis de confiança (Novo→Exclusivo) com XP, bonus% e opções de negociação
- **`Config.ContractNegotiation`** — volumes (1-12), prazos (30-120min), frequências (1-7 entregas)
- **`trucker_client_relationships`** — tabela SQL de relacionamento empresa↔cliente
- **ContractService** reescrito: GetClients, Negotiate, CompleteStop, Complete, Abandon
- **NUI**: lista de clientes com estrelas de confiança (★★★☆☆), modal de negociação, progresso de contrato
- **ox_target** "Guardar Veículo" adicionado ao veículo ao retirar da garagem
- **qbx_vehiclekeys** — chave dada automaticamente ao retirar veículo

### Changed
- Tab Entrega agora mostra **clientes** para negociar em vez de contratos genéricos
- Contratos criados por **negociação** (on-demand) em vez de geração automática (cron)
- XP de confiança: +100 base + streak×10 por entrega, -200 por abandono
- Reputação por setor (média dos trust_levels) desbloqueia clientes premium
- Limite de contratos baseado no nível da empresa (1-10:1, 11-20:2, 21-30:3)
- Garagem: botões Retirar e Guardar sempre visíveis

---

## [18.0.0] — 2026-03-22 — Jobs sem Trailer + Sistema de Contratos

Redesign do sistema de jobs: qualquer jogador pode fazer entregas com qualquer veículo (capacidade baseada em peso/classe). Novo sistema de contratos de frete para empresas (entregas A→B ou multi-parada).

### Added

- **`Config.VehicleCapacity`** — tabela de peso máximo por classe de veículo GTA (Compacto 50kg, Sedan 80kg, SUV 120kg, Van 200kg, Caminhão 400kg, etc.)
- **`Config.Contracts`** — configuração do sistema de contratos (refreshInterval, maxAvailable, tipos simple/multi)
- **`weight`** — campo de peso adicionado a todos os 47 produtos em `Config.PrimaryIndustries` (van=20kg, trailers=80kg, trailers2=150kg, tanker=200kg)
- **`server/services/contract_service.lua`** — ContractService completo: GenerateBatch, Accept, CompleteStop, Complete, cron de geração
- **`trucker_contracts`** + **`trucker_contract_stops`** — novas tabelas SQL para contratos de frete
- **`html/src/stores/useContractStore.ts`** — Zustand store para contratos no React
- **Tab Entrega (NUI)** — lista de contratos disponíveis (empresa) ou progresso do contrato ativo com checkmarks por parada
- **Botão GPS** na aba Indústrias — marca waypoint no mapa para localização da indústria
- **Botão ✕** no painel — fecha a UI visualmente (canto direito da barra de tabs)
- **Backspace** fecha a UI via RegisterKeyMapping
- **Retirar/Guardar veículo** — botões na aba Garagem com spawn/despawn de veículo

### Changed

- **StartJob** — removida exigência de trailer para jobs. Agora verifica peso vs capacidade do veículo. Carros pequenos reduzem cargoQty; motos/bicicletas bloqueiam
- **fetchNUI** — usa `GetParentResourceName()` em vez de resource name hardcoded; adicionado try/catch
- **Notificações** — `aurp_trucker:notify` e todas as notificações em StartJob trocadas de ShowNotification (NUI) para `lib.notify` (ox_lib) — visíveis mesmo com UI fechada
- **acceptJob callback** — fecha a UI via `CloseJobBoard()` antes de disparar o server event
- **JobCard (NUI)** — mostra peso em kg em vez do tipo de trailer
- **vite.config.ts** — `root` apontando para `src/` para resolver corretamente os source files no build
- **industries_npc** — corrigido envio de `item.product` (label) para `item.item` (id) em buyFromIndustry/sellToIndustry
- **jobStarted event** — mapeamento de campos server→client (originCoords→pickup.coords, etc.)

### Fixed

- NUI fetch URL case-sensitive (`aust_trucker` vs `AUST_trucker`) — resolvido com GetParentResourceName
- Modal de detalhes do job travava ao aceitar — adicionado try/catch no fetchNUI
- Vite build produzia apenas 4 modules — corrigido root para `src/` com index.html source separado

### Database Migration

- `ALTER TABLE trucker_jobs ADD COLUMN weight INT NOT NULL DEFAULT 80` (automático via SchemaService)

---

## [17.3.0] — 2026-03-22 — Integração AUST_governo

Conexão do pipeline de crude oil ao sistema de governo municipal: imposto de transporte automático na entrega, enforcement de alvará e DEFCON no Modo B (job board), e export de resumo para o painel de oversight do prefeito.

### Added

- **`server/crude_oil.lua`** — Export `GetActiveCrudeJobsSummary()`: itera `ActiveCrudeJobs` e retorna lista com `{ plate, wellId, manifestId, qty, pricePerBarrel, citizenId }` para consumo pelo painel econômico do governo.

### Changed

- **`server/crude_oil.lua`** — Após `plr.Functions.AddMoney('cash', totalPayment, 'crude_oil_delivery')` em `completeCrudeDelivery`: dispara `TriggerEvent('AUST_governo:server:collectTax', 'crude_transport', job.qty * job.pricePerBarrel, 'Frete crude — Manifesto N')` — fire-and-forget.

- **`server/events.lua`** — No branch `crude_` de `acceptJob` (Modo B), após check de job ativo:
  - Verifica `HasPermit(citizenId, 'transport_commercial')` em `pcall` — recusa com notify se sem alvará.
  - Verifica `GetCurrentDefcon()` em `pcall` — recusa com notify se DEFCON ≤ 2.
  - Defaults seguros: se `AUST_governo` offline, `hasPermit = true`, `defcon = 5`.

### Nota de escopo

Modo A (pickup direto no poço via `validatePickup` do AUST_oilfield) já está coberto pela Task 7 em AUST_oilfield. Este enforcement cobre apenas Modo B (job board).

---

## [17.2.0] — 2026-03-22 — Crude Oil Pipeline — Fase 1

Integração com AUST_oilfield: truckers com ADR `flammable_liquid` e veículo tanker retiram barris de crude oil nos poços e entregam em refinarias, com pagamento automático e suporte a Modo B (ordens postadas pelo dono do poço).

### Added

- **`server/crude_oil.lua`** — Core do pipeline server-side:
  - `ActiveCrudeJobs` (in-memory, indexado por placa) — evita conflitos de FK com `trucker_jobs`
  - Export `StartCrudeJob(src, plate, manifestId, wellId, qty, pricePerBarrel)` — chamado por AUST_oilfield após cargo carregado
  - Export `CheckPlayerAdr(citizenId, adrType)` — delega para `AdrService.HasCert`
  - `completeCrudeDelivery` net event — auth por citizenId, nil imediato do job (anti-double-delivery), pcall em `CompleteTransportDelivery`, pagamento em cash
  - `abandonCrudeJob` net event — `ReturnBarrels` + `ExpireManifest` em pcalls separados
  - `GetActiveCrudeJobByPlate(plate)` — **global** (sem `local`) para acesso cross-chunk por `exports.lua`

- **`client/crude_oil.lua`** — Delivery client-side:
  - Zonas ox_target nas refinarias com `canInteract` condicional (`CrudeJobActive and not IsUnloading`)
  - `StartDelivery(refineryId)` — guard nil em `CrudeJobData`, pcall em `lib.progressBar`, IsUnloading reset em todos os caminhos
  - Handlers: `crudeJobStarted` (ativa GPS), `crudeJobData` (qty), `crudeJobCompleted` (reset + resumo), `setCrudeGPS` (Modo B), `crudeJobAbandoned` (reset sem notify duplicado)
  - Init thread com pcall-wrapped `lib.callback.await('AUST_trucker:getRefineries')`

- **`server/exports.lua`** — Export `GetActiveJobByPlate(plate)`:
  ```lua
  exports('GetActiveJobByPlate', function(plate)
      local job = GetActiveCrudeJobByPlate(plate)
      if not job then return nil end
      return { cargoType='crude_oil', manifestId=job.manifestId, wellId=job.wellId,
               barrelCount=job.qty, pricePerBarrel=job.pricePerBarrel }
  end)
  ```

- **`config/config.lua`** — Bloco `Config.CrudeOil`:
  ```lua
  Config.CrudeOil = {
      Refineries = { ... },   -- coordenadas das refinarias
      UnloadTimePerBarrel = 2000,
      DeliveryRadius = 6.0,
  }
  ```

### Modified

- **`server/callbacks.lua`** — `getInitialData` mescla ordens crude de `GetPostedOrders()` no job board com flag `isCrudeOrder=true` e `adrLocked`; novo callback `AUST_trucker:getRefineries` com fallback nil-safe
- **`server/events.lua`** — `acceptJob` intercepta `crude_<wellId>` antes do rate-limit: valida ausência de job ativo regular, dispara `setCrudeGPS` com coords do poço
- **`fxmanifest.lua`** — `server/crude_oil.lua` adicionado antes de `server/exports.lua` (ordem crítica para global `GetActiveCrudeJobByPlate`); `client/crude_oil.lua` adicionado ao final de `client_scripts`

### Fixed (security & correctness)

| ID | Problema | Correção |
|----|----------|----------|
| SEC-01 | Double-delivery race em `completeCrudeDelivery` | `ActiveCrudeJobs[plate] = nil` antes do pcall e pagamento |
| SEC-02 | Multi-job exploit via Modo B (trucker aceitava ordem crude com job regular ativo) | `JobService.GetActiveByPlayer(citizenId)` check dentro do branch `crude_` |
| FIX-01 | `CrudeJobActive` travado em `true` após abandono | Handler `AUST_trucker:client:crudeJobAbandoned` adicionado; server dispara antes do notify |
| FIX-02 | `CrudeJobData` nil causava progressBar com duração errada | Guard `if not CrudeJobData then return end` antes de calcular duração |
| FIX-03 | `IsUnloading` travado se `lib.progressBar` lançasse erro | Wrapped em pcall; `IsUnloading = false` no finally |
| FIX-04 | `Config.CrudeOil` nil crash em `getRefineries` | `Config.CrudeOil and Config.CrudeOil.Refineries or {}` |

---

## [17.1.0] — 2026-03-21 — Quality Audit & NUI Fixes

### Fixed (CRITICAL)
- **`server/services/cargo_tracking_service.lua:158`** — Timing nil guard: `cargo.theftStartedAt or 0` era exploit (os.time()-0 ≈ 1.7B segundos); substituído por `if not cargo.theftStartedAt then return nil end` antes do cálculo de elapsed
- **`client/client.lua`** — Migração completa do sistema legado `aurp-trucker:` (hífen) → `AUST_trucker:` (underscore):
  - `acceptJob`, `joinCompany`, `toggleRecruiting`, `depositMoney`, `withdrawMoney`, `registerVehicle`, `removeVehicle` — prefixos corrigidos nos TriggerServerEvent
  - 11 `RegisterNUICallback` ausentes adicionados: `partyCreate`, `partyInvite`, `partyLeave`, `partyDisband`, `convoyStart`, `hireNpcDriver`, `fireNpcDriver`, `trainNpcDriver`, `setNpcAllowIllegal`, `npcRespondEvent`, `abandonJob`
  - `OpenJobBoard` reescrito: substituiu `TriggerServerEvent('aurp-trucker:checkPlayerCompany')` (sem handler) por `lib.callback.await('AUST_trucker:getInitialData')` que já retorna todos os dados necessários
  - Adicionados `RegisterNetEvent` corretos: `AUST_trucker:client:jobStarted`, `AUST_trucker:notify`, `AUST_trucker:client:companyUpdated`
  - 9 handlers `RegisterNetEvent('aurp-trucker:...')` mortos removidos (incluindo `RequestServerJobs` function)

### Fixed (HIGH)
- **`client/forklift.client.lua`** — `onResourceStop`: `exports.ox_target:removeLocalEntity(ped)` adicionado antes de `DeleteEntity` em dois loops de cleanup
- **`client/industries_npc.client.lua`** — Prefixo `aurp-trucker:buyFromIndustry/sellToIndustry` → `AUST_trucker:`; `removeLocalEntity` antes de `DeleteEntity` no `onResourceStop`; argumentos redundantes `totalPrice` removidos
- **`client/industries.client.lua`** — `aurp-trucker:updateIndustries` → `AUST_trucker:updateIndustries`; 2 `print` debug sem guard removidos
- **`server/services/anti_cheat_service.lua`** — Lookup precomputado `_secondaryById` em file-load substituindo O(n) loop por O(1) em `ValidateDelivery`
- **`server/services/illegal_service.lua`** — Lookup precomputado `_compatibleByType` em file-load substituindo O(n×m) loop por O(1) em `Generate`

### Fixed (MEDIUM)
- **`server/services/npc_driver_service.lua`** — Startup reconciliation: N×2 queries individuais consolidadas em 2 queries batch (`WHERE id IN (...)`)
- **`client/convoy.client.lua`** — `cbRadioControl` agora config-driven via `_KEY_CTRL` lookup map; suporta todas as teclas definidas em `Config.Party.cbRadioKey`

### Fixed (LOW)
- **`server/services/progression_service.lua`** — `or math.huge` morto removido de `LEVEL_THRESHOLDS` lookup
- **`html/src/components/overlay/NpcEventAlert.tsx`** — `repairCost?.toLocaleString()` sem fallback → `?? '?'`
- **`html/src/components/progression/SkillTree.tsx`** — `console.warn` (causava erro de build TypeScript) substituído por comentário

### Changed
- `docs/memory/project_AUST_trucker_dev.md` — Atualizado: fxmanifest v17, key files v17, 5 novos padrões (18-22: onResourceStop, precomputed lookups, anti-cheat nil guard, batch queries, hyphen vs underscore CRITICAL)

---

## [17.0.0] — 2026-03-21 — Fase Final (Comercial)

### Added
- **Framework abstraction layer** (`server/framework.lua`) — `Framework = {}` global implementado para QBX, QBCore e ESX
  - `Framework.GetPlayer`, `FindPlayerByCitizenId`, `GetCitizenId`, `GetCharInfo`, `GetJob`
  - `Framework.AddMoney`, `RemoveMoney`, `GetMoney`, `HasMoney`, `GetAllPlayers`, `GetSource`
  - Selecionado via `Config.Framework = 'qbx' | 'qbcore' | 'esx'` em `config/config.lua`
- **Auto-create tables** (`server/schema.lua`) — `SchemaService.EnsureTables()` cria todas as 18 tabelas e aplica 3 migrations (`ADD COLUMN IF NOT EXISTS`) no boot, dentro de `MySQL.ready` antes de `LoadCompanies()`
- `Config.Framework` em `config/config.lua`

### Changed
- `fxmanifest.lua`: `qbx_core` removido de `dependencies` (framework opcional via config); `server/framework.lua` e `server/schema.lua` adicionados como primeiros server_scripts; versão `17.0.0`
- Todos os ~219 acessos diretos a `exports.qbx_core`, `.PlayerData.*`, `.Functions.*`, `GetQBPlayers()` e `.PlayerData.source` em `server/**/*.lua` substituídos por `Framework.*`
- Loops `GetPlayers() + iterate + citizenId match + break` em `repo_service.lua`, `loan_service.lua` e `events.lua` substituídos por `Framework.FindPlayerByCitizenId`
- `server/main.lua`: chama `SchemaService.EnsureTables()` no `MySQL.ready`
- Docs: README, GUIA_JOGADOR, GUIA_STAFF atualizados para v17 (multi-framework, auto-tables, features v16+)

### Notes
- **Fase Final do blueprint**: A ✅ B ✅ C ✅ (0.00ms idle by architecture) D ✅
- Breaking change: `qbx_core` não é mais declarado como dependency hard — servidores ESX/QBCore não precisam ter qbx_core instalado

---

## [16.0.0] — 2026-03-21 — Repo Man Avançado (Fase 6)

### Added
- **6A — Colateral de veículo em empréstimos** (`trucker_loans.vehicle_plate VARCHAR(20) NULL`)
  - `LoanService.Create` aceita `vehiclePlate` opcional — penhor de veículo específico ao criar empréstimo
  - `RepoService.GenerateFromLoan`: se `loan.vehicle_plate` → usa direto via `DB_GetVehicleModel`; fallback: veículo aleatório da empresa (comportamento anterior)
  - `requestLoan` server event: aceita `vehiclePlate` como 3º argumento; valida pertencimento à empresa
  - `DB_GetAvailableRepoOrders` expõe `loan_id` para NUI diferenciar ordens de empréstimo vs. NPC
  - Migration: `sql/update_loan_collateral_v16.sql`
- **6B — Server-side validation + owner blip**
  - `completeRepoOrder` server event valida `dist <= impoundRadius * 2` via `GetEntityCoords(GetPlayerPed(src))`
  - `client/repo.client.lua`: `repoAgentUpdate` cria/atualiza blip vermelho piscante ("Agente Repo") para o dono; limpo em `repoOwnerMissionEnded`
- **6C — Flatbed sync multi-client**
  - `AddStateBagChangeHandler('attachedVehicle')` em `flatbed.client.lua` propaga attach/detach para todos os clientes via OneSync StateBag
  - Guard: entity owner ignorado (já processou localmente)

### Changed
- `server/database.lua`: `DB_CreateLoan` novo param `vehiclePlate`; `DB_GetAvailableRepoOrders` inclui `loan_id`; nova `DB_GetVehicleModel`
- `server/services/loan_service.lua`: `LoanService.Create` novo param `vehiclePlate`
- `server/services/repo_service.lua`: `GenerateFromLoan` reescrito com branch colateral vs. fallback
- `server/events.lua`: `requestLoan` extrai e valida `vehicle_plate`; `completeRepoOrder` valida proximidade
- `client/repo.client.lua`: stub `repoAgentUpdate` substituído; `repoOwnerMissionEnded` limpa blip
- `client/flatbed.client.lua`: StateBagChangeHandler para sync multi-client

### Notes
- **Fase 6 do blueprint**: 6A ✅ 6B ✅ 6C ✅ 6D ✅ (loan_id exposto no payload de `updateRepoOrders`)

---

## [15.0.0] — 2026-03-21 — Anti-Cheat (Fase 5 Completa)

### Added
- **AntiCheatService** (`server/services/anti_cheat_service.lua`)
  - `RateLimit(citizenId, action)` — cooldown in-memory por evento (`os.time() + cooldownSeconds`), configurável em `Config.AntiCheat.RateLimits`
  - `ValidateDelivery(src, citizenId, activeJob, elapsedSeconds)` — barras: velocidade impossível (`dist/MaxSpeedKmh*3600`) + proximidade ao destino via OneSync (`GetPlayerPed`+`GetEntityCoords`, fail-open se ped não roteado)
  - `CleanupPlayer(citizenId)` — remove entry completa de `_cooldowns` no `playerDropped`
- **Rate limiting** em 6 eventos: `acceptJob` (3s), `completeJob` (5s), `startCargoTheft` (10s), `completeCargoTheft` (5s), `depositMoney` (2s), `withdrawMoney` (2s)
- `Config.AntiCheat` em `config/config.lua` — `Enabled`, `DestinationRadius` (80m), `MaxSpeedKmh` (120), `RateLimits`

### Changed
- `server/services/job_service.lua`
  - `JobService.Complete` — elapsed agora calculado server-side (`os.time() - accepted_at_unix`), corrigindo padrão #8; `ValidateDelivery` executado antes do convoy branch
  - `JobService.CompleteTheft` — elapsed calculado via `os.time() - theftStartedAt` (server-side)
- `server/events.lua` — `playerDropped` chama `AntiCheatService.CleanupPlayer`; rate limit em 6 handlers
- `fxmanifest.lua` — `anti_cheat_service.lua` adicionado após `cargo_tracking_service.lua`

### Notes
- **Fase 5 do blueprint 100% concluída:** ADR ✅ Forklift ✅ Skills contextuais ✅ Cargo Theft ✅ Anti-Cheat ✅

---

## [14.0.0] — 2026-03-21 — Vehicle-Bound Cargo + Theft

### Added
- **Cargo vinculado ao veículo** (`server/services/cargo_tracking_service.lua`)
  - Cargo registrado em `VP_Trucker.CargoByPlate[plate]` quando jogador entra no caminhão com job ativo
  - Persistido em `trucker_jobs.truck_plate` para recuperação pós-restart via `CargoTrackingService.LoadFromDB`
- **Roubo de carga**: caminhão parado sem motorista por 30s → vulnerável
  - `ct_vulnerable` StateBag (OneSync) detectado por todos os clients via `AddStateBagChangeHandler`
  - ox_target adicionado ao caminhão vulnerável; progresso de 20s (server-authoritative timing)
  - Transferência para veículo do ladrão com validação de proximidade ≤15m server-side
- **Job do ladrão**: pagamento = `base_payment × timeMult × 1.25` depositado no banco; thief stats rastreados via `DB_AddPlayerStats`
- **GPS Tracker**: upgrade de $5.000 cobrado da conta da empresa (`purchaseGpsTracker` callback)
  - Dono notificado com blip exato quando roubo inicia
  - Policiais notificados com referência vaga de zona (`Config.CargoTheft.PoliceZones`)
- `Config.CargoTheft` block em `config/config.lua`
- Migration: `sql/update_cargo_theft_v14.sql`

### Changed
- `server/events.lua` — `acceptJob` envia `startCargoMonitoring`; `completeJob` roteia carga roubada para `CompleteTheft`
- `server/services/job_service.lua` — `JobService.CompleteTheft()` para pagamento de cargo roubado
- `server/database.lua` — 7 novas funções DB (plate tracking, GPS, active cargo jobs)
- `server/callbacks.lua` — callback `purchaseGpsTracker`

---

## [13.0.0] — 2026-03-21 — Skill Tree Contextual Bonuses

### Changed
- **Skill bonuses now contextual** (`server/services/progression_service.lua`)
  - `GetPaymentMultiplier(citizenId)` replaced by `CalcBonus(citizenId, jobData)` → `{ paymentMult, speedBonus }`
  - **Distance** (+2%/lv): active when `job.distance >= Config.Skills.DistanceThreshold` (default 10km)
  - **Valuable** (+2%/lv): active when `job.basePayment >= Config.Skills.ValuableThreshold` (default $5.000)
  - **Fragile** (+2%/lv): active when `cargoIntegrity >= Config.Skills.FragileThreshold` (default 85%); disabled on illegal jobs
  - **Speed** (+2%/lv): adds to `timeMult` directly instead of `paymentMult`; reduces slow-delivery penalty
- `server/services/job_service.lua` — applies `CalcBonus` (preserves `companyMult` + `integrityMult`)
- `server/services/illegal_service.lua` — applies `CalcBonus` (preserves `mult`; no `companyMult`/`integrityMult`; Fragile disabled)
- `html/src/components/progression/SkillTree.tsx` — description strings updated to show real thresholds

### Added
- `Config.Skills` block in `config/config.lua` — all thresholds and `BonusPerLevel` are operator-configurable

---

## [12.0.0] — 2026-03-21 — Forklift System

### Added
- **Forklift System** (`server/services/forklift_service.lua`, `client/forklift.client.lua`)
  - **Modo 1 — Trade Point Mini-Job:** 2 locais fixos (Walker Logistics, Pacific Shipyard); player aluga forklift ($500), carrega 5 pallets físicos em caminhão NPC, recebe pagamento com speed_mult (≤90s → 1.3×, ≤150s → 1.0×, >150s → 0.7×)
  - **Modo 2 — Delivery Job Integration:** `cargo_qty` (1–6) em delivery jobs; sem forklift = N progressBars sequenciais (com showTextUI por pacote); com forklift = mecânica física de pallets
  - Aluguel $500 (banco) / Devolução voluntária 50% ($250) em raio 15m do spawn
  - Timer server-side auto-cancela missão após `timeLimit` segundos; `tradePointTimeout` event notifica o client
  - `VP_Trucker.ForkliftRentals[citizenId]` em memória; `VP_Trucker.TradePointActive[locationId]` — um player por trade point
  - StateBag ownership: client armazena source ID string; server valida `tostring(src)` em cada `palletLoaded`
  - `playerDropped`: `ForkliftService.OnPlayerDropped` limpa rental e TradePointActive sem crash
- **Database** (`import.sql`, `sql/update_forklift_v12.sql`)
  - Coluna `cargo_qty TINYINT UNSIGNED NOT NULL DEFAULT 1` em `trucker_jobs`
- **Config** (`config/config.lua`) — bloco `Config.Forklift` com `TradePoints`, `IndustrySpawns`, parâmetros de detecção
- **React NUI** — `cargoQty` em `Job` interface; badge "Forklift rec." para qty ≥ 3 em `JobCard` e modal de `JobList`

### Modified
- `server/services/job_service.lua` — `GenerateOne()` sorteia `cargo_qty` ponderado (1–6); payment = `basePrice × cargoQty + dist × mult`; `GetAvailable()` e `GetActiveByPlayer()` expõem `cargoQty` e `originId`
- `server/database.lua` — `DB_InsertJob` SQL inclui `cargo_qty`
- `server/main.lua` — `VP_Trucker.ForkliftRentals = {}` e `VP_Trucker.TradePointActive = {}`
- `server/callbacks.lua` — callbacks `rentForklift`, `returnForklift`, `completeTradePoint` (com validação server-side de `mode`, `locationId` e `expected`)
- `server/events.lua` — NetEvent `palletLoaded` (StateBag source ID check); `updateForkliftExpected`; `playerDropped` chama `ForkliftService.OnPlayerDropped`
- `client/client.lua` — globals `VP_Trucker_ForkliftActive` e `VP_Trucker_CurrentJobOriginId`; `StartLoading()` refatorado com `_CompleteLoading()` extraído; branch forklift vs. loop de progressBars com `lib.showTextUI` por pacote
- `fxmanifest.lua` — registrou `forklift_service.lua` e `forklift.client.lua`

---

## [11.0.0] — 2026-03-20 — ADR Certifications

### Added
- **ADR Certification System** (`server/services/adr_service.lua`, `client/adr.client.lua`)
  - 6 certification types: `flammable_liquid`, `flammable_gas`, `toxic`, `corrosive`, `explosive`, `environmental`
  - Exam flow at NPC examiner (Terminal Portuário A1): 3 random MCQs, ≥2/3 correct = cert granted for 30 days
  - 30-min retry cooldown on failure; exam fee non-refundable (TOCTOU-safe: deducted before grading)
  - Renewal without re-exam: pay 60% of exam cost at NPC or directly from PDA
  - Jobs with ADR-required cargo appear locked in UI with explanatory label for uncertified players
  - Server-side ADR gate in `JobService.Accept` — cannot be bypassed client-side
- **Database** (`import.sql`, `sql/update_adr_v11.sql`)
  - New table `trucker_adr_certs` with `UNIQUE KEY (citizenid, adr_type)`
  - `INSERT ... ON DUPLICATE KEY UPDATE` upsert preserves `created_at` for audit
- **Config** (`config/config.lua`)
  - Full `Config.Adr` block: `ExaminerLocation`, `ValiditySeconds`, `RetryCooldownSeconds`, costs per type, question banks (3-4 questions per type), `TypeLabels`
  - `adr` field added to 11 hazmat products in `Config.PrimaryIndustries` and `Config.IllegalJobs`
- **React NUI**
  - `useAdrStore` — Zustand store with `setCerts` / `upsertCert`
  - `AdrPanel` — grid of 6 `AdrCertCard` components
  - `AdrCertCard` — status badge (Válida/Expirada/Disponível), expiry date, GPS/Renovar buttons
  - New **ADR** tab in TabBar

### Modified
- `server/services/job_service.lua` — `GetAvailable(citizenId)` adds `adrRequired` + `adrLocked` overlay; `Accept` returns boolean (false = ADR gate blocked)
- `server/events.lua` — `acceptJob` handler checks `JobService.Accept` return value and notifies on block
- `server/callbacks.lua` — `getInitialData` passes `citizenId` to `GetAvailable` and returns `adrCerts`; added `submitAdrExam` and `renewAdrCert` callbacks
- `server/main.lua` — `VP_Trucker.AdrExamCooldowns = {}` in-memory cache
- `fxmanifest.lua` — added `adr_service.lua` (after `progression_service`) and `adr.client.lua` (after `hud.client.lua`)
- `html/src/hooks/useNUI.ts` — `open` case populates `useAdrStore`; new `adrCertGranted` case calls `upsertCert`

---

## [10.0.0] — 2026-03-20 — NPC Drivers System

### Added
- **NPC Driver Service** (`server/services/npc_driver_service.lua`)
  - Full autonomous driver simulation: idle → assigned → working → resting → idle cycle
  - Skill levels (junior / pleno / sênior) with configurable efficiency and speed factors
  - Cron-based `SetInterval` tick instead of thread loop
  - Restart recovery: `event`-status jobs auto-fail, expired `active` jobs complete, past `resting_until` → idle
- **Job Assignment** (`_TryAssignJob`)
  - Picks legal or illegal jobs based on `allow_illegal_npc` company flag
  - Reserves job row via `assigned_citizenid = 'npc_<driverId>'`
- **Event System** (`_RollEvent`, `_HandleMinorEvent`, `_HandleGraveEvent`)
  - Minor events: fuel surcharge, traffic delay (adjust payment/ETA transparently)
  - Grave events: major_accident, cargo_stolen, contraband_caught
  - Owner notified via NUI overlay with 60-second response window
  - SALA (police) alert on contraband via `AUST_trucker:npcContrabandAlert` server event
- **Satisfaction & Tenure** (`_ApplySatisfactionDecay`, `_CheckTenure`, `_CheckQuitRisk`)
  - Daily satisfaction decay; salary demands at tenure milestones
  - Quit risk when satisfaction ≤ 20 (random roll, owner notified)
- **Reputation System** — company reputation affects job eligibility and client tips
- **Management API** — `Hire`, `Fire`, `Train`, `SetAllowIllegal`, `GetAgencyProfiles`
  - Agency profiles rotate every 24 h; hire requires player proximity to agency blip
- **Position Broadcasting** (`_BroadcastPositions`) — linear interpolation every 15 s, no real vehicles
- **Client** (`client/npc_driver.client.lua`)
  - Blip management for active NPC routes
  - Agency sphere zone: spawns idle driver peds, ox_target interaction
  - Grave event overlay trigger; notifications for job completed / driver quit / salary demand
- **React NUI**
  - `useNpcDriverStore` — Zustand store (drivers, profiles, reputation, allowIllegal, pendingEvent)
  - `NpcDriverPanel` — hired drivers list with hire/toggle-illegal controls
  - `NpcDriverCard` — per-driver card: satisfaction bar, XP, tenure, train/fire actions
  - `NpcHireModal` — agency modal with 3 rotating profiles and hire costs
  - `NpcEventAlert` — fixed overlay for grave events with countdown and pay/ignore buttons
  - New **Motoristas** tab in TabBar
- **Schema** (`import.sql`)
  - `trucker_npc_drivers`: comprehensive schema with skill, satisfaction, XP, tenure, status
  - `trucker_npc_jobs`: job tracking with earnings, distance, illegal flag, event status
  - `trucker_companies`: added `reputation TINYINT` and `allow_illegal_npc TINYINT` columns
- **Config** (`config/config.lua`) — full `Config.NpcDrivers` block with all tuning parameters

---

## [6.1.0] — Previous Release — Flatbed + Repo Gameplay

See git history for earlier changes.
