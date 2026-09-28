import { useState } from 'react'
import type { AgencyProfile } from '../../types'
import { fetchNUI } from '../../hooks/useNUI'

interface Props {
  profiles: AgencyProfile[]
  onClose: () => void
  onHired: () => void
}

const SKILL_LABEL: Record<string, string> = {
  junior: 'Junior',
  pleno:  'Pleno',
  senior: 'Sênior',
}

export function NpcHireModal({ profiles, onClose, onHired }: Props) {
  const [loading, setLoading] = useState(false)
  const [error, setError]     = useState<string | null>(null)

  async function handleHire(profile: AgencyProfile) {
    setLoading(true)
    setError(null)
    const r = await fetchNUI<{ success: boolean; reason?: string }>(
      'hireNpcDriver', { profileIndex: profile.index }
    )
    setLoading(false)
    if (r.success) {
      onHired()
    } else {
      setError(r.reason ?? 'Erro ao contratar')
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-app-bg rounded-xl border border-app-border w-[400px] p-4 flex flex-col gap-3">
        <div className="flex justify-between items-center">
          <h3 className="text-txt-light font-semibold">Agência de Emprego</h3>
          <button onClick={onClose} className="text-txt hover:text-txt-light text-lg">×</button>
        </div>

        {error && (
          <div className="bg-danger-dark/20 border border-danger-dark text-danger rounded px-3 py-2 text-sm">
            {error}
          </div>
        )}

        <p className="text-txt text-xs">Vá até a agência para contratar. Perfis renovam a cada 24h.</p>

        <div className="flex flex-col gap-2">
          {profiles.map((p) => (
            <div key={p.index} className="bg-card rounded-lg p-3 flex items-center justify-between gap-3">
              <div>
                <div className="text-txt-light text-sm font-medium">{p.name}</div>
                <div className="text-txt text-xs">
                  {SKILL_LABEL[p.skillLevel] ?? p.skillLevel} · Salário: ${p.salary}/job
                </div>
              </div>
              <button
                onClick={() => handleHire(p)}
                disabled={loading}
                className="bg-success-dark hover:bg-success text-white rounded px-3 py-1 text-sm font-medium disabled:opacity-50"
              >
                ${p.hireCost.toLocaleString()}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
