# 00 — Current State Snapshot

**ANALYZED HEAD: `c9d9187b514b892dc932cf37da5d2b51b7addca3`** (branch `claude/compare-aust-trucker-repos-bcy7zy`)
**BASE (`origin/main`): `e5ce6ccff20c7251ceff0de66cf602e38dec89e6`**
**DATE:** 2026-10-04

> Este pacote documental **não altera código**. A linha de base do "Gate 4" (diff de código vazio) é o commit `c9d9187`: todo o diff de código desta missão em relação a ele deve ser vazio; só `docs/review/` é adicionado.

## 1. Estado Git

| Item | Valor |
|---|---|
| REPOSITORY | `AUST_trucker` |
| ORGANIZATION | `Haze-Studio-s` |
| URL | https://github.com/Haze-Studio-s/AUST_trucker |
| BRANCH analisada | `claude/compare-aust-trucker-repos-bcy7zy` |
| HEAD SHA | `c9d9187b514b892dc932cf37da5d2b51b7addca3` |
| `origin/main` | `e5ce6ccff20c7251ceff0de66cf602e38dec89e6` |
| GIT STATUS no início da missão | limpo (sem arquivo modificado) |
| UNTRACKED | nenhum |
| DIRTY FILES | nenhum |
| Branches remotas | `main`, `claude/compare-aust-trucker-repos-bcy7zy`, `feat/sync-vp-local-2026-09-28` |
| Arquivos versionados | 366 (`git ls-files`); 39 212 linhas Lua |

### Relação HEAD analisado × `main`

O HEAD analisado é `main` (`e5ce6cc`) **mais** a branch do PR #9. Diferença de código em relação à `main` (13 arquivos, +1 971 / −55):

| Arquivo | Origem | Natureza |
|---|---|---|
| `shared/pallet_spawn_validation.lua` (novo) | PR #9 | validação de spawn de pallets |
| `shared/pallet_sync_guard.lua` (novo) | PR #9 | idempotência do `polarixSyncPallets` |
| `shared/fork_lift.lua` (novo) | PR #9 | regras puras do levantamento cinemático; **não carregado pelo manifest** |
| `server/pallet_registry.lua` (novo) | PR #9 | registro de pallet + estados lógicos |
| `client/modules/pallet_debug.lua` (novo) | PR #9 | telemetria (só com `Config.Debug`) |
| `server/main.lua` | PR #9 | `HandlePalletLoaded` com registry; callbacks `palletClaim`/`confirmCarry`/`release`/`kinematicOff` |
| `client/main.lua` | PR #9 | handler `polarixSyncPallets` idempotente |
| `shared/config.lua` | PR #9 | `KinematicLift` (`Enabled = false`), `ForkliftAttachProfiles`, `PalletSpawnRules` |
| `fxmanifest.lua` | PR #9 | registra 4 dos 5 arquivos novos (**falta `shared/fork_lift.lua`**) |
| `tests/pallet_hardening_test.py`, `tests/kinematic_lift_test.py` | PR #9 | testes de lógica pura |
| `docs/PALLET_DEBUG_TESTE_HUMANO.md`, `AUST_TRUCKER_FORKLIFT_REFERENCE_STUDY.md` | PR #9 | documentação |

**Observação importante:** `client/modules/forklift.lua` **não** foi alterado pelo PR #9. O cliente ainda roda o fluxo do J2 (`e5ce6cc`). Com `KinematicLift.Enabled = false` o servidor também permanece no fluxo legado.

## 2. Pull Requests relevantes (API do GitHub)

| PR | Estado | Título | Observação |
|---|---|---|---|
| [#9](https://github.com/Haze-Studio-s/AUST_trucker/pull/9) | **open, draft** | Fase 2A pallets: telemetria, sync idempotente, usedPallets e validação de spawns | head `c9d9187`, base `main` `e5ce6cc`; ainda não mergeado |
| #8 | closed | log do motivo em toda recusa de carga/cintas/entrega | mergeado por `vinicius3232` (commit `74b89e4` na `main`) |
| #7 | closed | carga travada: promover `STEP_GET_TRUCK` para `STATUS_LOADING` | mergeado (`aeab287`) |
| #6 | closed | residuais da auditoria | mergeado (`5c58e14`) |
| #5 | closed | fixa `easingthemes/ssh-deploy` | mergeado (`eda8fdd`) |
| #4 | closed | itens menores da auditoria | mergeado (`fa84666`) |
| #3 | closed | endurecimento de segurança, rodada 2 | mergeado (`8772f97`) |
| #2 | closed | corrige três exploits de dinheiro infinito | mergeado |
| #1 | closed | sync do repo VP local | **não** aparece mergeado na linha principal lida; **UNKNOWN** |

A API de listagem devolveu `merged: false` para os PRs fechados, mas a história da `main` contém os "Merge pull request #N" correspondentes (#3–#8). Adotamos a história Git como fonte.

## 3. Commits recentes (últimos 12 do HEAD analisado)

```
c9d9187 Claude   10-04 16:44 feat(pallets): estado lógico do pallet no servidor e módulo de levantamento cinemático (desligado por flag)
24c9793 Claude   10-04 16:32 Merge main (J2KGOD forklift/PropEditor) into PR #9 branch
594d99d Claude   10-04 16:31 docs: estudo de engenharia comparativa de pallets/forklift
5cb5ba7 Claude   10-04 16:23 docs: estudo comparativo forklift/pallets
e5ce6cc J2KGOD   10-04 07:13 Fix prop gizmo confirmation flow
c66afde J2KGOD   10-04 06:59 Restrict save to keyboard Enter; ignore mouse clicks
213404f J2KGOD   10-04 06:48 Add 6DoF Prop Editor freecam & gizmo
9bd6aa8 J2KGOD   10-04 06:37 Auto-attach props and activate 3D gizmo
d8f530e J2KGOD   10-04 06:30 Add 6DoF PropEditor and hot reload
0e10fa8 J2KGOD   10-04 05:52 Fix CalcBonus and company payout regression
ecd55f0 J2KGOD   10-04 05:40 Improve forklift loading and payouts
0f2c831 J2KGOD   10-04 04:23 Stabilize forklift pallet physics transitions
```

Nas 24 h anteriores à análise a `main` recebeu **mais de 30 commits** do J2KGOD só sobre pallet/forklift (de `1b4dc34` em 10-03 23:46 até `ecd55f0` em 10-04 05:40), sem teste in-game registrado no repositório.

## 4. Versões declaradas (divergentes)

| Fonte | Versão |
|---|---|
| `fxmanifest.lua` `version` | **20.8.5** |
| `README.md` badge (linha 3) e tabela de versões (linhas 357–385) | **20.9.0** |
| `CHANGELOG.md` entrada mais recente | **[20.9.0] — 2026-10-04 — Módulo PropEditor 6DoF** |
| Entrada do CHANGELOG para a auditoria | `[20.8.0]` |

**DOC_DRIFT confirmado:** o manifest está em 20.8.5 enquanto README e CHANGELOG já declaram 20.9.0. Não há tag/release correspondente verificada.

## 5. Documentação existente e divergência

| Documento | Linhas | Observação |
|---|---|---|
| `README.md` | 404 | descreve versões até 20.9.0 |
| `CHANGELOG.md` | n/d | 20.9.0 no topo |
| `AUDIT_REPORT.md` | 113 | relatório da auditoria de 10-03 (anterior ao trabalho de pallets) |
| `GUIA_STAFF.md` / `GUIA_JOGADOR.md` / `DESCRICAO_VENDA.md` | 724 / 347 / 89 | guias; não verificados contra o código neste pacote (**UNKNOWN**) |
| `docs/ATUALIZACOES_VP_E_DIRECIONAMENTO_LSRP_GTAW.md`, `docs/SYNC_VP_LOCAL_2026-09-28.md` | n/d | histórico de sync com repositório VP local |
| `docs/superpowers/{plans,specs}` e `.superpowers/` | n/d | planos/specs de ferramentas auxiliares; origem não verificada |
| `docs/PALLET_DEBUG_TESTE_HUMANO.md` | 36 | roteiro do teste humano da Fase 2A |
| `AUST_TRUCKER_FORKLIFT_REFERENCE_STUDY.md` | n/d | estudo comparativo (raiz do repositório) |
| `.github/workflows/deploy.yml` | n/d | deploy via `easingthemes/ssh-deploy` |

## 6. Observações iniciais

1. **O repositório não tem teste de integração in-game.** Os únicos testes são `tests/pallet_hardening_test.py` (59 casos) e `tests/kinematic_lift_test.py` (77 casos), ambos de lógica pura via `lupa`, criados no PR #9.
2. **`fxmanifest.lua` carrega todos os arquivos `.lua` do repositório, exceto `shared/fork_lift.lua`** (pendência conhecida; edição bloqueada pelo classificador de permissões na sessão anterior). Nenhum arquivo `.lua` referenciado no manifest está ausente.
3. **Arquivos grandes:** `client/client.lua` (3 606 linhas), `client/main.lua` (3 302), `server/events.lua` (3 005), `server/main.lua` (2 453), `server/database.lua` (1 916), `config/config.lua` (1 890), `client/modules/offset_editor.lua` (1 740), `server/callbacks.lua` (1 737).
4. **Dois "donos" do fluxo físico de pallet** convivem na `main`: o do J2 (`client/modules/forklift.lua`, físico/estado local) e o do PR #9 (servidor com registry; cliente ainda não conectado ao claim).
5. **Referências externas clonadas para leitura** (commit lido): Polarix `d11dcd1`, Don `4adaf7a`, Mobius `9edc213`, xDope `1718e31`, qb-truckerjob `f994467`, qbx_core `1825a3c`, ls_trucking `7940d00`, XS-Trucking `50af0ac`, fiji-oil `c6189a1`, distortionz_towjob `e518902`, esx_deliveries `3f4a28f`, ox_lib `66906c5`, ox_target `bf03d52`, ox_inventory `488aa6d`.
6. Os números de linha citados nos demais documentos referem-se ao HEAD `c9d9187`.

## 7. Como ler este pacote

`16_J2_REVIEW_PACKAGE.md` é o índice executivo; `18_EXECUTIVE_SUMMARY.md` resume tudo em uma página; `17_J2_REVIEW_CHECKLIST.md` permite aprovar/rejeitar cada PLAN ID individualmente.

## Revisões do pacote documental

| Revisão | Commit documental base | Conteúdo |
|---|---|---|
| V1 | `c9d9187` (código) → docs até `3a89631` | documentos 00–18 e adendo `08b` (parcial) |
| **V2** | `3a89631` | estudo completo do XS-Trucking (server/client/bridge/NUI/tools); atualizações de 08, 08b, 09, 14, 15, 16, 17, 18; novo `19_AUST_DEVICE_ECOSYSTEM_INTEGRATION.md`. **Nenhum código alterado**; o código do AUST em `3a89631` é idêntico ao de `c9d9187`. |
