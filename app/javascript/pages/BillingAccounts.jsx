import React from 'react'
import { Link } from '@inertiajs/react'
import { Wallet, ChevronRight } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import DataTable from '../components/DataTable'

export default function BillingAccounts({ accounts = [], stats = {} }) {
  const columns = [
    {
      accessorKey: 'account_code',
      header: 'Account',
      cell: ({ getValue }) => (
        <span className="font-mono font-medium text-brand-ink">{getValue() || '—'}</span>
      ),
    },
    {
      accessorKey: 'billing_name',
      header: 'Billing name',
      cell: ({ row }) => (
        <Link href={`/accounts/${row.original.id}`} className="text-sm font-medium text-brand-ink hover:text-brand-primary hover:underline">
          {row.original.billing_name}
        </Link>
      ),
    },
    {
      accessorKey: 'phone',
      header: 'Phone',
      cell: ({ getValue }) => <span className="text-sm text-brand-muted">{getValue() || '—'}</span>,
    },
    {
      accessorKey: 'member_count',
      header: 'Members',
      cell: ({ getValue }) => <span className="text-sm text-brand-ink">{getValue()}</span>,
    },
    {
      accessorKey: 'outstanding',
      header: 'Outstanding',
      cell: ({ getValue }) => {
        const v = getValue()
        return v > 0
          ? <span className="text-sm font-medium text-brand-danger">R{Number(v).toLocaleString('en-ZA', { minimumFractionDigits: 2 })}</span>
          : <span className="text-sm text-brand-muted">—</span>
      },
    },
    {
      id: 'view',
      header: '',
      enableSorting: false,
      enableGlobalFilter: false,
      cell: ({ row }) => (
        <Link href={`/accounts/${row.original.id}`} className="inline-flex items-center text-brand-primary hover:underline">
          View <ChevronRight size={14} />
        </Link>
      ),
    },
  ]

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
          <p className="text-sm text-brand-muted">No accounts yet.</p>
        </div>
      ) : (
        <DataTable
          columns={columns}
          data={accounts}
          pageSize={5000}
          globalFilterPlaceholder="Search accounts by code, name, or phone…"
        />
      )}
    </DashboardLayout>
  )
}
