"use client";
import { useState } from "react";
import { useTradingStore } from "@/lib/store";
import { api } from "@/lib/ws";
import { Check, X, ChevronDown, ChevronRight, Activity } from "lucide-react";
import { cn, formatCurrency } from "@/lib/utils";
import toast from "react-hot-toast";

const CONFIDENCE_LEVEL = (c: number) =>
  c >= 0.75 ? "High" : c >= 0.55 ? "Moderate" : "Low";

const CONFIDENCE_COLOR = (c: number) =>
  c >= 0.75 ? "var(--profit)" : c >= 0.55 ? "var(--neutral)" : "var(--loss)";

export function SignalsTab() {
  const { signals, symbols, account, selectedSymbol, setSelectedSymbol } = useTradingStore();
  const [expanded, setExpanded] = useState<string | null>(null);
  const [filter, setFilter] = useState<"all" | "buy" | "sell">("all");

  const entries = symbols.map((sym) => ({ sym, data: signals[sym] }))
    .filter((e) => e.data && e.data.signal !== "hold")
    .filter((e) => filter === "all" || e.data?.signal === filter);

  const handleManualOrder = async (sym: string, type: string) => {
    try {
      const result = await api.post("/api/orders/market", {
        symbol: sym, order_type: type, volume: 0.01, comment: "Manual-UI",
      });
      if (result.success) {
        toast.success(`Manual ${type.toUpperCase()} ${sym} sent`);
      } else {
        toast.error(`Order failed: ${result.error || result.comment}`);
      }
    } catch {
      toast.error("Order request failed");
    }
  };

  return (
    <div className="space-y-3">
      {/* Header bar */}
      <div className="flex items-center justify-between card px-4 py-3">
        <div className="flex items-center gap-2">
          <Activity className="w-4 h-4 text-brand" />
          <span className="text-sm font-semibold text-gray-200">
            {entries.length} active signals
          </span>
          <span className="text-xs text-gray-600">sorted by confidence</span>
        </div>
        <div className="flex items-center gap-2">
          {/* Filter buttons */}
          {(["all", "buy", "sell"] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={cn(
                "px-3 py-1 rounded-full text-[10px] font-semibold uppercase mono transition-all",
                filter === f
                  ? f === "buy"
                    ? "bg-profit/20 text-profit border border-profit/30"
                    : f === "sell"
                    ? "bg-loss/20 text-loss border border-loss/30"
                    : "bg-brand/20 text-brand border border-brand/30"
                  : "bg-bg-surface text-gray-600 border border-bg-border hover:text-gray-400"
              )}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      {/* No signals state */}
      {entries.length === 0 && (
        <div className="card p-12 text-center">
          <Activity className="w-8 h-8 text-gray-700 mx-auto mb-3" />
          <p className="text-gray-600 text-sm">No active signals</p>
          <p className="text-gray-700 text-xs mt-1">Start the system to generate signals</p>
        </div>
      )}

      {/* Signal cards grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {entries
          .sort((a, b) => (b.data?.confidence || 0) - (a.data?.confidence || 0))
          .map(({ sym, data }) => {
            if (!data) return null;
            const conf = data.confidence || 0;
            const isBuy = data.signal === "buy";
            const isExpanded = expanded === sym;
            const confLevel = CONFIDENCE_LEVEL(conf);
            const confColor = CONFIDENCE_COLOR(conf);
            const ind = data.indicators || {};

            return (
              <div
                key={sym}
                className={cn("signal-card", data.signal)}
              >
                {/* Card header */}
                <div className="flex items-center justify-between px-4 py-3 border-b border-bg-border">
                  <div className="flex items-center gap-3">
                    <span className="text-base font-bold text-gray-100 mono">{sym}</span>
                    <span className={cn(
                      "metric-pill text-[10px] font-bold",
                      isBuy ? "profit" : "loss"
                    )}>
                      {data.signal.toUpperCase()}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[10px] text-gray-600 mono">{data.regime}</span>
                    <span className={cn(
                      "text-[10px] px-2 py-0.5 rounded-full border mono",
                      conf >= 0.75
                        ? "bg-profit/10 text-profit border-profit/20"
                        : conf >= 0.55
                        ? "bg-neutral/10 text-neutral border-neutral/20"
                        : "bg-loss/10 text-loss border-loss/20"
                    )}>
                      {confLevel}
                    </span>
                  </div>
                </div>

                {/* Card body */}
                <div className="px-4 py-3 space-y-3">
                  {/* Price action line */}
                  <p className="text-[11px] text-gray-400 leading-relaxed">
                    <span className={cn("font-bold text-xs", isBuy ? "text-profit" : "text-loss")}>
                      {data.signal.toUpperCase()}
                    </span>{" "}
                    signal on <span className="text-gray-200">{sym}</span>.
                    AI confidence: <span style={{ color: confColor }}>{(conf * 100).toFixed(0)}%</span>.
                    Market regime: <span className="text-gray-300">{data.regime}</span>.
                  </p>

                  {/* Confidence bar */}
                  <div>
                    <div className="flex justify-between items-center mb-1">
                      <span className="text-[10px] text-gray-600 mono">Confidence</span>
                      <span className="text-[10px] font-semibold mono" style={{ color: confColor }}>
                        {confLevel} — {(conf * 100).toFixed(0)}%
                      </span>
                    </div>
                    <div className="confidence-bar">
                      <div
                        className={cn("confidence-bar-fill",
                          conf >= 0.75 ? "high" : conf >= 0.55 ? "medium" : "low")}
                        style={{ width: `${conf * 100}%` }}
                      />
                    </div>
                  </div>

                  {/* Indicators mini row */}
                  <div className="flex flex-wrap gap-1.5">
                    {ind.rsi !== undefined && (
                      <span className="metric-pill neutral text-[9px]">
                        RSI {ind.rsi?.toFixed(1)}
                      </span>
                    )}
                    {ind.atr !== undefined && (
                      <span className="metric-pill cyan text-[9px]">
                        ATR {ind.atr?.toFixed(5)}
                      </span>
                    )}
                    {ind.stoch_k !== undefined && (
                      <span className="metric-pill brand text-[9px]">
                        Stoch {ind.stoch_k?.toFixed(0)}
                      </span>
                    )}
                  </div>

                  {/* Expandable indicator detail */}
                  <button
                    onClick={() => setExpanded(isExpanded ? null : sym)}
                    className="flex items-center gap-1 text-[10px] text-brand/70 hover:text-brand transition-colors"
                  >
                    {isExpanded ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                    Show agent analysis
                  </button>
                  {isExpanded && (
                    <div className="bg-bg-surface rounded-lg p-3 space-y-1.5 text-[10px] mono animate-slide-up">
                      <div className="grid grid-cols-2 gap-x-4 gap-y-1">
                        {Object.entries(ind).map(([k, v]) => (
                          <div key={k} className="flex justify-between">
                            <span className="text-gray-600">{k}</span>
                            <span className="text-gray-300">{typeof v === "number" ? v.toFixed(5) : String(v)}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                {/* Action buttons */}
                <div className="grid grid-cols-2 gap-0 border-t border-bg-border">
                  <button
                    onClick={() => handleManualOrder(sym, data.signal)}
                    className="btn btn-approve rounded-none rounded-bl-lg justify-center py-3"
                  >
                    <Check className="w-3.5 h-3.5" /> APPROVE
                  </button>
                  <button
                    onClick={() => toast(`Signal ${sym} rejected`, { icon: "🚫" })}
                    className="btn btn-reject rounded-none rounded-br-lg justify-center py-3 border-l border-bg-border"
                  >
                    <X className="w-3.5 h-3.5" /> REJECT
                  </button>
                </div>
              </div>
            );
          })}
      </div>
    </div>
  );
}
