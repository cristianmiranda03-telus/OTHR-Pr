"""
OpportunityOptimizerAgent — evaluates, optimizes and prioritizes potential
market entries based on expected return, risk, and opportunity cost.
"""
from __future__ import annotations
import asyncio
from datetime import datetime, timezone
from dateutil import parser as dateparser
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, OpportunityEntry, Suggestion, SuggestionStatus,
    TradeDirection, WsEventType,
)

POLYMARKET_BASE = "https://polymarket.com/event"


class OpportunityOptimizerAgent(BaseAgent):
    """
    Collects pending suggestions and unanalyzed markets, ranks them by
    expected value and opportunity cost, and broadcasts a prioritized list.
    """

    def __init__(self, **kwargs):
        self._opportunity_store: dict = kwargs.pop("opportunity_store", {})
        super().__init__(
            name="OpportunityOptimizer",
            category=AgentCategory.OPPORTUNITY_OPTIMIZER,
            **kwargs,
        )

    async def investigate(self) -> list[Suggestion]:
        await self.log("Optimizing opportunity pipeline...")

        pending = [
            s for s in self._store.values()
            if s.status == SuggestionStatus.PENDING
        ]

        if not pending:
            await self.log("No pending signals to optimize.")
            return []

        try:
            portfolio = await self.polymarket.get_portfolio()
            balance = portfolio.balance_usdc
        except Exception:
            balance = 100.0

        opportunities = []
        for s in pending:
            end_str = s.end_date.strftime("%Y-%m-%d") if s.end_date else "unknown"
            opportunities.append({
                "market_id": s.market_id,
                "question": s.market_question,
                "price": s.price_at_discovery,
                "confidence": s.confidence_score,
                "direction": s.direction.value,
                "end_date": end_str,
            })

        await self.log(f"Ranking {len(opportunities)} opportunities against ${balance:.2f} capital...")

        ranked_data = await self.llm.rank_opportunities(opportunities, balance)
        ranked_list = ranked_data.get("ranked", [])

        count = 0
        for i, entry in enumerate(ranked_list):
            mid = entry.get("market_id", "")
            matching = next((s for s in pending if s.market_id == mid), None)
            if not matching:
                continue

            opp = OpportunityEntry(
                market_id=mid,
                market_question=matching.market_question,
                current_price=matching.price_at_discovery,
                end_date=matching.end_date,
                expected_return_pct=float(entry.get("expected_return_pct", 0)),
                risk_score=matching.confidence_score,
                opportunity_cost_note=entry.get("opportunity_cost_note", ""),
                recommended_size_usdc=float(entry.get("recommended_size_usdc", 10)),
                priority_rank=entry.get("priority", i + 1),
                reasoning=f"Priority #{entry.get('priority', i+1)}: {entry.get('opportunity_cost_note', '')}",
                direction=matching.direction,
                confidence=matching.confidence_score,
                agent_id=self.id,
                market_url=matching.market_url,
            )

            self._opportunity_store[opp.id] = opp
            await self.ws.broadcast(WsEventType.OPPORTUNITY_RANK, opp.model_dump())
            count += 1

        note = ranked_data.get("portfolio_note", "")
        if note:
            await self.log(f"Portfolio note: {note}")

        await self.log(f"Optimization complete — {count} ranked opportunities.")
        return []
