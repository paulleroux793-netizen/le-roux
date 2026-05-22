import React from 'react'
import { BellRing } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function Recalls({ recalls = [], stats = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><BellRing size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Recalls</h1>
          <p className="text-sm text-brand-muted">{stats.due ?? 0} due — 6-month check-ups & follow-ups (sent over WhatsApp)</p>
        </div>
      </div>

      {recalls.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">No recalls scheduled yet.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr><th className="px-4 py-3 font-semibold">Patient</th><th className="px-4 py-3 font-semibold">Type</th><th className="px-4 py-3 font-semibold">Due</th><th className="px-4 py-3 font-semibold">Status</th></tr>
            </thead>
            <tbody>
              {recalls.map((r) => (
                <tr key={r.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 text-brand-ink">{r.patient_name}</td>
                  <td className="px-4 py-2.5 capitalize text-brand-muted">{r.recall_type}</td>
                  <td className={cn('px-4 py-2.5', r.overdue ? 'font-medium text-brand-danger' : 'text-brand-muted')}>{fmtDate(r.due_on)}</td>
                  <td className="px-4 py-2.5 capitalize text-brand-ink">{r.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
