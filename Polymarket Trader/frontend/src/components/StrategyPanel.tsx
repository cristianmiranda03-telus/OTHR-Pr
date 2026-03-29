"use client";
import { useEffect, useState } from "react";
import type { StrategyReport } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import TimeAgo from "./TimeAgo";
import clsx from "clsx";

const DIFFICULTY_STYLE: Record<string, string> = {
  easy:   "text-neon-green border-neon-green",
  medium: "text-neon-yellow border-[#FFE000]",
  hard:   "text-neon-red border-neon-red",
};

const DIFFICULTY_LABEL: Record<string, string> = {
  easy:   "Beginner",
  medium: "Intermediate",
  hard:   "Advanced",
};

interface Props {
  liveReports: StrategyReport[];
}

export default function StrategyPanel({ liveReports }: Props) {
  const [reports, setReports] = useState<StrategyReport[]>([]);
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<StrategyReport[]>("/api/strategies")
      .then((r) => { if (r.data) setReports(r.data); })
      .catch(() => {});
  }, []);

  // Merge live updates
  useEffect(() => {
    if (!liveReports.length) return;
    setReports((prev) => {
      const map = new Map(prev.map((r) => [r.id, r]));
      liveReports.forEach((r) => map.set(r.id, r));
      return Array.from(map.values()).sort(
        (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      );
    });
  }, [liveReports]);

  return (
    <div className="flex flex-col gap-4 h-full">
      {/* Header info */}
      <div className="joker-card p-3 border-l-2 border-neon-violet">
        <p className="text-xs text-gray-400">
          The <span className="text-neon-violet">StrategyScoutAgent</span> continuously researches
          trading methods from academic papers, trading forums and market documentation.
          Reports below represent discovered patterns you can apply to your trading.
        </p>
      </div>

      {reports.length === 0 && (
        <div className="joker-card p-8 text-center">
          <p className="text-gray-600 text-sm">
            Strategy Scout is gathering intelligence...
          </p>
          <p className="text-[10px] text-gray-700 mt-2 font-mono">
            [researching prediction market strategies]
          </p>
        </div>
      )}

      <div className="flex flex-col gap-3 overflow-y-auto pr-1 flex-1">
        {reports.map((report) => (
          <div
            key={report.id}
            className={clsx(
              "joker-card p-4 cursor-pointer",
              expanded === report.id && "border-[#BC13FE55]"
            )}
            onClick={() => setExpanded(expanded === report.id ? null : report.id)}
          >
            {/* Header */}
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-sm text-gray-200 font-semibold leading-snug">
                  {report.title}
                </p>
                <p className="text-[10px] text-gray-600 mt-1">
                  <TimeAgo date={report.created_at} />
                  {report.source && ` · ${report.source.slice(0, 50)}`}
                </p>
              </div>
              <span className={clsx(
                "badge flex-shrink-0 border text-[10px]",
                DIFFICULTY_STYLE[report.difficulty] ?? DIFFICULTY_STYLE.medium
              )}>
                {DIFFICULTY_LABEL[report.difficulty] ?? report.difficulty}
              </span>
            </div>

            {/* Summary always visible */}
            {report.summary && (
              <p className="text-xs text-gray-400 mt-2 leading-relaxed line-clamp-2">
                {report.summary}
              </p>
            )}

            {/* Expanded: insights */}
            {expanded === report.id && (
              <div className="mt-3 border-t border-bg-border pt-3">
                {report.summary && (
                  <div className="mb-3">
                    <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-1">Full Summary</p>
                    <p className="text-xs text-gray-400 leading-relaxed">{report.summary}</p>
                  </div>
                )}
                {report.actionable_insights.length > 0 && (
                  <div>
                    <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-2">
                      Actionable Insights
                    </p>
                    <ul className="space-y-2">
                      {report.actionable_insights.map((insight, i) => (
                        <li key={i} className="flex gap-2">
                          <span className="text-neon-violet flex-shrink-0 mt-0.5">▸</span>
                          <span className="text-xs text-gray-300 leading-relaxed">{insight}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </div>
            )}

            {/* Collapse hint */}
            <p className="text-[10px] text-gray-700 mt-2">
              {expanded === report.id ? "▲ collapse" : "▼ expand insights"}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
