export type AgentStatus =
  | "idle"
  | "running"
  | "investigating"
  | "suggestion_ready"
  | "error";

export type AgentCategory =
  | "orchestrator"
  | "politics"
  | "crypto"
  | "sports"
  | "science"
  | "strategy_scout"
  | "whale_watcher"
  | "event_evaluator"
  | "strategy_evaluator"
  | "position_advisor"
  | "entry_analyst"
  | "opportunity_optimizer";

export type TradeDirection = "BUY" | "SELL";

export type SuggestionStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "executed"
  | "failed";

export type InvestigationStatus = "analyzing" | "complete" | "skipped" | "error";

export type WsEventType =
  | "agent_log"
  | "agent_status"
  | "new_suggestion"
  | "suggestion_update"
  | "portfolio_update"
  | "investigation_update"
  | "strategy_report"
  | "event_evaluation"
  | "position_advice"
  | "opportunity_rank"
  | "system"
  | "bitcoin_signal";

// ─── Agent ──────────────────────────────────────────────────────────

export interface AgentInfo {
  id: string;
  name: string;
  category: AgentCategory;
  status: AgentStatus;
  current_task: string | null;
  last_active: string | null;
  suggestions_generated: number;
  error_message: string | null;
}

export interface AgentLog {
  agent_id: string;
  agent_name: string;
  message: string;
  level: "info" | "warning" | "error";
  timestamp: string;
}

// ─── Suggestion ──────────────────────────────────────────────────────

export interface Suggestion {
  id: string;
  market_id: string;
  market_question: string;
  outcome: string;
  direction: TradeDirection;
  price_at_discovery: number;
  confidence_score: number;
  reasoning: string;
  agent_id: string;
  agent_name: string;
  category: AgentCategory;
  status: SuggestionStatus;
  created_at: string;
  updated_at: string;
  execution_tx: string | null;
  tags: string[];
  end_date: string | null;
  market_url: string | null;
}

// ─── Investigation ───────────────────────────────────────────────────

export interface Investigation {
  id: string;
  agent_id: string;
  agent_name: string;
  category: AgentCategory;
  market_id: string;
  market_question: string;
  price_at_analysis: number;
  status: InvestigationStatus;
  news_summary: string | null;
  sentiment: {
    sentiment: string;
    confidence: number;
    reasoning: string;
    key_factors: string[];
  } | null;
  conclusion: string | null;
  direction_found: string | null;
  started_at: string;
  finished_at: string | null;
}

// ─── Strategy ────────────────────────────────────────────────────────

export interface StrategyReport {
  id: string;
  title: string;
  source: string;
  summary: string;
  actionable_insights: string[];
  difficulty: string;
  agent_id: string;
  created_at: string;
}

// ─── Portfolio ───────────────────────────────────────────────────────

export interface Position {
  market_id: string;
  market_question: string;
  outcome: string;
  size: number;
  avg_price: number;
  current_price: number;
  pnl: number;
  pnl_pct: number;
  opened_at: string | null;
  category?: string;
  market_url?: string;
}

export interface OpenOrder {
  id: string;
  side: string;
  price: number | string | null;
  size_remaining?: number | string | null;
  token_id?: string;
}

export interface Portfolio {
  balance_usdc: number;
  total_positions_value: number;
  total_pnl: number;
  total_pnl_pct: number;
  positions: Position[];
  open_orders?: OpenOrder[];
  last_updated: string;
  source?: "live" | "demo";
  positions_note?: string | null;
}

// ─── Events ─────────────────────────────────────────────────────────

export interface MarketEvent {
  id: string;
  question: string;
  outcomes: string[];
  yes_price: number;
  volume: number;
  liquidity: number;
  end_date: string | null;
  days_left: number | null;
  category: string;
  market_url: string | null;
}

// ─── Event Evaluation ────────────────────────────────────────────────

export interface EventScenario {
  name: string;
  probability: number;
  description: string;
  impact: string;
}

export interface EventEvaluation {
  id: string;
  market_id: string;
  market_question: string;
  current_price: number;
  end_date: string | null;
  category: string;
  scenarios: EventScenario[];
  most_likely_outcome: string;
  confidence: number;
  news_context: string;
  agent_id: string;
  created_at: string;
  market_url: string | null;
}

// ─── Position Advice ─────────────────────────────────────────────────

export interface PositionAdvice {
  id: string;
  market_id: string;
  market_question: string;
  outcome: string;
  current_size: number;
  avg_price: number;
  current_price: number;
  current_pnl: number;
  recommended_action: string;
  urgency: string;
  hold_duration: string;
  scenarios: EventScenario[];
  reasoning: string;
  risk_level: string;
  agent_id: string;
  created_at: string;
  market_url: string | null;
}

// ─── Opportunity Ranking ─────────────────────────────────────────────

export interface OpportunityEntry {
  id: string;
  market_id: string;
  market_question: string;
  current_price: number;
  end_date: string | null;
  expected_return_pct: number;
  risk_score: number;
  opportunity_cost_note: string;
  recommended_size_usdc: number;
  priority_rank: number;
  reasoning: string;
  direction: TradeDirection;
  confidence: number;
  agent_id: string;
  created_at: string;
  market_url: string | null;
}

// ─── Bitcoin Live ─────────────────────────────────────────────────────

export interface BitcoinMarket {
  id: string;
  question: string;
  yes_price: number;
  volume: number;
  liquidity: number;
  end_date: string | null;
  days_left: number;
  hours_left: number;
  market_url: string | null;
  token_id: string;
}

export interface AgentsConsensus {
  price_agent_dir: string;
  sentiment_dir: string;
  btc_sentiment: string;
  momentum_score: number;
  volume_tier: string;
}

export interface BitcoinSignal {
  market_id: string;
  gamma_id: string;
  market_question: string;
  direction: TradeDirection;
  yes_price: number;
  confidence: number;
  win_probability: number;
  expected_return_pct: number;
  suggested_amount_pct: number;
  reasoning: string;
  key_signal: string;
  urgency: "high" | "medium" | "low";
  signal_quality: "strong" | "moderate" | "weak";
  hours_left: number;
  days_left: number;
  volume: number;
  liquidity: number;
  agents_consensus: AgentsConsensus;
  market_url: string | null;
  end_date: string | null;
  analyzed_at: string;
}

// ─── Config ──────────────────────────────────────────────────────────

export interface AppConfig {
  polymarket_api_key: string;
  polymarket_api_secret: string;
  polymarket_api_passphrase: string;
  polymarket_private_key: string;
  polymarket_proxy_wallet: string;
  fuelxi_api_url: string;
  fuelxi_api_key: string;
  fuelxi_model: string;
  llm_provider: string;
  openai_api_key: string;
  openai_model: string;
  tavily_api_key: string;
  update_interval: number;
  min_confidence: number;
  max_parallel_agents: number;
}

// ─── WebSocket ───────────────────────────────────────────────────────

export interface WsMessage {
  event: WsEventType;
  data: unknown;
  timestamp: string;
}

export interface ApiResponse<T = unknown> {
  success: boolean;
  data: T;
  message: string;
}
