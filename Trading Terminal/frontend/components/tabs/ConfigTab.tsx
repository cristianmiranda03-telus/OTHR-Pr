"use client";
import { useState } from "react";
import { api } from "@/lib/ws";
import { cn } from "@/lib/utils";
import { Save, Wifi, WifiOff, AlertTriangle, Globe, Monitor, Plus, X } from "lucide-react";
import toast from "react-hot-toast";

type MT5Mode = "local" | "metaapi" | "demo";

const SYMBOL_PRESETS = [
  "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD",
  "XAUUSD", "XAGUSD", "BTCUSD", "ETHUSD", "NAS100",
  "US30", "SPX500", "USOIL", "NATGAS",
];

export function ConfigTab() {
  const [mt5Mode, setMt5Mode]           = useState<MT5Mode>("local");
  const [mt5Login, setMt5Login]         = useState("");
  const [mt5Pass, setMt5Pass]           = useState("");
  const [mt5Server, setMt5Server]       = useState("");
  const [metaapiToken, setMetaapiToken] = useState("");
  const [metaapiAccount, setMetaapiAccount] = useState("");
  const [symbols, setSymbols]           = useState<string[]>(["EURUSD", "GBPUSD", "XAUUSD", "BTCUSD"]);
  const [newSymbol, setNewSymbol]       = useState("");
  const [lotSize, setLotSize]           = useState("0.01");
  const [riskPct, setRiskPct]           = useState("1.0");
  const [maxPositions, setMaxPositions] = useState("3");
  const [saving, setSaving]             = useState(false);
  const [testing, setTesting]           = useState(false);

  const handleAddSymbol = () => {
    const s = newSymbol.trim().toUpperCase();
    if (s && !symbols.includes(s)) {
      setSymbols([...symbols, s]);
      setNewSymbol("");
    }
  };
  const handleRemoveSymbol = (sym: string) => setSymbols(symbols.filter((s) => s !== sym));
  const handleAddPreset = (sym: string) => {
    if (!symbols.includes(sym)) setSymbols([...symbols, sym]);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const cfg: Record<string, unknown> = {
        mt5_mode: mt5Mode,
        symbols,
        trading: { lot_size: parseFloat(lotSize), risk_percent: parseFloat(riskPct), max_positions: parseInt(maxPositions) },
      };
      if (mt5Mode === "local") {
        cfg.mt5 = { login: parseInt(mt5Login) || 0, password: mt5Pass, server: mt5Server };
      } else if (mt5Mode === "metaapi") {
        cfg.metaapi = { token: metaapiToken, account_id: metaapiAccount };
      }
      await api.post("/api/config/mt5", cfg);
      toast.success("Configuration saved");
    } catch {
      toast.error("Failed to save config");
    }
    setSaving(false);
  };

  const handleTestConnection = async () => {
    setTesting(true);
    try {
      const result = await api.get("/api/health");
      if (result.mt5_connected) {
        toast.success(`MT5 Connected — ${result.mt5_info?.server || "OK"}`);
      } else {
        toast.error(`MT5 not connected. Mode: ${result.mt5_mode || "local"}`);
      }
    } catch {
      toast.error("Backend unreachable");
    }
    setTesting(false);
  };

  return (
    <div className="space-y-4 max-w-3xl mx-auto">

      {/* ── MT5 Connection ─────────────────────────────────────── */}
      <div className="card">
        <div className="card-header">
          <div className="flex items-center gap-2">
            <Wifi className="w-4 h-4 text-brand" />
            <span className="text-sm font-semibold text-gray-200">MT5 Connection</span>
          </div>
          <button onClick={handleTestConnection} className="btn btn-brand py-1.5 px-3 text-[10px]">
            {testing ? "Testing..." : "Test connection"}
          </button>
        </div>

        <div className="p-4 space-y-4">
          {/* Mode selector */}
          <div className="grid grid-cols-3 gap-2">
            {([
              { v: "local",    label: "Local Desktop", icon: Monitor, desc: "MT5 running on this PC" },
              { v: "metaapi",  label: "Remote / Web",  icon: Globe,   desc: "MetaAPI cloud bridge" },
              { v: "demo",     label: "Demo Mode",     icon: AlertTriangle, desc: "Paper trading (no MT5)" },
            ] as const).map(({ v, label, icon: Icon, desc }) => (
              <button
                key={v}
                onClick={() => setMt5Mode(v)}
                className={cn(
                  "p-3 rounded-lg border text-left transition-all",
                  mt5Mode === v
                    ? "bg-brand/10 border-brand/40 shadow-glow-sm"
                    : "bg-bg-surface border-bg-border hover:border-bg-border-hi"
                )}
              >
                <Icon className={cn("w-4 h-4 mb-1.5", mt5Mode === v ? "text-brand" : "text-gray-600")} />
                <div className={cn("text-xs font-semibold", mt5Mode === v ? "text-brand" : "text-gray-300")}>{label}</div>
                <div className="text-[10px] text-gray-600 mt-0.5">{desc}</div>
              </button>
            ))}
          </div>

          {/* Local mode fields */}
          {mt5Mode === "local" && (
            <div className="grid grid-cols-2 gap-3 animate-fade-in">
              <div>
                <label className="data-label mb-1 block">Login</label>
                <input
                  type="text" value={mt5Login} onChange={(e) => setMt5Login(e.target.value)}
                  placeholder="12345678" className="input-field"
                />
              </div>
              <div>
                <label className="data-label mb-1 block">Password</label>
                <input
                  type="password" value={mt5Pass} onChange={(e) => setMt5Pass(e.target.value)}
                  placeholder="••••••••" className="input-field"
                />
              </div>
              <div className="col-span-2">
                <label className="data-label mb-1 block">Server</label>
                <input
                  type="text" value={mt5Server} onChange={(e) => setMt5Server(e.target.value)}
                  placeholder="BrokerName-Server" className="input-field"
                />
              </div>
            </div>
          )}

          {/* MetaAPI / Remote mode */}
          {mt5Mode === "metaapi" && (
            <div className="space-y-3 animate-fade-in">
              <div className="bg-cyan/5 border border-cyan/20 rounded-lg p-3 text-[11px] text-cyan/80">
                <Globe className="w-3.5 h-3.5 inline mr-1" />
                Remote mode uses <strong>MetaAPI.cloud</strong> — no local MT5 needed.
                Get a free token at <span className="underline">metaapi.cloud</span>.
              </div>
              <div>
                <label className="data-label mb-1 block">MetaAPI Token</label>
                <input
                  type="password" value={metaapiToken} onChange={(e) => setMetaapiToken(e.target.value)}
                  placeholder="your-metaapi-token" className="input-field"
                />
              </div>
              <div>
                <label className="data-label mb-1 block">Account ID</label>
                <input
                  type="text" value={metaapiAccount} onChange={(e) => setMetaapiAccount(e.target.value)}
                  placeholder="account-id from MetaAPI dashboard" className="input-field"
                />
              </div>
            </div>
          )}

          {mt5Mode === "demo" && (
            <div className="bg-neutral/5 border border-neutral/20 rounded-lg p-3 text-[11px] text-neutral/80 animate-fade-in">
              <AlertTriangle className="w-3.5 h-3.5 inline mr-1" />
              Demo mode simulates a $10,000 account with synthetic market data.
              No real orders are placed.
            </div>
          )}
        </div>
      </div>

      {/* ── Symbols ────────────────────────────────────────────── */}
      <div className="card">
        <div className="card-header">
          <span className="text-sm font-semibold text-gray-200">Watchlist / Trading Symbols</span>
        </div>
        <div className="p-4 space-y-3">
          {/* Active symbols */}
          <div className="flex flex-wrap gap-2">
            {symbols.map((sym) => (
              <span key={sym} className="flex items-center gap-1 metric-pill brand text-[10px]">
                {sym}
                <button onClick={() => handleRemoveSymbol(sym)} className="hover:text-loss ml-0.5">
                  <X className="w-2.5 h-2.5" />
                </button>
              </span>
            ))}
          </div>

          {/* Add custom symbol */}
          <div className="flex gap-2">
            <input
              type="text" value={newSymbol} onChange={(e) => setNewSymbol(e.target.value.toUpperCase())}
              onKeyDown={(e) => e.key === "Enter" && handleAddSymbol()}
              placeholder="Add symbol (e.g. USDJPY)" className="input-field"
            />
            <button onClick={handleAddSymbol} className="btn btn-brand py-2 px-3 shrink-0">
              <Plus className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Preset chips */}
          <div>
            <div className="data-label mb-2">Quick add:</div>
            <div className="flex flex-wrap gap-1.5">
              {SYMBOL_PRESETS.filter((s) => !symbols.includes(s)).map((sym) => (
                <button
                  key={sym}
                  onClick={() => handleAddPreset(sym)}
                  className="text-[10px] mono px-2 py-0.5 rounded-md bg-bg-surface border border-bg-border hover:border-brand/30 hover:text-brand text-gray-500 transition-all"
                >
                  + {sym}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* ── Risk Parameters ────────────────────────────────────── */}
      <div className="card">
        <div className="card-header">
          <span className="text-sm font-semibold text-gray-200">Risk Parameters</span>
        </div>
        <div className="p-4 grid grid-cols-3 gap-3">
          <div>
            <label className="data-label mb-1 block">Default Lot Size</label>
            <input type="number" value={lotSize} step="0.001" min="0.001" onChange={(e) => setLotSize(e.target.value)} className="input-field" />
          </div>
          <div>
            <label className="data-label mb-1 block">Risk per Trade %</label>
            <input type="number" value={riskPct} step="0.1" min="0.1" max="5" onChange={(e) => setRiskPct(e.target.value)} className="input-field" />
          </div>
          <div>
            <label className="data-label mb-1 block">Max Positions</label>
            <input type="number" value={maxPositions} step="1" min="1" max="20" onChange={(e) => setMaxPositions(e.target.value)} className="input-field" />
          </div>
        </div>
      </div>

      {/* ── Save ───────────────────────────────────────────────── */}
      <button onClick={handleSave} disabled={saving} className="btn btn-brand w-full justify-center py-3 text-sm">
        <Save className="w-4 h-4" />
        {saving ? "Saving..." : "Save Configuration"}
      </button>
    </div>
  );
}
