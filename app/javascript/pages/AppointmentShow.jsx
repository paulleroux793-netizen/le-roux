import React from 'react'
import { Link } from '@inertiajs/react'
import DashboardLayout from '../layouts/DashboardLayout'

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
}

export default function AppointmentShow({ appointment }) {
  const apt = appointment

  return (
    <DashboardLayout>
      <div className="mb-6">
        <Link
          href="/appointments"
          className="text-sm text-brand-taupe hover:text-brand-brown transition-colors"
        >
          ← Back to Appointments
        </Link>
      </div>

      {/* Main details */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <div className="flex items-start justify-between mb-6">
          <h1 className="text-xl font-bold text-brand-brown">Appointment Details</h1>
          <StatusBadge status={apt.status} />
        </div>

        <div className="grid grid-cols-2 gap-6">
          <Field label="Patient">
            <p className="text-gray-900 text-sm">{apt.patient_name}</p>
            <p className="text-xs text-gray-400 mt-0.5">{apt.patient_phone}</p>
          </Field>
          <Field label="Date & Time">
            <p className="text-gray-900 text-sm">
              {new Date(apt.start_time).toLocaleDateString('en-ZA', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
            </p>
            <p className="text-xs text-gray-400 mt-0.5">
              {new Date(apt.start_time).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })} — {new Date(apt.end_time).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })}
            </p>
          </Field>
          <Field label="Reason">
            <p className="text-gray-900 text-sm">{apt.reason || 'Not specified'}</p>
          </Field>
          <Field label="Notes">
            <p className="text-gray-900 text-sm">{apt.notes || 'None'}</p>
          </Field>
        </div>
      </div>

      {/* N3 — End-of-appointment AI bullet summary */}
      {apt.summary && (
        <div className="mb-5 rounded-xl border border-brand-primary/20 bg-gradient-to-br from-brand-primary/5 to-white p-5">
          <div className="mb-3 flex items-center justify-between">
            <div>
              <h2 className="text-base font-semibold text-brand-ink">Appointment summary</h2>
              <p className="text-xs text-brand-muted">
                Auto-generated from the chair-side scribe transcript ·{' '}
                {new Date(apt.summary.generated_at).toLocaleString('en-ZA')}
              </p>
            </div>
            <span className="inline-flex items-center rounded-full bg-brand-primary/10 px-2 py-0.5 text-[11px] font-semibold text-brand-primary">AI generated</span>
          </div>

          <div className="space-y-4">
            {apt.summary.decisions && (
              <div>
                <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-brand-muted">Decisions &amp; recommendations</p>
                <p className="text-sm text-brand-ink whitespace-pre-wrap">{apt.summary.decisions}</p>
              </div>
            )}

            {(apt.summary.patient_questions || []).length > 0 && (
              <div>
                <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-brand-muted">Patient questions &amp; answers</p>
                <ul className="space-y-1.5 text-sm">
                  {apt.summary.patient_questions.map((qa, i) => (
                    <li key={i} className="rounded-lg bg-white border border-brand-border px-3 py-2">
                      <p className="font-medium text-brand-ink">Q: {qa.q}</p>
                      <p className="mt-0.5 text-brand-muted">A: {qa.a}</p>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {apt.summary.estimate_intent && (
              <div>
                <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-brand-muted">Estimate intent (planned at chair-side)</p>
                <p className="text-sm text-brand-ink whitespace-pre-wrap">{apt.summary.estimate_intent}</p>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Cancellation Reason */}
      {apt.cancellation_reason && (
        <div className="bg-red-50 rounded-xl border border-red-100 p-5 mb-5">
          <h2 className="text-sm font-semibold text-red-700 mb-2">Cancellation Reason</h2>
          <p className="text-sm text-red-700">
            <span className="font-medium">Category:</span> {apt.cancellation_reason.category}
          </p>
          {apt.cancellation_reason.details && (
            <p className="text-sm text-red-600 mt-1">{apt.cancellation_reason.details}</p>
          )}
        </div>
      )}

      {/* Confirmation Logs */}
      {apt.confirmation_logs?.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-base font-semibold text-brand-brown mb-4">Confirmation History</h2>
          <div className="space-y-2">
            {apt.confirmation_logs.map((log, i) => (
              <div
                key={i}
                className={`flex items-center justify-between px-4 py-3 rounded-lg text-sm ${
                  log.flagged
                    ? 'bg-amber-50 border border-amber-100'
                    : 'bg-gray-50'
                }`}
              >
                <div className="flex items-center gap-2">
                  <span className="font-medium text-gray-800 capitalize">{log.method}</span>
                  <span className="text-gray-400">·</span>
                  <span className="text-gray-600 capitalize">{log.outcome || 'pending'}</span>
                  {log.flagged && (
                    <span className="text-xs font-semibold text-amber-600 bg-amber-100 px-1.5 py-0.5 rounded">
                      FLAGGED
                    </span>
                  )}
                </div>
                <span className="text-xs text-gray-400">
                  {log.attempts} attempt{log.attempts !== 1 ? 's' : ''} · {new Date(log.created_at).toLocaleString('en-ZA')}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </DashboardLayout>
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

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${STATUS_STYLES[status] || 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}
