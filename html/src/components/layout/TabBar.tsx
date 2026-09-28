import { useAppStore } from '../../stores/useAppStore'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { useRepoStore } from '../../stores/useRepoStore'
import { useContractStore } from '../../stores/useContractStore'
import type { TabName } from '../../types'
import clsx from 'clsx'

export function TabBar() {
  const { activeTab, setTab }         = useAppStore()
  const { activeJob }                  = useJobStore()
  const { company }                    = useCompanyStore()
  const { activeRepoOrder }            = useRepoStore()
  const { clients, activeContract }  = useContractStore()

  const isRepo = company?.company_type === 'repo'

  const TABS: { id: TabName; label: string; icon?: string }[] = [
    { id: isRepo ? 'missions' : 'jobs', label: isRepo ? 'Missões Guincho' : 'Fretes Disponíveis' },
    { id: 'garage',     label: 'Frota & Aluguel' },
    { id: 'active',     label: 'Viagem Ativa' },
    { id: 'company',    label: 'Empresa' },
    { id: 'industries', label: 'Indústrias' },
    { id: 'stats',      label: 'Progresso & Skills' },
    { id: 'convoy',     label: 'Comboio' },
    { id: 'drivers',    label: 'Motoristas' },
    { id: 'adr',        label: 'ADR' },
  ]

  return (
    <div className="bg-lation-surface-deep px-3 py-2 border-b border-lation-line">
      <nav className="flex items-center gap-1.5 overflow-x-auto scrollbar-hide">
        {TABS.map((tab) => {
          const disabled = tab.id === 'active' && !activeJob && !activeContract && !company
          const isActive = activeTab === tab.id

          return (
            <button
              key={tab.id}
              onClick={() => !disabled && setTab(tab.id)}
              disabled={disabled}
              className={clsx(
                'px-3.5 py-1.5 rounded-md text-xs font-semibold tracking-wide transition-all whitespace-nowrap flex items-center gap-2 border select-none',
                isActive
                  ? 'bg-lation-btn-bg text-lation-btn-text border-lation-btn-border shadow-[0_0_12px_rgba(16,185,129,0.2)]'
                  : 'bg-transparent text-lation-content-sec border-transparent hover:text-white hover:bg-lation-surface-hover hover:border-lation-line',
                disabled && 'opacity-30 cursor-not-allowed hover:bg-transparent hover:text-lation-content-sec'
              )}
            >
              <span>{tab.label}</span>

              {tab.id === 'active' && (activeJob || activeContract) && (
                <span className="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
              )}
              {tab.id === 'active' && !activeJob && !activeContract && clients.length > 0 && (
                <span className="w-2 h-2 rounded-full bg-gold" />
              )}
              {tab.id === 'missions' && activeRepoOrder && (
                <span className="w-2 h-2 rounded-full bg-lation-accent-bright animate-ping" />
              )}
            </button>
          )
        })}
      </nav>
    </div>
  )
}
