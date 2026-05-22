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
// Patient-journey colour scheme (Paul's spec 2026-05-22):
//   scheduled        → white (normal)
//   confirmed        → green
//   arrived          → light yellow
//   in_consultation  → light blue
//   completed        → darker blue (white text)
// The other statuses keep sensible distinct tints.
const STATUS_COLORS = {
  scheduled:            { bg: '#FFFFFF', text: '#374151', border: '#CBD5E1', label: 'Scheduled',        dot: 'bg-gray-300' },
  confirmed:            { bg: '#BBF7D0', text: '#065F46', border: '#4ADE80', label: 'Confirmed',        dot: 'bg-emerald-500' },
  arrived:              { bg: '#FEF08A', text: '#854D0E', border: '#FACC15', label: 'Arrived',          dot: 'bg-yellow-400' },
  in_consultation:      { bg: '#BFDBFE', text: '#1E3A8A', border: '#60A5FA', label: 'In Consultation',  dot: 'bg-blue-400' },
  completed:            { bg: '#1D4ED8', text: '#FFFFFF', border: '#1E3A8A', label: 'Completed',        dot: 'bg-blue-700' },
  cancelled:            { bg: '#FEE2E2', text: '#991B1B', border: '#FCA5A5', label: 'Cancelled',        dot: 'bg-brand-danger' },
  no_show:              { bg: '#F3F4F6', text: '#4B5563', border: '#E5E7EB', label: 'No show',          dot: 'bg-brand-muted' },
  rescheduled:          { bg: '#FEF3C7', text: '#92400E', border: '#FDE68A', label: 'Rescheduled',      dot: 'bg-brand-warning' },
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
  // Height of the scrollable calendar body for the inline dashboard view,
  // which leaves room for the page header + stat cards (~210px).
  heightClass = 'h-[calc(100vh-210px)]',
  // Fullscreen /calendar page: make the whole component fill its parent
  // (h-full flex column) so FullCalendar's own toolbar stays pinned at
  // the top — week nav + view switch are always visible — while only the
  // time-grid scrolls internally on short screens. Compact slot CSS keeps
  // the full 08:00–17:00 day on one screen on a normal monitor.
  fillHeight = false,
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
            isNew: apt.is_new_patient,
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

    // Compact card per Paul's spec: name + reason for visit. Full details
    // (contact, new/existing, etc.) live in the click pop-over.
    return (
      <div className="flex h-full w-full cursor-pointer flex-col justify-center overflow-hidden px-1.5 py-0.5 leading-tight">
        <p className="truncate text-[12px] font-semibold">{patient}</p>
        {reason && (
          <p className="truncate text-[10px] opacity-75">{reason}</p>
        )}
      </div>
    )
  }

  return (
    <div className={`appointment-calendar overflow-hidden rounded-xl border border-brand-border bg-white shadow-sm ${fillHeight ? 'flex h-full flex-col' : ''}`}>
      {/* Compact toolbar: search + legend */}
      <div className="flex flex-shrink-0 flex-wrap items-center justify-between gap-3 border-b border-brand-border bg-brand-surface px-4 py-3">
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

      <div className={`flex flex-col px-3 pb-3 pt-2 md:px-4 ${fillHeight ? 'min-h-0 flex-1' : heightClass}`}>
        {search && filtered.length === 0 && (
          <div className="mb-3 rounded-lg border border-dashed border-brand-border bg-brand-surface px-4 py-2.5 text-sm text-brand-muted">
            No appointments match your search.
          </div>
        )}

      {/* min-h-0 flex-1 gives FullCalendar a bounded pixel height so its
          height="100%" + expandRows can compress the whole 08:00–17:00
          day to fit. Without this the flex parent reports no height and
          FC falls back to an oversized aspect-ratio layout that scrolls. */}
      <div className="min-h-0 flex-1">
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
        slotMaxTime="17:00:00"
        scrollTime="08:00:00"
        allDaySlot={false}
        nowIndicator
        height="100%"
        stickyHeaderDates
        slotDuration="00:15:00"
        slotLabelInterval="01:00:00"
        snapDuration="00:15:00"
        weekends={false}
        firstDay={1}
        buttonText={{ timeGridWeek: 'Week', timeGridDay: 'Day', dayGridMonth: 'Month' }}
        eventTimeFormat={{ hour: 'numeric', minute: '2-digit', meridiem: 'short' }}
        slotLabelFormat={{ hour: 'numeric', minute: '2-digit', meridiem: 'short' }}
        dayHeaderFormat={{ weekday: 'short', day: 'numeric' }}
      />
      </div>
      </div>

      {/* Comfortable, readable slot rows. Without expandRows the grid keeps
          these fixed heights and scrolls vertically when the day is taller
          than the viewport — a normal, familiar week-calendar feel. The
          FullCalendar toolbar stays pinned above the scroller. */}
      <style>{`
        .appointment-calendar .fc-timegrid-slot { height: 1.5em !important; }
        .appointment-calendar .fc-timegrid-slot-label { font-size: 11px; }
        .appointment-calendar .fc-col-header-cell-cushion { font-size: 12px; }
      `}</style>
    </div>
  )
}

