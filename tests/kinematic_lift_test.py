#!/usr/bin/env python3
"""Testes do levantamento cinemático (shared/fork_lift.lua) e do estado lógico do pallet
(server/pallet_registry.lua). Requer: pip install lupa. Uso: python3 tests/kinematic_lift_test.py"""
import os, re, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = LuaRuntime(unpack_returned_tuples=True)
for f in ('shared/fork_lift.lua', 'server/pallet_registry.lua'):
    L.execute(open(os.path.join(ROOT, f), encoding='utf-8').read())

L.execute('''
CFG = { LiftThreshold = 0.08, LiftHysteresis = 0.03, LiftDwellMs = 150, MaxForkliftSpeed = 1.5, HeadingTolerance = 25.0,
        Align = { xMax = 1.3, yMin = 0.1, yMax = 3.5, zMax = 0.9 } }
function runSeq(seq, aligned)
  -- seq = lista de {t, boneZ}; devolve a lista de eventos
  local st, out = ForkLift.NewDetector(), {}
  for _, s in ipairs(seq) do
    local ev = ForkLift.Step(st, s[1], aligned == nil and true or aligned, s[2], CFG)
    out[#out + 1] = ev
  end
  return table.concat(out, ','), st
end
function mkLobby(n)
  local nets = {}
  for i = 1, n do nets[i] = 1000 + i end
  return { requiredCount = n, palletNetIds = nets, loadedCount = 0 }
end
''')

results = []
def check(name, cond, detail=''):
    results.append((name, bool(cond), detail))
def lua(expr): return L.eval(expr)

# ---- Ângulos -------------------------------------------------------------
check('ANGLE diferença modular 350 vs 10 = 20', abs(lua('ForkLift.AngleDiff(350, 10)') - 20.0) < 1e-9)
check('ANGLE 0 vs 180 = 180', abs(lua('ForkLift.AngleDiff(0, 180)') - 180.0) < 1e-9)
check('AXIS 0 vs 180 = 0 (pallet simétrico)', abs(lua('ForkLift.AxisDiff(0, 180)')) < 1e-9)
check('AXIS 90 vs 0 = 90', abs(lua('ForkLift.AxisDiff(90, 0)') - 90.0) < 1e-9)
check('AXIS NaN vira rejeição (>= 90)', lua('ForkLift.AxisDiff(0/0, 0)') >= 90.0)
# bug do ESX: "angle < 1 or angle - 180 < 1" aceitaria 170°; o módulo rejeita
check('ANGLE ESX aceitaria 170 vs 0; AxisDiff dá 10 (>1)', abs(lua('ForkLift.AxisDiff(170, 0)') - 10.0) < 1e-9)

# ---- Alinhamento ---------------------------------------------------------
def aligned(x, y, z, hd=0.0, sp=0.0):
    return lua('ForkLift.IsAligned({x=%s,y=%s,z=%s}, %s, %s, CFG)' % (x, y, z, hd, sp))
check('ALIGN dentro da caixa', aligned(0.2, 1.5, 0.1))
check('ALIGN fora em X', not aligned(1.4, 1.5, 0.1))
check('ALIGN atrás do garfo (y < yMin)', not aligned(0.0, 0.0, 0.0))
check('ALIGN longe demais (y > yMax)', not aligned(0.0, 3.6, 0.0))
check('ALIGN fora em Z', not aligned(0.0, 1.5, 1.0))
check('ALIGN heading acima da tolerância', not aligned(0.0, 1.5, 0.0, hd=30.0))
check('ALIGN velocidade alta', not aligned(0.0, 1.5, 0.0, sp=2.0))
check('ALIGN NaN no pallet', not lua('ForkLift.IsAligned({x=0/0,y=1,z=0}, 0, 0, CFG)'))
check('ALIGN nil no pallet', not lua('ForkLift.IsAligned(nil, 0, 0, CFG)'))

# ---- Detector ------------------------------------------------------------
evs, _ = L.eval('function() return runSeq({{0,1.00},{50,1.00},{100,1.01}}) end')()
check('DETECTOR parado: engage e nenhum intent', evs == 'engage,none,none', evs)
evs, _ = L.eval('function() return runSeq({{0,1.0},{50,1.09},{100,1.09},{150,1.09},{200,1.09}}) end')()
check('DETECTOR sobe 9 cm e sustenta 150 ms => intent', evs.endswith('intent'), evs)
evs, _ = L.eval('function() return runSeq({{0,1.0},{50,1.09},{100,1.09},{120,1.0}}) end')()
check('DETECTOR sobe e desce antes do dwell => sem intent', 'intent' not in evs, evs)
evs, _ = L.eval('function() return runSeq({{0,1.0},{50,1.05},{100,1.05},{300,1.05}}) end')()
check('DETECTOR 5 cm (< 8 cm) nunca dispara', 'intent' not in evs, evs)
# histerese: oscila perto do limiar sem zerar o dwell
evs, _ = L.eval('function() return runSeq({{0,1.0},{10,1.085},{60,1.07},{120,1.085},{200,1.085}}) end')()
check('DETECTOR histerese (1.07 > 0.08-0.03) não reinicia o dwell', evs.endswith('intent'), evs)
# fora da histerese reinicia
evs, _ = L.eval('function() return runSeq({{0,1.0},{10,1.09},{60,1.04},{120,1.09},{200,1.09}}) end')()
check('DETECTOR queda abaixo de limiar-histerese reinicia dwell (sem intent)', 'intent' not in evs, evs)
# mastro descendo antes de subir: repouso acompanha o mínimo
evs, _ = L.eval('function() return runSeq({{0,1.0},{50,0.90},{100,0.99},{150,0.99},{200,0.99},{260,0.99}}) end')()
check('DETECTOR repouso acompanha o ponto mais baixo (descer não é intent; subir 9 cm de 0.90 é)', evs.endswith('intent'), evs)
# desalinhamento
evs, st = L.eval('function() return runSeq({{0,1.0},{50,1.09},{100,1.09}}, false) end')()
check('DETECTOR desalinhado nunca engata', evs == 'none,none,none', evs)
r = L.eval('''function()
  local st = ForkLift.NewDetector()
  ForkLift.Step(st, 0, true, 1.0, CFG)
  local ev = ForkLift.Step(st, 10, false, 1.0, CFG)
  return ev, st.phase
end''')()
check('DETECTOR perder o alinhamento => disengage e volta a idle', r == ('disengage', 'idle'), str(r))
check('DETECTOR boneZ NaN ignorado', L.eval('function() local st=ForkLift.NewDetector() local ev = ForkLift.Step(st,0,true,0/0,CFG) return ev end')() == 'none')
# determinístico a 50 ms: 3 ticks de dwell
evs, _ = L.eval('function() return runSeq({{0,1.0},{50,1.09},{100,1.09},{150,1.09},{200,1.09}}) end')()
check('DETECTOR dwell de 150 ms: intent só no 5º tick (t=200)', evs == 'engage,none,none,none,intent', evs)

# ---- Pose relativa / attach ---------------------------------------------
rel = L.eval('''ForkLift.RelativeAttach({x=0.3,y=2.0,z=0.1},{x=0.0,y=1.5,z=0.4},{x=0,y=0,z=90},{x=0,y=0,z=10})''')
check('ATTACH offset = pallet - osso (referencial do forklift)',
      abs(rel.x - 0.3) < 1e-9 and abs(rel.y - 0.5) < 1e-9 and abs(rel.z + 0.3) < 1e-9)
check('ATTACH yaw relativo = 80', abs(rel.yaw - 80.0) < 1e-9)
rel2 = L.eval('''ForkLift.RelativeAttach({x=0,y=0,z=0},{x=0,y=0,z=0},{x=0,y=0,z=350},{x=0,y=0,z=10})''')
check('ATTACH yaw normalizado em [-180,180) (350-10=340 => -20)', abs(rel2.yaw + 20.0) < 1e-9)
check('ATTACH erro de posição', abs(lua('ForkLift.AttachError({x=0,y=0,z=0},{x=0.03,y=0.04,z=0})') - 0.05) < 1e-9)

mid = L.eval('ForkLift.Blend({x=0,y=0,z=0,pitch=0,roll=0,yaw=170},{x=1,y=2,z=3,pitch=0,roll=0,yaw=-170},0.5)')
check('BLEND meio do caminho', abs(mid.x - 0.5) < 1e-9 and abs(mid.z - 1.5) < 1e-9)
check('BLEND yaw pelo caminho curto (170 -> -170 passa por 180)', abs(abs(mid.yaw) - 180.0) < 1e-6 or abs(mid.yaw - 180.0) < 1e-6, str(mid.yaw))
check('BLEND t fora de 0..1 é limitado', abs(lua('ForkLift.Blend({x=0,y=0,z=0,pitch=0,roll=0,yaw=0},{x=4,y=0,z=0,pitch=0,roll=0,yaw=0},9).x') - 4.0) < 1e-9)

# ---- Perfil forklift x pallet -------------------------------------------
prof = L.eval('''ForkLift.ResolveProfile({ ['111'] = { ['222'] = { bone='forks', x=0.1, z=0.2, yaw=5 } } }, {'999','111'}, {'333','222'})''')
check('PERFIL resolvido por combinação', prof and prof.bone == 'forks' and abs(prof.x - 0.1) < 1e-9 and prof.y == 0.0 and prof.yaw == 5)
check('PERFIL inexistente => nil (sem fallback para offset de trailer)',
      lua("ForkLift.ResolveProfile({ ['111'] = { ['222'] = {} } }, {'111'}, {'999'})") is None)
check('PERFIL tabela vazia/nil => nil', lua('ForkLift.ResolveProfile(nil, {"1"}, {"2"})') is None)

# ---- Registry: estados --------------------------------------------------
def regcall(code): return L.eval('function() %s end' % code)()
r = regcall('''local lb = mkLobby(3)
  local ok, why, rec = PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {maxCarried=1})
  return ok, rec.state, rec.carrier, rec.version''')
check('STATE claim: STAGED -> CLAIMED', r == (True, 'CLAIMED', 7, 1), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local ok, why, rec, idem = PalletRegistry.Claim(lb, 1001, 7, 'r1', 1100, {})
  return ok, idem, rec.version''')
check('STATE claim idempotente (mesmo reqId e carregador)', r == (True, True, 1), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local ok, why = PalletRegistry.Claim(lb, 1001, 8, 'r2', 1100, {})
  return ok, why''')
check('STATE segundo jogador não reivindica pallet CLAIMED', r[0] is False and 'CLAIMED' in r[1], str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {maxCarried=1})
  local ok, why = PalletRegistry.Claim(lb, 1002, 7, 'r2', 1100, {maxCarried=1})
  return ok, why''')
check('STATE um forklift carrega um pallet por vez', r[0] is False and 'já segura' in r[1], str(r))
r = regcall('''local lb = mkLobby(3)
  local ok, why = PalletRegistry.Claim(lb, 9999, 7, 'r1', 1000, {})
  return ok, why''')
check('STATE netId fora do lobby recusado', r[0] is False and 'não é palete' in r[1], str(r))
r = regcall('''local lb = mkLobby(3)
  local ok, why = PalletRegistry.Claim(lb, 'x', 7, 'r1', 1000, {})
  return ok, why''')
check('STATE netId malformado recusado', r[0] is False, str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local ok1 = PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  local ok2, _, _, idem = PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  return ok1, ok2, idem, lb.palletStates[1001].state''')
check('STATE CLAIMED -> CARRIED, confirmação repetida é idempotente', r == (True, True, True, 'CARRIED'), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local ok, why = PalletRegistry.ConfirmCarry(lb, 1001, 8, 'r1')
  return ok''')
check('STATE só o carregador confirma', r is False)
r = regcall('''local lb = mkLobby(3)
  local ok = PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  return ok''')
check('STATE confirmar sem claim é recusado (STAGED)', r is False)

# lease
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local early = PalletRegistry.ExpireClaims(lb, 5000, 10000)
  local late = PalletRegistry.ExpireClaims(lb, 12000, 10000)
  return #early, #late, lb.palletStates[1001].state''')
check('LEASE CLAIMED expira só após o lease e volta a STAGED', r == (0, 1, 'STAGED'), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  local freed = PalletRegistry.ExpireClaims(lb, 999999, 10000)
  return #freed, lb.palletStates[1001].state''')
check('LEASE CARRIED não expira', r == (0, 'CARRIED'), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ExpireClaims(lb, 20000, 10000)
  local ok = PalletRegistry.Claim(lb, 1001, 8, 'r9', 20001, {})
  return ok, lb.palletStates[1001].carrier''')
check('LEASE slot preso (Polarix) é liberado e outro jogador reivindica', r == (True, 8), str(r))

# release
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  local ok = PalletRegistry.Release(lb, 1001, 7, 'rr')
  local ok2, _, _, idem = PalletRegistry.Release(lb, 1001, 7, 'rr')
  return ok, ok2, idem, lb.palletStates[1001].state''')
check('RELEASE CARRIED -> STAGED; repetir é idempotente', r == (True, True, True, 'STAGED'), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local ok = PalletRegistry.Release(lb, 1001, 8, 'rr')
  return ok''')
check('RELEASE só o carregador libera', r is False)

# estiva
r = regcall('''local lb = mkLobby(3)
  local ok1 = PalletRegistry.CanStow(lb, 1001, 7, true)
  local ok2 = PalletRegistry.CanStow(lb, 1001, 7, false)
  return ok1, ok2''')
check('STOW strict recusa STAGED; legado aceita', r == (False, True), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local a = PalletRegistry.CanStow(lb, 1001, 7, true)
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  local b = PalletRegistry.CanStow(lb, 1001, 7, true)
  local c = PalletRegistry.CanStow(lb, 1001, 8, true)
  return a, b, c''')
check('STOW exige CARRIED pelo mesmo jogador (CLAIMED não basta; outro jogador não)', r == (False, True, False), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  PalletRegistry.MarkStowed(lb, 1001, 2)
  local ok = PalletRegistry.CanStow(lb, 1001, 7, true)
  return lb.palletStates[1001].state, lb.palletStates[1001].slot, ok, PalletRegistry.CarriedBy(lb, 7)''')
check('STOW MarkStowed => STOWED, libera o forklift (carregando 0)', r == ('STOWED', 2, True, 0), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  PalletRegistry.MarkStowed(lb, 1001, 1)
  local n = PalletRegistry.MarkDelivered(lb)
  return n, lb.palletStates[1001].state''')
check('DELIVERED só a partir de STOWED', r == (1, 'DELIVERED'), str(r))
check('STOW sem netId em strict é recusado', regcall('local lb=mkLobby(1) local ok=PalletRegistry.CanStow(lb, nil, 7, true) return ok') is False)

# recuperação
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  local list = PalletRegistry.Recover(lb, 7)
  local st1 = lb.palletStates[1001].state
  local okR = PalletRegistry.MarkRecovered(lb, 1001)
  local ok = PalletRegistry.Claim(lb, 1001, 8, 'r5', 5000, {})
  return #list, st1, okR, ok''')
check('RECOVERY queda do carregador: CARRIED -> RECOVERY -> STAGED -> reivindicável', r == (1, 'RECOVERY', True, True), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.ConfirmCarry(lb, 1001, 7, 'r1')
  PalletRegistry.MarkStowed(lb, 1001, 1)
  local list = PalletRegistry.Recover(lb, 7)
  return #list, lb.palletStates[1001].state''')
check('RECOVERY não mexe em pallet já STOWED', r == (0, 'STOWED'), str(r))
r = regcall('''local lb = mkLobby(3)
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  local before = lb.palletStates[1001].version
  PalletRegistry.Claim(lb, 1001, 7, 'r1', 1000, {})
  PalletRegistry.Claim(lb, 1001, 8, 'r2', 1000, {})
  return before == lb.palletStates[1001].version''')
check('CAS: claims repetidos/concorrentes não mudam a versão', r is True)

# Registry legado intacto
r = regcall('''local lb = mkLobby(2)
  local v = PalletRegistry.Evaluate(lb, 1, 1001)
  PalletRegistry.Commit(lb, 1001, 1, 1)
  local v2 = PalletRegistry.Evaluate(lb, 1, 1001)
  return v, v2''')
check('LEGADO Evaluate/Commit continuam funcionando', r == ('ok', 'retry'), str(r))

# ---- Config e fiação estática (arquivos que já existem) -------------------
cfg = open(os.path.join(ROOT, 'shared/config.lua'), encoding='utf-8').read()
check('CONFIG KinematicLift presente', 'KinematicLift = {' in cfg and 'LiftThreshold = 0.08' in cfg)
check('CONFIG Enabled é a única chave de rollback', re.search(r'KinematicLift = \{\s*Enabled = (?:true|false)', cfg) is not None)
check('CONFIG ForkliftAttachProfiles separado dos offsets de trailer', 'ForkliftAttachProfiles = {}' in cfg)
check('CONFIG MaxLiftTolerance marcado como legado', 'legado: nenhum código usa' in cfg)

srv = open(os.path.join(ROOT, 'server/main.lua'), encoding='utf-8').read()
check('SERVER callback palletClaim registrado', "lib.callback.register('aurp_trucker:server:palletClaim'" in srv)
check('SERVER eventos confirmCarry/release/kinematicOff',
      all(("'aurp_trucker:server:%s'" % e) in srv for e in ('palletConfirmCarry', 'palletRelease', 'palletKinematicOff')))
check('SERVER estiva consulta CanStow strict', 'PalletRegistry.CanStow(lobby, palletNetId, src, true)' in srv)
check('SERVER MarkStowed após Commit', 'PalletRegistry.MarkStowed(lobby, palletNetId, slotIndex)' in srv)
check('SERVER unfreeze global só no fluxo legado', 'if not klActive and lobby.pallets then' in srv)
check('SERVER playerDropped chama Recover', 'PalletRegistry.Recover(lobby, src)' in srv)
check('SERVER claim valida forklift do lobby e distância',
      'GetVehiclePedIsIn(ped, false) ~= lobby.forklift' in srv and 'kl.ClaimMaxDist' in srv)

dbg = open(os.path.join(ROOT, 'client/modules/pallet_debug.lua'), encoding='utf-8').read()
check('DEBUG hooks OnState/OnLift', 'function PalletDebug.OnState' in dbg and 'function PalletDebug.OnLift' in dbg)

# sintaxe Lua 5.4 dos arquivos tocados
for f in ('shared/fork_lift.lua', 'server/pallet_registry.lua', 'server/main.lua', 'shared/config.lua',
          'client/modules/pallet_debug.lua', 'client/modules/forklift.lua'):
    src = open(os.path.join(ROOT, f), encoding='utf-8').read()
    err = L.eval('function(s) local f, e = load(s) return e end')(src)
    check('SINTAXE %s' % f, err is None, str(err))

# ---- Relatório -----------------------------------------------------------
w = max(len(n) for n, _, _ in results)
fails = 0
for n, ok, d in results:
    print(('PASS' if ok else 'FAIL'), n.ljust(w), ('' if ok else '  -> ' + d))
    fails += 0 if ok else 1
print('\n%d/%d PASS' % (len(results) - fails, len(results)))
sys.exit(1 if fails else 0)
