import React from 'react'
import { Globe } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { useLanguage } from '../lib/LanguageContext'

export default function Settings({ schedules, pricing }) {
  const { t, language, setLanguage } = useLanguage()

  return (
    <DashboardLayout>
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-brand-brown">{t('settings_title')}</h1>
        <p className="text-gray-500 mt-1 text-sm">{t('settings_subtitle')}</p>
      </div>

      {/* Language Toggle */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-primary/10">
              <Globe size={20} className="text-brand-primary" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-brand-brown">{t('settings_language')}</h2>
              <p className="text-xs text-gray-500 mt-0.5">{t('settings_language_desc')}</p>
            </div>
          </div>
          <div className="flex items-center gap-1 rounded-xl border border-gray-200 bg-gray-50 p-1">
            <button
              onClick={() => setLanguage('en')}
              className={`rounded-lg px-4 py-2 text-sm font-medium transition-all ${
                language === 'en'
                  ? 'bg-white text-brand-ink shadow-sm'
                  : 'text-gray-500 hover:text-brand-ink'
              }`}
            >
              English
            </button>
            <button
              onClick={() => setLanguage('af')}
              className={`rounded-lg px-4 py-2 text-sm font-medium transition-all ${
                language === 'af'
                  ? 'bg-white text-brand-ink shadow-sm'
                  : 'text-gray-500 hover:text-brand-ink'
              }`}
            >
              Afrikaans
            </button>
          </div>
        </div>
      </div>

      {/* Office Hours */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <h2 className="text-base font-semibold text-brand-brown mb-4">{t('settings_office_hours')}</h2>
        <div className="overflow-hidden rounded-lg border border-gray-100">
          <table className="min-w-full">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-100">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">{t('settings_day')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">{t('settings_hours')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">{t('settings_break')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">{t('settings_status')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {schedules?.map((schedule) => (
                <tr key={schedule.id} className="hover:bg-brand-cream transition-colors">
                  <td className="px-4 py-3 text-sm font-medium text-gray-900 capitalize">{schedule.day_name}</td>
                  <td className="px-4 py-3 text-sm text-gray-600">
                    {schedule.active ? `${schedule.start_time} — ${schedule.end_time}` : '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">
                    {schedule.break_start && schedule.break_end
                      ? `${schedule.break_start} — ${schedule.break_end}`
                      : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${schedule.active ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-500'}`}>
                      {schedule.active ? t('settings_open') : t('settings_closed')}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Pricing */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-5">
        <h2 className="text-base font-semibold text-brand-brown mb-4">{t('settings_pricing')}</h2>
        <div className="divide-y divide-gray-100">
          {pricing && Object.entries(pricing).map(([treatment, price]) => (
            <div key={treatment} className="flex items-center justify-between py-3 first:pt-0 last:pb-0">
              <span className="text-sm font-medium text-gray-800 capitalize">{treatment}</span>
              <span className="text-sm font-semibold text-brand-taupe">{price}</span>
            </div>
          ))}
          <div className="flex items-center justify-between py-3 last:pb-0">
            <span className="text-sm text-gray-400">{t('settings_all_other')}</span>
            <span className="text-sm text-gray-400 italic">{t('settings_requires_consult')}</span>
          </div>
        </div>
      </div>

    </DashboardLayout>
  )
}
