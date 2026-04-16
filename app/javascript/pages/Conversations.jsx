import React, { useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  MessageSquare, Search, Upload,
  ChevronLeft, ChevronRight, Clock, X as XIcon,
} from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { useLanguage } from '../lib/LanguageContext'

const PAGE_SIZE = 10

export default function Conversations({ conversations = [], filters }) {
  const { t, language } = useLanguage()
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(0)
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

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageItems = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)

  const handleFilter = (key, value) => {
    router.get('/conversations', { ...filters, [key]: value || undefined }, { preserveState: true })
  }

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-start justify-between gap-4">
        <div>
          <span className="inline-flex items-center rounded-full border border-brand-accent bg-white px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.22em] text-brand-primary">
            {t('conv_badge')}
          </span>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-brand-ink">{t('conv_title')}</h1>
          <p className="mt-2 text-sm leading-6 text-brand-muted">{t('conv_subtitle')}</p>
        </div>
        <button
          type="button"
          onClick={() => setImportOpen(true)}
          className="inline-flex items-center gap-2 rounded-2xl bg-brand-primary px-4 py-2.5 text-sm font-medium text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] transition-colors hover:bg-brand-primary-dark"
        >
          <Upload size={15} />
          {t('conv_import')}
        </button>
      </div>

      {/* Toolbar */}
      <div className="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-brand-accent/75 bg-white p-3 shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <div className="relative flex-1 min-w-[240px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted" />
          <input
            type="text"
            value={query}
            onChange={(e) => { setQuery(e.target.value); setPage(0) }}
            placeholder={t('conv_search')}
            className="w-full rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 pl-9 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
          />
        </div>

        <FilterPill
          value={filters?.source || ''}
          onChange={(v) => handleFilter('source', v)}
          options={[
            { value: '', label: t('conv_all_sources') },
            { value: 'live', label: t('conv_live') },
            { value: 'import', label: t('conv_imported') },
          ]}
        />
        <FilterPill
          value={filters?.channel || ''}
          onChange={(v) => handleFilter('channel', v)}
          options={[
            { value: '', label: t('conv_all_channels') },
            { value: 'whatsapp', label: t('conv_whatsapp') },
            { value: 'voice', label: t('conv_voice') },
          ]}
        />
      </div>

      {/* Row list */}
      <div className="overflow-hidden rounded-xl border border-brand-accent/75 bg-white shadow-[0_24px_60px_-46px_rgba(57,60,77,0.35)]">
        <div className="flex items-center gap-3 border-b border-brand-accent/60 bg-brand-surface/25 px-5 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-brand-muted">
          <span className="w-9" />
          <span className="flex-1">{t('conv_col_customer')}</span>
          <span className="hidden md:block w-[38%]">{t('conv_col_topic')}</span>
          <span className="w-28 text-right">{t('conv_col_when')}</span>
          <span className="w-20" />
        </div>

        {pageItems.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-brand-surface">
              <MessageSquare size={18} className="text-brand-primary" />
            </div>
            <p className="text-sm text-brand-muted">{t('conv_no_match')}</p>
          </div>
        ) : (
          <ul className="divide-y divide-brand-accent/35">
            {pageItems.map((c) => (
              <ConversationRow key={c.id} conv={c} t={t} language={language} />
            ))}
          </ul>
        )}

        {filtered.length > 0 && (
          <div className="flex items-center justify-between border-t border-brand-accent/60 px-5 py-3 text-xs text-brand-muted">
            <span>
              {t('conv_showing')} {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, filtered.length)} {t('rem_of')} {filtered.length}
            </span>
            <div className="flex items-center gap-1">
              <button
                type="button"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                className="rounded-xl p-1.5 hover:bg-brand-surface/45 disabled:opacity-40 disabled:hover:bg-transparent"
                aria-label="Previous page"
              >
                <ChevronLeft size={14} />
              </button>
              <span className="px-2">
                {page + 1} / {pageCount}
              </span>
              <button
                type="button"
                disabled={page + 1 >= pageCount}
                onClick={() => setPage((p) => Math.min(pageCount - 1, p + 1))}
                className="rounded-xl p-1.5 hover:bg-brand-surface/45 disabled:opacity-40 disabled:hover:bg-transparent"
                aria-label="Next page"
              >
                <ChevronRight size={14} />
              </button>
            </div>
          </div>
        )}
      </div>

      <ImportModal open={importOpen} onClose={() => setImportOpen(false)} t={t} />
    </DashboardLayout>
  )
}

function ConversationRow({ conv, t, language }) {
  const openConversation = () => {
    router.visit(`/conversations/${conv.id}`)
  }

  const snippet = conv.topic || conv.last_message || '—'
  const relative = formatRelative(conv.updated_at, t, language)

  return (
    <li
      onClick={openConversation}
      className="group flex cursor-pointer items-center gap-3 px-5 py-3.5 transition-colors hover:bg-brand-surface/25"
    >
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
        conv.channel === 'whatsapp' ? 'bg-brand-success/10 text-brand-success' : 'bg-brand-primary/10 text-brand-primary'
      }`}>
        <MessageSquare size={16} />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="truncate text-sm font-medium text-brand-ink group-hover:text-brand-primary">
            {conv.patient_name}
          </p>
          {conv.source === 'import' && (
            <span className="rounded-full bg-brand-surface px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-brand-primary">
              {t('conv_imported')}
            </span>
          )}
        </div>
        <p className="mt-0.5 truncate text-[11px] text-brand-muted">{conv.patient_phone}</p>
      </div>

      <div className="hidden md:block w-[38%] min-w-0">
        {conv.topic && (
          <p className="truncate text-xs font-medium text-brand-primary">{conv.topic}</p>
        )}
        {conv.last_message && (
          <p className="mt-0.5 truncate text-xs text-brand-muted">{conv.last_message}</p>
        )}
        {!conv.topic && !conv.last_message && (
          <p className="text-xs text-brand-muted/70">{t('conv_no_messages')}</p>
        )}
      </div>
      <div className="max-w-[40%] truncate text-xs text-brand-muted md:hidden">
        {snippet}
      </div>

      <div className="w-28 text-right flex-shrink-0">
        <span className="inline-flex items-center gap-1 text-[11px] text-brand-muted">
          <Clock size={10} />
          {relative}
        </span>
      </div>

      <div className="w-20 flex items-center justify-end flex-shrink-0">
        <span className="text-[11px] text-brand-muted">{conv.message_count} {t('conv_msgs')}</span>
      </div>
    </li>
  )
}

function FilterPill({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="rounded-2xl border border-brand-accent/80 bg-white px-3 py-2.5 text-xs font-medium text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>{o.label}</option>
      ))}
    </select>
  )
}

function ImportModal({ open, onClose, t }) {
  const [file, setFile] = useState(null)
  const [ownerName, setOwnerName] = useState('Dr Le Roux')
  const [patientPhone, setPatientPhone] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (!open) return null

  const isTxt = file && /\.txt$/i.test(file.name)

  const handleSubmit = (e) => {
    e.preventDefault()
    if (!file) {
      toast.error(t('conv_import_choose'))
      return
    }
    const formData = new FormData()
    formData.append('file', file)
    if (isTxt) {
      formData.append('owner_name', ownerName)
      formData.append('patient_phone', patientPhone)
    }
    setSubmitting(true)
    router.post('/conversations/import', formData, {
      forceFormData: true,
      onSuccess: () => { onClose(); setFile(null); setPatientPhone('') },
      onError:   () => toast.error(t('conv_import_error')),
      onFinish:  () => setSubmitting(false),
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-brand-ink/30 p-4 backdrop-blur-[4px]">
      <div className="w-full max-w-md rounded-xl border border-brand-accent/80 bg-white shadow-[0_38px_90px_-55px_rgba(57,60,77,0.5)]">
        <div className="flex items-center justify-between border-b border-brand-accent/70 bg-gradient-to-br from-brand-surface/45 via-white to-white px-5 py-4">
          <h2 className="text-sm font-semibold text-brand-ink">{t('conv_import_title')}</h2>
          <button type="button" onClick={onClose} className="rounded-xl p-1 text-brand-muted transition-colors hover:bg-brand-surface/45 hover:text-brand-ink">
            <XIcon size={16} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-brand-muted">
              {t('conv_import_file_label')}
            </label>
            <input
              type="file"
              accept=".json,.txt"
              onChange={(e) => setFile(e.target.files?.[0] || null)}
              className="block w-full text-xs text-brand-muted file:mr-3 file:rounded-2xl file:border-0 file:bg-brand-surface file:px-3 file:py-2 file:text-xs file:font-semibold file:text-brand-primary hover:file:bg-brand-accent"
            />
            <p className="mt-1.5 text-[11px] text-brand-muted">
              {t('conv_import_file_hint')} <code>phone</code>, <code>name</code>, <code>messages[]</code>.
            </p>
          </div>

          {isTxt && (
            <>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-brand-muted">
                  {t('conv_import_owner_label')}
                </label>
                <input
                  type="text"
                  value={ownerName}
                  onChange={(e) => setOwnerName(e.target.value)}
                  className="w-full rounded-2xl border border-brand-accent/80 px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-brand-muted">
                  {t('conv_import_phone_label')}
                </label>
                <input
                  type="tel"
                  value={patientPhone}
                  onChange={(e) => setPatientPhone(e.target.value)}
                  required
                  className="w-full rounded-2xl border border-brand-accent/80 px-3 py-2.5 text-sm text-brand-ink focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
                />
              </div>
            </>
          )}

          <div className="flex items-center justify-end gap-2 pt-2">
            <button type="button" onClick={onClose} className="rounded-2xl px-3 py-2 text-xs font-medium text-brand-muted hover:bg-brand-surface/45">
              {t('conv_import_cancel')}
            </button>
            <button
              type="submit"
              disabled={submitting || !file}
              className="inline-flex items-center gap-2 rounded-2xl bg-brand-primary px-4 py-2 text-xs font-medium text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.9)] hover:bg-brand-primary-dark disabled:opacity-50"
            >
              <Upload size={13} />
              {submitting ? t('conv_import_importing') : t('conv_import_btn')}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function formatRelative(iso, t, language) {
  if (!iso) return '—'
  const locale = language === 'af' ? 'af-ZA' : 'en-ZA'
  const d = new Date(iso)
  const diffMs = Date.now() - d.getTime()
  const mins = Math.round(diffMs / 60000)
  if (mins < 1) return t('conv_just_now')
  if (mins < 60) return `${mins}${t('conv_m_ago')}`
  const hrs = Math.round(mins / 60)
  if (hrs < 24) return `${hrs}${t('conv_h_ago')}`
  const days = Math.round(hrs / 24)
  if (days < 7) return `${days}${t('conv_d_ago')}`
  return d.toLocaleDateString(locale, { month: 'short', day: 'numeric' })
}
