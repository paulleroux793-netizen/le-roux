import React from 'react'
import { createRoot } from 'react-dom/client'
import { createInertiaApp } from '@inertiajs/react'

import './stylesheets/application.css'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('./pages/**/*.jsx', { eager: true })
    return pages[`./pages/${name}.jsx`]
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
  progress: {
    color: '#4B5563',
  },
})
