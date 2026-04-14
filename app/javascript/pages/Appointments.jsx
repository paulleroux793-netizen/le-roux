import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { CalendarDays, List } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import AppointmentCalendar from '../components/AppointmentCalendar'

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
}

const INPUT_CLASS =
  'border border-gray-200 rounded-lg px-3 py-2 text-sm text-gray-800 bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe transition-colors'

export default function Appointments({
  appointments,
  calendar_appointments = [],
  filters,
  stats,
}) {
  // Local UI state — which view the user is looking at. Defaults to
  // the calendar (Schedule) per the premium-dashboard reference.
  const [view, setView] = useState('schedule')

  const handleFilter = (key, value) => {
    router.get('/appointments', { ...filters, [key]: value || undefined }, { preserveState: true })
  }

  return (
    <DashboardLayout>
      <div className="mb-8 flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-brand-brown">Appointments</h1>
          <p className="text-gray-500 mt-1 text-sm">{stats?.total ?? 0} total appointments</p>
        </div>

        {/* View toggle */}
        <div className="inline-flex items-center bg-gray-100 rounded-lg p-1">
          <ViewTab
            active={view === 'schedule'}
            onClick={() => setView('schedule')}
            icon={CalendarDays}
            label="Schedule"
          />
          <ViewTab
            active={view === 'list'}
            onClick={() => setView('list')}
            icon={List}
            label="List"
          />
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
        <AppointmentCalendar appointments={calendar_appointments} />
      ) : (
        <>
          {/* Filters */}
          <div className="bg-white rounded-xl border border-gray-200 p-4 mb-5 flex gap-3">
            <input
              type="text"
              placeholder="Search patient name or phone…"
              defaultValue={filters?.search || ''}
              onKeyDown={(e) => e.key === 'Enter' && handleFilter('search', e.target.value)}
              className={`flex-1 ${INPUT_CLASS}`}
            />
            <select
              value={filters?.status || ''}
              onChange={(e) => handleFilter('status', e.target.value)}
              className={INPUT_CLASS}
            >
              <option value="">All Statuses</option>
              <option value="scheduled">Scheduled</option>
              <option value="confirmed">Confirmed</option>
              <option value="completed">Completed</option>
              <option value="cancelled">Cancelled</option>
              <option value="no_show">No Show</option>
              <option value="rescheduled">Rescheduled</option>
            </select>
            <input
              type="date"
              value={filters?.date || ''}
              onChange={(e) => handleFilter('date', e.target.value)}
              className={INPUT_CLASS}
            />
          </div>

          {/* Appointments Table */}
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <table className="min-w-full divide-y divide-gray-100">
              <thead>
                <tr className="bg-gray-50">
                  <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide">Patient</th>
                  <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide">Date & Time</th>
                  <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide">Reason</th>
                  <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                  <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {appointments?.length > 0 ? appointments.map((apt) => (
                  <tr key={apt.id} className="hover:bg-brand-cream transition-colors">
                    <td className="px-6 py-4">
                      <p className="text-sm font-medium text-gray-900">{apt.patient_name}</p>
                      <p className="text-xs text-gray-400 mt-0.5">{apt.patient_phone}</p>
                    </td>
                    <td className="px-6 py-4">
                      <p className="text-sm text-gray-800">
                        {new Date(apt.start_time).toLocaleDateString('en-ZA', { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' })}
                      </p>
                      <p className="text-xs text-gray-400 mt-0.5">
                        {new Date(apt.start_time).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })} — {new Date(apt.end_time).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })}
                      </p>
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-600">{apt.reason || '—'}</td>
                    <td className="px-6 py-4">
                      <StatusBadge status={apt.status} />
                    </td>
                    <td className="px-6 py-4">
                      <Link
                        href={`/appointments/${apt.id}`}
                        className="text-brand-taupe hover:text-brand-brown text-sm font-medium transition-colors"
                      >
                        View →
                      </Link>
                    </td>
                  </tr>
                )) : (
                  <tr>
                    <td colSpan="5" className="px-6 py-12 text-center text-gray-400 text-sm">
                      No appointments found
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
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

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[status] || 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}
