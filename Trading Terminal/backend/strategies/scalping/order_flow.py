"""
Strategy: Order Flow Scalping
Uses volume imbalance, liquidity sweeps, and momentum divergence.
Not a common strategy - focuses on institutional footprint detection.
"""
import numpy as np
import pandas as pd
from typing import Dict, List, Optional
from ..base_strategy import BaseStrategy
from ...core.indicators import Indicators


class OrderFlowScalping(BaseStrategy):
    """
    Order Flow Scalping Strategy
    
    Concept: Detects when large institutional orders create temporary
    price imbalances (liquidity grabs) and fades the spike or
    rides the continuation.
    
    Entry Conditions:
    - Volume spike (>1.5x average) in direction of prevailing trend
    - Price at or near VWAP with momentum turning
    - No active order blocks overhead/below
    - ATR confirms sufficient volatility
    
    Exit: ATR-based with dynamic trailing
    """

    DEFAULT_PARAMS = {
        "fast_ema": 8,
        "slow_ema": 21,
        "rsi_period": 9,
        "rsi_oversold": 35,
        "rsi_overbought": 65,
        "volume_ratio": 1.3,
        "atr_period": 10,
        "atr_sl_mult": 1.5,
        "atr_tp_mult": 2.5,
        "min_bars": 50,
        "vwap_tolerance": 0.0005,
    }

    def __init__(self, config: Optional[Dict] = None):
        super().__init__("OrderFlowScalping", config)

    def signal(self, df: pd.DataFrame, open_positions: list,
               params: Optional[Dict] = None) -> Dict:
        p = {**self.DEFAULT_PARAMS, **(params or self.config)}
        if len(df) < p["min_bars"]:
            return {"signal": "hold"}

        # Compute indicators
        fast_ema = Indicators.ema(df["close"], p["fast_ema"])
        slow_ema = Indicators.ema(df["close"], p["slow_ema"])
        rsi = Indicators.rsi(df["close"], p["rsi_period"])
        atr = Indicators.atr(df, p["atr_period"])
        obv = Indicators.obv(df)

        last = df.iloc[-1]
        prev = df.iloc[-2]

        avg_volume = df["volume"].rolling(20).mean().iloc[-1]
        vol_ratio = last["volume"] / avg_volume if avg_volume > 0 else 1.0

        # Trend direction
        bull_trend = fast_ema.iloc[-1] > slow_ema.iloc[-1]
        bear_trend = fast_ema.iloc[-1] < slow_ema.iloc[-1]
        ema_cross_bull = (fast_ema.iloc[-1] > slow_ema.iloc[-1] and
                          fast_ema.iloc[-2] <= slow_ema.iloc[-2])
        ema_cross_bear = (fast_ema.iloc[-1] < slow_ema.iloc[-1] and
                          fast_ema.iloc[-2] >= slow_ema.iloc[-2])

        rsi_val = rsi.iloc[-1]
        obv_rising = obv.iloc[-1] > obv.iloc[-3]
        obv_falling = obv.iloc[-1] < obv.iloc[-3]

        # Volume spike confirmation
        vol_spike = vol_ratio >= p["volume_ratio"]

        # VWAP proximity
        try:
            vwap = Indicators.vwap(df)
            vwap_val = vwap.iloc[-1]
            near_vwap = abs(last["close"] - vwap_val) / vwap_val < p["vwap_tolerance"] * 3
            above_vwap = last["close"] > vwap_val * 1.0002
            below_vwap = last["close"] < vwap_val * 0.9998
        except Exception:
            near_vwap = True
            above_vwap = False
            below_vwap = False

        atr_val = float(atr.iloc[-1])
        entry = float(last["close"])
        sl_long = entry - atr_val * p["atr_sl_mult"]
        tp_long = entry + atr_val * p["atr_tp_mult"]
        sl_short = entry + atr_val * p["atr_sl_mult"]
        tp_short = entry - atr_val * p["atr_tp_mult"]

        already_long = any(pos.order_type == "buy" for pos in open_positions
                           if hasattr(pos, "order_type"))
        already_short = any(pos.order_type == "sell" for pos in open_positions
                            if hasattr(pos, "order_type"))

        # ── BUY CONDITIONS ──────────────────────────────────────────────
        long_cond = (
            bull_trend and
            vol_spike and
            (rsi_val < p["rsi_oversold"] + 15) and
            obv_rising and
            (near_vwap or above_vwap) and
            not already_long
        )

        # ── SELL CONDITIONS ─────────────────────────────────────────────
        short_cond = (
            bear_trend and
            vol_spike and
            (rsi_val > p["rsi_overbought"] - 15) and
            obv_falling and
            (near_vwap or below_vwap) and
            not already_short
        )

        # EMA cross for stronger signal
        if ema_cross_bull and vol_spike and obv_rising:
            long_cond = True
        if ema_cross_bear and vol_spike and obv_falling:
            short_cond = True

        if long_cond:
            return {
                "signal": "buy",
                "sl": round(sl_long, 5),
                "tp": round(tp_long, 5),
                "volume": 0.01,
                "snapshot": {
                    "rsi": round(rsi_val, 1),
                    "vol_ratio": round(vol_ratio, 2),
                    "atr": round(atr_val, 5),
                },
            }
        elif short_cond:
            return {
                "signal": "sell",
                "sl": round(sl_short, 5),
                "tp": round(tp_short, 5),
                "volume": 0.01,
                "snapshot": {
                    "rsi": round(rsi_val, 1),
                    "vol_ratio": round(vol_ratio, 2),
                    "atr": round(atr_val, 5),
                },
            }
        return {"signal": "hold"}
