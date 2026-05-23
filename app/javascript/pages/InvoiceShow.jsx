import React from 'react'
import { Link } from '@inertiajs/react'
import { ArrowLeft, Printer, MessageCircle } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import BrandLogo from '../components/BrandLogo'
import { cn } from '../lib/utils'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function InvoiceShow({ invoice = {}, practice = {}, patient = {} }) {
  return (
    <DashboardLayout>
      <div className="mb-4 flex items-center justify-between no-print">
        <Link href="/invoices" className="inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
          <ArrowLeft size={14} /> All invoices
        </Link>
        <div className="flex gap-2">
          <button onClick={() => window.print()} className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-ink hover:bg-brand-surface">
            <Printer size={14} /> Print / PDF
          </button>
          <button className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-1.5 text-sm text-white opacity-60" title="Phase 3.3 stub — wired to WhatsApp later" disabled>
            <MessageCircle size={14} /> Send on WhatsApp
          </button>
        </div>
      </div>

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
          </div>
        </div>

        {/* Patient + scheme (for self-claim) */}
        <div className="grid grid-cols-2 gap-4 border-b border-brand-border py-4 text-sm">
          <div>
            <p className="text-xs uppercase tracking-wide text-brand-muted">Patient</p>
            <p className="font-medium text-brand-ink">{patient.name}</p>
            <p className="text-brand-muted">{patient.phone}</p>
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
      </div>
    </DashboardLayout>
  )
}
