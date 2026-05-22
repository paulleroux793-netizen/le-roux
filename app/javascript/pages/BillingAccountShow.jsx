import React from 'react'
import { Link } from '@inertiajs/react'
import { Wallet, ArrowLeft } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

export default function BillingAccountShow({ account = {} }) {
  return (
    <DashboardLayout>
      <Link href="/accounts" className="mb-4 inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
        <ArrowLeft size={14} /> Back to accounts
      </Link>

      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Wallet size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">{account.billing_name}</h1>
          <p className="text-sm text-brand-muted font-mono">{account.account_code}</p>
        </div>
      </div>

      <div className="mb-5 grid gap-3 sm:grid-cols-2">
        <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
          <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">Contact</p>
          <p className="mt-1 text-sm text-brand-ink">{account.phone || '—'}</p>
          <p className="text-sm text-brand-muted">{account.email || '—'}</p>
        </div>
        <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
          <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">Address</p>
          <p className="mt-1 text-sm text-brand-ink">{account.address || '—'}</p>
        </div>
      </div>

      <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
        <div className="border-b border-brand-border bg-brand-surface px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-brand-muted">
          Members on this account
        </div>
        <table className="w-full text-sm">
          <tbody>
            {(account.members || []).map((m) => (
              <tr key={m.id} className="border-b border-brand-border/60 last:border-0">
                <td className="px-4 py-2.5 text-brand-ink">{m.name}</td>
                <td className="px-4 py-2.5 text-brand-muted">{m.phone}</td>
                <td className="px-4 py-2.5 text-right text-xs text-brand-muted">{m.relationship}</td>
              </tr>
            ))}
            {(account.members || []).length === 0 && (
              <tr><td className="px-4 py-6 text-center text-brand-muted">No members linked yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </DashboardLayout>
  )
}
