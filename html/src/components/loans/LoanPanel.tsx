import { useState, useEffect } from 'react'
import { useStatsStore } from '../../stores/useStatsStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

interface LoanPlan {
  loan_amount: number
  interest_rate: number
  repayment_days: number
}

const DEFAULT_PLANS: LoanPlan[] = [
  { loan_amount: 20000, interest_rate: 20.0, repayment_days: 15 },
  { loan_amount: 50000, interest_rate: 17.5, repayment_days: 20 },
  { loan_amount: 100000, interest_rate: 15.0, repayment_days: 25 },
  { loan_amount: 400000, interest_rate: 12.5, repayment_days: 30 },
]

export function LoanPanel({ isCompany = false }: { isCompany?: boolean }) {
  const { personalLoan, setPersonalLoan, stats } = useStatsStore()
  const { companyLoan, setCompanyLoan } = useCompanyStore()
  const [payAmount, setPayAmount] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [plans, setPlans] = useState<LoanPlan[]>(DEFAULT_PLANS)
  const [maxAllowed, setMaxAllowed] = useState(40000)

  const activeLoan = isCompany ? companyLoan : personalLoan

  useEffect(() => {
    fetchNUI<any>('getInitialData', {})
      .then((data) => {
        if (data && data.loanPlans) {
          if (data.loanPlans.plans) setPlans(data.loanPlans.plans)
          if (data.loanPlans.maxAllowed) setMaxAllowed(data.loanPlans.maxAllowed)
        }
      })
      .catch(() => {})
  }, [])

  async function handleTakePlan(planIndex: number) {
    setLoading(true)
    setError(null)
    try {
      const res = await fetchNUI<{ ok: boolean; loan?: any; reason?: string }>('takeLoanPlan', { planIndex })
      if (res && res.ok && res.loan) {
        if (isCompany) {
          setCompanyLoan(res.loan)
        } else {
          setPersonalLoan(res.loan)
        }
      } else {
        setError(res?.reason || 'Não foi possível contratar o empréstimo')
      }
    } catch {
      setError('Erro de comunicação com o banco central')
    }
    setLoading(false)
  }

  async function handlePay() {
    if (!activeLoan) return
    const amount = parseInt(payAmount, 10)
    if (isNaN(amount) || amount <= 0) {
      setError('Informe um valor válido')
      return
    }
    setLoading(true)
    setError(null)
    try {
      const res = await fetchNUI<{ success: boolean; remaining_balance?: number; reason?: string }>('payLoan', {
        loanId: activeLoan.id,
        amount,
        isCompanyLoan: isCompany
      })
      if (res && res.success) {
        const remaining = res.remaining_balance ?? 0
        if (isCompany) {
          setCompanyLoan(remaining <= 0 ? null : { ...activeLoan, remaining_balance: remaining })
        } else {
          setPersonalLoan(remaining <= 0 ? null : { ...activeLoan, remaining_balance: remaining })
        }
        setPayAmount('')
      } else {
        setError(res?.reason || 'Falha ao processar pagamento')
      }
    } catch {}
    setLoading(false)
  }

  const playerLevel = stats?.level || 1

  return (
    <div className="space-y-5 select-none">
      {/* Header Informativo */}
      <div className="flex items-center justify-between border-b border-lation-line pb-2.5">
        <div className="flex items-center gap-2">
          <span className="w-2.5 h-2.5 rounded bg-lation-accent" />
          <h3 className="text-xs font-bold uppercase tracking-wider text-lation-content-sec">
            Sistema Financeiro & Linhas de Crédito Bancário
          </h3>
        </div>
        <span className="text-[11px] font-mono text-lation-accent-bright bg-lation-surface-deep px-3 py-1 rounded border border-lation-line">
          Limite Autorizado: R$ {maxAllowed.toLocaleString('pt-BR')} (Nível {playerLevel})
        </span>
      </div>

      {error && (
        <div className="p-3 rounded bg-rose-500/10 border border-rose-500/30 text-xs text-rose-400 font-semibold">
          ⚠️ {error}
        </div>
      )}

      {/* Empréstimo Ativo */}
      {activeLoan && activeLoan.status === 'active' ? (
        <div className="p-4 bg-lation-surface-band border border-lation-accent rounded-lg space-y-4">
          <div className="flex items-center justify-between border-b border-lation-line pb-2">
            <div>
              <span className="text-[10px] font-mono uppercase text-lation-accent-bright font-bold">Financiamento Ativo</span>
              <h4 className="text-sm font-bold text-white">Contrato #{activeLoan.id}</h4>
            </div>
            <span className="px-2.5 py-1 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 text-[10px] font-bold font-mono">
              EM DIA
            </span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-center">
            <div className="p-3 bg-lation-surface-deep border border-lation-line rounded">
              <span className="text-[10px] uppercase text-lation-content-muted font-mono">Saldo Devedor Restante</span>
              <p className="text-lg font-mono font-bold text-white mt-1">
                R$ {activeLoan.remaining_balance?.toLocaleString('pt-BR')}
              </p>
            </div>
            <div className="p-3 bg-lation-surface-deep border border-lation-line rounded">
              <span className="text-[10px] uppercase text-lation-content-muted font-mono">Parcela Diária</span>
              <p className="text-lg font-mono font-bold text-amber-400 mt-1">
                R$ {(activeLoan.monthly_payment || activeLoan.daily_payment || 0).toLocaleString('pt-BR')}
              </p>
            </div>
            <div className="p-3 bg-lation-surface-deep border border-lation-line rounded">
              <span className="text-[10px] uppercase text-lation-content-muted font-mono">Valor Contratado</span>
              <p className="text-lg font-mono font-bold text-lation-btn-text mt-1">
                R$ {activeLoan.amount?.toLocaleString('pt-BR')}
              </p>
            </div>
          </div>

          {/* Área de Amortização / Pagamento */}
          <div className="flex gap-2 pt-2">
            <input
              type="number"
              value={payAmount}
              onChange={(e) => setPayAmount(e.target.value)}
              placeholder="Digite o valor a amortizar (R$)"
              className="flex-1 bg-lation-surface-deep border border-lation-line rounded px-3 py-2 text-xs text-white placeholder-lation-content-muted focus:outline-none focus:border-lation-accent"
            />
            <button
              onClick={handlePay}
              disabled={loading}
              className="px-6 py-2 bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border rounded text-xs font-bold hover:brightness-110"
            >
              {loading ? 'Processando...' : 'Efetuar Pagamento'}
            </button>
          </div>
        </div>
      ) : (
        /* Planos de Crédito Disponíveis */
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
          {plans.map((p, idx) => {
            const planIdx = idx + 1
            const isLocked = p.loan_amount > maxAllowed
            const totalRepay = Math.ceil(p.loan_amount * (1 + p.interest_rate / 100))
            const daily = Math.ceil(totalRepay / p.repayment_days)

            return (
              <div
                key={planIdx}
                className={`p-4 rounded-lg border flex flex-col justify-between space-y-3 transition-all ${
                  isLocked
                    ? 'bg-lation-surface-deep border-lation-line opacity-50'
                    : 'bg-lation-surface-band border-lation-line hover:border-lation-line-focus'
                }`}
              >
                <div>
                  <div className="flex items-center justify-between">
                    <span className="text-[10px] font-mono font-bold text-lation-accent-bright">
                      PLANO #{planIdx}
                    </span>
                    <span className="text-[10px] font-mono text-lation-content-muted">
                      {p.repayment_days} Dias
                    </span>
                  </div>

                  <h4 className="text-base font-bold text-white mt-1">
                    R$ {p.loan_amount.toLocaleString('pt-BR')}
                  </h4>

                  <div className="mt-3 space-y-1 text-[11px] text-lation-content-muted">
                    <p>• Taxa de Juros: <span className="text-white font-mono font-bold">{p.interest_rate}%</span></p>
                    <p>• Parcela Diária: <span className="text-amber-400 font-mono font-bold">R$ {daily.toLocaleString('pt-BR')}</span></p>
                    <p>• Total a Pagar: <span className="text-white font-mono">R$ {totalRepay.toLocaleString('pt-BR')}</span></p>
                  </div>
                </div>

                <button
                  onClick={() => handleTakePlan(planIdx)}
                  disabled={isLocked || loading}
                  className={`w-full py-2 rounded text-xs font-bold tracking-wide transition-all ${
                    isLocked
                      ? 'bg-lation-surface-deep text-lation-content-muted border border-lation-line cursor-not-allowed'
                      : 'bg-lation-btn-bg text-lation-btn-text border border-lation-btn-border hover:brightness-110 shadow-sm'
                  }`}
                >
                  {isLocked ? 'Nível Insuficiente' : 'Contratar Linha'}
                </button>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
