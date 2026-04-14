import React, { useEffect } from 'react'
import { X } from 'lucide-react'

// ── Shared modal primitive ──────────────────────────────────────────
// Deliberately tiny: a fixed-position backdrop, a centred panel, a
// titled header with a close button, and a slot for children. Phase
// 9.6 uses this for the four appointment modals (Detail, Create,
// Edit, Cancel) — subsequent sub-areas (Patient forms) will reuse
// it without modification.
//
// Why not `@radix-ui/react-dialog` or `headlessui`? — STACK.md
// hasn't pulled either in, and for a single-dialog-at-a-time flow
// the ~40 lines below do the job. If we ever need nested dialogs or
// complex focus trapping we can swap to Radix without touching the
// call sites since the API is intentionally compatible.
export default function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  size = 'md',
}) {
  // Close on Escape — wired only while the modal is actually open so
  // we don't leak listeners onto the window for every mounted modal.
  useEffect(() => {
    if (!open) return
    const onKey = (e) => e.key === 'Escape' && onClose?.()
    window.addEventListener('keydown', onKey)
    // Lock body scroll while the modal is open so the page behind
    // doesn't wiggle under the overlay on mobile / short screens.
    const prevOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = prevOverflow
    }
  }, [open, onClose])

  if (!open) return null

  const sizeClass = {
    sm: 'max-w-sm',
    md: 'max-w-md',
    lg: 'max-w-lg',
    xl: 'max-w-xl',
    '2xl': 'max-w-2xl',
  }[size] || 'max-w-md'

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-[#393C4D]/28 backdrop-blur-[4px]"
        onClick={onClose}
      />

      {/* Panel */}
      <div
        className={`relative flex max-h-[90vh] w-full ${sizeClass} flex-col rounded-[28px] border border-brand-accent/80 bg-white shadow-[0_38px_90px_-55px_rgba(57,60,77,0.5)]`}
      >
        {/* Header */}
        <div className="flex items-start justify-between border-b border-brand-accent/70 bg-gradient-to-br from-brand-surface/45 via-white to-white p-5">
          <h2 id="modal-title" className="text-lg font-semibold text-brand-ink">
            {title}
          </h2>
          <button
            onClick={onClose}
            className="rounded-xl p-1 text-brand-muted transition-colors hover:bg-brand-surface/60 hover:text-brand-ink"
            aria-label="Close"
          >
            <X size={18} />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-5">{children}</div>

        {/* Footer */}
        {footer && (
          <div className="flex items-center justify-end gap-2 rounded-b-[28px] border-t border-brand-accent/70 bg-brand-surface/20 p-4">
            {footer}
          </div>
        )}
      </div>
    </div>
  )
}
