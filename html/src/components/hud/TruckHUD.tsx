import { useHUDStore } from '../../stores/useHUDStore'

const positionClasses: Record<string, string> = {
  'bottom-left':  'bottom-6 left-6',
  'bottom-right': 'bottom-6 right-6',
  'top-left':     'top-6 left-6',
  'top-right':    'top-6 right-6',
}

function Bar({ value, low, high, icon }: {
  value:  number
  low?:   number
  high?:  number
  icon:   string
}) {
  const pct   = Math.max(0, Math.min(100, value))
  const color = high !== undefined && pct >= high
    ? 'bg-danger'
    : low !== undefined && pct <= low
    ? 'bg-gold'
    : 'bg-success'

  return (
    <div className="flex items-center gap-2 text-white text-xs">
      <span className="w-4 text-center">{icon}</span>
      <div className="w-24 h-2 bg-white/20 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${color}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="w-8 text-right tabular-nums">{Math.floor(pct)}%</span>
    </div>
  )
}

export function TruckHUD() {
  const { hud } = useHUDStore()

  if (!hud.visible) return null

  const pos = positionClasses[hud.position ?? 'bottom-left'] ?? positionClasses['bottom-left']

  return (
    <div
      className={`fixed ${pos} pointer-events-none select-none`}
      style={{ zIndex: 9998 }}
    >
      <div className="bg-black/60 backdrop-blur-sm rounded-xl px-3 py-2 flex flex-col gap-1.5 min-w-[180px]">
        {/* Velocidade */}
        <div className="flex items-center gap-2 text-white text-sm font-semibold">
          <span>🚛</span>
          <span className="tabular-nums">{hud.speed} km/h</span>
        </div>

        {/* Combustível */}
        <Bar
          value={hud.fuel}
          low={20}
          icon="⛽"
        />

        {/* Fadiga */}
        <Bar
          value={hud.fatigue}
          high={90}
          icon="😴"
        />

        {/* Integridade da carga (só com job ativo) */}
        {hud.integrity !== null && (
          <>
            <div className="border-t border-white/20 my-0.5" />
            <Bar
              value={hud.integrity}
              low={50}
              icon="📦"
            />
          </>
        )}
      </div>
    </div>
  )
}
