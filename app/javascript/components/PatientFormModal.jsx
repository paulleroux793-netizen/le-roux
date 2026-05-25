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
  // Phone is now optional — family/shared phones are common in SA, and ID
  // number is sufficient identity. Validate only when supplied.
  phone:      z.string()
    .refine((v) => !v || phoneRegex.test(v), 'Must be a valid phone number')
    .optional(),
  email:      z.string().email('Invalid email').or(z.literal('')).optional(),
  date_of_birth: z.string().optional(),
  // SA ID number (13 digits) OR passport. Free-text; validation is loose
  // so receptionist can type-as-they-hear; uniqueness lives on the model.
  id_number:  z.string().optional(),
  notes:      z.string().optional(),

  // ── Billing account (optional) ──
  // If billing_name is supplied we attach a BillingAccount. Otherwise we
  // skip account creation entirely (most "self-pay walk-ins" don't need one).
  account_code:         z.string().optional(),
  account_billing_name: z.string().optional(),
  account_email:        z.string().email('Invalid email').or(z.literal('')).optional(),
  account_phone:        z.string()
    .refine((v) => !v || phoneRegex.test(v), 'Must be a valid phone number')
    .optional(),

  // ── Medical aid (optional) ──
  // scheme_id picks from the seeded dropdown; scheme_name_other lets the
  // receptionist type any scheme name not yet in the catalogue.
  scheme_id:          z.string().optional(),
  scheme_name_other:  z.string().optional(),
  membership_number:  z.string().optional(),
  dependant_code:     z.string().optional(),

  // POPIA — Patient has signed the paper AI-processing consent form.
  // The receptionist ticks this AFTER filing the signed form physically.
  // When false: AI summaries, mailbox drafts, scribe outputs all SKIP
  // this patient. Default false.
  ai_consent: z.boolean().optional(),

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
  date_of_birth: '', id_number: '', notes: '',
  ai_consent: false,
  account_code: '', account_billing_name: '', account_email: '', account_phone: '',
  scheme_id: '', scheme_name_other: '', membership_number: '', dependant_code: '',
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
  schemes = [],            // [{id, name}, ...] seeded SA medical schemes
}) {
  const isEdit = mode === 'edit'

  const {
    register,
    handleSubmit,
    reset,
    watch,
    formState: { errors, isSubmitting },
  } = useForm({
    resolver: zodResolver(schema),
    defaultValues: EMPTY_DEFAULTS,
  })

  // Watch scheme_id so we can reveal the "Other" free-text field when the
  // receptionist picks the sentinel "other" option.
  const watchedSchemeId = watch('scheme_id')
  const isOtherScheme = watchedSchemeId === 'other'

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
        id_number:  patient.id_number  || '',
        notes:      patient.notes      || '',
        ai_consent: !!patient.ai_consent,
        // Account/scheme aren't editable from this modal in edit mode —
        // they live on their own dedicated screens. Keep blank so the
        // hidden inputs don't overwrite anything on submit.
        account_code: '', account_billing_name: '', account_email: '', account_phone: '',
        scheme_id: '', scheme_name_other: '', membership_number: '', dependant_code: '',
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
        phone:      nullify(data.phone),
        email:      nullify(data.email),
        date_of_birth: nullify(data.date_of_birth),
        id_number:  nullify(data.id_number),
        notes:      nullify(data.notes),
        ai_consent: !!data.ai_consent,
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

    // Account & scheme are sent as separate top-level keys (not nested
    // under patient) so PatientsController#create can route them to the
    // attach_account! / attach_scheme! helpers — best-effort, never blocks
    // the patient create.
    if (!isEdit && data.account_billing_name) {
      payload.account = {
        account_code:  nullify(data.account_code),
        billing_name:  data.account_billing_name,
        email:         nullify(data.account_email),
        phone:         nullify(data.account_phone),
      }
    }
    if (!isEdit && data.membership_number) {
      payload.scheme = {
        scheme_id:         data.scheme_id === 'other' ? null : nullify(data.scheme_id),
        scheme_name:       data.scheme_id === 'other' ? nullify(data.scheme_name_other) : null,
        membership_number: data.membership_number,
        dependant_code:    nullify(data.dependant_code),
      }
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
            <Field label="Phone (optional)" error={errors.phone?.message}>
              <Input type="tel" placeholder="+27 82 123 4567" {...register('phone')} />
            </Field>
            <Field label="Email" error={errors.email?.message}>
              <Input type="email" {...register('email')} />
            </Field>
            <Field label="Date of birth">
              <Input type="date" {...register('date_of_birth')} />
            </Field>
            <Field label="ID / passport number">
              <Input placeholder="13-digit SA ID or passport" {...register('id_number')} />
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

        {/* ── POPIA consent (Paul's 2026-05-24 decision: paper form + this checkbox) ── */}
        <Section title="AI processing consent (POPIA)" subtitle="Tick only after the patient has signed the paper consent form and it's filed.">
          <label className="flex items-start gap-3 rounded-2xl border border-brand-accent/80 bg-brand-surface/30 px-4 py-3">
            <input
              type="checkbox"
              {...register('ai_consent')}
              className="mt-0.5 h-5 w-5 rounded border-brand-accent text-brand-primary focus:ring-brand-primary"
            />
            <span className="text-sm text-brand-ink">
              <strong>Consent to AI processing — paper form on file.</strong>
              <span className="mt-0.5 block text-xs text-brand-muted">
                When ticked, the chair-side scribe summary, mailbox booking drafts, and any future AI features will process this patient's data. When unticked, all AI features SKIP this patient.
              </span>
            </span>
          </label>
        </Section>

        {/* ── Billing account (create only — edit happens on the Account screen) ── */}
        {!isEdit && (
          <Section title="Billing account" subtitle="Optional — leave blank for a self-pay walk-in. Only fill this if a family member or insurer pays.">
            <div className="grid grid-cols-2 gap-4">
              <Field label="Account holder / billing name">
                <Input placeholder="e.g. John Smith (father)" {...register('account_billing_name')} />
              </Field>
              <Field label="Existing account code">
                <Input placeholder="e.g. ACC-0042 (leave blank to auto-generate)" {...register('account_code')} />
              </Field>
              <Field label="Billing email" error={errors.account_email?.message}>
                <Input type="email" {...register('account_email')} />
              </Field>
              <Field label="Billing phone" error={errors.account_phone?.message}>
                <Input type="tel" placeholder="+27 82 123 4567" {...register('account_phone')} />
              </Field>
            </div>
          </Section>
        )}

        {/* ── Medical aid (create only) ──────────────────────────── */}
        {!isEdit && (
          <Section title="Medical aid" subtitle="Optional — patient claims back themselves. We don't submit claims.">
            <div className="grid grid-cols-2 gap-4">
              <Field label="Scheme">
                <select
                  {...register('scheme_id')}
                  className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
                >
                  <option value="">— None / Private —</option>
                  {schemes.map((s) => (
                    <option key={s.id} value={s.id}>{s.name}</option>
                  ))}
                  <option value="other">Other (type below)…</option>
                </select>
              </Field>
              {isOtherScheme && (
                <Field label="Other scheme name">
                  <Input placeholder="e.g. Sizwe Hosmed" {...register('scheme_name_other')} />
                </Field>
              )}
              <Field label="Membership number">
                <Input {...register('membership_number')} />
              </Field>
              <Field label="Dependant code">
                <Input placeholder="e.g. 01" {...register('dependant_code')} />
              </Field>
            </div>
          </Section>
        )}

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
            <Field label="Medical aid provider (for claim-back)">
              <Input {...register('mh_insurance_provider')} />
            </Field>
            <Field label="Medical aid policy number">
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
