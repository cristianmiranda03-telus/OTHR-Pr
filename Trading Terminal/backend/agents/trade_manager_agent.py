"""
Trade Manager Agent - Monitors open positions and manages risk in real-time.
Sends orders to MT5, closes risky positions, and manages multi-trade execution.
"""
import json
import asyncio
from datetime import datetime
from typing import Any

from .base_agent import BaseAgent
from config.settings import settings


TRADE_MANAGER_PROMPT = """You are a professional forex risk manager and trade execution specialist.
Your job is to evaluate open positions in real-time and make precise decisions on:
- Closing positions that are losing beyond acceptable limits
- Moving stop-losses to breakeven when in sufficient profit
- Scaling out profitable positions
- Identifying which signals to execute immediately

Always prioritize capital preservation. Be decisive. Respond in JSON only."""


class TradeManagerAgent(BaseAgent):
    """Monitors and manages open MT5 positions in real-time."""

    def __init__(self):
        super().__init__(
            agent_id="trade_manager",
            name="Trade Manager",
            description="Real-time position monitor, risk manager, and order executor",
        )
        self.open_positions: list[dict] = []
        self.pending_signals: list[dict] = []
        self.executed_signals: list[dict] = []
        self.closed_positions: list[dict] = []

    def get_open_positions(self) -> list[dict]:
        """Fetch open positions from MT5."""
        try:
            import MetaTrader5 as mt5
            positions = mt5.positions_get()
            if positions is None:
                return []
            result = []
            for p in positions:
                result.append({
                    "ticket": p.ticket,
                    "symbol": p.symbol,
                    "type": "buy" if p.type == 0 else "sell",
                    "volume": p.volume,
                    "open_price": p.price_open,
                    "current_price": p.price_current,
                    "sl": p.sl,
                    "tp": p.tp,
                    "profit": p.profit,
                    "swap": p.swap,
                    "comment": p.comment,
                    "magic": p.magic,
                    "open_time": datetime.fromtimestamp(p.time).isoformat(),
                    "pnl_pct": round((p.profit / (p.price_open * p.volume * 100000 + 1)) * 100, 3),
                })
            self.open_positions = result
            return result
        except Exception:
            # Demo positions when MT5 not connected
            return self.open_positions or []

    def close_position(self, ticket: int, comment: str = "Risk management") -> dict:
        """Close a position by ticket number."""
        try:
            import MetaTrader5 as mt5
            position = mt5.positions_get(ticket=ticket)
            if not position:
                return {"success": False, "error": "Position not found"}
            pos = position[0]
            trade_type = mt5.ORDER_TYPE_SELL if pos.type == 0 else mt5.ORDER_TYPE_BUY
            symbol_info = mt5.symbol_info(pos.symbol)
            if symbol_info is None:
                return {"success": False, "error": "Symbol info not found"}
            price = symbol_info.ask if trade_type == mt5.ORDER_TYPE_BUY else symbol_info.bid
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": pos.symbol,
                "volume": pos.volume,
                "type": trade_type,
                "position": ticket,
                "price": price,
                "deviation": 20,
                "magic": 999999,
                "comment": comment,
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }
            result = mt5.order_send(request)
            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return {"success": True, "ticket": ticket, "message": f"Closed at {price}"}
            return {"success": False, "error": f"Retcode: {result.retcode} - {result.comment}"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def send_order(self, signal: dict) -> dict:
        """Send a buy/sell order to MT5."""
        try:
            import MetaTrader5 as mt5
            symbol = signal["symbol"]
            direction = signal["direction"]  # "buy" or "sell"
            volume = signal.get("volume", 0.01)
            sl_pips = signal.get("sl_pips", 20)
            tp_pips = signal.get("tp_pips", 40)

            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                return {"success": False, "error": f"Symbol {symbol} not found"}

            if not symbol_info.visible:
                mt5.symbol_select(symbol, True)

            point = symbol_info.point
            price = symbol_info.ask if direction == "buy" else symbol_info.bid
            order_type = mt5.ORDER_TYPE_BUY if direction == "buy" else mt5.ORDER_TYPE_SELL

            sl = price - sl_pips * point * 10 if direction == "buy" else price + sl_pips * point * 10
            tp = price + tp_pips * point * 10 if direction == "buy" else price - tp_pips * point * 10

            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": symbol,
                "volume": float(volume),
                "type": order_type,
                "price": price,
                "sl": sl,
                "tp": tp,
                "deviation": 20,
                "magic": 888888,
                "comment": signal.get("comment", "Quant-Joker Auto"),
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }

            result = mt5.order_send(request)
            if result.retcode == mt5.TRADE_RETCODE_DONE:
                executed = {**signal, "ticket": result.order, "price": price, "executed_at": datetime.utcnow().isoformat(), "status": "executed"}
                self.executed_signals.append(executed)
                return {"success": True, "ticket": result.order, "price": price}
            return {"success": False, "error": f"Retcode: {result.retcode} - {result.comment}"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def move_to_breakeven(self, ticket: int, buffer_pips: float = 2.0) -> dict:
        """Move stop-loss to breakeven + buffer."""
        try:
            import MetaTrader5 as mt5
            position = mt5.positions_get(ticket=ticket)
            if not position:
                return {"success": False, "error": "Position not found"}
            pos = position[0]
            symbol_info = mt5.symbol_info(pos.symbol)
            if symbol_info is None:
                return {"success": False, "error": "Symbol info not found"}
            point = symbol_info.point
            new_sl = pos.price_open + buffer_pips * point * 10 if pos.type == 0 else pos.price_open - buffer_pips * point * 10
            request = {
                "action": mt5.TRADE_ACTION_SLTP,
                "position": ticket,
                "sl": new_sl,
                "tp": pos.tp,
            }
            result = mt5.order_send(request)
            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return {"success": True, "ticket": ticket, "new_sl": new_sl}
            return {"success": False, "error": f"Retcode: {result.retcode}"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    async def execute_signal_batch(self, signals: list[dict]) -> list[dict]:
        """Execute multiple trade signals when high confidence + low risk."""
        results = []
        max_trades = settings.MAX_CONCURRENT_TRADES
        current_open = len(self.get_open_positions())

        for signal in signals:
            if current_open >= max_trades:
                await self.log("info", f"Max concurrent trades ({max_trades}) reached. Signal skipped: {signal.get('symbol')}")
                break
            if signal.get("confidence", 0) >= 0.70 and signal.get("risk_pct", 99) <= settings.MAX_RISK_PCT:
                result = self.send_order(signal)
                results.append({"signal": signal, "result": result})
                if result.get("success"):
                    await self.log("action", f"Order executed: {signal['symbol']} {signal['direction']} | Ticket: {result.get('ticket')}")
                    current_open += 1
                else:
                    await self.log("error", f"Order failed: {signal['symbol']} - {result.get('error')}")
            else:
                await self.log("info", f"Signal below threshold: {signal.get('symbol')} confidence={signal.get('confidence', 0):.2f}")

        return results

    async def run(self, context: dict | None = None) -> dict:
        """Evaluate all open positions and manage risk."""
        await self.log("thinking", "Scanning open positions for risk management...")

        positions = self.get_open_positions()
        await self.log("action", f"Found {len(positions)} open positions. Evaluating risk...")

        if not positions:
            await self.log("info", "No open positions. Monitoring for new signals.")
            return {"positions": [], "actions_taken": [], "signals_pending": len(self.pending_signals)}

        ctx = context or {}
        news_sentiment = ctx.get("news_sentiment", "neutral")
        account_equity = ctx.get("equity", 10000)
        max_risk_pct = settings.MAX_RISK_PCT

        prompt = f"""Evaluate these open trading positions and decide actions:

POSITIONS:
{json.dumps(positions, indent=2)}

CONTEXT:
- News sentiment: {news_sentiment}
- Account equity: {account_equity}
- Max risk per trade: {max_risk_pct}%
- Max drawdown tolerance: 5%

Respond ONLY with JSON:
{{
  "actions": [
    {{
      "ticket": 123,
      "action": "keep|close|move_to_breakeven|partial_close",
      "reason": "...",
      "urgency": "immediate|normal|monitor"
    }}
  ],
  "overall_risk_level": "low|medium|high|critical",
  "portfolio_comment": "...",
  "suggested_new_signals": [
    {{
      "symbol": "...",
      "direction": "buy|sell",
      "confidence": 0.0-1.0,
      "sl_pips": 20,
      "tp_pips": 40,
      "volume": 0.01,
      "reason": "..."
    }}
  ]
}}"""

        response = await self.ai_call(TRADE_MANAGER_PROMPT, prompt)

        try:
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                response = response.split("```")[1].split("```")[0]

            decision = json.loads(response.strip())
            actions_taken = []

            for action_item in decision.get("actions", []):
                ticket = action_item.get("ticket")
                action = action_item.get("action", "keep")
                urgency = action_item.get("urgency", "normal")

                if action == "close" and urgency == "immediate":
                    result = self.close_position(ticket, reason := action_item.get("reason", "Risk management"))
                    actions_taken.append({"ticket": ticket, "action": "close", "result": result})
                    await self.log("action", f"CLOSED position #{ticket}: {reason}")
                elif action == "move_to_breakeven":
                    result = self.move_to_breakeven(ticket)
                    actions_taken.append({"ticket": ticket, "action": "breakeven", "result": result})
                    await self.log("action", f"Moved #{ticket} to breakeven")
                else:
                    await self.log("info", f"Position #{ticket}: {action} - {action_item.get('reason', '')}")

            # Queue new signals for execution
            new_signals = decision.get("suggested_new_signals", [])
            if new_signals:
                self.pending_signals.extend(new_signals)
                await self.log("action", f"Added {len(new_signals)} new trade signals to queue")

            await self.log(
                "result",
                f"Risk scan complete: {len(actions_taken)} actions taken, {len(new_signals)} new signals. Risk level: {decision.get('overall_risk_level', '?').upper()}",
                decision,
            )

            return {
                "positions": positions,
                "actions_taken": actions_taken,
                "decision": decision,
                "signals_pending": len(self.pending_signals),
            }

        except Exception as e:
            await self.log("error", f"Trade manager parse error: {e}")
            return {"positions": positions, "actions_taken": [], "error": str(e)}
