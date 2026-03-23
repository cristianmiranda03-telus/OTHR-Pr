"""
Agent 4: Risk Manager (The Risk Officer)
The most conservative agent - protects capital above all else.
"""
from typing import Dict, Tuple, Optional
from .base_agent import BaseAgent
from ..core.risk import RiskCalculator
from ..ai.llm_client import LLMClient


class RiskManagerAgent(BaseAgent):
    """
    Enforces all risk rules:
    - Daily loss circuit breaker
    - Dynamic position sizing (ATR + Kelly)
    - Correlation-aware exposure
    - Volatility-adjusted SL/TP
    - Session risk adjustment
    """

    def __init__(self, config: dict, llm: LLMClient, risk_calc: RiskCalculator):
        super().__init__("RiskManager", config)
        self.llm = llm
        self.risk = risk_calc
        self.risk_cfg = config.get("risk", {})
        self.scalping_cfg = config.get("scalping", {})

    async def _execute(self, context: Dict) -> Dict:
        symbol = context.get("symbol", "EURUSD")
        signal = context.get("signal", "hold")
        account = context.get("account", {})
        positions = context.get("positions", [])
        technical = context.get("technical_data", {})
        session_info = context.get("session_info", {})
        symbol_info = context.get("symbol_info", {})

        self._emit(f"⚖️ Risk assessment for {signal} {symbol}...")

        # Circuit breaker check
        balance = account.get("balance", 10000)
        equity = account.get("equity", balance)
        self.risk.update_equity(equity)
        can_trade, reason = self.risk.can_trade()
        if not can_trade:
            self._emit(f"🚨 TRADE BLOCKED: {reason}", "critical")
            return {"approved": False, "reason": reason, "lot_size": 0.0,
                    "sl": 0.0, "tp": 0.0, "risk_score": 1.0}

        # Exposure check
        max_pos = self.risk_cfg.get("max_positions", 5)
        max_per_sym = self.risk_cfg.get("max_positions_per_symbol", 2)
        can_open, exp_reason = self.risk.check_exposure(
            positions, max_pos, max_per_sym, symbol)
        if not can_open:
            self._emit(f"⚠ Exposure limit: {exp_reason}", "warning")
            return {"approved": False, "reason": exp_reason, "lot_size": 0.0,
                    "sl": 0.0, "tp": 0.0, "risk_score": 0.8}

        # Spread check
        current_spread = context.get("spread", 0)
        max_spread = self.scalping_cfg.get("max_spread_pips", 3.0)
        if current_spread > max_spread:
            msg = f"Spread too wide: {current_spread:.1f} > {max_spread}"
            self._emit(f"⚠ {msg}", "warning")
            return {"approved": False, "reason": msg, "lot_size": 0.0,
                    "sl": 0.0, "tp": 0.0, "risk_score": 0.6}

        # Session filter
        session_score = context.get("session_score", 50)
        if session_score < 30:
            msg = f"Poor session score: {session_score:.0f}/100"
            self._emit(f"⚠ {msg}", "warning")
            return {"approved": False, "reason": msg, "lot_size": 0.0,
                    "sl": 0.0, "tp": 0.0, "risk_score": 0.4}

        # ATR-based SL/TP
        entry_price = technical.get("entry_price", 0)
        atr = technical.get("atr", 0.001)
        sr = technical.get("support_resistance", {})
        digits = symbol_info.get("digits", 5)

        sl, tp = self.risk.calculate_sl_tp(
            entry_price, signal, atr, digits,
            support_resistance=sr,
        )

        # Lot size calculation
        sl_pips = abs(entry_price - sl) / (10 ** (-digits + 1))
        pip_value = self._get_pip_value(symbol, symbol_info)
        risk_pct = self.risk_cfg.get("risk_per_trade_pct", 0.5)

        # Scale down risk during low confidence or bad session
        confidence = technical.get("confidence", 0.5)
        if confidence < 0.6:
            risk_pct *= 0.7
        if not session_info.get("overlap_active", False):
            risk_pct *= 0.8

        lot_size = self.risk.calculate_lot_size(
            balance, risk_pct, sl_pips, pip_value, symbol_info
        )

        # R:R check - minimum 1.5:1
        if entry_price > 0:
            reward_pips = abs(tp - entry_price) / (10 ** (-digits + 1))
            rr_ratio = reward_pips / sl_pips if sl_pips > 0 else 0
            if rr_ratio < 1.5:
                tp_adjusted = (entry_price + (sl_dist := abs(entry_price - sl)) * 2.0
                               if signal == "buy"
                               else entry_price - abs(entry_price - sl) * 2.0)
                tp = round(tp_adjusted, digits)
                self._emit(f"ℹ️ TP adjusted for min 2:1 R:R")

        # Risk score (0=safe, 1=dangerous)
        daily_loss_pct = abs(self.risk.daily_pnl) / balance * 100 if balance else 0
        max_daily = self.risk_cfg.get("max_daily_loss_pct", 2.0)
        risk_score = min(daily_loss_pct / max_daily, 1.0) * 0.5 + (1 - confidence) * 0.5

        result = {
            "approved": True,
            "reason": "Risk checks passed",
            "lot_size": lot_size,
            "sl": sl,
            "tp": tp,
            "risk_pct": round(risk_pct, 2),
            "sl_pips": round(sl_pips, 1),
            "pip_value": round(pip_value, 4),
            "risk_score": round(risk_score, 3),
            "daily_stats": self.risk.get_stats(),
            "session_score": session_score,
        }
        self._emit(f"✅ APPROVED: {lot_size} lots | SL={sl:.5f} | TP={tp:.5f} | "
                   f"Risk={risk_pct:.2f}% | R:R≈{rr_ratio:.1f}:1"
                   if entry_price > 0 else f"✅ Lot: {lot_size}")
        return result

    def _get_pip_value(self, symbol: str, symbol_info: dict) -> float:
        """Calculate pip value in account currency."""
        contract_size = symbol_info.get("trade_contract_size", 100000)
        digits = symbol_info.get("digits", 5)
        pip_size = 10 ** (-digits + 1)
        if "JPY" in symbol:
            return contract_size * pip_size / 100
        elif symbol in ("XAUUSD",):
            return 1.0
        elif symbol.endswith("USD"):
            return contract_size * pip_size
        else:
            return contract_size * pip_size * 1.1

    def update_equity_external(self, equity: float, realized_pnl: float = 0.0):
        self.risk.update_equity(equity, realized_pnl)

    def record_trade_result(self, profit: float, pips: float):
        self.risk.record_trade(profit, pips)

    def get_daily_stats(self) -> Dict:
        return self.risk.get_stats()
