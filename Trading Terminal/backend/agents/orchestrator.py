"""
Orchestrator Agent - Master controller for all Quant-Joker AI agents.
Runs the full agentic loop: news → strategy → backtest → performance → trade management.
Coordinates agent execution, shares context, and drives system-wide optimization.
"""
import asyncio
import json
from datetime import datetime
from typing import Any

from .base_agent import BaseAgent, broadcast, AgentMessage, AgentStatus
from .news_agent import NewsAgent
from .strategy_agent import StrategyAgent
from .backtest_agent import BacktestAgent
from .performance_agent import PerformanceAgent
from .trade_manager_agent import TradeManagerAgent
from config.settings import settings


ORCHESTRATOR_PROMPT = """You are the master AI orchestrator for Quant-Joker Trader, an algorithmic trading system.
Your job is to coordinate all sub-agents and make the highest-level decisions about:
- Which strategies to deploy right now
- How aggressively to trade
- What the current market opportunity score is
- Whether to scale up, maintain, or halt trading

Always prioritize: maximum risk-adjusted returns in minimum time. Be decisive and systematic."""


class Orchestrator(BaseAgent):
    """Master orchestrator coordinating all trading agents."""

    def __init__(self):
        super().__init__(
            agent_id="orchestrator",
            name="Quant-Joker Orchestrator",
            description="Master AI controller that coordinates all agents for maximum profit optimization",
        )
        self.news_agent = NewsAgent()
        self.strategy_agent = StrategyAgent()
        self.backtest_agent = BacktestAgent()
        self.performance_agent = PerformanceAgent()
        self.trade_manager = TradeManagerAgent()

        self._loop_task: asyncio.Task | None = None
        self._running = False
        self.cycle_count = 0
        self.last_cycle: str | None = None
        self.system_state: dict = {
            "market_regime": "unknown",
            "opportunity_score": 0.0,
            "trading_mode": "paused",
            "active_strategies": [],
            "risk_level": "medium",
        }
        self.cycle_results: list[dict] = []

    def get_all_agents(self) -> list[dict]:
        """Return status of all agents."""
        return [
            self.to_dict(),
            self.news_agent.to_dict(),
            self.strategy_agent.to_dict(),
            self.backtest_agent.to_dict(),
            self.performance_agent.to_dict(),
            self.trade_manager.to_dict(),
        ]

    def get_system_state(self) -> dict:
        return {
            **self.system_state,
            "cycle_count": self.cycle_count,
            "last_cycle": self.last_cycle,
            "is_running": self._running,
        }

    async def _get_mt5_context(self) -> dict:
        """Gather current market context from MT5."""
        context = {
            "symbol": "EURUSD",
            "timeframe": "H1",
            "session": self._current_session(),
            "equity": 10000,
            "volatility": "medium",
            "trend": "unknown",
        }
        try:
            import MetaTrader5 as mt5
            account = mt5.account_info()
            if account:
                context["equity"] = account.equity
                context["balance"] = account.balance

            # Get last 50 candles to assess trend and volatility
            rates = mt5.copy_rates_from_pos("EURUSD", mt5.TIMEFRAME_H1, 0, 50)
            if rates is not None and len(rates) > 20:
                import numpy as np
                closes = [r[4] for r in rates]  # close prices
                sma20 = sum(closes[-20:]) / 20
                sma50 = sum(closes) / len(closes)
                current = closes[-1]
                returns = [closes[i]/closes[i-1]-1 for i in range(1, len(closes))]
                vol = float(np.std(returns) * 100)

                context["trend"] = "bullish" if current > sma20 > sma50 else ("bearish" if current < sma20 < sma50 else "ranging")
                context["volatility"] = "high" if vol > 0.05 else ("low" if vol < 0.02 else "medium")
        except Exception:
            pass
        return context

    def _current_session(self) -> str:
        hour = datetime.utcnow().hour
        if 8 <= hour < 12:
            return "London"
        elif 12 <= hour < 17:
            return "London/New York Overlap"
        elif 17 <= hour < 22:
            return "New York"
        elif 22 <= hour or hour < 2:
            return "Sydney"
        else:
            return "Tokyo"

    async def run_full_cycle(self) -> dict:
        """Execute a complete orchestration cycle."""
        self.status = AgentStatus.RUNNING
        cycle_start = datetime.utcnow().isoformat()
        await self.log("info", f"═══ ORCHESTRATOR CYCLE #{self.cycle_count + 1} STARTED ═══")

        # Phase 1: Gather market context
        await self.log("thinking", "Phase 1/5: Gathering market context from MT5...")
        context = await self._get_mt5_context()
        await self.log("action", f"Market context: {context.get('symbol')}/{context.get('timeframe')} | Session: {context.get('session')} | Trend: {context.get('trend')} | Vol: {context.get('volatility')}")

        # Phase 2: News analysis
        await self.log("thinking", "Phase 2/5: Running News Intelligence Agent...")
        self.news_agent.status = AgentStatus.RUNNING
        news_result = await self.news_agent.safe_run(context)
        news_analysis = news_result.get("analysis", {}) if news_result else {}
        context["news_sentiment"] = news_analysis.get("overall_sentiment", "neutral")

        # Phase 3: Strategy research
        await self.log("thinking", "Phase 3/5: Running Strategy Research Agent...")
        self.strategy_agent.status = AgentStatus.RUNNING
        strategy_result = await self.strategy_agent.safe_run(context)
        recommended = strategy_result.get("recommended_strategies", []) if strategy_result else []
        context["recommended_strategies"] = recommended

        # Phase 4: Backtesting recommended strategies
        await self.log("thinking", "Phase 4/5: Running Backtesting Engine...")
        strategies_to_test = [r["strategy_id"] for r in recommended[:3] if r.get("strategy_id")]
        if not strategies_to_test:
            strategies_to_test = ["rsi", "sma_cross"]

        backtest_context = {
            **context,
            "strategies": strategies_to_test,
            "cash": context.get("balance", 10000.0),
        }
        self.backtest_agent.status = AgentStatus.RUNNING
        backtest_result = await self.backtest_agent.safe_run(backtest_context)
        rankings = backtest_result.get("rankings", []) if backtest_result else []
        context["backtest_rankings"] = rankings

        # Phase 5: Performance evaluation
        await self.log("thinking", "Phase 5/5: Running Performance Optimizer...")
        active_strategies = [r["strategy_id"] for r in rankings[:2] if r.get("composite_score", 0) > 10]
        context["active_strategies"] = active_strategies
        self.performance_agent.status = AgentStatus.RUNNING
        performance_result = await self.performance_agent.safe_run(context)
        perf_recommendations = (performance_result or {}).get("recommendations", {})

        # Phase 6: Trade management
        await self.log("thinking", "Phase 6: Trade Manager checking positions...")
        self.trade_manager.status = AgentStatus.RUNNING
        trade_result = await self.trade_manager.safe_run({
            **context,
            "equity": (performance_result or {}).get("account", {}).get("equity", 10000) if performance_result else 10000,
        })

        # Orchestrator AI decision
        await self.log("thinking", "Synthesizing all agent results into final trading decision...")
        await self._make_final_decision(context, news_analysis, rankings, perf_recommendations)

        self.cycle_count += 1
        self.last_cycle = datetime.utcnow().isoformat()
        self.status = AgentStatus.DONE

        cycle_summary = {
            "cycle": self.cycle_count,
            "started_at": cycle_start,
            "completed_at": self.last_cycle,
            "symbol": context.get("symbol"),
            "session": context.get("session"),
            "trend": context.get("trend"),
            "news_sentiment": context.get("news_sentiment"),
            "strategies_tested": len(rankings),
            "active_strategies": active_strategies,
            "system_state": self.system_state.copy(),
            "trade_actions": len((trade_result or {}).get("actions_taken", [])),
        }
        self.cycle_results.append(cycle_summary)
        if len(self.cycle_results) > 50:
            self.cycle_results = self.cycle_results[-50:]

        await self.log("result", f"═══ CYCLE #{self.cycle_count} COMPLETE ═══ Mode: {self.system_state['trading_mode'].upper()} | Score: {self.system_state['opportunity_score']:.2f} | Active: {active_strategies}", cycle_summary)

        return cycle_summary

    async def _make_final_decision(self, context: dict, news: dict, rankings: list, perf_recs: dict):
        """Master AI decision on trading mode and opportunity score."""
        prompt = f"""Synthesize all agent reports and make final trading decisions:

MARKET CONTEXT: {json.dumps(context, indent=2)}
NEWS ANALYSIS: sentiment={news.get('overall_sentiment')}, risk={news.get('risk_appetite')}, themes={news.get('key_themes')}
TOP STRATEGIES: {json.dumps([{{'id': r.get('strategy_id'), 'score': r.get('composite_score'), 'return': r.get('stats',{{}}).get('total_return_pct')}} for r in rankings[:3]], indent=2)}
PERFORMANCE RECS: grade={perf_recs.get('performance_grade')}, health={perf_recs.get('system_health')}, timing={perf_recs.get('market_timing')}

Respond ONLY with JSON:
{{
  "opportunity_score": 0.0-1.0,
  "trading_mode": "aggressive|normal|conservative|paused",
  "market_regime": "trending|ranging|volatile|transitional",
  "strategies_to_activate": ["strategy_id"],
  "risk_level": "low|medium|high",
  "position_size_multiplier": 0.5-2.0,
  "max_trades": 1-10,
  "decision_summary": "one sentence decision summary"
}}"""

        response = await self.ai_call(ORCHESTRATOR_PROMPT, prompt)
        try:
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                response = response.split("```")[1].split("```")[0]
            decision = json.loads(response.strip())
            self.system_state.update({
                "market_regime": decision.get("market_regime", "unknown"),
                "opportunity_score": decision.get("opportunity_score", 0.0),
                "trading_mode": decision.get("trading_mode", "paused"),
                "active_strategies": decision.get("strategies_to_activate", []),
                "risk_level": decision.get("risk_level", "medium"),
            })
            await self.log("result", f"DECISION: {decision.get('decision_summary', '')}", decision)

            # If aggressive/normal mode and high confidence, execute signals
            if decision.get("trading_mode") in ("aggressive", "normal") and decision.get("opportunity_score", 0) >= 0.65:
                await self._auto_execute_signals(decision, rankings)

        except Exception as e:
            await self.log("error", f"Final decision parse error: {e}")

    async def _auto_execute_signals(self, decision: dict, rankings: list):
        """Auto-execute trade signals when conditions are met."""
        signals_to_execute = []
        for strategy_id in decision.get("strategies_to_activate", []):
            for r in rankings:
                if r.get("strategy_id") == strategy_id and r.get("stats"):
                    stats = r["stats"]
                    if stats.get("sharpe_ratio", 0) >= settings.MIN_SHARPE and stats.get("win_rate", 0) >= 50:
                        signal = {
                            "symbol": "EURUSD",
                            "direction": "buy",  # Would come from live signal in production
                            "confidence": min(1.0, decision.get("opportunity_score", 0.5) + 0.1),
                            "sl_pips": 25,
                            "tp_pips": 50,
                            "volume": 0.01 * decision.get("position_size_multiplier", 1.0),
                            "comment": f"QJ-Auto-{strategy_id}",
                            "risk_pct": settings.MAX_RISK_PCT * 0.5,
                        }
                        signals_to_execute.append(signal)

        if signals_to_execute:
            await self.log("action", f"Auto-executing {len(signals_to_execute)} signals...")
            await self.trade_manager.execute_signal_batch(signals_to_execute)

    async def start_loop(self, interval_seconds: int | None = None):
        """Start the continuous orchestration loop."""
        if self._running:
            await self.log("info", "Orchestrator loop already running")
            return
        self._running = True
        interval = interval_seconds or settings.AGENT_LOOP_INTERVAL
        await self.log("info", f"Orchestrator loop started (interval: {interval}s)")
        self._loop_task = asyncio.create_task(self._run_loop(interval))

    async def _run_loop(self, interval: int):
        """Internal loop that continuously runs cycles."""
        while self._running:
            try:
                await self.run_full_cycle()
            except Exception as e:
                await self.log("error", f"Cycle error: {e}")
            await asyncio.sleep(interval)

    async def stop_loop(self):
        """Stop the orchestration loop."""
        self._running = False
        if self._loop_task:
            self._loop_task.cancel()
            self._loop_task = None
        self.status = AgentStatus.IDLE
        await self.log("info", "Orchestrator loop stopped")

    async def run(self, context: dict | None = None) -> dict:
        """Single cycle run (used by safe_run)."""
        return await self.run_full_cycle()


# Singleton instance
orchestrator = Orchestrator()
