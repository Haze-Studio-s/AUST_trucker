# Teste humano — pallets afundando (telemetria Fase 2A)

Objetivo: coletar evidência de runtime para separar **A)** pivô/bounds, **B)** colisão do asset, **C)** física dinâmica, **D)** ownership, **E)** segundo `polarixSyncPallets`. Nada aqui altera a física.

## Preparação
1. `shared/config.lua`: `Config.Debug = true` (no servidor e no client; reinicie o resource `AUST_trucker`).
2. Abra o console F8 (client) e o console do servidor. Filtre por `[AUST PALLET DEBUG]`.
3. Inicie um frete de **carga seca** (com empilhadeira) e vá ao pátio dos pallets (~1222, -3185).

## Comando
`/palletdebug` — acompanha o pallet mais próximo e zera `t` (uma linha por segundo).
`/palletdebug <netId>` acompanha um netId; `/palletdebug dump` imprime todos uma vez; `/palletdebug freeze|unfreeze` congela/solta o pallet acompanhado (teste manual); `/palletdebug stop` para; `/palletdebug auto` religa o acompanhamento automático (liga sozinho no 1º pallet sincronizado, `t=0` no momento do sync).

Campos por linha: `t`, `netId`, `ent`, `model`, `owner(srv)` (id do jogador dono), `mine`, `xyz`, `dZ` (variação desde a linha anterior), `groundZ` (nativa) e `rayZ` (raio só contra o mapa), `minDim.z`/`maxDim.z`, `baseZ` (= Z + minDim.z), `heightAboveGround` (= baseZ − chão), `frozen`, `static/dynamic`, `collision`, `attached`, `slot`, `statebag`, `job`, `syncs` e as marcas `FALLING`, `FIRST_DROP_AT_t=…`, `BASE_BELOW_GROUND`. `gravity` não tem leitura nativa (`n/a`).

Linhas de evento (client): `sync#N … action=applied|skipped`, `snap … preZ/groundZ/postZ`. Servidor: `server spawn …` (netId, owner, Z pedido e Z de spawn) e `server palletLoaded …`.

## Roteiro (5 minutos)
1. **Nasce com a base abaixo do chão?** Veja o `snap` e a 1ª linha de telemetria: `heightAboveGround` < −0,02 ou `BASE_BELOW_GROUND` → pivô/bounds (A) ou placement. `minDim.z` mostra onde fica a base do modelo em relação à origem.
2. **O Z muda sozinho?** Fique parado sem tocar. `dZ` < 0 e `FALLING` indicam queda; `FIRST_DROP_AT_t` dá o instante.
3. **Quando começa?** Compare com a linha `sync#2`: queda **depois** de `sync#2 … skipped` ⇒ o 2º sync não é a causa (agora ele não reposiciona); queda logo após um snap ⇒ colocação.
4. **O 2º sync ocorre antes da queda?** Os dois `sync#` aparecem com `t`. Antes da Fase 2A o 2º refazia o snap; agora aparece `skipped (já sincronizado)`.
5. **Quem é o owner?** `owner(srv)` e `mine`. Se o dono não for você e afundar só para ele/observadores ⇒ ownership (D).
6. **`prop_pallet_05a` se comporta diferente?** Troque o modelo (`Config.Polarix.DefaultPalletModel` ou `prop_model` do slot no admin) por `prop_pallet_05a`, reinicie e repita 1–5. Estável ⇒ asset (B).
7. **Congelado fica visualmente correto?** Com o pallet acompanhado, rode `/palletdebug freeze` (e `/palletdebug unfreeze` para soltar; só age quando você digita) e observe `heightAboveGround` e o visual; se já nasce enterrado ⇒ pivô/bounds (A); se só afunda quando solto ⇒ física/suporte (C).

## Matriz de decisão
| Observação | Conclusão |
|---|---|
| Enterrado já no `snap`, estável depois | pivô/bounds ou placement (A) |
| Estável congelado, afunda solto | colisão dinâmica / suporte (B/C) |
| `prop_pallet_05a` estável, 04b afunda | colisão do asset (B) |
| Afunda só com owner ≠ operador | ownership (D) |
| Queda coincide com re-snap | segundo sync (E) |

Envie: as linhas `[AUST PALLET DEBUG]` do client e do servidor de um pallet do spawn até 30 s depois, mais o resultado de cada pergunta acima.
