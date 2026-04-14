/** @type {import('tailwindcss').Config} */

// ── Brand design tokens — single source of truth ──────────────────
// Phase 9.14. Every colour used in the app flows from this block.
// Update a hex here and the whole dashboard (including FullCalendar,
// via the CSS variables mirrored in app/javascript/styles/application.css)
// re-themes in one step.
//
// Palette direction: clean dental-clinic SaaS — white surfaces, soft
// cool grey borders, a single teal accent used sparingly for CTAs,
// active nav, and focus rings. Status hues (success / warning / danger)
// are reserved strictly for status communication.
//
// Token roles:
//   primary        — CTAs, active nav, links, focus rings
//   primary-dark   — hover state for primary
//   accent         — subtle tinted background for selected rows / pills
//   surface        — app background (near-white, faint cool tint)
//   white          — cards, modals, table rows
//   ink            — primary high-contrast text
//   ink-soft       — secondary headings
//   muted          — helper text, placeholder, borders on inputs
//   border         — dividers, card borders
//   success        — confirmed / paid
//   warning        — pending / reminder due
//   danger         — cancelled / failed
//
// Legacy keys (secondary, secondary-dark, brown, taupe, gold, cream)
// are kept as aliases pointing at the new palette so the ~hundreds of
// existing `bg-brand-*` class references keep compiling without a
// mass rename. Page-level refactors in Phase 9.14 will gradually
// retire them in favour of the role-based keys above.

const tokens = {
  primary:          '#0E9F9F', // teal
  'primary-dark':   '#0B8080',
  accent:           '#E6F7F7', // primary-light tint
  surface:          '#EEF0F3', // app background (visibly grey vs white cards/navbar)
  white:            '#FFFFFF',
  ink:              '#0F172A',
  'ink-soft':       '#334155',
  muted:            '#64748B',
  border:           '#E2E8F0',
  success:          '#10B981',
  warning:          '#F59E0B',
  danger:           '#EF4444',
}

export default {
  content: [
    './app/views/**/*.{erb,jsx}',
    './app/javascript/**/*.{js,jsx}',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          ...tokens,
          // Legacy aliases — map pre-9.14 class names onto the new
          // tokens so existing markup keeps rendering.  These will be
          // retired once every page has been refactored.
          secondary:        tokens.primary,
          'secondary-dark': tokens['primary-dark'],
          brown:            tokens.ink,
          'brown-mid':      tokens['ink-soft'],
          taupe:            tokens.primary,
          'taupe-mid':      tokens['primary-dark'],
          gold:             tokens.primary,
          'gold-light':     tokens.accent,
          cream:            tokens.surface,
        },
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
