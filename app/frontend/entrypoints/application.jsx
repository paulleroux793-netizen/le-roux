import React from 'react'
import { createRoot } from 'react-dom/client'
import { createInertiaApp } from '@inertiajs/react'

import '../stylesheets/application.css'

// Test: Log when this file loads
console.log('application.jsx loaded')

createInertiaApp({
  resolve: (name) => {
    console.log('Resolving page:', name)
    const pages = import.meta.glob('../pages/**/*.jsx', { eager: true })
    console.log('Available pages:', Object.keys(pages))
    const page = pages[`../pages/${name}.jsx`]
    console.log('Resolved page:', page)
    return page
  },
  setup({ el, App, props }) {
    console.log('Setting up Inertia with props:', props)
    createRoot(el).render(<App {...props} />)
  },
  progress: {
    color: '#4B5563',
  },
})
