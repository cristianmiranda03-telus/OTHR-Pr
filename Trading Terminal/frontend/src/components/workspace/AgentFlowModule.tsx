'use client';

import { useState, useEffect, useRef } from 'react';
import { Bot, Newspaper, Cpu, BarChart2, TrendingUp, Shield, Zap } from 'lucide-react';

const API = 'http://localhost:8000';
const WS_URL = 'ws://localhost:8000/api/agents/stream';

type AgentStatus = 'idle' | 'thinking' | 'running' | 'done' | 'error' | 'waiting';
type AgentInfo = {
  agent_id: string; name: string; description: string;
  status: AgentStatus; last_run: string | null; run_count: number; error: string | null;
};
type LogEntry = { agent_id: string; level: string; content: string; timestamp: string; };
type SystemState = {
  market_regime: string; opportunity_score: number; trading_mode: string;
  active_strategies: string[]; risk_level: string; cycle_count: number;
  is_running: boolean; last_cycle: string | null;
};

const AGENT_META: Record<string, { icon: React.ElementType; color: string }> = {
  orchestrator:      { icon: Zap,       color: 'text-t-red' },
  news_agent:        { icon: Newspaper, color: 'text-t-blue' },
  strategy_agent:    { icon: Cpu,       color: 'text-t-blue' },
  backtest_agent:    { icon: BarChart2, color: 'text-t-green' },
  performance_agent: { icon: Shield,    color: 'text-t-orange' },
  trade_manager:     { icon: TrendingUp,color: 'text-t-green' },
};

const STATUS_DOT: Record<AgentStatus, string> = {
  idle: 'dot-dim', thinking: 'dot-blue', running: 'dot-yellow',
  done: 'dot-green', error: 'dot-red', waiting: 'dot-yellow',
};

export function AgentFlowModule({ consoleMode = false }: { consoleMode?: boolean }) {
  const [agents, setAgents] = useState<AgentInfo[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [systemState, setSystemState] = useState<SystemState | null>(null);
  const [wsOk, setWsOk] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const logsEndRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    fetch(`${API}/api/agents/status`).then(r => r.json())
      .then(d => { setAgents(d.agents || []); setSystemState(d.system_state || null); }).catch(() => {});

    const connect = () => {
      try {
        const ws = new WebSocket(WS_URL);
        wsRef.current = ws;
        ws.onopen = () => setWsOk(true);
        ws.onmessage = e => {
          try {
            const data = JSON.parse(e.data);
            if (data.type === 'init') { setAgents(data.agents || []); setSystemState(data.system_state || null); }
            else if (data.type === 'heartbeat' && data.state) setSystemState(data.state);
            else if (data.agent_id) {
              setLogs(prev => [...prev, data].slice(-300));
              setAgents(prev => prev.map(a => a.agent_id === data.agent_id
                ? { ...a, status: (data.level === 'error' ? 'error' : data.level === 'result' ? 'done' : 'running') as AgentStatus }
                : a));
            }
          } catch {}
        };
        ws.onclose = () => { setWsOk(false); wsRef.current = null; setTimeout(connect, 3000); };
        ws.onerror = () => ws.close();
      } catch {}
    };
    connect();
    const ping = setInterval(() => wsRef.current?.readyState === WebSocket.OPEN && wsRef.current.send('ping'), 25000);
    return () => { clearInterval(ping); wsRef.current?.close(); };
  }, []);

  useEffect(() => { logsEndRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [logs]);

  const filtered = selected ? logs.filter(l => l.agent_id === selected) : logs;

  return (
    <div className="t-card flex flex-col h-full">
      {/* Header */}
      <div className="section-header">
        <span className={`dot ${wsOk ? 'dot-green' : 'dot-dim'}`} />
        <span>{consoleMode ? 'CONSOLE' : 'AI AGENT FLOW'}</span>
        <span className="ml-auto text-t-dim">{wsOk ? 'LIVE' : 'RECONNECTING...'}</span>
        {systemState && (
          <span className="ml-3 text-t-dim">
            CYCLE #{systemState.cycle_count} ·{' '}
            <span className={systemState.trading_mode === 'aggressive' ? 'text-t-red' : 'text-t-green'}>
              {systemState.trading_mode?.toUpperCase()}
            </span>
          </span>
        )}
      </div>

      <div className="flex flex-1 min-h-0">
        {/* Agent list */}
        {!consoleMode && (
          <div className="w-44 border-r border-t-border flex flex-col overflow-y-auto shrink-0">
            <button
              onClick={() => setSelected(null)}
              className={`px-3 py-1.5 text-left text-2xs uppercase tracking-wider border-b border-t-border transition ${
                selected === null ? 'text-t-text bg-t-hover' : 'text-t-dim hover:text-t-muted'
              }`}
            >All Agents</button>

            {agents.map(agent => {
              const meta = AGENT_META[agent.agent_id] || { icon: Bot, color: 'text-t-muted' };
              const Icon = meta.icon;
              const sel = selected === agent.agent_id;
              return (
                <button
                  key={agent.agent_id}
                  onClick={() => setSelected(sel ? null : agent.agent_id)}
                  className={`px-3 py-2 text-left border-b border-t-border/50 transition ${sel ? 'bg-t-hover' : 'hover:bg-t-surface/50'}`}
                >
                  <div className="flex items-center gap-1.5 mb-0.5">
                    <Icon className={`w-3 h-3 shrink-0 ${meta.color}`} />
                    <span className="text-2xs text-t-text truncate">{agent.name}</span>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <span className={`dot ${STATUS_DOT[agent.status] || 'dot-dim'}`} />
                    <span className={`text-2xs agent-${agent.status}`}>{agent.status.toUpperCase()}</span>
                    {agent.run_count > 0 && <span className="text-2xs text-t-dim ml-auto">×{agent.run_count}</span>}
                  </div>
                  {(agent.status === 'running' || agent.status === 'thinking') && (
                    <div className="mini-bar mt-1">
                      <div className={`mini-bar-fill ${agent.status === 'thinking' ? 'blue' : 'yellow'}`}
                        style={{ width: '60%', animation: 'none' }} />
                    </div>
                  )}
                </button>
              );
            })}
          </div>
        )}

        {/* Log stream */}
        <div className="flex-1 flex flex-col min-h-0">
          {systemState && !consoleMode && (
            <div className="flex items-center gap-4 px-3 py-1 border-b border-t-border bg-t-surface text-2xs text-t-dim">
              <span>MARKET: <span className="text-t-text">{systemState.market_regime?.toUpperCase()}</span></span>
              <span>RISK: <span className={systemState.risk_level === 'high' ? 'text-t-red' : 'text-t-text'}>{systemState.risk_level?.toUpperCase()}</span></span>
              <span>SCORE: <span className={systemState.opportunity_score >= 0.65 ? 'text-t-green' : 'text-t-red'}>{(systemState.opportunity_score * 100).toFixed(0)}%</span></span>
              {systemState.active_strategies?.length > 0 && (
                <span>ACTIVE: <span className="text-t-green">{systemState.active_strategies.join(', ')}</span></span>
              )}
            </div>
          )}

          <div className="flex-1 overflow-y-auto p-2 space-y-0.5 font-mono text-xs bg-t-bg">
            {filtered.length === 0 ? (
              <div className="text-t-dim text-center py-8">
                {wsOk ? '> Waiting for agent activity...' : '> WebSocket disconnected. Reconnecting...'}
              </div>
            ) : (
              filtered.map((log, i) => (
                <div key={i} className={`flex gap-2 text-2xs leading-relaxed log-${log.level}`}>
                  <span className="text-t-dim shrink-0">
                    {new Date(log.timestamp).toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                  </span>
                  <span className="text-t-dim shrink-0 w-20 truncate">[{log.agent_id?.replace('_agent', '').replace('_', '-').toUpperCase()}]</span>
                  <span className="flex-1">{log.content}</span>
                </div>
              ))
            )}
            <div ref={logsEndRef} />
          </div>
        </div>
      </div>
    </div>
  );
}
