import React, { useState } from 'react'
import { Link } from '@inertiajs/react'
import { Pencil, HeartPulse, Shield, Phone } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import PatientFormModal from '../components/PatientFormModal'

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
}

export default function PatientShow({ patient, medical_history, appointments, conversations }) {
  const [editOpen, setEditOpen] = useState(false)

  return (
    <DashboardLayout>
      <div className="mb-6">
        <Link href="/patients" className="text-sm text-brand-taupe hover:text-brand-brown transition-colors">
          ← Back to Patients
        </Link>
      </div>

      {/* Patient Info Card */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <div className="flex items-start justify-between mb-4">
          <h1 className="text-xl font-bold text-brand-brown">{patient.full_name}</h1>
          <button
            type="button"
            onClick={() => setEditOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-brand-brown hover:bg-brand-cream rounded-lg transition-colors border border-gray-200"
          >
            <Pencil size={13} /> Edit
          </button>
        </div>
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
