import { create } from 'zustand'
import type { TabName } from '../types'

interface AppStore {
  isOpen: boolean
  activeTab: TabName
  setOpen: (v: boolean) => void
  setTab: (tab: TabName) => void
}

export const useAppStore = create<AppStore>((set) => ({
  isOpen: false,
  activeTab: 'jobs',
  setOpen: (isOpen) => set({ isOpen }),
  setTab: (activeTab) => set({ activeTab }),
}))
