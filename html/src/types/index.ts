export interface Job {
  id: string
  originName: string
  destName: string
  cargoItem: string
  trailerModel: string
  basePayment: number
  distance: number
  weight?: number     // peso da carga em kg
  expiresAt: number  // Unix timestamp (seconds)
  cargoQty?: number  // 1-6 pacotes, default 1
}

export interface ActiveJob extends Job {
  acceptedAt: number  // Unix timestamp (seconds)
  stage: 'pickup' | 'delivering'
  distanceRemaining?: number
}

export interface CompanyPerks {
  vehicles: number
  members: number
  bonus: number
}

export interface Company {
  id: string
  name: string
  balance: number
  is_recruiting: number
  owner_citizenid: string
  role: 'owner' | 'manager' | 'driver'
  company_type: 'logistics' | 'repo'
  company_level: number
  company_xp: number
  xp_next: number         // XP required for next level (0 if at max level 30)
  xp_level_start: number  // XP threshold of the current level (for bar calculation)
  perks: CompanyPerks
}

export interface Member {
  citizenid: string
  company_id: string
  role: 'owner' | 'manager' | 'driver'
  joined_at: string
}

export interface Vehicle {
  plate: string
  model: string
  vehicle_type: string
  status: 'stored' | 'out'
}

export interface Industry {
  id: string
  name: string
  industryType: 'primary' | 'secondary' | 'tertiary'
  coords?: { x: number; y: number; z: number }
  production: IndustryProduct | null
  consumption: IndustryProduct[]
  ownedByCompanyId?:   string | null
  ownedByCompanyName?: string | null
}

export interface IndustryOwnership {
  industryId:      string
  industryName:    string
  purchasePrice:   number
  totalEarned:     number
  productionLevel: number
  npcWorkers:      number
}

export interface IndustryProduct {
  product: string
  item: string
  price: number
  currentStock: number
  maxStock: number
  unit: string
  productionPerHour?: number
  consumptionPerHour?: number
}

// Tipo de skill disponível
export type SkillType = 'distance' | 'valuable' | 'fragile' | 'speed'

// Mapa de skills (ausente = nível 0)
export interface Skills {
  distance: number
  valuable: number
  fragile:  number
  speed:    number
}

// Stats completas (reflete trucker_player_progression)
export interface Stats {
  citizenid:        string
  level:            number
  xp:               number
  rank:             number
  reputation:       number
  skill_points:     number
  total_earnings:   number
  total_deliveries: number
  total_distance:   number
}

export interface PartyMember {
  citizenid: string
  name:      string
  isLeader:  boolean
  online:    boolean
}

export interface Party {
  partyId:      string
  isLeader:     boolean
  members:      PartyMember[]
  convoyActive: boolean
  maxSize:      number
}

export interface ConvoyPayment {
  convoy_id:       string
  amount:          number
  bonus_mult:      number
  completed_count: number
  total_count:     number
  created_at:      string
}

export type TabName = 'jobs' | 'missions' | 'active' | 'company' | 'garage' | 'industries' | 'stats' | 'convoy' | 'drivers' | 'adr'

export interface AdrCert {
  adr_type:   string
  expires_at: number   // Unix timestamp (seconds); 0 if not owned
  label:      string
}

// ============================================================
// NPC DRIVERS (v10.0.0)
// ============================================================

export type SkillLevel = 'junior' | 'pleno' | 'senior'
export type DriverStatus = 'idle' | 'working' | 'resting' | 'fired' | 'quit'
export type DemandType = 'salary_raise' | 'better_vehicle' | 'rest_day' | 'profit_share'

export interface NpcDriver {
  id: string
  name: string
  skill_level: SkillLevel
  salary: number
  satisfaction: number
  xp: number
  tenure_days: number
  total_earnings: number
  status: DriverStatus
  active_job_id?: string | null
  demand?: { type: DemandType; value?: number; expiresAt: number }
  activeJob?: { origin_id: string; dest_id: string; expected_end_at: number }
}

export interface AgencyProfile {
  index: number
  name: string
  skillLevel: SkillLevel
  salary: number
  hireCost: number
}

export interface NpcGraveEvent {
  eventId: string
  driverId: string
  driverName: string
  type: 'major_accident' | 'cargo_stolen' | 'contraband_caught'
  repairCost?: number
  bribeAmount?: number
  expiresAt: number
}

export interface NpcDriverData {
  drivers: NpcDriver[]
  profiles: AgencyProfile[]
  reputation: number
  allowIllegal: boolean
}

export interface HUDData {
  visible:   boolean
  speed:     number
  fuel:      number        // 0–100
  fatigue:   number        // 0–100
  integrity: number | null // 0–100 com job ativo, null sem job
  position:  string        // 'bottom-left' | 'bottom-right' | 'top-left' | 'top-right'
}
