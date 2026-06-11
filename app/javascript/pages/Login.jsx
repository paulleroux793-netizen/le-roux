import React, { useState } from 'react'
import { router } from '@inertiajs/react'

export default function Login({ notice, alert }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const submit = (e) => {
    e.preventDefault()
    setSubmitting(true)
    router.post('/login', { email, password }, { onFinish: () => setSubmitting(false) })
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-brand-surface px-4">
      <div className="w-full max-w-sm rounded-2xl border border-brand-border bg-white p-8 shadow-sm">
        <div className="mb-6 text-center">
          <h1 className="text-xl font-semibold text-brand-ink">Dr Chalita le Roux</h1>
          <p className="text-sm text-brand-muted">Sign in to the practice dashboard</p>
        </div>

        {alert && <div className="mb-4 rounded-lg bg-red-50 px-3 py-2 text-sm text-brand-danger">{alert}</div>}
        {notice && <div className="mb-4 rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">{notice}</div>}

        <form onSubmit={submit} className="space-y-4">
          <div>
            <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Email</label>
            <input type="email" autoFocus required value={email} onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-lg border border-brand-border px-3 py-2 text-sm focus:border-brand-primary focus:outline-none" />
          </div>
          <div>
            <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Password</label>
            <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-lg border border-brand-border px-3 py-2 text-sm focus:border-brand-primary focus:outline-none" />
          </div>
          <button type="submit" disabled={submitting}
            className="w-full rounded-lg bg-brand-primary px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:opacity-50">
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
