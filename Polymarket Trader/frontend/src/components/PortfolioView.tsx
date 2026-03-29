"use client";
import { useEffect, useState } from "react";
import type { Portfolio, Position } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import TimeAgo from "./TimeAgo";
import clsx from "clsx";

interface Props {
  portfolioOverride?: Portfolio | null;
  onRefresh?: () => void;
}

export default function PortfolioView({ portfolioOverride, onRefresh }: Props) {
  const [portfolio, setPortfolio] = useState<Portfolio | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchPortfolio = async () => {
    try {
      // Cache-bust so Refresh always hits backend and last_updated updates
      const res = await apiFetch<Portfolio>(`/api/portfolio?t=${Date.now()}`);
      setPortfolio(res.data);
      return res.data;
    } catch {
      return null;
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    if (portfolioOverride) {
      setPortfolio(portfolioOverride);
      setLoading(false);
    }
  }, [portfolioOverride]);

  useEffect(() => {
    fetchPortfolio();
    const interval = setInterval(fetchPortfolio, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleRefresh = async () => {
    setRefreshing(true);
    await fetchPortfolio();
    onRefresh?.();
  };

  if (loading) {
    return (
      <section className="flex flex-col gap-4">
        <div className="animate-pulse space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-12 bg-[#1a1a1a] rounded" />
          ))}
        </div>
      </section>
    );
  }

  if (!portfolio) {
    return (
      <section className="flex flex-col gap-4">
        <div className="joker-card p-8 text-center">
          <p className="text-sm text-gray-600">
            Unable to load portfolio. Check API credentials in Config tab.
          </p>
        </div>
      </section>
    );
  }

  const pnlPositive = portfolio.total_pnl >= 0;
  const isLive = portfolio.source === "live";

  return (
    <section className="flex flex-col gap-4 max-w-2xl">
      {/* Live vs Demo + Refresh */}
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          {isLive ? (
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-[#39FF1422] text-neon-green border border-[#39FF1444] font-mono uppercase">
              Live from Polymarket
            </span>
          ) : (
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-[#FFE00022] text-neon-yellow border border-[#FFE00044] font-mono uppercase">
              Demo data
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {portfolio.last_updated && (
            <span className="text-[10px] text-gray-600">
              Updated <TimeAgo date={portfolio.last_updated} />
            </span>
          )}
          <button
            type="button"
            onClick={handleRefresh}
            disabled={refreshing}
            className="text-[10px] px-2 py-1 rounded border border-neon-violet text-neon-violet hover:bg-[#BC13FE15] transition-colors disabled:opacity-50"
          >
            {refreshing ? "Refreshing…" : "Refresh"}
          </button>
        </div>
      </div>

      {!isLive && (
        <div className="joker-card p-3 border-l-2 border-neon-yellow">
          <p className="text-xs text-gray-400">
            Add your <strong className="text-neon-yellow">Polymarket API key, secret and passphrase</strong> in the{" "}
            <strong>Config</strong> tab, then save and click <strong>Refresh</strong> to see your real balance and positions.
          </p>
        </div>
      )}

      {/* Summary stats */}
      <div className="grid grid-cols-2 gap-2">
        <StatCard
          label="Balance"
          value={`$${portfolio.balance_usdc.toFixed(2)}`}
          valueClass="text-white"
        />
        <StatCard
          label="Positions Value"
          value={`$${portfolio.total_positions_value.toFixed(2)}`}
          valueClass="text-white"
        />
        <StatCard
          label="Total P&L"
          value={`${pnlPositive ? "+" : ""}$${portfolio.total_pnl.toFixed(2)}`}
          valueClass={pnlPositive ? "text-neon-green glow-green" : "text-neon-red glow-red"}
        />
        <StatCard
          label="Return"
          value={`${pnlPositive ? "+" : ""}${portfolio.total_pnl_pct.toFixed(2)}%`}
          valueClass={pnlPositive ? "text-neon-green" : "text-neon-red"}
        />
      </div>

      {/* Positions */}
      <div className="joker-card p-4">
        <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-3">
          Open Positions ({portfolio.positions.length})
        </p>
        {portfolio.positions.length === 0 ? (
          <div className="py-4 space-y-2">
            <p className="text-sm text-gray-600 text-center">No open positions.</p>
            {portfolio.positions_note && (
              <p className="text-xs text-neon-yellow/90 border border-neon-yellow/30 rounded p-3 bg-[#FFE00008]">
                {portfolio.positions_note}
              </p>
            )}
          </div>
        ) : (
          <div className="flex flex-col gap-4">
            {Object.entries(
              portfolio.positions.reduce((acc, pos) => {
                const cat = pos.category || "Other";
                if (!acc[cat]) acc[cat] = [];
                acc[cat].push(pos);
                return acc;
              }, {} as Record<string, Position[]>)
            ).map(([category, positions]) => (
              <div key={category} className="space-y-2">
                <h3 className="text-xs font-mono text-neon-violet uppercase border-b border-bg-border pb-1">
                  {category}
                </h3>
                {positions.map((pos, i) => (
                  <PositionRow key={i} position={pos} />
                ))}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Open orders on the book (CLOB) — same source as test.ipynb get_orders */}
      {portfolio.open_orders && portfolio.open_orders.length > 0 && (
        <div className="joker-card p-4">
          <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-3">
            Open orders on book ({portfolio.open_orders.length})
          </p>
          <div className="flex flex-col gap-2">
            {portfolio.open_orders.map((o, i) => (
              <div
                key={o.id || i}
                className="border border-bg-border rounded p-2 text-xs font-mono text-gray-400"
              >
                <span className="text-neon-violet">{String(o.side || "—").toUpperCase()}</span>
                {" · "}
                price {o.price ?? "—"} · remaining {o.size_remaining ?? "—"}
                {o.token_id ? (
                  <span className="block text-[10px] text-gray-600 truncate mt-1">
                    token {String(o.token_id).slice(0, 24)}…
                  </span>
                ) : null}
              </div>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

function StatCard({
  label,
  value,
  valueClass,
}: {
  label: string;
  value: string;
  valueClass: string;
}) {
  return (
    <div className="bg-[#1a1a1a] rounded p-3 border border-bg-border">
      <p className="text-[10px] text-gray-600 uppercase tracking-widest mb-1">{label}</p>
      <p className={clsx("font-mono font-semibold text-sm", valueClass)}>{value}</p>
    </div>
  );
}

function PositionRow({ position }: { position: Position }) {
  const pnlPositive = position.pnl >= 0;
  return (
    <div className="border border-bg-border rounded p-3 hover:border-[#BC13FE44] transition-colors relative group">
      {position.market_url && (
        <a
          href={position.market_url}
          target="_blank"
          rel="noopener noreferrer"
          className="absolute top-2 right-2 text-xs text-neon-violet opacity-0 group-hover:opacity-100 transition-opacity"
          title="View on Polymarket"
        >
          ↗
        </a>
      )}
      <div className="flex justify-between items-start gap-2">
        <div className="min-w-0 flex-1 pr-6">
          <p className="text-xs text-gray-300 line-clamp-2">
            {position.market_url ? (
              <a href={position.market_url} target="_blank" rel="noopener noreferrer" className="hover:text-neon-violet transition-colors">
                {position.market_question}
              </a>
            ) : (
              position.market_question
            )}
          </p>
          <p className="text-[10px] text-gray-600 mt-0.5">
            <span className="text-gray-400 font-mono">{position.outcome}</span> • {position.size.toFixed(2)} shares
          </p>
        </div>
        <div className="text-right flex-shrink-0">
          <p
            className={clsx(
              "text-sm font-mono font-semibold",
              pnlPositive ? "text-neon-green" : "text-neon-red"
            )}
          >
            {pnlPositive ? "+" : ""}${position.pnl.toFixed(2)}
          </p>
          <p className="text-[10px] text-gray-600">
            {position.avg_price.toFixed(3)} → {position.current_price.toFixed(3)}
          </p>
        </div>
      </div>
    </div>
  );
}
