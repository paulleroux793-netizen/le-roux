import React, { useState, useEffect } from 'react'
import { router, Link, Head } from '@inertiajs/react'
import { ArrowLeft, Plus, ChevronLeft, ChevronRight, CalendarDays } from 'lucide-react'
import AppointmentDetailModal from '../components/AppointmentDetailModal'
import AppointmentFormModal from '../components/AppointmentFormModal'
import CancelAppointmentModal from '../components/CancelAppointmentModal'

// ── Elixir-style day diary: one column per dentist ────────────────────
// Matches the practice's Elixir "express diary": a time axis down the left,
// a column per working dentist, blocks showing NAME [ACCOUNT] + reason,
// coloured by type (green treatment · purple consult · yellow new-patient),
// pink "Closed" blocks for breaks. Ivory appointments are editable; the
// read-only Elixir history for the same day is shown faded for context.
const DAY_START = 8 * 60   // 08:00
const DAY_END = 19 * 60    // 19:00
const PX = 1.25            // pixels per minute

const minsFromMidnight = (iso) => {
  const d = new Date(iso)
  return d.getHours() * 60 + d.getMinutes()
}
const fmtTime = (iso) =>
  new Date(iso).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit', hour12: false })
const fmtDayTitle = (dateStr) =>
  new Date(dateStr + 'T00:00:00').toLocaleDateString('en-ZA', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  })
// Pure date math in UTC so a +2 (SAST) browser doesn't roll the day back when we
// round-trip through toISOString(). (This was why the prev/next arrows "didn't move".)
const shiftDate = (dateStr, n) => {
  const [y, m, d] = dateStr.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  dt.setUTCDate(dt.getUTCDate() + n)
  return dt.toISOString().slice(0, 10)
}
const todayStr = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// Block colour follows the patient-journey status (Paul's workflow).
const WHITE_TEXT = new Set(['in_consultation', 'completed'])
const apptStyle = (a) => {
  const hex = a.status_color || '#ffffff'
  const isWhite = hex.toLowerCase() === '#ffffff'
  return {
    backgroundColor: hex,
    color: WHITE_TEXT.has(a.status) ? '#ffffff' : '#1f2937',
    border: isWhite ? '1px solid #cbd5e1' : `1px solid rgba(0,0,0,0.12)`,
    borderLeft: `4px solid ${isWhite ? '#94a3b8' : hex}`,
  }
}

export default function Diary({
  date,
  providers = [],
  appointments = [],
  elixir_blocks = [],
  closed_blocks = [],
  patients = [],
}) {
  const [modalMode, setModalMode] = useState(null)
  const [selected, setSelected] = useState(null)
  const [prefillStart, setPrefillStart] = useState(null)
  const [prefillProvider, setPrefillProvider] = useState(null)

  const closeModal = () => { setModalMode(null); setSelected(null); setPrefillStart(null); setPrefillProvider(null) }
  const openDetail = (apt) => { setSelected(apt); setModalMode('detail') }
  const openEdit = (apt) => { if (apt) setSelected(apt); setModalMode('edit') }
  const openCancel = (apt) => { if (apt) setSelected(apt); setModalMode('cancel') }

  const goTo = (d) => router.get('/diary', { date: d }, { preserveScroll: true })

  // Live refresh every 30s so the diary stays current across machines — but NEVER
  // while a modal is open (it was interrupting clicks / making things feel stuck).
  useEffect(() => {
    if (modalMode) return undefined
    const t = setInterval(() => {
      router.reload({ only: ['appointments', 'elixir_blocks', 'closed_blocks'], preserveState: true, preserveScroll: true })
    }, 30_000)
    return () => clearInterval(t)
  }, [modalMode])

  // Click a historical Elixir block → pre-fill a new booking for that dentist + time
  // (so clicking history "re-books" the slot, and a click always opens something).
  const openRebook = (b) => {
    const prov = providers.find((p) => p.id === b.provider_id) || null
    setPrefillProvider(prov)
    setPrefillStart(new Date(b.start_time))
    setSelected(null)
    setModalMode('create')
  }

  // Click a "Closed" block to remove it.
  const removeClosed = (c) => {
    if (window.confirm(`Remove blocked time "${c.note || 'Closed'}"?`)) {
      router.delete(`/calendar_notes/${c.id}`, { preserveScroll: true })
    }
  }

  const gridHeight = (DAY_END - DAY_START) * PX
  const hourRows = []
  for (let h = DAY_START / 60; h <= DAY_END / 60; h++) hourRows.push(h)

  const blockBox = (startIso, endIso) => {
    const s = Math.max(minsFromMidnight(startIso), DAY_START)
    const e = Math.min(minsFromMidnight(endIso), DAY_END)
    return { top: (s - DAY_START) * PX, height: Math.max((e - s) * PX, 20) }
  }

  const onColumnClick = (provider, ev) => {
    // Only treat clicks on the column background (not on a block) as "book here".
    if (ev.target.closest('[data-block]')) return
    const rect = ev.currentTarget.getBoundingClientRect()
    const y = ev.clientY - rect.top
    const raw = DAY_START + Math.round((y / PX) / 15) * 15
    const snapped = Math.min(Math.max(raw, DAY_START), DAY_END - 15) // clamp to clinic hours
    const dt = new Date(date + 'T00:00:00')
    dt.setMinutes(snapped)
    setPrefillProvider(provider)
    setPrefillStart(dt)
    setSelected(null)
    setModalMode('create')
  }

  const apptsFor = (pid) => appointments.filter((a) => a.provider_id === pid)
  const elixirFor = (pid) => elixir_blocks.filter((b) => b.provider_id === pid)
  const closedFor = (pid) => closed_blocks.filter((c) => c.provider_id === pid || c.provider_id == null)

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-brand-bg">
      <Head title={`Diary — ${fmtDayTitle(date)}`} />

      {/* Top bar: back · date nav · legend · new appointment */}
      <header className="flex flex-shrink-0 items-center justify-between gap-4 border-b border-brand-border bg-white px-4 py-2.5 shadow-sm">
        <div className="flex items-center gap-3">
          <Link href="/dashboard" className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-medium text-brand-muted transition-colors hover:bg-brand-surface hover:text-brand-ink">
            <ArrowLeft size={16} /> Dashboard
          </Link>
          <span className="h-5 w-px bg-brand-border" />
          <div className="flex items-center gap-1">
            <button onClick={() => goTo(shiftDate(date, -1))} title="Previous day" className="rounded-lg p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-ink"><ChevronLeft size={18} /></button>
            <button onClick={() => goTo(todayStr())} className="rounded-lg px-2.5 py-1.5 text-sm font-medium text-brand-muted hover:bg-brand-surface hover:text-brand-ink">Today</button>
            <button onClick={() => goTo(shiftDate(date, 1))} title="Next day" className="rounded-lg p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-ink"><ChevronRight size={18} /></button>
          </div>
          <div className="flex items-center gap-2">
            <CalendarDays size={16} className="text-brand-primary" />
            <h1 className="text-base font-semibold tracking-tight text-brand-ink">{fmtDayTitle(date)}</h1>
            <input type="date" value={date} onChange={(e) => e.target.value && goTo(e.target.value)} className="ml-1 rounded-lg border border-brand-border px-2 py-1 text-xs text-brand-muted" />
          </div>
        </div>

        <div className="flex items-center gap-3">
          <Legend />
          <button onClick={() => { setSelected(null); setPrefillStart(null); setPrefillProvider(providers[0] || null); setModalMode('create') }} className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark">
            <Plus size={15} /> New appointment
          </button>
        </div>
      </header>

      {/* Grid */}
      <main className="min-h-0 flex-1 overflow-auto p-3">
        {providers.length === 0 ? (
          <p className="p-8 text-center text-sm text-brand-muted">No active dentists configured.</p>
        ) : (
          <div className="inline-flex min-w-full rounded-xl border border-brand-border bg-white shadow-sm">
            {/* Time gutter */}
            <div className="w-14 flex-shrink-0 border-r border-brand-border">
              <div className="h-9 border-b border-brand-border" />
              <div className="relative" style={{ height: gridHeight }}>
                {hourRows.map((h) => (
                  <div key={h} className="absolute right-1 -translate-y-1/2 text-[11px] font-medium text-brand-muted" style={{ top: (h * 60 - DAY_START) * PX }}>
                    {String(h).padStart(2, '0')}:00
                  </div>
                ))}
              </div>
            </div>

            {/* Provider columns */}
            {providers.map((prov) => (
              <div key={prov.id} className="min-w-[260px] flex-1 border-r border-brand-border last:border-r-0">
                <div className="flex h-9 items-center justify-center gap-2 border-b border-brand-border bg-brand-surface/40 text-sm font-semibold text-brand-ink">
                  <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: prov.color }} />
                  {prov.name}
                </div>
                <div className="relative cursor-copy" style={{ height: gridHeight }} onClick={(e) => onColumnClick(prov, e)}>
                  {/* hour lines */}
                  {hourRows.map((h) => (
                    <div key={h} className="pointer-events-none absolute inset-x-0 border-t border-brand-border/60" style={{ top: (h * 60 - DAY_START) * PX }} />
                  ))}

                  {/* Closed / blocked — click to remove */}
                  {closedFor(prov.id).map((c) => (
                    <button
                      key={`c${c.id}`}
                      type="button"
                      data-block
                      title="Click to remove this blocked time"
                      onClick={(e) => { e.stopPropagation(); removeClosed(c) }}
                      className="absolute inset-x-1 rounded-md border border-pink-300 bg-pink-100/80 px-2 py-1 text-left text-[11px] font-medium text-pink-800 transition hover:bg-pink-200/80"
                      style={blockBox(c.starts_at, c.ends_at)}
                    >
                      ⛔ {c.note || 'Closed'}
                    </button>
                  ))}

                  {/* Read-only Elixir history (faded). Click to re-book that slot. */}
                  {elixirFor(prov.id).map((b) => (
                    <button
                      key={b.id}
                      type="button"
                      data-block
                      title="Elixir history — click to re-book this slot"
                      onClick={(e) => { e.stopPropagation(); openRebook(b) }}
                      className="absolute inset-x-1 overflow-hidden rounded-md border border-dashed border-slate-300 bg-slate-100/80 px-2 py-1 text-left text-[11px] leading-tight text-slate-600 transition hover:border-brand-primary hover:bg-slate-100"
                      style={blockBox(b.start_time, b.end_time)}
                    >
                      <div className="flex items-center justify-between font-semibold">
                        <span className="truncate">{b.patient_name}{b.account_code ? ` [${b.account_code}]` : b.is_new_patient ? ' [New]' : ''}</span>
                        <span className="ml-1 rounded bg-slate-200 px-1 text-[9px] uppercase tracking-wide text-slate-500">Elixir</span>
                      </div>
                      {b.reason && <div className="truncate opacity-80">{b.reason}</div>}
                    </button>
                  ))}

                  {/* Ivory appointments (editable) — colour = patient-journey status */}
                  {apptsFor(prov.id).map((a) => (
                    <button
                      key={a.id}
                      data-block
                      onClick={(e) => { e.stopPropagation(); openDetail(a) }}
                      title={`${a.patient_name} · ${a.status}`}
                      className="absolute inset-x-1 overflow-hidden rounded-md px-2 py-1 text-left text-[11px] leading-tight shadow-sm transition hover:shadow-md hover:brightness-95"
                      style={{ ...blockBox(a.start_time, a.end_time), ...apptStyle(a) }}
                    >
                      <div className="flex items-center justify-between font-semibold">
                        <span className="truncate">{a.patient_name}{a.account_code ? ` [${a.account_code}]` : a.is_new_patient ? ' [New]' : ''}</span>
                        <span className="ml-1 whitespace-nowrap text-[9px] font-normal opacity-70">{fmtTime(a.start_time)}</span>
                      </div>
                      {a.reason && <div className="truncate opacity-80">{a.reason}</div>}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* Modals */}
      <AppointmentDetailModal appointment={selected} open={modalMode === 'detail'} onClose={closeModal} onEdit={() => openEdit(selected)} onCancel={() => openCancel(selected)} />
      <AppointmentFormModal mode="create" open={modalMode === 'create'} onClose={closeModal} patients={patients} prefillStart={prefillStart} providers={providers} prefillProvider={prefillProvider} />
      <AppointmentFormModal mode="edit" appointment={selected} open={modalMode === 'edit'} onClose={closeModal} providers={providers} />
      <CancelAppointmentModal appointment={selected} open={modalMode === 'cancel'} onClose={closeModal} />
    </div>
  )
}

function Legend() {
  const items = [
    ['#ffffff', 'Booked'],
    ['#22c55e', 'Confirmed'],
    ['#facc15', 'Arrived'],
    ['#3b82f6', 'In chair'],
    ['#8b5cf6', 'Completed'],
    ['#f9a8d4', 'Closed'],
  ]
  return (
    <div className="hidden items-center gap-3 lg:flex">
      {items.map(([c, label]) => (
        <span key={label} className="inline-flex items-center gap-1 text-[11px] text-brand-muted">
          <span className="h-2.5 w-2.5 rounded-sm border border-slate-300" style={{ backgroundColor: c }} /> {label}
        </span>
      ))}
    </div>
  )
}
