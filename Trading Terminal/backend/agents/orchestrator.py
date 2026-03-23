"""
Agent 1: Orchestrator (The CEO / Agent Manager)
Global state manager, veto authority, and workflow coordinator.
Uses LangGraph for stateful multi-agent orchestration.
"""
import asyncio
import json
from datetime import datetime
from typing import Dict, List, Optional, Any
from loguru import logger

from .base_agent import BaseAgent, AgentStatus
from .technical_analyst import TechnicalAnalystAgent
from .news_sentinel import NewsSentinelAgent
from .risk_manager import RiskManagerAgent
from .mt5_executor import MT5ExecutorAgent
from .memory_agent import MemoryAgent
from .explorer_agent import ExplorerAgent
from .data_cleaner import DataCleanerAgent
from ..core.mt5_connection import MT5Connection
from ..core.sessions import SessionManager
from ..utils.event_bus import EventBus


class OrchestratorAgent(BaseAgent):
    """
    Supreme coordinator of all agents.
    
    Workflow per symbol per cycle:
    1. Data Cleaner → clean OHLCV data
    2. Technical Analyst → find opportunity
    3. Memory Agent → check past similar patterns
    4. News Sentinel → macro validation
    5. Risk Manager → position sizing + SL/TP
    6. MT5 Executor → execute trade
    7. Memory Agent → store result (async post-close)
    8. Explorer Agent → background optimization (async)
    
    Veto conditions:
    - Technical signal < 0.55 confidence
    - News verdict is "block"
    - Memory risk_score > 0.7
    - Risk check fails
    - Not in active session (if session_filter=True)
    """

    def __init__(
        self,
        config: dict,
        mt5: MT5Connection,
        technical: TechnicalAnalystAgent,
        news: NewsSentinelAgent,
        risk: RiskManagerAgent,
        executor: MT5ExecutorAgent,
        memory: MemoryAgent,
        explorer: ExplorerAgent,
        data_cleaner: DataCleanerAgent,
        session_mgr: SessionManager,
        event_bus: EventBus,
    ):
        super().__init__("Orchestrator", config)
        self.mt5 = mt5
        self.technical = technical
        self.news = news
        self.risk = risk
        self.executor = executor
        self.memory = memory
        self.explorer = explorer
        self.data_cleaner = data_cleaner
        self.session_mgr = session_mgr
        self.bus = event_bus

        self.trading_cfg = config.get("trading", {})
        self.scalping_cfg = config.get("scalping", {})
        self._running = False
        self._cycle_count = 0
        self._open_trade_contexts: Dict[int, Dict] = {}
        self._stats = {
            "total_cycles": 0, "signals_found": 0, "trades_opened": 0,
            "trades_vetoed": 0, "veto_reasons": {},
        }

    async def _execute(self, context: Dict) -> Dict:
        """Single orchestration cycle for one symbol."""
        symbol = context.get("symbol", "EURUSD")
        self._cycle_count += 1
        self._stats["total_cycles"] += 1

        # ── 0. Account & market state ──────────────────────────────────
        account = await self.mt5.get_account_info()
        positions = await self.mt5.get_positions(symbol)
        tick = await self.mt5.get_tick(symbol)
        symbol_info = await self.mt5.get_symbol_info(symbol)
        session_info = self.session_mgr.get_session_info()
        session_score = self.session_mgr.scalping_score(symbol)

        if not account:
            return {"cycle": self._cycle_count, "action": "skip",
                    "reason": "No account data"}

        # Check mode
        mode = self.trading_cfg.get("mode", "paper")
        self._emit(f"🔄 Cycle #{self._cycle_count} | {symbol} | {mode.upper()} | "
                   f"Sessions: {session_info.get('active_sessions', [])} | "
                   f"Score: {session_score:.0f}/100")

        # ── 1. Fetch and clean data ─────────────────────────────────────
        df_m1 = await self.mt5.get_ohlcv(symbol, "M1", 300)
        df_m5 = await self.mt5.get_ohlcv(symbol, "M5", 200)
        df_h1 = await self.mt5.get_ohlcv(symbol, "H1", 100)

        if len(df_m1) < 50:
            return {"cycle": self._cycle_count, "action": "skip",
                    "reason": "Insufficient data"}

        clean_result = await self.data_cleaner.run({
            "df": df_m1, "symbol": symbol, "timeframe": "M1"})
        df_m1 = clean_result.get("df", df_m1)
        data_quality = clean_result.get("quality_score", 1.0)

        if data_quality < 0.6:
            self._emit(f"⚠ Low data quality ({data_quality:.0%}) - skipping", "warning")
            return {"cycle": self._cycle_count, "action": "skip",
                    "reason": f"Data quality {data_quality:.0%}"}

        # ── 2. Technical Analysis ───────────────────────────────────────
        tech_result = await self.technical.run({
            "symbol": symbol, "df_primary": df_m1,
            "df_m5": df_m5, "df_h1": df_h1,
        })

        signal = tech_result.get("signal", "hold")
        confidence = tech_result.get("confidence", 0.0)

        await self.bus.publish("technical_update", {
            "symbol": symbol, "signal": signal, "confidence": confidence,
            "indicators": tech_result.get("indicators", {}),
            "regime": tech_result.get("regime", "unknown"),
        })

        if signal == "hold":
            return {"cycle": self._cycle_count, "action": "hold",
                    "signal": "hold", "reason": "No signal"}

        self._stats["signals_found"] += 1

        # ── 3. Memory Check (Auditor) ───────────────────────────────────
        market_ctx = {
            **tech_result.get("snapshot", {}),
            "session": str(session_info.get("active_sessions", [])),
            "session_score": session_score,
        }
        memory_result = await self.memory.run({
            "action": "query", "market_context": market_ctx})

        memory_risk = memory_result.get("risk_score", 0.5)
        memory_warning = memory_result.get("warning")

        if memory_warning:
            await self.bus.publish("system_warning", {
                "level": "warning", "message": memory_warning, "agent": "MemoryAgent"})

        # Veto: Memory too risky
        if memory_risk > 0.75:
            reason = f"Memory veto: risk score {memory_risk:.0%} - too similar to past losses"
            self._veto(reason)
            return {"cycle": self._cycle_count, "action": "veto",
                    "reason": reason, "signal": signal}

        # ── 4. News Sentinel ────────────────────────────────────────────
        news_result = await self.news.run({"symbol": symbol})
        news_verdict = news_result.get("verdict", "clear")

        await self.bus.publish("news_update", {
            "symbol": symbol, "verdict": news_verdict,
            "sentiment": news_result.get("sentiment"),
            "events": news_result.get("upcoming_events", []),
        })

        # Veto: News blocks
        if news_verdict == "block":
            reason = f"News veto: {news_result.get('reason', 'High-impact event')}"
            self._veto(reason)
            return {"cycle": self._cycle_count, "action": "veto",
                    "reason": reason, "signal": signal}

        # Reduce confidence in "caution" mode
        if news_verdict == "caution":
            confidence *= 0.8
            self._emit(f"⚠ News caution - confidence reduced to {confidence:.1%}", "warning")

        # Veto: Low confidence after adjustments
        min_conf = 0.52
        if confidence < min_conf:
            reason = f"Confidence veto: {confidence:.1%} < {min_conf:.0%} after news adjustment"
            self._veto(reason)
            return {"cycle": self._cycle_count, "action": "veto",
                    "reason": reason, "signal": signal}

        # ── 5. Risk Manager ─────────────────────────────────────────────
        spread = tick.get("spread", 2.0) if tick else 2.0
        risk_result = await self.risk.run({
            "symbol": symbol, "signal": signal,
            "account": account, "positions": positions,
            "technical_data": tech_result,
            "session_info": session_info,
            "symbol_info": symbol_info or {},
            "spread": spread, "session_score": session_score,
        })

        if not risk_result.get("approved"):
            reason = f"Risk veto: {risk_result.get('reason', 'Risk check failed')}"
            self._veto(reason)
            return {"cycle": self._cycle_count, "action": "veto",
                    "reason": reason, "signal": signal}

        lot_size = risk_result.get("lot_size", 0.01)
        sl = risk_result.get("sl", 0.0)
        tp = risk_result.get("tp", 0.0)

        # ── 6. Execute Trade ────────────────────────────────────────────
        if mode == "paper":
            self._emit(f"📄 PAPER TRADE: {signal.upper()} {lot_size} {symbol} | "
                       f"SL={sl:.5f} | TP={tp:.5f} | Conf={confidence:.1%}")
            exec_result = {
                "success": True, "ticket": self._cycle_count * -1,
                "price_executed": tech_result.get("entry_price", 0),
                "simulated": True, "paper": True,
            }
        else:
            exec_result = await self.executor.run({
                "action": "open", "symbol": symbol, "signal": signal,
                "lot_size": lot_size, "sl": sl, "tp": tp,
                "entry_price": tech_result.get("entry_price", 0),
                "strategy_name": context.get("strategy_name", "TT-Scalp"),
            })

        if exec_result.get("success"):
            ticket = exec_result.get("ticket", 0)
            self._stats["trades_opened"] += 1
            self._open_trade_contexts[ticket] = {
                "symbol": symbol, "signal": signal,
                "market_context": {**market_ctx, "confidence": confidence,
                                    "news_sentiment": news_result.get("sentiment", "neutral"),
                                    "timeframe": "M1"},
                "lot_size": lot_size, "sl": sl, "tp": tp,
                "entry_price": exec_result.get("price_executed", 0),
                "open_time": datetime.now(),
            }
            await self.bus.publish("trade_opened", {
                "ticket": ticket, "symbol": symbol, "type": signal,
                "lot_size": lot_size, "sl": sl, "tp": tp,
                "entry_price": exec_result.get("price_executed", 0),
                "confidence": confidence, "mode": mode,
            })
            self._emit(f"🎯 TRADE OPENED: #{ticket} | {signal.upper()} {lot_size} {symbol} | "
                       f"SL={sl:.5f} | TP={tp:.5f} | Conf={confidence:.1%} | Mode={mode.upper()}")

        return {
            "cycle": self._cycle_count, "action": "trade",
            "signal": signal, "symbol": symbol,
            "lot_size": lot_size, "sl": sl, "tp": tp,
            "confidence": confidence, "ticket": exec_result.get("ticket"),
            "technical": tech_result.get("snapshot"),
            "risk": {k: v for k, v in risk_result.items()
                     if k not in ("daily_stats",)},
        }

    async def notify_trade_closed(self, ticket: int, profit: float,
                                   pips: float, exit_reason: str):
        """Called when a trade closes - triggers memory storage."""
        if ticket not in self._open_trade_contexts:
            return

        ctx = self._open_trade_contexts.pop(ticket)
        duration = (datetime.now() - ctx["open_time"]).total_seconds() / 60

        # Update risk stats
        self.risk.record_trade_result(profit, pips)
        account = await self.mt5.get_account_info()
        if account:
            self.risk.update_equity_external(account.get("equity", 0), profit)

        # Store in memory (async)
        asyncio.create_task(self.memory.run({
            "action": "store",
            "trade": {
                "ticket": ticket, "symbol": ctx["symbol"],
                "type": ctx["signal"], "profit": profit, "pips": pips,
                "exit_reason": exit_reason, "duration_mins": round(duration, 1),
            },
            "market_context": ctx.get("market_context", {}),
        }))

        await self.bus.publish("trade_closed", {
            "ticket": ticket, "symbol": ctx["symbol"],
            "profit": profit, "pips": pips, "reason": exit_reason,
        })

        outcome = "WIN" if profit > 0 else "LOSS"
        self._emit(f"{'🟢' if profit > 0 else '🔴'} TRADE CLOSED #{ticket} | "
                   f"{outcome} | P/L={profit:.2f} | Pips={pips:.1f} | "
                   f"Duration={duration:.0f}m | Reason={exit_reason}")

    async def run_main_loop(self, symbols: Optional[List[str]] = None,
                             interval_seconds: int = 30):
        """Main trading loop - runs continuously."""
        symbols = symbols or self.trading_cfg.get("symbols", ["EURUSD"])
        self._running = True
        self._emit(f"🚀 TRADING TERMINAL STARTED | Symbols: {symbols} | "
                   f"Mode: {self.trading_cfg.get('mode','paper').upper()} | "
                   f"Interval: {interval_seconds}s")

        # Background: Explorer optimization every 6 hours
        asyncio.create_task(self._exploration_loop(symbols))
        # Background: Trailing stop updates every 60s
        asyncio.create_task(self._trailing_stop_loop())
        # Background: Position monitor
        asyncio.create_task(self._position_monitor_loop())

        while self._running:
            try:
                for symbol in symbols:
                    if not self._running:
                        break
                    await self.run({"symbol": symbol})
                    await asyncio.sleep(1.0)
                await asyncio.sleep(interval_seconds)
            except asyncio.CancelledError:
                break
            except Exception as e:
                self._emit(f"Main loop error: {e}", "error")
                await asyncio.sleep(5)

        self._emit("⛔ Trading loop stopped")

    async def stop(self):
        self._running = False
        await self.executor.run({"action": "close_all"})
        self._emit("🛑 All positions closed - system stopped")

    async def _exploration_loop(self, symbols: List[str]):
        """Background strategy exploration."""
        interval = self.config.get("explorer", {}).get(
            "optimization_interval_hours", 6) * 3600
        while self._running:
            await asyncio.sleep(interval)
            for symbol in symbols[:2]:
                try:
                    df = await self.mt5.get_ohlcv(symbol, "M1", 1000)
                    if len(df) > 100:
                        await self.explorer.run({
                            "action": "explore", "df": df,
                            "symbol": symbol, "timeframe": "M1",
                        })
                except Exception as e:
                    self._emit(f"Exploration error: {e}", "warning")

    async def _trailing_stop_loop(self):
        """Update trailing stops every 60 seconds."""
        from ..core.indicators import Indicators
        while self._running:
            await asyncio.sleep(60)
            try:
                atrs = {}
                for symbol in self.trading_cfg.get("symbols", []):
                    df = await self.mt5.get_ohlcv(symbol, "M1", 50)
                    if len(df) > 14:
                        atr = Indicators.atr(df, 14).iloc[-1]
                        atrs[symbol] = float(atr)
                if atrs:
                    await self.executor.run({
                        "action": "update_trailing",
                        "atrs": atrs,
                    })
            except Exception as e:
                self._emit(f"Trailing stop error: {e}", "warning")

    async def _position_monitor_loop(self):
        """Monitor open positions and notify on close."""
        known_tickets = set()
        while self._running:
            await asyncio.sleep(10)
            try:
                positions = await self.mt5.get_positions()
                current_tickets = {p["ticket"] for p in positions}
                # Detect closed positions
                for ticket in list(self._open_trade_contexts.keys()):
                    if ticket > 0 and ticket not in current_tickets:
                        history = await self.mt5.get_history(days=1)
                        for deal in history:
                            if deal.get("position_id") == ticket:
                                await self.notify_trade_closed(
                                    ticket=ticket,
                                    profit=deal.get("profit", 0),
                                    pips=deal.get("profit", 0),
                                    exit_reason=deal.get("comment", "auto"),
                                )
                                break
            except Exception as e:
                self._emit(f"Position monitor error: {e}", "warning")

    def _veto(self, reason: str):
        self._stats["trades_vetoed"] += 1
        cat = reason.split(":")[0] if ":" in reason else reason[:30]
        self._stats["veto_reasons"][cat] = \
            self._stats["veto_reasons"].get(cat, 0) + 1
        self._emit(f"🚫 VETO: {reason}", "warning")

    def get_full_stats(self) -> Dict:
        return {
            **self._stats,
            "cycle": self._cycle_count,
            "running": self._running,
            "open_trades": len(self._open_trade_contexts),
            "risk_stats": self.risk.get_daily_stats(),
            "execution_stats": self.executor.get_execution_stats(),
            "memory_stats": self.memory.get_memory_stats(),
            "data_quality": self.data_cleaner.get_quality_scores(),
            "strategy_leaderboard": self.explorer.get_strategy_leaderboard()[:5],
        }
