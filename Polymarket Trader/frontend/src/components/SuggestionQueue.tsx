"use client";
import { useState } from "react";
import type { AgentCategory, Portfolio, Suggestion, SuggestionStatus } from "@/types";
import SuggestionCard from "./SuggestionCard";
import { apiFetch } from "@/hooks/useApi";
import clsx from "clsx";

// ── Status filters ────────────────────────────────────────────────────
const STATUS_FILTERS: { label: string; value: SuggestionStatus | "all" }[] = [
  { label: "All",      value: "all" },
  { label: "Pending",  value: "pending" },
  { label: "Executed", value: "executed" },
  { label: "Rejected", value: "rejected" },
];

// ── Category filters ──────────────────────────────────────────────────
const CATEGORY_FILTERS: { label: string; value: AgentCategory | "all"; icon: string }[] = [
  { label: "All Areas",    value: "all",                   icon: "◈" },
  { label: "Politics",     value: "politics",               icon: "🏛" },
  { label: "Crypto",       value: "crypto",                 icon: "₿" },
  { label: "Sports",       value: "sports",                 icon: "⚽" },
  { label: "Science",      value: "science",                icon: "🔬" },
  { label: "Whales",       value: "whale_watcher",          icon: "🐋" },
  { label: "New Entries",  value: "entry_analyst",           icon: "🔎" },
];

interface Props {
  suggestions: Suggestion[];
  portfolio?:  Portfolio | null;
  onUpdate:    (updated: Suggestion) => void;
}

export default function SuggestionQueue({ suggestions, portfolio, onUpdate }: Props) {
  const [statusFilter,   setStatusFilter]   = useState<SuggestionStatus | "all">("pending");
  const [categoryFilter, setCategoryFilter] = useState<AgentCategory | "all">("all");

  const balance = portfolio?.balance_usdc;

  const now = Date.now();

  // Filter out expired pending signals client-side as safety net
  const activeSuggestions = suggestions.filter((s) => {
    if (s.status === "pending") {
      if (s.end_date && new Date(s.end_date).getTime() <= now) return false;
      if (s.price_at_discovery <= 0.005 || s.price_at_discovery >= 0.995) return false;
    }
    return true;
  });

  // Apply user filters
  const visible = activeSuggestions.filter((s) => {
    if (statusFilter   !== "all" && s.status   !== statusFilter)   return false;
    if (categoryFilter !== "all" && s.category !== categoryFilter) return false;
    return true;
  });

  // Sort: pending by soonest expiry first, then others by created_at desc
  const sorted = [...visible].sort((a, b) => {
    if (a.status === "pending" && b.status === "pending") {
      if (a.end_date && b.end_date)
        return new Date(a.end_date).getTime() - new Date(b.end_date).getTime();
      if (a.end_date) return -1;
      if (b.end_date) return 1;
    }
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
  });

  const pendingCount = activeSuggestions.filter((s) => s.status === "pending").length;

  const handleApprove = async (id: string, amount: number) => {
    try {
      const res = await apiFetch<Suggestion>(`/api/suggestions/approve/${id}`, {
        method: "POST",
        body: JSON.stringify({ suggestion_id: id, amount_usdc: amount }),
      });
      if (res.data) onUpdate(res.data);
    } catch (err: unknown) {
      // Re-fetch the suggestion to get updated status (FAILED) from backend
      try {
        const refreshed = await apiFetch<Suggestion[]>("/api/suggestions");
        if (refreshed.data) {
          const updated = refreshed.data.find((s) => s.id === id);
          if (updated) onUpdate(updated);
        }
      } catch { /* ignore */ }
      // Re-throw so the SuggestionCard can show the error
      throw err;
    }
  };

  const handleReject = async (id: string) => {
    try {
      const res = await apiFetch<Suggestion>(`/api/suggestions/reject/${id}`, {
        method: "POST",
      });
      if (res.data) onUpdate(res.data);
    } catch (err) {
      console.error("Reject failed:", err);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      {/* Pending alert banner */}
      {statusFilter === "pending" && pendingCount > 0 && (
        <div className="joker-card p-3 border-l-2 border-neon-green flex items-center justify-between">
          <p className="text-xs text-gray-400">
            <span className="text-neon-green font-semibold">
              {pendingCount} active signal{pendingCount > 1 ? "s" : ""}
            </span>{" "}
            sorted by soonest expiry. Expired markets are automatically removed.
          </p>
          {balance !== undefined && (
            <span className="text-xs font-mono text-neon-green flex-shrink-0 ml-3">
              ${balance.toFixed(2)} avail.
            </span>
          )}
        </div>
      )}

      {/* ── Filters row ────────────────────────────────────── */}
      <div className="flex flex-col gap-2">
        {/* Status tabs */}
        <div className="flex gap-1">
          {STATUS_FILTERS.map((f) => (
            <button
              key={f.value}
              onClick={() => setStatusFilter(f.value)}
              className={clsx(
                "text-xs px-3 py-1 rounded border transition-all",
                statusFilter === f.value
                  ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                  : "border-bg-border text-gray-500 hover:border-gray-500"
              )}
            >
              {f.label}
              {f.value === "pending" && pendingCount > 0 && (
                <span className="ml-1 text-neon-green">({pendingCount})</span>
              )}
            </button>
          ))}
        </div>

        {/* Category chips */}
        <div className="flex gap-1.5 flex-wrap">
          {CATEGORY_FILTERS.map((f) => {
            const count = activeSuggestions.filter(
              (s) => (statusFilter === "all" || s.status === statusFilter) &&
                     (f.value === "all" || s.category === f.value)
            ).length;
            return (
              <button
                key={f.value}
                onClick={() => setCategoryFilter(f.value)}
                className={clsx(
                  "flex items-center gap-1 text-[11px] px-2.5 py-1 rounded-full border transition-all",
                  categoryFilter === f.value
                    ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                    : "border-bg-border text-gray-500 hover:border-gray-500"
                )}
              >
                <span>{f.icon}</span>
                <span>{f.label}</span>
                {count > 0 && (
                  <span className={clsx(
                    "text-[10px] font-bold",
                    categoryFilter === f.value ? "text-neon-violet" : "text-gray-600"
                  )}>
                    {count}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Cards ──────────────────────────────────────────── */}
      <div className="flex flex-col gap-3">
        {sorted.length === 0 ? (
          <div className="joker-card p-8 text-center">
            <p className="text-gray-600 text-sm">
              {statusFilter === "pending"
                ? "No active signals. Agents are scanning markets..."
                : `No ${statusFilter === "all" ? "" : statusFilter + " "}signals${categoryFilter !== "all" ? ` in ${categoryFilter}` : ""}.`}
            </p>
            <p className="text-[10px] text-gray-700 mt-2 font-mono">[agents running in background]</p>
          </div>
        ) : (
          sorted.map((s) => (
            <SuggestionCard
              key={s.id}
              suggestion={s}
              balance={balance}
              onApprove={handleApprove}
              onReject={handleReject}
            />
          ))
        )}
      </div>
    </div>
  );
}
