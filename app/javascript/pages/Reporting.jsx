import React from 'react'
import { BarChart3 } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

function Kpi({ label, value, accent }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className={`mt-1 text-2xl font-semibold ${accent || 'text-brand-ink'}`}>{value}</p>
    </div>
  )
}

export default function Reporting({ kpis = {}, production_by_setting = {}, invoices_by_status = {}, production_by_provider = [], aged_debt = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><BarChart3 size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Reporting</h1>
          <p className="text-sm text-brand-muted">Practice KPIs — production, collections, outstanding</p>
        </div>
      </div>

      {/* Financial KPIs */}
      <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Money</p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Production (month)" value={rand(kpis.production_month)} />
        <Kpi label="Collections (month)" value={rand(kpis.collections_month)} accent="text-emerald-600" />
        <Kpi label="Collection rate"
             value={kpis.collection_rate == null ? '—' : `${kpis.collection_rate}%`}
             accent={kpis.collection_rate != null && kpis.collection_rate >= 98 ? 'text-emerald-600' : 'text-amber-600'} />
        <Kpi label="Outstanding" value={rand(kpis.outstanding)} accent="text-brand-danger" />
        <Kpi label="Invoices" value={kpis.invoices_total ?? 0} />
      </div>

      {/* Aged debt — outstanding bucketed by age since invoice date (chase 90+) */}
      <p className="mt-6 mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Aged debt (outstanding by age)</p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Current (0–30d)" value={rand(aged_debt.current)} />
        <Kpi label="31–60 days" value={rand(aged_debt.d31_60)} accent={(aged_debt.d31_60 || 0) > 0 ? 'text-amber-600' : undefined} />
        <Kpi label="61–90 days" value={rand(aged_debt.d61_90)} accent={(aged_debt.d61_90 || 0) > 0 ? 'text-amber-600' : undefined} />
        <Kpi label="90+ days" value={rand(aged_debt.d90plus)} accent={(aged_debt.d90plus || 0) > 0 ? 'text-brand-danger' : undefined} />
      </div>

      {/* Production by dentist — owner sees Dr Chalita vs Dr Eliska at a glance */}
      {production_by_provider.length > 0 && (
        <>
          <p className="mt-6 mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Production by dentist (month)</p>
          <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
            <table className="w-full text-sm">
              <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
                <tr><th className="px-4 py-2.5 font-semibold">Dentist</th><th className="px-4 py-2.5 text-right font-semibold">Production</th><th className="px-4 py-2.5 text-right font-semibold">Invoices</th></tr>
              </thead>
              <tbody>
                {production_by_provider.map((p) => (
                  <tr key={p.provider} className="border-b border-brand-border/60 last:border-0">
                    <td className="px-4 py-2.5 text-brand-ink">{p.provider}</td>
                    <td className="px-4 py-2.5 text-right font-medium text-brand-ink">{rand(p.production)}</td>
                    <td className="px-4 py-2.5 text-right text-brand-muted">{p.invoices}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {/* C3 — Clinical-context KPIs the competitors don't surface as cleanly */}
      <p className="mt-6 mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Clinical performance</p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Case acceptance"
             value={kpis.case_acceptance_rate == null ? '—' : `${kpis.case_acceptance_rate}%`}
             accent={kpis.case_acceptance_rate != null && kpis.case_acceptance_rate >= 70 ? 'text-emerald-600' : 'text-amber-600'} />
        <Kpi label="Estimates issued (month)" value={kpis.estimates_this_month ?? 0} />
        <Kpi label="Treatment completion (Q)"
             value={kpis.treatment_completion_rate == null ? '—' : `${kpis.treatment_completion_rate}%`}
             accent="text-brand-primary" />
        <Kpi label="Chair hours today" value={`${kpis.chair_hours_today ?? 0} h`} />
        <Kpi label="No-show rate (90d)"
             value={kpis.no_show_rate == null ? '—' : `${kpis.no_show_rate}%`}
             accent={kpis.no_show_rate == null ? undefined : kpis.no_show_rate <= 5 ? 'text-emerald-600' : kpis.no_show_rate <= 10 ? 'text-amber-600' : 'text-brand-danger'} />
      </div>

      {/* Operational backlog */}
      <p className="mt-6 mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Backlog</p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Open courses" value={kpis.courses_open ?? 0} />
        <Kpi label="Open estimates" value={kpis.estimates_open ?? 0} />
        <Kpi label="Imaging to match" value={kpis.imaging_needs_match ?? 0} accent="text-amber-600" />
        <Kpi label="Recalls due" value={kpis.recalls_due ?? 0} />
      </div>

      <div className="mt-6 grid gap-6 sm:grid-cols-2">
        <div className="rounded-xl border border-brand-border bg-white p-5">
          <h2 className="mb-3 text-sm font-semibold text-brand-ink">Courses by setting</h2>
          {Object.entries(production_by_setting).map(([k, v]) => (
            <div key={k} className="flex justify-between border-b border-brand-border/40 py-1.5 text-sm last:border-0">
              <span className="capitalize text-brand-muted">{k.replace('_', ' ')}</span><span className="text-brand-ink">{v}</span>
            </div>
          ))}
          {Object.keys(production_by_setting).length === 0 && <p className="text-xs text-brand-muted">No data yet.</p>}
        </div>
        <div className="rounded-xl border border-brand-border bg-white p-5">
          <h2 className="mb-3 text-sm font-semibold text-brand-ink">Invoices by status</h2>
          {Object.entries(invoices_by_status).map(([k, v]) => (
            <div key={k} className="flex justify-between border-b border-brand-border/40 py-1.5 text-sm last:border-0">
              <span className="capitalize text-brand-muted">{k.replace('_', ' ')}</span><span className="text-brand-ink">{v}</span>
            </div>
          ))}
          {Object.keys(invoices_by_status).length === 0 && <p className="text-xs text-brand-muted">No data yet.</p>}
        </div>
      </div>
    </DashboardLayout>
  )
}
