import { useTradingStore } from "./store";
import toast from "react-hot-toast";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
const WS_URL = process.env.NEXT_PUBLIC_WS_URL || "ws://localhost:8000/ws";
const API_URL = API_BASE;

let ws: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectDelay = 1000;

export function connectWebSocket() {
  const store = useTradingStore.getState();

  if (ws && ws.readyState === WebSocket.OPEN) return;

  ws = new WebSocket(WS_URL);

  ws.onopen = () => {
    store.setWsConnected(true);
    store.setApiConnected(true);
    reconnectDelay = 1000;
    toast.success("Connected to Trading Terminal");
    if (reconnectTimer) clearTimeout(reconnectTimer);
  };

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      handleMessage(msg);
    } catch (e) {
      console.error("WS parse error:", e);
    }
  };

  ws.onclose = () => {
    store.setWsConnected(false);
    toast.error("Connection lost - reconnecting...");
    reconnectTimer = setTimeout(() => {
      reconnectDelay = Math.min(reconnectDelay * 1.5, 30000);
      connectWebSocket();
    }, reconnectDelay);
  };

  ws.onerror = () => {
    store.setApiConnected(false);
  };
}

function handleMessage(msg: Record<string, unknown>) {
  const store = useTradingStore.getState();
  const type = msg.type as string;
  const data = msg.data as Record<string, unknown>;
  const timestamp = (msg.timestamp as string) || new Date().toISOString();

  switch (type) {
    case "init":
    case "state":
      if (data.account) store.setAccount(data.account as ReturnType<typeof store.account>);
      if (data.positions) store.setPositions(data.positions as ReturnType<typeof store.positions>);
      if (data.session) store.setSession(data.session as ReturnType<typeof store.session>);
      if (data.stats) store.setStats(data.stats as ReturnType<typeof store.stats>);
      if (data.running !== undefined) store.setRunning(data.running as boolean);
      if (data.mode) store.setMode(data.mode as "paper" | "live");
      if (data.symbols) store.setSymbols(data.symbols as string[]);
      break;

    case "technical_update":
      if (data.symbol) {
        store.updateSignal(data.symbol as string, {
          signal: data.signal,
          confidence: data.confidence,
          indicators: data.indicators || {},
          regime: data.regime,
        });
        store.addAgentLog({
          time: timestamp,
          agent: "TechnicalAnalyst",
          message: `${data.symbol}: ${data.signal?.toString().toUpperCase()} | conf=${
            ((data.confidence as number) * 100).toFixed(0)
          }% | ${data.regime}`,
          level: "info",
        });
      }
      break;

    case "trade_opened":
      store.addTradeEvent({ type: "opened", ...data as Record<string, unknown>, timestamp } as ReturnType<typeof store.recentTrades[0]>);
      toast.success(
        `🎯 ${(data.type as string)?.toUpperCase()} ${data.lot_size} ${data.symbol} @ ${(data.entry_price as number)?.toFixed(5)}`
      );
      store.addAgentLog({
        time: timestamp,
        agent: "MT5Executor",
        message: `OPENED #${data.ticket} | ${data.type?.toString().toUpperCase()} ${data.lot_size} ${data.symbol}`,
        level: "info",
      });
      break;

    case "trade_closed":
      store.addTradeEvent({ type: "closed", ...data as Record<string, unknown>, timestamp } as ReturnType<typeof store.recentTrades[0]>);
      const profit = data.profit as number;
      if (profit > 0) {
        toast.success(`🟢 WIN: +$${profit.toFixed(2)} (${data.pips} pips)`);
      } else {
        toast.error(`🔴 LOSS: $${profit.toFixed(2)} (${data.pips} pips)`);
      }
      break;

    case "news_update":
      store.addAgentLog({
        time: timestamp,
        agent: "NewsSentinel",
        message: `${data.symbol}: ${data.verdict?.toString().toUpperCase()} | ${data.sentiment}`,
        level: data.verdict === "block" ? "warning" : "info",
      });
      if (data.verdict === "block") {
        toast(`⚠️ News block: ${data.symbol}`, { icon: "📰" });
      }
      break;

    case "system_warning":
      toast(`⚠️ ${data.message}`, { icon: "🚨", duration: 6000 });
      store.addAgentLog({
        time: timestamp,
        agent: (data.agent as string) || "System",
        message: data.message as string,
        level: "warning",
      });
      break;

    case "system_ready":
      toast.success(`✅ System ready | Mode: ${(data.mode as string)?.toUpperCase()}`);
      break;
  }

  // Always update equity curve with account equity
  const account = useTradingStore.getState().account;
  if (account.equity) {
    store.addEquityPoint({ time: timestamp, equity: account.equity });
  }
}

export function sendWsMessage(action: string, payload: Record<string, unknown> = {}) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action, ...payload }));
  }
}

export const api = {
  get: (path: string) => fetch(`${API_URL}${path}`).then((r) => r.json()),
  post: (path: string, body: unknown) =>
    fetch(`${API_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }).then((r) => r.json()),
  delete: (path: string) => fetch(`${API_URL}${path}`, { method: "DELETE" }).then((r) => r.json()),
};
