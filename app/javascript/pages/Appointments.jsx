import React, { useState, useMemo } from 'react'
import { router } from '@inertiajs/react'
import { CalendarDays, List, Plus, CheckCircle, Eye, Pencil, X as XIcon } from 'lucide-react'
import { toast } from 'sonner'
import DashboardLayout from '../layouts/DashboardLayout'
import AppointmentCalendar from '../components/AppointmentCalendar'
import AppointmentDetailModal from '../components/AppointmentDetailModal'
import AppointmentFormModal from '../components/AppointmentFormModal'
import CancelAppointmentModal from '../components/CancelAppointmentModal'
import DataTable from '../components/DataTable'

// Token-driven status pills — shared palette with AppointmentCalendar.
const STATUS_STYLES = {
  scheduled:   'border border-brand-primary/15 bg-brand-primary/10 text-brand-primary',
  confirmed:   'border border-brand-success/15 bg-brand-success/10 text-brand-success',
  completed:   'border border-brand-primary-dark/15 bg-brand-primary-dark/10 text-brand-primary-dark',
  cancelled:   'border border-brand-danger/15 bg-brand-danger/10 text-brand-danger',
  no_show:     'border border-brand-muted/15 bg-brand-muted/10 text-brand-muted',
  rescheduled: 'border border-brand-warning/15 bg-brand-warning/10 text-brand-warning',
}

// Single source of truth for statuses — reused in the table header
// filter dropdown and the status badge renderer below.
const STATUS_OPTIONS = [
  { value: 'scheduled',   label: 'Scheduled' },
  { value: 'confirmed',   label: 'Confirmed' },
  { value: 'completed',   label: 'Completed' },
  { value: 'cancelled',   label: 'Cancelled' },
  { value: 'no_show',     label: 'No show' },
  { value: 'rescheduled', label: 'Rescheduled' },
]

export default function Appointments({
  appointments = [],
  calendar_appointments = [],
  calendar_meta = {},
  patients = [],
  stats,
}) {
  const [view, setView] = useState('schedule')
  const [modalMode, setModalMode] = useState(null)
  const [selected, setSelected] = useState(null)

  const openDetail = (apt) => { setSelected(apt); setModalMode('detail') }
  const openCreate = () => { setSelected(null); setModalMode('create') }
  const openEdit   = (apt) => { if (apt) setSelected(apt); setModalMode('edit') }
  const openCancel = (apt) => { if (apt) setSelected(apt); setModalMode('cancel') }
  const closeModal = () => { setModalMode(null); setSelected(null) }

  const handleEventClick = (event) => {
    const id = Number(event.id)
    const source = calendar_appointments.find((a) => a.id === id)
    if (source) openDetail(source)
  }

  // One-click confirm — used from the list row Confirm button.
  const confirmAppointment = (apt) => {
    router.patch(`/appointments/${apt.id}/confirm`, {}, {
      preserveScroll: true,
      onSuccess: () => toast.success(`${apt.patient_name} confirmed`),
      onError:   () => toast.error('Could not confirm'),
    })
  }

  // ── Column definitions for the List view ────────────────────
  // Memoised so @tanstack/react-table doesn't re-instantiate them
  // on every render (which would reset column widths + sort state).
  const columns = useMemo(() => [
    {
      accessorKey: 'patient_name',
      header: 'Patient',
      cell: ({ row }) => (
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary/10">
            <span className="text-xs font-semibold text-brand-primary">
              {initials(row.original.patient_name)}
            </span>
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-brand-ink">{row.original.patient_name}</p>
            <p className="text-xs text-brand-muted">{row.original.patient_phone}</p>
          </div>
        </div>
      ),
    },
    {
      accessorKey: 'start_time',
      header: 'Date & Time',
      // Sort chronologically, not string-wise. Custom sortingFn
      // because the accessor returns an ISO string.
      sortingFn: (a, b) =>
        new Date(a.original.start_time) - new Date(b.original.start_time),
      cell: ({ row }) => (
        <div>
          <p className="text-sm text-gray-800">
            {new Date(row.original.start_time).toLocaleDateString('en-ZA', {
              weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
            })}
          </p>
          <p className="mt-0.5 text-xs text-brand-muted">
            {fmtTime(row.original.start_time)} — {fmtTime(row.original.end_time)}
          </p>
        </div>
      ),
      // Custom filter: row.start_time === selected ISO date
      filterFn: (row, columnId, value) => {
        if (!value) return true
        const d = new Date(row.original.start_time)
        const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
        return iso === value
      },
    },
    {
      accessorKey: 'reason',
      header: 'Reason',
      cell: ({ getValue }) => (
        <span className="text-sm text-gray-600">{getValue() || '—'}</span>
      ),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ getValue }) => <StatusBadge status={getValue()} />,
      // Exact match filter so the dropdown "Scheduled" only matches scheduled rows.
      filterFn: 'equals',
    },
    {
      id: 'actions',
      header: 'Actions',
      enableSorting: false,
      enableGlobalFilter: false,
      cell: ({ row }) => (
        <div className="flex items-center gap-1">
          <IconBtn
            title="View"
            onClick={() => openDetail(row.original)}
            icon={Eye}
          />
          <IconBtn
            title="Edit"
            onClick={() => openEdit(row.original)}
            icon={Pencil}
          />
          {row.original.status !== 'confirmed' &&
           row.original.status !== 'cancelled' && (
            <IconBtn
              title="Confirm"
              onClick={() => confirmAppointment(row.original)}
              icon={CheckCircle}
              colorClass="text-brand-success hover:bg-brand-success/10"
            />
          )}
          {row.original.status !== 'cancelled' && (
            <IconBtn
              title="Cancel"
              onClick={() => openCancel(row.original)}
              icon={XIcon}
              colorClass="text-brand-danger hover:bg-brand-danger/10"
            />
          )}
        </div>
      ),
    },
  ], [])

  return (
    <DashboardLayout>
      <div className="mb-8 flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-border bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.2em] text-brand-primary">
            Schedule view
          </span>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">Appointments</h1>
          <p className="mt-2 text-sm leading-6 text-brand-muted">
            {stats?.total ?? 0} appointments tracked across the live clinic diary.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div className="inline-flex items-center rounded-xl border border-brand-border bg-brand-surface p-1">
            <ViewTab active={view === 'schedule'} onClick={() => setView('schedule')} icon={CalendarDays} label="Schedule" />
            <ViewTab active={view === 'list'}     onClick={() => setView('list')}     icon={List}         label="List" />
          </div>

          <button
            onClick={openCreate}
            className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
          >
            <Plus size={15} /> New Appointment
          </button>
        </div>
      </div>

      {/* Stats Row */}
      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[
          ['Scheduled',  stats?.scheduled,  'bg-brand-primary/10',      'text-brand-primary'],
          ['Confirmed',  stats?.confirmed,  'bg-brand-success/10',      'text-brand-success'],
          ['Completed',  stats?.completed,  'bg-brand-primary-dark/10', 'text-brand-primary-dark'],
          ['Cancelled',  stats?.cancelled,  'bg-brand-danger/10',       'text-brand-danger'],
        ].map(([label, count, tint, color]) => (
          <div key={label} className="rounded-xl border border-brand-border bg-white p-5 shadow-sm">
            <div className={`mb-4 inline-flex rounded-lg px-3 py-2 text-xs font-semibold ${tint} ${color}`}>
              {label}
            </div>
            <p className={`text-3xl font-semibold tracking-tight ${color}`}>{count ?? 0}</p>
            <p className="mt-1 text-xs uppercase tracking-[0.18em] text-brand-muted">Live count</p>
          </div>
        ))}
      </div>

      {view === 'schedule' ? (
        <AppointmentCalendar
          appointments={calendar_appointments}
          calendarMeta={calendar_meta}
          onEventClick={handleEventClick}
        />
      ) : (
        <DataTable
          columns={columns}
          data={appointments}
          globalFilterPlaceholder="Search patient, phone, reason…"
          initialSort={[{ id: 'start_time', desc: true }]}
          pageSize={10}
          totalLabel="appointments"
          emptyMessage="No appointments found"
          filters={({ setColumnFilter, getColumnFilter }) => (
            <>
              <select
                value={getColumnFilter('status')}
                onChange={(e) => setColumnFilter('status', e.target.value)}
                className="rounded-lg border border-brand-border bg-white px-3 py-2 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-primary/20"
              >
                <option value="">All statuses</option>
                {STATUS_OPTIONS.map((s) => (
                  <option key={s.value} value={s.value}>{s.label}</option>
                ))}
              </select>
              <input
                type="date"
                value={getColumnFilter('start_time')}
                onChange={(e) => setColumnFilter('start_time', e.target.value)}
                className="rounded-lg border border-brand-border bg-white px-3 py-2 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-primary/20"
              />
              {(getColumnFilter('status') || getColumnFilter('start_time')) && (
                <button
                  type="button"
                  onClick={() => {
                    setColumnFilter('status', '')
                    setColumnFilter('start_time', '')
                  }}
                  className="px-2 text-xs text-brand-muted hover:text-brand-ink"
                >
                  Clear
                </button>
              )}
            </>
          )}
        />
      )}

      {/* ── Modals ─────────────────────────────────────────────── */}
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
    </DashboardLayout>
  )
}

function ViewTab({ active, onClick, icon: Icon, label }) {
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold transition-all ${
        active
          ? 'border border-brand-border bg-white text-brand-primary shadow-sm'
          : 'text-brand-muted hover:text-brand-ink'
      }`}
    >
      <Icon size={14} />
      {label}
    </button>
  )
}

function IconBtn({ title, onClick, icon: Icon, colorClass = 'text-brand-muted hover:bg-brand-surface' }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      onClick={onClick}
      className={`rounded-lg p-1.5 transition-colors ${colorClass}`}
    >
      <Icon size={15} />
    </button>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ${STATUS_STYLES[status] || 'border border-brand-muted/15 bg-brand-surface text-brand-muted'}`}>
      {String(status).replace('_', ' ')}
    </span>
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

function fmtTime(iso) {
  return new Date(iso).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })
}
