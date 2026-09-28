import { useEffect } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { Vehicle } from '../../types'

export function GaragePanel() {
  const { company, vehicles, setVehicles } = useCompanyStore()

  useEffect(() => {
    if (!company) return
    fetchNUI<Vehicle[]>('getVehicles', { companyId: company.id })
      .then(data => setVehicles(data ?? []))
  }, [company?.id])

  async function handleRegister() {
    await fetchNUI('registerVehicle')
  }

  async function handleRetrieve(plate: string) {
    await fetchNUI('retrieveVehicle', { plate })
  }

  async function handleStore(plate: string) {
    await fetchNUI('storeVehicle', { plate })
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h3 className="text-txt-light font-semibold">Veículos da Empresa</h3>
        <span className="text-txt text-sm">{vehicles.length}/2</span>
      </div>

      {vehicles.length === 0 ? (
        <p className="text-txt-secondary text-sm text-center py-4">Nenhum veículo registrado</p>
      ) : (
        <div className="space-y-2">
          {vehicles.map(v => (
            <div key={v.plate} className="flex justify-between items-center bg-card rounded-lg p-3 border border-app-border">
              <div>
                <p className="text-txt-light text-sm font-medium">{v.plate}</p>
                <p className="text-txt text-xs">{v.model} · {v.vehicle_type}</p>
              </div>
              <div className="flex items-center gap-2">
                <span className={`text-xs px-2 py-0.5 rounded-full ${v.status === 'stored' ? 'bg-success/20 text-success' : 'bg-warning/20 text-warning'}`}>
                  {v.status === 'stored' ? 'Disponível' : 'Em Uso'}
                </span>
                <button
                  onClick={() => handleRetrieve(v.plate)}
                  className="text-primary hover:text-primary-light text-xs font-medium transition-colors"
                >
                  Retirar
                </button>
                <button
                  onClick={() => handleStore(v.plate)}
                  className="text-warning hover:text-warning text-xs font-medium transition-colors"
                >
                  Guardar
                </button>
                {company?.role === 'owner' && (
                  <button
                    onClick={() => fetchNUI('removeVehicle', { plate: v.plate })}
                    className="text-danger hover:text-danger text-xs transition-colors"
                  >
                    Remover
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {vehicles.length < 2 && (
        <button
          onClick={handleRegister}
          className="w-full py-2 bg-primary/20 hover:bg-primary/40 text-primary border border-primary/30 rounded-lg text-sm transition-colors"
        >
          Registrar Veículo Atual
        </button>
      )}
    </div>
  )
}
