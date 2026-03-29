"use client";
import type { AgentInfo } from "@/types";
import clsx from "clsx";

interface Props {
  agents: AgentInfo[];
  heartbeat?: {
    pending_suggestions?: number;
    executed_suggestions?: number;
    event_evaluations?: number;
    position_advices?: number;
    ranked_opportunities?: number;
  } | null;
}

const STATUS_COLORS: Record<string, string> = {
  idle: "border-gray-600 text-gray-500",
  running: "border-neon-blue text-neon-blue shadow-[0_0_8px_rgba(0,255,255,0.3)]",
  investigating: "border-neon-violet text-neon-violet shadow-[0_0_8px_rgba(188,19,254,0.3)] animate-pulse-slow",
  suggestion_ready: "border-neon-green text-neon-green shadow-[0_0_8px_rgba(57,255,20,0.3)]",
  error: "border-neon-red text-neon-red shadow-[0_0_8px_rgba(255,7,58,0.3)]",
};

const CATEGORY_ICONS: Record<string, string> = {
  orchestrator: "♠",
  politics: "🏛",
  crypto: "₿",
  sports: "⚽",
  science: "🔬",
  strategy_scout: "🕵",
  whale_watcher: "🐋",
  event_evaluator: "🎯",
  strategy_evaluator: "⚖",
  position_advisor: "🛡",
  entry_analyst: "🔎",
  opportunity_optimizer: "📊",
};

export default function AgentFlowPanel({ agents, heartbeat }: Props) {
  const orchestrator = agents.find((a) => a.category === "orchestrator");

  const marketAgents = agents.filter(
    (a) => ["politics", "crypto", "sports", "science"].includes(a.category)
  );
  const strategyAgents = agents.filter(
    (a) => ["strategy_scout", "whale_watcher"].includes(a.category) || a.name === "PortfolioAnalyst"
  );
  const advisoryAgents = agents.filter(
    (a) => ["event_evaluator", "strategy_evaluator", "position_advisor", "entry_analyst", "opportunity_optimizer"].includes(a.category)
  );

  const activeCount = agents.filter((a) => a.status !== "idle" && a.status !== "error").length;
  const totalSigs = agents.reduce((sum, a) => sum + a.suggestions_generated, 0);

  const renderAgent = (agent: AgentInfo | undefined, fallbackName: string) => {
    if (!agent) {
      return (
        <div className="flex flex-col items-center justify-center p-2.5 border border-gray-800 rounded bg-[#111] opacity-40 w-28 h-[72px]">
          <span className="text-base">{CATEGORY_ICONS[fallbackName.toLowerCase()] || "◈"}</span>
          <p className="text-[9px] text-gray-600 font-mono uppercase text-center mt-1">{fallbackName}</p>
          <p className="text-[8px] text-gray-700">offline</p>
        </div>
      );
    }
    const icon = CATEGORY_ICONS[agent.category] || "◈";
    return (
      <div
        className={clsx(
          "flex flex-col items-center justify-center p-2.5 border rounded bg-[#1a1a1a] w-28 h-[72px] transition-all relative group",
          STATUS_COLORS[agent.status] || STATUS_COLORS.idle
        )}
      >
        <span className="text-base">{icon}</span>
        <p className="text-[9px] font-mono uppercase text-center truncate w-full mt-0.5" title={agent.name}>
          {agent.name.replace("Agent", "")}
        </p>
        <div className="flex items-center gap-1 mt-0.5">
          <span className="text-[8px] uppercase tracking-widest opacity-80">
            {agent.status}
          </span>
          {agent.suggestions_generated > 0 && (
            <span className="text-[8px] text-neon-green font-mono">
              +{agent.suggestions_generated}
            </span>
          )}
        </div>
        {agent.current_task && (
          <div className="absolute -bottom-5 left-1/2 -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-opacity z-10 whitespace-nowrap">
            <span className="text-[8px] bg-black/90 text-gray-300 px-2 py-0.5 rounded border border-bg-border">
              {agent.current_task.slice(0, 50)}
            </span>
          </div>
        )}
      </div>
    );
  };

  const Connector = ({ vertical = true }: { vertical?: boolean }) =>
    vertical ? (
      <div className="w-px h-5 bg-gradient-to-b from-gray-600 to-gray-800 mx-auto" />
    ) : null;

  const TierLabel = ({ text, color }: { text: string; color: string }) => (
    <div className={clsx("text-[9px] uppercase tracking-[0.2em] font-mono mb-2 text-center", color)}>
      {text}
    </div>
  );

  return (
    <section className="flex flex-col gap-4 p-4 bg-[#0a0a0a] rounded border border-bg-border overflow-x-auto">
      <div className="flex items-center justify-between border-b border-bg-border pb-2">
        <h2 className="text-xs text-gray-500 uppercase tracking-widest font-mono">
          Agent Flow — Live System Architecture
        </h2>
        <div className="flex items-center gap-3 text-[10px] font-mono">
          <span className="text-neon-blue">{activeCount} active</span>
          <span className="text-neon-green">{totalSigs} signals</span>
          {heartbeat?.pending_suggestions != null && heartbeat.pending_suggestions > 0 && (
            <span className="text-neon-yellow">{heartbeat.pending_suggestions} pending</span>
          )}
        </div>
      </div>

      {/* Orchestrator */}
      <div className="flex flex-col items-center">
        <TierLabel text="Orchestrator" color="text-neon-violet" />
        {renderAgent(orchestrator, "Orchestrator")}
        <Connector />
        <div className="text-[8px] text-gray-600 text-center">coordinates all tiers</div>
      </div>

      {/* Branch line */}
      <div className="w-full max-w-3xl mx-auto relative">
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent" />
        <div className="absolute top-0 left-1/4 -translate-y-1/2 w-1.5 h-1.5 rounded-full bg-neon-blue" />
        <div className="absolute top-0 left-1/2 -translate-x-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full bg-neon-violet" />
        <div className="absolute top-0 left-3/4 -translate-y-1/2 w-1.5 h-1.5 rounded-full bg-neon-green" />
      </div>

      {/* Tier 1: Data Collection */}
      <div className="flex flex-wrap justify-center gap-6">
        <div className="flex flex-col items-center gap-2 p-3 border border-[#1a3a5a] rounded bg-[#0a1520]">
          <TierLabel text="Tier 1 — Market Scanners" color="text-neon-blue" />
          <div className="flex gap-2 flex-wrap justify-center">
            {renderAgent(marketAgents.find((a) => a.category === "politics"), "politics")}
            {renderAgent(marketAgents.find((a) => a.category === "crypto"), "crypto")}
            {renderAgent(marketAgents.find((a) => a.category === "sports"), "sports")}
            {renderAgent(marketAgents.find((a) => a.category === "science"), "science")}
          </div>
          <p className="text-[8px] text-gray-600 text-center">scan markets → LLM sentiment → trading signals</p>
        </div>

        <div className="flex flex-col items-center gap-2 p-3 border border-[#2a1a3a] rounded bg-[#15091f]">
          <TierLabel text="Tier 1 — Strategy Research" color="text-neon-violet" />
          <div className="flex gap-2 flex-wrap justify-center">
            {renderAgent(strategyAgents.find((a) => a.category === "strategy_scout"), "strategy_scout")}
            {renderAgent(strategyAgents.find((a) => a.category === "whale_watcher"), "whale_watcher")}
            {renderAgent(strategyAgents.find((a) => a.name === "PortfolioAnalyst"), "PortfolioAnalyst")}
          </div>
          <p className="text-[8px] text-gray-600 text-center">research strategies, whales, portfolio state</p>
        </div>
      </div>

      {/* Arrow down */}
      <div className="flex justify-center">
        <div className="flex flex-col items-center">
          <div className="w-px h-4 bg-gray-600" />
          <span className="text-[8px] text-gray-500">feeds data to</span>
          <div className="w-px h-4 bg-gray-600" />
          <div className="w-0 h-0 border-l-[4px] border-r-[4px] border-t-[6px] border-l-transparent border-r-transparent border-t-gray-600" />
        </div>
      </div>

      {/* Tier 2: Advisory */}
      <div className="flex flex-col items-center gap-2 p-3 border border-[#1a3a1a] rounded bg-[#091f09] mx-auto">
        <TierLabel text="Tier 2 — Advisory & Evaluation" color="text-neon-green" />
        <div className="flex gap-2 flex-wrap justify-center">
          {renderAgent(advisoryAgents.find((a) => a.category === "event_evaluator"), "event_evaluator")}
          {renderAgent(advisoryAgents.find((a) => a.category === "strategy_evaluator"), "strategy_evaluator")}
          {renderAgent(advisoryAgents.find((a) => a.category === "position_advisor"), "position_advisor")}
          {renderAgent(advisoryAgents.find((a) => a.category === "entry_analyst"), "entry_analyst")}
        </div>
        <p className="text-[8px] text-gray-600 text-center">evaluate events, strategies, positions → detailed advice</p>
      </div>

      {/* Arrow down */}
      <div className="flex justify-center">
        <div className="flex flex-col items-center">
          <div className="w-px h-4 bg-gray-600" />
          <span className="text-[8px] text-gray-500">prioritizes</span>
          <div className="w-px h-4 bg-gray-600" />
          <div className="w-0 h-0 border-l-[4px] border-r-[4px] border-t-[6px] border-l-transparent border-r-transparent border-t-gray-600" />
        </div>
      </div>

      {/* Tier 3: Optimizer */}
      <div className="flex flex-col items-center gap-2 p-3 border border-[#3a3a0a] rounded bg-[#1f1f05] mx-auto">
        <TierLabel text="Tier 3 — Opportunity Optimizer" color="text-neon-yellow" />
        <div className="flex gap-2 justify-center">
          {renderAgent(advisoryAgents.find((a) => a.category === "opportunity_optimizer"), "opportunity_optimizer")}
        </div>
        <p className="text-[8px] text-gray-600 text-center">rank by profitability, risk, opportunity cost</p>
      </div>

      {/* Output flows */}
      <div className="flex justify-center">
        <div className="w-px h-6 bg-gray-600" />
      </div>

      <div className="flex justify-center gap-6 flex-wrap">
        <OutputNode label="Trading Signals" color="neon-green" icon="⚡"
          count={heartbeat?.pending_suggestions} />
        <OutputNode label="Position Advice" color="neon-blue" icon="🛡"
          count={heartbeat?.position_advices} />
        <OutputNode label="Ranked Opps" color="neon-yellow" icon="📊"
          count={heartbeat?.ranked_opportunities} />
        <OutputNode label="Event Scenarios" color="neon-violet" icon="🎯"
          count={heartbeat?.event_evaluations} />
      </div>

      {/* Final: User approval */}
      <div className="flex justify-center mt-2">
        <div className="px-4 py-2 border-2 border-neon-green rounded-lg bg-[#39FF1409] text-center">
          <p className="text-[10px] text-neon-green font-mono uppercase tracking-widest">
            You Review & Approve
          </p>
          <p className="text-[8px] text-gray-500 mt-0.5">agents propose → you decide → system executes</p>
        </div>
      </div>
    </section>
  );
}

function OutputNode({ label, color, icon, count }: {
  label: string; color: string; icon: string; count?: number;
}) {
  return (
    <div className={clsx(
      "px-3 py-1.5 border text-[10px] uppercase font-mono rounded bg-opacity-10 flex items-center gap-1.5",
      `border-${color} text-${color}`
    )}
      style={{
        borderColor: `var(--${color})`,
        color: `var(--${color})`,
      }}
    >
      <span>{icon}</span>
      <span>{label}</span>
      {count != null && count > 0 && (
        <span className="text-[9px] font-bold">({count})</span>
      )}
    </div>
  );
}
