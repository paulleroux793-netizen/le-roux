import React, { createContext, useContext, useState, useCallback } from 'react'
import { router } from '@inertiajs/react'
import translations from './translations'

const LanguageContext = createContext()

const STORAGE_KEY = 'dr-leroux-language'
const SUPPORTED = ['en', 'af']

// initialServerLang is passed from inertia.jsx's setup() where page props are
// available before Inertia's page context is mounted. We can't call usePage()
// here because LanguageProvider wraps <App>, which sets up that context.
export function LanguageProvider({ initialServerLang, children }) {
  const [language, setLanguageState] = useState(() => {
    const server = SUPPORTED.includes(initialServerLang) ? initialServerLang : null
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
