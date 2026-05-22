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

export default function Reporting({ kpis = {}, production_by_setting = {}, invoices_by_status = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><BarChart3 size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Reporting</h1>
          <p className="text-sm text-brand-muted">Practice KPIs — production, collections, outstanding</p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Production (month)" value={rand(kpis.production_month)} />
        <Kpi label="Collections (month)" value={rand(kpis.collections_month)} accent="text-emerald-600" />
        <Kpi label="Outstanding" value={rand(kpis.outstanding)} accent="text-brand-danger" />
        <Kpi label="Open courses" value={kpis.courses_open ?? 0} />
        <Kpi label="Open estimates" value={kpis.estimates_open ?? 0} />
        <Kpi label="Invoices" value={kpis.invoices_total ?? 0} />
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
