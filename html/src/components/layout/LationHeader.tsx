import { useAppStore } from '../../stores/useAppStore'
import { useStatsStore } from '../../stores/useStatsStore'
import { useJobStore } from '../../stores/useJobStore'
import { fetchNUI } from '../../hooks/useNUI'

export function LationHeader() {
  const { setOpen, playerName, playerMoney } = useAppStore()
  const { stats } = useStatsStore()
  const { activeJob } = useJobStore()

  function handleClose() {
    setOpen(false)
    fetchNUI('closeUI', {}).catch(() => {})
    fetchNUI('close', {}).catch(() => {})
  }

  const name = stats?.name || playerName || 'Motorista'
  const initials = name
    .split(' ')
    .slice(0, 2)
    .map(p => p[0])
    .join('')
    .toUpperCase() || 'TR'

  const currentLevel = stats?.level || 1
  const currentXp = stats?.xp || 0
  const xpNeeded = currentLevel * 1000
  const xpPercent = Math.min(100, Math.floor((currentXp % 1000) / 10))
  const balance = stats?.money !== undefined ? stats.money : playerMoney

  return (
    <header className="relative flex items-center justify-between px-5 py-3 bg-lation-surface-band bg-gradient-to-r from-emerald-500/10 via-transparent to-transparent border-b border-lation-line border-l-4 border-l-lation-accent select-none">
      {/* Brand & Subtitle */}
      <div className="flex flex-col">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-lation-accent animate-pulse" />
          <h1 className="font-bold text-base text-white tracking-wider font-sans uppercase">
            Central de Logística
          </h1>
        </div>
        <p className="text-xs text-lation-accent-soft font-medium pl-4">
          Terminal de Fretes, Frotas & Operações
        </p>
      </div>

      {/* Driver Profile Bar */}
      <div className="flex items-center gap-4">
        {/* Status Badge */}
        <div className="hidden md:flex items-center gap-1.5 px-2.5 py-1 rounded bg-lation-surface-elevated border border-lation-line text-xs">
          <span
            className={`w-2 h-2 rounded-full ${
              activeJob ? 'bg-amber-400 animate-ping' : 'bg-lation-accent'
            }`}
          />
          <span className="text-lation-content-sec font-medium">
            {activeJob ? 'Em Rota de Entrega' : 'Disponível p/ Frete'}
          </span>
        </div>

        {/* Profile Details Container */}
        <div className="flex items-center gap-3 bg-lation-surface-deep border border-lation-line rounded-lg px-3 py-1.5 shadow-inner">
          {/* Avatar Icon */}
          <div className="w-9 h-9 rounded bg-lation-btn-bg border border-lation-btn-border text-lation-btn-text flex items-center justify-center font-bold text-sm tracking-wider shadow-sm">
            {initials}
          </div>

          {/* Info Rows */}
          <div className="flex flex-col min-w-[170px] gap-1">
            <div className="flex items-center justify-between gap-2">
              <span className="font-semibold text-xs text-white truncate max-w-[110px]" title={name}>
                {name}
              </span>
              <span className="chip money text-[10px] py-0.5 px-1.5">
                R$ {balance.toLocaleString('pt-BR')}
              </span>
            </div>

            {/* Level and XP progress */}
            <div className="flex items-center gap-2" title={`${currentXp % 1000} / ${xpNeeded} XP`}>
              <span className="font-mono text-[10px] text-lation-accent-bright font-bold">
                NV. {currentLevel}
              </span>
              <div className="flex-1 h-1.5 bg-lation-surface-elevated rounded-full overflow-hidden">
                <div
                  className="h-full bg-gradient-to-r from-lation-accent to-lation-accent-bright transition-all duration-300"
                  style={{ width: `${xpPercent}%` }}
                />
              </div>
              <span className="font-mono text-[9px] text-lation-content-muted">
                {stats?.reputation || 100}% Rep.
              </span>
            </div>
          </div>
        </div>

        {/* Close Button */}
        <button
          onClick={handleClose}
          className="w-8 h-8 rounded-md bg-lation-surface-elevated hover:bg-lation-err-bg text-lation-content-sec hover:text-lation-err-text border border-lation-line hover:border-lation-err-border transition-all flex items-center justify-center font-bold text-sm ml-1"
          title="Fechar Painel (ESC)"
        >
          ✕
        </button>
      </div>
    </header>
  )
}
