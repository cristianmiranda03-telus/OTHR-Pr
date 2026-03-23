"""
Trading Sessions Manager
NYSE, LSE, TSE session detection with volatility windows for optimal scalping.
"""
from datetime import datetime, time
import pytz
from typing import Dict, List, Optional
from dataclasses import dataclass


@dataclass
class Session:
    name: str
    timezone: str
    open_time: time
    close_time: time
    peak_start: time
    peak_end: time
    currency_pairs: List[str]
    indices: List[str]


SESSIONS: Dict[str, Session] = {
    "tse": Session(
        name="Tokyo Stock Exchange",
        timezone="Asia/Tokyo",
        open_time=time(9, 0),
        close_time=time(15, 30),
        peak_start=time(9, 0),
        peak_end=time(11, 30),
        currency_pairs=["USDJPY", "EURJPY", "GBPJPY", "AUDJPY"],
        indices=["JP225", "N225"],
    ),
    "lse": Session(
        name="London Stock Exchange",
        timezone="Europe/London",
        open_time=time(8, 0),
        close_time=time(16, 30),
        peak_start=time(8, 0),
        peak_end=time(10, 30),
        currency_pairs=["GBPUSD", "EURGBP", "GBPJPY", "EURUSD", "USDCHF"],
        indices=["UK100", "GER40", "FRA40"],
    ),
    "nyse": Session(
        name="New York Stock Exchange",
        timezone="America/New_York",
        open_time=time(9, 30),
        close_time=time(16, 0),
        peak_start=time(9, 30),
        peak_end=time(11, 30),
        currency_pairs=["EURUSD", "GBPUSD", "USDCAD", "USDJPY", "XAUUSD"],
        indices=["NAS100", "US30", "US500", "SPX500"],
    ),
    "forex_london_ny_overlap": Session(
        name="London-New York Overlap",
        timezone="UTC",
        open_time=time(13, 30),
        close_time=time(16, 30),
        peak_start=time(13, 30),
        peak_end=time(15, 30),
        currency_pairs=["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "XAUUSD"],
        indices=["NAS100", "US30"],
    ),
}


class SessionManager:
    """Determines active sessions and provides scalping quality scores."""

    def __init__(self, config: Optional[dict] = None):
        self.config = config or {}
        self.utc = pytz.UTC

    def now_utc(self) -> datetime:
        return datetime.now(tz=self.utc)

    def get_active_sessions(self, dt: Optional[datetime] = None) -> List[str]:
        """Return list of currently active session names."""
        dt = dt or self.now_utc()
        active = []
        for key, session in SESSIONS.items():
            tz = pytz.timezone(session.timezone)
            local_time = dt.astimezone(tz).time()
            if session.open_time <= local_time < session.close_time:
                active.append(key)
        return active

    def is_peak_volatility(self, session_key: str,
                            dt: Optional[datetime] = None) -> bool:
        """True if within the peak volatility window of the session."""
        dt = dt or self.now_utc()
        if session_key not in SESSIONS:
            return False
        session = SESSIONS[session_key]
        tz = pytz.timezone(session.timezone)
        local_time = dt.astimezone(tz).time()
        return session.peak_start <= local_time < session.peak_end

    def scalping_score(self, symbol: str,
                       dt: Optional[datetime] = None) -> float:
        """
        Score 0-100 for scalping opportunity based on:
        - Active sessions
        - Peak volatility windows
        - Symbol relevance to sessions
        """
        dt = dt or self.now_utc()
        active = self.get_active_sessions(dt)
        if not active:
            return 0.0

        score = 0.0
        for key in active:
            session = SESSIONS[key]
            base_score = 50.0
            if symbol in session.currency_pairs or symbol in session.indices:
                base_score += 25.0
            if self.is_peak_volatility(key, dt):
                base_score += 25.0
            if key == "forex_london_ny_overlap":
                base_score += 15.0
            score = max(score, base_score)
        return min(score, 100.0)

    def get_session_info(self, dt: Optional[datetime] = None) -> Dict:
        """Full session context for agent decision making."""
        dt = dt or self.now_utc()
        active = self.get_active_sessions(dt)
        peaks = {k: self.is_peak_volatility(k, dt) for k in active}
        is_weekend = dt.weekday() >= 5
        return {
            "active_sessions": active,
            "peak_sessions": [k for k, v in peaks.items() if v],
            "is_weekend": is_weekend,
            "utc_time": dt.strftime("%H:%M:%S"),
            "day_of_week": dt.strftime("%A"),
            "recommended_trading": not is_weekend and bool(active),
            "overlap_active": "forex_london_ny_overlap" in active,
        }

    def hours_until_next_session(self, session_key: str,
                                  dt: Optional[datetime] = None) -> float:
        """Hours until next opening of a session."""
        import math
        dt = dt or self.now_utc()
        if session_key not in SESSIONS:
            return math.inf
        session = SESSIONS[session_key]
        tz = pytz.timezone(session.timezone)
        local_dt = dt.astimezone(tz)
        open_dt = local_dt.replace(
            hour=session.open_time.hour,
            minute=session.open_time.minute,
            second=0, microsecond=0,
        )
        if local_dt >= open_dt:
            from datetime import timedelta
            open_dt += timedelta(days=1)
        delta = (open_dt - local_dt).total_seconds() / 3600
        return round(delta, 2)
