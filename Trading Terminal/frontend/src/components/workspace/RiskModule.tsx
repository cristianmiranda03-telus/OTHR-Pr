'use client';

import { TrendingUp, TrendingDown } from 'lucide-react';

type Account = { login: number; server: string; balance: number; equity: number; currency: string } | null;

export function RiskModule({ account }: { account: Account }) {
  const pnl = account ? account.equity - account.balance : null;
  const pct = pnl && account?.balance ? (pnl / account.balance * 100) : null;
  const eqPct = account ? Math.min(120, (account.equity / account.balance) * 100) : 0;

  return (
    <div className="t-card h-full flex flex-col">
      <div className="section-header"><span>ACCOUNT RISK</span></div>

      <div className="flex-1 p-3 space-y-3">
        {/* Balance / Equity */}
        <div className="grid grid-cols-2 gap-2">
          <div className="stat-box">
            <div className="label">Balance</div>
            <div className="value text-t-text text-sm">
              {account ? `${account.currency} ${account.balance?.toFixed(2)}` : '—'}
            </div>
          </div>
          <div className="stat-box">
            <div className="label">Equity</div>
            <div className={`value text-sm ${pnl !== null ? (pnl >= 0 ? 'text-t-green' : 'text-t-red') : 'text-t-text'}`}>
              {account ? `${account.currency} ${account.equity?.toFixed(2)}` : '—'}
            </div>
          </div>
        </div>

        {/* Float P&L */}
        <div className="stat-box">
          <div className="label flex items-center justify-between">
            <span>Float P&L</span>
            {pnl !== null && (pnl >= 0 ? <TrendingUp className="w-3 h-3 text-t-green" /> : <TrendingDown className="w-3 h-3 text-t-red" />)}
          </div>
          <div className={`value text-lg ${pnl !== null ? (pnl >= 0 ? 'text-t-green' : 'text-t-red') : 'text-t-muted'}`}>
            {pnl !== null ? `${pnl >= 0 ? '+' : ''}${pnl.toFixed(2)}` : '—'}
          </div>
          {pct !== null && (
            <div className={`text-2xs mt-1 ${pct >= 0 ? 'text-t-green' : 'text-t-red'}`}>
              {pct >= 0 ? '+' : ''}{pct.toFixed(2)}% of balance
            </div>
          )}
        </div>

        {/* Equity bar */}
        {account && (
          <div>
            <div className="flex justify-between text-2xs text-t-muted mb-1">
              <span>Equity / Balance</span>
              <span className={eqPct >= 100 ? 'text-t-green' : 'text-t-red'}>{eqPct.toFixed(1)}%</span>
            </div>
            <div className="mini-bar">
              <div className={`mini-bar-fill ${eqPct >= 100 ? 'green' : eqPct >= 90 ? 'blue' : 'red'}`}
                style={{ width: `${Math.min(100, eqPct)}%` }} />
            </div>
          </div>
        )}

        {/* Info */}
        <div className="text-2xs text-t-dim space-y-0.5 pt-1 border-t border-t-border">
          <div>Server: <span className="text-t-muted">{account?.server ?? '—'}</span></div>
          <div>Login: <span className="text-t-muted">{account?.login ?? '—'}</span></div>
        </div>
      </div>
    </div>
  );
}
