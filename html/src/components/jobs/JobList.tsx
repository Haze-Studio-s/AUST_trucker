import { useState } from 'react'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { JobCard } from './JobCard'
import { Modal } from '../layout/Modal'
import { fetchNUI } from '../../hooks/useNUI'

export function JobList() {
  const { jobs, selectedJobId, selectJob } = useJobStore()
  const { company } = useCompanyStore()
  const [accepting, setAccepting] = useState(false)

  const selectedJob = jobs.find(j => j.id === selectedJobId)

  async function handleAccept() {
    if (!selectedJob) return
    setAccepting(true)
    try {
      await fetchNUI('acceptJob', { jobId: selectedJob.id })
    } catch { /* Lua fecha a UI */ }
    selectJob(null)
    setAccepting(false)
  }

  if (jobs.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-64 text-lation-content-sec">
        <div className="w-12 h-12 rounded-full bg-lation-surface-elevated border border-lation-line flex items-center justify-center text-lation-accent text-lg mb-3">
          📦
        </div>
        <p className="text-base font-semibold text-white">Nenhum frete disponível no momento</p>
        <p className="text-xs text-lation-content-muted mt-1">Aguardando novos despachos pela central logística...</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Header section indicator */}
      <div className="flex items-center justify-between border-b border-lation-line pb-2.5">
        <div className="flex items-center gap-2">
          <span className="w-2.5 h-2.5 rounded bg-lation-accent" />
          <h2 className="text-xs font-bold uppercase tracking-wider text-lation-content-sec">
            Rotas e Cargas Disponíveis
          </h2>
          <span className="chip font-mono text-[10px] text-lation-accent-bright bg-lation-btn-bg border-lation-btn-border py-0.5 px-2">
            {jobs.length} fretes
          </span>
        </div>

        {!company && (
          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded bg-amber-500/10 border border-amber-500/30 text-[11px] text-amber-300">
            <span>⚠️ É recomendado vincular-se a uma empresa para bônus corporativos</span>
          </div>
        )}
      </div>

      {/* Grid of Job Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {jobs.map(job => (
          <JobCard
            key={job.id}
            job={job}
            isSelected={selectedJobId === job.id}
            onSelect={() => selectJob(job.id)}
          />
        ))}
      </div>

      {/* Selected Job Modal / Route Inspector */}
      {selectedJob && (
        <Modal title="MANIFESTO DE TRANSPORTE" onClose={() => selectJob(null)}>
          <div className="space-y-4 select-none">
            {/* Header Summary */}
            <div className="p-3.5 bg-lation-surface-band rounded-lg border border-lation-line flex items-center justify-between">
              <div>
                <span className="text-[10px] font-mono uppercase tracking-wider text-lation-accent-soft">Carga Solicitada</span>
                <h3 className="text-base font-bold text-white mt-0.5">{selectedJob.cargoItem}</h3>
              </div>
              <div className="text-right">
                <span className="text-[10px] font-mono uppercase tracking-wider text-lation-content-muted">Remuneração Base</span>
                <p className="font-mono text-lg font-bold text-lation-btn-text">
                  R$ {selectedJob.basePayment.toLocaleString('pt-BR')}
                </p>
              </div>
            </div>

            {/* Trajectory breakdown */}
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div className="bg-lation-surface-deep border border-lation-line rounded-lg p-2.5">
                <p className="text-[10px] text-lation-content-muted font-mono uppercase">Local de Coleta</p>
                <p className="font-semibold text-white mt-1">{selectedJob.originName}</p>
              </div>
              <div className="bg-lation-surface-deep border border-lation-line rounded-lg p-2.5">
                <p className="text-[10px] text-lation-content-muted font-mono uppercase">Ponto de Entrega</p>
                <p className="font-semibold text-white mt-1">{selectedJob.destName}</p>
              </div>
              <div className="bg-lation-surface-deep border border-lation-line rounded-lg p-2.5">
                <p className="text-[10px] text-lation-content-muted font-mono uppercase">Distância da Viagem</p>
                <p className="font-mono font-bold text-white mt-1">
                  {selectedJob.distance > 0 ? `${selectedJob.distance.toFixed(1)} km` : 'Especial'}
                </p>
              </div>
              <div className="bg-lation-surface-deep border border-lation-line rounded-lg p-2.5">
                <p className="text-[10px] text-lation-content-muted font-mono uppercase">Peso & Equipamento</p>
                <p className="font-mono font-bold text-white mt-1">
                  {selectedJob.weight ?? 850} kg · {selectedJob.trailerModel || 'Semirreboque'}
                </p>
              </div>
            </div>

            {/* Special Conditions / Alerts */}
            {selectedJob.adrRequired && (
              <div className="p-2.5 bg-amber-500/10 border border-amber-500/30 rounded-lg text-xs text-amber-300 flex items-center justify-between">
                <span>Certificação ADR Requerida: <b>{selectedJob.adrRequired}</b></span>
                <span className="chip text-[10px] bg-amber-500/20 text-amber-200 border-amber-500/40">Perigo</span>
              </div>
            )}

            {selectedJob.cargoQty && selectedJob.cargoQty >= 3 && (
              <div className="p-2.5 bg-lation-surface-deep border border-lation-line rounded-lg text-xs text-lation-content-sec flex items-center justify-between">
                <span>Volume fracionado: <b>{selectedJob.cargoQty} paletes</b></span>
                <span className="chip text-[10px] bg-gold/15 text-gold border-gold/30">Forklift Recomendado</span>
              </div>
            )}

            {/* Actions */}
            <div className="flex gap-2 pt-2">
              <button
                onClick={() => selectJob(null)}
                className="flex-1 py-2.5 rounded-lg text-xs font-semibold bg-lation-surface-elevated text-lation-content hover:text-white border border-lation-line hover:border-lation-line-strong transition-all"
              >
                Voltar à Lista
              </button>
              <button
                onClick={handleAccept}
                disabled={accepting}
                className="flex-[2] py-2.5 rounded-lg text-xs font-bold bg-lation-btn-bg text-white border border-lation-accent hover:border-lation-accent-bright shadow-[0_0_15px_rgba(16,185,129,0.3)] hover:shadow-[0_0_20px_rgba(16,185,129,0.5)] transition-all flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {accepting ? 'Despachando Carga...' : 'Aceitar e Iniciar Trajeto'}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
