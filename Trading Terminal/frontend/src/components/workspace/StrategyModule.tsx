'use client';

import { useState, useEffect } from 'react';
import { Play } from 'lucide-react';

const API = 'http://localhost:8000';

export function StrategyModule() {
  const [strategies, setStrategies] = useState<{ strategies: string[]; params: Record<string, string[]> }>({ strategies: [], params: {} });
  const [selected, setSelected] = useState('rsi');
  const [params, setParams] = useState<Record<string, number | boolean>>({});
  const [result, setResult] = useState<{ error: string | null; stats: Record<string, number> | null }>({ error: null, stats: null });
  const [running, setRunning] = useState(false);
  const [symbol, setSymbol] = useState('EURUSD');
  const [timeframe, setTimeframe] = useState('H1');

  useEffect(() => {
    fetch(`${API}/api/strategies/list`).then(r => r.json()).then(d => {
      setStrategies(d);
      if (d.params?.rsi) setParams({ rsi_period: 14, rsi_low: 30, rsi_high: 70, ma_period: 50, use_ma_filter: true });
    }).catch(() => setStrategies({ strategies: ['rsi', 'sma_cross'], params: {} }));
  }, []);

  const runBacktest = async () => {
    setRunning(true); setResult({ error: null, stats: null });
    try {
      const rr = await fetch(`${API}/api/market/rates?symbol=${encodeURIComponent(symbol)}&timeframe=${timeframe}&count=500`);
      const rd = await rr.json();
      if (!rd.data?.length) { setResult({ error: 'No market data. Connect MT5.', stats: null }); return; }
      const res = await fetch(`${API}/api/strategies/backtest`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ strategy_name: selected, data: rd.data, strategy_params: params, cash: 10000 }),
      });
      const data = await res.json();
      setResult({ error: data.error || null, stats: data.stats || null });
    } catch { setResult({ error: 'Request failed.', stats: null }); }
    finally { setRunning(false); }
  };

  const paramList = strategies.params?.[selected] || [];

  return (
    <div className="t-card h-full flex flex-col">
      <div className="section-header"><span>QUICK BACKTEST</span></div>
      <div className="flex-1 p-3 space-y-3 overflow-auto">
        <div className="flex flex-wrap gap-3 items-end">
          {[
            { label: 'Strategy', el: <select value={selected} onChange={e => { setSelected(e.target.value); setParams({}); }} className="t-select text-xs">{(strategies.strategies || []).map(s => <option key={s}>{s}</option>)}</select> },
            { label: 'Symbol', el: <input value={symbol} onChange={e => setSymbol(e.target.value)} className="t-input" style={{ width: 80 }} /> },
            { label: 'Timeframe', el: <select value={timeframe} onChange={e => setTimeframe(e.target.value)} className="t-select text-xs">{['M5','M15','M30','H1','H4','D1'].map(tf => <option key={tf}>{tf}</option>)}</select> },
          ].map(f => (
            <div key={f.label}>
              <div className="text-2xs text-t-muted uppercase mb-1">{f.label}</div>
              {f.el}
            </div>
          ))}
          {paramList.map(p => (
            <div key={p}>
              <div className="text-2xs text-t-muted uppercase mb-1">{p}</div>
              {p === 'use_ma_filter' ? (
                <select value={params[p] ? 'true' : 'false'} onChange={e => setParams(prev => ({...prev, [p]: e.target.value === 'true'}))} className="t-select text-xs" style={{ width: 56 }}>
                  <option value="true">Yes</option><option value="false">No</option>
                </select>
              ) : (
                <input type="number" value={params[p] ?? ''} onChange={e => setParams(prev => ({...prev, [p]: Number(e.target.value)}))} className="t-input text-center" style={{ width: 52 }} />
              )}
            </div>
          ))}
          <button onClick={runBacktest} disabled={running} className="btn btn-green text-xs self-end py-1.5">
            <Play className="w-3 h-3" />{running ? 'Running...' : 'Run Backtest'}
          </button>
        </div>

        {result.error && <div className="text-xs text-t-red bg-t-redBg border border-t-red/30 rounded p-2">{result.error}</div>}

        {result.stats && (
          <div className="grid grid-cols-4 gap-2">
            {[
              { label: 'Final Value', v: `$${result.stats.final_value?.toFixed(2)}`, c: 'text-t-text' },
              { label: 'Return %', v: `${result.stats.total_return_pct > 0 ? '+' : ''}${result.stats.total_return_pct?.toFixed(2)}%`, c: result.stats.total_return_pct >= 0 ? 'text-t-green' : 'text-t-red' },
              { label: 'Sharpe', v: result.stats.sharpe_ratio?.toFixed(3), c: result.stats.sharpe_ratio >= 1 ? 'text-t-green' : 'text-t-yellow' },
              { label: 'Max DD%', v: `${result.stats.max_drawdown_pct?.toFixed(2)}%`, c: result.stats.max_drawdown_pct <= 10 ? 'text-t-green' : 'text-t-red' },
              { label: 'Trades', v: result.stats.total_trades, c: 'text-t-text' },
              { label: 'Won', v: result.stats.won_trades, c: 'text-t-green' },
              { label: 'Lost', v: result.stats.lost_trades, c: 'text-t-red' },
              { label: 'Win Rate', v: `${result.stats.total_trades > 0 ? (result.stats.won_trades / result.stats.total_trades * 100).toFixed(1) : 0}%`, c: 'text-t-text' },
            ].map(m => (
              <div key={m.label} className="stat-box">
                <div className="label">{m.label}</div>
                <div className={`value text-sm ${m.c}`}>{m.v}</div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
