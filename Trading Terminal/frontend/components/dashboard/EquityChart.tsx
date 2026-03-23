"use client";
import { useTradingStore } from "@/lib/store";
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from "recharts";
import { TrendingUp } from "lucide-react";

const CustomTooltip = ({ active, payload }: Record<string, unknown>) => {
  if (active && payload && (payload as unknown[]).length) {
    const p = (payload as Array<{ value: number }>)[0];
    return (
      <div className="bg-bg-raised border border-bg-border rounded p-2 text-xs font-mono">
        <p className="text-profit">${p.value.toFixed(2)}</p>
      </div>
    );
  }
  return null;
};

export function EquityChart() {
  const { equityCurve, account } = useTradingStore();
  const startBalance = account.balance || 10000;

  const data = equityCurve.slice(-200).map((p, i) => ({
    time: i,
    equity: p.equity,
  }));

  if (data.length < 2) {
    return (
      <div className="card">
        <div className="card-header">
          <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
            <TrendingUp className="w-3.5 h-3.5 text-brand" /> Equity Curve
          </span>
        </div>
        <div className="h-32 flex items-center justify-center text-gray-600 text-sm">
          Waiting for data...
        </div>
      </div>
    );
  }

  const latest = data[data.length - 1]?.equity || startBalance;
  const pnlPct = ((latest - startBalance) / startBalance * 100).toFixed(2);
  const isPositive = latest >= startBalance;

  return (
    <div className="card">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider flex items-center gap-2">
          <TrendingUp className="w-3.5 h-3.5 text-brand" /> Equity Curve
        </span>
        <span className={`text-sm font-semibold mono ${isPositive ? "text-profit" : "text-loss"}`}>
          {isPositive ? "+" : ""}{pnlPct}%
        </span>
      </div>
      <div className="p-2">
        <ResponsiveContainer width="100%" height={140}>
          <AreaChart data={data} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id="equityGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={isPositive ? "#10b981" : "#ef4444"} stopOpacity={0.3} />
                <stop offset="95%" stopColor={isPositive ? "#10b981" : "#ef4444"} stopOpacity={0} />
              </linearGradient>
            </defs>
            <XAxis dataKey="time" hide />
            <YAxis
              domain={["auto", "auto"]}
              hide
            />
            <Tooltip content={<CustomTooltip />} />
            <ReferenceLine
              y={startBalance}
              stroke="#374151"
              strokeDasharray="3 3"
              strokeWidth={1}
            />
            <Area
              type="monotone"
              dataKey="equity"
              stroke={isPositive ? "#10b981" : "#ef4444"}
              strokeWidth={1.5}
              fill="url(#equityGrad)"
              dot={false}
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
