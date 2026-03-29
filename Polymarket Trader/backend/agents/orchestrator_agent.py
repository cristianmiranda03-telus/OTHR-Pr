"""
OrchestratorAgent — "El Joker"
Coordinates all sub-agents, runs them in parallel, collects suggestions,
and manages the overall trading workflow with auto-recovery.
"""
from __future__ import annotations
import asyncio
import logging
from datetime import datetime
from typing import TYPE_CHECKING

from ..models import (
    AgentCategory, AgentInfo, AgentStatus, Suggestion, SuggestionStatus, WsEventType,
)
from ..config import get_settings
from ..llm_client import LLMClient
from ..websocket_manager import WebSocketManager
from ..polymarket_client import PolymarketClient

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

_AGENT_STAGGER_DELAY = 5.0
_HEARTBEAT_INTERVAL = 30
_RESTART_COOLDOWN = 60


class OrchestratorAgent:
    """
    El Joker — master coordinator.
    Spawns and supervises all market, strategy, and advisory agents in asyncio Tasks,
    collects their suggestions, and feeds them to the frontend queue.
    Automatically restarts crashed agents.
    """

    def __init__(
        self,
        agent_registry: dict[str, AgentInfo],
        suggestion_store: dict[str, Suggestion],
        investigation_store: dict,
        strategy_store: dict,
        evaluation_store: dict,
        advice_store: dict,
        opportunity_store: dict,
        ws_manager: WebSocketManager,
        polymarket_client: PolymarketClient,
    ):
        self.settings = get_settings()
        self.ws = ws_manager
        self.polymarket = polymarket_client
        self._registry = agent_registry
        self._store = suggestion_store
        self._investigations = investigation_store
        self._strategies = strategy_store
        self._evaluations = evaluation_store
        self._advice = advice_store
        self._opportunities = opportunity_store
        self._agent_tasks: list[asyncio.Task] = []
        self._agents: list = []
        self._llm = LLMClient()
        self._running = False

        import uuid
        self.id = str(uuid.uuid4())
        self._registry[self.id] = AgentInfo(
            id=self.id,
            name="OrchestratorAgent",
            category=AgentCategory.ORCHESTRATOR,
            status=AgentStatus.IDLE,
        )

    async def run(self):
        """Launch all agents and supervise them indefinitely."""
        self._running = True
        await self._log("El Joker awakens. Initializing 12-agent swarm...")
        await self._set_status(AgentStatus.RUNNING, "Launching agent swarm")

        self._agents = self._create_agents()

        self._agent_tasks = []
        for i, agent in enumerate(self._agents):
            delay = i * _AGENT_STAGGER_DELAY
            task = asyncio.create_task(
                self._run_agent_with_delay(agent, delay),
                name=agent.name,
            )
            self._agent_tasks.append(task)

        await self._log(
            f"Launching {len(self._agents)} agents "
            f"(staggered {_AGENT_STAGGER_DELAY:.0f}s apart to respect rate limits)."
        )

        while self._running:
            await self._heartbeat()
            await self._check_and_restart_crashed()
            await asyncio.sleep(_HEARTBEAT_INTERVAL)

    async def _run_agent_with_delay(self, agent, delay: float):
        """Start an agent after a delay. No semaphore — rate limiting is done at the LLM level."""
        await asyncio.sleep(delay)
        await agent.run()

    def _create_agents(self):
        """Instantiate all sub-agents with shared state references."""
        from .market_agents.politics_agent import PoliticsAgent
        from .market_agents.crypto_agent import CryptoAgent
        from .market_agents.sports_agent import SportsAgent
        from .market_agents.science_agent import ScienceAgent
        from .strategy_agents.strategy_scout_agent import StrategyScoutAgent
        from .strategy_agents.whale_watcher_agent import WhaleWatcherAgent
        from .strategy_agents.portfolio_analyst_agent import PortfolioAnalystAgent
        from .advisory_agents.event_evaluator_agent import EventEvaluatorAgent
        from .advisory_agents.strategy_evaluator_agent import StrategyEvaluatorAgent
        from .advisory_agents.position_advisor_agent import PositionAdvisorAgent
        from .advisory_agents.entry_analyst_agent import EntryAnalystAgent
        from .advisory_agents.opportunity_optimizer_agent import OpportunityOptimizerAgent

        base_kwargs = dict(
            agent_registry=self._registry,
            suggestion_store=self._store,
            investigation_store=self._investigations,
            strategy_store=self._strategies,
            ws_manager=self.ws,
            polymarket_client=self.polymarket,
        )

        return [
            PoliticsAgent(**base_kwargs),
            CryptoAgent(**base_kwargs),
            SportsAgent(**base_kwargs),
            ScienceAgent(**base_kwargs),
            StrategyScoutAgent(**base_kwargs),
            WhaleWatcherAgent(**base_kwargs),
            EventEvaluatorAgent(**base_kwargs, evaluation_store=self._evaluations),
            StrategyEvaluatorAgent(**base_kwargs),
            PortfolioAnalystAgent(**base_kwargs),
            PositionAdvisorAgent(**base_kwargs, advice_store=self._advice),
            EntryAnalystAgent(**base_kwargs),
            OpportunityOptimizerAgent(**base_kwargs, opportunity_store=self._opportunities),
        ]

    async def _check_and_restart_crashed(self):
        """Detect crashed agent tasks and restart them."""
        for i, task in enumerate(self._agent_tasks):
            if not task.done():
                continue
            if task.cancelled():
                continue

            exc = task.exception()
            agent = self._agents[i]
            name = agent.name

            if exc:
                await self._log(
                    f"Agent '{name}' crashed: {exc}. Restarting in {_RESTART_COOLDOWN}s...",
                    level="error",
                )
            else:
                await self._log(
                    f"Agent '{name}' stopped unexpectedly (no exception). Restarting...",
                    level="warning",
                )

            info = self._registry.get(agent.id)
            if info:
                info.status = AgentStatus.ERROR
                info.error_message = str(exc) if exc else "Stopped unexpectedly"
                await self.ws.broadcast(WsEventType.AGENT_STATUS, info.model_dump())

            new_task = asyncio.create_task(
                self._run_agent_with_delay(agent, _RESTART_COOLDOWN),
                name=name,
            )
            self._agent_tasks[i] = new_task
            await self._log(f"Agent '{name}' scheduled for restart.")

    async def _heartbeat(self):
        by_status: dict[str, int] = {}
        for info in self._registry.values():
            by_status[info.status.value] = by_status.get(info.status.value, 0) + 1

        pending = sum(1 for s in self._store.values() if s.status == SuggestionStatus.PENDING)
        executed = sum(1 for s in self._store.values() if s.status == SuggestionStatus.EXECUTED)
        evaluations = len(self._evaluations)
        advice_count = len(self._advice)
        opportunities = len(self._opportunities)

        active = by_status.get("running", 0) + by_status.get("investigating", 0)
        idle = by_status.get("idle", 0)
        errors = by_status.get("error", 0)
        ready = by_status.get("suggestion_ready", 0)

        alive_tasks = sum(1 for t in self._agent_tasks if not t.done())
        dead_tasks = len(self._agent_tasks) - alive_tasks

        summary = (
            f"Heartbeat — {active} active, {idle} idle, {ready} ready, {errors} errors | "
            f"{alive_tasks}/{len(self._agent_tasks)} tasks alive "
            f"({dead_tasks} restarting) | "
            f"{pending} pending signals, {executed} executed | "
            f"{evaluations} evals, {advice_count} advices, {opportunities} opps"
        )
        await self._log(summary)

        await self.ws.broadcast(WsEventType.SYSTEM, {
            "type": "heartbeat",
            "active_agents": active,
            "idle_agents": idle,
            "error_agents": errors,
            "pending_suggestions": pending,
            "executed_suggestions": executed,
            "event_evaluations": evaluations,
            "position_advices": advice_count,
            "ranked_opportunities": opportunities,
            "alive_tasks": alive_tasks,
            "dead_tasks": dead_tasks,
            "agent_breakdown": by_status,
            "timestamp": datetime.utcnow().isoformat(),
        })

    async def _log(self, message: str, level: str = "info"):
        from ..models import AgentLog
        log_entry = AgentLog(
            agent_id=self.id,
            agent_name="OrchestratorAgent",
            message=message,
            level=level,
        )
        getattr(logger, level, logger.info)(f"[Orchestrator] {message}")
        await self.ws.broadcast(WsEventType.AGENT_LOG, log_entry.model_dump())

    async def _set_status(self, status: AgentStatus, task: str | None = None):
        info = self._registry.get(self.id)
        if info:
            info.status = status
            info.current_task = task
            info.last_active = datetime.utcnow()
            await self.ws.broadcast(WsEventType.AGENT_STATUS, info.model_dump())
