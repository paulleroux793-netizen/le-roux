import React, { useMemo, useRef } from 'react'
import { router } from '@inertiajs/react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import interactionPlugin from '@fullcalendar/interaction'
import { toast } from 'sonner'

// ── Brand palette for event blocks ──────────────────────────────────
// Keyed by Appointment.status enum values from the Rails side. Kept
// small and muted so the calendar still reads as "premium" rather than
// a rainbow of competing colours. Status meanings are the same as
// STATUS_STYLES in Appointments.jsx; we use slightly different shades
// here because event blocks sit on a white grid and need more contrast.
const STATUS_COLORS = {
  scheduled:   { bg: '#FEF3C7', border: '#F59E0B', text: '#92400E' }, // amber
  confirmed:   { bg: '#D1FAE5', border: '#10B981', text: '#065F46' }, // emerald
  completed:   { bg: '#DBEAFE', border: '#3B82F6', text: '#1E40AF' }, // blue
  cancelled:   { bg: '#FEE2E2', border: '#EF4444', text: '#991B1B' }, // red
  no_show:     { bg: '#F3F4F6', border: '#9CA3AF', text: '#4B5563' }, // gray
  rescheduled: { bg: '#EDE9FE', border: '#8B5CF6', text: '#5B21B6' }, // purple
}

export default function AppointmentCalendar({ appointments = [], onEventClick }) {
  const calendarRef = useRef(null)

  // Convert Rails appointment props → FullCalendar event objects.
  // Memoised so FullCalendar doesn't re-render on every parent render.
  const events = useMemo(
    () =>
      appointments.map((apt) => {
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
    [appointments]
  )

  // Drag-to-reschedule — fires after a user drops an event on a new slot.
  // We PATCH /appointments/:id with the new window; on server error we
  // revert the drop so the calendar stays in sync with the DB.
  const handleEventDrop = (info) => {
    const { id } = info.event
    const payload = {
      appointment: {
        start_time: info.event.start.toISOString(),
        end_time:   info.event.end ? info.event.end.toISOString() : null,
      },
    }

    router.patch(`/appointments/${id}`, payload, {
      preserveScroll: true,
      onSuccess: () => toast.success('Appointment rescheduled'),
      onError: () => {
        info.revert()
        toast.error('Could not reschedule — reverted')
      },
    })
  }

  // Clicking an event bubbles up to the parent so the host page can
  // decide what to open (detail modal in sub-area #2, or navigation
  // fallback for now).
  const handleEventClick = (info) => {
    info.jsEvent.preventDefault()
    if (onEventClick) {
      onEventClick(info.event)
    } else {
      router.visit(`/appointments/${info.event.id}`)
    }
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-5">
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
        droppable={false}
        eventDrop={handleEventDrop}
        eventClick={handleEventClick}
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
      />
    </div>
  )
}
