import React, { useState, useEffect, useMemo } from 'react'
import { Link, router } from '@inertiajs/react'
import {
  Users, CalendarCheck, UserPlus, Activity,
  Clock, Bell, Phone, MessageCircle, ArrowUpRight,
  TrendingUp, Calendar, Plus, XCircle, RefreshCw
} from 'lucide-react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend
} from 'recharts'
import DashboardLayout from '../layouts/DashboardLayout'
import AppointmentFormModal from '../components/AppointmentFormModal'
import CancelAppointmentModal from '../components/CancelAppointmentModal'
import { useLanguage } from '../lib/LanguageContext'

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

// Map server day abbreviations (Mon, Tue…) to translation keys
const DAY_KEY_MAP = { Mon: 'day_mon', Tue: 'day_tue', Wed: 'day_wed', Thu: 'day_thu', Fri: 'day_fri', Sat: 'day_sat', Sun: 'day_sun' }

export default function Dashboard({
  stats,
  todays_appointments = [],
  upcoming_appointments = [],
  weekly_chart = [],
  recent_patients = [],
  reminders = [],
  patients = [],
  checkout_ready: checkoutReady = [],
  asap_list: asapList = [],
  intake_outstanding: intakeOutstanding = [],
  no_shows_to_rebook: noShows = [],
  lab_cases_due: labCases = [],
  unscheduled_treatment: unscheduledTx = [],
}) {
  const { t, language } = useLanguage()

  const greeting = useMemo(() => {
    const hour = new Date().getHours()
    if (hour < 12) return t('greeting_morning')
    if (hour < 17) return t('greeting_afternoon')
    return t('greeting_evening')
  }, [t])

  // Translate chart day labels
  const localChart = useMemo(() =>
    weekly_chart.map((d) => ({ ...d, day: t(DAY_KEY_MAP[d.day]) || d.day })),
    [weekly_chart, t]
  )

  // ── Modal state ──────────────────────────────────────────────
  const [createOpen, setCreateOpen] = useState(false)
  const [editAppointment, setEditAppointment] = useState(null)
  const [cancelAppointment, setCancelAppointment] = useState(null)

  // Poll for fresh data every 15 seconds
  useEffect(() => {
    const POLL_INTERVAL = 15_000
    const timer = setInterval(() => {
      router.reload({
        only: [
          'stats', 'todays_appointments', 'upcoming_appointments',
          'weekly_chart', 'recent_patients', 'reminders', 'patients',
          'checkout_ready',
        ],
        preserveState: true,
        preserveScroll: true,
      })
    }, POLL_INTERVAL)
    return () => clearInterval(timer)
  }, [])

  const dateFmt = language === 'af' ? 'af-ZA' : 'en-ZA'

  const [showQuickStart, setShowQuickStart] = useState(() => {
    try { return localStorage.getItem('ivory_quickstart_dismissed') !== '1' } catch { return false }
  })
  const dismissQuickStart = () => {
    try { localStorage.setItem('ivory_quickstart_dismissed', '1') } catch { /* ignore */ }
    setShowQuickStart(false)
  }

  return (
    <DashboardLayout>
      {/* Header */}
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-brand-ink">
            {greeting} 👋
          </h1>
          <p className="mt-1 text-sm text-brand-muted">{t('dashboard_subtitle')}</p>
        </div>
        <button
          onClick={() => setCreateOpen(true)}
          className="inline-flex items-center gap-2 rounded-xl bg-brand-primary px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-brand-primary-dark"
        >
          <Plus size={16} />
          {t('new_appointment')}
        </button>
      </div>

      {/* New-staff onboarding — dismissible quick-start with the core daily actions */}
      {showQuickStart && (
        <div className="mb-6 rounded-xl border border-brand-primary/30 bg-brand-primary/5 p-4">
          <div className="mb-2 flex items-center justify-between">
            <p className="text-sm font-semibold text-brand-ink">New here? Quick start</p>
            <button type="button" onClick={dismissQuickStart} className="rounded-md px-2 py-1 text-xs text-brand-muted hover:bg-white hover:text-brand-ink">Hide</button>
          </div>
          <div className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-3 lg:grid-cols-5">
            {[
              { label: 'Book an appointment', href: '/diary' },
              { label: 'Add a patient', href: '/patients' },
              { label: 'Take a payment', href: '/invoices' },
              { label: 'Work recalls', href: '/recalls' },
              { label: 'Statements', href: '/accounts' },
            ].map((a) => (
              <Link key={a.href} href={a.href} className="rounded-lg border border-brand-border bg-white px-3 py-2 font-medium text-brand-ink transition hover:border-brand-primary hover:text-brand-primary">
                {a.label} →
              </Link>
            ))}
          </div>
        </div>
      )}

      {/* N4 — Real-time checkout banners. Patient in chair → draft estimate
          is ready to hand them at the desk before they leave. */}
      {checkoutReady.length > 0 && (
        <div className="mb-6 space-y-2">
          {checkoutReady.map((c) => (
            <a key={c.appointment_id}
              href={`/estimates/${c.estimate_id}`}
              className="group flex items-center justify-between rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 hover:bg-amber-100 transition-colors">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-amber-800">
                  {c.status === 'completed' ? 'Estimate ready for checkout' : 'Estimate ready while in chair'}
                </p>
                <p className="text-sm font-medium text-brand-ink">
                  {c.patient_name} · {c.estimate_number} · <strong>R{c.estimate_total.toLocaleString('en-ZA', { minimumFractionDigits: 2 })}</strong>
                </p>
              </div>
              <span className="rounded-lg bg-white px-3 py-1.5 text-xs font-semibold text-amber-700 group-hover:bg-amber-700 group-hover:text-white">
                Open estimate →
              </span>
            </a>
          ))}
        </div>
      )}

      {/* Patient flow today — live arrivals board (Waiting → In chair → Ready for checkout) */}
      {(() => {
        const groups = [
          { key: 'waiting',  label: 'Waiting',            statuses: ['arrived'],         dot: 'bg-amber-400' },
          { key: 'inchair',  label: 'In chair',           statuses: ['in_consultation'], dot: 'bg-blue-500' },
          { key: 'checkout', label: 'Ready for checkout', statuses: ['completed'],        dot: 'bg-purple-500' },
        ]
        const fmt = (s) => new Date(s).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })
        const data = groups.map((g) => ({ ...g, items: todays_appointments.filter((a) => g.statuses.includes(a.status)) }))
        if (!data.some((g) => g.items.length > 0)) return null
        return (
          <div className="mb-8">
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-brand-muted">Patient flow today</p>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              {data.map((g) => (
                <div key={g.key} className="rounded-xl border border-brand-border bg-white p-4">
                  <div className="mb-2 flex items-center gap-2">
                    <span className={`h-2 w-2 rounded-full ${g.dot}`} />
                    <p className="text-sm font-semibold text-brand-ink">{g.label}</p>
                    <span className="ml-auto rounded-full bg-brand-surface px-2 py-0.5 text-xs font-medium text-brand-muted">{g.items.length}</span>
                  </div>
                  {g.items.length === 0
                    ? <p className="text-xs text-brand-muted">—</p>
                    : <ul className="space-y-1">{g.items.map((a) => (
                        <li key={a.id} className="flex items-center justify-between text-sm">
                          <span className="truncate text-brand-ink">{a.patient_name}</span>
                          <span className="ml-2 flex-shrink-0 text-xs text-brand-muted">{fmt(a.start_time)}</span>
                        </li>
                      ))}</ul>}
                </div>
              ))}
            </div>
          </div>
        )
      })()}

      {/* ASAP — patients who want an earlier slot; offer when a gap opens (cut empty chairs) */}
      {asapList.length > 0 && (
        <div className="mb-8 rounded-xl border border-brand-border bg-white p-4">
          <div className="mb-1 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-emerald-500" />
            <p className="text-sm font-semibold text-brand-ink">Wants an earlier slot</p>
            <span className="ml-auto rounded-full bg-brand-surface px-2 py-0.5 text-xs font-medium text-brand-muted">{asapList.length}</span>
          </div>
          <p className="mb-2 text-xs text-brand-muted">A slot opened up? Offer it to these patients first.</p>
          <ul className="divide-y divide-brand-border/40">
            {asapList.map((a) => (
              <li key={a.id} className="flex items-center justify-between py-1.5 text-sm">
                <span className="truncate text-brand-ink">{a.patient_name}<span className="ml-1 text-xs text-brand-muted">· currently {new Date(a.start_time).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })}</span></span>
                {a.patient_phone && (
                  <span className="ml-2 flex flex-shrink-0 items-center gap-3">
                    <a href={`https://wa.me/${a.patient_phone.replace(/\D/g, '')}?text=${encodeURIComponent(`Hi ${a.patient_name}, an earlier appointment slot has just opened up at Dr Chalita le Roux — would you like it? Let me know and I'll book it for you.`)}`}
                      target="_blank" rel="noopener noreferrer" title="Send a WhatsApp offering the earlier slot"
                      className="text-xs font-medium text-emerald-700 hover:underline">WhatsApp offer</a>
                    <a href={`tel:${a.patient_phone.replace(/\s/g, '')}`} className="text-xs font-medium text-brand-primary hover:underline">Call</a>
                  </span>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Intake outstanding before visit — chase/resend the form so the chart is ready */}
      {intakeOutstanding.length > 0 && (
        <div className="mb-8 rounded-xl border border-amber-200 bg-amber-50/60 p-4">
          <div className="mb-1 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-amber-500" />
            <p className="text-sm font-semibold text-brand-ink">Intake outstanding before visit</p>
            <span className="ml-auto rounded-full bg-white px-2 py-0.5 text-xs font-medium text-amber-700">{intakeOutstanding.length}</span>
          </div>
          <p className="mb-2 text-xs text-brand-muted">These patients have an upcoming visit but haven't completed their intake form.</p>
          <ul className="divide-y divide-amber-200/60">
            {intakeOutstanding.map((p) => (
              <li key={p.patient_id} className="flex items-center justify-between py-1.5 text-sm">
                <span className="truncate text-brand-ink">{p.patient_name}<span className="ml-1 text-xs text-brand-muted">· {new Date(p.start_time).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })} · {p.intake_status}</span></span>
                <button type="button" onClick={() => router.post(`/patients/${p.patient_id}/send-intake`, {}, { preserveScroll: true })} className="ml-2 flex-shrink-0 rounded-lg border border-amber-300 bg-white px-2.5 py-1 text-xs font-medium text-amber-700 hover:bg-amber-100">Send intake</button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Recent no-shows — call/message to rebook (speed recovers the revenue) */}
      {noShows.length > 0 && (
        <div className="mb-8 rounded-xl border border-rose-200 bg-rose-50/50 p-4">
          <div className="mb-1 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-rose-500" />
            <p className="text-sm font-semibold text-brand-ink">Recent no-shows — rebook them</p>
            <span className="ml-auto rounded-full bg-white px-2 py-0.5 text-xs font-medium text-rose-700">{noShows.length}</span>
          </div>
          <p className="mb-2 text-xs text-brand-muted">Reach out fast — most patients rebook with whoever responds first.</p>
          <ul className="divide-y divide-rose-200/60">
            {noShows.map((p) => (
              <li key={`${p.patient_id}-${p.start_time}`} className="flex items-center justify-between py-1.5 text-sm">
                <span className="truncate text-brand-ink">{p.patient_name}<span className="ml-1 text-xs text-brand-muted">· missed {new Date(p.start_time).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })}</span></span>
                <span className="ml-2 flex flex-shrink-0 items-center gap-3">
                  {p.patient_phone && <a href={`tel:${p.patient_phone.replace(/\s/g, '')}`} className="text-xs font-medium text-brand-primary hover:underline">Call</a>}
                  <Link href={`/patients/${p.patient_id}`} className="text-xs font-medium text-brand-primary hover:underline">Rebook →</Link>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Lab cases due back — book the seat/fit when the crown/bridge returns */}
      {labCases.length > 0 && (
        <div className="mb-8 rounded-xl border border-indigo-200 bg-indigo-50/50 p-4">
          <div className="mb-1 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-indigo-500" />
            <p className="text-sm font-semibold text-brand-ink">Lab cases due back</p>
            <span className="ml-auto rounded-full bg-white px-2 py-0.5 text-xs font-medium text-indigo-700">{labCases.length}</span>
          </div>
          <p className="mb-2 text-xs text-brand-muted">When these return from the lab, book the seat/fit appointment.</p>
          <ul className="divide-y divide-indigo-200/60">
            {labCases.map((c) => (
              <li key={c.item_id} className="flex items-center justify-between py-1.5 text-sm">
                <span className="truncate text-brand-ink">
                  {c.patient_id ? <Link href={`/patients/${c.patient_id}`} className="hover:underline">{c.patient_name}</Link> : c.patient_name}
                  <span className="ml-1 text-xs text-brand-muted">· {c.description}{c.tooth ? ` #${c.tooth}` : ''}{c.lab_name ? ` · ${c.lab_name}` : ''}</span>
                </span>
                <span className={`ml-2 flex-shrink-0 text-xs ${c.overdue ? 'font-semibold text-brand-danger' : 'text-brand-muted'}`}>
                  {c.overdue ? 'overdue · ' : 'due '}{new Date(c.due_on).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Accepted-but-unscheduled treatment — planned work with no future booking = recoverable production */}
      {unscheduledTx.length > 0 && (
        <div className="mb-8 rounded-xl border border-amber-200 bg-amber-50/50 p-4">
          <div className="mb-1 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-amber-500" />
            <p className="text-sm font-semibold text-brand-ink">Unscheduled treatment — rebook</p>
            <span className="ml-auto rounded-full bg-white px-2 py-0.5 text-xs font-medium text-amber-700">{unscheduledTx.length}</span>
          </div>
          <p className="mb-2 text-xs text-brand-muted">Planned treatment with no upcoming appointment — call/message to book it in.</p>
          <ul className="divide-y divide-amber-200/60">
            {unscheduledTx.map((u) => (
              <li key={u.patient_id} className="flex items-center justify-between py-1.5 text-sm">
                <span className="truncate text-brand-ink">
                  <Link href={`/patients/${u.patient_id}`} className="hover:underline">{u.patient_name}</Link>
                  <span className="ml-1 text-xs text-brand-muted">· {u.item_count} item{u.item_count === 1 ? '' : 's'}</span>
                </span>
                <span className="ml-2 flex-shrink-0 text-xs font-semibold text-amber-700">
                  R{Number(u.value || 0).toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Stat Cards */}
      <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard
          title={t('stat_total_patients')}
          value={stats?.total_patients ?? 0}
          subtitle={`${stats?.new_patients_month ?? 0} ${t('stat_new_this_month')}`}
          icon={Users}
          accent="primary"
        />
        <StatCard
          title={t('stat_todays_appointments')}
          value={stats?.todays_appointments ?? 0}
          subtitle={`${stats?.confirmed_today ?? 0} ${t('stat_confirmed')} · ${stats?.pending_confirmations ?? 0} ${t('stat_pending')}`}
          icon={CalendarCheck}
          accent="success"
        />
        <StatCard
          title={t('stat_new_patients')}
          value={stats?.new_patients_month ?? 0}
          subtitle={t('stat_this_month')}
          icon={UserPlus}
          accent="info"
        />
        <Link href="/accounts" className="block">
          <StatCard
            title="Outstanding"
            value={`R${(stats?.outstanding_balance ?? 0).toLocaleString('en-ZA', { maximumFractionDigits: 0 })}`}
            subtitle="owed across accounts →"
            icon={Activity}
            accent="warning"
          />
        </Link>
        <Link href="/estimates" className="block">
          <StatCard
            title="Estimate pipeline"
            value={`R${(stats?.estimates_pipeline ?? 0).toLocaleString('en-ZA', { maximumFractionDigits: 0 })}`}
            subtitle={`${stats?.estimates_awaiting ?? 0} awaiting acceptance →`}
            icon={TrendingUp}
            accent="info"
          />
        </Link>
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
        {/* Chart — spans 2 cols */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm xl:col-span-2">
          <div className="mb-6 flex items-center justify-between">
            <div>
              <h2 className="text-base font-semibold text-brand-ink">{t('chart_title')}</h2>
              <p className="mt-0.5 text-xs text-brand-muted">{t('chart_subtitle')}</p>
            </div>
            <Link
              href="/appointments"
              className="inline-flex items-center gap-1 rounded-lg border border-brand-border px-3 py-1.5 text-xs font-medium text-brand-muted transition-colors hover:bg-brand-surface hover:text-brand-ink"
            >
              {t('view_all')} <ArrowUpRight size={12} />
            </Link>
          </div>
          <div className="h-[280px]">
            {localChart.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={localChart} barGap={4} barSize={18}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" vertical={false} />
                  <XAxis dataKey="day" axisLine={false} tickLine={false} tick={{ fill: '#64748B', fontSize: 12, fontWeight: 500 }} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fill: '#64748B', fontSize: 12 }} allowDecimals={false} />
                  <Tooltip content={<ChartTooltip />} cursor={{ fill: 'rgba(14,159,159,0.04)' }} />
                  <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: 12, paddingTop: 12 }} />
                  <Bar dataKey="confirmed" name={t('chart_confirmed')} fill={CHART_COLORS.confirmed} radius={[4, 4, 0, 0]} />
                  <Bar dataKey="scheduled" name={t('chart_scheduled')} fill={CHART_COLORS.scheduled} radius={[4, 4, 0, 0]} />
                  <Bar dataKey="completed" name={t('chart_completed')} fill={CHART_COLORS.completed} radius={[4, 4, 0, 0]} />
                  <Bar dataKey="cancelled" name={t('chart_cancelled')} fill={CHART_COLORS.cancelled} radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-brand-muted">
                {t('no_appointment_data')}
              </div>
            )}
          </div>
        </div>

        {/* Upcoming Appointments sidebar */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Calendar size={16} className="text-brand-primary" />
              {t('upcoming')}
            </h2>
            <Link href="/appointments" className="text-xs font-medium text-brand-primary transition-colors hover:text-brand-primary-dark">
              {t('see_all')} →
            </Link>
          </div>
          {upcoming_appointments.length > 0 ? (
            <div className="space-y-3">
              {upcoming_appointments.map((apt) => (
                <div key={apt.id} className="rounded-lg border border-brand-border p-3 transition-colors hover:bg-brand-surface">
                  <Link href={`/appointments/${apt.id}`} className="block">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                        <p className="mt-0.5 text-xs text-brand-muted">{apt.reason || t('consultation')}</p>
                      </div>
                      <StatusBadge status={apt.status} t={t} />
                    </div>
                    <div className="mt-2 flex items-center gap-1.5 text-xs text-brand-muted">
                      <Clock size={11} />
                      <span>{fmtDate(apt.start_time, dateFmt)} · {fmtTime(apt.start_time, dateFmt)}</span>
                    </div>
                  </Link>
                  {apt.status !== 'cancelled' && apt.status !== 'completed' && (
                    <div className="mt-2 flex gap-2 border-t border-brand-border/50 pt-2">
                      <button onClick={() => setEditAppointment(apt)} className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark">
                        <RefreshCw size={11} /> {t('reschedule_action')}
                      </button>
                      <button onClick={() => setCancelAppointment(apt)} className="flex items-center gap-1 text-xs font-medium text-brand-danger hover:text-red-700">
                        <XCircle size={11} /> {t('cancel_action')}
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <Calendar size={32} className="mb-2 text-brand-border" />
              <p className="text-sm text-brand-muted">{t('no_upcoming')}</p>
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
              {t('todays_schedule')}
            </h2>
            <span className="rounded-full bg-brand-primary/10 px-2.5 py-1 text-xs font-semibold text-brand-primary">
              {todays_appointments.length} {t('appointments_count')}
            </span>
          </div>
          {todays_appointments.length > 0 ? (
            <div className="divide-y divide-brand-border">
              {todays_appointments.map((apt) => (
                <div key={apt.id} className="-mx-2 flex items-center gap-3 rounded-lg px-2 py-3 transition-colors hover:bg-brand-surface">
                  <Link href={`/appointments/${apt.id}`} className="flex min-w-0 flex-1 items-center gap-3">
                    <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary/10">
                      <span className="text-xs font-semibold text-brand-primary">{initials(apt.patient_name)}</span>
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                      <p className="mt-0.5 truncate text-xs text-brand-muted">{apt.reason || t('general_consultation')}</p>
                    </div>
                    <div className="flex-shrink-0 text-right">
                      <p className="text-xs font-semibold text-brand-ink">{fmtTime(apt.start_time, dateFmt)}</p>
                      <p className="text-[11px] text-brand-muted">{fmtTime(apt.end_time, dateFmt)}</p>
                    </div>
                  </Link>
                  <StatusBadge status={apt.status} t={t} />
                  {apt.status !== 'cancelled' && apt.status !== 'completed' && (
                    <div className="flex flex-shrink-0 gap-1">
                      <button onClick={() => setEditAppointment(apt)} title={t('reschedule_action')} className="rounded-lg p-1.5 text-brand-muted transition-colors hover:bg-brand-primary/10 hover:text-brand-primary">
                        <RefreshCw size={14} />
                      </button>
                      <button onClick={() => setCancelAppointment(apt)} title={t('cancel_action')} className="rounded-lg p-1.5 text-brand-muted transition-colors hover:bg-brand-danger/10 hover:text-brand-danger">
                        <XCircle size={14} />
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <CalendarCheck size={32} className="mb-2 text-brand-border" />
              <p className="text-sm text-brand-muted">{t('no_appointments_today')}</p>
            </div>
          )}
        </div>

        {/* Reminders */}
        <div className="rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="flex items-center gap-2 text-base font-semibold text-brand-ink">
              <Bell size={16} className="text-brand-primary" />
              {t('reminders')}
            </h2>
            {reminders.length > 0 && (
              <span className="rounded-full bg-brand-warning/10 px-2 py-0.5 text-xs font-semibold text-brand-warning">
                {reminders.length} {t('pending_label')}
              </span>
            )}
          </div>
          {reminders.length > 0 ? (
            <div className="space-y-3">
              {reminders.map((apt) => (
                <div key={apt.id} className="rounded-lg border border-brand-border bg-brand-surface/50 p-3">
                  <p className="truncate text-sm font-medium text-brand-ink">{apt.patient_name}</p>
                  <p className="mt-0.5 text-xs text-brand-muted">{t('unconfirmed')} · {fmtTime(apt.start_time, dateFmt)}</p>
                  <div className="mt-2 flex gap-3">
                    <a href={`tel:${apt.patient_phone}`} className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark">
                      <Phone size={11} /> {t('call')}
                    </a>
                    <Link href={`/appointments/${apt.id}`} className="flex items-center gap-1 text-xs font-medium text-brand-primary hover:text-brand-primary-dark">
                      <MessageCircle size={11} /> {t('view')}
                    </Link>
                    <button onClick={() => setCancelAppointment(apt)} className="flex items-center gap-1 text-xs font-medium text-brand-danger hover:text-red-700">
                      <XCircle size={11} /> {t('cancel_action')}
                    </button>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <Bell size={32} className="mb-2 text-brand-border" />
              <p className="text-sm text-brand-muted">{t('all_caught_up')}</p>
            </div>
          )}
        </div>
      </div>

      {/* Patients Table */}
      {recent_patients.length > 0 && (
        <div className="mt-6 rounded-xl border border-brand-border bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <div>
              <h2 className="text-base font-semibold text-brand-ink">{t('recent_patients')}</h2>
              <p className="mt-0.5 text-xs text-brand-muted">{t('recent_patients_subtitle')}</p>
            </div>
            <Link href="/patients" className="inline-flex items-center gap-1 rounded-lg border border-brand-border px-3 py-1.5 text-xs font-medium text-brand-muted transition-colors hover:bg-brand-surface hover:text-brand-ink">
              {t('all_patients')} <ArrowUpRight size={12} />
            </Link>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-brand-border">
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('th_patient')}</th>
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('th_phone')}</th>
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('th_email')}</th>
                  <th className="pb-3 pr-4 text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('th_appointments')}</th>
                  <th className="pb-3 text-xs font-semibold uppercase tracking-wider text-brand-muted">{t('th_last_visit')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-brand-border">
                {recent_patients.map((p) => (
                  <tr key={p.id} className="transition-colors hover:bg-brand-surface/50">
                    <td className="py-3 pr-4">
                      <Link href={`/patients/${p.id}`} className="flex items-center gap-3">
                        <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary/10">
                          <span className="text-[11px] font-semibold text-brand-primary">{initials(p.name)}</span>
                        </div>
                        <span className="font-medium text-brand-ink hover:text-brand-primary">{p.name}</span>
                      </Link>
                    </td>
                    <td className="py-3 pr-4 text-brand-muted">{p.phone}</td>
                    <td className="py-3 pr-4 text-brand-muted">{p.email || '—'}</td>
                    <td className="py-3 pr-4">
                      <span className="inline-flex items-center rounded-full bg-brand-primary/10 px-2 py-0.5 text-xs font-semibold text-brand-primary">{p.appointment_count}</span>
                    </td>
                    <td className="py-3 text-brand-muted">{p.last_appointment_at ? fmtDate(p.last_appointment_at, dateFmt) : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ── Modals ────────────────────────────────────────────── */}
      <AppointmentFormModal open={createOpen} onClose={() => setCreateOpen(false)} mode="create" patients={patients} />
      <AppointmentFormModal open={!!editAppointment} onClose={() => setEditAppointment(null)} mode="edit" appointment={editAppointment} />
      <CancelAppointmentModal open={!!cancelAppointment} onClose={() => setCancelAppointment(null)} appointment={cancelAppointment} />
    </DashboardLayout>
  )
}

/* ── Helpers ──────────────────────────────────── */

function initials(name = '') {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]?.toUpperCase() || '').join('') || '·'
}

function fmtTime(iso, locale = 'en-ZA') {
  return new Date(iso).toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' })
}

function fmtDate(iso, locale = 'en-ZA') {
  return new Date(iso).toLocaleDateString(locale, { day: 'numeric', month: 'short' })
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
    primary: { icon: 'bg-brand-primary/10 text-brand-primary', value: 'text-brand-ink' },
    success: { icon: 'bg-brand-success/10 text-brand-success', value: 'text-brand-ink' },
    warning: { icon: 'bg-brand-warning/10 text-brand-warning', value: 'text-brand-ink' },
    info:    { icon: 'bg-sky-50 text-sky-600', value: 'text-brand-ink' },
  }
  const styles = accentMap[accent] || accentMap.primary

  return (
    <div className="rounded-xl border border-brand-border bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between">
        <div className={`flex h-10 w-10 items-center justify-center rounded-lg ${styles.icon}`}><Icon size={20} /></div>
        <TrendingUp size={14} className="text-brand-success" />
      </div>
      <p className={`mt-4 text-2xl font-bold tracking-tight ${styles.value}`}>{value}</p>
      <p className="mt-0.5 text-sm font-medium text-brand-ink">{title}</p>
      <p className="mt-1 text-xs text-brand-muted">{subtitle}</p>
    </div>
  )
}

const STATUS_KEYS = {
  scheduled: 'status_scheduled', confirmed: 'status_confirmed', completed: 'status_completed',
  cancelled: 'status_cancelled', no_show: 'status_no_show', rescheduled: 'status_rescheduled',
}

function StatusBadge({ status, t }) {
  const label = t(STATUS_KEYS[status]) || status?.replace('_', ' ')
  return (
    <span className={`inline-flex flex-shrink-0 items-center rounded-full px-2.5 py-1 text-[11px] font-medium capitalize ${STATUS_STYLES[status] || 'border border-brand-muted/15 bg-brand-surface text-brand-muted'}`}>
      {label}
    </span>
  )
}
