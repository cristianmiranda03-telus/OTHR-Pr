"use client";
import { useTradingStore } from "@/lib/store";
import { BarChart2, Target, TrendingDown, Zap } from "lucide-react";

export function StatsPanel() {
  const { stats } = useTradingStore();
  const risk = stats?.risk_stats;

  const items = [
    { label: "Total Cycles",  value: stats?.total_cycles || 0,            icon: Zap,         color: "text-brand" },
    { label: "Signals Found", value: stats?.signals_found || 0,           icon: Target,       color: "text-neutral" },
    { label: "Trades Opened", value: stats?.trades_opened || 0,           icon: BarChart2,    color: "text-profit" },
    { label: "Vetoed",        value: stats?.trades_vetoed || 0,           icon: TrendingDown, color: "text-loss" },
  ];

  return (
    <div className="card">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
          <BarChart2 className="w-3.5 h-3.5 text-brand" /> System Stats
        </span>
      </div>
      <div className="p-3 grid grid-cols-2 gap-2">
        {items.map((item) => (
          <div key={item.label}
            className="bg-bg-surface rounded-lg px-3 py-2.5">
            <div className="flex items-center gap-1.5 mb-1">
              <item.icon className={`w-3 h-3 ${item.color}`} />
              <span className="text-[10px] text-gray-600 uppercase tracking-wider">{item.label}</span>
            </div>
            <p className={`text-xl font-bold mono ${item.color}`}>{item.value.toLocaleString()}</p>
          </div>
        ))}
      </div>

      {/* Risk stats */}
      {risk && (
        <div className="border-t border-bg-border p-3">
          <p className="text-[10px] text-gray-600 uppercase tracking-wider mb-2">Risk Metrics</p>
          <div className="grid grid-cols-3 gap-2 text-center">
            <div>
              <p className="text-[10px] text-gray-600">Win Rate</p>
              <p className={`text-sm font-bold mono ${risk.win_rate >= 50 ? "text-profit" : "text-loss"}`}>
                {risk.win_rate.toFixed(1)}%
              </p>
            </div>
            <div>
              <p className="text-[10px] text-gray-600">Avg P/L</p>
              <p className={`text-sm font-bold mono ${risk.avg_profit >= 0 ? "text-profit" : "text-loss"}`}>
                ${risk.avg_profit.toFixed(2)}
              </p>
            </div>
            <div>
              <p className="text-[10px] text-gray-600">Trading</p>
              <p className={`text-sm font-bold mono ${risk.trading_enabled ? "text-profit" : "text-loss"}`}>
                {risk.trading_enabled ? "ON" : "OFF"}
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
