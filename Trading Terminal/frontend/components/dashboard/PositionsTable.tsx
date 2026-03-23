"use client";
import { useTradingStore } from "@/lib/store";
import { formatCurrency, profitColor } from "@/lib/utils";
import { X, TrendingUp, TrendingDown } from "lucide-react";
import { api } from "@/lib/ws";
import toast from "react-hot-toast";

export function PositionsTable() {
  const { positions } = useTradingStore();

  const handleClose = async (ticket: number) => {
    try {
      const result = await api.delete(`/api/positions/${ticket}`);
      if (result.success) {
        toast.success(`Position #${ticket} closed`);
      } else {
        toast.error(`Close failed: ${result.error || "Unknown"}`);
      }
    } catch {
      toast.error("Failed to close position");
    }
  };

  if (positions.length === 0) {
    return (
      <div className="card">
        <div className="card-header">
          <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider">
            Open Positions
          </span>
          <span className="text-[10px] mono text-gray-600">0 positions</span>
        </div>
        <div className="p-6 text-center text-gray-600 text-sm">
          No open positions
        </div>
      </div>
    );
  }

  const totalPnl = positions.reduce((sum, p) => sum + (p.profit || 0), 0);

  return (
    <div className="card overflow-hidden">
      <div className="card-header">
        <span className="text-xs font-semibold text-gray-300 uppercase tracking-wider">
          Open Positions ({positions.length})
        </span>
        <span className={`text-sm font-semibold mono ${profitColor(totalPnl)}`}>
          {formatCurrency(totalPnl)}
        </span>
      </div>
      <div className="overflow-x-auto">
        <table>
          <thead>
            <tr>
              <th>Ticket</th>
              <th>Symbol</th>
              <th>Type</th>
              <th>Lots</th>
              <th>Open</th>
              <th>Current</th>
              <th>SL</th>
              <th>TP</th>
              <th>P/L</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {positions.map((pos) => {
              const isBuy = pos.type === 0;
              const pnl = pos.profit || 0;
              return (
                <tr key={pos.ticket} className={pnl > 0 ? "flash-profit" : ""}>
                  <td className="text-gray-400">{pos.ticket}</td>
                  <td className="text-gray-100 font-medium">{pos.symbol}</td>
                  <td>
                    <span className={`flex items-center gap-1 ${isBuy ? "text-profit" : "text-loss"}`}>
                      {isBuy ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                      {isBuy ? "BUY" : "SELL"}
                    </span>
                  </td>
                  <td>{pos.volume}</td>
                  <td>{pos.price_open?.toFixed(5)}</td>
                  <td className={`font-medium ${profitColor(pnl)}`}>
                    {pos.price_current?.toFixed(5)}
                  </td>
                  <td className="text-loss/70">{pos.sl > 0 ? pos.sl.toFixed(5) : "—"}</td>
                  <td className="text-profit/70">{pos.tp > 0 ? pos.tp.toFixed(5) : "—"}</td>
                  <td className={`font-semibold ${profitColor(pnl)}`}>
                    {pnl >= 0 ? "+" : ""}{formatCurrency(pnl)}
                  </td>
                  <td>
                    <button
                      onClick={() => handleClose(pos.ticket)}
                      className="p-1 rounded hover:bg-loss/20 text-gray-600 hover:text-loss transition-colors"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
