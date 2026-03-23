import { create } from "zustand";

export interface AccountInfo {
  login?: number;
  balance?: number;
  equity?: number;
  margin?: number;
  margin_free?: number;
  profit?: number;
  currency?: string;
  leverage?: number;
  server?: string;
}

export interface Position {
  ticket: number;
  symbol: string;
  type: number;
  volume: number;
  price_open: number;
  price_current: number;
  profit: number;
  sl: number;
  tp: number;
  time: string;
  comment: string;
}

export interface AgentStatus {
  name: string;
  status: "idle" | "running" | "thinking" | "error" | "halted";
  last_run?: string;
  run_count: number;
  error_count: number;
}

export interface TradeEvent {
  type: string;
  ticket?: number;
  symbol?: string;
  profit?: number;
  signal?: string;
  confidence?: number;
  timestamp: string;
}

export interface SessionInfo {
  active_sessions: string[];
  peak_sessions: string[];
  is_weekend: boolean;
  utc_time: string;
  day_of_week: string;
  recommended_trading: boolean;
  overlap_active: boolean;
}

export interface Stats {
  total_cycles: number;
  signals_found: number;
  trades_opened: number;
  trades_vetoed: number;
  veto_reasons: Record<string, number>;
  running: boolean;
  open_trades: number;
  risk_stats?: {
    win_rate: number;
    total_trades: number;
    avg_profit: number;
    total_pnl: number;
    daily_pnl: number;
    trading_enabled: boolean;
  };
}

interface TradingStore {
  // Connection
  wsConnected: boolean;
  apiConnected: boolean;
  mode: "paper" | "live";
  running: boolean;

  // Market data
  account: AccountInfo;
  positions: Position[];
  session: SessionInfo | null;
  symbols: string[];
  selectedSymbol: string;

  // Agents
  agentStatuses: Record<string, AgentStatus>;
  agentLogs: Array<{ time: string; agent: string; message: string; level: string }>;

  // Stats
  stats: Stats | null;
  equityCurve: Array<{ time: string; equity: number }>;
  recentTrades: TradeEvent[];

  // Technical signals
  signals: Record<string, { signal: string; confidence: number; indicators: Record<string, number>; regime: string }>;

  // Actions
  setWsConnected: (v: boolean) => void;
  setApiConnected: (v: boolean) => void;
  setAccount: (a: AccountInfo) => void;
  setPositions: (p: Position[]) => void;
  setSession: (s: SessionInfo) => void;
  setStats: (s: Stats) => void;
  setRunning: (v: boolean) => void;
  setMode: (m: "paper" | "live") => void;
  setSymbols: (s: string[]) => void;
  setSelectedSymbol: (s: string) => void;
  updateAgentStatus: (name: string, status: AgentStatus) => void;
  addAgentLog: (log: { time: string; agent: string; message: string; level: string }) => void;
  addTradeEvent: (event: TradeEvent) => void;
  addEquityPoint: (point: { time: string; equity: number }) => void;
  updateSignal: (symbol: string, data: Record<string, unknown>) => void;
}

export const useTradingStore = create<TradingStore>((set) => ({
  wsConnected: false,
  apiConnected: false,
  mode: "paper",
  running: false,
  account: {},
  positions: [],
  session: null,
  symbols: ["EURUSD", "GBPUSD", "XAUUSD", "BTCUSD", "USDJPY", "NAS100"],
  selectedSymbol: "EURUSD",
  agentStatuses: {},
  agentLogs: [],
  stats: null,
  equityCurve: [],
  recentTrades: [],
  signals: {},

  setWsConnected: (v) => set({ wsConnected: v }),
  setApiConnected: (v) => set({ apiConnected: v }),
  setAccount: (a) => set({ account: a }),
  setPositions: (p) => set({ positions: p }),
  setSession: (s) => set({ session: s }),
  setStats: (s) => set({ stats: s }),
  setRunning: (v) => set({ running: v }),
  setMode: (m) => set({ mode: m }),
  setSymbols: (s) => set({ symbols: s }),
  setSelectedSymbol: (s) => set({ selectedSymbol: s }),

  updateAgentStatus: (name, status) =>
    set((state) => ({
      agentStatuses: { ...state.agentStatuses, [name]: status },
    })),

  addAgentLog: (log) =>
    set((state) => ({
      agentLogs: [...state.agentLogs.slice(-999), log],
    })),

  addTradeEvent: (event) =>
    set((state) => ({
      recentTrades: [...state.recentTrades.slice(-199), event],
    })),

  addEquityPoint: (point) =>
    set((state) => ({
      equityCurve: [...state.equityCurve.slice(-499), point],
    })),

  updateSignal: (symbol, data) =>
    set((state) => ({
      signals: { ...state.signals, [symbol]: data as ReturnType<typeof state.signals[string]> },
    })),
}));
