import React, { useState, useMemo } from 'react'
import { Scan, Search } from 'lucide-react'
import DashboardLayout from '../layouts/DashboardLayout'
import { cn } from '../lib/utils'

const MOD_STYLE = {
  intraoral_2d: 'bg-blue-50 text-blue-700 border-blue-200',
  panoramic: 'bg-purple-50 text-purple-700 border-purple-200',
  cbct_3d: 'bg-teal-50 text-teal-700 border-teal-200',
  cephalometric: 'bg-indigo-50 text-indigo-700 border-indigo-200',
  photo: 'bg-amber-50 text-amber-700 border-amber-200',
  other: 'bg-gray-50 text-gray-600 border-gray-200',
}
const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

function Stat({ label, value }) {
  return (
    <div className="rounded-xl border border-brand-border bg-white px-5 py-4">
      <p className="text-xs font-medium uppercase tracking-wide text-brand-muted">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-brand-ink">{value}</p>
    </div>
  )
}

export default function Imaging({ studies = [], stats = {} }) {
  const [q, setQ] = useState('')
  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase()
    if (!s) return studies
    return studies.filter((x) => (x.patient_name || '').toLowerCase().includes(s) || x.modality.includes(s))
  }, [q, studies])

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary"><Scan size={18} className="text-white" /></div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Imaging (SIDEXIS)</h1>
          <p className="text-sm text-brand-muted">X-rays & scans from Sirona SIDEXIS — originals stay on-prem; matched to patients here</p>
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Studies" value={stats.total ?? studies.length} />
        <Stat label="Matched" value={stats.matched ?? '—'} />
        <Stat label="Needs match" value={stats.needs_match ?? '—'} />
        <Stat label="CBCT 3D" value={(stats.by_modality && stats.by_modality.cbct_3d) ?? 0} />
      </div>

      <div className="mb-3 flex items-center gap-2 rounded-xl border border-brand-border bg-white px-3 py-2">
        <Search size={15} className="text-brand-muted" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search patient or modality…" className="w-full bg-transparent text-sm outline-none placeholder:text-brand-muted" />
      </div>

      <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-3 font-semibold">Patient</th>
              <th className="px-4 py-3 font-semibold">Modality</th>
              <th className="px-4 py-3 font-semibold">Captured</th>
              <th className="px-4 py-3 font-semibold">Status</th>
              <th className="px-4 py-3 font-semibold">File</th>
            </tr>
          </thead>
          <tbody>
            {filtered.slice(0, 200).map((s) => (
              <tr key={s.id} className="border-b border-brand-border/60 last:border-0 hover:bg-brand-surface/50">
                <td className="px-4 py-2 text-brand-ink">{s.patient_name}</td>
                <td className="px-4 py-2"><span className={cn('inline-flex rounded-md border px-2 py-0.5 text-xs font-medium', MOD_STYLE[s.modality] || MOD_STYLE.other)}>{s.modality_label}</span></td>
                <td className="px-4 py-2 text-brand-muted">{fmtDate(s.captured_at)}</td>
                <td className="px-4 py-2">
                  <span className={cn('text-xs font-medium', s.status === 'matched' ? 'text-emerald-600' : 'text-amber-600')}>{s.status === 'matched' ? 'Matched' : 'Needs match'}</span>
                </td>
                <td className="px-4 py-2 text-xs text-brand-muted truncate max-w-[260px]">{s.file_name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {filtered.length > 200 && <p className="mt-2 text-center text-xs text-brand-muted">Showing first 200 of {filtered.length}.</p>}
    </DashboardLayout>
  )
}
