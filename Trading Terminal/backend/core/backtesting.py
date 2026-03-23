"""
Backtesting Engine
High-performance vectorized backtesting with full P/L accounting and metrics.
"""
import pandas as pd
import numpy as np
from typing import Dict, List, Optional, Callable
from dataclasses import dataclass, field
from datetime import datetime
import json
from loguru import logger


@dataclass
class Trade:
    ticket: int
    symbol: str
    order_type: str
    entry_time: datetime
    entry_price: float
    volume: float
    sl: float
    tp: float
    exit_time: Optional[datetime] = None
    exit_price: Optional[float] = None
    profit: float = 0.0
    pips: float = 0.0
    status: str = "open"
    reason: str = ""
    indicators_snapshot: Dict = field(default_factory=dict)


@dataclass
class BacktestResult:
    strategy_name: str
    symbol: str
    timeframe: str
    start_date: str
    end_date: str
    initial_balance: float
    final_balance: float
    total_return_pct: float
    max_drawdown_pct: float
    sharpe_ratio: float
    sortino_ratio: float
    win_rate: float
    profit_factor: float
    total_trades: int
    winning_trades: int
    losing_trades: int
    avg_win: float
    avg_loss: float
    best_trade: float
    worst_trade: float
    avg_trade_duration_mins: float
    trades: List[Trade] = field(default_factory=list)
    equity_curve: List[float] = field(default_factory=list)
    parameters: Dict = field(default_factory=dict)

    def to_dict(self) -> Dict:
        d = {k: v for k, v in self.__dict__.items() if k != "trades"}
        d["trades"] = [
            {
                "ticket": t.ticket,
                "entry_time": t.entry_time.isoformat(),
                "exit_time": t.exit_time.isoformat() if t.exit_time else None,
                "entry_price": t.entry_price,
                "exit_price": t.exit_price,
                "profit": t.profit,
                "pips": t.pips,
                "status": t.status,
                "reason": t.reason,
            }
            for t in self.trades
        ]
        return d

    def summary(self) -> str:
        return (
            f"{'─'*60}\n"
            f"Strategy: {self.strategy_name} | {self.symbol} {self.timeframe}\n"
            f"Period: {self.start_date} → {self.end_date}\n"
            f"Balance: ${self.initial_balance:,.2f} → ${self.final_balance:,.2f} "
            f"({self.total_return_pct:+.1f}%)\n"
            f"Max Drawdown: {self.max_drawdown_pct:.1f}% | Sharpe: {self.sharpe_ratio:.2f} "
            f"| Sortino: {self.sortino_ratio:.2f}\n"
            f"Win Rate: {self.win_rate:.1f}% | PF: {self.profit_factor:.2f} "
            f"| Trades: {self.total_trades}\n"
            f"Avg Win: ${self.avg_win:.2f} | Avg Loss: ${self.avg_loss:.2f}\n"
            f"{'─'*60}"
        )


class Backtester:
    """
    Event-driven backtester that processes OHLCV data bar by bar.
    Supports multiple entry/exit signal callbacks.
    """

    def __init__(self, config: dict):
        self.cfg = config
        self.commission = config.get("commission_per_lot", 7.0)
        self._ticket_counter = 1

    def run(
        self,
        df: pd.DataFrame,
        strategy_fn: Callable,
        strategy_name: str,
        symbol: str,
        timeframe: str,
        initial_balance: Optional[float] = None,
        parameters: Optional[Dict] = None,
    ) -> BacktestResult:
        """
        Run backtest on prepared OHLCV DataFrame.
        strategy_fn(df_slice, position) -> Dict with keys:
            signal: 'buy' | 'sell' | 'close' | 'hold'
            sl: float (optional)
            tp: float (optional)
            volume: float (optional)
        """
        balance = initial_balance or self.cfg.get("initial_balance", 10000.0)
        initial_balance = balance
        parameters = parameters or {}

        equity_curve = [balance]
        open_trades: List[Trade] = []
        closed_trades: List[Trade] = []
        peak_equity = balance

        for i in range(50, len(df)):
            df_slice = df.iloc[:i + 1]
            current = df.iloc[i]

            # Check SL/TP hits on open trades
            trades_to_close = []
            for trade in open_trades:
                closed, reason, exit_price = self._check_exit(trade, current)
                if closed:
                    pnl = self._calculate_pnl(trade, exit_price, symbol)
                    balance += pnl
                    trade.exit_time = current.name
                    trade.exit_price = exit_price
                    trade.profit = round(pnl, 2)
                    trade.status = "closed"
                    trade.reason = reason
                    trades_to_close.append(trade)

            for trade in trades_to_close:
                open_trades.remove(trade)
                closed_trades.append(trade)

            # Strategy signal
            try:
                signal_data = strategy_fn(df_slice, open_trades, parameters)
            except Exception as e:
                logger.debug(f"Strategy error at bar {i}: {e}")
                signal_data = {"signal": "hold"}

            signal = signal_data.get("signal", "hold")

            if signal in ("buy", "sell") and len(open_trades) < 3:
                trade = Trade(
                    ticket=self._ticket_counter,
                    symbol=symbol,
                    order_type=signal,
                    entry_time=current.name,
                    entry_price=current["close"],
                    volume=signal_data.get("volume", 0.01),
                    sl=signal_data.get("sl", 0.0),
                    tp=signal_data.get("tp", 0.0),
                    indicators_snapshot=signal_data.get("snapshot", {}),
                )
                open_trades.append(trade)
                self._ticket_counter += 1

            elif signal == "close" and open_trades:
                trade = open_trades[-1]
                exit_price = current["close"]
                pnl = self._calculate_pnl(trade, exit_price, symbol)
                balance += pnl
                trade.exit_time = current.name
                trade.exit_price = exit_price
                trade.profit = round(pnl, 2)
                trade.status = "closed"
                trade.reason = "signal"
                closed_trades.append(trade)
                open_trades.pop()

            unrealized = sum(self._calculate_pnl(t, current["close"], symbol)
                             for t in open_trades)
            current_equity = balance + unrealized
            equity_curve.append(current_equity)
            if current_equity > peak_equity:
                peak_equity = current_equity

        # Force close remaining
        if df is not None and len(df) > 0:
            last = df.iloc[-1]
            for trade in open_trades:
                pnl = self._calculate_pnl(trade, last["close"], symbol)
                balance += pnl
                trade.exit_time = last.name
                trade.exit_price = last["close"]
                trade.profit = round(pnl, 2)
                trade.status = "closed"
                trade.reason = "end_of_data"
                closed_trades.append(trade)

        return self._compute_result(
            strategy_name, symbol, timeframe,
            str(df.index[0].date()), str(df.index[-1].date()),
            initial_balance, balance, closed_trades, equity_curve, parameters
        )

    def _check_exit(self, trade: Trade,
                    candle: pd.Series) -> tuple:
        if trade.order_type == "buy":
            if trade.sl > 0 and candle["low"] <= trade.sl:
                return True, "sl", trade.sl
            if trade.tp > 0 and candle["high"] >= trade.tp:
                return True, "tp", trade.tp
        else:
            if trade.sl > 0 and candle["high"] >= trade.sl:
                return True, "sl", trade.sl
            if trade.tp > 0 and candle["low"] <= trade.tp:
                return True, "tp", trade.tp
        return False, "", 0.0

    def _calculate_pnl(self, trade: Trade, exit_price: float,
                        symbol: str) -> float:
        digits = 5 if "JPY" not in symbol else 3
        point = 10 ** (-digits)
        pip_size = point * 10
        contract_size = 100000
        if "JPY" in symbol:
            pip_value = trade.volume * pip_size * contract_size / exit_price
        elif symbol in ("XAUUSD",):
            pip_value = trade.volume * 0.1
            pip_size = 0.01
        else:
            pip_value = trade.volume * pip_size * contract_size
        if trade.order_type == "buy":
            pips = (exit_price - trade.entry_price) / pip_size
        else:
            pips = (trade.entry_price - exit_price) / pip_size
        trade.pips = round(pips, 1)
        pnl = pips * pip_value - (self.commission * trade.volume)
        return round(pnl, 2)

    def _compute_result(
        self, strategy_name, symbol, timeframe,
        start, end, initial_balance, final_balance,
        trades, equity_curve, parameters
    ) -> BacktestResult:
        if not trades:
            return BacktestResult(
                strategy_name=strategy_name, symbol=symbol, timeframe=timeframe,
                start_date=start, end_date=end, initial_balance=initial_balance,
                final_balance=final_balance, total_return_pct=0, max_drawdown_pct=0,
                sharpe_ratio=0, sortino_ratio=0, win_rate=0, profit_factor=0,
                total_trades=0, winning_trades=0, losing_trades=0,
                avg_win=0, avg_loss=0, best_trade=0, worst_trade=0,
                avg_trade_duration_mins=0, trades=trades,
                equity_curve=equity_curve, parameters=parameters,
            )

        profits = [t.profit for t in trades]
        wins = [p for p in profits if p > 0]
        losses = [p for p in profits if p <= 0]
        eq = np.array(equity_curve)
        peak = np.maximum.accumulate(eq)
        dd = (peak - eq) / peak * 100
        max_dd = float(dd.max())
        returns = pd.Series(eq).pct_change().dropna()
        sharpe = float(returns.mean() / returns.std() * np.sqrt(252 * 390)) if returns.std() > 0 else 0
        neg_returns = returns[returns < 0]
        sortino = float(returns.mean() / neg_returns.std() * np.sqrt(252 * 390)) if len(neg_returns) > 0 else 0
        gross_profit = sum(wins)
        gross_loss = abs(sum(losses))
        pf = gross_profit / gross_loss if gross_loss > 0 else 999.0
        durations = []
        for t in trades:
            if t.exit_time and t.entry_time:
                d = (t.exit_time - t.entry_time).total_seconds() / 60
                durations.append(d)

        return BacktestResult(
            strategy_name=strategy_name, symbol=symbol, timeframe=timeframe,
            start_date=start, end_date=end,
            initial_balance=initial_balance, final_balance=round(final_balance, 2),
            total_return_pct=round((final_balance - initial_balance) / initial_balance * 100, 2),
            max_drawdown_pct=round(max_dd, 2),
            sharpe_ratio=round(sharpe, 3), sortino_ratio=round(sortino, 3),
            win_rate=round(len(wins) / len(profits) * 100, 1),
            profit_factor=round(pf, 3),
            total_trades=len(trades), winning_trades=len(wins),
            losing_trades=len(losses),
            avg_win=round(np.mean(wins) if wins else 0, 2),
            avg_loss=round(np.mean(losses) if losses else 0, 2),
            best_trade=round(max(profits), 2),
            worst_trade=round(min(profits), 2),
            avg_trade_duration_mins=round(np.mean(durations) if durations else 0, 1),
            trades=trades, equity_curve=equity_curve.tolist() if isinstance(equity_curve, np.ndarray) else equity_curve,
            parameters=parameters,
        )
