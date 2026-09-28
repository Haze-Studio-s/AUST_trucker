import { useState, useEffect } from 'react'
import { usePartyStore } from '../../stores/usePartyStore'
import { useJobStore } from '../../stores/useJobStore'
import { fetchNUI } from '../../hooks/useNUI'

type PanelView = 'party' | 'history'

export function PartyPanel() {
  const { party, setParty, convoyHistory } = usePartyStore()
  const { jobs } = useJobStore()
  const [view, setView]               = useState<PanelView>('party')
  const [searchName, setSearchName]   = useState('')
  const [loading, setLoading]         = useState(false)
  const [historyLoading, setHistoryLoading] = useState(false)
  const [error, setError]             = useState<string | null>(null)
  const [selectedRoute, setSelectedRoute] = useState<string | null>(null)

  // Quando o histórico chegar do servidor, desligar o loading
  useEffect(() => {
    if (historyLoading) setHistoryLoading(false)
  }, [convoyHistory])

  async function handleCreate() {
    setLoading(true)
    const result = await fetchNUI<{ success: boolean; partyId?: string; reason?: string }>('partyCreate')
    if (!result.success) setError(result.reason ?? 'Erro ao criar party')
    setLoading(false)
  }

  async function handleInvite() {
    if (!searchName.trim()) return
    setLoading(true)
    const result = await fetchNUI<{ success: boolean; reason?: string }>('partyInvite', searchName.trim())
    if (!result.success) setError(result.reason ?? 'Erro ao convidar')
    else setSearchName('')
    setLoading(false)
  }

  async function handleLeave() {
    await fetchNUI('partyLeave')
    setParty(null)
  }

  async function handleDisband() {
    await fetchNUI('partyDisband')
    setParty(null)
  }

  async function handleStartConvoy() {
    setLoading(true)
    const result = await fetchNUI<{ success: boolean; reason?: string }>('convoyStart')
    if (!result.success) setError(result.reason ?? 'Erro ao iniciar convoy')
    setLoading(false)
  }

  async function handleShowHistory() {
    setView('history')
    setHistoryLoading(true)
    await fetchNUI('getConvoyHistory')
  }

  const activeCount = party?.members.filter(m => m.online).length ?? 0

  // ── Aba de histórico ─────────────────────────────────────────────
  if (view === 'history') {
    return (
      <div className="flex flex-col gap-4">
        <div className="flex items-center gap-3">
          <button
            className="text-txt-secondary hover:text-txt-light text-sm flex items-center gap-1"
            onClick={() => setView('party')}
          >
            ← Voltar
          </button>
          <h2 className="text-lg font-semibold text-txt-light">Histórico de Convoys</h2>
        </div>

        {historyLoading ? (
          <div className="flex items-center justify-center py-8 text-txt-secondary text-sm">
            Carregando...
          </div>
        ) : convoyHistory.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-10 gap-2 text-txt-secondary">
            <span className="text-3xl">🚚</span>
            <p className="text-sm">Nenhum convoy concluído ainda.</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2 overflow-auto max-h-[60vh]">
            {/* Cabeçalho */}
            <div className="grid grid-cols-4 gap-2 px-3 text-xs text-txt-secondary uppercase tracking-wide">
              <span>Data</span>
              <span className="text-center">Membros</span>
              <span className="text-center">Bônus</span>
              <span className="text-right">Recebido</span>
            </div>

            {convoyHistory.map((row, i) => {
              const date = new Date(row.created_at)
              const dateStr = date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' })
              const timeStr = date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
              const bonusPct = Math.round((row.bonus_mult - 1) * 100)

              return (
                <div
                  key={row.convoy_id + i}
                  className="grid grid-cols-4 gap-2 items-center bg-card rounded-lg px-3 py-2.5 border border-app-border"
                >
                  <div className="flex flex-col">
                    <span className="text-txt-light text-sm">{dateStr}</span>
                    <span className="text-txt-secondary text-xs">{timeStr}</span>
                  </div>

                  <div className="flex flex-col items-center">
                    <span className="text-txt-light text-sm font-medium">
                      {row.completed_count}/{row.total_count}
                    </span>
                    <span className="text-txt-secondary text-xs">concluíram</span>
                  </div>

                  <div className="flex flex-col items-center">
                    <span className={`text-sm font-semibold ${bonusPct > 0 ? 'text-gold' : 'text-txt'}`}>
                      ×{row.bonus_mult.toFixed(2)}
                    </span>
                    {bonusPct > 0 && (
                      <span className="text-gold text-xs">+{bonusPct}%</span>
                    )}
                  </div>

                  <div className="flex flex-col items-end">
                    <span className="text-success text-sm font-bold">
                      ${row.amount.toLocaleString('pt-BR')}
                    </span>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    )
  }

  // ── Aba principal (party) ─────────────────────────────────────────
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-txt-light">Convoy</h2>
        <button
          className="text-xs text-txt-secondary hover:text-gold transition-colors"
          onClick={handleShowHistory}
          title="Ver histórico de convoys"
        >
          Histórico →
        </button>
      </div>

      {error && (
        <div className="bg-danger-dark/20 border border-danger-dark text-danger rounded px-3 py-2 text-sm">
          {error}
          <button className="ml-2 underline" onClick={() => setError(null)}>×</button>
        </div>
      )}

      {!party ? (
        <div className="flex flex-col gap-3">
          <p className="text-txt text-sm">Você não está em nenhum party.</p>
          <button
            className="bg-primary-active hover:bg-primary text-white rounded px-4 py-2 text-sm font-medium disabled:opacity-50"
            onClick={handleCreate}
            disabled={loading}
          >
            Criar Party
          </button>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {/* Convoy status */}
          {party.convoyActive && (
            <div className="bg-success-dark/20 border border-success-dark text-success rounded px-3 py-2 text-sm font-medium">
              Convoy ativo — use a tecla Z para o Rádio CB
            </div>
          )}

          {/* Lista de membros */}
          <div className="flex flex-col gap-1">
            {party.members.map(m => (
              <div
                key={m.citizenid}
                className="flex items-center gap-2 bg-card rounded px-3 py-2"
              >
                <span className={`w-2 h-2 rounded-full ${m.online ? 'bg-success' : 'bg-txt-secondary'}`} />
                <span className="text-txt-light text-sm flex-1">{m.name}</span>
                {m.isLeader && (
                  <span className="text-gold text-xs">👑 Líder</span>
                )}
                {!m.online && (
                  <span className="text-txt-secondary text-xs">offline (grace)</span>
                )}
              </div>
            ))}
          </div>

          {/* Convidar jogador — apenas líder */}
          {party.isLeader && !party.convoyActive && (
            <div className="flex gap-2">
              <input
                className="flex-1 bg-card border border-app-border text-txt-light rounded px-3 py-2 text-sm"
                placeholder="Nome do jogador..."
                value={searchName}
                onChange={e => setSearchName(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleInvite()}
              />
              <button
                className="bg-primary-active hover:bg-primary text-white rounded px-3 py-2 text-sm disabled:opacity-50"
                onClick={handleInvite}
                disabled={loading || !searchName.trim()}
              >
                Convidar
              </button>
            </div>
          )}

          {/* Rotas disponíveis — líder escolhe antes de iniciar */}
          {party.isLeader && !party.convoyActive && jobs.length > 0 && (
            <div className="flex flex-col gap-2">
              <p className="text-txt text-xs uppercase tracking-wide">Escolha a rota do Convoy</p>
              <div className="max-h-48 overflow-auto space-y-1.5">
                {jobs.map(job => (
                  <div
                    key={job.id}
                    onClick={() => setSelectedRoute(job.id)}
                    className={`bg-card rounded-lg p-2.5 border cursor-pointer transition-all ${
                      selectedRoute === job.id
                        ? 'border-primary bg-primary/10'
                        : 'border-app-border hover:border-primary/50'
                    }`}
                  >
                    <div className="flex justify-between items-start">
                      <div>
                        <p className="text-txt-light text-sm font-medium">{job.cargoItem}</p>
                        <p className="text-txt-secondary text-xs">{job.originName} → {job.destName}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-success text-sm font-semibold">${job.basePayment.toLocaleString()}</p>
                        <p className="text-txt-secondary text-xs">{job.distance.toFixed(1)} km</p>
                      </div>
                    </div>
                    <div className="flex gap-2 mt-1 text-xs text-txt-secondary">
                      <span>{job.weight ?? 80}kg</span>
                      {job.cargoQty && job.cargoQty > 1 && <span>{job.cargoQty} pacotes</span>}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Ações */}
          <div className="flex gap-2">
            {party.isLeader && !party.convoyActive && (
              <button
                className="flex-1 bg-success-dark hover:bg-success text-white rounded px-4 py-2 text-sm font-medium disabled:opacity-50"
                onClick={handleStartConvoy}
                disabled={loading || activeCount < 2}
                title={activeCount < 2 ? 'Precisa de pelo menos 2 membros online' : ''}
              >
                Iniciar Convoy ({activeCount}/{party.maxSize})
              </button>
            )}
            {party.isLeader ? (
              <button
                className="bg-danger-dark hover:bg-danger-dark text-danger rounded px-4 py-2 text-sm"
                onClick={handleDisband}
                disabled={loading}
              >
                Dissolver
              </button>
            ) : (
              <button
                className="flex-1 bg-card-alt hover:bg-hover-bg text-txt-light rounded px-4 py-2 text-sm"
                onClick={handleLeave}
                disabled={loading}
              >
                Sair do Party
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
