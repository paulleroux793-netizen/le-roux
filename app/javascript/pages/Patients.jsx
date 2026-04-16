import React, { useMemo, useState } from 'react'
import { Link } from '@inertiajs/react'
import { Eye, Pencil, Users, UserCheck, UserPlus, Plus } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import DataTable from '../components/DataTable'
import PatientFormModal from '../components/PatientFormModal'
import { useLanguage } from '../lib/LanguageContext'

// Phase 9.6 sub-area #3 — Patients list rebuilt on the shared DataTable.

export default function Patients({ patients = [], stats }) {
  const { t, language } = useLanguage()
  const dateFmt = language === 'af' ? 'af-ZA' : 'en-ZA'

  const [modalMode, setModalMode] = useState(null)
  const [selected, setSelected]   = useState(null)

  const openCreate = () => { setSelected(null); setModalMode('create') }
  const openEdit   = (p) => { setSelected(p);   setModalMode('edit') }
  const closeModal = () => { setModalMode(null); setSelected(null) }

  const STATUS_OPTIONS = [
    { value: 'active',   label: t('pat_status_active') },
    { value: 'inactive', label: t('pat_status_inactive') },
  ]

  const columns = useMemo(() => [
    {
      accessorKey: 'code',
      header: t('pat_col_id'),
      cell: ({ getValue }) => (
        <span className="text-sm font-medium text-gray-500">{getValue()}</span>
      ),
    },
    {
      accessorKey: 'full_name',
      header: t('pat_col_name'),
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
      header: t('pat_col_status'),
      cell: ({ getValue }) => <StatusBadge status={getValue()} t={t} />,
      filterFn: 'equals',
    },
    {
      id: 'due',
      header: t('pat_col_due'),
      enableSorting: false,
      enableGlobalFilter: false,
      cell: () => <span className="text-sm text-gray-300">—</span>,
    },
    {
      accessorKey: 'phone',
      header: t('pat_col_phone'),
      cell: ({ getValue }) => (
        <span className="text-sm text-brand-muted">{getValue() || '—'}</span>
      ),
    },
    {
      accessorKey: 'age',
      header: t('pat_col_age'),
      cell: ({ getValue }) => (
        <span className="text-sm text-brand-muted">{getValue() ?? '—'}</span>
      ),
    },
    {
      accessorKey: 'next_appointment',
      header: t('pat_col_next'),
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
            {new Date(v).toLocaleDateString(dateFmt, {
              year: 'numeric', month: 'short', day: 'numeric',
            })}
          </span>
        )
      },
    },
    {
      id: 'actions',
      header: t('pat_col_action'),
      enableSorting: false,
      enableGlobalFilter: false,
      cell: ({ row }) => (
        <div className="flex items-center gap-1">
          <Link
            href={`/patients/${row.original.id}`}
            title={t('view')}
            aria-label={t('view')}
            className="inline-flex rounded-xl p-1.5 text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            <Eye size={15} />
          </Link>
          <button
            type="button"
            title={t('reschedule_action')}
            aria-label={t('reschedule_action')}
            onClick={() => openEdit(row.original)}
            className="inline-flex rounded-xl p-1.5 text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            <Pencil size={15} />
          </button>
        </div>
      ),
    },
  ], [t, dateFmt])

  return (
    <DashboardLayout>
      <div className="mb-8 flex items-start justify-between">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
            {t('pat_badge')}
          </span>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">{t('pat_title')}</h1>
          <p className="mt-2 text-sm leading-6 text-brand-muted">
            {stats?.total ?? 0} {t('pat_registered')}
          </p>
        </div>
        <button
          onClick={openCreate}
          className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-brand-primary-dark"
        >
          <Plus size={15} /> {t('pat_new')}
        </button>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        <StatCard
          label={t('pat_total')}
          value={stats?.total ?? 0}
          icon={Users}
          color="text-brand-primary"
          tone="bg-brand-surface"
        />
        <StatCard
          label={t('pat_active')}
          value={stats?.active ?? 0}
          icon={UserCheck}
          color="text-emerald-600"
          tone="bg-brand-success/10"
        />
        <StatCard
          label={t('pat_new_month')}
          value={stats?.new_this_month ?? 0}
          icon={UserPlus}
          color="text-brand-secondary"
          tone="bg-brand-primary/10"
        />
      </div>

      <DataTable
        columns={columns}
        data={patients}
        globalFilterPlaceholder={t('pat_search')}
        initialSort={[{ id: 'full_name', desc: false }]}
        pageSize={10}
        totalLabel={t('pat_total_label')}
        emptyMessage={t('pat_empty')}
        filters={({ setColumnFilter, getColumnFilter }) => (
          <>
            <select
              value={getColumnFilter('status')}
              onChange={(e) => setColumnFilter('status', e.target.value)}
              className="rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            >
              <option value="">{t('pat_all_statuses')}</option>
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
                {t('pat_clear')}
              </button>
            )}
          </>
        )}
      />

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
    <div className="flex items-center gap-4 rounded-xl border border-brand-border bg-white p-4 shadow-sm">
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

function StatusBadge({ status, t }) {
  const styles = status === 'active'
    ? 'border border-brand-success/15 bg-brand-success/10 text-brand-success'
    : 'border border-brand-muted/15 bg-brand-surface text-brand-muted'
  const label = status === 'active' ? t('pat_status_active') : t('pat_status_inactive')
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${styles}`}>
      {label}
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
