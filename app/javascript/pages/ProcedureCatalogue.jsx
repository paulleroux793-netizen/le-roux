import React, { useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import { Stethoscope, Search, Pencil, Check, X, Plus, TrendingUp } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const CATEGORY_COLORS = {
  diagnostic:  'bg-blue-50 text-blue-700 border-blue-200',
  restorative: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  surgical:    'bg-red-50 text-red-700 border-red-200',
  preventive:  'bg-teal-50 text-teal-700 border-teal-200',
  cosmetic:    'bg-purple-50 text-purple-700 border-purple-200',
  other:       'bg-gray-50 text-gray-700 border-gray-200',
}
const CATEGORIES = ['diagnostic', 'restorative', 'surgical', 'preventive', 'cosmetic', 'other']
const VAT_OPTIONS = [['standard', '15%'], ['zero_rated', 'Zero']]
const EMPTY_ADD = { code: '', description: '', fee: '', category: 'other', vat_treatment: 'standard' }

const rand = (n) => (n == null ? '—' : `R${n.toLocaleString('en-ZA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`)

function Stat({ label, value }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-brand-ink">{value}</p>
    </div>
  )
}

const inputCls = 'w-full rounded-md border border-brand-primary/60 bg-white px-2 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary/40'

export default function ProcedureCatalogue({ codes = [], stats = {} }) {
  const [q, setQ] = useState('')
  const [editingId, setEditingId] = useState(null)
  const [draft, setDraft] = useState({ description: '', fee: '', category: 'other', vat_treatment: 'standard' })
  const [saving, setSaving] = useState(false)
  const [adding, setAdding] = useState(false)
  const [addDraft, setAddDraft] = useState(EMPTY_ADD)

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase()
    if (!s) return codes
    return codes.filter((c) => c.code.toLowerCase().includes(s) || (c.description || '').toLowerCase().includes(s))
  }, [q, codes])

  const startEdit = (c) => {
    setEditingId(c.id)
    setDraft({
      description: c.description || '',
      fee: c.fee != null ? String(c.fee) : '',
      category: c.category || 'other',
      vat_treatment: c.vat_treatment || 'standard',
    })
  }
  const cancelEdit = () => { setEditingId(null) }

  const saveEdit = (c) => {
    if (!draft.description.trim()) { toast.error('Description cannot be blank'); return }
    setSaving(true)
    router.patch(`/procedure-codes/${c.id}`, { procedure_code: {
      description: draft.description.trim(), fee: draft.fee, category: draft.category, vat_treatment: draft.vat_treatment,
    } }, {
      preserveScroll: true,
      onSuccess: (page) => { toast.success(page?.props?.flash?.notice || 'Updated'); cancelEdit() },
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not update'),
      onFinish: () => setSaving(false),
    })
  }

  const saveAdd = () => {
    if (!addDraft.code.trim() || !addDraft.description.trim()) { toast.error('Code and description are required'); return }
    setSaving(true)
    router.post('/procedure-codes', { procedure_code: addDraft }, {
      preserveScroll: true,
      onSuccess: (page) => { toast.success(page?.props?.flash?.notice || 'Added'); setAdding(false); setAddDraft(EMPTY_ADD) },
      onError: (errs) => toast.error(Object.values(errs || {})[0] || 'Could not add'),
      onFinish: () => setSaving(false),
    })
  }

  const bulkUplift = () => {
    const pct = window.prompt('Increase ALL fees by what % ? (e.g. 6 for the annual SADA increase)')
    if (pct == null) return
    const n = parseFloat(pct)
    if (!n) { toast.error('Enter a number, e.g. 6'); return }
    if (!window.confirm(`Apply +${n}% to every priced fee? (VAT-inclusive)`)) return
    router.post('/procedure-codes/bulk-uplift', { percent: n }, {
      preserveScroll: true,
      onSuccess: (page) => toast.success(page?.props?.flash?.notice || `Applied ${n}%`),
      onError: () => toast.error('Could not apply uplift'),
    })
  }

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Stethoscope size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Procedure Catalogue</h1>
          <p className="text-sm text-brand-muted">SADA tariff codes, fees, and VAT treatment · fees are VAT-inclusive at 15%</p>
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Codes" value={stats.total ?? codes.length} />
        <Stat label="Priced" value={stats.priced ?? '—'} />
        <Stat label="Zero-rated" value={stats.zero_rated ?? '—'} />
        <Stat label="VAT 15%" value={stats.standard_rated ?? '—'} />
      </div>

      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="flex flex-1 items-center gap-2 rounded-xl border border-brand-border bg-white px-3 py-2">
          <Search size={15} className="text-brand-muted" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search code or description…"
            className="w-full bg-transparent text-sm outline-none placeholder:text-brand-muted"
          />
        </div>
        <button
          type="button"
          onClick={() => setAdding((a) => !a)}
          className="inline-flex items-center gap-1.5 rounded-xl border border-brand-primary bg-brand-primary px-3 py-2 text-sm font-medium text-white hover:brightness-95"
        >
          <Plus size={15} /> Add code
        </button>
        <button
          type="button"
          onClick={bulkUplift}
          className="inline-flex items-center gap-1.5 rounded-xl border border-brand-border bg-white px-3 py-2 text-sm font-medium text-brand-ink hover:bg-brand-surface"
        >
          <TrendingUp size={15} /> Bulk uplift
        </button>
      </div>

      {adding && (
        <div className="mb-3 rounded-xl border border-brand-primary/40 bg-brand-surface/40 p-3">
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-6">
            <input value={addDraft.code} onChange={(e) => setAddDraft({ ...addDraft, code: e.target.value })} placeholder="Code (e.g. 8201)" className={inputCls} />
            <input value={addDraft.description} onChange={(e) => setAddDraft({ ...addDraft, description: e.target.value })} placeholder="Description" className={cn(inputCls, 'sm:col-span-2')} />
            <select value={addDraft.category} onChange={(e) => setAddDraft({ ...addDraft, category: e.target.value })} className={inputCls}>
              {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <select value={addDraft.vat_treatment} onChange={(e) => setAddDraft({ ...addDraft, vat_treatment: e.target.value })} className={inputCls}>
              {VAT_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
            <input value={addDraft.fee} onChange={(e) => setAddDraft({ ...addDraft, fee: e.target.value })} placeholder="Fee (incl VAT)" inputMode="decimal" className={inputCls} />
          </div>
          <div className="mt-2 flex justify-end gap-2">
            <button type="button" onClick={() => { setAdding(false); setAddDraft(EMPTY_ADD) }} className="rounded-md px-3 py-1.5 text-sm text-brand-muted hover:bg-brand-surface">Cancel</button>
            <button type="button" onClick={saveAdd} disabled={saving} className="rounded-md bg-brand-primary px-3 py-1.5 text-sm font-medium text-white hover:brightness-95 disabled:opacity-40">Save code</button>
          </div>
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-3 font-semibold">Code</th>
              <th className="px-4 py-3 font-semibold">Description</th>
              <th className="px-4 py-3 font-semibold">Category</th>
              <th className="px-4 py-3 font-semibold">VAT</th>
              <th className="px-4 py-3 text-right font-semibold">Fee</th>
              <th className="px-4 py-3 text-right font-semibold"> </th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((c) => {
              const isEditing = editingId === c.id
              return (
                <tr key={c.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                  <td className="px-4 py-2.5 font-mono font-medium text-brand-ink">{c.code}</td>
                  <td className="px-4 py-2.5 text-brand-ink">
                    {isEditing ? (
                      <input
                        value={draft.description}
                        onChange={(e) => setDraft({ ...draft, description: e.target.value })}
                        onKeyDown={(e) => { if (e.key === 'Enter') saveEdit(c); if (e.key === 'Escape') cancelEdit() }}
                        autoFocus disabled={saving} className={inputCls}
                      />
                    ) : (
                      <span>{c.description}</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5">
                    {isEditing ? (
                      <select value={draft.category} onChange={(e) => setDraft({ ...draft, category: e.target.value })} className={inputCls}>
                        {CATEGORIES.map((cat) => <option key={cat} value={cat}>{cat}</option>)}
                      </select>
                    ) : (
                      <span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', CATEGORY_COLORS[c.category] || CATEGORY_COLORS.other)}>{c.category}</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-xs text-brand-muted">
                    {isEditing ? (
                      <select value={draft.vat_treatment} onChange={(e) => setDraft({ ...draft, vat_treatment: e.target.value })} className={inputCls}>
                        {VAT_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                      </select>
                    ) : (c.vat_treatment === 'standard' ? '15%' : 'Zero')}
                  </td>
                  <td className="px-4 py-2.5 text-right font-medium text-brand-ink">
                    {isEditing ? (
                      <input
                        value={draft.fee}
                        onChange={(e) => setDraft({ ...draft, fee: e.target.value })}
                        onKeyDown={(e) => { if (e.key === 'Enter') saveEdit(c); if (e.key === 'Escape') cancelEdit() }}
                        inputMode="decimal" disabled={saving} className={cn(inputCls, 'text-right')}
                      />
                    ) : rand(c.fee)}
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    {isEditing ? (
                      <div className="flex items-center justify-end gap-1">
                        <button type="button" onClick={() => saveEdit(c)} disabled={saving} title="Save (Enter)" className="rounded-md p-1 text-emerald-600 hover:bg-emerald-50 disabled:opacity-40"><Check size={15} /></button>
                        <button type="button" onClick={cancelEdit} disabled={saving} title="Cancel (Esc)" className="rounded-md p-1 text-brand-muted hover:bg-brand-surface"><X size={15} /></button>
                      </div>
                    ) : (
                      <button type="button" onClick={() => startEdit(c)} title="Edit" className="rounded-md p-1 text-brand-muted hover:bg-brand-surface hover:text-brand-ink"><Pencil size={13} /></button>
                    )}
                  </td>
                </tr>
              )
            })}
            {filtered.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-brand-muted">No codes match “{q}”.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </DashboardLayout>
  )
}
