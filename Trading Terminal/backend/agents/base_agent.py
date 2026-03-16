"""
Base AI Agent - Fuelix API integration with multi-provider support.
All agents inherit from this class.
"""
import asyncio
import time
import json
import logging
from typing import Any, Callable
from datetime import datetime
from enum import Enum

import httpx

from config.settings import settings

logger = logging.getLogger(__name__)


class AgentStatus(str, Enum):
    IDLE = "idle"
    THINKING = "thinking"
    RUNNING = "running"
    DONE = "done"
    ERROR = "error"
    WAITING = "waiting"


class AgentMessage:
    """A message in the agent's activity log."""
    def __init__(self, agent_id: str, level: str, content: str, data: Any = None):
        self.agent_id = agent_id
        self.level = level  # info | thinking | action | result | error
        self.content = content
        self.data = data
        self.timestamp = datetime.utcnow().isoformat()

    def to_dict(self) -> dict:
        return {
            "agent_id": self.agent_id,
            "level": self.level,
            "content": self.content,
            "data": self.data,
            "timestamp": self.timestamp,
        }


# Global broadcast channel: coroutines can subscribe to receive real-time messages
_subscribers: list[Callable] = []


def subscribe(callback: Callable):
    _subscribers.append(callback)


def unsubscribe(callback: Callable):
    if callback in _subscribers:
        _subscribers.remove(callback)


async def broadcast(msg: AgentMessage):
    """Broadcast a message to all WebSocket subscribers."""
    payload = msg.to_dict()
    dead = []
    for cb in list(_subscribers):
        try:
            if asyncio.iscoroutinefunction(cb):
                await cb(payload)
            else:
                cb(payload)
        except Exception:
            dead.append(cb)
    for cb in dead:
        _subscribers.remove(cb)


class BaseAgent:
    """Base class for all Quant-Joker AI agents."""

    def __init__(self, agent_id: str, name: str, description: str):
        self.agent_id = agent_id
        self.name = name
        self.description = description
        self.status = AgentStatus.IDLE
        self.last_result: Any = None
        self.last_run: str | None = None
        self.error: str | None = None
        self.run_count: int = 0
        self._log: list[dict] = []

    # ------------------------------------------------------------------ #
    # Logging                                                              #
    # ------------------------------------------------------------------ #
    async def log(self, level: str, content: str, data: Any = None):
        msg = AgentMessage(self.agent_id, level, content, data)
        self._log.append(msg.to_dict())
        if len(self._log) > 500:
            self._log = self._log[-500:]
        await broadcast(msg)
        logger.info("[%s] %s: %s", self.agent_id, level, content)

    def get_log(self) -> list[dict]:
        return self._log[-100:]

    def to_dict(self) -> dict:
        return {
            "agent_id": self.agent_id,
            "name": self.name,
            "description": self.description,
            "status": self.status,
            "last_run": self.last_run,
            "run_count": self.run_count,
            "error": self.error,
        }

    # ------------------------------------------------------------------ #
    # AI Call                                                              #
    # ------------------------------------------------------------------ #
    async def ai_call(
        self,
        system_prompt: str,
        user_message: str,
        temperature: float = 0.3,
        max_tokens: int = 2048,
    ) -> str:
        """
        Call the configured AI provider (Fuelix by default).
        Returns the assistant's reply as a string.
        """
        provider = settings.AI_PROVIDER.lower()
        if provider == "fuelix":
            return await self._call_fuelix(system_prompt, user_message, temperature, max_tokens)
        elif provider == "openai":
            return await self._call_openai(system_prompt, user_message, temperature, max_tokens)
        elif provider == "gemini":
            return await self._call_gemini(system_prompt, user_message, temperature, max_tokens)
        else:
            return await self._call_fuelix(system_prompt, user_message, temperature, max_tokens)

    async def _call_fuelix(self, system: str, user: str, temp: float, max_tok: int) -> str:
        payload = {
            "model": settings.FUELIX_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temp,
            "max_tokens": max_tok,
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {settings.FUELIX_API_KEY}",
        }
        try:
            async with httpx.AsyncClient(timeout=60) as client:
                r = await client.post(
                    f"{settings.FUELIX_BASE_URL}/chat/completions",
                    json=payload,
                    headers=headers,
                )
                r.raise_for_status()
                data = r.json()
                return data["choices"][0]["message"]["content"]
        except Exception as e:
            await self.log("error", f"AI call failed: {e}")
            return f"[AI Error: {e}]"

    async def _call_openai(self, system: str, user: str, temp: float, max_tok: int) -> str:
        payload = {
            "model": settings.OPENAI_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temp,
            "max_tokens": max_tok,
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
        }
        try:
            async with httpx.AsyncClient(timeout=60) as client:
                r = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    json=payload,
                    headers=headers,
                )
                r.raise_for_status()
                data = r.json()
                return data["choices"][0]["message"]["content"]
        except Exception as e:
            await self.log("error", f"OpenAI call failed: {e}")
            return f"[AI Error: {e}]"

    async def _call_gemini(self, system: str, user: str, temp: float, max_tok: int) -> str:
        payload = {
            "model": settings.GEMINI_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temp,
            "max_tokens": max_tok,
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {settings.GEMINI_API_KEY}",
        }
        try:
            async with httpx.AsyncClient(timeout=60) as client:
                r = await client.post(
                    "https://api.openai.com/v1/chat/completions",  # Gemini OpenAI-compat endpoint
                    json=payload,
                    headers=headers,
                )
                r.raise_for_status()
                data = r.json()
                return data["choices"][0]["message"]["content"]
        except Exception as e:
            await self.log("error", f"Gemini call failed: {e}")
            return f"[AI Error: {e}]"

    # ------------------------------------------------------------------ #
    # Lifecycle                                                            #
    # ------------------------------------------------------------------ #
    async def run(self, context: dict | None = None) -> Any:
        """Override in subclasses to implement agent logic."""
        raise NotImplementedError

    async def safe_run(self, context: dict | None = None) -> Any:
        """Wrap run() with status tracking and error handling."""
        self.status = AgentStatus.RUNNING
        self.error = None
        await self.log("info", f"Agent {self.name} starting...")
        try:
            result = await self.run(context)
            self.last_result = result
            self.last_run = datetime.utcnow().isoformat()
            self.run_count += 1
            self.status = AgentStatus.DONE
            await self.log("result", f"Agent {self.name} completed.")
            return result
        except Exception as e:
            self.error = str(e)
            self.status = AgentStatus.ERROR
            await self.log("error", f"Agent {self.name} error: {e}")
            return None
