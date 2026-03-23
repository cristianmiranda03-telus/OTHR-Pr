"""
MetaAPI Bridge — Remote / Web MT5 connection via MetaAPI.cloud REST API.

Provides the same interface as MT5Connection so the rest of the system
needs no changes when switching between local and remote modes.

MetaAPI docs: https://metaapi.cloud/docs/client/
"""
import asyncio
import time
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
import pandas as pd
import numpy as np

try:
    import httpx
    HTTPX_OK = True
except ImportError:
    HTTPX_OK = False

from ..utils.logger import get_logger

log = get_logger("MetaAPIBridge")

# MetaAPI regional endpoints
REGION_URLS = {
    "new-york":  "https://mt-client-api-v1.new-york.agiliumtrade.ai",
    "london":    "https://mt-client-api-v1.london.agiliumtrade.ai",
    "singapore": "https://mt-client-api-v1.singapore.agiliumtrade.ai",
}

# Map our timeframe strings to MetaAPI format
METAAPI_TF_MAP = {
    "M1":  "1m",  "M2":  "2m",  "M3":  "3m",  "M4":  "4m",
    "M5":  "5m",  "M10": "10m", "M15": "15m", "M30": "30m",
    "H1":  "1h",  "H4":  "4h",  "D1":  "1d",  "W1":  "1w",
    "MN1": "1mn",
}


class MetaAPIBridge:
    """
    Drop-in replacement for MT5Connection that uses MetaAPI.cloud.

    Exposes the same async interface:
      connect / disconnect / ensure_connected
      get_account_info / get_ohlcv / get_tick / get_positions / get_history
      send_order / close_position / modify_position / cancel_order
    """

    def __init__(self, config: dict):
        self.config      = config
        self.connected   = False
        self.account_info: Optional[Dict] = None
        self._client: Optional[Any] = None    # httpx.AsyncClient
        self._last_heartbeat = 0.0
        self._reconnect_attempts = 0

        # Pluck MetaAPI config
        ma = config.get("metaapi", {})
        self._token      = ma.get("token", "")
        self._account_id = ma.get("account_id", "")
        region           = ma.get("region", "new-york")
        self._base_url   = REGION_URLS.get(region, REGION_URLS["new-york"])

    # ─────────────────────────── HELPERS ───────────────────────────────

    def _headers(self) -> Dict[str, str]:
        return {
            "auth-token":   self._token,
            "Content-Type": "application/json",
        }

    def _acct_url(self, path: str = "") -> str:
        return f"{self._base_url}/users/current/accounts/{self._account_id}{path}"

    async def _get(self, path: str, params: dict = None) -> Any:
        assert self._client
        r = await self._client.get(self._acct_url(path), params=params or {})
        r.raise_for_status()
        return r.json()

    async def _post(self, path: str, body: dict) -> Any:
        assert self._client
        r = await self._client.post(self._acct_url(path), json=body)
        r.raise_for_status()
        return r.json()

    async def _delete(self, path: str) -> Any:
        assert self._client
        r = await self._client.delete(self._acct_url(path))
        r.raise_for_status()
        return r.json() if r.content else {}

    # ─────────────────────────── CONNECTION ────────────────────────────

    async def connect(self) -> bool:
        if not HTTPX_OK:
            log.error("httpx not installed — cannot use MetaAPI mode")
            return False

        if not self._token or not self._account_id:
            log.error("MetaAPI: missing token or account_id in config")
            self.connected = True        # Fall back to simulation
            self.account_info = self._sim_account()
            log.warning("MetaAPI demo mode — no credentials, using simulation")
            return True

        try:
            self._client = httpx.AsyncClient(
                headers=self._headers(),
                timeout=30.0,
                base_url=self._base_url,
            )
            info = await self._get("/accountInformation")
            self.account_info = self._parse_account(info)
            self.connected   = True
            self._last_heartbeat = time.time()
            log.info(f"✅ MetaAPI connected | Account: {self.account_info.get('login')} | "
                     f"Balance: {self.account_info.get('balance'):.2f} {self.account_info.get('currency')} | "
                     f"Server: {self.account_info.get('server')}")
            return True
        except Exception as exc:
            log.error(f"MetaAPI connect failed: {exc}")
            # Fall back to simulation so the rest of the system still works
            self.connected   = True
            self.account_info = self._sim_account()
            log.warning("Falling back to simulation (MetaAPI unreachable)")
            return True     # Return True so system starts

    async def disconnect(self):
        if self._client:
            await self._client.aclose()
            self._client = None
        self.connected = False
        log.info("MetaAPI disconnected")

    async def ensure_connected(self) -> bool:
        if self.connected and (time.time() - self._last_heartbeat) < 60:
            return True
        if not self.connected:
            backoff = min(30 * (2 ** self._reconnect_attempts), 300)
            last = getattr(self, "_last_reconnect_time", 0)
            if (time.time() - last) < backoff:
                return False
            self._last_reconnect_time = time.time()
            self._reconnect_attempts += 1
            if await self.connect():
                self._reconnect_attempts = 0
            return self.connected
        self._last_heartbeat = time.time()
        return True

    # ─────────────────────────── ACCOUNT ───────────────────────────────

    async def get_account_info(self) -> Dict:
        if not self.connected or not self._client:
            return self.account_info or self._sim_account()
        try:
            info = await self._get("/accountInformation")
            self.account_info = self._parse_account(info)
            return self.account_info
        except Exception:
            return self.account_info or self._sim_account()

    def _parse_account(self, raw: dict) -> Dict:
        return {
            "login":       raw.get("login", 0),
            "balance":     float(raw.get("balance", 0)),
            "equity":      float(raw.get("equity", 0)),
            "margin":      float(raw.get("margin", 0)),
            "margin_free": float(raw.get("freeMargin", 0)),
            "margin_level": float(raw.get("marginLevel", 0)),
            "profit":      float(raw.get("equity", 0)) - float(raw.get("balance", 0)),
            "currency":    raw.get("currency", "USD"),
            "server":      raw.get("broker", "MetaAPI"),
            "name":        raw.get("name", ""),
            "leverage":    raw.get("leverage", 100),
        }

    # ─────────────────────────── MARKET DATA ───────────────────────────

    async def get_ohlcv(self, symbol: str, timeframe: str, bars: int = 500,
                        start: Optional[datetime] = None) -> pd.DataFrame:
        if not self._client:
            return self._sim_ohlcv(symbol, bars)

        tf = METAAPI_TF_MAP.get(timeframe.upper(), "1m")
        try:
            end_time   = datetime.utcnow()
            start_time = start or (end_time - timedelta(minutes=bars))
            data = await self._get(
                f"/candles/{symbol}/{tf}",
                params={
                    "startTime": start_time.isoformat() + "Z",
                    "limit": bars,
                },
            )
            if not data:
                return pd.DataFrame()

            rows = []
            for c in data:
                rows.append({
                    "time":   pd.to_datetime(c.get("time") or c.get("brokerTime")),
                    "open":   float(c["open"]),
                    "high":   float(c["high"]),
                    "low":    float(c["low"]),
                    "close":  float(c["close"]),
                    "volume": float(c.get("tickVolume", c.get("volume", 0))),
                    "spread": float(c.get("spread", 1.5)),
                })
            df = pd.DataFrame(rows).set_index("time")
            return df

        except Exception as exc:
            log.warning(f"MetaAPI get_ohlcv [{symbol}]: {exc} — using sim data")
            return self._sim_ohlcv(symbol, bars)

    async def get_tick(self, symbol: str) -> Optional[Dict]:
        if not self._client:
            return self._sim_tick(symbol)
        try:
            data = await self._get(f"/symbols/{symbol}/current-price")
            return {
                "bid":    float(data.get("bid", 0)),
                "ask":    float(data.get("ask", 0)),
                "last":   float(data.get("bid", 0)),
                "volume": 0,
                "time":   datetime.utcnow(),
                "spread": round((float(data.get("ask", 0)) - float(data.get("bid", 0))) * 10000, 1),
            }
        except Exception:
            return self._sim_tick(symbol)

    async def get_symbols(self, group: str = "") -> List[str]:
        if not self._client:
            return ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD", "NAS100"]
        try:
            data = await self._get("/symbols")
            names = [s["symbol"] for s in data]
            return [n for n in names if group.upper() in n.upper()] if group else names
        except Exception:
            return ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD"]

    async def get_symbol_info(self, symbol: str) -> Optional[Dict]:
        if not self._client:
            return self._sim_symbol_info(symbol)
        try:
            data = await self._get(f"/symbols/{symbol}")
            return {
                "name":               symbol,
                "digits":             data.get("digits", 5),
                "point":              10 ** -data.get("digits", 5),
                "trade_contract_size": data.get("contractSize", 100000),
                "volume_min":         data.get("minVolume", 0.01),
                "volume_max":         data.get("maxVolume", 100.0),
                "volume_step":        data.get("volumeStep", 0.01),
            }
        except Exception:
            return self._sim_symbol_info(symbol)

    # ─────────────────────────── ORDERS ────────────────────────────────

    async def send_order(
        self, symbol: str, order_type: str, volume: float,
        price: float = 0.0, sl: float = 0.0, tp: float = 0.0,
        comment: str = "TT-Agent", magic: int = 20250101,
        deviation: int = 20
    ) -> Dict:
        if not self._client:
            return self._sim_order_result(symbol, order_type, volume, price)

        action_type = "ORDER_TYPE_BUY" if order_type.lower() == "buy" else "ORDER_TYPE_SELL"
        body: Dict[str, Any] = {
            "actionType": action_type,
            "symbol":     symbol,
            "volume":     volume,
            "comment":    comment,
        }
        if sl:  body["stopLoss"]   = sl
        if tp:  body["takeProfit"] = tp

        try:
            result = await self._post("/trade", body)
            success = result.get("numericCode") in (0, 10009) or "orderId" in result
            ticket  = result.get("orderId") or result.get("positionId") or 0

            if success:
                log.info(f"✅ MetaAPI ORDER {order_type.upper()} {volume} {symbol} | "
                         f"Ticket: {ticket} | SL: {sl} | TP: {tp}")
            else:
                log.error(f"❌ MetaAPI ORDER FAILED {order_type.upper()} {symbol}: {result}")

            return {
                "success":         success,
                "ticket":          ticket,
                "price_executed":  price,
                "retcode":         result.get("numericCode", 0),
                "comment":         result.get("message", ""),
            }
        except Exception as exc:
            log.error(f"MetaAPI send_order error: {exc}")
            return {"success": False, "error": str(exc)}

    async def close_position(self, ticket: int, volume: Optional[float] = None) -> Dict:
        if not self._client:
            return {"success": True, "ticket": ticket, "simulated": True}
        try:
            body: Dict[str, Any] = {"actionType": "POSITION_CLOSE_ID", "positionId": str(ticket)}
            if volume:
                body["volume"] = volume
            result = await self._post("/trade", body)
            success = result.get("numericCode") in (0, 10009)
            if success:
                log.info(f"✅ MetaAPI CLOSED position {ticket}")
            return {"success": success, "ticket": ticket, **result}
        except Exception as exc:
            return {"success": False, "error": str(exc)}

    async def modify_position(self, ticket: int, sl: float, tp: float) -> Dict:
        if not self._client:
            return {"success": True, "simulated": True}
        try:
            body = {
                "actionType": "POSITION_MODIFY",
                "positionId": str(ticket),
                "stopLoss":   sl,
                "takeProfit": tp,
            }
            result = await self._post("/trade", body)
            success = result.get("numericCode") in (0, 10009)
            if success:
                log.info(f"✅ MetaAPI MODIFIED position {ticket} | SL: {sl} | TP: {tp}")
            return {"success": success, **result}
        except Exception as exc:
            return {"success": False, "error": str(exc)}

    async def cancel_order(self, ticket: int) -> Dict:
        if not self._client:
            return {"success": True, "simulated": True}
        try:
            body = {"actionType": "ORDER_CANCEL", "orderId": str(ticket)}
            result = await self._post("/trade", body)
            return {"success": result.get("numericCode") in (0, 10009)}
        except Exception as exc:
            return {"success": False, "error": str(exc)}

    async def get_positions(self, symbol: Optional[str] = None) -> List[Dict]:
        if not self._client:
            return []
        try:
            data = await self._get("/positions")
            result = []
            for p in data:
                if symbol and p.get("symbol") != symbol:
                    continue
                result.append({
                    "ticket":       int(p.get("id", 0)),
                    "symbol":       p.get("symbol", ""),
                    "type":         0 if p.get("type") == "POSITION_TYPE_BUY" else 1,
                    "volume":       float(p.get("volume", 0)),
                    "price_open":   float(p.get("openPrice", 0)),
                    "price_current": float(p.get("currentPrice", 0)),
                    "profit":       float(p.get("profit", 0)),
                    "sl":           float(p.get("stopLoss", 0)),
                    "tp":           float(p.get("takeProfit", 0)),
                    "comment":      p.get("comment", ""),
                    "magic":        p.get("magic", 0),
                    "time":         datetime.fromisoformat(
                        p.get("time", datetime.utcnow().isoformat())
                    ),
                })
            return result
        except Exception as exc:
            log.warning(f"MetaAPI get_positions: {exc}")
            return []

    async def get_pending_orders(self, symbol: Optional[str] = None) -> List[Dict]:
        if not self._client:
            return []
        try:
            data = await self._get("/orders")
            return [o for o in data if not symbol or o.get("symbol") == symbol]
        except Exception:
            return []

    async def get_history(self, days: int = 7) -> List[Dict]:
        if not self._client:
            return []
        try:
            from_date = (datetime.utcnow() - timedelta(days=days)).isoformat() + "Z"
            to_date   = datetime.utcnow().isoformat() + "Z"
            data = await self._get(
                "/history-deals/time-range",
                params={"startTime": from_date, "endTime": to_date},
            )
            result = []
            for d in data:
                result.append({
                    "ticket":  int(d.get("id", 0)),
                    "symbol":  d.get("symbol", ""),
                    "type":    d.get("type", ""),
                    "volume":  float(d.get("volume", 0)),
                    "price":   float(d.get("price", 0)),
                    "profit":  float(d.get("profit", 0)),
                    "time":    datetime.fromisoformat(
                        d.get("time", datetime.utcnow().isoformat())
                    ),
                })
            return result
        except Exception:
            return []

    # ─────────────────────────── SIMULATION FALLBACK ───────────────────

    def _sim_account(self) -> Dict:
        return {
            "login": 0, "balance": 10000.0, "equity": 10000.0,
            "margin": 0.0, "margin_free": 10000.0, "margin_level": 0.0,
            "profit": 0.0, "currency": "USD", "server": "MetaAPI-Demo",
            "name": "Remote Demo", "leverage": 100,
        }

    def _sim_ohlcv(self, symbol: str, bars: int) -> pd.DataFrame:
        np.random.seed(hash(symbol) % 2**31)
        dates = pd.date_range(end=datetime.now(), periods=bars, freq="1min")
        price = 1.10000 + np.cumsum(np.random.randn(bars) * 0.0001)
        return pd.DataFrame({
            "open":   price,
            "high":   price + np.abs(np.random.randn(bars) * 0.0003),
            "low":    price - np.abs(np.random.randn(bars) * 0.0003),
            "close":  price + np.random.randn(bars) * 0.0001,
            "volume": np.random.randint(100, 1000, bars).astype(float),
            "spread": np.full(bars, 1.5),
        }, index=dates)

    def _sim_tick(self, symbol: str) -> Dict:
        bid = 1.10000 + np.random.randn() * 0.0001
        return {
            "bid": bid, "ask": bid + 0.00015, "last": bid,
            "volume": 0, "time": datetime.now(), "spread": 1.5,
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
        log.info(f"[SIM-MetaAPI] ORDER {order_type.upper()} {volume} {symbol} @ {price:.5f} | Ticket: {ticket}")
        return {
            "success": True, "ticket": ticket, "price_executed": price,
            "retcode": 10009, "comment": "Simulated-MetaAPI", "simulated": True,
        }


def create_connection(config: dict):
    """
    Factory: returns MT5Connection (local) or MetaAPIBridge (remote/web)
    based on config['mt5']['mode'].
    """
    mode = config.get("mt5", {}).get("mode", "local").lower()

    if mode == "metaapi":
        log.info("Using MetaAPI bridge for remote MT5 connection")
        return MetaAPIBridge(config)

    # demo mode = local with no real MT5
    if mode == "demo":
        log.info("Running in demo/simulation mode (no MT5)")
        from .mt5_connection import MT5Connection
        demo_cfg = dict(config.get("mt5", {}))
        demo_cfg["login"] = 0  # Force simulation
        cfg = dict(config)
        cfg["mt5"] = demo_cfg
        return MT5Connection(cfg)

    # Default: local MT5
    from .mt5_connection import MT5Connection
    return MT5Connection(config)
