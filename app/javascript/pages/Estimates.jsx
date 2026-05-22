import React from 'react'
import { FileText } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const STATUS_STYLE = {
  draft: 'bg-gray-100 text-gray-600 border-gray-200',
  sent: 'bg-blue-50 text-blue-700 border-blue-200',
  accepted: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  rejected: 'bg-red-50 text-red-700 border-red-200',
  expired: 'bg-amber-50 text-amber-700 border-amber-200',
}
const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function Estimates({ estimates = [], stats = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <FileText size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Estimates</h1>
          <p className="text-sm text-brand-muted">{stats.total ?? estimates.length} quotes — given to patients before treatment (the AI scribe will draft these in Phase 6)</p>
        </div>
      </div>

      {estimates.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">No estimates yet.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Number</th>
                <th className="px-4 py-3 font-semibold">Patient</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 text-center font-semibold">Lines</th>
                <th className="px-4 py-3 font-semibold">Valid until</th>
                <th className="px-4 py-3 text-right font-semibold">Total</th>
              </tr>
            </thead>
            <tbody>
              {estimates.map((e) => (
                <tr key={e.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 font-mono font-medium text-brand-ink">{e.number}</td>
                  <td className="px-4 py-2.5 text-brand-ink">{e.patient_name}</td>
                  <td className="px-4 py-2.5"><span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', STATUS_STYLE[e.status])}>{e.status}</span></td>
                  <td className="px-4 py-2.5 text-center text-brand-ink">{e.line_count}</td>
                  <td className="px-4 py-2.5 text-brand-muted">{fmtDate(e.valid_until)}</td>
                  <td className="px-4 py-2.5 text-right text-brand-ink">{rand(e.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
