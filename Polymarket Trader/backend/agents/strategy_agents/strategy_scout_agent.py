"""
StrategyScoutAgent — researches external sources for novel trading patterns.
Optimized: processes 3 queries per cycle (rotating), faster LLM calls.
"""
from __future__ import annotations
import asyncio
from ..base_agent import BaseAgent
from ...models import AgentCategory, Suggestion, StrategyReport, WsEventType


RESEARCH_QUERIES = [
    "prediction market trading strategy 2026",
    "polymarket edge finding arbitrage method",
    "kalshi polymarket probability mispricing research",
    "prediction market liquidity alpha generation",
    "information asymmetry prediction markets",
    "market making prediction market techniques",
    "polymarket event contract hedging strategies",
    "prediction market mean reversion patterns",
]


class StrategyScoutAgent(BaseAgent):
    """
    Scans external sources for novel trading strategies.
    Processes a rotating batch of 3 queries per cycle for speed.
    """

    def __init__(self, **kwargs):
        super().__init__(
            name="StrategyScoutAgent",
            category=AgentCategory.STRATEGY_SCOUT,
            **kwargs,
        )
        self._query_index = 0

    async def investigate(self) -> list[Suggestion]:
        batch_size = 3
        batch = []
        for i in range(batch_size):
            idx = (self._query_index + i) % len(RESEARCH_QUERIES)
            batch.append(RESEARCH_QUERIES[idx])
        self._query_index = (self._query_index + batch_size) % len(RESEARCH_QUERIES)

        await self.log(f"Scouting {batch_size} strategy queries (batch rotation)...")

        results = await asyncio.gather(
            *[self._research_query(q) for q in batch],
            return_exceptions=True,
        )

        count = 0
        for r in results:
            if isinstance(r, StrategyReport):
                self._strategies[r.id] = r
                await self.ws.broadcast(WsEventType.STRATEGY_REPORT, r.model_dump())
                count += 1

        await self.log(f"Scout cycle complete — {count} reports generated (next batch offset: {self._query_index}).")
        return []

    async def _research_query(self, query: str) -> StrategyReport | None:
        await self.log(f"Researching: '{query[:50]}'")

        raw_content = await self.search_web(query)
        if not raw_content:
            raw_content = f"Use your knowledge about: {query}"

        parsed = await self.llm.summarize_for_strategy(raw_content, query)

        return StrategyReport(
            title=parsed.get("title", query[:60]),
            source=query,
            summary=parsed.get("summary", ""),
            actionable_insights=parsed.get("actionable_insights", []),
            difficulty=parsed.get("difficulty", "medium"),
            agent_id=self.id,
        )
