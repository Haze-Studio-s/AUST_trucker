import { useEffect, useState } from 'react'
import { useIndustryStore } from '../../stores/useIndustryStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { Industry } from '../../types'

export function IndustryList() {
  const { industries, setIndustries, ownedIndustries, addOwnedIndustry } = useIndustryStore()
  const company = useCompanyStore(s => s.company)
  const [buyError, setBuyError] = useState<string | null>(null)

  useEffect(() => {
    fetchNUI<Record<string, Industry>>('getIndustries')
      .then(data => { if (data) setIndustries(data) })
  }, [])

  const list = Object.values(industries)
  const canBuy = company?.company_type === 'logistics' &&
    (company?.role === 'owner' || company?.role === 'manager') &&
    ownedIndustries.length < 3

  const handleBuyIndustry = async (industryId: string, industryName: string, price: number) => {
    setBuyError(null)
    const result = await fetchNUI<{ success: boolean; reason?: string; price?: number }>('buyIndustry', { industryId })
    if (result?.success) {
      addOwnedIndustry({
        industryId,
        industryName,
        purchasePrice: result.price ?? price,
        totalEarned: 0,
        productionLevel: 1,
        npcWorkers: 0,
      })
      // Refetch industries to update ownership badges
      fetchNUI<Record<string, Industry>>('getIndustries')
        .then(data => { if (data) setIndustries(data) })
    } else {
      setBuyError(result?.reason ?? 'Erro ao comprar indústria')
    }
  }

  if (list.length === 0) return (
    <div className="flex items-center justify-center h-full text-txt-secondary">
      <p>Carregando indústrias...</p>
    </div>
  )

  return (
    <div className="space-y-3">
      {buyError && (
        <div className="bg-danger-dark/20 border border-danger-dark rounded p-2 text-danger text-xs">
          {buyError}
        </div>
      )}
      {list.map(industry => {
        const isMyCompany = industry.ownedByCompanyId && industry.ownedByCompanyId === company?.id
        const isOwned = !!industry.ownedByCompanyId
        // Estimate buy price for display (actual price comes from server)
        const estimatedPrice = industry.production
          ? Math.floor((industry.production.price ?? 0) * (industry.production.productionPerHour ?? 1) * 10)
          : 0

        return (
          <div key={industry.id} className="bg-card rounded-lg p-3 border border-app-border">
            <div className="flex justify-between items-start mb-2">
              <div>
                <h4 className="text-txt-light font-medium text-sm">{industry.name}</h4>
                {isMyCompany && (
                  <span className="text-success text-xs font-medium">✓ Sua empresa</span>
                )}
                {isOwned && !isMyCompany && (
                  <span className="text-gold text-xs">
                    {industry.ownedByCompanyName ?? 'Empresa privada'}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2">
                <span className="text-txt-secondary text-xs capitalize">{industry.industryType}</span>
                <button
                  onClick={() => fetchNUI('industryGPS', { industryId: industry.id, name: industry.name })}
                  className="bg-primary/30 hover:bg-primary/50 text-primary hover:text-primary-light text-xs font-medium px-2 py-1 rounded border border-primary/30 transition-colors"
                >
                  GPS
                </button>
              </div>
            </div>

            {industry.production && (
              <div className="flex justify-between items-center bg-app-bg rounded p-2 mb-1">
                <div>
                  <p className="text-txt text-xs">🔹 {industry.production.product}</p>
                  <p className="text-txt-secondary text-xs">{industry.production.currentStock}/{industry.production.maxStock} {industry.production.unit}</p>
                </div>
                <div className="text-right">
                  <p className="text-success text-sm font-medium">${industry.production.price}</p>
                  <p className="text-txt-secondary text-xs">comprar</p>
                </div>
              </div>
            )}

            {industry.consumption.map(item => (
              <div key={item.item} className="flex justify-between items-center bg-app-bg rounded p-2 mb-1">
                <div>
                  <p className="text-txt text-xs">🔸 {item.product}</p>
                  <p className="text-txt-secondary text-xs">{item.currentStock}/{item.maxStock} {item.unit}</p>
                </div>
                <div className="text-right">
                  <p className="text-primary text-sm font-medium">${item.price}</p>
                  <p className="text-txt-secondary text-xs">vender</p>
                </div>
              </div>
            ))}

            {/* production guard intentional: server rejects purchase of industries without production (price = basePrice × productionPerHour × mult) */}
            {!isOwned && canBuy && industry.production && (
              <button
                onClick={() => handleBuyIndustry(industry.id, industry.name, estimatedPrice)}
                className="mt-2 w-full bg-primary hover:bg-primary-active text-white text-xs py-1.5 rounded transition-colors"
              >
                Comprar Indústria {estimatedPrice > 0 ? `(~$${estimatedPrice.toLocaleString()})` : ''}
              </button>
            )}
          </div>
        )
      })}
    </div>
  )
}
