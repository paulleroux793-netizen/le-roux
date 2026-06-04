import React, { useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { FolderOpen, Folder, FileText, Image, FileSignature, StickyNote, ArrowLeft, ShieldCheck, MessageCircle, Send, Printer } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const DOC_ICON = { image: Image, xray: Image, form: FileSignature, note: StickyNote, pdf: FileText, file: FileText }
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export default function PatientFile({ patient = {}, folders = [], forms = [], notes = [] }) {
  const [open, setOpen] = useState(folders.find((f) => f.count > 0)?.key || null)
  const [sending, setSending] = useState(false)

  const hasCompletedForm = forms.some((f) => f.status === 'completed')

  const sendIntake = () => {
    if (!window.confirm(`Send the intake forms link to ${patient.name} on WhatsApp?`)) return
    setSending(true)
    router.post(`/patients/${patient.id}/send-intake`, {}, {
      preserveScroll: true,
      onFinish: () => setSending(false),
    })
  }

  return (
    <DashboardLayout>
      <Link href={`/patients/${patient.id}`} className="mb-4 inline-flex items-center gap-1 text-sm text-brand-muted hover:text-brand-ink">
        <ArrowLeft size={14} /> Patient
      </Link>

      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <FolderOpen size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">{patient.name} — Digital File</h1>
          <p className="text-sm text-brand-muted">Paperless patient file — replaces the physical folders</p>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        {/* Folders + documents */}
        <div className="lg:col-span-2">
          <div className="space-y-2">
            {folders.map((f) => {
              const isOpen = open === f.key
              return (
                <div key={f.key} className="overflow-hidden rounded-xl border border-brand-border bg-white">
                  <button onClick={() => setOpen(isOpen ? null : f.key)} className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-brand-surface/50">
                    <Folder size={16} className="text-brand-muted" />
                    <span className="text-sm font-medium text-brand-ink">{f.label}</span>
                    <span className="ml-auto text-xs text-brand-muted">{f.count}</span>
                  </button>
                  {isOpen && f.documents.length > 0 && (
                    <div className="border-t border-brand-border">
                      {f.documents.map((d) => {
                        const Icon = DOC_ICON[d.doc_type] || FileText
                        return (
                          <div key={d.id} className="flex items-center gap-3 border-b border-brand-border/50 px-4 py-2 last:border-0">
                            <Icon size={15} className="text-brand-muted" />
                            <span className="text-sm text-brand-ink">{d.title}</span>
                            {d.signed && <span className="inline-flex items-center gap-1 rounded border border-emerald-200 bg-emerald-50 px-1.5 py-0.5 text-[11px] text-emerald-700"><ShieldCheck size={11} /> Signed</span>}
                            <span className="ml-auto text-xs text-brand-muted">{d.source.replace('_', ' ')} · {fmtDate(d.captured_at)}</span>
                          </div>
                        )
                      })}
                    </div>
                  )}
                  {isOpen && f.documents.length === 0 && (
                    <div className="border-t border-brand-border px-4 py-3 text-xs text-brand-muted">Empty folder.</div>
                  )}
                </div>
              )
            })}
          </div>
        </div>

        {/* Forms + notepad */}
        <div className="space-y-6">
          <div>
            <div className="mb-2 flex items-center justify-between">
              <h2 className="flex items-center gap-2 text-sm font-semibold text-brand-ink"><MessageCircle size={15} /> WhatsApp forms</h2>
              <div className="flex items-center gap-1.5">
                <button
                  onClick={sendIntake}
                  disabled={sending}
                  className="inline-flex items-center gap-1 rounded-lg bg-brand-primary px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary-dark disabled:opacity-60"
                >
                  <Send size={12} /> {sending ? 'Sending…' : 'Send intake'}
                </button>
                {hasCompletedForm && (
                  <a
                    href={`/patients/${patient.id}/intake.pdf`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 rounded-lg border border-brand-border bg-white px-2.5 py-1.5 text-xs font-semibold text-brand-ink-soft hover:bg-brand-surface"
                  >
                    <Printer size={12} /> Print pack
                  </a>
                )}
              </div>
            </div>
            <div className="rounded-xl border border-brand-border bg-white">
              {forms.length === 0 && <p className="px-4 py-3 text-xs text-brand-muted">No forms sent.</p>}
              {forms.map((s) => (
                <div key={s.id} className="flex items-center gap-2 border-b border-brand-border/50 px-4 py-2 last:border-0">
                  <span className="text-sm text-brand-ink">{s.name}</span>
                  {s.signed && <ShieldCheck size={12} className="text-emerald-600" />}
                  <span className={cn('ml-auto rounded px-1.5 py-0.5 text-[11px]', s.status === 'completed' ? 'bg-emerald-50 text-emerald-700' : 'bg-blue-50 text-blue-700')}>{s.status}</span>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold text-brand-ink"><StickyNote size={15} /> Notepad</h2>
            <div className="rounded-xl border border-brand-border bg-white">
              {notes.length === 0 && <p className="px-4 py-3 text-xs text-brand-muted">No notes.</p>}
              {notes.map((n) => (
                <div key={n.id} className="border-b border-brand-border/50 px-4 py-2 last:border-0">
                  <p className="text-sm font-medium text-brand-ink">{n.title}</p>
                  <p className="text-xs text-brand-muted">{n.content}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </DashboardLayout>
  )
}
