"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { BitcoinMarket, BitcoinSignal, Portfolio, TradeDirection } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import clsx from "clsx";

// ─────────────────────────── Types ───────────────────────────────────

interface Props {
  portfolio: Portfolio | null;
  liveSignals?: BitcoinSignal[];
}

type TimeFilter = "1d" | "3d" | "7d" | "14d" | "30d";

const TIME_OPTS: { id: TimeFilter; label: string; days: number }[] = [
  { id: "1d", label: "24H", days: 1 },
  { id: "3d", label: "3D",  days: 3 },
  { id: "7d", label: "7D",  days: 7 },
  { id: "14d", label: "14D", days: 14 },
  { id: "30d", label: "30D", days: 30 },
];

// ─────────────────────────── Helpers ─────────────────────────────────

function fmtTime(hours: number): string {
  if (hours < 1) return `${Math.round(hours * 60)}m`;
  if (hours < 24) return `${hours.toFixed(1)}h`;
  return `${(hours / 24).toFixed(1)}d`;
}

function fmtUSD(n: number): string {
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000)    return `$${(n / 1_000).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}

/**
 * Mercado binario Polymarket: pagas `stake` USDC a precio límite p por acción del outcome.
 * Si ganas, cada acción paga $1 → bruto ≈ stake/p, neto ≈ stake/p − stake. Sin fees ni slippage.
 * SELL en la UI = apuesta al lado NO usando precio implícito (1 − precio YES).
 */
function payoutPreview(direction: TradeDirection, yesPrice: number, stake: number) {
  const p = yesPrice;
  if (!(stake > 0) || p <= 0.001 || p >= 0.999) return null;
  if (direction === "BUY") {
    const shares = stake / p;
    const payoutGross = shares;
    const profitNet = payoutGross - stake;
    return { outcomeLabel: "YES gana", payoutGross, profitNet, maxLoss: stake };
  }
  const pNo = 1 - p;
  if (pNo <= 0.001 || pNo >= 0.999) return null;
  const shares = stake / pNo;
  const payoutGross = shares;
  const profitNet = payoutGross - stake;
  return { outcomeLabel: "NO gana", payoutGross, profitNet, maxLoss: stake };
}

/** Valor esperado en USDC usando la prob. del modelo (win_probability = P(YES)). */
function evUSDC(direction: TradeDirection, pYesModel: number, preview: NonNullable<ReturnType<typeof payoutPreview>>) {
  const p = Math.min(0.99, Math.max(0.01, pYesModel));
  if (direction === "BUY") {
    return p * preview.profitNet - (1 - p) * preview.maxLoss;
  }
  return (1 - p) * preview.profitNet - p * preview.maxLoss;
}

function qualityColor(q: string) {
  if (q === "strong")   return "text-neon-green border-neon-green bg-[#39FF1415]";
  if (q === "moderate") return "text-yellow-400 border-yellow-600 bg-[#EAB30815]";
  return "text-gray-500 border-gray-700 bg-[#ffffff08]";
}

function dirColor(dir: string) {
  return dir === "BUY"
    ? "text-neon-green bg-[#39FF1420] border-neon-green"
    : "text-neon-red   bg-[#FF003C20] border-neon-red";
}

function urgencyDot(u: string) {
  if (u === "high")   return "bg-neon-red animate-pulse";
  if (u === "medium") return "bg-yellow-400";
  return "bg-gray-600";
}

function sentimentIcon(s: string) {
  if (s === "bullish") return { icon: "▲", cls: "text-neon-green" };
  if (s === "bearish") return { icon: "▼", cls: "text-neon-red" };
  return { icon: "—", cls: "text-gray-500" };
}

// ─────────────────────────── Sub-components ──────────────────────────

function AgentBadge({ label, value, active }: { label: string; value: string; active?: boolean }) {
  return (
    <div className={clsx(
      "flex flex-col items-center px-2 py-1 rounded border text-[9px] font-mono gap-0.5",
      active ? "border-neon-violet text-neon-violet bg-[#BC13FE15]" : "border-gray-800 text-gray-500",
    )}>
      <span className="uppercase tracking-widest opacity-60">{label}</span>
      <span className="font-bold">{value}</span>
    </div>
  );
}

function ConfBar({ value, color }: { value: number; color: string }) {
  return (
    <div className="h-1 w-full bg-gray-800 rounded-full overflow-hidden">
      <div
        className={clsx("h-full rounded-full transition-all duration-700", color)}
        style={{ width: `${Math.round(value * 100)}%` }}
      />
    </div>
  );
}

function SignalCard({
  signal,
  balance,
}: {
  signal: BitcoinSignal;
  balance: number;
}) {
  const [amount, setAmount] = useState<string>(() => {
    const suggested = balance > 0 ? (balance * signal.suggested_amount_pct) / 100 : 10;
    return String(Math.max(1, Math.round(suggested)));
  });
  const [trading, setTrading] = useState(false);
  const [tradeResult, setTradeResult] = useState<{ ok: boolean; msg: string } | null>(null);

  const suggestedUSDC = balance > 0
    ? Math.max(1, Math.round((balance * signal.suggested_amount_pct) / 100))
    : 0;

  const stakeNum = parseFloat(amount);
  const payPreview =
    Number.isFinite(stakeNum) && stakeNum > 0
      ? payoutPreview(signal.direction, signal.yes_price, stakeNum)
      : null;
  const evApprox = payPreview ? evUSDC(signal.direction, signal.win_probability, payPreview) : null;

  const handleTrade = useCallback(async () => {
    const numAmt = parseFloat(amount);
    if (!numAmt || numAmt <= 0) return;
    setTrading(true);
    setTradeResult(null);
    try {
      const res = await apiFetch<{ tx: string; simulated: boolean }>("/api/bitcoin-trade", {
        method: "POST",
        body: JSON.stringify({
          token_id: signal.market_id,
          direction: signal.direction,
          price: signal.yes_price,
          amount_usdc: numAmt,
        }),
      });
      if (res.success) {
        const label = res.data?.simulated ? "SIMULADO" : "EJECUTADO";
        setTradeResult({ ok: true, msg: `${label}: $${numAmt} USDC — ${res.data?.tx ?? ""}` });
      } else {
        setTradeResult({ ok: false, msg: res.message || "Error al ejecutar" });
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Error de red";
      setTradeResult({ ok: false, msg });
    } finally {
      setTrading(false);
    }
  }, [amount, signal.market_id, signal.direction, signal.yes_price]);

  const ac = signal.agents_consensus;
  const sent = sentimentIcon(ac.btc_sentiment);
  const confPct = Math.round(signal.confidence * 100);
  const winPct  = Math.round(signal.win_probability * 100);

  return (
    <div className={clsx(
      "border rounded-lg p-4 flex flex-col gap-3 transition-all",
      signal.signal_quality === "strong"
        ? "border-neon-green/40 bg-[#39FF1408]"
        : signal.signal_quality === "moderate"
        ? "border-yellow-600/40 bg-[#EAB30808]"
        : "border-gray-800 bg-[#ffffff04]",
    )}>

      {/* ── Header row ─── */}
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2 flex-wrap">
          {/* Urgency dot */}
          <span className={clsx("w-2 h-2 rounded-full flex-shrink-0 mt-0.5", urgencyDot(signal.urgency))} />
          {/* Direction badge */}
          <span className={clsx("text-[10px] font-bold px-2 py-0.5 rounded border", dirColor(signal.direction))}>
            {signal.direction}
          </span>
          {/* Quality badge */}
          <span className={clsx("text-[10px] font-mono px-2 py-0.5 rounded border uppercase", qualityColor(signal.signal_quality))}>
            {signal.signal_quality}
          </span>
          {/* Urgency label */}
          <span className={clsx(
            "text-[9px] font-mono uppercase tracking-widest",
            signal.urgency === "high" ? "text-neon-red" : signal.urgency === "medium" ? "text-yellow-400" : "text-gray-600",
          )}>
            {signal.urgency}
          </span>
        </div>
        <span className="text-[10px] text-gray-600 font-mono flex-shrink-0">
          ⏱ {fmtTime(signal.hours_left)}
        </span>
      </div>

      {/* ── Market question ─── */}
      <p className="text-xs text-gray-200 leading-relaxed">
        {signal.market_question}
        {signal.market_url && (
          <a
            href={signal.market_url}
            target="_blank"
            rel="noopener noreferrer"
            className="ml-2 text-neon-violet hover:underline text-[10px]"
          >
            ↗
          </a>
        )}
      </p>

      {/* ── Key signal ─── */}
      {signal.key_signal && (
        <p className="text-[11px] text-yellow-300 italic border-l-2 border-yellow-600 pl-2">
          {signal.key_signal}
        </p>
      )}

      {/* ── Metrics row ─── */}
      <div className="grid grid-cols-4 gap-2 text-center">
        <Metric label="Precio YES" value={`${(signal.yes_price * 100).toFixed(0)}%`} />
        <Metric label="Win Prob" value={`${winPct}%`} highlight />
        <Metric label="Retorno Est." value={`+${signal.expected_return_pct.toFixed(1)}%`} />
        <Metric label="Volumen" value={fmtUSD(signal.volume)} />
      </div>

      {/* ── Confidence bars ─── */}
      <div className="flex flex-col gap-1">
        <div className="flex justify-between text-[9px] font-mono text-gray-500">
          <span>CONFIANZA</span>
          <span className="text-neon-violet">{confPct}%</span>
        </div>
        <ConfBar value={signal.confidence} color="bg-neon-violet" />
        <div className="flex justify-between text-[9px] font-mono text-gray-500 mt-1">
          <span>PROB. GANAR</span>
          <span className={winPct > 60 ? "text-neon-green" : winPct < 40 ? "text-neon-red" : "text-yellow-400"}>
            {winPct}%
          </span>
        </div>
        <ConfBar
          value={signal.win_probability}
          color={winPct > 60 ? "bg-neon-green" : winPct < 40 ? "bg-neon-red" : "bg-yellow-400"}
        />
      </div>

      {/* ── Agent consensus ─── */}
      <div className="flex gap-2 flex-wrap">
        <AgentBadge label="Price" value={ac.price_agent_dir} active={ac.price_agent_dir === signal.direction} />
        <AgentBadge label="Sent" value={ac.sentiment_dir} active={ac.sentiment_dir === (signal.direction === "BUY" ? "YES" : "NO")} />
        <div className={clsx(
          "flex flex-col items-center px-2 py-1 rounded border text-[9px] font-mono gap-0.5 border-gray-800",
          sent.cls,
        )}>
          <span className="uppercase tracking-widest opacity-60">BTC</span>
          <span className={clsx("font-bold", sent.cls)}>{sent.icon} {ac.btc_sentiment}</span>
        </div>
        <AgentBadge label="Vol" value={ac.volume_tier} />
        <AgentBadge label="Mom" value={`${Math.round((ac.momentum_score ?? 0) * 100)}%`} active={(ac.momentum_score ?? 0) > 0.6} />
      </div>

      {/* ── Reasoning ─── */}
      <p className="text-[11px] text-gray-400 leading-relaxed border border-gray-800 rounded p-2 bg-[#ffffff05]">
        {signal.reasoning}
      </p>

      {/* ── Cuánto puedes ganar / perder (USDC) ─── */}
      {payPreview && (
        <div className="border border-gray-700 rounded p-2.5 bg-[#0a0a12] space-y-1.5">
          <div className="text-[9px] font-mono text-gray-500 uppercase tracking-widest">
            Con ${stakeNum.toFixed(2)} USDC (aprox., sin fees)
          </div>
          <p className="text-[11px] text-gray-300 leading-snug">
            Si <span className="text-neon-violet">{payPreview.outcomeLabel}</span>: cobras ~{" "}
            <span className="text-gray-200 font-mono">${payPreview.payoutGross.toFixed(2)}</span>
            {" → "}
            <span className="text-neon-green font-mono">+${payPreview.profitNet.toFixed(2)}</span>
            {" "}neto
          </p>
          <p className="text-[11px] text-gray-400">
            Si pierdes la apuesta:{" "}
            <span className="text-neon-red font-mono">−${payPreview.maxLoss.toFixed(2)}</span>
          </p>
          {evApprox !== null && Number.isFinite(evApprox) && (
            <p className="text-[10px] text-gray-500 border-t border-gray-800 pt-1.5 mt-1">
              Valor esperado (prob. modelo YES {Math.round(signal.win_probability * 100)}%):{" "}
              <span className={evApprox >= 0 ? "text-neon-green" : "text-neon-red"}>
                {evApprox >= 0 ? "+" : ""}${evApprox.toFixed(2)}
              </span>
              {" "}USDC
            </p>
          )}
        </div>
      )}

      {/* ── Trade controls ─── */}
      {tradeResult ? (
        <div className={clsx(
          "text-xs text-center rounded border px-3 py-2 font-mono",
          tradeResult.ok ? "text-neon-green border-neon-green bg-[#39FF1415]" : "text-neon-red border-neon-red bg-[#FF003C15]",
        )}>
          {tradeResult.ok ? "✓" : "✗"} {tradeResult.msg}
        </div>
      ) : (
        <div className="flex items-center gap-2">
          {/* Amount input */}
          <div className="flex flex-col gap-1 flex-1">
            <label className="text-[9px] font-mono text-gray-500 uppercase tracking-widest">
              Monto USDC
              {suggestedUSDC > 0 && (
                <button
                  onClick={() => setAmount(String(suggestedUSDC))}
                  className="ml-2 text-neon-violet hover:underline normal-case"
                >
                  (sugerido: ${suggestedUSDC})
                </button>
              )}
            </label>
            <input
              type="number"
              min="1"
              step="1"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full bg-bg-primary border border-gray-700 rounded px-2 py-1 text-xs font-mono text-gray-200 focus:outline-none focus:border-neon-violet"
            />
          </div>

          {/* Trade button */}
          <button
            onClick={handleTrade}
            disabled={trading || !amount || parseFloat(amount) <= 0}
            className={clsx(
              "px-4 py-2 rounded border text-xs font-mono font-bold uppercase tracking-wider transition-all self-end",
              signal.direction === "BUY"
                ? "border-neon-green text-neon-green hover:bg-[#39FF1420] disabled:opacity-40"
                : "border-neon-red text-neon-red hover:bg-[#FF003C20] disabled:opacity-40",
              trading && "opacity-50 cursor-not-allowed",
            )}
          >
            {trading ? "..." : `${signal.direction} ${amount ? `$${amount}` : ""}`}
          </button>
        </div>
      )}
    </div>
  );
}

function Metric({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div className="flex flex-col items-center gap-0.5">
      <span className="text-[8px] font-mono text-gray-600 uppercase tracking-widest">{label}</span>
      <span className={clsx("text-xs font-mono font-bold", highlight ? "text-neon-violet" : "text-gray-300")}>
        {value}
      </span>
    </div>
  );
}

function MarketRow({
  market,
  selected,
  onToggle,
}: {
  market: BitcoinMarket;
  selected: boolean;
  onToggle: () => void;
}) {
  const isUrgent = market.hours_left < 24;
  return (
    <button
      onClick={onToggle}
      className={clsx(
        "w-full flex items-center gap-3 px-3 py-2 rounded border text-left transition-all",
        selected
          ? "border-neon-violet bg-[#BC13FE15] text-gray-200"
          : "border-gray-800 hover:border-gray-600 text-gray-400",
      )}
    >
      {/* Checkbox */}
      <div className={clsx(
        "w-3 h-3 rounded-sm border flex-shrink-0 flex items-center justify-center",
        selected ? "border-neon-violet bg-neon-violet" : "border-gray-600",
      )}>
        {selected && <span className="text-black text-[8px] font-bold leading-none">✓</span>}
      </div>

      {/* Price badge */}
      <span className={clsx(
        "text-[10px] font-mono font-bold px-1.5 py-0.5 rounded flex-shrink-0",
        market.yes_price > 0.6 ? "text-neon-green bg-[#39FF1420]" :
        market.yes_price < 0.4 ? "text-neon-red bg-[#FF003C20]" :
        "text-gray-400 bg-gray-800",
      )}>
        {(market.yes_price * 100).toFixed(0)}%
      </span>

      {/* Question */}
      <span className="text-[11px] flex-1 truncate">{market.question}</span>

      {/* Meta */}
      <div className="flex-shrink-0 flex flex-col items-end gap-0.5">
        <span className={clsx("text-[9px] font-mono", isUrgent ? "text-neon-red" : "text-gray-600")}>
          ⏱ {fmtTime(market.hours_left)}
        </span>
        <span className="text-[9px] font-mono text-gray-700">{fmtUSD(market.volume)}</span>
      </div>
    </button>
  );
}

// ─────────────────────────── Main Panel ──────────────────────────────

export default function BitcoinLivePanel({ portfolio, liveSignals = [] }: Props) {
  const [timeFilter, setTimeFilter] = useState<TimeFilter>("7d");
  const [markets, setMarkets] = useState<BitcoinMarket[]>([]);
  const [loadingMarkets, setLoadingMarkets] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [signals, setSignals] = useState<BitcoinSignal[]>(liveSignals);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeProgress, setAnalyzeProgress] = useState(0);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const [apiError, setApiError] = useState<string | null>(null);
  const progressRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const balance = portfolio?.balance_usdc ?? 0;
  const maxDays = TIME_OPTS.find((t) => t.id === timeFilter)?.days ?? 7;

  // ── Sync live WS signals ─────────────────────────────────────────
  useEffect(() => {
    if (liveSignals.length > 0) setSignals(liveSignals);
  }, [liveSignals]);

  // ── Fetch markets ───────────────────────────────────────────────
  const fetchMarkets = useCallback(async () => {
    setLoadingMarkets(true);
    setApiError(null);
    try {
      const res = await apiFetch<BitcoinMarket[]>(`/api/bitcoin-live?max_days=${maxDays}&limit=40`);
      if (res.success && Array.isArray(res.data)) {
        setMarkets(res.data);
        setLastRefresh(new Date());
        if (res.data.length === 0 && res.message) {
          setApiError(res.message);
        }
      } else {
        setMarkets([]);
        setApiError(res.message || "Respuesta inválida del servidor");
      }
    } catch (e) {
      setMarkets([]);
      setApiError(e instanceof Error ? e.message : "No se pudo cargar /api/bitcoin-live");
    } finally {
      setLoadingMarkets(false);
    }
  }, [maxDays]);

  useEffect(() => {
    fetchMarkets();
    const interval = setInterval(fetchMarkets, 30_000);
    return () => clearInterval(interval);
  }, [fetchMarkets]);

  // ── Analyze ─────────────────────────────────────────────────────
  const handleAnalyze = useCallback(async () => {
    setAnalyzing(true);
    setAnalyzeProgress(0);

    // Simulate progress while agents run
    let prog = 0;
    progressRef.current = setInterval(() => {
      prog = Math.min(prog + 4, 90);
      setAnalyzeProgress(prog);
    }, 500);

    try {
      const body = {
        market_ids: selectedIds.size > 0 ? Array.from(selectedIds) : [],
        max_days: maxDays,
      };
      const res = await apiFetch<BitcoinSignal[]>("/api/bitcoin-analyze", {
        method: "POST",
        body: JSON.stringify(body),
      });
      if (res.success && Array.isArray(res.data)) {
        setSignals(res.data);
      } else {
        setApiError(res.message || "El análisis no devolvió datos");
      }
    } catch (e) {
      setApiError(e instanceof Error ? e.message : "Error en /api/bitcoin-analyze");
    } finally {
      if (progressRef.current) clearInterval(progressRef.current);
      setAnalyzeProgress(100);
      setTimeout(() => { setAnalyzing(false); setAnalyzeProgress(0); }, 600);
    }
  }, [selectedIds, maxDays]);

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };
  const selectAll  = () => setSelectedIds(new Set(markets.map((m) => m.id)));
  const clearAll   = () => setSelectedIds(new Set());

  const strongSignals = signals.filter((s) => s.signal_quality === "strong").length;

  return (
    <div className="flex flex-col gap-4">

      {/* ── Header ─────────────────────────────────────────────────── */}
      {apiError && (
        <div className="text-xs font-mono text-neon-red border border-neon-red/50 rounded px-3 py-2 bg-[#FF003C10]">
          {apiError}
        </div>
      )}

      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <span className="text-neon-violet font-title text-sm tracking-widest glow-violet">₿ BITCOIN LIVE</span>
          {strongSignals > 0 && (
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-[#39FF1433] text-neon-green font-bold animate-pulse">
              {strongSignals} STRONG
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          {lastRefresh && (
            <span className="text-[9px] font-mono text-gray-600">
              actualizado {lastRefresh.toLocaleTimeString()}
            </span>
          )}
          {/* Time filter */}
          <div className="flex gap-1">
            {TIME_OPTS.map((t) => (
              <button
                key={t.id}
                onClick={() => setTimeFilter(t.id)}
                className={clsx(
                  "px-2 py-1 text-[10px] font-mono rounded border transition-all",
                  timeFilter === t.id
                    ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                    : "border-gray-700 text-gray-500 hover:border-gray-500",
                )}
              >
                {t.label}
              </button>
            ))}
          </div>
          <button
            onClick={fetchMarkets}
            disabled={loadingMarkets}
            className="px-2 py-1 text-[10px] font-mono border border-gray-700 rounded text-gray-400 hover:border-gray-500 disabled:opacity-40"
          >
            {loadingMarkets ? "..." : "↺ Refresh"}
          </button>
        </div>
      </div>

      {/* ── Two-column layout ────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">

        {/* LEFT: Markets list ────────────────────────────────────── */}
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-mono text-gray-500 uppercase tracking-widest">
              Mercados Bitcoin ({markets.length})
            </span>
            <div className="flex gap-2">
              <button onClick={selectAll} className="text-[9px] font-mono text-neon-violet hover:underline">
                Todo
              </button>
              <button onClick={clearAll} className="text-[9px] font-mono text-gray-500 hover:underline">
                Limpiar
              </button>
            </div>
          </div>

          {loadingMarkets && markets.length === 0 ? (
            <div className="border border-gray-800 rounded p-6 text-center text-gray-600 text-xs font-mono">
              Buscando mercados Bitcoin...
            </div>
          ) : markets.length === 0 ? (
            <div className="border border-gray-800 rounded p-6 text-center text-gray-600 text-xs font-mono space-y-2">
              <p>No hay mercados Bitcoin en este rango (prueba 14D / 30D arriba).</p>
              <p className="text-gray-700">Los datos vienen de la búsqueda pública de Polymarket (Gamma).</p>
            </div>
          ) : (
            <div className="flex flex-col gap-1 max-h-[520px] overflow-y-auto pr-1">
              {markets.map((m) => (
                <MarketRow
                  key={m.id}
                  market={m}
                  selected={selectedIds.has(m.id)}
                  onToggle={() => toggleSelect(m.id)}
                />
              ))}
            </div>
          )}

          {/* Analyze button */}
          <button
            onClick={handleAnalyze}
            disabled={analyzing || markets.length === 0}
            className={clsx(
              "mt-2 w-full py-3 rounded border font-mono font-bold text-sm uppercase tracking-widest transition-all relative overflow-hidden",
              analyzing
                ? "border-neon-violet text-neon-violet"
                : "border-neon-green text-neon-green hover:bg-[#39FF1415] active:scale-[0.98]",
              (analyzing || markets.length === 0) && "opacity-60 cursor-not-allowed",
            )}
          >
            {/* Progress bar bg */}
            {analyzing && (
              <span
                className="absolute inset-0 bg-neon-violet/10 transition-all duration-300"
                style={{ width: `${analyzeProgress}%` }}
              />
            )}
            <span className="relative z-10 flex items-center justify-center gap-2">
              {analyzing ? (
                <>
                  <span className="animate-spin">◌</span>
                  Analizando con 3 agentes en paralelo... {analyzeProgress}%
                </>
              ) : (
                <>
                  ⚡ Analizar {selectedIds.size > 0 ? `${selectedIds.size} seleccionados` : "todos"}
                </>
              )}
            </span>
          </button>

          {/* Agent indicators */}
          {analyzing && (
            <div className="flex gap-2 justify-center">
              {[
                { name: "Price Agent", icon: "📈" },
                { name: "Momentum", icon: "⚡" },
                { name: "Sentiment", icon: "🧠" },
              ].map((a) => (
                <div
                  key={a.name}
                  className="flex flex-col items-center px-3 py-2 border border-neon-violet/40 rounded bg-[#BC13FE10] text-[9px] font-mono text-neon-violet gap-1"
                >
                  <span className="animate-pulse">{a.icon}</span>
                  <span className="uppercase tracking-widest">{a.name}</span>
                  <span className="text-[8px] opacity-60">CORRIENDO</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* RIGHT: Signals ────────────────────────────────────────── */}
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-mono text-gray-500 uppercase tracking-widest">
              Señales ({signals.length})
            </span>
            {signals.length > 0 && (
              <div className="flex gap-3 text-[9px] font-mono">
                <span className="text-neon-green">{signals.filter((s) => s.signal_quality === "strong").length} fuertes</span>
                <span className="text-yellow-400">{signals.filter((s) => s.signal_quality === "moderate").length} moderadas</span>
                <span className="text-gray-600">{signals.filter((s) => s.signal_quality === "weak").length} débiles</span>
              </div>
            )}
          </div>

          {signals.length === 0 ? (
            <div className="border border-gray-800 rounded p-8 text-center flex flex-col gap-2">
              <span className="text-2xl opacity-20">₿</span>
              <p className="text-gray-600 text-xs font-mono">
                Selecciona mercados y presiona Analizar para ver señales en tiempo real.
              </p>
              <p className="text-gray-700 text-[10px]">
                Los 3 agentes corren en paralelo — resultados en ~10s
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-3 max-h-[640px] overflow-y-auto pr-1">
              {signals.map((s) => (
                <SignalCard key={s.market_id} signal={s} balance={balance} />
              ))}
            </div>
          )}
        </div>

      </div>

      {/* ── Balance hint ───────────────────────────────────────────── */}
      {balance > 0 && (
        <div className="text-[10px] font-mono text-gray-600 text-center border-t border-gray-800 pt-2">
          Balance disponible: <span className="text-neon-green">${balance.toFixed(2)} USDC</span>
          {" · "}Montos sugeridos calculados con criterio de Kelly al 25%
        </div>
      )}
    </div>
  );
}
