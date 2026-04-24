import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  Globe, Clock, Bell, Palette, MapPin, Phone, Mail,
  Building2, CreditCard, ExternalLink, CheckCircle2, XCircle, Save,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { useLanguage } from '../lib/LanguageContext'

const TABS = [
  { key: 'practice', label: 'settings_tab_practice', labelAf: 'Praktyk-inligting', icon: Building2 },
  { key: 'hours',    label: 'settings_tab_hours',    labelAf: 'Kantoorure',        icon: Clock },
  { key: 'notifications', label: 'settings_tab_notifications', labelAf: 'Kennisgewings', icon: Bell },
  { key: 'appearance',    label: 'settings_tab_appearance',    labelAf: 'Voorkoms',       icon: Palette },
]

export default function Settings({ schedules, pricing, practice, notifications, ai_costs }) {
  const { t, language, setLanguage } = useLanguage()
  const [activeTab, setActiveTab] = useState('practice')

  return (
    <DashboardLayout>
      {/* Page header */}
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-1">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary/10">
            <Building2 size={20} className="text-brand-primary" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-brand-ink">{t('settings_title')}</h1>
        {ai_costs?.last_7_days && (
          <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm mb-4">
            <h2 className="text-sm font-semibold text-brand-ink mb-2">🤖 AI usage (last 7 days)</h2>
            <div className="grid grid-cols-3 gap-4 text-sm">
              <div><div className="text-gray-500">Calls</div><div className="text-lg font-semibold">{ai_costs.last_7_days.calls}</div></div>
              <div><div className="text-gray-500">Tokens</div><div className="text-lg font-semibold">{(ai_costs.last_7_days.input_tokens + ai_costs.last_7_days.output_tokens).toLocaleString()}</div></div>
              <div><div className="text-gray-500">Cost (USD)</div><div className="text-lg font-semibold">${Number(ai_costs.last_7_days.cost_usd).toFixed(4)}</div></div>
            </div>
            {ai_costs.today && (
              <div className="mt-3 text-xs text-gray-600">Today: {ai_costs.today.calls} call{ai_costs.today.calls === 1 ? '' : 's'}, ${Number(ai_costs.today.cost_usd).toFixed(4)}</div>
            )}
          </div>
        )}
            <p className="text-sm text-brand-muted">{t('settings_subtitle')}</p>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-brand-border mb-6">
        <nav className="flex gap-0" aria-label="Settings tabs">
          {TABS.map(({ key, label, icon: Icon }) => (
            <button
              key={key}
              onClick={() => setActiveTab(key)}
              className={`flex items-center gap-2 px-5 py-3 text-sm font-medium border-b-2 transition-colors ${
                activeTab === key
                  ? 'border-brand-primary text-brand-primary'
                  : 'border-transparent text-brand-muted hover:text-brand-ink hover:border-brand-border'
              }`}
            >
              <Icon size={16} />
              {t(label)}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab content */}
      <div className="max-w-4xl">
        {activeTab === 'practice' && <PracticeTab practice={practice} pricing={pricing} t={t} />}
        {activeTab === 'hours' && <HoursTab schedules={schedules} t={t} />}
        {activeTab === 'notifications' && <NotificationsTab notifications={notifications} t={t} />}
        {activeTab === 'appearance' && <AppearanceTab language={language} setLanguage={setLanguage} t={t} />}
      </div>
    </DashboardLayout>
  )
}

/* ── Practice Info Tab ──────────────────────────────────────────────── */
function PracticeTab({ practice, pricing, t }) {
  const [practiceForm, setPracticeForm] = useState({ ...practice })
  const [pricingForm, setPricingForm] = useState({ ...pricing })
  const [savingPractice, setSavingPractice] = useState(false)
  const [savingPricing, setSavingPricing] = useState(false)

  const savePractice = (e) => {
    e.preventDefault()
    setSavingPractice(true)
    router.patch('/settings/practice', { practice: practiceForm }, {
      preserveScroll: true,
      onSuccess: () => toast.success('Practice details saved'),
      onError: () => toast.error('Failed to save practice details'),
      onFinish: () => setSavingPractice(false),
    })
  }

  const savePricing = (e) => {
    e.preventDefault()
    setSavingPricing(true)
    router.patch('/settings/pricing', {
      pricing: {
        price_consultation: pricingForm.consultation,
        price_check_up:     pricingForm.check_up,
        price_cleaning:     pricingForm.cleaning,
      }
    }, {
      preserveScroll: true,
      onSuccess: () => toast.success('Pricing saved'),
      onError: () => toast.error('Failed to save pricing'),
      onFinish: () => setSavingPricing(false),
    })
  }

  const practiceField = (key, label, placeholder, icon) => (
    <div className="flex flex-col gap-1.5">
      <label className="text-xs font-semibold text-brand-muted uppercase tracking-wide">
        {icon && React.createElement(icon, { size: 12, className: 'inline mr-1 text-brand-muted' })}
        {label}
      </label>
      <input
        type="text"
        value={practiceForm[key] || ''}
        onChange={e => setPracticeForm(f => ({ ...f, [key]: e.target.value }))}
        placeholder={placeholder}
        className="h-9 rounded-lg border border-brand-border bg-brand-surface px-3 text-sm text-brand-ink focus:outline-none focus:ring-2 focus:ring-brand-primary/30 focus:border-brand-primary"
      />
    </div>
  )

  const pricingField = (key, label) => (
    <div className="flex items-center gap-3">
      <label className="w-36 text-sm font-medium text-brand-ink capitalize">{label}</label>
      <input
        type="text"
        value={pricingForm[key] || ''}
        onChange={e => setPricingForm(f => ({ ...f, [key]: e.target.value }))}
        placeholder="e.g. approximately R850"
        className="flex-1 h-9 rounded-lg border border-brand-border bg-brand-surface px-3 text-sm text-brand-ink focus:outline-none focus:ring-2 focus:ring-brand-primary/30 focus:border-brand-primary"
      />
    </div>
  )

  return (
    <div className="space-y-6">
      {/* Practice Details */}
      <Card
        icon={Building2}
        title={t('settings_practice_info')}
        subtitle={t('settings_practice_info_desc')}
      >
        <form onSubmit={savePractice} className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {practiceField('name', t('settings_practice_name'), 'Practice name')}
            {practiceField('phone', t('settings_practice_phone'), '+27 XX XXX XXXX', Phone)}
            {practiceField('email', t('settings_practice_email'), 'reception@example.com', Mail)}
            {practiceField('emergency_phone', 'Emergency phone', '071 XXX XXXX', Phone)}
            {practiceField('address_line1', 'Address line 1', 'Unit 2, Building Name', MapPin)}
            {practiceField('address_line2', 'Address line 2', 'Corner of Street A & Street B')}
            {practiceField('city', 'City / Suburb', 'Roodepoort, Johannesburg, 2040')}
            {practiceField('map_link', 'Google Maps link', 'https://maps.app.goo.gl/...')}
          </div>
          {practiceForm.map_link && (
            <a
              href={practiceForm.map_link}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 text-sm text-brand-primary hover:underline"
            >
              <MapPin size={14} />
              {t('settings_view_on_map')}
              <ExternalLink size={12} />
            </a>
          )}
          <div className="flex justify-end pt-2">
            <button
              type="submit"
              disabled={savingPractice}
              className="flex items-center gap-2 rounded-xl bg-brand-primary px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-brand-primary/90 disabled:opacity-50"
            >
              <Save size={15} />
              {savingPractice ? 'Saving…' : 'Save Practice Details'}
            </button>
          </div>
        </form>
      </Card>

      {/* Pricing */}
      <Card
        icon={CreditCard}
        title={t('settings_pricing')}
        subtitle={t('settings_pricing_desc')}
      >
        <form onSubmit={savePricing} className="space-y-3">
          {pricingField('consultation', 'Consultation')}
          {pricingField('check_up', 'Check-up')}
          {pricingField('cleaning', 'Cleaning')}

          <div className="flex items-center justify-between pt-1">
            <div className="rounded-lg bg-amber-50 border border-amber-200 p-3 flex-1 mr-4">
              <p className="text-xs text-amber-800">{t('settings_cash_practice_note')}</p>
            </div>
            <button
              type="submit"
              disabled={savingPricing}
              className="flex items-center gap-2 rounded-xl bg-brand-primary px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-brand-primary/90 disabled:opacity-50"
            >
              <Save size={15} />
              {savingPricing ? 'Saving…' : 'Save Pricing'}
            </button>
          </div>
        </form>
      </Card>
    </div>
  )
}

/* ── Office Hours Tab ───────────────────────────────────────────────── */
function HoursTab({ schedules, t }) {
  return (
    <div className="space-y-6">
      <Card
        icon={Clock}
        title={t('settings_office_hours')}
        subtitle={t('settings_office_hours_desc')}
      >
        <div className="overflow-hidden rounded-xl border border-brand-border">
          <table className="min-w-full">
            <thead>
              <tr className="bg-brand-surface">
                <th className="text-left px-5 py-3 text-xs font-semibold text-brand-muted uppercase tracking-wide">{t('settings_day')}</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-brand-muted uppercase tracking-wide">{t('settings_hours')}</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-brand-muted uppercase tracking-wide">{t('settings_break')}</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-brand-muted uppercase tracking-wide">{t('settings_status')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-brand-border bg-white">
              {schedules?.map((schedule) => (
                <tr key={schedule.id} className="hover:bg-brand-surface/50 transition-colors">
                  <td className="px-5 py-3.5 text-sm font-medium text-brand-ink capitalize">{schedule.day_name}</td>
                  <td className="px-5 py-3.5 text-sm text-brand-muted">
                    {schedule.active ? `${schedule.start_time} — ${schedule.end_time}` : '—'}
                  </td>
                  <td className="px-5 py-3.5 text-sm text-brand-muted">
                    {schedule.break_start && schedule.break_end
                      ? `${schedule.break_start} — ${schedule.break_end}`
                      : '—'}
                  </td>
                  <td className="px-5 py-3.5">
                    <span className={`inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full ${
                      schedule.active
                        ? 'bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200'
                        : 'bg-gray-50 text-gray-500 ring-1 ring-gray-200'
                    }`}>
                      {schedule.active
                        ? <><CheckCircle2 size={12} /> {t('settings_open')}</>
                        : <><XCircle size={12} /> {t('settings_closed')}</>
                      }
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  )
}

/* ── Notifications Tab ──────────────────────────────────────────────── */
function NotificationsTab({ notifications, t }) {
  const channels = [
    {
      key: 'whatsapp',
      label: 'WhatsApp',
      confirmations: notifications?.whatsapp_confirmations,
      reminders: notifications?.whatsapp_reminders,
      color: 'emerald',
    },
    {
      key: 'email',
      label: t('settings_notif_email'),
      confirmations: notifications?.email_confirmations,
      reminders: notifications?.email_reminders,
      color: 'blue',
    },
    {
      key: 'sms',
      label: 'SMS',
      confirmations: notifications?.sms_confirmations,
      reminders: notifications?.sms_reminders,
      color: 'violet',
    },
  ]

  return (
    <div className="space-y-6">
      <Card
        icon={Bell}
        title={t('settings_notif_title')}
        subtitle={t('settings_notif_subtitle')}
      >
        <div className="space-y-4">
          {channels.map(({ key, label, confirmations, reminders, color }) => (
            <div key={key} className="flex items-center justify-between rounded-xl border border-brand-border p-4 hover:bg-brand-surface/30 transition-colors">
              <div className="flex items-center gap-3">
                <div className={`flex h-10 w-10 items-center justify-center rounded-lg bg-${color}-50`}>
                  {key === 'whatsapp' && <Phone size={18} className={`text-${color}-600`} />}
                  {key === 'email' && <Mail size={18} className={`text-${color}-600`} />}
                  {key === 'sms' && <Phone size={18} className={`text-${color}-600`} />}
                </div>
                <div>
                  <p className="text-sm font-semibold text-brand-ink">{label}</p>
                  <p className="text-xs text-brand-muted">
                    {confirmations && reminders
                      ? t('settings_notif_both_active')
                      : confirmations
                        ? t('settings_notif_confirm_only')
                        : reminders
                          ? t('settings_notif_remind_only')
                          : t('settings_notif_not_configured')
                    }
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <StatusDot active={confirmations} label={t('settings_notif_confirmations')} />
                <StatusDot active={reminders} label={t('settings_notif_reminders')} />
              </div>
            </div>
          ))}
        </div>

        <div className="mt-5 rounded-lg bg-brand-surface p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-brand-ink">{t('settings_notif_reminder_timing')}</p>
              <p className="text-xs text-brand-muted">{t('settings_notif_reminder_timing_desc')}</p>
            </div>
            <span className="rounded-lg bg-white border border-brand-border px-4 py-2 text-sm font-semibold text-brand-ink">
              {notifications?.reminder_hours_before || 24}h
            </span>
          </div>
        </div>
      </Card>
    </div>
  )
}

/* ── Appearance Tab ─────────────────────────────────────────────────── */
function AppearanceTab({ language, setLanguage, t }) {
  return (
    <div className="space-y-6">
      {/* Language */}
      <Card
        icon={Globe}
        title={t('settings_language')}
        subtitle={t('settings_language_desc')}
      >
        <div className="flex items-center gap-2 rounded-xl border border-brand-border bg-brand-surface p-1.5 w-fit">
          <button
            onClick={() => setLanguage('en')}
            className={`rounded-lg px-5 py-2.5 text-sm font-medium transition-all ${
              language === 'en'
                ? 'bg-white text-brand-ink shadow-sm ring-1 ring-brand-border'
                : 'text-brand-muted hover:text-brand-ink'
            }`}
          >
            English
          </button>
          <button
            onClick={() => setLanguage('af')}
            className={`rounded-lg px-5 py-2.5 text-sm font-medium transition-all ${
              language === 'af'
                ? 'bg-white text-brand-ink shadow-sm ring-1 ring-brand-border'
                : 'text-brand-muted hover:text-brand-ink'
            }`}
          >
            Afrikaans
          </button>
        </div>
      </Card>
    </div>
  )
}

/* ── Shared Components ──────────────────────────────────────────────── */
function Card({ icon: Icon, title, subtitle, children }) {
  return (
    <div className="bg-white rounded-xl border border-brand-border shadow-sm">
      <div className="flex items-center gap-3 px-6 py-5 border-b border-brand-border">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-primary/10">
          <Icon size={18} className="text-brand-primary" />
        </div>
        <div>
          <h2 className="text-sm font-semibold text-brand-ink">{title}</h2>
          {subtitle && <p className="text-xs text-brand-muted mt-0.5">{subtitle}</p>}
        </div>
      </div>
      <div className="px-6 py-5">
        {children}
      </div>
    </div>
  )
}


function StatusDot({ active, label }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className={`h-2 w-2 rounded-full ${active ? 'bg-emerald-500' : 'bg-gray-300'}`} />
      <span className="text-xs text-brand-muted">{label}</span>
    </div>
  )
}
