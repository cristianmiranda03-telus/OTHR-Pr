"""Strategies and backtesting API."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Any

import pandas as pd

from core.backtester import run_backtest
from strategies.strategies import get_strategy_class

router = APIRouter(prefix="/api/strategies", tags=["Strategies"])


class BacktestRequest(BaseModel):
    strategy_name: str
    data: list[dict[str, Any]]  # [{datetime, open, high, low, close, volume?}, ...]
    start: str | None = None
    end: str | None = None
    cash: float = 100000.0
    commission: float = 0.0001
    slippage: float = 0.0001
    strategy_params: dict[str, Any] | None = None


@router.get("/list")
def list_strategies():
    """List available strategy names for backtesting."""
    from strategies.strategies import list_strategies as ls
    strategies = ls()
    return {
        "strategies": strategies,
        "params": {
            "rsi": ["rsi_period", "rsi_low", "rsi_high", "ma_period", "use_ma_filter"],
            "sma_cross": ["fast", "slow"],
            "ema_cross": ["fast", "slow"],
            "macd_signal": ["fast", "slow", "signal"],
            "bb_breakout": ["period", "devfactor"],
            "stoch_cross": ["k_period", "d_period"],
            "rsi_macd_confluence": ["rsi_period", "rsi_low", "rsi_high", "macd_fast", "macd_slow"],
            "atr_breakout": ["atr_period", "multiplier", "ma_period"],
            "mean_reversion": ["period", "z_entry", "z_exit"],
            "momentum_factor": ["lookback", "ma_fast", "ma_slow"],
            "volatility_regime": ["adx_period", "adx_threshold", "rsi_period"],
            "ml_random_forest": ["min_votes"],
            "triple_ema": ["ema1", "ema2", "ema3"],
        }
    }


@router.post("/backtest")
def backtest(req: BacktestRequest):
    """Run backtest on provided OHLCV data."""
    strategy_class = get_strategy_class(req.strategy_name)
    if strategy_class is None:
        raise HTTPException(status_code=400, detail=f"Unknown strategy: {req.strategy_name}")
    df = pd.DataFrame(req.data)
    if df.empty or "close" not in df.columns:
        raise HTTPException(status_code=400, detail="Data must include open, high, low, close.")
    for col in ("open", "high", "low", "close"):
        if col not in df.columns:
            df[col] = df.get("close", 0)
    if "datetime" not in df.columns and df.index.name != "datetime":
        df["datetime"] = df.index if hasattr(df.index, "tolist") else list(range(len(df)))
    return run_backtest(
        strategy_class,
        df,
        start=req.start,
        end=req.end,
        cash=req.cash,
        commission=req.commission,
        slippage=req.slippage,
        strategy_params=req.strategy_params,
    )
