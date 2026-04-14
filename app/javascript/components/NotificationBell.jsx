import React, { useEffect, useRef, useState, useCallback } from 'react'
import { router, usePage } from '@inertiajs/react'
import {
  Bell, Check, Calendar, CalendarX, CalendarCheck, UserPlus,
  MessageSquare, Info, AlertTriangle,
} from 'lucide-react'

// ── Navbar notification bell + dropdown ─────────────────────────────
// Phase 9.6 sub-area #6.
//
// Badge count comes from Inertia shared props (`unread_notifications_count`)
// so it stays accurate on every page transition without an extra
// fetch. Opening the dropdown triggers a one-shot fetch to /notifications
// for the latest 20 items — we don't poll because the receptionist
// actively triggers the events that create notifications, so "fresh
// on open" is the right latency trade-off for this app.
//
// Marking individual notifications read:
//   - Click → navigate (via Inertia) AND mark read in the background
//   - "Mark all as read" → POST /notifications/mark_all_read

const ICONS = {
  appointment_created:     Calendar,
  appointment_cancelled:   CalendarX,
  appointment_confirmed:   CalendarCheck,
  appointment_rescheduled: Calendar,
  patient_created:         UserPlus,
  conversation_started:    MessageSquare,
  system:                  Info,
}

const LEVEL_STYLES = {
  info:    'bg-brand-primary/10 text-brand-primary',
  success: 'bg-brand-success/10 text-brand-success',
  warning: 'bg-brand-warning/10 text-brand-warning',
  danger:  'bg-brand-danger/10 text-brand-danger',
}

export default function NotificationBell() {
  const { props } = usePage()
  // Shared prop from ApplicationController#inertia_share. Falls back
  // to 0 so the badge renders correctly before the first fetch.
  const sharedUnread = props.unread_notifications_count ?? 0

  const [open, setOpen]       = useState(false)
  const [items, setItems]     = useState([])
  const [loading, setLoading] = useState(false)
  // Local override so the badge can drop to 0 instantly when the
  // user hits "Mark all as read", without waiting for the next
  // Inertia navigation.
  const [localUnread, setLocalUnread] = useState(null)
  const unreadCount = localUnread ?? sharedUnread

  const containerRef = useRef(null)

  // Keep the local override in sync when the shared prop changes
  // (i.e. after an Inertia navigation refreshes the count).
  useEffect(() => { setLocalUnread(null) }, [sharedUnread])

  // Close on outside click.
  useEffect(() => {
    const handler = (e) => {
      if (!containerRef.current?.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const fetchItems = useCallback(async () => {
    setLoading(true)
    try {
      const res = await fetch('/notifications', {
        headers: { Accept: 'application/json' },
      })
      const data = await res.json()
      setItems(data.notifications || [])
      setLocalUnread(data.unread_count ?? 0)
    } catch (e) {
      // Silent — bell stays in previous state; console already logs.
      // eslint-disable-next-line no-console
      console.error('Failed to fetch notifications', e)
    } finally {
      setLoading(false)
    }
  }, [])

  const toggle = () => {
    const next = !open
    setOpen(next)
    if (next) fetchItems()
  }

  const markRead = async (id) => {
    try {
      await fetch(`/notifications/${id}/mark_read`, {
        method: 'PATCH',
        headers: {
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
      })
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('mark_read failed', e)
    }
  }

  const markAllRead = async () => {
    // Optimistic update so the badge snaps to 0 immediately.
    setLocalUnread(0)
    setItems((prev) => prev.map((n) => ({ ...n, read: true })))
    try {
      await fetch('/notifications/mark_all_read', {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
      })
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('mark_all_read failed', e)
    }
  }

  const clickItem = (n) => {
    setOpen(false)
    if (!n.read) {
      // Optimistic: drop the badge count immediately.
      setLocalUnread((prev) => Math.max(0, (prev ?? unreadCount) - 1))
      setItems((prev) => prev.map((x) => (x.id === n.id ? { ...x, read: true } : x)))
      markRead(n.id)
    }
    if (n.url) router.visit(n.url)
  }

  return (
    <div ref={containerRef} className="relative">
      <button
        onClick={toggle}
        className="relative rounded-2xl border border-transparent p-2 text-brand-muted transition-colors hover:border-brand-accent hover:bg-brand-surface/35 hover:text-brand-ink"
        aria-label="Notifications"
        aria-haspopup="true"
        aria-expanded={open}
      >
        <Bell size={18} />
        {unreadCount > 0 && (
          <span className="absolute right-1 top-1 flex h-[16px] min-w-[16px] items-center justify-center rounded-full bg-brand-danger px-1 text-[10px] font-semibold text-white">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 z-50 mt-2 flex max-h-[32rem] w-96 flex-col overflow-hidden rounded-xl border border-brand-accent/80 bg-white shadow-[0_30px_70px_-42px_rgba(57,60,77,0.45)]">
          <div className="flex items-center justify-between border-b border-brand-accent/70 px-4 py-3">
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-semibold text-brand-ink">Notifications</h3>
              {unreadCount > 0 && (
                <span className="rounded-full bg-brand-danger/10 px-1.5 py-0.5 text-[10px] font-semibold text-brand-danger">
                  {unreadCount} new
                </span>
              )}
            </div>
            {unreadCount > 0 && (
              <button
                type="button"
                onClick={markAllRead}
                className="inline-flex items-center gap-1 text-xs font-medium text-brand-primary transition-colors hover:text-brand-primary-dark"
              >
                <Check size={12} /> Mark all as read
              </button>
            )}
          </div>

          <div className="flex-1 overflow-y-auto">
            {loading && items.length === 0 ? (
              <EmptyState message="Loading…" />
            ) : items.length === 0 ? (
              <EmptyState message="You're all caught up" />
            ) : (
              items.map((n) => (
                <NotificationRow key={n.id} n={n} onClick={() => clickItem(n)} />
              ))
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function NotificationRow({ n, onClick }) {
  const Icon = ICONS[n.category] || (n.level === 'warning' ? AlertTriangle : Info)
  const toneClass = LEVEL_STYLES[n.level] || LEVEL_STYLES.info
  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full border-b border-brand-accent/35 px-4 py-3 text-left transition-colors last:border-b-0 ${
        n.read ? 'hover:bg-brand-surface/18' : 'bg-brand-surface/22 hover:bg-brand-surface/48'
      }`}
    >
      <div className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${toneClass}`}>
        <Icon size={14} />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <p className={`truncate text-sm ${n.read ? 'text-brand-muted' : 'font-semibold text-brand-ink'}`}>
            {n.title}
          </p>
          {!n.read && (
            <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand-primary" />
          )}
        </div>
        {n.body && <p className="truncate text-xs text-brand-muted">{n.body}</p>}
        <p className="mt-1 text-[10px] text-brand-muted">{relativeTime(n.created_at)}</p>
      </div>
    </button>
  )
}

function EmptyState({ message }) {
  return (
    <div className="px-4 py-10 text-center text-sm text-brand-muted">{message}</div>
  )
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
}

function relativeTime(iso) {
  if (!iso) return ''
  const then = new Date(iso).getTime()
  const diff = Date.now() - then
  const mins = Math.floor(diff / 60000)
  if (mins < 1)  return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d ago`
  return new Date(iso).toLocaleDateString('en-ZA')
}
