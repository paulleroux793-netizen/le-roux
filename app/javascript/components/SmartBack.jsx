import { ArrowLeft } from 'lucide-react'
import { router } from '@inertiajs/react'

// Context-aware "Back": returns the user to the page they actually came from
// (browser/Inertia history) instead of always jumping to a fixed index.
// Falls back to `fallback` when there's no in-app history (e.g. a deep link or
// a fresh tab) so the button is never a dead end.
//
// Fixes the glitch where Back from an estimate/invoice opened inside a patient
// account dropped you on the "All estimates" list instead of back on the patient.
export default function SmartBack({ fallback = '/', label = 'Back', className = '' }) {
  const handle = (e) => {
    e.preventDefault()
    if (window.history.length > 1) {
      window.history.back()
    } else {
      router.visit(fallback)
    }
  }

  return (
    <button
      type="button"
      onClick={handle}
      title="Back to where you were"
      className={`inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink ${className}`}
    >
      <ArrowLeft size={14} /> {label}
    </button>
  )
}
