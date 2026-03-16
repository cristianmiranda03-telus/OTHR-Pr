'use client';

import { useState } from 'react';
import { Activity } from 'lucide-react';

const API = 'http://localhost:8000';

export function MT5Login({ onSuccess }: { onSuccess: () => void }) {
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [server, setServer] = useState('');
  const [path, setPath] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(''); setLoading(true);
    try {
      const res = await fetch(`${API}/api/mt5/connect`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ login: parseInt(login, 10) || 0, password, server: server.trim() || 'Unknown', path: path.trim() || null }),
      });
      const data = await res.json().catch(() => ({}));
      if (data.success) { onSuccess(); }
      else { setError(data.message || 'Connection failed. Check MT5 terminal is open.'); }
    } catch {
      setError('Backend not reachable on port 8000. Run: python run_quasar.py');
    } finally { setLoading(false); }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-t-bg p-4">
      <div className="w-full max-w-sm">

        {/* Header */}
        <div className="flex items-center gap-3 mb-6">
          <div className="p-2 bg-t-surface border border-t-border rounded">
            <Activity className="w-5 h-5 text-t-red" />
          </div>
          <div>
            <div className="text-sm font-semibold text-t-text tracking-wide">QUANT-JOKER TRADER</div>
            <div className="text-2xs text-t-muted uppercase tracking-widest">AI Algorithmic · MT5</div>
          </div>
        </div>

        <div className="t-card p-5">
          <div className="text-2xs text-t-muted uppercase tracking-widest mb-4 pb-2 border-b border-t-border">
            Connect to Broker
          </div>

          <form onSubmit={submit} className="space-y-3">
            {[
              { label: 'Login (Account)', id: 'login', value: login, set: setLogin, type: 'text', placeholder: '12345678', required: true },
              { label: 'Password', id: 'pw', value: password, set: setPassword, type: 'password', placeholder: '••••••••', required: true },
              { label: 'Server', id: 'srv', value: server, set: setServer, type: 'text', placeholder: 'Broker-Server', required: true },
              { label: 'MT5 Path (optional)', id: 'path', value: path, set: setPath, type: 'text', placeholder: 'C:\\...\\terminal64.exe', required: false },
            ].map(f => (
              <div key={f.id}>
                <label className="block text-2xs text-t-muted uppercase tracking-wider mb-1">{f.label}</label>
                <input
                  type={f.type}
                  value={f.value}
                  onChange={e => f.set(e.target.value)}
                  placeholder={f.placeholder}
                  required={f.required}
                  className="t-input"
                />
              </div>
            ))}

            {error && (
              <div className="text-2xs text-t-red bg-t-redBg border border-t-red/30 rounded p-2">
                {error}
              </div>
            )}

            <button type="submit" disabled={loading} className="btn btn-red w-full justify-center py-2 text-xs mt-2">
              {loading ? 'CONNECTING...' : 'CONNECT TO MT5'}
            </button>

            <button type="button" onClick={() => onSuccess()}
              className="btn btn-ghost w-full justify-center py-1.5 text-2xs border-t-border">
              DEMO MODE (no MT5 required)
            </button>
          </form>
        </div>

        <p className="text-center text-2xs text-t-dim mt-3">
          Backend required on port 8000 · MT5 terminal must be open
        </p>
      </div>
    </div>
  );
}
