import { useAppStore } from '../../stores/useAppStore'
import { useJobStore } from '../../stores/useJobStore'
import { fetchNUI } from '../../hooks/useNUI'

export function FooterActions() {
  const { setOpen, activeTab, setTab } = useAppStore()
  const { activeJob, selectedJobId, jobs, selectJob } = useJobStore()

  const selectedJob = jobs.find(j => j.id === selectedJobId)

  function handleClose() {
    setOpen(false)
    fetchNUI('closeUI', {}).catch(() => {})
    fetchNUI('close', {}).catch(() => {})
  }

  async function handleAcceptJob() {
    if (!selectedJob) return
    try {
      await fetchNUI('acceptJob', { jobId: selectedJob.id })
    } catch { /* Lua fecha a UI */ }
    selectJob(null)
  }

  async function handleAbandonJob() {
    try {
      await fetchNUI('abandonJob', {})
    } catch { /* Lua trata */ }
  }

  return (
    <footer className="flex items-center justify-between px-5 py-2.5 bg-lation-surface-band border-t border-lation-line select-none">
      {/* Left Hint & Telemetry */}
      <div className="flex items-center gap-4 text-xs">
        <span className="text-lation-content-muted">
          Pressione <b className="text-lation-content-sec font-mono">ESC</b> para fechar
        </span>
        <div className="hidden sm:flex items-center gap-2 pl-3 border-l border-lation-line text-[11px] text-lation-accent-soft font-mono">
          <span className="w-1.5 h-1.5 rounded-full bg-lation-accent animate-pulse" />
          <span>SISTEMA CONECTADO · GPS ATIVO</span>
        </div>
      </div>

      {/* Right Action Buttons */}
      <div className="flex items-center gap-2.5">
        {activeJob && (
          <>
            {activeTab !== 'active' && (
              <button
                onClick={() => setTab('active')}
                className="px-3 py-1.5 rounded text-xs font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/40 hover:bg-amber-500/30 transition-all flex items-center gap-1.5"
              >
                <span>Ver Viagem Ativa</span>
              </button>
            )}
            <button
              onClick={handleAbandonJob}
              className="px-3 py-1.5 rounded text-xs font-semibold bg-lation-err-bg text-lation-err-text border border-lation-err-border hover:bg-red-950/60 transition-all"
            >
              Cancelar Contrato
            </button>
          </>
        )}

        {activeTab === 'jobs' && selectedJob && (
          <button
            onClick={handleAcceptJob}
            className="px-4 py-1.5 rounded text-xs font-bold bg-lation-btn-bg text-lation-btn-text border border-lation-accent hover:border-lation-accent-bright shadow-[0_0_15px_rgba(16,185,129,0.3)] hover:shadow-[0_0_20px_rgba(16,185,129,0.5)] transition-all flex items-center gap-1.5"
          >
            <span>Iniciar Trajeto</span>
          </button>
        )}

        <button
          onClick={handleClose}
          className="px-3 py-1.5 rounded text-xs font-medium bg-lation-surface-elevated text-lation-content hover:text-white border border-lation-line-strong hover:border-lation-accent transition-all"
        >
          Fechar
        </button>
      </div>
    </footer>
  )
}
