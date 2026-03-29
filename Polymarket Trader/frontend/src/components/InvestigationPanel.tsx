"use client";
import { useEffect, useState } from "react";
import type { Investigation } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import TimeAgo from "./TimeAgo";
import clsx from "clsx";

const CATEGORY_ICONS: Record<string, string> = {
  politics: "🏛", crypto: "₿", sports: "⚽", science: "🔬",
  strategy_scout: "🕵", whale_watcher: "🐋", orchestrator: "♠",
  event_evaluator: "🎯", strategy_evaluator: "⚖", position_advisor: "🛡",
  entry_analyst: "🔎", opportunity_optimizer: "📊",
};

const STATUS_COLOR: Record<string, string> = {
  analyzing: "text-neon-blue animate-pulse-slow",
  complete:  "text-neon-green",
  skipped:   "text-gray-500",
  error:     "text-neon-red",
};

interface Props {
  liveInvestigations: Investigation[];
}

export default function InvestigationPanel({ liveInvestigations }: Props) {
  const [investigations, setInvestigations] = useState<Investigation[]>([]);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [filter, setFilter] = useState<string>("all");

  useEffect(() => {
    apiFetch<Investigation[]>("/api/investigations?limit=100")
      .then((r) => { if (r.data) setInvestigations(r.data); })
      .catch(() => {});
  }, []);

  // Merge live updates
  useEffect(() => {
    if (!liveInvestigations.length) return;
    setInvestigations((prev) => {
      const map = new Map(prev.map((i) => [i.id, i]));
      liveInvestigations.forEach((i) => map.set(i.id, i));
      return Array.from(map.values()).sort(
        (a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime()
      );
    });
  }, [liveInvestigations]);

  const filters = ["all", "analyzing", "complete", "skipped", "error"];
  const visible = investigations.filter(
    (i) => filter === "all" || i.status === filter
  );

  const analyzingCount = investigations.filter((i) => i.status === "analyzing").length;
  const completeCount  = investigations.filter((i) => i.status === "complete").length;

  return (
    <div className="flex flex-col gap-4 h-full">
      {/* Stats */}
      <div className="grid grid-cols-4 gap-2">
        {[
          { label: "Total", value: investigations.length, color: "text-white" },
          { label: "Analyzing", value: analyzingCount, color: "text-neon-blue" },
          { label: "Complete", value: completeCount, color: "text-neon-green" },
          { label: "Skipped", value: investigations.filter((i) => i.status === "skipped").length, color: "text-gray-500" },
        ].map((stat) => (
          <div key={stat.label} className="joker-card p-3 text-center">
            <p className={clsx("font-mono font-bold text-xl", stat.color)}>{stat.value}</p>
            <p className="text-[10px] text-gray-600 uppercase tracking-widest mt-0.5">{stat.label}</p>
          </div>
        ))}
      </div>

      {/* Filters */}
      <div className="flex gap-1 flex-wrap">
        {filters.map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={clsx(
              "text-xs px-3 py-1 rounded border transition-all capitalize",
              filter === f
                ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                : "border-bg-border text-gray-500 hover:border-gray-500"
            )}
          >
            {f}
          </button>
        ))}
      </div>

      {/* Investigation list */}
      <div className="flex flex-col gap-2 overflow-y-auto pr-1 flex-1">
        {visible.length === 0 && (
          <div className="joker-card p-8 text-center">
            <p className="text-gray-600 text-sm">
              {filter === "all"
                ? "No investigations yet. Agents will start scanning markets shortly..."
                : `No ${filter} investigations.`}
            </p>
          </div>
        )}
        {visible.map((inv) => (
          <div
            key={inv.id}
            className={clsx(
              "joker-card p-3 cursor-pointer",
              expanded === inv.id && "border-[#BC13FE55]"
            )}
            onClick={() => setExpanded(expanded === inv.id ? null : inv.id)}
          >
            {/* Row */}
            <div className="flex items-start gap-2">
              <span className="text-base mt-0.5 flex-shrink-0">
                {CATEGORY_ICONS[inv.category] ?? "◈"}
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-xs text-gray-200 line-clamp-1">{inv.market_question}</p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-[10px] text-gray-600">{inv.agent_name}</span>
                  <span className="text-[10px] text-gray-600">•</span>
                  <span className="text-[10px] font-mono text-gray-500">
                    @ {inv.price_at_analysis.toFixed(3)}
                  </span>
                  {inv.direction_found && (
                    <span className={clsx(
                      "text-[10px] font-bold",
                      inv.direction_found === "BUY" ? "text-neon-green" : "text-neon-red"
                    )}>
                      → {inv.direction_found}
                    </span>
                  )}
                </div>
              </div>
              <div className="flex-shrink-0 text-right">
                <span className={clsx("text-[10px] font-semibold uppercase", STATUS_COLOR[inv.status])}>
                  {inv.status === "analyzing" ? "⟳ " : ""}{inv.status}
                </span>
                <TimeAgo date={inv.started_at} className="block text-[10px] text-gray-600 mt-0.5" />
              </div>
            </div>

            {/* Expanded details */}
            {expanded === inv.id && (
              <div className="mt-3 border-t border-bg-border pt-3 space-y-3">
                {inv.conclusion && (
                  <div>
                    <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-1">Conclusion</p>
                    <p className="text-xs text-gray-300">{inv.conclusion}</p>
                  </div>
                )}
                {inv.sentiment && (
                  <div>
                    <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-1">Sentiment Analysis</p>
                    <div className="grid grid-cols-2 gap-2">
                      <div className="bg-[#1a1a1a] rounded p-2">
                        <p className="text-[10px] text-gray-600">Sentiment</p>
                        <p className={clsx("text-sm font-semibold capitalize", {
                          "text-neon-green": inv.sentiment.sentiment === "bullish",
                          "text-neon-red":   inv.sentiment.sentiment === "bearish",
                          "text-gray-400":   inv.sentiment.sentiment === "neutral",
                        })}>
                          {inv.sentiment.sentiment}
                        </p>
                      </div>
                      <div className="bg-[#1a1a1a] rounded p-2">
                        <p className="text-[10px] text-gray-600">Confidence</p>
                        <p className="text-sm font-semibold text-white">
                          {(inv.sentiment.confidence * 100).toFixed(0)}%
                        </p>
                      </div>
                    </div>
                    {inv.sentiment.reasoning && (
                      <p className="text-xs text-gray-400 mt-2 leading-relaxed">
                        {inv.sentiment.reasoning}
                      </p>
                    )}
                    {inv.sentiment.key_factors?.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-2">
                        {inv.sentiment.key_factors.map((f, i) => (
                          <span key={i} className="text-[10px] px-2 py-0.5 bg-[#2a2a2a] rounded text-gray-400">
                            {f}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                )}
                {inv.news_summary && (
                  <div>
                    <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-1">Context Used</p>
                    <p className="text-[11px] text-gray-500 leading-relaxed line-clamp-4">
                      {inv.news_summary}
                    </p>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
