"use client";
import { useMemo } from "react";
import { useTradingStore } from "@/lib/store";

/* ─── Node definitions ─────────────────────────────────────────── */
const NODES = [
  { id: "orchestrator",  label: "Orchestrator",    sub: "CEO",          x: 400, y: 30,  icon: "⚡" },
  { id: "data_cleaner",  label: "Data Cleaner",     sub: "Quality",      x: 80,  y: 150, icon: "🧹" },
  { id: "technical",     label: "Technical",        sub: "Quant",        x: 240, y: 150, icon: "📊" },
  { id: "news",          label: "Sentinel",         sub: "Macro",        x: 560, y: 150, icon: "📡" },
  { id: "risk",          label: "Risk Manager",     sub: "Officer",      x: 720, y: 150, icon: "🛡" },
  { id: "memory",        label: "Memory",           sub: "Auditor",      x: 400, y: 270, icon: "🧠" },
  { id: "executor",      label: "MT5 Executor",     sub: "Bridge",       x: 400, y: 390, icon: "⚡" },
  { id: "explorer",      label: "Explorer",         sub: "Researcher",   x: 680, y: 390, icon: "🔬" },
];

/* ─── Edge definitions (from, to, label) ──────────────────────── */
const EDGES = [
  { from: "orchestrator", to: "data_cleaner", label: "clean",    color: "#6b7280" },
  { from: "orchestrator", to: "technical",    label: "analyze",  color: "#b026ff" },
  { from: "orchestrator", to: "news",         label: "validate", color: "#f59e0b" },
  { from: "orchestrator", to: "risk",         label: "size",     color: "#ef4444" },
  { from: "technical",    to: "memory",       label: "query",    color: "#b026ff" },
  { from: "news",         to: "memory",       label: "context",  color: "#f59e0b" },
  { from: "memory",       to: "orchestrator", label: "risk score",color: "#8b5cf6", dashed: true },
  { from: "risk",         to: "executor",     label: "approve",  color: "#10b981" },
  { from: "orchestrator", to: "executor",     label: "execute",  color: "#10b981" },
  { from: "executor",     to: "memory",       label: "store",    color: "#3b82f6" },
  { from: "explorer",     to: "orchestrator", label: "propose",  color: "#06b6d4", dashed: true },
  { from: "memory",       to: "explorer",     label: "patterns", color: "#06b6d4" },
];

const NODE_W = 110;
const NODE_H = 56;

function getNodeCenter(id: string) {
  const n = NODES.find((n) => n.id === id);
  if (!n) return { x: 0, y: 0 };
  return { x: n.x + NODE_W / 2, y: n.y + NODE_H / 2 };
}

function ArrowMarker({ id, color }: { id: string; color: string }) {
  return (
    <marker id={id} markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
      <path d="M0,0 L0,6 L8,3 z" fill={color} opacity="0.8" />
    </marker>
  );
}

/* ─── Edge path with curve ────────────────────────────────────── */
function EdgePath({ edge, active }: { edge: typeof EDGES[0]; active: boolean }) {
  const from = getNodeCenter(edge.from);
  const to = getNodeCenter(edge.to);
  const markerId = `arrow-${edge.from}-${edge.to}`;
  const mx = (from.x + to.x) / 2;
  const my = (from.y + to.y) / 2 - 20;
  const d = `M ${from.x} ${from.y} Q ${mx} ${my} ${to.x} ${to.y}`;

  return (
    <g>
      <defs>
        <ArrowMarker id={markerId} color={edge.color} />
      </defs>
      <path
        d={d}
        fill="none"
        stroke={edge.color}
        strokeWidth={active ? 2 : 1}
        strokeDasharray={edge.dashed ? "4 3" : undefined}
        markerEnd={`url(#${markerId})`}
        opacity={active ? 0.9 : 0.3}
        className={active ? "transition-all duration-500" : "transition-all duration-500"}
      />
      {/* Animated data particle on active edges */}
      {active && (
        <circle r="3" fill={edge.color} opacity="0.9">
          <animateMotion dur="1.8s" repeatCount="indefinite" path={d} />
        </circle>
      )}
      {/* Edge label */}
      <text
        x={mx}
        y={my - 6}
        textAnchor="middle"
        fontSize="8"
        fill={edge.color}
        opacity={active ? 0.9 : 0.3}
        fontFamily="JetBrains Mono, monospace"
      >
        {edge.label}
      </text>
    </g>
  );
}

/* ─── Agent Node ──────────────────────────────────────────────── */
function AgentNode({ node, status }: { node: typeof NODES[0]; status: string }) {
  const isRunning  = status === "running" || status === "thinking";
  const isError    = status === "error" || status === "halted";
  const isOrchestrator = node.id === "orchestrator";

  const borderColor = isError ? "#ef4444"
    : isRunning ? "#b026ff"
    : isOrchestrator ? "#6d28d9"
    : "#262626";

  const bgColor = isRunning
    ? "rgba(176,38,255,0.08)"
    : isOrchestrator
    ? "rgba(109,40,217,0.12)"
    : "#0f0f0f";

  const glowFilter = isRunning
    ? "drop-shadow(0 0 8px rgba(176,38,255,0.7))"
    : isOrchestrator
    ? "drop-shadow(0 0 4px rgba(109,40,217,0.4))"
    : "none";

  return (
    <g
      transform={`translate(${node.x}, ${node.y})`}
      style={{ filter: glowFilter, cursor: "default" }}
    >
      {/* Glow ring for active nodes */}
      {isRunning && (
        <rect
          x="-4" y="-4"
          width={NODE_W + 8} height={NODE_H + 8}
          rx="10" ry="10"
          fill="none"
          stroke="#b026ff"
          strokeWidth="1"
          opacity="0.4"
          className="animate-pulse-slow"
        />
      )}
      {/* Main rect */}
      <rect
        width={NODE_W} height={NODE_H}
        rx="7" ry="7"
        fill={bgColor}
        stroke={borderColor}
        strokeWidth={isRunning ? 1.5 : 1}
      />
      {/* Status indicator dot */}
      <circle
        cx={NODE_W - 10} cy={10} r={4}
        fill={isError ? "#ef4444" : isRunning ? "#b026ff" : status === "idle" ? "#374151" : "#374151"}
        className={isRunning ? "animate-pulse" : ""}
      />
      {/* Icon */}
      <text x={10} y={22} fontSize="13" fontFamily="sans-serif">{node.icon}</text>
      {/* Label */}
      <text
        x={NODE_W / 2} y={26}
        textAnchor="middle"
        fontSize="10"
        fontWeight="600"
        fill={isRunning ? "#e9d5ff" : isOrchestrator ? "#c4b5fd" : "#d1d5db"}
        fontFamily="Inter, sans-serif"
      >
        {node.label}
      </text>
      {/* Sub-label */}
      <text
        x={NODE_W / 2} y={40}
        textAnchor="middle"
        fontSize="8"
        fill={isRunning ? "#a78bfa" : "#4b5563"}
        fontFamily="JetBrains Mono, monospace"
      >
        {node.sub} {isRunning ? "●" : ""}
      </text>
      {/* Status text */}
      <text
        x={NODE_W / 2} y={52}
        textAnchor="middle"
        fontSize="7"
        fill={isError ? "#ef4444" : isRunning ? "#b026ff" : "#374151"}
        fontFamily="JetBrains Mono, monospace"
        textTransform="uppercase"
      >
        {status}
      </text>
    </g>
  );
}

/* ─── Main Component ──────────────────────────────────────────── */
export function AgentFlowchart() {
  const { agentStatuses, stats, running } = useTradingStore();

  const activeEdges = useMemo(() => {
    const activeAgents = Object.entries(agentStatuses)
      .filter(([, s]) => s.status === "running" || s.status === "thinking")
      .map(([k]) => k);

    return EDGES.filter(
      (e) => activeAgents.includes(e.from) || activeAgents.includes(e.to)
    );
  }, [agentStatuses]);

  const runCounts = Object.entries(agentStatuses).reduce((acc, [k, v]) => {
    acc[k] = v.run_count || 0;
    return acc;
  }, {} as Record<string, number>);

  return (
    <div className="card overflow-hidden">
      {/* Header */}
      <div className="card-header">
        <div className="flex items-center gap-2">
          <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider">
            Agent Network
          </span>
          {running && (
            <span className="flex items-center gap-1 text-[10px] text-brand mono">
              <span className="w-1.5 h-1.5 rounded-full bg-brand animate-pulse" />
              LIVE
            </span>
          )}
        </div>
        <div className="flex items-center gap-3 text-[10px] mono text-gray-600">
          <span>Cycles: <span className="text-gray-400">{stats?.total_cycles || 0}</span></span>
          <span>Signals: <span className="text-brand">{stats?.signals_found || 0}</span></span>
          <span>Trades: <span className="text-profit">{stats?.trades_opened || 0}</span></span>
          <span>Vetoed: <span className="text-loss">{stats?.trades_vetoed || 0}</span></span>
        </div>
      </div>

      {/* SVG Flowchart */}
      <div className="relative bg-bg-base overflow-x-auto">
        <svg
          width="840"
          height="470"
          viewBox="0 0 840 470"
          className="w-full"
          style={{ minWidth: "600px" }}
        >
          {/* Grid background */}
          <defs>
            <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
              <path d="M 20 0 L 0 0 0 20" fill="none" stroke="#1a1a1a" strokeWidth="0.5" />
            </pattern>
          </defs>
          <rect width="840" height="470" fill="url(#grid)" />

          {/* Inactive edges first (under active) */}
          {EDGES.filter(
            (e) => !activeEdges.some((ae) => ae.from === e.from && ae.to === e.to)
          ).map((edge, i) => (
            <EdgePath key={i} edge={edge} active={false} />
          ))}

          {/* Active edges on top */}
          {activeEdges.map((edge, i) => (
            <EdgePath key={`active-${i}`} edge={edge} active={true} />
          ))}

          {/* Agent nodes */}
          {NODES.map((node) => (
            <AgentNode
              key={node.id}
              node={node}
              status={agentStatuses[node.id]?.status || "idle"}
            />
          ))}

          {/* Run count badges */}
          {NODES.map((node) => {
            const count = runCounts[node.id] || 0;
            if (count === 0) return null;
            return (
              <text
                key={`count-${node.id}`}
                x={node.x + NODE_W}
                y={node.y}
                fontSize="8"
                fill="#6b7280"
                fontFamily="JetBrains Mono, monospace"
                textAnchor="end"
              >
                ×{count}
              </text>
            );
          })}
        </svg>
      </div>

      {/* Legend */}
      <div className="flex gap-4 px-4 py-2 border-t border-bg-border text-[10px] mono text-gray-600 flex-wrap">
        <span className="flex items-center gap-1">
          <span className="w-2 h-0.5 bg-brand inline-block" /> Active flow
        </span>
        <span className="flex items-center gap-1">
          <span className="w-2 h-0.5 bg-gray-700 inline-block" style={{ borderTop: "1px dashed #4b5563" }} /> Background
        </span>
        <span className="flex items-center gap-1">
          <span className="w-2 h-2 rounded-full bg-brand animate-pulse inline-block" /> Running
        </span>
        <span className="flex items-center gap-1">
          <span className="w-2 h-2 rounded-full bg-loss inline-block" /> Error
        </span>
        <span className="ml-auto">● Particle = live data transfer</span>
      </div>
    </div>
  );
}
