import React from 'react'
import { Link } from '@inertiajs/react'
import { ArrowLeft, ClipboardPlus, Lock } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import Odontogram from '../components/Odontogram'
import { cn } from '../lib/utils'

const SETTING_LABELS = {
  in_chair: 'In-chair', hospital_chair: 'Hospital chair',
  hospital_theatre: 'Hospital / theatre', sedation: 'Sedation',
}
const ITEM_STATUS_STYLE = {
  planned: 'bg-blue-50 text-blue-700 border-blue-200',
  completed: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  failed: 'bg-red-50 text-red-700 border-red-200',
  voided: 'bg-gray-100 text-gray-500 border-gray-200',
}
const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function CourseOfTreatmentShow({ course = {}, items = [], notes = [], chart = {} }) {
  return (
    <DashboardLayout>
      <Link href="/courses-of-treatment" className="mb-4 inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
        <ArrowLeft size={14} /> All courses
      </Link>

      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <ClipboardPlus size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">{course.description || 'Course of treatment'}</h1>
          <p className="text-sm text-brand-muted">
            {course.patient?.name} · {SETTING_LABELS[course.setting] || course.setting} · <span className="capitalize">{course.status}</span>
            {course.authorisation_number ? ` · Auth ${course.authorisation_number}` : ''}
          </p>
        </div>
        <div className="ml-auto text-right">
          <p className="text-xs uppercase tracking-wide text-brand-muted">Estimated</p>
          <p className="text-lg font-semibold text-brand-ink">{rand(course.estimated_total)}</p>
        </div>
      </div>

      <div className="mb-6">
        <h2 className="mb-2 text-sm font-semibold text-brand-ink">Tooth chart</h2>
        <Odontogram chart={chart} />
      </div>

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
                </tr>
              </thead>
              <tbody>
                {items.map((i) => (
                  <tr key={i.id} className="border-b border-brand-border/60 last:border-0">
                    <td className="px-3 py-2 font-mono text-brand-ink">{i.code}</td>
                    <td className="px-3 py-2 text-brand-ink">{i.description}</td>
                    <td className="px-3 py-2 text-brand-muted">{i.tooth_number || '—'}</td>
                    <td className="px-3 py-2"><span className={cn('inline-flex rounded border px-1.5 py-0.5 text-[11px] font-medium', ITEM_STATUS_STYLE[i.status])}>{i.status}</span></td>
                    <td className="px-3 py-2 text-right text-brand-ink">{rand(i.fee)}</td>
                  </tr>
                ))}
                {items.length === 0 && <tr><td colSpan={5} className="px-3 py-6 text-center text-brand-muted">No items yet.</td></tr>}
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
