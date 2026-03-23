"""
MT5 Connection Manager
Handles all MetaTrader 5 connection, authentication, order management and data retrieval.
"""
import asyncio
import time
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any, Tuple
from loguru import logger
import pandas as pd
import numpy as np

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    logger.warning("MetaTrader5 not installed - running in simulation mode")

from ..utils.logger import get_logger

log = get_logger("MT5Connection")


TIMEFRAME_MAP = {
    "M1":  mt5.TIMEFRAME_M1  if MT5_AVAILABLE else 1,
    "M2":  mt5.TIMEFRAME_M2  if MT5_AVAILABLE else 2,
    "M3":  mt5.TIMEFRAME_M3  if MT5_AVAILABLE else 3,
    "M4":  mt5.TIMEFRAME_M4  if MT5_AVAILABLE else 4,
    "M5":  mt5.TIMEFRAME_M5  if MT5_AVAILABLE else 5,
    "M10": mt5.TIMEFRAME_M10 if MT5_AVAILABLE else 10,
    "M15": mt5.TIMEFRAME_M15 if MT5_AVAILABLE else 15,
    "M30": mt5.TIMEFRAME_M30 if MT5_AVAILABLE else 30,
    "H1":  mt5.TIMEFRAME_H1  if MT5_AVAILABLE else 60,
    "H4":  mt5.TIMEFRAME_H4  if MT5_AVAILABLE else 240,
    "D1":  mt5.TIMEFRAME_D1  if MT5_AVAILABLE else 1440,
    "W1":  mt5.TIMEFRAME_W1  if MT5_AVAILABLE else 10080,
    "MN1": mt5.TIMEFRAME_MN1 if MT5_AVAILABLE else 43200,
}

ORDER_TYPE_MAP = {
    "buy":        mt5.ORDER_TYPE_BUY        if MT5_AVAILABLE else 0,
    "sell":       mt5.ORDER_TYPE_SELL       if MT5_AVAILABLE else 1,
    "buy_limit":  mt5.ORDER_TYPE_BUY_LIMIT  if MT5_AVAILABLE else 2,
    "sell_limit": mt5.ORDER_TYPE_SELL_LIMIT if MT5_AVAILABLE else 3,
    "buy_stop":   mt5.ORDER_TYPE_BUY_STOP   if MT5_AVAILABLE else 4,
    "sell_stop":  mt5.ORDER_TYPE_SELL_STOP  if MT5_AVAILABLE else 5,
}


class MT5Connection:
    """Thread-safe MT5 connection manager with full order lifecycle support."""

    def __init__(self, config: dict):
        self.config = config
        self.connected = False
        self.account_info: Optional[Dict] = None
        self._lock = asyncio.Lock()
        self._reconnect_attempts = 0
        self._max_reconnect = 5
        self._last_heartbeat = 0.0

    # ─────────────────────────── CONNECTION ────────────────────────────

    async def connect(self) -> bool:
        """Initialize and authenticate with MT5."""
        if not MT5_AVAILABLE:
            log.warning("⚠ MT5 library not available - simulation mode active")
            self.connected = True
            self.account_info = self._sim_account()
            return True

        async with self._lock:
            try:
                raw_path = self.config.get("path", "")
                path = raw_path if raw_path and raw_path.strip() else None
                init_kwargs = {"timeout": self.config.get("timeout", 60000)}
                if path:
                    init_kwargs["path"] = path
                if not mt5.initialize(**init_kwargs):
                    log.error(f"MT5 init failed: {mt5.last_error()}")
                    return False

                login = self.config.get("login")
                password = self.config.get("password")
                server = self.config.get("server")

                if login and password and server:
                    if not mt5.login(login=int(login), password=str(password), server=str(server)):
                        log.error(f"MT5 login failed: {mt5.last_error()}")
                        return False

                info = mt5.account_info()
                if info is None:
                    log.error("Cannot retrieve account info")
                    return False

                self.account_info = info._asdict()
                self.connected = True
                self._last_heartbeat = time.time()
                log.info(f"✅ Connected to MT5 | Account: {self.account_info['login']} | "
                         f"Balance: {self.account_info['balance']:.2f} {self.account_info['currency']} | "
                         f"Server: {self.account_info['server']}")
                return True

            except Exception as e:
                log.exception(f"MT5 connection error: {e}")
                return False

    async def disconnect(self):
        if MT5_AVAILABLE and self.connected:
            mt5.shutdown()
        self.connected = False
        log.info("MT5 disconnected")

    async def ensure_connected(self) -> bool:
        """Reconnect if needed — with exponential back-off to avoid log spam."""
        if not MT5_AVAILABLE:
            return True  # Simulation mode - always "connected"

        if self.connected and (time.time() - self._last_heartbeat) < 30:
            return True

        # Exponential back-off: don't retry more often than needed
        backoff = min(30 * (2 ** self._reconnect_attempts), 300)
        last_attempt = getattr(self, "_last_reconnect_time", 0)
        if not self.connected and (time.time() - last_attempt) < backoff:
            return False  # Still in back-off window, skip silently

        self._last_reconnect_time = time.time()
        if not self.connected:
            self._reconnect_attempts += 1
            log.warning(f"MT5 reconnect attempt {self._reconnect_attempts} "
                        f"(next in {backoff:.0f}s if MT5 not running)")
            if await self.connect():
                self._reconnect_attempts = 0
                return True
            return False

        self._last_heartbeat = time.time()
        return True

    # ─────────────────────────── ACCOUNT ───────────────────────────────

    async def get_account_info(self) -> Dict:
        if not MT5_AVAILABLE:
            return self._sim_account()
        if not self.connected:
            # Return cached or sim data without triggering reconnect on every WS poll
            return self.account_info or self._sim_account()
        if not await self.ensure_connected():
            return self.account_info or self._sim_account()
        info = mt5.account_info()
        if info:
            self.account_info = info._asdict()
        return self.account_info or self._sim_account()

    # ─────────────────────────── MARKET DATA ───────────────────────────

    async def get_ohlcv(self, symbol: str, timeframe: str, bars: int = 500,
                        start: Optional[datetime] = None) -> pd.DataFrame:
        """Fetch OHLCV data for a symbol."""
        if not MT5_AVAILABLE:
            return self._sim_ohlcv(symbol, bars)

        if not await self.ensure_connected():
            return pd.DataFrame()

        tf = TIMEFRAME_MAP.get(timeframe.upper(), mt5.TIMEFRAME_M1)
        try:
            if start:
                rates = mt5.copy_rates_from(symbol, tf, start, bars)
            else:
                rates = mt5.copy_rates_from_pos(symbol, tf, 0, bars)

            if rates is None or len(rates) == 0:
                log.warning(f"No data for {symbol} {timeframe}: {mt5.last_error()}")
                return pd.DataFrame()

            df = pd.DataFrame(rates)
            df["time"] = pd.to_datetime(df["time"], unit="s")
            df.set_index("time", inplace=True)
            df.rename(columns={"open": "open", "high": "high", "low": "low",
                                "close": "close", "tick_volume": "volume"}, inplace=True)
            return df[["open", "high", "low", "close", "volume", "spread"]]
        except Exception as e:
            log.error(f"get_ohlcv error [{symbol}]: {e}")
            return pd.DataFrame()

    async def get_tick(self, symbol: str) -> Optional[Dict]:
        """Get latest tick for symbol."""
        if not MT5_AVAILABLE:
            return self._sim_tick(symbol)
        tick = mt5.symbol_info_tick(symbol)
        if tick:
            return {
                "bid": tick.bid,
                "ask": tick.ask,
                "last": tick.last,
                "volume": tick.volume,
                "time": datetime.fromtimestamp(tick.time),
                "spread": round((tick.ask - tick.bid) * 10000, 1),
            }
        return None

    async def get_symbols(self, group: str = "") -> List[str]:
        if not MT5_AVAILABLE:
            return ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "NAS100", "US30"]
        symbols = mt5.symbols_get(group=group) if group else mt5.symbols_get()
        return [s.name for s in symbols] if symbols else []

    async def get_symbol_info(self, symbol: str) -> Optional[Dict]:
        if not MT5_AVAILABLE:
            return self._sim_symbol_info(symbol)
        info = mt5.symbol_info(symbol)
        return info._asdict() if info else None

    # ─────────────────────────── ORDERS ────────────────────────────────

    async def send_order(
        self, symbol: str, order_type: str, volume: float,
        price: float = 0.0, sl: float = 0.0, tp: float = 0.0,
        comment: str = "TT-Agent", magic: int = 20250101,
        deviation: int = 20
    ) -> Dict:
        """Send a trade order with slippage control."""
        if not MT5_AVAILABLE:
            return self._sim_order_result(symbol, order_type, volume, price)

        if not await self.ensure_connected():
            return {"error": "Not connected", "success": False}

        otype = ORDER_TYPE_MAP.get(order_type.lower())
        if otype is None:
            return {"error": f"Unknown order type: {order_type}", "success": False}

        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            return {"error": f"Cannot get tick for {symbol}", "success": False}

        if order_type.lower() == "buy":
            price = tick.ask
        elif order_type.lower() == "sell":
            price = tick.bid

        request = {
            "action":    mt5.TRADE_ACTION_DEAL,
            "symbol":    symbol,
            "volume":    float(volume),
            "type":      otype,
            "price":     price,
            "sl":        float(sl) if sl else 0.0,
            "tp":        float(tp) if tp else 0.0,
            "deviation": deviation,
            "magic":     magic,
            "comment":   comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)
        if result is None:
            return {"error": str(mt5.last_error()), "success": False}

        res_dict = result._asdict()
        success = result.retcode == mt5.TRADE_RETCODE_DONE
        if success:
            log.info(f"✅ ORDER {order_type.upper()} {volume} {symbol} @ {price:.5f} | "
                     f"Ticket: {result.order} | SL: {sl:.5f} | TP: {tp:.5f}")
        else:
            log.error(f"❌ ORDER FAILED {order_type.upper()} {symbol}: "
                      f"retcode={result.retcode} | comment={result.comment}")

        return {**res_dict, "success": success,
                "ticket": result.order, "price_executed": result.price}

    async def close_position(self, ticket: int, volume: Optional[float] = None) -> Dict:
        """Close a position fully or partially."""
        if not MT5_AVAILABLE:
            return {"success": True, "ticket": ticket, "simulated": True}

        positions = mt5.positions_get(ticket=ticket)
        if not positions:
            return {"error": f"Position {ticket} not found", "success": False}

        pos = positions[0]
        close_type = mt5.ORDER_TYPE_SELL if pos.type == 0 else mt5.ORDER_TYPE_BUY
        close_volume = volume if volume else pos.volume

        tick = mt5.symbol_info_tick(pos.symbol)
        close_price = tick.bid if close_type == mt5.ORDER_TYPE_SELL else tick.ask

        request = {
            "action":    mt5.TRADE_ACTION_DEAL,
            "symbol":    pos.symbol,
            "volume":    close_volume,
            "type":      close_type,
            "position":  ticket,
            "price":     close_price,
            "deviation": 20,
            "magic":     pos.magic,
            "comment":   "TT-Close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result is None:
            return {"error": str(mt5.last_error()), "success": False}

        success = result.retcode == mt5.TRADE_RETCODE_DONE
        if success:
            log.info(f"✅ CLOSED position {ticket} ({close_volume} lots) @ {close_price:.5f} | "
                     f"P/L: {pos.profit:.2f}")
        return {**result._asdict(), "success": success}

    async def modify_position(self, ticket: int, sl: float, tp: float) -> Dict:
        """Modify SL/TP of an open position."""
        if not MT5_AVAILABLE:
            return {"success": True, "simulated": True}

        request = {
            "action":   mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "sl":       sl,
            "tp":       tp,
        }
        result = mt5.order_send(request)
        if result is None:
            return {"error": str(mt5.last_error()), "success": False}
        success = result.retcode == mt5.TRADE_RETCODE_DONE
        if success:
            log.info(f"✅ MODIFIED position {ticket} | SL: {sl:.5f} | TP: {tp:.5f}")
        return {**result._asdict(), "success": success}

    async def cancel_order(self, ticket: int) -> Dict:
        """Cancel a pending order."""
        if not MT5_AVAILABLE:
            return {"success": True, "simulated": True}
        request = {"action": mt5.TRADE_ACTION_REMOVE, "order": ticket}
        result = mt5.order_send(request)
        if result is None:
            return {"error": str(mt5.last_error()), "success": False}
        return {**result._asdict(), "success": result.retcode == mt5.TRADE_RETCODE_DONE}

    # ─────────────────────────── POSITIONS & ORDERS ────────────────────

    async def get_positions(self, symbol: Optional[str] = None) -> List[Dict]:
        if not MT5_AVAILABLE:
            return []
        if not self.connected:
            return []
        positions = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
        if positions is None:
            return []
        result = []
        for p in positions:
            d = p._asdict()
            d["time"] = datetime.fromtimestamp(d["time"])
            result.append(d)
        return result

    async def get_pending_orders(self, symbol: Optional[str] = None) -> List[Dict]:
        if not MT5_AVAILABLE:
            return []
        orders = mt5.orders_get(symbol=symbol) if symbol else mt5.orders_get()
        if orders is None:
            return []
        return [o._asdict() for o in orders]

    async def get_history(self, days: int = 7) -> List[Dict]:
        """Get closed trades history."""
        if not MT5_AVAILABLE:
            return []
        from_date = datetime.now() - timedelta(days=days)
        deals = mt5.history_deals_get(from_date, datetime.now())
        if deals is None:
            return []
        result = []
        for d in deals:
            deal_dict = d._asdict()
            deal_dict["time"] = datetime.fromtimestamp(deal_dict["time"])
            result.append(deal_dict)
        return result

    # ─────────────────────────── SIMULATION ────────────────────────────

    def _sim_account(self) -> Dict:
        return {
            "login": 12345678, "balance": 10000.0, "equity": 10000.0,
            "margin": 0.0, "margin_free": 10000.0, "margin_level": 0.0,
            "profit": 0.0, "currency": "USD", "server": "Demo",
            "name": "Demo Account", "leverage": 100,
        }

    def _sim_ohlcv(self, symbol: str, bars: int) -> pd.DataFrame:
        np.random.seed(hash(symbol) % 2**31)
        dates = pd.date_range(end=datetime.now(), periods=bars, freq="1min")
        price = 1.10000 + np.cumsum(np.random.randn(bars) * 0.0001)
        df = pd.DataFrame({
            "open": price, "high": price + np.abs(np.random.randn(bars) * 0.0003),
            "low": price - np.abs(np.random.randn(bars) * 0.0003),
            "close": price + np.random.randn(bars) * 0.0001,
            "volume": np.random.randint(100, 1000, bars).astype(float),
            "spread": np.full(bars, 1.5),
        }, index=dates)
        return df

    def _sim_tick(self, symbol: str) -> Dict:
        bid = 1.10000 + np.random.randn() * 0.0001
        return {
            "bid": bid, "ask": bid + 0.00015, "last": bid,
            "volume": np.random.randint(1, 10),
            "time": datetime.now(), "spread": 1.5,
        }

    def _sim_symbol_info(self, symbol: str) -> Dict:
        return {
            "name": symbol, "digits": 5, "point": 0.00001,
            "trade_contract_size": 100000, "volume_min": 0.01,
            "volume_max": 100.0, "volume_step": 0.01,
        }

    def _sim_order_result(self, symbol: str, order_type: str,
                          volume: float, price: float) -> Dict:
        import random
        ticket = random.randint(100000, 999999)
        log.info(f"[SIM] ORDER {order_type.upper()} {volume} {symbol} @ {price:.5f} | Ticket: {ticket}")
        return {
            "success": True, "ticket": ticket, "price_executed": price,
            "retcode": 10009, "comment": "Simulated", "simulated": True,
        }
