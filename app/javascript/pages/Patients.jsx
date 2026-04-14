import React, { useMemo, useState } from 'react'
import { Link } from '@inertiajs/react'
import { Eye, Pencil, Users, UserCheck, UserPlus, Plus } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import DataTable from '../components/DataTable'
import PatientFormModal from '../components/PatientFormModal'

// Phase 9.6 sub-area #3 — Patients list rebuilt on the shared DataTable.
// Columns match the reference screenshot: ID No. · Patient · Status · Due
// · Phone · Age · Next Appointment · Actions. "Due" is a placeholder until
// Phase 12 (billing) lands — we render an em-dash so the column reads as
// intentionally empty rather than broken.
const STATUS_OPTIONS = [
  { value: 'active',   label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
]

export default function Patients({ patients = [], stats }) {
  // Modal state machine: at most one modal open at a time, plus the
  // patient being edited (null for create mode).
  const [modalMode, setModalMode] = useState(null)  // 'create' | 'edit' | null
  const [selected, setSelected]   = useState(null)

  const openCreate = () => { setSelected(null); setModalMode('create') }
  const openEdit   = (p) => { setSelected(p);   setModalMode('edit') }
  const closeModal = () => { setModalMode(null); setSelected(null) }

  // Memoised columns — see Appointments.jsx for the same rationale
  // (prevents tanstack from re-instantiating and wiping sort/column state).
  const columns = useMemo(() => [
    {
      accessorKey: 'code',
      header: 'ID No.',
      cell: ({ getValue }) => (
        <span className="text-sm font-medium text-gray-500">{getValue()}</span>
      ),
    },
    {
      accessorKey: 'full_name',
      header: 'Patient Name',
      cell: ({ row }) => (
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-surface">
            <span className="text-xs font-semibold text-brand-primary">
              {initials(row.original.full_name)}
            </span>
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-brand-ink">{row.original.full_name}</p>
            {row.original.email && (
              <p className="truncate text-xs text-brand-muted">{row.original.email}</p>
            )}
          </div>
        </div>
      ),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ getValue }) => <StatusBadge status={getValue()} />,
      filterFn: 'equals',
    },
    {
      id: 'due',
      header: 'Due',
      enableSorting: false,
      enableGlobalFilter: false,
      // Billing lands in Phase 12 — render a neutral placeholder so the
      // column reads as intentionally empty rather than missing.
      cell: () => <span className="text-sm text-gray-300">—</span>,
    },
    {
      accessorKey: 'phone',
      header: 'Phone',
      cell: ({ getValue }) => (
        <span className="text-sm text-brand-muted">{getValue() || '—'}</span>
      ),
    },
    {
      accessorKey: 'age',
      header: 'Age',
      cell: ({ getValue }) => (
        <span className="text-sm text-brand-muted">{getValue() ?? '—'}</span>
      ),
    },
    {
      accessorKey: 'next_appointment',
      header: 'Next Appointment',
      // Sort chronologically; null/undefined always last.
      sortingFn: (a, b) => {
        const av = a.original.next_appointment
        const bv = b.original.next_appointment
        if (!av && !bv) return 0
        if (!av) return 1
        if (!bv) return -1
        return new Date(av) - new Date(bv)
      },
      cell: ({ getValue }) => {
        const v = getValue()
        if (!v) return <span className="text-sm text-brand-muted/55">—</span>
        return (
          <span className="text-sm text-brand-ink">
            {new Date(v).toLocaleDateString('en-ZA', {
              year: 'numeric', month: 'short', day: 'numeric',
            })}
          </span>
        )
      },
    },
    {
      id: 'actions',
      header: 'Action',
      enableSorting: false,
      enableGlobalFilter: false,
      cell: ({ row }) => (
        <div className="flex items-center gap-1">
          <Link
            href={`/patients/${row.original.id}`}
            title="View"
            aria-label="View patient"
            className="inline-flex rounded-xl p-1.5 text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            <Eye size={15} />
          </Link>
          <button
            type="button"
            title="Edit"
            aria-label="Edit patient"
            onClick={() => openEdit(row.original)}
            className="inline-flex rounded-xl p-1.5 text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            <Pencil size={15} />
          </button>
        </div>
      ),
    },
  ], [])

  return (
    <DashboardLayout>
      <div className="mb-8 flex items-start justify-between">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
            Patient records
          </span>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">Patients</h1>
          <p className="mt-2 text-sm leading-6 text-brand-muted">
            {stats?.total ?? 0} registered patients
          </p>
        </div>
        <button
          onClick={openCreate}
          className="inline-flex items-center gap-1.5 rounded-2xl bg-brand-primary px-4 py-2.5 text-sm font-semibold text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark"
        >
          <Plus size={15} /> New Patient
        </button>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        <StatCard
          label="Total Patients"
          value={stats?.total ?? 0}
          icon={Users}
          color="text-brand-primary"
          tone="bg-brand-surface"
        />
        <StatCard
          label="Active"
          value={stats?.active ?? 0}
          icon={UserCheck}
          color="text-emerald-600"
          tone="bg-[#EAF8F0]"
        />
        <StatCard
          label="New This Month"
          value={stats?.new_this_month ?? 0}
          icon={UserPlus}
          color="text-brand-secondary"
          tone="bg-[#EEF4FF]"
        />
      </div>

      <DataTable
        columns={columns}
        data={patients}
        globalFilterPlaceholder="Search name, phone, email…"
        initialSort={[{ id: 'full_name', desc: false }]}
        pageSize={10}
        totalLabel="patients"
        emptyMessage="No patients registered yet"
        filters={({ setColumnFilter, getColumnFilter }) => (
          <>
            <select
              value={getColumnFilter('status')}
              onChange={(e) => setColumnFilter('status', e.target.value)}
              className="rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            >
              <option value="">All statuses</option>
              {STATUS_OPTIONS.map((s) => (
                <option key={s.value} value={s.value}>{s.label}</option>
              ))}
            </select>
            {getColumnFilter('status') && (
              <button
                type="button"
                onClick={() => setColumnFilter('status', '')}
                className="px-2 text-xs text-brand-muted hover:text-brand-ink"
              >
                Clear
              </button>
            )}
          </>
        )}
      />

      {/* ── Patient form modal (Create / Edit) ──────────────── */}
      <PatientFormModal
        open={modalMode === 'create'}
        mode="create"
        onClose={closeModal}
      />
      <PatientFormModal
        open={modalMode === 'edit'}
        mode="edit"
        patient={selected}
        medicalHistory={selected?.medical_history}
        bloodTypes={selected?.medical_history?.blood_types}
        onClose={closeModal}
      />
    </DashboardLayout>
  )
}

function StatCard({ label, value, icon: Icon, color, tone = 'bg-brand-surface' }) {
  return (
    <div className="flex items-center gap-4 rounded-[28px] border border-brand-accent/75 bg-white p-4 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
      <div className={`flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-2xl ${tone}`}>
        <Icon size={18} className={color} />
      </div>
      <div>
        <p className={`text-2xl font-bold ${color}`}>{value}</p>
        <p className="text-xs uppercase tracking-wide text-brand-muted">{label}</p>
      </div>
    </div>
  )
}

function StatusBadge({ status }) {
  const styles = status === 'active'
    ? 'border border-brand-success/15 bg-[#EAF8F0] text-brand-success'
    : 'border border-brand-muted/15 bg-[#F3F6FB] text-brand-muted'
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${styles}`}>
      {status}
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
