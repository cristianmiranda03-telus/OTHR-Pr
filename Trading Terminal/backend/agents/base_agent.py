"""
Base Agent - Common interface for all trading agents.
"""
import asyncio
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any, Dict, Optional
from enum import Enum
from loguru import logger


class AgentStatus(str, Enum):
    IDLE = "idle"
    RUNNING = "running"
    THINKING = "thinking"
    ERROR = "error"
    HALTED = "halted"


class BaseAgent(ABC):
    """Base class providing common agent infrastructure."""

    def __init__(self, name: str, config: dict):
        self.name = name
        self.config = config
        self.status = AgentStatus.IDLE
        self.last_run: Optional[datetime] = None
        self.last_result: Optional[Dict] = None
        self.error_count = 0
        self.run_count = 0
        self._log_buffer: list = []
        self.log = logger.bind(agent=name)

    async def run(self, context: Dict) -> Dict:
        """Execute agent logic with status tracking."""
        self.status = AgentStatus.RUNNING
        self.last_run = datetime.now()
        self.run_count += 1
        self._emit(f"▶ {self.name} starting")
        try:
            result = await self._execute(context)
            self.last_result = result
            self.status = AgentStatus.IDLE
            self.error_count = 0
            self._emit(f"✓ {self.name} completed")
            return result
        except Exception as e:
            self.error_count += 1
            self.status = AgentStatus.ERROR
            error_msg = f"❌ {self.name} error: {e}"
            self._emit(error_msg)
            self.log.exception(error_msg)
            return {"error": str(e), "agent": self.name, "success": False}

    @abstractmethod
    async def _execute(self, context: Dict) -> Dict:
        """Agent-specific logic to implement."""
        ...

    def _emit(self, message: str, level: str = "info"):
        """Add message to log buffer and emit to logger."""
        entry = {
            "time": datetime.now().isoformat(),
            "agent": self.name,
            "message": message,
            "level": level,
        }
        self._log_buffer.append(entry)
        if len(self._log_buffer) > 500:
            self._log_buffer = self._log_buffer[-400:]
        getattr(self.log, level)(message)

    def get_status_dict(self) -> Dict:
        return {
            "name": self.name,
            "status": self.status.value,
            "last_run": self.last_run.isoformat() if self.last_run else None,
            "run_count": self.run_count,
            "error_count": self.error_count,
        }

    def get_logs(self, last_n: int = 50) -> list:
        return self._log_buffer[-last_n:]
