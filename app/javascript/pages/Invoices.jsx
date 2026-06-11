import React from 'react'
import { Link } from '@inertiajs/react'
import { Receipt, ChevronRight } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const STATUS_STYLE = {
  open: 'bg-blue-50 text-blue-700 border-blue-200',
  part_paid: 'bg-amber-50 text-amber-700 border-amber-200',
  paid: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  written_off: 'bg-gray-100 text-gray-600 border-gray-200',
  void: 'bg-red-50 text-red-700 border-red-200',
}
const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

function Stat({ label, value }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-brand-ink">{value}</p>
    </div>
  )
}

export default function Invoices({ invoices = [], stats = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Receipt size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Invoices</h1>
          <p className="text-sm text-brand-muted">Patient-pay tax invoices — the document patients submit to their medical aid</p>
        </div>
      </div>

      <div className="mb-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="Invoices" value={stats.total ?? invoices.length} />
        <Stat label="Outstanding" value={stats.outstanding_count ?? '—'} />
        <Stat label="Owed" value={rand(stats.outstanding_amount)} />
      </div>

      {invoices.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center text-sm text-brand-muted">No invoices yet.</div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Number</th>
                <th className="px-4 py-3 font-semibold">Date</th>
                <th className="px-4 py-3 font-semibold">Patient</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 text-right font-semibold">Total</th>
                <th className="px-4 py-3 text-right font-semibold">Balance</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {invoices.map((i) => (
                <tr key={i.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 font-mono font-medium text-brand-ink">{i.number}</td>
                  {(() => {
                    const days = i.date ? Math.floor((new Date(new Date().toDateString()) - new Date(i.date)) / 86400000) : 0
                    const owes = (i.balance || 0) > 0 && !i.void && ['open', 'part_paid'].includes(i.status)
                    const tone = owes && days > 60 ? 'text-brand-danger font-medium' : owes && days > 30 ? 'text-amber-600 font-medium' : 'text-brand-muted'
                    return <td className={cn('px-4 py-2.5', tone)}>{fmtDate(i.date)}{owes && days > 30 ? ` · ${days}d overdue` : ''}</td>
                  })()}
                  <td className="px-4 py-2.5 text-brand-ink">{i.patient_name}</td>
                  <td className="px-4 py-2.5"><span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', STATUS_STYLE[i.status])}>{i.status}</span></td>
                  <td className="px-4 py-2.5 text-right text-brand-ink">{rand(i.total)}</td>
                  <td className="px-4 py-2.5 text-right text-brand-ink">{rand(i.balance)}</td>
                  <td className="px-4 py-2.5 text-right"><Link href={`/invoices/${i.id}`} className="inline-flex items-center text-brand-primary hover:underline">Open <ChevronRight size={14} /></Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
