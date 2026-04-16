import React, { useEffect, useMemo } from 'react'
import { Link, router } from '@inertiajs/react'
import {
  Users, CalendarCheck, UserPlus, Activity,
  Clock, Bell, Phone, MessageCircle, ArrowUpRight,
  TrendingUp, Calendar
} from 'lucide-react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend
} from 'recharts'
import DashboardLayout from '../layouts/DashboardLayout'

const STATUS_STYLES = {
  scheduled:   'border border-brand-primary/15 bg-brand-primary/10 text-brand-primary',
  confirmed:   'border border-brand-success/15 bg-brand-success/10 text-brand-success',
  completed:   'border border-brand-primary-dark/15 bg-brand-primary-dark/10 text-brand-primary-dark',
  cancelled:   'border border-brand-danger/15 bg-brand-danger/10 text-brand-danger',
  no_show:     'border border-brand-muted/15 bg-brand-muted/10 text-brand-muted',
  rescheduled: 'border border-brand-warning/15 bg-brand-warning/10 text-brand-warning',
}

const CHART_COLORS = {
  scheduled: '#0E9F9F',
  confirmed: '#10B981',
  completed: '#0B8080',
  cancelled: '#EF4444',
}

export default function Dashboard({
  stats,
  todays_appointments = [],
  upcoming_appointments = [],
  weekly_chart = [],
  recent_patients = [],
  reminders = [],
}) {
  const greeting = useMemo(() => {
    const hour = new Date().getHours()
    if (hour < 12) return 'Good morning'
    if (hour < 17) return 'Good afternoon'
    return 'Good evening'
  }, [])

  // Poll for fresh data every 15 seconds so the dashboard reflects
  // new bookings, confirmations, and reminders in near-real-time.
  // `only` limits the partial reload to just our dashboard props —
  // the server skips layout/shared data, keeping it lightweight.
  useEffect(() => {
    const POLL_INTERVAL = 15_000

    const timer = setInterval(() => {
      router.reload({
        only: [
          'stats',
          'todays_appointments',
          'upcoming_appointments',
          'weekly_chart',
          'recent_patients',
          'reminders',
        ],
        preserveState: true,
        preserveScroll: true,
      })
    }, POLL_INTERVAL)

    return () => clearInterval(timer)
  }, [])

  return (
    <DashboardLayout>
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight text-brand-ink">
          {greeting} 👋
        </h1>
        <p className="mt-1 text-sm text-brand-muted">
          Here&apos;s what&apos;s happening at the practice today.
        </p>
      </div>

      {/* Stat Cards */}
      <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          title="Total Patients"
          value={stats?.total_patients ?? 0}
          subtitle={`${stats?.new_patients_month ?? 0} new this month`}
          icon={Users}
          accent="primary"
        />
        <StatCard
          title="Today's Appointments"
          value={stats?.todays_appointments ?? 0}
          subtitle={`${stats?.confirmed_today ?? 0} confirmed · ${stats?.pending_confirmations ?? 0} pending`}
          icon={CalendarCheck}
          accent="success"
        />
        <StatCard
          title="New Patients"
          value={stats?.new_patients_month ?? 0}
          subtitle="This month"
          icon={UserPlus}
          accent="info"
        />
        <StatCard
          title="Total Appointments"
          value={stats?.total_appointments ?? 0}
          subtitle={`${stats?.completed_today ?? 0} completed today`}
          icon={Activity}
          accent="warning"
        />
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
        {/* Chart — spans 2 cols */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm xl:col-span-2">
          <div className="mb-6 flex items-center justify-between">
            <div>
              <h2 className="text-base font-semibold text-brand-ink">
                Appointment Overview
              </h2>
              <p className="mt-0.5 text-xs text-brand-muted">This week&apos;s appointment breakdown</p>
            </div>
            <Link
              href="/appointments"
              className="inline-flex items-center gap-1 rounded-lg border border-brand-border px-3 py-1.5 text-xs font-medium text-brand-muted transition-colors hover:bg-brand-surface hover:text-brand-ink"
            >
              View all <ArrowUpRight size={12} />
            </Link>
          </div>
          <div className="h-[280px]">
            {weekly_chart.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={weekly_chart} barGap={4} barSize={18}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" vertical={false} />
                  <XAxis
                    dataKey="day"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: '#64748B', fontSize: 12, fontWeight: 500 }}
                  />
                  <YAxis
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: '#64748B', fontSize: 12 }}
                    allowDecimals={false}
                  />
                  <Tooltip content={<ChartTooltip />} cursor={{ fill: 'rgba(14,159,159,0.04)' }} />
                  <Legend
                    iconType="circle"
                    iconSize={8}
                    wrapperStyle={{ fontSize: 12, paddingTop: 12 }}
                  />
                  <Bar dataKey="confirmed" name="Confirmed" fill={CHART_COLORS.confirmed} radius={[4, 4, 0, 0]} />
                  <Bar dataKey="scheduled" name="Scheduled" fill={CHART_COLORS.scheduled} radius={[4, 4, 0, 0]} />
                  <Bar dataKey="completed" name="Completed" fill={CHART_COLORS.completed} radius={[4, 4, 0, 0]} />
                  <Bar dataKey="cancelled" name="Cancelled" fill={CHART_COLORS.cancelled} radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-brand-muted">
                No appointment data for this week
              </div>
            )}
          </div>
        </div>

        {/* Upcoming Appointments sidebar */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Calendar size={16} className="text-brand-primary" />
              Upcoming
            </h2>
            <Link
              href="/appointments"
              className="text-xs font-medium text-brand-primary transition-colors hover:text-brand-primary-dark"
            >
              See all →
            </Link>
          </div>
          {upcoming_appointments.length > 0 ? (
            <div className="space-y-3">
              {upcoming_appointments.map((apt) => (
                <Link
                  key={apt.id}
                  href={`/appointments/${apt.id}`}
                  className="block rounded-lg border border-brand-border p-3 transition-colors hover:bg-brand-surface"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                      <p className="mt-0.5 text-xs text-brand-muted">{apt.reason || 'Consultation'}</p>
                    </div>
                    <StatusBadge status={apt.status} />
                  </div>
                  <div className="mt-2 flex items-center gap-1.5 text-xs text-brand-muted">
                    <Clock size={11} />
                    <span>{formatDate(apt.start_time)} · {formatTime(apt.start_time)}</span>
                  </div>
                </Link>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <Calendar size={32} className="mb-2 text-brand-border" />
              <p className="text-sm text-brand-muted">No upcoming appointments</p>
            </div>
          )}
        </div>
      </div>

      {/* Bottom Row — Today's Appointments + Reminders */}
      <div className="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-3">
        {/* Today's appointments — spans 2 cols */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm xl:col-span-2">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Clock size={16} className="text-brand-primary" />
              Today&apos;s Schedule
            </h2>
            <span className="rounded-full bg-brand-primary/10 px-2.5 py-1 text-xs font-semibold text-brand-primary">
              {todays_appointments.length} appointments
            </span>
          </div>
          {todays_appointments.length > 0 ? (
            <div className="divide-y divide-brand-border">
              {todays_appointments.map((apt) => (
                <Link
                  key={apt.id}
                  href={`/appointments/${apt.id}`}
                  className="-mx-2 flex items-center gap-3 rounded-lg px-2 py-3 transition-colors hover:bg-brand-surface"
                >
                  <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary/10">
                    <span className="text-xs font-semibold text-brand-primary">
                      {initials(apt.patient_name)}
                    </span>
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                    <p className="mt-0.5 truncate text-xs text-brand-muted">{apt.reason || 'General consultation'}</p>
                  </div>
                  <div className="flex-shrink-0 text-right">
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
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <CalendarCheck size={32} className="mb-2 text-brand-border" />
              <p className="text-sm text-brand-muted">No appointments scheduled for today</p>
            </div>
          )}
        </div>

        {/* Reminders */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Bell size={16} className="text-brand-primary" />
              Reminders
            </h2>
            {reminders.length > 0 && (
              <span className="rounded-full bg-brand-warning/10 px-2 py-0.5 text-xs font-semibold text-brand-warning">
                {reminders.length} pending
              </span>
            )}
          </div>
          {reminders.length > 0 ? (
            <div className="space-y-3">
              {reminders.map((apt) => (
                <div
                  key={apt.id}
                  className="rounded-lg border border-brand-border bg-brand-surface/50 p-3"
                >
                  <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                  <p className="mt-0.5 text-xs text-brand-muted">
                    Unconfirmed · {formatTime(apt.start_time)}
                  </p>
                  <div className="mt-2 flex gap-3">
                    <a
                      href={`tel:${apt.patient_phone}`}
                      className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark"
                    >
                      <Phone size={11} /> Call
                    </a>
                    <Link
                      href={`/appointments/${apt.id}`}
                      className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark"
                    >
                      <MessageCircle size={11} /> View
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <Bell size={32} className="mb-2 text-brand-border" />
              <p className="text-sm text-brand-muted">All caught up — no pending reminders</p>
            </div>
          )}
        </div>
      </div>

      {/* Patients Table */}
      {recent_patients.length > 0 && (
        <div className="mt-6 rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <div>
              <h2 className="text-base font-semibold text-brand-ink">Recent Patients</h2>
              <p className="mt-0.5 text-xs text-brand-muted">Latest patients registered in the system</p>
            </div>
            <Link
              href="/patients"
              className="inline-flex items-center gap-1 rounded-lg border border-brand-border px-3 py-1.5 text-xs font-medium text-brand-muted transition-colors hover:bg-brand-surface hover:text-brand-ink"
            >
              All patients <ArrowUpRight size={12} />
            </Link>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-brand-border">
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">Patient</th>
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">Phone</th>
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">Email</th>
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">Appointments</th>
                  <th className="pb-3 text-xs font-semibold uppercase tracking-wider text-brand-muted">Last Visit</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-brand-border">
                {recent_patients.map((p) => (
                  <tr key={p.id} className="transition-colors hover:bg-brand-surface/50">
                    <td className="py-3 pr-4">
                      <Link href={`/patients/${p.id}`} className="flex items-center gap-3">
                        <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary/10">
                          <span className="text-[11px] font-semibold text-brand-primary">
                            {initials(p.name)}
                          </span>
                        </div>
                        <span className="font-medium text-brand-ink hover:text-brand-primary">{p.name}</span>
                      </Link>
                    </td>
                    <td className="py-3 pr-4 text-brand-muted">{p.phone}</td>
                    <td className="py-3 pr-4 text-brand-muted">{p.email || '—'}</td>
                    <td className="py-3 pr-4">
                      <span className="inline-flex items-center rounded-full bg-brand-primary/10 px-2 py-0.5 text-xs font-semibold text-brand-primary">
                        {p.appointment_count}
                      </span>
                    </td>
                    <td className="py-3 text-brand-muted">
                      {p.last_appointment_at ? formatDate(p.last_appointment_at) : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </DashboardLayout>
  )
}

/* ── Helpers ──────────────────────────────────── */

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

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })
}

/* ── Sub-components ──────────────────────────── */

function ChartTooltip({ active, payload, label }) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-lg border border-brand-border bg-white px-3 py-2 shadow-lg">
      <p className="mb-1 text-xs font-semibold text-brand-ink">{label}</p>
      {payload.map((entry) => (
        <div key={entry.name} className="flex items-center gap-2 text-xs">
          <span className="h-2 w-2 rounded-full" style={{ backgroundColor: entry.color }} />
          <span className="text-brand-muted">{entry.name}:</span>
          <span className="font-semibold text-brand-ink">{entry.value}</span>
        </div>
      ))}
    </div>
  )
}

function StatCard({ title, value, subtitle, icon: Icon, accent }) {
  const accentMap = {
    primary: {
      icon: 'bg-brand-primary/10 text-brand-primary',
      value: 'text-brand-ink',
    },
    success: {
      icon: 'bg-brand-success/10 text-brand-success',
      value: 'text-brand-ink',
    },
    warning: {
      icon: 'bg-brand-warning/10 text-brand-warning',
      value: 'text-brand-ink',
    },
    info: {
      icon: 'bg-sky-50 text-sky-600',
      value: 'text-brand-ink',
    },
  }
  const styles = accentMap[accent] || accentMap.primary

  return (
    <div className="rounded-xl border border-brand-border bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between">
        <div className={`flex h-10 w-10 items-center justify-center rounded-lg ${styles.icon}`}>
          <Icon size={20} />
        </div>
        <TrendingUp size={14} className="text-brand-success" />
      </div>
      <p className={`mt-4 text-2xl font-bold tracking-tight ${styles.value}`}>{value}</p>
      <p className="mt-0.5 text-sm font-medium text-brand-ink">{title}</p>
      <p className="mt-1 text-xs text-brand-muted">{subtitle}</p>
    </div>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`inline-flex flex-shrink-0 items-center rounded-full px-2.5 py-1 text-[11px] font-medium capitalize ${STATUS_STYLES[status] || 'border border-brand-muted/15 bg-brand-surface text-brand-muted'}`}>
      {status?.replace('_', ' ')}
    </span>
  )
}
