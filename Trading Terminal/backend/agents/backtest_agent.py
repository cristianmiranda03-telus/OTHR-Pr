"""
Backtesting Agent - Runs and evaluates trading strategies on historical MT5 data.
Generates comprehensive performance statistics and ranks strategies.
"""
import json
import asyncio
from datetime import datetime, timedelta
from typing import Any

import pandas as pd
import numpy as np

from .base_agent import BaseAgent
from core.backtester import run_backtest
from strategies.strategies import get_strategy_class


BACKTEST_ANALYST_PROMPT = """You are a quantitative analyst specializing in trading strategy evaluation.
Analyze backtesting results and provide actionable insights on strategy quality, risk-adjusted returns, and deployment readiness.
Always respond in valid JSON format."""


class BacktestAgent(BaseAgent):
    """Runs backtests on strategies and evaluates performance."""

    def __init__(self):
        super().__init__(
            agent_id="backtest_agent",
            name="Backtesting Engine",
            description="Tests strategies on historical data and generates performance statistics",
        )
        self.results: dict[str, dict] = {}  # strategy_id -> backtest stats
        self.rankings: list[dict] = []

    def _fetch_mt5_data(self, symbol: str, timeframe: str, bars: int = 2000) -> pd.DataFrame | None:
        """Fetch historical OHLCV data from MT5."""
        try:
            import MetaTrader5 as mt5
            TF_MAP = {
                "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15,
                "M30": mt5.TIMEFRAME_M30, "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4,
                "D1": mt5.TIMEFRAME_D1, "W1": mt5.TIMEFRAME_W1,
            }
            tf = TF_MAP.get(timeframe, mt5.TIMEFRAME_H1)
            rates = mt5.copy_rates_from_pos(symbol, tf, 0, bars)
            if rates is None or len(rates) == 0:
                return None
            df = pd.DataFrame(rates)
            df["datetime"] = pd.to_datetime(df["time"], unit="s")
            df = df.rename(columns={"tick_volume": "volume"})
            return df[["datetime", "open", "high", "low", "close", "volume"]]
        except Exception:
            return None

    def _generate_demo_data(self, bars: int = 1000) -> pd.DataFrame:
        """Generate synthetic OHLCV data for testing when MT5 not connected."""
        np.random.seed(42)
        dates = pd.date_range(end=datetime.utcnow(), periods=bars, freq="1H")
        close = 1.1000
        prices = [close]
        for _ in range(bars - 1):
            ret = np.random.normal(0, 0.0005)
            close = max(0.5, close * (1 + ret))
            prices.append(close)
        prices = np.array(prices)
        opens = prices * (1 + np.random.normal(0, 0.0001, bars))
        highs = np.maximum(prices, opens) * (1 + np.abs(np.random.normal(0, 0.0003, bars)))
        lows = np.minimum(prices, opens) * (1 - np.abs(np.random.normal(0, 0.0003, bars)))
        volumes = np.random.randint(100, 5000, bars)
        return pd.DataFrame({
            "datetime": dates,
            "open": opens,
            "high": highs,
            "low": lows,
            "close": prices,
            "volume": volumes,
        })

    def compute_extra_stats(self, stats: dict, initial_cash: float) -> dict:
        """Compute additional metrics: profit factor, win rate, expectancy."""
        won = stats.get("won_trades", 0)
        lost = stats.get("lost_trades", 0)
        total = stats.get("total_trades", 0)
        win_rate = won / total if total > 0 else 0
        pnl = stats.get("final_value", initial_cash) - initial_cash
        expectancy = pnl / total if total > 0 else 0

        return {
            **stats,
            "win_rate": round(win_rate * 100, 1),
            "profit_factor": round(abs(won / lost) if lost > 0 else (2.0 if won > 0 else 0), 2),
            "expectancy_per_trade": round(expectancy, 2),
            "net_profit": round(pnl, 2),
            "initial_cash": initial_cash,
        }

    async def run_strategy_backtest(
        self,
        strategy_id: str,
        symbol: str = "EURUSD",
        timeframe: str = "H1",
        bars: int = 2000,
        cash: float = 10000.0,
        params: dict | None = None,
    ) -> dict:
        """Run a single strategy backtest."""
        await self.log("action", f"Backtesting '{strategy_id}' on {symbol}/{timeframe} ({bars} bars)...")

        # Get data
        df = self._fetch_mt5_data(symbol, timeframe, bars)
        if df is None:
            await self.log("info", "MT5 not connected, using synthetic data for backtest")
            df = self._generate_demo_data(bars)

        strategy_class = get_strategy_class(strategy_id)
        if strategy_class is None:
            return {"error": f"Strategy '{strategy_id}' not found", "stats": None}

        result = run_backtest(
            strategy_class=strategy_class,
            data_df=df,
            cash=cash,
            commission=0.0001,
            slippage=0.00005,
            strategy_params=params,
        )

        if result.get("stats"):
            result["stats"] = self.compute_extra_stats(result["stats"], cash)
            result["strategy_id"] = strategy_id
            result["symbol"] = symbol
            result["timeframe"] = timeframe
            result["bars"] = len(df)
            result["tested_at"] = datetime.utcnow().isoformat()
            self.results[strategy_id] = result
            await self.log("result", f"Backtest complete: {strategy_id} | Return: {result['stats'].get('total_return_pct', 0):.1f}% | Sharpe: {result['stats'].get('sharpe_ratio', 0):.2f} | WinRate: {result['stats'].get('win_rate', 0):.1f}%", result["stats"])

        return result

    async def run(self, context: dict | None = None) -> dict:
        """Run backtests on multiple strategies and rank them."""
        ctx = context or {}
        symbol = ctx.get("symbol", "EURUSD")
        timeframe = ctx.get("timeframe", "H1")
        strategies_to_test = ctx.get("strategies", ["rsi", "sma_cross"])
        cash = ctx.get("cash", 10000.0)

        await self.log("thinking", f"Running batch backtest on {len(strategies_to_test)} strategies for {symbol}/{timeframe}...")

        results = []
        for sid in strategies_to_test:
            r = await self.run_strategy_backtest(sid, symbol, timeframe, cash=cash)
            if r.get("stats"):
                results.append(r)
            await asyncio.sleep(0.1)

        # Rank by composite score: 40% return + 30% Sharpe + 30% win rate
        for r in results:
            s = r["stats"]
            score = (
                max(0, s.get("total_return_pct", 0)) * 0.4 +
                max(0, s.get("sharpe_ratio", 0)) * 30 * 0.3 +
                s.get("win_rate", 0) * 0.3
            )
            r["composite_score"] = round(score, 2)

        results.sort(key=lambda x: x.get("composite_score", 0), reverse=True)
        self.rankings = results

        await self.log("result", f"Backtesting complete: {len(results)} strategies ranked. Best: {results[0]['strategy_id'] if results else 'none'}", {"rankings": results[:5]})

        # AI analysis of results
        if results:
            await self._ai_analyze_results(results, symbol, timeframe)

        return {"rankings": results, "symbol": symbol, "timeframe": timeframe}

    async def _ai_analyze_results(self, results: list[dict], symbol: str, timeframe: str):
        """Use AI to analyze backtest results and provide deployment recommendations."""
        await self.log("thinking", "AI analyzing backtest results for deployment recommendation...")

        summary = []
        for r in results[:5]:
            s = r["stats"]
            summary.append({
                "strategy": r["strategy_id"],
                "return_pct": s.get("total_return_pct"),
                "sharpe": s.get("sharpe_ratio"),
                "win_rate": s.get("win_rate"),
                "max_dd": s.get("max_drawdown_pct"),
                "trades": s.get("total_trades"),
                "score": r.get("composite_score"),
            })

        prompt = f"""Analyze these backtesting results for {symbol} on {timeframe}:

{json.dumps(summary, indent=2)}

Respond ONLY with JSON:
{{
  "best_strategy": "strategy_id",
  "deployment_ready": ["list of strategy IDs ready for live trading"],
  "risk_level": "low|medium|high",
  "portfolio_recommendation": "use single best | use top-2 combined | avoid all",
  "position_sizing": "percentage of capital per trade",
  "warnings": ["warning1", "warning2"],
  "insights": "2-3 sentences on the results",
  "confidence_score": 0.0-1.0
}}"""

        response = await self.ai_call(BACKTEST_ANALYST_PROMPT, prompt)
        try:
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                response = response.split("```")[1].split("```")[0]
            analysis = json.loads(response.strip())
            await self.log("result", f"AI deployment analysis: Best={analysis.get('best_strategy')}, Ready={analysis.get('deployment_ready')}", analysis)
        except Exception as e:
            await self.log("error", f"AI analysis parse error: {e}")
