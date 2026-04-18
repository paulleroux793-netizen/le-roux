import React, { createContext, useContext, useState, useCallback } from 'react'
import { usePage, router } from '@inertiajs/react'
import translations from './translations'

const LanguageContext = createContext()

const STORAGE_KEY = 'dr-leroux-language'
const SUPPORTED = ['en', 'af']

export function LanguageProvider({ children }) {
  const { props } = usePage()

  const [language, setLanguageState] = useState(() => {
    // Server-provided preference (from session) wins; then localStorage; then 'en'
    const server = SUPPORTED.includes(props.ui_language) ? props.ui_language : null
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return server || (SUPPORTED.includes(stored) ? stored : 'en')
    } catch {
      return server || 'en'
    }
  })

  const setLanguage = useCallback((lang) => {
    if (!SUPPORTED.includes(lang)) return
    setLanguageState(lang)
    try {
      localStorage.setItem(STORAGE_KEY, lang)
    } catch {
      // localStorage unavailable — state still updates in memory
    }
    // Persist to session so server-rendered pages start in the right language
    router.post('/settings/language', { language: lang }, {
      preserveState: true,
      preserveScroll: true,
      only: [],
    })
  }, [])

  const t = useCallback((key) => {
    return translations[language]?.[key] || translations.en[key] || key
  }, [language])

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  )
}

export function useLanguage() {
  const ctx = useContext(LanguageContext)
  if (!ctx) throw new Error('useLanguage must be used within a LanguageProvider')
  return ctx
}
