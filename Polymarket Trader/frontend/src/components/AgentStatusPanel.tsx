"use client";
import { useEffect, useRef, useState } from "react";
import type { AgentInfo, AgentLog } from "@/types";
import TimeAgo from "./TimeAgo";
import clsx from "clsx";

const CATEGORY_ICONS: Record<string, string> = {
  orchestrator:           "♠",
  politics:               "🏛",
  crypto:                 "₿",
  sports:                 "⚽",
  science:                "🔬",
  strategy_scout:         "🕵",
  whale_watcher:          "🐋",
  event_evaluator:        "🎯",
  strategy_evaluator:     "⚖",
  position_advisor:       "🛡",
  entry_analyst:          "🔎",
  opportunity_optimizer:  "📊",
};

const STATUS_BADGE: Record<string, string> = {
  idle:             "badge-idle",
  running:          "badge-running",
  investigating:    "badge-investigating",
  suggestion_ready: "badge-ready",
  error:            "badge-error",
};

const STATUS_LABEL: Record<string, string> = {
  idle:             "Idle",
  running:          "Running",
  investigating:    "Analyzing",
  suggestion_ready: "Signal ready",
  error:            "Error",
};

interface Props {
  agents: AgentInfo[];
  logs: AgentLog[];
}

export default function AgentStatusPanel({ agents, logs }: Props) {
  const logEndRef = useRef<HTMLDivElement>(null);
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

  const logsForAgent = (agentId: string) =>
    logs.filter((l) => l.agent_id === agentId).slice(-5);

  return (
    <section className="flex flex-col gap-4">
      {/* Agent cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        {agents.length === 0 && (
          <p className="text-xs text-gray-600 text-center py-4">
            Waiting for agents to initialise...
          </p>
        )}
        {agents.map((agent) => (
          <div
            key={agent.id}
            className={clsx(
              "border border-bg-border rounded p-3 cursor-pointer transition-all",
              expanded === agent.id
                ? "border-neon-violet bg-[#1a1a2a]"
                : "hover:border-[#BC13FE44]"
            )}
            onClick={() => setExpanded(expanded === agent.id ? null : agent.id)}
          >
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <span className="text-lg w-6 flex-shrink-0">
                  {CATEGORY_ICONS[agent.category] ?? "◈"}
                </span>
                <div className="min-w-0">
                  <p className="font-mono text-sm text-gray-200 truncate">{agent.name}</p>
                  {agent.current_task && (
                    <p className="text-xs text-gray-500 truncate mt-0.5">
                      {agent.current_task}
                    </p>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                {agent.suggestions_generated > 0 && (
                  <span className="text-xs text-neon-green font-mono">
                    +{agent.suggestions_generated}
                  </span>
                )}
                <span className={clsx("badge", STATUS_BADGE[agent.status] ?? "badge-idle")}>
                  {agent.status === "investigating" && (
                    <span className="animate-pulse-slow">●</span>
                  )}
                  {STATUS_LABEL[agent.status] ?? agent.status}
                </span>
              </div>
            </div>

            {/* Expanded log section */}
            {expanded === agent.id && (
              <div className="mt-3 border-t border-bg-border pt-3 space-y-1">
                <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-2">
                  Recent Activity
                </p>
                {logsForAgent(agent.id).length === 0 ? (
                  <p className="text-xs text-gray-600">No activity yet.</p>
                ) : (
                  logsForAgent(agent.id).map((log, i) => (
                    <div
                      key={i}
                      className={clsx(
                        "log-entry",
                        log.level === "error"
                          ? "log-error"
                          : log.level === "warning"
                          ? "log-warning"
                          : "log-info"
                      )}
                    >
                      <TimeAgo date={log.timestamp} mode="clock" className="text-gray-600" />{" "}
                      {log.message}
                    </div>
                  ))
                )}
                {agent.last_active && (
                  <p className="text-[10px] text-gray-600 mt-2">
                    Last active: <TimeAgo date={agent.last_active} />
                  </p>
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Global log stream */}
      <div className="border-t border-bg-border pt-3 mt-2">
        <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-2">
          Live Log Stream
        </p>
        <div className="h-64 overflow-y-auto space-y-1 pr-1">
          {logs.slice(-50).map((log, i) => (
            <div
              key={i}
              className={clsx(
                "log-entry",
                log.level === "error"
                  ? "log-error"
                  : log.level === "warning"
                  ? "log-warning"
                  : "log-info"
              )}
            >
              <TimeAgo date={log.timestamp} mode="clock" className="text-gray-600 text-[10px]" />{" "}
              <span className="text-neon-violet text-[10px]">[{log.agent_name}]</span>{" "}
              {log.message}
            </div>
          ))}
          <div ref={logEndRef} />
        </div>
      </div>
    </section>
  );
}
