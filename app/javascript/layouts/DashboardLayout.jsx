import React from 'react'
import { Link, usePage } from '@inertiajs/react'
import {
  LayoutDashboard, Calendar, Users, MessageSquare, BarChart2,
  BellRing, Settings, ChevronDown, HelpCircle,
} from 'lucide-react'
import { cn } from '../lib/utils'
import GlobalSearch from '../components/GlobalSearch'
import NotificationBell from '../components/NotificationBell'

const NAV_ITEMS = [
  { name: 'Dashboard',     href: '/dashboard',     icon: LayoutDashboard },
  { name: 'Appointments',  href: '/appointments',  icon: Calendar },
  { name: 'Reminders',     href: '/reminders',     icon: BellRing },
  { name: 'Patients',      href: '/patients',      icon: Users },
  { name: 'Conversations', href: '/conversations', icon: MessageSquare },
  { name: 'Analytics',     href: '/analytics',     icon: BarChart2 },
]

export default function DashboardLayout({ children }) {
  const { url } = usePage()

  const isActive = (href) =>
    href === '/dashboard'
      ? url === '/' || url === '/dashboard'
      : url.startsWith(href)

  return (
    <div className="min-h-screen bg-transparent text-brand-ink">

      {/* ── Sidebar ─────────────────────────────────────────────────── */}
      <aside className="fixed inset-y-0 left-0 z-30 flex w-64 flex-col border-r border-brand-accent/70 bg-white/95 shadow-[0_24px_65px_-52px_rgba(57,60,77,0.35)] backdrop-blur">

        {/* Practice identity */}
        <div className="border-b border-brand-accent/70 px-5 py-5">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-2xl bg-brand-primary shadow-[0_18px_35px_-22px_rgba(49,100,222,0.9)]">
              <span className="select-none text-sm font-bold text-white">DL</span>
            </div>
            <div className="min-w-0">
              <h1 className="truncate text-sm font-semibold leading-tight text-brand-ink">
                Dr Chalita le Roux
              </h1>
              <p className="mt-0.5 text-xs tracking-wide text-brand-muted">AI Receptionist</p>
            </div>
          </div>
        </div>

        {/* Main navigation */}
        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-5">
          <p className="mb-3 px-3 text-xs font-semibold uppercase tracking-[0.22em] text-brand-muted select-none">
            Menu
          </p>
          {NAV_ITEMS.map(({ name, href, icon: Icon }) => {
            const active = isActive(href)
            return (
              <Link
                key={name}
                href={href}
                className={cn(
                  'flex items-center gap-3 rounded-2xl px-3.5 py-3 text-sm font-medium transition-all',
                  active
                    ? 'bg-brand-primary text-white shadow-[0_22px_45px_-30px_rgba(49,100,222,0.95)]'
                    : 'text-brand-muted hover:bg-brand-surface/45 hover:text-brand-ink'
                )}
              >
                <Icon
                  size={16}
                  className={cn('flex-shrink-0', active ? 'text-white' : 'text-brand-muted')}
                />
                <span className="truncate">{name}</span>
                {active && (
                  <span className="ml-auto h-1.5 w-1.5 flex-shrink-0 rounded-full bg-white" />
                )}
              </Link>
            )
          })}
        </nav>

        {/* Bottom — Settings / Support */}
        <div className="space-y-1 border-t border-brand-accent/70 px-3 pb-4 pt-3">
          <Link
            href="/settings"
            className={cn(
              'flex items-center gap-3 rounded-2xl px-3.5 py-3 text-sm font-medium transition-all',
              isActive('/settings')
                ? 'bg-brand-primary text-white shadow-[0_22px_45px_-30px_rgba(49,100,222,0.95)]'
                : 'text-brand-muted hover:bg-brand-surface/45 hover:text-brand-ink'
            )}
          >
            <Settings
              size={16}
              className={cn(
                'flex-shrink-0',
                isActive('/settings') ? 'text-white' : 'text-brand-muted'
              )}
            />
            Settings
            {isActive('/settings') && (
              <span className="ml-auto h-1.5 w-1.5 flex-shrink-0 rounded-full bg-white" />
            )}
          </Link>

          <button className="w-full rounded-2xl px-3.5 py-3 text-left text-sm font-medium text-brand-muted transition-all hover:bg-brand-surface/45 hover:text-brand-ink">
            <span className="flex items-center gap-3">
              <HelpCircle size={16} className="flex-shrink-0 text-brand-muted" />
              Support
            </span>
          </button>
        </div>
      </aside>

      {/* ── Top navbar ──────────────────────────────────────────────── */}
      <header className="fixed left-64 right-0 top-0 z-20 flex h-16 items-center gap-4 border-b border-brand-accent/70 bg-white/88 px-6 backdrop-blur">

        {/* Left spacer — keeps the search visually centered */}
        <div className="flex-1" />

        {/* Search — centered, wider, functional */}
        <GlobalSearch />

        {/* Right side — bell + doctor */}
        <div className="flex-1 flex items-center justify-end gap-2">
          <NotificationBell />

          <div className="mx-1 h-6 w-px bg-brand-accent" />

          <button className="group flex items-center gap-2 rounded-2xl border border-transparent py-1.5 pl-2 pr-2 transition-colors hover:border-brand-accent hover:bg-brand-surface/35">
            <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary">
              <span className="text-white text-xs font-semibold select-none">DL</span>
            </div>
            <span className="hidden text-sm font-medium text-brand-ink sm:block">
              Dr le Roux
            </span>
            <ChevronDown size={14} className="text-brand-muted group-hover:text-brand-ink" />
          </button>
        </div>
      </header>

      {/* ── Page content ────────────────────────────────────────────── */}
      <main className="ml-64 min-h-screen pt-16">
        <div className="p-8">
          {children}
        </div>
      </main>

    </div>
  )
}
