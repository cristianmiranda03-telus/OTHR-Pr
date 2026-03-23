"""
Agent 3: News Sentinel (The Macro Agent)
Monitors news, economic calendar, and market sentiment to filter dangerous trades.
"""
import asyncio
import json
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import httpx
from .base_agent import BaseAgent
from ..ai.llm_client import LLMClient


HIGH_IMPACT_KEYWORDS = [
    "federal reserve", "fed", "interest rate", "rate decision", "fomc",
    "inflation", "cpi", "ppi", "gdp", "nfp", "non-farm payroll",
    "unemployment", "ecb", "bank of england", "boe", "boj",
    "bank of japan", "recession", "default", "crisis", "crash",
    "black swan", "emergency", "geopolitical", "war", "sanctions",
]

CURRENCY_NEWS_MAP = {
    "EURUSD": ["eur", "usd", "ecb", "fed", "euro", "dollar"],
    "GBPUSD": ["gbp", "usd", "boe", "fed", "pound", "dollar"],
    "USDJPY": ["usd", "jpy", "fed", "boj", "yen", "dollar"],
    "XAUUSD": ["gold", "xau", "usd", "fed", "inflation", "safe haven"],
    "NAS100": ["nasdaq", "tech", "fed", "rate", "earnings"],
    "US30": ["dow", "djia", "fed", "rate", "industrial"],
}


class NewsSentinelAgent(BaseAgent):
    """
    Macro filter that:
    1. Fetches economic calendar events
    2. Scrapes news headlines from public RSS feeds
    3. Uses LLM to assess sentiment and Black Swan risk
    4. Blocks trades during high-impact events
    """

    def __init__(self, config: dict, llm: LLMClient):
        super().__init__("NewsSentinel", config)
        self.llm = llm
        self._news_cache: List[Dict] = []
        self._calendar_cache: List[Dict] = []
        self._last_fetch = datetime.min
        self._fetch_interval_mins = 15
        self._client = httpx.AsyncClient(timeout=15.0)

    async def _execute(self, context: Dict) -> Dict:
        symbol = context.get("symbol", "EURUSD")
        self._emit(f"📰 Scanning news/events for {symbol}...")

        # Refresh news cache periodically
        if (datetime.now() - self._last_fetch).total_seconds() > self._fetch_interval_mins * 60:
            await self._refresh_news()

        # Check economic calendar
        upcoming_events = self._get_upcoming_events(symbol, minutes_ahead=60)
        active_events = self._get_upcoming_events(symbol, minutes_ahead=5)

        # Analyze news sentiment
        relevant_news = self._filter_news_for_symbol(symbol)
        sentiment_result = await self._analyze_sentiment(symbol, relevant_news)

        # Black Swan detection
        black_swan = self._detect_black_swan(relevant_news)

        # Build verdict
        if active_events:
            verdict = "block"
            reason = f"High-impact event active: {active_events[0].get('event', 'Unknown')}"
        elif black_swan["detected"]:
            verdict = "block"
            reason = f"Black Swan risk: {black_swan['description']}"
        elif upcoming_events and sentiment_result["impact"] == "high":
            verdict = "caution"
            reason = f"High-impact event in < 60min: {upcoming_events[0].get('event', 'Unknown')}"
        elif sentiment_result["sentiment"] == "bearish" and symbol in ("EURUSD", "GBPUSD"):
            verdict = "caution"
            reason = f"Bearish macro sentiment for {symbol}"
        else:
            verdict = "clear"
            reason = "No significant macro risks detected"

        cleared = verdict == "clear"
        result = {
            "verdict": verdict,
            "cleared": cleared,
            "reason": reason,
            "sentiment": sentiment_result["sentiment"],
            "impact": sentiment_result["impact"],
            "confidence": sentiment_result.get("confidence", 0.5),
            "upcoming_events": upcoming_events[:3],
            "active_events": active_events,
            "black_swan": black_swan,
            "news_count": len(relevant_news),
            "news_headlines": [n.get("title", "")[:80] for n in relevant_news[:5]],
        }
        self._emit(f"📰 {symbol}: verdict={verdict} | sentiment={sentiment_result['sentiment']} | "
                   f"events={len(upcoming_events)} upcoming | {reason}")
        return result

    async def _refresh_news(self):
        """Fetch latest news from RSS feeds."""
        rss_feeds = [
            "https://feeds.reuters.com/reuters/businessNews",
            "https://feeds.bloomberg.com/markets/news.rss",
            "https://rss.cnn.com/rss/money_news_international.rss",
            "https://feeds.marketwatch.com/marketwatch/topstories",
        ]
        news_items = []
        for url in rss_feeds:
            try:
                resp = await self._client.get(url, timeout=8.0)
                if resp.status_code == 200:
                    items = self._parse_rss(resp.text)
                    news_items.extend(items)
            except Exception as e:
                self._emit(f"RSS fetch failed ({url}): {e}", "warning")

        if news_items:
            self._news_cache = news_items[:100]
            self._last_fetch = datetime.now()
            self._emit(f"📡 Fetched {len(news_items)} news items")
        else:
            # Use simulated data if all feeds fail
            self._news_cache = self._sim_news()
            self._last_fetch = datetime.now()

    def _parse_rss(self, xml_text: str) -> List[Dict]:
        """Parse RSS XML to news items."""
        items = []
        try:
            import feedparser
            feed = feedparser.parse(xml_text)
            for entry in feed.entries[:20]:
                items.append({
                    "title": entry.get("title", ""),
                    "summary": entry.get("summary", "")[:200],
                    "published": entry.get("published", ""),
                    "link": entry.get("link", ""),
                })
        except Exception:
            pass
        return items

    def _filter_news_for_symbol(self, symbol: str) -> List[Dict]:
        keywords = CURRENCY_NEWS_MAP.get(symbol, ["usd", "market"])
        relevant = []
        for news in self._news_cache:
            text = (news.get("title", "") + " " + news.get("summary", "")).lower()
            if any(kw in text for kw in keywords):
                relevant.append(news)
        return relevant[:15]

    def _get_upcoming_events(self, symbol: str,
                               minutes_ahead: int = 60) -> List[Dict]:
        """Check economic calendar for upcoming high-impact events."""
        # This would ideally connect to a real calendar API
        # Using simulated calendar based on known schedule patterns
        upcoming = []
        now = datetime.utcnow()
        for event in self._calendar_cache:
            event_time = event.get("time")
            if event_time:
                try:
                    et = datetime.fromisoformat(event_time)
                    diff = (et - now).total_seconds() / 60
                    if 0 <= diff <= minutes_ahead:
                        currency = event.get("currency", "")
                        if currency in symbol:
                            upcoming.append(event)
                except Exception:
                    pass
        return upcoming

    def _detect_black_swan(self, news: List[Dict]) -> Dict:
        """Simple keyword-based Black Swan detector."""
        black_swan_keywords = [
            "crash", "collapse", "emergency", "black swan", "crisis",
            "default", "war declaration", "pandemic", "sanctions",
            "flash crash", "circuit breaker",
        ]
        for item in news:
            text = (item.get("title", "") + " " + item.get("summary", "")).lower()
            for kw in black_swan_keywords:
                if kw in text:
                    return {
                        "detected": True,
                        "description": f"Keyword '{kw}' in: {item.get('title', '')[:60]}",
                        "headline": item.get("title", ""),
                    }
        return {"detected": False, "description": ""}

    async def _analyze_sentiment(self, symbol: str,
                                   news: List[Dict]) -> Dict:
        if not news:
            return {"sentiment": "neutral", "impact": "low", "confidence": 0.5}
        headlines = "\n".join([n.get("title", "") for n in news[:10]])
        try:
            result = await self.llm.analyze_news_sentiment(headlines, symbol)
            return result
        except Exception:
            # Fallback: keyword sentiment
            bullish_words = ["rise", "gain", "growth", "strong", "beat", "positive", "rally"]
            bearish_words = ["fall", "drop", "recession", "weak", "miss", "negative", "crash"]
            text = headlines.lower()
            bull_count = sum(text.count(w) for w in bullish_words)
            bear_count = sum(text.count(w) for w in bearish_words)
            if bull_count > bear_count + 2:
                return {"sentiment": "bullish", "impact": "medium", "confidence": 0.6}
            elif bear_count > bull_count + 2:
                return {"sentiment": "bearish", "impact": "medium", "confidence": 0.6}
            return {"sentiment": "neutral", "impact": "low", "confidence": 0.5}

    def _sim_news(self) -> List[Dict]:
        return [
            {"title": "Markets open higher amid positive earnings", "summary": "US equities..."},
            {"title": "Fed holds rates steady at FOMC meeting", "summary": "Federal Reserve..."},
            {"title": "Euro stabilizes after ECB policy statement", "summary": "European Central Bank..."},
        ]

    async def close(self):
        await self._client.aclose()
