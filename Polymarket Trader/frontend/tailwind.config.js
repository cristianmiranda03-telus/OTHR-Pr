/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // Joker palette
        bg: {
          primary:   "#101010",
          secondary: "#1a1a1a",
          card:      "#141414",
          border:    "#2a2a2a",
        },
        neon: {
          green:  "#39FF14",
          red:    "#FF073A",
          violet: "#BC13FE",
          yellow: "#FFE000",
          blue:   "#00F5FF",
        },
      },
      fontFamily: {
        title: ["'Special Elite'", "serif"],
        mono:  ["'Roboto Mono'", "monospace"],
        sans:  ["'Roboto Mono'", "monospace"],
      },
      boxShadow: {
        "neon-green":  "0 0 10px #39FF14, 0 0 20px #39FF1440",
        "neon-red":    "0 0 10px #FF073A, 0 0 20px #FF073A40",
        "neon-violet": "0 0 10px #BC13FE, 0 0 20px #BC13FE40",
        "neon-blue":   "0 0 10px #00F5FF, 0 0 20px #00F5FF40",
        "card":        "0 0 0 1px #2a2a2a",
      },
      keyframes: {
        flicker: {
          "0%, 19%, 21%, 23%, 25%, 54%, 56%, 100%": { opacity: "1" },
          "20%, 24%, 55%":                           { opacity: "0.4" },
        },
        "pulse-slow": {
          "0%, 100%": { opacity: "1" },
          "50%":      { opacity: "0.6" },
        },
        scanline: {
          "0%":   { transform: "translateY(-100%)" },
          "100%": { transform: "translateY(100vh)" },
        },
      },
      animation: {
        flicker:      "flicker 3s linear infinite",
        "pulse-slow": "pulse-slow 2s ease-in-out infinite",
        scanline:     "scanline 8s linear infinite",
      },
    },
  },
  plugins: [],
};
