import { useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { MemberList } from './MemberList'
import { fetchNUI } from '../../hooks/useNUI'
import { Modal } from '../layout/Modal'
import { LoanPanel } from '../loans/LoanPanel'

export function CompanyPanel() {
  const { company } = useCompanyStore()
  const [depositAmount, setDepositAmount] = useState('')
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [showDeposit, setShowDeposit] = useState(false)
  const [showWithdraw, setShowWithdraw] = useState(false)

  if (!company) return null
  const isOwner = company.role === 'owner'
  const isManager = company.role === 'manager' || isOwner

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-card rounded-lg p-4 border border-app-border">
        <div className="flex justify-between items-start">
          <div>
            <h2 className="text-txt-light font-bold text-lg">{company.name}</h2>
            <p className="text-txt text-sm mt-0.5 capitalize">{company.role}</p>
          </div>
          <div className="text-right">
            <p className="text-txt text-xs">Saldo</p>
            <p className="text-success font-bold">${company.balance.toLocaleString()}</p>
          </div>
        </div>

        <div className="flex gap-2 mt-3">
          <button onClick={() => setShowDeposit(true)} className="flex-1 py-1.5 bg-card-alt hover:bg-hover-bg text-txt-light rounded text-sm transition-colors">
            Depositar
          </button>
          {isManager && (
            <button onClick={() => setShowWithdraw(true)} className="flex-1 py-1.5 bg-card-alt hover:bg-hover-bg text-txt-light rounded text-sm transition-colors">
              Sacar
            </button>
          )}
          {isOwner && (
            <button
              onClick={() => fetchNUI('toggleRecruiting')}
              className={`flex-1 py-1.5 rounded text-sm transition-colors ${company.is_recruiting ? 'bg-success/20 text-success' : 'bg-card-alt text-txt'}`}
            >
              {company.is_recruiting ? 'Recrutando' : 'Recrutar'}
            </button>
          )}
        </div>
      </div>

      {/* Nível da empresa */}
      <div className="bg-card rounded-lg p-4 border border-app-border">
        <div className="flex justify-between items-center mb-2">
          <p className="text-txt-light text-sm font-semibold">
            Nível {company.company_level}
            {company.company_level < 30 && (
              <span className="text-txt font-normal ml-1">
                → {company.company_level + 1}
              </span>
            )}
          </p>
          {company.xp_next > 0 ? (
            <p className="text-txt text-xs">
              {company.company_xp - company.xp_level_start} / {company.xp_next - company.xp_level_start} XP
            </p>
          ) : (
            <p className="text-gold text-xs font-medium">Nível máximo</p>
          )}
        </div>

        {/* Barra de XP — progress relativo ao nível atual */}
        {company.xp_next > 0 && (
          <div className="w-full bg-card-alt rounded-full h-1.5">
            <div
              className="bg-primary-hover h-1.5 rounded-full transition-all"
              style={{
                width: `${Math.min(100, ((company.company_xp - company.xp_level_start) / (company.xp_next - company.xp_level_start)) * 100)}%`
              }}
            />
          </div>
        )}

        {/* Perks atuais */}
        <div className="grid grid-cols-3 gap-2 mt-3 text-center">
          <div className="bg-app-bg rounded p-2">
            <p className="text-primary font-bold text-sm">{company.perks.vehicles}</p>
            <p className="text-txt-secondary text-[10px]">Veículos</p>
          </div>
          <div className="bg-app-bg rounded p-2">
            <p className="text-primary font-bold text-sm">{company.perks.members}</p>
            <p className="text-txt-secondary text-[10px]">Membros</p>
          </div>
          <div className="bg-app-bg rounded p-2">
            <p className="text-primary font-bold text-sm">
              {Number(company.perks.bonus || 1) > 1.0
                ? `+${((Number(company.perks.bonus) - 1) * 100).toFixed(0)}%`
                : '0%'}
            </p>
            <p className="text-txt-secondary text-[10px]">Bônus</p>
          </div>
        </div>
      </div>

      {/* Membros */}
      <MemberList />

      {/* Empréstimo Empresarial — visível para Owner e Manager */}
      {isManager && (
        <div>
          <p className="text-xs text-txt-secondary uppercase tracking-wider mb-2">Empréstimo</p>
          <LoanPanel isCompany={true} />
        </div>
      )}

      {/* Ações de owner */}
      {isOwner && (
        <button
          onClick={() => fetchNUI('sellCompany')}
          className="w-full py-2 text-danger bg-danger/10 hover:bg-danger/20 border border-danger/30 rounded-lg text-sm transition-colors"
        >
          Vender Empresa ($25.000)
        </button>
      )}

      {!isOwner && (
        <button
          onClick={() => fetchNUI('leaveCompany')}
          className="w-full py-2 text-txt bg-card hover:bg-card-alt border border-app-border rounded-lg text-sm transition-colors"
        >
          Sair da Empresa
        </button>
      )}

      {/* Modal Depositar */}
      {showDeposit && (
        <Modal title="Depositar na Empresa" onClose={() => setShowDeposit(false)}>
          <input
            type="number" min="1" placeholder="Valor"
            value={depositAmount} onChange={e => setDepositAmount(e.target.value)}
            className="w-full bg-app-bg border border-app-border rounded px-3 py-2 text-txt-light text-sm mb-3 focus:outline-none focus:border-primary"
          />
          <button
            onClick={() => { fetchNUI('depositMoney', { amount: Number(depositAmount) }); setShowDeposit(false) }}
            disabled={!depositAmount || Number(depositAmount) <= 0}
            className="w-full py-2 bg-primary hover:bg-primary-hover disabled:opacity-40 text-white rounded text-sm"
          >
            Confirmar
          </button>
        </Modal>
      )}

      {/* Modal Sacar */}
      {showWithdraw && (
        <Modal title="Sacar da Empresa" onClose={() => setShowWithdraw(false)}>
          <input
            type="number" min="1" placeholder="Valor"
            value={withdrawAmount} onChange={e => setWithdrawAmount(e.target.value)}
            className="w-full bg-app-bg border border-app-border rounded px-3 py-2 text-txt-light text-sm mb-3 focus:outline-none focus:border-primary"
          />
          <button
            onClick={() => { fetchNUI('withdrawMoney', { amount: Number(withdrawAmount) }); setShowWithdraw(false) }}
            disabled={!withdrawAmount || Number(withdrawAmount) <= 0}
            className="w-full py-2 bg-primary hover:bg-primary-hover disabled:opacity-40 text-white rounded text-sm"
          >
            Confirmar
          </button>
        </Modal>
      )}
    </div>
  )
}
