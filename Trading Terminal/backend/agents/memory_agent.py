"""
Agent 6: Memory & Critique Agent (The Auditor)
Learns from every trade - stores context, identifies patterns, warns about danger zones.
"""
import asyncio
import json
from datetime import datetime
from typing import Dict, List, Optional
from .base_agent import BaseAgent
from ..data.chromadb_manager import ChromaMemoryManager
from ..ai.llm_client import LLMClient


class MemoryAgent(BaseAgent):
    """
    The system's long-term memory and self-improvement engine:
    - Records every trade with full context
    - Identifies dangerous market patterns
    - Provides pattern-based risk warnings to Orchestrator
    - Tracks strategy evolution over time
    - Generates periodic performance critiques
    """

    def __init__(self, config: dict, memory_db: ChromaMemoryManager, llm: LLMClient):
        super().__init__("MemoryAgent", config)
        self.memory = memory_db
        self.llm = llm
        self._critique_history: List[Dict] = []

    async def _execute(self, context: Dict) -> Dict:
        action = context.get("action", "query")
        if action == "store":
            return await self._store_trade(context)
        elif action == "query":
            return await self._query_risk(context)
        elif action == "critique":
            return await self._generate_critique(context)
        elif action == "store_strategy":
            return await self._store_strategy(context)
        else:
            return {"error": f"Unknown action: {action}"}

    async def _store_trade(self, context: Dict) -> Dict:
        """Store completed trade with full market context."""
        trade_data = context.get("trade", {})
        market_ctx = context.get("market_context", {})
        trade_id = trade_data.get("ticket", str(datetime.now().timestamp()))
        outcome = "win" if trade_data.get("profit", 0) > 0 else "loss"
        profit = trade_data.get("profit", 0)

        full_context = {
            "symbol": trade_data.get("symbol", ""),
            "timeframe": market_ctx.get("timeframe", "M1"),
            "session": market_ctx.get("session", ""),
            "hour_utc": datetime.now().hour,
            "day_of_week": datetime.now().strftime("%A"),
            "indicators": market_ctx.get("indicators", {}),
            "news_sentiment": market_ctx.get("news_sentiment", "neutral"),
            "regime": market_ctx.get("regime", "unknown"),
            "signal_confidence": market_ctx.get("confidence", 0),
            "entry_reason": market_ctx.get("entry_reason", ""),
            "exit_reason": trade_data.get("exit_reason", ""),
            "duration_mins": trade_data.get("duration_mins", 0),
            "pips": trade_data.get("pips", 0),
        }

        await self.memory.store_trade_context(
            trade_id=str(trade_id),
            context=full_context,
            outcome=outcome,
            profit=float(profit),
        )

        self._emit(f"💾 Stored trade {trade_id} | {outcome.upper()} | P/L={profit:.2f}")

        # Trigger critique if enough data
        if len(self._critique_history) % 10 == 0:
            asyncio.create_task(self._auto_critique(full_context, trade_data))

        return {
            "stored": True, "trade_id": trade_id,
            "outcome": outcome, "profit": profit,
        }

    async def _query_risk(self, context: Dict) -> Dict:
        """Query memory for similar dangerous patterns."""
        current_ctx = context.get("market_context", {})
        self._emit(f"🔍 Querying memory for pattern risk...")
        risk_assessment = await self.memory.get_pattern_risk(current_ctx)
        risk_score = risk_assessment.get("risk_score", 0.5)
        recommendation = risk_assessment.get("recommendation", "neutral")
        similar_losses = risk_assessment.get("similar_losses", 0)
        similar_wins = risk_assessment.get("similar_wins", 0)

        # LLM interpretation of memories
        if similar_losses + similar_wins > 3:
            memories = risk_assessment.get("memories", [])
            memory_text = "\n".join([
                f"- {m['text']} (profit: {m['metadata'].get('profit', 0):.2f})"
                for m in memories
            ])
            llm_context = {
                "current_situation": current_ctx,
                "similar_past_trades": memory_text,
                "win_rate_similar": similar_wins / (similar_wins + similar_losses)
                    if (similar_wins + similar_losses) > 0 else 0.5,
            }
            llm_result = await self.llm.analyze_market(llm_context)
            if llm_result.get("confidence", 0) > 0.7:
                recommendation = llm_result.get("decision", recommendation)

        warning = None
        if risk_score > 0.65:
            warning = (f"⚠ Memory alert: {similar_losses} similar losses found "
                       f"(risk score: {risk_score:.0%})")
            self._emit(warning, "warning")

        result = {
            **risk_assessment,
            "warning": warning,
            "llm_recommendation": recommendation,
        }
        self._emit(f"🧠 Memory: risk={risk_score:.1%} | "
                   f"wins={similar_wins} | losses={similar_losses} | rec={recommendation}")
        return result

    async def _generate_critique(self, context: Dict) -> Dict:
        """Generate LLM critique of recent trading performance."""
        recent_trades = context.get("recent_trades", [])
        if not recent_trades:
            return {"critique": "No recent trades to analyze"}

        trade_summary = "\n".join([
            f"- {t.get('symbol','?')} {t.get('type','?')} "
            f"P/L:{t.get('profit',0):.2f} pips:{t.get('pips',0):.1f} "
            f"reason:{t.get('exit_reason','?')}"
            for t in recent_trades[-20:]
        ])
        wins = sum(1 for t in recent_trades if t.get("profit", 0) > 0)
        win_rate = wins / len(recent_trades) * 100

        prompt = f"""You are a professional trading analyst. Critique this trading session:

Trades (last {len(recent_trades)}):
{trade_summary}

Win Rate: {win_rate:.1f}%

Provide:
1. What is working well
2. What patterns in losses
3. Specific improvements
4. Risk management observations
5. Overall grade (A-F)

Be concise and actionable."""

        try:
            critique = await self.llm.chat([{"role": "user", "content": prompt}])
            entry = {"time": datetime.now().isoformat(), "critique": critique,
                     "win_rate": win_rate, "trades_analyzed": len(recent_trades)}
            self._critique_history.append(entry)
            self._emit(f"📝 Critique generated | Win rate: {win_rate:.1f}%")
            return {"critique": critique, "win_rate": win_rate}
        except Exception as e:
            return {"error": str(e)}

    async def _store_strategy(self, context: Dict) -> Dict:
        strategy_name = context.get("strategy_name", "unknown")
        metrics = context.get("metrics", {})
        await self.memory.store_strategy_performance(strategy_name, metrics)
        return {"stored": True, "strategy": strategy_name}

    async def _auto_critique(self, context: Dict, trade: Dict):
        """Background auto-critique after significant losses."""
        import asyncio
        if trade.get("profit", 0) < -50:
            self._emit("📊 Auto-critique triggered after significant loss", "warning")

    def get_memory_stats(self) -> Dict:
        return {"critiques": len(self._critique_history)}
