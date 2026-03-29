"use client";
import { useEffect, useState } from "react";
import type { MarketEvent } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import clsx from "clsx";

type TermFilter = "all" | "short" | "medium" | "long";

const TERM_FILTERS: { id: TermFilter; label: string; desc: string }[] = [
  { id: "all",    label: "All",          desc: "Up to 1 year" },
  { id: "short",  label: "Short Term",   desc: "< 7 days" },
  { id: "medium", label: "Medium Term",  desc: "7 – 90 days" },
  { id: "long",   label: "Long Term",    desc: "90 – 365 days" },
];

const CATEGORY_FILTERS = [
  { id: "all", label: "All", icon: "◈" },
  { id: "politics", label: "Politics", icon: "🏛" },
  { id: "crypto", label: "Crypto", icon: "₿" },
  { id: "sports", label: "Sports", icon: "⚽" },
  { id: "science", label: "Science", icon: "🔬" },
];

export default function EventsPanel() {
  const [events, setEvents] = useState<MarketEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [term, setTerm] = useState<TermFilter>("all");
  const [category, setCategory] = useState("all");
  const [expanded, setExpanded] = useState<string | null>(null);

  const fetchEvents = async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (term !== "all") params.set("term", term);
      if (category !== "all") params.set("category", category);
      params.set("limit", "50");
      const res = await apiFetch<MarketEvent[]>(`/api/events?${params}`);
      if (res.data) setEvents(res.data);
    } catch {
      /* ignore */
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchEvents(); }, [term, category]);

  const urgencyColor = (daysLeft: number | null) => {
    if (daysLeft === null) return "text-gray-500";
    if (daysLeft <= 1) return "text-neon-red animate-pulse-slow";
    if (daysLeft <= 7) return "text-neon-red";
    if (daysLeft <= 30) return "text-neon-yellow";
    if (daysLeft <= 90) return "text-neon-blue";
    return "text-gray-400";
  };

  const formatDaysLeft = (d: number | null) => {
    if (d === null) return "No expiry";
    if (d <= 0) return "Expiring today";
    if (d === 1) return "1 day left";
    if (d <= 7) return `${d}d left`;
    if (d <= 30) return `${d}d (~${Math.round(d / 7)}w)`;
    if (d <= 365) return `${d}d (~${Math.round(d / 30)}mo)`;
    return `${d}d`;
  };

  return (
    <div className="flex flex-col gap-4">
      {/* Header with explanation */}
      <div className="joker-card p-3 border-l-2 border-neon-blue space-y-2">
        <p className="text-xs text-gray-400">
          Browse <span className="text-neon-blue font-semibold">{events.length}</span> active
          Polymarket events. Each event is a question with <span className="text-neon-green">Yes</span> / <span className="text-neon-red">No</span> outcomes.
          The <span className="text-white">Yes price</span> = market's probability that the event will happen.
        </p>
        <div className="flex gap-4 text-[10px]">
          <span className="text-gray-500">
            <span className="text-neon-green font-semibold">BUY Yes</span> = you think it WILL happen
          </span>
          <span className="text-gray-500">
            <span className="text-neon-red font-semibold">BUY No</span> = you think it WON'T happen
          </span>
          <span className="text-gray-500">
            Payout: <span className="text-white">$1.00</span> per share if correct
          </span>
        </div>
      </div>

      {/* Term filter */}
      <div className="flex gap-2 flex-wrap">
        {TERM_FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setTerm(f.id)}
            className={clsx(
              "flex flex-col px-4 py-2 rounded border transition-all text-left",
              term === f.id
                ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                : "border-bg-border text-gray-500 hover:border-gray-500"
            )}
          >
            <span className="text-xs font-semibold">{f.label}</span>
            <span className="text-[10px] opacity-70">{f.desc}</span>
          </button>
        ))}
      </div>

      {/* Category chips */}
      <div className="flex gap-1.5 flex-wrap">
        {CATEGORY_FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setCategory(f.id)}
            className={clsx(
              "flex items-center gap-1 text-[11px] px-2.5 py-1 rounded-full border transition-all",
              category === f.id
                ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                : "border-bg-border text-gray-500 hover:border-gray-500"
            )}
          >
            <span>{f.icon}</span>
            <span>{f.label}</span>
          </button>
        ))}
      </div>

      {/* Events list */}
      {loading ? (
        <div className="animate-pulse space-y-3">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-16 bg-[#1a1a1a] rounded" />
          ))}
        </div>
      ) : events.length === 0 ? (
        <div className="joker-card p-8 text-center">
          <p className="text-gray-600 text-sm">
            No events found for this filter.
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {events.map((ev) => {
            const yesPrice = ev.yes_price;
            const noPrice = Math.max(0, 1 - yesPrice);
            const yesProfitPer = (1 - yesPrice);
            const noProfitPer = (1 - noPrice);
            const isExpanded = expanded === ev.id;

            return (
              <div
                key={ev.id}
                className={clsx(
                  "joker-card p-3 cursor-pointer transition-all",
                  isExpanded ? "border-[#BC13FE55]" : "hover:border-[#BC13FE44]"
                )}
                onClick={() => setExpanded(isExpanded ? null : ev.id)}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm text-gray-200 leading-snug line-clamp-2">
                      {ev.market_url ? (
                        <a
                          href={ev.market_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          onClick={(e) => e.stopPropagation()}
                          className="hover:text-neon-violet transition-colors"
                        >
                          {ev.question}
                        </a>
                      ) : (
                        ev.question
                      )}
                    </p>
                    <div className="flex items-center gap-2 mt-1 flex-wrap">
                      <span className="text-[10px] px-1.5 py-0.5 bg-[#2a2a2a] rounded text-gray-400">
                        {ev.category}
                      </span>
                      <span className={clsx("text-[10px] font-semibold", urgencyColor(ev.days_left))}>
                        ⏱ {formatDaysLeft(ev.days_left)}
                      </span>
                      {ev.volume > 0 && (
                        <span className="text-[10px] text-gray-600">
                          Vol: ${(ev.volume / 1000).toFixed(0)}k
                        </span>
                      )}
                      {ev.liquidity > 0 && (
                        <span className="text-[10px] text-gray-600">
                          Liq: ${(ev.liquidity / 1000).toFixed(0)}k
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="flex-shrink-0 text-right">
                    <p className="text-sm font-mono font-semibold text-white">
                      {(yesPrice * 100).toFixed(1)}%
                    </p>
                    <p className="text-[10px] text-gray-600">Yes price</p>
                  </div>
                </div>

                {/* Yes/No price bar */}
                <div className="mt-2 flex items-center gap-1">
                  <div className="flex-1 h-2 bg-[#2a2a2a] rounded-full overflow-hidden flex">
                    <div
                      className="h-full rounded-l-full"
                      style={{
                        width: `${yesPrice * 100}%`,
                        background: "#39FF14",
                        boxShadow: "0 0 4px #39FF14",
                      }}
                    />
                    <div
                      className="h-full rounded-r-full"
                      style={{
                        width: `${noPrice * 100}%`,
                        background: "#FF073A",
                        boxShadow: "0 0 4px #FF073A",
                      }}
                    />
                  </div>
                </div>
                <div className="flex justify-between mt-1">
                  <span className="text-[9px] text-neon-green font-mono">
                    Yes ${yesPrice.toFixed(2)}
                  </span>
                  <span className="text-[9px] text-neon-red font-mono">
                    No ${noPrice.toFixed(2)}
                  </span>
                </div>

                {/* Expanded: Buy/Sell explanation + link */}
                {isExpanded && (
                  <div className="mt-3 border-t border-bg-border pt-3 space-y-3">
                    <p className="text-[10px] text-gray-600 uppercase tracking-widest">How to trade this event</p>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                      <div className="bg-[#0a1a0a] border border-[#39FF1433] rounded p-2.5">
                        <p className="text-xs font-bold text-neon-green">BUY "Yes" @ ${yesPrice.toFixed(2)}</p>
                        <p className="text-[10px] text-gray-400 mt-1">
                          You believe this <strong className="text-white">will happen</strong>.
                          Pay ${yesPrice.toFixed(2)} per share, receive $1.00 if correct.
                        </p>
                        <p className="text-[10px] text-neon-green mt-1">
                          Potential profit: +${yesProfitPer.toFixed(2)} per share ({((yesProfitPer / yesPrice) * 100).toFixed(0)}% return)
                        </p>
                      </div>
                      <div className="bg-[#1a0a0a] border border-[#FF073A33] rounded p-2.5">
                        <p className="text-xs font-bold text-neon-red">BUY "No" @ ${noPrice.toFixed(2)}</p>
                        <p className="text-[10px] text-gray-400 mt-1">
                          You believe this <strong className="text-white">won't happen</strong>.
                          Pay ${noPrice.toFixed(2)} per share, receive $1.00 if correct.
                        </p>
                        <p className="text-[10px] text-neon-green mt-1">
                          Potential profit: +${noProfitPer.toFixed(2)} per share ({((noProfitPer / noPrice) * 100).toFixed(0)}% return)
                        </p>
                      </div>
                    </div>

                    {ev.market_url && (
                      <a
                        href={ev.market_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        onClick={(e) => e.stopPropagation()}
                        className="flex items-center justify-center gap-2 w-full py-2 rounded border border-neon-violet text-neon-violet text-xs hover:bg-[#BC13FE15] transition-colors"
                      >
                        ↗ Trade on Polymarket
                      </a>
                    )}

                    <p className="text-[9px] text-gray-600 text-center">
                      Or wait for agents to generate a signal with their analysis in the Signals tab
                    </p>
                  </div>
                )}

                <p className="text-[9px] text-gray-700 mt-1 text-right">
                  {isExpanded ? "▲ collapse" : "▼ tap for trading details"}
                </p>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
