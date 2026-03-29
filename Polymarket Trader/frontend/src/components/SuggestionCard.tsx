"use client";
import { useState } from "react";
import type { Suggestion } from "@/types";
import TimeAgo from "./TimeAgo";
import { useMounted } from "@/hooks/useMounted";
import clsx from "clsx";

const CATEGORY_ICONS: Record<string, string> = {
  politics:               "🏛",
  crypto:                 "₿",
  sports:                 "⚽",
  science:                "🔬",
  strategy_scout:         "🕵",
  whale_watcher:          "🐋",
  orchestrator:           "♠",
  event_evaluator:        "🎯",
  strategy_evaluator:     "⚖",
  position_advisor:       "🛡",
  entry_analyst:          "🔎",
  opportunity_optimizer:  "📊",
};

const PRESET_AMOUNTS = [5, 10, 25, 50, 100];

const CONFIDENCE_LABELS: { min: number; label: string; desc: string }[] = [
  { min: 85, label: "Very High", desc: "Strong edge detected — LLM & data strongly agree" },
  { min: 70, label: "High",      desc: "Good opportunity — sentiment and price diverge clearly" },
  { min: 55, label: "Moderate",  desc: "Possible edge — some uncertainty in the analysis" },
  { min: 40, label: "Low",       desc: "Weak signal — proceed with caution, high uncertainty" },
  { min: 0,  label: "Very Low",  desc: "Speculative — minimal evidence, high risk" },
];

function getConfidenceInfo(pct: number) {
  for (const c of CONFIDENCE_LABELS) {
    if (pct >= c.min) return c;
  }
  return CONFIDENCE_LABELS[CONFIDENCE_LABELS.length - 1];
}

interface Props {
  suggestion: Suggestion;
  balance?: number;
  onApprove: (id: string, amount: number) => Promise<void>;
  onReject:  (id: string) => Promise<void>;
}

export default function SuggestionCard({ suggestion, balance, onApprove, onReject }: Props) {
  const mounted = useMounted();
  const [loading,   setLoading]   = useState<"approve" | "reject" | null>(null);
  const [expanded,  setExpanded]  = useState(false);
  const [showApproveForm, setShowApproveForm] = useState(false);
  const [amount, setAmount] = useState(10);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const isPending    = suggestion.status === "pending";
  const confidencePct = Math.round(suggestion.confidence_score * 100);
  const confidenceColor =
    confidencePct >= 75 ? "#39FF14" : confidencePct >= 55 ? "#FFE000" : "#FF073A";
  const confInfo = getConfidenceInfo(confidencePct);

  const expiryInfo = (() => {
    if (!mounted || !suggestion.end_date) return null;
    const ms   = new Date(suggestion.end_date).getTime() - Date.now();
    const hrs  = ms / 3_600_000;
    if (hrs < 0)   return { label: "EXPIRED",  color: "text-gray-500" };
    if (hrs < 6)   return { label: `${Math.round(hrs * 60)}m left`,  color: "text-neon-red glow-red animate-pulse-slow" };
    if (hrs < 24)  return { label: `${Math.round(hrs)}h left`,       color: "text-neon-yellow" };
    const days = Math.floor(hrs / 24);
    return { label: `${days}d left`, color: "text-gray-400" };
  })();

  const handleApprove = async () => {
    setLoading("approve");
    setErrorMsg(null);
    try {
      await onApprove(suggestion.id, amount);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setErrorMsg(msg);
    }
    setLoading(null);
    setShowApproveForm(false);
  };

  const handleReject = async () => {
    setLoading("reject");
    await onReject(suggestion.id);
    setLoading(null);
  };

  return (
    <div className={clsx(
      "joker-card p-4 transition-all duration-200",
      suggestion.status === "executed" && "border-[#39FF1444] opacity-70",
      suggestion.status === "rejected" && "border-[#FF073A22] opacity-50",
      suggestion.status === "failed"   && "border-[#FF073A88]",
      isPending && expiryInfo?.color.includes("neon-red") && "border-[#FF073A66]",
      isPending && !expiryInfo?.color.includes("neon-red") && "border-[#BC13FE33]",
    )}>
      {/* ── Top row ──────────────────────────────────────────── */}
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex items-start gap-2 min-w-0">
          <span className="text-xl mt-0.5">{CATEGORY_ICONS[suggestion.category] ?? "◈"}</span>
          <div className="min-w-0">
            <p className="text-sm text-gray-200 leading-snug line-clamp-2">
              {suggestion.market_question}
            </p>
            <div className="flex flex-wrap items-center gap-2 mt-0.5">
              <span className="text-[10px] text-gray-500">{suggestion.agent_name}</span>
              <span className="text-[10px] text-gray-600">·</span>
              <TimeAgo date={suggestion.created_at} className="text-[10px] text-gray-500" />
              {expiryInfo && (
                <>
                  <span className="text-[10px] text-gray-600">·</span>
                  <span className={clsx("text-[10px] font-semibold", expiryInfo.color)}>
                    ⏱ {expiryInfo.label}
                  </span>
                </>
              )}
              {suggestion.market_url && (
                <>
                  <span className="text-[10px] text-gray-600">·</span>
                  <a
                    href={suggestion.market_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    onClick={(e) => e.stopPropagation()}
                    className="text-[10px] text-neon-violet hover:underline"
                  >
                    ↗ View market
                  </a>
                </>
              )}
            </div>
          </div>
        </div>

        <span className={clsx(
          "badge flex-shrink-0 text-[10px]",
          suggestion.status === "pending"  && "badge-running",
          suggestion.status === "executed" && "badge-ready",
          suggestion.status === "rejected" && "badge-idle",
          suggestion.status === "approved" && "badge-investigating",
          suggestion.status === "failed"   && "badge-error",
        )}>
          {suggestion.status}
        </span>
      </div>

      {/* ── Direction + price ─────────────────────────────────── */}
      <div className="mb-3">
        <div className="flex items-center gap-3">
          <span className={clsx(
            "font-title text-2xl font-bold tracking-wider",
            suggestion.direction === "BUY" ? "text-neon-green glow-green" : "text-neon-red glow-red"
          )}>
            {suggestion.direction}
          </span>
          <span className="text-gray-400 text-sm">&quot;{suggestion.outcome}&quot;</span>
          <div className="ml-auto text-right">
            <span className="font-mono text-sm text-gray-300">
              @ <span className="text-white font-semibold">{suggestion.price_at_discovery.toFixed(3)}</span>
            </span>
            <span className="text-[10px] text-gray-600 block">
              {(suggestion.price_at_discovery * 100).toFixed(1)}% implied prob.
            </span>
          </div>
        </div>
        {/* Trade explanation */}
        <div className={clsx(
          "mt-2 p-2 rounded text-[10px] leading-relaxed border",
          suggestion.direction === "BUY"
            ? "bg-[#0a1a0a] border-[#39FF1422] text-gray-400"
            : "bg-[#1a0a0a] border-[#FF073A22] text-gray-400"
        )}>
          {suggestion.direction === "BUY" ? (
            <>
              <span className="text-neon-green font-semibold">BUY</span>{" "}
              &quot;{suggestion.outcome}&quot; shares at{" "}
              <span className="text-white font-mono">${suggestion.price_at_discovery.toFixed(2)}</span> each.
              {suggestion.outcome.toLowerCase() === "yes" ? (
                <> The AI believes this event <strong className="text-white">will happen</strong>. If correct, each share pays <span className="text-neon-green font-mono">$1.00</span> — potential return of <span className="text-neon-green font-semibold">+{(((1 - suggestion.price_at_discovery) / suggestion.price_at_discovery) * 100).toFixed(0)}%</span>.</>
              ) : (
                <> The AI believes this outcome is underpriced. If correct, each share pays <span className="text-neon-green font-mono">$1.00</span> — potential return of <span className="text-neon-green font-semibold">+{(((1 - suggestion.price_at_discovery) / suggestion.price_at_discovery) * 100).toFixed(0)}%</span>.</>
              )}
            </>
          ) : (
            <>
              <span className="text-neon-red font-semibold">SELL</span>{" "}
              your &quot;{suggestion.outcome}&quot; shares at{" "}
              <span className="text-white font-mono">${suggestion.price_at_discovery.toFixed(2)}</span> each.
              {" "}The AI thinks this outcome is overpriced and recommends locking in profit or cutting losses before the price drops.
            </>
          )}
        </div>
      </div>

      {/* ── Confidence bar + explanation ────────────────────────── */}
      <div className="mb-3">
        <div className="flex justify-between text-[10px] text-gray-500 mb-1">
          <span>
            Confidence —{" "}
            <span style={{ color: confidenceColor }} className="font-semibold">
              {confInfo.label}
            </span>
          </span>
          <span style={{ color: confidenceColor }} className="font-semibold">
            {confidencePct}%
          </span>
        </div>
        <div className="confidence-bar">
          <div className="confidence-fill" style={{
            width: `${confidencePct}%`,
            background: confidenceColor,
            boxShadow: `0 0 6px ${confidenceColor}`,
          }} />
        </div>
        <p className="text-[9px] text-gray-600 mt-1">
          {confInfo.desc}
        </p>
      </div>

      {/* ── Tags ─────────────────────────────────────────────── */}
      {suggestion.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-3">
          {suggestion.tags.map((tag) => (
            <span key={tag} className="text-[10px] px-2 py-0.5 rounded-full bg-[#2a2a2a] text-gray-400">
              #{tag}
            </span>
          ))}
        </div>
      )}

      {/* ── Reasoning (collapsible) ───────────────────────────── */}
      <div className="mb-4">
        <button
          onClick={() => setExpanded(!expanded)}
          className="text-[10px] text-neon-violet uppercase tracking-widest hover:text-white transition-colors"
        >
          {expanded ? "▼ Hide analysis" : "▶ Show agent analysis"}
        </button>
        {expanded && (
          <div className="mt-2 p-3 bg-[#0a0a0a] rounded border border-[#2a2a2a] text-xs text-gray-300 leading-relaxed">
            {suggestion.reasoning || "No reasoning available."}
          </div>
        )}
      </div>

      {/* ── Action buttons ────────────────────────────────────── */}
      {isPending && !showApproveForm && (
        <div className="flex gap-2">
          <button
            className="btn-approve flex-1"
            onClick={() => { setShowApproveForm(true); setErrorMsg(null); }}
            disabled={loading !== null}
          >
            ✓ Approve
          </button>
          <button
            className="btn-reject flex-1"
            onClick={handleReject}
            disabled={loading !== null}
          >
            {loading === "reject" ? "..." : "✕ Reject"}
          </button>
        </div>
      )}

      {/* ── Approve form with amount ──────────────────────────── */}
      {isPending && showApproveForm && (
        <div className="border border-[#39FF1444] rounded p-3 bg-[#0a1a0a] space-y-3">
          <p className="text-[10px] text-neon-green uppercase tracking-widest">Confirm trade</p>

          {/* Preset buttons */}
          <div className="flex gap-1.5 flex-wrap">
            {PRESET_AMOUNTS.map((p) => (
              <button
                key={p}
                onClick={() => setAmount(p)}
                className={clsx(
                  "text-xs px-2.5 py-1 rounded border transition-all",
                  amount === p
                    ? "border-neon-green text-neon-green bg-[#39FF1420]"
                    : "border-bg-border text-gray-500 hover:border-gray-400"
                )}
              >
                ${p}
              </button>
            ))}
          </div>

          {/* Custom amount */}
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-500">Custom:</span>
            <div className="relative flex-1">
              <span className="absolute left-2 top-1/2 -translate-y-1/2 text-gray-500 text-xs">$</span>
              <input
                type="number"
                min={1}
                step={1}
                value={amount}
                onChange={(e) => setAmount(Math.max(1, Number(e.target.value)))}
                className="w-full pl-5 pr-3 py-1.5 bg-[#1a1a1a] border border-bg-border rounded text-xs text-white font-mono focus:border-neon-green outline-none"
              />
            </div>
            {balance !== undefined && (
              <span className="text-[10px] text-gray-600 whitespace-nowrap">
                / ${balance.toFixed(2)} avail.
              </span>
            )}
          </div>

          {/* Summary */}
          <div className="text-[10px] text-gray-500 bg-[#111] rounded p-2 font-mono">
            <span className={suggestion.direction === "BUY" ? "text-neon-green" : "text-neon-red"}>
              {suggestion.direction}
            </span>
            {" "}{suggestion.outcome} @ {suggestion.price_at_discovery.toFixed(3)}
            {" · "}
            <span className="text-white">${amount.toFixed(2)} USDC</span>
            {" → ≈ "}
            <span className="text-neon-green">
              {(amount / suggestion.price_at_discovery).toFixed(2)} shares
            </span>
          </div>

          {/* Confidence reminder */}
          <div className="flex items-center gap-2 text-[10px]">
            <span className="text-gray-600">Agent confidence:</span>
            <span style={{ color: confidenceColor }} className="font-semibold">{confidencePct}% — {confInfo.label}</span>
          </div>

          <div className="flex gap-2">
            <button
              className="btn-approve flex-1 text-sm"
              onClick={handleApprove}
              disabled={loading !== null || amount <= 0}
            >
              {loading === "approve" ? "Executing..." : `✓ Execute $${amount}`}
            </button>
            <button
              onClick={() => setShowApproveForm(false)}
              className="px-3 py-1.5 text-xs border border-bg-border text-gray-500 rounded hover:border-gray-400 transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* ── Execution result ────────────────────────────────────── */}
      {suggestion.status === "executed" && suggestion.execution_tx && (
        <div className="mt-2 p-2 bg-[#0a1a0a] rounded border border-[#39FF1433]">
          <p className="text-[10px] text-neon-green font-mono truncate">
            ✓ {suggestion.execution_tx}
          </p>
        </div>
      )}
      {suggestion.status === "failed" && (
        <div className="mt-2 p-2 bg-[#1a0a0a] rounded border border-[#FF073A33]">
          <p className="text-[10px] text-neon-red">
            ✕ Execution failed — the order was not placed. Check Config for valid API credentials.
          </p>
        </div>
      )}
      {errorMsg && (
        <div className="mt-2 p-2 bg-[#1a0a0a] rounded border border-[#FF073A33]">
          <p className="text-[10px] text-neon-red">
            Error: {errorMsg}
          </p>
        </div>
      )}
    </div>
  );
}
