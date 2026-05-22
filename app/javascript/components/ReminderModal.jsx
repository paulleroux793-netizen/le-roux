import React, { useEffect, useState } from 'react'
import { router } from '@inertiajs/react'
import { Trash2, Check, Bell } from 'lucide-react'
import { toast } from 'sonner'
import Modal from './Modal'

// ── Diary reminder modal ────────────────────────────────────────────
// Create / edit / complete / delete a non-appointment diary reminder
// ("remember to call Mr X"). Self-contained: posts to /calendar_notes
// and lets the calendar reload its data. `note` is null in create mode;
// `prefillStart` is a Date from the clicked slot.
const pad = (n) => String(n).padStart(2, '0')
const toDateInput = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const toTimeInput = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`

export default function ReminderModal({ open, onClose, note, prefillStart }) {
  const isEdit = Boolean(note)
  const [text, setText] = useState('')
  const [date, setDate] = useState('')
  const [time, setTime] = useState('')

  // Seed the form whenever the modal opens for a new target.
  useEffect(() => {
    if (!open) return
    const base = note ? new Date(note.starts_at) : (prefillStart || new Date())
    setText(note ? note.note : '')
    setDate(toDateInput(base))
    setTime(toTimeInput(base))
  }, [open, note, prefillStart])

  if (!open) return null

  // Send a naive local datetime string (no Z / no offset). The server
  // parses it in the practice timezone (Time.zone.parse), so what the
  // user typed is what gets stored — no browser-UTC round-trip that
  // would shift the time. (Date + 'T' + time, e.g. "2026-05-20T09:00".)
  const startLocal = () => `${date}T${time}`

  const save = () => {
    if (!text.trim()) { toast.error('Please enter a reminder'); return }
    const payload = { calendar_note: { note: text.trim(), starts_at: startLocal() } }
    const opts = {
      preserveScroll: true,
      onSuccess: () => { toast.success(isEdit ? 'Reminder updated' : 'Reminder added'); onClose?.() },
      onError: () => toast.error('Could not save reminder'),
    }
    if (isEdit) router.patch(`/calendar_notes/${note.id}`, payload, opts)
    else router.post('/calendar_notes', payload, opts)
  }

  const toggleDone = () => {
    router.patch(`/calendar_notes/${note.id}`, { calendar_note: { done: !note.done } }, {
      preserveScroll: true,
      onSuccess: () => { toast.success(note.done ? 'Marked not done' : 'Marked done'); onClose?.() },
      onError: () => toast.error('Could not update reminder'),
    })
  }

  const remove = () => {
    router.delete(`/calendar_notes/${note.id}`, {
      preserveScroll: true,
      onSuccess: () => { toast.success('Reminder removed'); onClose?.() },
      onError: () => toast.error('Could not remove reminder'),
    })
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? 'Diary reminder' : 'New diary reminder'}
      size="md"
      footer={
        <div className="flex w-full items-center justify-between gap-2">
          {isEdit ? (
            <button
              onClick={remove}
              className="inline-flex items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-medium text-brand-danger transition-colors hover:bg-brand-danger/10"
            >
              <Trash2 size={15} /> Delete
            </button>
          ) : <span />}
          <div className="flex items-center gap-2">
            {isEdit && (
              <button
                onClick={toggleDone}
                className="inline-flex items-center gap-1.5 rounded-xl border border-brand-border px-3 py-2 text-sm font-medium text-brand-ink transition-colors hover:bg-brand-surface/50"
              >
                <Check size={15} /> {note.done ? 'Mark not done' : 'Mark done'}
              </button>
            )}
            <button
              onClick={save}
              className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-primary-dark"
            >
              {isEdit ? 'Save' : 'Add reminder'}
            </button>
          </div>
        </div>
      }
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
          <Bell size={15} /> A reminder is just a note on the diary — it isn't a patient appointment.
        </div>
        <label className="block">
          <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Reminder</span>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={2}
            autoFocus
            placeholder="e.g. Call Mr Botha about his crown"
            className="w-full rounded-lg border border-brand-border bg-white px-3 py-2 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-2 focus:ring-brand-primary/20"
          />
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Date</span>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="w-full rounded-lg border border-brand-border bg-white px-3 py-2 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-2 focus:ring-brand-primary/20"
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-brand-muted">Time</span>
            <input
              type="time"
              value={time}
              onChange={(e) => setTime(e.target.value)}
              className="w-full rounded-lg border border-brand-border bg-white px-3 py-2 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-2 focus:ring-brand-primary/20"
            />
          </label>
        </div>
      </div>
    </Modal>
  )
}
