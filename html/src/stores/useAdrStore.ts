import { create } from 'zustand'
import type { AdrCert } from '../types'

interface AdrStore {
  certs:     AdrCert[]
  setCerts:  (certs: AdrCert[]) => void
  upsertCert: (cert: AdrCert) => void
}

export const useAdrStore = create<AdrStore>((set) => ({
  certs: [],

  setCerts: (certs) => set({ certs }),

  upsertCert: (cert) =>
    set((state) => {
      const exists = state.certs.some((c) => c.adr_type === cert.adr_type)
      if (exists) {
        return { certs: state.certs.map((c) => (c.adr_type === cert.adr_type ? cert : c)) }
      }
      return { certs: [...state.certs, cert] }
    }),
}))
