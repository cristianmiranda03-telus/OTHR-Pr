"""
LLM abstraction layer.
- Default provider: FuelXI (OpenAI-compatible REST API at api.fuelix.ai)
- Ready to switch to OpenAI by setting llm.provider=openai in config.ini
- Global rate limiter: max 8 concurrent LLM calls + retry on 429
"""
from __future__ import annotations
import asyncio
import logging
import json
import httpx
from typing import Optional
from .config import get_settings

logger = logging.getLogger(__name__)

# Global concurrency gate shared by ALL LLMClient instances across all agents.
# FuelXI 1-minute window: keep max concurrent calls low to avoid bursting.
_LLM_SEMAPHORE = asyncio.Semaphore(4)
_MAX_RETRIES = 3
_RETRY_BASE_DELAY = 15.0  # seconds — FuelXI resets per 1-minute window


class LLMClient:
    """Unified LLM interface supporting FuelXI and OpenAI."""

    def __init__(self):
        self.settings = get_settings()
        self.provider = self.settings.llm_provider

    async def complete(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        temperature: float = 0.3,
        max_tokens: int = 1024,
    ) -> str:
        async with _LLM_SEMAPHORE:
            if self.provider == "openai":
                return await self._openai_complete(prompt, system_prompt, temperature, max_tokens)
            return await self._fuelxi_complete(prompt, system_prompt, temperature, max_tokens)

    # ─────────────────────── FuelXI (OpenAI-compatible) ──────────────

    async def _fuelxi_complete(
        self,
        prompt: str,
        system_prompt: Optional[str],
        temperature: float,
        max_tokens: int,
    ) -> str:
        url = f"{self.settings.fuelxi_api_url}/chat/completions"
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": self.settings.fuelxi_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.settings.fuelxi_api_key}",
        }

        last_exc = None
        for attempt in range(_MAX_RETRIES):
            try:
                async with httpx.AsyncClient(timeout=90.0) as client:
                    response = await client.post(url, json=payload, headers=headers)
                    response.raise_for_status()
                    data = response.json()
                    return data["choices"][0]["message"]["content"]
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code == 429:
                    wait = _RETRY_BASE_DELAY * (attempt + 1)
                    logger.warning(f"FuelXI 429 rate limit — waiting {wait:.0f}s (attempt {attempt+1}/{_MAX_RETRIES})")
                    last_exc = exc
                    await asyncio.sleep(wait)
                    continue
                logger.error(f"FuelXI HTTP error {exc.response.status_code}: {exc.response.text}")
                return self._fallback_response(prompt)
            except httpx.ConnectError:
                logger.error(f"FuelXI not reachable at {url}. Check api_url and api_key in config.ini.")
                return self._fallback_response(prompt)
            except Exception as exc:
                logger.error(f"FuelXI error: {exc}")
                return self._fallback_response(prompt)

        logger.error(f"FuelXI exhausted {_MAX_RETRIES} retries on 429: {last_exc}")
        return self._fallback_response(prompt)

    # ─────────────────────────── OpenAI ──────────────────────────────

    async def _openai_complete(
        self,
        prompt: str,
        system_prompt: Optional[str],
        temperature: float,
        max_tokens: int,
    ) -> str:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=self.settings.openai_api_key)
            messages = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            messages.append({"role": "user", "content": prompt})

            response = await client.chat.completions.create(
                model=self.settings.openai_model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )
            return response.choices[0].message.content or ""
        except Exception as exc:
            logger.error(f"OpenAI error: {exc}")
            return self._fallback_response(prompt)

    # ─────────────────────────── Helpers ─────────────────────────────

    def _fallback_response(self, _prompt: str) -> str:
        return json.dumps({
            "reasoning": "LLM unavailable — check config.ini credentials.",
            "confidence": 0.0,
            "sentiment": "neutral",
        })

    async def analyze_sentiment(self, text: str, context: str = "") -> dict:
        system = (
            "You are a financial sentiment analyst for prediction markets. "
            "Respond ONLY with a valid JSON object containing: "
            "'sentiment' (bullish/bearish/neutral), "
            "'confidence' (0.0-1.0 float), "
            "'reasoning' (1-2 sentences), "
            "'key_factors' (list of strings max 3 items)."
        )
        prompt = f"Context: {context}\n\nText to analyze:\n{text}"
        raw = await self.complete(prompt, system_prompt=system, temperature=0.2)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {"sentiment": "neutral", "confidence": 0.0, "reasoning": raw[:200], "key_factors": []}

    async def generate_trading_reasoning(
        self,
        market_question: str,
        outcome: str,
        direction: str,
        price: float,
        news_summary: str,
        sentiment_data: dict,
    ) -> tuple[str, float]:
        """Returns (reasoning_text, confidence_score)."""
        system = (
            "You are an expert prediction market trader. "
            "Given market data and news, write a concise, plain-language trading rationale "
            "that anyone can understand. Include: what's happening, why it's an opportunity, "
            "and what the main risk is. "
            "Respond ONLY with JSON: {\"reasoning\": str, \"confidence\": float}. "
            "Keep reasoning under 150 words."
        )
        prompt = (
            f"Market: {market_question}\n"
            f"Outcome: {outcome}\n"
            f"Direction: {direction}\n"
            f"Current price: {price:.3f} (implies {price*100:.1f}% probability)\n"
            f"News summary: {news_summary}\n"
            f"Sentiment: {sentiment_data}\n\n"
            "Write your trading rationale and confidence score (0.0-1.0)."
        )
        raw = await self.complete(prompt, system_prompt=system, temperature=0.3)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            parsed = json.loads(raw[start:end])
            reasoning = parsed.get("reasoning", raw)
            confidence = float(parsed.get("confidence", 0.5))
            return reasoning, max(0.0, min(1.0, confidence))
        except Exception:
            return raw[:300], 0.5

    async def summarize_for_strategy(self, content: str, query: str) -> dict:
        """Summarize research content into actionable strategy insights."""
        system = (
            "You are a quant research analyst for prediction markets. "
            "Extract actionable trading strategies from the content. "
            "Respond ONLY with JSON: "
            "{\"title\": str, \"summary\": str, \"actionable_insights\": [str], \"difficulty\": \"easy|medium|hard\"}."
        )
        prompt = f"Research query: {query}\n\nContent:\n{content[:2000]}"
        raw = await self.complete(prompt, system_prompt=system, temperature=0.2)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {
                "title": query[:60],
                "summary": raw[:200],
                "actionable_insights": [],
                "difficulty": "medium",
            }

    async def evaluate_event_scenarios(
        self, market_question: str, current_price: float, news_context: str, end_date_str: str = ""
    ) -> dict:
        """Generate probable scenarios for a market event."""
        system = (
            "You are an expert prediction market analyst. Given a market question, current price, "
            "and news context, generate 2-4 possible scenarios with probabilities. "
            "Respond ONLY with JSON: {\"scenarios\": [{\"name\": str, \"probability\": float 0-1, "
            "\"description\": str, \"impact\": \"positive|negative|neutral\"}], "
            "\"most_likely_outcome\": str, \"confidence\": float 0-1}."
        )
        prompt = (
            f"Market: {market_question}\n"
            f"Current price: {current_price:.3f} ({current_price*100:.1f}% implied prob.)\n"
            f"Expiry: {end_date_str or 'unknown'}\n\n"
            f"News/Context:\n{news_context[:1500]}\n\n"
            "Generate realistic scenarios."
        )
        raw = await self.complete(prompt, system_prompt=system, temperature=0.3, max_tokens=1200)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {"scenarios": [], "most_likely_outcome": "unknown", "confidence": 0.0}

    async def evaluate_strategy_quality(self, strategy_title: str, strategy_summary: str, insights: list[str]) -> dict:
        """Evaluate the quality and feasibility of a trading strategy."""
        system = (
            "You are a senior quant portfolio manager reviewing trading strategies for prediction markets. "
            "Evaluate the strategy for: feasibility, risk/reward ratio, capital requirements, and edge sustainability. "
            "Respond ONLY with JSON: {\"quality_score\": float 0-1, \"feasibility\": str, "
            "\"risk_reward\": str, \"edge_sustainability\": str, \"recommended_adjustments\": [str], "
            "\"verdict\": \"adopt|modify|reject\"}."
        )
        insights_text = "\n".join(f"- {i}" for i in insights) if insights else "None provided"
        prompt = f"Strategy: {strategy_title}\nSummary: {strategy_summary}\nInsights:\n{insights_text}"
        raw = await self.complete(prompt, system_prompt=system, temperature=0.2, max_tokens=800)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {"quality_score": 0.5, "feasibility": "unknown", "verdict": "modify"}

    async def advise_on_position(
        self, question: str, outcome: str, size: float, avg_price: float,
        current_price: float, pnl: float, pnl_pct: float, news_context: str
    ) -> dict:
        """Generate detailed hold/close/add advice for an open position."""
        system = (
            "You are a professional prediction market portfolio advisor. "
            "Analyze the position and give concrete, actionable advice. "
            "Respond ONLY with JSON: {\"action\": \"HOLD|CLOSE|ADD|PARTIAL_CLOSE\", "
            "\"urgency\": \"low|medium|high|critical\", \"hold_duration\": str (e.g. '3-5 days'), "
            "\"scenarios\": [{\"name\": str, \"probability\": float 0-1, \"description\": str, "
            "\"impact\": \"positive|negative|neutral\"}], "
            "\"reasoning\": str (2-3 sentences), \"risk_level\": \"low|medium|high\"}."
        )
        prompt = (
            f"Position: {question}\nOutcome held: {outcome}\n"
            f"Size: {size:.2f} shares | Avg price: {avg_price:.3f} | Current: {current_price:.3f}\n"
            f"P&L: ${pnl:.2f} ({pnl_pct:.1f}%)\n\n"
            f"Latest news/context:\n{news_context[:1200]}\n\n"
            "What should the trader do?"
        )
        raw = await self.complete(prompt, system_prompt=system, temperature=0.3, max_tokens=1000)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {"action": "HOLD", "urgency": "low", "reasoning": raw[:200], "scenarios": []}

    async def analyze_entry_opportunity(
        self, question: str, price: float, end_date_str: str, news_context: str, volume: float = 0
    ) -> dict:
        """Prepare detailed entry analysis for a new market."""
        system = (
            "You are an expert prediction market entry analyst. "
            "Evaluate whether this market represents a good entry opportunity. "
            "Respond ONLY with JSON: {\"should_enter\": bool, \"direction\": \"BUY|SELL\", "
            "\"confidence\": float 0-1, \"expected_return_pct\": float, "
            "\"risk_score\": float 0-1 (0=safe, 1=very risky), "
            "\"recommended_size_pct\": float (% of portfolio), "
            "\"reasoning\": str (2-3 sentences), \"key_risks\": [str]}."
        )
        prompt = (
            f"Market: {question}\n"
            f"Current price: {price:.3f} ({price*100:.1f}% implied prob.)\n"
            f"Expiry: {end_date_str}\nVolume: ${volume:,.0f}\n\n"
            f"Context/News:\n{news_context[:1200]}\n\n"
            "Should the trader enter this market?"
        )
        raw = await self.complete(prompt, system_prompt=system, temperature=0.3, max_tokens=800)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {"should_enter": False, "confidence": 0.0, "reasoning": raw[:200]}

    async def btc_quick_signal(
        self,
        market_question: str,
        yes_price: float,
        days_left: float,
        volume: float,
    ) -> dict:
        """Ultra-fast BTC market signal analysis. Returns direction, confidence, win_prob, urgency."""
        system = (
            "You are an expert Bitcoin prediction market trader focused on short-term scalping. "
            "Analyze the market question and current implied probability to find a trading edge. "
            "Consider whether the market price seems mispriced given current BTC conditions. "
            "Respond ONLY with valid JSON (no extra text): "
            "{\"direction\": \"BUY|SELL\", "
            "\"win_probability\": float 0-1, "
            "\"confidence\": float 0-1, "
            "\"urgency\": \"high|medium|low\", "
            "\"reasoning\": str, "
            "\"key_signal\": str}"
        )
        prompt = (
            f"Bitcoin prediction market: {market_question}\n"
            f"Current YES price: {yes_price:.3f} ({yes_price*100:.0f}% implied probability)\n"
            f"Days to expiry: {days_left:.1f}\n"
            f"Volume: ${volume:,.0f}\n\n"
            "Is there a scalping edge here? Give your direction and estimated true win probability."
        )
        raw = await self.complete(prompt, system_prompt=system, temperature=0.2, max_tokens=350)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {
                "direction": "BUY",
                "win_probability": yes_price,
                "confidence": 0.0,
                "urgency": "low",
                "reasoning": raw[:200],
                "key_signal": "",
            }

    async def btc_sentiment_signal(
        self,
        market_question: str,
        yes_price: float,
        hours_left: float,
    ) -> dict:
        """Quick BTC sentiment check — parallel partner to btc_quick_signal."""
        system = (
            "You are a Bitcoin market sentiment expert. "
            "Respond ONLY with valid JSON (no extra text): "
            "{\"btc_sentiment\": \"bullish|bearish|neutral\", "
            "\"price_mispriced\": bool, "
            "\"suggested_direction\": \"YES|NO\", "
            "\"edge_estimate\": float 0-1}"
        )
        prompt = (
            f"Bitcoin market: {market_question}\n"
            f"Current YES price: {yes_price:.3f} | Expires in {hours_left:.0f}h\n"
            "Is the market fairly priced or is there a clear edge?"
        )
        raw = await self.complete(prompt, system_prompt=system, temperature=0.2, max_tokens=150)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {
                "btc_sentiment": "neutral",
                "price_mispriced": False,
                "suggested_direction": "YES",
                "edge_estimate": 0.0,
            }

    async def rank_opportunities(self, opportunities: list[dict], balance: float) -> dict:
        """Rank and prioritize a list of trading opportunities."""
        system = (
            "You are a quantitative portfolio optimizer for prediction markets. "
            "Given a list of potential trades and available capital, rank them by: "
            "expected value, risk-adjusted return, opportunity cost, and capital efficiency. "
            "Respond ONLY with JSON: {\"ranked\": [{\"market_id\": str, \"priority\": int (1=best), "
            "\"recommended_size_usdc\": float, \"expected_return_pct\": float, "
            "\"opportunity_cost_note\": str}], \"portfolio_note\": str}."
        )
        opp_text = "\n".join(
            f"- [{o.get('market_id','')}] {o.get('question','')}: "
            f"price={o.get('price',0):.3f}, conf={o.get('confidence',0):.0%}, "
            f"direction={o.get('direction','?')}, expiry={o.get('end_date','?')}"
            for o in opportunities[:15]
        )
        prompt = f"Available capital: ${balance:,.2f}\n\nOpportunities:\n{opp_text}"
        raw = await self.complete(prompt, system_prompt=system, temperature=0.2, max_tokens=1500)
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            return json.loads(raw[start:end])
        except Exception:
            return {"ranked": [], "portfolio_note": raw[:200]}


llm_client = LLMClient()
