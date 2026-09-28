import { useState } from 'react'
import type { NpcDriver } from '../../types'
import { fetchNUI } from '../../hooks/useNUI'

interface Props {
  driver: NpcDriver
  canManage: boolean
  onUpdated: () => void
}

const SKILL_BADGE: Record<string, string> = {
  junior: 'bg-txt-muted text-txt-light',
  pleno:  'bg-primary-active text-primary-light',
  senior: 'bg-warning/60 text-gold',
}

const STATUS_LABEL: Record<string, string> = {
  idle:    'Disponível',
  working: 'Em rota',
  resting: 'Retido',
}

export function NpcDriverCard({ driver, canManage, onUpdated }: Props) {
  // UI-H03: substituir confirm()/alert() (quebrados no CEF do FiveM) por modal React
  const [confirmFire, setConfirmFire] = useState(false)
  const [trainError,  setTrainError ] = useState<string | null>(null)

  const satColor = driver.satisfaction >= 60
    ? 'bg-success'
    : driver.satisfaction >= 30
    ? 'bg-gold'
    : 'bg-danger'

  async function handleFire() {
    const r = await fetchNUI<{ success: boolean; reason?: string }>('fireNpcDriver', driver.id)
    if (r.success) {
      setConfirmFire(false)
      onUpdated()
    }
  }

  async function handleTrain() {
    setTrainError(null)
    const r = await fetchNUI<{ success: boolean; reason?: string; newSkill?: string }>('trainNpcDriver', driver.id)
    if (!r.success) setTrainError(r.reason ?? 'Erro ao treinar')
    else onUpdated()
  }

  return (
    <div className="bg-card rounded-lg p-3 flex flex-col gap-2">

      {/* UI-H03: Modal de confirmação de demissão (substituiu confirm()) */}
      {confirmFire && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 pointer-events-auto">
          <div className="bg-card rounded-lg border border-app-border w-64 p-4 space-y-4">
            <p className="text-txt-light text-sm text-center">Demitir {driver.name}?</p>
            <div className="flex gap-2">
              <button
                onClick={() => setConfirmFire(false)}
                className="flex-1 py-1.5 bg-card-alt hover:bg-app-bg text-txt rounded text-xs transition-colors"
              >
                Cancelar
              </button>
              <button
                onClick={handleFire}
                className="flex-1 py-1.5 bg-danger-dark hover:bg-danger text-danger rounded text-xs transition-colors font-semibold"
              >
                Confirmar
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="flex items-center gap-2">
        <span className={`text-xs font-bold px-2 py-0.5 rounded ${SKILL_BADGE[driver.skill_level] ?? ''}`}>
          {driver.skill_level.toUpperCase()}
        </span>
        <span className="text-txt-light text-sm font-medium flex-1">{driver.name}</span>
        <span className="text-txt text-xs">{STATUS_LABEL[driver.status] ?? driver.status}</span>
      </div>

      {/* Barra de satisfação */}
      <div className="flex items-center gap-2">
        <span className="text-txt text-xs w-20">Satisfação</span>
        <div className="flex-1 bg-card-alt rounded-full h-2">
          <div className={`h-2 rounded-full ${satColor}`} style={{ width: `${driver.satisfaction}%` }} />
        </div>
        <span className="text-txt text-xs w-8 text-right">{driver.satisfaction}%</span>
      </div>

      {/* Stats */}
      <div className="flex gap-4 text-xs text-txt">
        <span>XP: {driver.xp}</span>
        <span>Tenure: {driver.tenure_days}d</span>
        <span>Total: ${driver.total_earnings.toLocaleString()}</span>
      </div>

      {/* UI-H03: erro de treino (substituiu alert()) */}
      {trainError && (
        <p className="text-danger text-xs text-center">{trainError}</p>
      )}

      {/* Ações — UI-M01: hover classes distintas do estado normal */}
      {canManage && (
        <div className="flex gap-2 mt-1">
          {driver.skill_level !== 'senior' && (
            <button
              onClick={handleTrain}
              className="flex-1 bg-primary-active hover:bg-primary text-primary-light rounded px-2 py-1 text-xs transition-colors"
            >
              Treinar
            </button>
          )}
          <button
            onClick={() => setConfirmFire(true)}
            className="bg-danger-dark hover:bg-danger text-danger rounded px-2 py-1 text-xs transition-colors"
          >
            Demitir
          </button>
        </div>
      )}
    </div>
  )
}
