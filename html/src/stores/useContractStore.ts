import { create } from 'zustand'

export interface ClientRelationship {
  id: string
  name: string
  sector: string
  sectorLabel: string
  trustLevel: number
  trustXP: number
  trustLabel: string
  bonusPercent: number
  totalDeliveries: number
  totalRevenue: number
  streak: number
  locked: boolean
  sectorReputation: number
  maxOptions: number
}

export interface ContractStop {
  stop_order: number
  location_id: string
  location_name: string
  coords_x: number
  coords_y: number
  coords_z: number
  action: 'pickup' | 'delivery'
  cargo_item: string
  cargo_qty: number
  completed: number
}

export interface ActiveContract {
  id: string
  contractType: 'simple' | 'multi'
  totalPayment: number
  bonusPercent: number
  clientId: string
  clientName: string
  stops: ContractStop[]
  currentStop: ContractStop | null
  totalStops: number
}

interface ContractStore {
  clients: ClientRelationship[]
  activeContract: ActiveContract | null
  setClients: (c: ClientRelationship[]) => void
  setActiveContract: (c: ActiveContract | null) => void
}

export const useContractStore = create<ContractStore>((set) => ({
  clients: [],
  activeContract: null,
  setClients: (clients) => set({ clients }),
  setActiveContract: (activeContract) => set({ activeContract }),
}))
