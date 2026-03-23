# 🤖 Trading Terminal — AI Multi-Agent System

An autonomous AI trading system for MetaTrader 5 with 8 specialized agents, real-time dashboard, and continuous self-improvement.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ORCHESTRATOR                         │
│                    (CEO / Agent Manager)                    │
└────────┬────────┬────────┬────────┬────────┬───────────────┘
         │        │        │        │        │
    ┌────▼──┐ ┌───▼──┐ ┌───▼──┐ ┌───▼──┐ ┌───▼──┐
    │Quant  │ │News  │ │Risk  │ │MT5   │ │Memory│
    │Analyst│ │Sentin│ │Mgr   │ │Exec  │ │Agent │
    └───────┘ └──────┘ └──────┘ └──────┘ └──────┘
         │                                    │
    ┌────▼──┐                           ┌─────▼──┐
    │Explorer│                          │ChromaDB│
    │(Rsrch) │                          │(Local) │
    └────────┘                          └────────┘
         │
    ┌────▼────┐
    │DataClean│
    └─────────┘
```

## Quick Start

### 1. Install Dependencies

```bash
# Backend
pip install -r backend/requirements.txt

# Frontend
cd frontend && npm install
```

### 2. Configure MT5 Account

Edit `backend/config/settings.yaml`:
```yaml
mt5:
  login: YOUR_ACCOUNT_NUMBER
  password: "YOUR_PASSWORD"
  server: "YOUR_BROKER_SERVER"   # e.g. "ICMarkets-Demo"
```

Or use CLI:
```bash
python run.py --login 12345 --password secret --server ICMarkets-Demo
```

### 3. Start the System

```bash
# Paper trading (safe to test)
python run.py --paper

# With auto-start trading
python run.py --paper --auto-start

# Specific symbols
python run.py --paper --symbols EURUSD GBPUSD XAUUSD

# Live trading (⚠ CAUTION - real money)
python run.py --live
```

### 4. Open Dashboard

Navigate to **http://localhost:3000**

---

## The 8 Agents

| # | Agent | Role | Key Capability |
|---|-------|------|----------------|
| 1 | **Orchestrator** | CEO | Veto authority, global state, workflow |
| 2 | **Technical Analyst** | Quant | Multi-TF analysis, pattern detection, LLM enhancement |
| 3 | **News Sentinel** | Macro | News sentiment, Black Swan detection, event calendar |
| 4 | **Risk Manager** | Risk Officer | ATR SL/TP, Kelly sizing, circuit breakers |
| 5 | **MT5 Executor** | Bridge | Order execution, slippage control, trailing stops |
| 6 | **Memory Agent** | Auditor | Trade context storage, pattern risk warnings |
| 7 | **Explorer** | Researcher | Strategy variants, paper trading optimization |
| 8 | **Data Cleaner** | Data Guard | Gap filling, OHLC validation, spike removal |

## Veto System

The Orchestrator blocks trades if:
- Technical confidence < 52%
- News verdict = "block" (high-impact event)
- Memory risk score > 75% (similar past losses)
- Risk check fails (exposure limits, spread, circuit breaker)
- Session score < 30/100

## Strategies

- **OrderFlowScalping** — Volume imbalance + OBV + EMA alignment
- **VWAPMeanReversionScalp** — Fades VWAP extremes with BB confirmation
- **MicrostructureScalping** — ICT order blocks + FVGs + liquidity sweeps

## Session Focus

| Session | Times (UTC) | Peak Hours |
|---------|------------|------------|
| Tokyo | 00:00-06:00 | 00:00-02:30 |
| London | 08:00-16:30 | 08:00-10:30 |
| New York | 13:30-20:00 | 13:30-15:30 |
| **LDN-NY Overlap** | **13:30-16:30** | **⭐ Best for scalping** |

## Risk Management

- Daily loss limit: 2% → auto-stop
- Max drawdown: 5% → circuit breaker
- ATR-based SL/TP (not fixed pips)
- Minimum R:R = 2:1
- Position sizing: Fixed Risk % or Kelly Criterion

## AI Integration

- **FuelIX** (primary): `gemini-2.5-pro` via `https://api.fuelix.ai/v1/chat/completions`
- **OpenAI** (backup): GPT-4o
- **Google Gemini** (backup): gemini-1.5-pro
- **ChromaDB** (local): Persistent trade memory + pattern learning

## MT5 Files

Export directly to MT5:
- `backend/mt5_files/Experts/TradingTerminal_EA.mq5` → MT5 Expert Advisor
- `backend/mt5_files/Indicators/TT_Dashboard.mq5` → Dashboard indicator

Copy to MetaTrader 5 → `MQL5/Experts/` and `MQL5/Indicators/`

## Configuration Reference

See `backend/config/settings.yaml` for all parameters.

## ⚠ Disclaimer

**This software is for educational purposes only. Trading involves substantial risk of loss. Always test thoroughly in paper mode before any live deployment. Past performance does not guarantee future results.**
