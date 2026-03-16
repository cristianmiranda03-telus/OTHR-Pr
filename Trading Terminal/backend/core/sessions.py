"""Trading sessions (market hours) for major venues."""
from pydantic import BaseModel
from typing import Literal

SessionId = Literal["sydney", "tokyo", "london", "new_york", "overlap_london_ny"]


class Session(BaseModel):
    name: str
    open: str  # "HH:MM"
    close: str
    tz: str
    description: str


SESSIONS: dict[str, Session] = {
    "sydney": Session(
        name="Sydney",
        open="22:00",
        close="07:00",
        tz="Australia/Sydney",
        description="Asian pre-open",
    ),
    "tokyo": Session(
        name="Tokyo",
        open="00:00",
        close="09:00",
        tz="Asia/Tokyo",
        description="Asian session",
    ),
    "london": Session(
        name="London",
        open="08:00",
        close="17:00",
        tz="Europe/London",
        description="European session",
    ),
    "new_york": Session(
        name="New York",
        open="13:00",
        close="22:00",
        tz="America/New_York",
        description="US session",
    ),
    "overlap_london_ny": Session(
        name="London / NY Overlap",
        open="13:00",
        close="17:00",
        tz="UTC",
        description="Highest liquidity",
    ),
}


def get_sessions() -> dict[str, dict]:
    return {k: v.model_dump() for k, v in SESSIONS.items()}
