import React, { useEffect, useRef, useState } from 'react'
import { Link, router, usePage } from '@inertiajs/react'
import {
  LayoutDashboard, Calendar, Users, MessageSquare, BarChart2,
  BellRing, Settings, ChevronDown, HelpCircle, Globe,
  User, LogOut, KeyRound,
} from 'lucide-react'
import { cn } from '../lib/utils'
import GlobalSearch from '../components/GlobalSearch'
import NotificationBell from '../components/NotificationBell'
import { useLanguage } from '../lib/LanguageContext'

const NAV_ITEMS = [
  { key: 'nav_dashboard',     href: '/dashboard',     icon: LayoutDashboard },
  { key: 'nav_appointments',  href: '/appointments',  icon: Calendar },
  { key: 'nav_reminders',     href: '/reminders',     icon: BellRing },
  { key: 'nav_patients',      href: '/patients',      icon: Users },
  { key: 'nav_conversations', href: '/conversations', icon: MessageSquare },
  { key: 'nav_analytics',     href: '/analytics',     icon: BarChart2 },
]

export default function DashboardLayout({ children }) {
  const { url } = usePage()
  const { t, language, setLanguage } = useLanguage()
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const dropdownRef = useRef(null)

  useEffect(() => {
    const handler = (e) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
        setDropdownOpen(false)
      }
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const isActive = (href) =>
    href === '/dashboard'
      ? url === '/' || url === '/dashboard'
      : url.startsWith(href)

  return (
    <div className="min-h-screen bg-brand-surface text-brand-ink">

      {/* ── Sidebar ─────────────────────────────────────────────────── */}
      <aside className="fixed inset-y-0 left-0 z-30 flex w-64 flex-col border-r border-brand-border bg-white">

        {/* Practice identity — h-16 matches the top navbar height exactly */}
        <div className="flex h-16 flex-shrink-0 items-center gap-3 border-b border-brand-border px-5">
            <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-xl bg-brand-primary">
              <span className="select-none text-sm font-bold text-white">DL</span>
            </div>
            <div className="min-w-0">
              <h1 className="truncate text-sm font-semibold leading-tight text-brand-ink">
                Dr Chalita le Roux
              </h1>
              <p className="mt-0.5 text-xs tracking-wide text-brand-muted">{t('nav_subtitle')}</p>
            </div>
        </div>

        {/* Main navigation */}
        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-5">
          <p className="mb-3 px-3 text-xs font-semibold uppercase tracking-[0.22em] text-brand-muted select-none">
            {t('nav_menu')}
          </p>
          {NAV_ITEMS.map(({ key, href, icon: Icon }) => {
            const active = isActive(href)
            return (
              <Link
                key={key}
                href={href}
                className={cn(
                  'flex items-center gap-3 rounded-xl px-3.5 py-3 text-sm font-medium transition-all',
                  active
                    ? 'bg-brand-primary text-white'
                    : 'text-brand-muted hover:bg-brand-surface hover:text-brand-ink'
                )}
              >
                <Icon
                  size={16}
                  className={cn('flex-shrink-0', active ? 'text-white' : 'text-brand-muted')}
                />
                <span className="truncate">{t(key)}</span>
                {active && (
                  <span className="ml-auto h-1.5 w-1.5 flex-shrink-0 rounded-full bg-white" />
                )}
              </Link>
            )
          })}
        </nav>

        {/* Bottom — Settings / Support */}
        <div className="space-y-1 border-t border-brand-border px-3 pb-4 pt-3">
          <Link
            href="/settings"
            className={cn(
              'flex items-center gap-3 rounded-xl px-3.5 py-3 text-sm font-medium transition-all',
              isActive('/settings')
                ? 'bg-brand-primary text-white'
                : 'text-brand-muted hover:bg-brand-surface hover:text-brand-ink'
            )}
          >
            <Settings
              size={16}
              className={cn(
                'flex-shrink-0',
                isActive('/settings') ? 'text-white' : 'text-brand-muted'
              )}
            />
            {t('nav_settings')}
            {isActive('/settings') && (
              <span className="ml-auto h-1.5 w-1.5 flex-shrink-0 rounded-full bg-white" />
            )}
          </Link>

          <button className="w-full rounded-xl px-3.5 py-3 text-left text-sm font-medium text-brand-muted transition-all hover:bg-brand-surface hover:text-brand-ink">
            <span className="flex items-center gap-3">
              <HelpCircle size={16} className="flex-shrink-0 text-brand-muted" />
              {t('nav_support')}
            </span>
          </button>
        </div>
      </aside>

      {/* ── Top navbar ──────────────────────────────────────────────── */}
      <header className="fixed inset-x-0 top-0 z-20 flex h-16 items-center gap-4 border-b border-brand-border bg-white pl-64 pr-6">

        {/* Left spacer — keeps the search visually centered */}
        <div className="flex-1" />

        {/* Search — centered, wider, functional */}
        <GlobalSearch />

        {/* Right side — language toggle + bell + doctor */}
        <div className="flex-1 flex items-center justify-end gap-2">
          {/* Quick language toggle — EN / AF */}
          <div className="flex items-center gap-1 rounded-lg border border-brand-border bg-brand-surface px-1 py-0.5">
            <Globe size={13} className="text-brand-muted ml-1" />
            {['en', 'af'].map((lang) => (
              <button
                key={lang}
                onClick={() => setLanguage(lang)}
                className={cn(
                  'rounded px-2 py-0.5 text-xs font-semibold transition-colors',
                  language === lang
                    ? 'bg-white text-brand-ink shadow-sm'
                    : 'text-brand-muted hover:text-brand-ink'
                )}
              >
                {lang.toUpperCase()}
              </button>
            ))}
          </div>

          <NotificationBell />

          <div className="mx-1 h-6 w-px bg-brand-border" />

          {/* Doctor dropdown */}
          <div className="relative" ref={dropdownRef}>
            <button
              onClick={() => setDropdownOpen((o) => !o)}
              className="group flex items-center gap-2 rounded-xl border border-transparent py-1.5 pl-2 pr-2 transition-colors hover:border-brand-border hover:bg-brand-surface"
            >
              <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-brand-primary">
                <span className="text-white text-xs font-semibold select-none">DL</span>
              </div>
              <span className="hidden whitespace-nowrap text-sm font-medium text-brand-ink sm:block">
                Dr le Roux
              </span>
              <ChevronDown
                size={14}
                className={cn('text-brand-muted transition-transform group-hover:text-brand-ink', dropdownOpen && 'rotate-180')}
              />
            </button>

            {dropdownOpen && (
              <div className="absolute right-0 top-full z-50 mt-1.5 w-52 rounded-xl border border-brand-border bg-white py-1.5 shadow-[0_24px_60px_-16px_rgba(57,60,77,0.25)]">
                <div className="border-b border-brand-border px-4 py-2.5">
                  <p className="text-xs font-semibold text-brand-ink">Dr Chalita le Roux</p>
                  <p className="mt-0.5 text-[11px] text-brand-muted">General Practitioner</p>
                </div>
                <div className="py-1">
                  <DropdownItem
                    icon={User}
                    label="My Profile"
                    onClick={() => { setDropdownOpen(false); router.visit('/settings') }}
                  />
                  <DropdownItem
                    icon={KeyRound}
                    label="Change Password"
                    onClick={() => { setDropdownOpen(false); router.visit('/settings') }}
                  />
                </div>
                <div className="border-t border-brand-border py-1">
                  <DropdownItem
                    icon={LogOut}
                    label="Sign out"
                    danger
                    onClick={() => {
                      setDropdownOpen(false)
                      router.delete('/users/sign_out', { onError: () => router.visit('/') })
                    }}
                  />
                </div>
              </div>
            )}
          </div>
        </div>
      </header>

      {/* ── Page content ─────────────────────────────────────────── */}
      <main className="ml-64 min-h-screen pt-16">
        <div className="p-8">
          {children}
        </div>
      </main>

    </div>
  )
}

function DropdownItem({ icon: Icon, label, onClick, danger = false }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'flex w-full items-center gap-3 px-4 py-2 text-sm transition-colors',
        danger
          ? 'text-brand-danger hover:bg-brand-danger/5'
          : 'text-brand-ink hover:bg-brand-surface'
      )}
    >
      <Icon size={15} className={danger ? 'text-brand-danger' : 'text-brand-muted'} />
      {label}
    </button>
  )
}
