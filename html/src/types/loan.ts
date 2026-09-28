// html/src/types/loan.ts
export type LoanStatus = 'active' | 'paid' | 'defaulted'

export interface LoanData {
  id: number
  amount: number             // valor original solicitado
  remaining_balance: number  // saldo devedor atual
  monthly_payment: number    // parcela mínima
  next_payment_at: number | null    // unix timestamp UTC (segundos); null quando quitado
  status: LoanStatus
  is_company_loan: boolean   // true se company_id != null no DB
}
