import React, { useState, useEffect, useRef } from 'react'
import { router, Link, Head } from '@inertiajs/react'
import { ArrowLeft, Plus, ChevronLeft, ChevronRight, CalendarDays, Copy, X as XIcon } from 'lucide-react'
import { toast } from 'sonner'
import AppointmentDetailModal from '../components/AppointmentDetailModal'
import AppointmentFormModal from '../components/AppointmentFormModal'
import CancelAppointmentModal from '../components/CancelAppointmentModal'
import DiaryContextMenu from '../components/DiaryContextMenu'

// Friendly status labels for the right-click menu's success toast.
const STATUS_TOAST = {
  confirmed: 'Confirmed',
  arrived: 'Marked as arrived',
  in_consultation: 'Consultation started',
  completed: 'Marked as completed',
}

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

  // Delete = PERMANENTLY remove from the diary (hard delete, not the soft grey-out cancel).
  // Confirmed because it's irreversible. Wired to the modal "Delete" button, the right-click
  // "Delete" item, and the keyboard Delete/Backspace key on the selected block.
  const deleteAppointment = (apt) => {
    if (!apt) return
    if (!window.confirm(`Permanently delete ${apt.patient_name || 'this'} appointment? It will be removed from the diary and cannot be undone.`)) return
    router.delete(`/appointments/${apt.id}`, {
      preserveScroll: true,
      onSuccess: () => { toast('Appointment deleted'); closeModal() },
      onError: () => toast.error('Could not delete'),
    })
  }

  const goTo = (d) => router.get('/diary', { date: d }, { preserveScroll: true })

  // Live refresh every 30s so the diary stays current across machines — but NEVER
  // while a modal is open (it was interrupting clicks / making things feel stuck).
  // NOTE: ctxMenu is declared further down, so it must NOT be referenced here
  // (doing so crashed the whole page — temporal dead zone). The context menu
  // closes itself on outside-click/Escape, so pausing the 30s refresh for it
  // isn't needed.
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
    // Provider is closed for bookings on this date (e.g. maternity leave) — don't book.
    if (provider?.on_leave) {
      window.alert(`${provider.name} is not taking bookings on this date. Please book with an available dentist.`)
      return
    }
    const rect = ev.currentTarget.getBoundingClientRect()
    const y = ev.clientY - rect.top
    const raw = DAY_START + Math.round((y / PX) / 15) * 15
    const snapped = Math.min(Math.max(raw, DAY_START), DAY_END - 15) // clamp to clinic hours
    const dt = new Date(date + 'T00:00:00')
    dt.setMinutes(snapped)
    // Remember this empty slot so Ctrl+V can duplicate the copied appointment here.
    lastSlotRef.current = { provider, start: dt }
    setPrefillProvider(provider)
    setPrefillStart(dt)
    setSelected(null)
    setModalMode('create')
  }

  // ── Drag-to-move: drag an Ivory appointment to a new time and/or dentist ──
  // Elixir-parity reschedule. Keeps the duration; the dentist = the column you
  // drop on. Server enforces the per-provider no-overlap constraint, so a drop
  // onto a taken slot is rejected with a friendly message.
  const dragRef = useRef(null)
  const [dragId, setDragId] = useState(null)

  // ── Right-click context menu (status / cancel / edit) ────────────────
  // { x, y, appt } while open; null when closed. Acts ONLY on Ivory blocks.
  const [ctxMenu, setCtxMenu] = useState(null)
  // The currently-selected appointment (single click) — highlighted, and the
  // target for Ctrl+C / Ctrl+X.
  const [selectedId, setSelectedId] = useState(null)
  const onApptContextMenu = (e, a) => {
    e.preventDefault()
    e.stopPropagation()
    setCtxMenu({ x: e.clientX, y: e.clientY, appt: a })
  }
  const onCtxPick = (key) => {
    const appt = ctxMenu?.appt
    setCtxMenu(null)
    if (!appt) return
    if (key === 'cancel') {
      // Cancel = grey it out but KEEP it in the diary (never remove).
      router.patch(`/appointments/${appt.id}/set_status`, { status: 'cancelled' }, {
        preserveScroll: true, preserveState: true,
        onSuccess: () => toast('Cancelled — greyed, kept in the diary'),
        onError: () => toast.error('Could not cancel'),
      })
      return
    }
    if (key === 'delete') { deleteAppointment(appt); return }
    if (key === 'edit') { openEdit(appt); return }
    // A patient-journey status change — recolours server-side.
    router.patch(`/appointments/${appt.id}/set_status`, { status: key }, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => toast.success(STATUS_TOAST[key] || 'Status updated'),
      onError: () => toast.error('Could not update'),
    })
  }

  // ── Copy & paste (Ctrl/Cmd+C → duplicate, Ctrl/Cmd+V → place) ─────────
  // `lastApptRef` = the most recently clicked Ivory block; `lastSlotRef` =
  // the last empty slot clicked (provider + snapped start). `clipboard`
  // holds what was copied so a banner can show and Ctrl+V can duplicate it.
  const lastApptRef = useRef(null)
  const lastSlotRef = useRef(null)
  const [clipboard, setClipboard] = useState(null)

  useEffect(() => {
    const onKey = (e) => {
      // Don't hijack copy/paste while typing in an input (e.g. the date picker).
      const tag = (e.target?.tagName || '').toLowerCase()
      if (tag === 'input' || tag === 'textarea' || e.target?.isContentEditable) return
      const mod = e.ctrlKey || e.metaKey
      // Delete / Backspace (no modifier) = permanently REMOVE the last-clicked block from the diary.
      if (!mod && (e.key === 'Delete' || e.key === 'Backspace')) {
        const a = lastApptRef.current
        if (a) { e.preventDefault(); deleteAppointment(a) }
        return
      }
      // Ctrl+C = copy (duplicate on paste) · Ctrl+X = cut (move on paste).
      if (mod && (e.key === 'c' || e.key === 'C' || e.key === 'x' || e.key === 'X')) {
        const a = lastApptRef.current
        if (!a) return
        e.preventDefault()
        const cut = e.key === 'x' || e.key === 'X'
        const durationMin = Math.max(
          Math.round((new Date(a.end_time) - new Date(a.start_time)) / 60000), 15,
        )
        setClipboard({ apptId: a.id, patient_id: a.patient_id, patient_name: a.patient_name, reason: a.reason, durationMin, cut })
        toast(`${cut ? 'Cut' : 'Copied'} ${a.patient_name} — click a slot and Ctrl+V`)
      } else if (mod && (e.key === 'v' || e.key === 'V')) {
        if (!clipboard || !lastSlotRef.current) return
        e.preventDefault()
        const slot = lastSlotRef.current
        if (slot.provider?.on_leave) { window.alert(`${slot.provider.name} is not taking bookings on this date.`); return }
        const start = new Date(slot.start)
        const end = new Date(start.getTime() + clipboard.durationMin * 60000)
        const when = { start_time: start.toISOString(), end_time: end.toISOString(), provider_id: slot.provider.id }
        if (clipboard.cut) {
          // MOVE the original appointment to the new slot/dentist.
          router.patch(`/appointments/${clipboard.apptId}`, { appointment: when }, {
            preserveScroll: true, preserveState: true,
            onSuccess: () => { toast.success(`Moved ${clipboard.patient_name}`); setClipboard(null) },
            onError: () => toast.error('Could not move — that slot may be taken'),
          })
        } else {
          // DUPLICATE for the same patient.
          router.post('/appointments', {
            appointment: { ...when, patient_id: clipboard.patient_id, reason: clipboard.reason },
          }, {
            preserveScroll: true, preserveState: true,
            onSuccess: () => toast.success(`Pasted ${clipboard.patient_name}`),
            onError: () => toast.error('Could not paste — that slot may be taken'),
          })
        }
      } else if (e.key === 'Escape' && clipboard) {
        setClipboard(null)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [clipboard])

  const onApptDragStart = (e, a) => {
    const startMin = minsFromMidnight(a.start_time)
    const endMin = minsFromMidnight(a.end_time)
    const col = e.currentTarget.closest('[data-col]')
    const blockTopPx = (Math.max(startMin, DAY_START) - DAY_START) * PX
    const grabOffsetPx = col ? (e.clientY - col.getBoundingClientRect().top) - blockTopPx : 0
    dragRef.current = {
      id: a.id,
      durationMin: Math.max(endMin - startMin, 15),
      grabOffsetPx,
      origStartMin: startMin,
      origProviderId: a.provider_id,
    }
    e.dataTransfer.effectAllowed = 'move'
    try { e.dataTransfer.setData('text/plain', String(a.id)) } catch (_) {}
    setDragId(a.id)
  }
  const onApptDragEnd = () => { dragRef.current = null; setDragId(null) }
  const onColumnDragOver = (e) => { if (dragRef.current) { e.preventDefault(); e.dataTransfer.dropEffect = 'move' } }
  const onColumnDrop = (e, provider) => {
    const info = dragRef.current
    if (!info) return
    e.preventDefault()
    onApptDragEnd()
    if (provider?.on_leave) { window.alert(`${provider.name} is not taking bookings on this date.`); return }
    const rect = e.currentTarget.getBoundingClientRect()
    const topPx = (e.clientY - rect.top) - info.grabOffsetPx
    let startMin = DAY_START + Math.round((topPx / PX) / 15) * 15
    startMin = Math.min(Math.max(startMin, DAY_START), DAY_END - info.durationMin)
    if (startMin === info.origStartMin && provider.id === info.origProviderId) return // dropped where it was
    const start = new Date(date + 'T00:00:00'); start.setMinutes(startMin)
    const end = new Date(start.getTime() + info.durationMin * 60000)
    router.patch(`/appointments/${info.id}`, {
      appointment: { start_time: start.toISOString(), end_time: end.toISOString(), provider_id: provider.id },
    }, {
      preserveScroll: true, preserveState: true,
      onError: () => window.alert('Could not move — that slot may already be taken.'),
    })
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
            <button onClick={() => goTo(shiftDate(date, -1))} title="Previous day" aria-label="Previous day" className="rounded-lg p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-ink"><ChevronLeft size={18} /></button>
            <button onClick={() => goTo(todayStr())} className="rounded-lg px-2.5 py-1.5 text-sm font-medium text-brand-muted hover:bg-brand-surface hover:text-brand-ink">Today</button>
            <button onClick={() => goTo(shiftDate(date, 1))} title="Next day" aria-label="Next day" className="rounded-lg p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-ink"><ChevronRight size={18} /></button>
          </div>
          <div className="flex items-center gap-2">
            <CalendarDays size={16} className="text-brand-primary" />
            <h1 className="text-base font-semibold tracking-tight text-brand-ink">{fmtDayTitle(date)}</h1>
            <input type="date" value={date} onChange={(e) => e.target.value && goTo(e.target.value)} className="ml-1 rounded-lg border border-brand-border px-2 py-1 text-xs text-brand-muted" />
          </div>
        </div>

        <div className="flex items-center gap-3">
          <Legend />
          <button onClick={() => { setSelected(null); setPrefillStart(null); setPrefillProvider(providers.find((p) => !p.on_leave) || providers[0] || null); setModalMode('create') }} className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark">
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
                  {prov.on_leave && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-700">On leave</span>}
                </div>
                <div data-col className={`relative ${prov.on_leave ? 'cursor-not-allowed' : 'cursor-copy'}`} style={{ height: gridHeight }} onClick={(e) => onColumnClick(prov, e)} onDragOver={onColumnDragOver} onDrop={(e) => onColumnDrop(e, prov)}>
                  {/* hour lines */}
                  {hourRows.map((h) => (
                    <div key={h} className="pointer-events-none absolute inset-x-0 border-t border-brand-border/60" style={{ top: (h * 60 - DAY_START) * PX }} />
                  ))}

                  {/* Maternity-leave / not-bookable overlay: diagonal hatch + label, blocks click-to-book */}
                  {prov.on_leave && (
                    <div className="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-6"
                         style={{ backgroundImage: 'repeating-linear-gradient(45deg, rgba(180,180,180,0.10) 0, rgba(180,180,180,0.10) 10px, rgba(180,180,180,0.18) 10px, rgba(180,180,180,0.18) 20px)' }}>
                      <span className="rounded-lg bg-white/85 px-3 py-1.5 text-xs font-semibold text-brand-muted shadow-sm">Diary closed — not taking bookings</span>
                    </div>
                  )}

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
                      draggable={!prov.on_leave}
                      onDragStart={(e) => onApptDragStart(e, a)}
                      onDragEnd={onApptDragEnd}
                      onClick={(e) => { e.stopPropagation(); lastApptRef.current = a; setSelectedId(a.id) }}
                      onDoubleClick={(e) => { e.stopPropagation(); openDetail(a) }}
                      onContextMenu={(e) => onApptContextMenu(e, a)}
                      title={`${a.patient_name} · ${a.status} — click to select (Ctrl+C copy · Ctrl+X cut · Ctrl+V paste) · double-click to open · drag to move · right-click for status`}
                      className={`absolute inset-x-1 cursor-move overflow-hidden rounded-md px-2 py-1 text-left text-[11px] leading-tight shadow-sm transition hover:shadow-md hover:brightness-95 ${dragId === a.id ? 'opacity-40 ring-2 ring-brand-primary' : selectedId === a.id ? 'ring-2 ring-brand-primary ring-offset-1' : ''}`}
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

      {/* Copy banner — visible while an appointment is on the clipboard. */}
      {clipboard && (
        <div className="pointer-events-auto fixed bottom-4 left-1/2 z-40 flex -translate-x-1/2 items-center gap-3 rounded-xl border border-brand-primary/40 bg-brand-primary/10 px-4 py-2 text-sm text-brand-ink shadow-lg">
          <span className="flex items-center gap-2">
            <Copy size={14} className="text-brand-primary" />
            Copied <strong>{clipboard.patient_name}</strong> — click an empty slot then press Ctrl+V to duplicate. Esc to clear.
          </span>
          <button
            type="button"
            onClick={() => setClipboard(null)}
            className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-brand-muted hover:bg-white hover:text-brand-ink"
          >
            <XIcon size={13} /> Clear
          </button>
        </div>
      )}

      {/* Right-click status menu (Ivory blocks only). */}
      {ctxMenu && (
        <DiaryContextMenu x={ctxMenu.x} y={ctxMenu.y} onPick={onCtxPick} onClose={() => setCtxMenu(null)} />
      )}

      {/* Modals */}
      <AppointmentDetailModal appointment={selected} open={modalMode === 'detail'} onClose={closeModal} onEdit={() => openEdit(selected)} onCancel={() => openCancel(selected)} onDelete={() => deleteAppointment(selected)} />
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
