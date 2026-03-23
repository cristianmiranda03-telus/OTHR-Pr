import type { Metadata } from "next";
import "./globals.css";
import { Toaster } from "react-hot-toast";

export const metadata: Metadata = {
  title: "Trading Terminal | AI Multi-Agent System",
  description: "Autonomous AI trading system with 8 specialized agents",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      </head>
      <body className="bg-bg-base text-gray-100 antialiased">
        {children}
        <Toaster
          position="bottom-right"
          toastOptions={{
            className: "hot-toast-base",
            duration: 4500,
            style: {
              background: "#14141a",
              color: "#e8e8f0",
              border: "1px solid #2a2a38",
              borderRadius: "10px",
              fontSize: "12px",
              fontFamily: "Inter, sans-serif",
              boxShadow: "0 8px 32px rgba(0,0,0,0.6)",
            },
            success: {
              iconTheme: { primary: "#00d26a", secondary: "#14141a" },
            },
            error: {
              iconTheme: { primary: "#ff3b5c", secondary: "#14141a" },
            },
          }}
        />
      </body>
    </html>
  );
}
