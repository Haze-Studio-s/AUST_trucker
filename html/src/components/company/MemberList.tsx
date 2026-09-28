import { useEffect } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'
import type { Member } from '../../types'

const ROLE_LABEL: Record<string, string> = { owner: 'Owner', manager: 'Gerente', driver: 'Motorista' }

export function MemberList() {
  const { company, members, setMembers } = useCompanyStore()

  useEffect(() => {
    if (!company) return
    fetchNUI<Member[]>('getCompanyMembers', { companyId: company.id })
      .then(data => setMembers(data ?? []))
  }, [company?.id])

  return (
    <div className="bg-card rounded-lg p-3 border border-app-border">
      <h4 className="text-txt text-xs uppercase tracking-wide mb-2">Membros ({members.length})</h4>
      <div className="space-y-1.5">
        {members.map(m => (
          <div key={m.citizenid} className="flex justify-between items-center">
            <span className="text-txt text-sm">{m.citizenid.slice(0, 12)}…</span>
            <div className="flex items-center gap-2">
              <span className="text-txt-secondary text-xs">{ROLE_LABEL[m.role] ?? m.role}</span>
              {company?.role === 'owner' && m.role !== 'owner' && (
                <button
                  onClick={() => fetchNUI('kickMember', { citizenId: m.citizenid })}
                  className="text-danger hover:text-danger text-xs transition-colors"
                >
                  Kick
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
