import React, { useEffect, useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { Search, User, Calendar, MessageSquare, Loader2 } from 'lucide-react'

// ── Global navbar search ────────────────────────────────────────────
// Phase 9.6 sub-area #5 — Functional Global Search.
//
// Hits GET /search?q=... (JSON, not Inertia) on every keystroke,
// debounced at 200ms. Results are grouped into Patients / Appointments
// / Conversations and rendered inline under the input. Click a result
// to Inertia-navigate to its page; press Escape / click outside to
// close. Up/Down arrow keys cycle the flat result list so the
// receptionist can navigate entirely from the keyboard.
//
// Debounce + abort-on-each-keystroke keeps the network honest: if the
// user types "alice" we never leave a stale request for "ali" in
// flight that could land after the newer one.

const DEBOUNCE_MS = 200
const MIN_QUERY_LENGTH = 2

export default function GlobalSearch() {
  const [query, setQuery]       = useState('')
  const [results, setResults]   = useState(null) // null = idle, object = have data
  const [loading, setLoading]   = useState(false)
  const [open, setOpen]         = useState(false)
  const [activeIdx, setActiveIdx] = useState(-1)

  const containerRef = useRef(null)
  const abortRef     = useRef(null)

  // Flat ordered list of results (for keyboard navigation).
  const flatResults = results
    ? [
        ...(results.patients      || []).map((r) => ({ ...r, _kind: 'patient' })),
        ...(results.appointments  || []).map((r) => ({ ...r, _kind: 'appointment' })),
        ...(results.conversations || []).map((r) => ({ ...r, _kind: 'conversation' })),
      ]
    : []

  // Debounced fetch — abort the previous request whenever the query
  // changes so we never race a stale response back into state.
  useEffect(() => {
    if (query.trim().length < MIN_QUERY_LENGTH) {
      setResults(null)
      setLoading(false)
      return
    }

    const timer = setTimeout(() => {
      abortRef.current?.abort()
      const ctrl = new AbortController()
      abortRef.current = ctrl
      setLoading(true)

      fetch(`/search?q=${encodeURIComponent(query)}`, {
        headers: { Accept: 'application/json' },
        signal: ctrl.signal,
      })
        .then((r) => r.json())
        .then((data) => {
          setResults(data)
          setActiveIdx(-1)
          setLoading(false)
        })
        .catch((err) => {
          if (err.name !== 'AbortError') setLoading(false)
        })
    }, DEBOUNCE_MS)

    return () => clearTimeout(timer)
  }, [query])

  // Close on outside click.
  useEffect(() => {
    const handler = (e) => {
      if (!containerRef.current?.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const navigate = (item) => {
    setOpen(false)
    setQuery('')
    setResults(null)
    router.visit(item.url)
  }

  const onKeyDown = (e) => {
    if (!open) return
    if (e.key === 'Escape') {
      setOpen(false)
      e.currentTarget.blur()
      return
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActiveIdx((i) => Math.min(i + 1, flatResults.length - 1))
      return
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActiveIdx((i) => Math.max(i - 1, 0))
      return
    }
    if (e.key === 'Enter') {
      const target = activeIdx >= 0 ? flatResults[activeIdx] : flatResults[0]
      if (target) {
        e.preventDefault()
        navigate(target)
      }
    }
  }

  const hasAnyResults = flatResults.length > 0
  const showDropdown = open && query.trim().length >= MIN_QUERY_LENGTH

  return (
    <div ref={containerRef} className="w-full max-w-xl relative">
      <div className="relative">
        <Search
          size={15}
          className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted"
        />
        <input
          type="text"
          role="combobox"
          aria-expanded={showDropdown}
          aria-controls="global-search-listbox"
          placeholder="Search patients, appointments, conversations…"
          value={query}
          onChange={(e) => { setQuery(e.target.value); setOpen(true) }}
          onFocus={() => setOpen(true)}
          onKeyDown={onKeyDown}
          className="w-full rounded-2xl border border-brand-accent/80 bg-white/95 py-2.5 pl-10 pr-9 text-sm text-brand-ink placeholder:text-brand-muted focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45 transition-colors"
        />
        {loading && (
          <Loader2
            size={14}
            className="absolute right-3 top-1/2 -translate-y-1/2 animate-spin text-brand-muted"
          />
        )}
      </div>

      {showDropdown && (
        <div
          id="global-search-listbox"
          role="listbox"
          className="absolute left-0 right-0 z-50 mt-2 max-h-[28rem] overflow-y-auto rounded-xl border border-brand-accent/80 bg-white shadow-[0_30px_70px_-42px_rgba(57,60,77,0.45)]"
        >
          {!results ? (
            <EmptyState message="Type at least 2 characters to search…" />
          ) : !hasAnyResults ? (
            <EmptyState message={`No results for "${query}"`} />
          ) : (
            <>
              <ResultSection
                label="Patients"
                icon={User}
                items={results.patients}
                flatStart={0}
                activeIdx={activeIdx}
                onSelect={navigate}
                render={(p, isActive) => (
                  <Row active={isActive}>
                    <Avatar initials={initials(p.full_name)} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-brand-ink truncate">{p.full_name}</p>
                      <p className="truncate text-xs text-brand-muted">
                        {p.phone}{p.email ? ` · ${p.email}` : ''}
                      </p>
                    </div>
                  </Row>
                )}
              />
              <ResultSection
                label="Appointments"
                icon={Calendar}
                items={results.appointments}
                flatStart={(results.patients || []).length}
                activeIdx={activeIdx}
                onSelect={navigate}
                render={(a, isActive) => (
                  <Row active={isActive}>
                    <IconBubble icon={Calendar} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-brand-ink">
                        {a.patient_name}
                        {a.reason ? <span className="font-normal text-brand-muted"> · {a.reason}</span> : null}
                      </p>
                      <p className="text-xs text-brand-muted">
                        {new Date(a.start_time).toLocaleString('en-ZA', {
                          dateStyle: 'medium', timeStyle: 'short',
                        })}
                        <StatusDot status={a.status} />
                      </p>
                    </div>
                  </Row>
                )}
              />
              <ResultSection
                label="Conversations"
                icon={MessageSquare}
                items={results.conversations}
                flatStart={(results.patients || []).length + (results.appointments || []).length}
                activeIdx={activeIdx}
                onSelect={navigate}
                render={(c, isActive) => (
                  <Row active={isActive}>
                    <IconBubble icon={MessageSquare} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-brand-ink">
                        {c.patient_name}
                        <span className="font-normal text-brand-muted"> · {c.channel}</span>
                      </p>
                      <p className="text-xs text-brand-muted">
                        {new Date(c.updated_at).toLocaleDateString('en-ZA')}
                      </p>
                    </div>
                  </Row>
                )}
              />
            </>
          )}
        </div>
      )}
    </div>
  )
}

function ResultSection({ label, icon: Icon, items, flatStart, activeIdx, onSelect, render }) {
  if (!items || items.length === 0) return null
  return (
    <div>
      <div className="flex items-center gap-1.5 px-4 pb-1.5 pt-3 text-[10px] font-semibold uppercase tracking-wider text-brand-muted">
        <Icon size={11} />
        {label}
      </div>
      {items.map((item, i) => {
        const isActive = activeIdx === flatStart + i
        return (
          <button
            key={`${label}-${item.id}`}
            type="button"
            role="option"
            aria-selected={isActive}
            onMouseEnter={() => {/* noop — keyboard owns activeIdx */}}
            onClick={() => onSelect(item)}
            className="w-full text-left"
          >
            {render(item, isActive)}
          </button>
        )
      })}
    </div>
  )
}

function Row({ active, children }) {
  return (
    <div
      className={`flex items-center gap-3 px-4 py-2.5 ${
        active ? 'bg-brand-surface/65' : 'hover:bg-brand-surface/30'
      }`}
    >
      {children}
    </div>
  )
}

function EmptyState({ message }) {
  return (
    <div className="px-4 py-10 text-center text-sm text-brand-muted">{message}</div>
  )
}

function Avatar({ initials }) {
  return (
    <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-brand-surface">
      <span className="text-[10px] font-semibold text-brand-primary">{initials}</span>
    </div>
  )
}

function IconBubble({ icon: Icon }) {
  return (
    <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-brand-surface">
      <Icon size={14} className="text-brand-primary" />
    </div>
  )
}

function StatusDot({ status }) {
  const color = {
    scheduled: 'bg-amber-400',
    confirmed: 'bg-emerald-400',
    completed: 'bg-blue-400',
    cancelled: 'bg-red-400',
    no_show:   'bg-gray-300',
    rescheduled: 'bg-purple-400',
  }[status] || 'bg-gray-300'
  return (
    <span className="inline-flex items-center ml-2">
      <span className={`w-1.5 h-1.5 rounded-full ${color}`} />
      <span className="ml-1 capitalize">{String(status).replace('_', ' ')}</span>
    </span>
  )
}

function initials(name = '') {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]?.toUpperCase() || '')
      .join('') || '·'
  )
}
