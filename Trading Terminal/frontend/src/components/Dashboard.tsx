'use client';

import { useState, useEffect, useRef } from 'react';
import { LogOut, Play, Square, RefreshCw, ChevronLeft, ChevronRight, Activity } from 'lucide-react';
import { AgentFlowModule } from '@/components/workspace/AgentFlowModule';
import { StrategyListModule } from '@/components/workspace/StrategyListModule';
import { TradeManagerModule } from '@/components/workspace/TradeManagerModule';
import { ChartModule } from '@/components/workspace/ChartModule';
import { NewsModule } from '@/components/workspace/NewsModule';
import { RiskModule } from '@/components/workspace/RiskModule';
import { SessionsModule } from '@/components/workspace/SessionsModule';
import { SidebarConfig } from '@/components/workspace/SidebarConfig';

const API = 'http://localhost:8000';

type Tab = 'overview' | 'agents' | 'strategies' | 'trades' | 'news' | 'console';

const TABS: { id: Tab; label: string }[] = [
  { id: 'overview',    label: 'Overview' },
  { id: 'agents',      label: 'AI Agents' },
  { id: 'strategies',  label: 'Strategies' },
  { id: 'trades',      label: 'Trades' },
  { id: 'news',        label: 'News' },
  { id: 'console',     label: 'Console' },
];

type Account = {
  login: number; server: string; balance: number;
  equity: number; currency: string; profit?: number; margin?: number;
};
type SystemState = {
  market_regime: string; opportunity_score: number;
  trading_mode: string; active_strategies: string[];
  risk_level: string; cycle_count: number;
  is_running: boolean; last_cycle: string | null;
};

export function Dashboard({ onDisconnect }: { onDisconnect: () => void }) {
  const [account, setAccount] = useState<Account | null>(null);
  const [systemState, setSystemState] = useState<SystemState | null>(null);
  const [activeTab, setActiveTab] = useState<Tab>('overview');
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [disconnecting, setDisconnecting] = useState(false);
  const [cycleLoading, setCycleLoading] = useState(false);
  const [clock, setClock] = useState('');
  const [metrics, setMetrics] = useState<Record<string, number>>({});
  const pollRef = useRef<NodeJS.Timeout | null>(null);

  // Clock
  useEffect(() => {
    const tick = () => {
      const now = new Date();
      setClock(now.toLocaleTimeString('en-US', { hour12: false }) + ' UTC');
    };
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, []);

  // Data polling
  useEffect(() => {
    const fetchAll = () => {
      fetch(`${API}/api/mt5/state`).then(r => r.json())
        .then(d => { if (d?.account) setAccount(d.account); }).catch(() => {});
      fetch(`${API}/api/agents/status`).then(r => r.json())
        .then(d => { if (d?.system_state) setSystemState(d.system_state); }).catch(() => {});
      fetch(`${API}/api/agents/performance`).then(r => r.json())
        .then(d => { if (d?.metrics) setMetrics(d.metrics); }).catch(() => {});
    };
    fetchAll();
    pollRef.current = setInterval(fetchAll, 5000);
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, []);

  const disconnect = async () => {
    setDisconnecting(true);
    try {
      await fetch(`${API}/api/mt5/disconnect`, { method: 'POST' });
      onDisconnect();
    } finally { setDisconnecting(false); }
  };

  const toggleOrchestrator = async () => {
    if (systemState?.is_running) {
      await fetch(`${API}/api/agents/stop`, { method: 'POST' });
    } else {
      await fetch(`${API}/api/agents/start`, { method: 'POST' });
    }
  };

  const runCycle = async () => {
    setCycleLoading(true);
    try { await fetch(`${API}/api/agents/cycle`, { method: 'POST' }); }
    finally { setCycleLoading(false); }
  };

  const pnl = account ? account.equity - account.balance : null;
  const pnlPct = pnl !== null && account?.balance ? (pnl / account.balance * 100) : null;
  const isRunning = systemState?.is_running ?? false;
  const score = systemState?.opportunity_score ?? 0;

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-t-bg">

      {/* ── TOP BAR ──────────────────────────────────────────── */}
      <div className="flex items-center h-8 bg-t-surface border-b border-t-border px-3 shrink-0 gap-0">

        {/* Brand */}
        <div className="flex items-center gap-2 pr-4 border-r border-t-border mr-3">
          <Activity className="w-3 h-3 text-t-red" />
          <span className="text-xs font-semibold text-t-text tracking-wider">QUANT-JOKER</span>
          <span className="text-2xs text-t-dim uppercase tracking-widest">AI Algorithmic</span>
        </div>

        {/* Ticker tape: key stats */}
        <div className="flex items-center gap-0 overflow-hidden flex-1 text-2xs">
          {account && (
            <>
              <span className="ticker-item">
                <span className="text-t-muted">BALANCE</span>
                <span className="text-t-text font-semibold">{account.currency} {account.balance?.toFixed(2)}</span>
              </span>
              <span className="ticker-item">
                <span className="text-t-muted">EQUITY</span>
                <span className={pnl !== null && pnl >= 0 ? 'text-t-green font-semibold' : 'text-t-red font-semibold'}>
                  {account.currency} {account.equity?.toFixed(2)}
                </span>
              </span>
              {pnl !== null && (
                <span className="ticker-item">
                  <span className="text-t-muted">P&L</span>
                  <span className={pnl >= 0 ? 'text-t-green font-semibold' : 'text-t-red font-semibold'}>
                    {pnl >= 0 ? '+' : ''}{pnl.toFixed(2)} ({pnlPct?.toFixed(2)}%)
                  </span>
                </span>
              )}
            </>
          )}
          {metrics.win_rate !== undefined && (
            <span className="ticker-item">
              <span className="text-t-muted">WIN RATE</span>
              <span className={metrics.win_rate >= 55 ? 'text-t-green' : 'text-t-red'}>{metrics.win_rate?.toFixed(1)}%</span>
            </span>
          )}
          {systemState && (
            <>
              <span className="ticker-item">
                <span className="text-t-muted">REGIME</span>
                <span className="text-t-text">{systemState.market_regime?.toUpperCase()}</span>
              </span>
              <span className="ticker-item">
                <span className="text-t-muted">SCORE</span>
                <span className={score >= 0.65 ? 'text-t-green' : score >= 0.35 ? 'text-t-yellow' : 'text-t-red'}>
                  {(score * 100).toFixed(0)}%
                </span>
              </span>
              <span className="ticker-item">
                <span className={`dot ${isRunning ? 'dot-green' : 'dot-dim'} mr-1`} />
                <span className={isRunning ? 'text-t-green' : 'text-t-dim'}>
                  {isRunning ? 'LIVE' : 'IDLE'} #{systemState.cycle_count}
                </span>
              </span>
            </>
          )}
        </div>

        {/* Right controls */}
        <div className="flex items-center gap-2 pl-3 border-l border-t-border">
          <span className="text-2xs text-t-muted">{clock}</span>
          <button onClick={toggleOrchestrator}
            className={`btn ${isRunning ? 'btn-red' : 'btn-green'} py-0.5 px-2`}>
            {isRunning ? <><Square className="w-2.5 h-2.5" />STOP</> : <><Play className="w-2.5 h-2.5" />START</>}
          </button>
          <button onClick={runCycle} disabled={cycleLoading || isRunning}
            className="btn btn-ghost py-0.5 px-2">
            <RefreshCw className={`w-2.5 h-2.5 ${cycleLoading ? 'animate-spin' : ''}`} />
            CYCLE
          </button>
          {account && (
            <span className="text-2xs text-t-muted border-l border-t-border pl-2">
              {account.server} · #{account.login}
            </span>
          )}
          <button onClick={disconnect} disabled={disconnecting}
            className="btn btn-ghost py-0.5 px-2 border-t-border">
            <LogOut className="w-2.5 h-2.5" />
          </button>
        </div>
      </div>

      {/* ── METRIC BAR ───────────────────────────────────────── */}
      <div className="flex items-stretch h-16 bg-t-panel border-b border-t-border shrink-0">
        {[
          {
            label: 'Account Balance',
            value: account ? `${account.currency} ${account.balance?.toFixed(2)}` : '—',
            sub: `${(metrics.total_trades ?? 0)} trades`,
            icon: '$',
            color: 'text-t-text',
          },
          {
            label: 'Total P&L',
            value: pnl !== null ? `${pnl >= 0 ? '+' : ''}${account?.currency} ${pnl.toFixed(2)}` : '—',
            sub: pnlPct !== null ? `${pnlPct.toFixed(2)}% return` : '',
            icon: '~',
            color: pnl !== null ? (pnl >= 0 ? 'text-t-green' : 'text-t-red') : 'text-t-muted',
            bar: pnl !== null ? { pct: Math.min(100, Math.abs(pnlPct ?? 0) * 5), color: pnl >= 0 ? 'green' : 'red' } : null,
          },
          {
            label: 'Win Rate',
            value: metrics.win_rate !== undefined ? `${metrics.win_rate.toFixed(1)}%` : '—',
            sub: metrics.win_rate !== undefined ? (metrics.win_rate >= 55 ? 'Above threshold' : 'Below threshold') : '',
            icon: '%',
            color: metrics.win_rate !== undefined ? (metrics.win_rate >= 55 ? 'text-t-green' : 'text-t-red') : 'text-t-muted',
            bar: metrics.win_rate !== undefined ? { pct: metrics.win_rate, color: metrics.win_rate >= 55 ? 'green' : 'red' } : null,
          },
          {
            label: 'Daily P&L',
            value: account?.profit !== undefined ? `${account.profit >= 0 ? '+' : ''}${account.currency} ${account.profit?.toFixed(2)}` : '—',
            sub: '',
            icon: '~',
            color: account?.profit !== undefined ? (account.profit >= 0 ? 'text-t-green' : 'text-t-red') : 'text-t-muted',
          },
          {
            label: 'Consec. Losses',
            value: metrics.consecutive_losses !== undefined ? String(metrics.consecutive_losses) : '—',
            sub: metrics.consecutive_losses !== undefined ? (metrics.consecutive_losses <= 3 ? 'Within limits' : 'HIGH RISK') : '',
            icon: '⚠',
            color: metrics.consecutive_losses !== undefined ? (metrics.consecutive_losses <= 3 ? 'text-t-text' : 'text-t-red') : 'text-t-muted',
          },
        ].map((m, i) => (
          <div key={i} className="flex-1 border-r border-t-border px-4 py-2 flex flex-col justify-between min-w-0">
            <div className="flex items-start justify-between">
              <span className="text-2xs text-t-muted uppercase tracking-wide">{m.label}</span>
              <span className="text-2xs text-t-dim">{m.icon}</span>
            </div>
            <div>
              <div className={`text-sm font-semibold ${m.color} leading-tight`}>{m.value}</div>
              {m.sub && <div className={`text-2xs mt-0.5 ${m.color === 'text-t-red' ? 'text-t-red' : 'text-t-dim'}`}>{m.sub}</div>}
            </div>
            {m.bar && (
              <div className="mini-bar mt-1">
                <div className={`mini-bar-fill ${m.bar.color}`} style={{ width: `${m.bar.pct}%` }} />
              </div>
            )}
          </div>
        ))}
      </div>

      {/* ── MAIN AREA ────────────────────────────────────────── */}
      <div className="flex flex-1 min-h-0">

        {/* ── LEFT SIDEBAR ─────────────────────────────────── */}
        <div className={`flex flex-col bg-t-surface border-r border-t-border shrink-0 transition-all duration-200 ${sidebarOpen ? 'w-52' : 'w-8'}`}>
          <button
            onClick={() => setSidebarOpen(v => !v)}
            className="flex items-center justify-between px-2 py-1.5 border-b border-t-border text-t-dim hover:text-t-text transition text-2xs uppercase tracking-widest"
          >
            {sidebarOpen && <span>Configuration</span>}
            {sidebarOpen ? <ChevronLeft className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
          </button>
          {sidebarOpen && <SidebarConfig account={account} systemState={systemState} />}
        </div>

        {/* ── RIGHT CONTENT ────────────────────────────────── */}
        <div className="flex flex-col flex-1 min-w-0 min-h-0">

          {/* Tab bar */}
          <div className="tab-bar bg-t-panel shrink-0 px-2">
            {TABS.map(t => (
              <button key={t.id} className={`tab ${activeTab === t.id ? 'active' : ''}`}
                onClick={() => setActiveTab(t.id)}>
                {t.label}
              </button>
            ))}
          </div>

          {/* Tab content */}
          <div className="flex-1 min-h-0 overflow-auto p-2">
            {activeTab === 'overview' && (
              <div className="grid grid-cols-3 gap-2 h-full" style={{ gridTemplateRows: '1fr 1fr' }}>
                <div className="col-span-2 row-span-1"><ChartModule /></div>
                <div className="row-span-2">
                  <div className="flex flex-col gap-2 h-full">
                    <div className="flex-1"><RiskModule account={account} /></div>
                    <div className="flex-1"><SessionsModule /></div>
                  </div>
                </div>
                <div className="col-span-2 row-span-1"><TradeManagerModule compact /></div>
              </div>
            )}

            {activeTab === 'agents' && (
              <div className="h-full"><AgentFlowModule /></div>
            )}

            {activeTab === 'strategies' && (
              <div className="h-full"><StrategyListModule /></div>
            )}

            {activeTab === 'trades' && (
              <div className="h-full"><TradeManagerModule /></div>
            )}

            {activeTab === 'news' && (
              <div className="grid grid-cols-2 gap-2 h-full">
                <NewsModule />
                <div className="flex flex-col gap-2">
                  <ChartModule compact />
                </div>
              </div>
            )}

            {activeTab === 'console' && (
              <div className="h-full"><AgentFlowModule consoleMode /></div>
            )}
          </div>
        </div>
      </div>

      {/* ── STATUS BAR ───────────────────────────────────────── */}
      <div className="h-5 bg-t-surface border-t border-t-border flex items-center px-3 gap-4 text-2xs text-t-dim shrink-0">
        <span className={`dot ${isRunning ? 'dot-green' : 'dot-dim'}`} />
        <span>{isRunning ? 'Orchestrator running' : 'Orchestrator idle'}</span>
        {systemState?.last_cycle && (
          <span>Last cycle: {new Date(systemState.last_cycle).toLocaleTimeString()}</span>
        )}
        {systemState?.active_strategies?.length > 0 && (
          <span>Active: {systemState.active_strategies.join(', ')}</span>
        )}
        <span className="ml-auto">{account?.server} · MT5</span>
      </div>
    </div>
  );
}
