import { useEffect, useState } from 'react'
import { router } from '@inertiajs/react'

// R4 — Practice-wide keyboard shortcuts. The Perplexity user-complaint
// research called out that "Modern UI" redesigns routinely remove power-
// user shortcuts; we treat those as sacred and ADD them.
//
// Shortcuts (no modifier, unless noted; disabled when typing in inputs):
//   N  → New patient · B → Book appointment · F or / → Focus search
//   G then P/C/I/E/M/D → go to section · ? → shortcuts help overlay · Esc → close
const ROUTES = {
  'p': '/patients',
  'c': '/appointments/calendar',
  'i': '/invoices',
  'e': '/estimates',
  'm': '/mail',
  'd': '/dashboard',
}

// Shown in the help overlay (benchmark: a discoverable shortcuts dialog, not a toast).
const SHORTCUTS = [
  ['N', 'New patient'],
  ['B', 'Book appointment'],
  ['F  or  /', 'Focus search'],
  ['G then P', 'Go to Patients'],
  ['G then C', 'Go to Calendar'],
  ['G then I', 'Go to Invoices'],
  ['G then E', 'Go to Estimates'],
  ['G then M', 'Go to Mailbox'],
  ['G then D', 'Go to Dashboard'],
  ['?', 'Show this help'],
  ['Esc', 'Close dialogs'],
]

function isTyping(target) {
  if (!target) return false
  const tag = target.tagName?.toUpperCase()
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable
}

export default function GlobalShortcuts() {
  const [helpOpen, setHelpOpen] = useState(false)

  useEffect(() => {
    let gPressed = false
    let gTimer = null

    const onKey = (e) => {
      if (e.key === 'Escape') { setHelpOpen(false); return }
      if (isTyping(e.target)) return
      const k = e.key

      // G-prefix mode (vim-style "go to")
      if (gPressed) {
        const target = ROUTES[k.toLowerCase()]
        if (target) { e.preventDefault(); router.visit(target) }
        gPressed = false
        clearTimeout(gTimer)
        return
      }

      if (k === 'g' || k === 'G') {
        gPressed = true
        gTimer = setTimeout(() => { gPressed = false }, 1500)
        return
      }

      if (k === '?' || (k === '/' && e.shiftKey)) { e.preventDefault(); setHelpOpen((v) => !v); return }
      if (k === 'n' || k === 'N') { e.preventDefault(); router.visit('/patients?modal=new'); return }
      if (k === 'b' || k === 'B') { e.preventDefault(); router.visit('/appointments?modal=new'); return }
      if (k === 'f' || k === 'F') {
        const el = document.querySelector('[data-global-search] input, [data-search-input]')
        if (el) { e.preventDefault(); el.focus() }
        return
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  if (!helpOpen) return null
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 p-4" onClick={() => setHelpOpen(false)}>
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-base font-semibold text-brand-ink">Keyboard shortcuts</h2>
          <button onClick={() => setHelpOpen(false)} className="text-brand-muted hover:text-brand-ink" aria-label="Close">✕</button>
        </div>
        <div className="space-y-2">
          {SHORTCUTS.map(([keys, label]) => (
            <div key={keys} className="flex items-center justify-between text-sm">
              <span className="text-brand-muted">{label}</span>
              <kbd className="rounded border border-brand-border bg-brand-surface px-2 py-0.5 font-mono text-xs text-brand-ink">{keys}</kbd>
            </div>
          ))}
        </div>
        <p className="mt-4 text-xs text-brand-muted">Press <kbd className="rounded bg-brand-surface px-1 font-mono">?</kbd> anytime to open this. Shortcuts are disabled while typing.</p>
      </div>
    </div>
  )
}
