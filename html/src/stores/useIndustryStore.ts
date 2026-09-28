import { create } from 'zustand'
import type { Industry, IndustryOwnership } from '../types'

interface IndustryStore {
  industries: Record<string, Industry>
  ownedIndustries: IndustryOwnership[]
  setIndustries: (industries: Record<string, Industry>) => void
  setOwnedIndustries: (owned: IndustryOwnership[]) => void
  addOwnedIndustry: (owned: IndustryOwnership) => void
}

export const useIndustryStore = create<IndustryStore>((set) => ({
  industries: {},
  ownedIndustries: [],
  setIndustries: (industries) => set({ industries }),
  setOwnedIndustries: (ownedIndustries) => set({ ownedIndustries }),
  addOwnedIndustry: (owned) =>
    set((state) => ({ ownedIndustries: [...state.ownedIndustries, owned] })),
}))
