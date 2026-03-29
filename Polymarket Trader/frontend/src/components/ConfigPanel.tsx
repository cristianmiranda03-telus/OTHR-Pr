"use client";
import { useEffect, useState } from "react";
import type { AppConfig } from "@/types";
import { apiFetch } from "@/hooks/useApi";
import clsx from "clsx";

interface FieldDef {
  key: keyof AppConfig;
  label: string;
  type?: "text" | "password" | "number" | "select";
  options?: string[];
  placeholder?: string;
  section: string;
  hint?: string;
}

const FIELDS: FieldDef[] = [
  // FuelXI
  { key: "fuelxi_api_url",  label: "FuelXI API URL",  section: "FuelXI (Active LLM)", placeholder: "https://api.fuelix.ai/v1" },
  { key: "fuelxi_api_key",  label: "FuelXI API Key",  section: "FuelXI (Active LLM)", type: "password", placeholder: "ak-..." },
  { key: "fuelxi_model",    label: "FuelXI Model",    section: "FuelXI (Active LLM)", placeholder: "claude-sonnet-4-5" },
  { key: "llm_provider",    label: "LLM Provider",    section: "FuelXI (Active LLM)", type: "select", options: ["fuelxi", "openai"],
    hint: "Switch between FuelXI and OpenAI" },
  // OpenAI
  { key: "openai_api_key",  label: "OpenAI API Key",  section: "OpenAI (Optional)", type: "password", placeholder: "sk-..." },
  { key: "openai_model",    label: "OpenAI Model",    section: "OpenAI (Optional)", placeholder: "gpt-4o" },
  // Polymarket
  { key: "polymarket_api_key",        label: "API Key",        section: "Polymarket API", type: "password" },
  { key: "polymarket_api_secret",     label: "API Secret",     section: "Polymarket API", type: "password" },
  { key: "polymarket_api_passphrase", label: "API Passphrase", section: "Polymarket API", type: "password" },
  { key: "polymarket_private_key",    label: "Wallet Private Key", section: "Polymarket API", type: "password",
    hint: "Required for fetching real balance and trading (L2 Auth)." },
  { key: "polymarket_proxy_wallet",   label: "Profile (Proxy) Address", section: "Polymarket API", type: "text",
    placeholder: "0x...",
    hint: "Your Polymarket profile address — required to see positions. Find it on polymarket.com → Profile (dropdown)." },
  // Search
  { key: "tavily_api_key",  label: "Tavily API Key (optional)", section: "Web Search", type: "password",
    hint: "Enables live web search during analysis" },
  // App
  { key: "update_interval",    label: "Scan Interval (seconds)", section: "Agent Settings", type: "number",
    hint: "How often agents re-scan markets" },
  { key: "min_confidence",     label: "Min Confidence (0–1)",    section: "Agent Settings", type: "number",
    hint: "Signals below this threshold are discarded" },
  { key: "max_parallel_agents", label: "Max Parallel Agents",    section: "Agent Settings", type: "number" },
];

const SECTIONS = [...new Set(FIELDS.map((f) => f.section))];

interface Props {
  onSaved?: () => void;
}

export default function ConfigPanel({ onSaved }: Props) {
  const [config, setConfig] = useState<Partial<AppConfig>>({});
  const [saved, setSaved] = useState(false);
  const [saveMessage, setSaveMessage] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showPasswords, setShowPasswords] = useState<Record<string, boolean>>({});

  useEffect(() => {
    let cancelled = false;
    apiFetch<AppConfig>("/api/config")
      .then((r) => {
        if (!cancelled && r.data) setConfig(r.data as Partial<AppConfig>);
      })
      .catch((e) => {
        if (!cancelled) {
          const msg = e?.message || String(e);
          setError(
            msg.includes("fetch") || msg.includes("Failed to fetch")
              ? "Cannot reach backend. Start the app with: python run.py"
              : msg
          );
        }
      })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);

  const handleChange = (key: keyof AppConfig, value: string | number) => {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setSaved(false);
    setError(null);
  };

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    try {
      const res = await apiFetch<{ requires_restart: boolean }>("/api/config", {
        method: "POST",
        body: JSON.stringify(config),
      });
      setSaved(true);
      setSaveMessage(res.message || "Saved.");
      onSaved?.();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(
        msg.includes("fetch") || msg.includes("Failed to fetch")
          ? "Cannot reach backend. Start the app with: python run.py"
          : msg
      );
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-48">
        <p className="text-gray-600 text-sm animate-pulse-slow">Loading configuration...</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto flex flex-col gap-6">
      {/* Notice */}
      <div className="joker-card p-3 border-l-2 border-neon-yellow">
        <p className="text-xs text-gray-400">
          Changes are saved to <code className="text-neon-violet">config.ini</code>.{" "}
          <span className="text-neon-yellow">Restart the server</span> to apply LLM/API key changes.
          Masked values (•••) are not overwritten unless you enter new text.
        </p>
      </div>

      {SECTIONS.map((section) => (
        <div key={section} className="joker-card p-4 flex flex-col gap-3">
          <h3 className="font-title text-sm text-neon-violet glow-violet tracking-widest uppercase">
            {section}
          </h3>
          {FIELDS.filter((f) => f.section === section).map((field) => (
            <div key={field.key}>
              <label className="text-[10px] text-gray-500 uppercase tracking-widest block mb-1">
                {field.label}
                {field.hint && (
                  <span className="ml-2 text-gray-600 normal-case tracking-normal">
                    — {field.hint}
                  </span>
                )}
              </label>

              {field.type === "select" ? (
                <select
                  value={String(config[field.key] ?? "")}
                  onChange={(e) => handleChange(field.key, e.target.value)}
                  className="w-full bg-[#1a1a1a] border border-bg-border rounded px-3 py-2 text-xs text-gray-200 focus:border-neon-violet outline-none"
                >
                  {field.options!.map((opt) => (
                    <option key={opt} value={opt}>{opt}</option>
                  ))}
                </select>
              ) : (
                <div className="relative">
                  <input
                    type={
                      field.type === "password" && !showPasswords[field.key]
                        ? "password"
                        : field.type === "number"
                        ? "number"
                        : "text"
                    }
                    value={String(config[field.key] ?? "")}
                    onChange={(e) =>
                      handleChange(
                        field.key,
                        field.type === "number" ? Number(e.target.value) : e.target.value
                      )
                    }
                    placeholder={field.placeholder}
                    step={field.type === "number" ? "any" : undefined}
                    className="w-full bg-[#1a1a1a] border border-bg-border rounded px-3 py-2 text-xs text-gray-200 font-mono focus:border-neon-violet outline-none pr-10"
                  />
                  {field.type === "password" && (
                    <button
                      onClick={() =>
                        setShowPasswords((p) => ({ ...p, [field.key]: !p[field.key] }))
                      }
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-600 hover:text-gray-400 text-xs"
                    >
                      {showPasswords[field.key] ? "hide" : "show"}
                    </button>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      ))}

      {/* Save */}
      <div className="flex items-center gap-4 sticky bottom-0 bg-bg-primary py-3 border-t border-bg-border">
        <button
          onClick={handleSave}
          disabled={saving}
          className="btn-approve px-6"
        >
          {saving ? "Saving..." : "✓ Save Configuration"}
        </button>
        {saved && (
          <span className="text-xs text-neon-green">
            ✓ {saveMessage || "Saved to config.ini"}
          </span>
        )}
        {error && (
          <span className="text-xs text-neon-red">{error}</span>
        )}
      </div>
    </div>
  );
}
