'use client';

import { useState, useEffect } from 'react';

const API = 'http://localhost:8000';
type Session = { name: string; open: string; close: string; tz: string; description: string };

const SESSION_COLORS: Record<string, string> = {
  Sydney:     'text-t-muted',
  Tokyo:      'text-t-yellow',
  London:     'text-t-blue',
  'New York': 'text-t-green',
};

export function SessionsModule() {
  const [sessions, setSessions] = useState<Record<string, Session>>({});
  const [now, setNow] = useState(new Date());

  useEffect(() => {
    fetch(`${API}/api/sessions`).then(r => r.json()).then(setSessions).catch(() => setSessions({}));
    const t = setInterval(() => setNow(new Date()), 30000);
    return () => clearInterval(t);
  }, []);

  const isActive = (s: Session): boolean => {
    const [oh, om] = s.open.split(':').map(Number);
    const [ch, cm] = s.close.split(':').map(Number);
    const openMin = oh * 60 + om;
    const closeMin = ch * 60 + cm;
    const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
    if (closeMin > openMin) return nowMin >= openMin && nowMin < closeMin;
    return nowMin >= openMin || nowMin < closeMin;
  };

  const list = Object.entries(sessions);

  return (
    <div className="t-card h-full flex flex-col">
      <div className="section-header">
        <span>SESSIONS</span>
        <span className="ml-auto text-t-dim">
          {now.getUTCHours().toString().padStart(2,'0')}:{now.getUTCMinutes().toString().padStart(2,'0')} UTC
        </span>
      </div>

      <div className="flex-1 overflow-auto">
        {list.length === 0 ? (
          <div className="p-3 text-t-dim text-xs">Loading...</div>
        ) : (
          <table className="t-table">
            <thead><tr><th></th><th>SESSION</th><th>HOURS (UTC)</th><th>TZ</th></tr></thead>
            <tbody>
              {list.map(([key, s]) => {
                const active = isActive(s);
                const color = SESSION_COLORS[s.name] || 'text-t-muted';
                return (
                  <tr key={key} className={active ? 'bg-t-hover' : 'opacity-50'}>
                    <td>
                      <span className={`dot ${active ? (s.name === 'New York' ? 'dot-green' : s.name === 'London' ? 'dot-blue' : s.name === 'Tokyo' ? 'dot-yellow' : 'dot-dim') : 'dot-dim'}`} />
                    </td>
                    <td className={`font-semibold ${color}`}>{s.name}</td>
                    <td className="text-t-text">{s.open} – {s.close}</td>
                    <td className="text-t-dim">{s.tz}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
