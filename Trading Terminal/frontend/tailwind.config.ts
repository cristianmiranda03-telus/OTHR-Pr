import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: "class",
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        "bg-base":    "#050508",
        "bg-surface": "#0c0c10",
        "bg-raised":  "#111116",
        "bg-card":    "#14141a",
        "bg-border":  "#1e1e28",
        brand: { DEFAULT: "#b026ff", dim: "#7c1cb5", dark: "#4a1070" },
        profit: { DEFAULT: "#00d26a", dim: "#00a854", bright: "#1aff88" },
        loss:   { DEFAULT: "#ff3b5c", dim: "#cc2e49", bright: "#ff6b85" },
        neutral: { DEFAULT: "#f5a623", dim: "#cc8a1d" },
        cyan:   { DEFAULT: "#00c8ff" },
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "sans-serif"],
        mono: ["JetBrains Mono", "Fira Code", "monospace"],
      },
      boxShadow: {
        "glow-brand":  "0 0 20px rgba(176,38,255,0.35), 0 0 60px rgba(176,38,255,0.1)",
        "glow-profit": "0 0 20px rgba(0,210,106,0.35), 0 0 60px rgba(0,210,106,0.1)",
        "glow-loss":   "0 0 20px rgba(255,59,92,0.35), 0 0 60px rgba(255,59,92,0.1)",
        "glow-sm":     "0 0 10px rgba(176,38,255,0.25)",
        "card":        "0 4px 24px rgba(0,0,0,0.4)",
      },
      animation: {
        "pulse-slow":  "pulse 3s cubic-bezier(0.4,0,0.6,1) infinite",
        "blink":       "blink 1s step-end infinite",
        "slide-up":    "slideUp 0.25s ease-out",
        "fade-in":     "fadeIn 0.3s ease-out",
        "glow-pulse":  "glowPulse 2s ease-in-out infinite",
        "scan-line":   "scanLine 3s linear infinite",
      },
      keyframes: {
        blink:    { "0%,100%": { opacity:"1" }, "50%": { opacity:"0" } },
        slideUp:  { "0%": { transform:"translateY(8px)", opacity:"0" }, "100%": { transform:"translateY(0)", opacity:"1" } },
        fadeIn:   { "0%": { opacity:"0" }, "100%": { opacity:"1" } },
        glowPulse:{ "0%,100%": { boxShadow:"0 0 10px rgba(176,38,255,0.2)" }, "50%": { boxShadow:"0 0 25px rgba(176,38,255,0.6)" } },
        scanLine: { "0%": { transform:"translateY(-100%)" }, "100%": { transform:"translateY(100vh)" } },
      },
    },
  },
  plugins: [],
};

export default config;
