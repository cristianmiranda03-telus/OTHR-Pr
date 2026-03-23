"""
Event Bus - async pub/sub for agent communication and UI broadcasting.
"""
import asyncio
from typing import Any, Callable, Dict, List, Optional
from datetime import datetime
from loguru import logger


class EventBus:
    """
    Lightweight async event bus for decoupled agent communication.
    Agents publish events; the WebSocket manager subscribes to broadcast to UI.
    """

    def __init__(self):
        self._subscribers: Dict[str, List[Callable]] = {}
        self._history: List[Dict] = []
        self._max_history = 1000

    def subscribe(self, event_type: str, handler: Callable):
        if event_type not in self._subscribers:
            self._subscribers[event_type] = []
        self._subscribers[event_type].append(handler)

    def subscribe_all(self, handler: Callable):
        self.subscribe("*", handler)

    async def publish(self, event_type: str, data: Any):
        event = {
            "type": event_type,
            "data": data,
            "timestamp": datetime.now().isoformat(),
        }
        self._history.append(event)
        if len(self._history) > self._max_history:
            self._history = self._history[-800:]

        handlers = self._subscribers.get(event_type, []) + \
                   self._subscribers.get("*", [])

        for handler in handlers:
            try:
                if asyncio.iscoroutinefunction(handler):
                    await handler(event)
                else:
                    handler(event)
            except Exception as e:
                logger.warning(f"EventBus handler error ({event_type}): {e}")

    def get_history(self, event_type: Optional[str] = None,
                    last_n: int = 100) -> List[Dict]:
        if event_type:
            events = [e for e in self._history if e["type"] == event_type]
        else:
            events = self._history
        return events[-last_n:]
