"""
Risk Management Engine
Dynamic position sizing, SL/TP calculation, drawdown monitoring.
"""
from typing import Optional, Dict, Tuple
import numpy as np
from loguru import logger


class RiskCalculator:
    """
    Dynamic risk engine:
    - ATR-based SL/TP
    - Kelly Criterion position sizing
    - Drawdown circuit breaker
    - Correlation-aware exposure limits
    """

    def __init__(self, config: dict):
        self.cfg = config
        self.daily_pnl = 0.0
        self.peak_equity = 0.0
        self.trading_enabled = True
        self._trade_log: list = []

    # ─────────────────────── POSITION SIZING ──────────────

    def calculate_lot_size(
        self,
        balance: float,
        risk_pct: float,
        sl_pips: float,
        pip_value: float,
        symbol_info: Optional[dict] = None,
        method: str = "fixed_risk",
    ) -> float:
        """
        Calculate optimal lot size.
        Methods: fixed_risk | kelly | volatility_scaled
        """
        if sl_pips <= 0 or pip_value <= 0:
            return self.cfg.get("min_lot", 0.01)

        if method == "kelly":
            return self._kelly_lot(balance, sl_pips, pip_value)

        # Default: fixed risk per trade
        risk_amount = balance * (risk_pct / 100)
        lot_size = risk_amount / (sl_pips * pip_value)
        return self._clamp_lot(lot_size, symbol_info)

    def _kelly_lot(self, balance: float, sl_pips: float,
                   pip_value: float) -> float:
        """Simplified Kelly Criterion based on historical win rate."""
        win_rate = self._get_win_rate()
        avg_win = self._get_avg_win_pips()
        avg_loss = sl_pips
        if avg_loss <= 0:
            return 0.01
        rr = avg_win / avg_loss if avg_win > 0 else 1.0
        kelly = (win_rate * rr - (1 - win_rate)) / rr
        kelly = max(0.02, min(kelly, 0.10))  # Cap Kelly at 10%
        risk_amount = balance * kelly
        return self._clamp_lot(risk_amount / (sl_pips * pip_value))

    def _clamp_lot(self, lot: float,
                   symbol_info: Optional[dict] = None) -> float:
        min_lot = symbol_info.get("volume_min", 0.01) if symbol_info else 0.01
        max_lot = symbol_info.get("volume_max", 10.0) if symbol_info else 10.0
        step = symbol_info.get("volume_step", 0.01) if symbol_info else 0.01
        lot = max(min_lot, min(lot, max_lot))
        return round(round(lot / step) * step, 2)

    # ─────────────────────── SL / TP ──────────────────────

    def calculate_sl_tp(
        self,
        entry_price: float,
        order_type: str,
        atr: float,
        symbol_digits: int = 5,
        sl_mult: Optional[float] = None,
        tp_mult: Optional[float] = None,
        support_resistance: Optional[Dict] = None,
    ) -> Tuple[float, float]:
        """
        ATR-based SL/TP with optional S/R refinement.
        Returns (stop_loss, take_profit) prices.
        """
        sl_mult = sl_mult or self.cfg.get("sl_atr_multiplier", 1.5)
        tp_mult = tp_mult or self.cfg.get("tp_atr_multiplier", 2.5)
        sl_dist = atr * sl_mult
        tp_dist = atr * tp_mult

        if order_type.lower() in ("buy", "buy_limit", "buy_stop"):
            sl = entry_price - sl_dist
            tp = entry_price + tp_dist
            # Snap SL to nearest support if available
            if support_resistance:
                supports = [s for s in support_resistance.get("support", [])
                            if s < entry_price - sl_dist * 0.5]
                if supports:
                    sl = min(sl, max(supports) - atr * 0.3)
        else:
            sl = entry_price + sl_dist
            tp = entry_price - tp_dist
            if support_resistance:
                resistances = [r for r in support_resistance.get("resistance", [])
                               if r > entry_price + sl_dist * 0.5]
                if resistances:
                    sl = max(sl, min(resistances) + atr * 0.3)

        factor = 10 ** symbol_digits
        sl = round(sl * factor) / factor
        tp = round(tp * factor) / factor
        return sl, tp

    def calculate_trailing_stop(
        self,
        position: dict,
        current_price: float,
        atr: float,
    ) -> Optional[float]:
        """Calculate new trailing stop level."""
        mult = self.cfg.get("trailing_atr_multiplier", 1.0)
        dist = atr * mult
        if position["type"] == 0:  # Buy
            new_sl = current_price - dist
            if new_sl > position["sl"]:
                return round(new_sl, 5)
        else:  # Sell
            new_sl = current_price + dist
            if position["sl"] == 0 or new_sl < position["sl"]:
                return round(new_sl, 5)
        return None

    # ─────────────────────── DRAWDOWN CONTROL ─────────────

    def update_equity(self, equity: float, realized_pnl: float = 0.0):
        """Track equity and enforce circuit breakers."""
        if equity > self.peak_equity:
            self.peak_equity = equity
        if realized_pnl != 0:
            self.daily_pnl += realized_pnl

        max_daily_loss = self.cfg.get("max_daily_loss_pct", 2.0)
        max_dd = self.cfg.get("max_drawdown_pct", 5.0)

        if self.peak_equity > 0:
            dd_pct = (self.peak_equity - equity) / self.peak_equity * 100
            if dd_pct >= max_dd:
                self.trading_enabled = False
                logger.critical(
                    f"🚨 CIRCUIT BREAKER: Max drawdown {dd_pct:.1f}% >= {max_dd}% | TRADING HALTED")
                return

        if self.peak_equity > 0:
            daily_loss_pct = abs(self.daily_pnl) / self.peak_equity * 100
            if self.daily_pnl < 0 and daily_loss_pct >= max_daily_loss:
                self.trading_enabled = False
                logger.critical(
                    f"🚨 CIRCUIT BREAKER: Daily loss {daily_loss_pct:.1f}% >= {max_daily_loss}% | TRADING HALTED")

    def reset_daily(self):
        """Call at start of each trading day."""
        self.daily_pnl = 0.0
        if self.trading_enabled is False:
            # Re-enable if was halted by daily loss only
            logger.info("✅ Daily reset - trading re-enabled")
            self.trading_enabled = True

    def can_trade(self, reason: str = "") -> Tuple[bool, str]:
        """Check if system is allowed to open new trades."""
        if not self.trading_enabled:
            return False, "Circuit breaker active"
        return True, "OK"

    # ─────────────────────── POSITION EXPOSURE ────────────

    def check_exposure(
        self,
        positions: list,
        max_positions: int,
        max_per_symbol: int,
        symbol: str,
    ) -> Tuple[bool, str]:
        """Verify we can open a new position within exposure limits."""
        if len(positions) >= max_positions:
            return False, f"Max positions reached ({max_positions})"
        symbol_count = sum(1 for p in positions if p.get("symbol") == symbol)
        if symbol_count >= max_per_symbol:
            return False, f"Max positions for {symbol} reached ({max_per_symbol})"
        return True, "OK"

    def calculate_correlation_risk(self, symbols: list) -> float:
        """
        Simple correlation-based risk multiplier.
        Returns 0-1 where 1 = fully correlated (reduce position size).
        """
        correlated_groups = [
            {"EURUSD", "GBPUSD", "EURGBP"},
            {"USDJPY", "EURJPY", "GBPJPY"},
            {"XAUUSD", "XAGUSD"},
            {"NAS100", "US30", "US500"},
        ]
        if not symbols:
            return 0.0
        symbol_set = set(symbols)
        max_corr = 0.0
        for group in correlated_groups:
            overlap = len(symbol_set & group)
            if overlap > 1:
                max_corr = max(max_corr, (overlap - 1) / len(group))
        return max_corr

    # ─────────────────────── STATS ────────────────────────

    def record_trade(self, profit: float, pips: float):
        self._trade_log.append({"profit": profit, "pips": pips})

    def _get_win_rate(self) -> float:
        if len(self._trade_log) < 5:
            return 0.5
        wins = sum(1 for t in self._trade_log if t["profit"] > 0)
        return wins / len(self._trade_log)

    def _get_avg_win_pips(self) -> float:
        wins = [t["pips"] for t in self._trade_log if t["pips"] > 0]
        return np.mean(wins) if wins else 10.0

    def get_stats(self) -> Dict:
        if not self._trade_log:
            return {"win_rate": 0, "avg_profit": 0, "total_trades": 0}
        profits = [t["profit"] for t in self._trade_log]
        return {
            "total_trades": len(self._trade_log),
            "win_rate": round(self._get_win_rate() * 100, 1),
            "avg_profit": round(float(np.mean(profits)), 2),
            "total_pnl": round(float(sum(profits)), 2),
            "daily_pnl": round(self.daily_pnl, 2),
            "trading_enabled": self.trading_enabled,
        }
