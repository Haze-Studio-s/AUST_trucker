import { create } from 'zustand'
import type { NpcDriver, AgencyProfile, NpcGraveEvent } from '../types'

interface NpcDriverStore {
  drivers:      NpcDriver[]
  profiles:     AgencyProfile[]
  reputation:   number
  allowIllegal: boolean
  pendingEvent: NpcGraveEvent | null

  setDrivers:      (drivers: NpcDriver[]) => void
  setProfiles:     (profiles: AgencyProfile[]) => void
  setReputation:   (rep: number) => void
  setAllowIllegal: (allow: boolean) => void
  setPendingEvent: (event: NpcGraveEvent | null) => void
  removeDriver:    (driverId: string) => void
  updateDriver:    (updated: NpcDriver) => void
}

export const useNpcDriverStore = create<NpcDriverStore>((set) => ({
  drivers:      [],
  profiles:     [],
  reputation:   100,
  allowIllegal: false,
  pendingEvent: null,

  setDrivers:      (drivers) => set({ drivers }),
  setProfiles:     (profiles) => set({ profiles }),
  setReputation:   (reputation) => set({ reputation }),
  setAllowIllegal: (allowIllegal) => set({ allowIllegal }),
  setPendingEvent: (pendingEvent) => set({ pendingEvent }),
  removeDriver:    (driverId) =>
    set((state) => ({ drivers: state.drivers.filter((d) => d.id !== driverId) })),
  updateDriver: (updated) =>
    set((state) => ({
      drivers: state.drivers.map((d) => (d.id === updated.id ? updated : d)),
    })),
}))
