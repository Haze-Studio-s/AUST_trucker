import { useState } from 'react'
import { useJobStore } from '../../stores/useJobStore'
import { useContractStore } from '../../stores/useContractStore'
import type { ClientRelationship } from '../../stores/useContractStore'
import { fetchNUI } from '../../hooks/useNUI'

function TrustStars({ level }: { level: number }) {
  return (
    <span className="text-gold text-xs">
      {'★'.repeat(Math.max(0, level))}{'☆'.repeat(Math.max(0, 5 - level))}
    </span>
  )
}

function NegotiateModal({ client, onClose }: { client: ClientRelationship; onClose: () => void }) {
  const maxOpt = client.maxOptions || 1
  const volumes = [1, 3, 5, 8, 12].slice(0, maxOpt)
  const prazos = [30, 45, 60, 90, 120].slice(0, maxOpt)
  const frequencias = [1, 2, 3, 5, 7].slice(0, maxOpt)

  const [volume, setVolume] = useState(volumes[0])
  const [prazo, setPrazo] = useState(prazos[0])
  const [freq, setFreq] = useState(frequencias[0])

  const basePayment = 500
  const estimated = Math.floor(basePayment * volume * (1 + client.bonusPercent / 100)) * freq

  async function handleAccept() {
    await fetchNUI('negotiateContract', {
      clientId: client.id,
      terms: { volume, prazo, frequencia: freq }
    })
    onClose()
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 pointer-events-auto">
      <div className="bg-card rounded-lg border border-app-border w-full max-w-md mx-4">
        <div className="flex items-center justify-between px-4 py-3 border-b border-app-border">
          <h3 className="text-txt-light font-semibold text-sm">Negociar com {client.name}</h3>
          <button onClick={onClose} className="text-txt hover:text-txt-light">✕</button>
        </div>
        <div className="p-4 space-y-3">
          <div>
            <p className="text-txt text-xs mb-1">Volume por entrega</p>
            <div className="flex gap-1">
              {volumes.map(v => (
                <button key={v} onClick={() => setVolume(v)}
                  className={`px-3 py-1 rounded text-xs ${volume === v ? 'bg-primary text-white' : 'bg-card-alt text-txt'}`}
                >{v} un</button>
              ))}
            </div>
          </div>
          <div>
            <p className="text-txt text-xs mb-1">Prazo</p>
            <div className="flex gap-1">
              {prazos.map(p => (
                <button key={p} onClick={() => setPrazo(p)}
                  className={`px-3 py-1 rounded text-xs ${prazo === p ? 'bg-primary text-white' : 'bg-card-alt text-txt'}`}
                >{p}min</button>
              ))}
            </div>
          </div>
          <div>
            <p className="text-txt text-xs mb-1">Entregas no contrato</p>
            <div className="flex gap-1">
              {frequencias.map(f => (
                <button key={f} onClick={() => setFreq(f)}
                  className={`px-3 py-1 rounded text-xs ${freq === f ? 'bg-primary text-white' : 'bg-card-alt text-txt'}`}
                >{f}x</button>
              ))}
            </div>
          </div>
          <div className="bg-app-bg rounded p-3 flex justify-between items-center">
            <span className="text-txt text-sm">Pagamento estimado</span>
            <span className="text-success font-bold text-lg">${estimated.toLocaleString()}</span>
          </div>
          {client.bonusPercent > 0 && (
            <p className="text-success-dark text-xs text-center">+{client.bonusPercent}% bonus de relacionamento</p>
          )}
          <button onClick={handleAccept}
            className="w-full py-2 bg-primary hover:bg-primary-hover text-white rounded-lg font-medium transition-colors text-sm"
          >Fechar Contrato</button>
        </div>
      </div>
    </div>
  )
}

export function ActiveJob() {
  const { activeJob } = useJobStore()
  const { clients, activeContract } = useContractStore()
  const [negotiating, setNegotiating] = useState<ClientRelationship | null>(null)

  // ── Active contract view ──
  if (!activeJob && activeContract) {
    return (
      <div className="space-y-4">
        <div className="bg-card rounded-lg p-4 border border-app-border">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-txt text-xs uppercase tracking-wide">
                Contrato — {activeContract.clientName}
              </p>
              <div className="flex items-center gap-2 mt-1">
                <p className="text-txt-light font-semibold">
                  {activeContract.contractType === 'simple' ? 'Simples' : 'Multi-parada'}
                </p>
                {(activeContract as any).contractSource === 'resupply' && (
                  <span className="text-[10px] bg-primary/20 text-primary px-2 py-0.5 rounded-full font-medium">
                    📦 Ressuprimento
                  </span>
                )}
              </div>
            </div>
            <div className="text-right">
              <p className="text-success font-bold text-xl">${activeContract.totalPayment.toLocaleString()}</p>
              {activeContract.bonusPercent > 0 && (
                <p className="text-success-dark text-xs">+{activeContract.bonusPercent}% bonus</p>
              )}
            </div>
          </div>
        </div>
        <div className="space-y-2">
          <p className="text-txt text-xs uppercase tracking-wide px-1">Paradas</p>
          {activeContract.stops.map((stop, idx) => {
            const isCompleted = !!stop.completed
            const isPending = !isCompleted
            return (
              <div key={idx}
                className={`bg-card rounded-lg p-3 border ${isCompleted ? 'border-success-dark/30' : 'border-app-border'}`}>
                <div className="flex items-center gap-2">
                  <span className={`text-sm ${isCompleted ? 'text-success' : 'text-txt'}`}>
                    {isCompleted ? '✓' : `${idx + 1}.`}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className={`text-sm ${isCompleted ? 'text-txt-secondary line-through' : 'text-txt-light'}`}>
                      {stop.action === 'pickup' ? 'Coletar' : 'Entregar'}: {stop.location_name}
                    </p>
                    <p className="text-txt-secondary text-xs">{stop.cargo_item} x{stop.cargo_qty}</p>
                  </div>
                  {isPending && (
                    <button
                      onClick={() => fetchNUI('contractGPS', { stopOrder: stop.stop_order, locationId: stop.location_id })}
                      className="text-xs bg-primary/30 hover:bg-primary/50 text-primary px-2 py-1 rounded border border-primary/30 transition-colors font-medium"
                    >
                      GPS
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
        <button onClick={() => fetchNUI('abandonContract')}
          className="w-full py-2 bg-danger-dark/20 hover:bg-danger-dark/40 text-danger rounded-lg border border-danger/30 transition-colors text-sm">
          Abandonar Contrato
        </button>
      </div>
    )
  }

  // ── Client list (no active job, no active contract) ──
  if (!activeJob && !activeContract && clients.length > 0) {
    return (
      <div className="space-y-3">
        {negotiating && <NegotiateModal client={negotiating} onClose={() => setNegotiating(null)} />}
        <div className="px-1">
          <p className="text-txt text-sm font-medium">Clientes Disponíveis</p>
          <p className="text-txt-secondary text-xs mt-0.5">Negocie contratos de entrega com clientes</p>
        </div>
        {clients.map(client => (
          <div key={client.id} className={`bg-card rounded-lg p-3 border ${client.locked ? 'border-app-border opacity-50' : 'border-app-border'}`}>
            <div className="flex justify-between items-start">
              <div>
                <p className="text-txt-light text-sm font-medium">{client.name}</p>
                <div className="flex items-center gap-2 mt-0.5">
                  <TrustStars level={client.trustLevel} />
                  <span className="text-txt-secondary text-xs">{client.trustLabel}</span>
                </div>
              </div>
              <div className="text-right">
                <span className="text-txt-secondary text-xs">{client.sectorLabel}</span>
                {client.bonusPercent > 0 && (
                  <p className="text-success-dark text-xs">+{client.bonusPercent}%</p>
                )}
              </div>
            </div>
            <div className="flex items-center gap-3 mt-2 text-xs text-txt-secondary">
              <span>{client.totalDeliveries} entregas</span>
              {client.streak > 0 && <span className="text-warning">Streak: {client.streak}</span>}
              <span>${client.totalRevenue.toLocaleString()} total</span>
            </div>
            {client.locked ? (
              <p className="text-txt-secondary text-xs mt-2 italic">Reputação no setor {client.sectorLabel} insuficiente</p>
            ) : (
              <button onClick={() => setNegotiating(client)}
                className="mt-2 w-full py-1.5 bg-primary/20 hover:bg-primary/40 text-primary rounded border border-primary/30 transition-colors text-xs">
                Negociar Contrato
              </button>
            )}
          </div>
        ))}
      </div>
    )
  }

  // ── No active job ──
  if (!activeJob) {
    return (
      <div className="flex items-center justify-center h-full text-txt-secondary">
        <p>Nenhuma entrega ativa</p>
      </div>
    )
  }

  // ── Active job view (original) ──
  const elapsed = Math.floor(Date.now() / 1000 - activeJob.acceptedAt)
  const elapsedMin = Math.floor(elapsed / 60)
  const elapsedSec = elapsed % 60
  // UI-H01: thresholds alinhados ao config (fast=600s/+20%, normal=1200s/sem bônus, sem penalidade)
  const timeBonusLabel = elapsed <= 600 ? '+20% bônus' : 'Sem bônus'
  const timeBonusColor = elapsed <= 600 ? 'text-success' : 'text-txt'

  return (
    <div className="space-y-4">
      <div className="bg-card rounded-lg p-4 border border-app-border">
        <div className="flex justify-between items-start">
          <div>
            <p className="text-txt text-xs uppercase tracking-wide">
              {activeJob.stage === 'pickup' ? 'Ir buscar carga' : 'Entregar'}
            </p>
            <p className="text-txt-light font-semibold mt-1">{activeJob.cargoItem}</p>
          </div>
          <div className="text-right">
            <p className="text-success font-bold text-xl">${activeJob.basePayment.toLocaleString()}</p>
            <p className={`text-xs ${timeBonusColor}`}>{timeBonusLabel}</p>
          </div>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-card rounded-lg p-3 border border-app-border">
          <p className="text-txt text-xs">Origem</p>
          <p className="text-txt-light text-sm mt-0.5">{activeJob.originName}</p>
        </div>
        <div className="bg-card rounded-lg p-3 border border-app-border">
          <p className="text-txt text-xs">Destino</p>
          <p className="text-txt-light text-sm mt-0.5">{activeJob.destName}</p>
        </div>
        <div className="bg-card rounded-lg p-3 border border-app-border">
          <p className="text-txt text-xs">Distância</p>
          <p className="text-txt-light text-sm mt-0.5">{activeJob.distance.toFixed(1)} km</p>
        </div>
        <div className="bg-card rounded-lg p-3 border border-app-border">
          <p className="text-txt text-xs">Tempo decorrido</p>
          <p className="text-txt-light text-sm mt-0.5">{elapsedMin}m {elapsedSec}s</p>
        </div>
      </div>
      <button onClick={() => fetchNUI('abandonJob')}
        className="w-full py-2 bg-danger-dark/20 hover:bg-danger-dark/40 text-danger rounded-lg border border-danger/30 transition-colors text-sm">
        Abandonar Job
      </button>
    </div>
  )
}
