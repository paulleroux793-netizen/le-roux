import React, { useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  MessageSquare, Search, Upload,
  ChevronLeft, ChevronRight, Clock, X as XIcon,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

// ── Conversations list ─────────────────────────────────────────────
// Phase 10 — Historical WhatsApp imports live alongside live webhook
// threads in the same table. The list is restyled as a compact row
// layout (not the old card layout) so a receptionist can scan
// hundreds of rows quickly:
//
//   [icon]  Patient / phone        Topic snippet        [time]  [⧉ history]
//
// Primary row click opens WhatsApp (wa.me/<digits>) in a new tab so
// the receptionist can jump straight into the thread. The small
// history icon button opens our internal transcript view instead
// (kept separate so a click on the row always does the "useful"
// thing the user asked for).

const PAGE_SIZE = 10

export default function Conversations({ conversations = [], filters }) {
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(0)
  const [importOpen, setImportOpen] = useState(false)

  const filtered = useMemo(() => {
    if (!query.trim()) return conversations
    const q = query.toLowerCase()
    return conversations.filter((c) =>
      [c.patient_name, c.patient_phone, c.topic, c.last_message]
        .filter(Boolean)
        .some((s) => s.toLowerCase().includes(q))
    )
  }, [conversations, query])

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageItems = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)

  const handleFilter = (key, value) => {
    router.get('/conversations', { ...filters, [key]: value || undefined }, { preserveState: true })
  }

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-start justify-between gap-4">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
            Communication hub
          </span>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">Conversations</h1>
          <p className="mt-2 text-sm leading-6 text-brand-muted">WhatsApp and voice call transcripts</p>
        </div>
        <button
          type="button"
          onClick={() => setImportOpen(true)}
          className="inline-flex items-center gap-2 rounded-2xl bg-brand-primary px-4 py-2.5 text-sm font-medium text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark"
        >
          <Upload size={15} />
          Import chats
        </button>
      </div>

      {/* Toolbar: search + channel/source filters */}
      <div className="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-brand-accent/75 bg-white p-3 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <div className="relative flex-1 min-w-[240px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted" />
          <input
            type="text"
            value={query}
            onChange={(e) => { setQuery(e.target.value); setPage(0) }}
            placeholder="Search customer, phone or topic…"
            className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 pl-9 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
          />
        </div>

        <FilterPill
          value={filters?.source || ''}
          onChange={(v) => handleFilter('source', v)}
          options={[
            { value: '', label: 'All sources' },
            { value: 'live', label: 'Live' },
            { value: 'import', label: 'Imported' },
          ]}
        />
        <FilterPill
          value={filters?.channel || ''}
          onChange={(v) => handleFilter('channel', v)}
          options={[
            { value: '', label: 'All channels' },
            { value: 'whatsapp', label: 'WhatsApp' },
            { value: 'voice', label: 'Voice' },
          ]}
        />
      </div>

      {/* Row list */}
      <div className="overflow-hidden rounded-xl border border-brand-accent/75 bg-white shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        {/* List header */}
        <div className="flex items-center gap-3 border-b border-brand-accent/60 bg-brand-surface/25 px-5 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-brand-muted">
          <span className="w-9" />
          <span className="flex-1">Customer</span>
          <span className="hidden md:block w-[38%]">Topic / last message</span>
          <span className="w-28 text-right">When</span>
          <span className="w-20" />
        </div>

        {pageItems.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-brand-surface">
              <MessageSquare size={18} className="text-brand-primary" />
            </div>
            <p className="text-sm text-brand-muted">No conversations match.</p>
          </div>
        ) : (
          <ul className="divide-y divide-brand-accent/35">
            {pageItems.map((c) => (
              <ConversationRow key={c.id} conv={c} />
            ))}
          </ul>
        )}

        {/* Pagination footer */}
        {filtered.length > 0 && (
          <div className="flex items-center justify-between border-t border-brand-accent/60 px-5 py-3 text-xs text-brand-muted">
            <span>
              Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, filtered.length)} of {filtered.length}
            </span>
            <div className="flex items-center gap-1">
              <button
                type="button"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                className="rounded-xl p-1.5 hover:bg-brand-surface/45 disabled:opacity-40 disabled:hover:bg-transparent"
                aria-label="Previous page"
              >
                <ChevronLeft size={14} />
              </button>
              <span className="px-2">
                {page + 1} / {pageCount}
              </span>
              <button
                type="button"
                disabled={page + 1 >= pageCount}
                onClick={() => setPage((p) => Math.min(pageCount - 1, p + 1))}
                className="rounded-xl p-1.5 hover:bg-brand-surface/45 disabled:opacity-40 disabled:hover:bg-transparent"
                aria-label="Next page"
              >
                <ChevronRight size={14} />
              </button>
            </div>
          </div>
        )}
      </div>

      <ImportModal open={importOpen} onClose={() => setImportOpen(false)} />
    </DashboardLayout>
  )
}

function ConversationRow({ conv }) {
  // Row click → open the internal transcript. The receptionist can
  // read the full exchange and reply from within the app; we no
  // longer bounce out to wa.me on primary click.
  const openConversation = () => {
    router.visit(`/conversations/${conv.id}`)
  }

  const snippet = conv.topic || conv.last_message || '—'
  const relative = formatRelative(conv.updated_at)

  return (
    <li
      onClick={openConversation}
      className="group flex cursor-pointer items-center gap-3 px-5 py-3.5 transition-colors hover:bg-brand-surface/25"
    >
      {/* Channel icon */}
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
        conv.channel === 'whatsapp' ? 'bg-brand-success/10 text-brand-success' : 'bg-brand-primary/10 text-brand-primary'
      }`}>
        <MessageSquare size={16} />
      </div>

      {/* Patient */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="truncate text-sm font-medium text-brand-ink group-hover:text-brand-primary">
            {conv.patient_name}
          </p>
          {conv.source === 'import' && (
            <span className="rounded-full bg-brand-surface px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-brand-primary">
              Imported
            </span>
          )}
        </div>
        <p className="mt-0.5 truncate text-[11px] text-brand-muted">{conv.patient_phone}</p>
      </div>

      {/* Topic / last message */}
      <div className="hidden md:block w-[38%] min-w-0">
        {conv.topic && (
          <p className="truncate text-xs font-medium text-brand-primary">{conv.topic}</p>
        )}
        {conv.last_message && (
          <p className="mt-0.5 truncate text-xs text-brand-muted">{conv.last_message}</p>
        )}
        {!conv.topic && !conv.last_message && (
          <p className="text-xs text-brand-muted/70">No messages</p>
        )}
      </div>
      {/* Mobile fallback — show a single snippet line under the name */}
      <div className="max-w-[40%] truncate text-xs text-brand-muted md:hidden">
        {snippet}
      </div>

      {/* Time */}
      <div className="w-28 text-right flex-shrink-0">
        <span className="inline-flex items-center gap-1 text-[11px] text-brand-muted">
          <Clock size={10} />
          {relative}
        </span>
      </div>

      {/* Message count */}
      <div className="w-20 flex items-center justify-end flex-shrink-0">
        <span className="text-[11px] text-brand-muted">{conv.message_count} msgs</span>
      </div>
    </li>
  )
}

function FilterPill({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-xs font-medium text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>{o.label}</option>
      ))}
    </select>
  )
}

function ImportModal({ open, onClose }) {
  const [file, setFile] = useState(null)
  const [ownerName, setOwnerName] = useState('Dr Le Roux')
  const [patientPhone, setPatientPhone] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (!open) return null

  const isTxt = file && /\.txt$/i.test(file.name)

  const handleSubmit = (e) => {
    e.preventDefault()
    if (!file) {
      toast.error('Please choose a file to import')
      return
    }
    const formData = new FormData()
    formData.append('file', file)
    if (isTxt) {
      formData.append('owner_name', ownerName)
      formData.append('patient_phone', patientPhone)
    }
    setSubmitting(true)
    router.post('/conversations/import', formData, {
      forceFormData: true,
      onSuccess: () => { onClose(); setFile(null); setPatientPhone('') },
      onError:   () => toast.error('Import failed'),
      onFinish:  () => setSubmitting(false),
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-brand-ink/30 p-4 backdrop-blur-[4px]">
      <div className="w-full max-w-md rounded-xl border border-brand-accent/80 bg-white shadow-[0_38px_90px_-55px_rgba(57,60,77,0.5)]">
        <div className="flex items-center justify-between border-b border-brand-accent/70 bg-gradient-to-br from-brand-surface/45 via-white to-white px-5 py-4">
          <h2 className="text-sm font-semibold text-brand-ink">Import historical chats</h2>
          <button type="button" onClick={onClose} className="rounded-xl p-1 text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink">
            <XIcon size={16} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-brand-muted">
              Export file (.json preferred, .txt supported)
            </label>
            <input
              type="file"
              accept=".json,.txt"
              onChange={(e) => setFile(e.target.files?.[0] || null)}
              className="block w-full text-xs text-brand-muted file:mr-3 file:rounded-2xl file:border-0 file:bg-brand-surface file:px-3 file:py-2 file:text-xs file:font-semibold file:text-brand-primary hover:file:bg-brand-accent"
            />
            <p className="mt-1.5 text-[11px] text-brand-muted">
              JSON should be an array of threads with <code>phone</code>, <code>name</code>, <code>messages[]</code>.
            </p>
          </div>

          {isTxt && (
            <>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-brand-muted">
                  Owner (clinic) name as it appears in the export
                </label>
                <input
                  type="text"
                  value={ownerName}
                  onChange={(e) => setOwnerName(e.target.value)}
                  className="w-full rounded-2xl border border-brand-accent/80 px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-brand-muted">
                  Patient phone (E.164, e.g. +27831234567)
                </label>
                <input
                  type="tel"
                  value={patientPhone}
                  onChange={(e) => setPatientPhone(e.target.value)}
                  required
                  className="w-full rounded-2xl border border-brand-accent/80 px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
                />
              </div>
            </>
          )}

          <div className="flex items-center justify-end gap-2 pt-2">
            <button type="button" onClick={onClose} className="rounded-2xl px-3 py-2 text-xs font-medium text-brand-muted hover:bg-brand-surface/45">
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting || !file}
              className="inline-flex items-center gap-2 rounded-2xl bg-brand-primary px-4 py-2 text-xs font-medium text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] hover:bg-brand-primary-dark disabled:opacity-50"
            >
              <Upload size={13} />
              {submitting ? 'Importing…' : 'Import'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function formatRelative(iso) {
  if (!iso) return '—'
  const d = new Date(iso)
  const diffMs = Date.now() - d.getTime()
  const mins = Math.round(diffMs / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.round(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.round(hrs / 24)
  if (days < 7) return `${days}d ago`
  return d.toLocaleDateString('en-ZA', { month: 'short', day: 'numeric' })
}
