import React from 'react'
import DashboardLayout from '../layouts/DashboardLayout'
import { useLanguage } from '../lib/LanguageContext'

export default function Analytics({ cancellation_stats, booking_stats, channel_stats }) {
  const { t } = useLanguage()

  return (
    <DashboardLayout>
      <div className="mb-8">
        <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
          {t('ana_badge')}
        </span>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">{t('ana_title')}</h1>
        <p className="mt-2 text-sm leading-6 text-brand-muted">{t('ana_subtitle')}</p>
      </div>

      {/* Booking Stats */}
      <div className="mb-5 rounded-xl border border-brand-accent/75 bg-white p-6 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <h2 className="mb-5 text-base font-semibold text-brand-ink">{t('ana_booking_title')}</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
          <StatBlock label={t('ana_total_bookings')} value={booking_stats?.total_bookings_30d ?? 0} />
          <StatBlock label={t('ana_completed')}      value={booking_stats?.completed_30d ?? 0}      color="emerald" />
          <StatBlock label={t('ana_no_shows')}       value={booking_stats?.no_shows_30d ?? 0}       color="red" />
          <StatBlock label={t('ana_conversion')}     value={`${booking_stats?.conversion_rate ?? 0}%`} color="taupe" />
        </div>
      </div>

      {/* Channel Stats */}
      <div className="mb-5 rounded-xl border border-brand-accent/75 bg-white p-6 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <h2 className="mb-5 text-base font-semibold text-brand-ink">{t('ana_channel_title')}</h2>
        <div className="grid grid-cols-2 gap-5">
          <div className="rounded-xl border border-brand-success/15 bg-brand-success/10 p-6 text-center">
            <p className="text-3xl font-bold text-brand-success">{channel_stats?.whatsapp ?? 0}</p>
            <p className="mt-1 text-sm font-medium text-brand-ink">{t('ana_whatsapp_conv')}</p>
            <p className="mt-0.5 text-xs text-brand-muted">{channel_stats?.whatsapp_pct ?? 0}{t('ana_pct_total')}</p>
          </div>
          <div className="rounded-xl border border-brand-primary/15 bg-brand-primary/10 p-6 text-center">
            <p className="text-3xl font-bold text-brand-primary">{channel_stats?.voice ?? 0}</p>
            <p className="mt-1 text-sm font-medium text-brand-ink">{t('ana_voice_conv')}</p>
            <p className="mt-0.5 text-xs text-brand-muted">{channel_stats?.voice_pct ?? 0}{t('ana_pct_total')}</p>
          </div>
        </div>
      </div>

      {/* Cancellation Reasons */}
      <div className="rounded-xl border border-brand-accent/75 bg-white p-6 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <h2 className="mb-2 text-base font-semibold text-brand-ink">{t('ana_cancel_title')}</h2>
        <div className="flex items-center gap-4 mb-5">
          <p className="text-sm text-brand-muted">
            {t('ana_total_cancelled')} <span className="font-semibold text-brand-danger">{cancellation_stats?.total_cancelled ?? 0}</span>
          </p>
          <p className="text-sm text-brand-muted">
            {t('ana_rate')} <span className="font-semibold text-brand-danger">{cancellation_stats?.cancellation_rate ?? 0}%</span>
          </p>
        </div>
        <div className="space-y-3">
          {cancellation_stats?.by_reason?.map((item) => {
            const maxCount = Math.max(...(cancellation_stats.by_reason.map(r => r.count) || [1]), 1)
            const pct = maxCount > 0 ? (item.count / maxCount) * 100 : 0
            return (
              <div key={item.category}>
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-sm font-medium capitalize text-brand-ink">{item.category}</span>
                  <span className="text-sm text-brand-muted">{item.count}</span>
                </div>
                <div className="h-2 w-full rounded-full bg-brand-surface/55">
                  <div
                    className="h-2 rounded-full bg-brand-primary transition-all"
                    style={{ width: `${pct}%` }}
                  />
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </DashboardLayout>
  )
}

function StatBlock({ label, value, color = 'brown' }) {
  const colorMap = {
    brown:   'text-brand-primary',
    taupe:   'text-brand-secondary',
    emerald: 'text-brand-success',
    red:     'text-brand-danger',
  }
  return (
    <div className="text-center">
      <p className={`text-3xl font-bold ${colorMap[color]}`}>{value}</p>
      <p className="mt-1 text-xs uppercase tracking-wide text-brand-muted">{label}</p>
    </div>
  )
}
