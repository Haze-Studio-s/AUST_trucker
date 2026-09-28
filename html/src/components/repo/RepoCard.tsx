import type { RepoOrder, RepoMissionType } from '../../types/repo'
import { fetchNUI } from '../../hooks/useNUI'

interface RepoCardProps {
  order: RepoOrder
}

const MISSION_BADGE: Record<RepoMissionType, { label: string; className: string }> = {
  simple:      { label: 'SIMPLES',  className: 'bg-card-alt text-txt' },
  npc_hostile: { label: 'HOSTIL',   className: 'bg-orange-900/40 text-orange-400' },
  pvp:         { label: 'PVP',      className: 'bg-danger-dark/20 text-danger' },
  stealth:     { label: 'STEALTH',  className: 'bg-purple-900/40 text-purple-400' },
}

function formatCountdown(unixTs: number): string {
  const diff = unixTs - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'EXPIRADO'
  const hours = Math.floor(diff / 3600)
  const mins  = Math.floor((diff % 3600) / 60)
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export function RepoCard({ order }: RepoCardProps) {
  const badge = MISSION_BADGE[order.mission_type] ?? { label: order.mission_type.toUpperCase(), className: 'bg-card-alt text-txt' }

  async function handleAccept() {
    await fetchNUI('acceptRepoOrder', { orderId: order.id })
  }

  return (
    <div className="bg-card/60 border border-app-border/50 rounded-lg p-3">
      <div className="flex items-center justify-between mb-2">
        <span className={`text-xs px-2 py-0.5 rounded font-medium ${badge.className}`}>
          {badge.label}
        </span>
        <span className="text-xs text-txt-secondary">{formatCountdown(order.expires_at_unix)}</span>
      </div>

      <div className="grid grid-cols-3 gap-2 text-center mb-3">
        <div>
          <p className="text-sm font-bold text-txt-light uppercase">{order.vehicle_model}</p>
          <p className="text-[10px] text-txt-secondary">Veículo</p>
        </div>
        <div>
          <p className="text-sm font-bold text-txt">{order.location_zone}</p>
          <p className="text-[10px] text-txt-secondary">Zona</p>
        </div>
        <div>
          <p className="text-sm font-bold text-success">${order.payment.toLocaleString()}</p>
          <p className="text-[10px] text-txt-secondary">Pagamento</p>
        </div>
      </div>

      <button
        onClick={handleAccept}
        className="w-full py-1.5 bg-primary hover:bg-primary-hover text-white rounded text-sm font-medium transition-colors"
      >
        Aceitar Missão
      </button>
    </div>
  )
}
