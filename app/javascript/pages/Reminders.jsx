import React, { useEffect, useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  BellRing, Phone, MessageCircle, CheckCircle, X as XIcon,
  Clock, Search, ChevronLeft, ChevronRight, Sparkles,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import CancelAppointmentModal from '../components/CancelAppointmentModal'
import { useLanguage } from '../lib/LanguageContext'

// ── Pre-Appointment Reminders page ──────────────────────────────────

const STATUS_CHIP_KEYS = {
  Pending:     'chip_pending',
  Sent:        'chip_sent',
  Confirmed:   'chip_confirmed',
  Cancelled:   'chip_cancelled',
  'No Answer': 'chip_no_answer',
  Completed:   'chip_completed',
  'No Show':   'chip_no_show',
  Rescheduled: 'chip_rescheduled',
}

const STATUS_CHIP_STYLES = {
  Pending:     { bg: 'bg-amber-50',    text: 'text-amber-700',   border: 'border-amber-200' },
  Sent:        { bg: 'bg-blue-50',     text: 'text-blue-700',    border: 'border-blue-200' },
  Confirmed:   { bg: 'bg-emerald-50',  text: 'text-emerald-700', border: 'border-emerald-200' },
  Cancelled:   { bg: 'bg-red-50',      text: 'text-red-700',     border: 'border-red-200' },
  'No Answer': { bg: 'bg-orange-50',   text: 'text-orange-700',  border: 'border-orange-200' },
  Completed:   { bg: 'bg-brand-surface', text: 'text-brand-muted', border: 'border-brand-border' },
  'No Show':   { bg: 'bg-gray-50',     text: 'text-gray-600',    border: 'border-gray-200' },
  Rescheduled: { bg: 'bg-purple-50',   text: 'text-purple-700',  border: 'border-purple-200' },
}

const WINDOW_KEYS = ['today', 'tomorrow', 'week']

const PAGE_SIZE = 10

export default function Reminders({ reminders = [], stats }) {
  const { t, language } = useLanguage()
  const dateFmt = language === 'af' ? 'af-ZA' : 'en-ZA'

  const [windowKey, setWindowKey] = useState('week')
  const [cancelTarget, setCancelTarget] = useState(null)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [sortField, setSortField] = useState('start_time')
  const [sortDir, setSortDir] = useState('asc')

  const windowLabels = {
    today: t('rem_today'),
    tomorrow: t('rem_tomorrow'),
    week: t('rem_this_week'),
  }

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
        `${channel === 'whatsapp' ? 'WhatsApp' : t('rem_call')} ${t('rem_sent_success')} ${reminder.patient_name}`
      ),
      onError: () => toast.error(t('rem_send_error')),
    })
  }

  const confirmAppointment = (reminder) => {
    router.patch(`/appointments/${reminder.id}/confirm`, {}, {
      preserveScroll: true,
      onSuccess: () => toast.success(`${reminder.patient_name} ${t('rem_confirmed_success')}`),
      onError:   () => toast.error(t('rem_confirm_error')),
    })
  }

  return (
    <DashboardLayout>
      {/* Header */}
      <div className="mb-8">
        <div className="inline-flex items-center gap-2 rounded-full border border-brand-border bg-white/90 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
          <Sparkles size={12} />
          {t('rem_badge')}
        </div>
        <h1 className="mt-3 flex items-center gap-2 text-[1.9rem] font-semibold tracking-tight text-brand-ink">
          <BellRing size={22} className="text-brand-primary" />
          {t('rem_title')}
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-brand-muted">
          {t('rem_subtitle')}
        </p>
      </div>

      {/* Stat cards */}
      <div className="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard label={t('rem_total_upcoming')} value={stats?.total ?? 0} color="text-brand-primary" />
        <StatCard label={t('rem_pending')}        value={stats?.pending ?? 0} color="text-amber-600" />
        <StatCard label={t('rem_confirmed')}      value={stats?.confirmed ?? 0} color="text-emerald-600" />
        <StatCard label={t('rem_today')}          value={stats?.today ?? 0} color="text-brand-ink" />
      </div>

      {/* Controls row */}
      <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        {/* Window tabs */}
        <div className="inline-flex items-center rounded-xl border border-brand-border bg-white p-1">
          {WINDOW_KEYS.map((key) => (
            <button
              key={key}
              onClick={() => { setWindowKey(key); setPage(1) }}
              className={`rounded-lg px-4 py-2 text-xs font-semibold transition-colors ${
                windowKey === key
                  ? 'bg-brand-primary text-white shadow-sm'
                  : 'text-brand-muted hover:bg-brand-surface hover:text-brand-ink'
              }`}
            >
              {windowLabels[key]}
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
            placeholder={t('rem_search')}
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
            <p className="text-sm font-medium text-brand-ink">{t('rem_all_caught_up')}</p>
            <p className="mt-1 text-xs text-brand-muted">{t('rem_no_match')}</p>
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-brand-border bg-brand-surface/50">
                    <SortHeader label={t('rem_th_patient')} field="patient_name" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <SortHeader label={t('rem_th_appointment')} field="start_time" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <SortHeader label={t('rem_th_reason')} field="reason" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <SortHeader label={t('rem_th_status')} field="reminder_status" current={sortField} dir={sortDir} onSort={toggleSort} />
                    <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('rem_th_phone')}</th>
                    <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('rem_th_actions')}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-brand-border/50">
                  {paginated.map((r) => (
                    <ReminderRow
                      key={r.id}
                      reminder={r}
                      t={t}
                      dateFmt={dateFmt}
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
                {t('rem_showing')} <span className="font-semibold text-brand-ink">{(page - 1) * PAGE_SIZE + 1}</span> {t('rem_to')}{' '}
                <span className="font-semibold text-brand-ink">{Math.min(page * PAGE_SIZE, sorted.length)}</span> {t('rem_of')}{' '}
                <span className="font-semibold text-brand-ink">{sorted.length}</span> {t('rem_results')}
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
function ReminderRow({ reminder, t, dateFmt, onSend, onConfirm, onCancel }) {
  const chipStyle = STATUS_CHIP_STYLES[reminder.reminder_status] || STATUS_CHIP_STYLES.Pending
  const chipKey = STATUS_CHIP_KEYS[reminder.reminder_status] || 'chip_pending'

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
                  ? `${Math.round(reminder.hours_until * 60)}${t('rem_m_away')}`
                  : `${reminder.hours_until.toFixed(1)}${t('rem_h_away')}`}
              </p>
            )}
          </div>
        </div>
      </td>

      {/* Appointment time */}
      <td className="whitespace-nowrap px-4 py-3.5">
        <p className="text-sm text-brand-ink">{formatDate(reminder.start_time, dateFmt)}</p>
        <p className="text-xs text-brand-muted">{formatTime(reminder.start_time, dateFmt)} – {formatTime(reminder.end_time, dateFmt)}</p>
      </td>

      {/* Reason */}
      <td className="px-4 py-3.5">
        <p className="max-w-[180px] truncate text-sm text-brand-ink">
          {reminder.reason || t('rem_general_appointment')}
        </p>
      </td>

      {/* Status chip */}
      <td className="px-4 py-3.5">
        <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${chipStyle.bg} ${chipStyle.text} ${chipStyle.border}`}>
          {t(chipKey)}
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
            title={t('rem_send_whatsapp')}
            icon={MessageCircle}
            onClick={() => onSend(reminder, 'whatsapp')}
            colorClass="text-emerald-600 hover:bg-emerald-50"
          />
          <ActionBtn
            title={t('rem_call')}
            icon={Phone}
            onClick={() => onSend(reminder, 'voice')}
            colorClass="text-blue-600 hover:bg-blue-50"
          />
          {reminder.reminder_status === 'Pending' || reminder.reminder_status === 'Sent' ? (
            <ActionBtn
              title={t('rem_confirm')}
              icon={CheckCircle}
              onClick={() => onConfirm(reminder)}
              colorClass="text-brand-primary hover:bg-brand-primary/10"
            />
          ) : null}
          {reminder.reminder_status !== 'Cancelled' && (
            <ActionBtn
              title={t('rem_cancel')}
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

function formatDate(iso, locale = 'en-ZA') {
  return new Date(iso).toLocaleDateString(locale, {
    weekday: 'short', month: 'short', day: 'numeric',
  })
}

function formatTime(iso, locale = 'en-ZA') {
  return new Date(iso).toLocaleTimeString(locale, {
    hour: '2-digit', minute: '2-digit',
  })
}
