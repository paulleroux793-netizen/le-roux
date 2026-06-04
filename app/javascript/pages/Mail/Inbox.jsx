import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { Inbox as InboxIcon, Star, Search, Mail, Calendar, AlertCircle, PlusCircle, Paperclip, ChevronRight, Folder } from 'lucide-react'
import DashboardLayout from '../../layouts/DashboardLayout'
import { cn } from '../../lib/utils'

// N2 — Outlook-style unified inbox.
// Tri-pane layout: account/folder nav · conversation list · reading pane.
// Provider sync (Aurinko / Microsoft Graph / Gmail API) is a follow-up;
// this scaffold renders correctly with zero connected accounts and
// guides Paul through the next steps.

const INTENT_LABEL = {
  appointment_request: 'Appointment requests',
  insurance_inquiry:   'Insurance',
  treatment_question:  'Treatment Qs',
  billing_issue:       'Billing',
  marketing:           'Marketing',
  other:               'Other',
}

const fmt = (iso) => iso && new Date(iso).toLocaleString('en-ZA', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })

export default function MailInbox({
  accounts = [], threads = [], active_thread: activeThread = null,
  pending_drafts_count: pendingDraftsCount = 0, filters = {},
}) {
  const [q, setQ] = useState('')

  const goto = (params) => router.get('/mail', params, { preserveScroll: false, preserveState: false })

  const filtered = threads.filter((t) => {
    if (!q.trim()) return true
    const s = q.toLowerCase()
    return (t.subject || '').toLowerCase().includes(s) ||
           (t.from_name || '').toLowerCase().includes(s) ||
           (t.snippet || '').toLowerCase().includes(s)
  })

  return (
    <DashboardLayout>
      <div className="mb-4 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <InboxIcon size={18} className="text-white" />
        </div>
        <div className="flex-1">
          <h1 className="text-xl font-semibold text-brand-ink">Mailbox</h1>
          <p className="text-sm text-brand-muted">
            All practice email in one place — convert enquiries into appointments without leaving the dashboard.
          </p>
        </div>
        {pendingDraftsCount > 0 && (
          <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700 border border-amber-200">
            <AlertCircle size={13} /> {pendingDraftsCount} AI booking draft{pendingDraftsCount === 1 ? '' : 's'} pending review
          </span>
        )}
      </div>

      {accounts.length === 0 && (
        <div className="rounded-xl border border-brand-border bg-white p-8 text-center">
          <Mail size={32} className="mx-auto mb-3 text-brand-muted" />
          <h2 className="text-base font-semibold text-brand-ink">No mailboxes connected yet</h2>
          <p className="mt-1 text-sm text-brand-muted max-w-md mx-auto">
            Connect <code>info@drchalitaleroux.co.za</code> and your Gmail to see them here. The unified inbox supports
            Microsoft 365 (custom domain), Gmail (OAuth), and a managed provider path via <strong>Aurinko</strong> recommended for POPIA compliance.
          </p>
          <p className="mt-4 text-xs text-brand-muted">
            Setup is a Settings → Mail step (coming next). Once connected, threads + AI booking drafts populate here automatically.
          </p>
        </div>
      )}

      {accounts.length > 0 && (
        <div className="grid grid-cols-12 gap-4 h-[calc(100vh-200px)]">
          {/* ── Left rail: accounts + filters ─────────────────────── */}
          <aside className="col-span-2 overflow-y-auto rounded-xl border border-brand-border bg-white p-3">
            <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Accounts</p>
            <button onClick={() => goto({})}
              className={cn(
                'mb-1 flex w-full items-center justify-between rounded-lg px-2 py-1.5 text-xs font-medium',
                !filters.account_id ? 'bg-brand-primary text-white' : 'text-brand-ink hover:bg-brand-surface'
              )}>
              All accounts
            </button>
            {accounts.map((a) => (
              <button key={a.id} onClick={() => goto({ account_id: a.id })}
                className={cn(
                  'mb-1 flex w-full items-center justify-between gap-1 rounded-lg px-2 py-1.5 text-xs font-medium',
                  String(filters.account_id) === String(a.id) ? 'bg-brand-primary text-white' : 'text-brand-ink hover:bg-brand-surface'
                )}>
                <span className="truncate">{a.display_name || a.address}</span>
                {a.unread_count > 0 && <span className="text-[10px] font-semibold">{a.unread_count}</span>}
              </button>
            ))}

            {/* Folders (Outlook-style tree) for the selected account */}
            {(() => {
              const acct = accounts.find((a) => String(a.id) === String(filters.account_id))
              const folders = acct?.folders || []
              if (!acct || folders.length === 0) return null
              return (
                <>
                  <p className="mb-1 mt-4 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Folders</p>
                  {folders.map((f) => {
                    const active = filters.folder === f
                    const depth = (f.match(/[./]/g) || []).length
                    const label = f.split(/[./]/).filter(Boolean).pop() || f
                    return (
                      <button key={f} title={f}
                        onClick={() => goto({ account_id: acct.id, folder: active ? null : f })}
                        className={cn('mb-0.5 flex w-full items-center gap-1.5 rounded-lg py-1 pr-2 text-xs',
                          active ? 'bg-brand-primary text-white' : 'text-brand-ink hover:bg-brand-surface')}
                        style={{ paddingLeft: 8 + depth * 12 }}>
                        <Folder size={11} className="flex-shrink-0 opacity-70" />
                        <span className="truncate">{label}</span>
                      </button>
                    )
                  })}
                </>
              )
            })()}

            <p className="mb-2 mt-4 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Filters</p>
            {[
              { key: 'unread',               label: 'Unread' },
              { key: 'starred',              label: 'Starred', icon: Star },
              { key: 'appointment_requests', label: 'Appointment requests', icon: Calendar },
            ].map((f) => {
              const active = filters.filter === f.key
              const Icon = f.icon
              return (
                <button key={f.key} onClick={() => goto({ ...filters, filter: active ? null : f.key })}
                  className={cn(
                    'mb-1 flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-xs font-medium',
                    active ? 'bg-amber-50 text-amber-700' : 'text-brand-ink hover:bg-brand-surface'
                  )}>
                  {Icon && <Icon size={12} />} {f.label}
                </button>
              )
            })}

            <p className="mb-2 mt-4 text-[10px] font-semibold uppercase tracking-wide text-brand-muted">Categories</p>
            {Object.entries(INTENT_LABEL).map(([key, label]) => {
              const active = filters.intent === key
              return (
                <button key={key} onClick={() => goto({ ...filters, intent: active ? null : key })}
                  className={cn(
                    'mb-1 flex w-full items-center rounded-lg px-2 py-1.5 text-xs font-medium',
                    active ? 'bg-brand-primary/10 text-brand-primary' : 'text-brand-muted hover:bg-brand-surface'
                  )}>
                  {label}
                </button>
              )
            })}
          </aside>

          {/* ── Middle: conversation list ────────────────────────── */}
          <section className="col-span-4 overflow-hidden rounded-xl border border-brand-border bg-white">
            <div className="border-b border-brand-border p-2">
              <div className="flex items-center gap-2 rounded-lg border border-brand-border bg-white px-2 py-1.5">
                <Search size={13} className="text-brand-muted" />
                <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search subject, sender, body…"
                  className="w-full bg-transparent text-sm outline-none placeholder:text-brand-muted" />
              </div>
            </div>
            <div className="overflow-y-auto h-full">
              {filtered.length === 0 && <p className="p-6 text-center text-sm text-brand-muted">No conversations.</p>}
              {filtered.map((t) => (
                <Link key={t.id} href={`/mail?${new URLSearchParams({ ...filters, thread_id: t.id }).toString()}`}
                  className={cn(
                    'block border-b border-brand-border/60 px-3 py-2.5 hover:bg-brand-surface/40',
                    activeThread?.id === t.id && 'bg-brand-primary/5'
                  )}>
                  <div className="flex items-center gap-2">
                    <span className="truncate text-sm font-semibold text-brand-ink">{t.from_name}</span>
                    {t.unread_count > 0 && <span className="h-1.5 w-1.5 rounded-full bg-brand-primary" />}
                    {t.starred && <Star size={11} className="text-amber-500" />}
                    <span className="ml-auto text-[10px] text-brand-muted">{fmt(t.last_message_at)}</span>
                  </div>
                  <p className="mt-0.5 truncate text-sm text-brand-ink">{t.subject}</p>
                  <p className="mt-0.5 truncate text-xs text-brand-muted">{t.snippet}</p>
                  <div className="mt-1.5 flex items-center gap-1.5 text-[10px] text-brand-muted">
                    <span className="rounded bg-brand-surface px-1.5 py-0.5">{t.account_address}</span>
                    {t.clinical_intent && (
                      <span className="rounded bg-brand-primary/10 px-1.5 py-0.5 text-brand-primary">{INTENT_LABEL[t.clinical_intent] || t.clinical_intent}</span>
                    )}
                    {t.patient && (
                      <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-emerald-700">↪ {t.patient.name}</span>
                    )}
                  </div>
                </Link>
              ))}
            </div>
          </section>

          {/* ── Right: reading pane ──────────────────────────────── */}
          <section className="col-span-6 overflow-hidden rounded-xl border border-brand-border bg-white">
            {!activeThread ? (
              <div className="flex h-full flex-col items-center justify-center text-center text-sm text-brand-muted">
                <Mail size={28} className="mb-2" />
                <p>Select a conversation to read</p>
                <p className="mt-1 text-xs">AI booking drafts (if any) appear in this pane.</p>
              </div>
            ) : (
              <ReadingPane thread={activeThread} />
            )}
          </section>
        </div>
      )}
    </DashboardLayout>
  )
}

function ReadingPane({ thread }) {
  return (
    <div className="flex h-full flex-col">
      <header className="border-b border-brand-border p-4">
        <h2 className="text-base font-semibold text-brand-ink">{thread.subject}</h2>
        <p className="mt-0.5 text-xs text-brand-muted">{thread.message_count} message{thread.message_count === 1 ? '' : 's'} · {thread.participants?.join(', ')}</p>
        {thread.patient && (
          <Link href={`/patients/${thread.patient.id}`}
            className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-brand-primary hover:underline">
            ↪ {thread.patient.name} (confidence {Math.round((thread.patient.confidence || 0) * 100)}%) <ChevronRight size={11} />
          </Link>
        )}
      </header>

      {(thread.drafts || []).length > 0 && (
        <div className="border-b border-brand-border bg-amber-50/60 p-3">
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-amber-800">AI booking drafts — review &amp; confirm</p>
          {thread.drafts.map((d) => (
            <div key={d.id} className="mb-1 rounded-lg border border-amber-200 bg-white px-3 py-2 text-sm">
              <p className="font-medium text-brand-ink">
                {d.requested_start_time ? new Date(d.requested_start_time).toLocaleString('en-ZA') : 'Time TBC'} ·
                {' '}{d.requested_duration_minutes || '?'}m · {d.requested_reason || '(reason TBC)'}
              </p>
              <p className="mt-0.5 text-xs text-brand-muted">Confidence {Math.round((d.confidence || 0) * 100)}% · status {d.status}</p>
            </div>
          ))}
        </div>
      )}

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {(thread.messages || []).map((m) => (
          <article key={m.id} className="rounded-xl border border-brand-border bg-white p-4">
            <div className="mb-2 flex items-center gap-2 text-sm">
              <span className="font-semibold text-brand-ink">{m.from_name || m.from_address}</span>
              <span className="text-brand-muted">→ {m.to_addresses?.join(', ')}</span>
              <span className="ml-auto text-xs text-brand-muted">{fmt(m.received_at)}</span>
            </div>
            {m.has_attachments && (
              <p className="mb-2 inline-flex items-center gap-1 rounded bg-brand-surface px-2 py-0.5 text-xs text-brand-muted">
                <Paperclip size={11} /> Attachments
              </p>
            )}
            <div className="prose prose-sm max-w-none text-sm text-brand-ink whitespace-pre-wrap">
              {m.body_text || (m.body_html ? <em>HTML body (sanitised render coming next)</em> : <em className="text-brand-muted">No body</em>)}
            </div>
          </article>
        ))}
      </div>
    </div>
  )
}
