# AUST_trucker — Fase 3: React UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Substituir a NUI vanilla JS (~3000 linhas) por uma interface React + TypeScript + Vite + Tailwind, com stores Zustand por domínio, preservando todas as funcionalidades existentes.

**Architecture:** Fase 3 de 3. Pré-requisito: Fase 2 concluída (services + callbacks funcionando). A pasta `html/` é completamente substituída. O `client/ui.lua` mantém os `RegisterNUICallback` existentes — apenas o front-end muda.

**Tech Stack:** React 18, TypeScript 5, Vite 5, Tailwind CSS 3, Zustand 4, clsx

---

## Estrutura Final da NUI

```
html/
├── index.html
├── package.json
├── vite.config.ts
├── tsconfig.json
├── tailwind.config.ts
├── postcss.config.js
└── src/
    ├── main.tsx
    ├── App.tsx
    ├── index.css
    ├── hooks/
    │   └── useNUI.ts
    ├── stores/
    │   ├── useAppStore.ts
    │   ├── useJobStore.ts
    │   ├── useCompanyStore.ts
    │   ├── useIndustryStore.ts
    │   └── useStatsStore.ts
    ├── types/
    │   └── index.ts
    └── components/
        ├── layout/
        │   ├── TabBar.tsx
        │   └── Modal.tsx
        ├── jobs/
        │   ├── JobList.tsx
        │   ├── JobCard.tsx
        │   └── ActiveJob.tsx
        ├── company/
        │   ├── CompanySetup.tsx
        │   ├── CompanyPanel.tsx
        │   └── MemberList.tsx
        ├── garage/
        │   └── GaragePanel.tsx
        ├── industries/
        │   └── IndustryList.tsx
        └── stats/
            └── StatsPanel.tsx
```

## Design Visual (Tailwind tokens)

```
bg-zinc-900     → fundo principal
bg-zinc-800     → cards e painéis
bg-zinc-700     → hover states
border-zinc-700 → bordas
text-zinc-100   → texto primário
text-zinc-400   → texto secundário
blue-500        → ações primárias, badge de job
green-500       → entrega ativa, sucesso
red-500         → urgente (<5min), erro
amber-500       → aviso (<15min)
```

## Comunicação Lua ↔ React

```
Lua → React:  SendNUIMessage({ action, ...data })
React → Lua:  fetch('https://AUST_trucker/<endpoint>', { method:'POST', body: JSON })
```

**Todas as ações possíveis (Lua → React):**
`open`, `close`, `updateJobs`, `updateActiveJob`, `updateCompany`,
`updateMembers`, `updateVehicles`, `updateStats`, `updateIndustries`, `notify`

---

## Task 1: Scaffold do projeto Vite + React + TypeScript + Tailwind

**Files:**
- Modify: `html/` (substituir conteúdo existente)
- Create: `html/package.json`, `html/vite.config.ts`, `html/tailwind.config.ts`, `html/tsconfig.json`, `html/postcss.config.js`

- [x] **Passo 1: Atualizar fxmanifest.lua ANTES de remover arquivos antigos**

Atualizar o bloco `files {}` no fxmanifest ANTES de deletar os arquivos, para evitar erro de resource durante a transição:

```lua
files {
    'html/index.html',
    'html/assets/*.js',
    'html/assets/*.css',
}
```

Depois remover os arquivos antigos:
```bash
rm html/style_new.css html/script.js
# Manter apenas html/index.html (será substituído pelo build na Task 4)
```

- [x] **Passo 2: Criar html/package.json**

```json
{
  "name": "aurp-trucker-ui",
  "private": true,
  "version": "3.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "zustand": "^4.5.4",
    "clsx": "^2.1.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.40",
    "tailwindcss": "^3.4.7",
    "typescript": "^5.5.3",
    "vite": "^5.3.4"
  }
}
```

- [x] **Passo 3: Criar html/vite.config.ts**

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: '.',
    emptyOutDir: false,
    rollupOptions: {
      output: {
        assetFileNames: 'assets/[name]-[hash][extname]',
        chunkFileNames: 'assets/[name]-[hash].js',
        entryFileNames: 'assets/[name]-[hash].js',
      },
    },
  },
})
```

- [x] **Passo 4: Criar html/tailwind.config.ts**

```typescript
import type { Config } from 'tailwindcss'

export default {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {},
  },
  plugins: [],
} satisfies Config
```

- [x] **Passo 5: Criar html/postcss.config.js**

```javascript
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
```

- [x] **Passo 6: Criar html/tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"]
}
```

- [x] **Passo 7: Criar html/index.html**

```html
<!DOCTYPE html>
<html lang="pt-BR">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>AURP Trucker</title>
  </head>
  <body class="bg-transparent">
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [x] **Passo 8: Instalar dependências**

```bash
cd html && npm install
```

- [x] **Passo 9: Verificar instalação**

```bash
cd html && npm list --depth=0
```
Esperado: ver react, react-dom, zustand, clsx listados.

> **Nota:** NÃO executar `npm run build` aqui — o build script roda `tsc && vite build`, e o `tsconfig.json` aponta para `src/` que ainda não existe, então `tsc` vai falhar com "No inputs were found". O build completo será feito na Task 4 (após `App.tsx` existir) e na Task 5 (após os componentes de Jobs).

- [x] **Passo 10: Commit**

```bash
cd ..
git add html/package.json html/vite.config.ts html/tailwind.config.ts html/tsconfig.json html/postcss.config.js html/index.html
git commit -m "chore: scaffold Vite + React + TypeScript + Tailwind in html/"
```

---

## Task 2: Types, useNUI hook e fetchNUI

**Files:**
- Create: `html/src/types/index.ts`
- Create: `html/src/hooks/useNUI.ts`
- Create: `html/src/index.css`
- Create: `html/src/main.tsx`

- [x] **Passo 1: Criar html/src/types/index.ts**

```typescript
export interface Job {
  id: string
  originName: string
  destName: string
  cargoItem: string
  trailerModel: string
  basePayment: number
  distance: number
  expiresAt: number  // Unix timestamp (seconds)
}

export interface ActiveJob extends Job {
  acceptedAt: number  // Unix timestamp (seconds)
  stage: 'pickup' | 'delivering'
  distanceRemaining?: number
}

export interface Company {
  id: string
  name: string
  balance: number
  is_recruiting: number
  owner_citizenid: string
  role: 'owner' | 'manager' | 'driver'
}

export interface Member {
  citizenid: string
  company_id: string
  role: 'owner' | 'manager' | 'driver'
  joined_at: string
}

export interface Vehicle {
  plate: string
  model: string
  vehicle_type: string
  status: 'stored' | 'out'
}

export interface Industry {
  id: string
  name: string
  industryType: 'primary' | 'secondary' | 'tertiary'
  production: IndustryProduct | null
  consumption: IndustryProduct[]
}

export interface IndustryProduct {
  product: string
  item: string
  price: number
  currentStock: number
  maxStock: number
  unit: string
  productionPerHour?: number
  consumptionPerHour?: number
}

export interface Stats {
  citizenid: string
  total_earnings: number
  total_deliveries: number
  total_distance: number
}

export type TabName = 'jobs' | 'active' | 'company' | 'garage' | 'industries' | 'stats'
```

- [x] **Passo 2: Criar html/src/hooks/useNUI.ts**

```typescript
import { useEffect } from 'react'
import { useAppStore } from '../stores/useAppStore'
import { useJobStore } from '../stores/useJobStore'
import { useCompanyStore } from '../stores/useCompanyStore'
import { useIndustryStore } from '../stores/useIndustryStore'
import { useStatsStore } from '../stores/useStatsStore'
import type { Job, ActiveJob, Company, Member, Vehicle, Industry, Stats } from '../types'

interface NUIMessage {
  action: string
  jobs?: Job[]
  company?: Company | null
  activeJob?: ActiveJob | null
  stats?: Stats | null
  recruitingCompanies?: Company[]
  members?: Member[]
  vehicles?: Vehicle[]
  industries?: Record<string, Industry>
}

export function useNUI() {
  const { setOpen } = useAppStore()
  const { setJobs, setActiveJob } = useJobStore()
  const { setCompany, setRecruitingList, setMembers, setVehicles } = useCompanyStore()
  const { setIndustries } = useIndustryStore()
  const { setStats } = useStatsStore()

  useEffect(() => {
    const handler = (event: MessageEvent<NUIMessage>) => {
      const { action } = event.data
      switch (action) {
        case 'open':
          setJobs(event.data.jobs ?? [])
          setCompany(event.data.company ?? null)
          setActiveJob(event.data.activeJob ?? null)
          setStats(event.data.stats ?? null)
          setRecruitingList(event.data.recruitingCompanies ?? [])
          setOpen(true)
          break
        case 'close':
          setOpen(false)
          break
        case 'updateJobs':
          setJobs(event.data.jobs ?? [])
          break
        case 'updateActiveJob':
          setActiveJob(event.data.activeJob ?? null)
          break
        case 'updateCompany':
          setCompany(event.data.company ?? null)
          break
        case 'updateMembers':
          setMembers(event.data.members ?? [])
          break
        case 'updateVehicles':
          setVehicles(event.data.vehicles ?? [])
          break
        case 'updateStats':
          setStats(event.data.stats ?? null)
          break
        case 'updateIndustries':
          setIndustries(event.data.industries ?? {})
          break
      }
    }
    window.addEventListener('message', handler)
    return () => window.removeEventListener('message', handler)
  }, [])
}

// Utilitário: chama endpoint Lua via NUI fetch
export async function fetchNUI<T = unknown>(
  endpoint: string,
  data?: unknown
): Promise<T> {
  const response = await fetch(`https://AUST_trucker/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data ?? {}),
  })
  return response.json() as Promise<T>
}
```

- [x] **Passo 3: Criar html/src/index.css**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  background: transparent;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
}

::-webkit-scrollbar {
  width: 4px;
}
::-webkit-scrollbar-track {
  background: #27272a;
}
::-webkit-scrollbar-thumb {
  background: #52525b;
  border-radius: 2px;
}
```

- [x] **Passo 4: Criar html/src/main.tsx**

```typescript
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
```

- [x] **Passo 5: Commit**

```bash
git add html/src/
git commit -m "feat: add NUI types, useNUI hook, fetchNUI utility"
```

---

## Task 3: Stores Zustand

**Files:**
- Create: `html/src/stores/useAppStore.ts`
- Create: `html/src/stores/useJobStore.ts`
- Create: `html/src/stores/useCompanyStore.ts`
- Create: `html/src/stores/useIndustryStore.ts`
- Create: `html/src/stores/useStatsStore.ts`

- [x] **Passo 1: Criar todos os stores**

**`html/src/stores/useAppStore.ts`**
```typescript
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
```

**`html/src/stores/useJobStore.ts`**
```typescript
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
```

**`html/src/stores/useCompanyStore.ts`**
```typescript
import { create } from 'zustand'
import type { Company, Member, Vehicle } from '../types'

interface CompanyStore {
  company: Company | null
  members: Member[]
  vehicles: Vehicle[]
  recruitingList: Company[]
  setCompany: (company: Company | null) => void
  setMembers: (members: Member[]) => void
  setVehicles: (vehicles: Vehicle[]) => void
  setRecruitingList: (list: Company[]) => void
}

export const useCompanyStore = create<CompanyStore>((set) => ({
  company: null,
  members: [],
  vehicles: [],
  recruitingList: [],
  setCompany: (company) => set({ company }),
  setMembers: (members) => set({ members }),
  setVehicles: (vehicles) => set({ vehicles }),
  setRecruitingList: (recruitingList) => set({ recruitingList }),
}))
```

**`html/src/stores/useIndustryStore.ts`**
```typescript
import { create } from 'zustand'
import type { Industry } from '../types'

interface IndustryStore {
  industries: Record<string, Industry>
  setIndustries: (industries: Record<string, Industry>) => void
}

export const useIndustryStore = create<IndustryStore>((set) => ({
  industries: {},
  setIndustries: (industries) => set({ industries }),
}))
```

**`html/src/stores/useStatsStore.ts`**
```typescript
import { create } from 'zustand'
import type { Stats } from '../types'

interface StatsStore {
  stats: Stats | null
  setStats: (stats: Stats | null) => void
}

export const useStatsStore = create<StatsStore>((set) => ({
  stats: null,
  setStats: (stats) => set({ stats }),
}))
```

- [x] **Passo 2: Verificar build**

```bash
cd html && npm run build
```
Esperado: build sem erros (App.tsx ainda não existe — ok).

- [x] **Passo 3: Commit**

```bash
git add html/src/stores/
git commit -m "feat: add Zustand stores (app, jobs, company, industries, stats)"
```

---

## Task 4: Layout — App.tsx, TabBar e Modal

**Files:**
- Create: `html/src/App.tsx`
- Create: `html/src/components/layout/TabBar.tsx`
- Create: `html/src/components/layout/Modal.tsx`

- [x] **Passo 1: Criar TabBar.tsx**

```typescript
import { useAppStore } from '../../stores/useAppStore'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import type { TabName } from '../../types'
import clsx from 'clsx'

const TABS: { id: TabName; label: string }[] = [
  { id: 'jobs',       label: 'Jobs' },
  { id: 'active',     label: 'Entrega' },
  { id: 'company',    label: 'Empresa' },
  { id: 'garage',     label: 'Garagem' },
  { id: 'industries', label: 'Indústrias' },
  { id: 'stats',      label: 'Stats' },
]

export function TabBar() {
  const { activeTab, setTab } = useAppStore()
  const { activeJob } = useJobStore()
  const { company } = useCompanyStore()

  return (
    <div className="flex border-b border-zinc-700 bg-zinc-900">
      {TABS.map((tab) => {
        const disabled = (tab.id === 'active' && !activeJob)
          || (tab.id === 'garage' && !company)
        return (
          <button
            key={tab.id}
            onClick={() => !disabled && setTab(tab.id)}
            disabled={disabled}
            className={clsx(
              'px-4 py-3 text-sm font-medium transition-colors',
              activeTab === tab.id
                ? 'text-blue-400 border-b-2 border-blue-400'
                : 'text-zinc-400 hover:text-zinc-100',
              disabled && 'opacity-30 cursor-not-allowed'
            )}
          >
            {tab.label}
            {tab.id === 'active' && activeJob && (
              <span className="ml-1 w-2 h-2 bg-green-500 rounded-full inline-block" />
            )}
          </button>
        )
      })}
    </div>
  )
}
```

- [x] **Passo 2: Criar Modal.tsx**

```typescript
import type { ReactNode } from 'react'

interface ModalProps {
  title: string
  onClose: () => void
  children: ReactNode
}

export function Modal({ title, onClose, children }: ModalProps) {
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-800 rounded-lg border border-zinc-700 w-full max-w-md mx-4">
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-700">
          <h3 className="text-zinc-100 font-semibold">{title}</h3>
          <button
            onClick={onClose}
            className="text-zinc-400 hover:text-zinc-100 transition-colors"
          >
            ✕
          </button>
        </div>
        <div className="p-4">{children}</div>
      </div>
    </div>
  )
}
```

- [x] **Passo 3: Criar App.tsx (placeholder com tabs)**

```typescript
import { useNUI } from './hooks/useNUI'
import { useAppStore } from './stores/useAppStore'
import { useCompanyStore } from './stores/useCompanyStore'
import { TabBar } from './components/layout/TabBar'
import { JobList } from './components/jobs/JobList'
import { ActiveJob } from './components/jobs/ActiveJob'
import { CompanySetup } from './components/company/CompanySetup'
import { CompanyPanel } from './components/company/CompanyPanel'
import { GaragePanel } from './components/garage/GaragePanel'
import { IndustryList } from './components/industries/IndustryList'
import { StatsPanel } from './components/stats/StatsPanel'

export default function App() {
  useNUI()

  const { isOpen, activeTab } = useAppStore()
  const { company } = useCompanyStore()

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
      <div className="pointer-events-auto w-[700px] h-[520px] bg-zinc-900 rounded-xl border border-zinc-700 shadow-2xl flex flex-col overflow-hidden">
        <TabBar />
        <div className="flex-1 overflow-auto p-4">
          {activeTab === 'jobs'       && <JobList />}
          {activeTab === 'active'     && <ActiveJob />}
          {activeTab === 'company'    && (company ? <CompanyPanel /> : <CompanySetup />)}
          {activeTab === 'garage'     && <GaragePanel />}
          {activeTab === 'industries' && <IndustryList />}
          {activeTab === 'stats'      && <StatsPanel />}
        </div>
      </div>
    </div>
  )
}
```

**Nota:** Os componentes importados ainda não existem — criar stubs temporários em cada arquivo para o build passar:
```typescript
// Stub temporário (substituído nas próximas tasks)
export function ComponentName() { return <div>TODO</div> }
```

- [x] **Passo 4: Criar stubs temporários**

Criar um arquivo stub em cada path faltante:
- `html/src/components/jobs/JobList.tsx` → `export function JobList() { return <div>Jobs</div> }`
- `html/src/components/jobs/ActiveJob.tsx` → `export function ActiveJob() { return <div>Active</div> }`
- `html/src/components/jobs/JobCard.tsx` → `export function JobCard() { return null }`
- `html/src/components/company/CompanySetup.tsx` → stub
- `html/src/components/company/CompanyPanel.tsx` → stub
- `html/src/components/company/MemberList.tsx` → stub
- `html/src/components/garage/GaragePanel.tsx` → stub
- `html/src/components/industries/IndustryList.tsx` → stub
- `html/src/components/stats/StatsPanel.tsx` → stub

- [x] **Passo 5: Build**

```bash
cd html && npm run build
```
Esperado: build OK, arquivos em `html/assets/`.

- [x] **Passo 6: Verificar fxmanifest.lua** (já foi atualizado no Task 1 Passo 1 — apenas confirmar)

Se por algum motivo o Task 1 Passo 1 não foi commitado com o bloco correto, aplicar agora:

```lua
files {
    'html/index.html',
    'html/assets/*.js',
    'html/assets/*.css',
}
-- Remover referências antigas:
-- 'html/style_new.css',
-- 'html/script.js',
```

- [x] **Passo 7: Testar no servidor**

`ensure AUST_trucker`, pressionar F6 → painel AURP aparece com tabs (conteúdo TODO por enquanto).

- [x] **Passo 8: Commit**

```bash
git add html/src/ html/assets/ fxmanifest.lua
git commit -m "feat: add App layout, TabBar, Modal, and component stubs"
```

---

## Task 5: Componentes de Jobs

**Files:**
- Modify: `html/src/components/jobs/JobCard.tsx`
- Modify: `html/src/components/jobs/JobList.tsx`
- Modify: `html/src/components/jobs/ActiveJob.tsx`

- [x] **Passo 1: Implementar JobCard.tsx**

```typescript
import clsx from 'clsx'
import type { Job } from '../../types'
import { fetchNUI } from '../../hooks/useNUI'

interface JobCardProps {
  job: Job
  onSelect: () => void
}

function getMinutesLeft(expiresAt: number) {
  return Math.max(0, Math.floor((expiresAt - Date.now() / 1000) / 60))
}

export function JobCard({ job, onSelect }: JobCardProps) {
  const mins = getMinutesLeft(job.expiresAt)

  return (
    <div
      onClick={onSelect}
      className={clsx(
        'p-3 rounded-lg border cursor-pointer transition-all hover:bg-zinc-700',
        mins < 5
          ? 'border-red-500 bg-red-500/10'
          : mins < 15
          ? 'border-amber-500 bg-amber-500/10'
          : 'border-zinc-700 bg-zinc-800'
      )}
    >
      <div className="flex justify-between items-start">
        <div>
          <p className="text-zinc-100 font-medium text-sm">{job.cargoItem}</p>
          <p className="text-zinc-400 text-xs mt-0.5">{job.originName} → {job.destName}</p>
        </div>
        <div className="text-right">
          <p className="text-green-400 font-semibold text-sm">${job.basePayment.toLocaleString()}</p>
          <p className="text-zinc-400 text-xs">{job.distance.toFixed(1)} km</p>
        </div>
      </div>
      <div className="flex justify-between mt-2">
        <span className="text-zinc-500 text-xs">Trailer: {job.trailerModel}</span>
        <span className={clsx('text-xs', mins < 5 ? 'text-red-400' : mins < 15 ? 'text-amber-400' : 'text-zinc-500')}>
          {mins}min restantes
        </span>
      </div>
    </div>
  )
}
```

- [x] **Passo 2: Implementar JobList.tsx**

```typescript
import { useState } from 'react'
import { useJobStore } from '../../stores/useJobStore'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { JobCard } from './JobCard'
import { Modal } from '../layout/Modal'
import { fetchNUI } from '../../hooks/useNUI'

export function JobList() {
  const { jobs, selectedJobId, selectJob, setActiveJob } = useJobStore()
  const { company } = useCompanyStore()
  const [accepting, setAccepting] = useState(false)

  const selectedJob = jobs.find(j => j.id === selectedJobId)

  async function handleAccept() {
    if (!selectedJob) return
    setAccepting(true)
    await fetchNUI('acceptJob', { jobId: selectedJob.id })
    selectJob(null)
    setAccepting(false)
  }

  if (jobs.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-zinc-500">
        <p className="text-lg">Nenhum job disponível</p>
        <p className="text-sm mt-1">Aguarde o próximo ciclo de geração</p>
      </div>
    )
  }

  return (
    <>
      <div className="space-y-2">
        {!company && (
          <p className="text-amber-400 text-sm bg-amber-500/10 rounded-lg p-2 border border-amber-500/30">
            Entre em uma empresa para aceitar jobs
          </p>
        )}
        {jobs.map(job => (
          <JobCard key={job.id} job={job} onSelect={() => selectJob(job.id)} />
        ))}
      </div>

      {selectedJob && (
        <Modal title="Detalhes do Job" onClose={() => selectJob(null)}>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div className="bg-zinc-900 rounded p-2">
                <p className="text-zinc-400 text-xs">Carga</p>
                <p className="text-zinc-100">{selectedJob.cargoItem}</p>
              </div>
              <div className="bg-zinc-900 rounded p-2">
                <p className="text-zinc-400 text-xs">Pagamento</p>
                <p className="text-green-400 font-semibold">${selectedJob.basePayment.toLocaleString()}</p>
              </div>
              <div className="bg-zinc-900 rounded p-2">
                <p className="text-zinc-400 text-xs">Origem</p>
                <p className="text-zinc-100">{selectedJob.originName}</p>
              </div>
              <div className="bg-zinc-900 rounded p-2">
                <p className="text-zinc-400 text-xs">Destino</p>
                <p className="text-zinc-100">{selectedJob.destName}</p>
              </div>
              <div className="bg-zinc-900 rounded p-2">
                <p className="text-zinc-400 text-xs">Distância</p>
                <p className="text-zinc-100">{selectedJob.distance.toFixed(1)} km</p>
              </div>
              <div className="bg-zinc-900 rounded p-2">
                <p className="text-zinc-400 text-xs">Trailer</p>
                <p className="text-zinc-100">{selectedJob.trailerModel}</p>
              </div>
            </div>
            <button
              onClick={handleAccept}
              disabled={!company || accepting}
              className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white rounded-lg font-medium transition-colors"
            >
              {accepting ? 'Aceitando...' : 'Aceitar Job'}
            </button>
          </div>
        </Modal>
      )}
    </>
  )
}
```

- [x] **Passo 3: Implementar ActiveJob.tsx**

```typescript
import { useJobStore } from '../../stores/useJobStore'
import { fetchNUI } from '../../hooks/useNUI'

export function ActiveJob() {
  const { activeJob } = useJobStore()

  if (!activeJob) {
    return (
      <div className="flex items-center justify-center h-full text-zinc-500">
        <p>Nenhuma entrega ativa</p>
      </div>
    )
  }

  const elapsed = Math.floor(Date.now() / 1000 - activeJob.acceptedAt)
  const elapsedMin = Math.floor(elapsed / 60)
  const elapsedSec = elapsed % 60

  const timeBonusLabel = elapsed <= 300 ? '+20% bônus' : elapsed <= 600 ? 'Sem bônus' : '-20% penalidade'
  const timeBonusColor = elapsed <= 300 ? 'text-green-400' : elapsed <= 600 ? 'text-zinc-400' : 'text-red-400'

  return (
    <div className="space-y-4">
      <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <div className="flex justify-between items-start">
          <div>
            <p className="text-zinc-400 text-xs uppercase tracking-wide">
              {activeJob.stage === 'pickup' ? '📦 Ir buscar carga' : '🚚 Entregar'}
            </p>
            <p className="text-zinc-100 font-semibold mt-1">{activeJob.cargoItem}</p>
          </div>
          <div className="text-right">
            <p className="text-green-400 font-bold text-xl">${activeJob.basePayment.toLocaleString()}</p>
            <p className={`text-xs ${timeBonusColor}`}>{timeBonusLabel}</p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700">
          <p className="text-zinc-400 text-xs">Origem</p>
          <p className="text-zinc-100 text-sm mt-0.5">{activeJob.originName}</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700">
          <p className="text-zinc-400 text-xs">Destino</p>
          <p className="text-zinc-100 text-sm mt-0.5">{activeJob.destName}</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700">
          <p className="text-zinc-400 text-xs">Distância</p>
          <p className="text-zinc-100 text-sm mt-0.5">{activeJob.distance.toFixed(1)} km</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700">
          <p className="text-zinc-400 text-xs">Tempo decorrido</p>
          <p className="text-zinc-100 text-sm mt-0.5">{elapsedMin}m {elapsedSec}s</p>
        </div>
      </div>

      <button
        onClick={() => fetchNUI('abandonJob')}
        className="w-full py-2 bg-red-600/20 hover:bg-red-600/40 text-red-400 rounded-lg border border-red-500/30 transition-colors text-sm"
      >
        Abandonar Job
      </button>
    </div>
  )
}
```

- [x] **Passo 4: Build e testar**

```bash
cd html && npm run build
```
Abrir F6 em jogo → tab Jobs deve mostrar a lista de jobs com cards coloridos.

- [x] **Passo 5: Commit**

```bash
git add html/src/components/jobs/ html/assets/
git commit -m "feat: implement Jobs tab (JobList, JobCard, ActiveJob)"
```

---

## Task 6: Componentes de Empresa

**Files:**
- Modify: `html/src/components/company/CompanySetup.tsx`
- Modify: `html/src/components/company/CompanyPanel.tsx`
- Modify: `html/src/components/company/MemberList.tsx`

- [x] **Passo 1: Implementar CompanySetup.tsx**

```typescript
import { useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

export function CompanySetup() {
  const { recruitingList } = useCompanyStore()
  const [name, setName] = useState('')
  const [creating, setCreating] = useState(false)

  async function handleCreate() {
    if (!name.trim()) return
    setCreating(true)
    await fetchNUI('createCompany', { name: name.trim() })
    setCreating(false)
  }

  return (
    <div className="space-y-6">
      {/* Criar empresa */}
      <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 className="text-zinc-100 font-semibold mb-3">Criar Empresa</h3>
        <p className="text-zinc-400 text-sm mb-3">Custo: <span className="text-green-400 font-medium">$150.000</span></p>
        <input
          type="text"
          placeholder="Nome da empresa"
          value={name}
          onChange={e => setName(e.target.value)}
          maxLength={50}
          className="w-full bg-zinc-900 border border-zinc-700 rounded-lg px-3 py-2 text-zinc-100 text-sm placeholder-zinc-500 focus:outline-none focus:border-blue-500 mb-3"
        />
        <button
          onClick={handleCreate}
          disabled={!name.trim() || creating}
          className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white rounded-lg font-medium transition-colors text-sm"
        >
          {creating ? 'Criando...' : 'Criar Empresa ($150k)'}
        </button>
      </div>

      {/* Entrar em empresa */}
      {recruitingList.length > 0 && (
        <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
          <h3 className="text-zinc-100 font-semibold mb-3">Empresas Recrutando</h3>
          <div className="space-y-2">
            {recruitingList.map(company => (
              <div key={company.id} className="flex justify-between items-center bg-zinc-900 rounded p-2">
                <p className="text-zinc-100 text-sm">{company.name}</p>
                <button
                  onClick={() => fetchNUI('joinCompany', { companyId: company.id })}
                  className="text-blue-400 hover:text-blue-300 text-xs border border-blue-500/30 px-2 py-1 rounded transition-colors"
                >
                  Entrar
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
```

- [x] **Passo 2: Implementar CompanyPanel.tsx**

```typescript
import { useState } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { MemberList } from './MemberList'
import { fetchNUI } from '../../hooks/useNUI'
import { Modal } from '../layout/Modal'

export function CompanyPanel() {
  const { company } = useCompanyStore()
  const [depositAmount, setDepositAmount] = useState('')
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [showDeposit, setShowDeposit] = useState(false)
  const [showWithdraw, setShowWithdraw] = useState(false)

  if (!company) return null
  const isOwner = company.role === 'owner'
  const isManager = company.role === 'manager' || isOwner

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <div className="flex justify-between items-start">
          <div>
            <h2 className="text-zinc-100 font-bold text-lg">{company.name}</h2>
            <p className="text-zinc-400 text-sm mt-0.5 capitalize">{company.role}</p>
          </div>
          <div className="text-right">
            <p className="text-zinc-400 text-xs">Saldo</p>
            <p className="text-green-400 font-bold">${company.balance.toLocaleString()}</p>
          </div>
        </div>

        <div className="flex gap-2 mt-3">
          <button onClick={() => setShowDeposit(true)} className="flex-1 py-1.5 bg-zinc-700 hover:bg-zinc-600 text-zinc-100 rounded text-sm transition-colors">
            Depositar
          </button>
          {isManager && (
            <button onClick={() => setShowWithdraw(true)} className="flex-1 py-1.5 bg-zinc-700 hover:bg-zinc-600 text-zinc-100 rounded text-sm transition-colors">
              Sacar
            </button>
          )}
          {isOwner && (
            <button
              onClick={() => fetchNUI('toggleRecruiting')}
              className={`flex-1 py-1.5 rounded text-sm transition-colors ${company.is_recruiting ? 'bg-green-600/20 text-green-400' : 'bg-zinc-700 text-zinc-400'}`}
            >
              {company.is_recruiting ? 'Recrutando' : 'Recrutar'}
            </button>
          )}
        </div>
      </div>

      {/* Membros */}
      <MemberList />

      {/* Ações de owner */}
      {isOwner && (
        <button
          onClick={() => fetchNUI('sellCompany')}
          className="w-full py-2 text-red-400 bg-red-500/10 hover:bg-red-500/20 border border-red-500/30 rounded-lg text-sm transition-colors"
        >
          Vender Empresa ($25.000)
        </button>
      )}

      {!isOwner && (
        <button
          onClick={() => fetchNUI('leaveCompany')}
          className="w-full py-2 text-zinc-400 bg-zinc-800 hover:bg-zinc-700 border border-zinc-700 rounded-lg text-sm transition-colors"
        >
          Sair da Empresa
        </button>
      )}

      {/* Modal Depositar */}
      {showDeposit && (
        <Modal title="Depositar na Empresa" onClose={() => setShowDeposit(false)}>
          <input
            type="number" min="1" placeholder="Valor"
            value={depositAmount} onChange={e => setDepositAmount(e.target.value)}
            className="w-full bg-zinc-900 border border-zinc-700 rounded px-3 py-2 text-zinc-100 text-sm mb-3 focus:outline-none focus:border-blue-500"
          />
          <button
            onClick={() => { fetchNUI('depositMoney', { amount: Number(depositAmount) }); setShowDeposit(false) }}
            disabled={!depositAmount || Number(depositAmount) <= 0}
            className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white rounded text-sm"
          >
            Confirmar
          </button>
        </Modal>
      )}

      {/* Modal Sacar */}
      {showWithdraw && (
        <Modal title="Sacar da Empresa" onClose={() => setShowWithdraw(false)}>
          <input
            type="number" min="1" placeholder="Valor"
            value={withdrawAmount} onChange={e => setWithdrawAmount(e.target.value)}
            className="w-full bg-zinc-900 border border-zinc-700 rounded px-3 py-2 text-zinc-100 text-sm mb-3 focus:outline-none focus:border-blue-500"
          />
          <button
            onClick={() => { fetchNUI('withdrawMoney', { amount: Number(withdrawAmount) }); setShowWithdraw(false) }}
            disabled={!withdrawAmount || Number(withdrawAmount) <= 0}
            className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white rounded text-sm"
          >
            Confirmar
          </button>
        </Modal>
      )}
    </div>
  )
}
```

- [x] **Passo 3: Implementar MemberList.tsx**

```typescript
import { useEffect } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

const ROLE_LABEL: Record<string, string> = { owner: 'Owner', manager: 'Gerente', driver: 'Motorista' }

export function MemberList() {
  const { company, members, setMembers } = useCompanyStore()

  useEffect(() => {
    if (!company) return
    fetchNUI<{ citizenid: string; role: string; joined_at: string }[]>('getCompanyMembers', { companyId: company.id })
      .then(data => setMembers(data ?? []))
  }, [company?.id])

  return (
    <div className="bg-zinc-800 rounded-lg p-3 border border-zinc-700">
      <h4 className="text-zinc-400 text-xs uppercase tracking-wide mb-2">Membros ({members.length})</h4>
      <div className="space-y-1.5">
        {members.map(m => (
          <div key={m.citizenid} className="flex justify-between items-center">
            <span className="text-zinc-300 text-sm">{m.citizenid.slice(0, 12)}…</span>
            <div className="flex items-center gap-2">
              <span className="text-zinc-500 text-xs">{ROLE_LABEL[m.role] ?? m.role}</span>
              {company?.role === 'owner' && m.role !== 'owner' && (
                <button
                  onClick={() => fetchNUI('kickMember', { citizenId: m.citizenid })}
                  className="text-red-400 hover:text-red-300 text-xs transition-colors"
                >
                  Kick
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
```

- [x] **Passo 4: Build e testar**

```bash
cd html && npm run build
```
Testar criação de empresa, depositar, sacar, toggleRecruiting em jogo.

- [x] **Passo 5: Commit**

```bash
git add html/src/components/company/ html/assets/
git commit -m "feat: implement Company tab (CompanySetup, CompanyPanel, MemberList)"
```

---

## Task 7: GaragePanel, IndustryList e StatsPanel

**Files:**
- Modify: `html/src/components/garage/GaragePanel.tsx`
- Modify: `html/src/components/industries/IndustryList.tsx`
- Modify: `html/src/components/stats/StatsPanel.tsx`

- [x] **Passo 1: Implementar GaragePanel.tsx**

```typescript
import { useEffect } from 'react'
import { useCompanyStore } from '../../stores/useCompanyStore'
import { fetchNUI } from '../../hooks/useNUI'

export function GaragePanel() {
  const { company, vehicles, setVehicles } = useCompanyStore()

  useEffect(() => {
    if (!company) return
    fetchNUI<typeof vehicles>('getVehicles', { companyId: company.id })
      .then(data => setVehicles(data ?? []))
  }, [company?.id])

  async function handleRegister() {
    await fetchNUI('registerVehicle')
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h3 className="text-zinc-100 font-semibold">Veículos da Empresa</h3>
        <span className="text-zinc-400 text-sm">{vehicles.length}/2</span>
      </div>

      {vehicles.length === 0 ? (
        <p className="text-zinc-500 text-sm text-center py-4">Nenhum veículo registrado</p>
      ) : (
        <div className="space-y-2">
          {vehicles.map(v => (
            <div key={v.plate} className="flex justify-between items-center bg-zinc-800 rounded-lg p-3 border border-zinc-700">
              <div>
                <p className="text-zinc-100 text-sm font-medium">{v.plate}</p>
                <p className="text-zinc-400 text-xs">{v.model} · {v.vehicle_type}</p>
              </div>
              <div className="flex items-center gap-2">
                <span className={`text-xs px-2 py-0.5 rounded-full ${v.status === 'stored' ? 'bg-green-500/20 text-green-400' : 'bg-amber-500/20 text-amber-400'}`}>
                  {v.status === 'stored' ? 'Disponível' : 'Em Uso'}
                </span>
                {company?.role === 'owner' && (
                  <button
                    onClick={() => fetchNUI('removeVehicle', { plate: v.plate })}
                    className="text-red-400 hover:text-red-300 text-xs transition-colors"
                  >
                    Remover
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {vehicles.length < 2 && (
        <button
          onClick={handleRegister}
          className="w-full py-2 bg-blue-600/20 hover:bg-blue-600/40 text-blue-400 border border-blue-500/30 rounded-lg text-sm transition-colors"
        >
          Registrar Veículo Atual
        </button>
      )}
    </div>
  )
}
```

- [x] **Passo 2: Implementar IndustryList.tsx**

```typescript
import { useEffect } from 'react'
import { useIndustryStore } from '../../stores/useIndustryStore'
import { fetchNUI } from '../../hooks/useNUI'

export function IndustryList() {
  const { industries, setIndustries } = useIndustryStore()

  useEffect(() => {
    fetchNUI<typeof industries>('getIndustries')
      .then(data => { if (data) setIndustries(data) })
  }, [])

  const list = Object.values(industries)

  if (list.length === 0) return (
    <div className="flex items-center justify-center h-full text-zinc-500">
      <p>Carregando indústrias...</p>
    </div>
  )

  return (
    <div className="space-y-3">
      {list.map(industry => (
        <div key={industry.id} className="bg-zinc-800 rounded-lg p-3 border border-zinc-700">
          <div className="flex justify-between items-start mb-2">
            <h4 className="text-zinc-100 font-medium text-sm">{industry.name}</h4>
            <span className="text-zinc-500 text-xs capitalize">{industry.industryType}</span>
          </div>

          {industry.production && (
            <div className="flex justify-between items-center bg-zinc-900 rounded p-2 mb-1">
              <div>
                <p className="text-zinc-300 text-xs">🔹 {industry.production.product}</p>
                <p className="text-zinc-500 text-xs">{industry.production.currentStock}/{industry.production.maxStock} {industry.production.unit}</p>
              </div>
              <div className="text-right">
                <p className="text-green-400 text-sm font-medium">${industry.production.price}</p>
                <p className="text-zinc-500 text-xs">comprar</p>
              </div>
            </div>
          )}

          {industry.consumption.map(item => (
            <div key={item.item} className="flex justify-between items-center bg-zinc-900 rounded p-2 mb-1">
              <div>
                <p className="text-zinc-300 text-xs">🔸 {item.product}</p>
                <p className="text-zinc-500 text-xs">{item.currentStock}/{item.maxStock} {item.unit}</p>
              </div>
              <div className="text-right">
                <p className="text-blue-400 text-sm font-medium">${item.price}</p>
                <p className="text-zinc-500 text-xs">vender</p>
              </div>
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}
```

- [x] **Passo 3: Implementar StatsPanel.tsx**

```typescript
import { useStatsStore } from '../../stores/useStatsStore'

export function StatsPanel() {
  const { stats } = useStatsStore()

  if (!stats) return (
    <div className="flex items-center justify-center h-full text-zinc-500">
      <p>Sem estatísticas ainda</p>
    </div>
  )

  return (
    <div className="space-y-3">
      <h3 className="text-zinc-100 font-semibold">Suas Estatísticas</h3>
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700 text-center">
          <p className="text-green-400 font-bold text-xl">${stats.total_earnings.toLocaleString()}</p>
          <p className="text-zinc-400 text-xs mt-1">Total Ganho</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700 text-center">
          <p className="text-blue-400 font-bold text-xl">{stats.total_deliveries}</p>
          <p className="text-zinc-400 text-xs mt-1">Entregas</p>
        </div>
        <div className="bg-zinc-800 rounded-lg p-4 border border-zinc-700 text-center">
          <p className="text-zinc-100 font-bold text-xl">{stats.total_distance.toFixed(0)} km</p>
          <p className="text-zinc-400 text-xs mt-1">Distância</p>
        </div>
      </div>
    </div>
  )
}
```

- [x] **Passo 4: Adicionar NUICallbacks de dados no client/ui.lua e server/callbacks.lua**

Os componentes React `MemberList`, `GaragePanel` e `IndustryList` chamam `fetchNUI` para buscar dados sob demanda. Esses endpoints precisam de handlers no Lua.

**No arquivo `client/ui.lua`, adicionar os três handlers:**

```lua
-- Membros da empresa (chamado por MemberList.tsx)
RegisterNUICallback('getCompanyMembers', function(data, cb)
    local ok, members = pcall(lib.callback.await, 'AUST_trucker:getCompanyMembers', false)
    cb(ok and members or {})
end)

-- Veículos da empresa (chamado por GaragePanel.tsx)
RegisterNUICallback('getVehicles', function(data, cb)
    local ok, vehicles = pcall(lib.callback.await, 'AUST_trucker:getCompanyVehicles', false)
    cb(ok and vehicles or {})
end)

-- Indústrias (chamado por IndustryList.tsx)
RegisterNUICallback('getIndustries', function(data, cb)
    local ok, industries = pcall(lib.callback.await, 'AUST_trucker:getIndustries', false)
    cb(ok and industries or {})
end)
```

**No arquivo `server/callbacks.lua`, substituir e adicionar callbacks:**

> **ATENÇÃO — conflito com Fase 2:** A Fase 2 Task 6 já registrou `'AUST_trucker:getCompanyMembers'` com a assinatura `function(source, companyId)`. A versão da Fase 3 é diferente (deriva a empresa do jogador no servidor, sem confiar no `companyId` do cliente). **Localizar e remover ou substituir a entrada existente** — não adicionar uma segunda entrada com o mesmo nome.

Buscar e remover esta entrada existente do Task 6 (Fase 2):
```lua
-- REMOVER esta linha e as 3 seguintes:
lib.callback.register('AUST_trucker:getCompanyMembers', function(source, companyId)
    return DB_GetMembers(companyId)
end)
```

Em seu lugar (ou simplesmente adicionar os dois novos callbacks ausentes):

```lua
-- SUBSTITUIÇÃO de getCompanyMembers (derivação server-side, mais seguro)
lib.callback.register('AUST_trucker:getCompanyMembers', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return {} end
    return DB_GetMembers(company.id)   -- função correta: DB_GetMembers (Phase 1 Task 4)
end)

lib.callback.register('AUST_trucker:getCompanyVehicles', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return {} end
    local company = CompanyService.GetByMember(Player.PlayerData.citizenid)
    if not company then return {} end
    return DB_GetVehicles(company.id)
end)

lib.callback.register('AUST_trucker:getIndustries', function(source)
    return IndustryService.GetAll()
end)
```

> **Nota:** A função correta em `server/database.lua` (Fase 1 Task 4) é `DB_GetMembers(companyId)` — NÃO `DB_GetCompanyMembers`. `DB_GetVehicles(companyId)` e `IndustryService.GetAll()` existem com esses nomes exatos.

**Também em `client/ui.lua`, adicionar o handler para auto-refresh de jobs:**

A Fase 2 `events.lua` dispara `TriggerClientEvent('AUST_trucker:client:jobsUpdated', -1)` após cada ciclo de geração. Sem esse handler, a lista React não atualiza automaticamente — o jogador veria jobs estáticos até fechar e reabrir o painel.

```lua
-- Auto-refresh da lista de jobs quando o servidor gera novos
AddEventHandler('AUST_trucker:client:jobsUpdated', function()
    -- Só atualiza se a UI estiver aberta
    if not IsNUIFocused() then return end
    -- Reutiliza getInitialData (já registrado na Fase 2) e extrai apenas os jobs
    local ok, data = pcall(lib.callback.await, 'AUST_trucker:getInitialData', false)
    if ok and data and data.jobs then
        SendNUIMessage({ action = 'updateJobs', jobs = data.jobs })
    end
end)
```

> **Nota:** `'AUST_trucker:getInitialData'` está registrado na Fase 2 `server/callbacks.lua` e retorna `{ jobs, company, activeJob, stats, recruitingCompanies }`. Reutilizar evita criar um novo callback apenas para este caso.

Atualizar também o commit do Passo 6 para incluir esses arquivos.

- [x] **Passo 5: Build final e teste completo**

```bash
cd html && npm run build
```

Testar em jogo:
- Jobs: lista aparece, aceitar job, blips criados
- Entrega: tab Entrega mostra progresso, botão abandonar funciona
- Empresa: criar, entrar, depositar, sacar, kick
- Garagem: registrar veículo, status stored/out
- Indústrias: preços dinâmicos visíveis
- Stats: números corretos após completar jobs

- [x] **Passo 6: Commit**

```bash
git add html/src/components/garage/ html/src/components/industries/ html/src/components/stats/ html/assets/ server/callbacks.lua client/ui.lua
git commit -m "feat: implement Garage, Industries, Stats tabs"
```

---

## Task 8: Cleanup e Fase 3 Concluída

**Files:**
- Modify: `fxmanifest.lua` (remover referências antigas se houver)

- [x] **Passo 1: Verificar fxmanifest**

Confirmar que `files {}` aponta para `html/assets/*.js` e `html/assets/*.css` (não mais `html/script.js`).

- [x] **Passo 2: Teste de integração completo — lista de verificação**

- [x] F6 abre UI, Esc fecha
- [x] Tab Jobs: lista de jobs com urgência visual (vermelho/âmbar/neutro)
- [x] Aceitar job → tab Entrega ativa, blips no mapa
- [x] Completar job → stats atualizadas, $$ recebido, tab Entrega limpa
- [x] Criar empresa → tab Empresa mostra CompanyPanel
- [x] Depositar/sacar → saldo atualizado
- [x] Toggle recrutamento → outros jogadores veem empresa na lista
- [x] Outro jogador entra → aparece em MemberList
- [x] Kick membro → some da lista
- [x] Registrar veículo → aparece em Garagem com status 'Disponível'
- [x] Tab Indústrias → preços visíveis, atualizam após ciclo economia
- [x] Stats → números corretos

- [x] **Passo 3: Commit final Fase 3**

```bash
git add -A
git commit -m "feat: Phase 3 complete — React NUI replaces vanilla JS"
```

---

## Checklist Final — Fase 3 Concluída

- [x] `cd html && npm run build` sem erros
- [x] `ensure AUST_trucker` sem erros de UI
- [x] Todos os 6 tabs funcionais em jogo
- [x] `grep -rn "script\.js\|style_new\.css" fxmanifest.lua` → 0 resultados
- [x] Comunicação bidirecional Lua ↔ React funcionando (open/close/updates)

---

## Refactor Completo — v3.0.0

Após concluir as 3 fases, o `AUST_trucker` estará:
- **Stack:** qbx_core + ox_lib + ox_inventory + ox_target + oxmysql ✅
- **Persistência:** MySQL (7 tabelas, sem JSON) ✅
- **Servidor:** 4 services modulares + exports AUST_sala ✅
- **UI:** React + TypeScript + Vite + Tailwind ✅
- **Exports prontos para AUST_sala:** GetPlayerActiveJob, GetJobManifest, GetCompanyInfo, GetPlayerCompany, RecordInfraction, GetInfractions ✅
