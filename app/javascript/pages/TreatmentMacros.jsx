import React, { useState } from 'react'
import { Layers, ChevronDown, ChevronRight, FlaskConical } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function TreatmentMacros({ macros = [], stats = {} }) {
  const [open, setOpen] = useState(null)

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Layers size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Treatment Macros</h1>
          <p className="text-sm text-brand-muted">
            {stats.total ?? macros.length} bundles · {stats.lines ?? '—'} lines — one click charts a whole procedure
          </p>
        </div>
      </div>

      <div className="space-y-2">
        {macros.map((m) => {
          const isOpen = open === m.id
          return (
            <div key={m.id} className="overflow-hidden rounded-xl border border-brand-border bg-white">
              <button
                onClick={() => setOpen(isOpen ? null : m.id)}
                className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-brand-surface/50"
              >
                {isOpen ? <ChevronDown size={16} className="text-brand-muted" /> : <ChevronRight size={16} className="text-brand-muted" />}
                <span className="font-mono text-sm font-semibold text-brand-primary">{m.access_code}</span>
                <span className="text-sm text-brand-ink">{m.name}</span>
                {m.laboratory && (
                  <span className="inline-flex items-center gap-1 rounded-md border border-amber-200 bg-amber-50 px-1.5 py-0.5 text-[11px] font-medium text-amber-700">
                    <FlaskConical size={11} /> Lab
                  </span>
                )}
                <span className="ml-auto text-xs text-brand-muted">{m.line_count} lines</span>
                <span className="w-24 text-right text-sm font-medium text-brand-ink">{rand(m.estimated_total)}</span>
              </button>

              {isOpen && (
                <div className="border-t border-brand-border bg-brand-surface/30 px-4 py-2">
                  <table className="w-full text-sm">
                    <thead className="text-left text-xs uppercase tracking-wide text-brand-muted">
                      <tr>
                        <th className="py-1.5 font-semibold">Code</th>
                        <th className="py-1.5 font-semibold">Description</th>
                        <th className="py-1.5 text-center font-semibold">Qty</th>
                        <th className="py-1.5 text-right font-semibold">Line total</th>
                      </tr>
                    </thead>
                    <tbody>
                      {m.items.map((i, idx) => (
                        <tr key={idx} className="border-t border-brand-border/40">
                          <td className="py-1.5 font-mono text-brand-ink">{i.tariff_code}</td>
                          <td className="py-1.5 text-brand-muted">{i.description || '—'}</td>
                          <td className="py-1.5 text-center text-brand-ink">{i.quantity}</td>
                          <td className="py-1.5 text-right text-brand-ink">{rand(i.line_total)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </DashboardLayout>
  )
}
