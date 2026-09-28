import { useEffect } from 'react'
import { useAppStore } from '../stores/useAppStore'
import { useJobStore } from '../stores/useJobStore'
import { useCompanyStore } from '../stores/useCompanyStore'
import { useIndustryStore } from '../stores/useIndustryStore'
import { useStatsStore } from '../stores/useStatsStore'
import { useRepoStore } from '../stores/useRepoStore'
import { useHUDStore } from '../stores/useHUDStore'
import { usePartyStore } from '../stores/usePartyStore'
import { useNpcDriverStore } from '../stores/useNpcDriverStore'
import { useAdrStore } from '../stores/useAdrStore'
import { useContractStore } from '../stores/useContractStore'
import type { ClientRelationship, ActiveContract } from '../stores/useContractStore'
import type { Job, ActiveJob, Company, Member, Vehicle, Industry, IndustryOwnership, Stats, Skills, Party, NpcGraveEvent, NpcDriver, NpcDriverData, AdrCert, ConvoyPayment, RentalTruck, ActiveRental } from '../types'
import type { LoanData } from '../types/loan'
import type { RepoOrder } from '../types/repo'

const ADR_LABELS: Record<string, string> = {
  flammable_liquid: 'Líquidos Inflamáveis',
  flammable_gas:    'Gases Inflamáveis',
  toxic:            'Substâncias Tóxicas',
  corrosive:        'Substâncias Corrosivas',
  explosive:        'Explosivos',
  environmental:    'Perigosas ao Meio Ambiente',
}

interface NUIMessage {
  action:               string
  jobs?:                Job[]
  company?:             Company | null
  activeJob?:           ActiveJob | null
  stats?:               Stats | null
  skills?:              Partial<Skills>
  recruitingCompanies?: Company[]
  members?:             Member[]
  vehicles?:            Vehicle[]
  industries?:          Record<string, Industry>
  ownedIndustries?:     IndustryOwnership[]
  refreshStats?:        boolean
  // Loans
  loan?:                LoanData
  personalLoan?:        LoanData | null
  companyLoan?:         LoanData | null
  // Repo
  repoOrders?:          RepoOrder[]
  activeRepoOrder?:     RepoOrder | null
  repoOrder?:           RepoOrder
  payment?:             number
  // HUD — campos enviados pelo Lua no nível raiz do payload (não aninhados)
  visible?:   boolean
  speed?:     number
  fuel?:      number
  fatigue?:   number
  integrity?: number | null
  position?:  string
  // Party / Convoy
  party?:               Party | null
  currentParty?:        Party | null
  // NPC Drivers
  npcDrivers?:          NpcDriverData | null
  event?:               NpcGraveEvent
  eventId?:             string
  driverId?:            string
  drivers?:             NpcDriver[]
  // ADR
  adrCerts?:            AdrCert[]
  adrType?:             string
  expiresAt?:           number
  // Contracts
  clients?:             ClientRelationship[]
  activeContract?:      ActiveContract | null
  contract?:            ActiveContract | null
  // Company History
  history?:             unknown
  // Convoy History
  convoyHistory?:       ConvoyPayment[]
  // Profile & Rental
  playerName?:          string
  playerMoney?:         number
  rentalTrucks?:        RentalTruck[]
  activeRental?:        ActiveRental | null
}

export function useNUI() {
  const { setOpen, setTab, setPlayerProfile, setRentalTrucks, setActiveRental } = useAppStore()
  const { setJobs, setActiveJob }                                      = useJobStore()
  const { setCompany, setRecruitingList, setMembers, setVehicles, setCompanyLoan } = useCompanyStore()
  const { setIndustries, setOwnedIndustries }                         = useIndustryStore()
  const { setStats, setSkills, setPersonalLoan }                       = useStatsStore()
  const { setRepoOrders, setActiveRepoOrder }                          = useRepoStore()
  const { setHUD }                                                     = useHUDStore()
  const { setParty, setConvoyActive, setConvoyHistory }                = usePartyStore()
  const { setDrivers, setProfiles, setReputation, setAllowIllegal, setPendingEvent, removeDriver } = useNpcDriverStore()
  const { setCerts, upsertCert } = useAdrStore()
  const { setClients, setActiveContract } = useContractStore()

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' || e.keyCode === 27) {
        setOpen(false)
        fetchNUI('closeUI', {}).catch(() => {})
        fetchNUI('close', {}).catch(() => {})
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [setOpen])

  useEffect(() => {
    const handler = (event: MessageEvent<NUIMessage>) => {
      const { action } = event.data
      switch (action) {
        case 'open': {
          const openCompany = event.data.company ?? null
          setJobs(event.data.jobs ?? [])
          setCompany(openCompany)
          setActiveJob(event.data.activeJob ?? null)
          setStats(event.data.stats ?? null)
          if (event.data.playerName !== undefined || event.data.playerMoney !== undefined) {
            setPlayerProfile(event.data.playerName || 'Motorista', event.data.playerMoney ?? 0)
          } else if (event.data.stats?.name) {
            setPlayerProfile(event.data.stats.name, event.data.stats.money ?? 0)
          }
          if (event.data.rentalTrucks) {
            setRentalTrucks(event.data.rentalTrucks)
          }
          if (event.data.activeRental !== undefined) {
            setActiveRental(event.data.activeRental)
          }
          setRecruitingList(event.data.recruitingCompanies ?? [])
          if (event.data.skills) setSkills(event.data.skills)
          setPersonalLoan(event.data.personalLoan ?? null)
          setCompanyLoan(event.data.companyLoan ?? null)
          setRepoOrders(event.data.repoOrders ?? [])
          setActiveRepoOrder(event.data.activeRepoOrder ?? null)
          setOwnedIndustries(event.data.ownedIndustries ?? [])
          setParty(event.data.currentParty ?? null)
          if (event.data.npcDrivers) {
            setDrivers(event.data.npcDrivers.drivers ?? [])
            setProfiles(event.data.npcDrivers.profiles ?? [])
            setReputation(event.data.npcDrivers.reputation ?? 100)
            setAllowIllegal(event.data.npcDrivers.allowIllegal ?? false)
          }
          if (event.data.adrCerts) setCerts(event.data.adrCerts)
          setClients(event.data.clients ?? [])
          setActiveContract(event.data.activeContract ?? null)
          setTab(openCompany?.company_type === 'repo' ? 'missions' : 'jobs')
          setOpen(true)
          break
        }
        case 'close':
          setOpen(false)
          break
        case 'updateJobs':
          setJobs(event.data.jobs ?? [])
          break
        case 'updateActiveJob':
          setActiveJob(event.data.activeJob ?? null)
          break
        case 'updateCompany': {
          const updatedCompany = event.data.company ?? null
          setCompany(updatedCompany)
          setTab(updatedCompany?.company_type === 'repo' ? 'missions' : 'jobs')
          break
        }
        case 'updateMembers':
          setMembers(event.data.members ?? [])
          break
        case 'updateVehicles':
          setVehicles(event.data.vehicles ?? [])
          break
        case 'updateRental':
          setActiveRental(event.data.activeRental ?? null)
          break
        case 'updateStats':
          setStats(event.data.stats ?? null)
          break
        case 'updateSkills':
          if (event.data.skills) setSkills(event.data.skills)
          break
        case 'updateCompanyHistory':
          window.dispatchEvent(new CustomEvent('companyHistory', { detail: event.data.history }))
          break
        case 'updateConvoyHistory':
          setConvoyHistory(event.data.convoyHistory ?? [])
          break
        case 'updateIndustries':
          setIndustries(event.data.industries ?? {})
          break
        case 'updateLoan': {
          const loan = event.data.loan
          if (!loan) break
          if (loan.is_company_loan) {
            setCompanyLoan(loan)
          } else {
            setPersonalLoan(loan)
          }
          break
        }
        case 'updateRepoOrders':
          setRepoOrders(event.data.repoOrders ?? [])
          break
        case 'startRepoMission':
          setActiveRepoOrder(event.data.repoOrder ?? null)
          break
        case 'repoMissionComplete':
          setActiveRepoOrder(null)
          break
        case 'partyUpdate':
          setParty(event.data.party ?? null)
          break
        case 'convoyStarted':
          setConvoyActive(true)
          break
        case 'convoyEnded':
          setConvoyActive(false)
          break
        case 'updateHUD':
          setHUD({
            visible:   event.data.visible   ?? false,
            speed:     event.data.speed     ?? 0,
            fuel:      event.data.fuel      ?? 100,
            fatigue:   event.data.fatigue   ?? 0,
            integrity: event.data.integrity ?? null,
            position:  event.data.position  ?? 'bottom-left',
          })
          break
        case 'npcGraveEvent':
          if (event.data.event) setPendingEvent(event.data.event)
          break
        case 'npcEventResolved':
          setPendingEvent(null)
          break
        case 'npcDriverQuit':
          if (event.data.driverId) removeDriver(event.data.driverId)
          break
        case 'updateNpcDrivers':
          if (event.data.drivers) setDrivers(event.data.drivers)
          break
        case 'adrCertGranted': {
          const { adrType, expiresAt } = event.data
          if (adrType !== undefined && expiresAt !== undefined) {
            upsertCert({ adr_type: adrType, expires_at: expiresAt, label: ADR_LABELS[adrType] ?? adrType })
          }
          break
        }
        case 'contractStarted':
          setActiveContract(event.data.contract ?? null)
          break
        case 'contractStopCompleted':
          setActiveContract(event.data.contract ?? null)
          break
        case 'contractCompleted':
          setActiveContract(null)
          break
      }
    }
    window.addEventListener('message', handler)
    return () => {
      window.removeEventListener('message', handler)
    }
  }, [])
}

// Nome do resource — GetParentResourceName() existe no NUI browser do FiveM
const RESOURCE_NAME =
  (typeof (window as any).GetParentResourceName === 'function'
    ? (window as any).GetParentResourceName()
    : 'aust_trucker') as string

// Utilitário: chama endpoint Lua via NUI fetch
export async function fetchNUI<T = unknown>(
  endpoint: string,
  data?: unknown
): Promise<T> {
  try {
    const response = await fetch(`https://${RESOURCE_NAME}/${endpoint}`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(data ?? {}),
    })
    return await response.json() as T
  } catch {
    return 'ok' as T
  }
}
