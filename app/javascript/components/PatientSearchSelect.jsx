import React, { useState, useEffect, useRef } from 'react'
import { Search, X } from 'lucide-react'

// Type-ahead patient picker: type a name, surname or account number and pick
// from live matches — no scrolling a 2,000-row dropdown. Hits /patients/lookup.
export default function PatientSearchSelect({ selected, onSelect, autoFocus = false }) {
  const [q, setQ] = useState('')
  const [results, setResults] = useState([])
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const boxRef = useRef(null)

  useEffect(() => {
    if (q.trim().length < 2) { setResults([]); return }
    const ctrl = new AbortController()
    const timer = setTimeout(async () => {
      setLoading(true)
      try {
        const res = await fetch(`/patients/lookup?q=${encodeURIComponent(q.trim())}`, {
          headers: { Accept: 'application/json' }, signal: ctrl.signal,
        })
        const data = await res.json()
        setResults(data.results || [])
        setOpen(true)
      } catch (_e) { /* aborted / network */ } finally { setLoading(false) }
    }, 220)
    return () => { clearTimeout(timer); ctrl.abort() }
  }, [q])

  useEffect(() => {
    const onDoc = (e) => { if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])

  if (selected) {
    return (
      <div className="flex items-center justify-between rounded-2xl border border-brand-accent/80 bg-brand-surface/40 px-3 py-2.5 text-sm">
        <span className="font-medium text-brand-ink">
          {selected.name}{selected.account_code ? ` [${selected.account_code}]` : ''}
          {selected.phone ? <span className="ml-1.5 font-normal text-brand-muted">{selected.phone}</span> : null}
        </span>
        <button type="button" onClick={() => onSelect(null)} title="Change patient"
          className="rounded-lg p-1 text-brand-muted transition hover:bg-white hover:text-brand-ink">
          <X size={14} />
        </button>
      </div>
    )
  }

  return (
    <div ref={boxRef} className="relative">
      <div className="flex items-center rounded-2xl border border-brand-accent/80 bg-white px-3 focus-within:border-brand-primary focus-within:ring-4 focus-within:ring-brand-accent/45">
        <Search size={15} className="flex-shrink-0 text-brand-muted" />
        <input
          autoFocus={autoFocus}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onFocus={() => results.length && setOpen(true)}
          placeholder="Type name, surname or account no…"
          className="w-full bg-transparent px-2 py-2.5 text-sm text-brand-ink placeholder:text-brand-muted focus:outline-none"
        />
      </div>
      {open && q.trim().length >= 2 && (
        <div className="absolute z-50 mt-1 max-h-64 w-full overflow-auto rounded-2xl border border-brand-border bg-white py-1 shadow-[0_24px_60px_-16px_rgba(57,60,77,0.25)]">
          {loading && <div className="px-3 py-2 text-xs text-brand-muted">Searching…</div>}
          {!loading && results.length === 0 && (
            <div className="px-3 py-2 text-xs text-brand-muted">No matches — try fewer letters, or use “New patient”.</div>
          )}
          {results.map((r) => (
            <button
              key={r.id}
              type="button"
              onClick={() => { onSelect(r); setOpen(false); setQ('') }}
              className="flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm transition hover:bg-brand-surface"
            >
              <span className="truncate font-medium text-brand-ink">
                {r.name}{r.account_code ? <span className="ml-1 text-brand-primary">[{r.account_code}]</span> : null}
              </span>
              <span className="flex-shrink-0 text-xs text-brand-muted">{r.phone}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
