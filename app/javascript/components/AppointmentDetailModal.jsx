import React from 'react'
import { router } from '@inertiajs/react'
import { Phone, Mail, Calendar, Edit3, X as XIcon, FileText, UserPlus, UserCheck, Cake, Globe, User, ClipboardPlus, Mic, MessageCircle, Send, Trash2 } from 'lucide-react'
import { Link } from '@inertiajs/react'
import { toast } from 'sonner'
import Modal from './Modal'

// ── Detail modal ────────────────────────────────────────────────────
// Click an event on the calendar → this pops open with the full patient
// + booking detail and the patient-journey status buttons. Reception
// drives a patient through the day from here:
//   Confirm → Arrived → In Consultation → Completed
// Each transition recolours the event on the calendar.
const STATUS_CHIP = {
  scheduled:            'bg-gray-100 text-gray-600',
  confirmed:            'bg-emerald-100 text-emerald-700',
  arrived:              'bg-yellow-100 text-yellow-800',
  in_consultation:      'bg-blue-100 text-blue-700',
  completed:            'bg-blue-700 text-white',
  cancelled:            'bg-red-100 text-red-700',
  no_show:              'bg-gray-100 text-gray-600',
  rescheduled:          'bg-violet-100 text-violet-700',
  pending_confirmation: 'bg-orange-100 text-orange-700',
}

// The front-desk journey, in order. Each button sets the status via
// /appointments/:id/set_status and tints the calendar event.
// "Start consultation" triggers ScribeSession.start_for under the hood
// (P9.4) — the receptionist doesn't need to know that.
const JOURNEY = [
  { key: 'confirmed',       label: 'Confirm',            active: 'bg-emerald-500' },
  { key: 'arrived',         label: 'Arrived',            active: 'bg-yellow-400 text-yellow-900' },
  { key: 'in_consultation', label: 'Start consultation', active: 'bg-blue-400', icon: Mic, hint: 'Scribe auto-starts' },
  { key: 'completed',       label: 'Completed',          active: 'bg-blue-700' },
]

const STATUS_LABEL = {
  scheduled: 'Scheduled', confirmed: 'Confirmed', arrived: 'Arrived',
  in_consultation: 'In Consultation', completed: 'Completed',
  cancelled: 'Cancelled', no_show: 'No show', rescheduled: 'Rescheduled',
  pending_confirmation: 'Pending Confirmation',
}

const fmtDate = (iso) =>
  new Date(iso).toLocaleDateString('en-ZA', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })

const fmtTime = (iso) =>
  new Date(iso).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })

const fmtDob = (iso) => {
  if (!iso) return null
  const d = new Date(iso)
  const age = Math.floor((Date.now() - d.getTime()) / (365.25 * 24 * 3600 * 1000))
  return `${d.toLocaleDateString('en-ZA', { day: 'numeric', month: 'short', year: 'numeric' })} (age ${age})`
}

export default function AppointmentDetailModal({ appointment, open, onClose, onEdit, onCancel, onDelete }) {
  if (!appointment) return null

  const setStatus = (status) => {
    router.patch(`/appointments/${appointment.id}/set_status`, { status }, {
      preserveScroll: true,
      onSuccess: () => { toast.success(`Marked as ${STATUS_LABEL[status] || status}`); onClose?.() },
      onError:   () => toast.error('Could not update status'),
    })
  }

  // Send the practice's standard WhatsApp messages to this patient (reception-triggered).
  // kind = 'pack' (4 messages) or 'confirm' (booking confirmation only).
  const sendWhatsapp = (kind) => {
    const what = kind === 'pack' ? 'all 4 standard WhatsApp messages' : 'the booking confirmation'
    if (!window.confirm(`Send ${what} to ${appointment.patient_name || 'this patient'} on WhatsApp?`)) return
    router.post(`/appointments/${appointment.id}/whatsapp_${kind}`, {}, {
      preserveScroll: true,
      onSuccess: () => toast.success('WhatsApp message(s) sent'),
      onError:   () => toast.error('Could not send WhatsApp message(s)'),
    })
  }

  const dob = fmtDob(appointment.patient_dob)
  const isNew = appointment.is_new_patient

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Appointment Details"
      size="xl"
      footer={
        <div className="flex w-full items-center justify-between gap-2">
          <div className="flex items-center gap-1">
            <button
              onClick={onCancel}
              className="inline-flex items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-medium text-brand-danger transition-colors hover:bg-brand-danger/10"
            >
              <XIcon size={15} /> Cancel
            </button>
            {onDelete && (
              <button
                onClick={onDelete}
                title="Permanently remove this appointment from the diary"
                className="inline-flex items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-medium text-brand-danger transition-colors hover:bg-brand-danger/10"
              >
                <Trash2 size={15} /> Delete
              </button>
            )}
          </div>
          <button
            onClick={onEdit}
            className="inline-flex items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-medium text-brand-ink transition-colors hover:bg-brand-surface/45"
          >
            <Edit3 size={15} /> Edit
          </button>
        </div>
      }
    >
      {/* Patient card */}
      <div className="mb-4 rounded-xl border border-brand-accent/75 bg-gradient-to-br from-brand-surface/35 to-white p-5">
        <div className="flex items-start gap-4">
          <div className="flex h-14 w-14 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-primary">
            <span className="text-white font-semibold">
              {(appointment.patient_name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()}
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <h3 className="truncate text-lg font-semibold text-brand-ink">{appointment.patient_name}</h3>
              <span className={`inline-flex flex-shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold ${isNew ? 'bg-sky-100 text-sky-700' : 'bg-gray-100 text-gray-600'}`}>
                {isNew ? <><UserPlus size={11} /> New patient</> : <><UserCheck size={11} /> Returning</>}
              </span>
            </div>
            <div className="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-brand-muted">
              {appointment.patient_phone && (
                <span className="flex items-center gap-1.5"><Phone size={13} /> {appointment.patient_phone}</span>
              )}
              {appointment.patient_email && (
                <span className="flex items-center gap-1.5"><Mail size={13} /> {appointment.patient_email}</span>
              )}
            </div>
          </div>
          <span className={`inline-flex flex-shrink-0 items-center rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_CHIP[appointment.status] || 'bg-gray-100 text-gray-600'}`}>
            {STATUS_LABEL[appointment.status] || appointment.status}
          </span>
        </div>
      </div>

      {/* Patient journey — one-click status buttons */}
      <div className="mb-4">
        <h4 className="mb-2 text-xs font-semibold uppercase tracking-wide text-brand-muted">Patient journey</h4>
        <div className="grid grid-cols-4 gap-2">
          {JOURNEY.map((step) => {
            const isCurrent = appointment.status === step.key
            const StepIcon = step.icon
            return (
              <button
                key={step.key}
                onClick={() => setStatus(step.key)}
                title={step.hint || undefined}
                className={`flex items-center justify-center gap-1 rounded-xl px-2 py-2.5 text-xs font-semibold transition-colors ${
                  isCurrent
                    ? `${step.active} ${step.key === 'arrived' ? '' : 'text-white'} shadow-sm`
                    : 'border border-brand-border bg-white text-brand-ink hover:bg-brand-surface/50'
                }`}
              >
                {StepIcon && <StepIcon size={12} />}
                {step.label}
              </button>
            )
          })}
        </div>
        <p className="mt-1.5 text-[11px] text-brand-muted">
          Tap to update — the colour on the calendar changes to match.
        </p>
      </div>

      {/* WhatsApp standard messages — reception sends the practice's standard pack or just the confirmation */}
      {appointment.patient_phone && (
        <div className="mb-4">
          <h4 className="mb-2 text-xs font-semibold uppercase tracking-wide text-brand-muted">WhatsApp the patient</h4>
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => sendWhatsapp('pack')}
              className="flex items-center justify-center gap-1.5 rounded-xl border border-emerald-200 bg-emerald-50 px-2 py-2.5 text-xs font-semibold text-emerald-700 transition-colors hover:bg-emerald-100"
            >
              <MessageCircle size={13} /> Send 4 standard messages
            </button>
            <button
              onClick={() => sendWhatsapp('confirm')}
              className="flex items-center justify-center gap-1.5 rounded-xl border border-emerald-200 bg-white px-2 py-2.5 text-xs font-semibold text-emerald-700 transition-colors hover:bg-emerald-50"
            >
              <Send size={13} /> Send booking confirmation
            </button>
          </div>
          <p className="mt-1.5 text-[11px] text-brand-muted">
            Pack = location, directions, intake form + the booking confirmation. Or send just the confirmation.
          </p>
        </div>
      )}

      {/* Booking info */}
      <div>
        <h4 className="mb-2 text-sm font-semibold text-brand-ink">Booking information</h4>
        <div className="space-y-3 rounded-xl border border-brand-accent/75 p-4">
          <Row icon={Calendar} label="Date">{fmtDate(appointment.start_time)}</Row>
          <Row icon={Calendar} label="Time">{fmtTime(appointment.start_time)} — {fmtTime(appointment.end_time)}</Row>
          <Row icon={FileText} label="Reason for visit">{appointment.reason || '—'}</Row>
          {dob && <Row icon={Cake} label="Date of birth">{dob}</Row>}
          {appointment.patient_language && (
            <Row icon={Globe} label="Preferred language">
              {appointment.patient_language === 'af' ? 'Afrikaans' : 'English'}
            </Row>
          )}
          {appointment.notes && (
            <Row icon={FileText} label="Notes"><span className="whitespace-pre-wrap">{appointment.notes}</span></Row>
          )}
        </div>
      </div>

      {/* Context-aware primary action: one click from the booking straight into a
          new estimate — which then pre-suggests the codes for this visit reason. */}
      <button
        type="button"
        onClick={() => { router.post(`/patients/${appointment.patient_id}/estimates`); onClose?.() }}
        className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-brand-primary px-3 py-2.5 text-sm font-semibold text-white hover:bg-brand-primary-dark"
      >
        <FileText size={15} /> Start estimate for this visit
      </button>

      {/* R3 — quick links so reception/dentist can jump from a calendar
          pop-over to the patient's profile or active treatment plan
          without backtracking through the patients list. */}
      <div className="mt-2 grid grid-cols-2 gap-2">
        <Link
          href={`/patients/${appointment.patient_id}`}
          onClick={onClose}
          className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 text-sm font-medium text-brand-ink hover:bg-brand-surface"
        >
          <span className="flex items-center gap-2"><User size={14} /> Open patient profile</span>
          <span className="text-brand-muted group-hover:text-brand-ink">→</span>
        </Link>
        <Link
          href={`/courses-of-treatment?patient_id=${appointment.patient_id}`}
          onClick={onClose}
          className="group flex items-center justify-between rounded-xl border border-brand-border bg-white px-3 py-2.5 text-sm font-medium text-brand-ink hover:bg-brand-surface"
        >
          <span className="flex items-center gap-2"><ClipboardPlus size={14} /> View treatment plans</span>
          <span className="text-brand-muted group-hover:text-brand-ink">→</span>
        </Link>
      </div>
    </Modal>
  )
}

function Row({ icon: Icon, label, children }) {
  return (
    <div className="flex items-start gap-3">
      <Icon size={15} className="mt-0.5 flex-shrink-0 text-brand-primary" />
      <div className="flex-1">
        <p className="text-xs font-semibold uppercase tracking-wide text-brand-muted">{label}</p>
        <p className="mt-0.5 text-sm text-brand-ink">{children}</p>
      </div>
    </div>
  )
}
