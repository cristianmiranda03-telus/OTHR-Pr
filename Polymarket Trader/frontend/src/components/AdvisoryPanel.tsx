"use client";
import { useEffect, useState } from "react";
import type { EventEvaluation, OpportunityEntry, PositionAdvice } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import TimeAgo from "./TimeAgo";
import clsx from "clsx";

type SubTab = "evaluations" | "advice" | "opportunities";

interface Props {
  liveEvaluations: EventEvaluation[];
  liveAdvice: PositionAdvice[];
  liveOpportunities: OpportunityEntry[];
}

const URGENCY_COLOR: Record<string, string> = {
  low: "text-gray-400",
  medium: "text-neon-yellow",
  high: "text-neon-red",
  critical: "text-neon-red animate-pulse-slow font-bold",
};

const ACTION_COLOR: Record<string, string> = {
  HOLD: "text-neon-blue",
  CLOSE: "text-neon-red",
  ADD: "text-neon-green",
  PARTIAL_CLOSE: "text-neon-yellow",
};

export default function AdvisoryPanel({ liveEvaluations, liveAdvice, liveOpportunities }: Props) {
  const [subTab, setSubTab] = useState<SubTab>("evaluations");
  const [evaluations, setEvaluations] = useState<EventEvaluation[]>([]);
  const [advice, setAdvice] = useState<PositionAdvice[]>([]);
  const [opportunities, setOpportunities] = useState<OpportunityEntry[]>([]);
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    Promise.allSettled([
      apiFetch<EventEvaluation[]>("/api/evaluations"),
      apiFetch<PositionAdvice[]>("/api/advice"),
      apiFetch<OpportunityEntry[]>("/api/opportunities"),
    ]).then(([evRes, advRes, oppRes]) => {
      if (evRes.status === "fulfilled" && evRes.value.data) setEvaluations(evRes.value.data);
      if (advRes.status === "fulfilled" && advRes.value.data) setAdvice(advRes.value.data);
      if (oppRes.status === "fulfilled" && oppRes.value.data) setOpportunities(oppRes.value.data);
    });
  }, []);

  useEffect(() => {
    if (liveEvaluations.length) {
      setEvaluations((prev) => {
        const map = new Map(prev.map((e) => [e.id, e]));
        liveEvaluations.forEach((e) => map.set(e.id, e));
        return Array.from(map.values()).sort(
          (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        );
      });
    }
  }, [liveEvaluations]);

  useEffect(() => {
    if (liveAdvice.length) {
      setAdvice((prev) => {
        const map = new Map(prev.map((a) => [a.id, a]));
        liveAdvice.forEach((a) => map.set(a.id, a));
        return Array.from(map.values()).sort(
          (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        );
      });
    }
  }, [liveAdvice]);

  useEffect(() => {
    if (liveOpportunities.length) {
      setOpportunities((prev) => {
        const map = new Map(prev.map((o) => [o.id, o]));
        liveOpportunities.forEach((o) => map.set(o.id, o));
        return Array.from(map.values()).sort((a, b) => a.priority_rank - b.priority_rank);
      });
    }
  }, [liveOpportunities]);

  const tabs: { id: SubTab; label: string; count: number; icon: string }[] = [
    { id: "evaluations", label: "Event Scenarios", count: evaluations.length, icon: "🎯" },
    { id: "advice", label: "Position Advice", count: advice.length, icon: "🛡" },
    { id: "opportunities", label: "Ranked Opportunities", count: opportunities.length, icon: "📊" },
  ];

  return (
    <div className="flex flex-col gap-4">
      {/* Sub-tabs */}
      <div className="flex gap-1">
        {tabs.map((t) => (
          <button
            key={t.id}
            onClick={() => setSubTab(t.id)}
            className={clsx(
              "flex items-center gap-1.5 text-xs px-3 py-1.5 rounded border transition-all",
              subTab === t.id
                ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                : "border-bg-border text-gray-500 hover:border-gray-500"
            )}
          >
            <span>{t.icon}</span>
            <span>{t.label}</span>
            {t.count > 0 && (
              <span className="text-[10px] font-bold text-neon-green">{t.count}</span>
            )}
          </button>
        ))}
      </div>

      {/* Event Evaluations */}
      {subTab === "evaluations" && (
        <div className="flex flex-col gap-3">
          {evaluations.length === 0 ? (
            <EmptyState text="EventEvaluator is analyzing open markets..." />
          ) : evaluations.map((ev) => (
            <div
              key={ev.id}
              className={clsx("joker-card p-4 cursor-pointer", expanded === ev.id && "border-[#BC13FE55]")}
              onClick={() => setExpanded(expanded === ev.id ? null : ev.id)}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm text-gray-200 line-clamp-2">
                    {ev.market_url ? (
                      <a href={ev.market_url} target="_blank" rel="noopener noreferrer"
                        onClick={(e) => e.stopPropagation()}
                        className="hover:text-neon-violet transition-colors">
                        {ev.market_question}
                      </a>
                    ) : ev.market_question}
                  </p>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-gray-600">{ev.category}</span>
                    <span className="text-[10px] text-gray-500">@ {ev.current_price.toFixed(3)}</span>
                    <TimeAgo date={ev.created_at} className="text-[10px] text-gray-600" />
                  </div>
                </div>
                <div className="text-right flex-shrink-0">
                  <p className="text-xs font-semibold text-neon-green">
                    {(ev.confidence * 100).toFixed(0)}% conf.
                  </p>
                  <p className="text-[10px] text-gray-500 mt-0.5">{ev.scenarios.length} scenarios</p>
                </div>
              </div>

              {ev.most_likely_outcome && (
                <p className="text-[10px] text-neon-blue mt-2">
                  Most likely: <span className="font-semibold">{ev.most_likely_outcome}</span>
                </p>
              )}

              {expanded === ev.id && (
                <div className="mt-3 border-t border-bg-border pt-3 space-y-3">
                  {ev.scenarios.map((s, i) => (
                    <div key={i} className="bg-[#1a1a1a] rounded p-3">
                      <div className="flex justify-between items-center mb-1">
                        <span className="text-xs font-semibold text-gray-200">{s.name}</span>
                        <span className={clsx("text-xs font-mono", {
                          "text-neon-green": s.impact === "positive",
                          "text-neon-red": s.impact === "negative",
                          "text-gray-400": s.impact === "neutral",
                        })}>
                          {(s.probability * 100).toFixed(0)}%
                        </span>
                      </div>
                      <p className="text-[11px] text-gray-400">{s.description}</p>
                      <div className="mt-1 h-1 bg-[#2a2a2a] rounded-full overflow-hidden">
                        <div className="h-full bg-neon-violet rounded-full" style={{ width: `${s.probability * 100}%` }} />
                      </div>
                    </div>
                  ))}
                  {ev.news_context && (
                    <div>
                      <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-1">Context Used</p>
                      <p className="text-[11px] text-gray-500 line-clamp-4">{ev.news_context}</p>
                    </div>
                  )}
                </div>
              )}
              <p className="text-[10px] text-gray-700 mt-2">
                {expanded === ev.id ? "▲ collapse" : "▼ expand scenarios"}
              </p>
            </div>
          ))}
        </div>
      )}

      {/* Position Advice */}
      {subTab === "advice" && (
        <div className="flex flex-col gap-3">
          {advice.length === 0 ? (
            <EmptyState text="PositionAdvisor is reviewing your open positions..." />
          ) : advice.map((adv) => (
            <div
              key={adv.id}
              className={clsx("joker-card p-4 cursor-pointer", expanded === adv.id && "border-[#BC13FE55]")}
              onClick={() => setExpanded(expanded === adv.id ? null : adv.id)}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm text-gray-200 line-clamp-1">{adv.market_question}</p>
                  <div className="flex items-center gap-2 mt-1 flex-wrap">
                    <span className="text-[10px] text-gray-400 font-mono">{adv.outcome}</span>
                    <span className="text-[10px] text-gray-600">
                      {adv.current_size.toFixed(1)} shares @ {adv.avg_price.toFixed(3)}
                    </span>
                    <span className={clsx("text-[10px] font-mono",
                      adv.current_pnl >= 0 ? "text-neon-green" : "text-neon-red"
                    )}>
                      {adv.current_pnl >= 0 ? "+" : ""}${adv.current_pnl.toFixed(2)}
                    </span>
                  </div>
                </div>
                <div className="flex flex-col items-end gap-1 flex-shrink-0">
                  <span className={clsx(
                    "text-sm font-bold font-title tracking-wider",
                    ACTION_COLOR[adv.recommended_action] || "text-gray-400"
                  )}>
                    {adv.recommended_action}
                  </span>
                  <span className={clsx("text-[10px]", URGENCY_COLOR[adv.urgency] || "text-gray-500")}>
                    {adv.urgency.toUpperCase()} urgency
                  </span>
                </div>
              </div>

              {adv.reasoning && (
                <p className="text-xs text-gray-400 mt-2 leading-relaxed line-clamp-2">{adv.reasoning}</p>
              )}

              {expanded === adv.id && (
                <div className="mt-3 border-t border-bg-border pt-3 space-y-3">
                  <div className="grid grid-cols-3 gap-2">
                    <MiniStat label="Risk" value={adv.risk_level.toUpperCase()}
                      color={adv.risk_level === "high" ? "text-neon-red" : adv.risk_level === "low" ? "text-neon-green" : "text-neon-yellow"} />
                    <MiniStat label="Hold" value={adv.hold_duration || "N/A"} color="text-gray-300" />
                    <MiniStat label="Price" value={`${adv.avg_price.toFixed(3)} → ${adv.current_price.toFixed(3)}`} color="text-gray-300" />
                  </div>
                  {adv.scenarios.length > 0 && (
                    <div>
                      <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-2">Scenarios</p>
                      {adv.scenarios.map((s, i) => (
                        <div key={i} className="flex items-center gap-2 mb-1">
                          <span className={clsx("w-2 h-2 rounded-full flex-shrink-0", {
                            "bg-neon-green": s.impact === "positive",
                            "bg-neon-red": s.impact === "negative",
                            "bg-gray-500": s.impact === "neutral",
                          })} />
                          <span className="text-[11px] text-gray-300 flex-1">{s.name}: {s.description}</span>
                          <span className="text-[10px] font-mono text-gray-500">{(s.probability * 100).toFixed(0)}%</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
              <p className="text-[10px] text-gray-700 mt-2">
                {expanded === adv.id ? "▲ collapse" : "▼ expand details"}
              </p>
            </div>
          ))}
        </div>
      )}

      {/* Opportunity Rankings */}
      {subTab === "opportunities" && (
        <div className="flex flex-col gap-3">
          {opportunities.length === 0 ? (
            <EmptyState text="OpportunityOptimizer is ranking potential trades..." />
          ) : opportunities.map((opp) => (
            <div key={opp.id} className="joker-card p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-start gap-3 min-w-0">
                  <span className={clsx(
                    "text-lg font-title font-bold w-8 text-center flex-shrink-0",
                    opp.priority_rank <= 3 ? "text-neon-green" : "text-gray-500"
                  )}>
                    #{opp.priority_rank}
                  </span>
                  <div className="min-w-0">
                    <p className="text-sm text-gray-200 line-clamp-1">
                      {opp.market_url ? (
                        <a href={opp.market_url} target="_blank" rel="noopener noreferrer"
                          className="hover:text-neon-violet transition-colors">
                          {opp.market_question}
                        </a>
                      ) : opp.market_question}
                    </p>
                    <div className="flex items-center gap-2 mt-1 flex-wrap">
                      <span className={clsx(
                        "text-[10px] font-bold",
                        opp.direction === "BUY" ? "text-neon-green" : "text-neon-red"
                      )}>
                        {opp.direction}
                      </span>
                      <span className="text-[10px] text-gray-500">@ {opp.current_price.toFixed(3)}</span>
                      <span className="text-[10px] text-gray-500">conf: {(opp.confidence * 100).toFixed(0)}%</span>
                    </div>
                  </div>
                </div>
                <div className="text-right flex-shrink-0">
                  <p className={clsx("text-sm font-mono font-semibold",
                    opp.expected_return_pct > 0 ? "text-neon-green" : "text-neon-red"
                  )}>
                    {opp.expected_return_pct > 0 ? "+" : ""}{opp.expected_return_pct.toFixed(1)}%
                  </p>
                  <p className="text-[10px] text-gray-500">
                    ${opp.recommended_size_usdc.toFixed(0)} suggested
                  </p>
                </div>
              </div>

              {opp.opportunity_cost_note && (
                <p className="text-[11px] text-gray-500 mt-2 leading-relaxed">
                  <span className="text-neon-violet">▸</span> {opp.opportunity_cost_note}
                </p>
              )}

              {opp.reasoning && (
                <p className="text-[11px] text-gray-600 mt-1">{opp.reasoning}</p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="joker-card p-8 text-center">
      <p className="text-gray-600 text-sm">{text}</p>
      <p className="text-[10px] text-gray-700 mt-2 font-mono">[agent working in background]</p>
    </div>
  );
}

function MiniStat({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="bg-[#1a1a1a] rounded p-2 text-center">
      <p className="text-[10px] text-gray-600">{label}</p>
      <p className={clsx("text-xs font-semibold", color)}>{value}</p>
    </div>
  );
}
