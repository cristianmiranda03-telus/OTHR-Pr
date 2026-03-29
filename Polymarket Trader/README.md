# ♠ Polymarket Trader — Multi-Agent Terminal

An AI-powered, multi-agent prediction market trading terminal for Polymarket.
Dark neon "Joker" UI. FastAPI backend. Next.js frontend. One command to run.

---

## Architecture (AI Agents & Orchestrator)

For a full description of how the **Orchestrator Agent** and all sub-agents work, data flow, and Mermaid diagrams, see:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — Agent lifecycle, market/strategy flows, and file map.

Quick overview: one **Orchestrator** ("El Joker") spawns 6 agents in parallel (Politics, Crypto, Sports, Science, StrategyScout, WhaleWatcher). Market agents fetch Polymarket data → LLM sentiment/reasoning → Suggestions; StrategyScout writes strategy reports; WhaleWatcher produces copy-trade suggestions. All share in-memory stores and broadcast live updates via WebSocket.

---

## Quick Start

### 1. Prerequisites

| Tool       | Version      |
|------------|-------------|
| Python     | 3.11+        |
| Node.js    | 18+          |
| npm        | 9+           |
| Ollama     | latest       |

### 2. Install Python dependencies

```bash
cd "Polymarket Trader"
pip install -r requirements.txt
```

### 3. Configure

Copy `config.ini` and fill in your keys:

```ini
[polymarket_api]
api_key     = your_polymarket_api_key
api_secret  = your_polymarket_api_secret
api_passphrase = your_passphrase

[fuelxi]
api_url = http://localhost:11434   # Ollama endpoint
model   = llama3.1

[search]
tavily_api_key = your_tavily_key   # Optional but recommended
```

### 4. Start Ollama (FuelXI)

```bash
ollama pull llama3.1
ollama serve
```

### 5. Run everything

```bash
python run.py
```

- **Frontend UI:**   http://localhost:3000
- **Backend API:**   http://localhost:8000
- **API Docs:**      http://localhost:8000/docs
- **WebSocket:**     ws://localhost:8000/ws/updates

---

## Architecture

```
Polymarket Trader/
├── run.py                          # Single launcher
├── config.ini                      # All configuration
├── requirements.txt
├── backend/
│   ├── main.py                     # FastAPI app + endpoints
│   ├── models.py                   # Pydantic models
│   ├── config.py                   # Settings (env-based)
│   ├── websocket_manager.py        # Real-time broadcast hub
│   ├── polymarket_client.py        # Polymarket API wrapper
│   ├── llm_client.py               # FuelXI / OpenAI abstraction
│   └── agents/
│       ├── base_agent.py           # Abstract base class
│       ├── orchestrator_agent.py   # El Joker — master coordinator
│       ├── market_agents/
│       │   ├── politics_agent.py
│       │   ├── crypto_agent.py
│       │   ├── sports_agent.py
│       │   └── science_agent.py
│       └── strategy_agents/
│           ├── strategy_scout_agent.py
│           └── whale_watcher_agent.py
└── frontend/
    └── src/
        ├── app/                    # Next.js App Router
        ├── components/             # React components
        │   ├── Dashboard.tsx
        │   ├── AgentStatusPanel.tsx
        │   ├── SuggestionQueue.tsx
        │   ├── SuggestionCard.tsx
        │   └── PortfolioView.tsx
        ├── hooks/
        │   ├── useWebSocket.ts
        │   └── useApi.ts
        └── types/index.ts
```

## Switching LLM Provider

To use OpenAI GPT instead of FuelXI, change `config.ini`:

```ini
[llm]
provider = openai

[openai]
api_key = sk-...
model   = gpt-4o
```

## API Reference

| Method | Endpoint                                | Description                       |
|--------|-----------------------------------------|-----------------------------------|
| GET    | `/api/agents`                           | All agent statuses                |
| GET    | `/api/suggestions`                      | All suggestions (filterable)      |
| POST   | `/api/suggestions/approve/{id}`         | Execute a suggestion              |
| POST   | `/api/suggestions/reject/{id}`          | Reject a suggestion               |
| GET    | `/api/portfolio`                        | Current portfolio                 |
| WS     | `/ws/updates`                           | Real-time event stream            |

---

> **Disclaimer:** This is an experimental tool. Never risk money you cannot afford to lose.
