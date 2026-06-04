import React, { useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { cn } from '../lib/utils'

// Public, mobile-first patient intake wizard. Rendered on an UNAUTHENTICATED route
// (IntakesController < PublicController) — the patient opens it from the tokenised
// WhatsApp link. It renders dynamically from each FormTemplate's `schema` JSON, so
// adding/editing forms is a seed change, not a frontend change.
//
// Print-and-sign: nothing is signed here. On submit the answers are filed; reception
// prints the pre-filled pack (IntakePdf) and the patient signs + initials by hand.

const TRUTHY = [true, 'true', '1', 'yes', 'on']
const truthy = (v) => TRUTHY.includes(v)

// Is a field visible given the current answers? (reveal_when conditional logic.)
function isVisible(field, values) {
  const rule = field.reveal_when
  if (!rule) return true
  const expected = rule.equals
  const answer = values[rule.field]
  const actual = typeof expected === 'boolean' ? truthy(answer) : answer
  return actual === expected
}

function Shell({ children }) {
  return (
    <div className="min-h-screen bg-brand-surface text-brand-ink">
      <div className="mx-auto w-full max-w-xl px-4 py-6">{children}</div>
    </div>
  )
}

function Centered({ emoji, title, body }) {
  return (
    <Shell>
      <div className="mt-16 text-center">
        <div className="text-5xl mb-4">{emoji}</div>
        <h1 className="text-2xl font-semibold mb-3">{title}</h1>
        <p className="text-sm text-brand-muted">{body}</p>
      </div>
    </Shell>
  )
}

export default function PublicIntake(props) {
  const { token, invalid, completed, patient, practice, privacy_notice = [], templates = [] } = props

  if (invalid || !token) {
    return (
      <Centered
        emoji="🔒"
        title="This link is no longer valid"
        body="Your intake link may have expired (links are valid for 14 days). Please contact the practice and we'll send you a fresh one."
      />
    )
  }

  if (completed) {
    return (
      <Centered
        emoji="✅"
        title="All done — thank you!"
        body="We've received your forms. There's nothing more to do now; we'll print them for you to sign when you arrive for your visit."
      />
    )
  }

  return <Wizard token={token} patient={patient} practice={practice} privacyNotice={privacy_notice} templates={templates} />
}

function Wizard({ token, patient, practice, privacyNotice, templates }) {
  // answers: { [templateKey]: { [fieldKey]: value } }
  const [answers, setAnswers] = useState({})
  const [privacyAck, setPrivacyAck] = useState(false)
  const [stepIndex, setStepIndex] = useState(0)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)

  const steps = useMemo(() => {
    const list = [{ kind: 'privacy' }]
    templates.forEach((t) => {
      const sections = (t.schema && t.schema.sections) || []
      sections.forEach((section, idx) => {
        list.push({
          kind: 'section',
          templateKey: t.key,
          templateName: t.name,
          intro: idx === 0 ? t.schema.intro : null,
          section,
        })
      })
    })
    return list
  }, [templates])

  const step = steps[stepIndex]
  const isLast = stepIndex === steps.length - 1
  const progress = Math.round(((stepIndex + 1) / steps.length) * 100)

  const valuesFor = (key) => answers[key] || {}
  const setValue = (templateKey, fieldKey, value) => {
    setAnswers((prev) => ({ ...prev, [templateKey]: { ...(prev[templateKey] || {}), [fieldKey]: value } }))
  }

  // Required visible fields on the current section must be answered before Next.
  const canAdvance = () => {
    if (step.kind === 'privacy') return privacyAck
    const values = valuesFor(step.templateKey)
    return step.section.fields.every((f) => {
      if (!f.required || !isVisible(f, values)) return true
      const v = values[f.key]
      if (f.type === 'yesno') return v === true || v === false
      if (f.type === 'checkbox') return v === true
      return v !== undefined && String(v).trim() !== ''
    })
  }

  const goNext = () => {
    if (!canAdvance()) {
      setError('Please complete the required fields before continuing.')
      return
    }
    setError(null)
    if (isLast) return submit()
    setStepIndex((i) => i + 1)
    window.scrollTo(0, 0)
  }

  const goBack = () => {
    setError(null)
    setStepIndex((i) => Math.max(0, i - 1))
    window.scrollTo(0, 0)
  }

  const submit = () => {
    setSubmitting(true)
    router.patch(`/intake/${token}`, { answers }, {
      preserveScroll: true,
      onError: () => {
        setSubmitting(false)
        setError('Something went wrong saving your form. Please try again.')
      },
      onFinish: () => setSubmitting(false),
    })
  }

  return (
    <Shell>
      {/* Header + progress */}
      <div className="mb-5">
        <p className="text-xs font-semibold uppercase tracking-wide text-brand-primary">
          {practice?.name || 'Dr Chalita le Roux Inc'}
        </p>
        <h1 className="text-xl font-semibold mt-1">
          {patient?.first_name ? `Hi ${patient.first_name} 👋` : 'Patient forms'}
        </h1>
        <div className="mt-3 h-1.5 w-full rounded-full bg-brand-border">
          <div className="h-1.5 rounded-full bg-brand-primary transition-all" style={{ width: `${progress}%` }} />
        </div>
        <p className="mt-1 text-xs text-brand-muted">Step {stepIndex + 1} of {steps.length}</p>
      </div>

      <div className="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-brand-border">
        {step.kind === 'privacy'
          ? <PrivacyStep notice={privacyNotice} ack={privacyAck} setAck={setPrivacyAck} />
          : <SectionStep step={step} values={valuesFor(step.templateKey)} setValue={setValue} />}
      </div>

      {error && <p className="mt-3 text-sm text-brand-danger">{error}</p>}

      <div className="mt-5 flex items-center justify-between gap-3">
        <button
          type="button"
          onClick={goBack}
          disabled={stepIndex === 0 || submitting}
          className="rounded-xl px-4 py-2.5 text-sm font-semibold text-brand-ink-soft disabled:opacity-0"
        >
          ← Back
        </button>
        <button
          type="button"
          onClick={goNext}
          disabled={submitting}
          className="rounded-xl bg-brand-primary px-6 py-2.5 text-sm font-semibold text-white hover:bg-brand-primary-dark disabled:opacity-60"
        >
          {submitting ? 'Saving…' : isLast ? 'Submit' : 'Next →'}
        </button>
      </div>
    </Shell>
  )
}

function PrivacyStep({ notice, ack, setAck }) {
  return (
    <div>
      <h2 className="text-lg font-semibold mb-1">Before we start — your privacy</h2>
      <p className="text-sm text-brand-muted mb-4">Please read how we look after your information.</p>
      <div className="max-h-72 overflow-y-auto rounded-xl bg-brand-surface p-4 text-sm space-y-3">
        {notice.map((s) => (
          <div key={s.title}>
            <p className="font-semibold text-brand-ink">{s.title}</p>
            <p className="text-brand-ink-soft">{s.body}</p>
          </div>
        ))}
      </div>
      <label className="mt-4 flex items-start gap-3 text-sm">
        <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} className="mt-0.5 h-5 w-5 accent-[var(--brand-primary)]" />
        <span>I have read the privacy notice above and understand how my information will be used and protected.</span>
      </label>
    </div>
  )
}

function SectionStep({ step, values, setValue }) {
  return (
    <div>
      {step.intro && <p className="mb-4 text-sm text-brand-muted">{step.intro}</p>}
      <p className="text-xs font-semibold uppercase tracking-wide text-brand-primary">{step.templateName}</p>
      <h2 className="text-lg font-semibold mb-4">{step.section.title}</h2>
      <div className="space-y-4">
        {step.section.fields.map((field) =>
          isVisible(field, values)
            ? <Field key={field.key} field={field} value={values[field.key]} onChange={(v) => setValue(step.templateKey, field.key, v)} />
            : null
        )}
      </div>
    </div>
  )
}

function Field({ field, value, onChange }) {
  const label = (
    <label className="block text-sm font-medium text-brand-ink">
      {field.label}{field.required && <span className="text-brand-danger"> *</span>}
    </label>
  )

  if (field.type === 'heading') {
    return <h3 className="pt-2 text-sm font-semibold text-brand-primary">{field.label}</h3>
  }
  if (field.type === 'statement') {
    return <p className="text-xs leading-relaxed text-brand-ink-soft">{field.label}</p>
  }

  if (field.type === 'yesno') {
    return (
      <div>
        {label}
        <div className="mt-1.5 flex gap-2">
          {[['Yes', true], ['No', false]].map(([text, val]) => (
            <button
              key={text}
              type="button"
              onClick={() => onChange(val)}
              className={cn(
                'flex-1 rounded-xl border px-4 py-2.5 text-sm font-semibold',
                value === val ? 'border-brand-primary bg-brand-primary text-white' : 'border-brand-border bg-white text-brand-ink-soft'
              )}
            >
              {text}
            </button>
          ))}
        </div>
      </div>
    )
  }

  if (field.type === 'checkbox') {
    return (
      <label className="flex items-start gap-3 text-sm">
        <input type="checkbox" checked={!!value} onChange={(e) => onChange(e.target.checked)} className="mt-0.5 h-5 w-5 accent-[var(--brand-primary)]" />
        <span>{field.label}{field.required && <span className="text-brand-danger"> *</span>}</span>
      </label>
    )
  }

  if (field.type === 'select') {
    return (
      <div>
        {label}
        <select
          value={value || ''}
          onChange={(e) => onChange(e.target.value)}
          className="mt-1.5 w-full rounded-xl border border-brand-border bg-white px-3 py-2.5 text-base"
        >
          <option value="" disabled>Select…</option>
          {(field.options || []).map((opt) => <option key={opt} value={opt}>{opt}</option>)}
        </select>
      </div>
    )
  }

  if (field.type === 'textarea') {
    return (
      <div>
        {label}
        {field.help && <p className="text-xs text-brand-muted">{field.help}</p>}
        <textarea
          value={value || ''}
          onChange={(e) => onChange(e.target.value)}
          rows={3}
          className="mt-1.5 w-full rounded-xl border border-brand-border bg-white px-3 py-2.5 text-base"
        />
      </div>
    )
  }

  // text / tel / email / date / id_number
  const inputType = { tel: 'tel', email: 'email', date: 'date' }[field.type] || 'text'
  const inputMode = field.type === 'id_number' ? 'numeric' : undefined
  return (
    <div>
      {label}
      {field.help && <p className="text-xs text-brand-muted">{field.help}</p>}
      <input
        type={inputType}
        inputMode={inputMode}
        value={value || ''}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1.5 w-full rounded-xl border border-brand-border bg-white px-3 py-2.5 text-base"
      />
    </div>
  )
}
