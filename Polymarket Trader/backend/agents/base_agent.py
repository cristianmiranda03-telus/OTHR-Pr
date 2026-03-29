"""
BaseAgent — abstract foundation for all trading agents.
"""
from __future__ import annotations
import asyncio
import importlib.util
import logging
import uuid
from abc import ABC, abstractmethod
from datetime import datetime
from typing import TYPE_CHECKING, Optional

from ..models import (
    AgentCategory, AgentInfo, AgentLog, AgentStatus,
    Investigation, InvestigationStatus,
    Suggestion, WsEventType,
)
from ..llm_client import LLMClient
from ..config import get_settings

if TYPE_CHECKING:
    from ..websocket_manager import WebSocketManager
    from ..polymarket_client import PolymarketClient

logger = logging.getLogger(__name__)


class BaseAgent(ABC):

    def __init__(
        self,
        name: str,
        category: AgentCategory,
        agent_registry: dict[str, AgentInfo],
        suggestion_store: dict[str, Suggestion],
        investigation_store: dict[str, Investigation],
        strategy_store: dict,
        ws_manager: "WebSocketManager",
        polymarket_client: "PolymarketClient",
    ):
        self.id = str(uuid.uuid4())
        self.name = name
        self.category = category
        self.settings = get_settings()
        self.llm = LLMClient()
        self.polymarket = polymarket_client
        self.ws = ws_manager
        self._registry = agent_registry
        self._store = suggestion_store
        self._investigations = investigation_store
        self._strategies = strategy_store
        self._running = False

        self._registry[self.id] = AgentInfo(
            id=self.id,
            name=self.name,
            category=self.category,
            status=AgentStatus.IDLE,
        )
        # Broadcast initial creation so frontend sees them immediately
        asyncio.create_task(self.ws.broadcast(WsEventType.AGENT_STATUS, self._registry[self.id].model_dump()))

    # ─────────────────────── Lifecycle ───────────────────────────────

    _MAX_CONSECUTIVE_ERRORS = 5
    _ERROR_BACKOFF_BASE = 30

    async def run(self):
        self._running = True
        self._cycle = 0
        self._consecutive_errors = 0
        await self.log(f"{self.name} initialized and ready.")
        while self._running:
            self._cycle += 1
            try:
                await self._set_status(
                    AgentStatus.INVESTIGATING,
                    f"Cycle #{self._cycle} — investigating...",
                )
                suggestions = await self.investigate()
                for suggestion in suggestions:
                    await self._emit_suggestion(suggestion)
                self._consecutive_errors = 0
                await self._set_status(AgentStatus.IDLE, f"Cycle #{self._cycle} complete")
                await self.log(
                    f"Cycle #{self._cycle} done — "
                    f"{len(suggestions)} signals. "
                    f"Next in {self.settings.update_interval}s."
                )
            except asyncio.CancelledError:
                await self.log("Cancelled — shutting down.")
                break
            except Exception as exc:
                self._consecutive_errors += 1
                backoff = min(
                    self._ERROR_BACKOFF_BASE * self._consecutive_errors,
                    300,
                )
                await self._set_status(AgentStatus.ERROR, str(exc)[:200])
                await self.log(
                    f"Error in cycle #{self._cycle} "
                    f"({self._consecutive_errors}/{self._MAX_CONSECUTIVE_ERRORS}): {exc}. "
                    f"Retrying in {backoff}s.",
                    level="error",
                )
                if self._consecutive_errors >= self._MAX_CONSECUTIVE_ERRORS:
                    await self.log(
                        f"Too many consecutive errors ({self._consecutive_errors}). "
                        f"Stopping — orchestrator will restart me.",
                        level="error",
                    )
                    return
                await asyncio.sleep(backoff)
                continue
            await asyncio.sleep(self.settings.update_interval)

    def stop(self):
        self._running = False

    @abstractmethod
    async def investigate(self) -> list[Suggestion]:
        ...

    # ─────────────────────── Investigation tracking ───────────────────

    def _start_investigation(self, market_id: str, market_question: str, price: float) -> Investigation:
        inv = Investigation(
            agent_id=self.id,
            agent_name=self.name,
            category=self.category,
            market_id=market_id,
            market_question=market_question,
            price_at_analysis=price,
            status=InvestigationStatus.ANALYZING,
        )
        self._investigations[inv.id] = inv
        return inv

    async def _update_investigation(self, inv: Investigation, **kwargs):
        for k, v in kwargs.items():
            setattr(inv, k, v)
        if inv.status in (InvestigationStatus.COMPLETE, InvestigationStatus.SKIPPED, InvestigationStatus.ERROR):
            inv.finished_at = datetime.utcnow()
        await self.ws.broadcast(WsEventType.INVESTIGATION_UPDATE, inv.model_dump())

    # ─────────────────────── Helpers ─────────────────────────────────

    async def log(self, message: str, level: str = "info"):
        log_entry = AgentLog(
            agent_id=self.id,
            agent_name=self.name,
            message=message,
            level=level,
        )
        getattr(logger, level, logger.info)(f"[{self.name}] {message}")
        await self.ws.broadcast(WsEventType.AGENT_LOG, log_entry.model_dump())

    async def _set_status(self, status: AgentStatus, task: Optional[str] = None):
        info = self._registry.get(self.id)
        if info:
            info.status = status
            info.current_task = task
            info.last_active = datetime.utcnow()
            if status == AgentStatus.ERROR:
                info.error_message = task
            await self.ws.broadcast(WsEventType.AGENT_STATUS, info.model_dump())

    async def _emit_suggestion(self, suggestion: Suggestion):
        if suggestion.confidence_score < self.settings.min_confidence:
            await self.log(
                f"Signal skipped (confidence {suggestion.confidence_score:.0%} < "
                f"{self.settings.min_confidence:.0%} threshold)"
            )
            return

        self._store[suggestion.id] = suggestion

        info = self._registry.get(self.id)
        if info:
            info.suggestions_generated += 1
            info.status = AgentStatus.SUGGESTION_READY

        await self.ws.broadcast(WsEventType.NEW_SUGGESTION, suggestion.model_dump())
        await self.log(
            f"New signal: {suggestion.direction.value} '{suggestion.outcome}' "
            f"on '{suggestion.market_question[:50]}' — {suggestion.confidence_score:.0%} confidence"
        )

    async def search_web(self, query: str) -> str:
        """Optional Tavily web search — gracefully skipped if unavailable."""
        if not self.settings.tavily_api_key:
            return ""
        try:
            if importlib.util.find_spec("tavily") is None:
                return ""
            from tavily import TavilyClient
            client = TavilyClient(api_key=self.settings.tavily_api_key)
            result = await asyncio.to_thread(
                client.search, query, max_results=5, search_depth="advanced"
            )
            snippets = [r.get("content", "") for r in result.get("results", [])]
            return "\n\n".join(snippets[:3])
        except Exception as exc:
            await self.log(f"Web search skipped: {exc}", level="warning")
            return ""

    def _extract_price(self, market: dict, outcome: str = "Yes") -> float:
        outcomes = market.get("outcomes", [])
        prices_raw = market.get("outcomePrices", [])
        try:
            idx = outcomes.index(outcome)
            return float(prices_raw[idx])
        except (ValueError, IndexError):
            return 0.5
