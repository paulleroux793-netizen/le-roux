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

// Dr Chalita le Roux brand palette — gold wordmark + warm grey (from the practice logo).
// Keep in sync with app/javascript/styles/application.css :root.
const tokens = {
  primary:          '#9A7521', // deep gold (readable with white text)
  'primary-dark':   '#7C5E1A',
  accent:           '#F4ECD8', // warm gold tint
  surface:          '#F5F2EC', // warm off-white app background
  white:            '#FFFFFF',
  ink:              '#2B2620', // warm near-black
  'ink-soft':       '#4C453B',
  muted:            '#8B8378', // warm grey (logo subtitle tone)
  border:           '#E8E1D4', // warm light border
  success:          '#10B981',
  warning:          '#F59E0B',
  danger:           '#C0392B',
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
