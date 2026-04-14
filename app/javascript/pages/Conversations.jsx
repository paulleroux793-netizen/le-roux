import React, { useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  MessageSquare, Search, Upload, History, ExternalLink,
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
          <h1 className="text-2xl font-bold text-brand-brown">Conversations</h1>
          <p className="text-gray-500 mt-1 text-sm">WhatsApp and voice call transcripts</p>
        </div>
        <button
          type="button"
          onClick={() => setImportOpen(true)}
          className="inline-flex items-center gap-2 bg-brand-brown text-white text-sm font-medium px-4 py-2 rounded-lg hover:bg-brand-brown/90 transition-colors"
        >
          <Upload size={15} />
          Import chats
        </button>
      </div>

      {/* Toolbar: search + channel/source filters */}
      <div className="bg-white rounded-xl border border-gray-200 p-3 mb-4 flex flex-wrap items-center gap-3">
        <div className="relative flex-1 min-w-[240px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            value={query}
            onChange={(e) => { setQuery(e.target.value); setPage(0) }}
            placeholder="Search customer, phone or topic…"
            className="w-full pl-9 pr-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe"
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
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        {/* List header */}
        <div className="flex items-center gap-3 px-5 py-2.5 bg-gray-50 border-b border-gray-100 text-[11px] font-semibold uppercase tracking-wide text-gray-500">
          <span className="w-9" />
          <span className="flex-1">Customer</span>
          <span className="hidden md:block w-[38%]">Topic / last message</span>
          <span className="w-28 text-right">When</span>
          <span className="w-20" />
        </div>

        {pageItems.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div className="w-12 h-12 mx-auto rounded-full bg-brand-cream flex items-center justify-center mb-3">
              <MessageSquare size={18} className="text-brand-taupe" />
            </div>
            <p className="text-sm text-gray-500">No conversations match.</p>
          </div>
        ) : (
          <ul className="divide-y divide-gray-100">
            {pageItems.map((c) => (
              <ConversationRow key={c.id} conv={c} />
            ))}
          </ul>
        )}

        {/* Pagination footer */}
        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-5 py-3 border-t border-gray-100 text-xs text-gray-500">
            <span>
              Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, filtered.length)} of {filtered.length}
            </span>
            <div className="flex items-center gap-1">
              <button
                type="button"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                className="p-1.5 rounded-md hover:bg-gray-100 disabled:opacity-40 disabled:hover:bg-transparent"
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
                className="p-1.5 rounded-md hover:bg-gray-100 disabled:opacity-40 disabled:hover:bg-transparent"
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
  const openWhatsApp = () => {
    if (conv.whatsapp_url) {
      window.open(conv.whatsapp_url, '_blank', 'noopener,noreferrer')
    } else {
      toast.error('No phone number on file')
    }
  }

  const openHistory = (e) => {
    e.stopPropagation()
    router.visit(`/conversations/${conv.id}`)
  }

  const snippet = conv.topic || conv.last_message || '—'
  const relative = formatRelative(conv.updated_at)

  return (
    <li
      onClick={openWhatsApp}
      className="flex items-center gap-3 px-5 py-3.5 hover:bg-brand-cream/30 transition-colors cursor-pointer group"
    >
      {/* Channel icon */}
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
        conv.channel === 'whatsapp' ? 'bg-emerald-50 text-emerald-600' : 'bg-blue-50 text-blue-600'
      }`}>
        <MessageSquare size={16} />
      </div>

      {/* Patient */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-gray-900 truncate group-hover:text-brand-brown">
            {conv.patient_name}
          </p>
          {conv.source === 'import' && (
            <span className="text-[10px] font-semibold px-1.5 py-0.5 rounded-full bg-purple-100 text-purple-700 uppercase tracking-wide">
              Imported
            </span>
          )}
        </div>
        <p className="text-[11px] text-gray-400 mt-0.5 truncate">{conv.patient_phone}</p>
      </div>

      {/* Topic / last message */}
      <div className="hidden md:block w-[38%] min-w-0">
        {conv.topic && (
          <p className="text-xs font-medium text-brand-taupe truncate">{conv.topic}</p>
        )}
        {conv.last_message && (
          <p className="text-xs text-gray-400 mt-0.5 truncate">{conv.last_message}</p>
        )}
        {!conv.topic && !conv.last_message && (
          <p className="text-xs text-gray-300">No messages</p>
        )}
      </div>
      {/* Mobile fallback — show a single snippet line under the name */}
      <div className="md:hidden text-xs text-gray-400 truncate max-w-[40%]">
        {snippet}
      </div>

      {/* Time */}
      <div className="w-28 text-right flex-shrink-0">
        <span className="inline-flex items-center gap-1 text-[11px] text-gray-500">
          <Clock size={10} />
          {relative}
        </span>
      </div>

      {/* Actions */}
      <div className="w-20 flex items-center justify-end gap-1 flex-shrink-0">
        <button
          type="button"
          onClick={openHistory}
          title="View internal transcript"
          aria-label="View internal transcript"
          className="p-2 rounded-md text-gray-400 hover:text-brand-brown hover:bg-brand-cream"
        >
          <History size={14} />
        </button>
        <span
          title="Opens in WhatsApp"
          className="p-2 rounded-md text-gray-300 group-hover:text-emerald-600"
        >
          <ExternalLink size={14} />
        </span>
      </div>
    </li>
  )
}

function FilterPill({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="text-xs font-medium border border-gray-200 rounded-lg px-3 py-2 bg-white text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-taupe/25 focus:border-brand-taupe"
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
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl shadow-xl w-full max-w-md">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h2 className="text-sm font-semibold text-brand-brown">Import historical chats</h2>
          <button type="button" onClick={onClose} className="p-1 rounded-md hover:bg-gray-100 text-gray-400">
            <XIcon size={16} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1.5">
              Export file (.json preferred, .txt supported)
            </label>
            <input
              type="file"
              accept=".json,.txt"
              onChange={(e) => setFile(e.target.files?.[0] || null)}
              className="block w-full text-xs text-gray-600 file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0 file:text-xs file:font-semibold file:bg-brand-cream file:text-brand-brown hover:file:bg-brand-cream/70"
            />
            <p className="text-[11px] text-gray-400 mt-1.5">
              JSON should be an array of threads with <code>phone</code>, <code>name</code>, <code>messages[]</code>.
            </p>
          </div>

          {isTxt && (
            <>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1.5">
                  Owner (clinic) name as it appears in the export
                </label>
                <input
                  type="text"
                  value={ownerName}
                  onChange={(e) => setOwnerName(e.target.value)}
                  className="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-taupe/25"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1.5">
                  Patient phone (E.164, e.g. +27831234567)
                </label>
                <input
                  type="tel"
                  value={patientPhone}
                  onChange={(e) => setPatientPhone(e.target.value)}
                  required
                  className="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-taupe/25"
                />
              </div>
            </>
          )}

          <div className="flex items-center justify-end gap-2 pt-2">
            <button type="button" onClick={onClose} className="text-xs font-medium text-gray-500 px-3 py-2 rounded-lg hover:bg-gray-100">
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting || !file}
              className="inline-flex items-center gap-2 bg-brand-brown text-white text-xs font-medium px-4 py-2 rounded-lg hover:bg-brand-brown/90 disabled:opacity-50"
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
