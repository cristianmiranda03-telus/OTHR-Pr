"""
WebSocket connection manager — broadcasts real-time events to all connected clients.
"""
import asyncio
import json
import logging
from datetime import datetime
from typing import Any
from fastapi import WebSocket
from .models import WsMessage, WsEventType

logger = logging.getLogger(__name__)


class WebSocketManager:
    def __init__(self):
        self._connections: list[WebSocket] = []
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self._connections.append(websocket)
        logger.info(f"WS client connected. Total: {len(self._connections)}")
        await self._send_to(websocket, WsMessage(
            event=WsEventType.SYSTEM,
            data={"message": "Connected to Polymarket Trader WebSocket"},
        ))

    async def disconnect(self, websocket: WebSocket):
        async with self._lock:
            if websocket in self._connections:
                self._connections.remove(websocket)
        logger.info(f"WS client disconnected. Total: {len(self._connections)}")

    async def broadcast(self, event: WsEventType, data: Any):
        message = WsMessage(event=event, data=data)
        payload = message.model_dump_json()
        dead: list[WebSocket] = []

        async with self._lock:
            connections = list(self._connections)

        for ws in connections:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)

        if dead:
            async with self._lock:
                for ws in dead:
                    self._connections.remove(ws)

    async def _send_to(self, websocket: WebSocket, message: WsMessage):
        try:
            await websocket.send_text(message.model_dump_json())
        except Exception as exc:
            logger.warning(f"Failed to send WS message: {exc}")

    @property
    def connection_count(self) -> int:
        return len(self._connections)


ws_manager = WebSocketManager()
