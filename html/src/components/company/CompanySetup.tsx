import { useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

type CompanyType = 'logistics' | 'repo'

const TYPE_OPTIONS: { value: CompanyType; label: string; desc: string }[] = [
  { value: 'logistics', label: 'Logística', desc: 'Aceita jobs de entrega de carga' },
  { value: 'repo',      label: 'Repo Man',  desc: 'Aceita missões de repossessão' },
]

export function CompanySetup() {
  const { recruitingList } = useCompanyStore()
  const [name, setName]             = useState('')
  const [companyType, setCompanyType] = useState<CompanyType>('logistics')
  const [creating, setCreating]     = useState(false)

  async function handleCreate() {
    if (!name.trim()) return
    setCreating(true)
    try {
      await fetchNUI('createCompany', { name: name.trim(), companyType })
    } finally {
      setCreating(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* Criar empresa */}
      <div className="bg-card rounded-lg p-4 border border-app-border">
        <h3 className="text-txt-light font-semibold mb-3">Criar Empresa</h3>
        <p className="text-txt text-sm mb-3">Custo: <span className="text-success font-medium">$150.000</span></p>

        <input
          type="text"
          placeholder="Nome da empresa"
          value={name}
          onChange={e => setName(e.target.value)}
          maxLength={50}
          className="w-full bg-app-bg border border-app-border rounded-lg px-3 py-2 text-txt-light text-sm placeholder-txt-secondary focus:outline-none focus:border-primary mb-3"
        />

        <p className="text-xs text-txt-secondary uppercase tracking-wider mb-2">Tipo de Empresa</p>
        <div className="grid grid-cols-2 gap-2 mb-3">
          {TYPE_OPTIONS.map(opt => (
            <button
              key={opt.value}
              onClick={() => setCompanyType(opt.value)}
              className={`p-2 rounded-lg border text-left transition-colors ${
                companyType === opt.value
                  ? 'border-primary bg-primary/10 text-primary-light'
                  : 'border-app-border bg-app-bg text-txt hover:border-hover-bg'
              }`}
            >
              <p className="text-sm font-medium">{opt.label}</p>
              <p className="text-[10px] mt-0.5 opacity-70">{opt.desc}</p>
            </button>
          ))}
        </div>

        <button
          onClick={handleCreate}
          disabled={!name.trim() || creating}
          className="w-full py-2 bg-primary hover:bg-primary-hover disabled:opacity-40 text-white rounded-lg font-medium transition-colors text-sm"
        >
          {creating ? 'Criando...' : 'Criar Empresa ($150k)'}
        </button>
      </div>

      {/* Entrar em empresa */}
      {recruitingList.length > 0 && (
        <div className="bg-card rounded-lg p-4 border border-app-border">
          <h3 className="text-txt-light font-semibold mb-3">Empresas Recrutando</h3>
          <div className="space-y-2">
            {recruitingList.map(company => (
              <div key={company.id} className="flex justify-between items-center bg-app-bg rounded p-2">
                <p className="text-txt-light text-sm">{company.name}</p>
                <button
                  onClick={() => fetchNUI('joinCompany', { companyId: company.id })}
                  className="text-primary hover:text-primary-light text-xs border border-primary/30 px-2 py-1 rounded transition-colors"
                >
                  Entrar
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
