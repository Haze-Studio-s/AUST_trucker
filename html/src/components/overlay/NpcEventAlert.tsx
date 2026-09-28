import { useEffect, useState } from 'react'
import { useNpcDriverStore } from '../../stores/useNpcDriverStore'
import { fetchNUI } from '../../hooks/useNUI'

const EVENT_LABELS: Record<string, string> = {
  major_accident:    'Acidente Grave',
  cargo_stolen:      'Carga Roubada',
  contraband_caught: 'Contrabando Flagrado',
}

export function NpcEventAlert() {
  const { pendingEvent, setPendingEvent } = useNpcDriverStore()
  const [secondsLeft, setSecondsLeft]    = useState(0)
  const [loading, setLoading]            = useState(false)

  useEffect(() => {
    if (!pendingEvent) return
    const remaining = Math.max(0, pendingEvent.expiresAt - Math.floor(Date.now() / 1000))
    setSecondsLeft(remaining)
    const interval = setInterval(() => {
      setSecondsLeft((s) => {
        if (s <= 1) { clearInterval(interval); return 0 }
        return s - 1
      })
    }, 1000)
    return () => clearInterval(interval)
  }, [pendingEvent])

  if (!pendingEvent) return null

  async function respond(response: 'pay' | 'ignore') {
    if (!pendingEvent) return
    setLoading(true)
    await fetchNUI('npcRespondEvent', { eventId: pendingEvent.eventId, response })
    setPendingEvent(null)
    setLoading(false)
  }

  const mins    = Math.floor(secondsLeft / 60)
  const secs    = secondsLeft % 60
  const timeStr = `${mins}:${secs.toString().padStart(2, '0')}`

  return (
    <div className="fixed top-4 right-4 z-50 w-[340px] bg-app-bg border border-danger-dark rounded-xl shadow-2xl p-4 flex flex-col gap-3 pointer-events-auto">
      <div className="flex justify-between items-center">
        <span className="text-danger font-bold text-sm">⚠ {EVENT_LABELS[pendingEvent.type] ?? pendingEvent.type}</span>
        <span className="text-txt text-xs font-mono">{timeStr}</span>
      </div>

      <p className="text-txt text-sm">
        <span className="font-medium text-txt-light">{pendingEvent.driverName}</span>
        {pendingEvent.type === 'major_accident' && ` sofreu um acidente grave. Custo de reparo: $${pendingEvent.repairCost?.toLocaleString() ?? '?'}`}
        {pendingEvent.type === 'cargo_stolen'   && ` teve a carga roubada.`}
        {pendingEvent.type === 'contraband_caught' && ` foi flagrado com contrabando. Suborno: $${pendingEvent.bribeAmount?.toLocaleString() ?? '?'} (multa já aplicada)`}
      </p>

      <div className="flex gap-2">
        {pendingEvent.type === 'major_accident' && (
          <button
            onClick={() => respond('pay')}
            disabled={loading}
            className="flex-1 bg-primary-active hover:bg-primary text-white rounded px-3 py-2 text-sm font-medium disabled:opacity-50"
          >
            Pagar ${pendingEvent.repairCost?.toLocaleString() ?? '?'}
          </button>
        )}
        {pendingEvent.type === 'contraband_caught' && (
          <button
            onClick={() => respond('pay')}
            disabled={loading}
            className="flex-1 bg-primary-active hover:bg-primary text-white rounded px-3 py-2 text-sm font-medium disabled:opacity-50"
          >
            Pagar Suborno
          </button>
        )}
        <button
          onClick={() => respond('ignore')}
          disabled={loading}
          className="flex-1 bg-card-alt hover:bg-hover-bg text-txt-light rounded px-3 py-2 text-sm font-medium disabled:opacity-50"
        >
          Ignorar
        </button>
      </div>
    </div>
  )
}
