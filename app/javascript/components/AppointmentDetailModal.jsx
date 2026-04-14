import React from 'react'
import { router } from '@inertiajs/react'
import { Phone, Mail, Calendar, Edit3, X as XIcon, CheckCircle } from 'lucide-react'
import { toast } from 'sonner'
import Modal from './Modal'

// ── Detail modal ────────────────────────────────────────────────────
// Rendered when the user clicks an event on the calendar. Mirrors the
// right-side panel from screenshot ref #1 (Jerome Bellingham). Keeps
// the heavy-weight AppointmentShow.jsx page intact — that's still
// available for deep-link access, but 90% of reception tasks are
// one-screen operations that don't need a full navigation.
//
// Actions (Edit / Cancel) are callbacks rather than navigation so the
// host page can swap this modal for the Edit / Cancel modals in place.
const STATUS_CHIP = {
  scheduled:   'bg-amber-100 text-amber-700',
  confirmed:   'bg-emerald-100 text-emerald-700',
  completed:   'bg-blue-100 text-blue-700',
  cancelled:   'bg-red-100 text-red-700',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-violet-100 text-violet-700',
}

const fmtDate = (iso) =>
  new Date(iso).toLocaleDateString('en-ZA', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })

const fmtTime = (iso) =>
  new Date(iso).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })

export default function AppointmentDetailModal({
  appointment,
  open,
  onClose,
  onEdit,
  onCancel,
}) {
  if (!appointment) return null

  const handleConfirm = () => {
    router.patch(`/appointments/${appointment.id}/confirm`, {}, {
      preserveScroll: true,
      onSuccess: () => {
        toast.success('Appointment confirmed')
        onClose?.()
      },
      onError: () => toast.error('Could not confirm'),
    })
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Appointment Details"
      size="xl"
      footer={
        <>
          <button
            onClick={onCancel}
            className="inline-flex items-center gap-1.5 rounded-xl px-4 py-2 text-sm font-medium text-brand-danger transition-colors hover:bg-brand-danger/10"
          >
            <XIcon size={15} /> Cancel
          </button>
          <button
            onClick={onEdit}
            className="inline-flex items-center gap-1.5 rounded-2xl px-4 py-2 text-sm font-medium text-brand-ink transition-colors hover:bg-brand-surface/45"
          >
            <Edit3 size={15} /> Edit
          </button>
          {appointment.status !== 'confirmed' && appointment.status !== 'cancelled' && (
            <button
              onClick={handleConfirm}
              className="inline-flex items-center gap-1.5 rounded-2xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark"
            >
              <CheckCircle size={15} /> Confirm
            </button>
          )}
        </>
      }
    >
      {/* Patient card */}
      <div className="mb-5 rounded-xl border border-brand-accent/75 bg-gradient-to-br from-brand-surface/35 to-white p-5">
        <div className="flex items-start gap-4">
          <div className="flex h-14 w-14 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-primary">
            <span className="text-white font-semibold">
              {(appointment.patient_name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()}
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="truncate text-lg font-semibold text-brand-ink">
              {appointment.patient_name}
            </h3>
            <div className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-brand-muted">
              {appointment.patient_phone && (
                <span className="flex items-center gap-1.5">
                  <Phone size={13} /> {appointment.patient_phone}
                </span>
              )}
            </div>
          </div>
          <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${STATUS_CHIP[appointment.status] || 'bg-gray-100 text-gray-600'}`}>
            {appointment.status}
          </span>
        </div>
      </div>

      {/* Booking Info */}
      <div>
        <h4 className="mb-3 text-sm font-semibold text-brand-ink">Booking Information</h4>
        <div className="space-y-3 rounded-xl border border-brand-accent/75 p-4">
          <Row icon={Calendar} label="Date">
            {fmtDate(appointment.start_time)}
          </Row>
          <Row icon={Calendar} label="Time">
            {fmtTime(appointment.start_time)} — {fmtTime(appointment.end_time)}
          </Row>
          <Row icon={Mail} label="Reason">
            {appointment.reason || '—'}
          </Row>
        </div>
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
