import { useStatsStore } from '../../stores/useStatsStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { SkillType } from '../../types'

const SKILL_META: Record<string, { label: string; icon: string; desc: string; maxDesc?: string }> = {
  distance: {
    label: 'Longa Distância',
    icon: '🛣️',
    desc: 'Desbloqueia rotas de maior raio e concede até +12% de bônus financeiro.',
    maxDesc: 'Rotas continentais sem limite de km'
  },
  valuable: {
    label: 'Carga Valiosa',
    icon: '💎',
    desc: 'Fretes de alta cotação com bônus de até +12% de pagamento e +60% de XP.',
    maxDesc: 'Especialista em cargas preciosas'
  },
  fragile: {
    label: 'Carga Frágil',
    icon: '📦',
    desc: 'Produtos delicados (vidro, eletrônicos). Até +12% de pagamento e +60% de XP.',
    maxDesc: 'Mestre em manuseio sem avarias'
  },
  fast: {
    label: 'Entrega Urgente',
    icon: '⚡',
    desc: 'Prazos just-in-time exigentes com bônus agressivo de até +12% e +60% de XP.',
    maxDesc: 'Piloto logístico prioritário'
  },
  product_type: {
    label: 'Certificados ADR',
    icon: '☣️',
    desc: 'Habilita classes de produtos perigosos: Explosivos, Gases, Inflamáveis e Tóxicos.',
    maxDesc: 'Certificação ADR Nível 6 Completa'
  },
  illegal: {
    label: 'Clandestino / Ilegal',
    icon: '💀',
    desc: 'Acesso a contratos arriscados no submundo com multiplicador base de 1.8x.',
    maxDesc: 'Transportador Clandestino Elite'
  }
}

const SKILL_TYPES: SkillType[] = ['distance', 'valuable', 'fragile', 'fast', 'product_type', 'illegal']
const MAX_LEVEL = 6

interface SkillTreeProps {
  onStatsRefresh: () => void
}

export function SkillTree({ onStatsRefresh }: SkillTreeProps) {
  const { stats, skills, setSkillLevel } = useStatsStore()
  const skillPoints = stats?.skill_points ?? 0

  const handlePurchase = async (skillType: SkillType) => {
    const currentLevel = (skills as any)[skillType] ?? 0
    if (currentLevel >= MAX_LEVEL || skillPoints < 1) return

    try {
      const result = await fetchNUI<{ ok: boolean; reason?: string }>(
        'upgradeSkill',
        { skillType }
      )
      if (result && result.ok) {
        setSkillLevel(skillType, currentLevel + 1)
        onStatsRefresh()
      }
    } catch {
      // Ignorar falha no Dev
    }
  }

  return (
    <div className="space-y-4 select-none">
      <div className="flex items-center justify-between border-b border-lation-line pb-2.5">
        <div className="flex items-center gap-2">
          <span className="w-2.5 h-2.5 rounded bg-lation-accent" />
          <h3 className="text-xs font-bold uppercase tracking-wider text-lation-content-sec">
            Árvore de Competências & Especializações (6 Ramos)
          </h3>
        </div>

        <div className="flex items-center gap-2">
          <span className={`text-[11px] px-3 py-1 rounded-full font-mono font-bold border ${
            skillPoints > 0
              ? 'bg-lation-btn-bg text-lation-btn-text border-lation-btn-border shadow-[0_0_10px_rgba(16,185,129,0.3)] animate-pulse'
              : 'bg-lation-surface-deep text-lation-content-muted border-lation-line'
          }`}>
            {skillPoints} Ponto{skillPoints !== 1 ? 's' : ''} Disponível{skillPoints !== 1 ? 'is' : ''}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {SKILL_TYPES.map((skillType) => {
          const meta = SKILL_META[skillType] || { label: skillType, icon: '⭐', desc: '' }
          const level = (skills as any)[skillType] ?? 0
          const canUpgrade = skillPoints > 0 && level < MAX_LEVEL
          const isMaxed = level >= MAX_LEVEL

          return (
            <div
              key={skillType}
              className="bg-lation-surface-band border border-lation-line hover:border-lation-line-focus rounded-lg p-3.5 flex flex-col justify-between transition-all"
            >
              <div>
                <div className="flex items-center gap-2.5 mb-2">
                  <div className="w-9 h-9 rounded-lg bg-lation-surface-deep border border-lation-line flex items-center justify-center text-lg">
                    {meta.icon}
                  </div>
                  <div>
                    <h4 className="text-xs font-bold text-white leading-tight">{meta.label}</h4>
                    <span className="text-[10px] font-mono text-lation-accent-bright font-semibold">
                      Nível {level} / {MAX_LEVEL}
                    </span>
                  </div>
                </div>

                <p className="text-[11px] text-lation-content-muted leading-relaxed mb-3">
                  {meta.desc}
                </p>
              </div>

              <div className="space-y-2.5 pt-2 border-t border-lation-line/60">
                {/* Indicadores de nível */}
                <div className="flex items-center gap-1.5">
                  {Array.from({ length: MAX_LEVEL }, (_, i) => (
                    <div
                      key={i}
                      className={`flex-1 h-1.5 rounded-sm transition-all ${
                        i < level
                          ? 'bg-lation-btn-bg border border-lation-btn-border shadow-[0_0_6px_rgba(16,185,129,0.5)]'
                          : 'bg-lation-surface-deep border border-lation-line'
                      }`}
                    />
                  ))}
                </div>

                {/* Ação de Aprimoramento */}
                {isMaxed ? (
                  <div className="py-1 px-2 text-center rounded bg-emerald-500/10 border border-emerald-500/30 text-[10px] font-bold text-emerald-400 font-mono">
                    COMPETÊNCIA MAXIMIZADA
                  </div>
                ) : (
                  <button
                    onClick={() => handlePurchase(skillType)}
                    disabled={!canUpgrade}
                    className={`w-full py-1.5 rounded text-xs font-bold tracking-wide transition-all ${
                      canUpgrade
                        ? 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border hover:brightness-110 shadow-sm'
                        : 'bg-lation-surface-deep text-lation-content-muted border border-lation-line cursor-not-allowed opacity-50'
                    }`}
                  >
                    {canUpgrade ? `Aprimorar para Nível ${level + 1}` : 'Requer Ponto de Habilidade'}
                  </button>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
