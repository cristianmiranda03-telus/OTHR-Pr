"use client";
import { useEffect, useState } from "react";
import { connectWebSocket } from "@/lib/ws";
import { useTradingStore } from "@/lib/store";
import { Header } from "@/components/Header";
import { AccountPanel } from "@/components/dashboard/AccountPanel";
import { ControlPanel } from "@/components/dashboard/ControlPanel";
import { AgentPanel } from "@/components/dashboard/AgentPanel";
import { AgentFlowchart } from "@/components/dashboard/AgentFlowchart";
import { SignalPanel } from "@/components/dashboard/SignalPanel";
import { PositionsTable } from "@/components/dashboard/PositionsTable";
import { EquityChart } from "@/components/dashboard/EquityChart";
import { ActivityLog } from "@/components/dashboard/ActivityLog";
import { SessionPanel } from "@/components/dashboard/SessionPanel";
import { StatsPanel } from "@/components/dashboard/StatsPanel";
import { SignalsTab } from "@/components/tabs/SignalsTab";
import { StrategiesTab } from "@/components/tabs/StrategiesTab";
import { ConfigTab } from "@/components/tabs/ConfigTab";
import { cn } from "@/lib/utils";

type TabId = "dashboard" | "signals" | "agents" | "positions" | "strategies" | "config";

export default function Dashboard() {
  const [activeTab, setActiveTab] = useState<TabId>("dashboard");
  const { positions, signals, stats, running } = useTradingStore();

  useEffect(() => {
    connectWebSocket();
  }, []);

  const signalCount = Object.values(signals).filter(
    (s) => s.signal !== "hold"
  ).length;
  const posCount = positions.length;
  const tradesToday = stats?.trades_opened || 0;

  const tabs: { id: TabId; label: string; count?: number; countClass?: string }[] = [
    { id: "dashboard",   label: "Dashboard" },
    { id: "signals",     label: "Signals",    count: signalCount,  countClass: signalCount > 0 ? "profit" : "" },
    { id: "agents",      label: "Agents",     count: running ? 8 : 0, countClass: running ? "brand" : "" },
    { id: "positions",   label: "Positions",  count: posCount,     countClass: posCount > 0 ? "neutral" : "" },
    { id: "strategies",  label: "Strategies", count: tradesToday },
    { id: "config",      label: "Config" },
  ];

  return (
    <div className="min-h-screen bg-bg-base flex flex-col">
      <Header />

      {/* Tab navigation */}
      <nav className="tab-bar sticky top-12 z-40 overflow-x-auto">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={cn("tab-item", activeTab === tab.id && "active")}
          >
            {tab.label}
            {tab.count !== undefined && tab.count > 0 && (
              <span className={cn("tab-badge", tab.countClass)}>{tab.count}</span>
            )}
          </button>
        ))}
      </nav>

      {/* Tab content */}
      <main className="flex-1 max-w-screen-2xl mx-auto w-full px-3 py-3">

        {/* ── DASHBOARD ───────────────────────────────────────────── */}
        {activeTab === "dashboard" && (
          <div className="space-y-3 animate-fade-in">
            <ControlPanel />
            <AccountPanel />
            <div className="grid grid-cols-12 gap-3">
              <div className="col-span-12 lg:col-span-9">
                <EquityChart />
              </div>
              <div className="col-span-12 lg:col-span-3">
                <SessionPanel />
              </div>
            </div>
            <div className="grid grid-cols-12 gap-3">
              <div className="col-span-12 lg:col-span-3 space-y-3">
                <StatsPanel />
                <SignalPanel />
              </div>
              <div className="col-span-12 lg:col-span-9">
                <ActivityLog maxHeight="280px" />
              </div>
            </div>
            <PositionsTable />
          </div>
        )}

        {/* ── SIGNALS ─────────────────────────────────────────────── */}
        {activeTab === "signals" && (
          <div className="animate-fade-in">
            <SignalsTab />
          </div>
        )}

        {/* ── AGENTS FLOWCHART ────────────────────────────────────── */}
        {activeTab === "agents" && (
          <div className="space-y-3 animate-fade-in">
            <AgentFlowchart />
            <AgentPanel />
            <ActivityLog maxHeight="350px" />
          </div>
        )}

        {/* ── POSITIONS ───────────────────────────────────────────── */}
        {activeTab === "positions" && (
          <div className="space-y-3 animate-fade-in">
            <PositionsTable />
            <ActivityLog maxHeight="250px" />
          </div>
        )}

        {/* ── STRATEGIES ──────────────────────────────────────────── */}
        {activeTab === "strategies" && (
          <div className="animate-fade-in">
            <StrategiesTab />
          </div>
        )}

        {/* ── CONFIG ──────────────────────────────────────────────── */}
        {activeTab === "config" && (
          <div className="animate-fade-in">
            <ConfigTab />
          </div>
        )}
      </main>
    </div>
  );
}
