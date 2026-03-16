'use client';

import { useState, useEffect } from 'react';
import { RefreshCw, TrendingUp, TrendingDown, Minus } from 'lucide-react';

const API = 'http://localhost:8000';

type NewsItem = { id: string; title: string; source: string; sentiment: string; time: string; symbols?: string[] };
type Analysis = {
  overall_sentiment?: string; risk_appetite?: string; key_themes?: string[];
  recommended_trades?: { pair: string; direction: string; confidence: number; reason: string }[];
  summary?: string;
};

export function NewsModule() {
  const [items, setItems] = useState<NewsItem[]>([]);
  const [analysis, setAnalysis] = useState<Analysis | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchAll = () => {
    Promise.all([
      fetch(`${API}/api/news/feed?limit=20`).then(r => r.json()),
      fetch(`${API}/api/agents/news/latest`).then(r => r.json()),
    ]).then(([feed, ai]) => {
      setItems(feed.items || []);
      setAnalysis(ai.analysis || null);
    }).catch(() => {}).finally(() => setLoading(false));
  };

  useEffect(() => { fetchAll(); }, []);

  const refresh = async () => {
    setRefreshing(true);
    try { await fetch(`${API}/api/agents/news/refresh`, { method: 'POST' }); fetchAll(); }
    finally { setRefreshing(false); }
  };

  const sentColor = (s: string) =>
    s === 'positive' || s === 'bullish' ? 'text-t-green' :
    s === 'negative' || s === 'bearish' ? 'text-t-red' : 'text-t-muted';

  return (
    <div className="t-card h-full flex flex-col">
      <div className="section-header">
        <span>NEWS & SENTIMENT</span>
        <button onClick={refresh} disabled={refreshing} className="btn btn-ghost text-2xs py-0.5 ml-auto">
          <RefreshCw className={`w-2.5 h-2.5 ${refreshing ? 'animate-spin' : ''}`} />
          AI ANALYZE
        </button>
      </div>

      {/* AI summary strip */}
      {analysis && (
        <div className="px-3 py-2 bg-t-surface border-b border-t-border text-2xs space-y-1">
          <div className="flex items-center gap-3 flex-wrap">
            <span className="text-t-dim">SENTIMENT:</span>
            <span className={`font-semibold ${sentColor(analysis.overall_sentiment || '')}`}>
              {analysis.overall_sentiment?.toUpperCase()}
            </span>
            <span className="text-t-dim">RISK:</span>
            <span className={analysis.risk_appetite === 'risk-on' ? 'text-t-green' : analysis.risk_appetite === 'risk-off' ? 'text-t-red' : 'text-t-yellow'}>
              {analysis.risk_appetite?.toUpperCase()}
            </span>
            {analysis.key_themes?.slice(0, 2).map((t, i) => (
              <span key={i} className="badge badge-dim">{t}</span>
            ))}
          </div>
          {analysis.summary && <p className="text-t-muted italic">{analysis.summary}</p>}
          {analysis.recommended_trades?.length ? (
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-t-dim">AI SIGNALS:</span>
              {analysis.recommended_trades.slice(0, 4).map((t, i) => (
                <span key={i} className={`badge ${t.direction === 'buy' ? 'badge-green' : 'badge-red'}`}>
                  {t.pair} {t.direction.toUpperCase()} {(t.confidence * 100).toFixed(0)}%
                </span>
              ))}
            </div>
          ) : null}
        </div>
      )}

      <div className="flex-1 overflow-auto">
        {loading ? (
          <div className="p-4 text-t-dim text-xs">Loading feed...</div>
        ) : items.length === 0 ? (
          <div className="p-6 text-t-dim text-xs text-center">No items · Click AI Analyze to fetch news</div>
        ) : (
          <table className="t-table">
            <thead><tr><th>TIME</th><th>TITLE</th><th>SOURCE</th><th>SENT</th><th>PAIRS</th></tr></thead>
            <tbody>
              {items.map(n => (
                <tr key={n.id}>
                  <td className="text-t-dim whitespace-nowrap" style={{ fontSize: '0.6rem' }}>
                    {n.time ? new Date(n.time).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false }) : '—'}
                  </td>
                  <td className="max-w-xs">
                    <span className="text-t-text line-clamp-1">{n.title}</span>
                  </td>
                  <td className="text-t-dim whitespace-nowrap">{n.source}</td>
                  <td>
                    {n.sentiment === 'positive' || n.sentiment === 'bullish'
                      ? <TrendingUp className="w-3 h-3 text-t-green" />
                      : n.sentiment === 'negative' || n.sentiment === 'bearish'
                      ? <TrendingDown className="w-3 h-3 text-t-red" />
                      : <Minus className="w-3 h-3 text-t-muted" />}
                  </td>
                  <td className="text-t-blue text-2xs">{n.symbols?.join(', ')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
