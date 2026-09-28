import { useAdrStore } from '../../stores/useAdrStore'
import { AdrCertCard } from './AdrCertCard'

const ADR_TYPES: { id: string; label: string }[] = [
  { id: 'flammable_liquid', label: 'Líquidos Inflamáveis'       },
  { id: 'flammable_gas',    label: 'Gases Inflamáveis'          },
  { id: 'toxic',            label: 'Substâncias Tóxicas'        },
  { id: 'corrosive',        label: 'Substâncias Corrosivas'     },
  { id: 'explosive',        label: 'Explosivos'                 },
  { id: 'environmental',    label: 'Perigosas ao Meio Ambiente' },
]

export function AdrPanel() {
  const { certs } = useAdrStore()

  const certMap = Object.fromEntries(certs.map((c) => [c.adr_type, c]))

  return (
    <div className="flex flex-col gap-3">
      <h2 className="text-txt-light font-semibold text-sm">
        Certificações ADR
        <span className="ml-2 text-txt font-normal text-xs">
          — Exija para cargas perigosas. Válidas por 30 dias.
        </span>
      </h2>
      <div className="grid grid-cols-2 gap-2">
        {ADR_TYPES.map((type) => (
          <AdrCertCard
            key={type.id}
            adrType={type.id}
            label={type.label}
            cert={certMap[type.id]}
          />
        ))}
      </div>
    </div>
  )
}
