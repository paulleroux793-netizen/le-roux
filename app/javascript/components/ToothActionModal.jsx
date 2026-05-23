import React, { useEffect, useState, useMemo } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import Modal from './Modal'
import { cn } from '../lib/utils'

// P9.3 — clickable-odontogram modal.
//
// Flow:
//   1. Tooth clicked → modal opens with the tooth number
//   2. Pick a condition (chips)
//   3. Suggested procedure surfaces automatically. The clinician can:
//        - confirm (the common case)
//        - tick "no procedure yet" (just record the chart entry)
//        - pick a different code from the catalogue dropdown
//   4. Submit → POST /courses-of-treatment/chart_quick_add → server
//      records the chart entry + planned treatment item on the patient's
//      open Course of Treatment (auto-creating one if needed).

const CONDITIONS = [
  { value: 'caries',             label: 'Caries',             color: 'bg-red-50 border-red-200 text-red-800' },
  { value: 'filling',            label: 'Filling',            color: 'bg-blue-50 border-blue-200 text-blue-800' },
  { value: 'crown',              label: 'Crown',              color: 'bg-amber-50 border-amber-200 text-amber-800' },
  { value: 'bridge',             label: 'Bridge',             color: 'bg-amber-50 border-amber-200 text-amber-800' },
  { value: 'root_canal',         label: 'Root canal',         color: 'bg-purple-50 border-purple-200 text-purple-800' },
  { value: 'extraction_planned', label: 'Extraction planned', color: 'bg-orange-50 border-orange-200 text-orange-800' },
  { value: 'fracture',           label: 'Fracture',           color: 'bg-pink-50 border-pink-200 text-pink-800' },
  { value: 'implant',            label: 'Implant',            color: 'bg-teal-50 border-teal-200 text-teal-800' },
  { value: 'missing',            label: 'Missing',            color: 'bg-gray-100 border-gray-300 text-gray-600' },
]

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function ToothActionModal({
  open,
  onClose,
  toothNumber,
  patientId,
  procedureSuggestions = {},   // { condition: { id, code, description, fee } }
  procedureCodes = [],         // [{ id, code, description }, …] for override
}) {
  const [condition, setCondition] = useState('')
  const [overrideCodeId, setOverrideCodeId] = useState('')
  const [skipProcedure, setSkipProcedure] = useState(false)
  const [showOverride, setShowOverride] = useState(false)
  const [submitting, setSubmitting] = useState(false)

  // Reset state every time the modal opens (or jumps to a new tooth).
  useEffect(() => {
    if (!open) return
    setCondition('')
    setOverrideCodeId('')
    setSkipProcedure(false)
    setShowOverride(false)
    setSubmitting(false)
  }, [open, toothNumber])

  const suggested = condition ? procedureSuggestions[condition] : null
  // "Missing" never proposes a procedure — only the chart entry is recorded.
  const procedureAvailable = !!suggested && condition !== 'missing'

  const overrideOptions = useMemo(() => procedureCodes, [procedureCodes])

  const finalProcedureCodeId = useMemo(() => {
    if (skipProcedure) return null
    if (overrideCodeId)  return overrideCodeId
    return suggested?.id || null
  }, [skipProcedure, overrideCodeId, suggested])

  const submit = () => {
    if (!condition) return
    setSubmitting(true)
    router.post('/courses-of-treatment/chart_quick_add', {
      patient_id:        patientId,
      tooth_number:      toothNumber,
      condition,
      procedure_code_id: finalProcedureCodeId,
    }, {
      preserveScroll: true,
      onSuccess: (page) => {
        const notice = page?.props?.flash?.notice
        toast.success(notice || 'Tooth charted')
        onClose?.()
      },
      onError: (errs) => {
        const msg = Object.values(errs || {})[0] || 'Could not chart tooth'
        toast.error(msg)
      },
      onFinish: () => setSubmitting(false),
    })
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`Tooth ${toothNumber || ''} — chart entry`}
      size="lg"
      footer={
        <>
          <button
            type="button"
            onClick={onClose}
            className="rounded-2xl px-4 py-2 text-sm font-medium text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={submit}
            disabled={!condition || submitting}
            className="rounded-2xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark disabled:opacity-50"
          >
            {finalProcedureCodeId ? 'Chart + add to plan' : 'Chart only'}
          </button>
        </>
      }
    >
      <div className="space-y-5">
        {/* Step 1 — pick condition */}
        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-brand-muted">
            1. Diagnosis on tooth {toothNumber}
          </p>
          <div className="flex flex-wrap gap-2">
            {CONDITIONS.map((c) => (
              <button
                key={c.value}
                type="button"
                onClick={() => setCondition(c.value)}
                className={cn(
                  'inline-flex items-center rounded-full border px-3 py-1.5 text-sm font-medium transition-colors',
                  condition === c.value
                    ? `${c.color} ring-2 ring-offset-1 ring-brand-primary/40`
                    : 'border-brand-border bg-white text-brand-ink hover:bg-brand-surface'
                )}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>

        {/* Step 2 — suggested procedure */}
        {condition && (
          <div className="rounded-xl border border-brand-border bg-brand-surface/40 p-4">
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-brand-muted">
              2. Suggested treatment
            </p>

            {!procedureAvailable && (
              <p className="text-sm text-brand-ink">
                No procedure suggested for <strong>{CONDITIONS.find((c) => c.value === condition)?.label}</strong> — this records a chart entry only.
              </p>
            )}

            {procedureAvailable && !skipProcedure && !showOverride && (
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-mono text-sm font-semibold text-brand-ink">{suggested.code}</p>
                  <p className="text-sm text-brand-ink">{suggested.description}</p>
                  <p className="mt-1 text-xs text-brand-muted">
                    Practice fee: <strong className="text-brand-ink">{rand(suggested.fee)}</strong>
                    {suggested.medical > 0 && <> · Discovery rate: <strong className="text-brand-ink">{rand(suggested.medical)}</strong></>}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-1.5 text-xs">
                  <button
                    type="button"
                    onClick={() => { setShowOverride(true); setSkipProcedure(false) }}
                    className="text-brand-primary hover:underline"
                  >
                    Pick a different code
                  </button>
                  <button
                    type="button"
                    onClick={() => setSkipProcedure(true)}
                    className="text-brand-muted hover:underline"
                  >
                    Chart only — no procedure yet
                  </button>
                </div>
              </div>
            )}

            {procedureAvailable && skipProcedure && (
              <div className="flex items-center justify-between">
                <p className="text-sm text-brand-muted">No procedure will be added — only the chart entry is recorded.</p>
                <button
                  type="button"
                  onClick={() => setSkipProcedure(false)}
                  className="text-xs text-brand-primary hover:underline"
                >
                  Add a procedure
                </button>
              </div>
            )}

            {procedureAvailable && showOverride && (
              <div>
                <select
                  value={overrideCodeId}
                  onChange={(e) => setOverrideCodeId(e.target.value)}
                  className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
                >
                  <option value="">— Use suggestion ({suggested.code}) —</option>
                  {overrideOptions.map((p) => (
                    <option key={p.id} value={p.id}>{p.code} — {p.description}</option>
                  ))}
                </select>
                <button
                  type="button"
                  onClick={() => { setShowOverride(false); setOverrideCodeId('') }}
                  className="mt-2 text-xs text-brand-muted hover:underline"
                >
                  ← Back to suggestion
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </Modal>
  )
}
