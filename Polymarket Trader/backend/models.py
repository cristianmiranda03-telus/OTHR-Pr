"""
Pydantic models used across the backend API.
"""
from __future__ import annotations
from datetime import datetime
from enum import Enum
from typing import Any, Optional
from pydantic import BaseModel, Field
import uuid


# ─────────────────────────── Enumerations ────────────────────────────

class AgentStatus(str, Enum):
    IDLE = "idle"
    RUNNING = "running"
    INVESTIGATING = "investigating"
    SUGGESTION_READY = "suggestion_ready"
    ERROR = "error"


class AgentCategory(str, Enum):
    ORCHESTRATOR = "orchestrator"
    POLITICS = "politics"
    CRYPTO = "crypto"
    SPORTS = "sports"
    SCIENCE = "science"
    STRATEGY_SCOUT = "strategy_scout"
    WHALE_WATCHER = "whale_watcher"
    EVENT_EVALUATOR = "event_evaluator"
    STRATEGY_EVALUATOR = "strategy_evaluator"
    POSITION_ADVISOR = "position_advisor"
    ENTRY_ANALYST = "entry_analyst"
    OPPORTUNITY_OPTIMIZER = "opportunity_optimizer"


class TradeDirection(str, Enum):
    BUY = "BUY"
    SELL = "SELL"


class SuggestionStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXECUTED = "executed"
    FAILED = "failed"


class WsEventType(str, Enum):
    AGENT_LOG = "agent_log"
    AGENT_STATUS = "agent_status"
    NEW_SUGGESTION = "new_suggestion"
    SUGGESTION_UPDATE = "suggestion_update"
    PORTFOLIO_UPDATE = "portfolio_update"
    INVESTIGATION_UPDATE = "investigation_update"
    STRATEGY_REPORT = "strategy_report"
    EVENT_EVALUATION = "event_evaluation"
    POSITION_ADVICE = "position_advice"
    OPPORTUNITY_RANK = "opportunity_rank"
    SYSTEM = "system"
    BITCOIN_SIGNAL = "bitcoin_signal"


# ─────────────────────────── Agent Models ────────────────────────────

class AgentInfo(BaseModel):
    id: str
    name: str
    category: AgentCategory
    status: AgentStatus = AgentStatus.IDLE
    current_task: Optional[str] = None
    last_active: Optional[datetime] = None
    suggestions_generated: int = 0
    error_message: Optional[str] = None


class AgentLog(BaseModel):
    agent_id: str
    agent_name: str
    message: str
    level: str = "info"
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ─────────────────────────── Suggestion Models ───────────────────────

class Suggestion(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    market_id: str
    market_question: str
    outcome: str
    direction: TradeDirection
    price_at_discovery: float
    confidence_score: float = Field(ge=0.0, le=1.0)
    reasoning: str
    agent_id: str
    agent_name: str
    category: AgentCategory
    status: SuggestionStatus = SuggestionStatus.PENDING
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    execution_tx: Optional[str] = None
    tags: list[str] = Field(default_factory=list)
    # Market expiry — used to prioritise and discard expired signals
    end_date: Optional[datetime] = None
    # Direct link to the market on Polymarket
    market_url: Optional[str] = None


class SuggestionAction(BaseModel):
    suggestion_id: str
    amount_usdc: Optional[float] = 10.0


# ─────────────────────────── Portfolio Models ────────────────────────

class Position(BaseModel):
    market_id: str
    market_question: str
    outcome: str
    size: float
    avg_price: float
    current_price: float
    pnl: float
    pnl_pct: float
    opened_at: Optional[datetime] = None
    category: Optional[str] = "Other"
    market_url: Optional[str] = None


class Portfolio(BaseModel):
    balance_usdc: float = 0.0
    total_positions_value: float = 0.0
    total_pnl: float = 0.0
    total_pnl_pct: float = 0.0
    positions: list[Position] = Field(default_factory=list)
    # CLOB open orders (limit orders on the book) — same flow as test.ipynb get_orders
    open_orders: list[dict[str, Any]] = Field(default_factory=list)
    last_updated: datetime = Field(default_factory=datetime.utcnow)
    source: str = "live"  # "live" | "demo" — so frontend can show real vs demo
    # When positions are empty: explains why (e.g. set proxy_wallet)
    positions_note: Optional[str] = None


# ─────────────────────────── WebSocket Models ────────────────────────

class WsMessage(BaseModel):
    event: WsEventType
    data: Any
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ─────────────────────────── Investigation Models ────────────────────

class InvestigationStatus(str, Enum):
    ANALYZING = "analyzing"
    COMPLETE = "complete"
    SKIPPED = "skipped"
    ERROR = "error"


class Investigation(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    agent_id: str
    agent_name: str
    category: AgentCategory
    market_id: str
    market_question: str
    price_at_analysis: float
    status: InvestigationStatus = InvestigationStatus.ANALYZING
    news_summary: Optional[str] = None
    sentiment: Optional[dict] = None
    conclusion: Optional[str] = None
    direction_found: Optional[str] = None
    started_at: datetime = Field(default_factory=datetime.utcnow)
    finished_at: Optional[datetime] = None


# ─────────────────────────── Strategy Models ─────────────────────────

class StrategyReport(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    source: str
    summary: str
    actionable_insights: list[str]
    difficulty: str = "medium"
    agent_id: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)


class WhaleActivity(BaseModel):
    trader_address: str
    rank: int
    win_rate: float
    total_profit: float
    recent_markets: list[str]
    recent_direction: Optional[TradeDirection] = None


# ─────────────────────────── Event Evaluation Models ─────────────────

class EventScenario(BaseModel):
    name: str
    probability: float = Field(ge=0.0, le=1.0)
    description: str
    impact: str = "neutral"  # positive / negative / neutral

class EventEvaluation(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    market_id: str
    market_question: str
    current_price: float
    end_date: Optional[datetime] = None
    category: str = "general"
    scenarios: list[EventScenario] = Field(default_factory=list)
    most_likely_outcome: str = ""
    confidence: float = 0.0
    news_context: str = ""
    agent_id: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    market_url: Optional[str] = None


# ─────────────────────────── Position Advice Models ──────────────────

class PositionAdvice(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    market_id: str
    market_question: str
    outcome: str
    current_size: float
    avg_price: float
    current_price: float
    current_pnl: float
    recommended_action: str  # HOLD / CLOSE / ADD / PARTIAL_CLOSE
    urgency: str = "low"  # low / medium / high / critical
    hold_duration: str = ""
    scenarios: list[EventScenario] = Field(default_factory=list)
    reasoning: str = ""
    risk_level: str = "medium"
    agent_id: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    market_url: Optional[str] = None


# ─────────────────────────── Opportunity Ranking Models ──────────────

class OpportunityEntry(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    market_id: str
    market_question: str
    current_price: float
    end_date: Optional[datetime] = None
    expected_return_pct: float = 0.0
    risk_score: float = 0.5
    opportunity_cost_note: str = ""
    recommended_size_usdc: float = 0.0
    priority_rank: int = 0
    reasoning: str = ""
    direction: TradeDirection = TradeDirection.BUY
    confidence: float = 0.0
    agent_id: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    market_url: Optional[str] = None


# ─────────────────────────── Config Models ───────────────────────────

class AppConfig(BaseModel):
    """Exposed (masked) configuration for the frontend settings panel."""
    polymarket_api_key: str = ""
    polymarket_api_secret: str = ""
    polymarket_api_passphrase: str = ""
    polymarket_private_key: str = ""
    polymarket_proxy_wallet: str = ""
    fuelxi_api_url: str = "https://api.fuelix.ai/v1"
    fuelxi_api_key: str = ""
    fuelxi_model: str = "claude-sonnet-4-5"
    llm_provider: str = "fuelxi"
    openai_api_key: str = ""
    openai_model: str = "gpt-4o"
    tavily_api_key: str = ""
    update_interval: int = 300
    min_confidence: float = 0.55
    max_parallel_agents: int = 6


# ─────────────────────────── API Response Wrappers ───────────────────

class ApiResponse(BaseModel):
    success: bool = True
    data: Any = None
    message: str = ""
