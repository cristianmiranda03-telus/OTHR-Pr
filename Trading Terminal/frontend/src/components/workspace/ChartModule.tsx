'use client';

import { useState, useEffect } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { RefreshCw } from 'lucide-react';

const API = 'http://localhost:8000';

export function ChartModule({ compact = false }: { compact?: boolean }) {
  const [symbol, setSymbol] = useState('EURUSD');
  const [timeframe, setTimeframe] = useState('H1');
  const [symbols, setSymbols] = useState<string[]>([]);
  const [data, setData] = useState<{ time: string; close: number; open: number; high: number; low: number }[]>([]);
  const [loading, setLoading] = useState(false);
  const [aiSignal, setAiSignal] = useState<{ bias?: string; impact?: string } | null>(null);

  useEffect(() => {
    fetch(`${API}/api/market/symbols`).then(r => r.json())
      .then(d => setSymbols(d.symbols || []))
      .catch(() => setSymbols(['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'USOIL']));
  }, []);

  const load = () => {
    setLoading(true);
    fetch(`${API}/api/market/rates?symbol=${encodeURIComponent(symbol)}&timeframe=${timeframe}&count=${compact ? 60 : 120}`)
      .then(r => r.json())
      .then(d => {
        if (d.data?.length) {
          setData(d.data.map((c: { datetime: string; close: number; open: number; high: number; low: number }) => ({
            time: c.datetime?.slice(11, 16) ?? '',
            close: c.close, open: c.open, high: c.high, low: c.low,
          })));
        } else setData([]);
      }).catch(() => setData([])).finally(() => setLoading(false));

    fetch(`${API}/api/agents/news/latest`).then(r => r.json()).then(d => {
      const pairs = d?.analysis?.pair_analysis;
      const key = symbol.replace('/', '');
      if (pairs?.[key]) setAiSignal({ bias: pairs[key].bias, impact: pairs[key].impact });
    }).catch(() => {});
  };

  useEffect(() => { load(); }, [symbol, timeframe]);

  const last = data[data.length - 1]?.close;
  const first = data[0]?.close;
  const chg = last && first ? ((last - first) / first * 100) : null;
  const up = chg !== null && chg >= 0;
  const color = up ? 'var(--t-green)' : 'var(--t-red)';

  return (
    <div className="t-card h-full flex flex-col">
      <div className="section-header">
        <span className="text-t-text">{symbol}</span>
        {last && (
          <span className="text-t-text font-semibold ml-1">{last.toFixed(symbol.includes('JPY') ? 3 : 5)}</span>
        )}
        {chg !== null && (
          <span className={up ? 'text-t-green' : 'text-t-red'}>
            {up ? '▲' : '▼'}{Math.abs(chg).toFixed(3)}%
          </span>
        )}
        {aiSignal && (
          <span className={`badge ml-1 ${aiSignal.bias === 'bullish' ? 'badge-green' : aiSignal.bias === 'bearish' ? 'badge-red' : 'badge-dim'}`}>
            {aiSignal.bias}
          </span>
        )}
        <div className="ml-auto flex items-center gap-1">
          <select value={symbol} onChange={e => setSymbol(e.target.value)} className="t-select text-2xs py-0.5">
            {symbols.slice(0, 50).map(s => <option key={s} value={s}>{s}</option>)}
          </select>
          <select value={timeframe} onChange={e => setTimeframe(e.target.value)} className="t-select text-2xs py-0.5">
            {['M1','M5','M15','M30','H1','H4','D1'].map(tf => <option key={tf} value={tf}>{tf}</option>)}
          </select>
          <button onClick={load} className="btn btn-ghost px-1.5 py-0.5">
            <RefreshCw className={`w-2.5 h-2.5 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="flex-1 min-h-0 p-1">
        {loading ? (
          <div className="h-full flex items-center justify-center text-t-dim text-xs">Loading...</div>
        ) : data.length === 0 ? (
          <div className="h-full flex items-center justify-center text-t-dim text-xs">No data · Connect MT5</div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 4, right: 2, left: 2, bottom: 4 }}>
              <defs>
                <linearGradient id="cg" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={color} stopOpacity={0.2} />
                  <stop offset="100%" stopColor={color} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="1 6" stroke="rgba(37,37,37,0.8)" />
              <XAxis dataKey="time" stroke="#4a4a4a" fontSize={9} tick={{ fill: '#4a4a4a' }} tickLine={false}
                interval={Math.floor(data.length / 6)} />
              <YAxis stroke="#4a4a4a" fontSize={9} tick={{ fill: '#4a4a4a' }} tickLine={false}
                domain={['auto', 'auto']} tickFormatter={v => v.toFixed(4)} width={52} />
              <Tooltip
                contentStyle={{ background: '#1a1a1a', border: '1px solid #333', borderRadius: 2, fontSize: 10 }}
                labelStyle={{ color: '#868e96' }}
                formatter={(v: number) => [v.toFixed(5), 'Price']}
              />
              <Area type="monotone" dataKey="close" stroke={color} fill="url(#cg)" strokeWidth={1.5} dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
