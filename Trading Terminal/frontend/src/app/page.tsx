'use client';

import { useState, useEffect } from 'react';
import { MT5Login } from '@/components/MT5Login';
import { Dashboard } from '@/components/Dashboard';

const API = 'http://localhost:8000';

export default function Home() {
  const [connected, setConnected] = useState<boolean | null>(null);

  useEffect(() => {
    fetch(`${API}/api/mt5/state`)
      .then(r => r.json())
      .then(d => setConnected(d?.connected ?? false))
      .catch(() => setConnected(false));
  }, []);

  if (connected === null) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-t-bg gap-3">
        <div className="flex items-center gap-2">
          <span className="dot dot-red animate-blink" />
          <span className="text-xs text-t-muted uppercase tracking-widest">Initializing Quant-Joker Trader...</span>
        </div>
      </div>
    );
  }

  if (!connected) return <MT5Login onSuccess={() => setConnected(true)} />;
  return <Dashboard onDisconnect={() => setConnected(false)} />;
}
