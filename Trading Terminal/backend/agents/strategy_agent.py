"""
Strategy Research Agent - Discovers and proposes new trading strategies.
Covers basic, advanced, quant, and AI-based approaches.
"""
import json
from typing import Any

from .base_agent import BaseAgent


STRATEGY_CATALOG = [
    # ── BASIC ──────────────────────────────────────────────────────────
    {
        "id": "rsi_ob_os",
        "name": "RSI Overbought/Oversold",
        "category": "basic",
        "description": "Buy when RSI < 30 (oversold), sell when RSI > 70 (overbought). Optional MA trend filter.",
        "timeframes": ["M15", "H1", "H4"],
        "indicators": ["RSI", "SMA"],
        "params": {"rsi_period": 14, "rsi_low": 30, "rsi_high": 70, "ma_period": 50, "use_ma_filter": True},
        "backtest_key": "rsi",
        "status": "active",
    },
    {
        "id": "sma_cross",
        "name": "SMA Golden/Death Cross",
        "category": "basic",
        "description": "Buy on golden cross (fast MA > slow MA), sell on death cross.",
        "timeframes": ["H1", "H4", "D1"],
        "indicators": ["SMA"],
        "params": {"fast": 10, "slow": 30},
        "backtest_key": "sma_cross",
        "status": "active",
    },
    {
        "id": "ema_cross",
        "name": "EMA Cross",
        "category": "basic",
        "description": "Exponential MA crossover for faster signal response vs SMA.",
        "timeframes": ["M15", "M30", "H1"],
        "indicators": ["EMA"],
        "params": {"fast": 9, "slow": 21},
        "backtest_key": "ema_cross",
        "status": "active",
    },
    {
        "id": "macd_signal",
        "name": "MACD Signal Cross",
        "category": "basic",
        "description": "Buy when MACD line crosses above signal line, sell on cross below.",
        "timeframes": ["H1", "H4"],
        "indicators": ["MACD"],
        "params": {"fast": 12, "slow": 26, "signal": 9},
        "backtest_key": "macd_signal",
        "status": "active",
    },
    {
        "id": "bb_squeeze",
        "name": "Bollinger Band Breakout",
        "category": "basic",
        "description": "Trade breakouts when price closes outside Bollinger Bands.",
        "timeframes": ["M30", "H1", "H4"],
        "indicators": ["Bollinger Bands"],
        "params": {"period": 20, "std_dev": 2.0},
        "backtest_key": "bb_breakout",
        "status": "active",
    },
    {
        "id": "stoch_cross",
        "name": "Stochastic Crossover",
        "category": "basic",
        "description": "Buy when %K crosses above %D in oversold zone (<20), sell in overbought zone (>80).",
        "timeframes": ["M15", "H1"],
        "indicators": ["Stochastic"],
        "params": {"k_period": 14, "d_period": 3, "slowing": 3},
        "backtest_key": "stoch_cross",
        "status": "active",
    },
    # ── ADVANCED ───────────────────────────────────────────────────────
    {
        "id": "rsi_macd_confluence",
        "name": "RSI + MACD Confluence",
        "category": "advanced",
        "description": "Requires both RSI oversold and MACD bullish cross simultaneously for high-probability entries.",
        "timeframes": ["H1", "H4"],
        "indicators": ["RSI", "MACD", "EMA"],
        "params": {"rsi_period": 14, "rsi_low": 35, "macd_fast": 12, "macd_slow": 26, "macd_signal": 9},
        "backtest_key": "rsi_macd_confluence",
        "status": "active",
    },
    {
        "id": "ichimoku_cloud",
        "name": "Ichimoku Cloud Strategy",
        "category": "advanced",
        "description": "Full Ichimoku system: Tenkan/Kijun cross, price above/below cloud, Chikou confirmation.",
        "timeframes": ["H4", "D1"],
        "indicators": ["Ichimoku"],
        "params": {"tenkan": 9, "kijun": 26, "senkou_b": 52},
        "backtest_key": "ichimoku",
        "status": "active",
    },
    {
        "id": "pivot_bounce",
        "name": "Pivot Point Bounce",
        "category": "advanced",
        "description": "Trade bounces off daily/weekly pivot support and resistance levels.",
        "timeframes": ["M15", "M30", "H1"],
        "indicators": ["Pivot Points", "RSI"],
        "params": {"pivot_type": "daily"},
        "backtest_key": "pivot_bounce",
        "status": "active",
    },
    {
        "id": "atr_breakout",
        "name": "ATR Channel Breakout",
        "category": "advanced",
        "description": "Breakout strategy using ATR to define volatility channels. Captures trending moves.",
        "timeframes": ["H1", "H4"],
        "indicators": ["ATR", "SMA"],
        "params": {"atr_period": 14, "multiplier": 2.0, "ma_period": 20},
        "backtest_key": "atr_breakout",
        "status": "active",
    },
    {
        "id": "mean_reversion",
        "name": "Mean Reversion (Z-Score)",
        "category": "advanced",
        "description": "Buy when price is >2 std deviations below the mean, sell when >2 above. Statistical arbitrage.",
        "timeframes": ["M30", "H1"],
        "indicators": ["Bollinger Bands", "Z-Score"],
        "params": {"lookback": 20, "z_threshold": 2.0},
        "backtest_key": "mean_reversion",
        "status": "active",
    },
    {
        "id": "fibonacci_retracement",
        "name": "Fibonacci Retracement",
        "category": "advanced",
        "description": "Trade pullbacks to key Fibonacci levels (38.2%, 50%, 61.8%) in trending markets.",
        "timeframes": ["H1", "H4", "D1"],
        "indicators": ["Fibonacci", "RSI"],
        "params": {"swing_lookback": 50, "entry_levels": [0.382, 0.5, 0.618]},
        "backtest_key": "fibonacci",
        "status": "active",
    },
    {
        "id": "vwap_reversion",
        "name": "VWAP Reversion",
        "category": "advanced",
        "description": "Mean reversion to VWAP. Short when price is extended above VWAP, long when below.",
        "timeframes": ["M5", "M15", "M30"],
        "indicators": ["VWAP", "Bollinger Bands"],
        "params": {"std_bands": [1.5, 2.5]},
        "backtest_key": "vwap_reversion",
        "status": "active",
    },
    # ── QUANT ──────────────────────────────────────────────────────────
    {
        "id": "momentum_factor",
        "name": "Price Momentum Factor",
        "category": "quant",
        "description": "Systematic momentum: long top-performing instruments, short worst over 12-1 month lookback.",
        "timeframes": ["D1", "W1"],
        "indicators": ["ROC", "SMA"],
        "params": {"lookback_months": 12, "skip_months": 1, "rebalance_days": 20},
        "backtest_key": "momentum_factor",
        "status": "active",
    },
    {
        "id": "carry_trade",
        "name": "Carry Trade Strategy",
        "category": "quant",
        "description": "Exploit interest rate differentials. Long high-yield currency, short low-yield.",
        "timeframes": ["D1", "W1"],
        "indicators": ["Interest Rate Diff"],
        "params": {"min_rate_diff": 1.5},
        "backtest_key": "carry_trade",
        "status": "active",
    },
    {
        "id": "volatility_regime",
        "name": "Volatility Regime Filter",
        "category": "quant",
        "description": "Switches between trend-following and mean-reversion based on VIX/ATR regime detection.",
        "timeframes": ["H4", "D1"],
        "indicators": ["ATR", "VIX-proxy", "ADX"],
        "params": {"atr_period": 14, "adx_period": 14, "adx_threshold": 25},
        "backtest_key": "volatility_regime",
        "status": "active",
    },
    {
        "id": "pairs_cointegration",
        "name": "Pairs Cointegration",
        "category": "quant",
        "description": "Statistical arbitrage on cointegrated pairs (e.g., EURUSD/GBPUSD spread). Mean-reverting spread trading.",
        "timeframes": ["H1", "H4"],
        "indicators": ["Z-Score", "Cointegration"],
        "params": {"window": 60, "entry_z": 2.0, "exit_z": 0.5},
        "backtest_key": "pairs_cointegration",
        "status": "active",
    },
    {
        "id": "kalman_filter",
        "name": "Kalman Filter Trend",
        "category": "quant",
        "description": "Kalman filter for dynamic price smoothing and trend estimation. Adaptive to market changes.",
        "timeframes": ["M30", "H1"],
        "indicators": ["Kalman Filter"],
        "params": {"obs_noise": 0.1, "trans_cov": 0.0001},
        "backtest_key": "kalman_filter",
        "status": "active",
    },
    # ── AI / ML ────────────────────────────────────────────────────────
    {
        "id": "ml_random_forest",
        "name": "Random Forest Classifier",
        "category": "ai",
        "description": "ML model trained on 50+ technical features to predict next-bar direction with probability score.",
        "timeframes": ["H1", "H4"],
        "indicators": ["RSI", "MACD", "BB", "ATR", "Volume", "EMA stack"],
        "params": {"n_estimators": 100, "min_confidence": 0.65, "train_bars": 2000},
        "backtest_key": "ml_random_forest",
        "status": "active",
    },
    {
        "id": "ml_gradient_boost",
        "name": "Gradient Boosting (XGBoost-style)",
        "category": "ai",
        "description": "Gradient boosted trees on engineered features. High accuracy on trending markets.",
        "timeframes": ["H1", "H4"],
        "indicators": ["Multi-indicator features"],
        "params": {"n_estimators": 200, "learning_rate": 0.05, "min_confidence": 0.60},
        "backtest_key": "ml_gradient_boost",
        "status": "active",
    },
    {
        "id": "lstm_sequence",
        "name": "LSTM Price Sequence",
        "category": "ai",
        "description": "Long Short-Term Memory neural network on OHLCV sequences for pattern recognition.",
        "timeframes": ["H1", "H4"],
        "indicators": ["Raw OHLCV", "RSI", "MACD"],
        "params": {"sequence_len": 60, "hidden_dim": 128, "min_confidence": 0.62},
        "backtest_key": "lstm_sequence",
        "status": "pending",
    },
    {
        "id": "reinforcement_learning",
        "name": "RL Trading Agent (PPO)",
        "category": "ai",
        "description": "Proximal Policy Optimization RL agent that learns optimal entry/exit through simulation.",
        "timeframes": ["M30", "H1"],
        "indicators": ["State space: OHLCV + 20 indicators"],
        "params": {"gamma": 0.99, "lr": 0.0003, "train_episodes": 10000},
        "backtest_key": "rl_ppo",
        "status": "research",
    },
    {
        "id": "llm_sentiment",
        "name": "LLM News Sentiment Trader",
        "category": "ai",
        "description": "Uses AI to score news sentiment in real-time and trade based on directional confidence score.",
        "timeframes": ["M15", "H1"],
        "indicators": ["News Sentiment Score", "RSI filter"],
        "params": {"min_confidence": 0.75, "news_window_min": 60},
        "backtest_key": "llm_sentiment",
        "status": "active",
    },
]

STRATEGY_RESEARCH_PROMPT = """You are a quantitative trading researcher and algorithm developer.
Your expertise covers: technical analysis, quantitative finance, machine learning, market microstructure, and risk management.
Provide precise, actionable strategy recommendations in JSON format."""


class StrategyAgent(BaseAgent):
    """Researches and proposes new trading strategies."""

    def __init__(self):
        super().__init__(
            agent_id="strategy_agent",
            name="Strategy Research",
            description="Researches and proposes new trading strategies (basic, advanced, quant, AI/ML)",
        )
        self.strategies = STRATEGY_CATALOG.copy()
        self.new_strategies: list[dict] = []
        self.recommended: list[dict] = []

    def get_all_strategies(self) -> list[dict]:
        return self.strategies

    def get_strategies_by_category(self, category: str) -> list[dict]:
        return [s for s in self.strategies if s["category"] == category]

    async def run(self, context: dict | None = None) -> dict:
        await self.log("thinking", "Analyzing current market conditions to recommend optimal strategies...")

        ctx = context or {}
        symbol = ctx.get("symbol", "EURUSD")
        timeframe = ctx.get("timeframe", "H1")
        volatility = ctx.get("volatility", "medium")
        trend = ctx.get("trend", "unknown")
        news_sentiment = ctx.get("news_sentiment", "neutral")
        session = ctx.get("session", "London")

        await self.log("action", f"Generating strategy recommendations for {symbol} on {timeframe} (Volatility: {volatility}, Trend: {trend})")

        prompt = f"""Given the following market conditions, recommend the BEST 3-5 trading strategies:

Symbol: {symbol}
Timeframe: {timeframe}
Volatility: {volatility}
Trend direction: {trend}
News sentiment: {news_sentiment}
Trading session: {session}

Available strategies: {json.dumps([{"id": s["id"], "name": s["name"], "category": s["category"]} for s in self.strategies], indent=2)}

Respond ONLY with JSON:
{{
  "recommended_strategies": [
    {{
      "strategy_id": "...",
      "confidence": 0.0-1.0,
      "reason": "...",
      "suggested_params": {{}},
      "expected_winrate": 0.0-1.0,
      "risk_level": "low|medium|high"
    }}
  ],
  "market_regime": "trending|ranging|volatile|transitional",
  "regime_confidence": 0.0-1.0,
  "new_strategy_idea": {{
    "name": "...",
    "description": "...",
    "category": "basic|advanced|quant|ai",
    "entry_logic": "...",
    "exit_logic": "...",
    "timeframes": ["..."],
    "indicators": ["..."]
  }},
  "analysis": "2-3 sentences on why these strategies fit current conditions"
}}"""

        response = await self.ai_call(STRATEGY_RESEARCH_PROMPT, prompt)

        try:
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                response = response.split("```")[1].split("```")[0]

            result = json.loads(response.strip())
            self.recommended = result.get("recommended_strategies", [])

            # If AI proposed a new strategy, add it to the catalog
            new_strat = result.get("new_strategy_idea")
            if new_strat and new_strat.get("name"):
                new_strat["id"] = f"ai_proposed_{len(self.new_strategies) + 1}"
                new_strat["status"] = "proposed"
                new_strat["params"] = {}
                new_strat["backtest_key"] = None
                self.new_strategies.append(new_strat)
                await self.log("action", f"AI proposed new strategy: {new_strat['name']}")

            await self.log(
                "result",
                f"Strategy research complete: {len(self.recommended)} strategies recommended for {symbol}/{timeframe}. Regime: {result.get('market_regime', '?')}",
                result,
            )
            return result

        except Exception as e:
            await self.log("error", f"Strategy research parse error: {e}")
            return {"recommended_strategies": [], "error": str(e)}
