import React, { useEffect, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import { CreditCard, Banknote, Building2 } from 'lucide-react'
import Modal from './Modal'
import { cn } from '../lib/utils'

// R1.5 — Record-payment modal. Card / cash / EFT, full or partial.
// Defaults to the outstanding balance so the common case ("pay it off")
// is one click. Reference field auto-shows for EFT (proof of payment ref).

const METHODS = [
  { value: 'card', label: 'Card',  icon: CreditCard, hint: 'Yoco / Zapper tap' },
  { value: 'cash', label: 'Cash',  icon: Banknote,   hint: 'Counted at reception' },
  { value: 'eft',  label: 'EFT',   icon: Building2,  hint: 'Bank transfer' },
]

export default function PaymentModal({ open, onClose, invoice = {} }) {
  const balance = Math.max(0, Number(invoice.balance || 0))
  const [amount, setAmount]     = useState('')
  const [method, setMethod]     = useState('card')
  const [reference, setReference] = useState('')
  const [notes, setNotes]       = useState('')
  const [saving, setSaving]     = useState(false)

  useEffect(() => {
    if (!open) return
    setAmount(balance > 0 ? balance.toFixed(2) : '')
    setMethod('card'); setReference(''); setNotes(''); setSaving(false)
  }, [open, balance])

  const submit = () => {
    const amt = parseFloat(amount)
    if (!amt || amt <= 0) { toast.error('Enter an amount greater than R0'); return }
    setSaving(true)
    router.post(`/invoices/${invoice.id}/payments`, {
      amount: amt, method, reference: reference || null, notes: notes || null,
    }, {
      preserveScroll: true,
      onSuccess: (page) => {
        toast.success(page?.props?.flash?.notice || 'Payment recorded')
        onClose?.()
      },
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not record'),
      onFinish: () => setSaving(false),
    })
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Record payment"
      size="md"
      footer={
        <>
          <button type="button" onClick={onClose}
            className="rounded-2xl px-4 py-2 text-sm font-medium text-brand-muted hover:bg-brand-surface/45 hover:text-brand-ink">
            Cancel
          </button>
          <button type="button" onClick={submit} disabled={saving}
            className="rounded-2xl bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">
            Record payment
          </button>
        </>
      }
    >
      <div className="space-y-4">
        {balance > 0 ? (
          <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800">
            Outstanding balance: <strong>R{balance.toLocaleString('en-ZA', { minimumFractionDigits: 2 })}</strong>
          </div>
        ) : (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
            Invoice already paid in full. You can still record a refund/credit if needed.
          </div>
        )}

        <div>
          <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Method</label>
          <div className="grid grid-cols-3 gap-2">
            {METHODS.map((m) => {
              const Icon = m.icon
              const active = method === m.value
              return (
                <button key={m.value} type="button" onClick={() => setMethod(m.value)}
                  className={cn(
                    'flex flex-col items-center gap-1 rounded-xl border px-3 py-3 text-sm font-medium transition-colors',
                    active
                      ? 'border-brand-primary bg-brand-primary/5 text-brand-primary ring-2 ring-brand-primary/30'
                      : 'border-brand-border bg-white text-brand-ink hover:bg-brand-surface'
                  )}>
                  <Icon size={20} />
                  {m.label}
                  <span className="text-[10px] text-brand-muted">{m.hint}</span>
                </button>
              )
            })}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Amount (R)</label>
            <input type="number" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)}
              className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
            {balance > 0 && (
              <button type="button" onClick={() => setAmount(balance.toFixed(2))}
                className="mt-1 text-xs text-brand-primary hover:underline">
                Pay full balance (R{balance.toFixed(2)})
              </button>
            )}
          </div>
          {method === 'eft' && (
            <div>
              <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-brand-muted">EFT reference</label>
              <input type="text" value={reference} onChange={(e) => setReference(e.target.value)}
                placeholder="e.g. POP-1234"
                className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
            </div>
          )}
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Notes (optional)</label>
          <textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)}
            className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
        </div>
      </div>
    </Modal>
  )
}
