import React from 'react'
import {
  ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid,
  PieChart, Pie, Cell, Legend, LineChart, Line,
} from 'recharts'
import DashboardLayout from '../layouts/DashboardLayout'
import { useLanguage } from '../lib/LanguageContext'

// Brand palette matched to Tailwind tokens
const COLORS = {
  primary:   '#2E7D9B',
  success:   '#16a34a',
  warning:   '#d97706',
  danger:    '#dc2626',
  muted:     '#9ca3af',
  secondary: '#6b7280',
}

const STATUS_COLORS = {
  scheduled:   COLORS.primary,
  confirmed:   COLORS.success,
  completed:   '#6366f1',
  cancelled:   COLORS.danger,
  no_show:     COLORS.muted,
  rescheduled: COLORS.warning,
  pending_confirmation: '#f97316',
}

const CustomTooltip = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-lg border border-brand-border bg-white px-3 py-2 shadow-md text-xs">
      {label && <p className="mb-1 font-semibold text-brand-ink">{label}</p>}
      {payload.map((p, i) => (
        <p key={i} style={{ color: p.color || p.fill }} className="font-medium">
          {p.name}: {p.value}
        </p>
      ))}
    </div>
  )
}

export default function Analytics({
  cancellation_stats,
  booking_stats,
  channel_stats,
  daily_bookings = [],
  status_distribution = [],
}) {
  const { t } = useLanguage()

  const channelData = [
    { name: 'WhatsApp', value: channel_stats?.whatsapp ?? 0, fill: COLORS.success },
    { name: 'Voice',    value: channel_stats?.voice    ?? 0, fill: COLORS.primary },
  ]

  return (
    <DashboardLayout>
      <div className="mb-8">
        <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
          {t('ana_badge')}
        </span>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">{t('ana_title')}</h1>
        <p className="mt-2 text-sm leading-6 text-brand-muted">{t('ana_subtitle')}</p>
      </div>

      {/* ── KPI row ──────────────────────────────────────────────── */}
      <div className="mb-6 grid grid-cols-2 gap-4 md:grid-cols-4">
        <KpiCard
          label={t('ana_total_bookings')}
          value={booking_stats?.total_bookings_30d ?? 0}
          color="text-brand-primary"
          bg="bg-brand-primary/10"
        />
        <KpiCard
          label={t('ana_completed')}
          value={booking_stats?.completed_30d ?? 0}
          color="text-brand-success"
          bg="bg-brand-success/10"
        />
        <KpiCard
          label={t('ana_no_shows')}
          value={booking_stats?.no_shows_30d ?? 0}
          color="text-brand-danger"
          bg="bg-brand-danger/10"
        />
        <KpiCard
          label={t('ana_conversion')}
          value={`${booking_stats?.conversion_rate ?? 0}%`}
          color="text-brand-primary"
          bg="bg-brand-primary/10"
        />
      </div>

      {/* ── Daily bookings bar chart ─────────────────────────────── */}
      <div className="mb-5 rounded-xl border border-brand-accent/75 bg-white p-6 shadow-sm">
        <h2 className="mb-1 text-base font-semibold text-brand-ink">Bookings — last 30 days</h2>
        <p className="mb-4 text-xs text-brand-muted">New appointments created per day</p>
        {daily_bookings.length > 0 ? (
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={daily_bookings} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" vertical={false} />
              <XAxis
                dataKey="date"
                tick={{ fontSize: 10, fill: '#9ca3af' }}
                tickLine={false}
                axisLine={false}
                interval={4}
              />
              <YAxis
                tick={{ fontSize: 10, fill: '#9ca3af' }}
                tickLine={false}
                axisLine={false}
                allowDecimals={false}
              />
              <Tooltip content={<CustomTooltip />} cursor={{ fill: '#f3f4f6' }} />
              <Bar dataKey="count" name="Bookings" fill={COLORS.primary} radius={[4, 4, 0, 0]} maxBarSize={28} />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <EmptyChart />
        )}
      </div>

      {/* ── Status distribution + Channel split ─────────────────── */}
      <div className="mb-5 grid grid-cols-1 gap-5 lg:grid-cols-2">
        {/* Status donut */}
        <div className="rounded-xl border border-brand-accent/75 bg-white p-6 shadow-sm">
          <h2 className="mb-1 text-base font-semibold text-brand-ink">Appointment status</h2>
          <p className="mb-4 text-xs text-brand-muted">All-time breakdown by status</p>
          {status_distribution.length > 0 ? (
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie
                  data={status_distribution}
                  dataKey="value"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={90}
                  paddingAngle={3}
                >
                  {status_distribution.map((entry, i) => {
                    const raw = entry.name.toLowerCase().replace(' ', '_')
                    return (
                      <Cell
                        key={i}
                        fill={STATUS_COLORS[raw] || Object.values(COLORS)[i % Object.values(COLORS).length]}
                      />
                    )
                  })}
                </Pie>
                <Tooltip content={<CustomTooltip />} />
                <Legend
                  iconType="circle"
                  iconSize={8}
                  formatter={(v) => <span className="text-xs text-brand-muted">{v}</span>}
                />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <EmptyChart />
          )}
        </div>

        {/* Channel split bar */}
        <div className="rounded-xl border border-brand-accent/75 bg-white p-6 shadow-sm">
          <h2 className="mb-1 text-base font-semibold text-brand-ink">{t('ana_channel_title')}</h2>
          <p className="mb-4 text-xs text-brand-muted">Total conversations per channel</p>
          {channelData.some((d) => d.value > 0) ? (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={channelData} layout="vertical" margin={{ top: 4, right: 24, left: 20, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 10, fill: '#9ca3af' }} tickLine={false} axisLine={false} allowDecimals={false} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 12, fill: '#374151' }} tickLine={false} axisLine={false} width={68} />
                <Tooltip content={<CustomTooltip />} cursor={{ fill: '#f3f4f6' }} />
                <Bar dataKey="value" name="Conversations" radius={[0, 4, 4, 0]} maxBarSize={32}>
                  {channelData.map((entry, i) => (
                    <Cell key={i} fill={entry.fill} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <EmptyChart />
          )}
        </div>
      </div>

      {/* ── Cancellation reasons ─────────────────────────────────── */}
      <div className="rounded-xl border border-brand-accent/75 bg-white p-6 shadow-sm">
        <div className="mb-4 flex items-center gap-4">
          <div>
            <h2 className="text-base font-semibold text-brand-ink">{t('ana_cancel_title')}</h2>
            <p className="mt-0.5 text-xs text-brand-muted">
              {t('ana_total_cancelled')}{' '}
              <span className="font-semibold text-brand-danger">{cancellation_stats?.total_cancelled ?? 0}</span>
              {'  '}·{'  '}
              {t('ana_rate')}{' '}
              <span className="font-semibold text-brand-danger">{cancellation_stats?.cancellation_rate ?? 0}%</span>
            </p>
          </div>
        </div>

        {(cancellation_stats?.by_reason?.length ?? 0) > 0 ? (
          <ResponsiveContainer width="100%" height={180}>
            <BarChart
              data={cancellation_stats.by_reason}
              layout="vertical"
              margin={{ top: 0, right: 24, left: 100, bottom: 0 }}
            >
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" horizontal={false} />
              <XAxis type="number" tick={{ fontSize: 10, fill: '#9ca3af' }} tickLine={false} axisLine={false} allowDecimals={false} />
              <YAxis
                type="category"
                dataKey="category"
                tick={{ fontSize: 11, fill: '#374151' }}
                tickLine={false}
                axisLine={false}
                width={96}
                tickFormatter={(v) => v.charAt(0).toUpperCase() + v.slice(1)}
              />
              <Tooltip content={<CustomTooltip />} cursor={{ fill: '#f3f4f6' }} />
              <Bar dataKey="count" name="Cases" fill={COLORS.danger} radius={[0, 4, 4, 0]} maxBarSize={20} />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <p className="py-8 text-center text-sm text-brand-muted">No cancellation data yet</p>
        )}
      </div>
    </DashboardLayout>
  )
}

function KpiCard({ label, value, color, bg }) {
  return (
    <div className="rounded-xl border border-brand-accent/75 bg-white p-5 shadow-sm">
      <div className={`mb-3 inline-flex rounded-lg px-3 py-2 text-xs font-semibold ${bg} ${color}`}>
        {label}
      </div>
      <p className={`text-3xl font-bold tracking-tight ${color}`}>{value}</p>
      <p className="mt-1 text-[11px] uppercase tracking-[0.18em] text-brand-muted">last 30 days</p>
    </div>
  )
}

function EmptyChart() {
  return (
    <div className="flex h-[220px] items-center justify-center rounded-xl bg-brand-surface/40">
      <p className="text-sm text-brand-muted">No data yet</p>
    </div>
  )
}
