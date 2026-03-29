from __future__ import annotations

import asyncio
import inspect
from dataclasses import asdict, is_dataclass
from typing import Any, Awaitable, Callable, Dict, List, Optional, TypeVar

from pocketoption_connector.config import ConnectorSettings
from pocketoption_connector.exceptions import (
    ConnectorError,
    DependencyMissingError,
    UnsupportedFeatureError,
)

T = TypeVar("T")


def _load_backend():
    try:
        import pocketoptionapi_async as po  # type: ignore
    except ImportError as exc:  # pragma: no cover - environment specific
        raise DependencyMissingError(
            "Install dependencies: pip install -r requirements.txt "
            "(package name on PyPI: pocketoptionapi-async)."
        ) from exc
    return po


def run_async(coro: Awaitable[T]) -> T:
    """
    Run ``coro`` from synchronous code (notebooks or CLI).

    Applies ``nest_asyncio`` so Jupyter-style kernels can schedule the coroutine
    without manually juggling event loops.
    """
    import nest_asyncio

    nest_asyncio.apply()
    loop = asyncio.get_event_loop()
    return loop.run_until_complete(coro)


def _serialize(obj: Any) -> Any:
    if obj is None or isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, dict):
        return {k: _serialize(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_serialize(x) for x in obj]
    if is_dataclass(obj):
        return asdict(obj)
    for attr in ("model_dump", "dict"):
        fn = getattr(obj, attr, None)
        if callable(fn):
            try:
                return _serialize(fn())
            except TypeError:
                pass
    result: Dict[str, Any] = {}
    for attr in (
        "balance",
        "currency",
        "is_demo",
        "order_id",
        "status",
        "profit",
        "asset",
        "amount",
        "direction",
        "duration",
        "open",
        "high",
        "low",
        "close",
        "volume",
        "timestamp",
    ):
        if hasattr(obj, attr):
            result[attr] = _serialize(getattr(obj, attr))
    if result:
        return result
    return repr(obj)


class PocketOptionConnector:
    """
    Thin, documented facade over the community async client.

    Authentication: Pocket Option’s web session is represented by the **SSID** cookie.
    This is different from ``iqoptionapi``, which logs in with email and password against
    IQ Option’s flow. Email/password login for Pocket Option is **not** implemented here
    because there is no stable, documented public login API for third-party scripts.

    References:

    - PocketOptionAPI Async docs: https://chipadevteam.github.io/PocketOptionAPI/
    - Similar community project (IQ Option): https://github.com/iqoptionapi/iqoptionapi
    """

    def __init__(
        self,
        ssid: str,
        *,
        is_demo: bool = True,
        enable_logging: bool = False,
        client_factory: Optional[Callable[..., Any]] = None,
    ) -> None:
        self._po = _load_backend()
        self._ssid = ssid
        self._is_demo = is_demo
        self._enable_logging = enable_logging
        factory = client_factory or self._po.AsyncPocketOptionClient
        self._client = factory(
            ssid,
            is_demo=is_demo,
            enable_logging=enable_logging,
        )
        self._connected = False

    @classmethod
    def from_settings(cls, settings: ConnectorSettings, **kwargs: Any) -> "PocketOptionConnector":
        return cls(settings.ssid, is_demo=settings.is_demo, **kwargs)

    async def connect(self) -> bool:
        connect = self._client.connect
        result = connect()
        if inspect.isawaitable(result):
            result = await result
        self._connected = bool(result)
        return self._connected

    async def disconnect(self) -> None:
        disconnect = self._client.disconnect
        out = disconnect()
        if inspect.isawaitable(out):
            await out
        self._connected = False

    @property
    def is_connected(self) -> bool:
        return self._connected

    async def get_balance(self) -> Dict[str, Any]:
        self._require_connection()
        bal = await self._client.get_balance()
        return _serialize(bal)

    async def get_account_snapshot(self) -> Dict[str, Any]:
        """
        Aggregate lightweight account / session info for dashboards.

        Always includes balance; adds connection stats when the backend exposes them.
        """
        snapshot: Dict[str, Any] = {"balance": await self.get_balance()}
        stats_fn = getattr(self._client, "get_connection_stats", None)
        if callable(stats_fn):
            stats = stats_fn()
            if inspect.isawaitable(stats):
                stats = await stats
            snapshot["connection"] = _serialize(stats)
        return snapshot

    async def fetch_candles(
        self,
        asset: str,
        timeframe_seconds: int,
        *,
        count: int = 100,
        end_time: Any = None,
        as_dataframe: bool = False,
    ):
        """
        Historical / aggregated candles (not a tick-by-tick firehose).

        ``asset`` examples: ``\"EURUSD_otc\"`` (names match the web platform).
        """
        self._require_connection()
        if as_dataframe:
            fn = getattr(self._client, "get_candles_dataframe", None)
            if fn is None:
                raise UnsupportedFeatureError(
                    "get_candles_dataframe is not available in this pocketoptionapi-async version."
                )
            return await fn(asset, timeframe_seconds, count=count, end_time=end_time)
        candles = await self._client.get_candles(asset, timeframe_seconds, count=count, end_time=end_time)
        return [_serialize(c) for c in candles]

    async def place_order(
        self,
        asset: str,
        amount: float,
        direction: str,
        duration_seconds: int,
    ) -> Dict[str, Any]:
        """
        Place a binary option order (CALL/PUT).

        ``direction``: ``\"call\"`` or ``\"put\"`` (case-insensitive), or pass
        ``OrderDirection`` from ``pocketoptionapi_async`` if you import it yourself.
        """
        self._require_connection()
        order_direction = self._resolve_direction(direction)
        order = await self._client.place_order(
            asset=asset,
            amount=amount,
            direction=order_direction,
            duration=duration_seconds,
        )
        return _serialize(order)

    async def list_active_orders(self) -> List[Dict[str, Any]]:
        self._require_connection()
        orders = await self._client.get_active_orders()
        return [_serialize(o) for o in orders]

    async def check_order_result(self, order_id: Any) -> Optional[Dict[str, Any]]:
        self._require_connection()
        result = await self._client.check_order_result(order_id)
        if result is None:
            return None
        return _serialize(result)

    async def get_available_assets(self) -> List[str]:
        """
        Return tradable symbols when the backend exposes a discovery helper.

        If the installed ``pocketoptionapi-async`` build has no such method, this raises
        :class:`UnsupportedFeatureError` and you should copy symbols from the web terminal
        (for example ``EURUSD_otc``).
        """
        self._require_connection()
        for candidate in (
            "get_assets",
            "get_symbols",
            "list_assets",
            "get_available_assets",
        ):
            fn = getattr(self._client, candidate, None)
            if not callable(fn):
                continue
            raw = fn()
            if inspect.isawaitable(raw):
                raw = await raw
            if raw is None:
                continue
            if isinstance(raw, (list, tuple)):
                return [str(x) for x in raw]
            if isinstance(raw, dict):
                return [str(k) for k in raw.keys()]
        raise UnsupportedFeatureError(
            "Asset listing is not implemented by this pocketoptionapi-async build. "
            "Use symbol names from https://pocketoption.com/ (chart picker / OTC suffixes)."
        )

    async def list_tournaments(self) -> List[Dict[str, Any]]:
        raise UnsupportedFeatureError(
            "Tournaments are a web-only feature in practice. "
            "The community async client documented at "
            "https://chipadevteam.github.io/PocketOptionAPI/ does not expose tournament APIs. "
            "Automating tournament entry may also conflict with Pocket Option’s terms—verify locally."
        )

    async def get_trading_signals(self) -> List[Dict[str, Any]]:
        raise UnsupportedFeatureError(
            "Marketing/signal feeds inside Pocket Option are not part of the community API surface. "
            "For systematic trading you normally subscribe to candles and compute indicators yourself."
        )

    def _require_connection(self) -> None:
        if not self._connected:
            raise ConnectorError("Not connected. Await connect() first.")

    def _resolve_direction(self, direction: Any) -> Any:
        if direction is None:
            raise ValueError("direction is required")
        text = str(direction).strip().lower()
        enum = getattr(self._po, "OrderDirection", None)
        if enum is not None:
            if text in ("call", "up", "higher"):
                return enum.CALL
            if text in ("put", "down", "lower"):
                return enum.PUT
        return direction
