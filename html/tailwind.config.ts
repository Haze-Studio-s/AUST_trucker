import type { Config } from 'tailwindcss'

export default {
  content: ['./src/**/*.{ts,tsx,html}'],
  theme: {
    extend: {
      colors: {
        // Lation Modern UI (Emerald / Green Edition)
        'lation-surface':          '#1e1f24',
        'lation-surface-band':     '#18191e',
        'lation-surface-hover':    '#252630',
        'lation-surface-elevated': '#2a2b31',
        'lation-surface-deep':     '#16171b',

        'lation-line':             '#2a2b31',
        'lation-line-strong':      '#3a3b41',
        'lation-line-hover':       '#4a4b51',

        'lation-content':          '#e4e4e7',
        'lation-content-sec':      '#a1a1aa',
        'lation-content-muted':    '#71717a',
        'lation-content-heading':  '#ffffff',

        'lation-accent':           '#10b981',
        'lation-accent-soft':      '#34d399',
        'lation-accent-bright':    '#6afe87',
        'lation-accent-dim':       'rgba(16, 185, 129, 0.12)',

        'lation-btn-bg':           '#1b3b2d',
        'lation-btn-text':         '#6afe87',
        'lation-btn-border':       '#224d3a',
        'lation-btn-hover':        '#234d3b',

        'lation-err-bg':           '#35202b',
        'lation-err-text':         '#ff9f87',
        'lation-err-border':       '#4a2b3b',

        'lation-warn-bg':          '#3b2f1b',
        'lation-warn-text':        '#fcd34d',
        'lation-warn-border':      '#4d3e24',

        // Backward compatibility mappings with dark modern styling
        'app-bg':        '#16171b',
        'card':          '#1e1f24',
        'card-alt':      '#252630',
        'app-border':    '#2a2b31',
        'hover-bg':      '#2a2b31',
        'primary':       '#10b981',
        'primary-hover': '#059669',
        'primary-active':'#047857',
        'primary-light': '#6afe87',
        'txt':           '#e4e4e7',
        'txt-secondary': '#a1a1aa',
        'txt-muted':     '#71717a',
        'txt-light':     '#ffffff',
        'txt-bright':    '#ffffff',
        'success':       '#10b981',
        'success-dark':  '#059669',
        'danger':        '#ef4444',
        'danger-dark':   '#b91c1c',
        'warning':       '#f59e0b',
        'gold':          '#fbbf24',
      },
      fontFamily: {
        sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'Consolas', 'monospace'],
      },
      boxShadow: {
        'lation-panel': 'inset 0 1px 0 rgba(255, 255, 255, 0.06), 0 1px 2px rgba(0, 0, 0, 0.25), 0 12px 32px rgba(0, 0, 0, 0.45)',
        'lation-glow': '0 0 20px rgba(16, 185, 129, 0.32)',
      },
    },
  },
  plugins: [],
} satisfies Config
