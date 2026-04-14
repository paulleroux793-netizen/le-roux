import React, { useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  BellRing, Phone, MessageCircle, CheckCircle, X as XIcon,
  AlertTriangle, Clock, Flag,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import CancelAppointmentModal from '../components/CancelAppointmentModal'

// ── Pre-Appointment Reminders page ──────────────────────────────────
// Phase 9.6 sub-area #7.
//
// Dedicated page where the receptionist can chase up every upcoming
// unconfirmed appointment in the next 7 days. Window tabs switch
// between Today / Tomorrow / This Week. Each row surfaces:
//   - Patient, time, reason, hours until
//   - The most recent confirmation attempt (channel + outcome chip)
//   - Action buttons: Send WhatsApp · Call · Confirm · Cancel
//
// All dispatch actions go through existing server endpoints (no new
// ad-hoc client-side state). Confirmation / cancel reuse the same
// endpoints the Appointments page uses, so the log + notification
// flows stay consistent.

const OUTCOME_CHIPS = {
  confirmed:   { label: 'Confirmed',   class: 'bg-[#EAF8F0] text-brand-success' },
  rescheduled: { label: 'Rescheduled', class: 'bg-[#EEF4FF] text-brand-primary' },
  cancelled:   { label: 'Cancelled',   class: 'bg-[#FFF1F1] text-brand-danger' },
  no_answer:   { label: 'No answer',   class: 'bg-[#FFF8E8] text-[#C58A22]' },
  voicemail:   { label: 'Voicemail',   class: 'bg-[#FFF8E8] text-[#C58A22]' },
  unclear:     { label: 'Unclear',     class: 'bg-[#F3F6FB] text-brand-muted' },
}

const WINDOWS = [
  { key: 'today',    label: 'Today' },
  { key: 'tomorrow', label: 'Tomorrow' },
  { key: 'week',     label: 'This Week' },
]

export default function Reminders({ reminders = [], stats }) {
  const [windowKey, setWindowKey] = useState('today')
  const [cancelTarget, setCancelTarget] = useState(null)

  // Client-side window filter — all reminders are already loaded
  // (cap is ~500 via LIST_ROW_LIMIT logic), so filtering client-side
  // avoids a round-trip on tab switch.
  const filtered = useMemo(() => {
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1)
    const dayAfter = new Date(today); dayAfter.setDate(dayAfter.getDate() + 2)

    return reminders.filter((r) => {
      const d = new Date(r.start_time)
      if (windowKey === 'today')    return d >= today    && d < tomorrow
      if (windowKey === 'tomorrow') return d >= tomorrow && d < dayAfter
      return true  // 'week' — everything in the 7-day window
    })
  }, [reminders, windowKey])

  const sendReminder = (reminder, channel) => {
    router.post(`/reminders/${reminder.id}/send`, { method: channel }, {
      preserveScroll: true,
      onSuccess: () => toast.success(
        `${channel === 'whatsapp' ? 'WhatsApp' : 'Voice'} reminder queued for ${reminder.patient_name}`
      ),
      onError: () => toast.error('Could not send reminder'),
    })
  }

  const confirmAppointment = (reminder) => {
    router.patch(`/appointments/${reminder.id}/confirm`, {}, {
      preserveScroll: true,
      onSuccess: () => toast.success(`${reminder.patient_name} confirmed`),
      onError:   () => toast.error('Could not confirm'),
    })
  }

  return (
    <DashboardLayout>
      <div className="mb-8 flex items-start justify-between">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
            Follow-up queue
          </span>
          <h1 className="mt-3 flex items-center gap-2 text-3xl font-semibold tracking-tight text-brand-ink">
            <BellRing size={22} className="text-brand-primary" />
            Pre-Appointment Reminders
          </h1>
          <p className="mt-2 text-sm leading-6 text-brand-muted">
            Chase up unconfirmed appointments in the next 7 days
          </p>
        </div>
      </div>

      {/* Stat row */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        <StatCard label="Pending total" value={stats?.total_pending ?? 0} color="text-brand-primary" />
        <StatCard label="Today"         value={stats?.today ?? 0}         color="text-brand-secondary" />
        <StatCard label="Tomorrow"      value={stats?.tomorrow ?? 0}      color="text-brand-ink" />
        <StatCard label="Flagged"       value={stats?.flagged ?? 0}       color="text-brand-danger" />
      </div>

      {/* Window tabs */}
      <div className="mb-5 inline-flex items-center rounded-2xl border border-brand-accent/80 bg-white p-1 shadow-[0_20px_45px_-34px_rgba(57,60,77,0.25)]">
        {WINDOWS.map((w) => (
          <button
            key={w.key}
            onClick={() => setWindowKey(w.key)}
            className={`rounded-2xl px-4 py-2 text-xs font-semibold transition-colors ${
              windowKey === w.key
                ? 'bg-brand-primary text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)]'
                : 'text-brand-muted hover:bg-brand-surface/45 hover:text-brand-ink'
            }`}
          >
            {w.label}
          </button>
        ))}
      </div>

      {/* List */}
      <div className="overflow-hidden rounded-[28px] border border-brand-accent/75 bg-white shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        {filtered.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-[#EAF8F0]">
              <CheckCircle size={20} className="text-brand-success" />
            </div>
            <p className="text-sm text-brand-muted">No pending reminders — all caught up.</p>
          </div>
        ) : (
          <ul className="divide-y divide-brand-accent/35">
            {filtered.map((r) => (
              <ReminderRow
                key={r.id}
                reminder={r}
                onSend={sendReminder}
                onConfirm={confirmAppointment}
                onCancel={() => setCancelTarget(r)}
              />
            ))}
          </ul>
        )}
      </div>

      <CancelAppointmentModal
        appointment={cancelTarget}
        open={!!cancelTarget}
        onClose={() => setCancelTarget(null)}
      />
    </DashboardLayout>
  )
}

function ReminderRow({ reminder, onSend, onConfirm, onCancel }) {
  const isUrgent = reminder.hours_until != null && reminder.hours_until < 24
  const isVeryUrgent = reminder.hours_until != null && reminder.hours_until < 3

  return (
    <li className={`flex items-center gap-4 px-5 py-4 transition-colors hover:bg-brand-surface/25 ${
      isVeryUrgent ? 'bg-[#FFF1F1]/80' : isUrgent ? 'bg-[#FFF8E8]/65' : ''
    }`}>
      {/* Avatar */}
      <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-surface">
        <span className="text-xs font-semibold text-brand-primary">
          {initials(reminder.patient_name)}
        </span>
      </div>

      {/* Patient + time */}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <p className="truncate text-sm font-medium text-brand-ink">{reminder.patient_name}</p>
          {reminder.last_attempt?.flagged && (
            <span className="inline-flex items-center gap-1 rounded-full bg-[#FFF1F1] px-1.5 py-0.5 text-[10px] font-semibold text-brand-danger">
              <Flag size={9} /> Flagged
            </span>
          )}
        </div>
        <p className="mt-0.5 text-xs text-brand-muted">
          <Clock size={11} className="inline mr-1 -mt-0.5" />
          {formatDateTime(reminder.start_time)}
          {reminder.reason && <span className="text-brand-muted/70"> · {reminder.reason}</span>}
        </p>
        <p className="mt-0.5 text-[11px] text-brand-muted">{reminder.patient_phone}</p>
      </div>

      {/* Time until + last attempt */}
      <div className="hidden md:flex flex-col items-end gap-1 flex-shrink-0 min-w-[140px]">
        {reminder.hours_until != null && (
          <span className={`text-xs font-semibold ${
            isVeryUrgent ? 'text-brand-danger' : isUrgent ? 'text-[#C58A22]' : 'text-brand-muted'
          }`}>
            {reminder.hours_until < 1
              ? `${Math.round(reminder.hours_until * 60)}m away`
              : `${reminder.hours_until.toFixed(1)}h away`}
          </span>
        )}
        <LastAttempt attempt={reminder.last_attempt} />
      </div>

      {/* Actions */}
      <div className="flex items-center gap-1 flex-shrink-0">
        <ActionBtn
          title="Send WhatsApp reminder"
          icon={MessageCircle}
          onClick={() => onSend(reminder, 'whatsapp')}
          colorClass="text-emerald-600 hover:bg-emerald-50"
        />
        <ActionBtn
          title="Send voice reminder"
          icon={Phone}
          onClick={() => onSend(reminder, 'voice')}
          colorClass="text-blue-600 hover:bg-blue-50"
        />
        <ActionBtn
          title="Confirm"
          icon={CheckCircle}
          onClick={() => onConfirm(reminder)}
          colorClass="text-brand-primary hover:bg-brand-surface/65"
        />
        <ActionBtn
          title="Cancel"
          icon={XIcon}
          onClick={onCancel}
          colorClass="text-red-600 hover:bg-red-50"
        />
      </div>
    </li>
  )
}

function LastAttempt({ attempt }) {
  if (!attempt) {
    return (
      <span className="inline-flex items-center gap-1 text-[10px] font-medium text-brand-muted">
        <AlertTriangle size={10} /> Never contacted
      </span>
    )
  }
  const chip = OUTCOME_CHIPS[attempt.outcome]
  return (
    <span className="inline-flex items-center gap-1 text-[10px] font-medium text-brand-muted">
      via <span className="capitalize">{attempt.method}</span>
      {chip && (
        <span className={`ml-1 px-1.5 py-0.5 rounded-full ${chip.class}`}>{chip.label}</span>
      )}
      {!attempt.outcome && (
        <span className="ml-1 rounded-full bg-[#F3F6FB] px-1.5 py-0.5 text-brand-muted">Awaiting reply</span>
      )}
    </span>
  )
}

function ActionBtn({ title, icon: Icon, onClick, colorClass }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      onClick={onClick}
      className={`p-2 rounded-md transition-colors ${colorClass}`}
    >
      <Icon size={15} />
    </button>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div className="rounded-[28px] border border-brand-accent/75 bg-white p-4 text-center shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
      <p className={`text-2xl font-bold ${color}`}>{value}</p>
      <p className="mt-1 text-xs uppercase tracking-wide text-brand-muted">{label}</p>
    </div>
  )
}

function initials(name = '') {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]?.toUpperCase() || '')
      .join('') || '·'
  )
}

function formatDateTime(iso) {
  const d = new Date(iso)
  return d.toLocaleString('en-ZA', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}
