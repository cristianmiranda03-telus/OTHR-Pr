"use client";
import { useEffect, useState } from "react";
import { useTradingStore } from "@/lib/store";
import { Clock } from "lucide-react";

const SESSION_INFO = {
  tse:    { label: "TOKYO",    flag: "🇯🇵", color: "text-blue-400" },
  lse:    { label: "LONDON",   flag: "🇬🇧", color: "text-neutral" },
  nyse:   { label: "NEW YORK", flag: "🇺🇸", color: "text-profit" },
  forex_london_ny_overlap: { label: "LDN-NY", flag: "🔥", color: "text-brand" },
};

export function SessionPanel() {
  const { session, signals, symbols } = useTradingStore();
  const [time, setTime] = useState("");

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      setTime(now.toUTCString().split(" ").slice(4, 5)[0] + " UTC");
    };
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, []);

  const activeSessions = session?.active_sessions || [];
  const isOverlap = session?.overlap_active;

  return (
    <div className="card">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
          <Clock className="w-3.5 h-3.5 text-brand" /> Sessions
        </span>
        <span className="mono text-xs text-gray-400">{time}</span>
      </div>
      <div className="p-3 space-y-2">
        {/* Overlap banner */}
        {isOverlap && (
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-brand/10 border border-brand/20">
            <span className="text-brand animate-pulse-slow text-sm">🔥</span>
            <span className="text-xs font-semibold text-brand">
              LONDON-NY OVERLAP ACTIVE - Peak Volatility
            </span>
          </div>
        )}

        {/* Session bars */}
        <div className="grid grid-cols-2 gap-2">
          {Object.entries(SESSION_INFO).filter(([k]) => k !== "forex_london_ny_overlap").map(([key, info]) => {
            const isActive = activeSessions.includes(key);
            const isPeak = session?.peak_sessions?.includes(key);
            return (
              <div key={key}
                className={`flex items-center gap-2 px-3 py-2 rounded-lg transition-colors
                  ${isActive ? "bg-bg-raised border border-bg-border" : "bg-bg-surface opacity-40"}`}>
                <span className="text-base">{info.flag}</span>
                <div>
                  <p className={`text-xs font-semibold ${isActive ? info.color : "text-gray-600"}`}>
                    {info.label}
                    {isPeak && <span className="text-brand ml-1 text-[10px]">PEAK</span>}
                  </p>
                  <p className="text-[10px] text-gray-600">
                    {isActive ? "OPEN" : "CLOSED"}
                  </p>
                </div>
                {isActive && (
                  <div className="ml-auto">
                    <span className="status-dot active w-2 h-2" />
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* Symbol scores */}
        <div className="pt-1">
          <p className="text-[10px] text-gray-600 uppercase tracking-wider mb-1.5">
            Scalp Score by Symbol
          </p>
          <div className="space-y-1">
            {symbols.slice(0, 4).map((sym) => {
              const sigData = signals[sym];
              const score = 50; // Would come from API
              return (
                <div key={sym} className="flex items-center gap-2">
                  <span className="text-[11px] mono text-gray-400 w-16">{sym}</span>
                  <div className="flex-1 h-1.5 bg-bg-border rounded-full overflow-hidden">
                    <div
                      className="h-full rounded-full bg-gradient-to-r from-brand/50 to-brand transition-all duration-1000"
                      style={{ width: `${score}%` }}
                    />
                  </div>
                  <span className="text-[10px] mono text-gray-600 w-8 text-right">{score}</span>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
