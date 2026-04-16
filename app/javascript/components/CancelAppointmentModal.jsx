import React, { useState, useEffect } from 'react'
import { router } from '@inertiajs/react'
import { AlertTriangle } from 'lucide-react'
import { toast } from 'sonner'
import Modal from './Modal'
import { useLanguage } from '../lib/LanguageContext'

// ── Cancel confirmation modal ───────────────────────────────────────
// Captures a structured cancellation reason (matching the backend
// CancellationReason::CATEGORIES whitelist) plus optional free-text
// details. The category is what Phase 11 analytics will aggregate on,
// so we force the reception to pick one rather than leaving it empty.

const CATEGORY_KEYS = [
  { value: 'cost',      key: 'cancel_cat_cost' },
  { value: 'timing',    key: 'cancel_cat_timing' },
  { value: 'fear',      key: 'cancel_cat_fear' },
  { value: 'transport', key: 'cancel_cat_transport' },
  { value: 'other',     key: 'cancel_cat_other' },
]

export default function CancelAppointmentModal({ appointment, open, onClose }) {
  const { t } = useLanguage()
  const [category, setCategory] = useState('')
  const [details, setDetails] = useState('')
  const [submitting, setSubmitting] = useState(false)

  // Reset form whenever the modal (re)opens so a stale half-filled
  // state from a previous cancel doesn't leak into the next one.
  useEffect(() => {
    if (open) {
      setCategory('')
      setDetails('')
      setSubmitting(false)
    }
  }, [open])

  if (!appointment) return null

  const handleConfirm = () => {
    if (!category) {
      toast.error(t('cancel_pick_reason'))
      return
    }
    setSubmitting(true)
    router.patch(
      `/appointments/${appointment.id}/cancel`,
      { cancellation: { category, details } },
      {
        preserveScroll: true,
        onSuccess: () => {
          toast.success(t('cancel_success'))
          onClose?.()
        },
        onError: () => toast.error(t('cancel_error')),
        onFinish: () => setSubmitting(false),
      }
    )
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t('cancel_title')}
      size="md"
      footer={
        <>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
          >
            {t('cancel_keep')}
          </button>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={submitting}
            className="px-4 py-2 text-sm font-semibold text-white bg-red-600 hover:bg-red-700 disabled:opacity-50 rounded-lg transition-colors"
          >
            {submitting ? t('cancel_submitting') : t('cancel_confirm')}
          </button>
        </>
      }
    >
      <div className="flex items-start gap-3 p-4 rounded-lg bg-red-50 border border-red-100 mb-5">
        <AlertTriangle size={18} className="text-red-600 flex-shrink-0 mt-0.5" />
        <div className="text-sm text-red-700">
          {t('cancel_warning')}{' '}
          <span className="font-semibold">{appointment.patient_name}</span>. {t('cancel_irreversible')}
        </div>
      </div>

      <label className="block mb-4">
        <span className="block text-xs font-semibold text-gray-600 uppercase tracking-wide mb-1.5">
          {t('cancel_reason_label')}
        </span>
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe"
        >
          <option value="">{t('cancel_reason_placeholder')}</option>
          {CATEGORY_KEYS.map((c) => (
            <option key={c.value} value={c.value}>{t(c.key)}</option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="block text-xs font-semibold text-gray-600 uppercase tracking-wide mb-1.5">
          {t('cancel_notes_label')} <span className="text-gray-400 font-normal">{t('cancel_notes_optional')}</span>
        </span>
        <textarea
          rows={3}
          value={details}
          onChange={(e) => setDetails(e.target.value)}
          placeholder={t('cancel_notes_placeholder')}
          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe resize-none"
        />
      </label>
    </Modal>
  )
}
