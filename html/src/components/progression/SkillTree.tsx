import { useStatsStore } from '../../stores/useStatsStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { SkillType } from '../../types'

const SKILL_META: Record<SkillType, { label: string; icon: string; desc: string }> = {
  distance: { label: 'Distância',  icon: '🛣️', desc: '+2% p/ nível em rotas ≥10km'              },
  valuable: { label: 'Valioso',    icon: '💎', desc: '+2% p/ nível em jobs ≥$1.500'             },
  fragile:  { label: 'Frágil',     icon: '📦', desc: '+2% p/ nível com integridade ≥85%'        },
  speed:    { label: 'Velocidade', icon: '⚡', desc: '+2% p/ nível no multiplicador de tempo'   },
}

const SKILL_TYPES: SkillType[] = ['distance', 'valuable', 'fragile', 'speed']
const MAX_LEVEL = 6

interface SkillTreeProps {
  onStatsRefresh: () => void
}

export function SkillTree({ onStatsRefresh }: SkillTreeProps) {
  const { stats, skills, setSkillLevel } = useStatsStore()
  const skillPoints = stats?.skill_points ?? 0

  const handlePurchase = async (skillType: SkillType) => {
    const currentLevel = skills[skillType]
    if (currentLevel >= MAX_LEVEL || skillPoints < 1) return

    const result = await fetchNUI<{ success: boolean; error?: string }>(
      'purchaseSkill',
      { skillType }
    )
    if (result.success) {
      setSkillLevel(skillType, currentLevel + 1)
      onStatsRefresh()  // re-fetch stats para atualizar skill_points no store
    } else {
      // purchaseSkill failed: handled silently (error shown via lib.notify server-side)
    }
  }

  const totalBonus = Object.values(skills).reduce((sum, lvl) => sum + lvl, 0) * 2

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-txt uppercase tracking-wider">
          Árvore de Skills
        </span>
        <div className="flex items-center gap-2">
          {totalBonus > 0 && (
            <span className="text-[10px] text-success-dark font-medium">
              +{totalBonus}% bônus total
            </span>
          )}
          <span className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${
            skillPoints > 0
              ? 'bg-warning/20 text-warning'
              : 'bg-card-alt text-txt-secondary'
          }`}>
            {skillPoints} ponto{skillPoints !== 1 ? 's' : ''}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-4 gap-2">
        {SKILL_TYPES.map((skillType) => {
          const meta         = SKILL_META[skillType]
          const level        = skills[skillType]
          const canUpgrade   = skillPoints > 0 && level < MAX_LEVEL
          const isMaxed      = level >= MAX_LEVEL

          return (
            <div
              key={skillType}
              className="bg-card/60 border border-app-border/50 rounded-lg p-2.5 flex flex-col gap-2"
            >
              {/* Cabeçalho */}
              <div className="text-center">
                <div className="text-xl leading-none mb-0.5">{meta.icon}</div>
                <div className="text-[11px] font-semibold text-txt-light">{meta.label}</div>
                <div className="text-[9px] text-txt-secondary leading-tight mt-0.5">{meta.desc}</div>
              </div>

              {/* Barra de nível */}
              <div className="flex justify-center gap-0.5">
                {Array.from({ length: MAX_LEVEL }, (_, i) => (
                  <div
                    key={i}
                    className={`w-5 h-2 rounded-sm transition-colors ${
                      i < level
                        ? 'bg-warning'
                        : 'bg-card-alt'
                    }`}
                  />
                ))}
              </div>

              {/* Status / botão */}
              <div className="text-center">
                {isMaxed ? (
                  <span className="text-[10px] text-success-dark font-semibold">
                    MÁXIMO (+{level * 2}%)
                  </span>
                ) : canUpgrade ? (
                  <button
                    onClick={() => handlePurchase(skillType)}
                    className="w-full text-[10px] bg-warning/20 hover:bg-warning/30 text-warning py-1 rounded transition-colors font-medium"
                  >
                    Nível {level + 1} (+{(level + 1) * 2}%)
                  </button>
                ) : (
                  <span className="text-[10px] text-txt-muted">
                    {level > 0 ? `Nível ${level} (+${level * 2}%)` : 'Nenhum ponto'}
                  </span>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
