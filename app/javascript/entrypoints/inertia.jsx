import React from 'react'
import { createRoot } from 'react-dom/client'
import { createInertiaApp } from '@inertiajs/react'
import { Toaster } from 'sonner'
import { LanguageProvider } from '../lib/LanguageContext'

import '../styles/application.css'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('../pages/**/*.jsx', { eager: true })
    return pages[`../pages/${name}.jsx`]
  },
  setup({ el, App, props }) {
    createRoot(el).render(
      <LanguageProvider initialServerLang={props.props?.ui_language}>
        <App {...props} />
        <Toaster position="top-right" richColors closeButton />
      </LanguageProvider>
    )
  },
  progress: {
    color: '#4B5563',
  },
})
