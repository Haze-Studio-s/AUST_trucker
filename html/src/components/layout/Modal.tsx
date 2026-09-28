import type { ReactNode } from 'react'

interface ModalProps {
  title: string
  onClose: () => void
  children: ReactNode
}

export function Modal({ title, onClose, children }: ModalProps) {
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 pointer-events-auto">
      <div className="bg-card rounded-lg border border-app-border shadow-[0_4px_24px_rgba(0,0,0,0.3)] w-full max-w-md mx-4">
        <div className="flex items-center justify-between px-4 py-3 border-b border-app-border">
          <h3 className="text-txt-light font-semibold">{title}</h3>
          <button
            onClick={onClose}
            className="text-txt hover:text-txt-light transition-colors"
          >
            ✕
          </button>
        </div>
        <div className="p-4">{children}</div>
      </div>
    </div>
  )
}
