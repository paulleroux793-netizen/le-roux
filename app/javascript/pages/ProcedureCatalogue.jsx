import React, { useMemo, useState } from 'react'
import { Stethoscope, Search } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const CATEGORY_COLORS = {
  diagnostic:  'bg-blue-50 text-blue-700 border-blue-200',
  restorative: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  surgical:    'bg-red-50 text-red-700 border-red-200',
  preventive:  'bg-teal-50 text-teal-700 border-teal-200',
  cosmetic:    'bg-purple-50 text-purple-700 border-purple-200',
  other:       'bg-gray-50 text-gray-700 border-gray-200',
}

const rand = (n) => (n == null ? '—' : `R${n.toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`)

function Stat({ label, value }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-brand-ink">{value}</p>
    </div>
  )
}

export default function ProcedureCatalogue({ codes = [], stats = {} }) {
  const [q, setQ] = useState('')
  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase()
    if (!s) return codes
    return codes.filter((c) => c.code.toLowerCase().includes(s) || (c.description || '').toLowerCase().includes(s))
  }, [q, codes])

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Stethoscope size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Procedure Catalogue</h1>
          <p className="text-sm text-brand-muted">SADA tariff codes, fees, and VAT treatment</p>
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Codes" value={stats.total ?? codes.length} />
        <Stat label="Priced" value={stats.priced ?? '—'} />
        <Stat label="Zero-rated" value={stats.zero_rated ?? '—'} />
        <Stat label="VAT 15%" value={stats.standard_rated ?? '—'} />
      </div>

      <div className="mb-3 flex items-center gap-2 rounded-xl border border-brand-border bg-white px-3 py-2">
        <Search size={15} className="text-brand-muted" />
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search code or description…"
          className="w-full bg-transparent text-sm outline-none placeholder:text-brand-muted"
        />
      </div>

      <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-3 font-semibold">Code</th>
              <th className="px-4 py-3 font-semibold">Description</th>
              <th className="px-4 py-3 font-semibold">Category</th>
              <th className="px-4 py-3 font-semibold">VAT</th>
              <th className="px-4 py-3 text-right font-semibold">Fee</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((c) => (
              <tr key={c.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                <td className="px-4 py-2.5 font-mono font-medium text-brand-ink">{c.code}</td>
                <td className="px-4 py-2.5 text-brand-ink">{c.description}</td>
                <td className="px-4 py-2.5">
                  <span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', CATEGORY_COLORS[c.category] || CATEGORY_COLORS.other)}>
                    {c.category}
                  </span>
                </td>
                <td className="px-4 py-2.5 text-xs text-brand-muted">{c.vat_treatment === 'standard' ? '15%' : 'Zero'}</td>
                <td className="px-4 py-2.5 text-right font-medium text-brand-ink">{rand(c.fee)}</td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-8 text-center text-brand-muted">No codes match “{q}”.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </DashboardLayout>
  )
}
