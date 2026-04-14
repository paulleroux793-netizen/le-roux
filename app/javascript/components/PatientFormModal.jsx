import React, { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import Modal from './Modal'

// ── Patient form modal (Create & Edit) ──────────────────────────────
// Phase 9.6 sub-area #4 — Patient Forms & Records.
//
// Single component handles both Create and Edit because the fields
// are identical; only endpoint + defaults differ.
//   - mode="create" → POST /patients
//   - mode="edit"   → PATCH /patients/:id
//
// The form is split into two visual sections:
//   1. Demographics — first/last name, phone, email, DOB, notes
//   2. Medical History — nested attributes on the medical_history
//      association. Everything here is optional so the receptionist
//      can capture a quick booking and fill records later.
//
// Phone validation mirrors the Rails model regex so errors surface
// client-side before a round-trip. Server-side validation is the
// source of truth — the redirect flow will surface any mismatch via
// the toast error handler.
const phoneRegex = /^\+?\d{10,15}$/

const schema = z.object({
  first_name: z.string().min(1, 'First name is required'),
  last_name:  z.string().min(1, 'Last name is required'),
  phone:      z.string().regex(phoneRegex, 'Must be a valid phone number'),
  email:      z.string().email('Invalid email').or(z.literal('')).optional(),
  date_of_birth: z.string().optional(),
  notes:      z.string().optional(),

  // Medical history — all optional.
  mh_allergies:              z.string().optional(),
  mh_chronic_conditions:     z.string().optional(),
  mh_current_medications:    z.string().optional(),
  mh_blood_type:             z.string().optional(),
  mh_emergency_contact_name: z.string().optional(),
  mh_emergency_contact_phone: z.string()
    .refine((v) => !v || phoneRegex.test(v), 'Must be a valid phone number')
    .optional(),
  mh_insurance_provider:        z.string().optional(),
  mh_insurance_policy_number:   z.string().optional(),
  mh_dental_notes:              z.string().optional(),
  mh_last_dental_visit:         z.string().optional(),
})

// Default blood types — the server is the authoritative source
// (PatientMedicalHistory::BLOOD_TYPES) but we mirror it here so
// the dropdown still renders if the prop isn't passed (e.g. create
// mode before a patient exists).
const DEFAULT_BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']

const EMPTY_DEFAULTS = {
  first_name: '', last_name: '', phone: '', email: '',
  date_of_birth: '', notes: '',
  mh_allergies: '', mh_chronic_conditions: '', mh_current_medications: '',
  mh_blood_type: '', mh_emergency_contact_name: '', mh_emergency_contact_phone: '',
  mh_insurance_provider: '', mh_insurance_policy_number: '',
  mh_dental_notes: '', mh_last_dental_visit: '',
}

export default function PatientFormModal({
  open,
  onClose,
  mode = 'create',         // 'create' | 'edit'
  patient,                 // required for mode=edit
  medicalHistory,          // optional existing medical history hash
  bloodTypes = DEFAULT_BLOOD_TYPES,
}) {
  const isEdit = mode === 'edit'

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm({
    resolver: zodResolver(schema),
    defaultValues: EMPTY_DEFAULTS,
  })

  // Hydrate form when opening or switching target patient.
  useEffect(() => {
    if (!open) return
    if (isEdit && patient) {
      reset({
        first_name: patient.first_name || '',
        last_name:  patient.last_name  || '',
        phone:      patient.phone      || '',
        email:      patient.email      || '',
        date_of_birth: patient.date_of_birth || '',
        notes:      patient.notes      || '',
        mh_allergies:              medicalHistory?.allergies || '',
        mh_chronic_conditions:     medicalHistory?.chronic_conditions || '',
        mh_current_medications:    medicalHistory?.current_medications || '',
        mh_blood_type:             medicalHistory?.blood_type || '',
        mh_emergency_contact_name: medicalHistory?.emergency_contact_name || '',
        mh_emergency_contact_phone: medicalHistory?.emergency_contact_phone || '',
        mh_insurance_provider:     medicalHistory?.insurance_provider || '',
        mh_insurance_policy_number: medicalHistory?.insurance_policy_number || '',
        mh_dental_notes:           medicalHistory?.dental_notes || '',
        mh_last_dental_visit:      medicalHistory?.last_dental_visit
          ? medicalHistory.last_dental_visit.slice(0, 10)
          : '',
      })
    } else {
      reset(EMPTY_DEFAULTS)
    }
  }, [open, isEdit, patient, medicalHistory, reset])

  const onSubmit = (data) => {
    // Reshape flat form into the nested params shape Rails expects.
    // Empty strings become nulls so they clear fields on update.
    const nullify = (v) => (v === '' || v == null ? null : v)
    const payload = {
      patient: {
        first_name: data.first_name,
        last_name:  data.last_name,
        phone:      data.phone,
        email:      nullify(data.email),
        date_of_birth: nullify(data.date_of_birth),
        notes:      nullify(data.notes),
        medical_history_attributes: {
          ...(medicalHistory?.id ? { id: medicalHistory.id } : {}),
          allergies:              nullify(data.mh_allergies),
          chronic_conditions:     nullify(data.mh_chronic_conditions),
          current_medications:    nullify(data.mh_current_medications),
          blood_type:             nullify(data.mh_blood_type),
          emergency_contact_name: nullify(data.mh_emergency_contact_name),
          emergency_contact_phone: nullify(data.mh_emergency_contact_phone),
          insurance_provider:     nullify(data.mh_insurance_provider),
          insurance_policy_number: nullify(data.mh_insurance_policy_number),
          dental_notes:           nullify(data.mh_dental_notes),
          last_dental_visit:      nullify(data.mh_last_dental_visit),
        },
      },
    }

    const opts = {
      preserveScroll: true,
      preserveState: true,
      onSuccess: (page) => {
        const notice = page?.props?.flash?.notice
        toast.success(notice || (isEdit ? 'Patient updated' : 'Patient created'))
        onClose?.()
      },
      onError: (errs) => {
        const msg = Object.values(errs || {})[0] || 'Something went wrong'
        toast.error(msg)
      },
    }

    if (isEdit) {
      router.patch(`/patients/${patient.id}`, payload, opts)
    } else {
      router.post('/patients', payload, opts)
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? 'Edit Patient' : 'New Patient'}
      size="2xl"
      footer={
        <>
          <button
            type="button"
            onClick={onClose}
            className="rounded-2xl px-4 py-2 text-sm font-medium text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink"
          >
            Cancel
          </button>
          <button
            type="submit"
            form="patient-form"
            disabled={isSubmitting}
            className="rounded-2xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark disabled:opacity-50"
          >
            {isEdit ? 'Save changes' : 'Create patient'}
          </button>
        </>
      }
    >
      <form id="patient-form" onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        {/* ── Demographics ─────────────────────────────────────── */}
        <Section title="Demographics">
          <div className="grid grid-cols-2 gap-4">
            <Field label="First name" error={errors.first_name?.message}>
              <Input {...register('first_name')} />
            </Field>
            <Field label="Last name" error={errors.last_name?.message}>
              <Input {...register('last_name')} />
            </Field>
            <Field label="Phone" error={errors.phone?.message}>
              <Input type="tel" placeholder="+27 82 123 4567" {...register('phone')} />
            </Field>
            <Field label="Email" error={errors.email?.message}>
              <Input type="email" {...register('email')} />
            </Field>
            <Field label="Date of birth">
              <Input type="date" {...register('date_of_birth')} />
            </Field>
          </div>
          <Field label="Notes">
            <textarea
              rows={2}
              placeholder="General notes about this patient…"
              {...register('notes')}
              className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
            />
          </Field>
        </Section>

        {/* ── Medical history ──────────────────────────────────── */}
        <Section title="Medical History" subtitle="Optional — fill in what you have">
          <div className="grid grid-cols-2 gap-4">
            <Field label="Allergies">
              <textarea
                rows={2}
                placeholder="e.g. Penicillin, latex"
                {...register('mh_allergies')}
                className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
              />
            </Field>
            <Field label="Chronic conditions">
              <textarea
                rows={2}
                placeholder="e.g. Hypertension, diabetes"
                {...register('mh_chronic_conditions')}
                className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
              />
            </Field>
            <Field label="Current medications">
              <textarea
                rows={2}
                {...register('mh_current_medications')}
                className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
              />
            </Field>
            <Field label="Blood type">
              <select
                {...register('mh_blood_type')}
                className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
              >
                <option value="">Unknown</option>
                {bloodTypes.map((bt) => (
                  <option key={bt} value={bt}>{bt}</option>
                ))}
              </select>
            </Field>
            <Field label="Emergency contact name">
              <Input {...register('mh_emergency_contact_name')} />
            </Field>
            <Field label="Emergency contact phone" error={errors.mh_emergency_contact_phone?.message}>
              <Input type="tel" placeholder="+27 82 123 4567" {...register('mh_emergency_contact_phone')} />
            </Field>
            <Field label="Insurance provider">
              <Input {...register('mh_insurance_provider')} />
            </Field>
            <Field label="Policy number">
              <Input {...register('mh_insurance_policy_number')} />
            </Field>
            <Field label="Last dental visit">
              <Input type="date" {...register('mh_last_dental_visit')} />
            </Field>
          </div>
          <Field label="Dental notes">
            <textarea
            rows={2}
            placeholder="Prior procedures, sensitivities, anxiety triggers…"
            {...register('mh_dental_notes')}
            className="w-full resize-none rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
          />
        </Field>
        </Section>
      </form>
    </Modal>
  )
}

function Section({ title, subtitle, children }) {
  return (
    <div>
      <div className="mb-3 border-b border-brand-accent/60 pb-2">
        <h3 className="text-sm font-semibold text-brand-ink">{title}</h3>
        {subtitle && <p className="mt-0.5 text-xs text-brand-muted">{subtitle}</p>}
      </div>
      <div className="space-y-4">{children}</div>
    </div>
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

const Input = React.forwardRef(function Input(props, ref) {
  return (
    <input
      ref={ref}
      {...props}
      className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
    />
  )
})
