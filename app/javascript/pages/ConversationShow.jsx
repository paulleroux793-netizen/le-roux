import React, { useEffect, useRef, useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { toast } from 'sonner'
import { ArrowLeft, Send, Phone, MessageCircle, Tag, X as XIcon, Plus, ExternalLink } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

// ── Conversation detail + reply composer ───────────────────────────
// Phase 10.1 — the receptionist reads the full transcript here and
// can type a WhatsApp reply directly into the thread. Send posts to
// POST /conversations/:id/reply which pushes the text out via
// Twilio (free-form, subject to the 24h customer-service window)
// and appends it to the JSONB messages array as an "assistant"
// entry — same shape the webhook produces — so the transcript
// stays consistent.
//
// Palette: white surfaces, light-blue (sky) accents for clinic
// bubbles / active states / focus rings, neutral greys for
// borders and secondary text. No custom brand tokens — every
// class is a stock Tailwind hue so the page renders identically
// regardless of theme config.

export default function ConversationShow({ conversation }) {
  const conv = conversation
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const scrollRef = useRef(null)

  // Auto-scroll to the latest message whenever the transcript
  // changes length (either a new webhook message or a successful
  // reply that Inertia just re-rendered).
  useEffect(() => {
    const el = scrollRef.current
    if (el) el.scrollTop = el.scrollHeight
  }, [conv.messages?.length])

  const canReply = conv.channel === 'whatsapp'

  const handleSend = (e) => {
    e.preventDefault()
    const trimmed = body.trim()
    if (!trimmed) return

    setSending(true)
    router.post(`/conversations/${conv.id}/reply`, { body: trimmed }, {
      preserveScroll: false,
      onSuccess: () => { setBody(''); toast.success('Reply sent') },
      onError:   () => toast.error('Could not send reply'),
      onFinish:  () => setSending(false),
    })
  }

  const handleKeyDown = (e) => {
    // Enter to send, Shift+Enter to insert a newline — same convention
    // as WhatsApp Web / Slack / iMessage on macOS.
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend(e)
    }
  }

  return (
    <DashboardLayout>
      <div className="mb-5">
        <Link
          href="/conversations"
          className="inline-flex items-center gap-1.5 text-sm text-sky-600 hover:text-sky-700 transition-colors"
        >
          <ArrowLeft size={14} /> Back to Conversations
        </Link>
      </div>

      {/* Header card */}
      <div className="bg-white rounded-xl border border-gray-200 p-5 mb-4 shadow-sm">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-11 h-11 rounded-full bg-sky-50 flex items-center justify-center flex-shrink-0 border border-sky-100">
              <span className="text-sky-700 text-sm font-semibold">
                {initials(conv.patient_name)}
              </span>
            </div>
            <div className="min-w-0">
              <h1 className="text-lg font-bold text-gray-900 truncate">{conv.patient_name}</h1>
              <p className="text-xs text-gray-500 mt-0.5 flex items-center gap-1.5">
                <Phone size={11} />
                {conv.patient_phone}
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2 flex-shrink-0">
            <Chip
              label={conv.channel}
              tone={conv.channel === 'whatsapp' ? 'sky' : 'blue'}
            />
            <Chip
              label={conv.status}
              tone={conv.status === 'active' ? 'sky' : 'gray'}
            />
            {conv.language && (
              <Chip
                label={conv.language === 'af' ? 'Afrikaans' : 'English'}
                tone={conv.language === 'af' ? 'green' : 'gray'}
              />
            )}
            {conv.source === 'import' && <Chip label="Imported" tone="slate" />}
            {conv.patient_id && (
              <Link
                href={`/patients/${conv.patient_id}`}
                className="inline-flex items-center gap-1 rounded-full border border-sky-100 bg-sky-50 px-2.5 py-1 text-[11px] font-semibold text-sky-700 hover:bg-sky-100 transition-colors"
              >
                <ExternalLink size={10} />
                View patient
              </Link>
            )}
          </div>
        </div>
        {conv.topic && (
          <p className="text-xs text-gray-500 mt-3">
            Topic: <span className="font-medium text-sky-700">{conv.topic}</span>
          </p>
        )}
        <TagEditor conversationId={conv.id} initialTags={conv.tags || []} />
      </div>

      {/* Chat card */}
      <div
        className="bg-white rounded-xl border border-gray-200 shadow-sm flex flex-col"
        style={{ height: 'calc(100vh - 260px)' }}
      >
        {/* Messages scroller */}
        <div
          ref={scrollRef}
          className="flex-1 overflow-y-auto px-5 py-5 space-y-3 bg-gray-50"
        >
          {conv.messages?.length > 0 ? (
            conv.messages.map((msg, i) => <Bubble key={i} msg={msg} />)
          ) : (
            <div className="h-full flex items-center justify-center">
              <div className="text-center">
                <div className="w-12 h-12 mx-auto rounded-full bg-sky-50 border border-sky-100 flex items-center justify-center mb-3">
                  <MessageCircle size={18} className="text-sky-600" />
                </div>
                <p className="text-sm text-gray-400">No messages yet</p>
              </div>
            </div>
          )}
        </div>

        {/* Composer */}
        <form
          onSubmit={handleSend}
          className="border-t border-gray-200 px-4 py-3 bg-white rounded-b-xl"
        >
          {!canReply && (
            <p className="text-[11px] text-amber-600 mb-2">
              Replies are only supported on WhatsApp conversations.
            </p>
          )}
          <div className="flex items-end gap-2">
            <textarea
              value={body}
              onChange={(e) => setBody(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={!canReply || sending}
              placeholder={canReply ? 'Type your message…  (Enter to send, Shift+Enter for new line)' : 'Cannot reply to this conversation'}
              rows={1}
              className="flex-1 resize-none max-h-40 text-sm bg-gray-50 border border-gray-200 rounded-xl px-4 py-2.5 text-gray-900 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-sky-500/30 focus:border-sky-400 disabled:opacity-50 disabled:cursor-not-allowed"
            />
            <button
              type="submit"
              disabled={!canReply || sending || !body.trim()}
              className="w-10 h-10 rounded-xl bg-sky-600 text-white flex items-center justify-center hover:bg-sky-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors flex-shrink-0 shadow-sm"
              aria-label="Send reply"
            >
              <Send size={16} />
            </button>
          </div>
        </form>
      </div>
    </DashboardLayout>
  )
}

function Bubble({ msg }) {
  const isClinic = msg.role === 'assistant'
  return (
    <div className={`flex ${isClinic ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`max-w-[70%] rounded-2xl px-4 py-2.5 shadow-sm ${
          isClinic
            ? 'bg-sky-600 text-white rounded-tr-sm'
            : 'bg-white border border-gray-200 text-gray-800 rounded-tl-sm'
        }`}
      >
        <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{msg.content}</p>
        {msg.timestamp && (
          <p className={`text-[10px] mt-1 ${isClinic ? 'text-white/70' : 'text-gray-400'}`}>
            {formatTime(msg.timestamp)}
          </p>
        )}
      </div>
    </div>
  )
}

function Chip({ label, tone }) {
  const tones = {
    sky:   'bg-sky-50 text-sky-700 border border-sky-100',
    blue:  'bg-blue-50 text-blue-700 border border-blue-100',
    gray:  'bg-gray-100 text-gray-600 border border-gray-200',
    slate: 'bg-slate-100 text-slate-600 border border-slate-200',
    green: 'bg-emerald-50 text-emerald-700 border border-emerald-100',
  }
  return (
    <span className={`text-[11px] font-semibold px-2.5 py-1 rounded-full capitalize ${tones[tone] || tones.gray}`}>
      {label}
    </span>
  )
}

function initials(name = '') {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() || '')
    .join('') || '·'
}

function TagEditor({ conversationId, initialTags }) {
  const [tags, setTags] = useState(initialTags)
  const [input, setInput] = useState('')
  const [saving, setSaving] = useState(false)

  const SUGGESTED = [
    'good-booking-flow', 'escalation-needed', 'afrikaans-example',
    'english-example', 'cancellation-flow', 'faq-quality',
    'training-data', 'needs-improvement', 'urgent-case'
  ]

  const addTag = (tag) => {
    const normalized = tag.toLowerCase().trim().replace(/\s+/g, '-')
    if (!normalized || tags.includes(normalized)) return
    const newTags = [...tags, normalized]
    setTags(newTags)
    saveTags(newTags)
    setInput('')
  }

  const removeTag = (tag) => {
    const newTags = tags.filter((t) => t !== tag)
    setTags(newTags)
    saveTags(newTags)
  }

  const saveTags = (newTags) => {
    setSaving(true)
    router.patch(`/conversations/${conversationId}/update_tags`, { tags: newTags }, {
      preserveScroll: true,
      onSuccess: () => toast.success('Tags updated'),
      onError: () => toast.error('Failed to update tags'),
      onFinish: () => setSaving(false),
    })
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      addTag(input)
    }
  }

  const suggestions = SUGGESTED.filter((s) => !tags.includes(s) && s.includes(input.toLowerCase()))

  return (
    <div className="mt-3 pt-3 border-t border-gray-100">
      <div className="flex items-center gap-1.5 mb-2">
        <Tag size={12} className="text-gray-400" />
        <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Tags</span>
        {saving && <span className="text-[10px] text-sky-500 animate-pulse">Saving…</span>}
      </div>

      <div className="flex flex-wrap gap-1.5 mb-2">
        {tags.map((tag) => (
          <span
            key={tag}
            className="inline-flex items-center gap-1 bg-sky-50 text-sky-700 border border-sky-100 px-2 py-0.5 rounded-full text-[11px] font-medium"
          >
            {tag}
            <button
              type="button"
              onClick={() => removeTag(tag)}
              className="hover:text-sky-900 transition-colors"
            >
              <XIcon size={10} />
            </button>
          </span>
        ))}
      </div>

      <div className="flex items-center gap-2">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Add tag…"
          className="flex-1 text-xs bg-gray-50 border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-sky-500/30 focus:border-sky-400"
        />
        <button
          type="button"
          onClick={() => addTag(input)}
          disabled={!input.trim()}
          className="text-sky-600 hover:text-sky-700 disabled:opacity-40 transition-colors"
        >
          <Plus size={14} />
        </button>
      </div>

      {input && suggestions.length > 0 && (
        <div className="mt-1.5 flex flex-wrap gap-1">
          {suggestions.slice(0, 5).map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => addTag(s)}
              className="text-[10px] text-gray-500 bg-gray-100 hover:bg-sky-50 hover:text-sky-600 border border-gray-200 rounded-full px-2 py-0.5 transition-colors"
            >
              + {s}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function formatTime(iso) {
  try {
    const d = new Date(iso)
    return d.toLocaleString('en-ZA', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  } catch {
    return ''
  }
}
