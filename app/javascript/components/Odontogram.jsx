import React from 'react'
import { cn } from '../lib/utils'

// FDI two-digit notation. Upper arch: Q1 (18→11) + Q2 (21→28).
// Lower arch: Q4 (48→41) + Q3 (31→38).
const UPPER = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28]
const LOWER = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38]

const CONDITION_STYLE = {
  healthy:            'bg-white text-brand-ink border-brand-border',
  caries:             'bg-red-100 text-red-800 border-red-300',
  filling:            'bg-blue-100 text-blue-800 border-blue-300',
  crown:              'bg-amber-100 text-amber-800 border-amber-300',
  bridge:             'bg-amber-100 text-amber-800 border-amber-300',
  root_canal:         'bg-purple-100 text-purple-800 border-purple-300',
  implant:            'bg-teal-100 text-teal-800 border-teal-300',
  missing:            'bg-gray-200 text-gray-400 border-gray-300 line-through',
  extraction_planned: 'bg-orange-100 text-orange-800 border-orange-300',
  fracture:           'bg-pink-100 text-pink-800 border-pink-300',
}

const LABELS = {
  healthy: 'Healthy', caries: 'Caries', filling: 'Filling', crown: 'Crown', bridge: 'Bridge',
  root_canal: 'Root canal', implant: 'Implant', missing: 'Missing',
  extraction_planned: 'Extraction planned', fracture: 'Fracture',
}

function Tooth({ number, condition, onClick }) {
  const style = CONDITION_STYLE[condition] || CONDITION_STYLE.healthy
  return (
    <button
      type="button"
      onClick={onClick ? () => onClick(number) : undefined}
      title={`Tooth ${number}${condition ? ` — ${LABELS[condition] || condition}` : ''}`}
      className={cn(
        'flex h-10 w-9 flex-col items-center justify-center rounded-md border text-[11px] font-semibold transition-transform',
        style,
        onClick && 'hover:scale-105 cursor-pointer'
      )}
    >
      {number}
    </button>
  )
}

export default function Odontogram({ chart = {}, onToothClick = null }) {
  const present = Object.entries(chart)
  return (
    <div className="rounded-xl border border-brand-border bg-white p-4">
      <div className="flex flex-col items-center gap-1.5">
        <div className="flex gap-1">
          {UPPER.map((n) => <Tooth key={n} number={n} condition={chart[String(n)]} onClick={onToothClick} />)}
        </div>
        <div className="my-1 h-px w-full bg-brand-border" />
        <div className="flex gap-1">
          {LOWER.map((n) => <Tooth key={n} number={n} condition={chart[String(n)]} onClick={onToothClick} />)}
        </div>
      </div>

      {/* Legend — only conditions actually present, plus a hint when empty */}
      <div className="mt-4 flex flex-wrap gap-2">
        {present.length === 0 && (
          <span className="text-xs text-brand-muted">No charted conditions yet — every tooth is shown as healthy.</span>
        )}
        {[...new Set(present.map(([, c]) => c))].map((c) => (
          <span key={c} className={cn('inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 text-[11px] font-medium', CONDITION_STYLE[c] || CONDITION_STYLE.healthy)}>
            {LABELS[c] || c}
          </span>
        ))}
      </div>
    </div>
  )
}
