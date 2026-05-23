import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { toast } from 'sonner'
import { ArrowLeft, Printer, MessageCircle, Info, Download, ThumbsUp } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import BrandLogo from '../components/BrandLogo'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function EstimateShow({ estimate = {}, practice = {}, patient = {} }) {
  const multiVisit = (estimate.visits || []).length > 1
  const [accepting, setAccepting] = useState(false)
  const isAccepted = estimate.status === 'accepted'

  const acceptEstimate = () => {
    if (!confirm(`Patient accepts this R${(estimate.total || 0).toLocaleString('en-ZA')} estimate? An invoice will be created and the estimate locked.`)) return
    setAccepting(true)
    router.post(`/estimates/${estimate.id}/accept_and_invoice`, {}, {
      onSuccess: (page) => toast.success(page?.props?.flash?.notice || 'Accepted'),
      onError:   (errs) => toast.error(Object.values(errs || {})[0] || 'Could not accept'),
      onFinish:  () => setAccepting(false),
    })
  }

  return (
    <DashboardLayout>
      <div className="mb-4 flex items-center justify-between no-print">
        <Link href="/estimates" className="inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
          <ArrowLeft size={14} /> All estimates
        </Link>
        <div className="flex flex-wrap gap-2">
          <button onClick={() => window.print()} className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-ink hover:bg-brand-surface">
            <Printer size={14} /> Print
          </button>
          <a
            href={`/estimates/${estimate.id}.pdf`}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm text-brand-ink hover:bg-brand-surface"
          >
            <Download size={14} /> Download PDF
          </a>
          <button
            className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border bg-white px-3 py-1.5 text-sm text-brand-muted opacity-60"
            disabled
            title="WhatsApp send activates after the Twilio media-URL config is verified — for now use Print or Download PDF"
          >
            <MessageCircle size={14} /> Send on WhatsApp
          </button>
          <button
            onClick={acceptEstimate}
            disabled={isAccepted || accepting}
            className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-emerald-700 disabled:opacity-50"
            title={isAccepted ? 'Already accepted' : 'Patient accepts the quote — convert to invoice'}
          >
            <ThumbsUp size={14} /> {isAccepted ? 'Accepted' : 'Accept estimate'}
          </button>
        </div>
      </div>

      <div className="print-document mx-auto max-w-3xl rounded-xl border border-brand-border bg-white p-8 shadow-sm">
        {/* Header — brand wordmark + practice identifiers */}
        <div className="flex items-start justify-between border-b border-brand-border pb-5">
          <div>
            <BrandLogo className="h-14" />
            <p className="mt-2 text-xs text-brand-muted">{practice.address}</p>
            <p className="text-xs text-brand-muted">{practice.phone} · {practice.email}</p>
            <p className="mt-2 text-xs text-brand-ink"><span className="text-brand-muted">HPCSA:</span> {practice.hpcsa} &nbsp; <span className="text-brand-muted">Practice no:</span> {practice.bhf} &nbsp; <span className="text-brand-muted">VAT:</span> {practice.vat_number}</p>
          </div>
          <div className="text-right">
            <p className="text-xs uppercase tracking-wide text-brand-muted">Estimate</p>
            <p className="font-mono text-sm font-semibold text-brand-ink">{estimate.number}</p>
            <p className="mt-1 text-xs text-brand-muted">Date: {fmtDate(estimate.date)}</p>
          </div>
        </div>

        {/* Patient + scheme */}
        <div className="grid grid-cols-2 gap-4 border-b border-brand-border py-4 text-sm">
          <div>
            <p className="text-xs uppercase tracking-wide text-brand-muted">Estimate for</p>
            <p className="font-medium text-brand-ink">{patient.name}</p>
            <p className="text-brand-muted">{patient.phone}</p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-brand-muted">Medical aid (for your claim)</p>
            <p className="text-brand-ink">{patient.scheme || '— Private —'}</p>
            {patient.member_number && <p className="text-brand-muted">Member no: {patient.member_number}</p>}
          </div>
        </div>

        {/* Multi-visit explainer (replaces the confusing "phases") */}
        {multiVisit && (
          <div className="mt-4 flex items-start gap-2 rounded-md border border-brand-border bg-brand-surface px-3 py-2 text-xs text-brand-ink">
            <Info size={14} className="mt-0.5 flex-shrink-0 text-brand-primary" />
            <p>This treatment is planned over <strong>{estimate.visits.length} visits</strong> — each visit is a separate appointment. The grouping below shows what is planned for each visit.</p>
          </div>
        )}

        {/* Lines grouped by visit */}
        {(estimate.visits || []).map((v) => (
          <div key={v.visit} className="mt-4">
            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-brand-primary">Visit {v.visit}</p>
            <table className="w-full text-sm">
              <thead className="border-b border-brand-border text-left text-xs uppercase tracking-wide text-brand-muted">
                <tr>
                  <th className="py-1.5 font-semibold">Code</th>
                  <th className="py-1.5 font-semibold">Description</th>
                  <th className="py-1.5 text-center font-semibold">Tooth</th>
                  <th className="py-1.5 text-right font-semibold">Medical</th>
                  <th className="py-1.5 text-right font-semibold">Self</th>
                  <th className="py-1.5 text-right font-semibold">Amount</th>
                </tr>
              </thead>
              <tbody>
                {v.lines.map((l, i) => (
                  <tr key={i} className="border-b border-brand-border/40">
                    <td className="py-1.5 font-mono text-brand-ink">{l.code}</td>
                    <td className="py-1.5 text-brand-ink">
                      {l.description}
                      {l.icd10_code && <span className="ml-2 text-xs text-brand-muted">ICD-10: {l.icd10_code}</span>}
                    </td>
                    <td className="py-1.5 text-center text-brand-muted">{l.tooth_number || '—'}</td>
                    <td className="py-1.5 text-right text-brand-muted">{rand(l.medical)}</td>
                    <td className="py-1.5 text-right text-brand-muted">{rand(l.self_portion)}</td>
                    <td className="py-1.5 text-right text-brand-ink">{rand(l.line_total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}

        {/* Totals */}
        <div className="mt-4 ml-auto w-64 space-y-1 text-sm">
          <div className="flex justify-between text-brand-muted"><span>Medical (claim from your aid)</span><span>{rand(estimate.medical_total)}</span></div>
          <div className="flex justify-between text-brand-muted"><span>Self (you pay)</span><span>{rand(estimate.self_total)}</span></div>
          <div className="flex justify-between border-t border-brand-border pt-1 font-semibold text-brand-ink"><span>Total estimate</span><span>{rand(estimate.total)}</span></div>
        </div>

        <div className="mt-6 border-t border-brand-border pt-4 text-xs text-brand-muted">
          <p className="font-medium text-brand-ink">Payment / banking</p>
          <p>{practice.bank}</p>
          <p className="mt-3 font-semibold text-brand-ink">ESTIMATE VALID FOR 14 DAYS</p>
          <p className="mt-1">This is an estimate of planned treatment, not a final account. Actual fees may vary depending on what is clinically required on the day. You may submit the final invoice to your medical aid to claim back.</p>
        </div>
      </div>
    </DashboardLayout>
  )
}
