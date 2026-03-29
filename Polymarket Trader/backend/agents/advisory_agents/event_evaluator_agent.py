"""
EventEvaluatorAgent — evaluates open events and creates probable scenarios
based on news, LLM reasoning, and current market data.
"""
from __future__ import annotations
import asyncio
from datetime import datetime, timezone
from dateutil import parser as dateparser
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, EventEvaluation, EventScenario, Suggestion, WsEventType,
)

POLYMARKET_BASE = "https://polymarket.com/event"
MAX_EVENTS = 12


class EventEvaluatorAgent(BaseAgent):
    """
    Fetches active markets across categories, evaluates each with news context,
    and produces scenario analyses showing the most probable outcomes.
    """

    def __init__(self, **kwargs):
        self._evaluations: dict = kwargs.pop("evaluation_store", {})
        super().__init__(
            name="EventEvaluatorAgent",
            category=AgentCategory.EVENT_EVALUATOR,
            **kwargs,
        )

    async def investigate(self) -> list[Suggestion]:
        await self.log("Scanning open events for scenario evaluation...")

        markets = await self.polymarket.get_markets(active=True, limit=MAX_EVENTS * 2)
        now = datetime.now(timezone.utc)

        active = []
        for m in markets:
            if m.get("closed") is True or str(m.get("closed", "")).lower() == "true":
                continue
            if m.get("resolved") is True or str(m.get("resolved", "")).lower() == "true":
                continue
            prices = m.get("outcomePrices") or []
            try:
                if prices and (float(prices[0]) <= 0.005 or float(prices[0]) >= 0.995):
                    continue
            except (ValueError, IndexError, TypeError):
                pass
            end = self._parse_end(m)
            if end and end < now:
                continue
            active.append(m)

        await self.log(f"Evaluating {len(active)} active events...")

        tasks = [self._evaluate_event(m) for m in active[:MAX_EVENTS]]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        count = 0
        for r in results:
            if isinstance(r, EventEvaluation):
                self._evaluations[r.id] = r
                await self.ws.broadcast(WsEventType.EVENT_EVALUATION, r.model_dump())
                count += 1
            elif isinstance(r, Exception):
                await self.log(f"Event eval error: {r}", level="warning")

        await self.log(f"Event evaluation complete — {count} scenarios generated.")
        return []

    async def _evaluate_event(self, market: dict) -> EventEvaluation | None:
        question = market.get("question", "Unknown")
        market_id = market.get("id", "")
        outcomes = market.get("outcomes", ["Yes", "No"])
        outcome = outcomes[0] if outcomes else "Yes"
        price = self._extract_price(market, outcome)
        end_date = self._parse_end(market)
        end_str = end_date.strftime("%Y-%m-%d") if end_date else "unknown"

        slug = market.get("slug") or market.get("conditionId") or market_id
        market_url = f"{POLYMARKET_BASE}/{slug}" if slug else None

        tags = market.get("tags") or []
        category = tags[0] if tags else "general"

        await self.log(f"Evaluating: '{question[:50]}...'")

        news = await self.search_web(f"{question} latest news analysis")
        if not news:
            news = f"Use your knowledge to analyze: {question}"

        parsed = await self.llm.evaluate_event_scenarios(
            market_question=question,
            current_price=price,
            news_context=news,
            end_date_str=end_str,
        )

        scenarios = [
            EventScenario(**s) for s in parsed.get("scenarios", [])
            if isinstance(s, dict)
        ]

        return EventEvaluation(
            market_id=market_id,
            market_question=question,
            current_price=price,
            end_date=end_date,
            category=category,
            scenarios=scenarios,
            most_likely_outcome=parsed.get("most_likely_outcome", ""),
            confidence=float(parsed.get("confidence", 0)),
            news_context=news[:500],
            agent_id=self.id,
            market_url=market_url,
        )

    def _parse_end(self, market: dict) -> datetime | None:
        for field in ("endDate", "end_date", "resolutionDate", "endDateIso"):
            raw = market.get(field)
            if raw:
                try:
                    dt = dateparser.parse(str(raw))
                    if dt and dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    return dt
                except Exception:
                    pass
        return None
