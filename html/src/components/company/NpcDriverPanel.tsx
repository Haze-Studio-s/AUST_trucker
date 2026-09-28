import { useState } from 'react'
import { useNpcDriverStore } from '../../stores/useNpcDriverStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import { NpcDriverCard } from './NpcDriverCard'
import { NpcHireModal } from './NpcHireModal'

export function NpcDriverPanel() {
  const { drivers, profiles, reputation, allowIllegal, setDrivers, setReputation, setAllowIllegal, setProfiles } =
    useNpcDriverStore()
  const { company } = useCompanyStore()
  const [showHire, setShowHire] = useState(false)
  const [loading, setLoading]   = useState(false)

  const canManage = company?.role === 'owner' || company?.role === 'manager'
  const isOwner   = company?.role === 'owner'

  async function refresh() {
    const r = await fetchNUI<{
      success: boolean
      drivers?: typeof drivers
      reputation?: number
      allowIllegal?: boolean
      profiles?: typeof profiles
    }>('getNpcDriverData')
    if (r.success) {
      setDrivers(r.drivers ?? [])
      setReputation(r.reputation ?? 100)
      setAllowIllegal(r.allowIllegal ?? false)
      setProfiles(r.profiles ?? [])
    }
  }

  async function toggleIllegal() {
    setLoading(true)
    await fetchNUI('setNpcAllowIllegal', !allowIllegal)
    setAllowIllegal(!allowIllegal)
    setLoading(false)
  }

  const repColor = reputation >= 70 ? 'text-success' : reputation >= 40 ? 'text-gold' : 'text-danger'

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-txt-light">Motoristas NPC</h2>
        <span className={`text-sm font-medium ${repColor}`}>
          Reputação: {reputation}/100
        </span>
      </div>

      {/* Toggle ilegal + botão contratar */}
      <div className="flex gap-2">
        {isOwner && (
          <button
            onClick={toggleIllegal}
            disabled={loading}
            className={`flex-1 rounded px-3 py-2 text-sm font-medium transition-colors ${
              allowIllegal
                ? 'bg-danger-dark text-danger hover:bg-danger-dark'
                : 'bg-card-alt text-txt hover:bg-hover-bg'
            }`}
          >
            {allowIllegal ? 'Ilegais: ON' : 'Ilegais: OFF'}
          </button>
        )}
        {canManage && drivers.length < 5 && (
          <button
            onClick={() => setShowHire(true)}
            className="flex-1 bg-success-dark hover:bg-success text-white rounded px-3 py-2 text-sm font-medium"
          >
            Contratar ({drivers.length}/5)
          </button>
        )}
      </div>

      {/* Lista de drivers */}
      {drivers.length === 0 ? (
        <p className="text-txt-secondary text-sm text-center py-4">Nenhum motorista contratado.</p>
      ) : (
        <div className="flex flex-col gap-2 overflow-auto max-h-[340px]">
          {drivers.map((d) => (
            <NpcDriverCard
              key={d.id}
              driver={d}
              canManage={canManage}
              onUpdated={refresh}
            />
          ))}
        </div>
      )}

      {showHire && (
        <NpcHireModal
          profiles={profiles}
          onClose={() => setShowHire(false)}
          onHired={() => { setShowHire(false); refresh() }}
        />
      )}
    </div>
  )
}
