"use client";
import { useCallback, useEffect, useState } from "react";
import type {
  AgentInfo, AgentLog, BitcoinSignal, EventEvaluation, Investigation, OpportunityEntry,
  Portfolio, PositionAdvice, StrategyReport, Suggestion, WsMessage,
} from "@/types";
import { useWebSocket } from "@/hooks/useWebSocket";
import { apiFetch } from "@/hooks/useApi";
import { useMounted } from "@/hooks/useMounted";
import AgentStatusPanel from "./AgentStatusPanel";
import AgentFlowPanel from "./AgentFlowPanel";
import SuggestionQueue from "./SuggestionQueue";
import PortfolioView from "./PortfolioView";
import InvestigationPanel from "./InvestigationPanel";
import StrategyPanel from "./StrategyPanel";
import EventsPanel from "./EventsPanel";
import AdvisoryPanel from "./AdvisoryPanel";
import ConfigPanel from "./ConfigPanel";
import GuidePanel from "./GuidePanel";
import BitcoinLivePanel from "./BitcoinLivePanel";
import clsx from "clsx";

// ─── Tab definitions ──────────────────────────────────────────────────
type Tab = "bitcoin" | "signals" | "events" | "advisory" | "flow" | "agents" | "analysis" | "strategies" | "portfolio" | "config" | "guide";

const TABS: { id: Tab; label: string; icon: string }[] = [
  { id: "guide",      label: "Guide",      icon: "📖" },
  { id: "bitcoin",    label: "BTC Live",   icon: "₿" },
  { id: "signals",    label: "Signals",    icon: "⚡" },
  { id: "events",     label: "Events",     icon: "📋" },
  { id: "advisory",   label: "Advisory",   icon: "🛡" },
  { id: "flow",       label: "Flow",       icon: "⎈" },
  { id: "agents",     label: "Agents",     icon: "◈" },
  { id: "analysis",   label: "Analysis",   icon: "🔍" },
  { id: "strategies", label: "Strategies", icon: "🗺" },
  { id: "portfolio",  label: "Portfolio",  icon: "💼" },
  { id: "config",     label: "Config",     icon: "⚙" },
];

export default function Dashboard() {
  const [tab, setTab] = useState<Tab>("bitcoin");

  // ── State ────────────────────────────────────────────────────────
  const [agents,          setAgents]          = useState<AgentInfo[]>([]);
  const [logs,            setLogs]            = useState<AgentLog[]>([]);
  const [suggestions,     setSuggestions]     = useState<Suggestion[]>([]);
  const [portfolio,       setPortfolio]       = useState<Portfolio | null>(null);
  const [investigations,  setInvestigations]  = useState<Investigation[]>([]);
  const [strategyReports, setStrategyReports] = useState<StrategyReport[]>([]);
  const [evaluations,     setEvaluations]     = useState<EventEvaluation[]>([]);
  const [positionAdvice,  setPositionAdvice]  = useState<PositionAdvice[]>([]);
  const [opportunities,   setOpportunities]   = useState<OpportunityEntry[]>([]);
  const [heartbeat,       setHeartbeat]       = useState<Record<string, number> | null>(null);
  const [btcSignals,      setBtcSignals]      = useState<BitcoinSignal[]>([]);

  // ── Bootstrap ────────────────────────────────────────────────────
  useEffect(() => {
    const init = async () => {
      try {
        const [agRes, sugRes, portRes, invRes, strRes, evRes, advRes, oppRes] = await Promise.allSettled([
          apiFetch<AgentInfo[]>("/api/agents"),
          apiFetch<Suggestion[]>("/api/suggestions"),
          apiFetch<Portfolio>("/api/portfolio"),
          apiFetch<Investigation[]>("/api/investigations"),
          apiFetch<StrategyReport[]>("/api/strategies"),
          apiFetch<EventEvaluation[]>("/api/evaluations"),
          apiFetch<PositionAdvice[]>("/api/advice"),
          apiFetch<OpportunityEntry[]>("/api/opportunities"),
        ]);
        if (agRes.status   === "fulfilled" && agRes.value.data)   setAgents(agRes.value.data);
        if (sugRes.status  === "fulfilled" && sugRes.value.data)  setSuggestions(sugRes.value.data);
        if (portRes.status === "fulfilled" && portRes.value.data) setPortfolio(portRes.value.data);
        if (invRes.status  === "fulfilled" && invRes.value.data)  setInvestigations(invRes.value.data);
        if (strRes.status  === "fulfilled" && strRes.value.data)  setStrategyReports(strRes.value.data);
        if (evRes.status   === "fulfilled" && evRes.value.data)   setEvaluations(evRes.value.data);
        if (advRes.status  === "fulfilled" && advRes.value.data)  setPositionAdvice(advRes.value.data);
        if (oppRes.status  === "fulfilled" && oppRes.value.data)  setOpportunities(oppRes.value.data);
      } catch { /* WS will bring data */ }
    };
    init();
  }, []);

  // ── WebSocket ────────────────────────────────────────────────────
  const handleMessage = useCallback((msg: WsMessage) => {
    switch (msg.event) {
      case "agent_log": {
        setLogs((p) => [...p.slice(-300), msg.data as AgentLog]);
        break;
      }
      case "agent_status": {
        const u = msg.data as AgentInfo;
        setAgents((p) => {
          const idx = p.findIndex((a) => a.id === u.id);
          if (idx === -1) return [...p, u];
          const n = [...p]; n[idx] = u; return n;
        });
        break;
      }
      case "new_suggestion": {
        const s = msg.data as Suggestion;
        setSuggestions((p) => p.find((x) => x.id === s.id) ? p : [s, ...p]);
        break;
      }
      case "suggestion_update": {
        const u = msg.data as Suggestion;
        setSuggestions((p) => p.map((s) => s.id === u.id ? u : s));
        break;
      }
      case "portfolio_update": {
        setPortfolio(msg.data as Portfolio);
        break;
      }
      case "investigation_update": {
        const inv = msg.data as Investigation;
        setInvestigations((p) => {
          const idx = p.findIndex((i) => i.id === inv.id);
          if (idx === -1) return [inv, ...p];
          const n = [...p]; n[idx] = inv; return n;
        });
        break;
      }
      case "strategy_report": {
        const r = msg.data as StrategyReport;
        setStrategyReports((p) => {
          const idx = p.findIndex((x) => x.id === r.id);
          if (idx === -1) return [r, ...p];
          const n = [...p]; n[idx] = r; return n;
        });
        break;
      }
      case "event_evaluation": {
        const ev = msg.data as EventEvaluation;
        setEvaluations((p) => {
          const idx = p.findIndex((x) => x.id === ev.id);
          if (idx === -1) return [ev, ...p];
          const n = [...p]; n[idx] = ev; return n;
        });
        break;
      }
      case "position_advice": {
        const adv = msg.data as PositionAdvice;
        setPositionAdvice((p) => {
          const idx = p.findIndex((x) => x.id === adv.id);
          if (idx === -1) return [adv, ...p];
          const n = [...p]; n[idx] = adv; return n;
        });
        break;
      }
      case "opportunity_rank": {
        const opp = msg.data as OpportunityEntry;
        setOpportunities((p) => {
          const idx = p.findIndex((x) => x.id === opp.id);
          if (idx === -1) return [...p, opp].sort((a, b) => a.priority_rank - b.priority_rank);
          const n = [...p]; n[idx] = opp; return n.sort((a, b) => a.priority_rank - b.priority_rank);
        });
        break;
      }
      case "system": {
        const data = msg.data as Record<string, unknown>;
        if (data?.type === "heartbeat") {
          setHeartbeat(data as unknown as Record<string, number>);
        }
        break;
      }
      case "bitcoin_signal": {
        const payload = msg.data as { signals: BitcoinSignal[]; count: number };
        if (payload?.signals) setBtcSignals(payload.signals);
        break;
      }
    }
  }, []);

  const { connected } = useWebSocket({ "*": handleMessage });
  const mounted = useMounted();
  const [clock, setClock] = useState("");

  const handleSuggestionUpdate = useCallback((updated: Suggestion) => {
    setSuggestions((p) => p.map((s) => s.id === updated.id ? updated : s));
  }, []);

  // ── Live clock (client-only) ─────────────────────────────────────
  useEffect(() => {
    setClock(new Date().toLocaleTimeString());
    const id = setInterval(() => setClock(new Date().toLocaleTimeString()), 1000);
    return () => clearInterval(id);
  }, []);

  // ── Counts ───────────────────────────────────────────────────────
  const pendingCount  = suggestions.filter((s) => s.status === "pending").length;
  const analyzingCount = investigations.filter((i) => i.status === "analyzing").length;
  const activeAgents  = agents.filter((a) => a.status !== "idle" && a.status !== "error").length;
  const advisoryCount = evaluations.length + positionAdvice.length + opportunities.length;

  const btcStrongCount = btcSignals.filter((s) => s.signal_quality === "strong").length;

  const badge = (tabId: Tab): number => {
    if (tabId === "bitcoin")    return btcStrongCount;
    if (tabId === "signals")    return pendingCount;
    if (tabId === "analysis")   return analyzingCount;
    if (tabId === "strategies") return strategyReports.length;
    if (tabId === "advisory")   return advisoryCount;
    return 0;
  };

  return (
    <div className="h-screen flex flex-col bg-bg-primary overflow-hidden">
      {/* CRT overlay */}
      <div className="scanline-overlay" />

      {/* ── Top bar ─────────────────────────────────────────────── */}
      <header className="flex-shrink-0 border-b border-bg-border px-4 py-2 flex items-center justify-between gap-4 z-10">
        <div className="flex items-center gap-3">
          <span className="font-title text-base text-neon-violet glow-violet tracking-widest">
            ♠ POLYMARKET TRADER
          </span>
        </div>

        {/* Status pills */}
        <div className="flex items-center gap-3">
          <Pill
            dot={connected}
            label={connected ? "LIVE" : "OFFLINE"}
            color={connected ? "green" : "red"}
          />
          <Pill dot={activeAgents > 0} label={`${activeAgents}/${agents.length} AGENTS`} color="violet" />
          {pendingCount > 0 && (
            <Pill dot label={`${pendingCount} SIGNALS`} color="green" pulse />
          )}
          {advisoryCount > 0 && (
            <Pill dot label={`${advisoryCount} ADVISORY`} color="blue" />
          )}
          {btcStrongCount > 0 && (
            <Pill dot label={`${btcStrongCount} BTC ⚡`} color="green" pulse />
          )}
        </div>
      </header>

      {/* ── Tab navigation ──────────────────────────────────────── */}
      <nav className="flex-shrink-0 flex border-b border-bg-border overflow-x-auto z-10">
        {TABS.map((t) => {
          const count = badge(t.id);
          return (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={clsx(
                "flex items-center gap-1.5 px-4 py-2.5 text-xs font-mono whitespace-nowrap transition-all border-b-2",
                tab === t.id
                  ? "border-neon-violet text-neon-violet bg-[#BC13FE10]"
                  : "border-transparent text-gray-500 hover:text-gray-300 hover:border-gray-600"
              )}
            >
              <span className="text-sm">{t.icon}</span>
              <span className="uppercase tracking-wider">{t.label}</span>
              {count > 0 && (
                <span className={clsx(
                  "text-[10px] px-1.5 py-0.5 rounded-full font-bold ml-0.5",
                  t.id === "signals" ? "bg-[#39FF1433] text-neon-green" : "bg-[#BC13FE33] text-neon-violet"
                )}>
                  {count}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* ── Main content area ────────────────────────────────────── */}
      <main className="flex-1 overflow-y-auto p-4">
        <div className="max-w-5xl mx-auto">

          {tab === "guide" && (
            <GuidePanel />
          )}

          {tab === "bitcoin" && (
            <BitcoinLivePanel
              portfolio={portfolio}
              liveSignals={btcSignals}
            />
          )}

          {tab === "signals" && (
            <SuggestionQueue
              suggestions={suggestions}
              portfolio={portfolio}
              onUpdate={handleSuggestionUpdate}
            />
          )}

          {tab === "events" && (
            <EventsPanel />
          )}

          {tab === "advisory" && (
            <AdvisoryPanel
              liveEvaluations={evaluations}
              liveAdvice={positionAdvice}
              liveOpportunities={opportunities}
            />
          )}

          {tab === "flow" && (
            <AgentFlowPanel agents={agents} heartbeat={heartbeat} />
          )}

          {tab === "agents" && (
            <AgentStatusPanel agents={agents} logs={logs} />
          )}

          {tab === "analysis" && (
            <InvestigationPanel liveInvestigations={investigations} />
          )}

          {tab === "strategies" && (
            <StrategyPanel liveReports={strategyReports} />
          )}

          {tab === "portfolio" && (
            <PortfolioView portfolioOverride={portfolio} />
          )}

          {tab === "config" && (
            <ConfigPanel onSaved={async () => {
              try {
                const res = await apiFetch<Portfolio>("/api/portfolio");
                if (res.data) setPortfolio(res.data);
              } catch { /* ignore */ }
            }} />
          )}

        </div>
      </main>

      {/* ── Bottom status bar ────────────────────────────────────── */}
      <footer className="flex-shrink-0 border-t border-bg-border px-4 py-1.5 flex items-center gap-4 text-[10px] text-gray-600 font-mono z-10">
        {logs.slice(-1).map((log, i) => (
          <span key={i} className="truncate">
            <span className="text-neon-violet">[{log.agent_name}]</span>{" "}
            {log.message}
          </span>
        ))}
        {mounted && (
          <span className="ml-auto flex-shrink-0 tabular-nums">{clock}</span>
        )}
      </footer>
    </div>
  );
}

// ── Helper ────────────────────────────────────────────────────────────

function Pill({
  dot, label, color, pulse,
}: {
  dot: boolean; label: string; color: "green" | "red" | "violet" | "blue"; pulse?: boolean;
}) {
  const dotColor = { green: "bg-neon-green", red: "bg-neon-red", violet: "bg-neon-violet", blue: "bg-neon-blue" }[color];
  const textColor = { green: "text-neon-green", red: "text-neon-red", violet: "text-neon-violet", blue: "text-neon-blue" }[color];
  return (
    <div className="flex items-center gap-1.5">
      {dot && (
        <div className={clsx("w-1.5 h-1.5 rounded-full", dotColor, pulse && "animate-pulse")} />
      )}
      <span className={clsx("text-[10px] font-mono", textColor)}>{label}</span>
    </div>
  );
}
