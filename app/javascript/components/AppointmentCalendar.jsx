import React, { useEffect, useMemo, useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { Bell, CalendarRange, Plus, Scissors, Search, X as XIcon } from 'lucide-react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import interactionPlugin from '@fullcalendar/interaction'
import { toast } from 'sonner'
import ReminderModal from './ReminderModal'

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
  notes = [],
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

  // ── Cut / paste move ────────────────────────────────────────────────
  // `clipboard` holds the appointment "cut" for moving (id + duration +
  // name); while set, a banner shows and clicking any time slot drops it
  // there (preserving its length). `lastSelectedRef` remembers the most
  // recently clicked event so Ctrl+X knows what to cut even after the
  // detail modal has opened/closed. `lastSlotRef` remembers the last
  // empty slot clicked so Ctrl+V has a target.
  const [clipboard, setClipboard] = useState(null)
  const lastSelectedRef = useRef(null)
  const lastSlotRef = useRef(null)

  // Diary reminder modal: { mode: 'create'|'edit', note, prefillStart }.
  const [reminderModal, setReminderModal] = useState(null)

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

  // Diary reminders rendered as distinct amber events (id prefixed
  // "note-" so click/drag handlers can tell them apart from bookings).
  const noteEvents = useMemo(
    () =>
      notes.map((n) => ({
        id: `note-${n.id}`,
        title: n.note,
        start: n.starts_at,
        end: n.ends_at,
        backgroundColor: n.done ? '#F1F5F9' : '#FEF3C7',
        borderColor: n.done ? '#CBD5E1' : '#F59E0B',
        textColor: n.done ? '#94A3B8' : '#92400E',
        extendedProps: { type: 'note', done: n.done, raw: n },
      })),
    [notes]
  )

  const allEvents = useMemo(() => [...events, ...noteEvents], [events, noteEvents])

  // Drag-to-reschedule and drag-to-resize both end here: PATCH the server,
  // revert the UI on error. `revert` is the FullCalendar callback that
  // snaps the event back to where it was if the save fails (e.g. the slot
  // is already booked — the DB exclusion constraint rejects it).
  // A note event's id is "note-<id>"; appointments are plain numeric ids.
  const isNoteId = (id) => String(id).startsWith('note-')
  const noteIdOf = (id) => String(id).replace('note-', '')

  const persistMove = (id, start, end, revert) => {
    const ok = () => toast.success(isNoteId(id) ? 'Reminder moved' : 'Appointment moved')
    const fail = () => { revert?.(); toast.error('Could not move — slot may be taken') }
    if (isNoteId(id)) {
      router.patch(`/calendar_notes/${noteIdOf(id)}`, {
        calendar_note: { starts_at: start.toISOString(), ends_at: end ? end.toISOString() : null },
      }, { preserveScroll: true, onSuccess: ok, onError: fail })
    } else {
      router.patch(`/appointments/${id}`, {
        appointment: { start_time: start.toISOString(), end_time: end ? end.toISOString() : null },
      }, { preserveScroll: true, onSuccess: ok, onError: fail })
    }
  }

  const handleEventDrop   = (info) => persistMove(info.event.id, info.event.start, info.event.end, info.revert)
  const handleEventResize = (info) => persistMove(info.event.id, info.event.start, info.event.end, info.revert)

  const handleEventClick = (info) => {
    info.jsEvent.preventDefault()
    // Diary reminder → open the reminder editor instead of the patient modal.
    if (info.event.extendedProps?.type === 'note') {
      setReminderModal({ mode: 'edit', note: info.event.extendedProps.raw })
      return
    }
    // Remember this event so Ctrl+X can cut it later (the detail modal
    // opens on top, but the keyboard shortcut still needs the target).
    lastSelectedRef.current = {
      id: info.event.id,
      title: info.event.title,
      durationMs: info.event.end && info.event.start
        ? info.event.end.getTime() - info.event.start.getTime()
        : 30 * 60 * 1000,
    }
    if (onEventClick) {
      onEventClick(info.event)
    } else {
      router.visit(`/appointments/${info.event.id}`)
    }
  }

  // Drop a cut appointment onto a new start time, keeping its length.
  const placeClipboardAt = (startDate) => {
    if (!clipboard) return
    const end = new Date(startDate.getTime() + clipboard.durationMs)
    persistMove(clipboard.id, startDate, end, null)
    setClipboard(null)
  }

  // Clicking an empty slot: if something is "cut", drop it here; otherwise
  // open the diary-reminder creator pre-filled with that time. (Remember
  // the slot too, so Ctrl+V has a paste target.)
  const handleDateClick = (info) => {
    lastSlotRef.current = info.date
    if (clipboard) {
      placeClipboardAt(info.date)
    } else {
      setReminderModal({ mode: 'create', prefillStart: info.date })
    }
  }

  // Cut (Ctrl/Cmd+X) the last-clicked appointment; paste (Ctrl/Cmd+V) at
  // the last-clicked slot; Esc cancels a pending move.
  useEffect(() => {
    const onKey = (e) => {
      const mod = e.ctrlKey || e.metaKey
      if (mod && (e.key === 'x' || e.key === 'X')) {
        if (lastSelectedRef.current) {
          e.preventDefault()
          setClipboard(lastSelectedRef.current)
          toast(`Cut ${lastSelectedRef.current.title} — click a slot to drop it, or Ctrl+V`)
        }
      } else if (mod && (e.key === 'v' || e.key === 'V')) {
        if (clipboard && lastSlotRef.current) {
          e.preventDefault()
          placeClipboardAt(lastSlotRef.current)
        }
      } else if (e.key === 'Escape' && clipboard) {
        setClipboard(null)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [clipboard])

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

  // Cut an event for moving without going through the detail modal —
  // the little scissors button on each card. stopPropagation so the
  // click doesn't also open the modal.
  const cutEvent = (e, ev) => {
    e.stopPropagation()
    const durationMs = ev.end && ev.start ? ev.end.getTime() - ev.start.getTime() : 30 * 60 * 1000
    setClipboard({ id: ev.id, title: ev.title, durationMs })
    toast(`Cut ${ev.title} — click a slot to drop it here. Esc to cancel`)
  }

  // Compact event card — patient name + reason, plus a hover scissors
  // button to cut-and-move. Click the body opens the detail pop-over.
  const renderEventContent = (arg) => {
    const ext = arg.event.extendedProps

    // Diary reminder card: bell + note text, struck through when done.
    if (ext.type === 'note') {
      return (
        <div className="flex h-full w-full cursor-pointer items-start gap-1 overflow-hidden px-1.5 py-0.5 leading-tight">
          <Bell size={11} className="mt-0.5 flex-shrink-0 opacity-80" />
          <p className={`truncate text-[11px] font-medium ${ext.done ? 'line-through opacity-60' : ''}`}>
            {arg.event.title}
          </p>
        </div>
      )
    }

    const { reason } = ext
    const patient = arg.event.title

    return (
      <div className="group/event relative flex h-full w-full cursor-pointer flex-col justify-center overflow-hidden px-1.5 py-0.5 leading-tight">
        <p className="truncate pr-5 text-[12px] font-semibold">{patient}</p>
        {reason && (
          <p className="truncate text-[10px] opacity-75">{reason}</p>
        )}
        <button
          type="button"
          title="Cut / move this appointment"
          onClick={(e) => cutEvent(e, arg.event)}
          className="absolute right-0.5 top-0.5 rounded p-0.5 opacity-0 transition-opacity hover:bg-black/10 group-hover/event:opacity-100"
        >
          <Scissors size={12} />
        </button>
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

        {/* Cut/paste banner — visible while an appointment is "cut". */}
        {clipboard && (
          <div className="mb-2 flex items-center justify-between gap-3 rounded-lg border border-brand-primary/40 bg-brand-primary/10 px-4 py-2 text-sm text-brand-ink">
            <span className="flex items-center gap-2">
              <Scissors size={14} className="text-brand-primary" />
              Moving <strong>{clipboard.title}</strong> — click any time slot to drop it (or press Ctrl+V). Esc to cancel.
            </span>
            <button
              type="button"
              onClick={() => setClipboard(null)}
              className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-brand-muted hover:bg-white hover:text-brand-ink"
            >
              <XIcon size={13} /> Cancel
            </button>
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
        events={allEvents}
        editable
        eventResizableFromStart
        selectable
        selectMirror
        eventDrop={handleEventDrop}
        eventResize={handleEventResize}
        eventClick={handleEventClick}
        dateClick={handleDateClick}
        datesSet={handleDatesSet}
        eventContent={renderEventContent}
        eventClassNames={(arg) => (clipboard && String(clipboard.id) === arg.event.id ? ['fc-cut-event'] : [])}
        slotMinTime="06:00:00"
        slotMaxTime="20:00:00"
        scrollTime="08:00:00"
        allDaySlot={false}
        nowIndicator
        height="100%"
        stickyHeaderDates
        slotDuration="00:15:00"
        slotLabelInterval="01:00:00"
        snapDuration="00:15:00"
        businessHours={{ daysOfWeek: [1, 2, 3, 4, 5], startTime: '08:00', endTime: '17:00' }}
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
        /* The appointment currently "cut" for moving — dimmed + dashed. */
        .appointment-calendar .fc-cut-event { opacity: 0.45; outline: 2px dashed #0f766e; outline-offset: -2px; }
      `}</style>

      {/* Diary reminder create/edit modal (self-contained — no patient). */}
      <ReminderModal
        open={Boolean(reminderModal)}
        onClose={() => setReminderModal(null)}
        note={reminderModal?.note}
        prefillStart={reminderModal?.prefillStart}
      />
    </div>
  )
}

