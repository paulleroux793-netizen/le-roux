import React, { useEffect, useState } from 'react'
import { UserPlus, Users, Ban } from 'lucide-react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import Modal from './Modal'
import PatientSearchSelect from './PatientSearchSelect'
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

function buildSchema(t, getNewPatientMode) {
  return z
    .object({
      // patient_id is only required when NOT in new-patient mode. When
      // the user toggles "New patient" the inline fields take over and
      // patient_id can be blank.
      patient_id: z.union([z.string(), z.number()]).optional(),
      start_time: z.string().min(1, t('validation_start_required')),
      end_time: z.string().min(1, t('validation_end_required')),
      duration: z.union([z.string(), z.number()]).optional(),
      reason: z.string().optional(),
      notes: z.string().optional(),
      // MUST be in the schema or zodResolver strips it from the submitted data —
      // that was why the chosen dentist was lost (bookings defaulted to the active
      // dentist; Closed blocks got null → showed in BOTH columns).
      provider_id: z.union([z.string(), z.number()]).optional(),
    })
    .refine((v) => new Date(v.end_time) > new Date(v.start_time), {
      path: ['end_time'],
      message: t('validation_end_after_start'),
    })
    .refine((v) => (typeof getNewPatientMode === 'function' && getNewPatientMode()) || !!v.patient_id, {
      path: ['patient_id'],
      message: t('validation_patient_required'),
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
  prefillStart = null,   // Date | null — opened from a calendar empty-slot click
  providers = [],        // [{id, name, color}] — diary dentists (optional)
  prefillProvider = null, // {id,...} — column the empty slot was clicked in
}) {
  const { t } = useLanguage()
  const isEdit = mode === 'edit'

  // ── New-Patient inline path ───────────────────────────────────────
  // When reception clicks an empty calendar slot, the most common case
  // is "Mrs Smith just called — book her in for tomorrow 10am". We
  // don't want them to bounce to /patients first. The toggle below
  // lets them capture the patient inline:
  //   - Existing patient: pick from dropdown (the original flow)
  //   - New patient:      type first name + last name + phone here
  // Server-side AppointmentsController#create accepts both shapes.
  const [newPatientMode, setNewPatientMode] = useState(false)
  const [closedMode, setClosedMode] = useState(false) // block-out time (no patient)
  const [selectedPatient, setSelectedPatient] = useState(null) // type-ahead pick
  const [newFirstName,   setNewFirstName]   = useState('')
  const [newLastName,    setNewLastName]    = useState('')
  const [newPhone,       setNewPhone]       = useState('')

  const {
    register,
    handleSubmit,
    reset,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm({
    resolver: zodResolver(buildSchema(t, () => newPatientMode || closedMode)),
    defaultValues: {
      patient_id: '',
      start_time: '',
      end_time: '',
      duration: 30,
      reason: '',
      notes: '',
      provider_id: '',
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
  // EDIT mode is exempt: a saved appointment's slot length is explicit, so we
  // must never auto-shrink it (a 90-min whitening reopened for edit was silently
  // becoming 30 min when this fired on hydration).
  useEffect(() => {
    if (isEdit) return
    if (!reason) return
    setValue('duration', defaultDurationFor(reason))
  }, [reason, isEdit, setValue])

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
      // Seed duration from the appointment's REAL length so the derive-end effect
      // reproduces the saved end_time instead of clobbering it with a default.
      const mins = Math.round(
        (new Date(appointment.end_time) - new Date(appointment.start_time)) / 60000
      )
      reset({
        patient_id: appointment.patient_id || '',
        start_time: toLocalInput(appointment.start_time),
        end_time: toLocalInput(appointment.end_time),
        duration: mins > 0 ? mins : 30,
        reason: appointment.reason || '',
        notes: appointment.notes || '',
        provider_id: appointment.provider_id || '',
      })
    } else {
      const start = prefillStart ? dtLocal(prefillStart) : ''
      reset({
        patient_id: '', start_time: start, end_time: '', duration: 30, reason: '', notes: '',
        provider_id: prefillProvider?.id || providers[0]?.id || '',
      })
    }
    setNewPatientMode(false)
    setClosedMode(false)
    setSelectedPatient(null)
    setNewFirstName(''); setNewLastName(''); setNewPhone('')
  }, [open, isEdit, appointment, prefillStart, prefillProvider, reset])

  const onSubmit = (data) => {
    // Closed / block-out: no patient — create a calendar note in this dentist's column.
    if (closedMode) {
      router.post('/calendar_notes', {
        calendar_note: {
          starts_at: new Date(data.start_time).toISOString(),
          ends_at: new Date(data.end_time).toISOString(),
          note: (data.reason || '').trim() || 'Closed',
          provider_id: data.provider_id || null,
        },
      }, {
        preserveScroll: true, preserveState: false,
        onSuccess: () => { toast.success('Time blocked out'); onClose?.() },
        onError: () => toast.error('Could not block out time'),
      })
      return
    }
    // New-patient inline path: pre-flight check on required fields
    // (the zod schema lets these through because they live OUTSIDE
    // the form — they're plain useState — to keep the schema simple).
    if (!isEdit && newPatientMode) {
      if (!newFirstName.trim() || !newLastName.trim() || !newPhone.trim()) {
        toast.error('New patient: first name, last name, and phone are required')
        return
      }
    }

    const payload = {
      appointment: {
        ...(isEdit ? {} : { patient_id: newPatientMode ? null : data.patient_id }),
        start_time: new Date(data.start_time).toISOString(),
        end_time: new Date(data.end_time).toISOString(),
        reason: data.reason || null,
        notes: data.notes || null,
        provider_id: data.provider_id || null,
      },
      // Server creates the patient first, then the appointment. Both
      // succeed or both roll back.
      ...(!isEdit && newPatientMode && {
        new_patient: {
          first_name: newFirstName.trim(),
          last_name:  newLastName.trim(),
          phone:      newPhone.trim(),
        },
      }),
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
            {isEdit ? t('modal_save_btn') : (closedMode ? 'Block out time' : t('modal_book_btn'))}
          </button>
        </>
      }
    >
      <form id="appointment-form" onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        {/* Patient — toggle between Existing (picker) and New (inline capture) */}
        {!isEdit && (
          <div className="space-y-2">
            <div className="inline-flex rounded-2xl border border-brand-border bg-brand-surface p-1">
              <button type="button" onClick={() => { setNewPatientMode(false); setClosedMode(false) }}
                className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition-colors ${
                  !newPatientMode && !closedMode ? 'bg-white text-brand-ink shadow-sm' : 'text-brand-muted hover:text-brand-ink'
                }`}>
                <Users size={13} /> Existing patient
              </button>
              <button type="button" onClick={() => { setNewPatientMode(true); setClosedMode(false) }}
                className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition-colors ${
                  newPatientMode && !closedMode ? 'bg-white text-brand-primary shadow-sm' : 'text-brand-muted hover:text-brand-ink'
                }`}>
                <UserPlus size={13} /> New patient
              </button>
              <button type="button" onClick={() => { setClosedMode(true); setNewPatientMode(false) }}
                className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition-colors ${
                  closedMode ? 'bg-white text-pink-600 shadow-sm' : 'text-brand-muted hover:text-brand-ink'
                }`}>
                <Ban size={13} /> Closed / block
              </button>
            </div>

            {closedMode ? (
              <p className="rounded-2xl border border-brand-accent/60 bg-brand-surface/40 px-3 py-2.5 text-xs text-brand-muted">
                Blocking out time (e.g. lunch, leave, closed) in the selected dentist’s column — no patient needed. Type a label in “Reason”.
              </p>
            ) : !newPatientMode ? (
              <Field label={t('modal_patient_label')} error={errors.patient_id?.message}>
                <input type="hidden" {...register('patient_id')} />
                <PatientSearchSelect
                  selected={selectedPatient}
                  autoFocus
                  onSelect={(p) => {
                    setSelectedPatient(p)
                    setValue('patient_id', p?.id || '', { shouldValidate: true })
                  }}
                />
              </Field>
            ) : (
              <div className="grid grid-cols-3 gap-3 rounded-2xl border border-brand-accent/80 bg-brand-surface/40 p-3">
                <Field label="First name">
                  <input value={newFirstName} onChange={(e) => setNewFirstName(e.target.value)}
                    autoFocus
                    className="w-full rounded-xl border border-brand-accent/80 bg-white px-2.5 py-2 text-sm focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
                </Field>
                <Field label="Last name">
                  <input value={newLastName} onChange={(e) => setNewLastName(e.target.value)}
                    className="w-full rounded-xl border border-brand-accent/80 bg-white px-2.5 py-2 text-sm focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
                </Field>
                <Field label="Phone">
                  <input type="tel" value={newPhone} onChange={(e) => setNewPhone(e.target.value)}
                    placeholder="+27 82 123 4567"
                    className="w-full rounded-xl border border-brand-accent/80 bg-white px-2.5 py-2 text-sm focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
                </Field>
                <p className="col-span-3 text-xs text-brand-muted">
                  This will create a new patient record and book the appointment in one step. You can fill in ID number, medical aid, and medical history later from the patient profile.
                </p>
              </div>
            )}
          </div>
        )}

        {providers.length > 0 && (
          <Field label="Dentist">
            <select
              {...register('provider_id')}
              className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            >
              {providers.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
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
