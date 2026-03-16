"""MT5 connection API."""
from fastapi import APIRouter
from pydantic import BaseModel

from core.mt5_connector import connect_mt5, disconnect_mt5, get_mt5_state, MT5Credentials

router = APIRouter(prefix="/api/mt5", tags=["MT5"])


class ConnectBody(BaseModel):
    login: int
    password: str
    server: str
    path: str | None = None


@router.post("/connect")
def connect(body: ConnectBody):
    try:
        creds = MT5Credentials(login=body.login, password=body.password, server=body.server, path=body.path)
        return connect_mt5(creds)
    except Exception as e:
        return {"success": False, "message": str(e), "account": None}


@router.post("/disconnect")
def disconnect():
    return disconnect_mt5()


@router.get("/state")
def state():
    return get_mt5_state()
