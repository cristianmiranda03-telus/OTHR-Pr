# ♠ Quant-Joker Trader v2.0

**AI-Powered Agentic Trading Platform** — Dark Joker theme with neon red, green & violet.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    QUANT-JOKER TRADER                       │
│                                                             │
│  Frontend (Next.js 14 + Tailwind)   Backend (FastAPI)       │
│  ┌──────────────────────────┐       ┌──────────────────┐    │
│  │  Dashboard               │◄─────►│  REST API + WS   │    │
│  │  ├─ AgentFlowModule      │       │  ├─ /api/agents  │    │
│  │  ├─ StrategyListModule   │       │  ├─ /api/mt5     │    │
│  │  ├─ TradeManagerModule   │       │  ├─ /api/market  │    │
│  │  ├─ ChartModule          │       │  ├─ /api/news    │    │
│  │  ├─ NewsModule           │       │  └─ /api/strategies   │
│  │  ├─ RiskModule           │       └──────────────────┘    │
│  │  └─ SessionsModule       │                │              │
│  └──────────────────────────┘                │              │
│                                      ┌───────▼──────┐       │
│                                      │  AI AGENTS   │       │
│                                      │ Orchestrator │       │
│                                      │ News Agent   │       │
│                                      │ Strategy Agt │       │
│                                      │ Backtest Agt │       │
│                                      │ Perf Agent   │       │
│                                      │ Trade Mgr    │       │
│                                      └───────┬──────┘       │
│                                              │              │
│                                      ┌───────▼──────┐       │
│                                      │  MetaTrader5 │       │
│                                      │  (live data) │       │
│                                      └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## AI Agent System

| Agent | Role |
|---|---|
| **Orchestrator** | Master controller — runs full cycles, coordinates all agents, makes final trade decisions |
| **News Intelligence** | Fetches & analyzes financial news, scores market sentiment per pair |
| **Strategy Research** | Recommends optimal strategies based on current market regime |
| **Backtesting Engine** | Tests strategies on MT5 historical data, ranks by composite score |
| **Performance Optimizer** | Evaluates live P&L, adjusts strategy allocation and risk settings |
| **Trade Manager** | Monitors open positions, closes risky trades, executes multi-signal batches |

## Strategy Library (21 strategies)

| Category | Strategies |
|---|---|
| **Basic** | RSI OB/OS, SMA Cross, EMA Cross, MACD Signal, Bollinger Breakout, Stochastic Cross |
| **Advanced** | RSI+MACD Confluence, Ichimoku Cloud, Pivot Bounce, ATR Breakout, Mean Reversion, Fibonacci, VWAP |
| **Quant** | Momentum Factor, Carry Trade, Volatility Regime, Pairs Cointegration, Kalman Filter |
| **AI/ML** | Random Forest (multi-vote), Gradient Boost, LSTM Sequence, RL PPO, LLM Sentiment |

## Setup

### Prerequisites
- Python 3.11+
- Node.js 18+
- MetaTrader 5 terminal (optional — demo mode available)

### Backend
```bash
cd backend
pip install -r requirements.txt
```

### Frontend
```bash
cd frontend
npm install
```

### Run
```bash
python run_quasar.py
```

Opens http://localhost:3000 automatically.

## AI Provider

Currently uses **Fuelix** (OpenAI-compatible API):
- Base URL: `https://api.fuelix.ai/v1`
- Model: `gemini-3-pro`

To switch to GPT-4 or Gemini, set in `.env`:
```env
AI_PROVIDER=openai
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o
```

## Usage

1. **Connect MT5** — enter login/password/server, or use Demo mode
2. **Start Orchestrator** — click `[ START ]` in the header
3. **Watch Agent Flow** — real-time activity in the AI Agents panel
4. **Review Strategies** — filter/sort by category, run backtests
5. **Deploy Strategy** — after backtesting, click DEPLOY to activate on MT5
6. **Monitor Trades** — Trade Manager shows open positions with AI risk assessment
7. **Run Manual Cycle** — click `[ CYCLE ]` for a single orchestration pass

## WebSocket Feed

Real-time agent activity stream:
```
ws://localhost:8000/api/agents/stream
```

## License

Quant-Joker Trader — For educational and personal trading use only.
Trading carries risk. Past performance does not guarantee future results.
