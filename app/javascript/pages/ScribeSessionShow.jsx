import React from 'react'
import { Link } from '@inertiajs/react'
import { ArrowLeft, Mic, FileText, CheckCircle2 } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function ScribeSessionShow({ session = {} }) {
  const est = session.estimate
  return (
    <DashboardLayout>
      <Link href="/scribe-sessions" className="mb-4 inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
        <ArrowLeft size={14} /> All sessions
      </Link>

      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><Mic size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">{session.patient_name} — Scribe review</h1>
          <p className="text-sm text-brand-muted capitalize">Status: {session.status}</p>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div>
          <h2 className="mb-2 text-sm font-semibold text-brand-ink">Transcript (local)</h2>
          <div className="rounded-xl border border-brand-border bg-white p-4 text-sm text-brand-ink whitespace-pre-wrap">
            {session.transcript || 'No transcript.'}
          </div>

          <h2 className="mb-2 mt-5 text-sm font-semibold text-brand-ink">Extracted findings</h2>
          <div className="rounded-xl border border-brand-border bg-white">
            {(session.findings || []).map((f, i) => (
              <div key={i} className="flex items-center gap-2 border-b border-brand-border/50 px-4 py-2 text-sm last:border-0">
                <span className="font-mono text-brand-primary">{f.code}</span>
                <span className="text-brand-muted">tooth {f.tooth || '—'}</span>
                <span className="ml-auto truncate text-xs text-brand-muted">{f.note}</span>
              </div>
            ))}
            {(session.findings || []).length === 0 && <p className="px-4 py-3 text-xs text-brand-muted">No findings.</p>}
          </div>
        </div>

        <div>
          <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold text-brand-ink"><FileText size={15} /> Proposed estimate (review)</h2>
          {est ? (
            <div className="rounded-xl border border-brand-border bg-white p-4">
              <div className="mb-3 flex items-center justify-between">
                <span className="font-mono text-sm text-brand-ink">{est.number}</span>
                <span className="text-lg font-semibold text-brand-ink">{rand(est.total)}</span>
              </div>
              <table className="w-full text-sm">
                <tbody>
                  {(est.lines || []).map((l, i) => (
                    <tr key={i} className="border-t border-brand-border/40">
                      <td className="py-1.5 font-mono text-brand-ink">{l.code}</td>
                      <td className="py-1.5 text-brand-muted">{l.description}</td>
                      <td className="py-1.5 text-center text-brand-muted">{l.tooth || '—'}</td>
                      <td className="py-1.5 text-right text-brand-ink">{rand(l.fee)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <button className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-lg bg-brand-primary px-3 py-2 text-sm font-medium text-white opacity-60" disabled title="Review-and-confirm action (wired with auth)">
                <CheckCircle2 size={15} /> Accept & give to patient
              </button>
            </div>
          ) : (
            <p className="rounded-xl border border-dashed border-brand-border bg-white px-4 py-6 text-center text-sm text-brand-muted">No draft estimate.</p>
          )}
        </div>
      </div>
    </DashboardLayout>
  )
}
