import { useAppStore } from '../../stores/useAppStore'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { useRepoStore } from '../../stores/useRepoStore'
import { useContractStore } from '../../stores/useContractStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { TabName } from '../../types'
import clsx from 'clsx'

export function TabBar() {
  const { activeTab, setTab, setOpen } = useAppStore()
  const { activeJob }                  = useJobStore()
  const { company }                    = useCompanyStore()
  const { activeRepoOrder }            = useRepoStore()
  const { clients, activeContract }  = useContractStore()

  const isRepo = company?.company_type === 'repo'

  const TABS: { id: TabName; label: string }[] = [
    { id: isRepo ? 'missions' : 'jobs', label: isRepo ? 'Missões' : 'Jobs' },
    { id: 'active',     label: 'Contratos' },
    { id: 'company',    label: 'Empresa' },
    { id: 'garage',     label: 'Garagem' },
    { id: 'industries', label: 'Indústrias' },
    { id: 'stats',      label: 'Stats' },
    { id: 'convoy',     label: 'Convoy' },
    { id: 'drivers',    label: 'Motoristas' },
    { id: 'adr',        label: 'ADR'        },
  ]

  function handleClose() {
    setOpen(false)
    fetchNUI('closeUI', {})
  }

  return (
    <div className="flex border-b border-app-border bg-card items-center">
      <div className="flex flex-1 overflow-x-auto scrollbar-hide">
        {TABS.map((tab) => {
          const disabled = (tab.id === 'active' && !activeJob && !activeContract && !company)
            || (tab.id === 'garage' && !company)
          return (
            <button
              key={tab.id}
              onClick={() => !disabled && setTab(tab.id)}
              disabled={disabled}
              className={clsx(
                'px-2.5 py-3 text-xs font-medium transition-colors whitespace-nowrap',
                activeTab === tab.id
                  ? 'text-primary border-b-2 border-primary'
                  : 'text-txt hover:text-txt-light',
                disabled && 'opacity-30 cursor-not-allowed'
              )}
            >
              {tab.label}
              {tab.id === 'active' && (activeJob || activeContract) && (
                <span className="ml-1 w-2 h-2 bg-success rounded-full inline-block" />
              )}
              {tab.id === 'active' && !activeJob && !activeContract && clients.length > 0 && (
                <span className="ml-1 w-2 h-2 bg-gold rounded-full inline-block" />
              )}
              {tab.id === 'missions' && activeRepoOrder && (
                <span className="ml-1 w-2 h-2 bg-primary-hover rounded-full inline-block" />
              )}
            </button>
          )
        })}
      </div>
      <button
        onClick={handleClose}
        className="w-9 h-9 flex items-center justify-center ml-1 mr-1 text-txt hover:text-danger hover:bg-card-alt rounded transition-colors flex-shrink-0 text-base font-bold"
        title="Fechar (ESC)"
      >
        ✕
      </button>
    </div>
  )
}
