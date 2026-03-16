"""
Quant-Joker Trader - Extended Strategy Library.
Includes: Basic, Advanced, Quant, and AI/ML-inspired strategies using Backtrader.
"""
from typing import Any

try:
    import backtrader as bt
    import backtrader.indicators as btind
    BACKTRADER_AVAILABLE = True
except ImportError:
    BACKTRADER_AVAILABLE = False
    bt = None


if BACKTRADER_AVAILABLE:

    # ── BASIC STRATEGIES ──────────────────────────────────────────────── #

    class RSIStrategy(bt.Strategy):
        """RSI oversold/overbought with optional MA filter."""
        params = (
            ("rsi_period", 14),
            ("rsi_low", 30),
            ("rsi_high", 70),
            ("ma_period", 50),
            ("use_ma_filter", True),
        )

        def __init__(self):
            self.rsi = bt.indicators.RSI(self.data.close, period=self.p.rsi_period)
            self.ma = bt.indicators.SMA(self.data.close, period=self.p.ma_period)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.rsi < self.p.rsi_low:
                    if not self.p.use_ma_filter or self.data.close[0] > self.ma[0]:
                        self.order = self.buy()
            else:
                if self.rsi > self.p.rsi_high:
                    self.order = self.close()


    class SMACrossStrategy(bt.Strategy):
        """SMA Golden/Death cross."""
        params = (("fast", 10), ("slow", 30))

        def __init__(self):
            self.fast_ma = bt.indicators.SMA(self.data.close, period=self.p.fast)
            self.slow_ma = bt.indicators.SMA(self.data.close, period=self.p.slow)
            self.crossover = bt.indicators.CrossOver(self.fast_ma, self.slow_ma)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.crossover > 0:
                    self.order = self.buy()
            else:
                if self.crossover < 0:
                    self.order = self.close()


    class EMACrossStrategy(bt.Strategy):
        """EMA cross - faster response than SMA."""
        params = (("fast", 9), ("slow", 21))

        def __init__(self):
            self.fast = bt.indicators.EMA(self.data.close, period=self.p.fast)
            self.slow = bt.indicators.EMA(self.data.close, period=self.p.slow)
            self.cross = bt.indicators.CrossOver(self.fast, self.slow)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.cross > 0:
                    self.order = self.buy()
            else:
                if self.cross < 0:
                    self.order = self.close()


    class MACDSignalStrategy(bt.Strategy):
        """MACD line crossing signal line."""
        params = (("fast", 12), ("slow", 26), ("signal", 9))

        def __init__(self):
            self.macd = bt.indicators.MACD(
                self.data.close,
                period1=self.p.fast,
                period2=self.p.slow,
                period_signal=self.p.signal,
            )
            self.cross = bt.indicators.CrossOver(self.macd.macd, self.macd.signal)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.cross > 0 and self.macd.macd[0] < 0:
                    self.order = self.buy()
            else:
                if self.cross < 0:
                    self.order = self.close()


    class BollingerBreakoutStrategy(bt.Strategy):
        """Trade breakouts outside Bollinger Bands."""
        params = (("period", 20), ("devfactor", 2.0), ("atr_period", 14))

        def __init__(self):
            self.bb = bt.indicators.BollingerBands(
                self.data.close,
                period=self.p.period,
                devfactor=self.p.devfactor,
            )
            self.atr = bt.indicators.ATR(self.data, period=self.p.atr_period)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.data.close[0] > self.bb.top[0]:
                    self.order = self.buy()
                elif self.data.close[0] < self.bb.bot[0]:
                    self.order = self.sell()
            else:
                if self.data.close[0] > self.bb.mid[0] and self.position.size > 0:
                    self.order = self.close()
                elif self.data.close[0] < self.bb.mid[0] and self.position.size < 0:
                    self.order = self.close()


    class StochasticCrossStrategy(bt.Strategy):
        """Stochastic oscillator crossover in oversold/overbought zones."""
        params = (("k_period", 14), ("d_period", 3), ("over_bought", 80), ("over_sold", 20))

        def __init__(self):
            self.stoch = bt.indicators.Stochastic(
                self.data,
                period=self.p.k_period,
                period_dfast=self.p.d_period,
            )
            self.cross = bt.indicators.CrossOver(self.stoch.percK, self.stoch.percD)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.cross > 0 and self.stoch.percK[0] < self.p.over_sold:
                    self.order = self.buy()
            else:
                if self.cross < 0 and self.stoch.percK[0] > self.p.over_bought:
                    self.order = self.close()


    # ── ADVANCED STRATEGIES ───────────────────────────────────────────── #

    class RSIMACDConfluenceStrategy(bt.Strategy):
        """RSI + MACD confluence: both must agree for entry."""
        params = (
            ("rsi_period", 14),
            ("rsi_low", 35),
            ("rsi_high", 65),
            ("macd_fast", 12),
            ("macd_slow", 26),
            ("macd_signal", 9),
            ("ema_period", 50),
        )

        def __init__(self):
            self.rsi = bt.indicators.RSI(self.data.close, period=self.p.rsi_period)
            self.macd = bt.indicators.MACD(
                self.data.close,
                period1=self.p.macd_fast,
                period2=self.p.macd_slow,
                period_signal=self.p.macd_signal,
            )
            self.macd_cross = bt.indicators.CrossOver(self.macd.macd, self.macd.signal)
            self.ema = bt.indicators.EMA(self.data.close, period=self.p.ema_period)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            above_ema = self.data.close[0] > self.ema[0]
            if not self.position:
                if self.rsi[0] < self.p.rsi_low and self.macd_cross[0] > 0 and above_ema:
                    self.order = self.buy()
            else:
                if self.rsi[0] > self.p.rsi_high or self.macd_cross[0] < 0:
                    self.order = self.close()


    class ATRBreakoutStrategy(bt.Strategy):
        """ATR-based volatility breakout."""
        params = (("atr_period", 14), ("multiplier", 2.0), ("ma_period", 20))

        def __init__(self):
            self.atr = bt.indicators.ATR(self.data, period=self.p.atr_period)
            self.ma = bt.indicators.SMA(self.data.close, period=self.p.ma_period)
            self.order = None
            self.channel_high = None
            self.channel_low = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            upper = self.ma[0] + self.p.multiplier * self.atr[0]
            lower = self.ma[0] - self.p.multiplier * self.atr[0]
            if not self.position:
                if self.data.close[0] > upper:
                    self.order = self.buy()
                elif self.data.close[0] < lower:
                    self.order = self.sell()
            else:
                if self.position.size > 0 and self.data.close[0] < self.ma[0]:
                    self.order = self.close()
                elif self.position.size < 0 and self.data.close[0] > self.ma[0]:
                    self.order = self.close()


    class MeanReversionStrategy(bt.Strategy):
        """Z-score mean reversion on Bollinger Bands."""
        params = (("period", 20), ("z_entry", 2.0), ("z_exit", 0.5))

        def __init__(self):
            self.bb = bt.indicators.BollingerBands(self.data.close, period=self.p.period, devfactor=self.p.z_entry)
            self.bb_exit = bt.indicators.BollingerBands(self.data.close, period=self.p.period, devfactor=self.p.z_exit)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.data.close[0] < self.bb.bot[0]:
                    self.order = self.buy()
                elif self.data.close[0] > self.bb.top[0]:
                    self.order = self.sell()
            else:
                if self.position.size > 0 and self.data.close[0] >= self.bb_exit.mid[0]:
                    self.order = self.close()
                elif self.position.size < 0 and self.data.close[0] <= self.bb_exit.mid[0]:
                    self.order = self.close()


    # ── QUANT STRATEGIES ──────────────────────────────────────────────── #

    class MomentumFactorStrategy(bt.Strategy):
        """Price momentum: trade direction of strongest trend."""
        params = (("lookback", 20), ("ma_fast", 5), ("ma_slow", 20))

        def __init__(self):
            self.fast = bt.indicators.EMA(self.data.close, period=self.p.ma_fast)
            self.slow = bt.indicators.EMA(self.data.close, period=self.p.ma_slow)
            self.cross = bt.indicators.CrossOver(self.fast, self.slow)
            self.roc = bt.indicators.RateOfChange(self.data.close, period=self.p.lookback)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            if not self.position:
                if self.cross > 0 and self.roc[0] > 0:
                    self.order = self.buy()
                elif self.cross < 0 and self.roc[0] < 0:
                    self.order = self.sell()
            else:
                if self.position.size > 0 and self.cross < 0:
                    self.order = self.close()
                elif self.position.size < 0 and self.cross > 0:
                    self.order = self.close()


    class VolatilityRegimeStrategy(bt.Strategy):
        """Switches trend-following/mean-reversion based on ADX (regime detection)."""
        params = (
            ("adx_period", 14),
            ("adx_threshold", 25),
            ("rsi_period", 14),
            ("ema_fast", 10),
            ("ema_slow", 30),
        )

        def __init__(self):
            self.adx = bt.indicators.AverageDirectionalMovementIndex(self.data, period=self.p.adx_period)
            self.rsi = bt.indicators.RSI(self.data.close, period=self.p.rsi_period)
            self.fast = bt.indicators.EMA(self.data.close, period=self.p.ema_fast)
            self.slow = bt.indicators.EMA(self.data.close, period=self.p.ema_slow)
            self.cross = bt.indicators.CrossOver(self.fast, self.slow)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            trending = self.adx[0] > self.p.adx_threshold
            if not self.position:
                if trending:
                    if self.cross > 0:
                        self.order = self.buy()
                    elif self.cross < 0:
                        self.order = self.sell()
                else:
                    if self.rsi[0] < 30:
                        self.order = self.buy()
                    elif self.rsi[0] > 70:
                        self.order = self.sell()
            else:
                if self.position.size > 0 and (self.cross < 0 or self.rsi[0] > 70):
                    self.order = self.close()
                elif self.position.size < 0 and (self.cross > 0 or self.rsi[0] < 30):
                    self.order = self.close()


    # ── AI/ML-INSPIRED STRATEGIES ────────────────────────────────────── #

    class MLRandomForestStrategy(bt.Strategy):
        """
        Simulates ML random forest by combining 5+ indicator signals as votes.
        Each indicator 'votes' for buy or sell; majority wins above confidence threshold.
        """
        params = (
            ("min_votes", 4),
            ("rsi_period", 14),
            ("macd_fast", 12),
            ("macd_slow", 26),
            ("macd_signal", 9),
            ("bb_period", 20),
            ("ema_fast", 9),
            ("ema_slow", 21),
            ("stoch_k", 14),
        )

        def __init__(self):
            self.rsi = bt.indicators.RSI(self.data.close, period=self.p.rsi_period)
            self.macd = bt.indicators.MACD(self.data.close, period1=self.p.macd_fast, period2=self.p.macd_slow, period_signal=self.p.macd_signal)
            self.macd_cross = bt.indicators.CrossOver(self.macd.macd, self.macd.signal)
            self.bb = bt.indicators.BollingerBands(self.data.close, period=self.p.bb_period)
            self.ema_f = bt.indicators.EMA(self.data.close, period=self.p.ema_fast)
            self.ema_s = bt.indicators.EMA(self.data.close, period=self.p.ema_slow)
            self.ema_cross = bt.indicators.CrossOver(self.ema_f, self.ema_s)
            self.stoch = bt.indicators.Stochastic(self.data, period=self.p.stoch_k)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def _count_votes(self) -> tuple[int, int]:
            buy_votes = sell_votes = 0
            # RSI
            if self.rsi[0] < 40: buy_votes += 1
            elif self.rsi[0] > 60: sell_votes += 1
            # MACD
            if self.macd_cross[0] > 0: buy_votes += 1
            elif self.macd_cross[0] < 0: sell_votes += 1
            # Bollinger
            if self.data.close[0] < self.bb.bot[0]: buy_votes += 1
            elif self.data.close[0] > self.bb.top[0]: sell_votes += 1
            # EMA cross
            if self.ema_cross[0] > 0: buy_votes += 1
            elif self.ema_cross[0] < 0: sell_votes += 1
            # Stoch
            if self.stoch.percK[0] < 25: buy_votes += 1
            elif self.stoch.percK[0] > 75: sell_votes += 1
            return buy_votes, sell_votes

        def next(self):
            if self.order:
                return
            buy_v, sell_v = self._count_votes()
            if not self.position:
                if buy_v >= self.p.min_votes:
                    self.order = self.buy()
                elif sell_v >= self.p.min_votes:
                    self.order = self.sell()
            else:
                if self.position.size > 0 and sell_v >= 3:
                    self.order = self.close()
                elif self.position.size < 0 and buy_v >= 3:
                    self.order = self.close()


    class TripleEMAStrategy(bt.Strategy):
        """Triple EMA filter: price must be above/below all 3 EMAs."""
        params = (("ema1", 8), ("ema2", 21), ("ema3", 55))

        def __init__(self):
            self.e1 = bt.indicators.EMA(self.data.close, period=self.p.ema1)
            self.e2 = bt.indicators.EMA(self.data.close, period=self.p.ema2)
            self.e3 = bt.indicators.EMA(self.data.close, period=self.p.ema3)
            self.cross = bt.indicators.CrossOver(self.e1, self.e2)
            self.order = None

        def notify_order(self, order):
            if order.status in (order.Completed, order.Canceled):
                self.order = None

        def next(self):
            if self.order:
                return
            price = self.data.close[0]
            bull_aligned = price > self.e1[0] > self.e2[0] > self.e3[0]
            bear_aligned = price < self.e1[0] < self.e2[0] < self.e3[0]
            if not self.position:
                if bull_aligned and self.cross > 0:
                    self.order = self.buy()
                elif bear_aligned and self.cross < 0:
                    self.order = self.sell()
            else:
                if self.position.size > 0 and not bull_aligned:
                    self.order = self.close()
                elif self.position.size < 0 and not bear_aligned:
                    self.order = self.close()


_STRATEGY_MAP = {
    "rsi": RSIStrategy,
    "sma_cross": SMACrossStrategy,
    "ema_cross": EMACrossStrategy,
    "macd_signal": MACDSignalStrategy,
    "bb_breakout": BollingerBreakoutStrategy,
    "stoch_cross": StochasticCrossStrategy,
    "rsi_macd_confluence": RSIMACDConfluenceStrategy,
    "atr_breakout": ATRBreakoutStrategy,
    "mean_reversion": MeanReversionStrategy,
    "momentum_factor": MomentumFactorStrategy,
    "volatility_regime": VolatilityRegimeStrategy,
    "ml_random_forest": MLRandomForestStrategy,
    "triple_ema": TripleEMAStrategy,
}


def get_strategy_class(name: str) -> type | None:
    """Return strategy class by name for backtesting."""
    if not BACKTRADER_AVAILABLE:
        return None
    return _STRATEGY_MAP.get(name)


def list_strategies() -> list[str]:
    """List all available strategy keys."""
    return list(_STRATEGY_MAP.keys()) if BACKTRADER_AVAILABLE else []
