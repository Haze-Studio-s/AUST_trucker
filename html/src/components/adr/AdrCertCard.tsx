import { fetchNUI } from '../../hooks/useNUI'
import { useAdrStore } from '../../stores/useAdrStore'
import type { AdrCert } from '../../types'

interface Props {
  adrType: string
  label:   string
  cert:    AdrCert | undefined  // undefined = not owned
}

const TYPE_ICON: Record<string, string> = {
  flammable_liquid: 'fas fa-fire',
  flammable_gas:    'fas fa-wind',
  toxic:            'fas fa-skull-crossbones',
  corrosive:        'fas fa-flask',
  explosive:        'fas fa-bomb',
  environmental:    'fas fa-leaf',
}

const TYPE_COLOR: Record<string, string> = {
  flammable_liquid: 'text-orange-400',
  flammable_gas:    'text-gold',
  toxic:            'text-success',
  corrosive:        'text-purple-400',
  explosive:        'text-danger',
  environmental:    'text-success-dark',
}

function formatDate(unix: number): string {
  return new Date(unix * 1000).toLocaleDateString('pt-BR')
}

export function AdrCertCard({ adrType, label, cert }: Props) {
  const { upsertCert } = useAdrStore()

  const now        = Math.floor(Date.now() / 1000)
  const isValid    = cert !== undefined && cert.expires_at > now
  const isExpired  = cert !== undefined && cert.expires_at <= now
  const isAvailable = cert === undefined

  const icon  = TYPE_ICON[adrType]  ?? 'fas fa-certificate'
  const color = TYPE_COLOR[adrType] ?? 'text-txt'

  async function handleGps() {
    await fetchNUI('setAdrGps', { adrType })
  }

  async function handleRenew() {
    const r = await fetchNUI<{ success: boolean; reason?: string; expiresAt?: number }>('renewAdrCert', { adrType })
    if (r.success && r.expiresAt) {
      upsertCert({ adr_type: adrType, expires_at: r.expiresAt, label })
    } else if (!r.success) {
      alert(r.reason ?? 'Erro ao renovar certificação')
    }
  }

  return (
    <div className="bg-card rounded-lg p-3 flex flex-col gap-2 border border-app-border">
      {/* Header */}
      <div className="flex items-center gap-2">
        <i className={`${icon} ${color} text-base w-5 text-center`} />
        <span className="text-txt-light text-sm font-medium flex-1">{label}</span>
        {isValid    && <span className="text-xs font-bold text-success bg-success-dark/30 px-2 py-0.5 rounded">Válida</span>}
        {isExpired  && <span className="text-xs font-bold text-gold bg-warning/30 px-2 py-0.5 rounded">Expirada</span>}
        {isAvailable && <span className="text-xs font-bold text-txt bg-card-alt px-2 py-0.5 rounded">Disponível</span>}
      </div>

      {/* Expiry info */}
      {cert && (
        <p className="text-xs text-txt">
          {isValid ? 'Válida até' : 'Expirou em'}: {formatDate(cert.expires_at)}
        </p>
      )}

      {/* Actions */}
      <div className="flex gap-2 mt-1">
        {isAvailable && (
          <button
            onClick={handleGps}
            className="flex-1 bg-primary-active hover:bg-primary-active text-primary-light rounded px-2 py-1 text-xs"
          >
            <i className="fas fa-map-marker-alt mr-1" />
            Obter Certificação
          </button>
        )}
        {isExpired && (
          <button
            onClick={handleRenew}
            className="flex-1 bg-warning/80 hover:bg-warning/60 text-gold rounded px-2 py-1 text-xs"
          >
            <i className="fas fa-rotate mr-1" />
            Renovar
          </button>
        )}
        {isValid && (
          <button
            onClick={handleRenew}
            className="flex-1 bg-card-alt hover:bg-hover-bg text-txt rounded px-2 py-1 text-xs"
          >
            <i className="fas fa-rotate mr-1" />
            Renovar antecipado
          </button>
        )}
      </div>
    </div>
  )
}
