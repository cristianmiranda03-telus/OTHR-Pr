"use client";
import { useRef, useEffect } from "react";
import { useTradingStore } from "@/lib/store";
import { Terminal } from "lucide-react";

const LOG_COLORS: Record<string, string> = {
  info:     "text-gray-400",
  warning:  "text-neutral",
  error:    "text-loss",
  critical: "text-loss font-bold",
  debug:    "text-gray-600",
};

const AGENT_COLORS: Record<string, string> = {
  Orchestrator:    "text-brand",
  TechnicalAnalyst:"text-profit/80",
  NewsSentinel:    "text-neutral/80",
  RiskManager:     "text-loss/80",
  MT5Executor:     "text-blue-400",
  MemoryAgent:     "text-purple-400",
  ExplorerAgent:   "text-cyan-400",
  DataCleaner:     "text-gray-400",
  System:          "text-gray-500",
};

export function ActivityLog({ maxHeight = "300px" }: { maxHeight?: string }) {
  const { agentLogs } = useTradingStore();
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [agentLogs.length]);

  return (
    <div className="card overflow-hidden">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
          <Terminal className="w-3.5 h-3.5 text-brand" /> Activity Log
        </span>
        <span className="text-[10px] mono text-gray-600">{agentLogs.length} entries</span>
      </div>
      <div
        className="overflow-y-auto font-mono text-[11px] p-2"
        style={{ maxHeight, minHeight: "120px" }}
      >
        {agentLogs.length === 0 && (
          <p className="text-gray-700 p-2">Waiting for system events...</p>
        )}
        {agentLogs.map((log, i) => (
          <div key={i}
            className="flex gap-2 py-0.5 hover:bg-bg-surface px-1 rounded transition-colors group">
            <span className="text-gray-700 flex-shrink-0 text-[10px]">
              {log.time ? new Date(log.time).toLocaleTimeString("en-US", { hour12: false }) : ""}
            </span>
            <span className={`flex-shrink-0 w-28 truncate ${AGENT_COLORS[log.agent] || "text-gray-500"}`}>
              [{log.agent}]
            </span>
            <span className={LOG_COLORS[log.level] || "text-gray-400"}>
              {log.message}
            </span>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
