import { create } from 'zustand'
import type { RepoOrder } from '../types/repo'

interface RepoStore {
  repoOrders:         RepoOrder[]
  activeRepoOrder:    RepoOrder | null
  setRepoOrders:      (orders: RepoOrder[]) => void
  setActiveRepoOrder: (order: RepoOrder | null) => void
}

export const useRepoStore = create<RepoStore>((set) => ({
  repoOrders:         [],
  activeRepoOrder:    null,
  setRepoOrders:      (repoOrders)      => set({ repoOrders }),
  setActiveRepoOrder: (activeRepoOrder) => set({ activeRepoOrder }),
}))
