import React from 'react'
import { Link } from '@inertiajs/react'
import { Clock, Bell, Phone, MessageCircle } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

const STATUS_STYLES = {
  scheduled:   'bg-amber-100 text-amber-800',
  confirmed:   'bg-emerald-100 text-emerald-800',
  completed:   'bg-blue-100 text-blue-800',
  cancelled:   'bg-red-100 text-red-800',
  no_show:     'bg-gray-100 text-gray-600',
  rescheduled: 'bg-purple-100 text-purple-800',
}

export default function Dashboard({
  stats,
  todays_appointments = [],
  reminders = [],
  system_status,
}) {
  return (
    <DashboardLayout>
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-brand-brown">Dashboard</h1>
        <p className="text-gray-500 mt-1 text-sm">Overview of today's activity</p>
      </div>

      {/* Stat Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-5 mb-8">
        <StatCard
          title="Today's Appointments"
          value={stats?.todays_appointments ?? 0}
          subtitle={`${stats?.confirmed_today ?? 0} confirmed · ${stats?.pending_confirmations ?? 0} pending`}
          accent="brown"
        />
        <StatCard
          title="WhatsApp Messages"
          value={stats?.whatsapp_messages ?? 0}
          subtitle="Last 7 days"
          accent="taupe"
        />
        <StatCard
          title="Flagged Patients"
          value={stats?.flagged_patients ?? 0}
          subtitle="Need follow-up"
          accent="amber"
        />
        <StatCard
          title="Confirmed Today"
          value={stats?.confirmed_today ?? 0}
          subtitle="Morning confirmations"
          accent="gold"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Today's appointments — spans 2 cols */}
        <div className="lg:col-span-2 bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-base font-semibold text-brand-brown flex items-center gap-2">
              <Clock size={16} className="text-brand-taupe" />
              Today's Appointments
            </h2>
            <Link
              href="/appointments"
              className="text-xs text-brand-taupe hover:text-brand-brown font-medium transition-colors"
            >
              View all →
            </Link>
          </div>
          {todays_appointments.length > 0 ? (
            <div className="divide-y divide-gray-100">
              {todays_appointments.map((apt) => (
                <Link
                  key={apt.id}
                  href={`/appointments/${apt.id}`}
                  className="flex items-center gap-3 py-3 first:pt-0 last:pb-0 hover:bg-brand-cream -mx-2 px-2 rounded-lg transition-colors"
                >
                  <div className="w-10 h-10 rounded-full bg-brand-cream flex items-center justify-center flex-shrink-0">
                    <span className="text-brand-brown text-xs font-semibold">
                      {initials(apt.patient_name)}
                    </span>
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="font-medium text-gray-900 text-sm truncate">{apt.patient_name}</p>
                    <p className="text-xs text-gray-400 mt-0.5 truncate">{apt.reason || 'General consultation'}</p>
                  </div>
                  <div className="text-right flex-shrink-0">
                    <p className="text-xs font-semibold text-gray-700">
                      {formatTime(apt.start_time)}
                    </p>
                    <p className="text-[11px] text-gray-400">
                      {formatTime(apt.end_time)}
                    </p>
                  </div>
                  <StatusBadge status={apt.status} />
                </Link>
              ))}
            </div>
          ) : (
            <p className="text-gray-400 text-sm py-8 text-center">
              No appointments scheduled for today
            </p>
          )}
        </div>

        {/* Reminders */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-base font-semibold text-brand-brown flex items-center gap-2">
              <Bell size={16} className="text-brand-taupe" />
              Reminders
            </h2>
            {reminders.length > 0 && (
              <span className="text-xs font-semibold text-amber-700 bg-amber-100 px-2 py-0.5 rounded-full">
                {reminders.length}
              </span>
            )}
          </div>
          {reminders.length > 0 ? (
            <div className="space-y-3">
              {reminders.map((apt) => (
                <div
                  key={apt.id}
                  className="border border-amber-100 bg-amber-50/50 rounded-lg p-3"
                >
                  <p className="font-medium text-gray-900 text-sm truncate">{apt.patient_name}</p>
                  <p className="text-xs text-gray-500 mt-0.5">
                    Unconfirmed · {formatTime(apt.start_time)}
                  </p>
                  <div className="flex gap-2 mt-2">
                    <a
                      href={`tel:${apt.patient_phone}`}
                      className="flex items-center gap-1 text-xs text-brand-taupe hover:text-brand-brown font-medium"
                    >
                      <Phone size={11} /> Call
                    </a>
                    <span className="text-gray-300">·</span>
                    <Link
                      href={`/appointments/${apt.id}`}
                      className="flex items-center gap-1 text-xs text-brand-taupe hover:text-brand-brown font-medium"
                    >
                      <MessageCircle size={11} /> Open
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-gray-400 text-sm py-8 text-center">
              No reminders — all set
            </p>
          )}
        </div>
      </div>

      {/* System status */}
      <div className="mt-6 bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-brand-brown mb-4">System Status</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            ['Database',         true],
            ['Google Calendar',  system_status?.google_calendar],
            ['Twilio WhatsApp',  system_status?.twilio],
            ['Claude AI',        system_status?.claude_ai],
          ].map(([name, connected]) => (
            <div key={name} className="flex items-center justify-between py-1">
              <span className="text-sm text-gray-600">{name}</span>
              <span className={`flex items-center gap-1.5 text-sm font-medium ${connected ? 'text-emerald-600' : 'text-gray-400'}`}>
                <span className={`w-2 h-2 rounded-full ${connected ? 'bg-emerald-400' : 'bg-gray-300'}`} />
                {connected ? 'Connected' : 'Pending'}
              </span>
            </div>
          ))}
        </div>
      </div>
    </DashboardLayout>
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

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })
}

function StatCard({ title, value, subtitle, accent }) {
  const accentMap = {
    brown: 'text-brand-brown',
    taupe: 'text-brand-taupe',
    amber: 'text-amber-600',
    gold:  'text-brand-gold',
  }
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-5">
      <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">{title}</p>
      <p className={`text-3xl font-bold mt-2 ${accentMap[accent] || 'text-brand-brown'}`}>{value}</p>
      <p className="text-xs text-gray-400 mt-1">{subtitle}</p>
    </div>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[status] || 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}
