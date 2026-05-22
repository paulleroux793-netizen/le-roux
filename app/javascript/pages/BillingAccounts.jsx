import React from 'react'
import { Link } from '@inertiajs/react'
import { Wallet, ChevronRight } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

export default function BillingAccounts({ accounts = [], stats = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Wallet size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Billing Accounts</h1>
          <p className="text-sm text-brand-muted">{stats.total ?? accounts.length} accounts — the unit that pays (family or individual)</p>
        </div>
      </div>

      {accounts.length === 0 ? (
        <div className="rounded-xl border border-dashed border-brand-border bg-white px-6 py-12 text-center">
          <p className="text-sm text-brand-muted">
            No accounts yet. They populate once the patient import is run (pending the patient-identity
            decision — see the build uncertainties).
          </p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Account</th>
                <th className="px-4 py-3 font-semibold">Billing name</th>
                <th className="px-4 py-3 font-semibold">Phone</th>
                <th className="px-4 py-3 text-center font-semibold">Members</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {accounts.map((a) => (
                <tr key={a.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 font-mono font-medium text-brand-ink">{a.account_code || '—'}</td>
                  <td className="px-4 py-2.5 text-brand-ink">{a.billing_name}</td>
                  <td className="px-4 py-2.5 text-brand-muted">{a.phone || '—'}</td>
                  <td className="px-4 py-2.5 text-center text-brand-ink">{a.member_count}</td>
                  <td className="px-4 py-2.5 text-right">
                    <Link href={`/accounts/${a.id}`} className="inline-flex items-center text-brand-primary hover:underline">
                      View <ChevronRight size={14} />
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  )
}
