import React, { useEffect, useRef } from 'react'
import { CheckCircle2, LogIn, Stethoscope, CheckCheck, XCircle, Edit3, UserX, Trash2 } from 'lucide-react'

// ── Right-click context menu for an Ivory diary block ──────────────────
// Elixir-parity: reception right-clicks a patient's block and drives the
// patient-journey status in one click, or jumps to cancel/edit. Positioned
// at the cursor; closes on outside-click, Escape, or after any action.
// The status keys match the server (confirmed · arrived · in_consultation ·
// completed); the block recolours server-side on the preserveState refresh.
const ITEMS = [
  { key: 'confirmed',       label: 'Confirm',           icon: CheckCircle2 },
  { key: 'arrived',         label: 'Arrived',           icon: LogIn },
  { key: 'in_consultation', label: 'Start consultation', icon: Stethoscope },
  { key: 'completed',       label: 'Completed',         icon: CheckCheck },
  { key: 'no_show',         label: 'No-show',           icon: UserX },
  { divider: true },
  { key: 'cancel',          label: 'Cancel appointment', icon: XCircle, danger: true },
  { key: 'delete',          label: 'Delete (remove)',    icon: Trash2, danger: true },
  { key: 'edit',            label: 'Edit',              icon: Edit3 },
]

export default function DiaryContextMenu({ x, y, onPick, onClose }) {
  const ref = useRef(null)

  useEffect(() => {
    const onDown = (e) => { if (ref.current && !ref.current.contains(e.target)) onClose() }
    const onKey = (e) => { if (e.key === 'Escape') onClose() }
    // capture so we close before any block's own onClick fires
    window.addEventListener('mousedown', onDown, true)
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('mousedown', onDown, true)
      window.removeEventListener('keydown', onKey)
    }
  }, [onClose])

  // Keep the menu on-screen if right-clicked near the right/bottom edge.
  const left = Math.min(x, (typeof window !== 'undefined' ? window.innerWidth : x) - 200)
  const top = Math.min(y, (typeof window !== 'undefined' ? window.innerHeight : y) - 260)

  return (
    <div
      ref={ref}
      role="menu"
      className="fixed z-50 w-48 overflow-hidden rounded-xl border border-brand-border bg-white py-1 text-sm shadow-lg"
      style={{ left, top }}
      onContextMenu={(e) => e.preventDefault()}
    >
      {ITEMS.map((item, i) =>
        item.divider ? (
          <div key={`d${i}`} className="my-1 h-px bg-brand-border" />
        ) : (
          <button
            key={item.key}
            type="button"
            role="menuitem"
            onClick={() => onPick(item.key)}
            className={`flex w-full items-center gap-2.5 px-3 py-2 text-left transition-colors hover:bg-brand-surface/60 ${
              item.danger ? 'text-brand-danger hover:bg-brand-danger/10' : 'text-brand-ink'
            }`}
          >
            <item.icon size={15} className={item.danger ? '' : 'text-brand-primary'} />
            {item.label}
          </button>
        )
      )}
    </div>
  )
}
