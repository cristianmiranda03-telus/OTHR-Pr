/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{js,ts,jsx,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        t: {
          bg:      '#080808',
          surface: '#0f0f0f',
          panel:   '#141414',
          card:    '#1a1a1a',
          hover:   '#1f1f1f',
          border:  '#252525',
          borderB: '#333333',
          red:     '#e03131',
          redDim:  '#c92a2a',
          redBg:   '#1a0808',
          redMid:  '#3d1010',
          green:   '#2f9e44',
          greenDim:'#276f33',
          greenBg: '#081a0d',
          blue:    '#228be6',
          blueBg:  '#0a1829',
          orange:  '#f76707',
          yellow:  '#f59f00',
          text:    '#f0f0f0',
          muted:   '#868e96',
          dim:     '#4a4a4a',
          white:   '#ffffff',
        },
      },
      fontFamily: {
        mono: ['"JetBrains Mono"', 'Consolas', 'Courier New', 'monospace'],
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      fontSize: {
        '2xs': ['0.625rem', { lineHeight: '0.875rem' }],
        xs:    ['0.7rem',   { lineHeight: '1rem' }],
        sm:    ['0.75rem',  { lineHeight: '1.1rem' }],
      },
      animation: {
        'blink': 'blink 1s step-end infinite',
        'slide-down': 'slideDown 0.2s ease-out',
        'fade-in': 'fadeIn 0.2s ease-out',
      },
      keyframes: {
        blink:     { '0%,100%': { opacity: '1' }, '50%': { opacity: '0' } },
        slideDown: { from: { opacity: '0', transform: 'translateY(-4px)' }, to: { opacity: '1', transform: 'translateY(0)' } },
        fadeIn:    { from: { opacity: '0' }, to: { opacity: '1' } },
      },
    },
  },
  plugins: [],
};
