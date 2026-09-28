import clsx from 'clsx'
import type { Job } from '../../types'

interface JobCardProps {
  job: Job
  onSelect: () => void
}

function getMinutesLeft(expiresAt: number) {
  return Math.max(0, Math.floor((expiresAt - Date.now() / 1000) / 60))
}

export function JobCard({ job, onSelect }: JobCardProps) {
  const mins = getMinutesLeft(job.expiresAt)

  return (
    <div
      onClick={onSelect}
      className={clsx(
        'p-3 rounded-lg border cursor-pointer transition-all hover:bg-card-alt',
        mins < 5
          ? 'border-danger bg-danger/10'
          : mins < 15
          ? 'border-warning bg-warning/10'
          : 'border-app-border bg-card'
      )}
    >
      <div className="flex justify-between items-start">
        <div>
          <p className="text-txt-light font-medium text-sm">{job.cargoItem}</p>
          <p className="text-txt text-xs mt-0.5">{job.originName} → {job.destName}</p>
        </div>
        <div className="text-right">
          <p className="text-success font-semibold text-sm">${job.basePayment.toLocaleString()}</p>
          <p className="text-txt text-xs">{job.distance.toFixed(1)} km</p>
        </div>
      </div>
      {job.cargoQty && job.cargoQty > 1 && (
        <div className="flex items-center gap-1 text-xs text-txt mt-1.5">
          <i className="fas fa-boxes" />
          <span>{job.cargoQty} pacotes</span>
          {job.cargoQty >= 3 && (
            <span className="ml-1 bg-warning/20 text-gold px-1.5 py-0.5 rounded text-xs font-medium">
              Forklift rec.
            </span>
          )}
        </div>
      )}
      <div className="flex justify-between mt-2">
        <span className={clsx('text-xs', (job.weight ?? 80) > 120 ? 'text-warning' : 'text-txt-secondary')}>
          {job.weight ?? 80}kg
        </span>
        <span className={clsx('text-xs', mins < 5 ? 'text-danger' : mins < 15 ? 'text-warning' : 'text-txt-secondary')}>
          {mins}min restantes
        </span>
      </div>
    </div>
  )
}
