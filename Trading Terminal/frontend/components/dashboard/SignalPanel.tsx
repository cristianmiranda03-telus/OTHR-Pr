"use client";
import { useTradingStore } from "@/lib/store";
import { signalColor } from "@/lib/utils";
import { Activity } from "lucide-react";

export function SignalPanel() {
  const { signals, symbols } = useTradingStore();

  return (
    <div className="card">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
          <Activity className="w-3.5 h-3.5 text-brand" /> Live Signals
        </span>
      </div>
      <div className="divide-y divide-bg-border">
        {symbols.map((sym) => {
          const sig = signals[sym];
          return (
            <div key={sym} className="flex items-center px-3 py-2.5 hover:bg-bg-surface transition-colors">
              <span className="text-xs font-medium text-gray-200 w-20 font-mono">{sym}</span>
              <span className={`text-xs font-bold w-10 mono ${signalColor(sig?.signal || "hold")}`}>
                {sig?.signal?.toUpperCase() || "—"}
              </span>
              {sig?.confidence !== undefined && (
                <div className="flex-1 mx-3">
                  <div className="h-1 bg-bg-border rounded-full overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all duration-500
                        ${sig.signal === "buy" ? "bg-profit" :
                          sig.signal === "sell" ? "bg-loss" : "bg-gray-700"}`}
                      style={{ width: `${(sig.confidence * 100).toFixed(0)}%` }}
                    />
                  </div>
                </div>
              )}
              <span className="text-[10px] text-gray-500 mono w-10 text-right">
                {sig?.confidence !== undefined
                  ? `${(sig.confidence * 100).toFixed(0)}%`
                  : "—"}
              </span>
              <span className="text-[10px] text-gray-600 mono ml-2 w-20 text-right hidden lg:block">
                {sig?.regime || "—"}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
