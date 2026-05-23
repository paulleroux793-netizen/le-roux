import { useEffect } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'

// R4 — Practice-wide keyboard shortcuts. The Perplexity user-complaint
// research called out that "Modern UI" redesigns routinely remove power-
// user shortcuts; we treat those as sacred and ADD them.
//
// Shortcuts (no modifier, unless noted; disabled when typing in inputs):
//   N  → New patient (/patients?modal=new)
//   B  → Book appointment (/appointments?modal=new)
//   F  → Focus global search
//   ?  → Show shortcut help toast
//   G then P → Go to Patients list
//   G then C → Go to Calendar (fullscreen)
//   G then I → Go to Invoices
//   G then E → Go to Estimates
//   G then M → Go to Mailbox

const ROUTES = {
  'p': '/patients',
  'c': '/appointments/calendar',
  'i': '/invoices',
  'e': '/estimates',
  'm': '/mail',
  'd': '/dashboard',
}

function isTyping(target) {
  if (!target) return false
  const tag = target.tagName?.toUpperCase()
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable
}

export default function GlobalShortcuts() {
  useEffect(() => {
    let gPressed = false
    let gTimer = null

    const showHelp = () => {
      toast('Shortcuts: N new patient · B book appt · F search · G+P/C/I/E/M go to · ? this help', {
        duration: 6000,
      })
    }

    const onKey = (e) => {
      if (isTyping(e.target)) return
      const k = e.key

      // G-prefix mode (vim-style "go to")
      if (gPressed) {
        const target = ROUTES[k.toLowerCase()]
        if (target) {
          e.preventDefault()
          router.visit(target)
        }
        gPressed = false
        clearTimeout(gTimer)
        return
      }

      if (k === 'g' || k === 'G') {
        gPressed = true
        gTimer = setTimeout(() => { gPressed = false }, 1500)
        return
      }

      if (k === '?' || (k === '/' && e.shiftKey)) { e.preventDefault(); showHelp(); return }
      if (k === 'n' || k === 'N') { e.preventDefault(); router.visit('/patients?modal=new'); return }
      if (k === 'b' || k === 'B') { e.preventDefault(); router.visit('/appointments?modal=new'); return }
      if (k === 'f' || k === 'F') {
        // Focus the global search input if one exists in the page.
        const el = document.querySelector('[data-global-search] input, [data-search-input]')
        if (el) { e.preventDefault(); el.focus() }
        return
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  return null
}
