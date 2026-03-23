"use client";
import { useTradingStore } from "@/lib/store";
import { agentStatusDot, agentStatusColor } from "@/lib/utils";
import { Brain, Eye, Radio, Shield, Zap, Database, FlaskConical, Filter } from "lucide-react";

const AGENTS = [
  { key: "orchestrator",   label: "Orchestrator",   icon: Brain,         desc: "CEO / Manager" },
  { key: "technical",      label: "Technical",      icon: Eye,           desc: "Quant Analyst" },
  { key: "news",           label: "News Sentinel",  icon: Radio,         desc: "Macro Agent" },
  { key: "risk",           label: "Risk Manager",   icon: Shield,        desc: "Risk Officer" },
  { key: "executor",       label: "MT5 Executor",   icon: Zap,           desc: "The Bridge" },
  { key: "memory",         label: "Memory",         icon: Database,      desc: "Auditor" },
  { key: "explorer",       label: "Explorer",       icon: FlaskConical,  desc: "Researcher" },
  { key: "data_cleaner",   label: "Data Cleaner",   icon: Filter,        desc: "Data Guard" },
];

export function AgentPanel() {
  const { agentStatuses, stats } = useTradingStore();

  return (
    <div className="card">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
          <Brain className="w-3.5 h-3.5 text-brand" /> Agent Network
        </span>
        <span className="text-[10px] text-gray-600 mono">
          {stats?.total_cycles || 0} cycles
        </span>
      </div>
      <div className="p-3 grid grid-cols-2 gap-2">
        {AGENTS.map((agent) => {
          const s = agentStatuses[agent.key];
          const status = s?.status || "idle";
          const Icon = agent.icon;
          return (
            <div key={agent.key}
              className="flex items-center gap-2.5 p-2 rounded-lg bg-bg-surface hover:bg-bg-raised transition-colors cursor-default">
              <div className="relative flex-shrink-0">
                <Icon className={`w-4 h-4 ${agentStatusColor(status)}`} />
                <span className={`absolute -bottom-0.5 -right-0.5 w-2 h-2 rounded-full border border-bg-base
                  ${status === "running" || status === "thinking" ? "bg-brand animate-pulse" :
                    status === "error" ? "bg-loss" :
                    "bg-gray-700"}`}
                />
              </div>
              <div className="min-w-0">
                <p className="text-xs font-medium text-gray-200 truncate">{agent.label}</p>
                <p className="text-[10px] text-gray-600 truncate">{agent.desc}</p>
              </div>
              <div className="ml-auto text-right flex-shrink-0">
                <span className={`text-[10px] mono capitalize ${agentStatusColor(status)}`}>
                  {status}
                </span>
                {s?.run_count !== undefined && (
                  <p className="text-[10px] text-gray-700 mono">{s.run_count}x</p>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Veto stats */}
      {stats?.trades_vetoed !== undefined && stats.trades_vetoed > 0 && (
        <div className="border-t border-bg-border px-3 py-2">
          <p className="text-[10px] text-gray-600 uppercase tracking-wider mb-1.5">Veto Summary</p>
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(stats.veto_reasons || {}).map(([reason, count]) => (
              <span key={reason}
                className="text-[10px] bg-loss/10 text-loss border border-loss/20 px-2 py-0.5 rounded mono">
                {reason.split(" ")[0]}: {count}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
