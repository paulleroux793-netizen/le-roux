import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { Wallet, ArrowLeft, FileText, Printer } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

const rand = (n) => `R${(Number(n) || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const dz = (iso) => (iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—')

function Stat({ label, value, accent }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className={`mt-1 text-xl font-semibold ${accent || 'text-brand-ink'}`}>{value}</p>
    </div>
  )
}

export default function BillingAccountShow({
  account = {}, period = {}, balance = {}, opening_balance = 0, closing_balance = 0, transactions = [], invoices = [],
}) {
  const [from, setFrom] = useState(period.from || '')
  const [to, setTo]     = useState(period.to || '')

  const applyRange = () => router.get(`/accounts/${account.id}`, { from, to }, { preserveScroll: true, preserveState: true })
  const statementUrl = `/accounts/${account.id}/statement.pdf?from=${from}&to=${to}`

  const askMethod = () => (window.prompt('Method: card / cash / eft', 'card') || '').toLowerCase()
  const takePayment = () => {
    const amount = window.prompt('Account payment (R) — settles oldest invoices first, remainder to credit:')
    if (!amount) return
    const method = askMethod(); if (!method) return
    router.post(`/accounts/${account.id}/receive_payment`, { amount, method }, { preserveScroll: true })
  }
  const takeDeposit = () => {
    const amount = window.prompt('Deposit (R) — banked as account credit:')
    if (!amount) return
    const method = askMethod(); if (!method) return
    router.post(`/accounts/${account.id}/deposit`, { amount, method }, { preserveScroll: true })
  }
  const takeRefund = () => {
    const amount = window.prompt(`Refund from credit (available R${Number(balance.credit || 0).toFixed(2)}):`)
    if (!amount) return
    const method = askMethod(); if (!method) return
    const reason = window.prompt('Reason (optional):') || ''
    router.post(`/accounts/${account.id}/refund`, { amount, method, reason }, { preserveScroll: true })
  }

  return (
    <DashboardLayout>
      <Link href="/accounts" className="mb-4 inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
        <ArrowLeft size={14} /> Back to accounts
      </Link>

      <div className="mb-5 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Wallet size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">{account.billing_name}</h1>
          <p className="font-mono text-sm text-brand-muted">{account.account_code}</p>
        </div>
      </div>

      {/* Balance summary */}
      <div className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Total billed" value={rand(balance.billed)} />
        <Stat label="Total paid" value={rand(balance.paid)} />
        <Stat label="Outstanding" value={rand(balance.outstanding)} accent={(balance.outstanding || 0) > 0 ? 'text-brand-danger' : 'text-emerald-600'} />
        <Stat label="Credit available" value={rand(balance.credit)} accent={(balance.credit || 0) > 0 ? 'text-indigo-600' : 'text-brand-muted'} />
      </div>

      {/* Account-level money actions */}
      <div className="mb-5 flex flex-wrap gap-2">
        <button onClick={takePayment} className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-emerald-700">
          <Wallet size={14} /> Take payment
        </button>
        <button onClick={takeDeposit} className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-300 bg-indigo-50 px-3 py-1.5 text-sm font-medium text-indigo-700 hover:bg-indigo-100">
          Deposit (credit)
        </button>
        {(balance.credit || 0) > 0 && (
          <button onClick={takeRefund} className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-muted hover:bg-brand-surface">
            Refund credit
          </button>
        )}
      </div>

      {/* Date range + statement */}
      <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-brand-border bg-white p-4">
        <div>
          <label className="block text-xs font-medium text-brand-muted">From</label>
          <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="mt-1 rounded-md border border-brand-border px-2 py-1.5 text-sm" />
        </div>
        <div>
          <label className="block text-xs font-medium text-brand-muted">To</label>
          <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="mt-1 rounded-md border border-brand-border px-2 py-1.5 text-sm" />
        </div>
        <button onClick={applyRange} className="rounded-lg border border-brand-border px-3 py-2 text-sm font-medium text-brand-ink hover:bg-brand-surface">View transactions</button>
        <a href={statementUrl} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-2 text-sm font-semibold text-white hover:brightness-95">
          <Printer size={14} /> Statement (PDF)
        </a>
      </div>

      {/* Transactions ledger */}
      <div className="mb-5 overflow-hidden rounded-xl border border-brand-border bg-white">
        <div className="border-b border-brand-border bg-brand-surface px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-brand-muted">
          Transactions · {dz(period.from)} – {dz(period.to)}
        </div>
        <table className="w-full text-sm">
          <thead className="border-b border-brand-border text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-2 font-semibold">Date</th>
              <th className="px-4 py-2 font-semibold">Reference</th>
              <th className="px-4 py-2 font-semibold">Description</th>
              <th className="px-4 py-2 text-right font-semibold">Debit</th>
              <th className="px-4 py-2 text-right font-semibold">Credit</th>
              <th className="px-4 py-2 text-right font-semibold">Balance</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-b border-brand-border/60 italic text-brand-muted">
              <td className="px-4 py-2">{dz(period.from)}</td><td /><td className="px-4 py-2">Opening balance</td><td /><td /><td className="px-4 py-2 text-right">{rand(opening_balance)}</td>
            </tr>
            {transactions.map((t, i) => (
              <tr key={i} className="border-b border-brand-border/40">
                <td className="px-4 py-2 text-brand-ink">{dz(t.date)}</td>
                <td className="px-4 py-2 font-mono text-xs text-brand-muted">{t.ref}</td>
                <td className="px-4 py-2 text-brand-ink">{t.description}</td>
                <td className="px-4 py-2 text-right text-brand-ink">{t.debit > 0 ? rand(t.debit) : ''}</td>
                <td className="px-4 py-2 text-right text-emerald-700">{t.credit > 0 ? rand(t.credit) : ''}</td>
                <td className="px-4 py-2 text-right text-brand-ink">{rand(t.balance)}</td>
              </tr>
            ))}
            <tr className="bg-brand-surface/60 font-semibold">
              <td className="px-4 py-2">{dz(period.to)}</td><td /><td className="px-4 py-2">Closing balance</td><td /><td /><td className="px-4 py-2 text-right">{rand(closing_balance)}</td>
            </tr>
            {transactions.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-6 text-center text-brand-muted">No transactions in this period.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Invoices (each is a tax invoice for its date) */}
      {invoices.length > 0 && (
        <div className="mb-5 overflow-hidden rounded-xl border border-brand-border bg-white">
          <div className="border-b border-brand-border bg-brand-surface px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-brand-muted">
            Tax invoices
          </div>
          <table className="w-full text-sm">
            <tbody>
              {invoices.map((inv) => (
                <tr key={inv.id} className="border-b border-brand-border/40 last:border-0">
                  <td className="px-4 py-2 text-brand-muted">{dz(inv.date)}</td>
                  <td className="px-4 py-2"><Link href={`/invoices/${inv.id}`} className="inline-flex items-center gap-1.5 font-mono text-brand-primary hover:underline"><FileText size={13} /> {inv.number}</Link></td>
                  <td className="px-4 py-2 text-xs text-brand-muted">{inv.provider}</td>
                  <td className="px-4 py-2 text-right text-brand-ink">{rand(inv.total)}</td>
                  <td className="px-4 py-2 text-right text-xs"><span className="rounded-md bg-brand-surface px-2 py-0.5 text-brand-muted">{inv.status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Members */}
      <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
        <div className="border-b border-brand-border bg-brand-surface px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-brand-muted">
          Members on this account
        </div>
        <table className="w-full text-sm">
          <thead className="border-b border-brand-border text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-2 font-semibold">Member</th>
              <th className="px-4 py-2 font-semibold">Next appointment</th>
              <th className="px-4 py-2 text-right font-semibold">Owes</th>
              <th className="px-4 py-2" />
            </tr>
          </thead>
          <tbody>
            {(account.members || []).map((m) => (
              <tr key={m.id} className="border-b border-brand-border/60 last:border-0">
                <td className="px-4 py-2.5">
                  <Link href={`/patients/${m.id}`} className="text-brand-ink hover:underline">{m.name}</Link>
                  <span className="ml-1 text-xs text-brand-muted">· {m.relationship}</span>
                </td>
                <td className="px-4 py-2.5 text-brand-muted">
                  {m.next_appointment
                    ? new Date(m.next_appointment).toLocaleString('en-ZA', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
                    : <span className="text-brand-muted/60">— none booked —</span>}
                </td>
                <td className="px-4 py-2.5 text-right">{(m.outstanding || 0) > 0 ? <span className="font-medium text-brand-danger">{rand(m.outstanding)}</span> : <span className="text-brand-muted">—</span>}</td>
                <td className="px-4 py-2.5 text-right"><Link href={`/patients/${m.id}`} className="text-xs font-medium text-brand-primary hover:underline">Book / view →</Link></td>
              </tr>
            ))}
            {(account.members || []).length === 0 && (
              <tr><td colSpan={4} className="px-4 py-6 text-center text-brand-muted">No members linked yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </DashboardLayout>
  )
}
