import React from 'react'
import { router } from '@inertiajs/react'
import { Receipt, Download, FileText } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const titleize = (s) => (s || '').toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase())
const PERIODS = [['day', 'Day'], ['month', 'Month'], ['year', 'Year']]

function Kpi({ label, value, accent }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className={`mt-1 text-2xl font-semibold ${accent || 'text-brand-ink'}`}>{value}</p>
    </div>
  )
}

export default function TransactionReport({ period = 'day', date = '', label = '', rows = [], totals_by_method = {}, total = 0, count = 0, turnover_by_provider = [], turnover_total = 0 }) {
  const reload = (next) =>
    router.get('/reporting/transactions', { period, date, ...next }, { preserveState: true, preserveScroll: true, replace: true })
  const qs = `period=${period}&date=${date}`

  return (
    <DashboardLayout>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><Receipt size={18} className="text-white" /></div>
          <div>
            <h1 className="text-xl font-semibold text-brand-ink">Transaction report</h1>
            <p className="text-sm text-brand-muted">Money received — {label}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <a href={`/reporting/transactions.csv?${qs}`}
             className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border bg-white px-3 py-2 text-sm font-medium text-brand-ink hover:bg-brand-surface">
            <Download size={15} /> Excel
          </a>
          <a href={`/reporting/transactions.pdf?${qs}`} target="_blank" rel="noreferrer"
             className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-2 text-sm font-medium text-white hover:bg-brand-primary-dark">
            <FileText size={15} /> PDF
          </a>
        </div>
      </div>

      {/* Period + date controls */}
      <div className="mb-5 flex flex-wrap items-center gap-3">
        <div className="inline-flex overflow-hidden rounded-lg border border-brand-border">
          {PERIODS.map(([key, lbl]) => (
            <button key={key} onClick={() => reload({ period: key })}
              className={`px-4 py-2 text-sm font-medium transition-colors ${period === key ? 'bg-brand-primary text-white' : 'bg-white text-brand-ink hover:bg-brand-surface'}`}>
              {lbl}
            </button>
          ))}
        </div>
        <input type="date" value={date} onChange={(e) => reload({ date: e.target.value })}
          className="rounded-lg border border-brand-border bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary/30" />
      </div>

      {/* Totals by method */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <Kpi label="Card" value={rand(totals_by_method.card)} />
        <Kpi label="Cash" value={rand(totals_by_method.cash)} />
        <Kpi label="EFT" value={rand(totals_by_method.eft)} />
        <Kpi label="Credit applied" value={rand(totals_by_method.credit)} />
        <Kpi label="Total received" value={rand(total)} accent="text-emerald-600" />
      </div>

      {/* Turnover by dentist — every charge code billed (the Elixir Transaction Analysis) */}
      {turnover_by_provider.length > 0 && (
        <div className="mt-8">
          <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Turnover by dentist — charge codes billed ({label})</p>
            <p className="text-sm font-semibold text-brand-ink">Total turnover {rand(turnover_total)}</p>
          </div>

          {/* per-dentist totals */}
          <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {turnover_by_provider.map((p) => (
              <div key={p.provider} className="rounded-xl border border-brand-border bg-white px-5 py-4">
                <p className="truncate text-xs font-medium uppercase tracking-wide text-brand-muted">{titleize(p.provider)}</p>
                <p className="mt-1 text-2xl font-semibold text-brand-ink">{rand(p.total)}</p>
                <p className="text-[11px] text-brand-muted">{p.count} charge-code line(s)</p>
              </div>
            ))}
          </div>

          {/* per-dentist detail */}
          {turnover_by_provider.map((p) => (
            <div key={p.provider} className="mb-5 overflow-hidden rounded-xl border border-brand-border bg-white">
              <div className="flex items-center justify-between border-b border-brand-border bg-brand-surface/60 px-4 py-2">
                <span className="text-sm font-semibold text-brand-ink">{titleize(p.provider)}</span>
                <span className="text-sm font-semibold text-emerald-600">{rand(p.total)}</span>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wide text-brand-muted">
                    <tr>
                      <th className="px-3 py-2 font-semibold">Date</th>
                      <th className="px-3 py-2 font-semibold">Patient</th>
                      <th className="px-3 py-2 font-semibold">Tooth</th>
                      <th className="px-3 py-2 font-semibold">Code</th>
                      <th className="px-3 py-2 font-semibold">Description</th>
                      <th className="px-3 py-2 text-center font-semibold">Units</th>
                      <th className="px-3 py-2 text-right font-semibold">Amount</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-brand-border/50">
                    {p.lines.map((l, i) => (
                      <tr key={i} className="hover:bg-brand-surface/30">
                        <td className="whitespace-nowrap px-3 py-1.5 text-brand-muted">{l.date}</td>
                        <td className="px-3 py-1.5 font-medium text-brand-ink">{l.patient}</td>
                        <td className="px-3 py-1.5 text-brand-muted">{l.tooth || '—'}</td>
                        <td className="px-3 py-1.5 font-medium text-brand-ink">{l.code}</td>
                        <td className="px-3 py-1.5 text-brand-muted">{l.description}</td>
                        <td className="px-3 py-1.5 text-center text-brand-muted">{l.units}</td>
                        <td className="whitespace-nowrap px-3 py-1.5 text-right font-medium text-brand-ink">{rand(l.total)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {p.truncated && (
                <p className="px-4 py-2 text-[11px] text-brand-muted">Showing first 300 of {p.count} lines — download the Excel or PDF for the full detail.</p>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Payments received to accounts */}
      <p className="mt-8 mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Payments received — to accounts</p>
      <div className="mt-6 overflow-hidden rounded-xl border border-brand-border bg-white">
        <table className="w-full text-sm">
          <thead className="bg-brand-surface/60 text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-2.5 font-semibold">Date / time</th>
              <th className="px-4 py-2.5 font-semibold">Patient / account</th>
              <th className="px-4 py-2.5 font-semibold">Method</th>
              <th className="px-4 py-2.5 font-semibold">Type</th>
              <th className="px-4 py-2.5 font-semibold">Reference</th>
              <th className="px-4 py-2.5 text-right font-semibold">Amount</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-brand-border/60">
            {rows.length === 0 ? (
              <tr><td colSpan={6} className="px-4 py-10 text-center text-brand-muted">No transactions in this period.</td></tr>
            ) : (
              rows.map((r, i) => (
                <tr key={i} className="hover:bg-brand-surface/30">
                  <td className="whitespace-nowrap px-4 py-2 text-brand-muted">{r.time}</td>
                  <td className="px-4 py-2 font-medium text-brand-ink">{r.party}</td>
                  <td className="px-4 py-2"><span className="rounded-full bg-brand-surface px-2 py-0.5 text-xs capitalize">{r.method}</span></td>
                  <td className="px-4 py-2 capitalize text-brand-muted">{(r.kind || '').replace('_', ' ')}</td>
                  <td className="px-4 py-2 text-brand-muted">{r.reference || '—'}</td>
                  <td className={`whitespace-nowrap px-4 py-2 text-right font-semibold ${r.amount < 0 ? 'text-brand-danger' : 'text-brand-ink'}`}>{rand(r.amount)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs text-brand-muted">{count} transaction(s) — {label}</p>
    </DashboardLayout>
  )
}
