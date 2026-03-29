"""
PositionAdvisorAgent — evaluates open positions and provides detailed
advice: hold/close/add, timing, scenarios, and risk assessment.
"""
from __future__ import annotations
import asyncio
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, EventScenario, PositionAdvice, Suggestion, WsEventType,
)


class PositionAdvisorAgent(BaseAgent):
    """
    Fetches the user's portfolio, analyzes each open position against
    current news and market conditions, and generates advisory reports.
    """

    def __init__(self, **kwargs):
        self._advice_store: dict = kwargs.pop("advice_store", {})
        super().__init__(
            name="PositionAdvisorAgent",
            category=AgentCategory.POSITION_ADVISOR,
            **kwargs,
        )

    async def investigate(self) -> list[Suggestion]:
        await self.log("Fetching portfolio for position advisory...")
        try:
            portfolio = await self.polymarket.get_portfolio()
        except Exception as e:
            await self.log(f"Portfolio fetch failed: {e}", level="error")
            return []

        if not portfolio.positions:
            await self.log("No open positions to advise on.")
            return []

        await self.log(f"Advising on {len(portfolio.positions)} positions...")
        positions = portfolio.positions[:8]

        tasks = [self._advise_position(pos) for pos in positions]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        count = 0
        for r in results:
            if isinstance(r, PositionAdvice):
                self._advice_store[r.id] = r
                await self.ws.broadcast(WsEventType.POSITION_ADVICE, r.model_dump())
                count += 1
            elif isinstance(r, Exception):
                await self.log(f"Position advice error: {r}", level="warning")

        await self.log(f"Position advisory complete — {count} advice reports.")
        return []

    async def _advise_position(self, pos) -> PositionAdvice | None:
        await self.log(f"Analyzing position: '{pos.market_question[:40]}...'")

        news = await self.search_web(f"{pos.market_question} latest update prediction market")
        if not news:
            news = f"Analyze the outlook for: {pos.market_question}"

        parsed = await self.llm.advise_on_position(
            question=pos.market_question,
            outcome=pos.outcome,
            size=pos.size,
            avg_price=pos.avg_price,
            current_price=pos.current_price,
            pnl=pos.pnl,
            pnl_pct=pos.pnl_pct,
            news_context=news,
        )

        scenarios = [
            EventScenario(**s) for s in parsed.get("scenarios", [])
            if isinstance(s, dict)
        ]

        return PositionAdvice(
            market_id=pos.market_id,
            market_question=pos.market_question,
            outcome=pos.outcome,
            current_size=pos.size,
            avg_price=pos.avg_price,
            current_price=pos.current_price,
            current_pnl=pos.pnl,
            recommended_action=parsed.get("action", "HOLD"),
            urgency=parsed.get("urgency", "low"),
            hold_duration=parsed.get("hold_duration", ""),
            scenarios=scenarios,
            reasoning=parsed.get("reasoning", ""),
            risk_level=parsed.get("risk_level", "medium"),
            agent_id=self.id,
            market_url=pos.market_url,
        )
