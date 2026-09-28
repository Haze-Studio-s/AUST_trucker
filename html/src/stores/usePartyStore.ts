import { create } from 'zustand'
import type { Party, PartyMember, ConvoyPayment } from '../types'

interface PartyStore {
  party:              Party | null
  convoyHistory:      ConvoyPayment[]
  setParty:           (party: Party | null) => void
  updateMembers:      (members: PartyMember[]) => void
  setConvoyActive:    (active: boolean) => void
  setConvoyHistory:   (history: ConvoyPayment[]) => void
}

export const usePartyStore = create<PartyStore>((set) => ({
  party:         null,
  convoyHistory: [],

  setParty: (party) => set({ party }),

  updateMembers: (members) => set((state) => ({
    party: state.party ? { ...state.party, members } : null,
  })),

  setConvoyActive: (convoyActive) => set((state) => ({
    party: state.party ? { ...state.party, convoyActive } : null,
  })),

  setConvoyHistory: (history) => set({ convoyHistory: history }),
}))
