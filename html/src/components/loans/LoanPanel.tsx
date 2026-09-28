import { useState } from 'react'
import { useStatsStore } from '../../stores/useStatsStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { LoanData, LoanStatus } from '../../types/loan'

interface LoanPanelProps {
  isCompany: boolean
}

function formatCountdown(unixTs: number): string {
  const diff = unixTs - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'VENCIDO'
  const days  = Math.floor(diff / 86400)
  const hours = Math.floor((diff % 86400) / 3600)
  if (days > 0) return `${days}d ${hours}h`
  const mins = Math.floor((diff % 3600) / 60)
  return `${hours}h ${mins}m`
}

function statusBadge(status: LoanStatus) {
  if (status === 'paid')      return <span className="text-xs px-2 py-0.5 rounded bg-card-alt text-txt">QUITADO</span>
  if (status === 'defaulted') return <span className="text-xs px-2 py-0.5 rounded bg-danger-dark/20 text-danger">INADIMPLENTE</span>
  return <span className="text-xs px-2 py-0.5 rounded bg-success-dark/20 text-success">ATIVO</span>
}

function LoanCard({ loan, isCompany }: { loan: LoanData; isCompany: boolean }) {
  const [payAmount, setPayAmount]   = useState(String(loan.monthly_payment))
  const [loading, setLoading]       = useState(false)
  const [error, setError]           = useState<string | null>(null)
  const { setPersonalLoan }         = useStatsStore()
  const { setCompanyLoan }          = useCompanyStore()

  const isOverdue = loan.next_payment_at !== null && loan.next_payment_at < Math.floor(Date.now() / 1000)

  const handlePay = async () => {
    const amount = parseInt(payAmount, 10)
    if (isNaN(amount) || amount < loan.monthly_payment) {
      setError(`Mínimo: $${loan.monthly_payment.toLocaleString()}`)
      return
    }
    setLoading(true)
    setError(null)

    const result = await fetchNUI<{ success: boolean; remaining_balance?: number; status?: string; reason?: string }>(
      'payLoan',
      { loanId: loan.id, amount, isCompanyLoan: isCompany }
    )

    setLoading(false)

    if (!result.success) {
      setError(result.reason ?? 'Erro ao processar pagamento')
      return
    }

    // Atualizar store local com novo saldo
    const updated: LoanData = {
      ...loan,
      remaining_balance: result.remaining_balance ?? 0,
      status: (result.status as LoanData['status']) ?? loan.status,
    }

    if (isCompany) setCompanyLoan(updated.status === 'paid' ? null : updated)
    else           setPersonalLoan(updated.status === 'paid' ? null : updated)
  }

  return (
    <div className={`rounded-lg p-3 border ${isOverdue ? 'border-danger/40 bg-danger-dark/10' : 'border-app-border/50 bg-card/60'}`}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-txt font-medium uppercase tracking-wider">
          {isCompany ? 'Empréstimo Empresarial' : 'Empréstimo Pessoal'}
        </span>
        {statusBadge(loan.status)}
      </div>

      <div className="grid grid-cols-3 gap-2 mb-3 text-center">
        <div>
          <p className="text-lg font-bold text-txt-light">${loan.remaining_balance.toLocaleString()}</p>
          <p className="text-[10px] text-txt-secondary uppercase">Saldo Devedor</p>
        </div>
        <div>
          <p className="text-lg font-bold text-warning">${loan.monthly_payment.toLocaleString()}</p>
          <p className="text-[10px] text-txt-secondary uppercase">Parcela Mín.</p>
        </div>
        <div>
          <p className={`text-lg font-bold ${isOverdue ? 'text-danger' : 'text-txt'}`}>
            {loan.next_payment_at !== null ? formatCountdown(loan.next_payment_at) : '—'}
          </p>
          <p className="text-[10px] text-txt-secondary uppercase">Vencimento</p>
        </div>
      </div>

      {loan.status === 'active' && (
        <div className="flex gap-2">
          <input
            type="number"
            value={payAmount}
            onChange={(e) => setPayAmount(e.target.value)}
            min={loan.monthly_payment}
            max={loan.remaining_balance}
            className="flex-1 bg-card-alt/50 border border-app-border rounded px-2 py-1.5 text-sm text-txt-light focus:outline-none focus:border-warning/50"
            placeholder={`$${loan.monthly_payment.toLocaleString()}`}
          />
          <button
            onClick={handlePay}
            disabled={loading}
            className="px-4 py-1.5 bg-warning hover:bg-warning disabled:opacity-50 text-white rounded text-sm transition-colors font-medium"
          >
            {loading ? '...' : 'Pagar'}
          </button>
        </div>
      )}

      {error && <p className="text-xs text-danger mt-1.5">{error}</p>}
    </div>
  )
}

export function LoanPanel({ isCompany }: LoanPanelProps) {
  const { personalLoan } = useStatsStore()
  const { companyLoan }  = useCompanyStore()

  const loan = isCompany ? companyLoan : personalLoan

  if (!loan || loan.status === 'paid') {
    return (
      <div className="rounded-lg p-3 border border-app-border/30 bg-card/30 text-center">
        <p className="text-xs text-txt-secondary">Nenhum empréstimo ativo</p>
        <p className="text-[10px] text-txt-muted mt-0.5">Visite o banco em Paleto Bay para solicitar</p>
      </div>
    )
  }

  return <LoanCard loan={loan} isCompany={isCompany} />
}
