"use client";
import { useTradingStore } from "@/lib/store";
import { formatCurrency, profitColor } from "@/lib/utils";
import { TrendingUp, DollarSign, BarChart2, Shield } from "lucide-react";

export function AccountPanel() {
  const { account, stats, mode } = useTradingStore();
  const dailyPnl = stats?.risk_stats?.daily_pnl || 0;
  const balance = account.balance || 0;
  const equity = account.equity || 0;
  const drawdown = balance > 0 ? ((balance - equity) / balance * 100) : 0;
  const winRate = stats?.risk_stats?.win_rate || 0;

  const metrics = [
    {
      label: "Balance",
      value: formatCurrency(balance, account.currency || "USD"),
      icon: DollarSign,
      color: "text-gray-100",
    },
    {
      label: "Equity",
      value: formatCurrency(equity, account.currency || "USD"),
      icon: TrendingUp,
      color: equity >= balance ? "text-profit" : "text-loss",
    },
    {
      label: "Daily P/L",
      value: formatCurrency(dailyPnl, account.currency || "USD"),
      icon: BarChart2,
      color: profitColor(dailyPnl),
    },
    {
      label: "Win Rate",
      value: `${winRate.toFixed(1)}%`,
      icon: Shield,
      color: winRate >= 50 ? "text-profit" : "text-neutral",
    },
  ];

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
      {metrics.map((m) => (
        <div key={m.label}
          className="card p-4 flex items-start gap-3 hover:border-bg-border/80 transition-colors">
          <div className="p-2 rounded-lg bg-bg-surface">
            <m.icon className="w-4 h-4 text-brand" />
          </div>
          <div>
            <p className="data-label mb-1">{m.label}</p>
            <p className={`data-value text-base font-semibold ${m.color}`}>{m.value}</p>
          </div>
        </div>
      ))}

      {/* Account detail row */}
      <div className="col-span-2 lg:col-span-4 card p-3">
        <div className="flex flex-wrap gap-4 text-xs">
          <span className="text-gray-500">
            Account: <span className="mono text-gray-300">{account.login || "---"}</span>
          </span>
          <span className="text-gray-500">
            Server: <span className="mono text-gray-300">{account.server || "---"}</span>
          </span>
          <span className="text-gray-500">
            Leverage: <span className="mono text-gray-300">1:{account.leverage || 0}</span>
          </span>
          <span className="text-gray-500">
            Mode: <span className={`mono font-semibold ${mode === "live" ? "text-loss" : "text-neutral"}`}>
              {mode.toUpperCase()}
            </span>
          </span>
          <span className="text-gray-500">
            Drawdown: <span className={`mono ${drawdown > 3 ? "text-loss" : "text-gray-300"}`}>
              {drawdown.toFixed(2)}%
            </span>
          </span>
          <span className="text-gray-500">
            Free Margin: <span className="mono text-gray-300">
              {formatCurrency(account.margin_free || 0, account.currency || "USD")}
            </span>
          </span>
          <span className="text-gray-500">
            Total Trades: <span className="mono text-gray-300">
              {stats?.risk_stats?.total_trades || 0}
            </span>
          </span>
          <span className="text-gray-500">
            Total P/L: <span className={`mono ${profitColor(stats?.risk_stats?.total_pnl || 0)}`}>
              {formatCurrency(stats?.risk_stats?.total_pnl || 0, account.currency || "USD")}
            </span>
          </span>
        </div>
      </div>
    </div>
  );
}
