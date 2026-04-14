import React from 'react'
import DashboardLayout from '../layouts/DashboardLayout'
import AppointmentCalendar from '../components/AppointmentCalendar'

export default function Dashboard({ stats, calendar_appointments, system_status }) {
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

      {/* Interactive Calendar — Phase 9.6 sub-area 1 */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-semibold text-brand-brown">Schedule</h2>
          <p className="text-xs text-gray-400">Drag an event to reschedule</p>
        </div>
        <AppointmentCalendar appointments={calendar_appointments || []} />
      </div>

      <div className="grid grid-cols-1 gap-6">
        {/* System Status */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-base font-semibold text-brand-brown mb-4">System Status</h2>
          <div className="space-y-3">
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
      </div>
    </DashboardLayout>
  )
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

