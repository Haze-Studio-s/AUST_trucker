import { useEffect, useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { useAppStore } from '../../stores/useAppStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { Vehicle, RentalTruck } from '../../types'

const DEFAULT_RENTAL_TRUCKS: RentalTruck[] = [
  { model: 'hauler', label: 'Hauler Comercial', fee: 300, deposit: 1500, capacity: '18.000 kg' },
  { model: 'phantom', label: 'Phantom Clássico', fee: 300, deposit: 1500, capacity: '22.000 kg' },
  { model: 'packer', label: 'Packer Pesado', fee: 400, deposit: 2000, capacity: '28.000 kg' },
]

export function GaragePanel() {
  const { company, vehicles, setVehicles } = useCompanyStore()
  const { rentalTrucks, activeRental, setActiveRental } = useAppStore()
  const [renting, setRenting] = useState(false)
  const [returning, setReturning] = useState(false)

  const availableRentals = rentalTrucks.length > 0 ? rentalTrucks : DEFAULT_RENTAL_TRUCKS

  useEffect(() => {
    if (!company) return
    fetchNUI<Vehicle[]>('getVehicles', { companyId: company.id })
      .then(data => setVehicles(data ?? []))
      .catch(() => {})
  }, [company?.id, setVehicles])

  async function handleRent(model: string) {
    if (activeRental) return
    setRenting(true)
    try {
      const res = await fetchNUI<{ ok: boolean; rental?: any; reason?: string }>('rentTruck', { model })
      if (res && res.ok && res.rental) {
        setActiveRental(res.rental)
      }
    } catch {
      // Ignorar falha de fetch no Dev
    }
    setRenting(false)
  }

  async function handleReturn() {
    setReturning(true)
    try {
      const res = await fetchNUI<{ ok: boolean; reason?: string }>('returnTruck', {})
      if (res && res.ok) {
        setActiveRental(null)
      }
    } catch {
      // Ignorar
    }
    setReturning(false)
  }

  async function handleRegister() {
    await fetchNUI('registerVehicle').catch(() => {})
    if (company) {
      fetchNUI<Vehicle[]>('getVehicles', { companyId: company.id })
        .then(data => setVehicles(data ?? []))
        .catch(() => {})
    }
  }

  async function handleRetrieve(plate: string) {
    await fetchNUI('retrieveVehicle', { plate }).catch(() => {})
  }

  async function handleStore(plate: string) {
    await fetchNUI('storeVehicle', { plate }).catch(() => {})
  }

  return (
    <div className="space-y-6 select-none">
      {/* ─── SEÇÃO 1: CENTRAL DE LOCAÇÃO DE CAMINHÕES ─── */}
      <div className="space-y-3">
        <div className="flex items-center justify-between border-b border-lation-line pb-2">
          <div className="flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded bg-lation-accent" />
            <h3 className="text-xs font-bold uppercase tracking-wider text-lation-content-sec">
              Locadora de Caminhões
            </h3>
            <span className="chip text-[10px] text-lation-accent-soft bg-lation-surface-elevated py-0.5 px-2">
              Caução Reembolsável
            </span>
          </div>

          <span className="text-[11px] text-lation-content-muted">
            Locação individual por diária
          </span>
        </div>

        {/* Card de Locação Ativa (Se houver caminhão alugado) */}
        {activeRental ? (
          <div className="p-4 rounded-lg bg-lation-surface-band border border-lation-accent bg-gradient-to-r from-emerald-500/10 via-transparent to-transparent flex items-center justify-between shadow-sm">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-lation-btn-bg border border-lation-btn-border flex items-center justify-center text-lation-btn-text text-xl">
                🚚
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-bold text-sm text-white uppercase">{activeRental.model}</span>
                  <span className="chip text-[10px] font-mono py-0.5 px-1.5 bg-lation-surface-deep text-lation-accent-bright border-lation-line">
                    PLACA: {activeRental.plate}
                  </span>
                </div>
                <p className="text-xs text-lation-content-sec mt-0.5">
                  Caução em custódia: <b className="font-mono text-white">R$ {activeRental.deposit?.toLocaleString('pt-BR') || '1.500'}</b> · Taxa diária paga
                </p>
              </div>
            </div>

            <button
              onClick={handleReturn}
              disabled={returning}
              className="px-4 py-2 rounded-lg text-xs font-bold bg-amber-500/20 text-amber-300 border border-amber-500/40 hover:bg-amber-500/30 transition-all flex items-center gap-1.5 disabled:opacity-50"
            >
              {returning ? 'Processando Devolução...' : 'Devolver Caminhão & Reaver Caução'}
            </button>
          </div>
        ) : (
          /* Grid de Caminhões para Locação */
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {availableRentals.map(truck => (
              <div
                key={truck.model}
                className="p-3.5 rounded-lg bg-lation-surface-deep border border-lation-line hover:border-lation-line-hover hover:bg-lation-surface-hover transition-all flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-start justify-between">
                    <div>
                      <h4 className="font-bold text-sm text-white">{truck.label}</h4>
                      <p className="text-[11px] font-mono text-lation-content-muted uppercase mt-0.5">
                        Modelo: {truck.model}
                      </p>
                    </div>
                    <span className="chip text-[10px] bg-lation-surface-elevated text-lation-content-sec">
                      {truck.capacity || '20.000 kg'}
                    </span>
                  </div>

                  {/* Informações de Custo e Caução */}
                  <div className="mt-3 space-y-1.5 text-xs bg-lation-surface-band p-2 rounded border border-lation-line">
                    <div className="flex justify-between">
                      <span className="text-lation-content-muted">Taxa de Locação:</span>
                      <span className="font-mono font-semibold text-white">R$ {truck.fee.toLocaleString('pt-BR')}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-lation-content-muted">Caução (Seguro):</span>
                      <span className="font-mono font-semibold text-lation-accent-bright">
                        R$ {truck.deposit.toLocaleString('pt-BR')}
                      </span>
                    </div>
                  </div>
                </div>

                <button
                  onClick={() => handleRent(truck.model)}
                  disabled={renting}
                  className="mt-3.5 w-full py-2 rounded text-xs font-bold bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border hover:border-lation-accent hover:text-white shadow-sm transition-all disabled:opacity-50"
                >
                  {renting ? 'Alugando...' : 'Alugar este Caminhão'}
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ─── SEÇÃO 2: FROTA EMPRESARIAL / VEÍCULOS PRÓPRIOS ─── */}
      <div className="space-y-3 pt-2">
        <div className="flex items-center justify-between border-b border-lation-line pb-2">
          <div className="flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded bg-lation-accent-soft" />
            <h3 className="text-xs font-bold uppercase tracking-wider text-lation-content-sec">
              Frota Própria & Corporativa
            </h3>
            {company && (
              <span className="chip text-[10px] text-lation-accent-bright font-mono py-0.5 px-2">
                {vehicles.length}/{company.perks?.vehicles || 2} vagas
              </span>
            )}
          </div>

          {!company && (
            <span className="text-xs text-amber-300">
              Disponível para membros de empresas registradas
            </span>
          )}
        </div>

        {!company ? (
          <div className="p-4 rounded-lg bg-lation-surface-deep border border-lation-line text-center text-xs text-lation-content-sec">
            Você não pertence a uma empresa de transporte. Para comprar e gerenciar sua própria frota com até 10 caminhões, funde ou ingresse em uma empresa na aba <b>Empresa</b>.
          </div>
        ) : vehicles.length === 0 ? (
          <div className="p-5 rounded-lg bg-lation-surface-deep border border-lation-line text-center">
            <p className="text-xs text-lation-content-sec">Nenhum veículo registrado na garagem corporativa.</p>
            <p className="text-[11px] text-lation-content-muted mt-1">
              Estacione seu caminhão na vaga da transportadora e clique em Registrar.
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {vehicles.map(v => (
              <div
                key={v.plate}
                className="flex items-center justify-between p-3 rounded-lg bg-lation-surface-deep border border-lation-line hover:border-lation-line-hover transition-all"
              >
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded bg-lation-surface-elevated border border-lation-line flex items-center justify-center font-mono font-bold text-xs text-white">
                    🚛
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono font-bold text-xs text-white tracking-wider">{v.plate}</span>
                      <span
                        className={`text-[10px] font-semibold px-2 py-0.5 rounded ${
                          v.status === 'stored'
                            ? 'bg-emerald-500/15 text-emerald-300 border border-emerald-500/30'
                            : 'bg-amber-500/15 text-amber-300 border border-amber-500/30'
                        }`}
                      >
                        {v.status === 'stored' ? 'Disponível na Garagem' : 'Em Circulação'}
                      </span>
                    </div>
                    <p className="text-xs text-lation-content-muted mt-0.5">
                      {v.model} · {v.vehicle_type || 'Pesado'}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  {v.status === 'stored' ? (
                    <button
                      onClick={() => handleRetrieve(v.plate)}
                      className="px-3 py-1.5 rounded text-xs font-semibold bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border hover:border-lation-accent hover:text-white transition-all"
                    >
                      Retirar Veículo
                    </button>
                  ) : (
                    <button
                      onClick={() => handleStore(v.plate)}
                      className="px-3 py-1.5 rounded text-xs font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/40 hover:bg-amber-500/30 transition-all"
                    >
                      Guardar na Garagem
                    </button>
                  )}

                  {company.role === 'owner' && (
                    <button
                      onClick={() => fetchNUI('removeVehicle', { plate: v.plate })}
                      className="px-2.5 py-1.5 rounded text-xs font-medium text-lation-content-muted hover:text-red-400 hover:bg-red-950/30 transition-all"
                      title="Desvincular da empresa"
                    >
                      Remover
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {company && vehicles.length < (company.perks?.vehicles || 2) && (
          <button
            onClick={handleRegister}
            className="w-full py-2.5 rounded-lg text-xs font-semibold bg-lation-surface-elevated hover:bg-lation-surface-hover text-white border border-lation-line-strong hover:border-lation-accent transition-all flex items-center justify-center gap-2"
          >
            <span>+ Registrar Caminhão Atual na Frota</span>
          </button>
        )}
      </div>
    </div>
  )
}
