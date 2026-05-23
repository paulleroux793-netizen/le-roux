import React, { useEffect, useState, useMemo } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import { Search } from 'lucide-react'
import Modal from './Modal'

// R1.2 — picker for adding a procedure to a COT without going through
// the tooth-first odontogram flow. Used for whole-mouth procedures
// like oral exam (8101), prophylaxis (8159), x-rays etc.
//
// Type-ahead filter over the full active catalogue (already shipped to
// the page as a prop). Pick a code, optionally type a tooth number,
// submit. Same /courses-of-treatment/:id/add_item endpoint.

const rand = (n) => n == null ? '—' : `R${n.toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function AddProcedureModal({
  open, onClose, courseId, procedureCodes = [],
}) {
  const [q, setQ]               = useState('')
  const [selectedId, setSel]    = useState(null)
  const [tooth, setTooth]       = useState('')
  const [submitting, setSubmit] = useState(false)

  useEffect(() => {
    if (!open) return
    setQ(''); setSel(null); setTooth(''); setSubmit(false)
  }, [open])

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase()
    if (!s) return procedureCodes.slice(0, 30)
    return procedureCodes
      .filter((p) => p.code.toLowerCase().includes(s) || (p.description || '').toLowerCase().includes(s))
      .slice(0, 30)
  }, [q, procedureCodes])

  const submit = () => {
    if (!selectedId) return
    setSubmit(true)
    router.post(`/courses-of-treatment/${courseId}/add_item`, {
      procedure_code_id: selectedId,
      tooth_number: tooth.trim() || null,
    }, {
      preserveScroll: true,
      onSuccess: (page) => {
        toast.success(page?.props?.flash?.notice || 'Procedure added')
        onClose?.()
      },
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not add'),
      onFinish: () => setSubmit(false),
    })
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Add procedure"
      size="lg"
      footer={
        <>
          <button type="button" onClick={onClose}
            className="rounded-2xl px-4 py-2 text-sm font-medium text-brand-muted hover:bg-brand-surface/45 hover:text-brand-ink">
            Cancel
          </button>
          <button type="button" onClick={submit} disabled={!selectedId || submitting}
            className="rounded-2xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white hover:bg-brand-primary-dark disabled:opacity-50">
            Add to plan
          </button>
        </>
      }
    >
      <div className="space-y-3">
        <div className="flex items-center gap-2 rounded-xl border border-brand-border bg-white px-3 py-2">
          <Search size={15} className="text-brand-muted" />
          <input value={q} onChange={(e) => setQ(e.target.value)}
            placeholder="Search by code or description — e.g. 8101 or 'cleaning'"
            autoFocus
            className="w-full bg-transparent text-sm outline-none placeholder:text-brand-muted" />
        </div>

        <div className="max-h-72 overflow-y-auto rounded-xl border border-brand-border bg-white">
          {filtered.map((p) => (
            <button
              key={p.id} type="button"
              onClick={() => setSel(p.id)}
              className={`flex w-full items-center justify-between border-b border-brand-border/40 px-3 py-2 text-left text-sm last:border-0 ${
                selectedId === p.id ? 'bg-brand-primary/10' : 'hover:bg-brand-surface/50'
              }`}
            >
              <div>
                <span className="font-mono font-semibold text-brand-ink">{p.code}</span>
                <span className="ml-2 text-brand-ink">{p.description}</span>
              </div>
              <span className="text-xs text-brand-muted">{rand(p.fee)}</span>
            </button>
          ))}
          {filtered.length === 0 && (
            <p className="px-3 py-6 text-center text-sm text-brand-muted">No matches.</p>
          )}
        </div>

        {selectedId && (
          <div className="rounded-xl border border-brand-border bg-brand-surface/40 px-4 py-3">
            <label className="block text-xs font-semibold uppercase tracking-wide text-brand-muted">
              Tooth number (optional — leave blank for whole-mouth procedures)
            </label>
            <input value={tooth} onChange={(e) => setTooth(e.target.value)}
              placeholder="e.g. 36"
              className="mt-1.5 w-32 rounded-xl border border-brand-accent/80 bg-white px-3 py-1.5 text-sm focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
          </div>
        )}
      </div>
    </Modal>
  )
}
