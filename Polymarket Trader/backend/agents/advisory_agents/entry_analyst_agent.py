"""
EntryAnalystAgent — prepares detailed analysis for entering new markets.
Identifies promising markets the user hasn't entered and evaluates
whether they represent good entry opportunities.
"""
from __future__ import annotations
import asyncio
from datetime import datetime, timezone
from dateutil import parser as dateparser
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, Suggestion, TradeDirection, WsEventType,
)

POLYMARKET_BASE = "https://polymarket.com/event"
MAX_MARKETS = 15


class EntryAnalystAgent(BaseAgent):
    """
    Scans active markets, filters out ones the user already holds,
    and produces detailed entry analysis with expected returns and risks.
    """

    def __init__(self, **kwargs):
        super().__init__(
            name="EntryAnalystAgent",
            category=AgentCategory.ENTRY_ANALYST,
            **kwargs,
        )

    async def investigate(self) -> list[Suggestion]:
        await self.log("Scanning markets for entry opportunities...")

        markets = await self.polymarket.get_markets(active=True, limit=MAX_MARKETS)
        now = datetime.now(timezone.utc)

        try:
            portfolio = await self.polymarket.get_portfolio()
            held_ids = {p.market_id for p in portfolio.positions}
        except Exception:
            held_ids = set()

        candidates = []
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
            mid = m.get("id", "")
            if mid in held_ids:
                continue
            candidates.append(m)

        if not candidates:
            await self.log("No new candidate markets found.")
            return []

        await self.log(f"Analyzing {len(candidates)} potential entries...")

        tasks = [self._analyze_entry(m) for m in candidates[:10]]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        suggestions = []
        for r in results:
            if isinstance(r, Suggestion):
                suggestions.append(r)
            elif isinstance(r, Exception):
                await self.log(f"Entry analysis error: {r}", level="warning")

        await self.log(f"Entry analysis done — {len(suggestions)} entry signals.")
        return suggestions

    async def _analyze_entry(self, market: dict) -> Suggestion | None:
        question = market.get("question", "Unknown")
        market_id = market.get("id", "")
        outcomes = market.get("outcomes", ["Yes", "No"])
        outcome = outcomes[0] if outcomes else "Yes"
        price = self._extract_price(market, outcome)
        end_date = self._parse_end(market)
        end_str = end_date.strftime("%Y-%m-%d") if end_date else "unknown"
        volume = float(market.get("volume", 0) or 0)

        slug = market.get("slug") or market.get("conditionId") or market_id
        market_url = f"{POLYMARKET_BASE}/{slug}" if slug else None

        inv = self._start_investigation(market_id, f"[ENTRY] {question}", price)
        await self.log(f"Entry analysis: '{question[:50]}...'")

        news = await self.search_web(f"{question} analysis prediction")
        if not news:
            news = f"Analyze entry opportunity for: {question}"

        parsed = await self.llm.analyze_entry_opportunity(
            question=question,
            price=price,
            end_date_str=end_str,
            news_context=news,
            volume=volume,
        )

        if not parsed.get("should_enter", False):
            from ...models import InvestigationStatus
            await self._update_investigation(
                inv,
                status=InvestigationStatus.SKIPPED,
                conclusion=f"Skip entry: {parsed.get('reasoning', 'insufficient edge')}",
            )
            return None

        direction_str = parsed.get("direction", "BUY")
        direction = TradeDirection.BUY if direction_str == "BUY" else TradeDirection.SELL
        confidence = float(parsed.get("confidence", 0.5))

        risks = parsed.get("key_risks", [])
        risk_text = " | Risks: " + "; ".join(risks[:3]) if risks else ""
        reasoning = (
            f"[ENTRY OPPORTUNITY] {parsed.get('reasoning', '')}"
            f" | Expected return: {parsed.get('expected_return_pct', 0):.1f}%"
            f" | Risk: {parsed.get('risk_score', 0.5):.0%}"
            f"{risk_text}"
        )

        from ...models import InvestigationStatus
        await self._update_investigation(
            inv,
            status=InvestigationStatus.COMPLETE,
            conclusion=f"Entry signal: {direction.value} at {price:.3f}, confidence {confidence:.0%}",
            direction_found=direction.value,
        )

        return Suggestion(
            market_id=market_id,
            market_question=question,
            outcome=outcome,
            direction=direction,
            price_at_discovery=price,
            confidence_score=confidence,
            reasoning=reasoning,
            agent_id=self.id,
            agent_name=self.name,
            category=self.category,
            tags=["new-entry", f"risk-{parsed.get('risk_score', 0.5):.1f}"],
            end_date=end_date,
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
