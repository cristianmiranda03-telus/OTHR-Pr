"""
Shared investigation logic for all category market agents.
"""
from __future__ import annotations
import asyncio
from datetime import datetime, timezone
from dateutil import parser as dateparser
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, AgentStatus, Investigation, InvestigationStatus,
    Suggestion, TradeDirection,
)

POLYMARKET_BASE = "https://polymarket.com/event"


class MarketBaseAgent(BaseAgent):
    CATEGORY_TAG: str = ""
    MAX_MARKETS: int = 10

    async def investigate(self) -> list[Suggestion]:
        await self.log(f"Fetching {self.CATEGORY_TAG} markets...")
        markets = await self.polymarket.get_markets(
            category=self.CATEGORY_TAG,
            active=True,
            limit=self.MAX_MARKETS,
        )
        await self.log(f"Found {len(markets)} markets from API. Filtering...")

        now = datetime.now(timezone.utc)
        active_markets = []
        for m in markets:
            # Skip closed/resolved/settled
            closed = m.get("closed")
            if closed is True or str(closed).lower() == "true":
                continue
            resolved = m.get("resolved")
            if resolved is True or str(resolved).lower() == "true":
                continue
            # Skip fully resolved prices
            prices = m.get("outcomePrices") or []
            try:
                if prices and (float(prices[0]) <= 0.005 or float(prices[0]) >= 0.995):
                    continue
            except (ValueError, IndexError, TypeError):
                pass
            # Skip expired
            end_date = self._parse_end_date(m)
            if end_date and end_date < now:
                await self.log(f"Skipping expired: '{m.get('question','')[:50]}'")
                continue
            active_markets.append(m)

        await self.log(f"{len(active_markets)} truly active markets to analyse with {self.llm.provider}...")
        tasks = [self._analyse_market(m) for m in active_markets]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        suggestions = [r for r in results if isinstance(r, Suggestion)]
        errors = [r for r in results if isinstance(r, Exception)]
        for e in errors:
            await self.log(f"Market analysis error: {e}", level="warning")

        await self.log(
            f"Cycle complete — {len(suggestions)} raw signals, "
            f"{len(markets) - len(suggestions) - len(errors)} skipped."
        )
        return suggestions

    async def _analyse_market(self, market: dict) -> Suggestion | None:
        question = market.get("question", "Unknown market")
        gamma_id = market.get("id", "")
        outcomes = market.get("outcomes", ["Yes", "No"])
        outcome = outcomes[0] if outcomes else "Yes"
        current_price = self._extract_price(market, outcome)
        end_date = self._parse_end_date(market)
        market_url = self._build_market_url(market)

        # Resolve the CLOB token ID — the CLOB needs this, not the Gamma market id
        clob_token_id = self._resolve_clob_token_id(market, outcome)
        market_id = clob_token_id or gamma_id

        # Start tracking this investigation
        inv = self._start_investigation(market_id, question, current_price)
        await self.log(f"Investigating: '{question[:60]}'")

        try:
            # Step 1: web search (optional)
            search_query = f"{question} {' '.join(self._extra_search_terms())}"
            news_text = await self.search_web(search_query)

            # If no web search, ask LLM to reason from training knowledge
            if not news_text:
                news_text = (
                    f"No live search available. "
                    f"Use your knowledge about: {question}"
                )

            # Step 2: LLM sentiment
            sentiment = await self.llm.analyze_sentiment(
                text=news_text,
                context=(
                    f"Prediction market: '{question}' | "
                    f"Current '{outcome}' price: {current_price:.2f} "
                    f"(implies {current_price*100:.1f}% probability)"
                ),
            )

            await self._update_investigation(
                inv,
                news_summary=news_text[:500] if len(news_text) > 10 else None,
                sentiment=sentiment,
            )

            # Step 3: detect discrepancy
            direction = self._determine_direction(sentiment, current_price)
            if direction is None:
                conclusion = (
                    f"No clear edge. Market at {current_price:.2f} aligns with "
                    f"{sentiment.get('sentiment', 'neutral')} sentiment."
                )
                await self._update_investigation(
                    inv,
                    status=InvestigationStatus.SKIPPED,
                    conclusion=conclusion,
                )
                return None

            # Step 4: generate reasoning
            reasoning, confidence = await self.llm.generate_trading_reasoning(
                market_question=question,
                outcome=outcome,
                direction=direction.value,
                price=current_price,
                news_summary=news_text[:800],
                sentiment_data=sentiment,
            )

            conclusion = (
                f"{direction.value} signal — {sentiment.get('sentiment', '?')} sentiment "
                f"vs {current_price:.2f} market price. Confidence: {confidence:.0%}"
            )
            await self._update_investigation(
                inv,
                status=InvestigationStatus.COMPLETE,
                conclusion=conclusion,
                direction_found=direction.value,
            )

            return Suggestion(
                market_id=market_id,
                market_question=question,
                outcome=outcome,
                direction=direction,
                price_at_discovery=current_price,
                confidence_score=confidence,
                reasoning=reasoning,
                agent_id=self.id,
                agent_name=self.name,
                category=self.category,
                tags=[self.CATEGORY_TAG],
                end_date=end_date,
                market_url=market_url,
            )

        except Exception as exc:
            await self._update_investigation(
                inv,
                status=InvestigationStatus.ERROR,
                conclusion=str(exc),
            )
            raise

    def _determine_direction(
        self, sentiment: dict, current_price: float
    ) -> TradeDirection | None:
        s = sentiment.get("sentiment", "neutral").lower()
        conf = float(sentiment.get("confidence", 0))

        if conf < 0.4:
            return None
        if s == "bullish" and current_price < 0.60:
            return TradeDirection.BUY
        if s == "bearish" and current_price > 0.40:
            return TradeDirection.SELL
        return None

    def _extra_search_terms(self) -> list[str]:
        return []

    def _resolve_clob_token_id(self, market: dict, outcome: str) -> str:
        """Extract the correct clobTokenId for the given outcome from the Gamma market object."""
        import json as _json
        outcomes = market.get("outcomes", [])
        token_ids = market.get("clobTokenIds") or market.get("clob_token_ids") or []
        if isinstance(outcomes, str):
            try:
                outcomes = _json.loads(outcomes)
            except Exception:
                outcomes = []
        if isinstance(token_ids, str):
            try:
                token_ids = _json.loads(token_ids)
            except Exception:
                token_ids = []
        if not token_ids:
            return ""
        try:
            idx = outcomes.index(outcome) if outcome in outcomes else 0
            return str(token_ids[idx]) if idx < len(token_ids) else str(token_ids[0])
        except (ValueError, IndexError):
            return str(token_ids[0]) if token_ids else ""

    def _parse_end_date(self, market: dict) -> datetime | None:
        """Parse market end/resolution date from various Gamma API field names."""
        for field in ("endDate", "end_date", "resolutionDate", "resolution_date", "endDateIso"):
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

    def _build_market_url(self, market: dict) -> str | None:
        """Build a direct Polymarket URL from the market object."""
        slug = market.get("slug") or market.get("conditionId") or market.get("id")
        if slug:
            return f"{POLYMARKET_BASE}/{slug}"
        return None
