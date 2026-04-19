import React, { useEffect, useRef, useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { toast } from 'sonner'
import { ArrowLeft, Send, Phone, MessageCircle, Tag, X as XIcon, Plus, ExternalLink } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'

export default function ConversationShow({ conversation }) {
  const conv = conversation
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const scrollRef = useRef(null)

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
          className="inline-flex items-center gap-1.5 text-sm text-brand-primary hover:text-brand-primary/80 transition-colors"
        >
          <ArrowLeft size={14} /> Back to Conversations
        </Link>
      </div>

      {/* Header card */}
      <div className="bg-white rounded-xl border border-brand-border p-5 mb-4 shadow-sm">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-11 h-11 rounded-full bg-brand-primary/10 flex items-center justify-center flex-shrink-0 border border-brand-primary/20">
              <span className="text-brand-primary text-sm font-semibold">
                {initials(conv.patient_name)}
              </span>
            </div>
            <div className="min-w-0">
              <h1 className="text-lg font-bold text-brand-ink truncate">{conv.patient_name}</h1>
              <p className="text-xs text-brand-muted mt-0.5 flex items-center gap-1.5">
                <Phone size={11} />
                {conv.patient_phone}
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2 flex-shrink-0">
            <Chip
              label={conv.channel}
              tone={conv.channel === 'whatsapp' ? 'primary' : 'default'}
            />
            <Chip
              label={conv.status}
              tone={conv.status === 'active' ? 'success' : 'default'}
            />
            {conv.language && (
              <Chip
                label={conv.language === 'af' ? 'Afrikaans' : 'English'}
                tone={conv.language === 'af' ? 'success' : 'default'}
              />
            )}
            {conv.source === 'import' && <Chip label="Imported" tone="default" />}
            {conv.patient_id && (
              <Link
                href={`/patients/${conv.patient_id}`}
                className="inline-flex items-center gap-1 rounded-full border border-brand-primary/20 bg-brand-primary/10 px-2.5 py-1 text-[11px] font-semibold text-brand-primary hover:bg-brand-primary/20 transition-colors"
              >
                <ExternalLink size={10} />
                View patient
              </Link>
            )}
          </div>
        </div>
        {conv.topic && (
          <p className="text-xs text-brand-muted mt-3">
            Topic: <span className="font-medium text-brand-primary">{conv.topic}</span>
          </p>
        )}
        <TagEditor conversationId={conv.id} initialTags={conv.tags || []} />
      </div>

      {/* Chat card */}
      <div
        className="bg-white rounded-xl border border-brand-border shadow-sm flex flex-col"
        style={{ height: 'calc(100vh - 260px)' }}
      >
        {/* Messages scroller */}
        <div
          ref={scrollRef}
          className="flex-1 overflow-y-auto px-5 py-5 space-y-3 bg-brand-surface"
        >
          {conv.messages?.length > 0 ? (
            conv.messages.map((msg, i) => <Bubble key={i} msg={msg} />)
          ) : (
            <div className="h-full flex items-center justify-center">
              <div className="text-center">
                <div className="w-12 h-12 mx-auto rounded-full bg-brand-primary/10 border border-brand-primary/20 flex items-center justify-center mb-3">
                  <MessageCircle size={18} className="text-brand-primary" />
                </div>
                <p className="text-sm text-brand-muted">No messages yet</p>
              </div>
            </div>
          )}
        </div>

        {/* Composer */}
        <MessageComposer
          body={body}
          setBody={setBody}
          onSend={handleSend}
          onKeyDown={handleKeyDown}
          canReply={canReply}
          sending={sending}
        />
      </div>
    </DashboardLayout>
  )
}

function MessageComposer({ body, setBody, onSend, onKeyDown, canReply, sending }) {
  const charCount = body.length
  const showCounter = charCount > 140

  return (
    <div className="border-t border-brand-border bg-white rounded-b-xl">
      {!canReply && (
        <div className="px-4 pt-3 pb-0">
          <p className="text-[11px] text-amber-600 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
            Replies are only supported on WhatsApp conversations.
          </p>
        </div>
      )}

      <form onSubmit={onSend} className="px-4 py-3">
        {/* Unified input + button border group */}
        <div className={`flex items-end gap-0 rounded-xl border transition-colors ${
          canReply
            ? 'border-brand-border focus-within:border-brand-primary focus-within:ring-2 focus-within:ring-brand-primary/20'
            : 'border-brand-border opacity-50'
        } bg-white overflow-hidden`}>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            onKeyDown={onKeyDown}
            disabled={!canReply || sending}
            placeholder="Type your message…"
            rows={2}
            className="flex-1 resize-none max-h-36 min-h-[56px] text-sm bg-transparent px-4 py-3 text-brand-ink placeholder:text-brand-muted focus:outline-none disabled:cursor-not-allowed"
          />
          <div className="flex flex-col items-center justify-end pb-2.5 pr-2.5 gap-1">
            <button
              type="submit"
              disabled={!canReply || sending || !body.trim()}
              className="h-9 w-9 rounded-lg bg-brand-primary text-white flex items-center justify-center hover:bg-brand-primary/90 disabled:opacity-40 disabled:cursor-not-allowed transition-colors shadow-sm flex-shrink-0"
              aria-label="Send reply"
            >
              {sending ? (
                <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-white/30 border-t-white" />
              ) : (
                <Send size={15} />
              )}
            </button>
          </div>
        </div>

        {/* Footer hint row */}
        <div className="mt-1.5 flex items-center justify-between px-0.5">
          <p className="text-[11px] text-brand-muted">
            Enter to send · Shift+Enter for new line
          </p>
          {showCounter && (
            <p className={`text-[11px] font-medium ${charCount > 1024 ? 'text-brand-danger' : 'text-brand-muted'}`}>
              {charCount}
            </p>
          )}
        </div>
      </form>
    </div>
  )
}

function Bubble({ msg }) {
  const isClinic = msg.role === 'assistant'
  return (
    <div className={`flex ${isClinic ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`max-w-[70%] rounded-2xl px-4 py-2.5 shadow-sm ${
          isClinic
            ? 'bg-brand-primary text-white rounded-tr-sm'
            : 'bg-white border border-brand-border text-brand-ink rounded-tl-sm'
        }`}
      >
        <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{msg.content}</p>
        {msg.timestamp && (
          <p className={`text-[10px] mt-1 ${isClinic ? 'text-white/70' : 'text-brand-muted'}`}>
            {formatTime(msg.timestamp)}
          </p>
        )}
      </div>
    </div>
  )
}

function Chip({ label, tone }) {
  const tones = {
    primary: 'bg-brand-primary/10 text-brand-primary border border-brand-primary/20',
    success: 'bg-emerald-50 text-emerald-700 border border-emerald-200',
    default: 'bg-brand-surface text-brand-muted border border-brand-border',
  }
  return (
    <span className={`text-[11px] font-semibold px-2.5 py-1 rounded-full capitalize ${tones[tone] || tones.default}`}>
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
    <div className="mt-3 pt-3 border-t border-brand-border">
      <div className="flex items-center gap-1.5 mb-2">
        <Tag size={12} className="text-brand-muted" />
        <span className="text-[11px] font-semibold uppercase tracking-wide text-brand-muted">Tags</span>
        {saving && <span className="text-[10px] text-brand-primary animate-pulse">Saving…</span>}
      </div>

      <div className="flex flex-wrap gap-1.5 mb-2">
        {tags.map((tag) => (
          <span
            key={tag}
            className="inline-flex items-center gap-1 bg-brand-primary/10 text-brand-primary border border-brand-primary/20 px-2 py-0.5 rounded-full text-[11px] font-medium"
          >
            {tag}
            <button
              type="button"
              onClick={() => removeTag(tag)}
              className="hover:text-brand-primary/60 transition-colors"
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
          className="flex-1 text-xs bg-brand-surface border border-brand-border rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-brand-primary/30 focus:border-brand-primary"
        />
        <button
          type="button"
          onClick={() => addTag(input)}
          disabled={!input.trim()}
          className="text-brand-primary hover:text-brand-primary/80 disabled:opacity-40 transition-colors"
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
              className="text-[10px] text-brand-muted bg-brand-surface hover:bg-brand-primary/10 hover:text-brand-primary border border-brand-border rounded-full px-2 py-0.5 transition-colors"
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
