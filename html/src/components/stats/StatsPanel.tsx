import { useState, useEffect } from 'react'
import { useStatsStore } from '../../stores/useStatsStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import { SkillTree } from '../progression/SkillTree'
import { LoanPanel } from '../loans/LoanPanel'

const RANK_LABELS = ['', 'Aprendiz', 'Motorista', 'Veterano', 'Especialista', 'Elite', 'Lenda']

// UI-C02: Thresholds espelhados do servidor (progression_service.lua)
// Chave = nível necessário; valor = XP total acumulado para atingi-lo
const LEVEL_XP_THRESHOLDS: Record<number, number> = {
  2: 100,    3: 250,    4: 500,    5: 900,
  6: 1400,   7: 2100,   8: 3000,   9: 4200,
  10: 5800,  11: 7800,  12: 10300, 13: 13300,
  14: 16900, 15: 21200, 16: 26300, 17: 32300,
  18: 39300, 19: 47500, 20: 57000, 21: 68000,
  22: 80500, 23: 94500, 24: 110000,25: 127500,
  26: 147000,27: 168500,28: 192000,29: 218000,
  30: 246500,
}

function calcXpProgress(xp: number, level: number): number {
  if (level >= 30) return 100
  const levelStart = level >= 2 ? (LEVEL_XP_THRESHOLDS[level] ?? 0) : 0
  const levelEnd   = LEVEL_XP_THRESHOLDS[level + 1]
  if (!levelEnd || levelEnd <= levelStart) return 100
  return Math.min(100, Math.max(0, Math.round((xp - levelStart) / (levelEnd - levelStart) * 100)))
}

interface CompanyHistory {
  companyName: string
  companyLevel: number
  companyXP: number
  balance: number
  memberCount: number
  totalJobs: number
  totalRevenue: number
  totalDistance: number
  totalContracts: number
  recentJobs: { cargo_item: string; base_payment: number; distance: number; completed_at: string }[]
  completedContracts: { id: string; contract_type: string; total_payment: number; clientName?: string; bonus_percent: number; completed_at: string }[]
  topClients: { name: string; trustLevel: number; trustLabel: string; totalDeliveries: number; totalRevenue: number; streak: number; sectorLabel: string }[]
}

function TrustStars({ level }: { level: number }) {
  return (
    <span className="text-gold text-xs">
      {'★'.repeat(Math.max(0, level))}{'☆'.repeat(Math.max(0, 5 - level))}
    </span>
  )
}

export function StatsPanel() {
  const { stats } = useStatsStore()
  const { company } = useCompanyStore()
  const [history, setHistory] = useState<CompanyHistory | null>(null)
  const [tab, setTab] = useState<'player' | 'company'>('player')

  // Stats are loaded via 'open' action in useNUI.ts (getInitialData sends stats)
  // Only fetch company history on demand
  useEffect(() => {
    if (company && tab === 'company') {
      fetchNUI('getCompanyHistory').catch(() => {})
    }
  }, [company?.id, tab])

  // Listen for company history from SendNUIMessage
  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail
      if (detail) setHistory(detail)
    }
    window.addEventListener('companyHistory', handler)
    return () => window.removeEventListener('companyHistory', handler)
  }, [])

  const handleStatsRefresh = async () => {
    await fetchNUI('getPlayerStats').catch(() => {})
  }

  return (
    <div className="space-y-3 h-full overflow-auto">
      {/* Tab switcher */}
      {company && (
        <div className="flex gap-1 bg-card rounded-lg p-1">
          <button
            onClick={() => setTab('player')}
            className={`flex-1 py-1.5 rounded text-xs font-medium transition-colors ${tab === 'player' ? 'bg-card-alt text-txt-light' : 'text-txt'}`}
          >Jogador</button>
          <button
            onClick={() => setTab('company')}
            className={`flex-1 py-1.5 rounded text-xs font-medium transition-colors ${tab === 'company' ? 'bg-card-alt text-txt-light' : 'text-txt'}`}
          >Empresa</button>
        </div>
      )}

      {/* Player Stats */}
      {tab === 'player' && (
        <>
          {!stats ? (
            <div className="flex items-center justify-center h-32 text-txt-secondary">
              <p>Sem estatísticas ainda</p>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-4 bg-card/60 rounded-lg p-3 border border-app-border/50">
                <div className="text-center px-3">
                  <p className="text-3xl font-bold text-warning">{stats.level ?? 1}</p>
                  <p className="text-[10px] text-txt-secondary uppercase tracking-wider">Nível</p>
                </div>
                <div className="flex-1">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs font-semibold text-txt">
                      {RANK_LABELS[stats.rank ?? 1] ?? `Rank ${stats.rank}`}
                    </span>
                    <span className="text-[10px] text-txt-secondary">
                      {(stats.skill_points ?? 0) > 0 && (
                        <span className="text-warning font-medium">{stats.skill_points} pts · </span>
                      )}
                      {(stats.xp ?? 0).toLocaleString()} XP
                    </span>
                  </div>
                  <div className="h-1.5 bg-card-alt rounded-full overflow-hidden">
                    <div className="h-full bg-warning rounded-full transition-all" style={{ width: `${calcXpProgress(stats.xp ?? 0, stats.level ?? 1)}%` }} />
                  </div>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2">
                <div className="bg-card rounded-lg p-3 border border-app-border text-center">
                  <p className="text-success font-bold text-lg">${Number(stats.total_earnings || 0).toLocaleString()}</p>
                  <p className="text-txt text-[10px]">Total Ganho</p>
                </div>
                <div className="bg-card rounded-lg p-3 border border-app-border text-center">
                  <p className="text-primary font-bold text-lg">{Number(stats.total_deliveries || 0)}</p>
                  <p className="text-txt text-[10px]">Entregas</p>
                </div>
                <div className="bg-card rounded-lg p-3 border border-app-border text-center">
                  <p className="text-txt-light font-bold text-lg">{Number(stats.total_distance || 0).toFixed(0)} km</p>
                  <p className="text-txt text-[10px]">Distância</p>
                </div>
              </div>
              <div className="border-t border-app-border/50 pt-3">
                <SkillTree onStatsRefresh={handleStatsRefresh} />
              </div>
              <LoanPanel isCompany={false} />
            </>
          )}
        </>
      )}

      {/* Company History */}
      {tab === 'company' && history && (
        <>
          {/* Company header — UI-M04: barra de XP da empresa */}
          <div className="bg-card rounded-lg p-3 border border-app-border">
            <div className="flex justify-between items-center">
              <div>
                <p className="text-txt-light font-semibold">{history.companyName}</p>
                <p className="text-txt-secondary text-xs">Nível {history.companyLevel} · {history.memberCount} membros</p>
              </div>
              <div className="text-right">
                <p className="text-success font-bold">${history.balance.toLocaleString()}</p>
                <p className="text-txt-secondary text-xs">Saldo</p>
              </div>
            </div>
            {/* Barra de XP da empresa — dados precisos vêm do store (xp_next / xp_level_start) */}
            {company && (
              <div className="mt-2">
                <div className="flex justify-between items-center mb-1">
                  <span className="text-[10px] text-txt-secondary">XP da Empresa</span>
                  <span className="text-[10px] text-txt-secondary">
                    {company.xp_next > 0
                      ? `${company.company_xp.toLocaleString()} / ${company.xp_next.toLocaleString()}`
                      : `${company.company_xp.toLocaleString()} — Nível Máximo`}
                  </span>
                </div>
                <div className="h-1.5 bg-card-alt rounded-full overflow-hidden">
                  <div
                    className="h-full bg-primary rounded-full transition-all"
                    style={{
                      width: `${company.xp_next > 0
                        ? Math.min(100, Math.max(0, Math.round(
                            (company.company_xp - company.xp_level_start) /
                            (company.xp_next    - company.xp_level_start) * 100
                          )))
                        : 100}%`
                    }}
                  />
                </div>
              </div>
            )}
          </div>

          {/* Company totals */}
          <div className="grid grid-cols-2 gap-2">
            <div className="bg-card rounded-lg p-2.5 border border-app-border text-center">
              <p className="text-success font-bold">${history.totalRevenue.toLocaleString()}</p>
              <p className="text-txt-secondary text-[10px]">Receita Total</p>
            </div>
            <div className="bg-card rounded-lg p-2.5 border border-app-border text-center">
              <p className="text-primary font-bold">{history.totalJobs}</p>
              <p className="text-txt-secondary text-[10px]">Jobs Completados</p>
            </div>
            <div className="bg-card rounded-lg p-2.5 border border-app-border text-center">
              <p className="text-purple-400 font-bold">{history.totalContracts}</p>
              <p className="text-txt-secondary text-[10px]">Contratos</p>
            </div>
            <div className="bg-card rounded-lg p-2.5 border border-app-border text-center">
              <p className="text-txt-light font-bold">{Number(history.totalDistance).toFixed(0)} km</p>
              <p className="text-txt-secondary text-[10px]">Distância Total</p>
            </div>
          </div>

          {/* Top Clients */}
          {history.topClients && history.topClients.length > 0 && (
            <div>
              <p className="text-txt text-xs uppercase tracking-wide px-1 mb-2">Clientes</p>
              <div className="space-y-1.5">
                {history.topClients
                  .filter(c => c.totalDeliveries > 0)
                  .sort((a, b) => b.totalDeliveries - a.totalDeliveries)
                  .slice(0, 5)
                  .map((client, idx) => (
                    <div key={idx} className="bg-card rounded p-2 border border-app-border flex justify-between items-center">
                      <div>
                        <p className="text-txt-light text-xs font-medium">{client.name}</p>
                        <div className="flex items-center gap-1.5 mt-0.5">
                          <TrustStars level={client.trustLevel} />
                          <span className="text-txt-secondary text-[10px]">{client.trustLabel}</span>
                          <span className="text-txt-muted text-[10px]">·</span>
                          <span className="text-txt-secondary text-[10px]">{client.sectorLabel}</span>
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="text-success text-xs font-medium">${client.totalRevenue.toLocaleString()}</p>
                        <p className="text-txt-secondary text-[10px]">{client.totalDeliveries} entregas</p>
                      </div>
                    </div>
                  ))}
                {history.topClients.every(c => c.totalDeliveries === 0) && (
                  <p className="text-txt-secondary text-xs text-center py-2">Nenhum cliente ativo ainda</p>
                )}
              </div>
            </div>
          )}

          {/* Recent Jobs */}
          {history.recentJobs.length > 0 && (
            <div>
              <p className="text-txt text-xs uppercase tracking-wide px-1 mb-2">Entregas Recentes</p>
              <div className="space-y-1">
                {history.recentJobs.slice(0, 8).map((job, idx) => (
                  <div key={idx} className="bg-card rounded p-2 border border-app-border flex justify-between items-center">
                    <div>
                      <p className="text-txt-light text-xs">{job.cargo_item}</p>
                      <p className="text-txt-secondary text-[10px]">{Number(job.distance).toFixed(1)} km</p>
                    </div>
                    <p className="text-success text-xs font-medium">${job.base_payment.toLocaleString()}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Recent Contracts */}
          {history.completedContracts.length > 0 && (
            <div>
              <p className="text-txt text-xs uppercase tracking-wide px-1 mb-2">Contratos Recentes</p>
              <div className="space-y-1">
                {history.completedContracts.map((contract, idx) => (
                  <div key={idx} className="bg-card rounded p-2 border border-app-border flex justify-between items-center">
                    <div>
                      <p className="text-txt-light text-xs">{contract.clientName ?? 'Cliente'}</p>
                      <p className="text-txt-secondary text-[10px]">
                        {contract.contract_type === 'simple' ? 'Simples' : 'Multi-parada'}
                        {contract.bonus_percent > 0 && ` · +${contract.bonus_percent}%`}
                      </p>
                    </div>
                    <p className="text-success text-xs font-medium">${contract.total_payment.toLocaleString()}</p>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      )}

      {tab === 'company' && !history && (
        <div className="flex items-center justify-center h-32 text-txt-secondary">
          <p>Carregando dados da empresa...</p>
        </div>
      )}
    </div>
  )
}
