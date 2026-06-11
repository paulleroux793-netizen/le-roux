import React from 'react'
import { FlaskConical, Clock } from 'lucide-react'
import { router, Link } from '@inertiajs/react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'
const today = () => new Date().toISOString().slice(0, 10)

export default function Lab({ out_at_lab = [], returned = [], stats = {} }) {
  // Tick a case back in via the SAME endpoint the treatment plan uses (no new API).
  const markReturned = (id) =>
    router.patch(`/treatment_items/${id}`, { lab_returned_on: today() }, { preserveScroll: true })

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><FlaskConical size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Lab cases</h1>
          <p className="text-sm text-brand-muted">{stats.out ?? 0} out at the lab — chase overdue cases and tick them in when they return.</p>
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-3">
        {[
          { label: 'Out at lab', value: stats.out ?? 0, tone: 'text-brand-ink' },
          { label: 'Overdue', value: stats.overdue ?? 0, tone: 'text-brand-danger' },
          { label: 'Returned (30d)', value: stats.returned_30d ?? 0, tone: 'text-emerald-600' },
        ].map((s) => (
          <div key={s.label} className="rounded-xl border border-brand-border bg-white px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">{s.label}</p>
            <p className={cn('mt-0.5 text-2xl font-bold', s.tone)}>{s.value}</p>
          </div>
        ))}
      </div>

      {/* Out at the lab */}
      <h2 className="mb-2 text-sm font-semibold text-brand-ink">Out at the lab</h2>
      {out_at_lab.length === 0 ? (
        <div className="mb-8 rounded-xl border border-dashed border-brand-border bg-white px-6 py-10 text-center text-sm text-brand-muted">
          Nothing is out at the lab right now. Send a case from a patient's treatment plan.
        </div>
      ) : (
        <div className="mb-8 overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-2 font-semibold">Patient</th>
                <th className="px-4 py-2 font-semibold">Procedure</th>
                <th className="px-4 py-2 font-semibold">Lab</th>
                <th className="px-4 py-2 font-semibold">Sent</th>
                <th className="px-4 py-2 font-semibold">Due back</th>
                <th className="px-4 py-2" />
              </tr>
            </thead>
            <tbody className="divide-y divide-brand-border">
              {out_at_lab.map((c) => (
                <tr key={c.id} className={cn(c.overdue && 'bg-red-50/60')}>
                  <td className="px-4 py-2 font-medium text-brand-ink">
                    {c.patient_id
                      ? <Link href={`/patients/${c.patient_id}`} className="hover:underline">{c.patient_name || '—'}</Link>
                      : (c.patient_name || '—')}
                  </td>
                  <td className="px-4 py-2 text-brand-muted">{c.description || '—'}{c.tooth ? ` · #${c.tooth}` : ''}</td>
                  <td className="px-4 py-2 text-brand-muted">{c.lab_name || '—'}</td>
                  <td className="px-4 py-2 text-brand-muted">{fmtDate(c.sent_on)}</td>
                  <td className={cn('px-4 py-2 font-medium', c.overdue ? 'text-brand-danger' : 'text-brand-ink')}>
                    {fmtDate(c.due_on)}
                    {c.overdue && <span className="ml-1 inline-flex items-center gap-0.5 text-[11px]"><Clock size={11} /> overdue</span>}
                  </td>
                  <td className="px-4 py-2 text-right">
                    <button type="button" onClick={() => markReturned(c.id)}
                      className="rounded-lg border border-indigo-300 bg-indigo-50 px-2.5 py-1 text-xs font-medium text-indigo-700 transition hover:bg-indigo-100">
                      Mark returned
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Recently returned */}
      <h2 className="mb-2 text-sm font-semibold text-brand-ink">Recently returned</h2>
      {returned.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-8 text-center text-sm text-brand-muted">No cases returned in the last 30 days.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <tbody className="divide-y divide-brand-border">
              {returned.map((c) => (
                <tr key={c.id}>
                  <td className="px-4 py-2 font-medium text-brand-ink">
                    {c.patient_id
                      ? <Link href={`/patients/${c.patient_id}`} className="hover:underline">{c.patient_name || '—'}</Link>
                      : (c.patient_name || '—')}
                  </td>
                  <td className="px-4 py-2 text-brand-muted">{c.description || '—'}{c.tooth ? ` · #${c.tooth}` : ''}</td>
                  <td className="px-4 py-2 text-brand-muted">{c.lab_name || '—'}</td>
                  <td className="px-4 py-2 text-emerald-600">returned {fmtDate(c.returned_on)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
