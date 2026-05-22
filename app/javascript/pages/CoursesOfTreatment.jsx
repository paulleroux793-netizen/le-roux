import React from 'react'
import { Link } from '@inertiajs/react'
import { ClipboardPlus, ChevronRight } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const SETTING_LABELS = {
  in_chair: 'In-chair', hospital_chair: 'Hospital chair',
  hospital_theatre: 'Hospital / theatre', sedation: 'Sedation',
}
const STATUS_STYLE = {
  planned: 'bg-blue-50 text-blue-700 border-blue-200',
  active: 'bg-amber-50 text-amber-700 border-amber-200',
  completed: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  closed: 'bg-gray-100 text-gray-600 border-gray-200',
}
const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function CoursesOfTreatment({ courses = [], stats = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <ClipboardPlus size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Courses of Treatment</h1>
          <p className="text-sm text-brand-muted">{stats.total ?? courses.length} total · {stats.open ?? 0} open — the clinical episode that links charting to billing</p>
        </div>
      </div>

      {courses.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">
          No courses of treatment yet.
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Patient</th>
                <th className="px-4 py-3 font-semibold">Description</th>
                <th className="px-4 py-3 font-semibold">Setting</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 text-center font-semibold">Items</th>
                <th className="px-4 py-3 text-right font-semibold">Estimated</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {courses.map((c) => (
                <tr key={c.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 font-medium text-brand-ink">{c.patient_name}</td>
                  <td className="px-4 py-2.5 text-brand-ink">{c.description || '—'}</td>
                  <td className="px-4 py-2.5 text-xs text-brand-muted">{SETTING_LABELS[c.setting] || c.setting}</td>
                  <td className="px-4 py-2.5">
                    <span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', STATUS_STYLE[c.status] || STATUS_STYLE.closed)}>{c.status}</span>
                  </td>
                  <td className="px-4 py-2.5 text-center text-brand-ink">{c.item_count}</td>
                  <td className="px-4 py-2.5 text-right font-medium text-brand-ink">{rand(c.estimated_total)}</td>
                  <td className="px-4 py-2.5 text-right">
                    <Link href={`/courses-of-treatment/${c.id}`} className="inline-flex items-center text-brand-primary hover:underline">View <ChevronRight size={14} /></Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
