import React from 'react'
import { BellRing, Phone } from 'lucide-react'
import { router, Link } from '@inertiajs/react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function Recalls({ recalls = [], stats = {} }) {
  // Reception works the list — one-tap outcome (contacted/booked/done).
  const setStatus = (id, status) => router.patch(`/recalls/${id}`, { status }, { preserveScroll: true })
  const btn = 'rounded-lg border px-2.5 py-1 text-xs font-medium transition'

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><BellRing size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Recalls</h1>
          <p className="text-sm text-brand-muted">{stats.due ?? 0} due — 6-month check-ups & follow-ups. Call or message, then mark the outcome.</p>
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'Due', value: stats.due ?? 0, sub: (stats.overdue ?? 0) > 0 ? `${stats.overdue} overdue` : null, tone: 'text-brand-danger' },
          { label: 'Contacted', value: stats.contacted ?? 0, tone: 'text-amber-600' },
          { label: 'Booked', value: stats.booked ?? 0, tone: 'text-emerald-600' },
          { label: 'Total', value: stats.total ?? 0, tone: 'text-brand-ink' },
        ].map((s) => (
          <div key={s.label} className="rounded-xl border border-brand-border bg-white px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">{s.label}</p>
            <p className={cn('mt-0.5 text-2xl font-bold', s.tone)}>{s.value}</p>
            {s.sub && <p className="text-[11px] font-medium text-brand-danger">{s.sub}</p>}
          </div>
        ))}
      </div>

      {recalls.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">No recalls scheduled yet.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Patient</th>
                <th className="px-4 py-3 font-semibold">Type</th>
                <th className="px-4 py-3 font-semibold">Due</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 text-right font-semibold">Work it</th>
              </tr>
            </thead>
            <tbody>
              {recalls.map((r) => (
                <tr key={r.id} className={cn('border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50', r.overdue && 'border-l-4 border-l-brand-danger')}>
                  <td className="px-4 py-2.5">
                    <Link href={`/patients/${r.patient_id}`} className="text-brand-ink hover:underline">{r.patient_name}</Link>
                  </td>
                  <td className="px-4 py-2.5 capitalize text-brand-muted">{r.recall_type}</td>
                  <td className={cn('px-4 py-2.5', r.overdue ? 'font-medium text-brand-danger' : 'text-brand-muted')}>
                    {fmtDate(r.due_on)}{r.overdue && <span className="ml-1.5 rounded-full bg-brand-danger/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-brand-danger">overdue</span>}
                  </td>
                  <td className="px-4 py-2.5 capitalize text-brand-ink">{r.status}</td>
                  <td className="px-4 py-2.5">
                    <div className="flex items-center justify-end gap-1.5">
                      {r.patient_phone && (
                        <a href={`tel:${r.patient_phone.replace(/\s/g, '')}`} title={`Call ${r.patient_phone}`}
                          className={cn(btn, 'inline-flex items-center gap-1 border-brand-border text-brand-primary hover:bg-brand-surface')}>
                          <Phone size={12} /> Call
                        </a>
                      )}
                      {r.status === 'due' && (
                        <button type="button" onClick={() => setStatus(r.id, 'contacted')}
                          className={cn(btn, 'border-brand-border text-brand-ink hover:bg-brand-surface')}>Contacted</button>
                      )}
                      {(r.status === 'due' || r.status === 'contacted') && (
                        <button type="button" onClick={() => setStatus(r.id, 'booked')}
                          className={cn(btn, 'border-emerald-300 bg-emerald-50 text-emerald-700 hover:bg-emerald-100')}>Booked</button>
                      )}
                    </div>
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
