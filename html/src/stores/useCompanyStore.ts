import { create } from 'zustand'
import type { Company, Member, Vehicle } from '../types'
import type { LoanData } from '../types/loan'

interface CompanyStore {
  company: Company | null
  members: Member[]
  vehicles: Vehicle[]
  recruitingList: Company[]
  companyLoan: LoanData | null
  setCompany: (company: Company | null) => void
  setMembers: (members: Member[]) => void
  setVehicles: (vehicles: Vehicle[]) => void
  setRecruitingList: (list: Company[]) => void
  setCompanyLoan: (loan: LoanData | null) => void
}

export const useCompanyStore = create<CompanyStore>((set) => ({
  company: null,
  members: [],
  vehicles: [],
  recruitingList: [],
  companyLoan: null,
  setCompany: (company) => set({ company }),
  setMembers: (members) => set({ members }),
  setVehicles: (vehicles) => set({ vehicles }),
  setRecruitingList: (recruitingList) => set({ recruitingList }),
  setCompanyLoan: (loan) => set({ companyLoan: loan }),
}))
