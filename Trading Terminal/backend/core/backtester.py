"""Backtesting engine using Backtrader (tick/bar simulation)."""
from typing import Any
import pandas as pd

try:
    import backtrader as bt
    BACKTRADER_AVAILABLE = True
except ImportError:
    BACKTRADER_AVAILABLE = False
    bt = None


def run_backtest(
    strategy_class: type,
    data_df: pd.DataFrame,
    start: str | None = None,
    end: str | None = None,
    cash: float = 100000.0,
    commission: float = 0.0001,
    slippage: float = 0.0001,
    strategy_params: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Run backtest and return summary stats.
    data_df must have columns: datetime (index or col), open, high, low, close, volume (optional).
    """
    if not BACKTRADER_AVAILABLE:
        return {"error": "backtrader not installed", "stats": None}

    if data_df is None or data_df.empty:
        return {"error": "No data provided", "stats": None}

    df = data_df.copy()
    if "datetime" in df.columns:
        df = df.set_index("datetime")
    df.index = pd.to_datetime(df.index)
    df = df.sort_index()
    if start:
        df = df.loc[df.index >= start]
    if end:
        df = df.loc[df.index <= end]
    if df.empty:
        return {"error": "No data in range", "stats": None}

    cerebro = bt.Cerebro()
    cerebro.broker.setcash(cash)
    cerebro.broker.setcommission(commission=commission)
    cerebro.addsizer(bt.sizers.PercentSizer, percents=95)

    data_bt = bt.feeds.PandasData(
        dataname=df,
        datetime=None,
        open="open",
        high="high",
        low="low",
        close="close",
        volume="volume" if "volume" in df.columns else None,
        openinterest=None,
    )
    cerebro.adddata(data_bt)
    cerebro.addstrategy(strategy_class, **(strategy_params or {}))
    cerebro.addanalyzer(bt.analyzers.SharpeRatio, _name="sharpe")
    cerebro.addanalyzer(bt.analyzers.DrawDown, _name="drawdown")
    cerebro.addanalyzer(bt.analyzers.Returns, _name="returns")
    cerebro.addanalyzer(bt.analyzers.TradeAnalyzer, _name="trades")

    try:
        results = cerebro.run()
        strat = results[0]
        broker_value = cerebro.broker.getvalue()
        sharpe = strat.analyzers.sharpe.get_analysis()
        dd = strat.analyzers.drawdown.get_analysis()
        ret = strat.analyzers.returns.get_analysis()
        ta = strat.analyzers.trades.get_analysis()

        return {
            "error": None,
            "stats": {
                "final_value": round(broker_value, 2),
                "total_return_pct": round(ret.get("rtot", 0) * 100, 2),
                "sharpe_ratio": round(sharpe.get("sharperatio", 0) or 0, 4),
                "max_drawdown_pct": round(dd.get("max", {}).get("drawdown", 0) or 0, 2),
                "max_drawdown_len": dd.get("max", {}).get("len", 0) or 0,
                "total_trades": ta.get("total", {}).get("closed", 0) or 0,
                "won_trades": ta.get("won", {}).get("total", 0) or 0,
                "lost_trades": ta.get("lost", {}).get("total", 0) or 0,
            },
        }
    except Exception as e:
        return {"error": str(e), "stats": None}
