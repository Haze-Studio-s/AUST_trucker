# 08b — XS-Trucking: aprofundamento (adendo ao 08)

**ANALYZED HEAD (AUST): `c9d9187`.** **Referência:** `XyraL/XS-Trucking` v3.0.0, commit `50af0ac`. **Nenhum código foi alterado.**

**LICENÇA:** "All rights reserved" (livre para uso em servidor próprio, sem redistribuição). **Só ideias; nenhum código pode ser copiado.** Tudo abaixo seria reimplementação independente.

**Lido:** `README.md`, `CHANGELOG.md`, `fxmanifest.lua`, `server/jobs.lua` (Jobs.Hooked/Deliver/payout/dockScore/spawnDriver), `server/settings.lua`, `server/garage.lua` (trechos), `bridge/dispatch.lua`, `client/placement.lua` (início), `client/guards.lua` (início), `tools/check-natives.mjs`, `check-returns.mjs` (e cabeçalhos de `check-netids/events/runtime/nui/manifest`), `.github/workflows/announce.yml`. **NÃO LIDO em corpo:** `server/business.lua`, `server/coop.lua`, `server/progress.lua`, `html/js/*` (usados só por leitura anterior/resumo do doc 08).

## 1. O que o XS-Trucking tem de diferente

| # | Tema | O que ele faz | AUST hoje | Valor |
|---|---|---|---|---|
| 1 | **CI estático (`tools/*.mjs`)** | 10 scripts Node sem jogo: natives inexistentes, `return x:gsub()` sem parênteses, eventos duplicados/sem handler/callback sem registro, NUI sem `RegisterNUICallback`, manifest × pasta, `os`/`io` no cliente, `NetToVeh` sem guarda | nenhum verificador no repo | **ALTO** |
| 2 | **Registro único de job** | `Jobs.active[src]` com estágios `hookup → enroute → return`; veículos criados no servidor | 3 sistemas paralelos (TD-02) | ALTO |
| 3 | **Orphan mode + state bag do servidor** | `SetEntityOrphanMode(…, 2)` em veículos e guardas; `xsTrucking`/`xsGuard` escritas no servidor | sem orphan mode (TD-26); statebags escritas por cliente (TD-22) | MÉDIO-ALTO |
| 4 | **Docking score** | distância 2D + diferença de heading do trailer ao ponto, medidas no servidor, viram bônus | prova = ped + tempo (TD-21) | MÉDIO |
| 5 | **Settings ao vivo** | schema declarativo (chave, grupo, min/max, caminho no `Config`) persistido em `xs_trucking_settings` | só `config.lua` | MÉDIO |
| 6 | **Bridges autodetectadas** | chaves (11), combustível (5), dispatch (7), inventário (4) + evento custom | integrações mais amarradas | MÉDIO |
| 7 | **Guardas armados no builder** | quantidade/arma/colete/mira definidos na rota; criados no servidor | não tem | BAIXO-MÉDIO |
| 8 | **Builder de spots/rotas com ghost** | câmera livre, raycast, preview | PropEditor 6DoF (mais forte para offsets) | BAIXO |
| 9 | **Desgaste por peça** | por km e dano, reduzido por skill | simulação própria sem peças | BAIXO |
| 10 | **NUI com mapa 3D** | Leaflet vendorizado | NUI própria | BAIXO |

## 2. O que ele NÃO resolve

- **Nenhum forklift/pallet**: `grep -i "forklift|pallet"` só acha `prop` de laptop em `spots.lua` e props de veículo em `jobs.lua`. Não ajuda no problema de física.
- **Prova de entrega limitada:** `Jobs.Hooked` exige apenas caminhão e trailer a ≤ 20 m; `Deliver` valida trailer no ponto, caminhão a ≤ 20 m do trailer e ped a raio + 15 m. Não há prova de carga porque não há carga física.
- **Sem lock de dono** (`SetNetworkIdCanMigrate(false)`): o AUST tem em `LockEntityNetworkOwner`.
- **Sem ADR com exame, contratos LC, indústria/economia de mundo.**

## 3. Verificadores de CI: mapeamento para defeitos reais do AUST

| Verificador (ideia) | Defeito do AUST que ele pegaria |
|---|---|
| eventos: handler duplicado | `playerDropped` conflitante (TD-27) |
| eventos: sem handler / sem consumidor | lista **NO CONSUMER** do doc 04 |
| callbacks que o cliente espera e o servidor não registra | `VP_Trucker`/esperas indefinidas (TD-12) |
| NUI: fetch × `RegisterNUICallback` | acoplamento NUI (TD-07) |
| manifest × pasta | `shared/fork_lift.lua` fora do manifest (W1-02) e arquivos órfãos |
| natives inexistentes | chamadas que só quebram em runtime |
| `os`/`io` no cliente | arquivos `shared/*` carregados nos dois lados |
| `NetToVeh` sem guarda no cliente | `WaitForNetworkEntity` sem retry (TD-31) |
| multi-retorno sem parênteses | classe de bug de parâmetros em oxmysql |

Observação: o `SetInterval` com argumentos trocados (TD-13) **não** seria pego por esses verificadores; exigiria checagem de assinatura própria.

## 4. Recomendações (para revisão de J2)

1. **W0-04:** implementar verificadores estáticos próprios (ferramenta Node, fora do runtime do jogo, sem tocar código de jogo). Começar por manifest × pasta, eventos e NUI.
2. **W3-01 (já existente):** incorporar a ideia de docking score como prova adicional de entrega por entidade.
3. **W4-01 / W4-03 (já existentes):** considerar orphan mode e statebags só do servidor, **após** teste em runtime.
4. **W5-05:** schema de settings ao vivo no painel admin (opcional).
5. Nada de copiar código; documentar a política em W0-01.

## 5. Limites desta análise

- Leitura estática; nada executado. Não rodei os `tools/*.mjs` do XS (apenas li).
- Documentação do autor e README podem divergir do código; priorizei o código lido.
