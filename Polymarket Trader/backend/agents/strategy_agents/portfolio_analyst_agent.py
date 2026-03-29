from __future__ import annotations
import asyncio
from datetime import datetime, timezone
from ..base_agent import BaseAgent
from ...models import (
    AgentCategory, AgentStatus, Investigation, InvestigationStatus,
    Suggestion, TradeDirection
)


class PortfolioAnalystAgent(BaseAgent):
    """
    Looks at the user's current open positions from the portfolio,
    cross-references them with recent news and strategies,
    and investigates if any positions should be closed or increased.
    """

    def __init__(self, **kwargs):
        super().__init__(
            name="PortfolioAnalyst",
            category=AgentCategory.STRATEGY_SCOUT,
            **kwargs,
        )

    async def investigate(self) -> list[Suggestion]:
        await self.log("Fetching live portfolio for analysis...")
        try:
            portfolio = await self.polymarket.get_portfolio()
        except Exception as e:
            await self.log(f"Failed to fetch portfolio: {e}", level="error")
            return []

        if not portfolio.positions:
            await self.log("No open positions found to analyze.")
            return []

        await self.log(f"Found {len(portfolio.positions)} open positions. Analyzing against recent market data...")
        
        # We will only analyze a max of 5 positions per cycle to save tokens
        positions_to_analyze = portfolio.positions[:5]
        
        suggestions = []
        tasks = [self._analyze_position(pos) for pos in positions_to_analyze]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        for r in results:
            if isinstance(r, Suggestion):
                suggestions.append(r)
            elif isinstance(r, Exception):
                await self.log(f"Position analysis error: {r}", level="warning")

        await self.log(f"Portfolio analysis complete. {len(suggestions)} suggestions generated.")
        return suggestions

    async def _analyze_position(self, pos) -> Suggestion | None:
        market_id = pos.market_id
        question = pos.market_question
        outcome = pos.outcome
        current_price = pos.current_price
        avg_price = pos.avg_price
        
        inv = self._start_investigation(market_id, f"[PORTFOLIO] {question}", current_price)
        await self.log(f"Analyzing open position: '{question[:40]}...' (Holding {outcome})")
        
        # Step 1: Web search for latest news
        search_query = f"{question} prediction market news"
        news_text = await self.search_web(search_query)
        if not news_text:
            news_text = f"Analyze the current outlook for {question}."

        # Step 2: Extract recent strategies to use as context
        recent_strategies = list(self._strategies.values())[-3:]
        strategy_context = "\n".join([f"- {s.title}: {s.summary}" for s in recent_strategies])
        
        context = (
            f"User currently holds {pos.size} shares of '{outcome}' at an average price of {avg_price:.2f}. "
            f"The current market price is {current_price:.2f}. "
            f"Current Profit/Loss: ${pos.pnl:.2f} ({pos.pnl_pct:.2f}%).\n\n"
            f"Recent Strategies discovered:\n{strategy_context}"
        )

        # Step 3: LLM Sentiment
        sentiment = await self.llm.analyze_sentiment(text=news_text, context=context)
        
        await self._update_investigation(
            inv,
            news_summary=news_text[:500],
            sentiment=sentiment,
        )

        # Step 4: Determine if they should hold, buy more, or sell
        # If sentiment is very negative against their outcome, suggest SELL.
        # If sentiment is very positive, suggest BUY (double down).
        # Otherwise, skip (HOLD).
        
        is_bullish = sentiment.get("sentiment") == "bullish"
        is_bearish = sentiment.get("sentiment") == "bearish"
        
        direction = None
        if outcome.lower() == "yes":
            if is_bullish: direction = TradeDirection.BUY
            elif is_bearish: direction = TradeDirection.SELL
        else:
            if is_bearish: direction = TradeDirection.BUY
            elif is_bullish: direction = TradeDirection.SELL
            
        if direction is None or sentiment.get("confidence", 0) < 0.6:
            conclusion = f"No strong signal to change position. Recommend HOLD. Current PNL: ${pos.pnl:.2f}."
            await self._update_investigation(inv, status=InvestigationStatus.SKIPPED, conclusion=conclusion)
            return None

        action_text = "DOUBLE DOWN (BUY MORE)" if direction == TradeDirection.BUY else "CLOSE POSITION (SELL)"
        
        reasoning, confidence = await self.llm.generate_trading_reasoning(
            market_question=question,
            outcome=outcome,
            direction=direction.value,
            price=current_price,
            news_summary=news_text[:800],
            sentiment_data=sentiment,
        )
        
        reasoning = f"[{action_text} ADVICE] " + reasoning

        conclusion = f"Signal generated: {direction.value} {outcome} at {current_price:.2f} (Confidence: {confidence:.0%})"
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
            market_url=pos.market_url,
        )
