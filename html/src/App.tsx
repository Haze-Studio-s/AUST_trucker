import { useNUI } from './hooks/useNUI'
import { useAppStore } from './stores/useAppStore'
import { useCompanyStore } from './stores/useCompanyStore'
import { LationHeader } from './components/layout/LationHeader'
import { TabBar } from './components/layout/TabBar'
import { FooterActions } from './components/layout/FooterActions'
import { JobList } from './components/jobs/JobList'
import { ActiveJob } from './components/jobs/ActiveJob'
import { CompanySetup } from './components/company/CompanySetup'
import { CompanyPanel } from './components/company/CompanyPanel'
import { GaragePanel } from './components/garage/GaragePanel'
import { IndustryList } from './components/industries/IndustryList'
import { StatsPanel } from './components/stats/StatsPanel'
import { RepoPanel } from './components/repo/RepoPanel'
import { TruckHUD } from './components/hud/TruckHUD'
import { PartyPanel } from './components/convoy/PartyPanel'
import { NpcDriverPanel } from './components/company/NpcDriverPanel'
import { NpcEventAlert } from './components/overlay/NpcEventAlert'
import { AdrPanel } from './components/adr/AdrPanel'

export default function App() {
  useNUI()

  const { isOpen, activeTab } = useAppStore()
  const { company } = useCompanyStore()

  if (!isOpen) return null

  return (
    <>
      <TruckHUD />
      <NpcEventAlert />

      <div className="fixed inset-0 flex items-center justify-center pointer-events-none bg-black/65 backdrop-blur-[2px] z-40 select-none">
        <div className="pointer-events-auto w-[88vw] max-w-[1360px] h-[86vh] bg-lation-surface rounded-xl border border-lation-line shadow-lation-panel flex flex-col overflow-hidden animate-fadeIn">
          {/* Header Superior com Perfil do Motorista */}
          <LationHeader />

          {/* Abas Técnicas de Navegação */}
          <TabBar />

          {/* Área Principal de Conteúdo */}
          <main className="flex-1 overflow-y-auto p-5 bg-lation-surface">
            {activeTab === 'jobs'       && <JobList />}
            {activeTab === 'garage'     && <GaragePanel />}
            {activeTab === 'missions'   && <RepoPanel />}
            {activeTab === 'active'     && <ActiveJob />}
            {activeTab === 'company'    && (company ? <CompanyPanel /> : <CompanySetup />)}
            {activeTab === 'industries' && <IndustryList />}
            {activeTab === 'stats'      && <StatsPanel />}
            {activeTab === 'convoy'     && <PartyPanel />}
            {activeTab === 'drivers'    && <NpcDriverPanel />}
            {activeTab === 'adr'        && <AdrPanel />}
          </main>

          {/* Rodapé com Atalhos e Ações Rápidas */}
          <FooterActions />
        </div>
      </div>
    </>
  )
}
