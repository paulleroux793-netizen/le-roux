import React, { useMemo, useRef } from 'react'
import { router } from '@inertiajs/react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import interactionPlugin from '@fullcalendar/interaction'
import { toast } from 'sonner'

// ── Status → pastel card theme ──────────────────────────────────────
// Each event block is rendered as a white-ish card with a subtle tint,
// a coloured left accent bar, and dark text — mirroring the premium
// dashboard reference screenshots. Keeping a single source of truth
// here means the 6 statuses stay consistent across the whole calendar.
const STATUS_THEMES = {
  scheduled:   { tint: '#FFFBEB', accent: '#D97706', chip: 'bg-amber-100 text-amber-700' },
  confirmed:   { tint: '#ECFDF5', accent: '#059669', chip: 'bg-emerald-100 text-emerald-700' },
  completed:   { tint: '#EFF6FF', accent: '#2563EB', chip: 'bg-blue-100 text-blue-700' },
  cancelled:   { tint: '#FEF2F2', accent: '#DC2626', chip: 'bg-red-100 text-red-700' },
  no_show:     { tint: '#F9FAFB', accent: '#6B7280', chip: 'bg-gray-100 text-gray-600' },
  rescheduled: { tint: '#F5F3FF', accent: '#7C3AED', chip: 'bg-violet-100 text-violet-700' },
}

// Initials for the avatar circle — "Jerome Bellingham" → "JB".
const initials = (name = '') =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() || '')
    .join('') || '·'

// Time range like "09.00 AM - 11.00 AM" (matches screenshot ref #3).
const formatRange = (start, end) => {
  const fmt = (d) =>
    d.toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit', hour12: true })
      .replace(':', '.')
  return `${fmt(start)} - ${fmt(end)}`
}

export default function AppointmentCalendar({ appointments = [], onEventClick }) {
  const calendarRef = useRef(null)

  // Rails prop shape → FullCalendar event object. Memoised so FC only
  // re-diffs on actual data change, not every parent render.
  const events = useMemo(
    () =>
      appointments.map((apt) => {
        const theme = STATUS_THEMES[apt.status] || STATUS_THEMES.scheduled
        return {
          id: String(apt.id),
          title: apt.patient_name,
          start: apt.start_time,
          end: apt.end_time,
          // We handle colours in eventContent + CSS vars; FC's default
          // background is overridden to plain white so the card tint
          // we render inside is the only visible fill.
          backgroundColor: '#FFFFFF',
          borderColor: theme.accent,
          extendedProps: {
            reason: apt.reason,
            status: apt.status,
            phone: apt.patient_phone,
            tint: theme.tint,
            accent: theme.accent,
          },
        }
      }),
    [appointments]
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

  // Custom card renderer — this is what gives us the screenshot look.
  // FullCalendar still positions the outer wrapper on the time grid;
  // we render the card inside with inline styles that pull from the
  // status theme. Absolute height tracks whatever slot the event spans.
  const renderEventContent = (arg) => {
    const { tint, accent, reason } = arg.event.extendedProps
    const patient = arg.event.title
    const start = arg.event.start
    const end = arg.event.end || arg.event.start
    return (
      <div
        className="h-full w-full rounded-md overflow-hidden flex flex-col p-2 text-[11px] leading-tight"
        style={{
          backgroundColor: tint,
          borderLeft: `3px solid ${accent}`,
        }}
      >
        <div className="flex items-center gap-1.5 mb-1">
          <span
            className="w-5 h-5 rounded-full flex items-center justify-center text-[9px] font-semibold text-white flex-shrink-0"
            style={{ backgroundColor: accent }}
          >
            {initials(patient)}
          </span>
          <span className="font-semibold text-gray-900 truncate">{patient}</span>
        </div>
        {reason && (
          <p className="text-gray-600 truncate mb-auto">{reason}</p>
        )}
        <p className="text-[10px] text-gray-500 mt-1 truncate">{formatRange(start, end)}</p>
      </div>
    )
  }

  return (
    <div className="appointment-calendar bg-white rounded-xl border border-gray-200 p-5">
      <FullCalendar
        ref={calendarRef}
        plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
        initialView="timeGridWeek"
        headerToolbar={{
          left: 'prev,next today',
          center: 'title',
          right: 'timeGridWeek,timeGridDay,dayGridMonth',
        }}
        events={events}
        editable
        eventDrop={handleEventDrop}
        eventClick={handleEventClick}
        eventContent={renderEventContent}
        slotMinTime="07:00:00"
        slotMaxTime="19:00:00"
        allDaySlot={false}
        nowIndicator
        height="auto"
        expandRows
        slotDuration="00:30:00"
        weekends
        firstDay={1}
        eventTimeFormat={{ hour: '2-digit', minute: '2-digit', meridiem: false }}
        dayHeaderFormat={{ weekday: 'short', day: 'numeric' }}
      />
    </div>
  )
}
