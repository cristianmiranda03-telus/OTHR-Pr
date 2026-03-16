"""Trading sessions API."""
from fastapi import APIRouter
from core.sessions import get_sessions

router = APIRouter(prefix="/api/sessions", tags=["Sessions"])


@router.get("")
def list_sessions():
    return get_sessions()
