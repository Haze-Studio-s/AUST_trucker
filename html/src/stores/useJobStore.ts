import { create } from 'zustand'
import type { Job, ActiveJob } from '../types'

interface JobStore {
  jobs: Job[]
  activeJob: ActiveJob | null
  selectedJobId: string | null
  setJobs: (jobs: Job[]) => void
  setActiveJob: (job: ActiveJob | null) => void
  selectJob: (id: string | null) => void
}

export const useJobStore = create<JobStore>((set) => ({
  jobs: [],
  activeJob: null,
  selectedJobId: null,
  setJobs: (jobs) => set({ jobs }),
  setActiveJob: (activeJob) => set({ activeJob }),
  selectJob: (selectedJobId) => set({ selectedJobId }),
}))
