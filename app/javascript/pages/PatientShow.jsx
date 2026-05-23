import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { Pencil, HeartPulse, Shield, Phone, Trash2, Calendar, ClipboardPlus, FileText, Receipt, Wallet, ArrowRight } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import PatientFormModal from '../components/PatientFormModal'
import AppointmentFormModal from '../components/AppointmentFormModal'

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
}

export default function PatientShow({
  patient, medical_history, appointments, conversations,
  open_courses_of_treatment: openCourses = [],
  open_estimates: openEstimates = [],
  open_invoices: openInvoices = [],
  outstanding_balance: outstandingBalance = 0,
  next_appointment: nextAppointment = null,
}) {
  const [editOpen, setEditOpen] = useState(false)
  const [bookOpen, setBookOpen] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)

  const handleDelete = () => {
    router.delete(`/patients/${patient.id}`, {
      onSuccess: () => setConfirmDelete(false),
    })
  }
  // Minimal patients list for the appointment-modal patient picker —
  // since we open the modal in "existing-patient" mode pre-selected to
  // THIS patient, we only need to surface this patient as an option.
  const minimalPatientList = [{ id: patient.id, name: patient.full_name, phone: patient.phone }]

  return (
    <DashboardLayout>
      <div className="mb-6">
        <Link href="/patients" className="text-sm text-brand-taupe hover:text-brand-brown transition-colors">
          ← Back to Patients
        </Link>
      </div>

      {/* Patient Info Card */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <div className="flex flex-wrap items-start justify-between gap-3 mb-4">
          <div>
            <h1 className="text-xl font-bold text-brand-brown">{patient.full_name}</h1>
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
            <button type="button" onClick={() => setConfirmDelete(true)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-brand-danger hover:bg-brand-danger/5 rounded-lg transition-colors border border-brand-danger/20">
              <Trash2 size={13} /> Delete
            </button>
          </div>
        </div>

        {/* R2 — Quick-action shortcuts. Visible counts so reception sees
            at a glance what's open without clicking around. */}
        {(openCourses.length > 0 || openEstimates.length > 0 || openInvoices.length > 0 || outstandingBalance > 0) && (
          <div className="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-3">
            {openCourses.length > 0 && (
              <Link href={`/courses-of-treatment/${openCourses[0].id}`}
                className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 hover:bg-brand-surface">
                <div className="flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-50 text-blue-700"><ClipboardPlus size={15} /></span>
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">Active treatment</p>
                    <p className="text-sm font-medium text-brand-ink">{openCourses[0].item_count} item{openCourses[0].item_count === 1 ? '' : 's'} · {openCourses[0].status}</p>
                  </div>
                </div>
                <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
              </Link>
            )}
            {openEstimates.length > 0 && (
              <Link href={`/estimates/${openEstimates[0].id}`}
                className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 hover:bg-brand-surface">
                <div className="flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-amber-50 text-amber-700"><FileText size={15} /></span>
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">Open estimate</p>
                    <p className="text-sm font-medium text-brand-ink">{openEstimates[0].number} · R{openEstimates[0].total.toLocaleString('en-ZA', { minimumFractionDigits: 2 })}</p>
                  </div>
                </div>
                <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
              </Link>
            )}
            {openInvoices.length > 0 && (
              <Link href={`/invoices/${openInvoices[0].id}`}
                className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 hover:bg-brand-surface">
                <div className="flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-50 text-emerald-700"><Wallet size={15} /></span>
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">Outstanding</p>
                    <p className="text-sm font-medium text-brand-danger">R{outstandingBalance.toLocaleString('en-ZA', { minimumFractionDigits: 2 })} on {openInvoices.length} invoice{openInvoices.length === 1 ? '' : 's'}</p>
                  </div>
                </div>
                <ArrowRight size={14} className="text-brand-muted group-hover:text-brand-ink" />
              </Link>
            )}
          </div>
        )}

        {/* Delete confirmation inline banner */}
        {confirmDelete && (
          <div className="mb-4 rounded-xl border border-brand-danger/30 bg-brand-danger/5 px-4 py-3">
            <p className="text-sm font-medium text-brand-danger mb-3">
              Permanently delete <span className="font-bold">{patient.full_name}</span>? This cannot be undone — all appointments, conversations, and medical history will be removed.
            </p>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={handleDelete}
                className="rounded-lg bg-brand-danger px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-danger/90 transition-colors"
              >
                Yes, delete permanently
              </button>
              <button
                type="button"
                onClick={() => setConfirmDelete(false)}
                className="rounded-lg border border-brand-border px-4 py-1.5 text-xs font-semibold text-brand-muted hover:text-brand-ink transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-5">
          <Field label="Phone"><p className="text-sm text-gray-800">{patient.phone}</p></Field>
          <Field label="Email"><p className="text-sm text-gray-800">{patient.email || '—'}</p></Field>
          <Field label="Date of Birth">
            <p className="text-sm text-gray-800">
              {patient.date_of_birth ? new Date(patient.date_of_birth).toLocaleDateString('en-ZA') : '—'}
            </p>
          </Field>
          <Field label="Patient Since">
            <p className="text-sm text-gray-800">{new Date(patient.created_at).toLocaleDateString('en-ZA')}</p>
          </Field>
          <Field label="Preferred Language">
            {patient.preferred_language ? (
              <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${
                patient.preferred_language === 'af'
                  ? 'bg-emerald-50 text-emerald-700'
                  : 'bg-gray-100 text-gray-600'
              }`}>
                {patient.preferred_language === 'af' ? 'Afrikaans' : 'English'}
              </span>
            ) : (
              <p className="text-sm text-gray-400">—</p>
            )}
          </Field>
        </div>
        {patient.notes && (
          <div className="mt-4 p-3 bg-brand-cream rounded-lg border border-gray-100">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">Notes</p>
            <p className="text-sm text-gray-700">{patient.notes}</p>
          </div>
        )}
      </div>

      {/* Medical History Panel */}
      <MedicalHistoryPanel
        mh={medical_history}
        onEdit={() => setEditOpen(true)}
      />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        {/* Appointment History */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-base font-semibold text-brand-brown mb-4">Appointment History</h2>
          {appointments?.length > 0 ? (
            <div className="space-y-2">
              {appointments.map((apt) => (
                <Link
                  key={apt.id}
                  href={`/appointments/${apt.id}`}
                  className="block p-3 rounded-lg bg-gray-50 hover:bg-brand-cream transition-colors"
                >
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

        {/* Conversations */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-base font-semibold text-brand-brown mb-4">Conversations</h2>
          {conversations?.length > 0 ? (
            <div className="space-y-2">
              {conversations.map((conv) => (
                <Link
                  key={conv.id}
                  href={`/conversations/${conv.id}`}
                  className="block p-3 rounded-lg bg-gray-50 hover:bg-brand-cream transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${conv.channel === 'whatsapp' ? 'bg-emerald-100 text-emerald-700' : 'bg-blue-100 text-blue-700'}`}>
                        {conv.channel}
                      </span>
                      <span className="text-xs text-gray-400">{conv.message_count} messages</span>
                    </div>
                    <span className="text-xs text-gray-400">
                      {new Date(conv.updated_at).toLocaleDateString('en-ZA')}
                    </span>
                  </div>
                </Link>
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-400">No conversations</p>
          )}
        </div>
      </div>

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

// ── Medical history panel ─────────────────────────────────────────
// Renders a rich view of the patient's medical history when present,
// otherwise a compact empty state that invites the user to fill it in.
function MedicalHistoryPanel({ mh, onEdit }) {
  const isEmpty = !mh?.any_data

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <HeartPulse size={16} className="text-brand-taupe" />
          <h2 className="text-base font-semibold text-brand-brown">Medical History</h2>
        </div>
        <button
          type="button"
          onClick={onEdit}
          className="text-xs font-semibold text-brand-taupe hover:text-brand-brown transition-colors"
        >
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
          <MhBlock
            label="Last dental visit"
            value={mh.last_dental_visit && new Date(mh.last_dental_visit).toLocaleDateString('en-ZA')}
          />
          <MhBlock label="Dental notes" value={mh.dental_notes} />

          {(mh.emergency_contact_name || mh.emergency_contact_phone) && (
            <div className="md:col-span-1">
              <div className="flex items-center gap-1.5 mb-1">
                <Phone size={12} className="text-gray-400" />
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">
                  Emergency contact
                </p>
              </div>
              <p className="text-sm text-gray-800">{mh.emergency_contact_name || '—'}</p>
              <p className="text-xs text-gray-500">{mh.emergency_contact_phone || '—'}</p>
            </div>
          )}

          {(mh.insurance_provider || mh.insurance_policy_number) && (
            <div className="md:col-span-1">
              <div className="flex items-center gap-1.5 mb-1">
                <Shield size={12} className="text-gray-400" />
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">
                  Medical Aid (claim-back)
                </p>
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
