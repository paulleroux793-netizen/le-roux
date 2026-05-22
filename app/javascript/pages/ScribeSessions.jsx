import React from 'react'
import { Link } from '@inertiajs/react'
import { Mic, ChevronRight, Sparkles } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const STATUS_STYLE = {
  recording: 'bg-red-50 text-red-700 border-red-200',
  transcribing: 'bg-amber-50 text-amber-700 border-amber-200',
  drafted: 'bg-blue-50 text-blue-700 border-blue-200',
  reviewed: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  discarded: 'bg-gray-100 text-gray-500 border-gray-200',
}

export default function ScribeSessions({ sessions = [], stats = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><Mic size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">AI Chair-side Scribe</h1>
          <p className="text-sm text-brand-muted">Local transcription → drafted estimates the dentist reviews. Audio never leaves the practice PC.</p>
        </div>
      </div>

      <div className="mb-5 flex items-start gap-2 rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800">
        <Sparkles size={16} className="mt-0.5 flex-shrink-0" />
        <p>The scribe drafts a proposed plan + estimate for review. It <strong>never auto-charts or auto-bills</strong> — Dr Chalita confirms every line.</p>
      </div>

      {sessions.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">No scribe sessions yet.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Patient</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 text-center font-semibold">Findings</th>
                <th className="px-4 py-3 font-semibold">Draft estimate</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {sessions.map((s) => (
                <tr key={s.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 text-brand-ink">{s.patient_name}</td>
                  <td className="px-4 py-2.5"><span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', STATUS_STYLE[s.status])}>{s.status}</span></td>
                  <td className="px-4 py-2.5 text-center text-brand-ink">{s.finding_count}</td>
                  <td className="px-4 py-2.5 font-mono text-xs text-brand-muted">{s.estimate_number || '—'}</td>
                  <td className="px-4 py-2.5 text-right"><Link href={`/scribe-sessions/${s.id}`} className="inline-flex items-center text-brand-primary hover:underline">Review <ChevronRight size={14} /></Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
