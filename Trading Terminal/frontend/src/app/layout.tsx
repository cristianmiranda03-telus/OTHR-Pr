import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Quant-Joker Trader',
  description: 'AI-Powered Algorithmic Trading Terminal',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="bg-t-bg text-t-text antialiased min-h-screen font-mono">
        {children}
      </body>
    </html>
  );
}
