import { create } from 'zustand'
import type { Stats, Skills, SkillType } from '../types'
import type { LoanData } from '../types/loan'

const DEFAULT_SKILLS: Skills = { distance: 0, valuable: 0, fragile: 0, speed: 0 }

interface StatsStore {
  stats:           Stats | null
  skills:          Skills
  personalLoan:    LoanData | null
  setStats:        (stats: Stats | null) => void
  setSkills:       (skills: Partial<Skills>) => void
  setSkillLevel:   (type: SkillType, level: number) => void
  setPersonalLoan: (loan: LoanData | null) => void
}

export const useStatsStore = create<StatsStore>((set) => ({
  stats:        null,
  skills:       { ...DEFAULT_SKILLS },
  personalLoan: null,

  setStats:  (stats)  => set({ stats }),

  setSkills: (skills) => set((state) => ({
    skills: { ...state.skills, ...skills },
  })),

  setSkillLevel: (type, level) => set((state) => ({
    skills: { ...state.skills, [type]: level },
  })),

  setPersonalLoan: (loan) => set({ personalLoan: loan }),
}))
