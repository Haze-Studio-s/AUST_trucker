import { create } from 'zustand'
import type { TabName, RentalTruck, ActiveRental } from '../types'

interface AppStore {
  isOpen: boolean
  activeTab: TabName
  playerName: string
  playerMoney: number
  rentalTrucks: RentalTruck[]
  activeRental: ActiveRental | null
  setOpen: (v: boolean) => void
  setTab: (tab: TabName) => void
  setPlayerProfile: (name: string, money: number) => void
  setRentalTrucks: (trucks: RentalTruck[]) => void
  setActiveRental: (rental: ActiveRental | null) => void
}

export const useAppStore = create<AppStore>((set) => ({
  isOpen: false,
  activeTab: 'jobs',
  playerName: 'Motorista',
  playerMoney: 0,
  rentalTrucks: [],
  activeRental: null,
  setOpen: (isOpen) => set({ isOpen }),
  setTab: (activeTab) => set({ activeTab }),
  setPlayerProfile: (playerName, playerMoney) => set({ playerName, playerMoney }),
  setRentalTrucks: (rentalTrucks) => set({ rentalTrucks }),
  setActiveRental: (activeRental) => set({ activeRental }),
}))
