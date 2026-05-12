import React, { useEffect, useMemo, useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  MessageSquare, Search, Upload, Send, Phone, Tag,
  Plus, X as XIcon, ExternalLink, MoreVertical,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { useLanguage } from '../lib/LanguageContext'

// WhatsApp Web-style 2-column conversations view:
//   left  → searchable list of threads (sidebar)
//   right → message bubbles + reply composer for the selected thread
//
// The Rails controller hydrates both the list AND the selected thread in
// one request — when you click a row we use Inertia partial reload with
// preserveScroll so only the right pane swaps.

export default function Conversations({
  conversations = [],
  selected_conversation = null,
  filters,
  all_tags = [],
}) {
  const { t, language } = useLanguage()
  const [query, setQuery] = useState('')
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

  const handleFilter = (key, value) => {
    router.get(
      '/conversations',
      { ...filters, [key]: value || undefined, selected_id: selected_conversation?.id || undefined },
      { preserveState: true, preserveScroll: true }
    )
  }

  const openConversation = (c) => {
    router.get(
      '/conversations',
      { ...filters, selected_id: c.id },
      { preserveState: true, preserveScroll: true }
    )
  }

  return (
    <DashboardLayout>
      <div className="flex h-[calc(100vh-120px)] overflow-hidden rounded-xl border border-brand-accent/75 bg-white shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">

        {/* ── LEFT: sidebar (conversation list) ───────────────────────── */}
        <aside className="flex w-[360px] flex-shrink-0 flex-col border-r border-brand-accent/60 bg-[#f0f2f5]">
          {/* Sidebar header */}
          <div className="flex items-center justify-between gap-2 bg-[#f0f2f5] px-4 py-3 border-b border-brand-accent/40">
            <h1 className="text-base font-semibold text-brand-ink">{t('conv_title')}</h1>
            <button
              type="button"
              onClick={() => setImportOpen(true)}
              className="rounded-full p-2 text-brand-muted hover:bg-brand-accent/30 hover:text-brand-primary transition-colors"
              title={t('conv_import')}
              aria-label={t('conv_import')}
            >
              <Upload size={16} />
            </button>
          </div>

          {/* Search */}
          <div className="bg-white px-3 py-2 border-b border-brand-accent/30">
            <div className="relative">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted" />
              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={t('conv_search')}
                className="w-full rounded-lg bg-[#f0f2f5] py-2 pl-9 pr-3 text-sm text-brand-ink placeholder:text-brand-muted focus:outline-none focus:ring-2 focus:ring-brand-primary/30"
              />
            </div>
          </div>

          {/* Filters row */}
          <div className="flex items-center gap-1.5 border-b border-brand-accent/30 bg-white px-3 py-2 overflow-x-auto">
            <MiniFilter
              value={filters?.channel || ''}
              onChange={(v) => handleFilter('channel', v)}
              options={[
                { value: '', label: t('conv_all_channels') },
                { value: 'whatsapp', label: 'WhatsApp' },
                { value: 'voice', label: 'Voice' },
              ]}
            />
            <MiniFilter
              value={filters?.tag || ''}
              onChange={(v) => handleFilter('tag', v)}
              options={[
                { value: '', label: 'All tags' },
                ...all_tags.map((tag) => ({ value: tag, label: tag })),
              ]}
            />
          </div>

          {/* Conversation list */}
          <ul className="flex-1 overflow-y-auto">
            {filtered.length === 0 ? (
              <li className="px-6 py-16 text-center text-sm text-brand-muted">
                <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-brand-accent/30">
                  <MessageSquare size={18} className="text-brand-primary" />
                </div>
                {t('conv_no_match')}
              </li>
            ) : (
              filtered.map((c) => (
                <SidebarRow
                  key={c.id}
                  conv={c}
                  active={selected_conversation?.id === c.id}
                  onClick={() => openConversation(c)}
                  language={language}
                  t={t}
                />
              ))
            )}
          </ul>
        </aside>

        {/* ── RIGHT: chat thread ──────────────────────────────────────── */}
        <main className="flex flex-1 flex-col bg-[#efeae2]">
          {selected_conversation ? (
            <ChatPane conv={selected_conversation} />
          ) : (
            <EmptyChatState t={t} />
          )}
        </main>
      </div>

      <ImportModal open={importOpen} onClose={() => setImportOpen(false)} t={t} />
    </DashboardLayout>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Sidebar row — WhatsApp-style conversation card
// ──────────────────────────────────────────────────────────────────────
function SidebarRow({ conv, active, onClick, language, t }) {
  const relative = formatShortTime(conv.updated_at, language)
  const preview = conv.last_message || conv.topic || `(${conv.message_count || 0} ${t('conv_msgs') || 'messages'})`
  const isFlagged = (conv.tags || []).includes('needs_review')

  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        className={`w-full text-left flex items-center gap-3 px-3 py-2.5 border-b border-brand-accent/20 transition-colors ${
          active ? 'bg-[#e7f3ec]' : 'hover:bg-[#f5f6f6]'
        }`}
      >
        <div className="flex-shrink-0 w-11 h-11 rounded-full bg-brand-primary/15 flex items-center justify-center text-brand-primary text-sm font-semibold">
          {initials(conv.patient_name)}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2">
            <p className="truncate text-sm font-medium text-brand-ink">
              {conv.patient_name || conv.patient_phone}
            </p>
            <span className="flex-shrink-0 text-[11px] text-brand-muted">{relative}</span>
          </div>
          <div className="flex items-center justify-between gap-2 mt-0.5">
            <p className="truncate text-xs text-brand-muted">{preview}</p>
            <div className="flex items-center gap-1 flex-shrink-0">
              {isFlagged && (
                <span
                  className="inline-flex items-center rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700"
                  title="Needs reception review"
                >
                  Flag
                </span>
              )}
              {conv.language === 'af' && (
                <span className="rounded-full bg-emerald-100 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-700">
                  AF
                </span>
              )}
            </div>
          </div>
        </div>
      </button>
    </li>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Chat pane (right side) — header, scrolling bubble feed, composer
// ──────────────────────────────────────────────────────────────────────
function ChatPane({ conv }) {
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const scrollRef = useRef(null)

  useEffect(() => {
    const el = scrollRef.current
    if (el) el.scrollTop = el.scrollHeight
  }, [conv.id, conv.messages?.length])

  const canReply = conv.channel === 'whatsapp'

  const handleSend = (e) => {
    e?.preventDefault?.()
    const trimmed = body.trim()
    if (!trimmed) return
    setSending(true)
    router.post(`/conversations/${conv.id}/reply`, { body: trimmed }, {
      preserveScroll: true,
      onSuccess: () => { setBody(''); toast.success('Reply sent — AI paused 4 hrs on this conversation') },
      onError:   () => toast.error('Could not send reply'),
      onFinish:  () => setSending(false),
    })
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend(e)
    }
  }

  return (
    <>
      {/* Header */}
      <div className="flex items-center gap-3 border-b border-brand-accent/30 bg-[#f0f2f5] px-4 py-3">
        <div className="flex-shrink-0 w-10 h-10 rounded-full bg-brand-primary/15 flex items-center justify-center text-brand-primary text-sm font-semibold">
          {initials(conv.patient_name)}
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold text-brand-ink">
            {conv.patient_name || conv.patient_phone}
          </p>
          <p className="truncate text-[11px] text-brand-muted">
            <Phone size={10} className="inline mr-1" />
            {conv.patient_phone}
            {conv.language && (
              <span className="ml-2 text-brand-primary/70">{conv.language === 'af' ? 'Afrikaans' : 'English'}</span>
            )}
          </p>
        </div>
        {conv.patient_id && (
          <a
            href={`/patients/${conv.patient_id}`}
            className="inline-flex items-center gap-1 rounded-full border border-brand-primary/20 bg-white/60 px-2.5 py-1 text-[11px] font-semibold text-brand-primary hover:bg-brand-primary/10 transition-colors"
          >
            <ExternalLink size={10} /> Patient
          </a>
        )}
      </div>

      {/* Bubble feed */}
      <div
        ref={scrollRef}
        className="flex-1 overflow-y-auto px-4 py-5 space-y-2 bg-[#efeae2]"
        style={{ backgroundImage: "url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22100%22 height=%22100%22><rect width=%22100%22 height=%22100%22 fill=%22%23efeae2%22/></svg>')" }}
      >
        {conv.messages?.length > 0 ? (
          conv.messages.map((m, i) => <Bubble key={i} msg={m} />)
        ) : (
          <div className="flex h-full items-center justify-center text-sm text-brand-muted">
            No messages yet
          </div>
        )}
      </div>

      {/* Composer */}
      {canReply ? (
        <form
          onSubmit={handleSend}
          className="flex items-end gap-2 border-t border-brand-accent/30 bg-[#f0f2f5] px-3 py-2"
        >
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={sending}
            placeholder="Type a message"
            rows={1}
            className="flex-1 resize-none max-h-28 min-h-[42px] rounded-lg border-0 bg-white px-3 py-2.5 text-sm text-brand-ink placeholder:text-brand-muted focus:outline-none focus:ring-2 focus:ring-brand-primary/30"
          />
          <button
            type="submit"
            disabled={sending || !body.trim()}
            className="h-10 w-10 rounded-full bg-brand-primary text-white flex items-center justify-center hover:bg-brand-primary/90 disabled:opacity-40 disabled:cursor-not-allowed transition-colors flex-shrink-0"
            aria-label="Send"
          >
            {sending ? (
              <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
            ) : (
              <Send size={16} />
            )}
          </button>
        </form>
      ) : (
        <div className="border-t border-brand-accent/30 bg-amber-50 px-4 py-3 text-xs text-amber-700">
          Replies are only supported on WhatsApp conversations.
        </div>
      )}
    </>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Bubble — message in chat feed
// ──────────────────────────────────────────────────────────────────────
function Bubble({ msg }) {
  const isClinic = msg.role === 'assistant'
  return (
    <div className={`flex ${isClinic ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`max-w-[70%] rounded-lg px-3 py-2 shadow-sm ${
          isClinic
            ? 'bg-[#d9fdd3] text-brand-ink rounded-tr-sm'
            : 'bg-white text-brand-ink rounded-tl-sm'
        }`}
      >
        <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{msg.content}</p>
        {msg.timestamp && (
          <p className="text-[10px] mt-0.5 text-brand-muted text-right">
            {formatTime(msg.timestamp)}
          </p>
        )}
      </div>
    </div>
  )
}

function EmptyChatState({ t }) {
  return (
    <div className="flex h-full flex-col items-center justify-center text-center px-8">
      <div className="mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-white shadow">
        <MessageSquare size={32} className="text-brand-primary" />
      </div>
      <h2 className="text-lg font-semibold text-brand-ink">Select a conversation</h2>
      <p className="mt-1 max-w-xs text-sm text-brand-muted">
        Pick a chat on the left to read messages and reply on behalf of the practice.
      </p>
    </div>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Mini filter pill (used in sidebar)
// ──────────────────────────────────────────────────────────────────────
function MiniFilter({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="rounded-full bg-[#f0f2f5] border border-brand-accent/40 px-2.5 py-1 text-[11px] font-medium text-brand-ink hover:bg-brand-accent/20 focus:outline-none focus:ring-2 focus:ring-brand-primary/30"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>{o.label}</option>
      ))}
    </select>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Import modal (kept compatible with original Conversations page)
// ──────────────────────────────────────────────────────────────────────
function ImportModal({ open, onClose, t }) {
  const [file, setFile] = useState(null)
  const [ownerName, setOwnerName] = useState('Dr Le Roux')
  const [patientPhone, setPatientPhone] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (!open) return null

  const handleSubmit = (e) => {
    e.preventDefault()
    if (!file) return
    setSubmitting(true)
    const fd = new FormData()
    fd.append('file', file)
    if (ownerName.trim()) fd.append('owner_name', ownerName.trim())
    if (patientPhone.trim()) fd.append('patient_phone', patientPhone.trim())
    router.post('/conversations/import', fd, {
      forceFormData: true,
      onFinish: () => { setSubmitting(false); onClose() },
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/45 px-4">
      <div className="bg-white rounded-xl p-6 w-full max-w-md shadow-2xl">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-brand-ink">Import conversations</h2>
          <button onClick={onClose} className="text-brand-muted hover:text-brand-ink"><XIcon size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-brand-muted mb-1">File (.json, .txt, .zip)</label>
            <input type="file" accept=".json,.txt,.zip" onChange={(e) => setFile(e.target.files[0])}
              className="w-full text-xs file:mr-2 file:rounded file:border-0 file:bg-brand-primary file:text-white file:px-3 file:py-1.5 file:text-xs file:font-medium" />
          </div>
          <div>
            <label className="block text-xs font-medium text-brand-muted mb-1">Owner name</label>
            <input type="text" value={ownerName} onChange={(e) => setOwnerName(e.target.value)}
              className="w-full text-sm rounded-lg border border-brand-accent/60 px-3 py-2" />
          </div>
          <div>
            <label className="block text-xs font-medium text-brand-muted mb-1">Patient phone (optional, for chats where the owner exported alone)</label>
            <input type="text" value={patientPhone} onChange={(e) => setPatientPhone(e.target.value)} placeholder="+27..."
              className="w-full text-sm rounded-lg border border-brand-accent/60 px-3 py-2" />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={onClose} className="px-3 py-2 text-sm text-brand-muted hover:text-brand-ink">Cancel</button>
            <button type="submit" disabled={!file || submitting} className="px-3 py-2 text-sm rounded-lg bg-brand-primary text-white hover:bg-brand-primary/90 disabled:opacity-40">
              {submitting ? 'Importing…' : 'Import'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────
function initials(name = '') {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() || '')
    .join('') || '·'
}

function formatTime(iso) {
  try {
    const d = new Date(iso)
    return d.toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })
  } catch {
    return ''
  }
}

function formatShortTime(iso, language) {
  if (!iso) return ''
  const locale = language === 'af' ? 'af-ZA' : 'en-ZA'
  const d = new Date(iso)
  const now = new Date()
  const sameDay = d.toDateString() === now.toDateString()
  if (sameDay) {
    return d.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' })
  }
  const diffDays = Math.round((now - d) / (1000 * 60 * 60 * 24))
  if (diffDays < 7) {
    return d.toLocaleDateString(locale, { weekday: 'short' })
  }
  return d.toLocaleDateString(locale, { month: 'short', day: 'numeric' })
}
