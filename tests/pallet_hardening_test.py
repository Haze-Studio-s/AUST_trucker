#!/usr/bin/env python3
"""Testes estáticos da Fase 2A (pallets). Requer: pip install lupa. Uso: python3 tests/pallet_hardening_test.py"""
import os, re, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = LuaRuntime(unpack_returned_tuples=True)
for f in ('shared/pallet_spawn_validation.lua', 'shared/pallet_sync_guard.lua', 'server/pallet_registry.lua'):
    L.execute(open(os.path.join(ROOT, f), encoding='utf-8').read())

L.execute('''
function mkLobby(required, nets) return { requiredCount = required, palletNetIds = nets, loadedCount = 0 } end
-- espelha a sequência de HandlePalletLoaded: Evaluate -> (ok) Commit com contagem
function handle(lobby, slot, nid)
  local v, r, n, s = PalletRegistry.Evaluate(lobby, slot, nid)
  if v == 'ok' then
    lobby.loadedCount = lobby.loadedCount + 1
    PalletRegistry.Commit(lobby, n, s, lobby.loadedCount)
  end
  return v, r
end
function spawnReasons(raw, rules)
  local acc, rej = PalletSpawnValidation.Validate(raw, rules)
  local out = {}
  for _, r in ipairs(rej) do out[#out + 1] = r.reason end
  return #acc, table.concat(out, '|')
end
''')

results = []
def check(name, cond, detail=''):
    results.append((name, bool(cond), detail))

def lua(expr): return L.eval(expr)
def run(code): return L.execute(code)

# ---- Spawns -------------------------------------------------------------
cfg = open(os.path.join(ROOT, 'shared/config.lua'), encoding='utf-8').read()
block = re.search(r'PalletSpawns = \{(.*?)\n        \},', cfg, re.S).group(1)
vecs = re.findall(r'vector4\(([-\d.]+), ([-\d.]+), ([-\d.]+)', block)
raw = '{' + ','.join('{x=%s,y=%s,z=%s}' % v for v in vecs) + '}'
acc, why = L.eval('function() return spawnReasons(%s, nil) end' % raw)()
check('SPAWN config atual (6) passa limpo', acc == len(vecs) == 6 and why == '', f'{acc} aceitos, rej="{why}"')
acc, why = L.eval('function() return spawnReasons({{x=1,y=1,z=1},{x=1,y=1,z=1}}, nil) end')()
check('SPAWN duplicata exata rejeitada', acc == 1 and why == 'duplicata exata', why)
acc, why = L.eval('function() return spawnReasons({{x=1,y=1,z=1},{x=1.2,y=1.1,z=1}}, nil) end')()
check('SPAWN duplicata aproximada rejeitada', acc == 1 and why == 'duplicata aproximada', why)
acc, why = L.eval('function() return spawnReasons({{x=0,y=0,z=1},{x=1.0,y=0,z=1}}, nil) end')()
check('SPAWN espaçamento mínimo', acc == 1 and why == 'muito próximo de outro spawn', why)
acc, why = L.eval('function() return spawnReasons({{x=0,y=0,z=1},{x=0,y=0,z=9}}, nil) end')()
check('SPAWN mesmo XY em Z diferente rejeitado (aproximada)', acc == 1 and why == 'duplicata aproximada', why)
acc, why = L.eval('function() return spawnReasons({{x=0/0,y=0,z=1},{x=1/0,y=0,z=1},{x=1,y="abc",z=1},"lixo",{x=1,y=2}}, nil) end')()
check('SPAWN NaN/inf/string/nil rejeitados', acc == 0 and why.count('|') == 4, why)
acc, why = L.eval('function() return spawnReasons({{x=99999,y=0,z=1},{x=0,y=0,z=-5000}}, nil) end')()
check('SPAWN fora do mundo', acc == 0 and why == 'coordenada fora do mundo|coordenada fora do mundo', why)
acc, why = L.eval('function() local t={} for i=1,20 do t[i]={x=i*10,y=0,z=1} end return spawnReasons(t, nil) end')()
check('SPAWN máximo 16', acc == 16 and why.count('excede') == 4, f'{acc} / {why}')
acc, why = L.eval('function() return spawnReasons({{x="5",y="6",z="7"}}, nil) end')()
check('SPAWN números como string do banco aceitos', acc == 1, why)
acc, why = L.eval('function() return spawnReasons(nil, nil) end')()
check('SPAWN lista nil não quebra', acc == 0)

# ---- Registry -----------------------------------------------------------
def h(lobby, slot, nid):
    return L.eval('function(l,s,n) return handle(l,s,n) end')(lobby, slot, nid)

lobby = lua('mkLobby(4, {101,102,103,104})')
v, _ = h(lobby, 1, 101)
check('REG primeiro palete aceito', v == 'ok' and lobby.loadedCount == 1)
v, _ = h(lobby, 1, 101)
check('REG mesmo pallet + mesmo slot = retry sem recontar', v == 'retry' and lobby.loadedCount == 1, v)
v, r = h(lobby, 2, 101)
check('REG mesmo pallet em outro slot rejeitado', v == 'reject' and 'já registrado' in r and lobby.loadedCount == 1, r)
v, r = h(lobby, 1, 102)
check('REG outro pallet em slot ocupado rejeitado', v == 'reject' and 'ocupado' in r and lobby.loadedCount == 1, r)
v, r = h(lobby, 2, 999)
check('REG pallet fora do job rejeitado', v == 'reject' and 'não é palete deste lobby' in r, r)
for bad in ('"101"', '101.5', '-3', '0', '0/0', '1/0', '{}', 'true'):
    v, r = L.eval('function() return handle(mkLobby(4,{101,102,103,104}), 1, %s) end' % bad)()
    check(f'REG netId malformado {bad}', v == 'reject' and 'malformado' in r, r)
for bad in ('0', '5', '-1', '1.5', '"x"', '0/0'):
    v, r = L.eval('function() return handle(mkLobby(4,{101,102,103,104}), %s, 101) end' % bad)()
    check(f'REG slot inválido {bad}', v == 'reject' and 'fora de 1..4' in r, r)
v, _ = h(lobby, 2, 102)
check('REG segundo pallet em slot livre aceito', v == 'ok' and lobby.loadedCount == 2)
v, _ = h(lobby, None, 102)
check('REG retry sem slot reconhecido', v == 'retry' and lobby.loadedCount == 2, v)
lobby2 = lua('mkLobby(2, {201,202})')
v1, _ = h(lobby2, None, None); v2, _ = h(lobby2, None, None); v3, _ = h(lobby2, None, None)
check('REG sem slot/netId resolve pela ordem do lobby e não duplica',
      (v1, v2, v3) == ('ok', 'ok', 'ok') and lobby2.loadedCount == 3 and lobby2.usedPallets[201] == 1 and lobby2.usedPallets[202] == 2,
      f'{v1},{v2},{v3}')
lobby3 = lua('mkLobby(3, {301,302,303})')
h(lobby3, 3, 303); v, _ = h(lobby3, 3, 303)
check('REG retry legítimo depois de contagem completa não conta de novo', v == 'retry' and lobby3.loadedCount == 1)

# ---- Placement (pallet↔trailer / trailer errado) ------------------------
ok = L.eval('function() return PalletRegistry.CheckPlacement(12.0, 60.0) end')()
check('PLACE pallet perto do trailer aceito', ok is True)
ok, r = L.eval('function() return PalletRegistry.CheckPlacement(250.0, 60.0) end')()
check('PLACE trailer errado/longe rejeitado', ok is False and 'máx' in r, r)
ok, r = L.eval('function() return PalletRegistry.CheckPlacement(nil, 60.0) end')()
check('PLACE entidade inexistente rejeitada', ok is False and 'inexistente' in r, r)
ok, r = L.eval('function() return PalletRegistry.CheckPlacement(0/0, 60.0) end')()
check('PLACE distância NaN rejeitada', ok is False, r)

# ---- Sync guard ---------------------------------------------------------
run('S = PalletSyncGuard.New()')
n1 = lua('PalletSyncGuard.Begin(S, "job1")'); c1 = lua('PalletSyncGuard.Claim(S, 11)')
n2 = lua('PalletSyncGuard.Begin(S, "job1")'); c2 = lua('PalletSyncGuard.Claim(S, 11)')
check('SYNC 2º sync do mesmo job não reaplica snap/física', (n1, c1, n2, c2) == (1, True, 2, False), (n1, c1, n2, c2))
check('SYNC netId diferente ainda aplica', lua('PalletSyncGuard.Claim(S, 12)') is True)
run('PalletSyncGuard.Release(S, 12)')
check('SYNC release após falha permite retry', lua('PalletSyncGuard.Claim(S, 12)') is True)
lua('PalletSyncGuard.Begin(S, "job2")')
check('SYNC novo job zera o estado', lua('PalletSyncGuard.Claim(S, 11)') is True and lua('S.syncCount') == 1)
run('PalletSyncGuard.Reset(S)')
check('SYNC reset limpa', lua('S.jobId') is None and lua('PalletSyncGuard.Claim(S, 11)') is True)
# 2 syncs concorrentes (thread 1 ainda esperando a entidade): só um aplica
run('S2 = PalletSyncGuard.New(); PalletSyncGuard.Begin(S2, "j"); a = PalletSyncGuard.Claim(S2, 5); PalletSyncGuard.Begin(S2, "j"); b = PalletSyncGuard.Claim(S2, 5)')
check('SYNC concorrência: só um claim por netId', lua('a') is True and lua('b') is False)

# ---- Arquivos: fxmanifest e wiring --------------------------------------
fx = open(os.path.join(ROOT, 'fxmanifest.lua'), encoding='utf-8').read()
for f in ('shared/pallet_spawn_validation.lua', 'shared/pallet_sync_guard.lua', 'server/pallet_registry.lua', 'client/modules/pallet_debug.lua'):
    check(f'MANIFEST lista {f}', f"'{f}'" in fx)
check('MANIFEST registry antes de server/main.lua', fx.index("'server/pallet_registry.lua'") < fx.index("'server/main.lua'"))
check('MANIFEST debug antes de main client', fx.index("'client/modules/pallet_debug.lua'") < fx.index("'client/main.lua'"))
check('MANIFEST shared antes do client', fx.index("'shared/pallet_sync_guard.lua'") < fx.index('client_scripts'))

# ---- Física inalterada (assinatura do bloco original) -------------------
cm = open(os.path.join(ROOT, 'client/main.lua'), encoding='utf-8').read()
for sig in ('SetEntityCoordsNoOffset(ent, pCoords.x, pCoords.y, finalRestZ, false, false, false)',
            'local finalRestZ = groundZ + bottomOffset + 0.02',
            'SetEntityDynamic(ent, false)', 'SetEntityHasGravity(ent, false)', 'FreezeEntityPosition(ent, true)',
            'SetEntityVelocity(ent, 0.0, 0.0, 0.0)'):
    check(f'FISICA da main preservada: {sig}', sig in cm)
sm = open(os.path.join(ROOT, 'server/main.lua'), encoding='utf-8').read()
check('FISICA servidor: spawn z+0.15 e Freeze(true) da main preservados',
      'CreateObject(pModel, coord.x, coord.y, coord.z + 0.15, true, true, false)' in sm and 'FreezeEntityPosition(pObj, true)' in sm and 'FreezeEntityPosition(pObj, false)' not in sm.split('LogPalletSpawn')[1][:600])
check('SYNC cliente usa os globais do módulo (sem guard local sombreando)',
      'local PalletSyncGuard' not in cm and 'local PalletSyncState' not in cm)
check('SYNC servidor envia jobId nos dois pontos', sm.count("polarixSyncPallets', src, palletNetIds, jobId)") == 1 and sm.count("polarixSyncPallets', src, lobby.palletNetIds, jobId)") == 1)

w = max(len(n) for n, _, _ in results)
bad = 0
for n, ok, d in results:
    print(('PASS' if ok else 'FAIL'), n.ljust(w), ('' if ok else f'  -> {d}'))
    bad += (not ok)
print(f'\n{len(results) - bad}/{len(results)} PASS')
sys.exit(1 if bad else 0)
