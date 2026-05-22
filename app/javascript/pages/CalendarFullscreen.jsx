import React, { useEffect, useState } from 'react'
import { router, Link, Head } from '@inertiajs/react'
import { ArrowLeft, Plus, Stethoscope } from 'lucide-react'
import AppointmentCalendar from '../components/AppointmentCalendar'
import AppointmentDetailModal from '../components/AppointmentDetailModal'
import AppointmentFormModal from '../components/AppointmentFormModal'
import CancelAppointmentModal from '../components/CancelAppointmentModal'

// ── Dedicated full-screen calendar ──────────────────────────────────
// Paul's spec (2026-05-22): "just the calendar from one tab where it
// shows the week we're looking at at the top with the dentist at the
// top." No dashboard sidebar, no stat cards — a slim bar with the
// dentist name + the week grid filling the screen. The week title and
// prev/next/today/view controls live in FullCalendar's own header
// toolbar, so "the week we're looking at" is right at the top.
//
// When a second (cosmetic) dentist is added later, this bar becomes a
// per-dentist tab strip and the calendar query gains a dentist filter.
const DENTIST_NAME = 'Dr Chalita le Roux'

export default function CalendarFullscreen({
  calendar_appointments = [],
  calendar_meta = {},
  patients = [],
}) {
  const [modalMode, setModalMode] = useState(null)
  const [selected, setSelected] = useState(null)

  const openDetail = (apt) => { setSelected(apt); setModalMode('detail') }
  const openCreate = () => { setSelected(null); setModalMode('create') }
  const openEdit   = (apt) => { if (apt) setSelected(apt); setModalMode('edit') }
  const openCancel = (apt) => { if (apt) setSelected(apt); setModalMode('cancel') }
  const closeModal = () => { setModalMode(null); setSelected(null) }

  // Live refresh every 15s — keeps the grid current as the AI books and
  // reception walks patients through the day on another machine.
  useEffect(() => {
    const timer = setInterval(() => {
      router.reload({
        only: ['calendar_appointments'],
        preserveState: true,
        preserveScroll: true,
      })
    }, 15_000)
    return () => clearInterval(timer)
  }, [])

  const handleEventClick = (event) => {
    const id = Number(event.id)
    const source = calendar_appointments.find((a) => a.id === id)
    if (source) openDetail(source)
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-brand-bg">
      <Head title="Calendar — Dr Chalita le Roux" />

      {/* Slim top bar: dentist name + back link + new appointment */}
      <header className="flex flex-shrink-0 items-center justify-between border-b border-brand-border bg-white px-4 py-2.5 shadow-sm">
        <div className="flex items-center gap-3">
          <Link
            href="/dashboard"
            className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-medium text-brand-muted transition-colors hover:bg-brand-surface hover:text-brand-ink"
          >
            <ArrowLeft size={16} /> Dashboard
          </Link>
          <span className="h-5 w-px bg-brand-border" />
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand-primary/10 text-brand-primary">
              <Stethoscope size={16} />
            </span>
            <h1 className="text-base font-semibold tracking-tight text-brand-ink">{DENTIST_NAME}</h1>
          </div>
        </div>

        <button
          onClick={openCreate}
          className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
        >
          <Plus size={15} /> New appointment
        </button>
      </header>

      {/* Calendar fills the rest of the viewport. fillHeight keeps the
          FullCalendar toolbar (week nav + view switch) pinned at the top;
          only the time-grid scrolls internally if a screen is too short. */}
      <main className="min-h-0 flex-1 overflow-hidden p-3">
        <AppointmentCalendar
          appointments={calendar_appointments}
          calendarMeta={calendar_meta}
          onEventClick={handleEventClick}
          fillHeight
        />
      </main>

      {/* Modals — shared with the dashboard Appointments page */}
      <AppointmentDetailModal
        appointment={selected}
        open={modalMode === 'detail'}
        onClose={closeModal}
        onEdit={() => openEdit(selected)}
        onCancel={() => openCancel(selected)}
      />
      <AppointmentFormModal
        mode="create"
        open={modalMode === 'create'}
        onClose={closeModal}
        patients={patients}
      />
      <AppointmentFormModal
        mode="edit"
        appointment={selected}
        open={modalMode === 'edit'}
        onClose={closeModal}
      />
      <CancelAppointmentModal
        appointment={selected}
        open={modalMode === 'cancel'}
        onClose={closeModal}
      />
    </div>
  )
}
