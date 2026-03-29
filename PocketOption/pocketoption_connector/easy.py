"""
High-level **synchronous** API: connect, read data, and trade with minimal boilerplate.

``PocketOption.session()`` resolves a session automatically:

- Uses ``POCKETOPTION_SSID`` when set.
- Otherwise signs in through the official web form via Playwright using
  ``POCKETOPTION_EMAIL`` / ``POCKETOPTION_PASSWORD`` (requires the ``[credentials]`` extra).
"""

from __future__ import annotations

import time
from types import TracebackType
from typing import Any, Dict, Iterator, List, Optional, Type, Union

from pocketoption_connector.client import PocketOptionConnector, run_async
from pocketoption_connector.config import ConnectorSettings, read_demo_from_env
from pocketoption_connector.credential_login import headless_from_env, resolve_ssid
from pocketoption_connector.exceptions import ConnectorError

Duration = Union[int, float, str]


def _duration_seconds(duration: Duration) -> int:
    if isinstance(duration, (int, float)):
        return int(duration)
    text = str(duration).strip().lower()
    if text.endswith("m") and text[:-1].isdigit():
        return int(text[:-1]) * 60
    if text.endswith("s") and text[:-1].isdigit():
        return int(text[:-1])
    if text.isdigit():
        return int(text)
    raise ValueError(
        f"Invalid duration {duration!r}. Use seconds (60) or strings like '1m', '5m', '30s'."
    )


def _maybe_load_dotenv(enabled: bool) -> None:
    if not enabled:
        return
    try:
        from dotenv import load_dotenv

        load_dotenv()
    except ImportError:
        pass


class _Session:
    """Context manager backing :meth:`PocketOption.session`."""

    def __init__(
        self,
        *,
        ssid: Optional[str] = None,
        email: Optional[str] = None,
        password: Optional[str] = None,
        demo: Optional[bool] = None,
        load_dotenv: bool = True,
        default_asset: Optional[str] = None,
        enable_logging: bool = False,
        allow_browser_login: bool = True,
        headless: Optional[bool] = None,
        login_url: Optional[str] = None,
    ) -> None:
        self._ssid_kw = ssid
        self._email_kw = email
        self._password_kw = password
        self._demo_kw = demo
        self._load_dotenv = load_dotenv
        self._default_asset = default_asset
        self._enable_logging = enable_logging
        self._allow_browser_login = allow_browser_login
        self._headless = headless
        self._login_url = login_url
        self._po: Optional[PocketOption] = None

    def __enter__(self) -> PocketOption:
        _maybe_load_dotenv(self._load_dotenv)
        explicit_ssid = (self._ssid_kw or "").strip()
        if explicit_ssid:
            ssid = explicit_ssid
            demo = self._demo_kw if self._demo_kw is not None else read_demo_from_env()
        elif self._allow_browser_login:
            h = self._headless if self._headless is not None else headless_from_env()
            ssid = resolve_ssid(
                email=self._email_kw,
                password=self._password_kw,
                load_dotenv=False,
                prefer_env_ssid=True,
                headless=h,
                login_url=self._login_url,
            )
            demo = self._demo_kw if self._demo_kw is not None else read_demo_from_env()
        else:
            settings = ConnectorSettings.from_env()
            ssid = settings.ssid
            demo = self._demo_kw if self._demo_kw is not None else settings.is_demo

        self._po = PocketOption(
            ssid,
            demo=demo,
            default_asset=self._default_asset,
            enable_logging=self._enable_logging,
        )
        self._po.connect()
        return self._po

    def __exit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc: Optional[BaseException],
        tb: Optional[TracebackType],
    ) -> None:
        if self._po is not None:
            self._po.close()
            self._po = None


class PocketOption:
    """
    Synchronous facade with fewer moving parts than :class:`PocketOptionConnector` + ``asyncio``.

    **Credential-first example** (``.env`` holds ``POCKETOPTION_EMAIL`` / ``POCKETOPTION_PASSWORD``)::

        from pocketoption_connector import PocketOption

        with PocketOption.session(default_asset=\"EURUSD_otc\") as po:
            print(po.balance)
            print(po.last_candle())

    **SSID-only example** — set ``POCKETOPTION_SSID`` instead; Playwright is not used.
    """

    def __init__(
        self,
        ssid: str,
        *,
        demo: bool = True,
        default_asset: Optional[str] = None,
        enable_logging: bool = False,
    ) -> None:
        self._default_asset = default_asset
        self._conn = PocketOptionConnector(
            ssid,
            is_demo=demo,
            enable_logging=enable_logging,
        )
        self._open = False

    @classmethod
    def session(
        cls,
        *,
        ssid: Optional[str] = None,
        email: Optional[str] = None,
        password: Optional[str] = None,
        demo: Optional[bool] = None,
        load_dotenv: bool = True,
        default_asset: Optional[str] = None,
        enable_logging: bool = False,
        allow_browser_login: bool = True,
        headless: Optional[bool] = None,
        login_url: Optional[str] = None,
    ) -> _Session:
        """
        Connect on enter and disconnect on exit.

        Resolution order when ``ssid`` is omitted:

        1. Environment variable ``POCKETOPTION_SSID``.
        2. Browser login with ``email``/``password`` arguments or
           ``POCKETOPTION_EMAIL`` / ``POCKETOPTION_PASSWORD`` (requires Playwright).
        """
        return _Session(
            ssid=ssid,
            email=email,
            password=password,
            demo=demo,
            load_dotenv=load_dotenv,
            default_asset=default_asset,
            enable_logging=enable_logging,
            allow_browser_login=allow_browser_login,
            headless=headless,
            login_url=login_url,
        )

    @classmethod
    def from_credentials(
        cls,
        email: str,
        password: str,
        *,
        demo: Optional[bool] = None,
        default_asset: Optional[str] = None,
        enable_logging: bool = False,
        headless: Optional[bool] = None,
        login_url: Optional[str] = None,
    ) -> PocketOption:
        """Connect immediately using an automated browser login (no SSID copy/paste)."""
        from pocketoption_connector.credential_login import obtain_ssid_via_browser

        h = headless if headless is not None else headless_from_env()
        ssid = obtain_ssid_via_browser(email, password, headless=h, login_url=login_url)
        effective_demo = demo if demo is not None else read_demo_from_env()
        po = cls(
            ssid,
            demo=effective_demo,
            default_asset=default_asset,
            enable_logging=enable_logging,
        )
        po.connect()
        return po

    @classmethod
    def from_env(
        cls,
        *,
        load_dotenv: bool = True,
        demo: Optional[bool] = None,
        default_asset: Optional[str] = None,
        enable_logging: bool = False,
        allow_browser_login: bool = True,
        headless: Optional[bool] = None,
        login_url: Optional[str] = None,
    ) -> PocketOption:
        """
        Build a connected client from environment variables.

        Uses ``POCKETOPTION_SSID`` when present; otherwise browser login via email/password env vars.
        """
        _maybe_load_dotenv(load_dotenv)
        if allow_browser_login:
            h = headless if headless is not None else headless_from_env()
            ssid = resolve_ssid(
                load_dotenv=False,
                prefer_env_ssid=True,
                headless=h,
                login_url=login_url,
            )
            effective_demo = demo if demo is not None else read_demo_from_env()
        else:
            settings = ConnectorSettings.from_env()
            ssid = settings.ssid
            effective_demo = demo if demo is not None else settings.is_demo
        po = cls(
            ssid,
            demo=effective_demo,
            default_asset=default_asset,
            enable_logging=enable_logging,
        )
        po.connect()
        return po

    def connect(self) -> PocketOption:
        ok = run_async(self._conn.connect())
        self._open = bool(ok)
        if not self._open:
            raise ConnectorError(
                "Connection failed. Refresh the SSID, confirm demo vs real, or retry browser login."
            )
        return self

    def close(self) -> None:
        if self._open:
            run_async(self._conn.disconnect())
            self._open = False

    def __enter__(self) -> PocketOption:
        if not self._open:
            self.connect()
        return self

    def __exit__(self, *args: Any) -> None:
        self.close()

    def _asset(self, asset: Optional[str]) -> str:
        a = asset or self._default_asset
        if not a:
            raise ValueError("Pass a symbol (e.g. 'EURUSD_otc') or set default_asset= when creating the client.")
        return a

    @property
    def balance(self) -> Dict[str, Any]:
        """Latest balance snapshot as a plain dict."""
        return run_async(self._conn.get_balance())

    @property
    def account_balance(self) -> Dict[str, Any]:
        """Alias of :attr:`balance` with a more explicit name."""
        return self.balance

    def account_snapshot(self) -> Dict[str, Any]:
        """Balance plus optional websocket stats when exposed by the backend."""
        return run_async(self._conn.get_account_snapshot())

    def candles(
        self,
        asset: Optional[str] = None,
        *,
        timeframe: int = 60,
        count: int = 100,
        as_dataframe: bool = False,
        end_time: Any = None,
    ):
        """OHLC candles. ``timeframe`` is expressed in seconds (``60`` == one minute)."""
        return run_async(
            self._conn.fetch_candles(
                self._asset(asset),
                timeframe,
                count=count,
                as_dataframe=as_dataframe,
                end_time=end_time,
            )
        )

    def last_candle(self, asset: Optional[str] = None, *, timeframe: int = 60) -> Any:
        """Return the most recent candle (``count=1`` under the hood)."""
        rows = self.candles(asset, timeframe=timeframe, count=1)
        return rows[-1] if rows else None

    def buy_call(
        self,
        asset: Optional[str] = None,
        amount: float = 1.0,
        duration: Duration = 60,
    ) -> Dict[str, Any]:
        """Open a CALL trade. ``duration`` accepts seconds or strings like ``\"1m\"``."""
        return self._place("call", asset, amount, duration)

    def buy_put(
        self,
        asset: Optional[str] = None,
        amount: float = 1.0,
        duration: Duration = 60,
    ) -> Dict[str, Any]:
        """Open a PUT trade."""
        return self._place("put", asset, amount, duration)

    def _place(
        self,
        side: str,
        asset: Optional[str],
        amount: float,
        duration: Duration,
    ) -> Dict[str, Any]:
        sec = _duration_seconds(duration)
        return run_async(
            self._conn.place_order(self._asset(asset), amount, side, sec),
        )

    def orders(self) -> List[Dict[str, Any]]:
        """Active orders."""
        return run_async(self._conn.list_active_orders())

    def check_order(self, order_id: Any) -> Optional[Dict[str, Any]]:
        """Fetch the latest state for a specific order id."""
        return run_async(self._conn.check_order_result(order_id))

    def wait_order(
        self,
        order_id: Any,
        *,
        poll_seconds: float = 2.0,
        timeout_seconds: float = 300.0,
    ) -> Optional[Dict[str, Any]]:
        """
        Poll until the reported ``status`` leaves the pending set or the timeout elapses.

        Status strings depend on the upstream client; treat this helper as best-effort.
        """
        deadline = time.monotonic() + timeout_seconds
        last: Optional[Dict[str, Any]] = None
        pending = {"pending", "open", "active", "new"}
        while time.monotonic() < deadline:
            last = self.check_order(order_id)
            if last is not None:
                st = last.get("status")
                if st is not None:
                    low = str(st).lower()
                    if low not in pending:
                        return last
            time.sleep(poll_seconds)
        return last

    def assets(self) -> List[str]:
        """Return symbols when the backend exposes them; otherwise use the web terminal."""
        return run_async(self._conn.get_available_assets())

    def stream_candles(
        self,
        asset: Optional[str] = None,
        *,
        timeframe: int = 60,
        interval_seconds: float = 5.0,
        max_updates: Optional[int] = None,
    ) -> Iterator[Any]:
        """Poll :meth:`last_candle` on a fixed interval (not a tick stream)."""
        n = 0
        while max_updates is None or n < max_updates:
            yield self.last_candle(asset, timeframe=timeframe)
            time.sleep(interval_seconds)
            n += 1

    def tournaments(self) -> Any:
        """Not available in the community transport; raises :class:`UnsupportedFeatureError`."""
        return run_async(self._conn.list_tournaments())

    def signals(self) -> Any:
        """Not available in the community transport; raises :class:`UnsupportedFeatureError`."""
        return run_async(self._conn.get_trading_signals())
