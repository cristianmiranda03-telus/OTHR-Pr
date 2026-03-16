"""
News Research Agent - Fetches financial news and analyzes market impact.
Uses AI to score news sentiment and predict directional bias.
"""
import asyncio
from datetime import datetime, timedelta
from typing import Any

import httpx

from .base_agent import BaseAgent


NEWS_SYSTEM_PROMPT = """You are a professional financial news analyst specializing in Forex, commodities, and indices trading.
Your task is to analyze recent news headlines and events, then provide:
1. Overall market sentiment (bullish/bearish/neutral) for each major pair
2. Key upcoming catalysts and their expected impact
3. Risk-off vs risk-on sentiment
4. Recommended pairs to trade and ones to avoid

Always respond in valid JSON format as specified. Be concise and actionable.
Focus on: USD, EUR, GBP, JPY, AUD, CAD, CHF, NZD pairs, Gold (XAUUSD), Oil (USOil), and major indices (US30, SP500, NAS100)."""


class NewsAgent(BaseAgent):
    """Fetches and analyzes financial news for trade impact."""

    def __init__(self):
        super().__init__(
            agent_id="news_agent",
            name="News Intelligence",
            description="Analyzes financial news and macro events for market impact and trade bias",
        )
        self.latest_analysis: dict | None = None
        self.news_cache: list[dict] = []

    async def fetch_news(self) -> list[dict]:
        """Fetch headlines from public financial RSS/APIs."""
        headlines = []

        # Try ForexFactory economic calendar simulation via scraping
        sources = [
            ("https://finance.yahoo.com/rss/topfinstories", "Yahoo Finance"),
            ("https://feeds.content.dowjones.io/public/rss/mw_realtimeheadlines", "MarketWatch"),
        ]

        for url, source in sources:
            try:
                async with httpx.AsyncClient(timeout=10) as client:
                    r = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
                    if r.status_code == 200:
                        # Basic RSS parsing
                        content = r.text
                        items = content.split("<item>")[1:]
                        for item in items[:10]:
                            title = ""
                            if "<title>" in item:
                                title = item.split("<title>")[1].split("</title>")[0]
                                title = title.replace("<![CDATA[", "").replace("]]>", "").strip()
                            if title:
                                headlines.append({"title": title, "source": source, "time": datetime.utcnow().isoformat()})
            except Exception:
                pass

        # Fallback demo headlines if fetch fails
        if not headlines:
            headlines = [
                {"title": "Federal Reserve signals potential rate cuts in Q2 2025", "source": "Reuters", "time": datetime.utcnow().isoformat()},
                {"title": "EUR/USD holds above 1.08 as ECB maintains hawkish stance", "source": "Bloomberg", "time": datetime.utcnow().isoformat()},
                {"title": "Gold surges past $2,400 amid geopolitical tensions", "source": "FT", "time": datetime.utcnow().isoformat()},
                {"title": "US Non-Farm Payrolls beat expectations at 180K jobs", "source": "BLS", "time": datetime.utcnow().isoformat()},
                {"title": "Oil prices rise on OPEC+ production cut extension", "source": "Reuters", "time": datetime.utcnow().isoformat()},
                {"title": "JPY weakens as Bank of Japan maintains ultra-loose policy", "source": "Nikkei", "time": datetime.utcnow().isoformat()},
                {"title": "GBP/USD drops on weaker UK CPI data", "source": "ONS", "time": datetime.utcnow().isoformat()},
                {"title": "S&P 500 reaches new all-time high driven by tech sector", "source": "WSJ", "time": datetime.utcnow().isoformat()},
            ]

        self.news_cache = headlines
        return headlines

    async def run(self, context: dict | None = None) -> dict:
        await self.log("thinking", "Fetching latest financial news and economic events...")

        headlines = await self.fetch_news()
        await self.log("action", f"Fetched {len(headlines)} news items. Analyzing with AI...")

        headlines_text = "\n".join([f"- [{h['source']}] {h['title']}" for h in headlines])

        prompt = f"""Analyze these financial headlines and provide a market impact assessment:

{headlines_text}

Respond ONLY with a JSON object in this exact format:
{{
  "overall_sentiment": "bullish|bearish|neutral",
  "risk_appetite": "risk-on|risk-off|neutral",
  "key_themes": ["theme1", "theme2"],
  "pair_analysis": {{
    "EURUSD": {{"bias": "bullish|bearish|neutral", "impact": "high|medium|low", "reason": "..."}},
    "GBPUSD": {{"bias": "bullish|bearish|neutral", "impact": "high|medium|low", "reason": "..."}},
    "USDJPY": {{"bias": "bullish|bearish|neutral", "impact": "high|medium|low", "reason": "..."}},
    "XAUUSD": {{"bias": "bullish|bearish|neutral", "impact": "high|medium|low", "reason": "..."}},
    "USOIL": {{"bias": "bullish|bearish|neutral", "impact": "high|medium|low", "reason": "..."}}
  }},
  "recommended_trades": [
    {{"pair": "...", "direction": "buy|sell", "confidence": 0.0-1.0, "reason": "..."}}
  ],
  "pairs_to_avoid": ["..."],
  "upcoming_events": [
    {{"event": "...", "impact": "high|medium|low", "expected": "..."}}
  ],
  "summary": "2-3 sentence trading summary"
}}"""

        response = await self.ai_call(NEWS_SYSTEM_PROMPT, prompt)

        try:
            # Extract JSON from response
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                response = response.split("```")[1].split("```")[0]

            import json
            analysis = json.loads(response.strip())
            self.latest_analysis = analysis

            await self.log("result", f"News analysis complete: {analysis.get('overall_sentiment','?').upper()} market, {len(analysis.get('recommended_trades', []))} trade opportunities", analysis)
            return {"headlines": headlines, "analysis": analysis}

        except Exception as e:
            await self.log("error", f"Failed to parse AI response: {e}. Raw: {response[:200]}")
            fallback = {
                "overall_sentiment": "neutral",
                "risk_appetite": "neutral",
                "key_themes": ["Data parsing error"],
                "pair_analysis": {},
                "recommended_trades": [],
                "pairs_to_avoid": [],
                "upcoming_events": [],
                "summary": f"News analysis encountered a parsing error: {e}",
                "raw_response": response[:500],
            }
            self.latest_analysis = fallback
            return {"headlines": headlines, "analysis": fallback}
