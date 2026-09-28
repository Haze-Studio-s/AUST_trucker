import { useState, useEffect } from 'react'
import { fetchNUI } from '../../hooks/useNUI'
import type { AgencyDriver, HiredDriver, FleetTruck } from '../../types'

export function NpcDriverPanel() {
  const [subTab, setSubTab] = useState<'hired' | 'agency'>('hired')
  const [agencyDrivers, setAgencyDrivers] = useState<AgencyDriver[]>([])
  const [hiredDrivers, setHiredDrivers] = useState<HiredDriver[]>([])
  const [fleetTrucks, setFleetTrucks] = useState<FleetTruck[]>([])
  const [actionId, setActionId] = useState<number | null>(null)

  const loadData = async () => {
    try {
      const res = await fetchNUI<any>('getInitialData', {})
      if (res) {
        if (res.agencyDrivers) setAgencyDrivers(res.agencyDrivers)
        if (res.hiredDrivers) setHiredDrivers(res.hiredDrivers)
        if (res.fleetTrucks) setFleetTrucks(res.fleetTrucks)
      }
    } catch {}
  }

  useEffect(() => {
    loadData()
  }, [])

  async function handleHire(driverIndex: number) {
    setActionId(driverIndex)
    try {
      const res = await fetchNUI<{ ok: boolean; reason?: string }>('hireAgencyDriver', { driverIndex })
      if (res && res.ok) {
        loadData()
        setSubTab('hired')
      }
    } catch {}
    setActionId(null)
  }

  async function handleAssignTruck(driverId: number, truckId: number) {
    try {
      const res = await fetchNUI<{ ok: boolean }>('assignDriverTruck', { driverId, truckId })
      if (res && res.ok) {
        loadData()
      }
    } catch {}
  }

  async function handleFire(driverId: number) {
    setActionId(driverId)
    try {
      const res = await fetchNUI<{ ok: boolean }>('fireAgencyDriver', { driverId })
      if (res && res.ok) {
        loadData()
      }
    } catch {}
    setActionId(null)
  }

  return (
    <div className="space-y-4 select-none">
      {/* Sub-Abas de Navegação */}
      <div className="flex items-center justify-between border-b border-lation-line pb-2">
        <div className="flex items-center gap-2">
          <button
            onClick={() => setSubTab('hired')}
            className={`px-3 py-1.5 rounded-md text-xs font-bold transition-all ${
              subTab === 'hired'
                ? 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border shadow-sm'
                : 'bg-lation-surface-deep text-lation-content-sec border border-lation-line hover:text-white'
            }`}
          >
            👥 Motoristas Contratados ({hiredDrivers.length})
          </button>
          <button
            onClick={() => setSubTab('agency')}
            className={`px-3 py-1.5 rounded-md text-xs font-bold transition-all ${
              subTab === 'agency'
                ? 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border shadow-sm'
                : 'bg-lation-surface-deep text-lation-content-sec border border-lation-line hover:text-white'
            }`}
          >
            🏢 Agência de Recrutamento
          </button>
        </div>
      </div>

      {/* ABA 1: MOTORISTAS DA MINHA FROTA */}
      {subTab === 'hired' && (
        <div className="space-y-3">
          {hiredDrivers.length === 0 ? (
            <div className="p-8 text-center bg-lation-surface-deep border border-lation-line rounded-lg">
              <span className="text-3xl mb-2 block">👤</span>
              <h4 className="text-sm font-bold text-white">Nenhum motorista contratado na sua frota</h4>
              <p className="text-xs text-lation-content-muted mt-1">
                Visite a Agência de Recrutamento para contratar motoristas e atribuí-los aos seus caminhões.
              </p>
              <button
                onClick={() => setSubTab('agency')}
                className="mt-4 px-4 py-2 rounded bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border text-xs font-bold hover:brightness-110"
              >
                Abrir Agência de Recrutamento
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {hiredDrivers.map((d) => {
                const assignedTruck = fleetTrucks.find((t) => t.truck_id === d.truck_id)

                return (
                  <div key={d.driver_id} className="p-4 bg-lation-surface-band border border-lation-line rounded-lg space-y-3">
                    <div className="flex items-center justify-between border-b border-lation-line/60 pb-2">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-lation-surface-deep border border-lation-line flex items-center justify-center font-bold text-base text-lation-accent-bright">
                          👤
                        </div>
                        <div>
                          <h4 className="text-sm font-bold text-white">{d.name}</h4>
                          <span className="text-[10px] font-mono text-lation-accent-bright font-semibold">
                            ID: #{d.driver_id}
                          </span>
                        </div>
                      </div>
                      <span className={`text-xs font-mono font-bold px-2 py-0.5 rounded border ${
                        assignedTruck
                          ? 'text-emerald-400 bg-emerald-500/10 border-emerald-500/30'
                          : 'text-amber-400 bg-amber-500/10 border-amber-500/30'
                      }`}>
                        {assignedTruck ? assignedTruck.truck_name.toUpperCase() : 'Sem Caminhão'}
                      </span>
                    </div>

                    {/* Competências */}
                    <div className="grid grid-cols-4 gap-1.5 text-center text-[10px]">
                      <div className="p-1.5 bg-lation-surface-deep border border-lation-line rounded">
                        <span className="text-lation-content-muted block">Distância</span>
                        <span className="font-bold text-white font-mono">Nv {d.distance_skill}</span>
                      </div>
                      <div className="p-1.5 bg-lation-surface-deep border border-lation-line rounded">
                        <span className="text-lation-content-muted block">Valioso</span>
                        <span className="font-bold text-white font-mono">Nv {d.valuable_skill}</span>
                      </div>
                      <div className="p-1.5 bg-lation-surface-deep border border-lation-line rounded">
                        <span className="text-lation-content-muted block">Frágil</span>
                        <span className="font-bold text-white font-mono">Nv {d.fragile_skill}</span>
                      </div>
                      <div className="p-1.5 bg-lation-surface-deep border border-lation-line rounded">
                        <span className="text-lation-content-muted block">Urgente</span>
                        <span className="font-bold text-white font-mono">Nv {d.fast_skill}</span>
                      </div>
                    </div>

                    {/* Atribuição de Caminhão */}
                    <div className="space-y-1">
                      <label className="text-[10px] text-lation-content-muted uppercase font-mono">
                        Caminhão Atribuído
                      </label>
                      <select
                        value={d.truck_id || 0}
                        onChange={(e) => handleAssignTruck(d.driver_id, Number(e.target.value))}
                        className="w-full bg-lation-surface-deep border border-lation-line rounded px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-lation-accent"
                      >
                        <option value={0}>Nenhum caminhão alocado (Inativo)</option>
                        {fleetTrucks.map((t) => (
                          <option key={t.truck_id} value={t.truck_id}>
                            #{t.truck_id} - {t.truck_name.toUpperCase()} (Combustível: {t.fuel}%)
                          </option>
                        ))}
                      </select>
                    </div>

                    {/* Ação de Demissão */}
                    <div className="flex justify-end pt-1">
                      <button
                        onClick={() => handleFire(d.driver_id)}
                        disabled={actionId === d.driver_id}
                        className="px-3 py-1 bg-rose-500/10 text-rose-400 border border-rose-500/30 rounded text-xs font-bold hover:bg-rose-500/20"
                      >
                        Demitir Motorista
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}

      {/* ABA 2: AGÊNCIA DE RECRUTAMENTO */}
      {subTab === 'agency' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
          {agencyDrivers.map((driver) => {
            const isLoading = actionId === driver.id

            return (
              <div
                key={driver.id}
                className="p-4 bg-lation-surface-band border border-lation-line hover:border-lation-line-focus rounded-lg flex flex-col justify-between space-y-3 transition-all"
              >
                <div>
                  <div className="flex items-center gap-3 mb-2">
                    <div className="w-10 h-10 rounded-full bg-lation-surface-deep border border-lation-line flex items-center justify-center font-bold text-base text-lation-accent-bright">
                      👤
                    </div>
                    <div>
                      <h4 className="text-xs font-bold text-white leading-tight">{driver.name}</h4>
                      <span className="text-[10px] font-mono text-emerald-400 font-bold">
                        R$ {driver.price.toLocaleString('pt-BR')}
                      </span>
                    </div>
                  </div>

                  <div className="space-y-1 text-[11px] text-lation-content-muted">
                    <p>• Distância: <span className="text-white font-mono font-bold">Nível {driver.distance_skill}</span></p>
                    <p>• Carga Valiosa: <span className="text-white font-mono font-bold">Nível {driver.valuable_skill}</span></p>
                    <p>• Carga Frágil: <span className="text-white font-mono font-bold">Nível {driver.fragile_skill}</span></p>
                    <p>• Entrega Urgente: <span className="text-white font-mono font-bold">Nível {driver.fast_skill}</span></p>
                    <p>• ADR: <span className="text-white font-mono font-bold">Classe {driver.product_type}</span></p>
                  </div>
                </div>

                <button
                  onClick={() => handleHire(driver.id)}
                  disabled={isLoading}
                  className="w-full py-1.5 bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border rounded text-xs font-bold hover:brightness-110 tracking-wide"
                >
                  {isLoading ? 'Contratando...' : 'Contratar'}
                </button>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
