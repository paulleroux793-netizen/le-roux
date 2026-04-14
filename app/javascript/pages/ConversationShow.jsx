import React, { useEffect, useRef, useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { toast } from 'sonner'
import { ArrowLeft, Send, Phone, MessageCircle } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

// ── Conversation detail + reply composer ───────────────────────────
// Phase 10.1 — the receptionist now reads the full transcript here
// and can type a WhatsApp reply directly into the thread. Send
// posts to POST /conversations/:id/reply which pushes the text out
// via Twilio (free-form, subject to the 24h customer-service
// window) and appends it to the JSONB messages array as an
// "assistant" entry — same shape the webhook produces — so the
// transcript stays consistent.
//
// Layout mirrors the screenshots the operator provided: a card
// scroller for the exchange, bubbles alternating left (patient,
// role=user) and right (clinic/AI, role=assistant), sticky
// composer pinned at the bottom of the card.

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
          className="inline-flex items-center gap-1.5 text-sm text-brand-primary transition-colors hover:text-brand-primary-dark"
        >
          <ArrowLeft size={14} /> Back to Conversations
        </Link>
      </div>

      {/* Header card */}
      <div className="mb-4 rounded-[28px] border border-brand-accent/75 bg-white p-5 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <div className="flex h-11 w-11 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-surface">
              <span className="text-sm font-semibold text-brand-primary">
                {initials(conv.patient_name)}
              </span>
            </div>
            <div className="min-w-0">
              <h1 className="truncate text-lg font-bold text-brand-ink">{conv.patient_name}</h1>
              <p className="mt-0.5 flex items-center gap-1.5 text-xs text-brand-muted">
                <Phone size={11} />
                {conv.patient_phone}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            <Chip
              label={conv.channel}
              tone={conv.channel === 'whatsapp' ? 'emerald' : 'blue'}
            />
            <Chip
              label={conv.status}
              tone={conv.status === 'active' ? 'emerald' : 'gray'}
            />
            {conv.source === 'import' && <Chip label="Imported" tone="purple" />}
          </div>
        </div>
        {conv.topic && (
          <p className="mt-3 text-xs text-brand-muted">
            Topic: <span className="font-medium text-brand-primary">{conv.topic}</span>
          </p>
        )}
      </div>

      {/* Chat card */}
      <div className="flex flex-col rounded-[28px] border border-brand-accent/75 bg-white shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]" style={{ height: 'calc(100vh - 260px)' }}>
        {/* Messages scroller */}
        <div
          ref={scrollRef}
          className="flex-1 space-y-3 overflow-y-auto bg-brand-surface/20 px-5 py-5"
        >
          {conv.messages?.length > 0 ? (
            conv.messages.map((msg, i) => <Bubble key={i} msg={msg} />)
          ) : (
            <div className="h-full flex items-center justify-center">
              <div className="text-center">
                <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-brand-surface">
                  <MessageCircle size={18} className="text-brand-primary" />
                </div>
                <p className="text-sm text-brand-muted">No messages yet</p>
              </div>
            </div>
          )}
        </div>

        {/* Composer */}
        <form
          onSubmit={handleSend}
          className="rounded-b-[28px] border-t border-brand-accent/70 bg-white px-4 py-3"
        >
          {!canReply && (
            <p className="mb-2 text-[11px] text-[#C58A22]">
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
              className="max-h-40 flex-1 resize-none rounded-2xl border border-brand-accent/80 bg-white px-4 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45 disabled:cursor-not-allowed disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={!canReply || sending || !body.trim()}
              className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-primary text-white transition-colors hover:bg-brand-primary-dark disabled:cursor-not-allowed disabled:opacity-40"
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
            ? 'rounded-tr-sm bg-brand-primary text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)]'
            : 'rounded-tl-sm border border-brand-accent/65 bg-white text-brand-ink'
        }`}
      >
        <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{msg.content}</p>
        {msg.timestamp && (
          <p className={`mt-1 text-[10px] ${isClinic ? 'text-white/70' : 'text-brand-muted'}`}>
            {formatTime(msg.timestamp)}
          </p>
        )}
      </div>
    </div>
  )
}

function Chip({ label, tone }) {
  const tones = {
    emerald: 'bg-[#EAF8F0] text-brand-success',
    blue:    'bg-[#EEF4FF] text-brand-primary',
    gray:    'bg-[#F3F6FB] text-brand-muted',
    purple:  'bg-brand-surface text-brand-primary',
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

function formatTime(iso) {
  try {
    const d = new Date(iso)
    return d.toLocaleString('en-ZA', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  } catch {
    return ''
  }
}
