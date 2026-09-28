import type { Config } from 'tailwindcss'

export default {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        'app-bg':        '#1a1b1e',
        'card':          '#25262b',
        'card-alt':      '#2c2e33',
        'app-border':    '#373a40',
        'hover-bg':      '#495057',
        'primary':       '#339af0',
        'primary-hover': '#228be6',
        'primary-active':'#1c7ed6',
        'primary-light': '#74c0fc',
        'txt':           '#c1c2c5',
        'txt-secondary': '#909296',
        'txt-muted':     '#5c5f66',
        'txt-light':     '#e9ecef',
        'txt-bright':    '#f1f3f5',
        'success':       '#51cf66',
        'success-dark':  '#2b8a3e',
        'danger':        '#ff6b6b',
        'danger-dark':   '#c92a2a',
        'warning':       '#ff922b',
        'gold':          '#ffd43b',
      },
    },
  },
  plugins: [],
} satisfies Config
