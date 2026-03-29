# Polymarket Trader — AI Agent Architecture

This document describes how the **Orchestrator Agent** and all sub-agents work together, the data flow, and where each component lives in the codebase.

---

## 1. High-Level System Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              POLYMARKET TRADER                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│   ┌─────────────┐     lifespan      ┌──────────────────────────────────────┐    │
│   │   run.py    │ ───────────────►  │  FastAPI (main.py)                    │    │
│   │  (launcher) │                   │  • REST API  • WebSocket /ws/updates  │    │
│   └─────────────┘                   └──────────────┬───────────────────────┘    │
│                                                      │                           │
│                                                      │ spawns (async task)      │
│                                                      ▼                           │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │              ORCHESTRATOR AGENT ("El Joker")                             │   │
│   │  • Registers itself in agent_registry                                    │   │
│   │  • Creates 6 sub-agents (Politics, Crypto, Sports, Science, Scout, Whale) │   │
│   │  • Runs each agent in a separate asyncio Task (semaphore-limited)        │   │
│   │  • Heartbeat every 60s → broadcast SYSTEM event                         │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                            │
│                    ┌─────────────────┼─────────────────┐                         │
│                    ▼                 ▼                 ▼                         │
│   ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐        │
│   │  MARKET AGENTS     │  │  STRATEGY AGENTS   │  │  SHARED STORES      │        │
│   │  PoliticsAgent     │  │  StrategyScout     │  │  • _suggestions    │        │
│   │  CryptoAgent       │  │  WhaleWatcher     │  │  • _investigations │        │
│   │  SportsAgent       │  │                    │  │  • _strategy_reports│        │
│   │  ScienceAgent      │  │                    │  │  • _agents (registry)│       │
│   └─────────┬──────────┘  └─────────┬──────────┘  └──────────▲─────────┘        │
│             │                       │                         │                   │
│             │    write Suggestions │  write StrategyReports  │                   │
│             │    + Investigations │                         │                   │
│             └──────────────────────┴─────────────────────────┘                   │
│                                                                                   │
│   Frontend (Next.js) ◄──── GET /api/*  +  WebSocket /ws/updates                  │
│   • Dashboard  • Signals  • Agents  • Analysis  • Strategies  • Config           │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Mermaid: Full Architecture Diagram

```mermaid
flowchart TB
    subgraph Entry["🚀 Entry Point"]
        RUN[run.py]
        CONFIG[config.ini]
    end

    subgraph Backend["Backend (FastAPI)"]
        API[main.py - REST + WebSocket]
        WS[/ws/updates]
        API --> WS
    end

    subgraph Orchestrator["♠ Orchestrator Agent (El Joker)"]
        ORCH[OrchestratorAgent.run]
        ORCH --> CREATE[Create 6 sub-agents]
        CREATE --> SPAWN[Spawn asyncio Tasks]
        SPAWN --> SEM[Semaphore: max_parallel_agents]
        SEM --> HEART[Heartbeat every 60s]
        HEART --> ORCH
    end

    subgraph MarketAgents["Market Agents (by category)"]
        POL[PoliticsAgent]
        CRY[CryptoAgent]
        SPO[SportsAgent]
        SCI[ScienceAgent]
    end

    subgraph StrategyAgents["Strategy Agents"]
        SCOUT[StrategyScoutAgent]
        WHALE[WhaleWatcherAgent]
    end

    subgraph External["External Services"]
        PM[Polymarket API]
        LLM[FuelXI / OpenAI]
        TAVILY[Tavily - optional]
    end

    subgraph Stores["In-Memory Stores (main.py)"]
        SUG[_suggestions]
        INV[_investigations]
        STRAT[_strategy_reports]
        REG[_agents registry]
    end

    RUN --> CONFIG
    RUN --> API
    API --> Orchestrator
    ORCH --> MarketAgents
    ORCH --> StrategyAgents
    MarketAgents --> PM
    MarketAgents --> LLM
    MarketAgents --> TAVILY
    StrategyAgents --> PM
    StrategyAgents --> LLM
    MarketAgents --> SUG
    MarketAgents --> INV
    StrategyAgents --> STRAT
    MarketAgents --> REG
    StrategyAgents --> REG
    Orchestrator --> REG
    Stores --> API
    API --> Frontend
    WS --> Frontend

    subgraph Frontend["Frontend (Next.js)"]
        Frontend[Dashboard · Signals · Agents · Analysis · Strategies · Config]
    end
```

---

## 3. Orchestrator Agent Lifecycle

```mermaid
sequenceDiagram
    participant FastAPI
    participant Orchestrator
    participant Registry
    participant Agent1
    participant Agent2
    participant Store

    FastAPI->>Orchestrator: lifespan start → _start_orchestrator()
    Orchestrator->>Orchestrator: Register self in _agents
    Orchestrator->>Orchestrator: _create_agents() → 6 instances
    Orchestrator->>Agent1: asyncio.create_task(agent.run())
    Orchestrator->>Agent2: asyncio.create_task(agent.run())
    Note over Orchestrator: Semaphore limits concurrent work
    loop Every 60s
        Orchestrator->>Registry: Count active agents
        Orchestrator->>Store: Count pending suggestions
        Orchestrator->>FastAPI: broadcast SYSTEM heartbeat
    end
    Note over Agent1,Agent2: Each agent runs its own infinite loop: investigate → sleep(update_interval)
```

**Orchestrator responsibilities:**

| Responsibility | Implementation |
|----------------|----------------|
| **Spawn sub-agents** | `_create_agents()` returns list of 6 agents (Politics, Crypto, Sports, Science, StrategyScout, WhaleWatcher). |
| **Parallel execution** | Each agent runs in `asyncio.create_task(guarded_run(agent))`. |
| **Concurrency limit** | `asyncio.Semaphore(max_parallel_agents)` so not all 6 run heavy LLM calls at once. |
| **Shared state** | All agents receive the same `agent_registry`, `suggestion_store`, `investigation_store`, `strategy_store`, `ws_manager`, `polymarket_client`. |
| **Heartbeat** | Every 60s logs and broadcasts `SYSTEM` event with `active_agents` and `pending_suggestions`. |

---

## 4. Single Market Agent Flow (e.g. PoliticsAgent)

Every **market agent** (Politics, Crypto, Sports, Science) follows the same pipeline, defined in `MarketBaseAgent`:

```mermaid
flowchart LR
    subgraph Investigate["investigate()"]
        A[Fetch markets from Polymarket API] --> B[Filter out expired markets]
        B --> C[For each market: _analyse_market]
    end

    subgraph Analyse["_analyse_market(market)"]
        C --> D[Start Investigation record]
        D --> E[Optional: Tavily web search]
        E --> F[LLM: analyze_sentiment]
        F --> G[Update Investigation with sentiment]
        G --> H{Discrepancy?}
        H -->|No| I[Mark Investigation SKIPPED]
        H -->|Yes| J[LLM: generate_trading_reasoning]
        J --> K[Create Suggestion]
        K --> L[Emit to store + WebSocket]
    end

    L --> M[Back to sleep for update_interval seconds]
    M --> A
```

**Steps in detail:**

1. **Fetch markets** — `polymarket.get_markets(category=CATEGORY_TAG, active=True, limit=MAX_MARKETS)`.
2. **Filter expired** — Drop any market where `end_date < now` (saves LLM cost).
3. **Per market** — `_analyse_market(market)`:
   - Create an **Investigation** (status `ANALYZING`) and broadcast `investigation_update`.
   - **Web search** (optional) — Tavily query; if no key, LLM uses its own knowledge.
   - **Sentiment** — `llm.analyze_sentiment(news_text, context)` → `{ sentiment, confidence, reasoning, key_factors }`.
   - **Discrepancy** — e.g. bullish + price &lt; 0.60 → BUY; bearish + price &gt; 0.40 → SELL; else skip.
   - **Reasoning** — `llm.generate_trading_reasoning(...)` → `(reasoning_text, confidence_score)`.
   - Build **Suggestion** with `end_date`, `market_url`, and emit to `suggestion_store` + WebSocket `new_suggestion`.
4. **Sleep** — `await asyncio.sleep(update_interval)`, then repeat.

---

## 5. Strategy Agents Flow

### StrategyScoutAgent

```mermaid
flowchart LR
    A[Research queries list] --> B[For each query: search_web]
    B --> C[LLM: summarize_for_strategy]
    C --> D[StrategyReport: title, summary, actionable_insights]
    D --> E[strategy_store + broadcast strategy_report]
    E --> F[Return no Suggestion]
    F --> G[Sleep update_interval]
    G --> A
```

- **Role:** Research only. Does **not** create trading Suggestions.
- **Output:** `StrategyReport` → `strategy_store` and WebSocket `strategy_report` for the **Strategies** tab.

### WhaleWatcherAgent

```mermaid
flowchart LR
    A[get_leaderboard] --> B[For top 5 traders]
    B --> C[get_trader_positions]
    C --> D{Position size >= 500 USD?}
    D -->|Yes| E[Build copy-trade Suggestion]
    D -->|No| F[Skip]
    E --> G[suggestion_store + new_suggestion]
    G --> H[Sleep update_interval]
    H --> A
```

- **Role:** Copy-trading. Creates **Suggestions** like “Copiando a trader #1 (85% win rate)…”
- **Output:** Same `Suggestion` type as market agents → appears in **Signals** queue.

---

## 6. Data Flow: From Agent to UI

```mermaid
flowchart TB
    subgraph Agents
        MA[Market Agent]
        WA[WhaleWatcher]
        SA[StrategyScout]
    end

    subgraph Stores
        SUG[(suggestions)]
        INV[(investigations)]
        STR[(strategy_reports)]
        REG[(agent_registry)]
    end

    subgraph Backend
        REST[REST API]
        WS[WebSocket Manager]
    end

    subgraph Frontend
        TAB[Signals / Agents / Analysis / Strategies]
    end

    MA --> SUG
    MA --> INV
    MA --> REG
    WA --> SUG
    WA --> REG
    SA --> STR
    SA --> REG

    SUG --> REST
    INV --> REST
    STR --> REST
    REG --> REST

    MA --> WS
    WA --> WS
    SA --> WS
    Orchestrator --> WS

    REST --> TAB
    WS --> TAB
```

| Store | Written by | Consumed by API | WebSocket events |
|-------|------------|-----------------|------------------|
| `_suggestions` | Market agents, WhaleWatcher | `GET /api/suggestions` | `new_suggestion`, `suggestion_update` |
| `_investigations` | Market agents | `GET /api/investigations` | `investigation_update` |
| `_strategy_reports` | StrategyScoutAgent | `GET /api/strategies` | `strategy_report` |
| `_agents` (registry) | All agents + Orchestrator | `GET /api/agents` | `agent_status` |

---

## 7. File Map

| Component | File(s) |
|-----------|--------|
| **Entry** | `run.py`, `config.ini` |
| **API & lifecycle** | `backend/main.py` |
| **Orchestrator** | `backend/agents/orchestrator_agent.py` |
| **Base agent** | `backend/agents/base_agent.py` |
| **Market agents** | `backend/agents/market_agents/_market_base.py`, `politics_agent.py`, `crypto_agent.py`, `sports_agent.py`, `science_agent.py` |
| **Strategy agents** | `backend/agents/strategy_agents/strategy_scout_agent.py`, `whale_watcher_agent.py` |
| **LLM** | `backend/llm_client.py` (FuelXI / OpenAI) |
| **Polymarket** | `backend/polymarket_client.py` |
| **Real-time** | `backend/websocket_manager.py` |
| **Models** | `backend/models.py` |

---

## 8. Summary

- **One Orchestrator** starts with the FastAPI app and creates **6 long-lived agents** in parallel (throttled by a semaphore).
- **Market agents** pull Polymarket markets → filter expired → run LLM sentiment + reasoning → push **Suggestions** and **Investigations**.
- **StrategyScout** only produces **StrategyReports** (no trades).
- **WhaleWatcher** produces **Suggestions** from leaderboard/positions.
- All agents share **registry**, **suggestion_store**, **investigation_store**, **strategy_store**, and **WebSocket**; the frontend reads via REST and listens via `/ws/updates` for live updates.
