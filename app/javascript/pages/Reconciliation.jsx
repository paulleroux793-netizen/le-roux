// Daily Reconciliation — the learning-loop dashboard.
//
// Compares what Elixir actually delivered today vs what Ivory predicted,
// and surfaces specific improvement suggestions Paul can act on.
//
// Paul, 2026-05-27: "What improvements can we make to Ivory so it can
// also get that result?"
import React from 'react'
import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../layouts/DashboardLayout'

const SEVERITY_STYLES = {
  high:   'border-rose-300  bg-rose-50  text-rose-900',
  medium: 'border-amber-300 bg-amber-50 text-amber-900',
  low:    'border-slate-200 bg-slate-50 text-slate-700',
}

function StatCard({ label, value, sub, tone }) {
  const toneClass = {
    good:    'bg-emerald-50  text-emerald-900 border-emerald-200',
    bad:     'bg-rose-50     text-rose-900    border-rose-200',
    neutral: 'bg-white       text-slate-900   border-slate-200',
  }[tone || 'neutral']
  return (
    <div className={`rounded-lg border ${toneClass} px-4 py-3`}>
      <div className="text-[10px] uppercase tracking-wider text-slate-500">{label}</div>
      <div className="mt-1 text-2xl font-semibold tabular-nums">{value}</div>
      {sub ? <div className="mt-0.5 text-[11px] text-slate-500">{sub}</div> : null}
    </div>
  )
}

function ImprovementCard({ s }) {
  const style = SEVERITY_STYLES[s.severity] || SEVERITY_STYLES.low
  return (
    <li className={`rounded-md border px-4 py-3 ${style}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <span className="text-[10px] uppercase tracking-wider font-semibold">{s.severity}</span>
            <span className="text-[10px] text-slate-500">{s.kind}</span>
          </div>
          <h3 className="mt-1 text-sm font-semibold">{s.title}</h3>
          <p className="mt-1 text-xs leading-relaxed">{s.detail}</p>
        </div>
      </div>
    </li>
  )
}

function PatientRow({ row }) {
  const im = row.ivory_match || {}
  const matchOk = !!im.appointment_id
  const hasGap = !matchOk || (im.predicted_estimate_zar && Math.abs(parseFloat(im.predicted_estimate_zar) - parseFloat(row.billed_zar)) > 200)
  return (
    <tr className={hasGap ? 'bg-rose-50/40' : ''}>
      <td className="px-3 py-2 text-xs font-semibold text-slate-700">{row.account_code}</td>
      <td className="px-3 py-2 text-xs">
        <div>{row.patient_name || '—'}</div>
        {row.dependant ? <div className="text-[10px] text-slate-500">({row.dependant})</div> : null}
      </td>
      <td className="px-3 py-2 text-xs text-right tabular-nums font-semibold">R{row.billed_zar}</td>
      <td className="px-3 py-2 text-xs text-right tabular-nums">R{row.paid_zar}</td>
      <td className="px-3 py-2 text-xs">
        <div className="flex flex-wrap gap-1">
          {row.codes.slice(0, 8).map((c, i) => (
            <span key={i} className="inline-block rounded bg-slate-100 px-1.5 py-0.5 text-[10px] font-mono">
              {c.code}{c.tooth ? `/${c.tooth}` : ''}
            </span>
          ))}
          {row.codes.length > 8 ? <span className="text-[10px] text-slate-500">+{row.codes.length - 8} more</span> : null}
        </div>
      </td>
      <td className="px-3 py-2 text-xs">
        {matchOk ? (
          <div>
            <Link href={`/appointments/${im.appointment_id}`} className="text-brand-primary hover:underline">#{im.appointment_id}</Link>
            <span className="ml-1 text-[10px] text-slate-500">({im.status})</span>
            <div className="mt-0.5 text-[10px] text-slate-600">
              {im.has_scribe ? '🎙 scribe' : '— no scribe'} {im.has_summary ? '· 📝 summary' : '· no summary'}
            </div>
          </div>
        ) : (
          <span className="text-[10px] text-rose-600 font-semibold">NO IVORY MATCH</span>
        )}
      </td>
      <td className="px-3 py-2 text-xs text-right tabular-nums">
        {im.predicted_estimate_zar ? (
          <>
            R{im.predicted_estimate_zar}
            {hasGap ? <div className="text-[10px] text-rose-600">gap</div> : null}
          </>
        ) : (
          <span className="text-[10px] text-slate-400">—</span>
        )}
      </td>
    </tr>
  )
}

export default function Reconciliation({ reconciliation, navigation, recent_imports }) {
  const r = reconciliation
  const triggerScan = () => router.post('/reconciliation/scan', { date: r.date })

  return (
    <DashboardLayout>
      {/* Header + date nav */}
      <header className="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
            Daily reconciliation
          </span>
          <h1 className="mt-2 text-2xl font-semibold text-brand-ink">{r.pretty_date}</h1>
          <p className="mt-1 text-sm text-slate-600">
            Comparing what Elixir actually delivered today against what Ivory predicted.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link href={`/reconciliation?date=${navigation.prev_date}`} className="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-xs hover:bg-slate-50">← Previous day</Link>
          <Link href={`/reconciliation?date=${navigation.today}`} className="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-xs hover:bg-slate-50">Today</Link>
          <Link href={`/reconciliation?date=${navigation.next_date}`} className="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-xs hover:bg-slate-50">Next day →</Link>
          <button onClick={triggerScan} className="rounded-md bg-brand-primary px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary/90">
            Scan Elixir folder
          </button>
        </div>
      </header>

      {/* Top stats */}
      <section className="mb-8 grid grid-cols-2 gap-3 md:grid-cols-5">
        <StatCard label="Elixir billed" value={`R${r.elixir_totals.billed_zar}`} sub={`${r.elixir_totals.procedures_billed} procedures · ${r.elixir_totals.unique_patients} patients`} />
        <StatCard label="Elixir received" value={`R${r.elixir_totals.received_zar}`} sub="card / cash / EFT today" />
        <StatCard label="Ivory invoiced" value={`R${r.ivory_totals.invoiced_zar}`} sub={`${r.ivory_totals.appointments_today} appointments today`} />
        <StatCard label="Gap" value={`R${r.delta.billed_vs_invoiced_zar}`} sub="Elixir minus Ivory" tone={parseFloat(r.delta.billed_vs_invoiced_zar) === 0 ? 'good' : 'bad'} />
        <StatCard label="Scribe coverage" value={`${r.delta.scribe_coverage_pct}%`} sub={`${r.ivory_totals.with_scribe} / ${r.ivory_totals.appointments_today} appointments`} tone={r.delta.scribe_coverage_pct >= 80 ? 'good' : 'bad'} />
      </section>

      {/* Patient diff table */}
      <section className="mb-8 rounded-lg border border-slate-200 bg-white">
        <header className="border-b border-slate-200 px-4 py-3">
          <h2 className="text-sm font-semibold text-slate-700">Per-patient comparison</h2>
          <p className="mt-0.5 text-xs text-slate-500">
            One row per Elixir billing account. Rows highlighted pink = Ivory has no match OR predicted estimate differs by &gt;R200.
          </p>
        </header>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-slate-200">
            <thead className="bg-slate-50">
              <tr className="text-left text-[10px] uppercase tracking-wider text-slate-500">
                <th className="px-3 py-2">Account</th>
                <th className="px-3 py-2">Patient</th>
                <th className="px-3 py-2 text-right">Billed</th>
                <th className="px-3 py-2 text-right">Paid</th>
                <th className="px-3 py-2">Codes</th>
                <th className="px-3 py-2">Ivory match</th>
                <th className="px-3 py-2 text-right">Ivory predicted</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {r.patient_rows.length === 0 ? (
                <tr><td colSpan={7} className="px-3 py-6 text-center text-xs text-slate-500">No Elixir transactions imported for this date yet. Click "Scan Elixir folder" above.</td></tr>
              ) : (
                r.patient_rows.map((row, i) => <PatientRow key={i} row={row} />)
              )}
            </tbody>
          </table>
        </div>
      </section>

      {/* Improvement suggestions */}
      <section className="mb-8">
        <header className="mb-3">
          <h2 className="text-sm font-semibold text-slate-700">Improvement suggestions</h2>
          <p className="mt-0.5 text-xs text-slate-500">
            Specific, actionable changes Ivory should make so it can produce today's result tomorrow.
          </p>
        </header>
        {r.improvements.length === 0 ? (
          <div className="rounded-md border border-emerald-200 bg-emerald-50 px-4 py-3 text-xs text-emerald-900">
            Nothing to suggest — Ivory matched Elixir on every dimension we currently check. Either we're doing very well, or there are no comparisons available yet.
          </div>
        ) : (
          <ul className="space-y-2">
            {r.improvements.map((s, i) => <ImprovementCard key={i} s={s} />)}
          </ul>
        )}
      </section>

      {/* Imports table */}
      <section className="mb-8 rounded-lg border border-slate-200 bg-white">
        <header className="border-b border-slate-200 px-4 py-3">
          <h2 className="text-sm font-semibold text-slate-700">Recent Elixir mirror imports</h2>
        </header>
        <table className="min-w-full divide-y divide-slate-200 text-xs">
          <thead className="bg-slate-50 text-[10px] uppercase tracking-wider text-slate-500">
            <tr>
              <th className="px-3 py-2 text-left">File</th>
              <th className="px-3 py-2 text-left">Kind</th>
              <th className="px-3 py-2 text-left">Status</th>
              <th className="px-3 py-2 text-right">Rows</th>
              <th className="px-3 py-2 text-left">Finished</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {recent_imports.length === 0 ? (
              <tr><td colSpan={5} className="px-3 py-6 text-center text-slate-500">No imports yet. Click "Scan Elixir folder" above.</td></tr>
            ) : (
              recent_imports.map(i => (
                <tr key={i.id}>
                  <td className="px-3 py-2">{i.file_name}</td>
                  <td className="px-3 py-2 font-mono text-[10px]">{i.file_kind}</td>
                  <td className="px-3 py-2">
                    {i.status === 'succeeded' ? <span className="text-emerald-700">✓ ok</span> :
                     i.status === 'failed'    ? <span className="text-rose-700">✗ {i.error_message?.slice(0, 80)}</span> :
                                                <span className="text-amber-700">{i.status}</span>}
                  </td>
                  <td className="px-3 py-2 text-right tabular-nums">{i.rows_inserted} / {i.rows_parsed}</td>
                  <td className="px-3 py-2 text-[10px] text-slate-500">{i.finished_at}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>
    </DashboardLayout>
  )
}
