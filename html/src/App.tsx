import { useNUI } from './hooks/useNUI'
import { useAppStore } from './stores/useAppStore'
import { useCompanyStore } from './stores/useCompanyStore'
import { TabBar } from './components/layout/TabBar'
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
      <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
        <div className="pointer-events-auto w-[90vw] max-w-[1400px] h-[85vh] bg-app-bg rounded-lg border border-app-border shadow-[0_1px_20px_rgba(0,0,0,0.1)] flex flex-col overflow-hidden">
          <TabBar />
          <div className="flex-1 overflow-auto p-4">
            {activeTab === 'jobs'       && <JobList />}
            {activeTab === 'missions'   && <RepoPanel />}
            {activeTab === 'active'     && <ActiveJob />}
            {activeTab === 'company'    && (company ? <CompanyPanel /> : <CompanySetup />)}
            {activeTab === 'garage'     && <GaragePanel />}
            {activeTab === 'industries' && <IndustryList />}
            {activeTab === 'stats'      && <StatsPanel />}
            {activeTab === 'convoy'     && <PartyPanel />}
            {activeTab === 'drivers'    && <NpcDriverPanel />}
            {activeTab === 'adr'        && <AdrPanel />}
          </div>
        </div>
      </div>
    </>
  )
}
