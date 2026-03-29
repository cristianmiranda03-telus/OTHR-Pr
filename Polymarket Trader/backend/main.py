"""
FastAPI application — REST endpoints + WebSocket hub.
"""
from __future__ import annotations
import asyncio
import configparser
import logging
from contextlib import asynccontextmanager
from pathlib import Path
from datetime import datetime, timezone, timedelta
import json as _json

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .config import get_settings, Settings
from .models import (
    AgentInfo, AppConfig, EventEvaluation, Investigation, OpportunityEntry,
    Portfolio, PositionAdvice, Suggestion, SuggestionAction, SuggestionStatus,
    StrategyReport, WsEventType, ApiResponse,
)
from .websocket_manager import ws_manager
from .polymarket_client import polymarket_client

logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).parent.parent
CONFIG_PATH = BASE_DIR / "config.ini"

# ─── Shared in-memory state ───────────────────────────────────────────
_agents: dict[str, AgentInfo] = {}
_suggestions: dict[str, Suggestion] = {}
_investigations: dict[str, Investigation] = {}
_strategy_reports: dict[str, StrategyReport] = {}
_event_evaluations: dict[str, EventEvaluation] = {}
_position_advice: dict[str, PositionAdvice] = {}
_opportunities: dict[str, OpportunityEntry] = {}
_orchestrator_task: asyncio.Task | None = None


# ─────────────────────────── Lifespan ────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _orchestrator_task
    logger.info("Starting Polymarket Trader backend...")
    _orchestrator_task = asyncio.create_task(_start_orchestrator())
    yield
    if _orchestrator_task:
        _orchestrator_task.cancel()
    await polymarket_client.close()
    logger.info("Backend shutdown complete.")


async def _start_orchestrator():
    await asyncio.sleep(1)
    from .agents.orchestrator_agent import OrchestratorAgent
    orchestrator = OrchestratorAgent(
        agent_registry=_agents,
        suggestion_store=_suggestions,
        investigation_store=_investigations,
        strategy_store=_strategy_reports,
        evaluation_store=_event_evaluations,
        advice_store=_position_advice,
        opportunity_store=_opportunities,
        ws_manager=ws_manager,
        polymarket_client=polymarket_client,
    )
    await orchestrator.run()


# ─────────────────────────── App Setup ───────────────────────────────

app = FastAPI(
    title="Polymarket Trader API",
    description="Multi-agent prediction market trading terminal",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─────────────────────────── Config ──────────────────────────────────

@app.get("/api/config", response_model=ApiResponse, tags=["Config"])
async def get_config():
    """Return current config with sensitive values partially masked."""
    s = get_settings()

    def mask(val: str) -> str:
        if not val or len(val) < 6:
            return val
        return val[:4] + "•" * (len(val) - 8) + val[-4:]

    cfg = AppConfig(
        polymarket_api_key=mask(s.polymarket_api_key),
        polymarket_api_secret=mask(s.polymarket_api_secret),
        polymarket_api_passphrase=mask(s.polymarket_api_passphrase),
        polymarket_private_key=mask(s.polymarket_private_key),
        polymarket_proxy_wallet=mask(s.polymarket_proxy_wallet) if s.polymarket_proxy_wallet else "",
        fuelxi_api_url=s.fuelxi_api_url,
        fuelxi_api_key=mask(s.fuelxi_api_key),
        fuelxi_model=s.fuelxi_model,
        llm_provider=s.llm_provider,
        openai_api_key=mask(s.openai_api_key),
        openai_model=s.openai_model,
        tavily_api_key=mask(s.tavily_api_key),
        update_interval=s.update_interval,
        min_confidence=s.min_confidence,
        max_parallel_agents=s.max_parallel_agents,
    )
    return ApiResponse(data=cfg)


@app.post("/api/config", response_model=ApiResponse, tags=["Config"])
async def update_config(cfg: AppConfig):
    """
    Persist configuration changes to config.ini.
    Only non-masked (non '•') values are written.
    Polymarket credentials take effect immediately (no restart needed for portfolio).
    """
    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)

    def _set(section: str, key: str, value: str):
        if "•" in str(value):
            return
        if not config.has_section(section):
            config.add_section(section)
        config.set(section, key, str(value))

    _set("polymarket_api", "api_key",        cfg.polymarket_api_key)
    _set("polymarket_api", "api_secret",     cfg.polymarket_api_secret)
    _set("polymarket_api", "api_passphrase", cfg.polymarket_api_passphrase)
    _set("polymarket_api", "private_key",    cfg.polymarket_private_key)
    _set("polymarket_api", "proxy_wallet",   cfg.polymarket_proxy_wallet)
    _set("fuelxi",  "api_url",   cfg.fuelxi_api_url)
    _set("fuelxi",  "api_key",   cfg.fuelxi_api_key)
    _set("fuelxi",  "model",     cfg.fuelxi_model)
    _set("llm",     "provider",  cfg.llm_provider)
    _set("openai",  "api_key",   cfg.openai_api_key)
    _set("openai",  "model",     cfg.openai_model)
    _set("search",  "tavily_api_key", cfg.tavily_api_key)
    _set("app_settings", "update_interval_seconds", str(cfg.update_interval))
    _set("app_settings", "min_confidence",          str(cfg.min_confidence))
    _set("app_settings", "max_parallel_agents",     str(cfg.max_parallel_agents))

    with open(CONFIG_PATH, "w") as f:
        config.write(f)

    # Bust the settings cache so new values are picked up immediately
    get_settings.cache_clear()

    # Hot-reload Polymarket credentials so the portfolio refreshes without restart
    new_settings = get_settings()
    if "•" not in cfg.polymarket_api_key and "•" not in cfg.polymarket_private_key:
        import os
        os.environ["POLYMARKET_API_KEY"]        = cfg.polymarket_api_key
        os.environ["POLYMARKET_API_SECRET"]     = cfg.polymarket_api_secret
        os.environ["POLYMARKET_API_PASSPHRASE"] = cfg.polymarket_api_passphrase
        os.environ["POLYMARKET_PRIVATE_KEY"]    = cfg.polymarket_private_key
    if "•" not in cfg.polymarket_proxy_wallet:
        import os
        os.environ["POLYMARKET_PROXY_WALLET"]   = cfg.polymarket_proxy_wallet or ""

    return ApiResponse(
        message="Configuration saved. Polymarket credentials active immediately. Restart to apply LLM key changes.",
        data={"requires_restart": bool(cfg.fuelxi_api_key and "•" not in cfg.fuelxi_api_key)}
    )


# ─────────────────────────── Agents ──────────────────────────────────

@app.get("/api/agents", response_model=ApiResponse, tags=["Agents"])
async def get_agents():
    return ApiResponse(data=list(_agents.values()))


# ─────────────────────────── Investigations ──────────────────────────

@app.get("/api/investigations", response_model=ApiResponse, tags=["Analysis"])
async def get_investigations(limit: int = 50):
    """Return most recent market investigations by all agents."""
    items = sorted(
        _investigations.values(),
        key=lambda x: x.started_at,
        reverse=True,
    )[:limit]
    return ApiResponse(data=items)


# ─────────────────────────── Strategies ──────────────────────────────

@app.get("/api/strategies", response_model=ApiResponse, tags=["Strategies"])
async def get_strategies():
    """Return strategy reports generated by StrategyScoutAgent."""
    items = sorted(
        _strategy_reports.values(),
        key=lambda x: x.created_at,
        reverse=True,
    )
    return ApiResponse(data=items)


# ─────────────────────────── Events (Listing + Expiry Filters) ───────

@app.get("/api/events", response_model=ApiResponse, tags=["Events"])
async def get_events(
    term: str | None = None,
    category: str | None = None,
    limit: int = 50,
):
    """
    Fetch open events from Polymarket with expiration filters.
    term: 'short' (<7d), 'medium' (7-90d), 'long' (90-365d), or None (all up to 1 year).
    Only returns truly active, non-resolved, non-expired markets.
    """
    from dateutil import parser as dateparser
    from .polymarket_client import _is_market_dead

    markets = await polymarket_client.get_markets(
        category=category,
        active=True,
        limit=min(limit * 2, 200),  # over-fetch to compensate for filtering
    )

    now = datetime.now(timezone.utc)
    max_horizon = now.replace(year=now.year + 1)

    enriched = []
    for m in markets:
        # Double-check: skip anything closed/resolved/settled
        if _is_market_dead(m):
            continue

        end_date = None
        for field in ("endDate", "end_date", "resolutionDate", "endDateIso"):
            raw = m.get(field)
            if raw:
                try:
                    dt = dateparser.parse(str(raw))
                    if dt and dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    end_date = dt
                    break
                except Exception:
                    pass

        # Skip expired or too far out
        if end_date and end_date < now:
            continue
        if end_date and end_date > max_horizon:
            continue
        # If no end_date at all, skip — we can't reliably determine if it's active
        if end_date is None:
            continue

        days_left = (end_date - now).days

        if term == "short" and days_left > 7:
            continue
        if term == "medium" and (days_left <= 7 or days_left > 90):
            continue
        if term == "long" and days_left <= 90:
            continue

        outcomes = m.get("outcomes", ["Yes", "No"])
        prices_raw = m.get("outcomePrices", [])
        try:
            yes_price = float(prices_raw[0]) if prices_raw else 0.5
        except (ValueError, IndexError):
            yes_price = 0.5

        # Skip fully resolved prices that slipped through
        if yes_price <= 0.005 or yes_price >= 0.995:
            continue

        slug = m.get("slug") or m.get("conditionId") or m.get("id", "")
        tags = m.get("tags") or []

        enriched.append({
            "id": m.get("id", ""),
            "question": m.get("question", ""),
            "outcomes": outcomes,
            "yes_price": yes_price,
            "volume": float(m.get("volume", 0) or 0),
            "liquidity": float(m.get("liquidity", 0) or 0),
            "end_date": end_date.isoformat(),
            "days_left": days_left,
            "category": tags[0] if tags else "general",
            "market_url": f"https://polymarket.com/event/{slug}" if slug else None,
        })

        if len(enriched) >= limit:
            break

    enriched.sort(key=lambda e: e.get("days_left") or 9999)
    return ApiResponse(data=enriched)


# ─────────────────────────── Event Evaluations ───────────────────────

@app.get("/api/evaluations", response_model=ApiResponse, tags=["Advisory"])
async def get_evaluations():
    items = sorted(_event_evaluations.values(), key=lambda x: x.created_at, reverse=True)
    return ApiResponse(data=items)


# ─────────────────────────── Position Advice ─────────────────────────

@app.get("/api/advice", response_model=ApiResponse, tags=["Advisory"])
async def get_advice():
    items = sorted(_position_advice.values(), key=lambda x: x.created_at, reverse=True)
    return ApiResponse(data=items)


# ─────────────────────────── Opportunity Rankings ────────────────────

@app.get("/api/opportunities", response_model=ApiResponse, tags=["Advisory"])
async def get_opportunities():
    items = sorted(_opportunities.values(), key=lambda x: x.priority_rank)
    return ApiResponse(data=items)


# ─────────────────────────── Suggestions ─────────────────────────────

@app.get("/api/suggestions", response_model=ApiResponse, tags=["Suggestions"])
async def get_suggestions(status: str | None = None, category: str | None = None):
    from datetime import timedelta

    now = datetime.now(timezone.utc)
    suggestions = list(_suggestions.values())

    # Max age for pending signals without a known end_date
    MAX_STALE_HOURS = 48

    def _is_valid(s):
        # Always show non-pending for history
        if s.status != SuggestionStatus.PENDING:
            return True

        # If end_date is set, check it hasn't expired
        if s.end_date:
            end = s.end_date
            if end.tzinfo is None:
                end = end.replace(tzinfo=timezone.utc)
            if end <= now:
                return False

        # If no end_date, drop if signal is stale (older than MAX_STALE_HOURS)
        if not s.end_date:
            created = s.created_at
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
            if (now - created) > timedelta(hours=MAX_STALE_HOURS):
                return False

        # Drop if price was at settled level (0 or 1)
        if s.price_at_discovery <= 0.005 or s.price_at_discovery >= 0.995:
            return False

        return True

    suggestions = [s for s in suggestions if _is_valid(s)]

    if status:
        suggestions = [s for s in suggestions if s.status.value == status]
    if category:
        suggestions = [s for s in suggestions if s.category.value == category]

    def _sort_key(s):
        if s.status == SuggestionStatus.PENDING and s.end_date:
            end = s.end_date
            if end.tzinfo is None:
                end = end.replace(tzinfo=timezone.utc)
            return (0, end)
        created = s.created_at
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        return (1, created)

    suggestions.sort(key=_sort_key)
    return ApiResponse(data=suggestions)


@app.post("/api/suggestions/approve/{suggestion_id}", response_model=ApiResponse, tags=["Suggestions"])
async def approve_suggestion(suggestion_id: str, action: SuggestionAction | None = None):
    suggestion = _suggestions.get(suggestion_id)
    if not suggestion:
        raise HTTPException(status_code=404, detail="Suggestion not found")
    if suggestion.status != SuggestionStatus.PENDING:
        raise HTTPException(status_code=400, detail=f"Suggestion is already {suggestion.status.value}")

    suggestion.status = SuggestionStatus.APPROVED
    error_detail = None
    try:
        amount = (action.amount_usdc if action else None) or 10.0
        receipt = await polymarket_client.place_order(
            token_id=suggestion.market_id,
            side="BUY" if suggestion.direction.value == "BUY" else "SELL",
            price=suggestion.price_at_discovery,
            size=amount,
        )

        # Check if the receipt signals an error (place_order returns dict with status)
        receipt_status = str(receipt.get("status", "")).lower()
        if receipt_status == "error":
            suggestion.status = SuggestionStatus.FAILED
            error_detail = receipt.get("error", "Order rejected by exchange")
            suggestion.execution_tx = None
        elif receipt_status == "simulated":
            suggestion.status = SuggestionStatus.EXECUTED
            suggestion.execution_tx = f"SIMULATED — {amount} USDC {suggestion.direction.value} @ {suggestion.price_at_discovery:.3f}"
        else:
            suggestion.status = SuggestionStatus.EXECUTED
            suggestion.execution_tx = (
                receipt.get("orderID")
                or receipt.get("id")
                or receipt.get("transactionsHashes", [None])[0]
                or f"OK — {amount} USDC"
            )
    except Exception as exc:
        suggestion.status = SuggestionStatus.FAILED
        error_detail = str(exc)
    finally:
        suggestion.updated_at = datetime.utcnow()
        await ws_manager.broadcast(WsEventType.SUGGESTION_UPDATE, suggestion.model_dump())

    if suggestion.status == SuggestionStatus.FAILED:
        raise HTTPException(status_code=500, detail=error_detail or "Order execution failed")

    return ApiResponse(data=suggestion, message="Order executed successfully")


@app.post("/api/suggestions/reject/{suggestion_id}", response_model=ApiResponse, tags=["Suggestions"])
async def reject_suggestion(suggestion_id: str):
    suggestion = _suggestions.get(suggestion_id)
    if not suggestion:
        raise HTTPException(status_code=404, detail="Suggestion not found")
    if suggestion.status != SuggestionStatus.PENDING:
        raise HTTPException(status_code=400, detail=f"Suggestion is already {suggestion.status.value}")

    suggestion.status = SuggestionStatus.REJECTED
    suggestion.updated_at = datetime.utcnow()
    await ws_manager.broadcast(WsEventType.SUGGESTION_UPDATE, suggestion.model_dump())
    return ApiResponse(data=suggestion, message="Suggestion rejected")


# ─────────────────────────── Bitcoin Live ────────────────────────────

BTC_KEYWORDS = [
    "bitcoin", "btc", "$100k", "$90k", "$80k", "$70k", "$60k", "$50k", "satoshi",
    "btc/usdt", "binance",
]


def _btc_market_text(m: dict) -> str:
    return " ".join([
        str(m.get("question") or ""),
        str(m.get("description") or ""),
        str(m.get("groupItemTitle") or ""),
    ]).lower()


def _gamma_yes_price_from_market(m: dict) -> float:
    from .polymarket_client import gamma_outcome_prices_list
    prices = gamma_outcome_prices_list(m)
    try:
        return float(prices[0]) if prices else 0.5
    except (ValueError, IndexError, TypeError):
        return 0.5


def _gamma_first_token_id(m: dict) -> str:
    token_ids = m.get("clobTokenIds") or m.get("clob_token_ids") or []
    if isinstance(token_ids, str):
        try:
            token_ids = _json.loads(token_ids)
        except Exception:
            token_ids = []
    return str(token_ids[0]) if token_ids else ""


def _polymarket_market_url(m: dict) -> str | None:
    ev = (m.get("_event_slug") or "").strip()
    slug = ev or (m.get("slug") or "").strip()
    if not slug:
        cid = m.get("conditionId") or m.get("condition_id")
        if cid:
            slug = str(cid)
    if slug:
        return f"https://polymarket.com/event/{slug}"
    return None


def _gamma_volume_liquidity(m: dict) -> tuple[float, float]:
    try:
        v = float(m.get("volumeNum", m.get("volume", 0)) or 0)
    except (TypeError, ValueError):
        v = 0.0
    try:
        lq = float(m.get("liquidityNum", m.get("liquidity", 0)) or 0)
    except (TypeError, ValueError):
        lq = 0.0
    return v, lq


@app.get("/api/bitcoin-live", response_model=ApiResponse, tags=["Bitcoin"])
async def get_bitcoin_live_markets(
    max_days: float = 7.0,
    limit: int = 25,
):
    """
    Fetch live Bitcoin-related prediction markets expiring within max_days.
    Sorted by soonest expiry first.
    Uses Gamma public-search (get_markets(tag=crypto) does not work — API expects tag_id).
    """
    from dateutil import parser as dateparser
    from .polymarket_client import _is_market_dead

    markets = await polymarket_client.fetch_merged_search_markets(
        ["bitcoin", "btc", "btc usdt"],
        per_query_limit=50,
    )

    now = datetime.now(timezone.utc)
    cutoff = now + timedelta(days=max_days)

    btc_markets = []
    for m in markets:
        if _is_market_dead(m):
            continue

        text = _btc_market_text(m)
        if not any(kw in text for kw in BTC_KEYWORDS):
            continue

        end_date = None
        for field in ("endDate", "end_date", "resolutionDate", "endDateIso"):
            raw_val = m.get(field)
            if raw_val:
                try:
                    dt = dateparser.parse(str(raw_val))
                    if dt and dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    end_date = dt
                    break
                except Exception:
                    pass

        if not end_date or end_date < now or end_date > cutoff:
            continue

        yes_price = _gamma_yes_price_from_market(m)

        if yes_price <= 0.005 or yes_price >= 0.995:
            continue

        hours_left = (end_date - now).total_seconds() / 3600
        days_left = hours_left / 24

        token_id = _gamma_first_token_id(m)
        vol, liq = _gamma_volume_liquidity(m)

        btc_markets.append({
            "id": m.get("id", ""),
            "question": m.get("question", ""),
            "yes_price": yes_price,
            "volume": vol,
            "liquidity": liq,
            "end_date": end_date.isoformat(),
            "days_left": round(days_left, 2),
            "hours_left": round(hours_left, 1),
            "market_url": _polymarket_market_url(m),
            "token_id": token_id or m.get("id", ""),
        })

    btc_markets.sort(key=lambda x: x["hours_left"])
    sliced = btc_markets[:limit]
    hint = ""
    if not sliced:
        hint = f"Sin mercados Bitcoin activos en los próximos {max_days} días. Prueba ampliar el rango (14D/30D)."
    return ApiResponse(data=sliced, message=hint)


class BitcoinAnalyzeRequest(BaseModel):
    market_ids: list[str] = Field(default_factory=list)
    max_days: float = 7.0


@app.post("/api/bitcoin-analyze", response_model=ApiResponse, tags=["Bitcoin"])
async def analyze_bitcoin_markets(request: BitcoinAnalyzeRequest):
    """
    Run fast parallel 3-agent analysis on Bitcoin prediction markets.
    Agents: PriceSignal + SentimentSignal + MomentumStats (all in parallel per market).
    Returns scored signals with direction, win probability, and suggested trade size.
    """
    from dateutil import parser as dateparser
    from .polymarket_client import _is_market_dead
    from .llm_client import llm_client

    markets = await polymarket_client.fetch_merged_search_markets(
        ["bitcoin", "btc", "btc usdt"],
        per_query_limit=55,
    )

    if request.market_ids:
        want = list(dict.fromkeys(request.market_ids))
        by_id: dict[str, dict] = {}
        for m in markets:
            k = str(m.get("id", ""))
            if k in want:
                by_id[k] = m
        for mid in want:
            if mid not in by_id:
                extra = await polymarket_client.get_market(mid)
                if extra:
                    by_id[mid] = extra
        markets = [by_id[mid] for mid in want if mid in by_id]

    now = datetime.now(timezone.utc)
    cutoff = now + timedelta(days=request.max_days)

    candidate_markets: list[tuple[dict, datetime, float]] = []
    for m in markets:
        if _is_market_dead(m):
            continue

        if not request.market_ids:
            text = _btc_market_text(m)
            if not any(kw in text for kw in BTC_KEYWORDS):
                continue

        end_date = None
        for field in ("endDate", "end_date", "resolutionDate", "endDateIso"):
            raw_val = m.get(field)
            if raw_val:
                try:
                    dt = dateparser.parse(str(raw_val))
                    if dt and dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    end_date = dt
                    break
                except Exception:
                    pass

        if not end_date or end_date < now or end_date > cutoff:
            continue

        yes_price = _gamma_yes_price_from_market(m)

        if yes_price <= 0.005 or yes_price >= 0.995:
            continue

        candidate_markets.append((m, end_date, yes_price))

    candidate_markets.sort(key=lambda x: x[1])
    candidate_markets = candidate_markets[:10]

    async def _analyze_one(m: dict, end_date: datetime, yes_price: float) -> dict:
        question = m.get("question", "")
        now_inner = datetime.now(timezone.utc)
        hours_left = (end_date - now_inner).total_seconds() / 3600
        days_left = hours_left / 24
        volume, liquidity = _gamma_volume_liquidity(m)

        # ── Agent 1: Price Signal (LLM) ─────────────────────────────
        async def price_agent() -> dict:
            return await llm_client.btc_quick_signal(
                market_question=question,
                yes_price=yes_price,
                days_left=days_left,
                volume=volume,
            )

        # ── Agent 2: Momentum Stats (pure math, no LLM) ─────────────
        async def momentum_agent() -> dict:
            score = 0.5
            if hours_left < 24:
                score += 0.20
            elif hours_left < 72:
                score += 0.10
            if volume > 100_000:
                score += 0.15
            elif volume > 10_000:
                score += 0.05
            if abs(yes_price - 0.5) > 0.3:
                score -= 0.10
            if liquidity > 50_000:
                score += 0.10
            score = min(1.0, max(0.0, score))
            return {
                "momentum_score": round(score, 3),
                "urgency": "high" if hours_left < 24 else ("medium" if hours_left < 72 else "low"),
                "volume_tier": "high" if volume > 100_000 else ("medium" if volume > 10_000 else "low"),
            }

        # ── Agent 3: Sentiment Signal (LLM) ─────────────────────────
        async def sentiment_agent() -> dict:
            return await llm_client.btc_sentiment_signal(
                market_question=question,
                yes_price=yes_price,
                hours_left=hours_left,
            )

        results = await asyncio.gather(
            price_agent(), momentum_agent(), sentiment_agent(),
            return_exceptions=True,
        )

        price_res   = results[0] if not isinstance(results[0], Exception) else {}
        momentum_res = results[1] if not isinstance(results[1], Exception) else {}
        sentiment_res = results[2] if not isinstance(results[2], Exception) else {}

        # ── Combine signals ──────────────────────────────────────────
        direction = price_res.get("direction", "BUY")
        sent_dir  = "BUY" if sentiment_res.get("suggested_direction", "YES") == "YES" else "SELL"
        # Consensus: if both agree use that, else default to price_agent
        if direction != sent_dir:
            direction = direction  # price_agent takes priority

        price_conf   = float(price_res.get("confidence", 0.4))
        sent_edge    = float(sentiment_res.get("edge_estimate", 0.3))
        mom_score    = float(momentum_res.get("momentum_score", 0.5))
        combined_conf = min(1.0, max(0.0, price_conf * 0.50 + sent_edge * 0.30 + mom_score * 0.20))

        win_prob = float(price_res.get("win_probability", yes_price))
        win_prob = min(0.99, max(0.01, win_prob))

        # Kelly criterion (quarter-Kelly cap)
        p = win_prob
        q = 1.0 - p
        b = (1.0 / yes_price) - 1.0 if yes_price > 0 else 0.0
        if b > 0 and p > q:
            kelly = (p * b - q) / b
            kelly = max(0.0, min(kelly * 0.25, 0.25))
        else:
            kelly = 0.0
        suggested_pct = round(kelly * 100, 1)

        exp_return = round((win_prob / yes_price - 1) * 100, 1) if direction == "BUY" else round(((1 - win_prob) / (1 - yes_price) - 1) * 100, 1) if yes_price < 1 else 0.0

        signal_quality = "strong" if combined_conf >= 0.70 else ("moderate" if combined_conf >= 0.50 else "weak")
        urgency = price_res.get("urgency") or momentum_res.get("urgency", "low")

        token_id = _gamma_first_token_id(m)

        market_url = _polymarket_market_url(m)

        return {
            "market_id": token_id or m.get("id", ""),
            "gamma_id": m.get("id", ""),
            "market_question": question,
            "direction": direction,
            "yes_price": yes_price,
            "confidence": round(combined_conf, 3),
            "win_probability": round(win_prob, 3),
            "expected_return_pct": exp_return,
            "suggested_amount_pct": suggested_pct,
            "reasoning": price_res.get("reasoning", "Analysis unavailable."),
            "key_signal": price_res.get("key_signal", ""),
            "urgency": urgency,
            "signal_quality": signal_quality,
            "hours_left": round(hours_left, 1),
            "days_left": round(days_left, 2),
            "volume": volume,
            "liquidity": liquidity,
            "agents_consensus": {
                "price_agent_dir": price_res.get("direction", "?"),
                "sentiment_dir": sentiment_res.get("suggested_direction", "?"),
                "btc_sentiment": sentiment_res.get("btc_sentiment", "neutral"),
                "momentum_score": momentum_res.get("momentum_score", 0),
                "volume_tier": momentum_res.get("volume_tier", "?"),
            },
            "market_url": market_url,
            "end_date": end_date.isoformat(),
            "analyzed_at": datetime.now(timezone.utc).isoformat(),
        }

    tasks = [_analyze_one(m, end_date, yp) for m, end_date, yp in candidate_markets]
    raw_results = await asyncio.gather(*tasks, return_exceptions=True)

    signals = [r for r in raw_results if isinstance(r, dict)]
    quality_order = {"strong": 0, "moderate": 1, "weak": 2}
    signals.sort(key=lambda x: (quality_order.get(x.get("signal_quality", "weak"), 2), -x.get("confidence", 0)))

    await ws_manager.broadcast(WsEventType.BITCOIN_SIGNAL, {"signals": signals, "count": len(signals)})

    return ApiResponse(data=signals, message=f"Analyzed {len(signals)} Bitcoin markets in parallel")


class BitcoinTradeRequest(BaseModel):
    token_id: str
    direction: str  # "BUY" | "SELL"
    price: float
    amount_usdc: float


@app.post("/api/bitcoin-trade", response_model=ApiResponse, tags=["Bitcoin"])
async def bitcoin_trade(req: BitcoinTradeRequest):
    """Place an order directly from a Bitcoin signal."""
    if req.amount_usdc <= 0:
        raise HTTPException(status_code=400, detail="amount_usdc must be > 0")
    side = "BUY" if req.direction.upper() == "BUY" else "SELL"
    receipt = await polymarket_client.place_order(
        token_id=req.token_id,
        side=side,
        price=req.price,
        size=req.amount_usdc,
    )
    status = str(receipt.get("status", "")).lower()
    if status == "error":
        raise HTTPException(status_code=500, detail=receipt.get("error", "Order rejected"))
    simulated = status == "simulated"
    tx = (
        receipt.get("orderID")
        or receipt.get("id")
        or (receipt.get("transactionsHashes") or [None])[0]
        or f"{'SIMULATED — ' if simulated else ''}{req.amount_usdc} USDC {req.direction} @ {req.price:.3f}"
    )
    return ApiResponse(
        data={"tx": tx, "simulated": simulated, "receipt": receipt},
        message="Order simulated (demo mode)" if simulated else "Order placed successfully",
    )


# ─────────────────────────── Portfolio ───────────────────────────────

@app.get("/api/portfolio", response_model=ApiResponse, tags=["Portfolio"])
async def get_portfolio():
    portfolio = await polymarket_client.get_portfolio()
    await ws_manager.broadcast(WsEventType.PORTFOLIO_UPDATE, portfolio.model_dump())
    return ApiResponse(data=portfolio)


# ─────────────────────────── WebSocket ───────────────────────────────

@app.websocket("/ws/updates")
async def websocket_endpoint(websocket: WebSocket):
    await ws_manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        await ws_manager.disconnect(websocket)
    except Exception as exc:
        logger.error(f"WebSocket error: {exc}")
        await ws_manager.disconnect(websocket)


# ─────────────────────────── Health ──────────────────────────────────

@app.get("/health", tags=["System"])
async def health_check():
    return {
        "status": "ok",
        "agents": len(_agents),
        "suggestions": len(_suggestions),
        "investigations": len(_investigations),
        "strategies": len(_strategy_reports),
        "event_evaluations": len(_event_evaluations),
        "position_advice": len(_position_advice),
        "opportunities": len(_opportunities),
        "ws_connections": ws_manager.connection_count,
    }
