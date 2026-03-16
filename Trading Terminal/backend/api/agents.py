"""
Agent API - REST endpoints + WebSocket for real-time agent activity streaming.
"""
import asyncio
import json
from datetime import datetime
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, BackgroundTasks
from pydantic import BaseModel

from agents.orchestrator import orchestrator
from agents.base_agent import subscribe, unsubscribe
from agents.strategy_agent import STRATEGY_CATALOG

router = APIRouter(prefix="/api/agents", tags=["agents"])


# ─── Models ───────────────────────────────────────────────────────────────── #

class BacktestRequest(BaseModel):
    strategy_id: str
    symbol: str = "EURUSD"
    timeframe: str = "H1"
    bars: int = 2000
    cash: float = 10000.0
    params: dict | None = None


class SignalRequest(BaseModel):
    symbol: str
    direction: str  # "buy" | "sell"
    confidence: float = 0.75
    sl_pips: float = 25.0
    tp_pips: float = 50.0
    volume: float = 0.01
    comment: str = "Manual"
    risk_pct: float = 1.0


class ClosePositionRequest(BaseModel):
    ticket: int
    comment: str = "Manual close"


# ─── WebSocket Manager ────────────────────────────────────────────────────── #

class ConnectionManager:
    def __init__(self):
        self.connections: list[WebSocket] = []

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.connections.append(ws)

    def disconnect(self, ws: WebSocket):
        if ws in self.connections:
            self.connections.remove(ws)

    async def broadcast(self, data: dict):
        dead = []
        for ws in list(self.connections):
            try:
                await ws.send_json(data)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)


ws_manager = ConnectionManager()


async def _ws_broadcast_callback(msg: dict):
    await ws_manager.broadcast(msg)


# ─── Endpoints ────────────────────────────────────────────────────────────── #

@router.websocket("/stream")
async def agent_stream(websocket: WebSocket):
    """WebSocket endpoint for real-time agent activity feed."""
    await ws_manager.connect(websocket)
    subscribe(_ws_broadcast_callback)

    # Send initial state
    await websocket.send_json({
        "type": "init",
        "agents": orchestrator.get_all_agents(),
        "system_state": orchestrator.get_system_state(),
        "timestamp": datetime.utcnow().isoformat(),
    })

    try:
        while True:
            # Keep alive with ping
            try:
                data = await asyncio.wait_for(websocket.receive_text(), timeout=30.0)
                if data == "ping":
                    await websocket.send_json({"type": "pong", "timestamp": datetime.utcnow().isoformat()})
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "heartbeat", "timestamp": datetime.utcnow().isoformat(), "state": orchestrator.get_system_state()})
    except WebSocketDisconnect:
        pass
    finally:
        ws_manager.disconnect(websocket)
        unsubscribe(_ws_broadcast_callback)


@router.get("/status")
def get_agents_status():
    """Get status of all agents."""
    return {
        "agents": orchestrator.get_all_agents(),
        "system_state": orchestrator.get_system_state(),
        "cycle_results": orchestrator.cycle_results[-10:],
    }


@router.post("/start")
async def start_orchestrator(background_tasks: BackgroundTasks):
    """Start the continuous orchestration loop."""
    if orchestrator._running:
        return {"message": "Orchestrator already running", "running": True}
    background_tasks.add_task(orchestrator.start_loop)
    return {"message": "Orchestrator starting...", "running": True}


@router.post("/stop")
async def stop_orchestrator():
    """Stop the orchestration loop."""
    await orchestrator.stop_loop()
    return {"message": "Orchestrator stopped", "running": False}


@router.post("/cycle")
async def run_single_cycle():
    """Trigger a single orchestration cycle manually."""
    if orchestrator._running:
        return {"message": "Loop is running automatically", "running": True}
    result = await orchestrator.run_full_cycle()
    return {"message": "Cycle complete", "result": result}


@router.post("/news/refresh")
async def refresh_news():
    """Force news agent to refresh."""
    result = await orchestrator.news_agent.safe_run()
    return {"result": result, "agent": orchestrator.news_agent.to_dict()}


@router.get("/news/latest")
def get_latest_news():
    """Get latest news analysis."""
    return {
        "headlines": orchestrator.news_agent.news_cache,
        "analysis": orchestrator.news_agent.latest_analysis,
        "agent": orchestrator.news_agent.to_dict(),
    }


@router.get("/strategies")
def get_all_strategies():
    """Get the full strategy catalog."""
    catalog = STRATEGY_CATALOG.copy()
    # Merge in backtest results
    for strategy in catalog:
        sid = strategy.get("backtest_key") or strategy.get("id")
        if sid in orchestrator.backtest_agent.results:
            bt = orchestrator.backtest_agent.results[sid]
            strategy["last_backtest"] = bt.get("stats")
            strategy["last_backtest_at"] = bt.get("tested_at")
    return {
        "strategies": catalog,
        "new_strategies": orchestrator.strategy_agent.new_strategies,
        "recommended": orchestrator.strategy_agent.recommended,
    }


@router.post("/backtest")
async def run_backtest(req: BacktestRequest):
    """Run a single strategy backtest."""
    result = await orchestrator.backtest_agent.run_strategy_backtest(
        strategy_id=req.strategy_id,
        symbol=req.symbol,
        timeframe=req.timeframe,
        bars=req.bars,
        cash=req.cash,
        params=req.params,
    )
    return result


@router.post("/backtest/batch")
async def run_batch_backtest(body: dict):
    """Run backtests on multiple strategies."""
    strategies = body.get("strategies", ["rsi", "sma_cross"])
    symbol = body.get("symbol", "EURUSD")
    timeframe = body.get("timeframe", "H1")
    result = await orchestrator.backtest_agent.safe_run({
        "strategies": strategies,
        "symbol": symbol,
        "timeframe": timeframe,
    })
    return result


@router.get("/backtest/rankings")
def get_backtest_rankings():
    """Get current strategy rankings from last backtest."""
    return {
        "rankings": orchestrator.backtest_agent.rankings,
        "results": orchestrator.backtest_agent.results,
    }


@router.get("/performance")
def get_performance():
    """Get performance metrics and recommendations."""
    return {
        "metrics": orchestrator.performance_agent.metrics,
        "equity_curve": orchestrator.performance_agent.equity_curve[-200:],
        "recommendations": orchestrator.performance_agent.system_recommendations,
        "active_strategies": orchestrator.system_state.get("active_strategies", []),
    }


@router.get("/trades/open")
def get_open_trades():
    """Get all open positions."""
    positions = orchestrator.trade_manager.get_open_positions()
    return {
        "positions": positions,
        "count": len(positions),
        "pending_signals": orchestrator.trade_manager.pending_signals,
    }


@router.post("/trades/execute")
async def execute_signal(req: SignalRequest):
    """Manually execute a trade signal."""
    signal = req.model_dump()
    results = await orchestrator.trade_manager.execute_signal_batch([signal])
    return {"results": results}


@router.post("/trades/close")
async def close_trade(req: ClosePositionRequest):
    """Manually close a position."""
    result = orchestrator.trade_manager.close_position(req.ticket, req.comment)
    return result


@router.post("/trades/signals/execute-all")
async def execute_pending_signals():
    """Execute all pending signals."""
    signals = orchestrator.trade_manager.pending_signals.copy()
    orchestrator.trade_manager.pending_signals = []
    results = await orchestrator.trade_manager.execute_signal_batch(signals)
    return {"executed": len(results), "results": results}


@router.get("/logs")
def get_agent_logs():
    """Get recent activity logs from all agents."""
    return {
        "orchestrator": orchestrator.get_log(),
        "news": orchestrator.news_agent.get_log(),
        "strategy": orchestrator.strategy_agent.get_log(),
        "backtest": orchestrator.backtest_agent.get_log(),
        "performance": orchestrator.performance_agent.get_log(),
        "trade_manager": orchestrator.trade_manager.get_log(),
    }


@router.get("/system/state")
def get_system_state():
    """Get overall system state."""
    return orchestrator.get_system_state()


@router.post("/strategy/deploy")
async def deploy_strategy_to_mt5(body: dict):
    """Deploy a tested strategy to MT5 as an Expert Advisor configuration."""
    strategy_id = body.get("strategy_id")
    symbol = body.get("symbol", "EURUSD")
    timeframe = body.get("timeframe", "H1")
    params = body.get("params", {})

    if strategy_id not in orchestrator.backtest_agent.results:
        return {"success": False, "error": "Strategy not backtested yet. Run backtest first."}

    result = orchestrator.backtest_agent.results[strategy_id]
    stats = result.get("stats", {})

    if stats.get("sharpe_ratio", 0) < 0.5 or stats.get("total_return_pct", 0) <= 0:
        return {
            "success": False,
            "error": f"Strategy {strategy_id} does not meet minimum quality thresholds (Sharpe < 0.5 or negative return).",
            "stats": stats,
        }

    await orchestrator.log("action", f"Deploying strategy '{strategy_id}' to MT5 on {symbol}/{timeframe}...")

    # Log deployment config (in production, this would set up an EA or signal listener)
    deployment_config = {
        "strategy_id": strategy_id,
        "symbol": symbol,
        "timeframe": timeframe,
        "params": params,
        "stats": stats,
        "deployed_at": datetime.utcnow().isoformat(),
        "status": "deployed",
    }

    await orchestrator.log("result", f"Strategy '{strategy_id}' deployed on {symbol}/{timeframe} | Return: {stats.get('total_return_pct', 0):.1f}% | Sharpe: {stats.get('sharpe_ratio', 0):.2f}", deployment_config)

    return {"success": True, "config": deployment_config}
