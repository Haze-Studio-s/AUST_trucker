import clsx from 'clsx'
import type { Job } from '../../types'

interface JobCardProps {
  job: Job
  isSelected?: boolean
  onSelect: () => void
}

function getMinutesLeft(expiresAt?: number) {
  if (!expiresAt) return null
  return Math.max(0, Math.floor((expiresAt - Date.now() / 1000) / 60))
}

export function JobCard({ job, isSelected, onSelect }: JobCardProps) {
  const mins = getMinutesLeft(job.expiresAt)

  // Map trailer models to user-friendly labels
  const trailerLabel = (job.trailerModel || '').toLowerCase().includes('tank')
    ? 'Tanque Líquido'
    : (job.trailerModel || '').toLowerCase().includes('cont')
    ? 'Porta Container'
    : (job.trailerModel || '').toLowerCase().includes('arm')
    ? 'Blindado / Forte'
    : (job.trailerModel || '').toLowerCase().includes('log')
    ? 'Carreta Graneleira'
    : 'Semirreboque Padrão'

  const isUrgent = mins !== null && mins < 10
  const isCritical = mins !== null && mins < 5
  const isHazard = Boolean(job.adrRequired)

  return (
    <div
      onClick={onSelect}
      className={clsx(
        'group relative p-3.5 rounded-lg border transition-all duration-150 cursor-pointer select-none',
        isSelected
          ? 'bg-lation-surface-hover border-lation-accent shadow-[0_4px_16px_rgba(0,0,0,0.3)] bg-gradient-to-r from-emerald-500/15 via-transparent to-transparent'
          : 'bg-lation-surface-deep border-lation-line hover:border-lation-line-hover hover:bg-lation-surface-hover hover:shadow-md'
      )}
      style={{
        boxShadow: isSelected ? 'inset 3px 0 0 #6afe87, 0 4px 16px rgba(0,0,0,0.3)' : undefined,
      }}
    >
      {/* Top Header: Cargo and Payout */}
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-bold text-sm text-white group-hover:text-lation-accent-bright transition-colors">
              {job.cargoItem}
            </span>
            <span className="chip text-[10px] py-0.5 px-2 bg-lation-surface-elevated text-lation-content-sec border-lation-line-strong">
              {trailerLabel}
            </span>
            {isHazard && (
              <span className="chip text-[10px] py-0.5 px-2 bg-amber-500/15 text-amber-300 border-amber-500/30">
                ADR: {job.adrRequired}
              </span>
            )}
          </div>

          {/* Route path */}
          <div className="flex items-center gap-1.5 text-xs text-lation-content-sec mt-1.5 font-medium">
            <span className="text-white">{job.originName}</span>
            <span className="text-lation-accent-soft font-mono">→</span>
            <span className="text-white">{job.destName}</span>
          </div>
        </div>

        {/* Payout & Distance */}
        <div className="text-right flex flex-col items-end">
          <span className="font-mono font-bold text-sm text-lation-btn-text bg-lation-btn-bg px-2.5 py-0.5 rounded border border-lation-btn-border shadow-sm">
            R$ {job.basePayment.toLocaleString('pt-BR')}
          </span>
          <span className="font-mono text-xs text-lation-content-muted mt-1">
            {job.distance > 0 ? `${job.distance.toFixed(1)} km` : 'Rota Especial'}
          </span>
        </div>
      </div>

      {/* Badges and Telemetry Row */}
      <div className="flex items-center justify-between gap-2 mt-3 pt-2.5 border-t border-lation-line text-xs">
        <div className="flex items-center gap-3">
          {/* Weight */}
          <span className="font-mono text-[11px] text-lation-content-sec">
            Peso: <b className="text-white">{job.weight ?? 850} kg</b>
          </span>

          {/* Qty packages if > 1 */}
          {job.cargoQty && job.cargoQty > 1 && (
            <span className="font-mono text-[11px] text-lation-content-sec">
              Vol: <b className="text-white">{job.cargoQty} pcs</b>
            </span>
          )}

          {job.cargoQty && job.cargoQty >= 3 && (
            <span className="text-[10px] text-gold font-medium bg-gold/10 px-1.5 py-0.5 rounded border border-gold/20">
              Forklift
            </span>
          )}
        </div>

        {/* Urgency countdown badge */}
        <div>
          {mins !== null ? (
            <span
              className={clsx(
                'text-[10px] font-mono px-2 py-0.5 rounded border font-semibold',
                isCritical
                  ? 'bg-lation-err-bg text-lation-err-text border-lation-err-border animate-pulse'
                  : isUrgent
                  ? 'bg-amber-500/15 text-amber-300 border-amber-500/30'
                  : 'bg-lation-surface-elevated text-lation-content-muted border-lation-line'
              )}
            >
              {isCritical ? `Crítico: ${mins}m` : isUrgent ? `Urgente: ${mins}m` : `Expira em ${mins}m`}
            </span>
          ) : (
            <span className="text-[10px] font-mono text-lation-accent-soft">
              Frete Contratual
            </span>
          )}
        </div>
      </div>
    </div>
  )
}
