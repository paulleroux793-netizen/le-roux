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

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
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
          <div className="w-9 h-9 rounded-full bg-brand-cream flex items-center justify-center flex-shrink-0">
            <span className="text-brand-brown text-xs font-semibold">
              {initials(row.original.patient_name)}
            </span>
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-gray-900">{row.original.patient_name}</p>
            <p className="text-xs text-gray-400">{row.original.patient_phone}</p>
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
          <p className="text-xs text-gray-400 mt-0.5">
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
              colorClass="text-emerald-600 hover:bg-emerald-50"
            />
          )}
          {row.original.status !== 'cancelled' && (
            <IconBtn
              title="Cancel"
              onClick={() => openCancel(row.original)}
              icon={XIcon}
              colorClass="text-red-600 hover:bg-red-50"
            />
          )}
        </div>
      ),
    },
  ], [])

  return (
    <DashboardLayout>
      <div className="mb-8 flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-brand-brown">Appointments</h1>
          <p className="text-gray-500 mt-1 text-sm">{stats?.total ?? 0} total appointments</p>
        </div>

        <div className="flex items-center gap-3">
          <div className="inline-flex items-center bg-gray-100 rounded-lg p-1">
            <ViewTab active={view === 'schedule'} onClick={() => setView('schedule')} icon={CalendarDays} label="Schedule" />
            <ViewTab active={view === 'list'}     onClick={() => setView('list')}     icon={List}         label="List" />
          </div>

          <button
            onClick={openCreate}
            className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold text-white bg-brand-taupe hover:bg-brand-brown rounded-lg transition-colors"
          >
            <Plus size={15} /> New Appointment
          </button>
        </div>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        {[
          ['Scheduled',  stats?.scheduled,  'text-amber-600'],
          ['Confirmed',  stats?.confirmed,  'text-emerald-600'],
          ['Completed',  stats?.completed,  'text-blue-600'],
          ['Cancelled',  stats?.cancelled,  'text-red-500'],
        ].map(([label, count, color]) => (
          <div key={label} className="bg-white rounded-xl border border-gray-200 p-4 text-center">
            <p className={`text-2xl font-bold ${color}`}>{count ?? 0}</p>
            <p className="text-xs text-gray-400 mt-1 uppercase tracking-wide">{label}</p>
          </div>
        ))}
      </div>

      {view === 'schedule' ? (
        <AppointmentCalendar
          appointments={calendar_appointments}
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
                className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe"
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
                className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe"
              />
              {(getColumnFilter('status') || getColumnFilter('start_time')) && (
                <button
                  type="button"
                  onClick={() => {
                    setColumnFilter('status', '')
                    setColumnFilter('start_time', '')
                  }}
                  className="text-xs text-gray-500 hover:text-brand-brown px-2"
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
      className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-semibold transition-colors ${
        active
          ? 'bg-white text-brand-brown shadow-sm'
          : 'text-gray-500 hover:text-gray-700'
      }`}
    >
      <Icon size={14} />
      {label}
    </button>
  )
}

function IconBtn({ title, onClick, icon: Icon, colorClass = 'text-gray-500 hover:bg-gray-100' }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      onClick={onClick}
      className={`p-1.5 rounded-md transition-colors ${colorClass}`}
    >
      <Icon size={15} />
    </button>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${STATUS_STYLES[status] || 'bg-gray-100 text-gray-600'}`}>
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
