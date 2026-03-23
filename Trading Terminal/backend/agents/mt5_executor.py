"""
Agent 5: MT5 Executor (The Bridge)
Translates agent decisions into MT5 orders with slippage control.
"""
import asyncio
from datetime import datetime
from typing import Dict, List, Optional
from .base_agent import BaseAgent
from ..core.mt5_connection import MT5Connection


class MT5ExecutorAgent(BaseAgent):
    """
    Mechanical execution layer:
    - Pre-execution validation
    - Slippage control (cancel if price moved too much)
    - Order confirmation and tracking
    - Trailing stop management
    - Partial close support
    """

    def __init__(self, config: dict, mt5: MT5Connection):
        super().__init__("MT5Executor", config)
        self.mt5 = mt5
        self.scalping_cfg = config.get("scalping", {})
        self._pending_orders: Dict[int, Dict] = {}
        self._executed_today: int = 0

    async def _execute(self, context: Dict) -> Dict:
        action = context.get("action", "open")
        if action == "open":
            return await self._open_trade(context)
        elif action == "close":
            return await self._close_trade(context)
        elif action == "modify":
            return await self._modify_trade(context)
        elif action == "close_all":
            return await self._close_all(context)
        elif action == "update_trailing":
            return await self._update_trailing_stops(context)
        else:
            return {"error": f"Unknown action: {action}", "success": False}

    async def _open_trade(self, context: Dict) -> Dict:
        symbol = context.get("symbol")
        signal = context.get("signal")
        lot_size = context.get("lot_size", 0.01)
        sl = context.get("sl", 0.0)
        tp = context.get("tp", 0.0)
        strategy_name = context.get("strategy_name", "TT-Agent")
        max_slippage = self.scalping_cfg.get("max_slippage_points", 3)

        self._emit(f"🚀 Executing {signal.upper()} {lot_size} {symbol}...")

        # Pre-execution price check
        tick = await self.mt5.get_tick(symbol)
        if not tick:
            return {"error": "Cannot get current price", "success": False}

        expected_price = context.get("entry_price", 0)
        current_price = tick["ask"] if signal == "buy" else tick["bid"]
        symbol_info = await self.mt5.get_symbol_info(symbol)
        digits = symbol_info.get("digits", 5) if symbol_info else 5
        point = 10 ** (-digits)

        # Slippage check
        if expected_price > 0:
            slippage_points = abs(current_price - expected_price) / point
            if slippage_points > max_slippage:
                msg = (f"Slippage too large: {slippage_points:.1f} points "
                       f"(max={max_slippage}) | TRADE CANCELLED")
                self._emit(f"⚠ {msg}", "warning")
                return {"success": False, "cancelled": True, "reason": msg,
                        "slippage_points": slippage_points}

        comment = f"{strategy_name[:10]}-{datetime.now().strftime('%H%M')}"
        result = await self.mt5.send_order(
            symbol=symbol,
            order_type=signal,
            volume=lot_size,
            sl=sl,
            tp=tp,
            comment=comment,
            deviation=int(max_slippage * 2),
        )

        if result.get("success"):
            ticket = result.get("ticket", 0)
            self._pending_orders[ticket] = {
                "symbol": symbol,
                "type": signal,
                "lot_size": lot_size,
                "entry_price": result.get("price_executed", current_price),
                "sl": sl,
                "tp": tp,
                "open_time": datetime.now().isoformat(),
                "strategy": strategy_name,
            }
            self._executed_today += 1
            self._emit(f"✅ OPENED: ticket={ticket} | {signal.upper()} {lot_size} {symbol} "
                       f"@ {result.get('price_executed', current_price):.5f} | "
                       f"SL={sl:.5f} | TP={tp:.5f}")

        return {**result, "action": "open",
                "symbol": symbol, "lot_size": lot_size}

    async def _close_trade(self, context: Dict) -> Dict:
        ticket = context.get("ticket")
        volume = context.get("volume")
        self._emit(f"⬛ Closing position {ticket}...")
        result = await self.mt5.close_position(ticket, volume)
        if result.get("success"):
            self._pending_orders.pop(ticket, None)
            self._emit(f"✅ CLOSED position {ticket}")
        return {**result, "action": "close"}

    async def _modify_trade(self, context: Dict) -> Dict:
        ticket = context.get("ticket")
        sl = context.get("sl", 0.0)
        tp = context.get("tp", 0.0)
        self._emit(f"✏ Modifying position {ticket} | SL={sl:.5f} | TP={tp:.5f}")
        result = await self.mt5.modify_position(ticket, sl, tp)
        if result.get("success") and ticket in self._pending_orders:
            self._pending_orders[ticket]["sl"] = sl
            self._pending_orders[ticket]["tp"] = tp
        return {**result, "action": "modify"}

    async def _close_all(self, context: Dict) -> Dict:
        """Emergency: close all open positions."""
        symbol_filter = context.get("symbol")
        self._emit(f"🚨 Closing ALL positions{' for ' + symbol_filter if symbol_filter else ''}...",
                   "warning")
        positions = await self.mt5.get_positions(symbol_filter)
        results = []
        for pos in positions:
            result = await self.mt5.close_position(pos["ticket"])
            results.append(result)
            await asyncio.sleep(0.1)
        self._emit(f"✅ Closed {len(results)} positions")
        return {"action": "close_all", "closed": len(results), "results": results}

    async def _update_trailing_stops(self, context: Dict) -> Dict:
        """Update trailing stops for all managed positions."""
        from ..core.risk import RiskCalculator
        risk_calc: RiskCalculator = context.get("risk_calc")
        atrs: dict = context.get("atrs", {})
        positions = await self.mt5.get_positions()
        updated = 0
        for pos in positions:
            symbol = pos.get("symbol", "")
            atr = atrs.get(symbol, 0.001)
            if risk_calc and atr > 0:
                new_sl = risk_calc.calculate_trailing_stop(pos, pos.get("price_current", 0), atr)
                if new_sl is not None:
                    result = await self.mt5.modify_position(
                        pos["ticket"], new_sl, pos.get("tp", 0))
                    if result.get("success"):
                        updated += 1
        return {"action": "trailing_stop", "updated": updated}

    def get_execution_stats(self) -> Dict:
        return {
            "executed_today": self._executed_today,
            "tracked_orders": len(self._pending_orders),
        }
