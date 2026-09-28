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
      <div className="flex flex-col items-center justify-center h-full text-txt-secondary">
        <p className="text-lg">Nenhum job disponível</p>
        <p className="text-sm mt-1">Aguarde o próximo ciclo de geração</p>
      </div>
    )
  }

  return (
    <>
      <div className="space-y-2">
        {!company && (
          <p className="text-warning text-sm bg-warning/10 rounded-lg p-2 border border-warning/30">
            Entre em uma empresa para aceitar jobs
          </p>
        )}
        {jobs.map(job => (
          <JobCard key={job.id} job={job} onSelect={() => selectJob(job.id)} />
        ))}
      </div>

      {selectedJob && (
        <Modal title="Detalhes do Job" onClose={() => selectJob(null)}>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div className="bg-app-bg rounded p-2">
                <p className="text-txt text-xs">Carga</p>
                <p className="text-txt-light">{selectedJob.cargoItem}</p>
              </div>
              <div className="bg-app-bg rounded p-2">
                <p className="text-txt text-xs">Pagamento</p>
                <p className="text-success font-semibold">${selectedJob.basePayment.toLocaleString()}</p>
              </div>
              <div className="bg-app-bg rounded p-2">
                <p className="text-txt text-xs">Origem</p>
                <p className="text-txt-light">{selectedJob.originName}</p>
              </div>
              <div className="bg-app-bg rounded p-2">
                <p className="text-txt text-xs">Destino</p>
                <p className="text-txt-light">{selectedJob.destName}</p>
              </div>
              <div className="bg-app-bg rounded p-2">
                <p className="text-txt text-xs">Distância</p>
                <p className="text-txt-light">{selectedJob.distance.toFixed(1)} km</p>
              </div>
              <div className="bg-app-bg rounded p-2">
                <p className="text-txt text-xs">Peso da Carga</p>
                <p className={(selectedJob.weight ?? 80) > 120 ? 'text-warning font-medium' : 'text-txt-light'}>
                  {selectedJob.weight ?? 80}kg
                </p>
              </div>
            </div>
            {selectedJob?.cargoQty && selectedJob.cargoQty > 1 && (
              <div className="flex items-center justify-between">
                <span className="text-txt text-sm">Pacotes</span>
                <div className="flex items-center gap-2">
                  <span className="text-txt-light text-sm font-medium">{selectedJob.cargoQty}</span>
                  {selectedJob.cargoQty >= 3 && (
                    <span className="bg-warning/20 text-gold px-1.5 py-0.5 rounded text-xs font-medium">
                      Forklift recomendado
                    </span>
                  )}
                </div>
              </div>
            )}
            <button
              onClick={handleAccept}
              disabled={!company || accepting}
              className="w-full py-2 bg-primary hover:bg-primary-hover disabled:opacity-40 disabled:cursor-not-allowed text-white rounded-lg font-medium transition-colors"
            >
              {accepting ? 'Aceitando...' : 'Aceitar Job'}
            </button>
          </div>
        </Modal>
      )}
    </>
  )
}
