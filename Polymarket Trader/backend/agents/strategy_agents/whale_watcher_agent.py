"""
WhaleWatcherAgent — "El Copión"
Tracks the most profitable Polymarket traders (whales) and mirrors
their large, high-conviction positions as copy-trading Suggestions.
"""
from __future__ import annotations
import asyncio
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, Suggestion, SuggestionStatus, TradeDirection, WhaleActivity,
)

WHALE_POSITION_THRESHOLD = 500
MIN_PROFIT_USD = 5000


class WhaleWatcherAgent(BaseAgent):
    """
    1. Fetches the Polymarket leaderboard.
    2. For each top trader, checks their most recent positions.
    3. If they opened a large position, generates a copy-trade Suggestion.
    """

    def __init__(self, **kwargs):
        super().__init__(
            name="WhaleWatcherAgent",
            category=AgentCategory.WHALE_WATCHER,
            **kwargs,
        )

    async def investigate(self) -> list[Suggestion]:
        await self.log("Scanning Polymarket leaderboard for whale activity...")
        leaderboard = await self.polymarket.get_leaderboard(limit=10)

        suggestions: list[Suggestion] = []
        tasks = [self._watch_whale(entry) for entry in leaderboard[:5]]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        for r in results:
            if isinstance(r, list):
                suggestions.extend(r)
            elif isinstance(r, Exception):
                await self.log(f"Whale watch error: {r}", level="warning")

        await self.log(f"Whale watch complete. {len(suggestions)} copy-trade suggestions.")
        return suggestions

    async def _watch_whale(self, leaderboard_entry: dict) -> list[Suggestion]:
        address = leaderboard_entry.get("address", "")
        rank = leaderboard_entry.get("rank", 0)
        profit = float(leaderboard_entry.get("profit", 0))

        if profit < MIN_PROFIT_USD:
            return []

        await self.log(f"Watching whale #{rank} ({address[:10]}...) — profit ${profit:,.0f}")
        positions = await self.polymarket.get_trader_positions(address)

        suggestions = []
        for pos in positions[:5]:
            raw_size = float(pos.get("size", 0))
            avg_price = float(pos.get("avgPrice", 0))
            position_value = raw_size * avg_price
            if position_value < WHALE_POSITION_THRESHOLD:
                continue

            asset = pos.get("asset") or {}
            token_id = asset.get("token_id") or pos.get("market", "")
            question = pos.get("_title") or pos.get("question", "")
            outcome = pos.get("side") or pos.get("outcome", "Yes")
            if outcome.upper() in ("BUY", "SELL"):
                outcome = "Yes"
            price_raw = pos.get("_curPrice") or pos.get("currentPrice")
            price = float(price_raw) if price_raw else avg_price or 0.5

            direction = TradeDirection.BUY

            profit_rank_factor = min(1.0, profit / 100_000)
            confidence = min(0.90, 0.50 + profit_rank_factor * 0.35)

            reasoning = (
                f"Copy-trade: Whale #{rank} (PnL ${profit:,.0f}) "
                f"holds ${position_value:,.0f} in '{outcome}' at {price:.2f}. "
                f"Top traders on Polymarket are profitable long-term — "
                f"mirroring high-conviction positions with proven edge."
            )

            slug = pos.get("_eventSlug") or pos.get("_slug") or ""
            market_url = f"https://polymarket.com/event/{slug}" if slug else None

            suggestions.append(Suggestion(
                market_id=token_id,
                market_question=question or f"Market {token_id[:20]}",
                outcome=outcome,
                direction=direction,
                price_at_discovery=price,
                confidence_score=round(confidence, 2),
                reasoning=reasoning,
                agent_id=self.id,
                agent_name=self.name,
                category=self.category,
                tags=["whale-copy", f"rank-{rank}"],
                market_url=market_url,
            ))

        return suggestions
