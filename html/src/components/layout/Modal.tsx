import type { ReactNode } from 'react'

interface ModalProps {
  title: string
  onClose: () => void
  children: ReactNode
}

export function Modal({ title, onClose, children }: ModalProps) {
  return (
    <div className="fixed inset-0 bg-black/75 backdrop-blur-sm flex items-center justify-center z-50 pointer-events-auto animate-fadeIn select-none p-4">
      <div className="bg-lation-surface border border-lation-line-strong rounded-xl shadow-2xl w-full max-w-lg overflow-hidden">
        {/* Header com Faixa Lation */}
        <div className="flex items-center justify-between px-5 py-3.5 bg-lation-surface-band border-b border-lation-line border-l-4 border-l-lation-accent bg-gradient-to-r from-emerald-500/10 via-transparent to-transparent">
          <h3 className="text-sm font-bold tracking-wider uppercase text-white font-sans">
            {title}
          </h3>
          <button
            onClick={onClose}
            className="w-7 h-7 rounded bg-lation-surface-elevated text-lation-content-sec hover:text-white hover:bg-lation-err-bg hover:border-lation-err-border border border-lation-line flex items-center justify-center font-bold text-xs transition-all"
            title="Fechar (ESC)"
          >
            ✕
          </button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  )
}
