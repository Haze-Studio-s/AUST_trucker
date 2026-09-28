import { useEffect, useState } from 'react'
import { useAppStore } from '../../stores/useAppStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { RentalTruck, FleetTruck, DealershipTruck } from '../../types'

const DEFAULT_DEALERSHIP: Record<string, DealershipTruck> = {
  vetirs: { name: 'Vetir Semi', price: 25000, engine: '10.0L Vetir I6', transmission: '5-Speed', hp: '380', img: 'img/trucks/vetirs.png', driver_bonus: 1, required_level: 0 },
  blacktop: { name: 'Brute Blacktop', price: 45000, engine: '11.0L Brute I6', transmission: '6-Speed', hp: '420', img: 'img/trucks/blacktop.png', driver_bonus: 2, required_level: 4 },
  brickades: { name: 'MTL Brickade', price: 60000, engine: '12.5L Turbocharged V8', transmission: '8-Speed', hp: '480', img: 'img/trucks/brickades.png', driver_bonus: 4, required_level: 10 },
  hauler: { name: 'JoBuilt Hauler', price: 70000, engine: '12.0L Turbocharged V8', transmission: '8-Speed', hp: '500', img: 'img/trucks/hauler.png', driver_bonus: 4, required_level: 12 },
  aerocab: { name: 'Vapid Tanker', price: 90000, engine: '12.5L Turbocharged V8', transmission: '8-Speed', hp: '565', img: 'img/trucks/aerocab.png', driver_bonus: 6, required_level: 16 },
  linerunner: { name: 'HVY Linerunner', price: 105000, engine: '14.0L Supercharged V10', transmission: '10-Speed', hp: '580', img: 'img/trucks/linerunner.png', driver_bonus: 6, required_level: 18 },
  packer: { name: 'MTL Packer', price: 110000, engine: '13.0L Supercharged V8', transmission: '8-Speed', hp: '570', img: 'img/trucks/packer.png', driver_bonus: 6, required_level: 20 },
  phantom: { name: 'JoBuilt Phantom', price: 130000, engine: '15.0L Turbocharged V12', transmission: '10-Speed', hp: '600', img: 'img/trucks/phantom.png', driver_bonus: 8, required_level: 24 },
  phantom3: { name: 'JoBuilt Phantom Custom', price: 180000, engine: '16.5L Twin-Turbo V16', transmission: '12-Speed Plus', hp: '650', img: 'img/trucks/phantom3.png', driver_bonus: 10, required_level: 30 }
}

const DEFAULT_RENTAL_TRUCKS: RentalTruck[] = [
  { model: 'hauler', label: 'Hauler Comercial', fee: 300, deposit: 1500, capacity: '18.000 kg' },
  { model: 'phantom', label: 'Phantom Clássico', fee: 300, deposit: 1500, capacity: '22.000 kg' },
  { model: 'packer', label: 'Packer Pesado', fee: 400, deposit: 2000, capacity: '28.000 kg' },
]

export function GaragePanel() {
  const { rentalTrucks, activeRental, setActiveRental } = useAppStore()
  const [subTab, setSubTab] = useState<'fleet' | 'dealership' | 'rental'>('fleet')
  const [fleetTrucks, setFleetTrucks] = useState<FleetTruck[]>([])
  const [actionLoading, setActionLoading] = useState<number | null>(null)

  const availableRentals = rentalTrucks.length > 0 ? rentalTrucks : DEFAULT_RENTAL_TRUCKS

  const loadFleet = async () => {
    try {
      const res = await fetchNUI<any>('getInitialData', {})
      if (res && res.fleetTrucks) {
        setFleetTrucks(res.fleetTrucks)
      }
    } catch {
      // Dev mode fallback
    }
  }

  useEffect(() => {
    loadFleet()
  }, [])

  async function handleBuy(model: string) {
    try {
      const res = await fetchNUI<{ ok: boolean; truck?: any; reason?: string }>('buyTruck', { model })
      if (res && res.ok) {
        loadFleet()
        setSubTab('fleet')
      }
    } catch {}
  }

  async function handleSell(truckId: number) {
    setActionLoading(truckId)
    try {
      const res = await fetchNUI<{ ok: boolean; refund?: number }>('sellTruck', { truckId })
      if (res && res.ok) {
        loadFleet()
      }
    } catch {}
    setActionLoading(null)
  }

  async function handleRepair(truckId: number, part: string = 'all') {
    setActionLoading(truckId)
    try {
      const res = await fetchNUI<{ ok: boolean; info?: any }>('repairTruck', { truckId, part })
      if (res && res.ok) {
        loadFleet()
      }
    } catch {}
    setActionLoading(null)
  }

  async function handleRent(model: string) {
    if (activeRental) return
    try {
      const res = await fetchNUI<{ ok: boolean; rental?: any; reason?: string }>('rentTruck', { model })
      if (res && res.ok && res.rental) {
        setActiveRental(res.rental)
      }
    } catch {}
  }

  async function handleReturn() {
    try {
      const res = await fetchNUI<{ ok: boolean; reason?: string }>('returnTruck', {})
      if (res && res.ok) {
        setActiveRental(null)
      }
    } catch {}
  }

  return (
    <div className="space-y-4 select-none">
      {/* Sub-Tabs de Navegação */}
      <div className="flex items-center justify-between border-b border-lation-line pb-2">
        <div className="flex items-center gap-2">
          <button
            onClick={() => setSubTab('fleet')}
            className={`px-3 py-1.5 rounded-md text-xs font-bold transition-all ${
              subTab === 'fleet'
                ? 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border shadow-sm'
                : 'bg-lation-surface-deep text-lation-content-sec border border-lation-line hover:text-white'
            }`}
          >
            🚛 Minha Frota ({fleetTrucks.length})
          </button>
          <button
            onClick={() => setSubTab('dealership')}
            className={`px-3 py-1.5 rounded-md text-xs font-bold transition-all ${
              subTab === 'dealership'
                ? 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border shadow-sm'
                : 'bg-lation-surface-deep text-lation-content-sec border border-lation-line hover:text-white'
            }`}
          >
            🏢 Concessionária
          </button>
          <button
            onClick={() => setSubTab('rental')}
            className={`px-3 py-1.5 rounded-md text-xs font-bold transition-all ${
              subTab === 'rental'
                ? 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border shadow-sm'
                : 'bg-lation-surface-deep text-lation-content-sec border border-lation-line hover:text-white'
            }`}
          >
            🔑 Aluguel com Caução
          </button>
        </div>
      </div>

      {/* ABA 1: MINHA FROTA & OFICINA MECÂNICA */}
      {subTab === 'fleet' && (
        <div className="space-y-3">
          {fleetTrucks.length === 0 ? (
            <div className="p-8 text-center bg-lation-surface-deep border border-lation-line rounded-lg">
              <span className="text-3xl mb-2 block">🚛</span>
              <h4 className="text-sm font-bold text-white">Nenhum caminhão próprio na frota</h4>
              <p className="text-xs text-lation-content-muted mt-1">
                Adquira seu primeiro veículo na Concessionária para participar do Mercado de Fretes sem taxas de aluguel.
              </p>
              <button
                onClick={() => setSubTab('dealership')}
                className="mt-4 px-4 py-2 rounded-md bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border text-xs font-bold hover:brightness-110"
              >
                Abrir Concessionária
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {fleetTrucks.map((truck) => {
                const catalogItem = DEFAULT_DEALERSHIP[truck.truck_name]
                const name = catalogItem ? catalogItem.name : truck.truck_name.toUpperCase()
                const enginePercent = Math.max(0, Math.floor(truck.engine / 10))
                const bodyPercent = Math.max(0, Math.floor(truck.body / 10))
                const transPercent = Math.max(0, Math.floor(truck.transmission / 10))
                const wheelsPercent = Math.max(0, Math.floor(truck.wheels / 10))
                const isLoading = actionLoading === truck.truck_id

                return (
                  <div key={truck.truck_id} className="p-4 bg-lation-surface-band border border-lation-line rounded-lg space-y-3">
                    <div className="flex items-center justify-between border-b border-lation-line/60 pb-2">
                      <div>
                        <h4 className="text-sm font-bold text-white">{name}</h4>
                        <span className="text-[10px] font-mono text-lation-accent-bright font-semibold">
                          ID: #{truck.truck_id} • Garagem: {truck.garage_id || 'Principal'}
                        </span>
                      </div>
                      <span className="text-xs font-mono font-bold text-lation-btn-text bg-lation-surface-deep border border-lation-line px-2.5 py-1 rounded">
                        Combustível: {truck.fuel}%
                      </span>
                    </div>

                    {/* Status de Desgaste Mecânico */}
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div className="p-2 bg-lation-surface-deep border border-lation-line rounded">
                        <div className="flex justify-between text-[10px] font-semibold text-lation-content-muted mb-1">
                          <span>⚙️ Motor</span>
                          <span className={enginePercent < 50 ? 'text-rose-400' : 'text-emerald-400'}>{enginePercent}%</span>
                        </div>
                        <div className="w-full h-1.5 bg-lation-surface rounded-full overflow-hidden">
                          <div className={`h-full ${enginePercent < 50 ? 'bg-rose-500' : 'bg-emerald-500'}`} style={{ width: `${enginePercent}%` }} />
                        </div>
                      </div>

                      <div className="p-2 bg-lation-surface-deep border border-lation-line rounded">
                        <div className="flex justify-between text-[10px] font-semibold text-lation-content-muted mb-1">
                          <span>🛡️ Lataria</span>
                          <span className={bodyPercent < 50 ? 'text-rose-400' : 'text-emerald-400'}>{bodyPercent}%</span>
                        </div>
                        <div className="w-full h-1.5 bg-lation-surface rounded-full overflow-hidden">
                          <div className={`h-full ${bodyPercent < 50 ? 'bg-rose-500' : 'bg-emerald-500'}`} style={{ width: `${bodyPercent}%` }} />
                        </div>
                      </div>

                      <div className="p-2 bg-lation-surface-deep border border-lation-line rounded">
                        <div className="flex justify-between text-[10px] font-semibold text-lation-content-muted mb-1">
                          <span>🔄 Transmissão</span>
                          <span className={transPercent < 50 ? 'text-rose-400' : 'text-emerald-400'}>{transPercent}%</span>
                        </div>
                        <div className="w-full h-1.5 bg-lation-surface rounded-full overflow-hidden">
                          <div className={`h-full ${transPercent < 50 ? 'bg-rose-500' : 'bg-emerald-500'}`} style={{ width: `${transPercent}%` }} />
                        </div>
                      </div>

                      <div className="p-2 bg-lation-surface-deep border border-lation-line rounded">
                        <div className="flex justify-between text-[10px] font-semibold text-lation-content-muted mb-1">
                          <span>🔘 Pneus</span>
                          <span className={wheelsPercent < 50 ? 'text-rose-400' : 'text-emerald-400'}>{wheelsPercent}%</span>
                        </div>
                        <div className="w-full h-1.5 bg-lation-surface rounded-full overflow-hidden">
                          <div className={`h-full ${wheelsPercent < 50 ? 'bg-rose-500' : 'bg-emerald-500'}`} style={{ width: `${wheelsPercent}%` }} />
                        </div>
                      </div>
                    </div>

                    {/* Ações da Oficina e Venda */}
                    <div className="flex items-center gap-2 pt-1">
                      <button
                        onClick={() => handleRepair(truck.truck_id, 'all')}
                        disabled={isLoading}
                        className="flex-1 py-1.5 bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border rounded text-xs font-bold hover:brightness-110"
                      >
                        🔧 Reparar Geral
                      </button>
                      <button
                        onClick={() => handleSell(truck.truck_id)}
                        disabled={isLoading}
                        className="py-1.5 px-3 bg-rose-500/10 text-rose-400 border border-rose-500/30 rounded text-xs font-bold hover:bg-rose-500/20"
                      >
                        💵 Vender (70%)
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}

      {/* ABA 2: CONCESSIONÁRIA */}
      {subTab === 'dealership' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {Object.entries(DEFAULT_DEALERSHIP).map(([modelKey, truck]) => (
            <div key={modelKey} className="p-4 bg-lation-surface-band border border-lation-line rounded-lg flex flex-col justify-between space-y-3">
              <div>
                <div className="flex items-center justify-between">
                  <h4 className="text-sm font-bold text-white">{truck.name}</h4>
                  <span className="font-mono text-xs font-bold text-lation-btn-text">
                    R$ {truck.price.toLocaleString('pt-BR')}
                  </span>
                </div>

                <div className="mt-2 space-y-1 text-[11px] text-lation-content-muted">
                  <p>• Motor: <span className="text-white font-mono">{truck.engine}</span></p>
                  <p>• Câmbio: <span className="text-white font-mono">{truck.transmission}</span></p>
                  <p>• Potência: <span className="text-white font-mono">{truck.hp} HP</span></p>
                  <p>• Nível Mínimo: <span className="text-lation-accent-bright font-bold">Nível {truck.required_level}</span></p>
                  <p>• Bônus p/ Motorista: <span className="text-emerald-400 font-bold">+{truck.driver_bonus}%</span></p>
                </div>
              </div>

              <button
                onClick={() => handleBuy(modelKey)}
                className="w-full py-2 bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border rounded text-xs font-bold hover:brightness-110 tracking-wide"
              >
                Comprar Caminhão
              </button>
            </div>
          ))}
        </div>
      )}

      {/* ABA 3: ALUGUEL COM CAUÇÃO */}
      {subTab === 'rental' && (
        <div className="space-y-3">
          {activeRental && (
            <div className="p-4 rounded-lg bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-between">
              <div>
                <h4 className="text-xs font-bold text-emerald-400">Locação Ativa</h4>
                <p className="text-xs text-white mt-0.5">Placa: <span className="font-mono font-bold">{activeRental.plate}</span></p>
              </div>
              <button
                onClick={handleReturn}
                className="py-1.5 px-4 bg-rose-500 text-white rounded text-xs font-bold hover:bg-rose-600"
              >
                Devolver Caminhão
              </button>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {availableRentals.map((r) => (
              <div key={r.model} className="p-4 bg-lation-surface-band border border-lation-line rounded-lg space-y-2">
                <h4 className="text-sm font-bold text-white">{r.label}</h4>
                <p className="text-xs text-lation-content-muted">Diária: <span className="text-white font-mono font-bold">R$ {r.fee}</span></p>
                <p className="text-xs text-lation-content-muted">Caução: <span className="text-amber-400 font-mono font-bold">R$ {r.deposit}</span></p>
                <button
                  onClick={() => handleRent(r.model)}
                  disabled={!!activeRental}
                  className={`w-full mt-2 py-1.5 rounded text-xs font-bold ${
                    activeRental
                      ? 'bg-lation-surface-deep text-lation-content-muted border border-lation-line cursor-not-allowed'
                      : 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border hover:brightness-110'
                  }`}
                >
                  {activeRental ? 'Já possui aluguel ativo' : 'Alugar Caminhão'}
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
