"""
Agent 2: Technical Analyst (The Quant)
Deep market analysis using multi-timeframe indicators + ML pattern detection.
"""
import json
import numpy as np
import pandas as pd
from typing import Dict, List, Optional
from .base_agent import BaseAgent
from ..core.indicators import Indicators
from ..ai.llm_client import LLMClient


class TechnicalAnalystAgent(BaseAgent):
    """
    Identifies trading opportunities using:
    - Multi-timeframe confluence analysis
    - Market microstructure (order blocks, FVGs, liquidity sweeps)
    - Volume analysis and VWAP
    - LLM-enhanced pattern interpretation
    - Momentum scoring
    """

    def __init__(self, config: dict, llm: LLMClient):
        super().__init__("TechnicalAnalyst", config)
        self.llm = llm
        self.ind = Indicators()
        self._last_signals: Dict[str, Dict] = {}

    async def _execute(self, context: Dict) -> Dict:
        symbol = context.get("symbol", "EURUSD")
        primary_df = context.get("df_primary")
        df_h1 = context.get("df_h1")
        df_m5 = context.get("df_m5")

        if primary_df is None or len(primary_df) < 50:
            return {"signal": "hold", "reason": "Insufficient data",
                    "confidence": 0.0, "symbol": symbol}

        self.status = self.status.__class__.THINKING
        self._emit(f"🔍 Analyzing {symbol} - computing indicators...")

        # Compute all indicators
        df = self.ind.compute_all(primary_df)
        last = df.iloc[-1]
        prev = df.iloc[-2]

        # Core signal components
        trend_score = self._analyze_trend(df, df_h1)
        momentum_score = self._analyze_momentum(df)
        volatility_score = self._analyze_volatility(df, last)
        volume_score = self._analyze_volume(df, last)
        structure_data = self._analyze_market_structure(df)
        patterns = self.ind.candle_pattern(df)
        regime = self.ind.market_regime(df)

        # Combine into opportunity score
        long_score = (
            trend_score.get("long", 0) * 0.35 +
            momentum_score.get("long", 0) * 0.25 +
            volume_score.get("confirmation", 0) * 0.20 +
            self._pattern_score(patterns, "long") * 0.20
        )
        short_score = (
            trend_score.get("short", 0) * 0.35 +
            momentum_score.get("short", 0) * 0.25 +
            volume_score.get("confirmation", 0) * 0.20 +
            self._pattern_score(patterns, "short") * 0.20
        )

        # Determine signal
        threshold = 0.55
        if long_score > threshold and long_score > short_score:
            signal = "buy"
            confidence = min(long_score, 0.95)
        elif short_score > threshold and short_score > long_score:
            signal = "sell"
            confidence = min(short_score, 0.95)
        else:
            signal = "hold"
            confidence = 0.3

        # LLM enhanced analysis for non-trivial cases
        if 0.45 < max(long_score, short_score) < 0.75:
            self._emit("🤖 LLM deep analysis triggered...")
            llm_result = await self._llm_analysis(
                symbol, last, trend_score, momentum_score,
                patterns, structure_data, regime
            )
            if llm_result.get("confidence", 0) > confidence:
                signal = llm_result.get("decision", signal)
                confidence = llm_result.get("confidence", confidence)

        # Build detailed snapshot for memory
        snapshot = {
            "rsi": round(float(last["rsi"]), 2) if not np.isnan(last["rsi"]) else 50.0,
            "macd_hist": round(float(last["macd_hist"]), 6) if not np.isnan(last["macd_hist"]) else 0.0,
            "atr": round(float(last["atr"]), 5),
            "atr_pct": round(float(last["atr_pct"]), 3),
            "bb_width": round(float(last["bb_width"]), 2),
            "vwap_distance": self._vwap_distance(df, last),
            "regime": regime,
            "trend": trend_score,
            "patterns": patterns,
            "order_blocks": structure_data.get("order_blocks", {}),
            "fvgs": structure_data.get("fvgs", [])[:3],
        }

        result = {
            "signal": signal,
            "confidence": round(confidence, 3),
            "symbol": symbol,
            "regime": regime,
            "long_score": round(long_score, 3),
            "short_score": round(short_score, 3),
            "entry_price": round(float(last["close"]), 5),
            "atr": round(float(last["atr"]), 5),
            "atr_pct": round(float(last["atr_pct"]), 3),
            "pivot_points": self.ind.pivot_points(df),
            "support_resistance": self.ind.support_resistance(df),
            "snapshot": snapshot,
            "indicators": {
                "rsi": snapshot["rsi"],
                "macd_hist": snapshot["macd_hist"],
                "stoch_k": round(float(last.get("stoch_k", 50)), 2),
                "ema_fast": round(float(last["ema_fast"]), 5),
                "ema_slow": round(float(last["ema_slow"]), 5),
                "bb_upper": round(float(last["bb_upper"]), 5),
                "bb_lower": round(float(last["bb_lower"]), 5),
            },
        }
        self._last_signals[symbol] = result
        self._emit(f"📊 {symbol}: signal={signal} | confidence={confidence:.1%} | "
                   f"regime={regime} | long={long_score:.2f} | short={short_score:.2f}")
        return result

    def _analyze_trend(self, df: pd.DataFrame,
                        df_h1: Optional[pd.DataFrame] = None) -> Dict:
        last = df.iloc[-1]
        ema_fast = last["ema_fast"]
        ema_slow = last["ema_slow"]
        ema200 = last["ema_200"]
        close = last["close"]
        # EMA alignment
        long_ema = ema_fast > ema_slow and ema_slow > ema200 * 0.999
        short_ema = ema_fast < ema_slow and ema_slow < ema200 * 1.001
        # MACD
        macd_bull = last["macd_hist"] > 0 and last["macd_hist"] > df["macd_hist"].iloc[-2]
        macd_bear = last["macd_hist"] < 0 and last["macd_hist"] < df["macd_hist"].iloc[-2]
        # Higher timeframe confluence
        htf_bull = htf_bear = False
        if df_h1 is not None and len(df_h1) > 50:
            htf = Indicators.compute_all(df_h1)
            htf_last = htf.iloc[-1]
            htf_bull = htf_last["ema_fast"] > htf_last["ema_slow"]
            htf_bear = htf_last["ema_fast"] < htf_last["ema_slow"]
        long_score = (
            (0.4 if long_ema else 0) +
            (0.3 if macd_bull else 0) +
            (0.3 if htf_bull else 0)
        )
        short_score = (
            (0.4 if short_ema else 0) +
            (0.3 if macd_bear else 0) +
            (0.3 if htf_bear else 0)
        )
        return {"long": long_score, "short": short_score,
                "htf_bull": htf_bull, "htf_bear": htf_bear}

    def _analyze_momentum(self, df: pd.DataFrame) -> Dict:
        last = df.iloc[-1]
        prev = df.iloc[-2]
        rsi = last["rsi"] if not np.isnan(last["rsi"]) else 50
        stoch_k = last.get("stoch_k", 50)
        cci = last.get("cci", 0)
        mfi = last.get("mfi", 50)
        # RSI: oversold=bullish, overbought=bearish
        rsi_bull = 30 < rsi < 60 and rsi > prev["rsi"]
        rsi_bear = 40 < rsi < 70 and rsi < prev["rsi"]
        rsi_extreme_bull = rsi < 35
        rsi_extreme_bear = rsi > 65
        stoch_bull = stoch_k < 30 or (20 < stoch_k < 50)
        stoch_bear = stoch_k > 70 or (50 < stoch_k < 80)
        long_score = (
            (0.35 if rsi_bull else 0) +
            (0.2 if rsi_extreme_bull else 0) +
            (0.25 if stoch_bull else 0) +
            (0.2 if mfi < 40 else 0)
        )
        short_score = (
            (0.35 if rsi_bear else 0) +
            (0.2 if rsi_extreme_bear else 0) +
            (0.25 if stoch_bear else 0) +
            (0.2 if mfi > 60 else 0)
        )
        return {"long": long_score, "short": short_score,
                "rsi": rsi, "stoch_k": stoch_k, "mfi": mfi}

    def _analyze_volatility(self, df: pd.DataFrame,
                              last: pd.Series) -> Dict:
        atr_pct = last["atr_pct"]
        bb_width = last["bb_width"]
        avg_atr = df["atr_pct"].rolling(50).mean().iloc[-1]
        squeeze = self.ind.squeeze_momentum(df)
        is_expanding = atr_pct > avg_atr * 1.2
        is_contracting = atr_pct < avg_atr * 0.7
        return {
            "atr_pct": atr_pct,
            "is_expanding": bool(is_expanding),
            "is_contracting": bool(is_contracting),
            "squeeze_active": bool(squeeze["squeeze"].iloc[-1]),
            "quality": "good" if 0.05 < atr_pct < 0.5 else "poor",
        }

    def _analyze_volume(self, df: pd.DataFrame,
                         last: pd.Series) -> Dict:
        avg_vol = df["volume"].rolling(20).mean().iloc[-1]
        curr_vol = last["volume"]
        vol_ratio = curr_vol / avg_vol if avg_vol > 0 else 1.0
        obv = self.ind.obv(df)
        obv_trend = "up" if obv.iloc[-1] > obv.iloc[-5] else "down"
        vwap_dist = self._vwap_distance(df, last)
        return {
            "vol_ratio": round(vol_ratio, 2),
            "confirmation": min(vol_ratio / 2, 1.0),
            "obv_trend": obv_trend,
            "vwap_distance": vwap_dist,
        }

    def _analyze_market_structure(self, df: pd.DataFrame) -> Dict:
        obs = self.ind.order_blocks(df)
        fvgs = self.ind.fair_value_gaps(df)
        sr = self.ind.support_resistance(df)
        return {"order_blocks": obs, "fvgs": fvgs, "support_resistance": sr}

    def _pattern_score(self, patterns: Dict, direction: str) -> float:
        if direction == "long":
            bull_patterns = ["hammer", "bullish_engulfing"]
            return 1.0 if any(patterns.get(p, False) for p in bull_patterns) else 0.0
        else:
            bear_patterns = ["shooting_star", "bearish_engulfing"]
            return 1.0 if any(patterns.get(p, False) for p in bear_patterns) else 0.0

    def _vwap_distance(self, df: pd.DataFrame, last: pd.Series) -> float:
        try:
            vwap = self.ind.vwap(df)
            vwap_val = vwap.iloc[-1]
            if np.isnan(vwap_val):
                return 0.0
            return round((last["close"] - vwap_val) / vwap_val * 100, 4)
        except Exception:
            return 0.0

    async def _llm_analysis(self, symbol: str, last: pd.Series,
                              trend: Dict, momentum: Dict,
                              patterns: Dict, structure: Dict,
                              regime: str) -> Dict:
        context = {
            "symbol": symbol,
            "regime": regime,
            "rsi": round(float(last.get("rsi", 50)), 1),
            "macd_histogram": round(float(last.get("macd_hist", 0)), 6),
            "atr_pct": round(float(last.get("atr_pct", 0)), 3),
            "trend_alignment": trend,
            "momentum": {k: v for k, v in momentum.items() if k != "long" and k != "short"},
            "patterns": {k: v for k, v in patterns.items() if v},
            "order_blocks": structure.get("order_blocks", {}),
        }
        return await self.llm.analyze_market(context)
