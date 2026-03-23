"use client";
import { useTradingStore } from "@/lib/store";
import { cn, formatCurrency } from "@/lib/utils";
import { Wifi, WifiOff, TrendingUp } from "lucide-react";

export function Header() {
  const { running, mode, account, agentStatuses } = useTradingStore();
  const activeAgents = Object.values(agentStatuses).filter(
    (a) => a.status === "running" || a.status === "thinking"
  ).length;
  const totalAgents  = Object.keys(agentStatuses).length || 8;
  const dailyPnl     = account?.profit || 0;

  return (
    <header className="sticky top-0 z-50 flex items-center gap-3 px-4 py-2.5 bg-bg-surface border-b border-bg-border h-12">
      {/* Logo */}
      <div className="flex items-center gap-2 shrink-0">
        <div className="w-6 h-6 rounded-md bg-brand/20 border border-brand/30 flex items-center justify-center">
          <TrendingUp className="w-3.5 h-3.5 text-brand" />
        </div>
        <span className="text-sm font-bold text-gray-100 tracking-tight">Trading Terminal</span>
        <span className="text-[9px] px-1.5 py-0.5 rounded bg-brand/15 text-brand border border-brand/25 mono font-semibold">
          AI
        </span>
      </div>

      <div className="w-px h-4 bg-bg-border mx-1" />

      {/* Live / Paper badge */}
      <div className={cn(
        "flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-bold mono",
        running && mode === "live"
          ? "bg-loss/15 text-loss border border-loss/30"
          : running
          ? "bg-profit/10 text-profit border border-profit/20"
          : "bg-bg-raised text-gray-600 border border-bg-border"
      )}>
        <span className={cn(
          "w-1.5 h-1.5 rounded-full",
          running && mode === "live" ? "bg-loss animate-pulse" :
          running ? "bg-profit animate-pulse" : "bg-gray-700"
        )} />
        {running ? (mode === "live" ? "LIVE" : "PAPER") : "STOPPED"}
      </div>

      {/* Agents counter */}
      {running && (
        <span className="text-[10px] mono text-gray-500">
          <span className="text-brand">{activeAgents}</span>
          <span>/{totalAgents}</span>
          <span className="ml-0.5">agents</span>
        </span>
      )}

      <div className="flex-1" />

      {/* Account P/L quick view */}
      {account && (
        <div className="flex items-center gap-4 text-[11px] mono">
          <div className="hidden sm:flex flex-col items-end">
            <span className="text-[9px] text-gray-600 uppercase tracking-wider">Balance</span>
            <span className="text-gray-300 font-semibold">{formatCurrency(account.balance)}</span>
          </div>
          <div className="flex flex-col items-end">
            <span className="text-[9px] text-gray-600 uppercase tracking-wider">Equity</span>
            <span className="text-gray-200 font-semibold">{formatCurrency(account.equity)}</span>
          </div>
          <div className="flex flex-col items-end">
            <span className="text-[9px] text-gray-600 uppercase tracking-wider">Open P/L</span>
            <span className={cn("font-bold", dailyPnl >= 0 ? "text-profit" : "text-loss")}>
              {dailyPnl >= 0 ? "+" : ""}{formatCurrency(dailyPnl)}
            </span>
          </div>
        </div>
      )}

      <div className="w-px h-4 bg-bg-border mx-1" />

      {/* Connection dot */}
      <div className="flex items-center gap-1.5 text-[10px] mono">
        {running ? (
          <Wifi className="w-3.5 h-3.5 text-profit" />
        ) : (
          <WifiOff className="w-3.5 h-3.5 text-gray-700" />
        )}
        <span className={running ? "text-profit" : "text-gray-600"}>
          {running ? "CONNECTED" : "OFFLINE"}
        </span>
      </div>
    </header>
  );
}
