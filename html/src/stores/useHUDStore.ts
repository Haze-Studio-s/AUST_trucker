import { create } from 'zustand'
import type { HUDData } from '../types'

interface HUDStore {
  hud: HUDData
  setHUD: (data: HUDData) => void
}

const defaultHUD: HUDData = {
  visible:   false,
  speed:     0,
  fuel:      100,
  fatigue:   0,
  integrity: null,
  position:  'bottom-left',
}

export const useHUDStore = create<HUDStore>((set) => ({
  hud:    defaultHUD,
  setHUD: (data) => set({ hud: data }),
}))
