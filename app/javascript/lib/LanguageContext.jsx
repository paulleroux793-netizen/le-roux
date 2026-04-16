import React, { createContext, useContext, useState, useCallback } from 'react'
import translations from './translations'

const LanguageContext = createContext()

const STORAGE_KEY = 'dr-leroux-language'

export function LanguageProvider({ children }) {
  const [language, setLanguageState] = useState(() => {
    try {
      return localStorage.getItem(STORAGE_KEY) || 'en'
    } catch {
      return 'en'
    }
  })

  const setLanguage = useCallback((lang) => {
    setLanguageState(lang)
    try {
      localStorage.setItem(STORAGE_KEY, lang)
    } catch {
      // localStorage unavailable — state still updates in memory
    }
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
