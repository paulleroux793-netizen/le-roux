import React, { useEffect, useMemo, useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { CalendarRange, Clock3, Search, Sparkles } from 'lucide-react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import interactionPlugin from '@fullcalendar/interaction'
import { toast } from 'sonner'

const DEFAULT_CALENDAR_VIEW = 'timeGridWeek'

// ── Status themes ────────────────────────────────────────────────
// Phase 9.14 — every colour resolves to a brand token so the
// calendar re-themes when tokens change. Pattern per status:
//   dot / avatar → solid brand-<role>
//   card         → brand-<role>/10 fill + brand-<role>/20 border
//   chip         → brand-<role>/10 fill + brand-<role> text
const STATUS_THEMES = {
  scheduled: {
    label: 'Scheduled',
    dot: 'bg-brand-primary',
    card: 'border border-brand-primary/20 bg-brand-primary/10',
    avatar: 'bg-brand-primary',
    chip: 'border border-brand-primary/10 bg-white/85 text-brand-primary',
  },
  confirmed: {
    label: 'Confirmed',
    dot: 'bg-brand-success',
    card: 'border border-brand-success/20 bg-brand-success/10',
    avatar: 'bg-brand-success',
    chip: 'border border-brand-success/10 bg-white/85 text-brand-success',
  },
  completed: {
    label: 'Completed',
    dot: 'bg-brand-primary-dark',
    card: 'border border-brand-primary-dark/20 bg-brand-primary-dark/10',
    avatar: 'bg-brand-primary-dark',
    chip: 'border border-brand-primary-dark/10 bg-white/85 text-brand-primary-dark',
  },
  cancelled: {
    label: 'Cancelled',
    dot: 'bg-brand-danger',
    card: 'border border-brand-danger/20 bg-brand-danger/10',
    avatar: 'bg-brand-danger',
    chip: 'border border-brand-danger/10 bg-white/85 text-brand-danger',
  },
  no_show: {
    label: 'No show',
    dot: 'bg-brand-muted',
    card: 'border border-brand-muted/20 bg-brand-muted/10',
    avatar: 'bg-brand-muted',
    chip: 'border border-brand-muted/10 bg-white/85 text-brand-muted',
  },
  rescheduled: {
    label: 'Rescheduled',
    dot: 'bg-brand-warning',
    card: 'border border-brand-warning/20 bg-brand-warning/10',
    avatar: 'bg-brand-warning',
    chip: 'border border-brand-warning/10 bg-white/85 text-brand-warning',
  },
}

// Initials for the avatar circle — "Jerome Bellingham" → "JB".
const initials = (name = '') =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() || '')
    .join('') || '·'

const formatClock = (date) =>
  date.toLocaleTimeString('en-ZA', { hour: 'numeric', minute: '2-digit', hour12: true })

const formatRange = (start, end) => {
  return `${formatClock(start)} - ${formatClock(end)}`
}

const toMillis = (value) => {
  if (!value) return null
  const stamp = Date.parse(value)
  return Number.isNaN(stamp) ? null : stamp
}

export default function AppointmentCalendar({
  appointments = [],
  onEventClick,
  calendarMeta = {},
}) {
  const calendarRef = useRef(null)
  const loadedRangeRef = useRef({
    startMs: toMillis(calendarMeta.range_start),
    endMs: toMillis(calendarMeta.range_end),
    view: calendarMeta.view || DEFAULT_CALENDAR_VIEW,
  })
  const [search, setSearch] = useState('')

  useEffect(() => {
    loadedRangeRef.current = {
      startMs: toMillis(calendarMeta.range_start),
      endMs: toMillis(calendarMeta.range_end),
      view: calendarMeta.view || DEFAULT_CALENDAR_VIEW,
    }
  }, [calendarMeta.range_start, calendarMeta.range_end, calendarMeta.view])

  // Filter appointments client-side by search text. Looks at patient
  // name, phone, reason, and status so a single input covers every
  // useful case without a dedicated dropdown. Case-insensitive.
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return appointments
    return appointments.filter((apt) => {
      const haystack = [
        apt.patient_name,
        apt.patient_phone,
        apt.reason,
        apt.status,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
      return haystack.includes(q)
    })
  }, [appointments, search])

  const statusSummary = useMemo(() => (
    Object.entries(STATUS_THEMES).map(([status, theme]) => ({
      status,
      label: theme.label,
      count: appointments.filter((appointment) => appointment.status === status).length,
      dot: theme.dot,
    }))
  ), [appointments])

  const events = useMemo(
    () =>
      filtered.map((apt) => ({
        id: String(apt.id),
        title: apt.patient_name,
        start: apt.start_time,
        end: apt.end_time,
        backgroundColor: '#FFFFFF',
        borderColor: 'transparent',
        extendedProps: {
          reason: apt.reason,
          status: apt.status,
          phone: apt.patient_phone,
        },
      })),
    [filtered]
  )

  // Drag-to-reschedule — PATCHes the server; reverts the UI drop on error.
  const handleEventDrop = (info) => {
    const payload = {
      appointment: {
        start_time: info.event.start.toISOString(),
        end_time:   info.event.end ? info.event.end.toISOString() : null,
      },
    }
    router.patch(`/appointments/${info.event.id}`, payload, {
      preserveScroll: true,
      onSuccess: () => toast.success('Appointment rescheduled'),
      onError: () => {
        info.revert()
        toast.error('Could not reschedule — reverted')
      },
    })
  }

  const handleEventClick = (info) => {
    info.jsEvent.preventDefault()
    if (onEventClick) {
      onEventClick(info.event)
    } else {
      router.visit(`/appointments/${info.event.id}`)
    }
  }

  const handleDatesSet = (info) => {
    const anchorDate = info.view.currentStart
      ? info.view.currentStart.toISOString().slice(0, 10)
      : info.start.toISOString().slice(0, 10)
    const nextRange = {
      startMs: info.start.getTime(),
      endMs: info.end.getTime(),
      view: info.view.type,
    }

    if (
      loadedRangeRef.current.startMs === nextRange.startMs &&
      loadedRangeRef.current.endMs === nextRange.endMs &&
      loadedRangeRef.current.view === nextRange.view
    ) {
      return
    }

    loadedRangeRef.current = nextRange

    router.get('/appointments', {
      calendar_start: info.start.toISOString(),
      calendar_end: info.end.toISOString(),
      calendar_date: anchorDate,
      calendar_view: info.view.type,
    }, {
      only: ['calendar_appointments', 'calendar_meta'],
      preserveState: true,
      preserveScroll: true,
      replace: true,
    })
  }

  const renderEventContent = (arg) => {
    const { reason, status, phone } = arg.event.extendedProps
    const patient = arg.event.title
    const start = arg.event.start
    const end = arg.event.end || arg.event.start
    const theme = STATUS_THEMES[status] || STATUS_THEMES.scheduled

    return (
      <div className={`h-full w-full rounded-2xl p-3 text-[11px] leading-tight ${theme.card}`}>
        <div className="flex items-start justify-between gap-2">
          <div className="flex min-w-0 items-center gap-2">
            <span
              className={`flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full text-[10px] font-semibold text-white ${theme.avatar}`}
            >
              {initials(patient)}
            </span>
            <div className="min-w-0">
              <p className="truncate text-[13px] font-semibold tracking-tight text-brand-ink">
                {patient}
              </p>
              <p className={`mt-0.5 inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold ${theme.chip}`}>
                {theme.label}
              </p>
            </div>
          </div>
          <div className="rounded-full border border-white/70 bg-white/80 px-2 py-1 text-[10px] font-semibold text-brand-ink shadow-sm">
            {formatRange(start, end)}
          </div>
        </div>

        <div className="mt-3 space-y-1.5">
          <p className="truncate text-[12px] font-semibold text-brand-ink">
            {reason || 'General appointment'}
          </p>
          {phone && (
            <p className="truncate text-[11px] text-brand-muted">
              {phone}
            </p>
          )}
        </div>

        <div className="mt-3 flex items-center gap-1.5 text-[10px] font-medium text-brand-muted">
          <span aria-hidden="true" className={`h-2.5 w-2.5 rounded-full ${theme.dot}`} />
          <span className="sr-only">{theme.label}</span>
          <Clock3 size={11} />
          <span>{formatClock(start)}</span>
        </div>
      </div>
    )
  }

  return (
    <div className="appointment-calendar overflow-hidden rounded-3xl border border-brand-border bg-white shadow-sm">
      <div className="border-b border-brand-border bg-gradient-to-br from-brand-surface via-white to-white px-6 py-6">
        <div className="flex flex-col gap-5 xl:flex-row xl:items-end xl:justify-between">
          <div className="space-y-3">
            <div className="inline-flex items-center gap-2 rounded-full border border-brand-border bg-white/90 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
              <Sparkles size={12} />
              Booking desk
            </div>
            <div>
              <h2 className="text-[1.9rem] font-semibold tracking-tight text-brand-ink">
                Clinic booking calendar
              </h2>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-brand-muted">
                Review live bookings, drag appointments to new times, and keep reception aligned with the diary at a glance.
              </p>
            </div>
          </div>

          <div className="flex flex-col gap-3 xl:min-w-[360px] xl:items-end">
            <div className="relative w-full max-w-md">
              <Search
                size={16}
                className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-brand-muted"
              />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search patient, phone, reason…"
                className="w-full rounded-2xl border border-brand-border bg-white px-11 py-3 text-sm text-brand-ink placeholder:text-brand-muted focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-primary/20"
              />
              {search && (
                <button
                  type="button"
                  onClick={() => setSearch('')}
                  aria-label="Clear search"
                  className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full px-2 py-1 text-xs font-medium text-brand-muted transition hover:bg-brand-surface hover:text-brand-ink"
                >
                  Clear
                </button>
              )}
            </div>

            <div className="flex flex-wrap gap-2">
              <MetaChip icon={CalendarRange}>
                {filtered.length} visible bookings
              </MetaChip>
              <MetaChip>
                {appointments.length} in loaded window
              </MetaChip>
            </div>
          </div>
        </div>
      </div>

      <div className="border-b border-brand-border bg-white px-6 py-4">
        <div className="flex flex-wrap gap-2.5">
          {statusSummary.map((item) => (
            <div
              key={item.status}
              className="inline-flex items-center gap-2 rounded-full border border-brand-border bg-brand-surface px-3 py-1.5 text-xs font-medium text-brand-muted"
            >
              <span className={`h-2.5 w-2.5 rounded-full ${item.dot}`} />
              <span>{item.label}</span>
              <span className="rounded-full bg-white px-1.5 py-0.5 text-[10px] font-semibold text-brand-ink">
                {item.count}
              </span>
            </div>
          ))}
        </div>
      </div>

      <div className="px-4 pb-5 pt-5 md:px-6">
        {search && filtered.length === 0 && (
          <div className="mb-4 rounded-2xl border border-dashed border-brand-border bg-brand-surface px-4 py-3 text-sm text-brand-muted">
            No appointments in this calendar window match your current search.
          </div>
        )}

      <FullCalendar
        ref={calendarRef}
        plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
        initialView={calendarMeta.view || DEFAULT_CALENDAR_VIEW}
        initialDate={calendarMeta.initial_date}
        headerToolbar={{
          left: 'title',
          center: '',
          right: 'today prev,next timeGridWeek,timeGridDay,dayGridMonth',
        }}
        events={events}
        editable
        eventDrop={handleEventDrop}
        eventClick={handleEventClick}
        datesSet={handleDatesSet}
        eventContent={renderEventContent}
        slotMinTime="08:00:00"
        slotMaxTime="18:00:00"
        allDaySlot={false}
        nowIndicator
        contentHeight={640}
        stickyHeaderDates
        slotDuration="00:30:00"
        weekends
        firstDay={1}
        buttonText={{ timeGridWeek: 'Week', timeGridDay: 'Day', dayGridMonth: 'Month' }}
        eventTimeFormat={{ hour: 'numeric', minute: '2-digit', meridiem: 'short' }}
        slotLabelFormat={{ hour: 'numeric', minute: '2-digit', meridiem: 'short' }}
        dayHeaderFormat={{ weekday: 'short', day: 'numeric' }}
      />
      </div>
    </div>
  )
}

function MetaChip({ children, icon: Icon }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full border border-brand-border bg-white px-3 py-1.5 text-xs font-medium text-brand-muted shadow-sm">
      {Icon ? <Icon size={13} className="text-brand-primary" /> : null}
      {children}
    </span>
  )
}
