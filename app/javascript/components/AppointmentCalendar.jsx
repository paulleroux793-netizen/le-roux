import React, { useMemo, useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { CalendarRange, Search } from 'lucide-react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import interactionPlugin from '@fullcalendar/interaction'
import { toast } from 'sonner'

const DEFAULT_CALENDAR_VIEW = 'timeGridWeek'

// ── Status colours ────────────────────────────────────────────────
// Minimal: a tinted background + matching text for the compact event
// card. All details live in the popup (AppointmentDetailModal).
const STATUS_COLORS = {
  scheduled:   { bg: '#E0F2FE', text: '#0369A1', border: '#BAE6FD', label: 'Scheduled',   dot: 'bg-brand-primary' },
  confirmed:   { bg: '#D1FAE5', text: '#065F46', border: '#A7F3D0', label: 'Confirmed',   dot: 'bg-brand-success' },
  completed:   { bg: '#E0E7FF', text: '#3730A3', border: '#C7D2FE', label: 'Completed',   dot: 'bg-brand-primary-dark' },
  cancelled:   { bg: '#FEE2E2', text: '#991B1B', border: '#FECACA', label: 'Cancelled',   dot: 'bg-brand-danger' },
  no_show:     { bg: '#F3F4F6', text: '#4B5563', border: '#E5E7EB', label: 'No show',     dot: 'bg-brand-muted' },
  rescheduled:          { bg: '#FEF3C7', text: '#92400E', border: '#FDE68A', label: 'Rescheduled',          dot: 'bg-brand-warning' },
  pending_confirmation: { bg: '#FFF7ED', text: '#9A3412', border: '#FED7AA', label: 'Pending Confirmation', dot: 'bg-orange-400' },
}

const formatClock = (date) =>
  date.toLocaleTimeString('en-ZA', { hour: 'numeric', minute: '2-digit', hour12: true })

// Stable, browser-tz-independent identifier for a FullCalendar visible
// range. We intentionally avoid getTime()/Date.parse comparisons here:
// FC's `startStr`/`endStr` are deterministic ISO strings derived from
// the view's anchor date, so two equivalent ranges always stringify
// identically regardless of browser timezone, DST boundaries, or
// sub-second normalization differences between Inertia round-trips.
const rangeKey = (view, startStr, endStr) => `${view}|${startStr}|${endStr}`

export default function AppointmentCalendar({
  appointments = [],
  onEventClick,
  calendarMeta = {},
}) {
  const calendarRef = useRef(null)
  // `loadedRangeKeyRef` tracks the last visible range we've already
  // fetched data for. `hasMountedRef` guards the very first datesSet
  // fire (which always corresponds to the data the server JUST sent
  // us in props — re-fetching it is wasted work and historically
  // raced with FullCalendar's internal event-source effect, causing
  // a runaway router.get loop that left the calendar perpetually
  // empty). See git history for the previous ms-based comparison
  // that drifted across browser timezones.
  const loadedRangeKeyRef = useRef(null)
  const hasMountedRef = useRef(false)
  const [search, setSearch] = useState('')
  // Freeze initialDate at mount. FullCalendar treats this as mount-only
  // but silently navigates when the prop reference changes — which
  // happens on every Inertia partial reload that updates calendarMeta.
  const [stableInitialDate] = useState(() => calendarMeta.initial_date)

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
    Object.entries(STATUS_COLORS).map(([status, theme]) => ({
      status,
      label: theme.label,
      count: appointments.filter((appointment) => appointment.status === status).length,
      dot: theme.dot,
    }))
  ), [appointments])

  const events = useMemo(
    () =>
      filtered.map((apt) => {
        const colors = STATUS_COLORS[apt.status] || STATUS_COLORS.scheduled
        return {
          id: String(apt.id),
          title: apt.patient_name,
          start: apt.start_time,
          end: apt.end_time,
          backgroundColor: colors.bg,
          borderColor: colors.border,
          textColor: colors.text,
          extendedProps: {
            reason: apt.reason,
            status: apt.status,
            phone: apt.patient_phone,
          },
        }
      }),
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
    const nextKey = rangeKey(info.view.type, info.startStr, info.endStr)

    // First fire is the initial mount — the server already sent us
    // calendar_appointments for this exact range, so re-fetching is
    // redundant AND was the trigger for the runaway refresh loop.
    // Just record the key and bail.
    if (!hasMountedRef.current) {
      hasMountedRef.current = true
      loadedRangeKeyRef.current = nextKey
      return
    }

    // Same range as last time (e.g. FC re-fired datesSet because its
    // events prop changed, not because the user navigated). Bail.
    if (loadedRangeKeyRef.current === nextKey) {
      return
    }

    loadedRangeKeyRef.current = nextKey

    const anchorDate = info.view.currentStart
      ? info.view.currentStart.toISOString().slice(0, 10)
      : info.start.toISOString().slice(0, 10)

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

  // Compact event card — shows only essential info that fits in a
  // 30-minute slot. Patient name + time + reason. Click to see full
  // details in AppointmentDetailModal.
  const renderEventContent = (arg) => {
    const { reason } = arg.event.extendedProps
    const patient = arg.event.title
    const start = arg.event.start
    const end = arg.event.end || arg.event.start

    return (
      <div className="flex h-full w-full cursor-pointer flex-col justify-center overflow-hidden px-2 py-1">
        <p className="truncate text-[12px] font-semibold leading-tight">
          {patient}
        </p>
        <p className="truncate text-[11px] font-medium leading-tight opacity-80">
          {formatClock(start)} – {formatClock(end)}
        </p>
        {reason && (
          <p className="truncate text-[10px] leading-tight opacity-60">
            {reason}
          </p>
        )}
      </div>
    )
  }

  return (
    <div className="appointment-calendar overflow-hidden rounded-xl border border-brand-border bg-white shadow-sm">
      {/* Compact toolbar: search + legend */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-brand-border bg-brand-surface px-4 py-3">
        {/* Search */}
        <div className="relative w-full max-w-xs">
          <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search patient, phone, reason…"
            className="w-full rounded-lg border border-brand-border bg-white py-1.5 pl-9 pr-8 text-sm text-brand-ink placeholder:text-brand-muted focus:border-brand-primary focus:outline-none focus:ring-2 focus:ring-brand-primary/20"
          />
          {search && (
            <button
              type="button"
              onClick={() => setSearch('')}
              aria-label="Clear search"
              className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-brand-muted hover:text-brand-ink"
            >
              ×
            </button>
          )}
        </div>

        {/* Legend pills */}
        <div className="flex flex-wrap gap-1.5">
          {statusSummary.filter(i => i.count > 0).map((item) => (
            <span
              key={item.status}
              className="inline-flex items-center gap-1.5 rounded-full border border-brand-border bg-white px-2.5 py-1 text-[11px] font-medium text-brand-muted"
            >
              <span className={`h-2 w-2 rounded-full ${item.dot}`} />
              {item.label}
              <span className="font-semibold text-brand-ink">{item.count}</span>
            </span>
          ))}
          <span className="inline-flex items-center gap-1.5 rounded-full border border-brand-border bg-white px-2.5 py-1 text-[11px] font-medium text-brand-muted">
            <CalendarRange size={11} className="text-brand-primary" />
            {filtered.length} shown
          </span>
        </div>
      </div>

      <div className="px-4 pb-4 pt-3 md:px-5">
        {search && filtered.length === 0 && (
          <div className="mb-3 rounded-lg border border-dashed border-brand-border bg-brand-surface px-4 py-2.5 text-sm text-brand-muted">
            No appointments match your search.
          </div>
        )}

      <FullCalendar
        ref={calendarRef}
        plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
        initialView={calendarMeta.view || DEFAULT_CALENDAR_VIEW}
        initialDate={stableInitialDate}
        headerToolbar={{
          left: 'title',
          center: '',
          right: 'today prev,next timeGridWeek,timeGridDay,dayGridMonth',
        }}
        events={events}
        editable
        selectable
        selectMirror
        eventDrop={handleEventDrop}
        eventClick={handleEventClick}
        datesSet={handleDatesSet}
        eventContent={renderEventContent}
        slotMinTime="08:00:00"
        slotMaxTime="17:30:00"
        allDaySlot={false}
        nowIndicator
        expandRows={false}
        height={600}
        stickyHeaderDates
        slotDuration="00:30:00"
        weekends={false}
        firstDay={1}
        buttonText={{ timeGridWeek: 'Week', timeGridDay: 'Day', dayGridMonth: 'Month' }}
        eventTimeFormat={{ hour: 'numeric', minute: '2-digit', meridiem: 'short' }}
        slotLabelFormat={{ hour: 'numeric', minute: '2-digit', meridiem: 'short' }}
        dayHeaderFormat={{ weekday: 'short', day: 'numeric' }}
        dayMaxEvents={3}
        moreLinkClick="popover"
      />
      </div>
    </div>
  )
}

