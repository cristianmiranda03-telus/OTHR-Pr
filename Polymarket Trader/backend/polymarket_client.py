"""
Polymarket CLOB API client.
Wraps the py-clob-client SDK and provides higher-level helpers.
Uses fresh get_settings() on each authenticated call so saved credentials apply immediately.
"""
from __future__ import annotations
import json
import logging
import asyncio
from typing import Optional

import httpx
from datetime import datetime, timedelta

from .config import get_settings
from .models import Portfolio, Position

logger = logging.getLogger(__name__)

GAMMA_BASE = "https://gamma-api.polymarket.com"
DATA_API_BASE = "https://data-api.polymarket.com"
CLOB_BASE  = "https://clob.polymarket.com"

USDC_DECIMALS = 1_000_000


def gamma_outcome_prices_list(m: dict) -> list:
    """Normalize outcomePrices from Gamma (list or JSON string)."""
    raw = m.get("outcomePrices")
    if raw is None:
        return []
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except Exception:
            return []
    return raw if isinstance(raw, list) else []


def flatten_markets_from_public_search(payload: dict) -> list[dict]:
    """Expand Gamma public-search JSON: events[].markets[] → flat market dicts with _event_slug."""
    out: list[dict] = []
    for ev in payload.get("events") or []:
        if not isinstance(ev, dict):
            continue
        ev_slug = (ev.get("slug") or "").strip()
        for m in ev.get("markets") or []:
            if not isinstance(m, dict):
                continue
            row = dict(m)
            if ev_slug:
                row["_event_slug"] = ev_slug
            out.append(row)
    return out


def _is_market_dead(m: dict) -> bool:
    """Return True if a market from Gamma is closed, resolved, or fully settled."""
    closed = m.get("closed")
    if closed is True or str(closed).lower() == "true":
        return True
    resolved = m.get("resolved")
    if resolved is True or str(resolved).lower() == "true":
        return True
    # Price at exactly 0.00 or 1.00 means fully resolved
    prices = gamma_outcome_prices_list(m)
    try:
        if prices:
            p = float(prices[0])
            if p <= 0.005 or p >= 0.995:
                return True
    except (ValueError, IndexError, TypeError):
        pass
    # Check the 'active' field from the response itself
    active_flag = m.get("active")
    if active_flag is False or str(active_flag).lower() == "false":
        return True
    return False


def _has_valid_polymarket_creds(settings) -> bool:
    """True if we have real API credentials (not placeholder or masked)."""
    # Prefer private key if available
    pk = (settings.polymarket_private_key or "").strip()
    if pk and "TU_" not in pk and "•" not in pk:
        return True
    # Fallback to API keys
    key = (settings.polymarket_api_key or "").strip()
    if not key or key == "TU_API_KEY_AQUI" or "•" in key:
        return False
    return bool(settings.polymarket_api_secret and settings.polymarket_api_passphrase)


class PolymarketClient:
    """Async client for Polymarket CLOB and Gamma API."""

    def __init__(self):
        self._http = httpx.AsyncClient(timeout=30.0)

    # ─────────────────────── Public Market Data ───────────────────────

    async def get_markets(
        self,
        category: Optional[str] = None,
        active: bool = True,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Fetch markets from Gamma API (no auth required).
        Adds closed=false to exclude resolved/settled markets.
        Non-numeric ``category`` values use public-search (Gamma ignores string ``tag``).
        """
        if category and not category.isdigit():
            try:
                raw = await self.fetch_merged_search_markets(
                    [category],
                    per_query_limit=max(limit + offset, 60),
                )
                filtered = [m for m in raw if not _is_market_dead(m)]
                return filtered[offset : offset + limit]
            except Exception as exc:
                logger.error("get_markets(search %r): %s", category, exc)
                return self._mock_markets(category)

        params: dict = {
            "limit": limit,
            "offset": offset,
            "active": str(active).lower(),
            "closed": "false",
        }
        if category and category.isdigit():
            params["tag_id"] = int(category)
        try:
            resp = await self._http.get(f"{GAMMA_BASE}/markets", params=params)
            resp.raise_for_status()
            raw = resp.json()
            # Post-filter: Gamma sometimes returns closed/resolved despite params
            filtered = []
            for m in raw:
                if _is_market_dead(m):
                    continue
                filtered.append(m)
            return filtered
        except Exception as exc:
            logger.error(f"get_markets error: {exc}")
            return self._mock_markets(category)

    async def get_market(self, market_id: str) -> Optional[dict]:
        try:
            resp = await self._http.get(f"{GAMMA_BASE}/markets/{market_id}")
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            logger.error(f"get_market({market_id}) error: {exc}")
            return None

    async def public_search(self, query: str, limit: int = 40) -> dict:
        """Gamma full-text search (returns events with nested markets)."""
        try:
            resp = await self._http.get(
                f"{GAMMA_BASE}/public-search",
                params={"q": query, "limit": min(max(limit, 1), 80)},
            )
            resp.raise_for_status()
            data = resp.json()
            return data if isinstance(data, dict) else {"events": []}
        except Exception as exc:
            logger.error("public_search(%r): %s", query, exc)
            return {"events": []}

    async def fetch_merged_search_markets(self, queries: list[str], per_query_limit: int = 40) -> list[dict]:
        """Run several public searches and dedupe by Gamma market id."""
        seen: set[str] = set()
        merged: list[dict] = []
        for q in queries:
            payload = await self.public_search(q, limit=per_query_limit)
            for m in flatten_markets_from_public_search(payload):
                mid = str(m.get("id", ""))
                if not mid or mid in seen:
                    continue
                seen.add(mid)
                merged.append(m)
        return merged

    async def get_orderbook(self, token_id: str) -> dict:
        try:
            resp = await self._http.get(f"{CLOB_BASE}/book", params={"token_id": token_id})
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            logger.error(f"get_orderbook error: {exc}")
            return {}

    # ─────────────────────── Leaderboard / Whales ────────────────────

    async def get_leaderboard(self, limit: int = 20) -> list[dict]:
        """Fetch trader leaderboard from Data API (v1/leaderboard)."""
        try:
            resp = await self._http.get(
                f"{DATA_API_BASE}/v1/leaderboard",
                params={
                    "limit": min(limit, 50),
                    "timePeriod": "ALL",
                    "orderBy": "PNL",
                    "category": "OVERALL",
                },
            )
            resp.raise_for_status()
            entries = resp.json()
            # Normalize to legacy shape for whale_watcher: address, rank, profit, winRate
            return [
                {
                    "address": e.get("proxyWallet", ""),
                    "rank": int(e.get("rank", i + 1)),
                    "profit": float(e.get("pnl", 0)),
                    "winRate": 0.0,  # Data API doesn't expose win rate
                    "vol": float(e.get("vol", 0)),
                }
                for i, e in enumerate(entries)
            ]
        except Exception as exc:
            logger.error(f"get_leaderboard error: {exc}")
            return self._mock_leaderboard()

    async def get_trader_positions(self, address: str) -> list[dict]:
        """Fetch current positions for a user from Data API (/positions).
        sizeThreshold=0 includes small positions; proxy wallet may differ from EOA.
        """
        try:
            resp = await self._http.get(
                f"{DATA_API_BASE}/positions",
                params={"user": address, "limit": 500, "sizeThreshold": 0},
            )
            resp.raise_for_status()
            raw = resp.json()
            # Normalize Data API position shape to CLOB-like: asset: { token_id, condition_id }, size, avgPrice, side
            out = []
            for p in raw:
                # Data API returns asset as token id string; conditionId camelCase
                token_id = p.get("asset") or p.get("token_id") or ""
                condition_id = p.get("conditionId") or p.get("condition_id") or ""
                size = float(p.get("size") or 0)
                if size <= 0:
                    continue
                out.append({
                    "asset": {"token_id": token_id, "condition_id": condition_id},
                    "size": size,
                    "avgPrice": float(p.get("avgPrice") or p.get("avg_price") or 0),
                    "side": p.get("outcome") or p.get("side") or "—",
                    # Preserve Data API fields so we don't lose P&L/value when CLOB midpoint fails
                    "_title": p.get("title") or p.get("question") or "",
                    "_slug": p.get("slug") or "",
                    "_eventSlug": p.get("eventSlug") or p.get("event_slug") or "",
                    "_curPrice": p.get("curPrice"),
                    "_currentValue": p.get("currentValue"),
                    "_cashPnl": p.get("cashPnl"),
                    "_percentPnl": p.get("percentPnl"),
                })
            return out
        except Exception as exc:
            logger.error(f"get_trader_positions error: {exc}")
            return []

    # ─────────────────────── Authenticated Operations ────────────────

    def _get_clob_client(self):
        """Build CLOB client from current settings (fresh credentials).
        When private key is set, match test.ipynb: ClobClient(host, key=..., chain_id=137)
        then set_api_creds(create_or_derive_api_creds()) only — mixing manual ApiCreds breaks L2.
        """
        from py_clob_client.client import ClobClient
        from py_clob_client.clob_types import ApiCreds

        s = get_settings()

        # Private key path — identical to working notebook flow
        pk = (s.polymarket_private_key or "").strip()
        if pk and "TU_" not in pk and "•" not in pk:
            # Polymarket holds USDC in a proxy (profile) wallet; balance_allowance without funder returns 0 for EOA-only
            proxy = (s.polymarket_proxy_wallet or "").strip()
            kwargs = dict(host=s.clob_base_url, key=pk, chain_id=137)
            if proxy and proxy.startswith("0x") and len(proxy) >= 42 and "•" not in proxy:
                # 1 = POLY_PROXY (Magic/email), 2 = GNOSIS_SAFE (browser wallet)
                sig = int(getattr(s, "polymarket_signature_type", 0) or 0)
                if sig not in (1, 2):
                    sig = 1
                kwargs["signature_type"] = sig
                kwargs["funder"] = proxy
                logger.info("CLOB client using funder (proxy) for balance/orders: %s", proxy[:10] + "…")
            client = ClobClient(**kwargs)
            client.set_api_creds(client.create_or_derive_api_creds())
            return client

        # Fallback: API key only (no L2 signer — balance/orders may still fail)
        creds = ApiCreds(
            api_key=s.polymarket_api_key,
            api_secret=s.polymarket_api_secret,
            api_passphrase=s.polymarket_api_passphrase,
        )
        client = ClobClient(s.clob_base_url, creds=creds)
        # L2 endpoints (e.g. get_balance_allowance) require set_api_creds to be called
        client.set_api_creds(creds)
        return client

    async def _market_info_for_token(self, token_id: str, condition_id: str = "") -> tuple[str, str, str, str]:
        """Resolve market question, outcome, category, and slug from Gamma API."""
        try:
            # Try by condition_id first (one market per condition)
            if condition_id:
                resp = await self._http.get(
                    f"{GAMMA_BASE}/markets",
                    params={"condition_id": condition_id, "limit": 1},
                )
                resp.raise_for_status()
                data = resp.json()
                if isinstance(data, list) and data:
                    m = data[0]
                    question = m.get("question") or m.get("title") or str(m.get("id", ""))
                    outcomes = m.get("outcomes") or ["Yes", "No"]
                    if isinstance(outcomes, str):
                        try:
                            outcomes = json.loads(outcomes)
                        except Exception:
                            outcomes = ["Yes", "No"]
                    if not isinstance(outcomes, list):
                        outcomes = ["Yes", "No"]
                    ids = m.get("clobTokenIds") or m.get("clob_token_ids") or []
                    if isinstance(ids, str):
                        try:
                            ids = json.loads(ids)
                        except Exception:
                            ids = []
                    idx = ids.index(token_id) if token_id and token_id in ids else 0
                    outcome = outcomes[idx] if idx < len(outcomes) else "—"
                    # Event slug for polymarket.com/event/{slug} — market slug alone often 404s
                    slug = m.get("slug") or ""
                    events = m.get("events") or []
                    if isinstance(events, list) and events:
                        ev = events[0] if isinstance(events[0], dict) else {}
                        slug = ev.get("slug") or ev.get("eventSlug") or slug
                    tags = m.get("tags") or []
                    category = (tags[0] if tags else None) or "Other"
                    return question, outcome, category, slug
            return f"Position {token_id[:14]}…", "—", "Other", ""
        except Exception as exc:
            logger.debug(f"Gamma market lookup: {exc}")
            return f"Position {token_id[:14]}…", "—", "Other", ""

    def _usdc_from_wei(self, v) -> float:
        """Balance API may return int or str."""
        if v is None:
            return 0.0
        try:
            return int(float(str(v))) / USDC_DECIMALS
        except (ValueError, TypeError):
            return 0.0

    async def get_portfolio(self) -> Portfolio:
        """Fetch real portfolio: balance + held positions (Data API) + open orders (CLOB get_orders), matching test.ipynb."""
        settings = get_settings()
        if not _has_valid_polymarket_creds(settings):
            logger.info("No valid Polymarket API credentials — returning demo portfolio.")
            return self._mock_portfolio()

        now = datetime.utcnow()
        open_orders: list[dict] = []

        try:
            client = self._get_clob_client()

            # Balance: get_balance_allowance (requires L2 — satisfied when private key + derive creds)
            from py_clob_client.clob_types import BalanceAllowanceParams, AssetType
            balance_usdc = 0.0
            try:
                balance_result = await asyncio.to_thread(
                    client.get_balance_allowance,
                    BalanceAllowanceParams(asset_type=AssetType.COLLATERAL),
                )
                balance_usdc = self._usdc_from_wei(balance_result.get("balance"))
            except Exception as bal_exc:
                logger.info("get_balance_allowance failed (balance stays 0): %s", bal_exc)
            # If still 0 with proxy set, funder may need signature_type=2 (GNOSIS_SAFE) — user can set proxy and retry
            if balance_usdc == 0.0 and (get_settings().polymarket_proxy_wallet or "").strip():
                logger.info(
                    "Balance is 0 with proxy_wallet set — if you use browser wallet, try signature_type=2 in client init."
                )

            # Open orders on the book — same as test.ipynb: client.get_orders(OpenOrderParams())
            try:
                from py_clob_client.clob_types import OpenOrderParams
                orders_raw = await asyncio.to_thread(
                    client.get_orders, OpenOrderParams()
                )
                if isinstance(orders_raw, list):
                    for o in orders_raw:
                        if isinstance(o, dict):
                            open_orders.append({
                                "id": o.get("id", ""),
                                "side": o.get("side", ""),
                                "price": o.get("price"),
                                "size_remaining": o.get("size-remaining") or o.get("size_remaining") or o.get("original_size"),
                                "token_id": o.get("asset_id") or o.get("token_id") or "",
                            })
            except Exception as ord_exc:
                logger.debug("get_orders: %s", ord_exc)

            # Held positions: ONLY Data API /positions — never use get_trades() (trades are history, not holdings)
            positions_raw: list[dict] = []
            positions_note: str | None = None
            try:
                s = get_settings()
                proxy = (s.polymarket_proxy_wallet or "").strip()
                if "•" in proxy:
                    proxy = ""
                eoa = await asyncio.to_thread(client.get_address) or ""
                eoa = eoa.strip() if eoa else ""

                # Collect from proxy first (Polymarket holds positions on profile/proxy wallet)
                seen_token: set[str] = set()

                async def _add_from_address(addr: str) -> None:
                    nonlocal positions_raw
                    if not addr or addr in ("",) or "•" in addr:
                        return
                    rows = await self.get_trader_positions(addr)
                    for row in rows:
                        tid = (row.get("asset") or {}).get("token_id") or ""
                        cid = (row.get("asset") or {}).get("condition_id") or ""
                        key = tid or cid or str(id(row))
                        if key in seen_token:
                            continue
                        seen_token.add(key)
                        positions_raw.append(row)

                if proxy:
                    await _add_from_address(proxy)
                if eoa and eoa.lower() != (proxy or "").lower():
                    await _add_from_address(eoa)

                if not positions_raw:
                    if not proxy:
                        positions_note = (
                            "Go to the Config tab → Polymarket API → Profile (Proxy) Address and paste your "
                            "Polymarket profile address (find it on polymarket.com in the profile dropdown). "
                            "Positions are tied to that address, not your signer wallet."
                        )
                    else:
                        positions_note = (
                            "No open positions for the configured proxy_wallet. "
                            "Double-check the address on polymarket.com → Profile."
                        )
                    logger.info("Data API /positions empty for proxy=%s eoa=%s — not using trade history as positions", bool(proxy), bool(eoa))
            except Exception as e:
                logger.info("positions fetch error: %s", e)
                positions_note = f"Positions request failed: {e!s}"

            def _f(x, default=0.0) -> float:
                try:
                    if x is None:
                        return default
                    return float(x)
                except (TypeError, ValueError):
                    return default

            positions = []
            for p in positions_raw:
                asset = p.get("asset") or {}
                token_id = asset.get("token_id") or ""
                condition_id = asset.get("condition_id") or ""
                size = float(p.get("size") or 0)
                avg_price = float(p.get("avgPrice") or p.get("avg_price") or 0)
                if size <= 0:
                    continue

                # Current price: Data API curPrice > CLOB midpoint > avg
                current_price = avg_price
                if p.get("_curPrice") is not None:
                    current_price = _f(p.get("_curPrice"), avg_price)
                elif token_id:
                    try:
                        current_price = float(await asyncio.to_thread(client.get_midpoint, token_id))
                    except Exception:
                        pass

                cost_basis = size * avg_price
                # P&L: prefer Data API cashPnl when present (authoritative)
                if p.get("_cashPnl") is not None:
                    pnl = _f(p.get("_cashPnl"))
                    current_value = cost_basis + pnl
                    if p.get("_percentPnl") is not None and cost_basis > 0:
                        pnl_pct = _f(p.get("_percentPnl"))
                    else:
                        pnl_pct = (pnl / cost_basis * 100) if cost_basis > 0 else 0.0
                elif p.get("_currentValue") is not None:
                    current_value = _f(p.get("_currentValue"))
                    pnl = current_value - cost_basis
                    pnl_pct = (pnl / cost_basis * 100) if cost_basis > 0 else 0.0
                else:
                    current_value = size * current_price
                    pnl = current_value - cost_basis
                    pnl_pct = (pnl / cost_basis * 100) if cost_basis > 0 else 0.0

                question, outcome, category, slug = await self._market_info_for_token(token_id, condition_id)
                if (p.get("_title") or "").strip():
                    question = p["_title"].strip()
                # Prefer Data API outcome (Yes/No/…); ignore BUY/SELL if ever present
                api_outcome = (p.get("side") or "").strip()
                if api_outcome and api_outcome.upper() not in ("BUY", "SELL"):
                    outcome = api_outcome
                if not outcome or outcome == "—" or outcome.startswith("["):
                    outcome = "—"
                # Working Polymarket links use event slug; Data API often has eventSlug
                url_slug = (p.get("_eventSlug") or p.get("_slug") or slug or "").strip()
                if url_slug:
                    market_url = f"https://polymarket.com/event/{url_slug}"
                elif condition_id:
                    # Fallback: Gamma search by condition_id is not a direct link; use market slug from Gamma only
                    market_url = f"https://polymarket.com/event/{slug}" if slug else None
                else:
                    market_url = None

                positions.append(Position(
                    market_id=token_id or condition_id,
                    market_question=question,
                    outcome=outcome,
                    size=size,
                    avg_price=avg_price,
                    current_price=current_price,
                    pnl=pnl,
                    pnl_pct=pnl_pct,
                    category=category,
                    market_url=market_url,
                ))

            total_val = sum(pos.size * pos.current_price for pos in positions)
            total_pnl = sum(pos.pnl for pos in positions)
            total_cost = sum(pos.size * pos.avg_price for pos in positions)
            total_pnl_pct = (total_pnl / total_cost * 100) if total_cost > 0 else 0.0

            return Portfolio(
                balance_usdc=round(balance_usdc, 2),
                total_positions_value=round(total_val, 2),
                total_pnl=round(total_pnl, 2),
                total_pnl_pct=round(total_pnl_pct, 2),
                positions=positions,
                open_orders=open_orders,
                last_updated=now,
                source="live",
                positions_note=positions_note,
            )
        except Exception as exc:
            logger.exception("get_portfolio error")
            return self._mock_portfolio()

    async def place_order(
        self,
        token_id: str,
        side: str,
        price: float,
        size: float,
    ) -> dict:
        """Place a limit order. Returns order receipt dict."""
        s = (side or "").strip().upper()
        if s not in ("BUY", "SELL"):
            return {"status": "error", "error": f"side must be BUY or SELL, got {side!r}"}

        if not _has_valid_polymarket_creds(get_settings()):
            logger.warning("No valid Polymarket API key — order simulated.")
            return {"status": "simulated", "token_id": token_id, "side": s, "price": price, "size": size}
        try:
            from py_clob_client.clob_types import OrderArgs, OrderType

            client = self._get_clob_client()
            order_args = OrderArgs(token_id=token_id, price=price, size=size, side=s)
            signed = await asyncio.to_thread(client.create_order, order_args)
            receipt = await asyncio.to_thread(client.post_order, signed, OrderType.GTC)
            return receipt
        except Exception as exc:
            logger.exception("place_order error")
            return {"status": "error", "error": str(exc)}

    # ──────────────────────────── Mocks ──────────────────────────────

    def _mock_markets(self, category: Optional[str] = None) -> list[dict]:
        """Demo data when API is unreachable."""
        now = datetime.utcnow()
        return [
            {
                "id": f"mock-{category or 'general'}-001",
                "slug": f"mock-{category or 'general'}-event-x",
                "question": f"[DEMO] Will {category or 'event'} X happen by end of 2025?",
                "outcomes": ["Yes", "No"],
                "outcomePrices": ["0.65", "0.35"],
                "volume": 150000,
                "liquidity": 45000,
                "active": True,
                "endDate": (now + timedelta(days=14)).isoformat() + "Z",
                "tags": [category or "general"],
            },
            {
                "id": f"mock-{category or 'general'}-002",
                "slug": f"mock-{category or 'general'}-event-y",
                "question": f"[DEMO] Will {category or 'event'} Y exceed target?",
                "outcomes": ["Yes", "No"],
                "outcomePrices": ["0.42", "0.58"],
                "volume": 89000,
                "liquidity": 22000,
                "active": True,
                "endDate": (now + timedelta(days=3)).isoformat() + "Z",
                "tags": [category or "general"],
            },
        ]

    def _mock_leaderboard(self) -> list[dict]:
        return [
            {"address": "0xDEMO1", "rank": 1, "profit": 85000, "winRate": 0.82, "trades": 312},
            {"address": "0xDEMO2", "rank": 2, "profit": 62000, "winRate": 0.75, "trades": 245},
            {"address": "0xDEMO3", "rank": 3, "profit": 47000, "winRate": 0.71, "trades": 198},
        ]

    def _mock_portfolio(self) -> Portfolio:
        return Portfolio(
            open_orders=[],
            balance_usdc=1000.0,
            total_positions_value=350.0,
            total_pnl=42.50,
            total_pnl_pct=12.14,
            source="demo",
            last_updated=datetime.utcnow(),
            positions=[
                Position(
                    market_id="mock-politics-001",
                    market_question="[DEMO] Will candidate X win?",
                    outcome="Yes",
                    size=50.0,
                    avg_price=0.62,
                    current_price=0.68,
                    pnl=3.0,
                    pnl_pct=9.68,
                    category="Politics",
                    market_url="https://polymarket.com",
                ),
            ],
        )

    async def close(self):
        await self._http.aclose()


polymarket_client = PolymarketClient()
