'use client';

import { useState, useEffect } from 'react';
import { TrendingUp, TrendingDown, X, RefreshCw, Zap, Plus } from 'lucide-react';

const API = 'http://localhost:8000';

type Position = {
  ticket: number; symbol: string; type: 'buy' | 'sell';
  volume: number; open_price: number; current_price: number;
  sl: number; tp: number; profit: number; open_time: string; pnl_pct: number;
};
type Signal = { symbol: string; direction: string; confidence: number; sl_pips: number; tp_pips: number; volume: number; };
type Metrics = Record<string, number>;

export function TradeManagerModule({ compact = false }: { compact?: boolean }) {
  const [positions, setPositions] = useState<Position[]>([]);
  const [signals, setSignals] = useState<Signal[]>([]);
  const [metrics, setMetrics] = useState<Metrics>({});
  const [history, setHistory] = useState<{ ticket: number; symbol: string; type: string; profit: number; time: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [closing, setClosing] = useState<number | null>(null);
  const [showManual, setShowManual] = useState(false);
  const [manual, setManual] = useState({ symbol: 'EURUSD', direction: 'buy', volume: 0.01, sl_pips: 25, tp_pips: 50 });

  const fetchAll = () => {
    Promise.all([
      fetch(`${API}/api/agents/trades/open`).then(r => r.json()),
      fetch(`${API}/api/agents/performance`).then(r => r.json()),
    ]).then(([t, p]) => {
      setPositions(t.positions || []);
      setSignals(t.pending_signals || []);
      setMetrics(p.metrics || {});
    }).catch(() => {}).finally(() => setLoading(false));
  };

  useEffect(() => { fetchAll(); const t = setInterval(fetchAll, 4000); return () => clearInterval(t); }, []);

  const close = async (ticket: number) => {
    setClosing(ticket);
    try {
      await fetch(`${API}/api/agents/trades/close`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ticket, comment: 'Manual' }),
      });
      fetchAll();
    } finally { setClosing(null); }
  };

  const execute = async () => {
    await fetch(`${API}/api/agents/trades/execute`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(manual),
    });
    setShowManual(false); fetchAll();
  };

  const totalPnL = positions.reduce((s, p) => s + p.profit, 0);

  if (compact) {
    return (
      <div className="t-card h-full flex flex-col">
        <div className="section-header">
          <span>Open Positions ({positions.length})</span>
          {totalPnL !== 0 && (
            <span className={`ml-auto font-semibold ${totalPnL >= 0 ? 'text-t-green' : 'text-t-red'}`}>
              {totalPnL >= 0 ? '+' : ''}{totalPnL.toFixed(2)}
            </span>
          )}
        </div>
        <div className="flex-1 overflow-auto">
          {loading ? (
            <div className="p-3 text-t-dim text-xs">Loading...</div>
          ) : positions.length === 0 ? (
            <div className="p-4 text-t-dim text-xs text-center">No open positions</div>
          ) : (
            <table className="t-table">
              <thead><tr>
                <th>SYMBOL</th><th>DIR</th><th>VOL</th><th>OPEN</th><th>P&L</th><th></th>
              </tr></thead>
              <tbody>
                {positions.map(p => (
                  <tr key={p.ticket}>
                    <td className="font-semibold">{p.symbol}</td>
                    <td>
                      <span className={p.type === 'buy' ? 'text-t-green' : 'text-t-red'}>
                        {p.type === 'buy' ? '▲ BUY' : '▼ SELL'}
                      </span>
                    </td>
                    <td className="text-t-muted">{p.volume}</td>
                    <td className="text-t-muted">{p.open_price?.toFixed(5)}</td>
                    <td className={p.profit >= 0 ? 'text-t-green font-semibold' : 'text-t-red font-semibold'}>
                      {p.profit >= 0 ? '+' : ''}{p.profit?.toFixed(2)}
                    </td>
                    <td>
                      <button onClick={() => close(p.ticket)} disabled={closing === p.ticket}
                        className="btn btn-ghost px-1.5 py-0.5 text-t-red hover:bg-t-redBg">
                        {closing === p.ticket ? <RefreshCw className="w-2.5 h-2.5 animate-spin" /> : <X className="w-2.5 h-2.5" />}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="t-card h-full flex flex-col">
      {/* Header */}
      <div className="section-header">
        <span>TRADE MANAGER</span>
        <span className="ml-1 text-t-dim">— {positions.length} open</span>
        <div className="ml-auto flex items-center gap-2">
          {signals.length > 0 && (
            <button
              onClick={async () => { await fetch(`${API}/api/agents/trades/signals/execute-all`, { method: 'POST' }); fetchAll(); }}
              className="btn btn-green text-2xs py-0.5"
            >
              <Zap className="w-2.5 h-2.5" />EXECUTE {signals.length}
            </button>
          )}
          <button onClick={() => setShowManual(v => !v)} className="btn btn-ghost text-2xs py-0.5">
            <Plus className="w-2.5 h-2.5" />NEW ORDER
          </button>
          <button onClick={fetchAll} className="btn btn-ghost px-1.5 py-0.5">
            <RefreshCw className="w-2.5 h-2.5" />
          </button>
        </div>
      </div>

      {/* Performance metrics strip */}
      {Object.keys(metrics).length > 0 && (
        <div className="flex items-stretch border-b border-t-border bg-t-surface text-2xs">
          {[
            { label: 'WIN RATE', v: `${metrics.win_rate?.toFixed(1)}%`, color: metrics.win_rate >= 55 ? 'text-t-green' : 'text-t-red' },
            { label: 'PROFIT FACTOR', v: metrics.profit_factor?.toFixed(2), color: metrics.profit_factor >= 1.5 ? 'text-t-green' : metrics.profit_factor >= 1 ? 'text-t-yellow' : 'text-t-red' },
            { label: 'MAX DD', v: `${metrics.max_drawdown_pct?.toFixed(1)}%`, color: metrics.max_drawdown_pct <= 10 ? 'text-t-green' : 'text-t-red' },
            { label: 'TOTAL P&L', v: `$${metrics.total_profit?.toFixed(2)}`, color: metrics.total_profit >= 0 ? 'text-t-green' : 'text-t-red' },
            { label: 'TRADES', v: String(metrics.total_trades ?? 0), color: 'text-t-text' },
          ].map(m => (
            <div key={m.label} className="flex-1 px-3 py-1.5 border-r border-t-border last:border-r-0">
              <div className="text-t-dim uppercase tracking-wide" style={{ fontSize: '0.55rem' }}>{m.label}</div>
              <div className={`font-semibold mt-0.5 ${m.color}`} style={{ fontSize: '0.75rem' }}>{m.v ?? '—'}</div>
            </div>
          ))}
        </div>
      )}

      {/* Manual order form */}
      {showManual && (
        <div className="border-b border-t-border bg-t-panel px-3 py-2">
          <div className="text-2xs text-t-muted mb-1 uppercase tracking-wide">New Order</div>
          <div className="flex items-center gap-2 flex-wrap">
            <select value={manual.symbol} onChange={e => setManual(p => ({...p, symbol: e.target.value}))} className="t-select text-2xs">
              {['EURUSD','GBPUSD','USDJPY','XAUUSD','USOIL','US30'].map(s => <option key={s}>{s}</option>)}
            </select>
            <select value={manual.direction} onChange={e => setManual(p => ({...p, direction: e.target.value}))} className="t-select text-2xs">
              <option value="buy">BUY</option><option value="sell">SELL</option>
            </select>
            {[
              { label: 'Vol', key: 'volume', step: 0.01 },
              { label: 'SL pips', key: 'sl_pips', step: 1 },
              { label: 'TP pips', key: 'tp_pips', step: 1 },
            ].map(f => (
              <div key={f.key} className="flex items-center gap-1">
                <span className="text-2xs text-t-dim">{f.label}</span>
                <input type="number" value={(manual as Record<string, number>)[f.key]} step={f.step}
                  onChange={e => setManual(p => ({...p, [f.key]: parseFloat(e.target.value)}))}
                  className="t-input text-center" style={{ width: 52, fontSize: '0.68rem', padding: '2px 4px' }} />
              </div>
            ))}
            <button onClick={execute}
              className={`btn text-2xs ${manual.direction === 'buy' ? 'btn-green' : 'btn-red'}`}>
              {manual.direction === 'buy' ? '▲ BUY' : '▼ SELL'} {manual.symbol}
            </button>
          </div>
        </div>
      )}

      <div className="flex-1 overflow-auto">
        {loading ? (
          <div className="p-4 text-t-dim text-xs text-center">Loading...</div>
        ) : positions.length === 0 && signals.length === 0 ? (
          <div className="p-8 text-t-dim text-xs text-center">No open positions</div>
        ) : (
          <>
            {/* Positions */}
            {positions.length > 0 && (
              <>
                <div className="px-3 py-1 bg-t-surface border-b border-t-border flex items-center justify-between text-2xs text-t-muted">
                  <span>OPEN POSITIONS</span>
                  <span className={totalPnL >= 0 ? 'text-t-green font-semibold' : 'text-t-red font-semibold'}>
                    Unrealized: {totalPnL >= 0 ? '+' : ''}{totalPnL.toFixed(2)}
                  </span>
                </div>
                <table className="t-table">
                  <thead><tr>
                    <th>#</th><th>SYMBOL</th><th>DIR</th><th>VOL</th>
                    <th className="text-right">OPEN</th><th className="text-right">CURRENT</th>
                    <th className="text-right">SL</th><th className="text-right">TP</th>
                    <th className="text-right">PROFIT</th><th></th>
                  </tr></thead>
                  <tbody>
                    {positions.map(pos => (
                      <tr key={pos.ticket}>
                        <td className="text-t-dim">{pos.ticket}</td>
                        <td className="font-semibold">{pos.symbol}</td>
                        <td>
                          <span className={`badge ${pos.type === 'buy' ? 'badge-green' : 'badge-red'}`}>
                            {pos.type === 'buy' ? '▲ BUY' : '▼ SELL'}
                          </span>
                        </td>
                        <td className="text-t-muted">{pos.volume}</td>
                        <td className="text-right text-t-muted">{pos.open_price?.toFixed(5)}</td>
                        <td className="text-right text-t-text">{pos.current_price?.toFixed(5)}</td>
                        <td className="text-right text-t-red">{pos.sl ? pos.sl.toFixed(5) : '—'}</td>
                        <td className="text-right text-t-green">{pos.tp ? pos.tp.toFixed(5) : '—'}</td>
                        <td className={`text-right font-semibold ${pos.profit >= 0 ? 'text-t-green' : 'text-t-red'}`}>
                          {pos.profit >= 0 ? '+' : ''}{pos.profit?.toFixed(2)}
                        </td>
                        <td>
                          <button onClick={() => close(pos.ticket)} disabled={closing === pos.ticket}
                            className="btn btn-ghost px-1.5 py-0.5 border-t-red/30 text-t-red hover:bg-t-redBg text-2xs">
                            {closing === pos.ticket ? '...' : 'CLOSE'}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </>
            )}

            {/* Pending signals */}
            {signals.length > 0 && (
              <>
                <div className="px-3 py-1 bg-t-surface border-b border-t-border text-2xs text-t-muted uppercase tracking-wide">
                  Pending Signals ({signals.length})
                </div>
                <table className="t-table">
                  <thead><tr>
                    <th>SYMBOL</th><th>DIR</th><th>CONF</th><th>SL</th><th>TP</th><th>VOL</th>
                  </tr></thead>
                  <tbody>
                    {signals.map((s, i) => (
                      <tr key={i}>
                        <td className="font-semibold">{s.symbol}</td>
                        <td><span className={`badge ${s.direction === 'buy' ? 'badge-green' : 'badge-red'}`}>{s.direction.toUpperCase()}</span></td>
                        <td className={s.confidence >= 0.7 ? 'text-t-green' : 'text-t-yellow'}>{(s.confidence * 100).toFixed(0)}%</td>
                        <td className="text-t-muted">{s.sl_pips}p</td>
                        <td className="text-t-muted">{s.tp_pips}p</td>
                        <td className="text-t-muted">{s.volume}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </>
            )}
          </>
        )}
      </div>
    </div>
  );
}
