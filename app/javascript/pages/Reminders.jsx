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
  confirmed:   { label: 'Confirmed',   class: 'bg-emerald-100 text-emerald-700' },
  rescheduled: { label: 'Rescheduled', class: 'bg-purple-100 text-purple-700' },
  cancelled:   { label: 'Cancelled',   class: 'bg-red-100 text-red-700' },
  no_answer:   { label: 'No answer',   class: 'bg-amber-100 text-amber-700' },
  voicemail:   { label: 'Voicemail',   class: 'bg-amber-100 text-amber-700' },
  unclear:     { label: 'Unclear',     class: 'bg-gray-100 text-gray-600' },
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
          <h1 className="text-2xl font-bold text-brand-brown flex items-center gap-2">
            <BellRing size={22} className="text-brand-taupe" />
            Pre-Appointment Reminders
          </h1>
          <p className="text-gray-500 mt-1 text-sm">
            Chase up unconfirmed appointments in the next 7 days
          </p>
        </div>
      </div>

      {/* Stat row */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        <StatCard label="Pending total" value={stats?.total_pending ?? 0} color="text-brand-brown" />
        <StatCard label="Today"         value={stats?.today ?? 0}         color="text-amber-600" />
        <StatCard label="Tomorrow"      value={stats?.tomorrow ?? 0}      color="text-blue-600" />
        <StatCard label="Flagged"       value={stats?.flagged ?? 0}       color="text-red-500" />
      </div>

      {/* Window tabs */}
      <div className="inline-flex items-center bg-gray-100 rounded-lg p-1 mb-5">
        {WINDOWS.map((w) => (
          <button
            key={w.key}
            onClick={() => setWindowKey(w.key)}
            className={`px-4 py-1.5 rounded-md text-xs font-semibold transition-colors ${
              windowKey === w.key
                ? 'bg-white text-brand-brown shadow-sm'
                : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            {w.label}
          </button>
        ))}
      </div>

      {/* List */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        {filtered.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div className="w-12 h-12 mx-auto rounded-full bg-emerald-50 flex items-center justify-center mb-3">
              <CheckCircle size={20} className="text-emerald-500" />
            </div>
            <p className="text-sm text-gray-500">No pending reminders — all caught up.</p>
          </div>
        ) : (
          <ul className="divide-y divide-gray-100">
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
    <li className={`flex items-center gap-4 px-5 py-4 hover:bg-brand-cream/30 transition-colors ${
      isVeryUrgent ? 'bg-red-50/40' : isUrgent ? 'bg-amber-50/30' : ''
    }`}>
      {/* Avatar */}
      <div className="w-10 h-10 rounded-full bg-brand-cream flex items-center justify-center flex-shrink-0">
        <span className="text-brand-brown text-xs font-semibold">
          {initials(reminder.patient_name)}
        </span>
      </div>

      {/* Patient + time */}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-gray-900 truncate">{reminder.patient_name}</p>
          {reminder.last_attempt?.flagged && (
            <span className="inline-flex items-center gap-1 text-[10px] font-semibold px-1.5 py-0.5 rounded-full bg-red-100 text-red-700">
              <Flag size={9} /> Flagged
            </span>
          )}
        </div>
        <p className="text-xs text-gray-500 mt-0.5">
          <Clock size={11} className="inline mr-1 -mt-0.5" />
          {formatDateTime(reminder.start_time)}
          {reminder.reason && <span className="text-gray-400"> · {reminder.reason}</span>}
        </p>
        <p className="text-[11px] text-gray-400 mt-0.5">{reminder.patient_phone}</p>
      </div>

      {/* Time until + last attempt */}
      <div className="hidden md:flex flex-col items-end gap-1 flex-shrink-0 min-w-[140px]">
        {reminder.hours_until != null && (
          <span className={`text-xs font-semibold ${
            isVeryUrgent ? 'text-red-600' : isUrgent ? 'text-amber-600' : 'text-gray-500'
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
          colorClass="text-brand-taupe hover:bg-brand-cream"
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
      <span className="inline-flex items-center gap-1 text-[10px] font-medium text-gray-400">
        <AlertTriangle size={10} /> Never contacted
      </span>
    )
  }
  const chip = OUTCOME_CHIPS[attempt.outcome]
  return (
    <span className="inline-flex items-center gap-1 text-[10px] font-medium text-gray-500">
      via <span className="capitalize">{attempt.method}</span>
      {chip && (
        <span className={`ml-1 px-1.5 py-0.5 rounded-full ${chip.class}`}>{chip.label}</span>
      )}
      {!attempt.outcome && (
        <span className="ml-1 px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-500">Awaiting reply</span>
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
    <div className="bg-white rounded-xl border border-gray-200 p-4 text-center">
      <p className={`text-2xl font-bold ${color}`}>{value}</p>
      <p className="text-xs text-gray-400 mt-1 uppercase tracking-wide">{label}</p>
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
