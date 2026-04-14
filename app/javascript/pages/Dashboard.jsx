import React from 'react'
import { Link } from '@inertiajs/react'
import { Clock, Bell, Phone, MessageCircle } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

const STATUS_STYLES = {
  scheduled:   'border border-brand-primary/15 bg-brand-primary/10 text-brand-primary',
  confirmed:   'border border-brand-success/15 bg-brand-success/10 text-brand-success',
  completed:   'border border-brand-primary-dark/15 bg-brand-primary-dark/10 text-brand-primary-dark',
  cancelled:   'border border-brand-danger/15 bg-brand-danger/10 text-brand-danger',
  no_show:     'border border-brand-muted/15 bg-brand-muted/10 text-brand-muted',
  rescheduled: 'border border-brand-warning/15 bg-brand-warning/10 text-brand-warning',
}

export default function Dashboard({
  stats,
  todays_appointments = [],
  reminders = [],
}) {
  return (
    <DashboardLayout>
      <div className="mb-8">
        <span className="inline-flex items-center rounded-full border border-brand-border bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
          Clinic overview
        </span>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">Dashboard</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-brand-muted">
          Review today&apos;s patient activity, outstanding reminders, and front-desk follow-ups from one place.
        </p>
      </div>

      {/* Stat Cards */}
      <div className="mb-8 grid grid-cols-1 gap-5 md:grid-cols-4">
        <StatCard
          title="Today's Appointments"
          value={stats?.todays_appointments ?? 0}
          subtitle={`${stats?.confirmed_today ?? 0} confirmed · ${stats?.pending_confirmations ?? 0} pending`}
          accent="primary"
        />
        <StatCard
          title="WhatsApp Messages"
          value={stats?.whatsapp_messages ?? 0}
          subtitle="Last 7 days"
          accent="primary"
        />
        <StatCard
          title="Flagged Patients"
          value={stats?.flagged_patients ?? 0}
          subtitle="Need follow-up"
          accent="warning"
        />
        <StatCard
          title="Confirmed Today"
          value={stats?.confirmed_today ?? 0}
          subtitle="Morning confirmations"
          accent="success"
        />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Today's appointments — spans 2 cols */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm lg:col-span-2">
          <div className="flex items-center justify-between mb-4">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Clock size={16} className="text-brand-primary" />
              Today's Appointments
            </h2>
            <Link
              href="/appointments"
              className="text-xs font-medium text-brand-primary transition-colors hover:text-brand-primary-dark"
            >
              View all →
            </Link>
          </div>
          {todays_appointments.length > 0 ? (
            <div className="divide-y divide-brand-border">
              {todays_appointments.map((apt) => (
                <Link
                  key={apt.id}
                  href={`/appointments/${apt.id}`}
                  className="-mx-2 flex items-center gap-3 rounded-lg px-2 py-3 transition-colors first:pt-0 last:pb-0 hover:bg-brand-surface"
                >
                  <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg bg-brand-primary/10">
                    <span className="text-xs font-semibold text-brand-primary">
                      {initials(apt.patient_name)}
                    </span>
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                    <p className="mt-0.5 truncate text-xs text-brand-muted">{apt.reason || 'General consultation'}</p>
                  </div>
                  <div className="text-right flex-shrink-0">
                    <p className="text-xs font-semibold text-brand-ink">
                      {formatTime(apt.start_time)}
                    </p>
                    <p className="text-[11px] text-brand-muted">
                      {formatTime(apt.end_time)}
                    </p>
                  </div>
                  <StatusBadge status={apt.status} />
                </Link>
              ))}
            </div>
          ) : (
            <p className="py-8 text-center text-sm text-brand-muted">
              No appointments scheduled for today
            </p>
          )}
        </div>

        {/* Reminders */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Bell size={16} className="text-brand-primary" />
              Reminders
            </h2>
            {reminders.length > 0 && (
              <span className="rounded-full bg-brand-warning/10 px-2 py-0.5 text-xs font-semibold text-brand-warning">
                {reminders.length}
              </span>
            )}
          </div>
          {reminders.length > 0 ? (
            <div className="space-y-3">
              {reminders.map((apt) => (
                <div
                  key={apt.id}
                  className="rounded-lg border border-brand-border bg-brand-surface p-3"
                >
                  <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                  <p className="mt-0.5 text-xs text-brand-muted">
                    Unconfirmed · {formatTime(apt.start_time)}
                  </p>
                  <div className="flex gap-2 mt-2">
                    <a
                      href={`tel:${apt.patient_phone}`}
                      className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark"
                    >
                      <Phone size={11} /> Call
                    </a>
                    <span className="text-brand-border">·</span>
                    <Link
                      href={`/appointments/${apt.id}`}
                      className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark"
                    >
                      <MessageCircle size={11} /> Open
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="py-8 text-center text-sm text-brand-muted">
              No reminders — all set
            </p>
          )}
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
    primary: ['text-brand-primary', 'bg-brand-primary/10 text-brand-primary'],
    success: ['text-brand-success', 'bg-brand-success/10 text-brand-success'],
    warning: ['text-brand-warning', 'bg-brand-warning/10 text-brand-warning'],
  }
  const [valueClass, chipClass] = accentMap[accent] || accentMap.primary
  return (
    <div className="rounded-xl border border-brand-border bg-white p-5 shadow-sm">
      <span className={`inline-flex rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] ${chipClass}`}>
        Today
      </span>
      <p className={`mt-4 text-3xl font-semibold tracking-tight ${valueClass}`}>{value}</p>
      <p className="mt-1 text-xs font-semibold uppercase tracking-[0.18em] text-brand-muted">{title}</p>
      <p className="mt-2 text-sm text-brand-muted">{subtitle}</p>
    </div>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ${STATUS_STYLES[status] || 'border border-brand-muted/15 bg-brand-surface text-brand-muted'}`}>
      {status}
    </span>
  )
}
