import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import {
  Pencil, HeartPulse, Shield, Phone, Trash2, Calendar, ClipboardPlus,
  FileText, Receipt, Wallet, ArrowRight, MessageSquare, Users, Plus, Scan, Grid3x3,
  AlertTriangle, GitMerge, UserCheck,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import Odontogram from '../components/Odontogram'
import PatientFormModal from '../components/PatientFormModal'
import AppointmentFormModal from '../components/AppointmentFormModal'
import DicomViewer from '../components/DicomViewer'

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
  // document statuses
  planned:     'bg-amber-100 text-amber-800',
  active:      'bg-blue-100 text-blue-800',
  draft:       'bg-gray-100 text-gray-600',
  sent:        'bg-amber-100 text-amber-800',
  accepted:    'bg-emerald-100 text-emerald-800',
  open:        'bg-amber-100 text-amber-800',
  part_paid:   'bg-orange-100 text-orange-800',
  paid:        'bg-emerald-100 text-emerald-800',
  void:        'bg-gray-100 text-gray-500',
}

const ZAR = (n) => `R${Number(n || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const dateZA = (s, opts) => s ? new Date(s).toLocaleDateString('en-ZA', opts) : '—'

export default function PatientShow({
  patient, medical_history, appointments, conversations,
  courses_of_treatment: courses = [],
  estimates = [],
  invoices = [],
  imaging_studies: imaging = [],
  billing_account: billingAccount = null,
  account_summary: accountSummary = {},
  open_courses_of_treatment: openCourses = [],
  open_estimates: openEstimates = [],
  open_invoices: openInvoices = [],
  outstanding_balance: outstandingBalance = 0,
  google_review_url: googleReviewUrl = null,
  next_appointment: nextAppointment = null,
  tooth_chart: toothChart = {},
  tooth_chart_detail: toothChartDetail = {},
  likely_match: likelyMatch = null,
}) {
  const [editOpen, setEditOpen] = useState(false)
  const [bookOpen, setBookOpen] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [tab, setTab] = useState('overview')
  const [dicomStudy, setDicomStudy] = useState(null)

  const handleDelete = () => {
    router.delete(`/patients/${patient.id}`, { onSuccess: () => setConfirmDelete(false) })
  }
  const mergeInto = () => {
    if (!likelyMatch) return
    const acct = likelyMatch.account_code ? ` (${likelyMatch.account_code})` : ''
    if (!window.confirm(`Merge this self-registration INTO ${likelyMatch.name}${acct}? Their submitted form, medical history and details move onto that patient and this placeholder is removed.`)) return
    router.post(`/patients/${patient.id}/merge_into`, { target_id: likelyMatch.id })
  }
  const confirmNew = () => {
    if (!window.confirm('Confirm this is a NEW patient (not a duplicate)? They will get an account number and consent on file.')) return
    router.post(`/patients/${patient.id}/confirm_new`)
  }
  const minimalPatientList = [{ id: patient.id, name: patient.full_name, phone: patient.phone }]

  const TABS = [
    { key: 'overview',   label: 'Overview',        icon: HeartPulse },
    { key: 'treatment',  label: 'Treatment Plans', icon: ClipboardPlus, count: courses.length },
    { key: 'chart',      label: 'Dental Chart',    icon: Grid3x3,       count: Object.keys(toothChart).length },
    { key: 'estimates',  label: 'Estimates',       icon: FileText,      count: estimates.length },
    { key: 'invoices',   label: 'Invoices',        icon: Receipt,       count: invoices.length },
    { key: 'imaging',    label: 'Imaging (SIDEXIS)', icon: Scan,        count: imaging.length },
    { key: 'account',    label: 'Account',         icon: Wallet },
    { key: 'history',    label: 'Visits & Chats',  icon: Calendar,      count: (appointments?.length || 0) + (conversations?.length || 0) },
  ]

  return (
    <DashboardLayout>
      <div className="mb-6">
        <Link href="/patients" className="text-sm text-brand-taupe hover:text-brand-brown transition-colors">
          ← Back to Patients
        </Link>
      </div>

      {patient.needs_review && (
        <div className="mb-4 rounded-xl border border-amber-300 bg-amber-50 p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle size={20} className="mt-0.5 flex-shrink-0 text-amber-600" />
            <div className="flex-1">
              <p className="text-sm font-semibold text-amber-900">Self-registered — needs review</p>
              <p className="mt-0.5 text-sm text-amber-800">
                {likelyMatch ? (
                  <>This looks like an existing patient: <strong>{likelyMatch.name}</strong>{likelyMatch.account_code ? ` (${likelyMatch.account_code})` : ''}. Verify their identity, then merge — or keep as a new patient.</>
                ) : (
                  <>Verify this patient's identity, then confirm them as new (no obvious existing match was found).</>
                )}
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {likelyMatch && (
                  <button onClick={mergeInto} className="inline-flex items-center gap-1.5 rounded-lg bg-amber-600 px-3 py-2 text-sm font-semibold text-white transition-colors hover:bg-amber-700">
                    <GitMerge size={15} /> Merge into {likelyMatch.name}
                  </button>
                )}
                <button onClick={confirmNew} className="inline-flex items-center gap-1.5 rounded-lg border border-amber-400 bg-white px-3 py-2 text-sm font-semibold text-amber-800 transition-colors hover:bg-amber-100">
                  <UserCheck size={15} /> Not a duplicate — keep as new
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Patient header (always visible — the spine of the record) ── */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <div className="flex flex-wrap items-start justify-between gap-3 mb-4">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-xl font-bold text-brand-brown">{patient.full_name}</h1>
              {billingAccount && (
                <span className="inline-flex items-center gap-1 rounded-full bg-brand-cream px-2.5 py-0.5 text-xs font-semibold text-brand-brown">
                  <Wallet size={11} /> {billingAccount.account_code}
                </span>
              )}
              {outstandingBalance > 0 && (
                <span className="inline-flex items-center gap-1 rounded-full bg-brand-danger/10 px-2.5 py-0.5 text-xs font-semibold text-brand-danger" title="Outstanding balance on this account">
                  <Wallet size={11} /> Owes {ZAR(outstandingBalance)}
                </span>
              )}
              {(medical_history?.allergies || medical_history?.chronic_conditions) && (
                <span className="inline-flex items-center gap-1 rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-semibold text-red-700"
                  title={[medical_history.allergies && `Allergies: ${medical_history.allergies}`, medical_history.chronic_conditions && `Conditions: ${medical_history.chronic_conditions}`].filter(Boolean).join(' · ')}>
                  <HeartPulse size={11} /> Medical alert
                </span>
              )}
              {patient.ai_consent && (
                <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-0.5 text-xs font-semibold text-emerald-700">
                  <Shield size={11} /> AI consent
                </span>
              )}
            </div>
            {nextAppointment && (
              <p className="mt-1 text-xs text-brand-muted">
                Next: <strong className="text-brand-ink">{new Date(nextAppointment.start_time).toLocaleString('en-ZA', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</strong> · {nextAppointment.reason || 'Appointment'}
              </p>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" onClick={() => setBookOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-brand-primary-dark">
              <Calendar size={13} /> Book appointment
            </button>
            <button type="button" onClick={() => setEditOpen(true)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-brand-brown hover:bg-brand-cream rounded-lg transition-colors border border-gray-200">
              <Pencil size={13} /> Edit
            </button>
            {googleReviewUrl && patient.phone && (
              <a
                href={`https://wa.me/${(patient.phone || '').replace(/\D/g, '')}?text=${encodeURIComponent(`Hi ${patient.first_name || patient.full_name || 'there'}, thank you for visiting Dr Chalita le Roux! We'd really appreciate a quick Google review — it helps us a lot: ${googleReviewUrl}`)}`}
                target="_blank" rel="noopener noreferrer"
                title="Open WhatsApp with a pre-filled review request to send"
                className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700 transition-colors hover:bg-emerald-100">
                <MessageSquare size={13} /> Request review
              </a>
            )}
            <button type="button" onClick={() => setConfirmDelete(true)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-brand-danger hover:bg-brand-danger/5 rounded-lg transition-colors border border-brand-danger/20">
              <Trash2 size={13} /> Delete
            </button>
          </div>
        </div>

        {/* Delete confirmation inline banner */}
        {confirmDelete && (
          <div className="mb-4 rounded-xl border border-brand-danger/30 bg-brand-danger/5 px-4 py-3">
            <p className="text-sm font-medium text-brand-danger mb-3">
              Permanently delete <span className="font-bold">{patient.full_name}</span>? This cannot be undone — all appointments, conversations, treatment plans, estimates and invoices for this patient will be removed.
            </p>
            <div className="flex items-center gap-2">
              <button type="button" onClick={handleDelete}
                className="rounded-lg bg-brand-danger px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-danger/90 transition-colors">
                Yes, delete permanently
              </button>
              <button type="button" onClick={() => setConfirmDelete(false)}
                className="rounded-lg border border-brand-border px-4 py-1.5 text-xs font-semibold text-brand-muted hover:text-brand-ink transition-colors">
                Cancel
              </button>
            </div>
          </div>
        )}

        <div className="grid grid-cols-2 md:grid-cols-4 gap-5">
          <Field label="Phone"><p className="text-sm text-gray-800">{patient.phone || '—'}</p></Field>
          <Field label="Email"><p className="text-sm text-gray-800">{patient.email || '—'}</p></Field>
          <Field label="Date of Birth">
            <p className="text-sm text-gray-800">{dateZA(patient.date_of_birth)}</p>
          </Field>
          <Field label="Patient Since">
            <p className="text-sm text-gray-800">{dateZA(patient.created_at)}</p>
          </Field>
        </div>
      </div>

      {/* Persistent medical-alert banner — always visible (every tab) so the dentist never
          misses a drug allergy / condition / medication before treatment. Allergies first. */}
      {(medical_history?.allergies || medical_history?.chronic_conditions || medical_history?.current_medications) && (
        <div className="mb-4 flex flex-wrap items-start gap-x-4 gap-y-1 rounded-lg border border-red-300 bg-red-50 px-4 py-2.5 text-sm">
          <span className="inline-flex shrink-0 items-center gap-1.5 font-bold uppercase tracking-wide text-red-700"><HeartPulse size={15} /> Medical alert</span>
          {medical_history.allergies && <span className="text-red-800"><span className="font-semibold">Allergies:</span> {medical_history.allergies}</span>}
          {medical_history.chronic_conditions && <span className="text-red-800"><span className="font-semibold">Conditions:</span> {medical_history.chronic_conditions}</span>}
          {medical_history.current_medications && <span className="text-red-800"><span className="font-semibold">Meds:</span> {medical_history.current_medications}</span>}
        </div>
      )}

      {/* ── Tab bar ── */}
      <div className="mb-5 flex flex-wrap gap-1 border-b border-gray-200">
        {TABS.map(({ key, label, icon: Icon, count }) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`-mb-px flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors ${
              tab === key
                ? 'border-brand-primary text-brand-brown'
                : 'border-transparent text-brand-muted hover:text-brand-ink'
            }`}
          >
            <Icon size={15} />
            {label}
            {count > 0 && (
              <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-semibold ${
                tab === key ? 'bg-brand-primary text-white' : 'bg-gray-100 text-gray-500'
              }`}>{count}</span>
            )}
          </button>
        ))}
      </div>

      {/* ── Tab content ── */}
      {tab === 'overview' && (
        <OverviewTab
          medicalHistory={medical_history}
          onEditMh={() => setEditOpen(true)}
          openCourses={openCourses}
          openEstimates={openEstimates}
          openInvoices={openInvoices}
          outstandingBalance={outstandingBalance}
          notes={patient.notes}
          onJump={setTab}
        />
      )}

      {tab === 'treatment' && (
        <div>
          <div className="mb-3 flex justify-end">
            <button
              type="button"
              onClick={() => router.post(`/patients/${patient.id}/courses_of_treatment`)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
            >
              <Plus size={14} /> New treatment plan
            </button>
          </div>
        <RecordList
          title="Treatment plans (Courses of Treatment)"
          emptyText="No treatment plans yet for this patient."
          items={courses}
          renderRow={(c) => (
            <RecordRow
              key={c.id}
              href={`/courses-of-treatment/${c.id}`}
              icon={ClipboardPlus}
              primary={c.description || `Course #${c.id}`}
              secondary={`${c.item_count} item${c.item_count === 1 ? '' : 's'} · est. ${ZAR(c.estimated_total)} · done ${ZAR(c.completed_total)}`}
              status={c.status}
              meta={dateZA(c.created_at, { day: 'numeric', month: 'short', year: 'numeric' })}
            />
          )}
        />
        </div>
      )}

      {tab === 'estimates' && (
        <div>
          <div className="mb-3 flex justify-end">
            <button
              type="button"
              onClick={() => router.post(`/patients/${patient.id}/estimates`)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
            >
              <Plus size={14} /> New estimate
            </button>
          </div>
        <RecordList
          title="Estimates"
          emptyText="No estimates yet for this patient."
          items={estimates}
          renderRow={(e) => (
            <RecordRow
              key={e.id}
              href={`/estimates/${e.id}`}
              icon={FileText}
              primary={e.title || e.number || `Estimate #${e.id}`}
              secondary={e.number || `Valid until ${dateZA(e.valid_until)}`}
              amount={ZAR(e.total)}
              status={e.status}
              meta={dateZA(e.created_at, { day: 'numeric', month: 'short', year: 'numeric' })}
            />
          )}
        />
        </div>
      )}

      {tab === 'invoices' && (
        <div>
          <div className="mb-3 flex justify-end">
            <button
              type="button"
              onClick={() => router.post(`/patients/${patient.id}/estimates`, { intent: 'invoice' })}
              title="Describe the treatment, let AI fill the codes, adjust, then create the invoice"
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
            >
              <Plus size={14} /> New invoice
            </button>
          </div>
        <RecordList
          title="Invoices"
          emptyText="No invoices yet for this patient."
          items={invoices}
          headerRight={
            <span className="text-sm font-semibold text-brand-danger">
              Outstanding: {ZAR(accountSummary.outstanding)}
            </span>
          }
          renderRow={(i) => (
            <RecordRow
              key={i.id}
              href={`/invoices/${i.id}`}
              icon={Receipt}
              primary={i.number || `Invoice #${i.id}`}
              secondary={i.balance > 0 ? `Balance ${ZAR(i.balance)}` : 'Settled'}
              amount={ZAR(i.total)}
              status={i.status}
              meta={dateZA(i.invoice_date || i.created_at, { day: 'numeric', month: 'short', year: 'numeric' })}
            />
          )}
        />
        </div>
      )}

      {tab === 'chart' && (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-3 text-xs text-brand-muted">
            <span className="inline-flex items-center gap-1.5"><span className="h-3 w-3 rounded bg-red-500" /> Needs work (outstanding)</span>
            <span className="inline-flex items-center gap-1.5"><span className="h-3 w-3 rounded bg-gray-800" /> Done / existing</span>
            <span className="inline-flex items-center gap-1.5"><span className="h-3 w-3 rounded border border-brand-border bg-white" /> Healthy / unrecorded</span>
          </div>
          <Odontogram chart={toothChart} details={toothChartDetail} />
          {Object.keys(toothChart).length === 0 && (
            <p className="text-sm text-brand-muted">No charted work yet for this patient — planned treatment shows red, completed/existing work shows black.</p>
          )}
        </div>
      )}

      {tab === 'imaging' && (
        imaging.length === 0 ? (
          <p className="text-sm text-brand-muted">No SIDEXIS scans linked to this patient yet.</p>
        ) : (
          <div>
            <h3 className="mb-3 text-sm font-medium text-brand-muted">
              {imaging.length} SIDEXIS scan{imaging.length === 1 ? '' : 's'} on file — click any to open full size
            </h3>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
              {imaging.map((s) => (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => setDicomStudy(s)}
                  className="group block w-full overflow-hidden rounded-lg border border-brand-border bg-white text-left transition hover:shadow-md"
                >
                  {s.has_image ? (
                    <img
                      src={`/imaging/${s.id}/image`}
                      alt={s.modality_label}
                      loading="lazy"
                      className="h-32 w-full bg-black object-contain"
                    />
                  ) : (
                    <div className="flex h-32 w-full items-center justify-center bg-gray-100">
                      <Scan className="h-8 w-8 text-brand-muted" />
                    </div>
                  )}
                  <div className="p-2">
                    <div className="text-xs font-medium text-brand-ink">{s.modality_label}</div>
                    <div className="text-xs text-brand-muted">
                      {dateZA(s.captured_at, { day: 'numeric', month: 'short', year: 'numeric' })}
                    </div>
                    {s.notes && <div className="truncate text-[11px] text-brand-muted">{s.notes}</div>}
                  </div>
                </button>
              ))}
            </div>
          </div>
        )
      )}

      {tab === 'account' && (
        <AccountTab account={billingAccount} summary={accountSummary} currentPatientId={patient.id} />
      )}

      {tab === 'history' && (
        <HistoryTab appointments={appointments} conversations={conversations} />
      )}

      {dicomStudy && <DicomViewer study={dicomStudy} onClose={() => setDicomStudy(null)} />}

      <PatientFormModal
        open={editOpen}
        mode="edit"
        patient={patient}
        medicalHistory={medical_history}
        bloodTypes={medical_history?.blood_types}
        onClose={() => setEditOpen(false)}
      />
      <AppointmentFormModal
        mode="create"
        open={bookOpen}
        onClose={() => setBookOpen(false)}
        patients={minimalPatientList}
      />
    </DashboardLayout>
  )
}

// ── Overview tab ──────────────────────────────────────────────────
function OverviewTab({ medicalHistory, onEditMh, openCourses, openEstimates, openInvoices, outstandingBalance, notes, onJump }) {
  const hasShortcuts = openCourses.length > 0 || openEstimates.length > 0 || openInvoices.length > 0 || outstandingBalance > 0
  return (
    <div className="space-y-5">
      {hasShortcuts && (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          {openCourses.length > 0 && (
            <button onClick={() => onJump('treatment')}
              className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 hover:bg-brand-surface text-left">
              <div className="flex items-center gap-2">
                <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-50 text-blue-700"><ClipboardPlus size={15} /></span>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">Active treatment</p>
                  <p className="text-sm font-medium text-brand-ink">{openCourses[0].item_count} item{openCourses[0].item_count === 1 ? '' : 's'} · {openCourses[0].status}</p>
                </div>
              </div>
              <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
            </button>
          )}
          {openEstimates.length > 0 && (
            <button onClick={() => onJump('estimates')}
              className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 hover:bg-brand-surface text-left">
              <div className="flex items-center gap-2">
                <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-amber-50 text-amber-700"><FileText size={15} /></span>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">Open estimate</p>
                  <p className="text-sm font-medium text-brand-ink">{openEstimates[0].number} · {ZAR(openEstimates[0].total)}</p>
                </div>
              </div>
              <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
            </button>
          )}
          {(openInvoices.length > 0 || outstandingBalance > 0) && (
            <button onClick={() => onJump('invoices')}
              className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 hover:bg-brand-surface text-left">
              <div className="flex items-center gap-2">
                <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-50 text-emerald-700"><Wallet size={15} /></span>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">Outstanding</p>
                  <p className="text-sm font-medium text-brand-danger">{ZAR(outstandingBalance)} on {openInvoices.length} invoice{openInvoices.length === 1 ? '' : 's'}</p>
                </div>
              </div>
              <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
            </button>
          )}
        </div>
      )}

      <MedicalHistoryPanel mh={medicalHistory} onEdit={onEditMh} />

      {notes && (
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">Notes</p>
          <p className="text-sm text-gray-700 whitespace-pre-line">{notes}</p>
        </div>
      )}
    </div>
  )
}

// ── Generic record list + row (treatment / estimates / invoices) ───
function RecordList({ title, items, renderRow, emptyText, headerRight }) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-base font-semibold text-brand-brown">{title}</h2>
        {headerRight}
      </div>
      {items.length > 0 ? (
        <div className="space-y-2">{items.map(renderRow)}</div>
      ) : (
        <p className="text-sm text-gray-400">{emptyText}</p>
      )}
    </div>
  )
}

function RecordRow({ href, icon: Icon, primary, secondary, amount, status, meta }) {
  return (
    <Link href={href} className="group flex items-center justify-between rounded-lg bg-gray-50 px-4 py-3 hover:bg-brand-cream transition-colors">
      <div className="flex items-center gap-3 min-w-0">
        <span className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg bg-white text-brand-taupe border border-gray-200"><Icon size={16} /></span>
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-gray-800">{primary}</p>
          <p className="truncate text-xs text-gray-400">{secondary}</p>
        </div>
      </div>
      <div className="flex items-center gap-3 flex-shrink-0">
        {amount && <span className="text-sm font-semibold text-brand-ink">{amount}</span>}
        {status && (
          <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${STATUS_STYLES[status] || 'bg-gray-100 text-gray-600'}`}>
            {String(status).replace('_', ' ')}
          </span>
        )}
        <span className="hidden sm:block text-xs text-gray-400 w-20 text-right">{meta}</span>
        <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
      </div>
    </Link>
  )
}

// ── Account tab ───────────────────────────────────────────────────
function AccountTab({ account, summary, currentPatientId }) {
  if (!account) {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-brand-brown mb-2">Billing account</h2>
        <p className="text-sm text-gray-400">No billing account linked to this patient yet. Add one from the Edit form.</p>
      </div>
    )
  }
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <SummaryStat label="Total billed" value={ZAR(summary.total_billed)} />
        <SummaryStat label="Total paid" value={ZAR(summary.total_paid)} tone="emerald" />
        <SummaryStat label="Outstanding" value={ZAR(summary.outstanding)} tone={summary.outstanding > 0 ? 'danger' : 'muted'} />
      </div>

      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <div className="mb-4 flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <Wallet size={16} className="text-brand-taupe" />
            <h2 className="text-base font-semibold text-brand-brown">Billing account</h2>
          </div>
          <Link href={`/accounts/${account.id}`}
            className="inline-flex items-center gap-1 rounded-lg bg-brand-primary px-3 py-1.5 text-xs font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
            title="Open the account ledger + print a statement">
            <Receipt size={13} /> View account &amp; statement
          </Link>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-5">
          <Field label="Account code"><p className="text-sm font-mono text-gray-800">{account.account_code}</p></Field>
          <Field label="Billing name"><p className="text-sm text-gray-800">{account.billing_name || '—'}</p></Field>
          <Field label="Members on account"><p className="text-sm text-gray-800">{account.members.length}</p></Field>
        </div>

        {account.members.length > 0 && (
          <div className="mt-5">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Patients on this account</p>
            <div className="space-y-1.5">
              {account.members.map((m) => (
                <Link key={m.id} href={`/patients/${m.id}`}
                  className={`flex items-center justify-between rounded-lg px-3 py-2 text-sm transition-colors ${
                    m.id === currentPatientId ? 'bg-brand-cream text-brand-brown font-medium' : 'bg-gray-50 text-gray-700 hover:bg-brand-cream'
                  }`}>
                  <span className="flex items-center gap-2"><Users size={13} className="text-brand-taupe" />{m.name}</span>
                  {m.is_head && <span className="text-[10px] font-semibold uppercase tracking-wide text-brand-taupe">Head</span>}
                </Link>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function SummaryStat({ label, value, tone = 'ink' }) {
  const toneClass = {
    ink: 'text-brand-ink', emerald: 'text-emerald-700', danger: 'text-brand-danger', muted: 'text-brand-muted',
  }[tone]
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4">
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">{label}</p>
      <p className={`text-lg font-bold ${toneClass}`}>{value}</p>
    </div>
  )
}

// ── History tab (appointments + conversations) ────────────────────
function HistoryTab({ appointments, conversations }) {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-brand-brown mb-4">Appointment history</h2>
        {appointments?.length > 0 ? (
          <div className="space-y-2">
            {appointments.map((apt) => (
              <Link key={apt.id} href={`/appointments/${apt.id}`}
                className="block p-3 rounded-lg bg-gray-50 hover:bg-brand-cream transition-colors">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium text-gray-800">
                      {new Date(apt.start_time).toLocaleDateString('en-ZA', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })}
                    </p>
                    <p className="text-xs text-gray-400 mt-0.5">{apt.reason || 'General'}</p>
                  </div>
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${STATUS_STYLES[apt.status] || 'bg-gray-100 text-gray-600'}`}>
                    {apt.status}
                  </span>
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <p className="text-sm text-gray-400">No appointments</p>
        )}
      </div>

      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-brand-brown mb-4">Conversations</h2>
        {conversations?.length > 0 ? (
          <div className="space-y-2">
            {conversations.map((conv) => (
              <Link key={conv.id} href={`/conversations/${conv.id}`}
                className="block p-3 rounded-lg bg-gray-50 hover:bg-brand-cream transition-colors">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${conv.channel === 'whatsapp' ? 'bg-emerald-100 text-emerald-700' : 'bg-blue-100 text-blue-700'}`}>
                      {conv.channel}
                    </span>
                    <span className="text-xs text-gray-400">{conv.message_count} messages</span>
                  </div>
                  <span className="text-xs text-gray-400">{dateZA(conv.updated_at)}</span>
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <p className="text-sm text-gray-400">No conversations</p>
        )}
      </div>
    </div>
  )
}

// ── Medical history panel ─────────────────────────────────────────
function MedicalHistoryPanel({ mh, onEdit }) {
  const isEmpty = !mh?.any_data

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <HeartPulse size={16} className="text-brand-taupe" />
          <h2 className="text-base font-semibold text-brand-brown">Medical History</h2>
        </div>
        <button type="button" onClick={onEdit}
          className="text-xs font-semibold text-brand-taupe hover:text-brand-brown transition-colors">
          {isEmpty ? '+ Add records' : 'Edit records'}
        </button>
      </div>

      {isEmpty ? (
        <p className="text-sm text-gray-400">
          No medical records on file yet. Click "Add records" to capture allergies,
          medications, medical aid details, and emergency contact details.
        </p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          <MhBlock label="Allergies" value={mh.allergies} tone="red" />
          <MhBlock label="Chronic conditions" value={mh.chronic_conditions} />
          <MhBlock label="Current medications" value={mh.current_medications} />
          <MhBlock label="Blood type" value={mh.blood_type} />
          <MhBlock label="Last dental visit" value={mh.last_dental_visit && dateZA(mh.last_dental_visit)} />
          <MhBlock label="Dental notes" value={mh.dental_notes} />

          {(mh.emergency_contact_name || mh.emergency_contact_phone) && (
            <div className="md:col-span-1">
              <div className="flex items-center gap-1.5 mb-1">
                <Phone size={12} className="text-gray-400" />
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Emergency contact</p>
              </div>
              <p className="text-sm text-gray-800">{mh.emergency_contact_name || '—'}</p>
              <p className="text-xs text-gray-500">{mh.emergency_contact_phone || '—'}</p>
            </div>
          )}

          {(mh.insurance_provider || mh.insurance_policy_number) && (
            <div className="md:col-span-1">
              <div className="flex items-center gap-1.5 mb-1">
                <Shield size={12} className="text-gray-400" />
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Medical Aid (claim-back)</p>
              </div>
              <p className="text-sm text-gray-800">{mh.insurance_provider || '—'}</p>
              <p className="text-xs text-gray-500 font-mono">{mh.insurance_policy_number || '—'}</p>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function MhBlock({ label, value, tone }) {
  if (!value) return null
  const toneClass = tone === 'red' ? 'text-red-700' : 'text-gray-800'
  return (
    <div>
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">{label}</p>
      <p className={`text-sm ${toneClass} whitespace-pre-line`}>{value}</p>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div>
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">{label}</p>
      {children}
    </div>
  )
}
