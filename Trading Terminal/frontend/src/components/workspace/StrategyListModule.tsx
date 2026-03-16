'use client';

import { useState, useEffect } from 'react';
import { RefreshCw, Zap, ChevronDown, ChevronRight } from 'lucide-react';

const API = 'http://localhost:8000';

type Strategy = {
  id: string; name: string; category: string; description: string;
  timeframes: string[]; indicators: string[]; status: string;
  backtest_key: string | null;
  last_backtest?: { total_return_pct: number; sharpe_ratio: number; win_rate: number; max_drawdown_pct: number; total_trades: number; profit_factor?: number; };
};
type BacktestResult = {
  strategy_id: string; composite_score: number;
  stats?: { total_return_pct: number; sharpe_ratio: number; win_rate: number; max_drawdown_pct: number; total_trades: number; profit_factor?: number; };
};

const CAT_BADGE: Record<string, string> = {
  basic: 'badge-dim', advanced: 'badge-blue', quant: 'badge-yellow', ai: 'badge-red',
};

export function StrategyListModule() {
  const [strategies, setStrategies] = useState<Strategy[]>([]);
  const [newStrategies, setNewStrategies] = useState<Strategy[]>([]);
  const [recommended, setRecommended] = useState<{ strategy_id: string; confidence: number }[]>([]);
  const [rankings, setRankings] = useState<BacktestResult[]>([]);
  const [loading, setLoading] = useState(true);
  const [backtesting, setBacktesting] = useState<string | null>(null);
  const [deploying, setDeploying] = useState<string | null>(null);
  const [filterCat, setFilterCat] = useState('all');
  const [sortBy, setSortBy] = useState<'return' | 'sharpe' | 'winrate' | 'name'>('return');
  const [symbol, setSymbol] = useState('EURUSD');
  const [tf, setTf] = useState('H1');
  const [expanded, setExpanded] = useState<string | null>(null);

  const fetchData = () => {
    setLoading(true);
    Promise.all([
      fetch(`${API}/api/agents/strategies`).then(r => r.json()),
      fetch(`${API}/api/agents/backtest/rankings`).then(r => r.json()),
    ]).then(([s, bt]) => {
      setStrategies(s.strategies || []);
      setNewStrategies(s.new_strategies || []);
      setRecommended(s.recommended || []);
      setRankings(bt.rankings || []);
    }).catch(() => {}).finally(() => setLoading(false));
  };

  useEffect(() => { fetchData(); }, []);

  const runBacktest = async (id: string) => {
    setBacktesting(id);
    try {
      await fetch(`${API}/api/agents/backtest`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ strategy_id: id, symbol, timeframe: tf, bars: 2000 }),
      });
      fetchData();
    } finally { setBacktesting(null); }
  };

  const runBatchBacktest = async () => {
    setBacktesting('batch');
    try {
      const keys = strategies.filter(s => s.backtest_key).map(s => s.backtest_key!);
      await fetch(`${API}/api/agents/backtest/batch`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ strategies: keys, symbol, timeframe: tf }),
      });
      fetchData();
    } finally { setBacktesting(null); }
  };

  const deploy = async (id: string) => {
    setDeploying(id);
    try {
      const r = await fetch(`${API}/api/agents/strategy/deploy`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ strategy_id: id, symbol, timeframe: tf }),
      });
      const d = await r.json();
      alert(d.success ? `Deployed ${id} on ${symbol}/${tf}` : `Error: ${d.error}`);
    } finally { setDeploying(null); }
  };

  const getBt = (id: string) => rankings.find(r => r.strategy_id === id);
  const isRec = (id: string) => recommended.some(r => r.strategy_id === id);
  const allStrats = [...strategies, ...newStrategies];
  const cats = ['all', 'basic', 'advanced', 'quant', 'ai'];
  const filtered = filterCat === 'all' ? allStrats : allStrats.filter(s => s.category === filterCat);
  const sorted = [...filtered].sort((a, b) => {
    const ak = a.backtest_key || a.id, bk = b.backtest_key || b.id;
    const abt = getBt(ak), bbt = getBt(bk);
    if (sortBy === 'return')  return (bbt?.stats?.total_return_pct ?? -999) - (abt?.stats?.total_return_pct ?? -999);
    if (sortBy === 'sharpe')  return (bbt?.stats?.sharpe_ratio ?? -999) - (abt?.stats?.sharpe_ratio ?? -999);
    if (sortBy === 'winrate') return (bbt?.stats?.win_rate ?? -999) - (abt?.stats?.win_rate ?? -999);
    return a.name.localeCompare(b.name);
  });

  const pct = (v: number, good: number, bad: number) =>
    v >= good ? 'text-t-green' : v >= bad ? 'text-t-yellow' : 'text-t-red';

  return (
    <div className="t-card h-full flex flex-col">
      {/* Header */}
      <div className="section-header">
        <span>STRATEGY LIBRARY</span>
        <span className="text-t-dim ml-1">({allStrats.length})</span>

        <div className="ml-auto flex items-center gap-2">
          <select value={symbol} onChange={e => setSymbol(e.target.value)} className="t-select text-2xs py-0.5">
            {['EURUSD','GBPUSD','USDJPY','XAUUSD','USOIL','US30','NAS100'].map(s => <option key={s}>{s}</option>)}
          </select>
          <select value={tf} onChange={e => setTf(e.target.value)} className="t-select text-2xs py-0.5">
            {['M5','M15','M30','H1','H4','D1'].map(t => <option key={t}>{t}</option>)}
          </select>
          <button onClick={runBatchBacktest} disabled={backtesting !== null} className="btn btn-green text-2xs py-0.5">
            <RefreshCw className={`w-2.5 h-2.5 ${backtesting === 'batch' ? 'animate-spin' : ''}`} />
            BACKTEST ALL
          </button>
          <button onClick={fetchData} className="btn btn-ghost px-1.5 py-0.5">
            <RefreshCw className="w-2.5 h-2.5" />
          </button>
        </div>
      </div>

      {/* Filter bar */}
      <div className="flex items-center gap-2 px-3 py-1.5 bg-t-surface border-b border-t-border">
        {cats.map(c => (
          <button key={c} onClick={() => setFilterCat(c)}
            className={`btn text-2xs py-0.5 px-2 uppercase ${filterCat === c ? 'btn-red' : 'btn-ghost'}`}>
            {c}
          </button>
        ))}
        <div className="ml-auto flex items-center gap-2 text-2xs text-t-dim">
          SORT:
          {(['return','sharpe','winrate','name'] as const).map(s => (
            <button key={s} onClick={() => setSortBy(s)}
              className={`px-1.5 py-0.5 rounded transition ${sortBy === s ? 'text-t-text' : 'text-t-dim hover:text-t-muted'}`}>
              {s.toUpperCase()}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-auto">
        {loading ? (
          <div className="p-6 text-t-dim text-xs text-center">Loading strategies...</div>
        ) : (
          <table className="t-table">
            <thead>
              <tr>
                <th style={{ width: 20 }}></th>
                <th>STRATEGY</th>
                <th>CAT</th>
                <th>TIMEFRAMES</th>
                <th className="text-right">RETURN%</th>
                <th className="text-right">SHARPE</th>
                <th className="text-right">WIN%</th>
                <th className="text-right">MAX DD%</th>
                <th className="text-right">TRADES</th>
                <th className="text-right">P.FACTOR</th>
                <th className="text-right">SCORE</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {sorted.map(s => {
                const key = s.backtest_key || s.id;
                const bt = getBt(key);
                const stats = bt?.stats || s.last_backtest;
                const rec = isRec(key);
                const exp = expanded === s.id;
                return (
                  <>
                    <tr key={s.id}
                      className={`cursor-pointer ${rec ? 'bg-t-redBg/30' : ''}`}
                      onClick={() => setExpanded(exp ? null : s.id)}
                    >
                      <td className="text-t-dim px-2">
                        {exp ? <ChevronDown className="w-2.5 h-2.5" /> : <ChevronRight className="w-2.5 h-2.5" />}
                      </td>
                      <td>
                        <div className="flex items-center gap-1">
                          {rec && <Zap className="w-2.5 h-2.5 text-t-red shrink-0" />}
                          <span className="font-semibold">{s.name}</span>
                        </div>
                      </td>
                      <td><span className={`badge ${CAT_BADGE[s.category] || 'badge-dim'}`}>{s.category}</span></td>
                      <td className="text-t-muted" style={{ fontSize: '0.6rem' }}>{s.timeframes?.join(', ')}</td>
                      <td className={`text-right font-semibold ${stats ? pct(stats.total_return_pct, 10, 0) : 'text-t-dim'}`}>
                        {stats ? `${stats.total_return_pct > 0 ? '+' : ''}${stats.total_return_pct?.toFixed(1)}%` : '—'}
                      </td>
                      <td className={`text-right ${stats ? pct(stats.sharpe_ratio, 1.5, 0.8) : 'text-t-dim'}`}>
                        {stats ? stats.sharpe_ratio?.toFixed(2) : '—'}
                      </td>
                      <td className={`text-right ${stats ? pct(stats.win_rate, 55, 45) : 'text-t-dim'}`}>
                        {stats ? `${stats.win_rate?.toFixed(1)}%` : '—'}
                      </td>
                      <td className={`text-right ${stats ? (stats.max_drawdown_pct <= 10 ? 'text-t-green' : stats.max_drawdown_pct <= 20 ? 'text-t-yellow' : 'text-t-red') : 'text-t-dim'}`}>
                        {stats ? `${stats.max_drawdown_pct?.toFixed(1)}%` : '—'}
                      </td>
                      <td className="text-right text-t-muted">{stats?.total_trades ?? '—'}</td>
                      <td className={`text-right ${stats?.profit_factor ? pct(stats.profit_factor, 1.5, 1) : 'text-t-dim'}`}>
                        {stats?.profit_factor?.toFixed(2) ?? '—'}
                      </td>
                      <td className={`text-right font-semibold ${bt ? pct(bt.composite_score, 20, 5) : 'text-t-dim'}`}>
                        {bt?.composite_score?.toFixed(1) ?? '—'}
                      </td>
                      <td>
                        <div className="flex items-center gap-1" onClick={e => e.stopPropagation()}>
                          {s.backtest_key && (
                            <button onClick={() => runBacktest(s.backtest_key!)} disabled={backtesting !== null}
                              className="btn btn-ghost text-2xs py-0.5 px-2">
                              {backtesting === s.backtest_key ? '...' : 'TEST'}
                            </button>
                          )}
                          {stats && (
                            <button onClick={() => deploy(s.backtest_key || s.id)} disabled={deploying !== null}
                              className="btn btn-blue text-2xs py-0.5 px-2">
                              {deploying === s.id ? '...' : 'DEPLOY'}
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                    {exp && (
                      <tr key={`${s.id}-exp`} className="bg-t-surface">
                        <td colSpan={12} className="px-8 py-2">
                          <p className="text-2xs text-t-muted">{s.description}</p>
                          <p className="text-2xs text-t-dim mt-0.5">Indicators: {s.indicators?.join(', ')}</p>
                          {rec && <p className="text-2xs text-t-red mt-0.5">★ AI Recommended for current market conditions</p>}
                        </td>
                      </tr>
                    )}
                  </>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Footer */}
      {rankings.length > 0 && (
        <div className="px-3 py-1.5 border-t border-t-border bg-t-surface text-2xs flex items-center gap-4">
          <span className="text-t-dim">BEST:</span>
          <span className="text-t-text font-semibold">{rankings[0]?.strategy_id}</span>
          <span className="text-t-dim">Score: <span className="text-t-text">{rankings[0]?.composite_score?.toFixed(1)}</span></span>
          <span className={rankings[0]?.stats?.total_return_pct >= 0 ? 'text-t-green' : 'text-t-red'}>
            Return: {rankings[0]?.stats?.total_return_pct?.toFixed(1)}%
          </span>
          <span className="text-t-dim">Sharpe: <span className="text-t-text">{rankings[0]?.stats?.sharpe_ratio?.toFixed(2)}</span></span>
        </div>
      )}
    </div>
  );
}
