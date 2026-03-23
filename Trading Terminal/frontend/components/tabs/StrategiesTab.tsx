"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/ws";
import { cn, formatCurrency, formatPercent } from "@/lib/utils";
import { TrendingUp, TrendingDown, Award, RefreshCw } from "lucide-react";

interface StrategyRow {
  strategy_name: string;
  symbol:        string;
  total_trades:  number;
  win_rate:      number;
  total_pnl:     number;
  max_drawdown:  number;
  profit_factor: number;
  last_seen:     string;
  is_live:       boolean;
}

export function StrategiesTab() {
  const [rows, setRows] = useState<StrategyRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [sort, setSort] = useState<keyof StrategyRow>("total_pnl");

  const load = async () => {
    setLoading(true);
    try {
      const data = await api.get("/api/strategies/leaderboard");
      setRows(data.leaderboard || []);
    } catch { /* silent */ }
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const sorted = [...rows].sort((a, b) => {
    const va = a[sort] as number, vb = b[sort] as number;
    return typeof va === "number" ? vb - va : 0;
  });

  const ColHeader = ({ label, key: k }: { label: string; key: keyof StrategyRow }) => (
    <th
      className="cursor-pointer hover:text-gray-300 transition-colors select-none"
      onClick={() => setSort(k)}
    >
      <span className={cn("flex items-center gap-1", sort === k && "text-brand")}>
        {label}
        {sort === k && <span className="text-brand">▼</span>}
      </span>
    </th>
  );

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between card px-4 py-3">
        <div className="flex items-center gap-2">
          <Award className="w-4 h-4 text-brand" />
          <span className="text-sm font-semibold text-gray-200">Strategy Leaderboard</span>
          <span className="text-xs text-gray-600">{rows.length} strategies tracked</span>
        </div>
        <button onClick={load} className="btn btn-brand py-1.5 px-3">
          <RefreshCw className={cn("w-3 h-3", loading && "animate-spin")} /> Refresh
        </button>
      </div>

      <div className="card overflow-x-auto">
        <table>
          <thead>
            <tr>
              <ColHeader label="Strategy"     key="strategy_name" />
              <ColHeader label="Symbol"       key="symbol" />
              <ColHeader label="Trades"       key="total_trades" />
              <ColHeader label="Win Rate"     key="win_rate" />
              <ColHeader label="P&L"          key="total_pnl" />
              <ColHeader label="Drawdown"     key="max_drawdown" />
              <ColHeader label="Prof. Factor" key="profit_factor" />
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr>
                <td colSpan={8} className="text-center py-8 text-gray-600">
                  Loading strategies...
                </td>
              </tr>
            )}
            {!loading && sorted.length === 0 && (
              <tr>
                <td colSpan={8} className="text-center py-8 text-gray-600">
                  No strategies tracked yet. Start the system to begin exploration.
                </td>
              </tr>
            )}
            {sorted.map((row, i) => (
              <tr key={i} className={row.is_live ? "border-l-2 border-brand" : ""}>
                <td>
                  <div className="flex items-center gap-2">
                    {i === 0 && <span title="Top performer">🏆</span>}
                    <span className="text-gray-200 font-medium">{row.strategy_name}</span>
                  </div>
                </td>
                <td className="text-brand mono">{row.symbol}</td>
                <td className="text-gray-400">{row.total_trades}</td>
                <td className={cn("font-semibold", row.win_rate >= 0.5 ? "text-profit" : "text-loss")}>
                  {formatPercent(row.win_rate)}
                </td>
                <td className={cn("font-bold", row.total_pnl >= 0 ? "text-profit" : "text-loss")}>
                  <span className="flex items-center gap-1">
                    {row.total_pnl >= 0 ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                    {formatCurrency(row.total_pnl)}
                  </span>
                </td>
                <td className="text-loss">{formatPercent(row.max_drawdown)}</td>
                <td className={cn(row.profit_factor >= 1.5 ? "text-profit" : row.profit_factor >= 1 ? "text-neutral" : "text-loss")}>
                  {row.profit_factor.toFixed(2)}x
                </td>
                <td>
                  {row.is_live
                    ? <span className="metric-pill brand text-[9px]">LIVE</span>
                    : <span className="metric-pill neutral text-[9px]">PAPER</span>
                  }
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
