import React, { useState, useRef } from 'react'
import { Link, router } from '@inertiajs/react'
import { toast } from 'sonner'
import { ArrowLeft, Printer, MessageCircle, Info, Download, ThumbsUp, UploadCloud, Paperclip, X as XIcon, Sparkles } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import BrandLogo from '../components/BrandLogo'
import SmartBack from '../components/SmartBack'

const rand = (n) => `R${(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

const editCls = 'w-full rounded-md border border-brand-border bg-white px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary/40'
const EMPTY_LINE = { procedure_code_id: '', code: '', description: '', tooth_number: '', quantity: '1', fee: '' }

export default function EstimateShow({ estimate = {}, practice = {}, patient = {}, attachments = [], procedure_codes = [], favourite_codes = [], treatment_macros = [], suggested_macros = [], visit_reason = null, providers = [], as_invoice = false }) {
  const multiVisit = (estimate.visits || []).length > 1
  const [accepting, setAccepting] = useState(false)
  const [aiPrompt, setAiPrompt] = useState('')
  const [aiBusy, setAiBusy] = useState(false)
  const [noteDismissed, setNoteDismissed] = useState(false)
  const aiCompose = () => {
    if (!aiPrompt.trim()) return
    setAiBusy(true)
    router.post(`/estimates/${estimate.id}/ai_compose`, { prompt: aiPrompt }, {
      preserveScroll: true,
      onSuccess: () => setAiPrompt(''),
      onFinish: () => setAiBusy(false),
    })
  }
  const [dragOver, setDragOver]   = useState(false)
  // Patient view = hide tariff codes (plain-language only) for presenting to the patient.
  const [patientView, setPatientView] = useState(false)
  const isAccepted = estimate.status === 'accepted'

  // ── Editable line items: add a tariff code (with tooth/qty/fee), remove a line ──
  const [draft, setDraft] = useState(EMPTY_LINE)
  const [codeQuery, setCodeQuery] = useState('')
  const [picked, setPicked] = useState(false)
  const codeInputRef = useRef(null)
  const allLines = (estimate.visits || []).flatMap((v) => v.lines || [])

  const codeMatches = (!picked && codeQuery.trim().length >= 1)
    ? procedure_codes.filter((c) => `${c.code} ${c.description}`.toLowerCase().includes(codeQuery.trim().toLowerCase())).slice(0, 8)
    : []

  const pickCode = (pc) => {
    setDraft({ ...draft, procedure_code_id: pc.id, code: pc.code, description: pc.description, fee: pc.fee != null ? String(pc.fee) : '' })
    setCodeQuery(`${pc.code} · ${pc.description}`)
    setPicked(true)
  }
  const addLine = () => {
    if (!draft.procedure_code_id && !draft.code && !draft.description) { toast.error('Pick a tariff code or type a description'); return }
    router.post(`/estimates/${estimate.id}/lines`, { estimate_line: draft }, {
      preserveScroll: true,
      // Reset the draft and put the cursor straight back in the code field so the
      // next line can be typed without reaching for the mouse (keyboard-first flow).
      onSuccess: () => { toast.success('Line added'); setDraft(EMPTY_LINE); setCodeQuery(''); setPicked(false); codeInputRef.current?.focus() },
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not add line'),
    })
  }

  // Enter in the code box: first Enter picks the top autocomplete match; once a code
  // is chosen (or a free-text description typed) Enter adds the line. Esc clears.
  const onCodeKey = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      if (codeMatches.length > 0) { pickCode(codeMatches[0]) } else { addLine() }
    } else if (e.key === 'Escape') {
      e.preventDefault(); setCodeQuery(''); setPicked(false); setDraft(EMPTY_LINE)
    }
  }
  // Enter in tooth/qty/fee adds the line immediately (cursor returns to the code box).
  const onFieldKey = (e) => { if (e.key === 'Enter') { e.preventDefault(); addLine() } }

  // One-click add of a common code (the favourites chips) — no typing at all.
  const quickAdd = (pc) => {
    router.post(`/estimates/${estimate.id}/lines`, {
      estimate_line: { procedure_code_id: pc.id, code: pc.code, description: pc.description, tooth_number: '', quantity: '1', fee: pc.fee != null ? String(pc.fee) : '' },
    }, {
      preserveScroll: true,
      onSuccess: () => toast.success(`Added ${pc.code}`),
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not add line'),
    })
  }

  // Apply a whole visit-bundle macro (adds all its codes as lines at once).
  const applyMacro = (id) => {
    if (!id) return
    router.post(`/estimates/${estimate.id}/apply_macro`, { treatment_macro_id: id }, {
      preserveScroll: true,
      onSuccess: () => toast.success('Visit bundle added'),
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not add bundle'),
    })
  }
  const removeLine = (id) => {
    router.delete(`/estimate_lines/${id}`, { preserveScroll: true, onSuccess: () => toast.success('Line removed') })
  }

  const uploadFile = (file) => {
    const fd = new FormData()
    fd.append('file', file)
    router.post(`/estimates/${estimate.id}/upload_attachment`, fd, {
      preserveScroll: true,
      onSuccess: (page) => toast.success(page?.props?.flash?.notice || `Attached ${file.name}`),
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Upload failed'),
      forceFormData: true,
    })
  }
  const onDrop = (e) => {
    e.preventDefault(); setDragOver(false)
    const files = Array.from(e.dataTransfer.files || [])
    files.forEach(uploadFile)
  }
  const onPick = (e) => {
    Array.from(e.target.files || []).forEach(uploadFile)
    e.target.value = '' // reset so the same file can be re-picked
  }
  const removeAttachment = (id) => {
    if (!confirm('Remove this attachment?')) return
    router.delete(`/estimates/${estimate.id}/attachments/${id}`, {
      preserveScroll: true,
      onSuccess: () => toast.success('Removed'),
    })
  }

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
        <SmartBack fallback="/estimates" />
        <div className="flex flex-wrap gap-2">
          <button onClick={() => setPatientView((v) => !v)} className="inline-flex items-center gap-1.5 rounded-lg border border-brand-border px-3 py-1.5 text-sm font-medium text-brand-ink hover:bg-brand-surface" title="Switch between the clinical view (with tariff codes) and a patient-friendly view (plain language, no codes)">
            {patientView ? 'Clinical view' : 'Patient view'}
          </button>
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
            title={isAccepted ? 'Already accepted' : (as_invoice ? 'Finalise this as an invoice' : 'Patient accepts the quote — convert to invoice')}
          >
            <ThumbsUp size={14} /> {isAccepted ? (as_invoice ? 'Invoiced' : 'Accepted') : (as_invoice ? 'Create invoice' : 'Accept estimate')}
          </button>
        </div>
      </div>

      {estimate.ai_note && !noteDismissed && (
        <div className="mx-auto mb-3 flex max-w-3xl items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-800 no-print">
          <Sparkles size={15} className="mt-0.5 shrink-0" />
          <span className="flex-1"><span className="font-semibold">AI note — please confirm:</span> {estimate.ai_note}</span>
          <button type="button" onClick={() => setNoteDismissed(true)} className="shrink-0 text-amber-600 hover:text-amber-800" title="Dismiss"><XIcon size={14} /></button>
        </div>
      )}

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
            {isAccepted && <p className="mt-1 text-xs font-medium text-emerald-600">Accepted</p>}
            {!isAccepted && estimate.valid_until && (() => {
              const days = Math.ceil((new Date(estimate.valid_until) - new Date(new Date().toDateString())) / 86400000)
              return days < 0
                ? <p className="mt-1 inline-block rounded-md bg-brand-danger/10 px-2 py-0.5 text-xs font-semibold text-brand-danger">Expired {fmtDate(estimate.valid_until)} — re-quote if proceeding</p>
                : <p className={`mt-1 text-xs ${days <= 7 ? 'font-medium text-amber-600' : 'text-brand-muted'}`}>Valid until {fmtDate(estimate.valid_until)}{days <= 7 ? ` · ${days} day${days === 1 ? '' : 's'} left` : ''}</p>
            })()}
          </div>
        </div>

        {/* Patient + scheme */}
        <div className="grid grid-cols-2 gap-4 border-b border-brand-border py-4 text-sm">
          <div>
            <p className="text-xs uppercase tracking-wide text-brand-muted">Estimate for</p>
            <p className="font-medium text-brand-ink">{patient.name}</p>
            <p className="text-brand-muted">{patient.phone}</p>
            {/* Treating dentist — carries through to the invoice on conversion (cycle 22) */}
            <div className="mt-2">
              <p className="text-xs uppercase tracking-wide text-brand-muted">Treating dentist</p>
              <p className="print-only font-medium text-brand-ink">{estimate.provider_name || '—'}</p>
              <select
                value={estimate.provider_name || ''}
                onChange={(e) => router.patch(`/estimates/${estimate.id}`, { provider_name: e.target.value }, { preserveScroll: true })}
                className="no-print mt-0.5 block w-full max-w-xs rounded-lg border border-brand-border px-2 py-1 text-sm text-brand-ink focus:border-brand-primary"
              >
                <option value="">— select dentist —</option>
                {providers.map((p) => <option key={p} value={p}>{p}</option>)}
              </select>
            </div>
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
                  {!patientView && <th className="py-1.5 font-semibold">Code</th>}
                  <th className="py-1.5 font-semibold">Treatment</th>
                  <th className="py-1.5 text-center font-semibold">Tooth</th>
                  <th className="py-1.5 text-right font-semibold">Medical</th>
                  <th className="py-1.5 text-right font-semibold">Self</th>
                  <th className="py-1.5 text-right font-semibold">Amount</th>
                </tr>
              </thead>
              <tbody>
                {v.lines.map((l, i) => (
                  <tr key={i} className="border-b border-brand-border/40">
                    {!patientView && <td className="py-1.5 font-mono text-brand-ink">{l.code}</td>}
                    <td className="py-1.5 text-brand-ink">
                      {l.description}
                      {!patientView && l.icd10_code && <span className="ml-2 text-xs text-brand-muted">ICD-10: {l.icd10_code}</span>}
                    </td>
                    <td className="py-1.5 text-center text-brand-muted">{l.tooth_number || '—'}</td>
                    <td className="py-1.5 text-right text-brand-muted">{rand(l.medical)}</td>
                    <td className="py-1.5 text-right text-brand-muted">{rand(l.self_portion)}</td>
                    <td className="py-1.5 text-right text-brand-ink">{rand(l.line_total)}</td>
                  </tr>
                ))}
              </tbody>
              {multiVisit && (
                <tfoot>
                  <tr className="border-t border-brand-border">
                    <td colSpan={patientView ? 2 : 3} className="py-1.5 text-right text-xs font-semibold uppercase tracking-wide text-brand-muted">Visit {v.visit} subtotal</td>
                    <td className="py-1.5 text-right text-xs text-brand-muted">{rand(v.lines.reduce((s, l) => s + (l.medical || 0), 0))}</td>
                    <td className="py-1.5 text-right text-xs font-semibold text-brand-ink">{rand(v.lines.reduce((s, l) => s + (l.self_portion || 0), 0))}</td>
                    <td className="py-1.5 text-right text-sm font-bold text-brand-ink">{rand(v.lines.reduce((s, l) => s + (l.line_total || 0), 0))}</td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        ))}

        {/* Totals — emphasise what the patient pays (benchmark: biggest driver of case acceptance) */}
        <div className="mt-4 ml-auto w-72 space-y-1 text-sm">
          <div className="flex justify-between text-brand-muted"><span>Total treatment fee</span><span>{rand(estimate.total)}</span></div>
          <div className="flex justify-between text-brand-muted"><span>Less estimated medical-aid reimbursement</span><span>−{rand(estimate.medical_total)}</span></div>
          <div className="mt-1 flex items-baseline justify-between border-t-2 border-brand-primary pt-2">
            <span className="font-semibold text-brand-ink">You pay our practice</span>
            <span className="text-xl font-bold text-brand-primary">{rand(estimate.self_total)}</span>
          </div>
          <p className="pt-1 text-[11px] leading-snug text-brand-muted">Medical-aid reimbursement is an estimate and not guaranteed — schemes set their own rates. You pay the practice and submit this estimate to claim back.</p>
        </div>

        <div className="mt-6 border-t border-brand-border pt-4 text-xs text-brand-muted">
          <p className="font-medium text-brand-ink">Payment / banking</p>
          <p>{practice.bank}</p>
          <p className="mt-3 font-semibold text-brand-ink">ESTIMATE VALID FOR 14 DAYS</p>
          <p className="mt-1">This is an estimate of planned treatment, not a final account. Actual fees may vary depending on what is clinically required on the day. You may submit the final invoice to your medical aid to claim back.</p>
        </div>
      </div>

      {/* Edit line items — add a tariff code (tooth / qty / fee) or remove a line */}
      {!isAccepted && (
        <div className="no-print mx-auto mt-4 max-w-3xl rounded-xl border border-brand-border bg-white p-5">
          <h3 className="mb-3 text-sm font-semibold text-brand-ink">Line items</h3>
          {allLines.length === 0 ? (
            <p className="mb-3 text-sm text-brand-muted">No line items yet — add tariff codes below.</p>
          ) : (
            <table className="mb-4 w-full text-sm">
              <tbody>
                {allLines.map((l) => (
                  <tr key={l.id} className="border-b border-brand-border/40">
                    <td className="py-1.5 font-mono text-brand-ink">{l.code}</td>
                    <td className="py-1.5 text-brand-ink">{l.description}</td>
                    <td className="py-1.5 text-center text-brand-muted">{l.tooth_number ? `#${l.tooth_number}` : '—'}</td>
                    <td className="py-1.5 text-right text-brand-ink">{rand(l.line_total)}</td>
                    <td className="py-1.5 pl-2 text-right">
                      <button onClick={() => removeLine(l.id)} title="Remove line" className="rounded p-1 text-brand-muted hover:bg-brand-surface hover:text-brand-danger"><XIcon size={14} /></button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {suggested_macros.length > 0 && (
            <div className="mb-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 no-print">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-700">
                Suggested for this visit{visit_reason ? <span className="font-normal normal-case"> — “{visit_reason}”</span> : null} · please review
              </p>
              <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
                {suggested_macros.map((m) => (
                  <button key={m.id} type="button" onClick={() => applyMacro(m.id)}
                    title={`Add the ${m.name} bundle (review the lines after)`}
                    className="rounded-full border border-amber-400 bg-white px-2.5 py-1 text-xs font-medium text-amber-800 hover:bg-amber-100">
                    + {m.name}
                  </button>
                ))}
                <span className="text-[11px] text-amber-700/80">AI-suggested from the booking — check before sending.</span>
              </div>
            </div>
          )}

          {!isAccepted && (
            <div className="mb-3 rounded-xl border border-brand-primary/30 bg-brand-primary/5 p-3 no-print">
              <label className="mb-1.5 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-brand-primary">
                <Sparkles size={13} /> Describe the treatment — AI fills in the codes
              </label>
              <div className="flex gap-2">
                <input value={aiPrompt} onChange={(e) => setAiPrompt(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); aiCompose() } }}
                  placeholder='e.g. "two crowns on tooth 21 and 11" or "root canal on 34"'
                  className="flex-1 rounded-lg border border-brand-border px-3 py-2 text-sm focus:border-brand-primary focus:outline-none" />
                <button type="button" onClick={aiCompose} disabled={aiBusy || !aiPrompt.trim()}
                  className="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-2 text-sm font-semibold text-white hover:brightness-95 disabled:opacity-50">
                  <Sparkles size={14} /> {aiBusy ? 'Thinking…' : 'Auto-fill codes'}
                </button>
              </div>
              <p className="mt-1 text-[11px] text-brand-muted">Uses your code catalogue + treatment bundles — one line per tooth. Review &amp; adjust after.</p>
            </div>
          )}

          {(favourite_codes.length > 0 || treatment_macros.length > 0) && (
            <div className="mb-2 flex flex-wrap items-center gap-1.5 no-print">
              {favourite_codes.length > 0 && <span className="text-[11px] font-medium uppercase tracking-wide text-brand-muted">Quick add</span>}
              {favourite_codes.map((c) => (
                <button key={c.id} type="button" onClick={() => quickAdd(c)}
                  title={`${c.description}${c.fee != null ? ` · ${rand(c.fee)}` : ''}`}
                  className="rounded-full border border-brand-border bg-brand-surface px-2.5 py-1 text-xs font-medium text-brand-ink hover:border-brand-primary hover:bg-white">
                  <span className="font-mono">{c.code}</span>
                </button>
              ))}
              {treatment_macros.length > 0 && (
                <select value="" onChange={(e) => { applyMacro(e.target.value); e.target.value = '' }}
                  title="Add a whole visit bundle (all its codes) in one click"
                  className="ml-1 rounded-full border border-brand-border bg-white px-2.5 py-1 text-xs font-medium text-brand-ink hover:border-brand-primary">
                  <option value="">+ Visit bundle…</option>
                  {treatment_macros.map((m) => (<option key={m.id} value={m.id}>{m.code} · {m.name}</option>))}
                </select>
              )}
            </div>
          )}

          <div className="grid grid-cols-1 gap-2 sm:grid-cols-12">
            <div className="relative sm:col-span-6">
              <input
                ref={codeInputRef}
                value={codeQuery}
                onChange={(e) => { setCodeQuery(e.target.value); setPicked(false); setDraft({ ...draft, procedure_code_id: '', code: '' }) }}
                onKeyDown={onCodeKey}
                placeholder="Search tariff code or treatment…  (Enter to pick / add)"
                className={editCls}
              />
              {codeMatches.length > 0 && (
                <div className="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded-md border border-brand-border bg-white shadow-lg">
                  {codeMatches.map((c) => (
                    <button key={c.id} type="button" onClick={() => pickCode(c)} className="flex w-full items-center justify-between gap-2 px-3 py-1.5 text-left text-sm hover:bg-brand-surface">
                      <span className="truncate"><span className="font-mono text-brand-ink">{c.code}</span> · {c.description}</span>
                      <span className="whitespace-nowrap text-brand-muted">{c.fee != null ? rand(c.fee) : '—'}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
            <input value={draft.tooth_number} onChange={(e) => setDraft({ ...draft, tooth_number: e.target.value })} onKeyDown={onFieldKey} placeholder="Tooth" className={`${editCls} sm:col-span-2`} />
            <input value={draft.quantity} onChange={(e) => setDraft({ ...draft, quantity: e.target.value })} onKeyDown={onFieldKey} placeholder="Qty" inputMode="numeric" className={`${editCls} sm:col-span-1`} />
            <input value={draft.fee} onChange={(e) => setDraft({ ...draft, fee: e.target.value })} onKeyDown={onFieldKey} placeholder="Fee incl VAT" inputMode="decimal" className={`${editCls} sm:col-span-2`} />
            <button onClick={addLine} className="rounded-md bg-brand-primary px-3 py-2 text-sm font-medium text-white hover:brightness-95 sm:col-span-1">Add</button>
          </div>
          <p className="mt-1 text-[11px] text-brand-muted no-print">Type a code or treatment, press <kbd className="rounded border border-brand-border px-1">Enter</kbd> to pick it, <kbd className="rounded border border-brand-border px-1">Enter</kbd> again to add the line — the cursor returns here for the next one. <kbd className="rounded border border-brand-border px-1">Esc</kbd> clears.</p>
          <p className="mt-2 text-xs text-brand-muted">Pick a code to auto-fill the fee (editable). Tooth + quantity optional. Totals update automatically.</p>
        </div>
      )}

      {/* C1 — Drag-drop attachments (screen only, hidden on print) */}
      <div className="no-print mx-auto mt-4 max-w-3xl">
        <div
          onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
          onDragLeave={() => setDragOver(false)}
          onDrop={onDrop}
          className={`rounded-xl border-2 border-dashed px-4 py-6 text-center transition-colors ${
            dragOver ? 'border-brand-primary bg-brand-primary/5' : 'border-brand-border bg-white'
          }`}
        >
          <UploadCloud size={22} className="mx-auto mb-1 text-brand-muted" />
          <p className="text-sm text-brand-ink">
            Drag X-ray screenshots, intra-oral photos, or reference PDFs here
          </p>
          <label className="mt-2 inline-flex cursor-pointer items-center gap-1 text-xs font-semibold text-brand-primary hover:underline">
            or browse files
            <input type="file" multiple onChange={onPick} className="hidden" />
          </label>
        </div>

        {attachments.length > 0 && (
          <ul className="mt-3 space-y-1.5">
            {attachments.map((a) => (
              <li key={a.id} className="flex items-center justify-between rounded-lg border border-brand-border bg-white px-3 py-2 text-sm">
                <a href={a.url} target="_blank" rel="noreferrer" className="flex items-center gap-2 text-brand-ink hover:underline">
                  <Paperclip size={13} className="text-brand-muted" />
                  <span>{a.filename}</span>
                  <span className="text-xs text-brand-muted">· {(a.byte_size / 1024).toFixed(1)} KB</span>
                </a>
                <button onClick={() => removeAttachment(a.id)} title="Remove"
                  className="rounded-md p-1 text-brand-muted hover:bg-brand-surface hover:text-brand-danger">
                  <XIcon size={13} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </DashboardLayout>
  )
}
