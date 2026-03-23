"""
FastAPI Backend - Trading Terminal API
WebSocket + REST for real-time trading data.
"""
import asyncio
import json
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Dict, List, Optional, Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import yaml
from loguru import logger

from ..core.mt5_connection import MT5Connection
from ..core.metaapi_bridge import create_connection as create_mt5_connection
from ..core.indicators import Indicators
from ..core.sessions import SessionManager
from ..core.risk import RiskCalculator
from ..core.backtesting import Backtester
from ..agents.orchestrator import OrchestratorAgent
from ..agents.technical_analyst import TechnicalAnalystAgent
from ..agents.news_sentinel import NewsSentinelAgent
from ..agents.risk_manager import RiskManagerAgent
from ..agents.mt5_executor import MT5ExecutorAgent
from ..agents.memory_agent import MemoryAgent
from ..agents.explorer_agent import ExplorerAgent
from ..agents.data_cleaner import DataCleanerAgent
from ..ai.llm_client import LLMClient
from ..data.chromadb_manager import ChromaMemoryManager
from ..utils.logger import setup_logging
from ..utils.event_bus import EventBus
from ..utils.config import load_config as _load_config_util


# ─── Global State ──────────────────────────────────────────────────────────────

class AppState:
    def __init__(self):
        self.config: Dict = {}
        self.mt5: Optional[MT5Connection] = None
        self.orchestrator: Optional[OrchestratorAgent] = None
        self.llm: Optional[LLMClient] = None
        self.memory_db: Optional[ChromaMemoryManager] = None
        self.event_bus: Optional[EventBus] = None
        self.session_mgr: Optional[SessionManager] = None
        self.trading_task: Optional[asyncio.Task] = None
        self.ws_manager: Optional["WebSocketManager"] = None
        self.initialized = False


state = AppState()


class WebSocketManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active_connections.append(ws)
        logger.info(f"WS connected. Total: {len(self.active_connections)}")

    def disconnect(self, ws: WebSocket):
        if ws in self.active_connections:
            self.active_connections.remove(ws)

    async def broadcast(self, data: dict):
        dead = []
        msg = json.dumps(data, default=str)
        for ws in self.active_connections:
            try:
                await ws.send_text(msg)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)

    async def send_to(self, ws: WebSocket, data: dict):
        try:
            await ws.send_text(json.dumps(data, default=str))
        except Exception:
            self.disconnect(ws)


# ─── App Lifecycle ──────────────────────────────────────────────────────────────

def load_config(config_path: str = "backend/config/settings.yaml") -> Dict:
    return _load_config_util(config_path)


async def initialize_system(config: Dict):
    """Bootstrap all agents and connections."""
    setup_logging(config.get("logging", {}))
    state.config = config
    state.event_bus = EventBus()
    state.ws_manager = WebSocketManager()

    # Subscribe event bus to WebSocket broadcast
    async def ws_broadcast(event: dict):
        if state.ws_manager:
            await state.ws_manager.broadcast(event)

    state.event_bus.subscribe_all(ws_broadcast)

    # MT5 Connection (local, metaapi-remote, or demo)
    mt5_mode = config.get("mt5", {}).get("mode", "local")
    logger.info(f"MT5 mode: {mt5_mode}")
    state.mt5 = create_mt5_connection(config)
    connected = await state.mt5.connect()
    logger.info(f"MT5 connected: {connected} (mode={mt5_mode})")

    # LLM Client
    state.llm = LLMClient(config.get("ai", {}))

    # ChromaDB
    state.memory_db = ChromaMemoryManager(config.get("chromadb", {}))
    await state.memory_db.initialize()

    # Session Manager
    state.session_mgr = SessionManager(config.get("sessions", {}))

    # Risk Calculator
    risk_calc = RiskCalculator(config.get("risk", {}))

    # Backtester
    backtester = Backtester(config.get("backtest", {}))

    # Build agents
    technical = TechnicalAnalystAgent(config, state.llm)
    news = NewsSentinelAgent(config, state.llm)
    risk = RiskManagerAgent(config, state.llm, risk_calc)
    executor = MT5ExecutorAgent(config, state.mt5)
    memory = MemoryAgent(config, state.memory_db, state.llm)
    explorer = ExplorerAgent(config, backtester, state.llm)
    data_cleaner = DataCleanerAgent(config)

    # Orchestrator
    state.orchestrator = OrchestratorAgent(
        config=config, mt5=state.mt5,
        technical=technical, news=news, risk=risk,
        executor=executor, memory=memory, explorer=explorer,
        data_cleaner=data_cleaner, session_mgr=state.session_mgr,
        event_bus=state.event_bus,
    )
    state.initialized = True
    logger.info("✅ Trading Terminal initialized - all agents ready")
    await state.event_bus.publish("system_ready", {
        "message": "All agents initialized", "mode": config.get("trading", {}).get("mode", "paper"),
        "symbols": config.get("trading", {}).get("symbols", []),
    })


@asynccontextmanager
async def lifespan(app: FastAPI):
    config = load_config()
    await initialize_system(config)
    yield
    if state.trading_task:
        state.trading_task.cancel()
    if state.mt5:
        await state.mt5.disconnect()
    logger.info("Trading Terminal shutdown complete")


# ─── FastAPI App ────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Trading Terminal API",
    description="AI-powered multi-agent trading system",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── WebSocket ──────────────────────────────────────────────────────────────────

async def _handle_ws(websocket: WebSocket):
    """Shared WebSocket handler for all WS paths."""
    ws_mgr = state.ws_manager
    if not ws_mgr:
        await websocket.close(code=1011)
        return
    await ws_mgr.connect(websocket)
    # Send initial state
    await ws_mgr.send_to(websocket, {
        "type": "init",
        "data": await _get_full_state(),
        "timestamp": datetime.now().isoformat(),
    })
    try:
        while True:
            text = await websocket.receive_text()
            try:
                msg = json.loads(text)
                await handle_ws_message(websocket, msg)
            except Exception as e:
                await ws_mgr.send_to(websocket, {
                    "type": "error", "data": str(e)})
    except WebSocketDisconnect:
        ws_mgr.disconnect(websocket)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await _handle_ws(websocket)


@app.websocket("/ws/updates")
async def websocket_updates_endpoint(websocket: WebSocket):
    """Alias path for /ws/updates compatibility."""
    await _handle_ws(websocket)


async def handle_ws_message(ws: WebSocket, msg: dict):
    action = msg.get("action")
    ws_mgr = state.ws_manager

    if action == "ping":
        await ws_mgr.send_to(ws, {"type": "pong", "timestamp": datetime.now().isoformat()})
    elif action == "get_state":
        await ws_mgr.send_to(ws, {"type": "state", "data": await _get_full_state()})
    elif action == "subscribe_symbol":
        pass  # Symbol subscriptions handled via broadcast
    elif action == "close_position":
        ticket = msg.get("ticket")
        if ticket and state.orchestrator:
            result = await state.orchestrator.executor.run(
                {"action": "close", "ticket": ticket})
            await ws_mgr.send_to(ws, {"type": "close_result", "data": result})


# ─── REST Endpoints ─────────────────────────────────────────────────────────────

@app.get("/api/health")
async def health():
    mt5_mode = state.config.get("mt5", {}).get("mode", "local")
    mt5_info = None
    if state.mt5 and state.mt5.account_info:
        ai = state.mt5.account_info
        mt5_info = {
            "login":  ai.get("login"),
            "server": ai.get("server"),
            "balance": ai.get("balance"),
        }
    return {
        "status":        "ok",
        "initialized":   state.initialized,
        "mt5_connected": state.mt5.connected if state.mt5 else False,
        "mt5_mode":      mt5_mode,
        "mt5_info":      mt5_info,
        "mode":          state.config.get("trading", {}).get("mode", "paper"),
        "symbols":       state.config.get("trading", {}).get("symbols", []),
        "timestamp":     datetime.now().isoformat(),
    }


@app.get("/api/account")
async def get_account():
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    account = await state.mt5.get_account_info()
    return account


@app.get("/api/positions")
async def get_positions(symbol: Optional[str] = None):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    return await state.mt5.get_positions(symbol)


@app.get("/api/orders")
async def get_orders():
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    return await state.mt5.get_pending_orders()


@app.get("/api/history")
async def get_history(days: int = 7):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    return await state.mt5.get_history(days)


@app.get("/api/ohlcv/{symbol}")
async def get_ohlcv(symbol: str, timeframe: str = "M1", bars: int = 200):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    df = await state.mt5.get_ohlcv(symbol, timeframe, bars)
    if df.empty:
        return []
    df = df.reset_index()
    df["time"] = df["time"].astype(str)
    return df.to_dict("records")


@app.get("/api/indicators/{symbol}")
async def get_indicators(symbol: str, timeframe: str = "M1", bars: int = 200):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    df = await state.mt5.get_ohlcv(symbol, timeframe, bars)
    if df.empty:
        return {}
    df = Indicators.compute_all(df)
    last = df.iloc[-1]
    return {
        "rsi": round(float(last.get("rsi", 50)), 2),
        "macd": round(float(last.get("macd", 0)), 6),
        "macd_signal": round(float(last.get("macd_signal", 0)), 6),
        "macd_hist": round(float(last.get("macd_hist", 0)), 6),
        "atr": round(float(last.get("atr", 0)), 5),
        "atr_pct": round(float(last.get("atr_pct", 0)), 3),
        "bb_upper": round(float(last.get("bb_upper", 0)), 5),
        "bb_lower": round(float(last.get("bb_lower", 0)), 5),
        "stoch_k": round(float(last.get("stoch_k", 50)), 2),
        "obv": round(float(last.get("obv", 0)), 0),
        "regime": Indicators.market_regime(df),
        "pivot_points": Indicators.pivot_points(df),
        "support_resistance": Indicators.support_resistance(df),
    }


@app.get("/api/session")
async def get_session():
    if not state.session_mgr:
        raise HTTPException(503, "Session manager not initialized")
    info = state.session_mgr.get_session_info()
    for symbol in state.config.get("trading", {}).get("symbols", []):
        info[f"score_{symbol}"] = state.session_mgr.scalping_score(symbol)
    return info


@app.get("/api/agents/status")
async def get_agents_status():
    if not state.orchestrator:
        return {}
    o = state.orchestrator
    return {
        "orchestrator": o.get_status_dict(),
        "technical": o.technical.get_status_dict(),
        "news": o.news.get_status_dict(),
        "risk": o.risk.get_status_dict(),
        "executor": o.executor.get_status_dict(),
        "memory": o.memory.get_status_dict(),
        "explorer": o.explorer.get_status_dict(),
        "data_cleaner": o.data_cleaner.get_status_dict(),
    }


@app.get("/api/agents/logs")
async def get_agent_logs(agent: str = "orchestrator", last_n: int = 100):
    if not state.orchestrator:
        return []
    agents_map = {
        "orchestrator": state.orchestrator,
        "technical": state.orchestrator.technical,
        "news": state.orchestrator.news,
        "risk": state.orchestrator.risk,
        "executor": state.orchestrator.executor,
        "memory": state.orchestrator.memory,
        "explorer": state.orchestrator.explorer,
        "data_cleaner": state.orchestrator.data_cleaner,
    }
    agent_obj = agents_map.get(agent, state.orchestrator)
    return agent_obj.get_logs(last_n)


@app.get("/api/stats")
async def get_stats():
    if not state.orchestrator:
        return {}
    return state.orchestrator.get_full_stats()


@app.get("/api/memory/stats")
async def get_memory_stats():
    if not state.memory_db:
        return {}
    return await state.memory_db.get_stats()


@app.get("/api/strategies/leaderboard")
async def get_strategy_leaderboard():
    if not state.orchestrator:
        return []
    return state.orchestrator.explorer.get_strategy_leaderboard()


# ─── Trading Control ────────────────────────────────────────────────────────────

class TradingStartRequest(BaseModel):
    symbols: Optional[List[str]] = None
    interval: int = 30
    mode: str = "paper"


@app.post("/api/trading/start")
async def start_trading(req: TradingStartRequest):
    if not state.orchestrator:
        raise HTTPException(503, "System not initialized")
    if state.trading_task and not state.trading_task.done():
        return {"status": "already_running"}

    # Update mode
    state.config["trading"]["mode"] = req.mode
    symbols = req.symbols or state.config.get("trading", {}).get("symbols", ["EURUSD"])

    state.trading_task = asyncio.create_task(
        state.orchestrator.run_main_loop(symbols=symbols, interval_seconds=req.interval)
    )
    logger.info(f"Trading started | symbols={symbols} | mode={req.mode}")
    return {"status": "started", "symbols": symbols, "mode": req.mode}


@app.post("/api/trading/stop")
async def stop_trading():
    if not state.orchestrator:
        raise HTTPException(503, "System not initialized")
    if state.trading_task:
        state.trading_task.cancel()
    await state.orchestrator.stop()
    return {"status": "stopped"}


class OrderRequest(BaseModel):
    symbol: str
    order_type: str
    volume: float
    sl: float = 0.0
    tp: float = 0.0
    comment: str = "Manual"


@app.post("/api/orders/market")
async def place_market_order(req: OrderRequest):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    result = await state.mt5.send_order(
        symbol=req.symbol, order_type=req.order_type,
        volume=req.volume, sl=req.sl, tp=req.tp, comment=req.comment
    )
    if state.event_bus:
        await state.event_bus.publish("manual_order", result)
    return result


@app.delete("/api/positions/{ticket}")
async def close_position(ticket: int, volume: Optional[float] = None):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    result = await state.mt5.close_position(ticket, volume)
    return result


@app.delete("/api/positions")
async def close_all_positions():
    if not state.orchestrator:
        raise HTTPException(503, "System not initialized")
    return await state.orchestrator.executor.run({"action": "close_all"})


# ─── Backtesting ────────────────────────────────────────────────────────────────

class BacktestRequest(BaseModel):
    symbol: str
    strategy: str = "OrderFlowScalping"
    timeframe: str = "M1"
    bars: int = 1000
    parameters: Optional[Dict] = None


@app.post("/api/backtest/run")
async def run_backtest(req: BacktestRequest):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    from ..strategies import STRATEGY_REGISTRY
    from ..core.backtesting import Backtester

    strat_cls = STRATEGY_REGISTRY.get(req.strategy)
    if not strat_cls:
        raise HTTPException(400, f"Unknown strategy: {req.strategy}")

    df = await state.mt5.get_ohlcv(req.symbol, req.timeframe, req.bars)
    if df.empty:
        raise HTTPException(400, "No data available")

    backtester = Backtester(state.config.get("backtest", {}))
    params = req.parameters or {}
    strat = strat_cls(config=params)

    result = backtester.run(
        df=df, strategy_fn=strat.signal,
        strategy_name=req.strategy, symbol=req.symbol,
        timeframe=req.timeframe, parameters=params,
    )
    return result.to_dict()


# ─── Config ─────────────────────────────────────────────────────────────────────

@app.get("/api/config")
async def get_config():
    safe = {k: v for k, v in state.config.items()
            if k not in ("ai",)}
    return safe


class MT5ConfigRequest(BaseModel):
    # Local MT5
    login:      Optional[int]  = None
    password:   Optional[str]  = None
    server:     Optional[str]  = None
    path:       Optional[str]  = None
    # Connection mode: local | metaapi | demo
    mt5_mode:   Optional[str]  = "local"
    # MetaAPI remote
    metaapi:    Optional[Dict] = None
    # Symbols override
    symbols:    Optional[List[str]] = None
    # Risk
    trading:    Optional[Dict] = None


@app.post("/api/config/mt5")
async def update_mt5_config(req: MT5ConfigRequest):
    mode = (req.mt5_mode or "local").lower()

    # Patch config
    state.config.setdefault("mt5", {})
    state.config["mt5"]["mode"] = mode

    if mode == "local":
        if req.login:    state.config["mt5"]["login"]    = req.login
        if req.password: state.config["mt5"]["password"] = req.password
        if req.server:   state.config["mt5"]["server"]   = req.server
        if req.path:     state.config["mt5"]["path"]     = req.path

    elif mode == "metaapi" and req.metaapi:
        state.config["metaapi"] = req.metaapi

    if req.symbols:
        state.config.setdefault("trading", {})["symbols"] = req.symbols

    if req.trading:
        state.config.setdefault("trading", {}).update(req.trading)

    # Reconnect with new settings
    if state.mt5:
        await state.mt5.disconnect()

    state.mt5 = create_mt5_connection(state.config)
    connected = await state.mt5.connect()

    # Update executor with new connection
    if state.orchestrator and hasattr(state.orchestrator, "executor"):
        state.orchestrator.executor.mt5 = state.mt5

    return {
        "connected": connected,
        "mt5_mode":  mode,
        "login":     req.login,
        "symbols":   state.config.get("trading", {}).get("symbols", []),
    }


# ─── Helpers ────────────────────────────────────────────────────────────────────

async def _get_full_state() -> Dict:
    account = {}
    positions = []
    if state.mt5:
        account = await state.mt5.get_account_info()
        positions = await state.mt5.get_positions()

    stats = {}
    if state.orchestrator:
        stats = state.orchestrator.get_full_stats()

    session_info = {}
    if state.session_mgr:
        session_info = state.session_mgr.get_session_info()

    return {
        "account": account,
        "positions": positions,
        "stats": stats,
        "session": session_info,
        "mode": state.config.get("trading", {}).get("mode", "paper"),
        "symbols": state.config.get("trading", {}).get("symbols", []),
        "running": state.trading_task is not None and not (
            state.trading_task.done() if state.trading_task else True),
    }


@app.get("/api/export/trades")
async def export_trades(format: str = "json", days: int = 30):
    if not state.mt5:
        raise HTTPException(503, "MT5 not initialized")
    history = await state.mt5.get_history(days)
    if format == "csv":
        import io
        import pandas as pd
        df = pd.DataFrame(history)
        stream = io.StringIO()
        df.to_csv(stream, index=False)
        from fastapi.responses import Response
        return Response(content=stream.getvalue(), media_type="text/csv",
                        headers={"Content-Disposition": "attachment; filename=trades.csv"})
    return history
