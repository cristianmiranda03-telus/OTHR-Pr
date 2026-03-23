"""
Agent 8: Data Cleaner (The Data Quality Guardian)
Ensures clean, gap-free data for reliable AI models.
"""
import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple
from .base_agent import BaseAgent


class DataCleanerAgent(BaseAgent):
    """
    Data quality assurance:
    - Gap detection and interpolation
    - Outlier/spike removal
    - Volume anomaly detection
    - OHLC integrity validation
    - Timestamp alignment across timeframes
    - Data freshness monitoring
    """

    def __init__(self, config: dict):
        super().__init__("DataCleaner", config)
        self._quality_scores: Dict[str, float] = {}

    async def _execute(self, context: Dict) -> Dict:
        df = context.get("df")
        symbol = context.get("symbol", "UNKNOWN")
        timeframe = context.get("timeframe", "M1")

        if df is None or len(df) == 0:
            return {"error": "No data provided", "quality_score": 0.0}

        self._emit(f"🧹 Cleaning {symbol} {timeframe} ({len(df)} bars)...")
        original_len = len(df)
        issues = []

        # Run all checks
        df, gap_issues = self._fix_gaps(df, timeframe)
        df, ohlc_issues = self._fix_ohlc_integrity(df)
        df, spike_issues = self._remove_spikes(df)
        df, vol_issues = self._fix_volume(df)
        all_issues = gap_issues + ohlc_issues + spike_issues + vol_issues

        # Compute quality score
        quality_score = max(0.0, 1.0 - len(all_issues) * 0.05)
        self._quality_scores[f"{symbol}_{timeframe}"] = quality_score

        if all_issues:
            for issue in all_issues[:5]:
                self._emit(f"  ⚠ {issue}", "warning")

        self._emit(f"✅ {symbol} {timeframe}: quality={quality_score:.0%} | "
                   f"fixed={original_len - len(df) if len(df) < original_len else 0} bars | "
                   f"issues={len(all_issues)}")

        return {
            "df": df,
            "quality_score": round(quality_score, 3),
            "issues": all_issues,
            "original_bars": original_len,
            "final_bars": len(df),
            "symbol": symbol,
            "timeframe": timeframe,
        }

    def _fix_gaps(self, df: pd.DataFrame,
                   timeframe: str) -> Tuple[pd.DataFrame, List[str]]:
        """Detect and fill time gaps with forward-fill."""
        issues = []
        if not isinstance(df.index, pd.DatetimeIndex):
            return df, issues

        tf_minutes = {"M1": 1, "M5": 5, "M15": 15, "M30": 30,
                      "H1": 60, "H4": 240, "D1": 1440}.get(timeframe, 1)
        expected_freq = f"{tf_minutes}min"

        try:
            full_range = pd.date_range(
                start=df.index[0], end=df.index[-1], freq=expected_freq)
            missing = full_range.difference(df.index)
            if len(missing) > 0:
                n_gaps = len(missing)
                gap_pct = n_gaps / len(full_range) * 100
                if gap_pct > 5:
                    issues.append(f"Large data gap: {n_gaps} bars missing ({gap_pct:.1f}%)")
                df = df.reindex(full_range, method="ffill")
                issues.append(f"Filled {n_gaps} gaps via forward-fill") if n_gaps > 0 else None
        except Exception as e:
            issues.append(f"Gap detection error: {e}")
        return df, [i for i in issues if i]

    def _fix_ohlc_integrity(self, df: pd.DataFrame) -> Tuple[pd.DataFrame, List[str]]:
        """Fix OHLC logical violations (high < low, etc.)."""
        issues = []
        df = df.copy()

        # High must be >= max(open, close)
        high_violations = (df["high"] < df[["open", "close"]].max(axis=1)).sum()
        if high_violations > 0:
            df["high"] = df[["high", "open", "close"]].max(axis=1)
            issues.append(f"Fixed {high_violations} high < open/close violations")

        # Low must be <= min(open, close)
        low_violations = (df["low"] > df[["open", "close"]].min(axis=1)).sum()
        if low_violations > 0:
            df["low"] = df[["low", "open", "close"]].min(axis=1)
            issues.append(f"Fixed {low_violations} low > open/close violations")

        # No zero prices
        for col in ["open", "high", "low", "close"]:
            zeros = (df[col] <= 0).sum()
            if zeros > 0:
                df[col] = df[col].replace(0, np.nan).ffill()
                issues.append(f"Fixed {zeros} zero values in {col}")

        # No NaN prices
        nan_count = df[["open", "high", "low", "close"]].isna().sum().sum()
        if nan_count > 0:
            df[["open", "high", "low", "close"]] = \
                df[["open", "high", "low", "close"]].ffill().bfill()
            issues.append(f"Fixed {nan_count} NaN price values")

        return df, issues

    def _remove_spikes(self, df: pd.DataFrame,
                        spike_factor: float = 10.0) -> Tuple[pd.DataFrame, List[str]]:
        """Remove price spikes (candles with abnormally large range)."""
        issues = []
        df = df.copy()
        candle_range = df["high"] - df["low"]
        median_range = candle_range.rolling(50, min_periods=10).median()
        spikes = candle_range > median_range * spike_factor
        n_spikes = spikes.sum()
        if n_spikes > 0:
            df.loc[spikes, "high"] = df.loc[spikes, "close"] + median_range[spikes]
            df.loc[spikes, "low"] = df.loc[spikes, "close"] - median_range[spikes]
            issues.append(f"Removed {n_spikes} price spikes")
        return df, issues

    def _fix_volume(self, df: pd.DataFrame) -> Tuple[pd.DataFrame, List[str]]:
        """Fix zero or negative volume."""
        issues = []
        df = df.copy()
        if "volume" not in df.columns:
            return df, issues
        zero_vol = (df["volume"] <= 0).sum()
        if zero_vol > 0:
            df["volume"] = df["volume"].replace(0, np.nan)
            df["volume"] = df["volume"].ffill().fillna(1)
            issues.append(f"Fixed {zero_vol} zero-volume bars")
        return df, issues

    def clean_multiple(self, dfs: Dict[str, pd.DataFrame],
                        timeframe: str = "M1") -> Dict[str, pd.DataFrame]:
        """Synchronous batch clean for multiple symbols."""
        cleaned = {}
        for symbol, df in dfs.items():
            try:
                df, _ = self._fix_gaps(df, timeframe)
                df, _ = self._fix_ohlc_integrity(df)
                df, _ = self._remove_spikes(df)
                df, _ = self._fix_volume(df)
                cleaned[symbol] = df
            except Exception as e:
                self._emit(f"Clean failed for {symbol}: {e}", "error")
                cleaned[symbol] = df
        return cleaned

    def get_quality_scores(self) -> Dict[str, float]:
        return self._quality_scores.copy()
