"""
Strategy: VWAP Mean Reversion Scalping
Fades extreme deviations from VWAP with volume confirmation.
"""
import numpy as np
import pandas as pd
from typing import Dict, Optional
from ..base_strategy import BaseStrategy
from ...core.indicators import Indicators


class VWAPMeanReversionScalp(BaseStrategy):
    """
    VWAP Mean Reversion - fades price when it deviates too far from VWAP
    and volume confirms institutional absorption.
    """

    DEFAULT_PARAMS = {
        "vwap_std_bands": 2.0,
        "rsi_period": 14,
        "rsi_mid": 50,
        "min_deviation_pct": 0.15,
        "max_deviation_pct": 0.5,
        "atr_sl_mult": 1.2,
        "atr_tp_mult": 2.0,
        "min_volume_ratio": 0.8,
    }

    def __init__(self, config: Optional[Dict] = None):
        super().__init__("VWAPMeanReversionScalp", config)
        self.metadata["description"] = "Fades extreme VWAP deviations"

    def signal(self, df: pd.DataFrame, open_positions: list,
               params: Optional[Dict] = None) -> Dict:
        p = {**self.DEFAULT_PARAMS, **(params or self.config)}
        if len(df) < 50:
            return {"signal": "hold"}

        try:
            vwap = Indicators.vwap(df)
        except Exception:
            return {"signal": "hold"}

        atr = Indicators.atr(df, 14)
        rsi = Indicators.rsi(df["close"], p["rsi_period"])
        bb_upper, bb_mid, bb_lower = Indicators.bollinger_bands(df["close"], 20)

        last = df.iloc[-1]
        vwap_val = float(vwap.iloc[-1])
        atr_val = float(atr.iloc[-1])
        rsi_val = float(rsi.iloc[-1])
        close = float(last["close"])

        if vwap_val <= 0:
            return {"signal": "hold"}

        deviation_pct = (close - vwap_val) / vwap_val * 100
        avg_volume = float(df["volume"].rolling(20).mean().iloc[-1])
        vol_ok = last["volume"] >= avg_volume * p["min_volume_ratio"]

        # Below VWAP + oversold → long (mean reversion up)
        buy_signal = (
            deviation_pct < -p["min_deviation_pct"] and
            abs(deviation_pct) < p["max_deviation_pct"] and
            rsi_val < 45 and vol_ok and
            close <= float(bb_lower.iloc[-1]) * 1.001
        )

        # Above VWAP + overbought → short (mean reversion down)
        sell_signal = (
            deviation_pct > p["min_deviation_pct"] and
            abs(deviation_pct) < p["max_deviation_pct"] and
            rsi_val > 55 and vol_ok and
            close >= float(bb_upper.iloc[-1]) * 0.999
        )

        if buy_signal:
            return {
                "signal": "buy",
                "sl": round(close - atr_val * p["atr_sl_mult"], 5),
                "tp": round(vwap_val + atr_val * 0.5, 5),
                "volume": 0.01,
            }
        elif sell_signal:
            return {
                "signal": "sell",
                "sl": round(close + atr_val * p["atr_sl_mult"], 5),
                "tp": round(vwap_val - atr_val * 0.5, 5),
                "volume": 0.01,
            }
        return {"signal": "hold"}
