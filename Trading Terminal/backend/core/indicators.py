"""
Technical Indicators Engine
Comprehensive indicator library for scalping and strategy development.
"""
import numpy as np
import pandas as pd
from typing import Optional, Tuple, Dict
from loguru import logger

try:
    import pandas_ta as ta
    PANDAS_TA = True
except ImportError:
    PANDAS_TA = False


class Indicators:
    """
    Full indicator suite: trend, momentum, volatility, volume, market structure,
    and advanced micro-structure indicators optimized for scalping.
    """

    # ─────────────────────── TREND ────────────────────────

    @staticmethod
    def ema(series: pd.Series, period: int) -> pd.Series:
        return series.ewm(span=period, adjust=False).mean()

    @staticmethod
    def sma(series: pd.Series, period: int) -> pd.Series:
        return series.rolling(window=period).mean()

    @staticmethod
    def wma(series: pd.Series, period: int) -> pd.Series:
        weights = np.arange(1, period + 1)
        return series.rolling(period).apply(
            lambda x: np.dot(x, weights) / weights.sum(), raw=True)

    @staticmethod
    def hma(series: pd.Series, period: int) -> pd.Series:
        half = int(period / 2)
        sqrt_p = int(np.sqrt(period))
        wma_half = Indicators.wma(series, half)
        wma_full = Indicators.wma(series, period)
        diff = 2 * wma_half - wma_full
        return Indicators.wma(diff, sqrt_p)

    @staticmethod
    def zlema(series: pd.Series, period: int) -> pd.Series:
        lag = int((period - 1) / 2)
        adjusted = series + (series - series.shift(lag))
        return adjusted.ewm(span=period, adjust=False).mean()

    @staticmethod
    def macd(series: pd.Series, fast: int = 12, slow: int = 26,
             signal: int = 9) -> Tuple[pd.Series, pd.Series, pd.Series]:
        ema_fast = Indicators.ema(series, fast)
        ema_slow = Indicators.ema(series, slow)
        macd_line = ema_fast - ema_slow
        signal_line = Indicators.ema(macd_line, signal)
        histogram = macd_line - signal_line
        return macd_line, signal_line, histogram

    @staticmethod
    def supertrend(df: pd.DataFrame, period: int = 10,
                   multiplier: float = 3.0) -> Tuple[pd.Series, pd.Series]:
        atr = Indicators.atr(df, period)
        hl2 = (df["high"] + df["low"]) / 2
        upper_band = hl2 + multiplier * atr
        lower_band = hl2 - multiplier * atr
        supertrend = pd.Series(index=df.index, dtype=float)
        direction = pd.Series(index=df.index, dtype=int)

        for i in range(1, len(df)):
            if df["close"].iloc[i] > upper_band.iloc[i - 1]:
                supertrend.iloc[i] = lower_band.iloc[i]
                direction.iloc[i] = 1
            elif df["close"].iloc[i] < lower_band.iloc[i - 1]:
                supertrend.iloc[i] = upper_band.iloc[i]
                direction.iloc[i] = -1
            else:
                direction.iloc[i] = direction.iloc[i - 1]
                if direction.iloc[i] == 1:
                    supertrend.iloc[i] = max(lower_band.iloc[i],
                                              supertrend.iloc[i - 1])
                else:
                    supertrend.iloc[i] = min(upper_band.iloc[i],
                                              supertrend.iloc[i - 1])
        return supertrend, direction

    # ─────────────────────── MOMENTUM ─────────────────────

    @staticmethod
    def rsi(series: pd.Series, period: int = 14) -> pd.Series:
        delta = series.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = -delta.where(delta < 0, 0.0)
        avg_gain = gain.ewm(com=period - 1, min_periods=period).mean()
        avg_loss = loss.ewm(com=period - 1, min_periods=period).mean()
        rs = avg_gain / avg_loss.replace(0, np.finfo(float).eps)
        return 100 - (100 / (1 + rs))

    @staticmethod
    def stochastic(df: pd.DataFrame, k_period: int = 14,
                   d_period: int = 3) -> Tuple[pd.Series, pd.Series]:
        low_min = df["low"].rolling(k_period).min()
        high_max = df["high"].rolling(k_period).max()
        k = 100 * (df["close"] - low_min) / (high_max - low_min).replace(0, np.finfo(float).eps)
        d = k.rolling(d_period).mean()
        return k, d

    @staticmethod
    def cci(df: pd.DataFrame, period: int = 20) -> pd.Series:
        tp = (df["high"] + df["low"] + df["close"]) / 3
        sma_tp = tp.rolling(period).mean()
        mad = tp.rolling(period).apply(lambda x: np.mean(np.abs(x - x.mean())), raw=True)
        return (tp - sma_tp) / (0.015 * mad.replace(0, np.finfo(float).eps))

    @staticmethod
    def williams_r(df: pd.DataFrame, period: int = 14) -> pd.Series:
        high_max = df["high"].rolling(period).max()
        low_min = df["low"].rolling(period).min()
        return -100 * (high_max - df["close"]) / (high_max - low_min).replace(0, np.finfo(float).eps)

    @staticmethod
    def momentum(series: pd.Series, period: int = 10) -> pd.Series:
        return series - series.shift(period)

    # ─────────────────────── VOLATILITY ───────────────────

    @staticmethod
    def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
        high = df["high"]
        low = df["low"]
        close_prev = df["close"].shift(1)
        tr = pd.concat([
            high - low,
            (high - close_prev).abs(),
            (low - close_prev).abs()
        ], axis=1).max(axis=1)
        return tr.ewm(com=period - 1, min_periods=period).mean()

    @staticmethod
    def bollinger_bands(series: pd.Series, period: int = 20,
                        std_dev: float = 2.0) -> Tuple[pd.Series, pd.Series, pd.Series]:
        middle = series.rolling(period).mean()
        std = series.rolling(period).std()
        upper = middle + std_dev * std
        lower = middle - std_dev * std
        return upper, middle, lower

    @staticmethod
    def keltner_channel(df: pd.DataFrame, ema_period: int = 20,
                        atr_period: int = 10,
                        multiplier: float = 1.5) -> Tuple[pd.Series, pd.Series, pd.Series]:
        middle = Indicators.ema(df["close"], ema_period)
        atr = Indicators.atr(df, atr_period)
        upper = middle + multiplier * atr
        lower = middle - multiplier * atr
        return upper, middle, lower

    @staticmethod
    def squeeze_momentum(df: pd.DataFrame, bb_period: int = 20, kc_period: int = 20,
                         kc_mult: float = 1.5) -> Dict[str, pd.Series]:
        bb_upper, bb_mid, bb_lower = Indicators.bollinger_bands(df["close"], bb_period)
        kc_upper, kc_mid, kc_lower = Indicators.keltner_channel(df, kc_period, kc_period, kc_mult)
        squeeze = (bb_lower > kc_lower) & (bb_upper < kc_upper)
        mom = Indicators.momentum(df["close"], 12)
        return {"squeeze": squeeze, "momentum": mom,
                "bb_width": bb_upper - bb_lower, "kc_width": kc_upper - kc_lower}

    # ─────────────────────── VOLUME ───────────────────────

    @staticmethod
    def vwap(df: pd.DataFrame) -> pd.Series:
        """Intraday VWAP - resets each day."""
        tp = (df["high"] + df["low"] + df["close"]) / 3
        cumvol = df["volume"].groupby(df.index.date).cumsum()
        cumtp = (tp * df["volume"]).groupby(df.index.date).cumsum()
        return cumtp / cumvol.replace(0, np.finfo(float).eps)

    @staticmethod
    def obv(df: pd.DataFrame) -> pd.Series:
        direction = np.sign(df["close"].diff())
        return (direction * df["volume"]).cumsum()

    @staticmethod
    def volume_profile(df: pd.DataFrame, bins: int = 50) -> pd.DataFrame:
        """Calculate volume profile (POC, VAH, VAL)."""
        price_range = np.linspace(df["low"].min(), df["high"].max(), bins)
        vol_at_price = np.zeros(bins - 1)
        for i in range(len(df)):
            row = df.iloc[i]
            mask = (price_range[:-1] >= row["low"]) & (price_range[1:] <= row["high"])
            vol_at_price[mask] += row["volume"] / max(mask.sum(), 1)
        mid_prices = (price_range[:-1] + price_range[1:]) / 2
        return pd.DataFrame({"price": mid_prices, "volume": vol_at_price})

    @staticmethod
    def money_flow_index(df: pd.DataFrame, period: int = 14) -> pd.Series:
        tp = (df["high"] + df["low"] + df["close"]) / 3
        mf = tp * df["volume"]
        pos_mf = mf.where(tp > tp.shift(1), 0.0)
        neg_mf = mf.where(tp < tp.shift(1), 0.0)
        pos_sum = pos_mf.rolling(period).sum()
        neg_sum = neg_mf.rolling(period).sum()
        mfr = pos_sum / neg_sum.replace(0, np.finfo(float).eps)
        return 100 - (100 / (1 + mfr))

    # ─────────────────────── MARKET STRUCTURE ─────────────

    @staticmethod
    def pivot_points(df: pd.DataFrame) -> Dict[str, float]:
        """Classic pivot points for scalping S/R."""
        high = df["high"].iloc[-2]
        low = df["low"].iloc[-2]
        close = df["close"].iloc[-2]
        pivot = (high + low + close) / 3
        return {
            "pivot": pivot,
            "r1": 2 * pivot - low,
            "r2": pivot + (high - low),
            "r3": high + 2 * (pivot - low),
            "s1": 2 * pivot - high,
            "s2": pivot - (high - low),
            "s3": low - 2 * (high - pivot),
        }

    @staticmethod
    def support_resistance(df: pd.DataFrame, window: int = 20,
                           n_levels: int = 5) -> Dict[str, list]:
        """Dynamic S/R levels via local extrema."""
        highs = df["high"].rolling(window, center=True).max()
        lows = df["low"].rolling(window, center=True).min()
        resistance = df["high"][df["high"] == highs].dropna().unique()
        support = df["low"][df["low"] == lows].dropna().unique()
        return {
            "resistance": sorted(resistance, reverse=True)[:n_levels],
            "support": sorted(support)[:n_levels],
        }

    @staticmethod
    def order_blocks(df: pd.DataFrame, lookback: int = 50) -> Dict[str, list]:
        """Detect institutional order blocks (ICT concept)."""
        bullish_obs = []
        bearish_obs = []
        for i in range(2, min(lookback, len(df) - 1)):
            idx = -(i + 1)
            candle = df.iloc[idx]
            next_candle = df.iloc[idx + 1]
            # Bearish OB: last up candle before strong down move
            if (candle["close"] > candle["open"] and
                    next_candle["close"] < candle["low"]):
                bearish_obs.append({
                    "high": candle["high"], "low": candle["low"],
                    "time": df.index[idx].isoformat(),
                })
            # Bullish OB: last down candle before strong up move
            if (candle["close"] < candle["open"] and
                    next_candle["close"] > candle["high"]):
                bullish_obs.append({
                    "high": candle["high"], "low": candle["low"],
                    "time": df.index[idx].isoformat(),
                })
        return {"bullish": bullish_obs[:3], "bearish": bearish_obs[:3]}

    @staticmethod
    def fair_value_gaps(df: pd.DataFrame) -> list:
        """ICT Fair Value Gaps (FVG) detection."""
        fvgs = []
        for i in range(1, len(df) - 1):
            prev = df.iloc[i - 1]
            curr = df.iloc[i]
            nxt = df.iloc[i + 1]
            # Bullish FVG: gap between prev high and next low
            if nxt["low"] > prev["high"]:
                fvgs.append({
                    "type": "bullish", "top": nxt["low"], "bottom": prev["high"],
                    "time": df.index[i].isoformat(),
                })
            # Bearish FVG
            if nxt["high"] < prev["low"]:
                fvgs.append({
                    "type": "bearish", "top": prev["low"], "bottom": nxt["high"],
                    "time": df.index[i].isoformat(),
                })
        return fvgs[-10:]

    # ─────────────────────── ADVANCED / COMPOSITE ─────────

    @staticmethod
    def market_regime(df: pd.DataFrame) -> str:
        """Classify market as trending/ranging/volatile."""
        atr_val = Indicators.atr(df, 14).iloc[-1]
        atr_pct = atr_val / df["close"].iloc[-1] * 100
        ema20 = Indicators.ema(df["close"], 20)
        ema50 = Indicators.ema(df["close"], 50)
        spread = abs(ema20.iloc[-1] - ema50.iloc[-1]) / df["close"].iloc[-1] * 100
        if spread > 0.3 and atr_pct < 0.5:
            return "trending"
        elif atr_pct > 1.0:
            return "volatile"
        else:
            return "ranging"

    @staticmethod
    def candle_pattern(df: pd.DataFrame) -> Dict[str, bool]:
        """Basic candlestick pattern detection."""
        c = df.iloc[-1]
        p = df.iloc[-2] if len(df) > 1 else c
        body = abs(c["close"] - c["open"])
        total_range = c["high"] - c["low"] if c["high"] != c["low"] else 0.0001
        upper_wick = c["high"] - max(c["open"], c["close"])
        lower_wick = min(c["open"], c["close"]) - c["low"]
        doji = body / total_range < 0.1
        hammer = lower_wick > 2 * body and upper_wick < body
        shooting_star = upper_wick > 2 * body and lower_wick < body
        bull_engulf = (c["close"] > c["open"] and p["close"] < p["open"] and
                       c["open"] < p["close"] and c["close"] > p["open"])
        bear_engulf = (c["close"] < c["open"] and p["close"] > p["open"] and
                       c["open"] > p["close"] and c["close"] < p["open"])
        return {
            "doji": doji, "hammer": hammer, "shooting_star": shooting_star,
            "bullish_engulfing": bull_engulf, "bearish_engulfing": bear_engulf,
        }

    @staticmethod
    def compute_all(df: pd.DataFrame, fast: int = 8, slow: int = 21) -> pd.DataFrame:
        """Compute comprehensive indicator set and attach to DataFrame."""
        df = df.copy()
        df["ema_fast"] = Indicators.ema(df["close"], fast)
        df["ema_slow"] = Indicators.ema(df["close"], slow)
        df["ema_200"] = Indicators.ema(df["close"], 200)
        df["rsi"] = Indicators.rsi(df["close"], 14)
        df["atr"] = Indicators.atr(df, 14)
        df["atr_pct"] = df["atr"] / df["close"] * 100
        macd_l, macd_s, macd_h = Indicators.macd(df["close"])
        df["macd"] = macd_l
        df["macd_signal"] = macd_s
        df["macd_hist"] = macd_h
        bb_u, bb_m, bb_l = Indicators.bollinger_bands(df["close"])
        df["bb_upper"] = bb_u
        df["bb_middle"] = bb_m
        df["bb_lower"] = bb_l
        df["bb_width"] = (bb_u - bb_l) / bb_m * 100
        stoch_k, stoch_d = Indicators.stochastic(df)
        df["stoch_k"] = stoch_k
        df["stoch_d"] = stoch_d
        df["cci"] = Indicators.cci(df)
        df["mfi"] = Indicators.money_flow_index(df)
        df["obv"] = Indicators.obv(df)
        try:
            df["vwap"] = Indicators.vwap(df)
        except Exception:
            df["vwap"] = np.nan
        return df
