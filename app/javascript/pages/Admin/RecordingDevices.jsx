import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import { Mic, Plus, Trash2, Activity } from 'lucide-react'
import DashboardLayout from '../../layouts/DashboardLayout'
import { cn } from '../../lib/utils'

// N1 — Admin-only screen for managing the always-on recording layout.
// Paul sees this; receptionists / dentists never need to. The mic-listener
// daemons register here so transcripts know which room produced them.

const LOCATION_LABEL = {
  surgery_1: 'Surgery 1', surgery_2: 'Surgery 2',
  reception: 'Reception', waiting_area: 'Waiting area',
  sterilisation: 'Sterilisation', other: 'Other',
}

export default function RecordingDevices({ devices = [], locations = [] }) {
  const [name, setName]         = useState('')
  const [location, setLocation] = useState(locations[0] || 'surgery_1')
  const [notes, setNotes]       = useState('')

  const add = (e) => {
    e.preventDefault()
    router.post('/admin/recording-devices',
      { recording_device: { name, location, notes } },
      {
        preserveScroll: true,
        onSuccess: () => { setName(''); setNotes(''); toast.success('Device added') },
        onError:   (errs) => toast.error(Object.values(errs || {})[0] || 'Could not add'),
      })
  }
  const toggle = (d) => {
    router.patch(`/admin/recording-devices/${d.id}`,
      { recording_device: { enabled: !d.enabled } },
      { preserveScroll: true,
        onSuccess: () => toast.success(d.enabled ? 'Device disabled' : 'Device enabled'),
        onError:   () => toast.error('Could not update') })
  }
  const remove = (d) => {
    if (!confirm(`Remove recording device "${d.name}"? Existing scribe sessions stay but new audio from this device will no longer be routed.`)) return
    router.delete(`/admin/recording-devices/${d.id}`,
      { preserveScroll: true, onSuccess: () => toast.success('Removed') })
  }

  return (
    <DashboardLayout>
      <div className="mb-6 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-primary">
          <Mic size={18} className="text-white" />
        </div>
        <div>
          <h1 className="text-xl font-semibold text-brand-ink">Recording devices</h1>
          <p className="text-sm text-brand-muted">
            Always-on microphones across the practice. Admin-only. Receptionists and dentists never see this screen.
          </p>
        </div>
      </div>

      <div className="mb-6 rounded-xl border border-brand-border bg-white p-4">
        <h2 className="mb-3 text-sm font-semibold text-brand-ink">Add a device</h2>
        <form onSubmit={add} className="grid grid-cols-1 gap-3 sm:grid-cols-4">
          <input value={name} onChange={(e) => setName(e.target.value)}
            placeholder="Device name (e.g. Surgery 1)" required
            className="rounded-xl border border-brand-accent/80 bg-white px-3 py-2 text-sm focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45" />
          <select value={location} onChange={(e) => setLocation(e.target.value)}
            className="rounded-xl border border-brand-accent/80 bg-white px-3 py-2 text-sm">
            {locations.map((l) => <option key={l} value={l}>{LOCATION_LABEL[l] || l}</option>)}
          </select>
          <input value={notes} onChange={(e) => setNotes(e.target.value)}
            placeholder="Notes (model / position)"
            className="rounded-xl border border-brand-accent/80 bg-white px-3 py-2 text-sm" />
          <button type="submit"
            className="inline-flex items-center justify-center gap-1.5 rounded-xl bg-brand-primary px-4 py-2 text-sm font-semibold text-white hover:bg-brand-primary-dark">
            <Plus size={14} /> Add
          </button>
        </form>
      </div>

      <div className="overflow-hidden rounded-xl border border-brand-border bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-brand-border bg-brand-surface text-left text-xs uppercase tracking-wide text-brand-muted">
            <tr>
              <th className="px-4 py-3 font-semibold">Name</th>
              <th className="px-4 py-3 font-semibold">Location</th>
              <th className="px-4 py-3 font-semibold">Status</th>
              <th className="px-4 py-3 font-semibold">Last heard</th>
              <th className="px-4 py-3 font-semibold">Sessions today</th>
              <th className="px-4 py-3 text-right font-semibold">Actions</th>
            </tr>
          </thead>
          <tbody>
            {devices.map((d) => (
              <tr key={d.id} className="border-b border-brand-border/60 last:border-0">
                <td className="px-4 py-2.5 font-medium text-brand-ink">{d.name}</td>
                <td className="px-4 py-2.5 text-brand-muted">{LOCATION_LABEL[d.location] || d.location}</td>
                <td className="px-4 py-2.5">
                  <button onClick={() => toggle(d)}
                    className={cn(
                      'inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-xs font-medium',
                      d.enabled ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-gray-200 bg-gray-50 text-gray-500',
                    )}>
                    <Activity size={12} /> {d.enabled ? 'Listening' : 'Disabled'}
                  </button>
                </td>
                <td className="px-4 py-2.5 text-xs text-brand-muted">
                  {d.last_seen_at ? new Date(d.last_seen_at).toLocaleString('en-ZA') : 'Never (daemon not yet started)'}
                </td>
                <td className="px-4 py-2.5 text-xs text-brand-ink">{d.session_count_today}</td>
                <td className="px-4 py-2.5 text-right">
                  <button onClick={() => remove(d)} title="Remove device"
                    className="rounded-md p-1.5 text-brand-muted hover:bg-brand-surface hover:text-brand-danger">
                    <Trash2 size={14} />
                  </button>
                </td>
              </tr>
            ))}
            {devices.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-brand-muted">
                No devices configured. Add at least one to get the always-on scribe rolling.
              </td></tr>
            )}
          </tbody>
        </table>
      </div>

      <p className="mt-4 text-xs text-brand-muted">
        Listener daemon will register devices automatically once configured (see ENV <code>SCRIBE_LISTENER_*</code>).
        Until then, devices added here are reserved labels you can route audio to manually via the API.
      </p>
    </DashboardLayout>
  )
}
