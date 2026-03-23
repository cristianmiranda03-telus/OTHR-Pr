"use client";
import { useState } from "react";
import { useTradingStore } from "@/lib/store";
import { api } from "@/lib/ws";
import { Play, Square, AlertTriangle, Settings } from "lucide-react";
import toast from "react-hot-toast";
import { cn } from "@/lib/utils";

export function ControlPanel() {
  const { running, mode, setRunning, setMode } = useTradingStore();
  const [loading, setLoading] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [mtConfig, setMtConfig] = useState({ login: "", password: "", server: "" });

  const handleStart = async () => {
    setLoading(true);
    try {
      const result = await api.post("/api/trading/start", {
        mode,
        interval: 30,
      });
      if (result.status === "started" || result.status === "already_running") {
        setRunning(true);
        toast.success(`Trading started in ${mode.toUpperCase()} mode`);
      }
    } catch {
      toast.error("Failed to start trading");
    } finally {
      setLoading(false);
    }
  };

  const handleStop = async () => {
    setLoading(true);
    try {
      await api.post("/api/trading/stop", {});
      setRunning(false);
      toast.success("Trading stopped - all positions closed");
    } catch {
      toast.error("Failed to stop trading");
    } finally {
      setLoading(false);
    }
  };

  const handleMtConnect = async () => {
    try {
      const result = await api.post("/api/config/mt5", {
        login: parseInt(mtConfig.login),
        password: mtConfig.password,
        server: mtConfig.server,
      });
      if (result.connected) {
        toast.success(`Connected to MT5: ${mtConfig.login}`);
        setShowSettings(false);
      } else {
        toast.error("MT5 connection failed");
      }
    } catch {
      toast.error("MT5 config update failed");
    }
  };

  return (
    <div className="card p-3">
      <div className="flex items-center gap-3 flex-wrap">
        {/* Status indicator */}
        <div className="flex items-center gap-2">
          <span className={cn("status-dot", running ? "active" : "idle")} />
          <span className="text-xs text-gray-400">
            {running ? (
              <span className="text-profit animate-pulse-slow">● RUNNING</span>
            ) : (
              <span className="text-gray-600">● STOPPED</span>
            )}
          </span>
        </div>

        {/* Mode toggle */}
        <div className="flex rounded-lg overflow-hidden border border-bg-border">
          <button
            onClick={() => !running && setMode("paper")}
            className={cn(
              "px-3 py-1.5 text-xs font-medium transition-colors",
              mode === "paper"
                ? "bg-neutral/20 text-neutral"
                : "text-gray-600 hover:text-gray-400"
            )}
          >
            PAPER
          </button>
          <button
            onClick={() => !running && setMode("live")}
            className={cn(
              "px-3 py-1.5 text-xs font-medium transition-colors flex items-center gap-1",
              mode === "live"
                ? "bg-loss/20 text-loss"
                : "text-gray-600 hover:text-gray-400"
            )}
          >
            {mode === "live" && <AlertTriangle className="w-3 h-3" />}
            LIVE
          </button>
        </div>

        {/* Start/Stop */}
        <div className="flex gap-2">
          {!running ? (
            <button
              onClick={handleStart}
              disabled={loading}
              className={cn(
                "flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-semibold transition-all",
                "bg-profit/20 text-profit border border-profit/30",
                "hover:bg-profit/30 hover:shadow-glow-profit",
                loading && "opacity-50 cursor-not-allowed"
              )}
            >
              <Play className="w-3.5 h-3.5" />
              START
            </button>
          ) : (
            <button
              onClick={handleStop}
              disabled={loading}
              className={cn(
                "flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-semibold transition-all",
                "bg-loss/20 text-loss border border-loss/30",
                "hover:bg-loss/30 hover:shadow-glow-loss",
                loading && "opacity-50 cursor-not-allowed"
              )}
            >
              <Square className="w-3.5 h-3.5" />
              STOP
            </button>
          )}
        </div>

        {/* Settings */}
        <button
          onClick={() => setShowSettings(!showSettings)}
          className="ml-auto p-2 rounded-lg text-gray-600 hover:text-gray-300 hover:bg-bg-raised transition-colors"
        >
          <Settings className="w-4 h-4" />
        </button>
      </div>

      {/* MT5 settings drawer */}
      {showSettings && (
        <div className="mt-3 pt-3 border-t border-bg-border space-y-2 animate-slide-up">
          <p className="text-xs text-gray-500 uppercase tracking-wider">MT5 Connection</p>
          <div className="grid grid-cols-3 gap-2">
            <input
              type="number"
              placeholder="Login"
              value={mtConfig.login}
              onChange={(e) => setMtConfig({ ...mtConfig, login: e.target.value })}
              className="bg-bg-surface border border-bg-border rounded px-3 py-2 text-xs text-gray-300
                         placeholder-gray-600 focus:outline-none focus:border-brand/50 mono"
            />
            <input
              type="password"
              placeholder="Password"
              value={mtConfig.password}
              onChange={(e) => setMtConfig({ ...mtConfig, password: e.target.value })}
              className="bg-bg-surface border border-bg-border rounded px-3 py-2 text-xs text-gray-300
                         placeholder-gray-600 focus:outline-none focus:border-brand/50"
            />
            <input
              type="text"
              placeholder="Server (e.g. ICMarkets-Demo)"
              value={mtConfig.server}
              onChange={(e) => setMtConfig({ ...mtConfig, server: e.target.value })}
              className="bg-bg-surface border border-bg-border rounded px-3 py-2 text-xs text-gray-300
                         placeholder-gray-600 focus:outline-none focus:border-brand/50"
            />
          </div>
          <button
            onClick={handleMtConnect}
            className="px-4 py-2 bg-brand/20 text-brand border border-brand/30 rounded-lg
                       text-xs font-semibold hover:bg-brand/30 transition-colors"
          >
            Connect MT5
          </button>
        </div>
      )}
    </div>
  );
}
