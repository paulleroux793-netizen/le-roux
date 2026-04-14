/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './app/views/**/*.{erb,jsx}',
    './app/javascript/**/*.{js,jsx}',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          primary:        '#3164DE',
          'primary-dark': '#274FB5',
          secondary:      '#769BF5',
          'secondary-dark': '#5D83E8',
          accent:         '#B1C5F6',
          surface:        '#D6E0F8',
          white:          '#FFFFFF',
          ink:            '#393C4D',
          muted:          '#8592AD',
          success:        '#19A14E',
          danger:         '#EF6161',
          // Backwards-compatible aliases for pre-theme-rollout classes.
          brown:          '#393C4D',
          'brown-mid':    '#2F3341',
          taupe:          '#3164DE',
          'taupe-mid':    '#274FB5',
          gold:           '#769BF5',
          'gold-light':   '#B1C5F6',
          cream:          '#D6E0F8',
        },
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
