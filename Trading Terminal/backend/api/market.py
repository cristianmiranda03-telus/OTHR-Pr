"""Market data and symbols (MT5 + stubs for Finviz, etc.)."""
from fastapi import APIRouter
from typing import Any

router = APIRouter(prefix="/api/market", tags=["Market"])


@router.get("/symbols")
def get_symbols():
    """Symbols from MT5 if connected; else demo list."""
    try:
        import MetaTrader5 as mt5
        if mt5.initialize():
            symbols = mt5.symbols_get()
            mt5.shutdown()
            if symbols:
                return {"symbols": [s.name for s in symbols[:200]]}
    except Exception:
        pass
    return {"symbols": ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD", "SPX", "VIX"]}


@router.get("/rates")
def get_rates(symbol: str = "EURUSD", timeframe: str = "M15", count: int = 100):
    """OHLCV rates from MT5. Timeframe: M1, M5, M15, M30, H1, H4, D1, W1, MN1."""
    try:
        import MetaTrader5 as mt5
        tf_map = {"M1": 1, "M5": 5, "M15": 15, "M30": 30, "H1": 60, "H4": 240, "D1": 1440, "W1": 10080, "MN1": 43200}
        tf = tf_map.get(timeframe.upper(), 15)
        if mt5.initialize():
            rates = mt5.copy_rates_from_pos(symbol, tf, 0, count)
            mt5.shutdown()
            if rates is not None and len(rates) > 0:
                import pandas as pd
                df = pd.DataFrame(rates)
                df["datetime"] = pd.to_datetime(df["time"], unit="s")
                return {"data": df.to_dict(orient="records")}
    except Exception as e:
        return {"error": str(e), "data": []}
    return {"data": []}
