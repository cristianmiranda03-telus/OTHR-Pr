"""News / sentiment stub and calendar."""
from fastapi import APIRouter
from datetime import datetime

router = APIRouter(prefix="/api/news", tags=["News"])


@router.get("/feed")
def get_feed(limit: int = 20):
    """Placeholder feed. Integrate Finviz, Reuters, etc. here."""
    return {
        "items": [
            {"id": "1", "title": "FOMC decision day", "source": "Reuters", "sentiment": "neutral", "time": datetime.utcnow().isoformat(), "symbols": ["USD"]},
            {"id": "2", "title": "ECB signals on rates", "source": "Bloomberg", "sentiment": "positive", "time": datetime.utcnow().isoformat(), "symbols": ["EUR"]},
        ][:limit],
    }


@router.get("/calendar")
def get_calendar():
    """Economic calendar placeholder."""
    return {"events": []}
