"""
Performance Evaluation Agent - Monitors live system performance and optimizes for maximum profit.
Adapts strategy parameters, manages portfolio allocation, and drives system improvements.
"""
import json
import asyncio
from datetime import datetime, timedelta
from typing import Any

from .base_agent import BaseAgent


PERFORMANCE_PROMPT = """You are a quantitative fund manager and systematic trading expert.
Your role is to evaluate trading system performance, identify weaknesses, and provide concrete optimization instructions.
Always prioritize risk-adjusted returns and capital preservation while maximizing profit.
Respond in valid JSON only."""


class PerformanceAgent(BaseAgent):
    """Evaluates system performance and drives optimization decisions."""

    def __init__(self):
        super().__init__(
            agent_id="performance_agent",
            name="Performance Optimizer",
            description="Evaluates live performance and optimizes the entire system for maximum risk-adjusted profit",
        )
        self.performance_history: list[dict] = []
        self.active_strategies: list[dict] = []
        self.system_recommendations: list[dict] = []
        self.equity_curve: list[dict] = []
        self.metrics: dict = {}

    def update_equity(self, balance: float, equity: float, timestamp: str | None = None):
        """Record equity snapshot for curve tracking."""
        self.equity_curve.append({
            "time": timestamp or datetime.utcnow().isoformat(),
            "balance": balance,
            "equity": equity,
        })
        if len(self.equity_curve) > 1440:  # keep 24h of minute data
            self.equity_curve = self.equity_curve[-1440:]

    def compute_live_metrics(self, trade_history: list[dict]) -> dict:
        """Compute live performance metrics from trade history."""
        if not trade_history:
            return {}

        profits = [t.get("profit", 0) for t in trade_history]
        wins = [p for p in profits if p > 0]
        losses = [p for p in profits if p <= 0]

        total_profit = sum(profits)
        gross_profit = sum(wins)
        gross_loss = abs(sum(losses))
        win_rate = len(wins) / len(profits) * 100 if profits else 0
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else (2.0 if gross_profit > 0 else 0)

        avg_win = sum(wins) / len(wins) if wins else 0
        avg_loss = abs(sum(losses) / len(losses)) if losses else 0
        risk_reward = avg_win / avg_loss if avg_loss > 0 else 0

        # Drawdown from equity curve
        max_dd = 0
        if self.equity_curve:
            equities = [e["equity"] for e in self.equity_curve]
            peak = equities[0]
            for eq in equities:
                if eq > peak:
                    peak = eq
                dd = (peak - eq) / peak * 100 if peak > 0 else 0
                max_dd = max(max_dd, dd)

        return {
            "total_trades": len(trade_history),
            "total_profit": round(total_profit, 2),
            "win_rate": round(win_rate, 1),
            "profit_factor": round(profit_factor, 2),
            "risk_reward": round(risk_reward, 2),
            "avg_win": round(avg_win, 2),
            "avg_loss": round(avg_loss, 2),
            "gross_profit": round(gross_profit, 2),
            "gross_loss": round(gross_loss, 2),
            "max_drawdown_pct": round(max_dd, 2),
            "consecutive_losses": self._max_consecutive_losses(profits),
        }

    def _max_consecutive_losses(self, profits: list[float]) -> int:
        max_streak = 0
        current = 0
        for p in profits:
            if p <= 0:
                current += 1
                max_streak = max(max_streak, current)
            else:
                current = 0
        return max_streak

    async def fetch_live_trades(self) -> tuple[list[dict], dict | None]:
        """Fetch closed trades and account info from MT5."""
        try:
            import MetaTrader5 as mt5
            account = mt5.account_info()
            account_dict = None
            if account:
                account_dict = {
                    "balance": account.balance,
                    "equity": account.equity,
                    "margin": account.margin,
                    "free_margin": account.margin_free,
                    "profit": account.profit,
                    "currency": account.currency,
                }
                self.update_equity(account.balance, account.equity)

            # Get last 100 closed deals
            from_date = datetime.utcnow() - timedelta(days=30)
            deals = mt5.history_deals_get(from_date, datetime.utcnow())
            trade_history = []
            if deals:
                for d in deals:
                    if d.type in (0, 1):  # buy/sell deals
                        trade_history.append({
                            "ticket": d.ticket,
                            "symbol": d.symbol,
                            "type": "buy" if d.type == 0 else "sell",
                            "volume": d.volume,
                            "price": d.price,
                            "profit": d.profit,
                            "commission": d.commission,
                            "swap": d.swap,
                            "time": datetime.fromtimestamp(d.time).isoformat(),
                        })
            return trade_history, account_dict
        except Exception as e:
            await self.log("info", f"MT5 not connected for live trades: {e}. Using demo data.")
            # Demo data
            import random
            random.seed(42)
            trades = []
            for i in range(20):
                profit = random.gauss(15, 40)
                trades.append({
                    "ticket": 1000 + i,
                    "symbol": random.choice(["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]),
                    "type": random.choice(["buy", "sell"]),
                    "volume": 0.1,
                    "price": 1.1000 + random.uniform(-0.01, 0.01),
                    "profit": round(profit, 2),
                    "commission": -0.5,
                    "swap": 0,
                    "time": (datetime.utcnow() - timedelta(days=random.randint(0, 30))).isoformat(),
                })
            return trades, {"balance": 10000, "equity": 10150, "margin": 200, "free_margin": 9800, "profit": 150, "currency": "USD"}

    async def run(self, context: dict | None = None) -> dict:
        """Evaluate performance and generate optimization recommendations."""
        await self.log("thinking", "Evaluating live system performance and generating optimization plan...")

        ctx = context or {}
        trade_history, account = await self.fetch_live_trades()

        metrics = self.compute_live_metrics(trade_history)
        self.metrics = metrics
        await self.log("action", f"Computed metrics: {len(trade_history)} trades, WinRate={metrics.get('win_rate', 0):.1f}%, PF={metrics.get('profit_factor', 0):.2f}")

        backtest_rankings = ctx.get("backtest_rankings", [])
        active_strategies = ctx.get("active_strategies", [])
        news_sentiment = ctx.get("news_sentiment", "neutral")

        prompt = f"""Evaluate trading system performance and provide optimization instructions:

LIVE METRICS:
{json.dumps(metrics, indent=2)}

ACCOUNT:
{json.dumps(account, indent=2)}

ACTIVE STRATEGIES: {json.dumps(active_strategies)}

BACKTEST RANKINGS (top 5):
{json.dumps(backtest_rankings[:5], indent=2)}

NEWS SENTIMENT: {news_sentiment}

Respond ONLY with JSON:
{{
  "performance_grade": "A|B|C|D|F",
  "system_health": "excellent|good|fair|poor",
  "critical_issues": ["issue1"],
  "strategy_adjustments": [
    {{
      "strategy_id": "...",
      "action": "keep|reduce_size|disable|optimize",
      "reason": "...",
      "new_params": {{}}
    }}
  ],
  "capital_allocation": {{
    "strategy_id_1": 0.0-1.0,
    "strategy_id_2": 0.0-1.0
  }},
  "risk_adjustments": {{
    "max_risk_pct": 0.0-5.0,
    "max_concurrent_trades": 1-10,
    "daily_loss_limit_pct": 0.0-10.0
  }},
  "new_strategies_to_backtest": ["strategy_id1"],
  "market_timing": "aggressive|normal|conservative|pause",
  "priority_actions": ["action1", "action2"],
  "optimization_summary": "2-3 sentences on system status and key improvements"
}}"""

        response = await self.ai_call(PERFORMANCE_PROMPT, prompt)

        try:
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                response = response.split("```")[1].split("```")[0]

            recommendations = json.loads(response.strip())
            self.system_recommendations = recommendations.get("priority_actions", [])

            await self.log(
                "result",
                f"System grade: {recommendations.get('performance_grade', '?')} | Health: {recommendations.get('system_health', '?')} | Timing: {recommendations.get('market_timing', '?')}",
                recommendations,
            )

            return {
                "metrics": metrics,
                "account": account,
                "trade_count": len(trade_history),
                "recommendations": recommendations,
                "equity_curve": self.equity_curve[-100:],
            }

        except Exception as e:
            await self.log("error", f"Performance analysis parse error: {e}")
            return {
                "metrics": metrics,
                "account": account,
                "trade_count": len(trade_history),
                "recommendations": {},
                "equity_curve": self.equity_curve[-100:],
                "error": str(e),
            }
