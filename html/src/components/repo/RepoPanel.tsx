import { useState } from 'react'
import { useRepoStore } from '../../stores/useRepoStore'
import { fetchNUI } from '../../hooks/useNUI'
import { RepoCard } from './RepoCard'
import type { RepoMissionType } from '../../types/repo'

const MISSION_LABEL: Record<RepoMissionType, string> = {
  simple:      'Simples',
  npc_hostile: 'Hostil',
  pvp:         'PVP',
  stealth:     'Stealth',
}

function formatCountdown(unixTs: number): string {
  const diff = unixTs - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'EXPIRADO'
  const hours = Math.floor(diff / 3600)
  const mins  = Math.floor((diff % 3600) / 60)
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export function RepoPanel() {
  const { repoOrders, activeRepoOrder, setActiveRepoOrder } = useRepoStore()
  const [abandoning, setAbandoning] = useState(false)

  async function handleAbandon() {
    if (!activeRepoOrder || abandoning) return
    setAbandoning(true)
    await fetchNUI('failRepoOrder', { orderId: activeRepoOrder.id })
    setActiveRepoOrder(null)
    setAbandoning(false)
  }

  return (
    <div className="space-y-4">
      {/* Active mission */}
      {activeRepoOrder && (
        <div className="bg-primary/20 border border-primary/30 rounded-lg p-3">
          <p className="text-xs text-primary uppercase tracking-wider font-medium mb-2">Missão Ativa</p>
          <div className="grid grid-cols-3 gap-2 text-center mb-3">
            <div>
              <p className="text-sm font-bold text-txt-light uppercase">{activeRepoOrder.vehicle_model}</p>
              <p className="text-[10px] text-txt-secondary">Veículo</p>
            </div>
            <div>
              <p className="text-sm font-bold text-txt">{MISSION_LABEL[activeRepoOrder.mission_type]}</p>
              <p className="text-[10px] text-txt-secondary">Tipo</p>
            </div>
            <div>
              <p className="text-sm font-bold text-success">${activeRepoOrder.payment.toLocaleString()}</p>
              <p className="text-[10px] text-txt-secondary">Recompensa</p>
            </div>
          </div>
          <p className="text-xs text-txt mb-3 text-center">
            Vá ao local e recolha o veículo — entregue no depósito (Sub-spec 2)
          </p>
          <p className="text-xs text-txt-secondary text-center mb-2">
            Expira em {formatCountdown(activeRepoOrder.expires_at_unix)}
          </p>
          <button
            onClick={handleAbandon}
            disabled={abandoning}
            className="w-full py-1.5 bg-card-alt hover:bg-danger-dark/20 text-txt hover:text-danger border border-app-border hover:border-danger/30 rounded text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {abandoning ? 'Aguarde...' : 'Abandonar Missão'}
          </button>
        </div>
      )}

      {/* Available orders */}
      <div>
        <p className="text-xs text-txt-secondary uppercase tracking-wider mb-2">
          Ordens Disponíveis ({repoOrders.length})
        </p>
        {repoOrders.length === 0 ? (
          <div className="bg-card/30 border border-app-border/30 rounded-lg p-4 text-center">
            <p className="text-xs text-txt-secondary">Nenhuma ordem disponível no momento</p>
            <p className="text-[10px] text-txt-muted mt-0.5">Novas ordens são geradas automaticamente</p>
          </div>
        ) : (
          <div className="space-y-2">
            {repoOrders.map(order => (
              <RepoCard key={order.id} order={order} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
