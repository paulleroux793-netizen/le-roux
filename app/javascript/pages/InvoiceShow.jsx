import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { ArrowLeft, Printer, MessageCircle, Download, Wallet, Ban, Undo2, CreditCard } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import BrandLogo from '../components/BrandLogo'
import SmartBack from '../components/SmartBack'
import PaymentModal from '../components/PaymentModal'
import { cn } from '../lib/utils'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function InvoiceShow({ invoice = {}, practice = {}, patient = {} }) {
  const [payOpen, setPayOpen] = useState(false)
  const balance = Number(invoice.balance || 0)
  const isPaid  = balance <= 0 && !invoice.void
  const credit  = Number(invoice.credit_available || 0)

  const applyCredit = () => {
    if (!invoice.account_id) return
    router.post(`/accounts/${invoice.account_id}/apply_credit`, { invoice_id: invoice.id }, { preserveScroll: true })
  }
  const writeOff = () => {
    const reason = window.prompt('Write this invoice off as bad debt? Enter a reason:')
    if (reason === null) return
    router.post(`/invoices/${invoice.id}/write_off`, { reason }, { preserveScroll: true })
  }
  const reversePayment = (p) => {
    const reason = window.prompt(`Reverse this ${p.method?.toUpperCase()} payment of R${Number(p.amount).toFixed(2)}? Enter a reason:`)
    if (reason === null) return
    router.post(`/payments/${p.id}/reverse`, { reason }, { preserveScroll: true })
  }

  return (
    <DashboardLayout>
      <div className="mb-4 flex items-center justify-between no-print">
        <SmartBack fallback="/invoices" />
        <div className="flex flex-wrap gap-2">
          <button onClick={() => window.print()} className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-ink hover:bg-brand-surface">
            <Printer size={14} /> Print
          </button>
          <a
            href={`/invoices/${invoice.id}.pdf`}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-ink hover:bg-brand-surface"
          >
            <Download size={14} /> Download PDF
          </a>
          <button
            className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border bg-white px-3 py-1.5 text-sm text-brand-muted opacity-60"
            title="WhatsApp send activates after the Twilio media-URL config is verified — for now use Print or Download PDF"
            disabled
          >
            <MessageCircle size={14} /> Send on WhatsApp
          </button>
          <button
            onClick={() => setPayOpen(true)}
            disabled={invoice.void}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-semibold shadow-sm',
              isPaid
                ? 'border border-brand-border bg-white text-brand-ink hover:bg-brand-surface'
                : 'bg-emerald-600 text-white hover:bg-emerald-700',
            )}
            title={invoice.void ? 'Void invoice — cannot record payment' : isPaid ? 'Add another payment or record a refund' : 'Record a card/cash/EFT payment'}
          >
            <Wallet size={14} /> {isPaid ? 'Add payment' : `Record payment · R${balance.toFixed(2)}`}
          </button>
          {credit > 0 && balance > 0 && invoice.writeable && (
            <button onClick={applyCredit} title={`Apply R${credit.toFixed(2)} account credit to this invoice`}
              className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-300 bg-indigo-50 px-3 py-1.5 text-sm font-medium text-indigo-700 hover:bg-indigo-100">
              <CreditCard size={14} /> Apply credit · R{credit.toFixed(2)}
            </button>
          )}
          {invoice.writeable && balance > 0 && (
            <button onClick={writeOff} title="Write off as bad debt"
              className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-muted hover:bg-brand-surface">
              <Ban size={14} /> Write off
            </button>
          )}
        </div>
      </div>

      <PaymentModal open={payOpen} onClose={() => setPayOpen(false)} invoice={invoice} />

      {/* The compliant invoice document */}
      <div className="print-document mx-auto max-w-3xl rounded-xl border border-brand-border bg-white p-8 shadow-sm">
        {invoice.void && (
          <div className="mb-4 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-center text-sm font-semibold text-red-700">VOID</div>
        )}

        {/* Header — practice + practitioner identifiers (mandatory for the patient's self-claim) */}
        <div className="flex items-start justify-between border-b border-brand-border pb-5">
          <div>
            {/* Real logo if provided (public/brand/logo.png), else gold wordmark */}
            <BrandLogo className="h-14" />
            <p className="mt-2 text-xs text-brand-muted">{practice.address}</p>
            <p className="text-xs text-brand-muted">{practice.phone} · {practice.email}</p>
            <div className="mt-2 space-y-0.5 text-xs text-brand-ink">
              <p><span className="text-brand-muted">Practitioner:</span> {practice.practitioner}</p>
              <p><span className="text-brand-muted">HPCSA:</span> {practice.hpcsa} &nbsp; <span className="text-brand-muted">BHF practice no:</span> {practice.bhf}</p>
              <p><span className="text-brand-muted">Company reg:</span> {practice.company_reg}{practice.vat_registered && practice.vat_number ? ` · VAT ${practice.vat_number}` : ' · Not VAT-registered'}</p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-xs uppercase tracking-wide text-brand-muted">Tax Invoice</p>
            <p className="font-mono text-sm font-semibold text-brand-ink">{invoice.number}</p>
            <p className="mt-1 text-xs text-brand-muted">Date: {fmtDate(invoice.date)}</p>
            {!isPaid && !invoice.void && invoice.date && (() => {
              const days = Math.floor((new Date(new Date().toDateString()) - new Date(invoice.date)) / 86400000)
              if (days <= 30) return null
              return <p className={`mt-1 inline-block rounded-md px-2 py-0.5 text-xs font-semibold ${days > 60 ? 'bg-brand-danger/10 text-brand-danger' : 'bg-amber-50 text-amber-700'}`}>{days} days overdue</p>
            })()}
          </div>
        </div>

        {/* Patient + scheme (for self-claim) */}
        <div className="grid grid-cols-2 gap-4 border-b border-brand-border py-4 text-sm">
          <div>
            <p className="text-xs uppercase tracking-wide text-brand-muted">Patient</p>
            <p className="font-medium text-brand-ink">{patient.name}</p>
            <p className="text-brand-muted">{patient.phone}</p>
            {invoice.provider_name && <p className="mt-1 text-brand-muted"><span className="text-xs uppercase tracking-wide">Provider:</span> {invoice.provider_name}</p>}
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-brand-muted">Medical aid (for your claim)</p>
            <p className="text-brand-ink">{patient.scheme || '— Private —'}</p>
            {patient.member_number && <p className="text-brand-muted">Member no: {patient.member_number}</p>}
          </div>
        </div>

        {/* Lines — code + tooth + Medical / Self / Amount per line (matches the practice format) */}
        <table className="mt-4 w-full text-sm">
          <thead className="border-b border-brand-border text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="py-2 font-semibold">Code</th>
              <th className="py-2 font-semibold">Description</th>
              <th className="py-2 text-center font-semibold">Tooth</th>
              <th className="py-2 text-center font-semibold">Qty</th>
              <th className="py-2 text-right font-semibold">Medical</th>
              <th className="py-2 text-right font-semibold">Self</th>
              <th className="py-2 text-right font-semibold">Amount</th>
            </tr>
          </thead>
          <tbody>
            {(invoice.lines || []).map((l, i) => (
              <tr key={i} className="border-b border-brand-border/50">
                <td className="py-2 font-mono text-brand-ink">{l.code}</td>
                <td className="py-2 text-brand-ink">
                  {l.description}{l.vat_treatment === 'standard' ? ' (incl. 15% VAT)' : ''}
                  {l.icd10_code && <span className="ml-2 text-xs text-brand-muted">ICD-10: {l.icd10_code}</span>}
                </td>
                <td className="py-2 text-center text-brand-muted">{l.tooth_number || '—'}</td>
                <td className="py-2 text-center text-brand-muted">{l.quantity}</td>
                <td className="py-2 text-right text-brand-muted">{rand(l.medical)}</td>
                <td className="py-2 text-right text-brand-muted">{rand(l.self_portion)}</td>
                <td className="py-2 text-right text-brand-ink">{rand(l.line_total)}</td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* Totals */}
        <div className="mt-4 ml-auto w-64 space-y-1 text-sm">
          <div className="flex justify-between text-brand-muted"><span>Medical (claim from your aid)</span><span>{rand(invoice.medical_total)}</span></div>
          <div className="flex justify-between text-brand-muted"><span>Self (you pay)</span><span>{rand(invoice.self_total)}</span></div>
          <div className="flex justify-between text-brand-muted"><span>VAT (incl.)</span><span>{rand(invoice.vat)}</span></div>
          <div className="flex justify-between border-t border-brand-border pt-1 font-semibold text-brand-ink"><span>Total</span><span>{rand(invoice.total)}</span></div>
          <div className="flex justify-between text-brand-muted"><span>Paid</span><span>{rand(invoice.paid)}</span></div>
          <div className={cn('flex justify-between font-semibold', invoice.balance > 0 ? 'text-brand-danger' : 'text-emerald-600')}><span>Balance due</span><span>{rand(invoice.balance)}</span></div>
        </div>

        <div className="mt-6 border-t border-brand-border pt-4 text-xs text-brand-muted">
          <p className="font-medium text-brand-ink">Payment / banking</p>
          <p>{practice.bank}</p>
          <p className="mt-2">This statement may be submitted to your medical aid for reimbursement. The practice does not claim on your behalf.</p>
        </div>

        {/* R1.5 — payments timeline (visible on-screen + in print) */}
        {(invoice.payments || []).length > 0 && (
          <div className="mt-6 border-t border-brand-border pt-4">
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-brand-muted">Payments received</p>
            <table className="w-full text-sm">
              <tbody>
                {invoice.payments.map((p) => (
                  <tr key={p.id} className={cn('border-b border-brand-border/40 last:border-0', p.reversed && 'opacity-50')}>
                    <td className="py-1.5 text-brand-muted">{fmtDate(p.received_at)}</td>
                    <td className="py-1.5 capitalize text-brand-ink">{p.method}{p.kind === 'credit_applied' ? ' (credit)' : ''}{p.reversed ? ' · reversed' : ''}</td>
                    <td className="py-1.5 text-xs text-brand-muted">{p.reference || p.notes || ''}</td>
                    <td className={cn('py-1.5 text-right font-medium', p.reversed ? 'text-brand-muted line-through' : 'text-emerald-700')}>{rand(p.amount)}</td>
                    <td className="py-1.5 pl-3 text-right no-print">
                      <a href={`/payments/${p.id}/receipt`} target="_blank" rel="noreferrer" className="text-xs text-brand-primary hover:underline">Receipt</a>
                      {!p.reversed && (p.kind === 'payment') && (
                        <button onClick={() => reversePayment(p)} title="Reverse this payment"
                          className="ml-2 inline-flex items-center gap-0.5 text-xs text-brand-danger hover:underline">
                          <Undo2 size={11} /> Reverse
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
