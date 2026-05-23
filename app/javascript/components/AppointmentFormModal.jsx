import React, { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import Modal from './Modal'
import { useLanguage } from '../lib/LanguageContext'

// ── Appointment form modal (Create & Edit) ──────────────────────────
// A single component handles both Create and Edit because the form
// fields are identical — only the submit endpoint and defaults
// change. `mode` picks which:
//   - mode="create" → POST /appointments with a patient picker
//   - mode="edit"   → PATCH /appointments/:id, patient pre-filled
//
// Validation is zod + react-hook-form. Times are entered as HTML5
// datetime-local inputs for zero-dependency input UX; zod parses the
// string into a date and enforces end > start.

// Build the schema dynamically so validation messages use the current language.
// The schema itself is static (field names don't change), but we wrap it
// in a function so `t()` is called at resolve-time, not import-time.
// Default appointment duration in minutes, inferred from the reason text.
// Per the practice config: check-up 45m, whitening 90m, cleaning 30m, etc.
function defaultDurationFor(reason) {
  const r = (reason || '').toLowerCase()
  if (r.includes('whiten')) return 90
  if (r.includes('check') || r.includes('exam') || r.includes('cosmetic') || r.includes('aligner')) return 45
  if (r.includes('clean') || r.includes('hygien') || r.includes('polish') || r.includes('scal')) return 30
  if (r.includes('consult')) return 30
  if (r.includes('extract')) return 30
  if (r.includes('filling') || r.includes('restor') || r.includes('crown')) return 45
  return 30
}

// Format a Date as the value an HTML datetime-local input expects (local TZ).
function dtLocal(d) {
  const pad = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

// Snap a datetime-local string's minutes to the nearest 15-min interval.
function snapTo15(str) {
  if (!str) return str
  const d = new Date(str)
  const snapped = Math.round(d.getMinutes() / 15) * 15
  if (snapped === d.getMinutes()) return str
  d.setMinutes(snapped, 0, 0)
  return dtLocal(d)
}

function buildSchema(t) {
  return z
    .object({
      patient_id: z.union([z.string(), z.number()]).refine((v) => !!v, t('validation_patient_required')),
      start_time: z.string().min(1, t('validation_start_required')),
      end_time: z.string().min(1, t('validation_end_required')),
      duration: z.union([z.string(), z.number()]).optional(),
      reason: z.string().optional(),
      notes: z.string().optional(),
    })
    .refine((v) => new Date(v.end_time) > new Date(v.start_time), {
      path: ['end_time'],
      message: t('validation_end_after_start'),
    })
}

// Convert an ISO string from the server to the value format an HTML
// datetime-local input expects: "YYYY-MM-DDTHH:mm" in *local* time.
const toLocalInput = (iso) => {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export default function AppointmentFormModal({
  open,
  onClose,
  mode = 'create',       // 'create' | 'edit'
  appointment,           // required for mode=edit
  patients = [],         // required for mode=create
}) {
  const { t } = useLanguage()
  const isEdit = mode === 'edit'

  const {
    register,
    handleSubmit,
    reset,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm({
    resolver: zodResolver(buildSchema(t)),
    defaultValues: {
      patient_id: '',
      start_time: '',
      end_time: '',
      duration: 30,
      reason: '',
      notes: '',
    },
  })

  // ── Smart booking: snap start to 15 min, infer duration from reason, derive end ──
  const startTime = watch('start_time')
  const reason    = watch('reason')
  const duration  = watch('duration')

  // Snap start_time to the nearest 15-minute interval whenever it changes.
  useEffect(() => {
    if (!startTime) return
    const snapped = snapTo15(startTime)
    if (snapped !== startTime) setValue('start_time', snapped)
  }, [startTime, setValue])

  // When reason text changes, suggest a duration that matches the practice's
  // typical slot length (check-up 45, whitening 90, etc.). Doesn't lock — the
  // user can still pick a different duration from the dropdown.
  useEffect(() => {
    if (!reason) return
    setValue('duration', defaultDurationFor(reason))
  }, [reason, setValue])

  // Whenever start_time or duration changes, derive end_time = start + duration.
  useEffect(() => {
    if (!startTime || !duration) return
    const d = new Date(startTime)
    d.setMinutes(d.getMinutes() + Number(duration))
    setValue('end_time', dtLocal(d))
  }, [startTime, duration, setValue])

  // When the modal opens (or the target appointment changes) hydrate
  // the form with the right defaults. Resetting inside a useEffect
  // keeps the form controlled while still reacting to prop changes.
  useEffect(() => {
    if (!open) return
    if (isEdit && appointment) {
      reset({
        patient_id: appointment.patient_id || '',
        start_time: toLocalInput(appointment.start_time),
        end_time: toLocalInput(appointment.end_time),
        reason: appointment.reason || '',
        notes: appointment.notes || '',
      })
    } else {
      reset({ patient_id: '', start_time: '', end_time: '', reason: '', notes: '' })
    }
  }, [open, isEdit, appointment, reset])

  const onSubmit = (data) => {
    const payload = {
      appointment: {
        ...(isEdit ? {} : { patient_id: data.patient_id }),
        start_time: new Date(data.start_time).toISOString(),
        end_time: new Date(data.end_time).toISOString(),
        reason: data.reason || null,
        notes: data.notes || null,
      },
    }

    const opts = {
      preserveScroll: true,
      preserveState: false,
      onSuccess: (page) => {
        const notice = page?.props?.flash?.notice
        toast.success(notice || (isEdit ? t('modal_success_update') : t('modal_success_create')))
        onClose?.()
      },
      onError: (errs) => {
        const msg = Object.values(errs || {})[0] || t('modal_error_generic')
        toast.error(msg)
      },
    }

    if (isEdit) {
      router.patch(`/appointments/${appointment.id}`, payload, opts)
    } else {
      router.post('/appointments', payload, opts)
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? t('modal_edit_appointment') : t('modal_new_appointment')}
      size="lg"
      footer={
        <>
          <button
            type="button"
            onClick={onClose}
            className="rounded-2xl px-4 py-2 text-sm font-medium text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            {t('modal_cancel_btn')}
          </button>
          <button
            type="submit"
            form="appointment-form"
            disabled={isSubmitting}
            className="rounded-2xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark disabled:opacity-50"
          >
            {isEdit ? t('modal_save_btn') : t('modal_book_btn')}
          </button>
        </>
      }
    >
      <form id="appointment-form" onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        {/* Patient — only shown in create mode */}
        {!isEdit && (
          <Field label={t('modal_patient_label')} error={errors.patient_id?.message}>
            <select
              {...register('patient_id')}
              className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            >
              <option value="">{t('modal_select_patient')}</option>
              {patients.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} — {p.phone}
                </option>
              ))}
            </select>
          </Field>
        )}

        <div className="grid grid-cols-3 gap-4">
          <Field label={t('modal_start_time')} error={errors.start_time?.message}>
            {/* step=900 = 15-min increments in the native picker; we also snap programmatically */}
            <input
              type="datetime-local"
              step="900"
              {...register('start_time')}
              className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            />
          </Field>
          <Field label="Duration">
            <select
              {...register('duration')}
              className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            >
              <option value="15">15 min</option>
              <option value="30">30 min</option>
              <option value="45">45 min — check-up / cosmetic</option>
              <option value="60">60 min</option>
              <option value="90">90 min — whitening</option>
              <option value="120">120 min</option>
            </select>
          </Field>
          <Field label={t('modal_end_time')} error={errors.end_time?.message}>
            <input
              type="datetime-local"
              readOnly
              {...register('end_time')}
              className="w-full rounded-2xl border border-brand-border bg-brand-surface/60 px-3 py-2.5 text-sm text-brand-muted focus:outline-none"
              title="Auto-set from Start + Duration"
            />
          </Field>
        </div>

        <Field label={t('modal_reason')}>
          <input
            type="text"
            placeholder={t('modal_reason_placeholder')}
            {...register('reason')}
            className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
          />
        </Field>

        <Field label={t('modal_notes')}>
          <textarea
            rows={3}
            placeholder={t('modal_notes_placeholder')}
            {...register('notes')}
            className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
          />
        </Field>
      </form>
    </Modal>
  )
}

function Field({ label, error, children }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-brand-muted">
        {label}
      </span>
      {children}
      {error && <span className="mt-1 block text-xs text-brand-danger">{error}</span>}
    </label>
  )
}
