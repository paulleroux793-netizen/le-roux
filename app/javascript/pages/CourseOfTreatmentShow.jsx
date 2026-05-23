import React, { useState, useMemo } from 'react'
import { Link, router } from '@inertiajs/react'
import { toast } from 'sonner'
import { ArrowLeft, ClipboardPlus, Lock, Plus, Check, X, RotateCcw, FileText, Receipt, Layers } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import Odontogram from '../components/Odontogram'
import ToothActionModal from '../components/ToothActionModal'
import AddProcedureModal from '../components/AddProcedureModal'
import { cn } from '../lib/utils'

const SETTING_LABELS = {
  in_chair: 'In-chair', hospital_chair: 'Hospital chair',
  hospital_theatre: 'Hospital / theatre', sedation: 'Sedation',
}
const ITEM_STATUS_STYLE = {
  planned:   'bg-blue-50 text-blue-700 border-blue-200',
  completed: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  failed:    'bg-red-50 text-red-700 border-red-200',
  voided:    'bg-gray-100 text-gray-500 border-gray-200',
}
const STATUS_LABEL = {
  planned: 'Planned', completed: 'Done', failed: 'Failed', voided: 'Voided',
}
const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function CourseOfTreatmentShow({
  course = {}, items = [], notes = [], chart = {},
  procedure_suggestions: procedureSuggestions = {},
  procedure_codes: procedureCodes = [],
  treatment_macros: treatmentMacros = [],
}) {
  const [activeTooth, setActiveTooth] = useState(null)
  const [addOpen, setAddOpen]         = useState(false)
  const [macroPickerOpen, setMacroPickerOpen] = useState(false)

  const applyMacro = (macroId) => {
    router.post(`/courses-of-treatment/${course.id}/apply_macro`,
      { treatment_macro_id: macroId },
      {
        preserveScroll: true,
        onSuccess: (page) => toast.success(page?.props?.flash?.notice || 'Template applied'),
        onError:   (errs) => toast.error(Object.values(errs || {})[0] || 'Could not apply'),
        onFinish:  () => setMacroPickerOpen(false),
      })
  }

  const completedCount = useMemo(() => items.filter((i) => i.status === 'completed').length, [items])
  const billableTotal  = useMemo(
    () => items.filter((i) => i.status === 'completed').reduce((s, i) => s + (i.fee || 0), 0),
    [items],
  )

  const updateStatus = (id, status) => {
    router.patch(`/treatment_items/${id}`, { status }, {
      preserveScroll: true,
      onSuccess: (page) => toast.success(page?.props?.flash?.notice || 'Updated'),
      onError:   (errs) => toast.error(Object.values(errs || {})[0] || 'Could not update'),
    })
  }
  const generateEstimate = () => {
    router.post(`/courses-of-treatment/${course.id}/generate_estimate`, {}, {
      onSuccess: (page) => toast.success(page?.props?.flash?.notice || 'Estimate created'),
      onError:   (errs) => toast.error(Object.values(errs || {})[0] || 'Could not generate'),
    })
  }
  const generateInvoice = () => {
    router.post(`/courses-of-treatment/${course.id}/generate_invoice`, {}, {
      onSuccess: (page) => toast.success(page?.props?.flash?.notice || 'Invoice created'),
      onError:   (errs) => toast.error(Object.values(errs || {})[0] || 'Could not generate'),
    })
  }

  return (
    <DashboardLayout>
      <Link href="/courses-of-treatment" className="mb-4 inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
        <ArrowLeft size={14} /> All courses
      </Link>

      <div className="mb-6 flex flex-wrap items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <ClipboardPlus size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">{course.description || 'Course of treatment'}</h1>
          <p className="text-sm text-brand-muted">
            <Link href={`/patients/${course.patient?.id}`} className="hover:text-brand-ink hover:underline">
              {course.patient?.name}
            </Link>
            {' · '}{SETTING_LABELS[course.setting] || course.setting} · <span className="capitalize">{course.status}</span>
            {course.authorisation_number ? ` · Auth ${course.authorisation_number}` : ''}
          </p>
        </div>
        <div className="ml-auto flex items-end gap-6">
          <div className="text-right">
            <p className="text-xs uppercase tracking-wide text-brand-muted">Planned</p>
            <p className="text-lg font-semibold text-brand-ink">{rand(course.estimated_total)}</p>
          </div>
          <div className="text-right">
            <p className="text-xs uppercase tracking-wide text-brand-muted">Done · billable</p>
            <p className="text-lg font-semibold text-emerald-600">{rand(billableTotal)}</p>
          </div>
        </div>
      </div>

      {/* ── Primary actions ─────────────────────────────────────────── */}
      <div className="mb-6 flex flex-wrap gap-2">
        <button onClick={() => setAddOpen(true)}
          className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-primary-dark">
          <Plus size={15} /> Add procedure
        </button>
        {treatmentMacros.length > 0 && (
          <div className="relative">
            <button onClick={() => setMacroPickerOpen((v) => !v)}
              className="inline-flex items-center gap-1.5 rounded-xl border border-brand-border bg-white px-4 py-2 text-sm font-semibold text-brand-ink hover:bg-brand-surface"
              title="Apply a visit-type template (e.g. Recall + hygiene, Surgical extraction)">
              <Layers size={15} /> Apply template
            </button>
            {macroPickerOpen && (
              <div className="absolute z-20 mt-1 max-h-72 w-72 overflow-y-auto rounded-xl border border-brand-border bg-white shadow-lg">
                {treatmentMacros.map((m) => (
                  <button key={m.id} onClick={() => applyMacro(m.id)}
                    className="block w-full border-b border-brand-border/40 px-3 py-2 text-left text-sm last:border-0 hover:bg-brand-surface">
                    <span className="font-mono font-semibold text-brand-ink">{m.access_code}</span>
                    <span className="ml-2 text-brand-ink">{m.name}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
        <button onClick={generateEstimate} disabled={items.length === 0}
          className="inline-flex items-center gap-1.5 rounded-xl border border-brand-border bg-white px-4 py-2 text-sm font-semibold text-brand-ink hover:bg-brand-surface disabled:opacity-40 disabled:hover:bg-white"
          title="Build a patient quote from every non-voided item">
          <FileText size={15} /> Generate estimate
        </button>
        <button onClick={generateInvoice} disabled={completedCount === 0}
          className="inline-flex items-center gap-1.5 rounded-xl border border-brand-border bg-white px-4 py-2 text-sm font-semibold text-brand-ink hover:bg-brand-surface disabled:opacity-40 disabled:hover:bg-white"
          title={completedCount === 0 ? 'Mark at least one item Done first' : `Invoice the ${completedCount} completed item${completedCount === 1 ? '' : 's'}`}>
          <Receipt size={15} /> Generate invoice
          {completedCount > 0 && <span className="ml-1 rounded-full bg-emerald-100 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-700">{completedCount}</span>}
        </button>
      </div>

      <div className="mb-6">
        <div className="mb-2 flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-brand-ink">Tooth chart</h2>
          <p className="text-xs text-brand-muted">Click any tooth to chart a finding or plan a procedure</p>
        </div>
        <Odontogram chart={chart} onToothClick={setActiveTooth} />
      </div>

      <ToothActionModal
        open={activeTooth !== null}
        toothNumber={activeTooth}
        patientId={course.patient?.id}
        procedureSuggestions={procedureSuggestions}
        procedureCodes={procedureCodes}
        onClose={() => setActiveTooth(null)}
      />
      <AddProcedureModal
        open={addOpen}
        onClose={() => setAddOpen(false)}
        courseId={course.id}
        procedureCodes={procedureCodes}
      />

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Treatment items */}
        <div>
          <h2 className="mb-2 text-sm font-semibold text-brand-ink">Treatment items</h2>
          <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
            <table className="w-full text-sm">
              <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
                <tr>
                  <th className="px-3 py-2 font-semibold">Code</th>
                  <th className="px-3 py-2 font-semibold">Procedure</th>
                  <th className="px-3 py-2 font-semibold">Tooth</th>
                  <th className="px-3 py-2 font-semibold">Status</th>
                  <th className="px-3 py-2 text-right font-semibold">Fee</th>
                  <th className="px-3 py-2 text-right font-semibold">Action</th>
                </tr>
              </thead>
              <tbody>
                {items.map((i) => (
                  <tr key={i.id} className={cn('border-b border-brand-border/60 last:border-0', i.status === 'voided' && 'opacity-60')}>
                    <td className="px-3 py-2 font-mono text-brand-ink">{i.code}</td>
                    <td className="px-3 py-2 text-brand-ink">{i.description}</td>
                    <td className="px-3 py-2 text-brand-muted">{i.tooth_number || '—'}</td>
                    <td className="px-3 py-2">
                      <span className={cn('inline-flex rounded border px-1.5 py-0.5 text-[11px] font-medium', ITEM_STATUS_STYLE[i.status])}>
                        {STATUS_LABEL[i.status] || i.status}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right text-brand-ink">{rand(i.fee)}</td>
                    <td className="px-3 py-2 text-right">
                      <ItemActions item={i} updateStatus={updateStatus} />
                    </td>
                  </tr>
                ))}
                {items.length === 0 && (
                  <tr><td colSpan={6} className="px-3 py-8 text-center text-brand-muted">
                    <p>No items yet.</p>
                    <p className="mt-1 text-xs">Click <strong>Add procedure</strong> above, or click a tooth on the chart.</p>
                  </td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Clinical notes */}
        <div>
          <h2 className="mb-2 text-sm font-semibold text-brand-ink">Clinical notes (SOAP)</h2>
          <div className="space-y-3">
            {notes.map((n) => (
              <div key={n.id} className="rounded-xl border border-brand-border bg-white p-4">
                <div className="mb-2 flex items-center gap-2 text-xs text-brand-muted">
                  {n.locked && <Lock size={12} className="text-brand-muted" />}
                  {n.signed_by ? `Signed by ${n.signed_by}` : 'Unsigned draft'}
                </div>
                {n.subjective && <p className="text-sm"><span className="font-semibold text-brand-muted">S:</span> {n.subjective}</p>}
                {n.objective && <p className="text-sm"><span className="font-semibold text-brand-muted">O:</span> {n.objective}</p>}
                {n.assessment && <p className="text-sm"><span className="font-semibold text-brand-muted">A:</span> {n.assessment}</p>}
                {n.plan && <p className="text-sm"><span className="font-semibold text-brand-muted">P:</span> {n.plan}</p>}
              </div>
            ))}
            {notes.length === 0 && <p className="rounded-xl border border-dashed border-brand-border bg-white px-4 py-6 text-center text-sm text-brand-muted">No clinical notes yet.</p>}
          </div>
        </div>
      </div>
    </DashboardLayout>
  )
}

// R1.1 — per-row action cluster. Planned → big green "Done" button
// (the one users will click 99% of the time); secondary undo/void
// kept compact behind small icons.
function ItemActions({ item, updateStatus }) {
  if (item.status === 'planned') {
    return (
      <div className="flex justify-end gap-1">
        <button onClick={() => updateStatus(item.id, 'completed')}
          title="Mark as done"
          className="inline-flex items-center gap-1 rounded-lg bg-emerald-600 px-2 py-1 text-xs font-semibold text-white hover:bg-emerald-700">
          <Check size={12} /> Done
        </button>
        <button onClick={() => updateStatus(item.id, 'voided')}
          title="Remove (mistake)"
          className="rounded-lg p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-danger">
          <X size={13} />
        </button>
      </div>
    )
  }
  if (item.status === 'completed') {
    return (
      <button onClick={() => updateStatus(item.id, 'planned')}
        title="Undo done"
        className="rounded-lg p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-ink">
        <RotateCcw size={13} />
      </button>
    )
  }
  return <span className="text-xs text-brand-muted">—</span>
}
