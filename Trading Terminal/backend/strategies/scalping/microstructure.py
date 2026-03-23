"""
Strategy: Market Microstructure Scalping
Uses ICT concepts: Order Blocks, Fair Value Gaps, Liquidity Sweeps.
"""
import numpy as np
import pandas as pd
from typing import Dict, Optional
from ..base_strategy import BaseStrategy
from ...core.indicators import Indicators


class MicrostructureScalping(BaseStrategy):
    """
    ICT-based Microstructure Scalping:
    - Identifies liquidity sweeps (stop hunts)
    - Fades into order blocks
    - Targets fair value gaps as profit areas
    """

    DEFAULT_PARAMS = {
        "ob_lookback": 30,
        "fvg_min_size_pct": 0.05,
        "sweep_candles": 3,
        "atr_period": 14,
        "atr_sl_mult": 1.0,
        "atr_tp_mult": 2.0,
        "trend_ema": 50,
    }

    def __init__(self, config: Optional[Dict] = None):
        super().__init__("MicrostructureScalping", config)
        self.metadata["description"] = "ICT order blocks and FVG scalping"

    def signal(self, df: pd.DataFrame, open_positions: list,
               params: Optional[Dict] = None) -> Dict:
        p = {**self.DEFAULT_PARAMS, **(params or self.config)}
        if len(df) < 60:
            return {"signal": "hold"}

        atr = Indicators.atr(df, p["atr_period"])
        trend_ema = Indicators.ema(df["close"], p["trend_ema"])
        atr_val = float(atr.iloc[-1])
        close = float(df.iloc[-1]["close"])
        trend_dir = "bull" if close > float(trend_ema.iloc[-1]) else "bear"

        # Detect liquidity sweep (price swept recent high/low then reversed)
        sweep = self._detect_sweep(df, p["sweep_candles"])

        # Get order blocks
        obs = Indicators.order_blocks(df, p["ob_lookback"])

        # Get fair value gaps
        fvgs = Indicators.fair_value_gaps(df)

        buy_signal = (
            sweep == "bullish_sweep" and
            trend_dir == "bull" and
            self._near_bullish_ob(close, obs, atr_val)
        )
        sell_signal = (
            sweep == "bearish_sweep" and
            trend_dir == "bear" and
            self._near_bearish_ob(close, obs, atr_val)
        )

        if buy_signal:
            tp = self._find_fvg_target(close, fvgs, "buy")
            return {
                "signal": "buy",
                "sl": round(close - atr_val * p["atr_sl_mult"], 5),
                "tp": round(tp or close + atr_val * p["atr_tp_mult"], 5),
                "volume": 0.01,
            }
        elif sell_signal:
            tp = self._find_fvg_target(close, fvgs, "sell")
            return {
                "signal": "sell",
                "sl": round(close + atr_val * p["atr_sl_mult"], 5),
                "tp": round(tp or close - atr_val * p["atr_tp_mult"], 5),
                "volume": 0.01,
            }
        return {"signal": "hold"}

    def _detect_sweep(self, df: pd.DataFrame, lookback: int) -> str:
        """Detect bullish/bearish liquidity sweeps."""
        if len(df) < lookback + 3:
            return "none"
        recent = df.iloc[-(lookback + 3):-3]
        last3 = df.iloc[-3:]
        prev_high = float(recent["high"].max())
        prev_low = float(recent["low"].min())
        last_high = float(last3["high"].max())
        last_low = float(last3["low"].min())
        last_close = float(df.iloc[-1]["close"])
        # Bearish sweep: price swept above prev high then closed below
        if last_high > prev_high and last_close < prev_high * 0.9995:
            return "bearish_sweep"
        # Bullish sweep: price swept below prev low then closed above
        if last_low < prev_low and last_close > prev_low * 1.0005:
            return "bullish_sweep"
        return "none"

    def _near_bullish_ob(self, price: float, obs: Dict,
                          atr: float) -> bool:
        for ob in obs.get("bullish", []):
            if ob["low"] <= price <= ob["high"] + atr:
                return True
        return False

    def _near_bearish_ob(self, price: float, obs: Dict,
                          atr: float) -> bool:
        for ob in obs.get("bearish", []):
            if ob["low"] - atr <= price <= ob["high"]:
                return True
        return False

    def _find_fvg_target(self, price: float, fvgs: list,
                          direction: str) -> Optional[float]:
        for fvg in fvgs:
            if direction == "buy" and fvg["type"] == "bullish" and fvg["bottom"] > price:
                return fvg["bottom"]
            if direction == "sell" and fvg["type"] == "bearish" and fvg["top"] < price:
                return fvg["top"]
        return None
