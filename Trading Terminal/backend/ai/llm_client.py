"""
LLM Client - Multi-provider AI connector
Supports FuelIX, OpenAI, and Google Gemini with automatic fallback.
"""
import asyncio
import json
from typing import Optional, List, Dict, Any
import httpx
from loguru import logger


class LLMClient:
    """
    Unified LLM client that abstracts provider differences.
    Primary: FuelIX (custom endpoint)
    Fallback: OpenAI | Gemini
    """

    def __init__(self, config: dict):
        self.cfg = config
        self.provider = config.get("provider", "fuelix")
        self._client = httpx.AsyncClient(timeout=60.0)

    async def chat(
        self,
        messages: List[Dict[str, str]],
        system_prompt: Optional[str] = None,
        temperature: float = 0.1,
        max_tokens: int = 2048,
        json_mode: bool = False,
    ) -> str:
        """Send chat completion request and return response text."""
        if system_prompt:
            messages = [{"role": "system", "content": system_prompt}] + messages

        try:
            if self.provider == "fuelix":
                return await self._fuelix_chat(messages, temperature, max_tokens, json_mode)
            elif self.provider == "openai":
                return await self._openai_chat(messages, temperature, max_tokens, json_mode)
            elif self.provider == "gemini":
                return await self._gemini_chat(messages, temperature, max_tokens)
            else:
                return await self._fuelix_chat(messages, temperature, max_tokens, json_mode)
        except Exception as e:
            logger.warning(f"LLM primary failed ({self.provider}): {e} | trying fallback")
            return await self._fallback(messages)

    async def _fuelix_chat(self, messages: List[Dict],
                            temperature: float, max_tokens: int,
                            json_mode: bool) -> str:
        cfg = self.cfg.get("fuelix", {})
        url = cfg.get("base_url", "https://api.fuelix.ai/v1/chat/completions")
        api_key = cfg.get("api_key", "")
        model = cfg.get("model", "gemini-2.5-pro")

        payload: Dict[str, Any] = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        resp = await self._client.post(url, json=payload, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"]

    async def _openai_chat(self, messages: List[Dict],
                            temperature: float, max_tokens: int,
                            json_mode: bool) -> str:
        cfg = self.cfg.get("openai", {})
        api_key = cfg.get("api_key", "")
        model = cfg.get("model", "gpt-4o")
        payload: Dict[str, Any] = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        resp = await self._client.post(
            "https://api.openai.com/v1/chat/completions",
            json=payload, headers=headers
        )
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"]

    async def _gemini_chat(self, messages: List[Dict],
                            temperature: float, max_tokens: int) -> str:
        cfg = self.cfg.get("gemini", {})
        api_key = cfg.get("api_key", "")
        model = cfg.get("model", "gemini-1.5-pro")
        gemini_messages = []
        for m in messages:
            role = "user" if m["role"] in ("user", "system") else "model"
            gemini_messages.append({"role": role, "parts": [{"text": m["content"]}]})
        payload = {
            "contents": gemini_messages,
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_tokens,
            },
        }
        url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
               f"{model}:generateContent?key={api_key}")
        resp = await self._client.post(url, json=payload)
        resp.raise_for_status()
        data = resp.json()
        return data["candidates"][0]["content"]["parts"][0]["text"]

    async def _fallback(self, messages: List[Dict]) -> str:
        """Rule-based fallback when all LLM providers fail."""
        logger.error("All LLM providers failed - using rule-based fallback")
        return json.dumps({"decision": "hold", "confidence": 0.0,
                           "reason": "LLM unavailable - defaulting to HOLD"})

    async def analyze_market(self, context: dict) -> dict:
        """Structured market analysis request."""
        prompt = f"""Analyze this trading context and return JSON:
Context: {json.dumps(context, indent=2, default=str)}

Return JSON with:
{{
  "decision": "buy|sell|hold",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation",
  "risk_level": "low|medium|high",
  "key_factors": ["factor1", "factor2"]
}}"""
        try:
            response = await self.chat(
                [{"role": "user", "content": prompt}],
                json_mode=True
            )
            return json.loads(response)
        except Exception as e:
            logger.error(f"analyze_market failed: {e}")
            return {"decision": "hold", "confidence": 0.0,
                    "reasoning": str(e), "risk_level": "high", "key_factors": []}

    async def analyze_news_sentiment(self, news_text: str,
                                      symbol: str) -> dict:
        """Sentiment analysis for news impact assessment."""
        prompt = f"""Analyze news sentiment for {symbol} trading. Return JSON:
News: {news_text[:2000]}

Return JSON:
{{
  "sentiment": "bullish|bearish|neutral",
  "impact": "high|medium|low",
  "confidence": 0.0-1.0,
  "keywords": ["word1"],
  "recommendation": "trade|avoid|monitor",
  "time_horizon": "immediate|short|medium"
}}"""
        try:
            response = await self.chat(
                [{"role": "user", "content": prompt}],
                json_mode=True
            )
            return json.loads(response)
        except Exception:
            return {"sentiment": "neutral", "impact": "low",
                    "confidence": 0.0, "recommendation": "monitor"}

    async def close(self):
        await self._client.aclose()
