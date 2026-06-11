import React, { useState, useMemo } from 'react'
import { Link } from '@inertiajs/react'
import { FileText, ChevronRight, Download } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

// Lifecycle tracker colours (Paul 2026-06-07): green = accepted / treatment done,
// blue = patient has booked the appointment in the diary, yellow = outstanding.
const LIFECYCLE = {
  green:  { dot: 'bg-emerald-500', pill: 'bg-emerald-50 text-emerald-700 border-emerald-200', label: 'Done' },
  blue:   { dot: 'bg-blue-500',    pill: 'bg-blue-50 text-blue-700 border-blue-200',          label: 'Booked' },
  yellow: { dot: 'bg-amber-400',   pill: 'bg-amber-50 text-amber-800 border-amber-200',       label: 'Outstanding' },
}
const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
// Compact rand for the pipeline chips (R1.2m / R450k / R1,234).
const randK = (n) => { n = n || 0; return n >= 1e6 ? `R${(n / 1e6).toFixed(1)}m` : n >= 1e3 ? `R${Math.round(n / 1e3)}k` : `R${Math.round(n)}` }
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function Estimates({ estimates = [], stats = {} }) {
  const [filter, setFilter] = useState('all')
  const [query, setQuery] = useState('')
  const filtered = useMemo(() => {
    const c = filter === 'all' ? null : filter === 'outstanding' ? 'yellow' : filter === 'booked' ? 'blue' : 'green'
    const q = query.trim().toLowerCase()
    return estimates.filter((e) =>
      (!c || e.status_colour === c) &&
      (!q || `${e.patient_name} ${e.number} ${e.account_code || ''}`.toLowerCase().includes(q))
    )
  }, [estimates, filter, query])

  const TABS = [
    { key: 'all',         label: 'All',         count: stats.total ?? estimates.length, dot: null },
    { key: 'outstanding', label: 'Outstanding', count: stats.outstanding ?? 0, value: stats.outstanding_value, dot: 'bg-amber-400' },
    { key: 'booked',      label: 'Booked',      count: stats.booked ?? 0,      value: stats.booked_value,      dot: 'bg-blue-500' },
    { key: 'done',        label: 'Done',        count: stats.done ?? 0,        value: stats.done_value,        dot: 'bg-emerald-500' },
  ]

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <FileText size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Estimates tracker</h1>
          <p className="text-sm text-brand-muted">Every estimate, colour-coded by where it stands — at a glance, who's had a quote and whether they're coming.</p>
        </div>
      </div>

      {/* Filter tabs + colour legend */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setFilter(t.key)}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm font-medium transition',
              filter === t.key ? 'border-brand-primary bg-brand-primary/5 text-brand-ink' : 'border-brand-border bg-white text-brand-muted hover:border-brand-primary'
            )}
          >
            {t.dot && <span className={cn('h-2 w-2 rounded-full', t.dot)} />}
            {t.label} <span className="text-xs text-brand-muted">({t.count}{t.value != null ? ` · ${randK(t.value)}` : ''})</span>
          </button>
        ))}
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Filter by patient, number, account…"
          className="ml-1 w-60 rounded-lg border border-brand-border px-3 py-1.5 text-sm focus:border-brand-primary focus:outline-none"
        />
        <a
          href="/estimates.csv"
          className="ml-auto inline-flex items-center gap-1.5 rounded-lg border border-brand-border bg-white px-3 py-1.5 text-sm font-medium text-brand-muted transition hover:border-brand-primary hover:text-brand-ink"
        >
          <Download size={14} /> Export CSV
        </a>
      </div>

      {(stats.aged ?? 0) > 0 && (
        <button
          type="button"
          onClick={() => setFilter('outstanding')}
          className="mb-3 flex w-full items-center gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-left text-sm text-amber-800 hover:bg-amber-100"
        >
          <span className="font-semibold">{stats.aged} overdue follow-up{stats.aged === 1 ? '' : 's'}</span>
          <span className="text-amber-700">— outstanding estimates older than 30 days{stats.aged_value ? ` · ${randK(stats.aged_value)}` : ''}. Worth a call.</span>
        </button>
      )}

      {filtered.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">No estimates in this view.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-3 py-3 font-semibold">Status</th>
                <th className="px-3 py-3 font-semibold">Number</th>
                <th className="px-3 py-3 font-semibold">Patient</th>
                <th className="px-3 py-3 font-semibold">Account</th>
                <th className="px-3 py-3 font-semibold">Date sent</th>
                <th className="px-3 py-3 font-semibold">Last activity</th>
                <th className="px-3 py-3 font-semibold">Treatment</th>
                <th className="px-3 py-3 font-semibold">Dr</th>
                <th className="px-3 py-3 text-right font-semibold">Value</th>
                <th className="px-3 py-3" />
              </tr>
            </thead>
            <tbody>
              {filtered.map((e) => {
                const lc = LIFECYCLE[e.status_colour] || LIFECYCLE.yellow
                return (
                  <tr key={e.id} className={cn('border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50', e.aged && 'border-l-4 border-l-amber-400')}>
                    <td className="px-3 py-2.5">
                      <span className={cn('inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 text-xs font-medium', lc.pill)}>
                        <span className={cn('h-2 w-2 rounded-full', lc.dot)} />{lc.label}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 font-mono font-medium text-brand-ink">{e.number}</td>
                    <td className="px-3 py-2.5"><Link href={`/patients/${e.patient_id}`} className="text-brand-ink hover:text-brand-primary hover:underline" title="Open patient to follow up">{e.patient_name}</Link></td>
                    <td className="px-3 py-2.5 font-mono text-xs text-brand-muted">{e.account_code || '—'}</td>
                    <td className="px-3 py-2.5 text-brand-muted">{fmtDate(e.date_sent)}</td>
                    <td className="px-3 py-2.5 text-brand-muted">{fmtDate(e.last_activity)}</td>
                    <td className="px-3 py-2.5 max-w-xs truncate text-brand-ink" title={e.details || ''}>{e.details || '—'}</td>
                    <td className="px-3 py-2.5 text-xs text-brand-muted">{e.provider_name || '—'}</td>
                    <td className="px-3 py-2.5 text-right text-brand-ink">{rand(e.total)}</td>
                    <td className="px-3 py-2.5 text-right"><Link href={`/estimates/${e.id}`} className="inline-flex items-center text-brand-primary hover:underline">Open <ChevronRight size={14} /></Link></td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
