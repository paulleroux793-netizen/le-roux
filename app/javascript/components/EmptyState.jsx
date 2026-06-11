import React from 'react'
import { Inbox } from 'lucide-react'

// Reusable empty state. Benchmark (Linear/Stripe/Notion): always answer
// what's here, why it's empty, and the one thing to do next.
//   <EmptyState icon={CalendarPlus} title="No appointments yet"
//     description="Bookings for this day will show here." action={<button…/>} />
// Use `compact` for inline/table empties (less vertical padding).
export default function EmptyState({ icon: Icon = Inbox, title, description, action, compact = false }) {
  return (
    <div className={`flex flex-col items-center justify-center rounded-xl border border-dashed border-brand-border text-center ${compact ? 'px-4 py-6' : 'px-6 py-12'}`}>
      <div className="mb-3 rounded-full bg-brand-surface p-3 text-brand-muted">
        <Icon size={compact ? 18 : 22} />
      </div>
      <p className="text-sm font-semibold text-brand-ink">{title}</p>
      {description && <p className="mt-1 max-w-sm text-xs leading-snug text-brand-muted">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}
