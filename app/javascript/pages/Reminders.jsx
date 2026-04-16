import React, { useEffect, useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  BellRing, Phone, MessageCircle, CheckCircle, X as XIcon,
  Clock, Search, ChevronLeft, ChevronRight, Sparkles,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import CancelAppointmentModal from '../components/CancelAppointmentModal'

// ── Pre-Appointment Reminders page ──────────────────────────────────
// Redesigned to match a clean table layout with status chips.
// Shows ALL upcoming appointments with their reminder/confirmation
// status so the receptionist sees the full picture at a glance.

const STATUS_CHIPS = {
  Pending:     { label: 'Pending',     bg: 'bg-amber-50',    text: 'text-amber-700',   border: 'border-amber-200' },
  Sent:        { label: 'Sent',        bg: 'bg-blue-50',     text: 'text-blue-700',    border: 'border-blue-200' },
  Confirmed:   { label: 'Confirmed',   bg: 'bg-emerald-50',  text: 'text-emerald-700', border: 'border-emerald-200' },
  Cancelled:   { label: 'Cancelled',   bg: 'bg-red-50',      text: 'text-red-700',     border: 'border-red-200' },
  'No Answer': { label: 'No Answer',   bg: 'bg-orange-50',   text: 'text-orange-700',  border: 'border-orange-200' },
  Completed:   { label: 'Completed',   bg: 'bg-brand-surface', text: 'text-brand-muted', border: 'border-brand-border' },
  'No Show':   { label: 'No Show',     bg: 'bg-gray-50',     text: 'text-gray-600',    border: 'border-gray-200' },
  Rescheduled: { label: 'Rescheduled', bg: 'bg-purple-50',   text: 'text-purple-700',  border: 'border-purple-200' },
}

const WINDOWS = [
  { key: 'today',    label: 'Today' },
  { key: 'tomorrow', label: 'Tomorrow' },
  { key: 'week',     label: 'This Week' },
]

const PAGE_SIZE = 10

export default function Reminders({ reminders = [], stats }) {
  const [windowKey, setWindowKey] = useState('week')
  const [cancelTarget, setCancelTarget] = useState(null)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [sortField, setSortField] = useState('start_time')
  const [sortDir, setSortDir] = useState('asc')

  // Poll for fresh reminder data every 15 seconds
  useEffect(() => {
    const timer = setInterval(() => {
      router.reload({
        only: ['reminders', 'stats'],
        preserveState: true,
        preserveScroll: true,
      })
    }, 15_000)
    return () => clearInterval(timer)
  }, [])

  // Window filter
  const windowed = useMemo(() => {
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1)
    const dayAfter = new Date(today); dayAfter.setDate(dayAfter.getDate() + 2)

    return reminders.filter((r) => {
      const d = new Date(r.start_time)
      if (windowKey === 'today')    return d >= today    && d < tomorrow
      if (windowKey === 'tomorrow') return d >= tomorrow && d < dayAfter
      return true
    })
  }, [reminders, windowKey])

  // Search filter
  const searched = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return windowed
    return windowed.filter((r) => {
      const haystack = [r.patient_name, r.patient_phone, r.reason, r.reminder_status]
        .filter(Boolean).join(' ').toLowerCase()
      return haystack.includes(q)
    })
  }, [windowed, search])

  // Sort
  const sorted = useMemo(() => {
    return [...searched].sort((a, b) => {
      let aVal = a[sortField] || ''
      let bVal = b[sortField] || ''
      if (sortField === 'start_time') {
        aVal = new Date(aVal); bVal = new Date(bVal)
      }
      if (aVal < bVal) return sortDir === 'asc' ? -1 : 1
      if (aVal > bVal) return sortDir === 'asc' ? 1 : -1
      return 0
    })
  }, [searched, sortField, sortDir])

  // Pagination
  const totalPages = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE))
  const paginated = sorted.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const toggleSort = (field) => {
    if (sortField === field) {
      setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    } else {
      setSortField(field)
      setSortDir('asc')
    }
    setPage(1)
  }

  const sendReminder = (reminder, channel) => {
    router.post(`/reminders/${reminder.id}/send`, { method: channel }, {
      preserveScroll: true,
      onSuccess: () => toast.success(
        `${channel === 'whatsapp' ? 'WhatsApp' : 'Voice'} reminder sent to ${reminder.patient_name}`
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
      {/* Header */}
      <div className="mb-8">
        <div className="inline-flex items-center gap-2 rounded-full border border-brand-border bg-white/90 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
          <Sparkles size={12} />
          Follow-up queue
        </div>
        <h1 className="mt-3 flex items-center gap-2 text-[1.9rem] font-semibold tracking-tight text-brand-ink">
          <BellRing size={22} className="text-brand-primary" />
          Pre-Appointment Reminders
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-brand-muted">
          Track all upcoming appointments and their confirmation status. Send reminders, confirm, or cancel directly from this page.
        </p>
      </div>

      {/* Stat cards */}
      <div className="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard label="Total upcoming" value={stats?.total ?? 0} color="text-brand-primary" />
        <StatCard label="Pending"        value={stats?.pending ?? 0} color="text-amber-600" />
        <StatCard label="Confirmed"      value={stats?.confirmed ?? 0} color="text-emerald-600" />
        <StatCard label="Today"          value={stats?.today ?? 0} color="text-brand-ink" />
      </div>

      {/* Controls row */}
      <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        {/* Window tabs */}
        <div className="inline-flex items-center rounded-xl border border-brand-border bg-white p-1">
          {WINDOWS.map((w) => (
            <button
              key={w.key}
              onClick={() => { setWindowKey(w.key); setPage(1) }}
              className={`rounded-lg px-4 py-2 text-xs font-semibold transition-colors ${
                windowKey === w.key
                  ? 'bg-brand-primary text-white shadow-sm'
                  : 'text-brand-muted hover:bg-brand-surface hover:text-brand-ink'
              }`}
            >
              {w.label}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="relative w-full max-w-xs">
          <Search size={15} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted" />
          <input
            type="text"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            placeholder="Search patient, phone, status…"
            className="w-full rounded-xl border border-brand-border bg-white px-9 py-2.5 text-sm text-brand-ink placeholder:text-brand-muted focus:border-brand-primary focus:outline-none focus:ring-2 focus:ring-brand-primary/20"
          />
        </div>
      </div>

      {/* Table */}
      <div className="overflow-hidden rounded-xl border border-brand-border bg-white shadow-sm">
        {sorted.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-brand-success/10">
              <CheckCircle size={20} className="text-brand-success" />
            </div>
            <p className="text-sm font-medium text-brand-ink">All caught up</p>
            <p className="mt-1 text-xs text-brand-muted">No appointments match your current filter.</p>
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-brand-border bg-brand-surface/50">
                    <SortHeader label="Patient" field="patient_name" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <SortHeader label="Appointment" field="start_time" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <SortHeader label="Reason" field="reason" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <SortHeader label="Status" field="reminder_status" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-brand-muted">Phone</th>
                    <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-brand-muted">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-brand-border/50">
                  {paginated.map((r) => (
                    <ReminderRow
                      key={r.id}
                      reminder={r}
                      onSend={sendReminder}
                      onConfirm={confirmAppointment}
                      onCancel={() => setCancelTarget(r)}
                    />
                  ))}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            <div className="flex items-center justify-between border-t border-brand-border px-4 py-3">
              <p className="text-xs text-brand-muted">
                Showing <span className="font-semibold text-brand-ink">{(page - 1) * PAGE_SIZE + 1}</span> to{' '}
                <span className="font-semibold text-brand-ink">{Math.min(page * PAGE_SIZE, sorted.length)}</span> of{' '}
                <span className="font-semibold text-brand-ink">{sorted.length}</span> results
              </p>
              <div className="flex items-center gap-1">
                <button
                  onClick={() => setPage(p => Math.max(1, p - 1))}
                  disabled={page <= 1}
                  className="rounded-lg p-1.5 text-brand-muted transition hover:bg-brand-surface disabled:opacity-30"
                >
                  <ChevronLeft size={16} />
                </button>
                {Array.from({ length: totalPages }, (_, i) => i + 1).slice(
                  Math.max(0, page - 3), page + 2
                ).map(p => (
                  <button
                    key={p}
                    onClick={() => setPage(p)}
                    className={`h-8 w-8 rounded-lg text-xs font-medium transition ${
                      p === page
                        ? 'bg-brand-primary text-white'
                        : 'text-brand-muted hover:bg-brand-surface'
                    }`}
                  >
                    {p}
                  </button>
                ))}
                <button
                  onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                  disabled={page >= totalPages}
                  className="rounded-lg p-1.5 text-brand-muted transition hover:bg-brand-surface disabled:opacity-30"
                >
                  <ChevronRight size={16} />
                </button>
              </div>
            </div>
          </>
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

// ── Table row ──────────────────────────────────────────────────────
function ReminderRow({ reminder, onSend, onConfirm, onCancel }) {
  const chip = STATUS_CHIPS[reminder.reminder_status] || STATUS_CHIPS.Pending

  return (
    <tr className="transition-colors hover:bg-brand-surface/30">
      {/* Patient */}
      <td className="whitespace-nowrap px-4 py-3.5">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary/10">
            <span className="text-xs font-semibold text-brand-primary">
              {initials(reminder.patient_name)}
            </span>
          </div>
          <div>
            <p className="text-sm font-medium text-brand-ink">{reminder.patient_name}</p>
            {reminder.hours_until != null && (
              <p className={`text-[11px] font-medium ${
                reminder.hours_until < 3 ? 'text-red-500' :
                reminder.hours_until < 24 ? 'text-amber-500' : 'text-brand-muted'
              }`}>
                {reminder.hours_until < 1
                  ? `${Math.round(reminder.hours_until * 60)}m away`
                  : `${reminder.hours_until.toFixed(1)}h away`}
              </p>
            )}
          </div>
        </div>
      </td>

      {/* Appointment time */}
      <td className="whitespace-nowrap px-4 py-3.5">
        <p className="text-sm text-brand-ink">{formatDate(reminder.start_time)}</p>
        <p className="text-xs text-brand-muted">{formatTime(reminder.start_time)} – {formatTime(reminder.end_time)}</p>
      </td>

      {/* Reason */}
      <td className="px-4 py-3.5">
        <p className="max-w-[180px] truncate text-sm text-brand-ink">
          {reminder.reason || 'General appointment'}
        </p>
      </td>

      {/* Status chip */}
      <td className="px-4 py-3.5">
        <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${chip.bg} ${chip.text} ${chip.border}`}>
          {chip.label}
        </span>
      </td>

      {/* Phone */}
      <td className="whitespace-nowrap px-4 py-3.5 text-sm text-brand-muted">
        {reminder.patient_phone}
      </td>

      {/* Actions */}
      <td className="whitespace-nowrap px-4 py-3.5 text-right">
        <div className="flex items-center justify-end gap-1">
          <ActionBtn
            title="Send WhatsApp"
            icon={MessageCircle}
            onClick={() => onSend(reminder, 'whatsapp')}
            colorClass="text-emerald-600 hover:bg-emerald-50"
          />
          <ActionBtn
            title="Call"
            icon={Phone}
            onClick={() => onSend(reminder, 'voice')}
            colorClass="text-blue-600 hover:bg-blue-50"
          />
          {reminder.reminder_status === 'Pending' || reminder.reminder_status === 'Sent' ? (
            <ActionBtn
              title="Confirm"
              icon={CheckCircle}
              onClick={() => onConfirm(reminder)}
              colorClass="text-brand-primary hover:bg-brand-primary/10"
            />
          ) : null}
          {reminder.reminder_status !== 'Cancelled' && (
            <ActionBtn
              title="Cancel"
              icon={XIcon}
              onClick={() => onCancel(reminder)}
              colorClass="text-red-500 hover:bg-red-50"
            />
          )}
        </div>
      </td>
    </tr>
  )
}

// ── Sortable table header ──────────────────────────────────────────
function SortHeader({ label, field, current, dir, onSort }) {
  const active = current === field
  return (
    <th
      onClick={() => onSort(field)}
      className="cursor-pointer select-none px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-brand-muted transition hover:text-brand-ink"
    >
      <span className="inline-flex items-center gap-1">
        {label}
        {active && (
          <span className="text-brand-primary">{dir === 'asc' ? '↑' : '↓'}</span>
        )}
      </span>
    </th>
  )
}

// ── Helpers ─────────────────────────────────────────────────────────
function ActionBtn({ title, icon: Icon, onClick, colorClass }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      onClick={onClick}
      className={`rounded-lg p-2 transition-colors ${colorClass}`}
    >
      <Icon size={15} />
    </button>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white p-4 text-center shadow-sm">
      <p className={`text-2xl font-bold ${color}`}>{value}</p>
      <p className="mt-1 text-xs uppercase tracking-wide text-brand-muted">{label}</p>
    </div>
  )
}

function initials(name = '') {
  return name.split(/\s+/).filter(Boolean).slice(0, 2)
    .map(w => w[0]?.toUpperCase() || '').join('') || '·'
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('en-ZA', {
    weekday: 'short', month: 'short', day: 'numeric',
  })
}

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString('en-ZA', {
    hour: '2-digit', minute: '2-digit',
  })
}
