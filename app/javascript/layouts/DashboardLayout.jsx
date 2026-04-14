import React from 'react'
import { Link, usePage } from '@inertiajs/react'
import {
  LayoutDashboard, Calendar, Users, MessageSquare, BarChart2,
  Settings, Bell, ChevronDown, HelpCircle,
} from 'lucide-react'
import { cn } from '../lib/utils'
import GlobalSearch from '../components/GlobalSearch'

const NAV_ITEMS = [
  { name: 'Dashboard',     href: '/dashboard',     icon: LayoutDashboard },
  { name: 'Appointments',  href: '/appointments',  icon: Calendar },
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
    <div className="min-h-screen bg-brand-cream">

      {/* ── Sidebar ─────────────────────────────────────────────────── */}
      <aside className="fixed inset-y-0 left-0 w-64 bg-brand-brown flex flex-col z-30">

        {/* Practice identity */}
        <div className="px-5 py-5 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-brand-gold flex items-center justify-center flex-shrink-0">
              <span className="text-brand-brown font-bold text-sm select-none">DL</span>
            </div>
            <div className="min-w-0">
              <h1 className="text-white font-semibold text-sm leading-tight truncate">
                Dr Chalita le Roux
              </h1>
              <p className="text-brand-gold text-xs mt-0.5 tracking-wide">AI Receptionist</p>
            </div>
          </div>
        </div>

        {/* Main navigation */}
        <nav className="flex-1 px-3 py-5 space-y-0.5 overflow-y-auto">
          <p className="text-white/30 text-xs font-semibold uppercase tracking-widest px-3 mb-3 select-none">
            Menu
          </p>
          {NAV_ITEMS.map(({ name, href, icon: Icon }) => {
            const active = isActive(href)
            return (
              <Link
                key={name}
                href={href}
                className={cn(
                  'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all',
                  active
                    ? 'bg-white/10 text-white'
                    : 'text-white/55 hover:bg-white/5 hover:text-white/90'
                )}
              >
                <Icon
                  size={16}
                  className={cn('flex-shrink-0', active ? 'text-brand-gold' : 'text-white/40')}
                />
                <span className="truncate">{name}</span>
                {active && (
                  <span className="ml-auto w-1.5 h-1.5 rounded-full bg-brand-gold flex-shrink-0" />
                )}
              </Link>
            )
          })}
        </nav>

        {/* Bottom — Settings / Support / Status */}
        <div className="px-3 pb-4 border-t border-white/10 pt-3 space-y-0.5">
          <Link
            href="/settings"
            className={cn(
              'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all',
              isActive('/settings')
                ? 'bg-white/10 text-white'
                : 'text-white/55 hover:bg-white/5 hover:text-white/90'
            )}
          >
            <Settings
              size={16}
              className={cn(
                'flex-shrink-0',
                isActive('/settings') ? 'text-brand-gold' : 'text-white/40'
              )}
            />
            Settings
            {isActive('/settings') && (
              <span className="ml-auto w-1.5 h-1.5 rounded-full bg-brand-gold flex-shrink-0" />
            )}
          </Link>

          <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-white/55 hover:bg-white/5 hover:text-white/90 transition-all">
            <HelpCircle size={16} className="flex-shrink-0 text-white/40" />
            Support
          </button>

          <div className="px-3 pt-2">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-green-400 flex-shrink-0 animate-pulse" />
              <span className="text-white/35 text-xs select-none">System Online</span>
            </div>
          </div>
        </div>
      </aside>

      {/* ── Top navbar ──────────────────────────────────────────────── */}
      <header className="fixed top-0 left-64 right-0 h-16 bg-white border-b border-gray-100 flex items-center px-6 gap-4 z-20">

        {/* Left spacer — keeps the search visually centered */}
        <div className="flex-1" />

        {/* Search — centered, wider, functional */}
        <GlobalSearch />

        {/* Right side — bell + doctor */}
        <div className="flex-1 flex items-center justify-end gap-2">
          <button
            className="relative p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
            aria-label="Notifications"
          >
            <Bell size={18} />
            {/* Notification dot — wire to real data in Phase 10+ */}
            <span className="absolute top-2 right-2 w-1.5 h-1.5 bg-brand-taupe rounded-full" />
          </button>

          <div className="w-px h-6 bg-gray-200 mx-1" />

          <button className="flex items-center gap-2 pl-2 pr-2 py-1.5 rounded-lg hover:bg-gray-50 transition-colors group">
            <div className="w-8 h-8 rounded-full bg-brand-brown flex items-center justify-center flex-shrink-0">
              <span className="text-white text-xs font-semibold select-none">DL</span>
            </div>
            <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900 hidden sm:block">
              Dr le Roux
            </span>
            <ChevronDown size={14} className="text-gray-400 group-hover:text-gray-600" />
          </button>
        </div>
      </header>

      {/* ── Page content ────────────────────────────────────────────── */}
      <main className="ml-64 pt-16 min-h-screen">
        <div className="p-8">
          {children}
        </div>
      </main>

    </div>
  )
}
