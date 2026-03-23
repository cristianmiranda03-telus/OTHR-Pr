import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatCurrency(value: number, currency = "USD", decimals = 2): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency", currency,
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
}

export function formatPct(value: number, decimals = 1): string {
  return `${value >= 0 ? "+" : ""}${value.toFixed(decimals)}%`;
}

/** Alias: format a ratio (0-1) as percent string */
export function formatPercent(ratio: number, decimals = 1): string {
  const pct = ratio * 100;
  return `${pct >= 0 ? "+" : ""}${pct.toFixed(decimals)}%`;
}

export function formatPips(pips: number): string {
  return `${pips >= 0 ? "+" : ""}${pips.toFixed(1)}`;
}

export function profitColor(value: number): string {
  if (value > 0) return "text-profit";
  if (value < 0) return "text-loss";
  return "text-gray-400";
}

export function signalColor(signal: string): string {
  if (signal === "buy") return "text-profit";
  if (signal === "sell") return "text-loss";
  return "text-gray-400";
}

export function agentStatusColor(status: string): string {
  switch (status) {
    case "running":  return "text-brand animate-pulse";
    case "thinking": return "text-neutral animate-pulse";
    case "error":    return "text-loss";
    case "halted":   return "text-loss";
    default:         return "text-gray-500";
  }
}

export function agentStatusDot(status: string): string {
  switch (status) {
    case "running":  return "status-dot active";
    case "thinking": return "status-dot warning";
    case "error":    return "status-dot error";
    case "halted":   return "status-dot error";
    default:         return "status-dot idle";
  }
}
